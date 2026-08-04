#!/usr/bin/env python3
"""Executable P2 reference/runtime fixtures.

This module is deliberately stdlib-only so that the integration train can prove
core authorization, filesystem transaction, command bounding, process-tree,
undo, and watchdog semantics before Dart/native packaging is available.
It is not an authorization root: callers must supply a P1 policy decision and
Capability Grant v2 envelope, and the final effect boundary validates both.
"""
from __future__ import annotations

import dataclasses
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import shutil
import signal
import subprocess
import tempfile
import threading
import time
import uuid
from collections.abc import Callable, Iterable
from typing import Any

OWNER_PROFILES = {"owner", "owner_unattended"}
SECRET_KEY = re.compile(r"(?i)(secret|token|password|passwd|credential|api[_-]?key|private[_-]?key)")
SECRET_VALUE = re.compile(r"(?i)(bearer\s+[a-z0-9._~+/=-]{8,}|sk-[a-z0-9_-]{8,}|gh[opusr]_[a-z0-9]{8,})")


class P2Denied(RuntimeError):
    pass


class P2Unsupported(RuntimeError):
    pass


@dataclasses.dataclass(frozen=True)
class EffectBinding:
    run_id: str
    task_id: str
    actor_id: str
    tool_id: str
    access_profile_id: str
    capability_id: str
    operation: str


