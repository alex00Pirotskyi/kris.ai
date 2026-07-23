#!/usr/bin/env python3
"""Project Manager 2 reference runtime for Kristin v1.7.

The service keeps project operations behind the probed sandbox worker, records
profiles/workspaces/processes/artifacts in the durable SQLite store, and fails
closed when a profile requests authority the current worker cannot enforce.
"""
from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import hashlib
import json
import mimetypes
import os
from pathlib import Path, PurePosixPath
import re
import secrets
import shutil
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time
from typing import Any, Iterable, Mapping, Sequence
import zipfile

import sandbox_worker

VERSION = "1.9.0+190"
PROFILE_SCHEMA_VERSION = "2.0.0"
ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = ROOT / "migrations" / "workflow"
MAX_SOURCE_FILES = 100_000
MAX_SOURCE_BYTES = 2 * 1024 * 1024 * 1024
MAX_ARTIFACT_BYTES = 512 * 1024 * 1024
IGNORED_NAMES = frozenset({
    ".git", ".dart_tool", "build", "dist", "node_modules", ".venv",
    "__pycache__", ".idea", ".vscode", ".kristin",
})
ACTIONS = ("analyze", "test", "build", "run", "package")


class ProjectManagerError(RuntimeError):
    def __init__(self, code: str, message: str, *, details: Mapping[str, Any] | None = None) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.details = dict(details or {})


class ProfileError(ProjectManagerError):
    pass


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_json(value: Any) -> str:
    return sha256_bytes(canonical_json(value).encode("utf-8"))


def new_id(prefix: str) -> str:
    return f"{prefix}_{int(time.time() * 1000):x}_{secrets.token_hex(8)}"


def safe_relative(value: str, *, allow_dot: bool = True) -> str:
    if not isinstance(value, str):
        raise ProfileError("profile_path_type", "Project-profile paths must be strings.")
    text = value.strip().replace("\\", "/")
    if text in ("", "."):
        if allow_dot:
            return "."
        raise ProfileError("profile_path_required", "A non-empty project-relative path is required.")
    path = PurePosixPath(text)
    if path.is_absolute() or ".." in path.parts or re.match(r"^[A-Za-z]:", text) or text.startswith("//"):
        raise ProfileError("profile_path_outside_project", f"Path must remain project-relative: {value}")
    normalized = "/".join(part for part in path.parts if part not in ("", "."))
    if not normalized:
        return "." if allow_dot else ""
    if "\x00" in normalized:
        raise ProfileError("profile_path_nul", "NUL bytes are not allowed in project-profile paths.")
    return normalized


def _strict_object(value: Any, label: str, allowed: set[str]) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ProfileError("profile_type_invalid", f"{label} must be a JSON object.")
    data = {str(key): item for key, item in value.items()}
    unknown = sorted(set(data) - allowed)
    if unknown:
        raise ProfileError(
            "profile_unknown_authority",
            f"{label} contains unsupported fields: {', '.join(unknown)}.",
            details={"fields": unknown},
        )
    return data


def _string_list(value: Any, label: str) -> tuple[str, ...]:
    if value is None:
        return ()
    if not isinstance(value, list):
        raise ProfileError("profile_type_invalid", f"{label} must be a JSON array.")
    result: list[str] = []
    for index, item in enumerate(value):
        if not isinstance(item, str):
            raise ProfileError("profile_type_invalid", f"{label}[{index}] must be a string.")
        if "\x00" in item:
            raise ProfileError("profile_argument_nul", f"{label}[{index}] contains a NUL byte.")
        result.append(item)
    return tuple(result)


@dataclasses.dataclass(frozen=True)
class ArtifactDeclaration:
    path: str
    logical_type: str = "file"
    validator: str = "presence"
    required: bool = True
    sensitivity: str = "project"

    @classmethod
    def from_json(cls, raw: Any, label: str) -> "ArtifactDeclaration":
        data = _strict_object(raw, label, {"path", "logicalType", "validator", "required", "sensitivity"})
        path = safe_relative(str(data.get("path", "")), allow_dot=False)
        validator = str(data.get("validator", "presence")).strip() or "presence"
        if validator not in {"presence", "text", "json", "zip", "image", "directory"}:
            raise ProfileError("profile_validator_unsupported", f"Unsupported artifact validator: {validator}")
        logical_type = str(data.get("logicalType", "file")).strip() or "file"
        sensitivity = str(data.get("sensitivity", "project")).strip() or "project"
        return cls(path, logical_type, validator, bool(data.get("required", True)), sensitivity)

    def to_json(self) -> dict[str, Any]:
        return {
            "path": self.path,
            "logicalType": self.logical_type,
            "validator": self.validator,
            "required": self.required,
            "sensitivity": self.sensitivity,
        }


