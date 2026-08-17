#!/usr/bin/env python3
"""KRIS Qwen v6 safety, idempotency, and controller identity helpers.

This module is intentionally standard-library only.  It contains the parts of
v6 that need deterministic unit tests without importing the 6k-line worker.
"""
from __future__ import annotations

import contextlib
import dataclasses
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import secrets
import tempfile
from typing import Any, Iterable, Mapping, Sequence

V6_GUARD_VERSION = "6.0.0"

AUTH_MARKERS = (
    "gh auth login",
    "not logged into any github hosts",
    "authentication failed",
    "bad credentials",
    "http 401",
    "status code: 401",
    "could not read username",
    "terminal prompts disabled",
    "repository not found",
    "invalid token",
    "token has expired",
    "requires authentication",
)

ACTION_FIELDS: dict[str, frozenset[str]] = {
    "read_file": frozenset({"action", "path", "start_line", "end_line", "why"}),
    "read_history": frozenset({"action", "ref", "path", "start_line", "end_line", "why"}),
    "list_files": frozenset({"action", "path", "why"}),
    "search": frozenset({"action", "query", "path", "why"}),
    "run": frozenset({"action", "argv", "why"}),
    "write_file": frozenset({"action", "path", "content", "why"}),
    "delete_file": frozenset({"action", "path", "why"}),
    "apply_patch": frozenset({"action", "patch", "why"}),
    "git_diff": frozenset({"action", "why"}),
    "finish": frozenset({"action", "summary", "commit_message", "why"}),
    "review_diff": frozenset({"action", "why"}),
    "review_finish": frozenset({"action", "verdict", "summary", "findings", "why"}),
    "blocked": frozenset({"action", "classification", "reason", "remediation", "why"}),
}

MAX_ACTION_JSON_BYTES = 512 * 1024
MAX_WRITE_BYTES = 256 * 1024
MAX_PATCH_BYTES = 512 * 1024
MAX_ARG_COUNT = 128
MAX_ARG_BYTES = 16 * 1024


class V6GuardError(RuntimeError):
    """Base class for deterministic v6 guard failures."""


class GitHubInfrastructureBlocked(V6GuardError):
    """GitHub authentication or credential plumbing is unavailable."""

    state = "BLOCKED_GITHUB_AUTH"
    signature = "github-auth-unavailable"
    retry_seconds = 300


class SharedAuthorityRequired(V6GuardError):
    """An integration candidate needs a separately governed shared authority."""

    state = "BLOCKED_SHARED_AUTHORITY"

    def __init__(self, report: Mapping[str, Any]):
        self.report = dict(report)
        paths = ", ".join(str(x) for x in self.report.get("sharedPaths", []))
        super().__init__(f"shared authority required before integration push: {paths}")


@dataclasses.dataclass(frozen=True)
class ProcessIdentity:
    pid: int
    start_ticks: int
    executable: str
    cmdline_sha256: str

    def to_json(self) -> dict[str, Any]:
        return dataclasses.asdict(self)


