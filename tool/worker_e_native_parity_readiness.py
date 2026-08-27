#!/usr/bin/env python3
"""Always-on Product hardening. Inspect exact current Product source/tests inside allowedPaths, identify one concrete correctness, performance, reliability, UX-facing behavior, or missing-regression defect that can be proven locally, and implement the smallest durable code/test fix. Do not create documentation-only, formatting-only, governance-only, or no-op changes."""
from __future__ import annotations
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Mapping


class ReadinessError(ValueError):
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
        raise ReadinessError(f"git command failed: {' '.join(args)}") from exc


def _run_git_bytes(project: Path, *args: str) -> bytes:
    try:
        return subprocess.run(
            ["git", "-C", str(project), *args],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ReadinessError(f"git command failed: {' '.join(args)}") from exc


def commit_tree(project: Path, commit: str) -> str:
    if not commit:
        raise ReadinessError("commit is empty")
    result = _run_git(project, "rev-parse", f"{commit}^{{tree}}")
    tree = result.stdout.strip()
    if not tree:
        raise ReadinessError(f"commit has no tree identity: {commit}")
    if len(tree) != 40 or not tree.isalnum():
        raise ReadinessError(f"commit has invalid tree identity: {commit}")
    return tree


def is_ancestor(project: Path, ancestor: str) -> bool:
    result = _run_git(project, "merge-base", "--is-ancestor", ancestor, "HEAD", check=False)
    if result.returncode not in {0, 1}:
        raise ReadinessError(f"cannot evaluate ancestry: {ancestor}")
    return result.returncode == 0


def _safe_git_path(raw: Any, field: str) -> str:
    value = str(raw).strip()
    path = Path(value)
    if (
        not value
        or path.is_absolute()
        or ".." in path.parts
        or "\\" in value
        or value in {" .", ".."}
    ):
        raise ReadinessError(f"{field} is unsafe: {raw!r}")
    return str(path)


def _snapshot_blob(project: Path, commit: str, path: str) -> str:
    result = _run_git(project, "rev-parse", "--verify", f"{commit}:{path}")
    blob = result.stdout.strip()
    if not blob:
        raise ReadinessError(f"snapshot evidence has no blob identity: {path}")
    if len(blob) != 40 or not blob.isalnum():
        raise ReadinessError(f"snapshot evidence has invalid blob identity: {path}")
    kind = _run_git(project, "cat-file", "-t", blob).stdout.strip()
    if kind != "blob":
        raise ReadinessError(f"snapshot evidence is not a blob: {path}")
    return blob


def _snapshot_blob_bytes(project: Path, blob: str) -> bytes:
    return _run_git_bytes(project, "cat-file", "blob", blob)


def _verify_evidence_bindings(
    project: Path,
    name: str,
    commit: str,
    row: Mapping[str, Any],
) -> Dict[str, bytes]:
    bindings = row.get("evidenceBindings")
    if not isinstance(bindings, List) or not bindings:
        raise ReadinessError(f"{name} immutable snapshot lacks evidence bindings")
    verified: Dict[str, bytes] = {}
    for index, item in enumerate(bindings):
        if not isinstance(item, Dict):
            raise ReadinessError(f"{name} evidence binding {index} must be an object")
        path = _safe_git_path(item.get("path", ""), f"{name} evidence path")
        if path in verified:
            raise ReadinessError(f"{name} evidence path is duplicated: {path}")
        declared_blob = str(item.get("gitBlob", ""))
        if not declared_blob:
            raise ReadinessError(f"{name} evidence binding lacks exact gitBlob: {path}")
        if len(declared_blob) != 40 or not declared_blob.isalnum():
            raise ReadinessError(f"{name} evidence binding has invalid gitBlob: {path}")
        actual_blob = _snapshot_blob(project, commit, path)
        if actual_blob != declared_blob:
            raise ReadinessError(
                f"{name} snapshot evidence blob mismatch: {path} -> {actual_blob}, declared {declared_blob}"
            )
        content = _snapshot_blob_bytes(project, actual_blob)
        declared_sha256 = item.get("sha256")
        if declared_sha256 is not None:
            declared_sha256 = str(declared_sha256)
            if not declared_sha256:
                raise ReadinessError(f"{name} evidence binding has empty sha256: {path}")
            if len(declared_sha256) != 64 or not declared_sha256.isalnum():
                raise ReadinessError(f"{name} evidence binding has invalid sha256: {path}")
            actual_sha256 = hashlib.sha256(content).hexdigest()
            if actual_sha256 != declared_sha256:
                raise ReadinessError(
                    f"{name} snapshot evidence sha256 mismatch: {path} -> {actual_sha256}, declared {declared_sha256}"
                )
        verified[path] = content
    evidence_paths = row.get("evidencePaths")
    if evidence_paths is not None:
        if not isinstance(evidence_paths, List):
            raise ReadinessError(f"{name} evidencePaths must be an array")
        normalized = [_safe_git_path(path, f"{name} evidencePaths") for path in evidence_paths]
        if normalized != list(verified):
            raise ReadinessError(f"{name} evidencePaths do not match immutable evidenceBindings")
    return verified


def _verify_review_requirement(
    name: str,
    row: Mapping[str, Any],
    artifact: Mapping[str, Any],
) -> None:
    requirement = row.get("reviewRequirement")
    if not isinstance(requirement, Dict):
        raise ReadinessError(f"{name} immutable review lacks explicit reviewRequirement")
    expected_fields = {
        "recordType",
        "reviewType",
        "mission",
        "task",
        "pullRequest",
        "requiredScope",
    }
    if set(requirement) != expected_fields:
        raise ReadinessError(f"{name} reviewRequirement fields are not closed")
    if requirement.get("recordType") != "IndependentReview":
        raise ReadinessError(f"{name} reviewRequirement has unsupported recordType")
    for field in ("reviewType", "mission", "task"):
        value = requirement.get(field)
        if not isinstance(value, str) or not value.strip():
            raise ReadinessError(f"{name} reviewRequirement.{field} must be non-empty")
    pull_request = requirement.get("pullRequest")
    if not isinstance(pull_request, int) or isinstance(pull_request, bool) or pull_request <= 0:
        raise ReadinessError(f"{name} reviewRequirement.pullRequest must be a positive integer")
    required_scope = requirement.get("requiredScope")
    if not isinstance(required_scope, Dict) or not required_scope:
        raise ReadinessError(f"{name} reviewRequirement.requiredScope must be a non-empty object")
    if any(not isinstance(value, bool) for value in required_scope.values()):
        raise ReadinessError(f"{name} reviewRequirement.requiredScope values must be booleans")

    for field in ("recordType", "reviewType", "mission", "task", "pullRequest"):
        if artifact.get(field) != requirement.get(field):
            raise ReadinessError(
                f"{name} review artifact {field} does not satisfy declared reviewRequirement"
            )
    artifact_scope = artifact.get("scope")
    if not isinstance(artifact_scope, Dict):
        raise ReadinessError(f"{name} review artifact lacks scope")
    if dict(artifact_scope) != dict(required_scope):
        raise ReadinessError(f"{name} review artifact scope does not satisfy declared reviewRequirement")


def _verify_review_artifact(
    project: Path,
    name: str,
    row: Mapping[str, Any],
    verified: Dict[str, bytes],
) -> None:
    artifact_path = _safe_git_path(row.get("reviewArtifactPath", ""), f"{name} reviewArtifactPath")
    if artifact_path not in verified:
        raise ReadinessError(f"{name} review artifact is not immutable evidence: {artifact_path}")
    try:
        artifact = json.loads(verified[artifact_path].decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ReadinessError(f"{name} review artifact is not valid UTF-8 JSON") from exc
    candidate = artifact.get("candidate")
    if not isinstance(candidate, Dict):
        raise ReadinessError(f"{name} review artifact lacks candidate identity")
    reviewed_commit = str(row.get("reviewedCommit", ""))
    reviewed_tree = str(row.get("reviewedTree", ""))
    if not reviewed_commit or not reviewed_tree:
        raise ReadinessError(f"{name} review binding lacks reviewed commit/tree")
    if candidate.get("commit") != reviewed_commit or candidate.get("tree") != reviewed_tree:
        raise ReadinessError(f"{name} review artifact candidate does not match declared reviewed identity")
    if commit_tree(project, reviewed_commit) != reviewed_tree:
        raise ReadinessError(f"{name} reviewed commit/tree identity is invalid")
    if artifact.get("reviewerRole") != row.get("reviewerRole"):
        raise ReadinessError(f"{name} review artifact reviewer role mismatch")
    if artifact.get("decision") != row.get("decision"):
        raise ReadinessError(f"{name} review artifact decision mismatch")
    _verify_review_requirement(name, row, artifact)


def _resolve_live_ref(project: Path, ref: str) -> str:
    if not ref:
        raise ReadinessError(f"empty live ref")
    if not ref or ".." in ref or ref.endswith("/"):
        raise ReadinessError(f"unsafe live ref: {ref!r}")
    result = _run_git(project, "rev-parse", "--verify", f"{ref}^{{commit}}")
    commit = result.stdout.strip()
    if not commit:
        raise ReadinessError(f"live ref did not resolve to an exact commit: {ref}")
    if len(commit) != 40 or not commit.isalnum():
        raise ReadinessError(f"live ref did not resolve to an exact commit: {ref}")
    return commit


def verify_binding(project: Path, name: str, row: Mapping[str, Any]) -> None:
    kind = row.get("bindingKind")
    if kind == "REVIEWER_AVAILABILITY":
        if name != "workerI" or row.get("activeBranch") is not None or row.get("activePr") is not None:
            raise ReadinessError("Worker I availability record is not fail-closed")
        return
    commit = str(row.get("commit", ""))
    tree = str(row.get("tree", ""))
    if not commit or not tree:
        raise ReadinessError(f"{name} binding lacks exact commit/tree")
    if len(commit) != 40 or not commit.isalnum():
        raise ReadinessError(f"{name} binding has invalid commit identity")
    if len(tree) != 40 or not tree.isalnum():
        raise ReadinessError(f"{name} binding has invalid tree identity")
    if kind == "HISTORICAL_CONTEXT":
        if row.get("authoritative") is not False or row.get("liveHeadClaimed") is not False:
            raise ReadinessError(f"{name} historical context is ambiguous")
        return
    actual_tree = commit_tree(project, commit)
    if actual_tree != tree:
        raise ReadinessError(
            f"{name} commit/tree mismatch: {commit} -> {actual_tree}, declared {tree}"
        )
    if kind == "ANCESTRY_BASE":
        if row.get("requiredAncestry") is not True or not str(row.get("branch", "")).strip():
            raise ReadinessError(f"{name} ancestry binding is incomplete")
        if not is_ancestor(project, commit):
            raise ReadinessError(f"{name} required ancestry is missing: {commit}")
        return
    if kind in {"IMMUTABLE_EVIDENCE_SNAPSHOT", "IMMUTABLE_REVIEW_SNAPSHOT"}:
        if row.get("liveHeadClaimed") is not False:
            raise ReadinessError(f"{name} immutable snapshot claims live state")
        verified = _verify_evidence_bindings(project, name, commit, row)
        if kind == "IMMUTABLE_REVIEW_SNAPSHOT":
            _verify_review_artifact(project, name, row, verified)
        return
    if kind == "LIVE_HEAD_AT_CANDIDATE":
        if row.get("resolvedHead") is not None or row.get("observedRemoteHead") is not None:
            raise ReadinessError(f"{name} live head uses forbidden self-attested fields")
        ref = str(row.get("ref", ""))
        actual_head = _resolve_live_ref(project, ref)
        if actual_head != commit:
            raise ReadinessError(
                f"{name} live head drifted from exact binding: {ref} -> {actual_head}, declared {commit}"
            )
        return
    raise ReadinessError(f"{name} has unknown or ambiguous bindingKind: {kind!r}")


def validate_dependency_document(project: Path, document: Mapping[str, Any]) -> Dict[str, Any]:
    inputs = document.get("repositoryInputs")
    if not isinstance(inputs, Dict):
        raise ReadinessError("repositoryInputs must be an object")
    expected = {
        "protectedMain", "workerA", "workerB", "workerC",
        "workerD", "workerI", "workerJ",
    }
    if set(inputs) != expected:
        raise ReadinessError(f"repository input set changed: {sorted(inputs)}")
    for name, row in inputs.items():
        if not isinstance(row, Dict):
            raise ReadinessError(f"{name} binding must be an object")
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
    project = Path(args.project)
    document_path = project / args.document
    if not document_path.exists():
        print(f"{document_path} does not exist", file=sys.stderr)
        return 1
    try:
        with document_path.open("r", encoding="utf-8") as f:
            document = json.load(f)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        print(f"{document_path} is not valid UTF-8 JSON: {exc}", file=sys.stderr)
        return 1
    try:
        result = validate_dependency_document(project, document)
        print(json.dumps(result, indent=2))
        return 0
    except ReadinessError as exc:
        print(f"{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