class UseLedger:
    """In-memory fixture ledger mirroring atomic pre-effect use consumption."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._uses: dict[str, int] = {}
        self._revoked: set[str] = set()

    def revoke(self, grant_id: str) -> None:
        with self._lock:
            self._revoked.add(grant_id)

    def consume(self, grant_id: str, max_uses: int) -> int:
        with self._lock:
            if grant_id in self._revoked:
                raise P2Denied("grant_revoked")
            consumed = self._uses.get(grant_id, 0)
            if consumed >= max_uses:
                raise P2Denied("grant_exhausted")
            consumed += 1
            self._uses[grant_id] = consumed
            return consumed


class EffectBoundary:
    """Validates P1 decision/grant at the last point before an effect."""

    REQUIRED_GRANT_FIELDS = {
        "schemaVersion", "grantId", "issuer", "binding", "scope",
        "budgets", "validity", "nonce", "auth",
    }

    def __init__(self, ledger: UseLedger, now: Callable[[], dt.datetime] | None = None) -> None:
        self.ledger = ledger
        self.now = now or (lambda: dt.datetime.now(dt.timezone.utc))

    def authorize(self, decision: dict[str, Any], grant: dict[str, Any], binding: EffectBinding) -> dict[str, Any]:
        if decision.get("status") != "allow":
            raise P2Denied("policy_not_allow")
        if set(grant) != self.REQUIRED_GRANT_FIELDS or grant.get("schemaVersion") != "2.0.0":
            raise P2Denied("grant_shape_invalid")
        issuer = grant.get("issuer") or {}
        if issuer.get("actorId") != "desktop_host" or issuer.get("authority") != "desktop_host:deterministic_policy":
            raise P2Denied("grant_issuer_invalid")
        expected = {
            "runId": binding.run_id,
            "taskId": binding.task_id,
            "actorId": binding.actor_id,
            "toolId": binding.tool_id,
            "accessProfileId": binding.access_profile_id,
        }
        if grant.get("binding") != expected:
            raise P2Denied("grant_binding_mismatch")
        decision_binding = decision.get("binding") or {}
        for key, value in expected.items():
            if decision_binding.get(key) != value:
                raise P2Denied("decision_binding_mismatch")
        if decision_binding.get("capabilityId") != binding.capability_id:
            raise P2Denied("decision_capability_mismatch")
        if binding.access_profile_id not in OWNER_PROFILES:
            raise P2Denied("owner_profile_required")
        effect = decision.get("effect") or {}
        if effect.get("action") != binding.operation:
            raise P2Denied("effect_operation_mismatch")
        validity = grant.get("validity") or {}
        try:
            not_before = dt.datetime.fromisoformat(str(validity["notBefore"]).replace("Z", "+00:00"))
            expires_at = dt.datetime.fromisoformat(str(validity["expiresAt"]).replace("Z", "+00:00"))
            max_uses = int(validity["maxUses"])
        except (KeyError, TypeError, ValueError) as exc:
            raise P2Denied("grant_validity_invalid") from exc
        now = self.now()
        if now < not_before:
            raise P2Denied("grant_not_yet_valid")
        if now >= expires_at:
            raise P2Denied("grant_expired")
        if max_uses < 1:
            raise P2Denied("grant_max_uses_invalid")
        secret_scope = ((grant.get("scope") or {}).get("secrets") or {})
        if secret_scope.get("rawReveal") is not False:
            raise P2Denied("raw_secret_reveal_forbidden")
        consumed = self.ledger.consume(str(grant["grantId"]), max_uses)
        return {"grantId": grant["grantId"], "useNumber": consumed, "authorizedAt": now.isoformat()}


def redact(value: Any) -> Any:
    if isinstance(value, dict):
        return {k: ("[REDACTED]" if SECRET_KEY.search(str(k)) else redact(v)) for k, v in value.items()}
    if isinstance(value, list):
        return [redact(v) for v in value]
    if isinstance(value, str):
        return SECRET_VALUE.sub("[REDACTED]", value)
    return value


@dataclasses.dataclass
class Receipt:
    effect_id: str
    task_id: str
    operation: str
    status: str
    started_at: str
    completed_at: str | None = None
    reversible: str = "irreversible"
    details: dict[str, Any] = dataclasses.field(default_factory=dict)

    def as_json(self) -> dict[str, Any]:
        return redact(dataclasses.asdict(self))


class Journal:
    def __init__(self, path: pathlib.Path) -> None:
        self.path = path
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.Lock()

    def append(self, receipt: Receipt) -> None:
        payload = json.dumps(receipt.as_json(), sort_keys=True, ensure_ascii=False)
        with self._lock, self.path.open("a", encoding="utf-8") as handle:
            handle.write(payload + "\n")
            handle.flush()
            os.fsync(handle.fileno())


class PathGuard:
    @staticmethod
    def absolute(path: os.PathLike[str] | str) -> pathlib.Path:
        raw = pathlib.Path(path).expanduser()
        if not raw.is_absolute():
            raise P2Denied("absolute_path_required")
        return raw

    @staticmethod
    def fingerprint(path: pathlib.Path) -> tuple[int, int, int, str]:
        stat = path.lstat()
        kind = "symlink" if path.is_symlink() else "dir" if path.is_dir() else "file"
        return (stat.st_dev, stat.st_ino, stat.st_mtime_ns, kind)

    @staticmethod
    def resolved_existing(path: pathlib.Path) -> pathlib.Path:
        return path.resolve(strict=True)

    @staticmethod
    def parent_resolution(path: pathlib.Path) -> pathlib.Path:
        parent = path.parent.resolve(strict=True)
        return parent / path.name


class FilesystemService:
    def __init__(self, boundary: EffectBoundary, journal: Journal, backup_root: pathlib.Path) -> None:
        self.boundary = boundary
        self.journal = journal
        self.backup_root = backup_root
        self.backup_root.mkdir(parents=True, exist_ok=True)

    def _begin(self, decision: dict[str, Any], grant: dict[str, Any], binding: EffectBinding) -> Receipt:
        authorization = self.boundary.authorize(decision, grant, binding)
        receipt = Receipt(str(uuid.uuid4()), binding.task_id, binding.operation, "started", dt.datetime.now(dt.timezone.utc).isoformat())
        receipt.details["authorization"] = authorization
        self.journal.append(receipt)
        return receipt

    def read_bytes(self, path: str, *, decision: dict[str, Any], grant: dict[str, Any], binding: EffectBinding, max_bytes: int) -> tuple[bytes, Receipt]:
        receipt = self._begin(decision, grant, binding)
        target = PathGuard.absolute(path)
        before = PathGuard.fingerprint(target)
        resolved = PathGuard.resolved_existing(target)
        with resolved.open("rb") as handle:
            data = handle.read(max_bytes + 1)
        if len(data) > max_bytes:
            receipt.status = "denied"
            receipt.details["reason"] = "read_budget_exceeded"
            self.journal.append(receipt)
            raise P2Denied("read_budget_exceeded")
        if PathGuard.fingerprint(target) != before:
            receipt.status = "unknown"
            receipt.details["reason"] = "path_changed_during_read"
            self.journal.append(receipt)
            raise P2Denied("path_changed_during_read")
        receipt.status = "succeeded"
        receipt.completed_at = dt.datetime.now(dt.timezone.utc).isoformat()
        receipt.reversible = "irreversible"
        receipt.details.update({"path": str(target), "resolvedPath": str(resolved), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
        self.journal.append(receipt)
        return data, receipt

    def write_bytes(self, path: str, data: bytes, *, decision: dict[str, Any], grant: dict[str, Any], binding: EffectBinding) -> Receipt:
        receipt = self._begin(decision, grant, binding)
        target = PathGuard.absolute(path)
        if target.is_symlink():
            raise P2Denied('symlink_mutation_requires_handle_relative_adapter')
        canonical = PathGuard.parent_resolution(target) if not target.exists() else PathGuard.resolved_existing(target)
        backup: pathlib.Path | None = None
        if target.exists() and target.is_file():
            backup = self.backup_root / f"{receipt.effect_id}.bak"
            shutil.copy2(target, backup, follow_symlinks=False)
            receipt.reversible = "reversible"
            receipt.details["backup"] = str(backup)
        else:
            receipt.reversible = "reversible"
            receipt.details["createdNew"] = True
        tmp = target.with_name(f".{target.name}.kristin-{receipt.effect_id}.tmp")
        try:
            with tmp.open("xb") as handle:
                handle.write(data)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(tmp, target)
            if PathGuard.resolved_existing(target) != canonical:
                raise P2Denied("final_target_changed")
            receipt.status = "succeeded"
            receipt.completed_at = dt.datetime.now(dt.timezone.utc).isoformat()
            receipt.details.update({"path": str(target), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
            self.journal.append(receipt)
            return receipt
        except BaseException:
            tmp.unlink(missing_ok=True)
            if backup and backup.exists():
                shutil.copy2(backup, target, follow_symlinks=False)
            elif receipt.details.get("createdNew"):
                target.unlink(missing_ok=True)
            receipt.status = "rolled_back"
            receipt.completed_at = dt.datetime.now(dt.timezone.utc).isoformat()
            self.journal.append(receipt)
            raise

    def delete(self, path: str, *, decision: dict[str, Any], grant: dict[str, Any], binding: EffectBinding) -> Receipt:
        receipt = self._begin(decision, grant, binding)
        target = PathGuard.absolute(path)
        PathGuard.resolved_existing(target)
        quarantine = self.backup_root / f"delete-{receipt.effect_id}"
        os.replace(target, quarantine)
        receipt.status = "succeeded"
        receipt.completed_at = dt.datetime.now(dt.timezone.utc).isoformat()
        receipt.reversible = "reversible"
        receipt.details.update({"path": str(target), "quarantine": str(quarantine)})
        self.journal.append(receipt)
        return receipt

    def restore(self, receipt: Receipt) -> None:
        if receipt.operation == "delete" and receipt.details.get("quarantine"):
            os.replace(receipt.details["quarantine"], receipt.details["path"])
            return
        backup = receipt.details.get("backup")
        path = receipt.details.get("path")
        if backup and path:
            shutil.copy2(backup, path, follow_symlinks=False)
            return
        if receipt.details.get("createdNew") and path:
            pathlib.Path(path).unlink(missing_ok=True)
            return
        raise P2Unsupported("receipt_not_restorable")

    def search(self, root: str, pattern: str, *, max_entries: int, follow_links: bool = False) -> list[str]:
        start = PathGuard.absolute(root)
        matcher = re.compile(pattern)
        found: list[str] = []
        visited: set[tuple[int, int]] = set()
        stack = [start]
        seen = 0
        while stack:
            item = stack.pop()
            st = item.stat(follow_symlinks=follow_links)
            identity = (st.st_dev, st.st_ino)
            if identity in visited:
                continue
            visited.add(identity)
            seen += 1
            if seen > max_entries:
                raise P2Denied("traversal_budget_exceeded")
            if matcher.search(item.name):
                found.append(str(item))
            if item.is_dir() and (follow_links or not item.is_symlink()):
                stack.extend(item.iterdir())
        return found


@dataclasses.dataclass(frozen=True)
class CommandSpec:
    executable: str
    args: tuple[str, ...] = ()
    cwd: str | None = None
    env_delta: dict[str, str | None] = dataclasses.field(default_factory=dict)
    timeout_seconds: float = 30.0
    max_stdout_bytes: int = 1_048_576
    max_stderr_bytes: int = 1_048_576
    shell: bool = False


@dataclasses.dataclass
class CommandResult:
    status: str
    exit_code: int | None
    stdout: bytes
    stderr: bytes
    timed_out: bool
    pid: int
    process_identity: str


class ProcessTree:
    """Linux/macOS process-group fixture; production Windows uses Job Objects."""

    @staticmethod
    def start_token(pid: int) -> str:
        proc = pathlib.Path(f"/proc/{pid}/stat")
        if proc.exists():
            fields = proc.read_text(encoding="utf-8", errors="replace").split()
            return f"linux:{pid}:{fields[21]}"
        return f"pid:{pid}:{time.monotonic_ns()}"

    @staticmethod
    def terminate_group(pid: int, *, grace_seconds: float = 1.0) -> None:
        if os.name == "nt":
            raise P2Unsupported("windows_requires_job_object_adapter")
        for sig, delay in ((signal.SIGTERM, grace_seconds), (signal.SIGKILL, 0.2)):
            try:
                os.killpg(pid, sig)
            except ProcessLookupError:
                return
            except PermissionError:
                # The child is ours even when macOS denies a group-level signal.
                # Fall back to the group leader and preserve fail-closed cleanup.
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    return
            deadline = time.monotonic() + delay
            while time.monotonic() < deadline:
                try:
                    os.killpg(pid, 0)
                except ProcessLookupError:
                    return
                except PermissionError:
                    # macOS may return EPERM for a group transitioning through
                    # exit. The probe is inconclusive; continue escalation.
                    break
                time.sleep(0.02)


class CommandService:
    def __init__(self, boundary: EffectBoundary, journal: Journal) -> None:
        self.boundary = boundary
        self.journal = journal

    def run(self, spec: CommandSpec, *, decision: dict[str, Any], grant: dict[str, Any], binding: EffectBinding) -> tuple[CommandResult, Receipt]:
        auth = self.boundary.authorize(decision, grant, binding)
        if spec.shell:
            raise P2Denied("shell_requires_distinct_shell_capability")
        executable = pathlib.Path(spec.executable)
        if not executable.is_absolute():
            resolved = shutil.which(spec.executable)
            if not resolved:
                raise P2Denied("executable_not_found")
            executable = pathlib.Path(resolved)
        cwd = pathlib.Path(spec.cwd).expanduser() if spec.cwd else pathlib.Path.cwd()
        if not cwd.is_absolute() or not cwd.is_dir():
            raise P2Denied("cwd_invalid")
        env = dict(os.environ)
        for key, value in spec.env_delta.items():
            if "=" in key or "\x00" in key or SECRET_KEY.search(key):
                raise P2Denied("environment_key_forbidden")
            if value is None:
                env.pop(key, None)
            else:
                if "\x00" in value:
                    raise P2Denied("environment_value_invalid")
                env[key] = value
        started = dt.datetime.now(dt.timezone.utc)
        receipt = Receipt(str(uuid.uuid4()), binding.task_id, binding.operation, "started", started.isoformat())
        receipt.details = {
            "authorization": auth,
            "executable": str(executable),
            "argsSha256": hashlib.sha256(json.dumps(spec.args).encode()).hexdigest(),
            "cwd": str(cwd.resolve()),
            "environmentKeys": sorted(spec.env_delta),
        }
        self.journal.append(receipt)
        proc = subprocess.Popen(
            [str(executable), *spec.args], cwd=cwd, env=env,
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            start_new_session=(os.name != "nt"),
        )
        identity = ProcessTree.start_token(proc.pid)
        try:
            stdout, stderr = proc.communicate(timeout=spec.timeout_seconds)
            timed_out = False
        except subprocess.TimeoutExpired:
            timed_out = True
            ProcessTree.terminate_group(proc.pid)
            stdout, stderr = proc.communicate()
        overflow = len(stdout) > spec.max_stdout_bytes or len(stderr) > spec.max_stderr_bytes
        stdout = stdout[:spec.max_stdout_bytes]
        stderr = stderr[:spec.max_stderr_bytes]
        if overflow and proc.poll() is None:
            ProcessTree.terminate_group(proc.pid)
        status = "timed_out" if timed_out else "output_budget_exceeded" if overflow else "succeeded" if proc.returncode == 0 else "failed"
        result = CommandResult(status, proc.returncode, stdout, stderr, timed_out, proc.pid, identity)
        receipt.status = status
        receipt.completed_at = dt.datetime.now(dt.timezone.utc).isoformat()
        receipt.reversible = "irreversible"
        receipt.details.update({
            "processIdentity": identity,
            "exitCode": proc.returncode,
            "stdoutBytes": len(stdout), "stderrBytes": len(stderr),
            "stdoutSha256": hashlib.sha256(stdout).hexdigest(),
            "stderrSha256": hashlib.sha256(stderr).hexdigest(),
            "timedOut": timed_out, "outputTruncated": overflow,
        })
        self.journal.append(receipt)
        return result, receipt


def make_fixture_grant(binding: EffectBinding, *, max_uses: int = 1, grant_id: str | None = None) -> dict[str, Any]:
    now = dt.datetime.now(dt.timezone.utc)
    return {
        "schemaVersion": "2.0.0",
        "grantId": grant_id or f"grant-{uuid.uuid4()}",
        "issuer": {"actorId": "desktop_host", "authority": "desktop_host:deterministic_policy"},
        "binding": {
            "runId": binding.run_id, "taskId": binding.task_id,
            "actorId": binding.actor_id, "toolId": binding.tool_id,
            "accessProfileId": binding.access_profile_id,
        },
        "scope": {
            "paths": {"roots": ["*"]}, "process": {"executables": ["*"]},
            "network": {"destinations": []}, "browser": {"profiles": []},
            "secrets": {"leaseIds": [], "rawReveal": False},
        },
        "budgets": {"wallClockMs": 60000, "maxOutputBytes": 1048576, "maxMutations": 10},
        "validity": {
            "issuedAt": now.isoformat(), "notBefore": (now - dt.timedelta(seconds=1)).isoformat(),
            "expiresAt": (now + dt.timedelta(minutes=5)).isoformat(), "maxUses": max_uses,
        },
        "nonce": uuid.uuid4().hex,
        "auth": {"algorithm": "hmac-sha256", "keyId": "fixture-only", "mac": "0" * 64},
    }


def make_fixture_decision(binding: EffectBinding, target: str) -> dict[str, Any]:
    return {
        "schemaVersion": "2.0.0", "status": "allow",
        "binding": {
            "runId": binding.run_id, "taskId": binding.task_id,
            "actorId": binding.actor_id, "toolId": binding.tool_id,
            "accessProfileId": binding.access_profile_id, "capabilityId": binding.capability_id,
        },
        "effect": {"domain": binding.capability_id.split(".")[0], "action": binding.operation, "target": target},
    }


def atomic_json(path: pathlib.Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(tmp, path)