def utc_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def atomic_write_json(path: pathlib.Path, value: Any, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, raw = tempfile.mkstemp(prefix=path.name + ".tmp-", dir=path.parent)
    tmp = pathlib.Path(raw)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        with contextlib.suppress(OSError):
            os.chmod(tmp, mode)
        os.replace(tmp, path)
        with contextlib.suppress(OSError):
            directory_fd = os.open(path.parent, os.O_RDONLY)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
    finally:
        with contextlib.suppress(FileNotFoundError):
            tmp.unlink()


def github_auth_failure(argv: Sequence[str], stdout: str, stderr: str, returncode: int) -> str | None:
    if returncode == 0:
        return None
    executable = pathlib.PurePath(str(argv[0])).name.lower() if argv else ""
    if executable not in {"gh", "git"}:
        return None
    text = f"{stdout}\n{stderr}".lower()
    if any(marker in text for marker in AUTH_MARKERS):
        return "github authentication is unavailable for the non-interactive worker"
    if executable == "git" and any(token in text for token in ("authentication", "credential", "username")):
        return "Git HTTPS credential plumbing is unavailable for the non-interactive worker"
    return None


def action_size_bytes(action: Mapping[str, Any]) -> int:
    return len(canonical_json(action).encode("utf-8"))


def validate_action_shape(action: Mapping[str, Any], *, review: bool = False) -> None:
    if not isinstance(action, Mapping):
        raise V6GuardError("model action must be an object")
    kind = action.get("action")
    if not isinstance(kind, str) or kind not in ACTION_FIELDS:
        raise V6GuardError(f"unknown model action: {kind!r}")
    if review and kind not in {
        "read_file", "list_files", "search", "run", "review_diff", "review_finish", "blocked"
    }:
        raise V6GuardError(f"action is unavailable in review mode: {kind}")
    unknown = sorted(set(action) - ACTION_FIELDS[kind])
    if unknown:
        raise V6GuardError(f"unknown fields for {kind}: {unknown}")
    size = action_size_bytes(action)
    if size > MAX_ACTION_JSON_BYTES:
        raise V6GuardError(f"model action exceeds {MAX_ACTION_JSON_BYTES} bytes")
    why = action.get("why")
    if not isinstance(why, str) or not why.strip() or len(why.encode("utf-8")) > 2000:
        raise V6GuardError("every model action requires a bounded non-empty why field")
    if kind == "write_file":
        content = action.get("content")
        if not isinstance(content, str) or len(content.encode("utf-8")) > MAX_WRITE_BYTES:
            raise V6GuardError(f"write_file content exceeds {MAX_WRITE_BYTES} bytes")
    if kind == "apply_patch":
        patch = action.get("patch")
        if not isinstance(patch, str) or len(patch.encode("utf-8")) > MAX_PATCH_BYTES:
            raise V6GuardError(f"apply_patch payload exceeds {MAX_PATCH_BYTES} bytes")
    if kind == "run":
        argv = action.get("argv")
        if not isinstance(argv, list) or not argv or len(argv) > MAX_ARG_COUNT:
            raise V6GuardError("run argv must be a bounded non-empty array")
        if not all(isinstance(item, str) and len(item.encode("utf-8")) <= MAX_ARG_BYTES for item in argv):
            raise V6GuardError("run argv contains an invalid or oversized argument")


def _path_matches(path: str, pattern: str) -> bool:
    """Git-style small glob: * does not cross '/', ** may cross directories."""
    out = ["^"]
    index = 0
    while index < len(pattern):
        char = pattern[index]
        if char == "*":
            if index + 1 < len(pattern) and pattern[index + 1] == "*":
                index += 2
                if index < len(pattern) and pattern[index] == "/":
                    out.append("(?:.*/)?")
                    index += 1
                else:
                    out.append(".*")
                continue
            out.append("[^/]*")
        elif char == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(char))
        index += 1
    out.append("$")
    return re.fullmatch("".join(out), path) is not None


def classify_shared_authority_paths(
    *,
    effective_paths: Iterable[str],
    allowed_patterns: Iterable[str],
    authority_config: Mapping[str, Any],
    mission: str,
) -> dict[str, Any]:
    paths = sorted({str(path).replace("\\", "/").lstrip("./") for path in effective_paths})
    patterns = [str(pattern).replace("\\", "/").lstrip("./") for pattern in allowed_patterns]
    outside = [path for path in paths if not any(_path_matches(path, pattern) for pattern in patterns)]
    authorities = authority_config.get("authorities")
    if not isinstance(authorities, Mapping):
        raise V6GuardError("shared authority configuration has no authorities object")
    shared: list[dict[str, Any]] = []
    ordinary: list[str] = []
    for path in outside:
        matches: list[dict[str, Any]] = []
        for authority_id, raw in authorities.items():
            if not isinstance(raw, Mapping):
                continue
            authority_path = raw.get("path")
            if not isinstance(authority_path, str):
                continue
            if _path_matches(path, authority_path.replace("\\", "/").lstrip("./")):
                eligible = raw.get("eligibleRequestingMissions")
                matches.append(
                    {
                        "authorityId": str(authority_id),
                        "path": path,
                        "authorityPath": authority_path,
                        "mode": str(raw.get("mode") or "UNKNOWN"),
                        "ownerMission": str(raw.get("ownerMission") or ""),
                        "requestingMission": mission,
                        "requestingMissionEligible": isinstance(eligible, list) and mission in eligible,
                    }
                )
        if matches:
            shared.extend(matches)
        else:
            ordinary.append(path)
    return {
        "schemaVersion": 1,
        "requestingMission": mission,
        "outsideAllowedPaths": outside,
        "sharedPaths": sorted({row["path"] for row in shared}),
        "requiredAuthorities": sorted(shared, key=lambda row: (row["path"], row["authorityId"])),
        "ordinaryForeignPaths": ordinary,
        "requiresSharedAuthority": bool(shared),
    }


