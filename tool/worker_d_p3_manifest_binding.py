#!/usr/bin/env python3
"""Verify P3 evidence artifacts against immutable Git candidate bytes."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path, PurePosixPath
from typing import Any

MANIFEST_PATH = "release/evidence/P3-001/manifest.json"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
GIT_OBJECT_RE = re.compile(r"^[0-9a-f]{40}$")
EXPECTED_ARTIFACT_PATHS = frozenset({
    ".github/workflows/worker-d-p3-readiness.yml",
    "config/test_center_registry.v1.json",
    "docs/roadmap/progress/2026-08-05-p3-001-readiness.md",
    "release/evidence/P3-001/READINESS.md",
    "release/evidence/P3-001/claim-boundary.json",
    "release/evidence/P3-001/dependency-status.json",
    "release/evidence/P3-001/fixture-specification.json",
    "release/evidence/P3-001/packaging-readiness-contract.json",
    "release/evidence/P3-001/runtime-candidate-matrix.json",
    "release/evidence/P3-001/test-center-registration.json",
    "tool/worker_d_p3_readiness.py",
    "tool/worker_d_p3_readiness_test.py",
})
PACKAGING_ARTIFACT_BINDINGS = {
    ".github/workflows/worker-d-p3-readiness.yml": (
        "548d1f0230e1ddb2e27aee07799058dca1bf893c",
        "ee25ca99e078dc49ffcd92098cceeecca56aaf17",
    ),
}


def _safe_relative_path(value: object) -> str | None:
    if not isinstance(value, str) or not value or value != value.strip():
        return None
    path = PurePosixPath(value.replace("\\", "/"))
    if path.is_absolute() or ".." in path.parts or "." in path.parts:
        return None
    return path.as_posix()


def _git(root: Path, *args: str, binary: bool = False) -> bytes | str:
    completed = subprocess.run(
        ["git", *args],
        cwd=root,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=not binary,
    )
    return completed.stdout if binary else completed.stdout.strip()


def _resolve_candidate(
    root: Path,
    record: object,
    label: str,
    errors: list[str],
) -> tuple[str, str] | None:
    if not isinstance(record, dict):
        errors.append(f"{label} must be an object")
        return None
    commit = record.get("commit")
    tree = record.get("tree")
    if not isinstance(commit, str) or GIT_OBJECT_RE.fullmatch(commit) is None:
        errors.append(f"{label}.commit must be a 40-character lowercase Git object id")
        return None
    if not isinstance(tree, str) or GIT_OBJECT_RE.fullmatch(tree) is None:
        errors.append(f"{label}.tree must be a 40-character lowercase Git object id")
        return None
    try:
        resolved_commit = _git(root, "rev-parse", "--verify", f"{commit}^{{commit}}")
        actual_tree = _git(root, "rev-parse", "--verify", f"{commit}^{{tree}}")
    except (OSError, subprocess.CalledProcessError):
        errors.append(f"{label}.commit does not resolve in repository: {commit}")
        return None
    if resolved_commit != commit:
        errors.append(f"{label}.commit does not resolve exactly to {commit}")
    if actual_tree != tree:
        errors.append(f"{label}.tree mismatch: declared {tree}, actual {actual_tree}")
    return commit, tree


def _git_blob_bytes(root: Path, commit: str, relative: str) -> bytes:
    raw = _git(root, "ls-tree", "-z", commit, "--", relative, binary=True)
    if not isinstance(raw, bytes) or not raw:
        raise ValueError("path is absent")
    entries = [entry for entry in raw.split(b"\0") if entry]
    if len(entries) != 1 or b"\t" not in entries[0]:
        raise ValueError("path does not resolve to exactly one tree entry")
    header, path_bytes = entries[0].split(b"\t", 1)
    mode, kind, blob_sha = header.decode("ascii").split()
    resolved_path = path_bytes.decode("utf-8")
    if resolved_path != relative:
        raise ValueError(f"resolved unexpected path {resolved_path}")
    if kind != "blob" or mode not in {"100644", "100755"}:
        raise ValueError(
            f"entry is not a regular source blob (mode={mode}, type={kind})"
        )
    data = _git(root, "cat-file", "blob", blob_sha, binary=True)
    if not isinstance(data, bytes):
        raise ValueError("Git blob read did not return bytes")
    return data


def validate_manifest_document(root: Path, manifest: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    tested = _resolve_candidate(
        root,
        manifest.get("testedSourceCandidate"),
        "testedSourceCandidate",
        errors,
    )
    packaging = manifest.get("evidencePackagingCandidate")
    if not isinstance(packaging, dict):
        errors.append("evidencePackagingCandidate must be an object")
    elif (
        packaging.get("binding") != "EXTERNAL_AFTER_PUBLICATION"
        or packaging.get("commit") is not None
        or packaging.get("tree") is not None
    ):
        errors.append(
            "evidencePackagingCandidate must remain externally bound without "
            "a self-referential package commit/tree"
        )

    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list):
        return [*errors, "manifest artifacts must be an array"]
    if tested is None:
        return errors

    observed: set[str] = set()
    resolved_candidates: dict[tuple[str, str], bool] = {tested: True}
    for index, artifact in enumerate(artifacts):
        label = f"manifest artifacts[{index}]"
        if not isinstance(artifact, dict):
            errors.append(f"{label} must be an object")
            continue
        if set(artifact) != {"path", "sha256"}:
            errors.append(f"{label} must contain exactly path and sha256")
            continue
        relative = _safe_relative_path(artifact.get("path"))
        if relative is None:
            errors.append(f"{label} has unsafe path")
            continue
        if relative in observed:
            errors.append(f"duplicate manifest artifact path {relative}")
            continue
        observed.add(relative)

        expected_digest = artifact.get("sha256")
        if (
            not isinstance(expected_digest, str)
            or SHA256_RE.fullmatch(expected_digest) is None
        ):
            errors.append(f"manifest artifact digest invalid {relative}")
            continue

        candidate = PACKAGING_ARTIFACT_BINDINGS.get(relative, tested)
        if candidate != tested and candidate not in resolved_candidates:
            candidate_errors: list[str] = []
            resolved = _resolve_candidate(
                root,
                {"commit": candidate[0], "tree": candidate[1]},
                f"packaging artifact {relative}",
                candidate_errors,
            )
            resolved_candidates[candidate] = (
                resolved is not None and not candidate_errors
            )
            errors.extend(candidate_errors)
        if not resolved_candidates.get(candidate, False):
            continue

        try:
            data = _git_blob_bytes(root, candidate[0], relative)
        except (
            OSError,
            subprocess.CalledProcessError,
            UnicodeError,
            ValueError,
        ) as exc:
            errors.append(f"manifest artifact Git binding invalid {relative}: {exc}")
            continue
        actual_digest = hashlib.sha256(data).hexdigest()
        if actual_digest != expected_digest:
            binding_kind = (
                "packaging candidate"
                if relative in PACKAGING_ARTIFACT_BINDINGS
                else "tested source candidate"
            )
            errors.append(
                "manifest artifact digest mismatch "
                f"{relative} at immutable {binding_kind} {candidate[0]} / "
                f"{candidate[1]}: expected {expected_digest}, computed {actual_digest}"
            )

    missing = sorted(EXPECTED_ARTIFACT_PATHS - observed)
    extra = sorted(observed - EXPECTED_ARTIFACT_PATHS)
    if missing:
        errors.append(f"manifest artifact bindings missing: {', '.join(missing)}")
    if extra:
        errors.append(f"manifest artifact bindings unexpected: {', '.join(extra)}")
    return errors


def validate(root: Path) -> list[str]:
    path = root / MANIFEST_PATH
    if path.is_symlink() or not path.is_file():
        return [f"missing evidence manifest {MANIFEST_PATH}"]
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return [f"evidence manifest is unreadable: {exc}"]
    if not isinstance(document, dict):
        return ["evidence manifest must be an object"]
    return validate_manifest_document(root, document)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--project", default=".")
    args = parser.parse_args()
    if not args.check:
        raise SystemExit("--check is required; validator is non-mutating")
    errors = validate(Path(args.project).resolve())
    if errors:
        print("\n".join(f"FAIL {error}" for error in errors))
        raise SystemExit(1)
    print("Worker D P3 immutable evidence artifact bindings: PASS")


if __name__ == "__main__":
    main()
