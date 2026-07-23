#!/usr/bin/env python3
"""Capture a deterministic Kristin production-readiness baseline.

P0-001 intentionally changes no product behavior. It separates two kinds of
output:

* ``baseline.json`` and ``BASELINE.md`` are deterministic. They are derived
  only from committed inputs: SOURCE_MANIFEST.sha256 and observations.json.
* ``execution.json`` and ``EXECUTION.md`` describe the current machine. Missing
  SDKs, missing checkout files, and gates that were not run are represented
  explicitly; none are silently treated as passing.

The implementation is dependency-free and safe to run before Flutter is
installed. In a complete checkout, use ``--manifest-mode verify``. A reviewer
working from a manifest snapshot may use ``--manifest-mode snapshot``; that
mode always records source verification as unavailable.
"""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Any, Iterable, Mapping, Sequence

SCHEMA_VERSION = "1.0.0"
MILESTONE_ID = "P0-001"
DEFAULT_OUTPUT = "release/evidence/baseline"
DEFAULT_OBSERVATIONS = "release/evidence/baseline/observations.json"
DEFAULT_MANIFEST = "SOURCE_MANIFEST.sha256"
MAX_COMMAND_OUTPUT = 50_000

STATUS_PASSED = "passed"
STATUS_FAILED = "failed"
STATUS_UNAVAILABLE = "unavailable"
STATUS_NOT_RUN = "not_run"

_HASH_RE = re.compile(r"^[0-9a-f]{64}$")
_SECRET_PATTERNS: tuple[tuple[re.Pattern[str], str], ...] = (
    (
        re.compile(r"(?i)\b(https?|socks5h?)://[^/\s:@]+:[^@\s/]+@"),
        r"\1://<redacted>@",
    ),
    (
        re.compile(r"(?i)(authorization\s*[:=]\s*bearer\s+)[^\s]+"),
        r"\1<redacted>",
    ),
    (
        re.compile(
            r"(?i)\b(api[_-]?key|token|secret|password)"
            r"(\s*[:=]\s*)[^\s,;]+"
        ),
        r"\1\2<redacted>",
    ),
    (re.compile(r"\bsk-[A-Za-z0-9_-]{16,}\b"), "<redacted-openai-key>"),
    (re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b"), "<redacted-github-token>"),
)


class BaselineError(ValueError):
    """Raised for invalid deterministic baseline input."""


@dataclass(frozen=True, order=True)
class ManifestEntry:
    sha256: str
    path: str


@dataclass(frozen=True)
class GateResult:
    name: str
    status: str
    reason: str
    argv: tuple[str, ...] = ()
    exit_code: int | None = None
    output_sha256: str | None = None
    output_tail: str = ""
    duration_ms: int = 0

    def to_json(self) -> dict[str, Any]:
        payload = asdict(self)
        payload["argv"] = list(self.argv)
        return payload


def canonical_json(value: Any) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        + "\n"
    ).encode("utf-8")


def pretty_json(value: Any) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode(
        "utf-8"
    )


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def stable_iso_time(observations: Mapping[str, Any]) -> str:
    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    if epoch is not None:
        try:
            instant = datetime.fromtimestamp(int(epoch), tz=timezone.utc)
        except (ValueError, OverflowError) as error:
            raise BaselineError("SOURCE_DATE_EPOCH must be an integer epoch") from error
        return instant.isoformat(timespec="seconds").replace("+00:00", "Z")
    observed = observations.get("observedAt")
    if not isinstance(observed, str) or not observed.strip():
        raise BaselineError(
            "observations.json must define observedAt when SOURCE_DATE_EPOCH is absent"
        )
    return observed.strip()


def execution_iso_time(observations: Mapping[str, Any]) -> str:
    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    if epoch is not None:
        return stable_iso_time(observations)
    return datetime.now(tz=timezone.utc).isoformat(timespec="seconds").replace(
        "+00:00", "Z"
    )


def normalize_manifest_path(raw: str) -> str:
    if "\\" in raw:
        raise BaselineError(f"manifest path must use POSIX separators: {raw!r}")
    path = PurePosixPath(raw)
    if not raw or path.is_absolute() or raw.startswith("/"):
        raise BaselineError(f"manifest path must be relative: {raw!r}")
    if any(part in ("", ".", "..") for part in path.parts):
        raise BaselineError(f"manifest path is not canonical: {raw!r}")
    normalized = path.as_posix()
    if normalized != raw:
        raise BaselineError(f"manifest path is not normalized: {raw!r}")
    return normalized


