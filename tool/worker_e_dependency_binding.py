#!/usr/bin/env python3
"""Exact Git binding validation for Worker E P11 dependency evidence."""
from __future__ import annotations
import hashlib
import json
import re
import subprocess
from pathlib import Path, PurePosixPath
from typing import Any, Mapping

SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
SAFE_REF = re.compile(r"^refs/(?:heads|remotes)/[A-Za-z0-9._/-]+$")


class DependencyBindingError(ValueError):
    pass


def _run_git(project: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            ["git", "-C", str(project), *args],
            check=check,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise DependencyBindingError(f"git command failed: {' '.join(args)}") from exc


def _run_git_bytes(project: Path, *args: str) -> bytes:
    try:
        return subprocess.run(
            ["git", "-C", str(project), *args],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as exc:
        raise DependencyBindingError(f"git command failed: {' '.join(args)}") from exc


def commit_tree(project: Path, commit: str) -> str:
    if not SHA40.fullmatch(commit):
        raise DependencyBindingError(f"invalid commit identity: {commit!r}")
    result = _run_git(project, "rev-parse", f"{commit}^{{tree}}")
    tree = result.stdout.strip()
    if not SHA40.fullmatch(tree):
        raise DependencyBindingError(f"commit has invalid tree identity: {commit}")
    return tree


def is_ancestor(project: Path, ancestor: str) -> bool:
    result = _run_git(project, "merge-base", "--is-ancestor", ancestor, "HEAD", check=False)
    if result.returncode not in {0, 1}:
        raise DependencyBindingError(f"cannot evaluate ancestry: {ancestor}")
    return result.returncode == 0


def _safe_git_path(raw: Any, field: str) -> str:
    value = str(raw).strip()
    path = PurePosixPath(value)
    if (
        not value
        or path.is_absolute()
        or ".." in path.parts
        or "\\" in value
        or value in {".", ".."}
    ):
        raise DependencyBindingError(f"{field} is unsafe: {raw!r}")
    return path.as_posix()


def _snapshot_blob(project: Path, commit: str, path: str) -> str:
    result = _run_git(project, "rev-parse", "--verify", f"{commit}:{path}")
    blob = result.stdout.strip()
    if not SHA40.fullmatch(blob):
        raise DependencyBindingError(f"snapshot evidence has invalid blob identity: {path}")
    kind = _run_git(project, "cat-file", "-t", blob).stdout.strip()
    if kind != "blob":
        raise DependencyBindingError(f"snapshot evidence is not a blob: {path}")
    return blob


def _snapshot_blob_bytes(project: Path, blob: str) -> bytes:
    return _run_git_bytes(project, "cat-file", "blob", blob)


def _verify_evidence_bindings(
    project: Path,
    name: str,
    commit: str,
    row: Mapping[str, Any],
) -> dict[str, bytes]:
    bindings = row.get("evidenceBindings")
    if not isinstance(bindings, list) or not bindings:
        raise DependencyBindingError(f"{name} immutable snapshot lacks evidence bindings")
    verified: dict[str, bytes] = {}
    for index, item in enumerate(bindings):
        if not isinstance(item, Mapping):
            raise DependencyBindingError(f"{name} evidence binding {index} must be an object")
        path = _safe_git_path(item.get("path", ""), f"{name} evidence path")
        if path in verified:
            raise DependencyBindingError(f"{name} evidence path is duplicated: {path}")
        declared_blob = str(item.get("gitBlob", ""))
        if not SHA40.fullmatch(declared_blob):
            raise DependencyBindingError(f"{name} evidence binding lacks exact gitBlob: {path}")
        actual_blob = _snapshot_blob(project, commit, path)
        if actual_blob != declared_blob:
            raise DependencyBindingError(
                f"{name} snapshot evidence blob mismatch: {path} -> {actual_blob}, declared {declared_blob}"
            )
        content = _snapshot_blob_bytes(project, actual_blob)
        declared_sha256 = item.get("sha256")
        if declared_sha256 is not None:
            declared_sha256 = str(declared_sha256)
            if not SHA256.fullmatch(declared_sha256):
                raise DependencyBindingError(f"{name} evidence binding has invalid sha256: {path}")
            actual_sha256 = hashlib.sha256(content).hexdigest()
            if actual_sha256 != declared_sha256:
                raise DependencyBindingError(
                    f"{name} snapshot evidence sha256 mismatch: {path} -> {actual_sha256}, declared {declared_sha256}"
                )
        verified[path] = content
    evidence_paths = row.get("evidencePaths")
    if evidence_paths is not None:
        if not isinstance(evidence_paths, list):
            raise DependencyBindingError(f"{name} evidencePaths must be an array")
        normalized = [_safe_git_path(path, f"{name} evidencePaths") for path in evidence_paths]
        if normalized != list(verified):
            raise DependencyBindingError(f"{name} evidencePaths do not match immutable evidenceBindings")
    return verified


def _verify_review_artifact(
    project: Path,
    name: str,
    row: Mapping[str, Any],
    verified: Mapping[str, bytes],
) -> None:
    artifact_path = _safe_git_path(row.get("reviewArtifactPath", ""), f"{name} reviewArtifactPath")
    if artifact_path not in verified:
        raise DependencyBindingError(f"{name} review artifact is not immutable evidence: {artifact_path}")
    try:
        artifact = json.loads(verified[artifact_path].decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise DependencyBindingError(f"{name} review artifact is not valid UTF-8 JSON") from exc
    candidate = artifact.get("candidate")
    if not isinstance(candidate, Mapping):
        raise DependencyBindingError(f"{name} review artifact lacks candidate identity")
    reviewed_commit = str(row.get("reviewedCommit", ""))
    reviewed_tree = str(row.get("reviewedTree", ""))
    if not SHA40.fullmatch(reviewed_commit) or not SHA40.fullmatch(reviewed_tree):
        raise DependencyBindingError(f"{name} review binding lacks reviewed commit/tree")
    if candidate.get("commit") != reviewed_commit or candidate.get("tree") != reviewed_tree:
        raise DependencyBindingError(f"{name} review artifact candidate does not match declared reviewed identity")
    if commit_tree(project, reviewed_commit) != reviewed_tree:
        raise DependencyBindingError(f"{name} reviewed commit/tree identity is invalid")
    if artifact.get("reviewerRole") != row.get("reviewerRole"):
        raise DependencyBindingError(f"{name} review artifact reviewer role mismatch")
    if artifact.get("decision") != row.get("decision"):
        raise DependencyBindingError(f"{name} review artifact decision mismatch")

    expected_review = row.get("expectedReview")
    if not isinstance(expected_review, Mapping):
        raise DependencyBindingError(f"{name} review binding lacks expected review requirement")
    expected_keys = {"reviewType", "mission", "task", "pullRequest", "requiredScope"}
    if set(expected_review) != expected_keys:
        raise DependencyBindingError(f"{name} expected review requirement has unsupported fields")
    expected_review_type = expected_review.get("reviewType")
    expected_mission = expected_review.get("mission")
    expected_task = expected_review.get("task")
    expected_pr = expected_review.get("pullRequest")
    required_scope = expected_review.get("requiredScope")
    if not isinstance(expected_review_type, str) or not expected_review_type.strip():
        raise DependencyBindingError(f"{name} expected review type is invalid")
    if not isinstance(expected_mission, str) or not expected_mission.strip():
        raise DependencyBindingError(f"{name} expected review mission is invalid")
    if not isinstance(expected_task, str) or not expected_task.strip():
        raise DependencyBindingError(f"{name} expected review task is invalid")
    if not isinstance(expected_pr, int) or isinstance(expected_pr, bool) or expected_pr <= 0:
        raise DependencyBindingError(f"{name} expected review pull request is invalid")
    if not isinstance(required_scope, Mapping) or not required_scope:
        raise DependencyBindingError(f"{name} expected review scope is invalid")

    if artifact.get("reviewType") != expected_review_type:
        raise DependencyBindingError(f"{name} review artifact review type mismatch")
    if artifact.get("mission") != expected_mission:
        raise DependencyBindingError(f"{name} review artifact mission mismatch")
    if artifact.get("task") != expected_task:
        raise DependencyBindingError(f"{name} review artifact task mismatch")
    if artifact.get("pullRequest") != expected_pr:
        raise DependencyBindingError(f"{name} review artifact pull request mismatch")
    artifact_scope = artifact.get("scope")
    if not isinstance(artifact_scope, Mapping):
        raise DependencyBindingError(f"{name} review artifact lacks review scope")
    for flag, expected_value in required_scope.items():
        if (
            not isinstance(flag, str)
            or not flag
            or not isinstance(expected_value, bool)
        ):
            raise DependencyBindingError(f"{name} expected review scope is invalid")
        if artifact_scope.get(flag) is not expected_value:
            raise DependencyBindingError(
                f"{name} review artifact review scope mismatch: {flag}"
            )


def _resolve_live_ref(project: Path, ref: str) -> str:
    if not SAFE_REF.fullmatch(ref) or ".." in ref or ref.endswith("/"):
        raise DependencyBindingError(f"unsafe live ref: {ref!r}")
    result = _run_git(project, "rev-parse", "--verify", f"{ref}^{{commit}}")
    commit = result.stdout.strip()
    if not SHA40.fullmatch(commit):
        raise DependencyBindingError(f"live ref did not resolve to an exact commit: {ref}")
    return commit


def verify_binding(project: Path, name: str, row: Mapping[str, Any]) -> None:
    kind = row.get("bindingKind")
    if kind == "REVIEWER_AVAILABILITY":
        if name != "workerI" or row.get("activeBranch") is not None or row.get("activePr") is not None:
            raise DependencyBindingError("Worker I availability record is not fail-closed")
        return
    commit = str(row.get("commit", ""))
    tree = str(row.get("tree", ""))
    if not SHA40.fullmatch(commit) or not SHA40.fullmatch(tree):
        raise DependencyBindingError(f"{name} binding lacks exact commit/tree")
    if kind == "HISTORICAL_CONTEXT":
        if row.get("authoritative") is not False or row.get("liveHeadClaimed") is not False:
            raise DependencyBindingError(f"{name} historical context is ambiguous")
        return
    actual_tree = commit_tree(project, commit)
    if actual_tree != tree:
        raise DependencyBindingError(
            f"{name} commit/tree mismatch: {commit} -> {actual_tree}, declared {tree}"
        )
    if kind == "ANCESTRY_BASE":
        if row.get("requiredAncestry") is not True or not str(row.get("branch", "")).strip():
            raise DependencyBindingError(f"{name} ancestry binding is incomplete")
        if not is_ancestor(project, commit):
            raise DependencyBindingError(f"{name} required ancestry is missing: {commit}")
        return
    if kind in {"IMMUTABLE_EVIDENCE_SNAPSHOT", "IMMUTABLE_REVIEW_SNAPSHOT"}:
        if row.get("liveHeadClaimed") is not False:
            raise DependencyBindingError(f"{name} immutable snapshot claims live state")
        verified = _verify_evidence_bindings(project, name, commit, row)
        if kind == "IMMUTABLE_REVIEW_SNAPSHOT":
            _verify_review_artifact(project, name, row, verified)
        return
    if kind == "LIVE_HEAD_AT_CANDIDATE":
        if row.get("resolvedHead") is not None or row.get("observedRemoteHead") is not None:
            raise DependencyBindingError(f"{name} live head uses forbidden self-attested fields")
        ref = str(row.get("ref", ""))
        actual_head = _resolve_live_ref(project, ref)
        if actual_head != commit:
            raise DependencyBindingError(
                f"{name} live head drifted from exact binding: {ref} -> {actual_head}, declared {commit}"
            )
        return
    raise DependencyBindingError(f"{name} has unknown or ambiguous bindingKind: {kind!r}")


def validate_dependency_document(project: Path, document: Mapping[str, Any]) -> dict[str, Any]:
    inputs = document.get("repositoryInputs")
    if not isinstance(inputs, Mapping):
        raise DependencyBindingError("repositoryInputs must be an object")
    expected = {
        "protectedMain", "workerA", "workerB", "workerC",
        "workerD", "workerI", "workerJ",
    }
    if set(inputs) != expected:
        raise DependencyBindingError(f"repository input set changed: {sorted(inputs)}")
    for name, row in inputs.items():
        if not isinstance(row, Mapping):
            raise DependencyBindingError(f"{name} binding must be an object")
        verify_binding(project, name, row)
    return {
        "schemaVersion": 1,
        "resultState": "PASS",
        "bindingCount": len(inputs),
        "requiredAncestry": [
            name for name, row in inputs.items()
            if row.get("bindingKind") == "ANCESTRY_BASE"
        ],
    }


def main() -> int:
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=".")
    parser.add_argument(
        "--document",
        default="release/evidence/P11-001/dependency-status.json",
    )
    args = parser.parse_args()
    project = Path(args.project).resolve()
    try:
        document = json.loads((project / args.document).read_text(encoding="utf-8"))
        print(json.dumps(validate_dependency_document(project, document), sort_keys=True))
        return 0
    except (OSError, json.JSONDecodeError, DependencyBindingError) as exc:
        print(json.dumps({"resultState": "FAIL", "error": str(exc)}, sort_keys=True))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
