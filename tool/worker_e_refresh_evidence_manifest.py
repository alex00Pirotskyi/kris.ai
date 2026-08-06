#!/usr/bin/env python3
"""Deterministically bind Worker E evidence to the current repository bytes."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import tempfile
from typing import Any

MANIFEST = Path("release/evidence/P11-001/manifest.json")
REQUIRED_ARTIFACTS = (
    ".github/workflows/worker-e-native-parity-readiness.yml",
    "release/evidence/P11-001/dependency-status.json",
    "release/evidence/P11-001/test-center-owner-handoff.json",
    "release/evidence/P11-001/test-center-registration-spec.json",
    "tool/worker_e_dependency_binding.py",
    "tool/worker_e_native_parity_readiness.py",
    "tool/worker_e_native_parity_readiness_test.py",
    "tool/worker_e_refresh_evidence_manifest.py",
    "tool/worker_e_refresh_evidence_manifest_test.py",
    "tool/worker_e_test_center_registration.py",
    "tool/worker_e_test_center_registration_test.py",
)


class ManifestError(ValueError):
    pass


def _safe_relative(value: str) -> str:
    raw = str(value).replace("\\", "/").strip()
    while raw.startswith("./"):
        raw = raw[2:]
    posix = PurePosixPath(raw)
    windows = PureWindowsPath(raw)
    if (
        not raw
        or raw == "."
        or raw.startswith("/")
        or posix.is_absolute()
        or windows.is_absolute()
        or windows.drive
        or ".." in posix.parts
        or ".." in windows.parts
        or "\0" in raw
    ):
        raise ManifestError(f"artifact path must be repository-relative: {value!r}")
    return posix.as_posix()


def _canonical_bytes(value: Any) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        + "\n"
    ).encode("utf-8")


def _load(project: Path) -> dict[str, Any]:
    try:
        value = json.loads((project / MANIFEST).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ManifestError(f"cannot load {MANIFEST}: {exc}") from exc
    if not isinstance(value, dict) or not isinstance(value.get("artifacts"), list):
        raise ManifestError("Worker E evidence manifest must contain an artifacts array")
    return value


def expected_manifest(project: Path) -> dict[str, Any]:
    project = project.resolve()
    value = _load(project)
    rows = value["artifacts"]
    seen: set[str] = set()
    normalized: list[dict[str, Any]] = []

    for raw_row in rows:
        if not isinstance(raw_row, dict):
            raise ManifestError("artifact rows must be objects")
        row = dict(raw_row)
        rel = _safe_relative(row.get("path", ""))
        if rel in seen:
            raise ManifestError(f"duplicate artifact path: {rel}")
        seen.add(rel)
        row["path"] = rel
        normalized.append(row)

    for rel in REQUIRED_ARTIFACTS:
        if rel not in seen:
            normalized.append({"path": rel})
            seen.add(rel)

    for row in normalized:
        path = project / row["path"]
        if not path.is_file():
            raise ManifestError(f"artifact path does not exist: {row['path']}")
        payload = path.read_bytes()
        row["bytes"] = len(payload)
        row["sha256"] = hashlib.sha256(payload).hexdigest()

    value["artifacts"] = normalized
    return value


def expected_bytes(project: Path) -> bytes:
    return _canonical_bytes(expected_manifest(project))


def check(project: Path) -> dict[str, Any]:
    project = project.resolve()
    current = (project / MANIFEST).read_bytes()
    expected = expected_bytes(project)
    if current != expected:
        raise ManifestError("Worker E evidence manifest is stale")
    return {
        "schemaVersion": 1,
        "resultState": "PASS",
        "path": MANIFEST.as_posix(),
        "sha256": hashlib.sha256(current).hexdigest(),
        "bytes": len(current),
        "artifactCount": len(_load(project)["artifacts"]),
    }


def write(project: Path) -> dict[str, Any]:
    project = project.resolve()
    path = project / MANIFEST
    expected = expected_bytes(project)
    before = path.read_bytes()
    if before == expected:
        return {**check(project), "changed": False}

    fd, name = tempfile.mkstemp(prefix=".worker-e-manifest-", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(expected)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(name, path)
    finally:
        try:
            os.unlink(name)
        except FileNotFoundError:
            pass

    return {**check(project), "changed": True}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=".")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    args = parser.parse_args()
    try:
        result = check(Path(args.project)) if args.check else write(Path(args.project))
    except ManifestError as exc:
        print(json.dumps({"schemaVersion": 1, "resultState": "FAIL", "error": str(exc)}, sort_keys=True))
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