@dataclasses.dataclass(frozen=True)
class CommandProfile:
    action: str
    executable: str
    arguments: tuple[str, ...]
    working_directory: str
    workspace_mode: str
    network_mode: str
    writable_paths: tuple[str, ...]
    timeout_seconds: int
    memory_limit_mb: int
    process_limit: int
    file_size_limit_mb: int
    expected_outputs: tuple[ArtifactDeclaration, ...]
    ports: tuple[int, ...]
    health_checks: tuple[str, ...]
    secret_references: tuple[str, ...]

    @property
    def display(self) -> str:
        return subprocess.list2cmdline([self.executable, *self.arguments])

    @classmethod
    def from_json(cls, action: str, raw: Any) -> "CommandProfile":
        data = _strict_object(
            raw,
            f"commands.{action}",
            {
                "executable", "arguments", "workingDirectory", "workspaceMode",
                "networkMode", "writablePaths", "timeoutSeconds", "memoryLimitMb",
                "processLimit", "fileSizeLimitMb", "expectedOutputs", "ports",
                "healthChecks", "secretReferences",
            },
        )
        executable = str(data.get("executable", "")).strip()
        if not executable:
            raise ProfileError("profile_executable_required", f"commands.{action}.executable is required.")
        if any(character in executable for character in ("\x00", "\n", "\r")):
            raise ProfileError("profile_executable_invalid", f"commands.{action}.executable is invalid.")
        name = executable.replace("\\", "/").split("/")[-1].lower()
        if name in {"sh", "bash", "zsh", "cmd", "cmd.exe", "powershell", "powershell.exe", "pwsh", "pwsh.exe"}:
            raise ProfileError("profile_shell_rejected", "Shell interpreters are not valid Project Manager commands.")
        arguments = _string_list(data.get("arguments", []), f"commands.{action}.arguments")
        working = safe_relative(str(data.get("workingDirectory", ".")))
        workspace_mode = str(data.get("workspaceMode", "")).strip()
        if not workspace_mode:
            workspace_mode = "read_only" if action in {"analyze", "test"} else "snapshot_writable"
        if workspace_mode not in {"read_only", "snapshot_writable"}:
            raise ProfileError("profile_workspace_mode_unsupported", f"Unsupported workspace mode: {workspace_mode}")
        if action in {"analyze", "test"} and workspace_mode != "read_only":
            raise ProfileError("profile_workspace_mode_excessive", f"{action} must use read_only workspace mode.")
        if action in {"build", "run", "package"} and workspace_mode != "snapshot_writable":
            raise ProfileError("profile_workspace_mode_unsafe", f"{action} must use snapshot_writable workspace mode.")
        network_mode = str(data.get("networkMode", "none")).strip() or "none"
        if network_mode not in {"none", "broker_https"}:
            raise ProfileError("profile_network_mode_unsupported", f"Unsupported network mode: {network_mode}")
        writable_paths = tuple(safe_relative(item, allow_dot=False) for item in _string_list(data.get("writablePaths", []), f"commands.{action}.writablePaths"))
        if workspace_mode == "read_only" and writable_paths:
            raise ProfileError("profile_write_scope_invalid", f"{action} is read-only and cannot declare writable paths.")
        timeout = int(data.get("timeoutSeconds", 600))
        memory = int(data.get("memoryLimitMb", 1024))
        process_limit = int(data.get("processLimit", 64))
        file_limit = int(data.get("fileSizeLimitMb", 128))
        if not 1 <= timeout <= 3600:
            raise ProfileError("profile_timeout_invalid", "timeoutSeconds must be 1..3600.")
        if not 128 <= memory <= 32768:
            raise ProfileError("profile_memory_invalid", "memoryLimitMb must be 128..32768.")
        if not 8 <= process_limit <= 1024:
            raise ProfileError("profile_process_limit_invalid", "processLimit must be 8..1024.")
        if not 1 <= file_limit <= 4096:
            raise ProfileError("profile_file_limit_invalid", "fileSizeLimitMb must be 1..4096.")
        expected_raw = data.get("expectedOutputs", [])
        if not isinstance(expected_raw, list):
            raise ProfileError("profile_type_invalid", f"commands.{action}.expectedOutputs must be an array.")
        expected = tuple(ArtifactDeclaration.from_json(item, f"commands.{action}.expectedOutputs[{index}]") for index, item in enumerate(expected_raw))
        ports_raw = data.get("ports", [])
        if not isinstance(ports_raw, list):
            raise ProfileError("profile_type_invalid", f"commands.{action}.ports must be an array.")
        ports: list[int] = []
        for index, item in enumerate(ports_raw):
            if isinstance(item, bool) or not isinstance(item, int) or not 1 <= item <= 65535:
                raise ProfileError("profile_port_invalid", f"commands.{action}.ports[{index}] must be 1..65535.")
            ports.append(item)
        return cls(
            action=action,
            executable=executable,
            arguments=arguments,
            working_directory=working,
            workspace_mode=workspace_mode,
            network_mode=network_mode,
            writable_paths=writable_paths,
            timeout_seconds=timeout,
            memory_limit_mb=memory,
            process_limit=process_limit,
            file_size_limit_mb=file_limit,
            expected_outputs=expected,
            ports=tuple(sorted(set(ports))),
            health_checks=_string_list(data.get("healthChecks", []), f"commands.{action}.healthChecks"),
            secret_references=_string_list(data.get("secretReferences", []), f"commands.{action}.secretReferences"),
        )

    def to_json(self) -> dict[str, Any]:
        return {
            "executable": self.executable,
            "arguments": list(self.arguments),
            "workingDirectory": self.working_directory,
            "workspaceMode": self.workspace_mode,
            "networkMode": self.network_mode,
            "writablePaths": list(self.writable_paths),
            "timeoutSeconds": self.timeout_seconds,
            "memoryLimitMb": self.memory_limit_mb,
            "processLimit": self.process_limit,
            "fileSizeLimitMb": self.file_size_limit_mb,
            "expectedOutputs": [item.to_json() for item in self.expected_outputs],
            "ports": list(self.ports),
            "healthChecks": list(self.health_checks),
            "secretReferences": list(self.secret_references),
        }


@dataclasses.dataclass(frozen=True)
class ProjectProfileV2:
    project_type: str
    commands: Mapping[str, CommandProfile]
    source: str
    schema_version: str = PROFILE_SCHEMA_VERSION
    sandbox_required: bool = True
    max_snapshot_files: int = MAX_SOURCE_FILES
    max_snapshot_bytes: int = MAX_SOURCE_BYTES

    def to_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": self.schema_version,
            "projectType": self.project_type,
            "sandbox": {
                "required": self.sandbox_required,
                "maxSnapshotFiles": self.max_snapshot_files,
                "maxSnapshotBytes": self.max_snapshot_bytes,
            },
            "commands": {name: command.to_json() for name, command in sorted(self.commands.items())},
            "source": self.source,
        }