def parse_source_manifest(path: Path) -> list[ManifestEntry]:
    if not path.is_file():
        raise BaselineError(f"source manifest not found: {path}")
    entries: list[ManifestEntry] = []
    seen: set[str] = set()
    for line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        if not raw_line.strip():
            continue
        if "  " not in raw_line:
            raise BaselineError(
                f"{path}:{line_number}: expected '<sha256>  <relative-path>'"
            )
        digest, raw_relative = raw_line.split("  ", 1)
        digest = digest.strip().lower()
        if not _HASH_RE.fullmatch(digest):
            raise BaselineError(f"{path}:{line_number}: invalid sha256")
        relative = normalize_manifest_path(raw_relative)
        if relative in seen:
            raise BaselineError(f"{path}:{line_number}: duplicate path {relative!r}")
        seen.add(relative)
        entries.append(ManifestEntry(digest, relative))
    if not entries:
        raise BaselineError("source manifest is empty")
    return sorted(entries, key=lambda item: item.path)


def manifest_bytes(entries: Iterable[ManifestEntry]) -> bytes:
    return "".join(f"{item.sha256}  {item.path}\n" for item in entries).encode("utf-8")


def load_json_object(path: Path, label: str) -> dict[str, Any]:
    if not path.is_file():
        raise BaselineError(f"{label} not found: {path}")
    try:
        decoded = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise BaselineError(f"{label} is invalid JSON: {error}") from error
    if not isinstance(decoded, dict):
        raise BaselineError(f"{label} must contain one JSON object")
    return decoded


def subset_digest(entries: Sequence[ManifestEntry]) -> str:
    return sha256_bytes(manifest_bytes(sorted(entries, key=lambda item: item.path)))


def is_test_path(path: str) -> bool:
    posix = PurePosixPath(path)
    name = posix.name.lower()
    return (
        path.startswith("test/")
        or name.endswith("_test.py")
        or name.endswith("_test.dart")
        or name.endswith(".test.py")
        or name.endswith(".test.dart")
    )


def extension_key(path: str) -> str:
    suffix = PurePosixPath(path).suffix.lower()
    return suffix if suffix else "<none>"


def inventory_source_tree(entries: Sequence[ManifestEntry]) -> dict[str, Any]:
    top_level = Counter(
        item.path.split("/", 1)[0] if "/" in item.path else "<root>"
        for item in entries
    )
    extensions = Counter(extension_key(item.path) for item in entries)
    schemas = [
        item for item in entries if item.path.startswith("schemas/") and item.path.endswith(".json")
    ]
    tests = [item for item in entries if is_test_path(item.path)]
    ci = [
        item
        for item in entries
        if item.path.startswith(".github/workflows/")
        and item.path.endswith((".yml", ".yaml"))
    ]
    tools = [item for item in entries if item.path.startswith("tool/")]
    docs = [item for item in entries if item.path.startswith("docs/")]
    migrations = [item for item in entries if item.path.startswith("migrations/")]
    return {
        "entryCount": len(entries),
        "topLevelCounts": dict(sorted(top_level.items())),
        "extensionCounts": dict(sorted(extensions.items())),
        "schemaCount": len(schemas),
        "schemaPaths": [item.path for item in schemas],
        "schemaSetSha256": subset_digest(schemas),
        "testAndGateFileCount": len(tests),
        "testAndGatePaths": [item.path for item in tests],
        "testAndGateSetSha256": subset_digest(tests),
        "ciWorkflowCount": len(ci),
        "ciWorkflowPaths": [item.path for item in ci],
        "ciWorkflowSetSha256": subset_digest(ci),
        "toolSourceCount": len(tools),
        "toolSourceSetSha256": subset_digest(tools),
        "documentationCount": len(docs),
        "documentationSetSha256": subset_digest(docs),
        "migrationCount": len(migrations),
        "migrationSetSha256": subset_digest(migrations),
    }


def manifest_hash_for(entries: Sequence[ManifestEntry], path: str) -> str | None:
    for item in entries:
        if item.path == path:
            return item.sha256
    return None


