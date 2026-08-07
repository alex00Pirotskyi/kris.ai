#!/usr/bin/env python3
"""Verify P3 dependency identity, owner lineage, and immutable evidence semantics."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path
from typing import Any

DOCUMENT_PATH = "release/evidence/P3-001/dependency-status.json"
GIT_OBJECT_RE = re.compile(r"^[0-9a-f]{40}$")

P1_012_EVIDENCE_PATHS = frozenset({
    "tasks/completed/P1-012.md",
    "release/evidence/P1-012/manifest.json",
    "release/evidence/P1-012/test-results.json",
    "release/evidence/P1-012/OWNER_APPROVAL.md",
    "config/local_ipc.v1.json",
    "docs/architecture/LOCAL_AUTHENTICATED_IPC_V1.md",
    "tool/local_authenticated_ipc.py",
    "lib/product/local_authenticated_ipc_v1.dart",
    "test/product/local_authenticated_ipc_v1_test.dart",
})
P2_004_EVIDENCE_PATHS = frozenset({
    "release/evidence/P2-004/IMPLEMENTATION.md",
    "release/evidence/P2-004/manifest.json",
    "release/evidence/P2-004/technology-spike.json",
    "release/evidence/P2-004/test-results.json",
})
P1_CLAIMS = {
    "Mutually authenticated loopback request": "mutual_authentication",
    "Unrelated local process rejected": "unrelated_local_process_rejected",
    "Replay rejected": "replay_rejected",
    "Tri-platform transport contract": "tri_platform_transport_contract",
}


def _object(value: object, label: str, errors: list[str]) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        errors.append(f"{label} must be an object")
        return None
    return value


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


def _declared_pair(
    record: object,
    label: str,
    errors: list[str],
    *,
    commit_key: str = "commit",
    tree_key: str = "tree",
) -> tuple[str, str] | None:
    obj = _object(record, label, errors)
    if obj is None:
        return None
    commit = obj.get(commit_key)
    tree = obj.get(tree_key)
    if not isinstance(commit, str) or GIT_OBJECT_RE.fullmatch(commit) is None:
        errors.append(
            f"{label}.{commit_key} must be a 40-character lowercase Git object id"
        )
        return None
    if not isinstance(tree, str) or GIT_OBJECT_RE.fullmatch(tree) is None:
        errors.append(
            f"{label}.{tree_key} must be a 40-character lowercase Git object id"
        )
        return None
    return commit, tree


def _verify_pair(
    root: Path,
    record: object,
    label: str,
    errors: list[str],
    *,
    commit_key: str = "commit",
    tree_key: str = "tree",
) -> tuple[str, str] | None:
    pair = _declared_pair(
        record,
        label,
        errors,
        commit_key=commit_key,
        tree_key=tree_key,
    )
    if pair is None:
        return None
    commit, tree = pair
    try:
        resolved = _git(root, "rev-parse", "--verify", f"{commit}^{{commit}}")
        actual_tree = _git(root, "rev-parse", "--verify", f"{commit}^{{tree}}")
    except (OSError, subprocess.CalledProcessError):
        errors.append(f"{label} commit does not resolve in repository: {commit}")
        return None
    if resolved != commit:
        errors.append(f"{label} does not resolve to the declared commit {commit}")
    if actual_tree != tree:
        errors.append(f"{label} tree mismatch: declared {tree}, actual {actual_tree}")
        return None
    return commit, tree


def _is_ancestor(root: Path, ancestor: str, descendant: str) -> bool:
    completed = subprocess.run(
        ["git", "merge-base", "--is-ancestor", ancestor, descendant],
        cwd=root,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return completed.returncode == 0


def _snapshot_bytes(root: Path, commit: str, path: str) -> bytes:
    data = _git(root, "show", f"{commit}:{path}", binary=True)
    if not isinstance(data, bytes):
        raise ValueError("Git snapshot read did not return bytes")
    return data


def _snapshot_json(
    root: Path,
    commit: str,
    path: str,
    errors: list[str],
) -> dict[str, Any] | None:
    try:
        value = json.loads(_snapshot_bytes(root, commit, path).decode("utf-8"))
    except (
        OSError,
        UnicodeError,
        json.JSONDecodeError,
        subprocess.CalledProcessError,
        ValueError,
    ) as exc:
        errors.append(f"immutable dependency evidence is unreadable {path}: {exc}")
        return None
    if not isinstance(value, dict):
        errors.append(f"immutable dependency evidence must be an object {path}")
        return None
    return value


def _validate_paths(
    root: Path,
    dependency: dict[str, Any],
    commit: str,
    expected: frozenset[str],
    task_id: str,
    errors: list[str],
) -> None:
    raw = dependency.get("evidencePaths")
    if not isinstance(raw, list) or any(not isinstance(item, str) for item in raw):
        errors.append(f"{task_id}.evidencePaths must contain only strings")
        return
    observed = set(raw)
    if len(observed) != len(raw):
        errors.append(f"{task_id}.evidencePaths contains duplicates")
    missing = sorted(expected - observed)
    extra = sorted(observed - expected)
    if missing:
        errors.append(
            f"{task_id}.evidencePaths missing immutable evidence: {', '.join(missing)}"
        )
    if extra:
        errors.append(
            f"{task_id}.evidencePaths contains unbound evidence: {', '.join(extra)}"
        )
    for path in sorted(observed & expected):
        try:
            _snapshot_bytes(root, commit, path)
        except (OSError, subprocess.CalledProcessError, ValueError):
            errors.append(
                f"{task_id}.evidencePaths does not resolve from implementation snapshot: {path}"
            )


def _validate_p1_012(
    root: Path,
    dependency: dict[str, Any],
    commit: str,
    errors: list[str],
) -> None:
    _validate_paths(root, dependency, commit, P1_012_EVIDENCE_PATHS, "P1-012", errors)
    manifest = _snapshot_json(root, commit, "release/evidence/P1-012/manifest.json", errors)
    results = _snapshot_json(root, commit, "release/evidence/P1-012/test-results.json", errors)
    try:
        owner = _snapshot_bytes(root, commit, "release/evidence/P1-012/OWNER_APPROVAL.md").decode("utf-8")
        _snapshot_bytes(root, commit, "tasks/completed/P1-012.md")
    except (OSError, UnicodeError, subprocess.CalledProcessError, ValueError) as exc:
        errors.append(f"P1-012 immutable status/review evidence is unreadable: {exc}")
        return
    if manifest is None or results is None:
        return
    if manifest.get("taskId") != "P1-012" or manifest.get("status") != "passed":
        errors.append("P1-012 manifest does not prove passed task evidence")
    expected_results_sha = hashlib.sha256(
        _snapshot_bytes(root, commit, "release/evidence/P1-012/test-results.json")
    ).hexdigest()
    if manifest.get("testResultsSha256") != expected_results_sha:
        errors.append("P1-012 manifest does not bind immutable test-results bytes")
    if results.get("taskId") != "P1-012" or results.get("passed") is not True:
        errors.append("P1-012 immutable test results are not passing")

    tests = dependency.get("tests")
    if not isinstance(tests, dict):
        errors.append("P1-012 tests claim must be an object")
    else:
        for key in ("caseCount", "passedCount", "failedCount"):
            if tests.get(key) != results.get(key):
                errors.append(f"P1-012 tests.{key} does not match immutable test results")
        result_items = results.get("results")
        if not isinstance(result_items, list):
            result_items = []
        expected_claims = sorted(
            P1_CLAIMS[name]
            for name in P1_CLAIMS
            if any(
                isinstance(item, dict)
                and item.get("name") == name
                and item.get("passed") is True
                for item in result_items
            )
        )
        claims = tests.get("claims")
        if not isinstance(claims, list) or sorted(claims) != expected_claims:
            errors.append("P1-012 tests.claims do not match immutable test results")

    if dependency.get("authoritativeStatus") != "DONE":
        errors.append("P1-012 authoritativeStatus must remain DONE for this snapshot")
    review = dependency.get("review")
    if not isinstance(review, dict):
        errors.append("P1-012 review claim must be an object")
    else:
        expected_owner = "PASS" if "- Decision: approve " in owner else "MISSING"
        if review.get("ownerApproval") != expected_owner:
            errors.append("P1-012 ownerApproval does not match immutable owner receipt")
        if review.get("independentReview") != "MISSING":
            errors.append(
                "P1-012 independentReview cannot advance without an immutable review receipt"
            )
    if dependency.get("decision") != "MISSING_INDEPENDENT_REVIEW":
        errors.append(
            "P1-012 decision must remain MISSING_INDEPENDENT_REVIEW until an immutable review receipt is bound"
        )


def _validate_p2_004(
    root: Path,
    dependency: dict[str, Any],
    commit: str,
    errors: list[str],
) -> None:
    _validate_paths(root, dependency, commit, P2_004_EVIDENCE_PATHS, "P2-004", errors)
    manifest = _snapshot_json(root, commit, "release/evidence/P2-004/manifest.json", errors)
    spike = _snapshot_json(root, commit, "release/evidence/P2-004/technology-spike.json", errors)
    results = _snapshot_json(root, commit, "release/evidence/P2-004/test-results.json", errors)
    if manifest is None or spike is None or results is None:
        return
    if (
        manifest.get("taskId") != "P2-004"
        or manifest.get("status") != "source_only"
        or manifest.get("ownerApproval") != {"status": "pending"}
        or manifest.get("independentReview") != {"status": "pending"}
        or manifest.get("platformReceipts") != {}
        or manifest.get("completedTaskPacket") is not None
    ):
        errors.append("P2-004 manifest does not prove the declared blocked review/measurement state")
    spike_decision = spike.get("decision")
    if not isinstance(spike_decision, dict):
        spike_decision = {}
    if (
        spike.get("completionEligible") is not False
        or spike.get("sourceOnly") is not True
        or spike_decision.get("status") != "blocked_external_tri_platform_measurement_required"
    ):
        errors.append("P2-004 technology spike does not prove external measurement blocking")
    result_items = results.get("tests")
    if not isinstance(result_items, list):
        result_items = []
    if (
        results.get("taskId") != "P2-004"
        or results.get("status") != "source_only"
        or not any(
            isinstance(item, dict)
            and item.get("name") == "measured automation-host comparison"
            and item.get("status") == "source_only"
            and item.get("detail") == "blocked_external_tri_platform_measurement_required"
            for item in result_items
        )
    ):
        errors.append("P2-004 test results do not prove measurement remains source-only")
    if dependency.get("authoritativeStatus") != "BLOCKED":
        errors.append("P2-004 authoritativeStatus must remain BLOCKED for this snapshot")
    if dependency.get("decision") != "MISSING_MEASUREMENT":
        errors.append("P2-004 decision must remain MISSING_MEASUREMENT for this snapshot")
    if dependency.get("review") != {"independentReview": "MISSING", "ownerApproval": "MISSING"}:
        errors.append("P2-004 review claims do not match immutable pending-review evidence")
    expected_measurements = {
        "memory": "MISSING_MEASUREMENT",
        "packaging": "MISSING_MEASUREMENT",
        "platformReceipts": {},
        "reliability": "MISSING_MEASUREMENT",
        "startup": "MISSING_MEASUREMENT",
    }
    if dependency.get("measurements") != expected_measurements:
        errors.append("P2-004 measurement claims do not match immutable source-only evidence")
    expected_blockers = {
        "CONFLICTING_ARCHITECTURE_DECISION",
        "MISSING_INDEPENDENT_REVIEW",
        "BLOCKED_EXTERNAL",
    }
    blockers = dependency.get("additionalBlockers")
    if not isinstance(blockers, list) or set(blockers) != expected_blockers:
        errors.append("P2-004 additionalBlockers do not match the immutable blocked snapshot")


def validate_document(root: Path, document: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    repository = _object(document.get("repository"), "repository", errors)
    worker_a: tuple[str, str] | None = None
    if repository is not None:
        for key in (
            "protectedMain",
            "workerBBranchCreationBase",
            "workerBSynchronizedBase",
            "workerC",
            "workerJ",
        ):
            _verify_pair(root, repository.get(key), f"repository.{key}", errors)
        worker_a = _verify_pair(
            root,
            repository.get("workerADependencyCandidate"),
            "repository.workerADependencyCandidate",
            errors,
        )
        _verify_pair(
            root,
            repository.get("workerD"),
            "repository.workerD",
            errors,
            commit_key="synchronizationCommit",
            tree_key="synchronizationTree",
        )

    dependencies = document.get("dependencies")
    if not isinstance(dependencies, list):
        errors.append("dependencies must be an array")
        return errors
    seen: set[str] = set()
    for index, raw_dependency in enumerate(dependencies):
        dependency = _object(raw_dependency, f"dependencies[{index}]", errors)
        if dependency is None:
            continue
        task_id = dependency.get("taskId")
        if not isinstance(task_id, str) or not task_id:
            errors.append(f"dependencies[{index}].taskId must be non-empty")
            continue
        if task_id in seen:
            errors.append(f"duplicate dependency taskId {task_id}")
            continue
        seen.add(task_id)
        pair = _verify_pair(
            root,
            dependency.get("implementation"),
            f"dependency {task_id} implementation",
            errors,
        )
        if pair is None:
            continue
        if worker_a is None:
            errors.append(f"{task_id} cannot prove Worker A dependency lineage")
            continue
        if not _is_ancestor(root, pair[0], worker_a[0]):
            errors.append(
                f"{task_id} implementation is outside repository.workerADependencyCandidate lineage"
            )
            continue
        if task_id == "P1-012":
            _validate_p1_012(root, dependency, pair[0], errors)
        elif task_id == "P2-004":
            if pair != worker_a:
                errors.append(
                    "P2-004 implementation must equal repository.workerADependencyCandidate"
                )
            _validate_p2_004(root, dependency, pair[0], errors)
        else:
            errors.append(f"unsupported P3 dependency semantic binding: {task_id}")
    return errors


def validate(root: Path) -> list[str]:
    path = root / DOCUMENT_PATH
    if path.is_symlink() or not path.is_file():
        return [f"missing dependency document {DOCUMENT_PATH}"]
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        return [f"dependency document is unreadable: {exc}"]
    if not isinstance(document, dict):
        return ["dependency document must be an object"]
    return validate_document(root, document)


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
    print("Worker D P3 immutable dependency semantic and owner-lineage bindings: PASS")


if __name__ == "__main__":
    main()