def parse_profile(root: Path) -> ProjectProfileV2:
    path = root / "kristin.project.json"
    if not path.is_file():
        return detect_profile(root)
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ProfileError("profile_json_invalid", f"Could not parse kristin.project.json: {exc}") from exc
    data = _strict_object(raw, "profile", {"schemaVersion", "projectType", "type", "commands", "sandbox", "analyze", "test", "build", "run", "package"})
    schema = str(data.get("schemaVersion", "1.0.0")).strip()
    project_type = str(data.get("projectType", data.get("type", "Custom"))).strip() or "Custom"
    commands_raw: dict[str, Any]
    if "commands" in data:
        commands_raw = _strict_object(data["commands"], "commands", set(ACTIONS))
        if any(name in data for name in ACTIONS):
            raise ProfileError("profile_command_conflict", "Use either commands.* or legacy top-level command objects, not both.")
    else:
        commands_raw = {name: data[name] for name in ACTIONS if name in data}
    commands = {name: CommandProfile.from_json(name, value) for name, value in commands_raw.items()}
    sandbox_raw = _strict_object(data.get("sandbox", {}), "sandbox", {"required", "maxSnapshotFiles", "maxSnapshotBytes"})
    required = bool(sandbox_raw.get("required", True))
    if not required:
        raise ProfileError("profile_unsandboxed_rejected", "Project Manager 2 does not support unsandboxed agent execution.")
    max_files = int(sandbox_raw.get("maxSnapshotFiles", MAX_SOURCE_FILES))
    max_bytes = int(sandbox_raw.get("maxSnapshotBytes", MAX_SOURCE_BYTES))
    if not 1 <= max_files <= MAX_SOURCE_FILES:
        raise ProfileError("profile_snapshot_limit_invalid", f"maxSnapshotFiles must be 1..{MAX_SOURCE_FILES}.")
    if not 1024 <= max_bytes <= MAX_SOURCE_BYTES:
        raise ProfileError("profile_snapshot_limit_invalid", f"maxSnapshotBytes must be 1024..{MAX_SOURCE_BYTES}.")
    return ProjectProfileV2(project_type, commands, "kristin.project.json", PROFILE_SCHEMA_VERSION if schema != PROFILE_SCHEMA_VERSION else schema, True, max_files, max_bytes)