def build_stable_baseline(
    entries: Sequence[ManifestEntry],
    observations: Mapping[str, Any],
    manifest_path: Path,
) -> dict[str, Any]:
    repository = observations.get("repository")
    release = observations.get("release")
    ci = observations.get("ci")
    tool_registry = observations.get("toolRegistry")
    blockers = observations.get("knownBlockers")
    for name, value in (
        ("repository", repository),
        ("release", release),
        ("ci", ci),
        ("toolRegistry", tool_registry),
    ):
        if not isinstance(value, dict):
            raise BaselineError(f"observations.json field {name!r} must be an object")
    if not isinstance(blockers, list):
        raise BaselineError("observations.json field 'knownBlockers' must be an array")

    source_inventory = inventory_source_tree(entries)
    normalized_manifest = manifest_bytes(entries)
    raw_manifest_sha = sha256_file(manifest_path)
    normalized_manifest_sha = sha256_bytes(normalized_manifest)
    registry_path = "schemas/tool_registry.v2.json"
    workflow_path = ".github/workflows/ci.yml"

    baseline: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "milestone": {
            "id": MILESTONE_ID,
            "name": "Capture reproducible baseline",
            "phase": "P0 — Stabilize, contain, and establish truth",
            "scope": "Inventory and evidence only; no product behavior changes.",
            "roadmapPath": "docs/KRISTIN_GOLD_STANDARD_PRODUCTION_ROADMAP.md",
            "acceptance": (
                "A clean checkout reproduces the deterministic report and every "
                "unavailable machine gate is explicit in execution.json."
            ),
        },
        "generatedAt": stable_iso_time(observations),
        "repository": repository,
        "release": release,
        "sourceTree": {
            "manifestPath": DEFAULT_MANIFEST,
            "manifestFileSha256": raw_manifest_sha,
            "normalizedManifestSha256": normalized_manifest_sha,
            **source_inventory,
        },
        "toolRegistry": {
            **tool_registry,
            "path": registry_path,
            "sourceSha256": manifest_hash_for(entries, registry_path),
            "fullLocalInspection": "execution.json#localInspection.toolRegistry",
        },
        "continuousIntegration": {
            **ci,
            "workflowPath": workflow_path,
            "workflowSourceSha256": manifest_hash_for(entries, workflow_path),
            "fullLocalInspection": "execution.json#localInspection.ciWorkflow",
        },
        "knownBlockers": blockers,
        "evidenceSources": observations.get("evidenceSources", []),
        "reproduction": {
            "deterministicCommand": (
                "python3 tool/capture_baseline.py --project . "
                "--manifest-mode verify --run-safe-gates"
            ),
            "snapshotCommand": (
                "python3 tool/capture_baseline.py --project . "
                "--manifest-mode snapshot"
            ),
            "deterministicInputs": [
                DEFAULT_MANIFEST,
                DEFAULT_OBSERVATIONS,
            ],
            "deterministicOutputs": [
                f"{DEFAULT_OUTPUT}/baseline.json",
                f"{DEFAULT_OUTPUT}/BASELINE.md",
            ],
            "machineSpecificOutputs": [
                f"{DEFAULT_OUTPUT}/execution.json",
                f"{DEFAULT_OUTPUT}/EXECUTION.md",
            ],
        },
    }
    fingerprint_input = dict(baseline)
    baseline["stableFingerprintSha256"] = sha256_bytes(canonical_json(fingerprint_input))
    return baseline


def redact(text: str, project_root: Path | None = None) -> str:
    value = text
    if project_root is not None:
        root_text = str(project_root.resolve())
        if root_text:
            value = value.replace(root_text, "<PROJECT>")
    for pattern, replacement in _SECRET_PATTERNS:
        value = pattern.sub(replacement, value)
    return value


def run_fixed_command(
    name: str,
    argv: Sequence[str],
    *,
    project_root: Path,
    timeout_seconds: int,
) -> GateResult:
    started = time.monotonic()
    try:
        completed = subprocess.run(
            list(argv),
            cwd=project_root,
            env={**os.environ, "CI": "true"},
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            check=False,
            timeout=timeout_seconds,
        )
        raw = completed.stdout or ""
        safe = redact(raw, project_root)[-MAX_COMMAND_OUTPUT:]
        return GateResult(
            name=name,
            status=STATUS_PASSED if completed.returncode == 0 else STATUS_FAILED,
            reason="command completed",
            argv=tuple(argv),
            exit_code=completed.returncode,
            output_sha256=sha256_bytes(raw.encode("utf-8", errors="replace")),
            output_tail=safe,
            duration_ms=int((time.monotonic() - started) * 1000),
        )
    except subprocess.TimeoutExpired as error:
        output = error.stdout or ""
        if isinstance(output, bytes):
            output = output.decode("utf-8", errors="replace")
        return GateResult(
            name=name,
            status=STATUS_FAILED,
            reason=f"timed out after {timeout_seconds} seconds",
            argv=tuple(argv),
            exit_code=None,
            output_sha256=sha256_bytes(output.encode("utf-8", errors="replace")),
            output_tail=redact(output, project_root)[-MAX_COMMAND_OUTPUT:],
            duration_ms=int((time.monotonic() - started) * 1000),
        )
    except OSError as error:
        return GateResult(
            name=name,
            status=STATUS_UNAVAILABLE,
            reason=f"could not execute command: {error}",
            argv=tuple(argv),
            duration_ms=int((time.monotonic() - started) * 1000),
        )