def write_shared_authority_report(
    path: pathlib.Path,
    *,
    classification: Mapping[str, Any],
    work_order: Mapping[str, Any],
    product_branch: str,
    product_head: str,
    main_head: str,
) -> dict[str, Any]:
    report = {
        "schemaVersion": 1,
        "state": "BLOCKED_SHARED_AUTHORITY",
        "recordedAt": utc_iso(),
        "workOrderId": work_order.get("workOrderId"),
        "mission": work_order.get("mission"),
        "roadmapTask": work_order.get("roadmapTask"),
        "productBranch": product_branch,
        "productHead": product_head,
        "protectedMainHead": main_head,
        **dict(classification),
    }
    atomic_write_json(path, report)
    return report


class OperationJournal:
    """Small durable idempotency journal for remote GitHub side effects."""

    def __init__(self, path: pathlib.Path):
        self.path = path

    def _load(self) -> dict[str, Any]:
        if not self.path.is_file():
            return {"schemaVersion": 1, "operations": {}}
        try:
            value = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise V6GuardError(f"operation journal is unreadable: {exc}") from exc
        if not isinstance(value, dict) or not isinstance(value.get("operations"), dict):
            raise V6GuardError("operation journal has invalid structure")
        return value

    @staticmethod
    def key(kind: str, target: Mapping[str, Any]) -> str:
        digest = hashlib.sha256(canonical_json({"kind": kind, "target": target}).encode("utf-8")).hexdigest()
        return f"{kind.lower()}:{digest[:32]}"

    def get(self, key: str) -> dict[str, Any] | None:
        return self._load()["operations"].get(key)

    def prepare(self, kind: str, target: Mapping[str, Any]) -> dict[str, Any]:
        value = self._load()
        key = self.key(kind, target)
        existing = value["operations"].get(key)
        if existing:
            return existing
        row = {
            "key": key,
            "kind": kind,
            "state": "PREPARED",
            "target": dict(target),
            "preparedAt": utc_iso(),
        }
        value["operations"][key] = row
        atomic_write_json(self.path, value)
        return row

    def complete(self, key: str, result: Mapping[str, Any]) -> dict[str, Any]:
        value = self._load()
        row = value["operations"].get(key)
        if not isinstance(row, dict):
            raise V6GuardError(f"operation was not prepared: {key}")
        row = {
            **row,
            "state": "COMPLETED",
            "completedAt": utc_iso(),
            "result": dict(result),
        }
        value["operations"][key] = row
        atomic_write_json(self.path, value)
        return row


def linux_process_identity(pid: int) -> ProcessIdentity | None:
    if not isinstance(pid, int) or pid <= 1:
        return None
    proc = pathlib.Path("/proc") / str(pid)
    try:
        stat = (proc / "stat").read_text(encoding="utf-8")
        closing = stat.rfind(")")
        if closing < 0:
            return None
        fields = stat[closing + 2 :].split()
        start_ticks = int(fields[19])
        cmdline = (proc / "cmdline").read_bytes()
        executable = os.readlink(proc / "exe")
    except (OSError, ValueError, IndexError):
        return None
    return ProcessIdentity(
        pid=pid,
        start_ticks=start_ticks,
        executable=executable,
        cmdline_sha256=hashlib.sha256(cmdline).hexdigest(),
    )


def process_identity_matches(recorded: Mapping[str, Any], current: ProcessIdentity | None) -> bool:
    if current is None:
        return False
    try:
        return (
            int(recorded.get("pid")) == current.pid
            and int(recorded.get("start_ticks", recorded.get("startTicks"))) == current.start_ticks
            and str(recorded.get("executable")) == current.executable
            and secrets.compare_digest(
                str(recorded.get("cmdline_sha256", recorded.get("cmdlineSha256"))),
                current.cmdline_sha256,
            )
        )
    except (TypeError, ValueError):
        return False


def sensitive_mount_overrides() -> list[str]:
    """bubblewrap arguments that hide common credential-bearing host trees."""
    rows: list[str] = []
    for path in ("/root", "/home", "/run/user"):
        if pathlib.Path(path).exists():
            rows.extend(["--tmpfs", path])
    return rows


def audit_worktree_links(root: pathlib.Path) -> list[str]:
    """Return symlink paths that resolve outside the bounded worktree."""
    root = root.resolve()
    violations: list[str] = []
    for path in root.rglob("*"):
        if not path.is_symlink():
            continue
        try:
            resolved = path.resolve(strict=False)
        except OSError:
            violations.append(path.relative_to(root).as_posix())
            continue
        if resolved != root and root not in resolved.parents:
            violations.append(path.relative_to(root).as_posix())
    return sorted(violations)