def detect_profile(root: Path) -> ProjectProfileV2:
    commands: dict[str, CommandProfile] = {}
    project_type = "Unknown"
    if (root / "pubspec.yaml").is_file():
        text = (root / "pubspec.yaml").read_text(encoding="utf-8", errors="replace")
        flutter = bool(re.search(r"(?m)^\s*flutter\s*:\s*$", text))
        executable = "flutter" if flutter else "dart"
        project_type = "Flutter" if flutter else "Dart"
        analyze_args = ["analyze"]
        test_args = ["test", "--concurrency=1"] if flutter else ["test"]
        commands["analyze"] = CommandProfile.from_json("analyze", {"executable": executable, "arguments": analyze_args})
        commands["test"] = CommandProfile.from_json("test", {"executable": executable, "arguments": test_args})
    elif (root / "pyproject.toml").is_file() or any(root.glob("*.py")):
        project_type = "Python"
        commands["analyze"] = CommandProfile.from_json("analyze", {"executable": sys.executable, "arguments": ["-m", "compileall", "-q", "."]})
        if (root / "test").exists() or (root / "tests").exists():
            commands["test"] = CommandProfile.from_json("test", {"executable": sys.executable, "arguments": ["-m", "unittest", "discover"]})
    elif (root / "package.json").is_file():
        project_type = "Node"
        package = {}
        try:
            package = json.loads((root / "package.json").read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            pass
        scripts = package.get("scripts", {}) if isinstance(package, dict) else {}
        if isinstance(scripts, dict) and "test" in scripts:
            commands["test"] = CommandProfile.from_json("test", {"executable": "npm", "arguments": ["test", "--", "--runInBand"]})
        if isinstance(scripts, dict) and "build" in scripts:
            commands["build"] = CommandProfile.from_json("build", {"executable": "npm", "arguments": ["run", "build"]})
    elif (root / "Cargo.toml").is_file():
        project_type = "Rust"
        commands["analyze"] = CommandProfile.from_json("analyze", {"executable": "cargo", "arguments": ["check"]})
        commands["test"] = CommandProfile.from_json("test", {"executable": "cargo", "arguments": ["test"]})
        commands["build"] = CommandProfile.from_json("build", {"executable": "cargo", "arguments": ["build"]})
    elif (root / "go.mod").is_file():
        project_type = "Go"
        commands["test"] = CommandProfile.from_json("test", {"executable": "go", "arguments": ["test", "./..."]})
        commands["build"] = CommandProfile.from_json("build", {"executable": "go", "arguments": ["build", "./..."]})
    return ProjectProfileV2(project_type, commands, "detected")


def data_root_default() -> Path:
    override = os.environ.get("KRISTIN_DATA_ROOT", "").strip()
    if override:
        return Path(override).expanduser().resolve()
    if os.name == "nt":
        base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
    elif sys.platform == "darwin":
        base = Path.home() / "Library" / "Application Support"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
    return (base / "KristinLocalAgent").resolve()


def workflow_database(data_root: Path) -> Path:
    return data_root / "state" / "workflow.sqlite3"


def open_store(data_root: Path) -> sqlite3.Connection:
    database = workflow_database(data_root)
    database.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(database)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    connection.execute("PRAGMA journal_mode = WAL")
    connection.execute("PRAGMA synchronous = FULL")
    connection.execute("PRAGMA busy_timeout = 5000")
    connection.execute(
        """CREATE TABLE IF NOT EXISTS schema_migrations (
             version INTEGER PRIMARY KEY,
             name TEXT NOT NULL,
             sha256 TEXT NOT NULL,
             applied_at TEXT NOT NULL
           ) WITHOUT ROWID"""
    )
    applied = {int(row["version"]): str(row["sha256"]) for row in connection.execute("SELECT version, sha256 FROM schema_migrations")}
    migration_paths = sorted(MIGRATIONS.glob("[0-9][0-9][0-9]_*.sql"))
    for expected, path in enumerate(migration_paths, 1):
        version = int(path.name.split("_", 1)[0])
        if version != expected:
            raise ProjectManagerError("workflow_migration_gap", "Workflow migrations are not contiguous.")
        sql = path.read_text(encoding="utf-8").replace("\r\n", "\n")
        if not sql.endswith("\n"):
            sql += "\n"
        digest = sha256_bytes(sql.encode("utf-8"))
        prior = applied.get(version)
        if prior is not None:
            if prior != digest:
                raise ProjectManagerError("workflow_migration_drift", f"Migration {version} hash changed after application.")
            continue
        connection.executescript("BEGIN IMMEDIATE;\n" + sql + f"\nPRAGMA user_version = {version};\nCOMMIT;\n")
        connection.execute(
            "INSERT INTO schema_migrations(version, name, sha256, applied_at) VALUES (?, ?, ?, ?)",
            (version, path.stem.split("_", 1)[1], digest, utc_now()),
        )
        connection.commit()
    return connection


def project_id(root: Path) -> str:
    return "project_" + sha256_bytes(str(root.resolve()).encode("utf-8"))[:24]


def tree_manifest(root: Path, *, max_files: int = MAX_SOURCE_FILES, max_bytes: int = MAX_SOURCE_BYTES) -> dict[str, Any]:
    files: list[dict[str, Any]] = []
    total = 0
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        relative = path.relative_to(root)
        if any(part in IGNORED_NAMES for part in relative.parts):
            continue
        if path.is_symlink():
            raise ProjectManagerError("workspace_symlink_rejected", f"Workspace enumeration rejects symlink: {relative.as_posix()}")
        if not path.is_file():
            continue
        size = path.stat().st_size
        total += size
        if len(files) + 1 > max_files or total > max_bytes:
            raise ProjectManagerError(
                "workspace_snapshot_limit",
                "Project exceeds the configured snapshot file or byte limit.",
                details={"files": len(files) + 1, "bytes": total},
            )
        files.append({"path": relative.as_posix(), "bytes": size, "sha256": sha256_bytes(path.read_bytes())})
    manifest = {"files": files, "fileCount": len(files), "totalBytes": total}
    manifest["sha256"] = sha256_json(manifest)
    return manifest


def resolve_executable(executable: str, project: Path) -> str | None:
    candidate = Path(executable)
    if candidate.is_absolute():
        return str(candidate) if candidate.is_file() else None
    project_candidate = project / candidate
    if ("/" in executable or "\\" in executable) and project_candidate.is_file():
        return str(project_candidate.resolve())
    return shutil.which(executable)


def action_readiness(
    profile: ProjectProfileV2,
    action: str,
    capabilities: Mapping[str, Any],
) -> dict[str, Any]:
    command = profile.commands.get(action)
    if action == "package" and command is None:
        # Built-in packaging only snapshots, hashes, archives, and records the
        # selected project. It does not execute project code, so tying it to an
        # OS sandbox would be a false dependency rather than a security control.
        return {
            "state": "ready",
            "reasons": [],
            "backend": "builtin_snapshot_packager",
            "assurance": "host_snapshot_no_project_code_execution",
        }
    if command is None:
        return {
            "state": "not_configured",
            "reasons": ["command_not_configured"],
            "backend": str(capabilities.get("backend", "unavailable")),
        }
    reasons: list[str] = []
    if not capabilities.get("available"):
        reasons.append("sandbox_unavailable")
    if command.network_mode != "none":
        reasons.append("worker_process_network_broker_unavailable")
    if command.secret_references:
        reasons.append("secret_use_requires_explicit_approval")
    if command.ports:
        reasons.append("worker_to_host_port_bridge_unavailable")
    return {
        "state": "blocked" if reasons else "ready",
        "reasons": reasons,
        "backend": str(capabilities.get("backend", "unavailable")),
        "assurance": "os_sandbox" if capabilities.get("available") else "none",
    }


def persist_profile(connection: sqlite3.Connection, root: Path, profile: ProjectProfileV2) -> None:
    now = utc_now()
    payload = profile.to_json()
    digest = sha256_json(payload)
    connection.execute(
        """INSERT INTO project_profiles(project_id, schema_version, profile_json, profile_sha256,
                                         source_path_hash, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(project_id) DO UPDATE SET
             schema_version=excluded.schema_version,
             profile_json=excluded.profile_json,
             profile_sha256=excluded.profile_sha256,
             source_path_hash=excluded.source_path_hash,
             updated_at=excluded.updated_at""",
        (project_id(root), profile.schema_version, canonical_json(payload), digest, sha256_bytes(str(root.resolve()).encode()), now, now),
    )
    connection.commit()


def _workspace_root(data_root: Path, root: Path, session_id: str) -> Path:
    return data_root / "workspaces" / project_id(root) / session_id / "workspace"


def _record_workspace(
    connection: sqlite3.Connection,
    *,
    session_id: str,
    root: Path,
    run_id: str | None,
    action: str,
    mode: str,
    path: Path,
    source_manifest: Mapping[str, Any],
    status: str,
    workspace_manifest: Mapping[str, Any] | None = None,
    details: Mapping[str, Any] | None = None,
) -> None:
    now = utc_now()
    details_value = dict(details or {})
    connection.execute(
        """INSERT INTO workspace_sessions(
             id, project_id, run_id, action, mode, source_root_hash, workspace_path,
             workspace_path_hash, source_manifest_sha256, workspace_manifest_sha256,
             status, created_at, updated_at, completed_at, details_json, details_sha256
           ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(id) DO UPDATE SET
             workspace_manifest_sha256=excluded.workspace_manifest_sha256,
             status=excluded.status,
             updated_at=excluded.updated_at,
             completed_at=excluded.completed_at,
             details_json=excluded.details_json,
             details_sha256=excluded.details_sha256""",
        (
            session_id,
            project_id(root),
            run_id,
            action,
            mode,
            sha256_bytes(str(root.resolve()).encode()),
            str(path),
            sha256_bytes(str(path).encode()),
            str(source_manifest["sha256"]),
            str(workspace_manifest["sha256"]) if workspace_manifest else None,
            status,
            now,
            now,
            now if status in {"completed", "failed", "interrupted", "discarded"} else None,
            canonical_json(details_value),
            sha256_json(details_value),
        ),
    )
    connection.commit()


def validate_artifact(path: Path, declaration: ArtifactDeclaration) -> tuple[bool, str, str]:
    if declaration.validator == "directory":
        return (path.is_dir(), "directory" if path.is_dir() else "missing_directory", "inode/directory")
    if not path.is_file():
        return (not declaration.required, "optional_missing" if not declaration.required else "missing", "application/octet-stream")
    size = path.stat().st_size
    if size > MAX_ARTIFACT_BYTES:
        return False, "artifact_too_large", "application/octet-stream"
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    try:
        if declaration.validator == "presence":
            return True, "present", mime
        if declaration.validator == "text":
            text = path.read_text(encoding="utf-8")
            return (bool(text.strip()), "nonempty_text" if text.strip() else "empty_text", mime)
        if declaration.validator == "json":
            json.loads(path.read_text(encoding="utf-8"))
            return True, "valid_json", "application/json"
        if declaration.validator == "zip":
            with zipfile.ZipFile(path) as archive:
                names = archive.namelist()
                for name in names:
                    safe_relative(name, allow_dot=False)
                bad = archive.testzip()
                return (bad is None, "valid_zip" if bad is None else f"corrupt_member:{bad}", "application/zip")
        if declaration.validator == "image":
            head = path.read_bytes()[:16]
            valid = (
                head.startswith(b"\x89PNG\r\n\x1a\n")
                or head.startswith(b"\xff\xd8\xff")
                or head.startswith((b"GIF87a", b"GIF89a"))
                or (head.startswith(b"RIFF") and b"WEBP" in head)
            )
            return valid, "valid_image_signature" if valid else "invalid_image_signature", mime
    except (OSError, UnicodeError, json.JSONDecodeError, zipfile.BadZipFile) as exc:
        return False, f"validation_error:{type(exc).__name__}", mime
    return False, "validator_unsupported", mime


def collect_artifacts(
    connection: sqlite3.Connection,
    *,
    root: Path,
    run_id: str | None,
    workspace_id: str,
    workspace: Path,
    action: str,
    declarations: Iterable[ArtifactDeclaration],
) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    now = utc_now()
    for declaration in declarations:
        candidate = workspace / declaration.path
        try:
            resolved_parent = candidate.parent.resolve()
        except OSError:
            resolved_parent = candidate.parent.absolute()
        if workspace.resolve() != resolved_parent and workspace.resolve() not in resolved_parent.parents:
            raise ProjectManagerError("artifact_path_outside_workspace", f"Artifact path escapes workspace: {declaration.path}")
        ok, detail, mime = validate_artifact(candidate, declaration)
        if candidate.is_file():
            data = candidate.read_bytes()
            digest = sha256_bytes(data)
            length = len(data)
        else:
            digest = sha256_json({"path": declaration.path, "detail": detail})
            length = 0
        record = {
            "id": new_id("artifact"),
            "projectId": project_id(root),
            "runId": run_id,
            "workspaceId": workspace_id,
            "producerAction": action,
            "relativePath": declaration.path,
            "logicalType": declaration.logical_type,
            "mimeType": mime,
            "contentSha256": digest,
            "byteLength": length,
            "validationState": "valid" if ok else "invalid",
            "validationDetail": detail,
            "sensitivity": declaration.sensitivity,
            "createdAt": now,
        }
        connection.execute(
            """INSERT OR IGNORE INTO artifact_records(
                 id, project_id, run_id, workspace_id, producer_action, relative_path,
                 logical_type, mime_type, content_sha256, byte_length, validation_state,
                 sensitivity, record_json, record_sha256, created_at, updated_at
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                record["id"], record["projectId"], run_id, workspace_id, action,
                declaration.path, declaration.logical_type, mime, digest, length,
                record["validationState"], declaration.sensitivity,
                canonical_json(record), sha256_json(record), now, now,
            ),
        )
        records.append(record)
    connection.commit()
    return records


def execute_action(
    *,
    root: Path,
    data_root: Path,
    action: str,
    run_id: str | None = None,
) -> dict[str, Any]:
    root = root.expanduser().resolve()
    if not root.is_dir():
        raise ProjectManagerError("project_missing", "The selected project directory does not exist.")
    if action not in ACTIONS:
        raise ProjectManagerError("project_action_invalid", f"Unknown Project Manager action: {action}")
    profile = parse_profile(root)
    capabilities = sandbox_worker.probe_backend()
    readiness = action_readiness(profile, action, capabilities)
    if readiness["state"] != "ready":
        raise ProjectManagerError("project_action_blocked", f"{action} is not ready.", details=readiness)
    connection = open_store(data_root)
    try:
        persist_profile(connection, root, profile)
        source_manifest = tree_manifest(root, max_files=profile.max_snapshot_files, max_bytes=profile.max_snapshot_bytes)
        session_id = new_id("workspace")
        command = profile.commands.get(action)
        if action == "package" and command is None:
            workspace = _workspace_root(data_root, root, session_id)
            workspace.parent.mkdir(parents=True, exist_ok=True)
            sandbox_worker._copy_project_snapshot(root, workspace)
            workspace_manifest = tree_manifest(workspace, max_files=profile.max_snapshot_files, max_bytes=profile.max_snapshot_bytes)
            package_dir = data_root / "packages" / project_id(root)
            package_dir.mkdir(parents=True, exist_ok=True)
            archive = package_dir / f"{session_id}.zip"
            _write_deterministic_zip(workspace, archive)
            declaration = ArtifactDeclaration(str(archive.relative_to(package_dir.parent.parent)).replace("\\", "/"), "archive", "zip")
            # Package lives outside the workspace, so record it directly.
            data = archive.read_bytes()
            record = {
                "id": new_id("artifact"), "projectId": project_id(root), "runId": run_id,
                "workspaceId": session_id, "producerAction": action,
                "relativePath": str(archive), "logicalType": "archive", "mimeType": "application/zip",
                "contentSha256": sha256_bytes(data), "byteLength": len(data),
                "validationState": "valid", "validationDetail": "deterministic_zip",
                "sensitivity": "project", "createdAt": utc_now(),
            }
            connection.execute(
                """INSERT INTO artifact_records(id, project_id, run_id, workspace_id, producer_action,
                   relative_path, logical_type, mime_type, content_sha256, byte_length,
                   validation_state, sensitivity, record_json, record_sha256, created_at, updated_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (record["id"], record["projectId"], run_id, session_id, action, record["relativePath"],
                 "archive", "application/zip", record["contentSha256"], record["byteLength"], "valid",
                 "project", canonical_json(record), sha256_json(record), record["createdAt"], record["createdAt"]),
            )
            connection.commit()
            _record_workspace(connection, session_id=session_id, root=root, run_id=run_id, action=action,
                              # project_manager_snapshot
                              mode="snapshot_writable", path=workspace, source_manifest=source_manifest,
                              workspace_manifest=workspace_manifest, status="completed",
                              details={"archive": str(archive), "archiveSha256": record["contentSha256"]})
            return {"action": action, "sessionId": session_id, "workspace": str(workspace), "archive": str(archive), "artifacts": [record], "passed": True}

        assert command is not None
        executable = resolve_executable(command.executable, root)
        if executable is None:
            raise ProjectManagerError("project_tool_missing", f"{command.executable} was not found on PATH.")
        workspace = root
        retained: Path | None = None
        if command.workspace_mode == "snapshot_writable":
            retained = _workspace_root(data_root, root, session_id)
            retained.parent.mkdir(parents=True, exist_ok=True)
            workspace = retained
        _record_workspace(connection, session_id=session_id, root=root, run_id=run_id, action=action,
                          mode=command.workspace_mode, path=workspace, source_manifest=source_manifest,
                          status="preparing")
        result = sandbox_worker.run_finite(
            executable=executable,
            arguments=list(command.arguments),
            project_root=root,
            working_directory=command.working_directory,
            workspace_mode=command.workspace_mode,
            timeout_seconds=command.timeout_seconds,
            memory_limit_mb=command.memory_limit_mb,
            process_limit=command.process_limit,
            file_size_limit_mb=command.file_size_limit_mb,
            retained_snapshot_root=retained,
        )
        effective_workspace = Path(str(result.get("workspaceSnapshotPath", root))).resolve()
        workspace_manifest = tree_manifest(effective_workspace, max_files=profile.max_snapshot_files, max_bytes=profile.max_snapshot_bytes)
        artifacts = collect_artifacts(
            connection,
            root=root,
            run_id=run_id,
            workspace_id=session_id,
            workspace=effective_workspace,
            action=action,
            declarations=command.expected_outputs,
        )
        passed = int(result.get("exitCode", 1)) == 0 and all(item["validationState"] == "valid" for item in artifacts if item)
        _record_workspace(connection, session_id=session_id, root=root, run_id=run_id, action=action,
                          mode=command.workspace_mode, path=effective_workspace, source_manifest=source_manifest,
                          workspace_manifest=workspace_manifest, status="completed" if passed else "failed",
                          details={"result": _bounded_result(result), "artifactCount": len(artifacts)})
        return {
            "action": action,
            "sessionId": session_id,
            "workspace": str(effective_workspace),
            "sourceManifestSha256": source_manifest["sha256"],
            "workspaceManifestSha256": workspace_manifest["sha256"],
            "sandbox": capabilities,
            "result": _bounded_result(result),
            "artifacts": artifacts,
            "passed": passed,
        }
    finally:
        connection.close()


def _bounded_result(result: Mapping[str, Any]) -> dict[str, Any]:
    allowed = {
        "backend", "available", "workspaceMode", "workspaceHash", "workspaceSnapshotHash",
        "workspaceRetained", "workingDirectory", "insideExecutable", "arguments",
        "startedAt", "completedAt", "exitCode", "stdout", "stderr", "truncated", "durationMs",
    }
    bounded = {key: result[key] for key in allowed if key in result}
    for key in ("stdout", "stderr"):
        text = str(bounded.get(key, ""))
        if len(text) > 64_000:
            bounded[key] = text[:64_000] + "…"
            bounded[f"{key}Sha256"] = sha256_bytes(text.encode())
    return bounded


def _write_deterministic_zip(root: Path, archive: Path) -> None:
    entries = tree_manifest(root)["files"]
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as output:
        for entry in entries:
            relative = str(entry["path"])
            info = zipfile.ZipInfo(relative, date_time=(2026, 7, 22, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            output.writestr(info, (root / relative).read_bytes())


def start_run(*, root: Path, data_root: Path, run_id: str | None = None) -> dict[str, Any]:
    root = root.expanduser().resolve()
    profile = parse_profile(root)
    command = profile.commands.get("run")
    capabilities = sandbox_worker.probe_backend()
    readiness = action_readiness(profile, "run", capabilities)
    if command is None or readiness["state"] != "ready":
        raise ProjectManagerError("project_action_blocked", "run is not ready.", details=readiness)
    executable = resolve_executable(command.executable, root)
    if executable is None:
        raise ProjectManagerError("project_tool_missing", f"{command.executable} was not found on PATH.")
    connection = open_store(data_root)
    try:
        persist_profile(connection, root, profile)
        process_id = new_id("process")
        workspace_id = new_id("workspace")
        snapshot = _workspace_root(data_root, root, workspace_id)
        snapshot.parent.mkdir(parents=True, exist_ok=True)
        request_dir = data_root / "processes" / process_id
        request_dir.mkdir(parents=True, exist_ok=False)
        request_path = request_dir / "request.json"
        result_path = request_dir / "result.json"
        log_path = request_dir / "launcher.log"
        request = {
            "processId": process_id,
            "workspaceId": workspace_id,
            "projectRoot": str(root),
            "dataRoot": str(data_root),
            "runId": run_id,
            "executable": executable,
            "arguments": list(command.arguments),
            "workingDirectory": command.working_directory,
            "timeoutSeconds": command.timeout_seconds,
            "memoryLimitMb": command.memory_limit_mb,
            "processLimit": command.process_limit,
            "fileSizeLimitMb": command.file_size_limit_mb,
            "retainedSnapshot": str(snapshot),
            "resultPath": str(result_path),
        }
        request_path.write_text(json.dumps(request, sort_keys=True), encoding="utf-8")
        launcher = [sys.executable, str(Path(__file__).resolve()), "internal-run", "--request", str(request_path)]
        log_handle = log_path.open("ab", buffering=0)
        try:
            process = subprocess.Popen(
                launcher,
                stdin=subprocess.DEVNULL,
                stdout=log_handle,
                stderr=subprocess.STDOUT,
                start_new_session=True,
                close_fds=True,
            )
        finally:
            log_handle.close()
        now = utc_now()
        launcher_identity = sandbox_worker.process_identity(process.pid)
        request_public = {key: value for key, value in request.items() if key not in {"projectRoot", "dataRoot", "resultPath", "retainedSnapshot"}}
        if launcher_identity:
            request_public["launcherStartTimeTicks"] = launcher_identity["startTimeTicks"]
        connection.execute(
            """INSERT INTO managed_project_processes(
                 id, project_id, run_id, workspace_id, action, state, sandbox_backend,
                 pid, process_group_id, command_sha256, request_json, request_sha256,
                 started_at, updated_at
               ) VALUES (?, ?, ?, ?, 'run', 'running', ?, ?, ?, ?, ?, ?, ?, ?)""",
            (process_id, project_id(root), run_id, workspace_id, str(capabilities.get("backend", "unavailable")),
             process.pid, process.pid, sha256_json([executable, *command.arguments]),
             canonical_json(request_public), sha256_json(request_public), now, now),
        )
        connection.commit()
        return {"processId": process_id, "pid": process.pid, "workspaceId": workspace_id, "state": "running", "log": str(log_path)}
    finally:
        connection.close()


def process_status(*, data_root: Path, process_id: str) -> dict[str, Any]:
    connection = open_store(data_root)
    try:
        row = connection.execute("SELECT * FROM managed_project_processes WHERE id = ?", (process_id,)).fetchone()
        if row is None:
            raise ProjectManagerError("project_process_missing", f"Unknown process: {process_id}")
        state = str(row["state"])
        pid = int(row["pid"] or 0)
        request_record = json.loads(str(row["request_json"]))
        launcher_identity = _recorded_launcher_identity(pid, request_record)
        request_dir = data_root / "processes" / process_id
        result_path = request_dir / "result.json"
        # A durable child result is authoritative even while the launcher remains
        # briefly visible as a zombie awaiting reaping by the init process.
        if state in {"running", "starting", "stopping"} and (
            result_path.is_file() or not sandbox_worker.process_identity_alive(launcher_identity)
        ):
            if result_path.is_file():
                try:
                    result = json.loads(result_path.read_text(encoding="utf-8"))
                except (OSError, json.JSONDecodeError):
                    result = {"exitCode": 1, "errorCode": "process_result_invalid"}
                exit_code = int(result.get("exitCode", 1))
                state = "succeeded" if exit_code == 0 else "failed"
                result_json = canonical_json(result)
                connection.execute(
                    """UPDATE managed_project_processes SET state=?, result_json=?, result_sha256=?,
                       exit_code=?, failure_code=?, updated_at=?, completed_at=? WHERE id=?""",
                    (state, result_json, sha256_bytes(result_json.encode()), exit_code,
                     result.get("errorCode"), utc_now(), utc_now(), process_id),
                )
            else:
                state = "interrupted"
                connection.execute(
                    "UPDATE managed_project_processes SET state='interrupted', failure_code='worker_disappeared', updated_at=?, completed_at=? WHERE id=?",
                    (utc_now(), utc_now(), process_id),
                )
            connection.commit()
            row = connection.execute("SELECT * FROM managed_project_processes WHERE id = ?", (process_id,)).fetchone()
        return {key: row[key] for key in row.keys() if key not in {"request_json", "result_json"}} | {
            "request": json.loads(str(row["request_json"])),
            "result": json.loads(str(row["result_json"])) if row["result_json"] else None,
        }
    finally:
        connection.close()


def stop_process(*, data_root: Path, process_id: str) -> dict[str, Any]:
    connection = open_store(data_root)
    try:
        row = connection.execute("SELECT * FROM managed_project_processes WHERE id = ?", (process_id,)).fetchone()
        if row is None:
            raise ProjectManagerError("project_process_missing", f"Unknown process: {process_id}")
        state = str(row["state"])
        pid = int(row["pid"] or 0)
        request_record = json.loads(str(row["request_json"]))
        launcher_identity = _recorded_launcher_identity(pid, request_record)
        if state not in {"running", "starting", "stopping"}:
            return process_status(data_root=data_root, process_id=process_id)
        connection.execute("UPDATE managed_project_processes SET state='stopping', updated_at=? WHERE id=?", (utc_now(), process_id))
        connection.commit()
        cleanup = {"observed": 0, "terminated": 0, "survivors": []}
        if sandbox_worker.process_identity_alive(launcher_identity):
            cleanup = sandbox_worker.terminate_process_tree(pid, grace_seconds=3.0)
        elif _pid_alive(pid):
            # The numeric PID still exists but no longer matches the durable
            # launch identity.  Fail closed rather than signalling an unrelated
            # process after PID reuse.
            now = utc_now()
            connection.execute(
                "UPDATE managed_project_processes SET state='interrupted', failure_code='launcher_identity_mismatch', updated_at=?, completed_at=? WHERE id=?",
                (now, now, process_id),
            )
            connection.commit()
            return process_status(data_root=data_root, process_id=process_id)
        if cleanup["survivors"]:
            now = utc_now()
            connection.execute(
                "UPDATE managed_project_processes SET state='interrupted', failure_code='process_tree_termination_incomplete', updated_at=?, completed_at=? WHERE id=?",
                (now, now, process_id),
            )
            connection.commit()
            return process_status(data_root=data_root, process_id=process_id)
        now = utc_now()
        connection.execute(
            "UPDATE managed_project_processes SET state='stopped', failure_code='user_stop', updated_at=?, completed_at=? WHERE id=?",
            (now, now, process_id),
        )
        connection.commit()
    finally:
        connection.close()
    return process_status(data_root=data_root, process_id=process_id)


def _pid_alive(pid: int) -> bool:
    if pid <= 1:
        return False
    if sys.platform.startswith("linux"):
        stat = Path(f"/proc/{pid}/stat")
        try:
            fields = stat.read_text(encoding="utf-8", errors="replace").split()
            if len(fields) > 2 and fields[2] == "Z":
                return False
        except OSError:
            pass
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def _recorded_launcher_identity(pid: int, request_record: Mapping[str, Any]) -> dict[str, int | str] | None:
    try:
        start_ticks = int(request_record["launcherStartTimeTicks"])
    except (KeyError, TypeError, ValueError):
        return sandbox_worker.process_identity(pid)
    return {"pid": pid, "startTimeTicks": start_ticks}


def snapshot(*, root: Path, data_root: Path) -> dict[str, Any]:
    root = root.expanduser().resolve()
    profile = parse_profile(root)
    capabilities = sandbox_worker.probe_backend()
    connection = open_store(data_root)
    try:
        persist_profile(connection, root, profile)
        readiness = {action: action_readiness(profile, action, capabilities) for action in ACTIONS}
        git = {"available": bool(shutil.which("git")), "branch": "", "dirty": None}
        if git["available"] and (root / ".git").exists():
            branch = subprocess.run(["git", "branch", "--show-current"], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=5)
            status = subprocess.run(["git", "status", "--porcelain"], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=5)
            git["branch"] = branch.stdout.strip()
            git["dirty"] = bool(status.stdout.strip())
        recent_workspaces = [dict(row) for row in connection.execute(
            "SELECT id, action, mode, status, workspace_path_hash, source_manifest_sha256, workspace_manifest_sha256, created_at, updated_at FROM workspace_sessions WHERE project_id=? ORDER BY updated_at DESC LIMIT 20",
            (project_id(root),),
        )]
        artifacts = [dict(row) for row in connection.execute(
            "SELECT id, run_id, workspace_id, producer_action, relative_path, logical_type, mime_type, content_sha256, byte_length, validation_state, sensitivity, created_at FROM artifact_records WHERE project_id=? ORDER BY updated_at DESC LIMIT 100",
            (project_id(root),),
        )]
        processes = [dict(row) for row in connection.execute(
            "SELECT id, run_id, workspace_id, action, state, sandbox_backend, pid, exit_code, failure_code, started_at, updated_at, completed_at FROM managed_project_processes WHERE project_id=? ORDER BY updated_at DESC LIMIT 20",
            (project_id(root),),
        )]
        return {
            "schemaVersion": "1.0.0",
            "version": VERSION,
            "project": {"id": project_id(root), "rootPathHash": sha256_bytes(str(root).encode()), "projectType": profile.project_type, "profileSource": profile.source},
            "sandbox": capabilities,
            "git": git,
            "actions": readiness,
            "profile": profile.to_json(),
            "recentWorkspaces": recent_workspaces,
            "artifacts": artifacts,
            "processes": processes,
            "limitations": [
                "Windows and macOS isolated worker helpers are not included in this source release.",
                "Worker-to-host preview port forwarding is unavailable.",
                "Profile-declared secrets remain blocked pending explicit per-use approval.",
                "Project process networking is disabled; public HTTPS research uses the separate broker.",
            ],
        }
    finally:
        connection.close()


def _internal_run(request_path: Path) -> int:
    request = json.loads(request_path.read_text(encoding="utf-8"))
    result_path = Path(str(request["resultPath"]))
    try:
        result = sandbox_worker.run_finite(
            executable=str(request["executable"]),
            arguments=[str(item) for item in request.get("arguments", [])],
            project_root=Path(str(request["projectRoot"])).resolve(),
            working_directory=str(request.get("workingDirectory", ".")),
            workspace_mode="snapshot_writable",
            timeout_seconds=int(request.get("timeoutSeconds", 600)),
            memory_limit_mb=int(request.get("memoryLimitMb", 1024)),
            process_limit=int(request.get("processLimit", 64)),
            file_size_limit_mb=int(request.get("fileSizeLimitMb", 128)),
            retained_snapshot_root=Path(str(request["retainedSnapshot"])).resolve(),
        )
        payload = {"exitCode": int(result.get("exitCode", 1)), "result": _bounded_result(result)}
    except Exception as exc:  # noqa: BLE001 - child must emit a durable result
        payload = {"exitCode": 1, "errorCode": getattr(exc, "code", type(exc).__name__), "error": str(exc)}
    result_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = result_path.with_suffix(".tmp")
    temporary.write_text(json.dumps(payload, sort_keys=True), encoding="utf-8")
    temporary.replace(result_path)
    return int(payload["exitCode"])


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Kristin Project Manager 2")
    parser.add_argument("--version", action="version", version=VERSION)
    sub = parser.add_subparsers(dest="command", required=True)
    status = sub.add_parser("status")
    status.add_argument("--project", type=Path, default=Path.cwd())
    status.add_argument("--data-root", type=Path, default=data_root_default())
    status.add_argument("--json", action="store_true")
    action = sub.add_parser("action")
    action.add_argument("action", choices=ACTIONS)
    action.add_argument("--project", type=Path, default=Path.cwd())
    action.add_argument("--data-root", type=Path, default=data_root_default())
    action.add_argument("--run-id")
    action.add_argument("--json", action="store_true")
    start = sub.add_parser("start")
    start.add_argument("--project", type=Path, default=Path.cwd())
    start.add_argument("--data-root", type=Path, default=data_root_default())
    start.add_argument("--run-id")
    start.add_argument("--json", action="store_true")
    proc = sub.add_parser("process-status")
    proc.add_argument("process_id")
    proc.add_argument("--data-root", type=Path, default=data_root_default())
    proc.add_argument("--json", action="store_true")
    stop = sub.add_parser("stop")
    stop.add_argument("process_id")
    stop.add_argument("--data-root", type=Path, default=data_root_default())
    stop.add_argument("--json", action="store_true")
    internal = sub.add_parser("internal-run")
    internal.add_argument("--request", type=Path, required=True)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "status":
            result = snapshot(root=args.project, data_root=args.data_root.expanduser().resolve())
        elif args.command == "action":
            result = execute_action(root=args.project, data_root=args.data_root.expanduser().resolve(), action=args.action, run_id=args.run_id)
        elif args.command == "start":
            result = start_run(root=args.project, data_root=args.data_root.expanduser().resolve(), run_id=args.run_id)
        elif args.command == "process-status":
            result = process_status(data_root=args.data_root.expanduser().resolve(), process_id=args.process_id)
        elif args.command == "stop":
            result = stop_process(data_root=args.data_root.expanduser().resolve(), process_id=args.process_id)
        elif args.command == "internal-run":
            return _internal_run(args.request.expanduser().resolve())
        else:  # pragma: no cover
            raise ProjectManagerError("project_command_invalid", "Unsupported command.")
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0 if result.get("passed", True) else 1
    except ProjectManagerError as exc:
        payload = {"errorCode": exc.code, "message": exc.message, "details": exc.details}
        print(json.dumps(payload, indent=2, sort_keys=True), file=sys.stderr)
        return 2
    except sandbox_worker.SandboxError as exc:
        print(json.dumps({"errorCode": "sandbox_error", "message": str(exc)}, indent=2), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