def verify_source_manifest(
    project_root: Path,
    entries: Sequence[ManifestEntry],
    mode: str,
) -> dict[str, Any]:
    if mode == "snapshot":
        return {
            "status": STATUS_UNAVAILABLE,
            "reason": (
                "snapshot mode selected; the manifest was inventoried but checkout "
                "bytes were not asserted"
            ),
            "entryCount": len(entries),
            "verifiedCount": 0,
            "missing": [],
            "mismatched": [],
        }
    missing: list[str] = []
    mismatched: list[dict[str, str]] = []
    verified = 0
    for item in entries:
        candidate = project_root / item.path
        if not candidate.is_file():
            missing.append(item.path)
            continue
        actual = sha256_file(candidate)
        if actual != item.sha256:
            mismatched.append(
                {"path": item.path, "expectedSha256": item.sha256, "actualSha256": actual}
            )
            continue
        verified += 1
    status = STATUS_PASSED if not missing and not mismatched else STATUS_FAILED
    return {
        "status": status,
        "reason": (
            "all manifest entries matched"
            if status == STATUS_PASSED
            else "one or more manifest entries were absent or changed"
        ),
        "entryCount": len(entries),
        "verifiedCount": verified,
        "missing": missing,
        "mismatched": mismatched,
    }


def inspect_json_file(
    project_root: Path,
    relative: str,
    expected_sha256: str | None,
) -> tuple[str, dict[str, Any] | None, str]:
    path = project_root / relative
    if not path.is_file():
        return STATUS_UNAVAILABLE, None, f"{relative} is not present in this checkout"
    actual = sha256_file(path)
    if expected_sha256 is not None and actual != expected_sha256:
        return (
            STATUS_FAILED,
            None,
            f"{relative} hash differs from SOURCE_MANIFEST.sha256",
        )
    try:
        decoded = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        return STATUS_FAILED, None, f"{relative} is invalid JSON: {error}"
    if not isinstance(decoded, dict):
        return STATUS_FAILED, None, f"{relative} must contain a JSON object"
    return STATUS_PASSED, decoded, "file hash and JSON structure verified"


def inspect_tool_registry(
    project_root: Path,
    entries: Sequence[ManifestEntry],
) -> dict[str, Any]:
    relative = "schemas/tool_registry.v2.json"
    status, decoded, reason = inspect_json_file(
        project_root, relative, manifest_hash_for(entries, relative)
    )
    result: dict[str, Any] = {"status": status, "reason": reason, "path": relative}
    if decoded is None:
        return result
    tools = decoded.get("tools")
    if not isinstance(tools, list):
        return {
            **result,
            "status": STATUS_FAILED,
            "reason": "tool registry field 'tools' is not an array",
        }
    summaries: list[dict[str, Any]] = []
    invalid_indices: list[int] = []
    for index, item in enumerate(tools):
        if not isinstance(item, dict) or not isinstance(item.get("name"), str):
            invalid_indices.append(index)
            continue
        summaries.append(
            {
                "name": item.get("name"),
                "version": item.get("version"),
                "permission": item.get("permission"),
                "risk": item.get("risk"),
                "dataBoundary": item.get("dataBoundary"),
                "idempotency": item.get("idempotency"),
            }
        )
    if invalid_indices:
        result["status"] = STATUS_FAILED
        result["reason"] = f"invalid tool records at indices {invalid_indices}"
    result.update(
        {
            "registryVersion": decoded.get("registryVersion"),
            "compatibilityPolicyVersion": decoded.get("compatibilityPolicyVersion"),
            "toolCount": len(tools),
            "tools": summaries,
        }
    )
    return result


