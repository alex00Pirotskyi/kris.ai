#!/usr/bin/env python3
"""Exact Git binding validation for Worker E P11 dependency evidence."""
from __future__ import annotations
import json
import re
import subprocess
from pathlib import Path
from typing import Any, Mapping

SHA40 = re.compile(r"^[0-9a-f]{40}$")

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

def _require_paths(project: Path, values: list[str], field: str) -> None:
    for raw in values:
        path = Path(str(raw))
        if path.is_absolute() or ".." in path.parts or not str(raw).strip():
            raise DependencyBindingError(f"{field} is unsafe: {raw!r}")
        if not (project / path).is_file():
            raise DependencyBindingError(f"{field} is missing: {raw}")

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
        evidence = row.get("evidencePaths")
        if not isinstance(evidence, list) or not evidence:
            raise DependencyBindingError(f"{name} immutable snapshot lacks evidence")
        _require_paths(project, evidence, f"{name} evidence")
        return
    if kind == "LIVE_HEAD_AT_CANDIDATE":
        if row.get("resolvedHead") != commit or row.get("observedRemoteHead") != commit:
            raise DependencyBindingError(f"{name} live head drifted from exact binding")
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
