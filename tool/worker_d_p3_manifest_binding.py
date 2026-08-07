#!/usr/bin/env python3
"""Verify P3 evidence-manifest artifact bindings against immutable Git bytes."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path, PurePosixPath

MANIFEST_PATH = "release/evidence/P3-001/manifest.json"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
GIT_OBJECT_RE = re.compile(r"^[0-9a-f]{40}$")
PACKAGING_BINDING = "IMMUTABLE_GIT_CANDIDATE"
PACKAGING_CLASSIFICATION = "STAGE_2_EVIDENCE_PACKAGING"
EXPECTED_ARTIFACT_PATHS = frozenset(
    {
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
    }
)


def _safe_relative_path(value: object) -> str | None:
    if not isinstance(value, str) or not value or value != value.strip():
        return None
    path = PurePosixPath(value.replace("\\", "/"))
    if path.is_absolute() or ".." in path.parts or "." in path.parts:
        return None
    return path.as_posix()


def _git_text(root: Path, *args: str) -> str:
    return subprocess.run(
        ["git", *args],
        cwd=root,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    ).stdout.strip()


def _git_bytes(root: Path, commit: str, rel: str) -> bytes:
    return subprocess.run(
        ["git", "show", f"{commit}:{rel}"],
        cwd=root,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout


def _git_is_ancestor(root: Path, ancestor: str, descendant: str) -> bool:
    return (
        subprocess.run(
            ["git", "merge-base", "--is-ancestor", ancestor, descendant],
            cwd=root,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode
        == 0
    )


def _candidate(
    value: object,
    label: str,
    errors: list[str],
    *,
    require_binding: bool = False,
) -> tuple[str, str] | None:
    if not isinstance(value, dict):
        errors.append(f"{label} must be an object")
        return None
    commit = value.get("commit")
    tree = value.get("tree")
    if not isinstance(commit, str) or GIT_OBJECT_RE.fullmatch(commit) is None:
        errors.append(f"{label}.commit must be a 40-character lowercase Git object id")
        return None
    if not isinstance(tree, str) or GIT_OBJECT_RE.fullmatch(tree) is None:
        errors.append(f"{label}.tree must be a 40-character lowercase Git object id")
        return None
    if require_binding:
        if value.get("binding") != PACKAGING_BINDING:
            errors.append(f"{label}.binding must be {PACKAGING_BINDING}")
            return None
        if value.get("classification") != PACKAGING_CLASSIFICATION:
            errors.append(f"{label}.classification must be {PACKAGING_CLASSIFICATION}")
            return None
    return commit, tree


def _verify_candidate(
    root: Path,
    candidate: tuple[str, str],
    label: str,
    errors: list[str],
) -> None:
    commit, declared_tree = candidate
    try:
        resolved_commit = _git_text(root, "rev-parse", "--verify", f"{commit}^{{commit}}")
        actual_tree = _git_text(root, "rev-parse", "--verify", f"{commit}^{{tree}}")
    except (OSError, subprocess.CalledProcessError):
        errors.append(f"{label}.commit does not resolve in repository: {commit}")
        return
    if resolved_commit != commit:
        errors.append(f"{label}.commit does not resolve to the declared commit {commit}")
    if actual_tree != declared_tree:
        errors.append(
            f"{label}.tree mismatch: declared {declared_tree}, actual {actual_tree}"
        )


def validate(root: Path) -> list[str]:
    errors: list[str] = []
    manifest_path = root / MANIFEST_PATH
    if manifest_path.is_symlink() or not manifest_path.is_file():
        return [f"missing evidence manifest {MANIFEST_PATH}"]
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        return [f"evidence manifest is unreadable: {error}"]
    if not isinstance(manifest, dict):
        return ["evidence manifest must be an object"]

    tested = _candidate(
        manifest.get("testedSourceCandidate"),
        "testedSourceCandidate",
        errors,
    )
    packaging = _candidate(
        manifest.get("evidencePackagingCandidate"),
        "evidencePackagingCandidate",
        errors,
        require_binding=True,
    )
    if tested is not None:
        _verify_candidate(root, tested, "testedSourceCandidate", errors)
    if packaging is not None:
        _verify_candidate(root, packaging, "evidencePackagingCandidate", errors)
    if tested is not None and packaging is not None:
        if not _git_is_ancestor(root, tested[0], packaging[0]):
            errors.append(
                "evidencePackagingCandidate.commit must descend from "
                "testedSourceCandidate.commit"
            )
        try:
            head = _git_text(root, "rev-parse", "--verify", "HEAD^{commit}")
        except (OSError, subprocess.CalledProcessError):
            errors.append("repository HEAD does not resolve")
            head = ""
        if head and not _git_is_ancestor(root, packaging[0], head):
            errors.append(
                "evidencePackagingCandidate.commit must be an ancestor of current HEAD"
            )

    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list):
        return errors + ["manifest artifacts must be an array"]
    observed: set[str] = set()
    for index, artifact in enumerate(artifacts):
        label = f"manifest artifacts[{index}]"
        if not isinstance(artifact, dict):
            errors.append(f"{label} must be an object")
            continue
        if set(artifact) != {"path", "sha256"}:
            errors.append(f"{label} must contain exactly path and sha256")
            continue
        rel = _safe_relative_path(artifact.get("path"))
        if rel is None:
            errors.append(f"{label} has unsafe path")
            continue
        if rel in observed:
            errors.append(f"duplicate manifest artifact path {rel}")
            continue
        observed.add(rel)
        expected = artifact.get("sha256")
        if not isinstance(expected, str) or SHA256_RE.fullmatch(expected) is None:
            errors.append(f"manifest artifact digest invalid {rel}")
            continue
        if packaging is None:
            continue
        try:
            packaged_bytes = _git_bytes(root, packaging[0], rel)
        except (OSError, subprocess.CalledProcessError):
            errors.append(
                f"manifest artifact is absent from immutable packaging candidate {rel}"
            )
            continue
        packaged_sha = hashlib.sha256(packaged_bytes).hexdigest()
        if packaged_sha != expected:
            errors.append(
                f"manifest artifact digest mismatch {rel}: expected {expected}, "
                f"packaging candidate computed {packaged_sha}"
            )
            continue
        try:
            head_bytes = _git_bytes(root, "HEAD", rel)
        except (OSError, subprocess.CalledProcessError):
            errors.append(f"manifest artifact is absent from current HEAD {rel}")
            continue
        if head_bytes != packaged_bytes:
            errors.append(
                f"manifest artifact drifted after frozen packaging candidate {rel}; "
                "explicit evidencePackagingCandidate rebind required"
            )

    missing = sorted(EXPECTED_ARTIFACT_PATHS - observed)
    extra = sorted(observed - EXPECTED_ARTIFACT_PATHS)
    if missing:
        errors.append(f"manifest artifact bindings missing: {', '.join(missing)}")
    if extra:
        errors.append(f"manifest artifact bindings unexpected: {', '.join(extra)}")
    return errors


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