def inspect_ci_workflow(
    project_root: Path,
    entries: Sequence[ManifestEntry],
) -> dict[str, Any]:
    relative = ".github/workflows/ci.yml"
    path = project_root / relative
    expected = manifest_hash_for(entries, relative)
    if not path.is_file():
        return {
            "status": STATUS_UNAVAILABLE,
            "reason": f"{relative} is not present in this checkout",
            "path": relative,
        }
    actual = sha256_file(path)
    text = path.read_text(encoding="utf-8", errors="replace")
    actions = re.findall(r"(?m)^\s*-?\s*uses:\s*([^\s#]+)", text)
    matrix_match = re.search(r"(?m)^\s*os:\s*\[([^\]]+)\]", text)
    matrix = []
    if matrix_match:
        matrix = [item.strip() for item in matrix_match.group(1).split(",") if item.strip()]
    channel_match = re.search(r"(?m)^\s*channel:\s*([^\s#]+)", text)
    moving_refs = [action for action in actions if re.search(r"@v\d+$", action)]
    if channel_match and channel_match.group(1).strip("'\"") == "stable":
        moving_refs.append("flutter channel: stable")
    status = STATUS_PASSED if expected is None or actual == expected else STATUS_FAILED
    return {
        "status": status,
        "reason": (
            "workflow source hash matched"
            if status == STATUS_PASSED
            else "workflow source hash differs from SOURCE_MANIFEST.sha256"
        ),
        "path": relative,
        "sha256": actual,
        "matrix": matrix,
        "actions": actions,
        "flutterChannel": channel_match.group(1).strip("'\"") if channel_match else None,
        "movingReferences": moving_refs,
    }


def inspect_pubspec(project_root: Path, expected_version: Any) -> dict[str, Any]:
    relative = "pubspec.yaml"
    path = project_root / relative
    if not path.is_file():
        return {
            "status": STATUS_UNAVAILABLE,
            "reason": f"{relative} is not present in this checkout",
            "path": relative,
        }
    text = path.read_text(encoding="utf-8", errors="replace")
    version_match = re.search(r"(?m)^version:\s*([^\s#]+)", text)
    sdk_match = re.search(r"(?m)^\s*sdk:\s*['\"]?([^'\"\n]+)", text)
    version = version_match.group(1) if version_match else None
    expected = str(expected_version) if expected_version is not None else None
    status = STATUS_PASSED if expected is None or version == expected else STATUS_FAILED
    return {
        "status": status,
        "reason": (
            "pubspec version matched the observation snapshot"
            if status == STATUS_PASSED
            else f"pubspec version {version!r} did not match expected {expected!r}"
        ),
        "path": relative,
        "version": version,
        "sdkConstraint": sdk_match.group(1).strip() if sdk_match else None,
    }


def tool_probe(name: str) -> dict[str, Any]:
    executable = shutil.which(name)
    if executable is None:
        return {
            "status": STATUS_UNAVAILABLE,
            "reason": f"{name} is not available on PATH",
            "version": None,
        }
    if name == "python3":
        version = platform.python_version()
    else:
        try:
            completed = subprocess.run(
                [executable, "--version"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                errors="replace",
                check=False,
                timeout=20,
            )
            version = redact((completed.stdout or "").strip())[:1000]
        except (OSError, subprocess.TimeoutExpired) as error:
            return {
                "status": STATUS_UNAVAILABLE,
                "reason": f"{name} version probe failed: {error}",
                "version": None,
            }
    return {"status": STATUS_PASSED, "reason": "available", "version": version}


def not_run_sdk_gate(name: str, executable: str, tools: Mapping[str, Any]) -> GateResult:
    probe = tools.get(executable)
    if not isinstance(probe, dict) or probe.get("status") != STATUS_PASSED:
        return GateResult(
            name=name,
            status=STATUS_UNAVAILABLE,
            reason=f"{executable} is unavailable; gate was not executed",
        )
    return GateResult(
        name=name,
        status=STATUS_NOT_RUN,
        reason="P0-001 records SDK availability but does not mutate or build the product",
    )


def safe_source_gates(project_root: Path, enabled: bool) -> list[GateResult]:
    specs: tuple[tuple[str, tuple[str, ...], int], ...] = (
        (
            "offline_system_contracts",
            (sys.executable, "tool/system_test.py", "--project", ".", "--json"),
            180,
        ),
        (
            "durable_workflow_kernel",
            (sys.executable, "tool/workflow_kernel_test.py", "--project", ".", "--json"),
            240,
        ),
        (
            "source_release_validation",
            (sys.executable, "tool/validate_release.py", "--skip-sdk"),
            600,
        ),
    )
    results: list[GateResult] = []
    for name, argv, timeout in specs:
        script_path = project_root / argv[1]
        if not script_path.is_file():
            results.append(
                GateResult(
                    name=name,
                    status=STATUS_UNAVAILABLE,
                    reason=f"{argv[1]} is not present in this checkout",
                    argv=argv,
                )
            )
        elif not enabled:
            results.append(
                GateResult(
                    name=name,
                    status=STATUS_NOT_RUN,
                    reason="--run-safe-gates was not selected",
                    argv=argv,
                )
            )
        else:
            results.append(
                run_fixed_command(
                    name,
                    argv,
                    project_root=project_root,
                    timeout_seconds=timeout,
                )
            )
    return results


def build_execution_report(
    project_root: Path,
    entries: Sequence[ManifestEntry],
    observations: Mapping[str, Any],
    *,
    manifest_mode: str,
    run_safe_gates_enabled: bool,
) -> dict[str, Any]:
    tools = {name: tool_probe(name) for name in ("python3", "git", "dart", "flutter", "node")}
    release_observation = observations.get("release", {})
    expected_version = (
        release_observation.get("version")
        if isinstance(release_observation, dict)
        else None
    )
    source_verification = verify_source_manifest(project_root, entries, manifest_mode)
    gates = safe_source_gates(project_root, run_safe_gates_enabled)
    gates.extend(
        (
            not_run_sdk_gate("dart_format", "dart", tools),
            not_run_sdk_gate("flutter_dependency_resolution", "flutter", tools),
            not_run_sdk_gate("flutter_static_analysis", "flutter", tools),
            not_run_sdk_gate("flutter_tests", "flutter", tools),
            not_run_sdk_gate("native_release_build", "flutter", tools),
        )
    )
    local_inspection = {
        "pubspec": inspect_pubspec(project_root, expected_version),
        "toolRegistry": inspect_tool_registry(project_root, entries),
        "ciWorkflow": inspect_ci_workflow(project_root, entries),
    }
    explicit_statuses = [source_verification.get("status")]
    explicit_statuses.extend(result.status for result in gates)
    explicit_statuses.extend(
        item.get("status") for item in local_inspection.values() if isinstance(item, dict)
    )
    blocking_failures = [
        result.name for result in gates if result.status == STATUS_FAILED
    ]
    if source_verification.get("status") == STATUS_FAILED:
        blocking_failures.insert(0, "source_manifest_integrity")
    for name, inspection in local_inspection.items():
        if inspection.get("status") == STATUS_FAILED:
            blocking_failures.append(f"local_inspection.{name}")
    return {
        "schemaVersion": SCHEMA_VERSION,
        "milestoneId": MILESTONE_ID,
        "capturedAt": execution_iso_time(observations),
        "projectRoot": "<PROJECT>",
        "manifestMode": manifest_mode,
        "runSafeGates": run_safe_gates_enabled,
        "host": {
            "system": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
            "pythonImplementation": platform.python_implementation(),
        },
        "tools": tools,
        "sourceManifestIntegrity": source_verification,
        "localInspection": local_inspection,
        "gates": [item.to_json() for item in gates],
        "statusSummary": dict(sorted(Counter(str(item) for item in explicit_statuses).items())),
        "blockingFailures": blocking_failures,
        "captureStatus": STATUS_PASSED,
        "projectGateStatus": STATUS_FAILED if blocking_failures else (
            STATUS_UNAVAILABLE
            if STATUS_UNAVAILABLE in explicit_statuses or STATUS_NOT_RUN in explicit_statuses
            else STATUS_PASSED
        ),
        "note": (
            "captureStatus describes this evidence capture, not product readiness. "
            "A missing or unrun gate is never promoted to passed."
        ),
    }


def render_baseline_markdown(baseline: Mapping[str, Any]) -> str:
    repository = baseline["repository"]
    release = baseline["release"]
    source = baseline["sourceTree"]
    registry = baseline["toolRegistry"]
    ci = baseline["continuousIntegration"]
    run = ci.get("latestObservedRun", {}) if isinstance(ci, dict) else {}
    lines = [
        "# Kristin P0-001 reproducible baseline",
        "",
        f"Generated from committed inputs at **{baseline['generatedAt']}**.",
        "",
        "> This is a deterministic observation report, not a claim that the product passes all gates. "
        "Machine-specific availability and execution status are recorded in `execution.json`.",
        "",
        "## Milestone contract",
        "",
        f"- ID: `{baseline['milestone']['id']}`",
        f"- Scope: {baseline['milestone']['scope']}",
        f"- Acceptance: {baseline['milestone']['acceptance']}",
        "",
        "## Repository snapshot",
        "",
        f"- Repository: `{repository.get('url')}`",
        f"- Branch: `{repository.get('branch')}`",
        f"- Commit: `{repository.get('commit')}`",
        f"- Commit message: {repository.get('commitMessage')}",
        f"- Imported files/additions: {repository.get('filesChanged')} files / {repository.get('additions')} additions",
        "",
        "## Release snapshot",
        "",
        f"- Version: `{release.get('version')}`",
        f"- Classification: `{release.get('classification')}`",
        f"- Source gate reported by existing release metadata: `{release.get('sourceGatePassed')}`",
        f"- Compiled desktop release validated: `{release.get('compiledReleaseValidated')}`",
        "",
        "## Source inventory",
        "",
        f"- Manifest entries: **{source.get('entryCount')}**",
        f"- Schemas: **{source.get('schemaCount')}**",
        f"- Tests and executable gate files: **{source.get('testAndGateFileCount')}**",
        f"- Tool sources: **{source.get('toolSourceCount')}**",
        f"- Documentation files: **{source.get('documentationCount')}**",
        f"- Workflow migrations: **{source.get('migrationCount')}**",
        f"- Source manifest SHA-256: `{source.get('manifestFileSha256')}`",
        f"- Normalized source-set SHA-256: `{source.get('normalizedManifestSha256')}`",
        "",
        "### Top-level source counts",
        "",
        "| Path | Count |",
        "|---|---:|",
    ]
    for name, count in source.get("topLevelCounts", {}).items():
        lines.append(f"| `{name}` | {count} |")
    lines.extend(
        (
            "",
            "## Tool registry",
            "",
            f"- Registry version: `{registry.get('registryVersion')}`",
            f"- Canonical tool contracts: **{registry.get('canonicalToolContractCount')}**",
            f"- Registry source SHA-256: `{registry.get('sourceSha256')}`",
            "- Full per-tool local inspection: `execution.json#localInspection.toolRegistry`",
            "",
            "## Current CI observation",
            "",
            f"- Workflow: `{ci.get('workflowName')}`",
            f"- Matrix: `{', '.join(ci.get('matrix', []))}`",
            f"- Latest run: `{run.get('id')}` — **{run.get('conclusion')}**",
            f"- Failing step: `{run.get('failedStep')}`",
            f"- Failing command: `{run.get('failedCommand')}`",
            "",
        )
    )
    jobs = run.get("jobs", []) if isinstance(run, dict) else []
    if jobs:
        lines.extend(("| Platform | Result | Job |", "|---|---:|---:|"))
        for job in jobs:
            if isinstance(job, dict):
                lines.append(
                    f"| `{job.get('platform')}` | {job.get('conclusion')} | `{job.get('jobId')}` |"
                )
        lines.append("")
    lines.extend(("## Known blockers", ""))
    for blocker in baseline.get("knownBlockers", []):
        if not isinstance(blocker, dict):
            continue
        lines.append(
            f"- **{blocker.get('severity', 'unknown')} — {blocker.get('title', 'unnamed')}**: "
            f"{blocker.get('detail', '')} Next task: `{blocker.get('nextTask', 'unassigned')}`."
        )
    lines.extend(
        (
            "",
            "## Reproduction",
            "",
            "From a clean checkout of the recorded commit:",
            "",
            "```bash",
            str(baseline["reproduction"]["deterministicCommand"]),
            "```",
            "",
            "The deterministic outputs are `baseline.json` and `BASELINE.md`. "
            "The execution outputs intentionally record host-specific availability.",
            "",
            f"Stable fingerprint: `{baseline['stableFingerprintSha256']}`",
            "",
        )
    )
    return "\n".join(lines)


def render_execution_markdown(execution: Mapping[str, Any]) -> str:
    lines = [
        "# Kristin P0-001 machine execution",
        "",
        f"Captured: **{execution.get('capturedAt')}**",
        "",
        f"- Manifest mode: `{execution.get('manifestMode')}`",
        f"- Evidence capture: **{execution.get('captureStatus')}**",
        f"- Product gate status on this machine: **{execution.get('projectGateStatus')}**",
        "",
        "## Tool availability",
        "",
        "| Tool | Status | Version / reason |",
        "|---|---:|---|",
    ]
    for name, result in execution.get("tools", {}).items():
        detail = result.get("version") or result.get("reason")
        lines.append(f"| `{name}` | {result.get('status')} | {str(detail).replace('|', '\\|')} |")
    source = execution.get("sourceManifestIntegrity", {})
    lines.extend(
        (
            "",
            "## Source manifest verification",
            "",
            f"- Status: **{source.get('status')}**",
            f"- Reason: {source.get('reason')}",
            f"- Verified: {source.get('verifiedCount')} / {source.get('entryCount')}",
            f"- Missing: {len(source.get('missing', []))}",
            f"- Mismatched: {len(source.get('mismatched', []))}",
            "",
            "## Gates",
            "",
            "| Gate | Status | Exit | Reason |",
            "|---|---:|---:|---|",
        )
    )
    for result in execution.get("gates", []):
        exit_code = "—" if result.get("exit_code") is None else result.get("exit_code")
        reason = str(result.get("reason", "")).replace("|", "\\|")
        lines.append(
            f"| `{result.get('name')}` | {result.get('status')} | {exit_code} | {reason} |"
        )
    lines.extend(("", "## Local inspections", ""))
    for name, result in execution.get("localInspection", {}).items():
        lines.append(f"- `{name}`: **{result.get('status')}** — {result.get('reason')}")
    if execution.get("blockingFailures"):
        lines.extend(("", "## Blocking failures", ""))
        for failure in execution["blockingFailures"]:
            lines.append(f"- `{failure}`")
    lines.extend(("", f"> {execution.get('note')}", ""))
    return "\n".join(lines)


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temporary:
        temporary.write(data)
        temporary.flush()
        os.fsync(temporary.fileno())
        temporary_path = Path(temporary.name)
    temporary_path.replace(path)


def capture(
    *,
    project_root: Path,
    manifest_path: Path,
    observations_path: Path,
    output_directory: Path,
    manifest_mode: str,
    run_safe_gates_enabled: bool,
) -> tuple[dict[str, Any], dict[str, Any]]:
    entries = parse_source_manifest(manifest_path)
    observations = load_json_object(observations_path, "baseline observations")
    baseline = build_stable_baseline(entries, observations, manifest_path)
    execution = build_execution_report(
        project_root,
        entries,
        observations,
        manifest_mode=manifest_mode,
        run_safe_gates_enabled=run_safe_gates_enabled,
    )
    # Rebuild the stable payload before writing. This catches accidental
    # dependence on mutable execution state in the same process.
    repeated = build_stable_baseline(entries, observations, manifest_path)
    if canonical_json(baseline) != canonical_json(repeated):
        raise BaselineError("deterministic baseline changed within one capture")

    atomic_write(output_directory / "baseline.json", pretty_json(baseline))
    atomic_write(
        output_directory / "BASELINE.md",
        render_baseline_markdown(baseline).encode("utf-8"),
    )
    atomic_write(output_directory / "execution.json", pretty_json(execution))
    atomic_write(
        output_directory / "EXECUTION.md",
        render_execution_markdown(execution).encode("utf-8"),
    )
    capture_manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "milestoneId": MILESTONE_ID,
        "deterministic": {
            "baseline.json": sha256_file(output_directory / "baseline.json"),
            "BASELINE.md": sha256_file(output_directory / "BASELINE.md"),
        },
        "machineSpecific": {
            "execution.json": sha256_file(output_directory / "execution.json"),
            "EXECUTION.md": sha256_file(output_directory / "EXECUTION.md"),
        },
        "stableFingerprintSha256": baseline["stableFingerprintSha256"],
    }
    atomic_write(output_directory / "capture_manifest.json", pretty_json(capture_manifest))
    return baseline, execution


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=".", help="Kristin checkout root")
    parser.add_argument("--manifest", default=DEFAULT_MANIFEST)
    parser.add_argument("--observations", default=DEFAULT_OBSERVATIONS)
    parser.add_argument("--output", default=DEFAULT_OUTPUT)
    parser.add_argument(
        "--manifest-mode",
        choices=("verify", "snapshot"),
        default="verify",
        help="verify checkout bytes or inventory the manifest snapshot only",
    )
    parser.add_argument(
        "--run-safe-gates",
        action="store_true",
        help="run fixed, network-free Python source gates when present",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="exit non-zero for local manifest mismatch or an executed gate failure",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    project_root = Path(args.project).expanduser().resolve()
    manifest_path = (project_root / args.manifest).resolve()
    observations_path = (project_root / args.observations).resolve()
    output_directory = (project_root / args.output).resolve()
    try:
        baseline, execution = capture(
            project_root=project_root,
            manifest_path=manifest_path,
            observations_path=observations_path,
            output_directory=output_directory,
            manifest_mode=args.manifest_mode,
            run_safe_gates_enabled=args.run_safe_gates,
        )
    except (BaselineError, OSError) as error:
        print(f"P0-001 baseline capture failed: {error}", file=sys.stderr)
        return 2
    print(
        "P0-001 baseline captured: "
        f"entries={baseline['sourceTree']['entryCount']} "
        f"fingerprint={baseline['stableFingerprintSha256']} "
        f"project_gate_status={execution['projectGateStatus']}"
    )
    if args.strict and execution["blockingFailures"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
