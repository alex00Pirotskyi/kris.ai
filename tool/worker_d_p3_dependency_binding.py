#!/usr/bin/env python3
"""Verify P3 dependency Git identities and semantic evidence at immutable commits."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path
from typing import Any

DOCUMENT_PATH = "release/evidence/P3-001/dependency-status.json"
GIT_OBJECT_RE = re.compile(r"^[0-9a-f]{40}$")
P1_REVIEW_CANDIDATES = (
    "release/evidence/P1-012/INDEPENDENT_REVIEW.md",
    "release/evidence/P1-012/independent-review.json",
)
P1_REQUIRED_EVIDENCE = frozenset(
    {
        "tasks/completed/P1-012.md",
        "release/evidence/P1-012/manifest.json",
        "release/evidence/P1-012/test-results.json",
        "release/evidence/P1-012/OWNER_APPROVAL.md",
        "config/local_ipc.v1.json",
        "docs/architecture/LOCAL_AUTHENTICATED_IPC_V1.md",
        "tool/local_authenticated_ipc.py",
        "lib/product/local_authenticated_ipc_v1.dart",
        "test/product/local_authenticated_ipc_v1_test.dart",
    }
)
P2_REQUIRED_EVIDENCE = frozenset(
    {
        "release/evidence/P2-004/IMPLEMENTATION.md",
        "release/evidence/P2-004/manifest.json",
        "release/evidence/P2-004/technology-spike.json",
        "release/evidence/P2-004/test-results.json",
    }
)
P1_EXPECTED_CLAIMS = {
    "mutual_authentication": "Mutually authenticated loopback request",
    "unrelated_local_process_rejected": "Unrelated local process rejected",
    "replay_rejected": "Replay rejected",
    "tri_platform_transport_contract": "Tri-platform transport contract",
}
MISSING_MEASUREMENT = "MISSING_MEASUREMENT"


def _require_object(
    value: object, label: str, errors: list[str]
) -> dict[str, Any] | None:
    if not isinstance(value, dict):
        errors.append(f"{label} must be an object")
        return None
    return value


def _binding(
    record: object,
    label: str,
    errors: list[str],
    *,
    commit_key: str = "commit",
    tree_key: str = "tree",
) -> tuple[str, str, str] | None:
    obj = _require_object(record, label, errors)
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
    return label, commit, tree


def collect_bindings(
    document: dict[str, Any], errors: list[str]
) -> list[tuple[str, str, str]]:
    bindings: list[tuple[str, str, str]] = []
    dependencies = document.get("dependencies")
    if not isinstance(dependencies, list):
        errors.append("dependencies must be an array")
    else:
        seen: set[str] = set()
        for index, dependency in enumerate(dependencies):
            label = f"dependencies[{index}]"
            obj = _require_object(dependency, label, errors)
            if obj is None:
                continue
            task_id = obj.get("taskId")
            if not isinstance(task_id, str) or not task_id:
                errors.append(f"{label}.taskId must be non-empty")
                continue
            if task_id in seen:
                errors.append(f"duplicate dependency taskId {task_id}")
                continue
            seen.add(task_id)
            item = _binding(
                obj.get("implementation"),
                f"dependency {task_id} implementation",
                errors,
            )
            if item is not None:
                bindings.append(item)
    repository = _require_object(document.get("repository"), "repository", errors)
    if repository is not None:
        for key in (
            "protectedMain",
            "workerADependencyCandidate",
            "workerBBranchCreationBase",
            "workerBSynchronizedBase",
            "workerC",
            "workerJ",
        ):
            item = _binding(repository.get(key), f"repository.{key}", errors)
            if item is not None:
                bindings.append(item)
        item = _binding(
            repository.get("workerD"),
            "repository.workerD",
            errors,
            commit_key="synchronizationCommit",
            tree_key="synchronizationTree",
        )
        if item is not None:
            bindings.append(item)
    return bindings


def _git(root: Path, *args: str) -> str:
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


def _git_exists(root: Path, commit: str, rel: str) -> bool:
    return (
        subprocess.run(
            ["git", "cat-file", "-e", f"{commit}:{rel}"],
            cwd=root,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode
        == 0
    )


def _json_at(
    root: Path,
    commit: str,
    rel: str,
    label: str,
    errors: list[str],
) -> dict[str, Any] | None:
    try:
        payload = _git_bytes(root, commit, rel)
    except (OSError, subprocess.CalledProcessError):
        errors.append(f"{label} missing immutable evidence {rel}")
        return None
    try:
        value = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        errors.append(f"{label} immutable evidence is invalid JSON {rel}: {exc}")
        return None
    if not isinstance(value, dict):
        errors.append(f"{label} immutable evidence must be an object {rel}")
        return None
    return value


def _text_at(
    root: Path,
    commit: str,
    rel: str,
    label: str,
    errors: list[str],
) -> str | None:
    try:
        return _git_bytes(root, commit, rel).decode("utf-8")
    except (OSError, subprocess.CalledProcessError, UnicodeDecodeError):
        errors.append(f"{label} missing or non-UTF8 immutable evidence {rel}")
        return None


def _exact_evidence_paths(
    dependency: dict[str, Any],
    expected: frozenset[str],
    label: str,
    errors: list[str],
) -> None:
    paths = dependency.get("evidencePaths")
    if not isinstance(paths, list) or not all(isinstance(item, str) for item in paths):
        errors.append(f"{label}.evidencePaths must be a string array")
        return
    observed = set(paths)
    if observed != expected or len(paths) != len(expected):
        errors.append(
            f"{label}.evidencePaths do not exactly match immutable dependency evidence"
        )


def _validate_p1_012(
    root: Path,
    dependency: dict[str, Any],
    commit: str,
    errors: list[str],
) -> None:
    label = "dependency P1-012"
    _exact_evidence_paths(dependency, P1_REQUIRED_EVIDENCE, label, errors)
    for rel in P1_REQUIRED_EVIDENCE:
        if not _git_exists(root, commit, rel):
            errors.append(
                f"{label} declared evidence is absent at implementation commit: {rel}"
            )

    task = _text_at(root, commit, "tasks/completed/P1-012.md", label, errors)
    manifest = _json_at(
        root, commit, "release/evidence/P1-012/manifest.json", label, errors
    )
    results = _json_at(
        root, commit, "release/evidence/P1-012/test-results.json", label, errors
    )
    approval = _text_at(
        root, commit, "release/evidence/P1-012/OWNER_APPROVAL.md", label, errors
    )

    if dependency.get("authoritativeStatus") != "DONE":
        errors.append(f"{label}.authoritativeStatus must derive as DONE")
    if dependency.get("decision") != "MISSING_INDEPENDENT_REVIEW":
        errors.append(f"{label}.decision must derive as MISSING_INDEPENDENT_REVIEW")
    review = dependency.get("review")
    if review != {"independentReview": "MISSING", "ownerApproval": "PASS"}:
        errors.append(f"{label}.review does not match immutable review evidence")

    if task is not None and "\n## Status\n\nDONE\n" not in task:
        errors.append(f"{label} completed task packet does not record DONE")
    if manifest is not None:
        if manifest.get("taskId") != "P1-012" or manifest.get("status") != "passed":
            errors.append(f"{label} manifest does not record P1-012 passed")
        claims = manifest.get("claims")
        if (
            not isinstance(claims, dict)
            or set(claims)
            != {
                "mutualAuthentication",
                "peerIdentity",
                "replayProtection",
                "unauthorizedLocalProcessRejected",
            }
            or any(value is not True for value in claims.values())
        ):
            errors.append(
                f"{label} manifest security claims are not the immutable accepted set"
            )
        if manifest.get("testResults") != "release/evidence/P1-012/test-results.json":
            errors.append(f"{label} manifest test-results binding drifted")
    if results is not None:
        tests = dependency.get("tests")
        if not isinstance(tests, dict):
            errors.append(f"{label}.tests must be an object")
        else:
            for key in ("caseCount", "passedCount", "failedCount"):
                if tests.get(key) != results.get(key):
                    errors.append(
                        f"{label}.tests.{key} does not match immutable results"
                    )
            declared_claims = tests.get("claims")
            if (
                not isinstance(declared_claims, list)
                or set(declared_claims) != set(P1_EXPECTED_CLAIMS)
                or len(declared_claims) != len(P1_EXPECTED_CLAIMS)
            ):
                errors.append(
                    f"{label}.tests.claims do not match immutable result coverage"
                )
            result_names = {
                item.get("name")
                for item in results.get("results", [])
                if isinstance(item, dict) and item.get("passed") is True
            }
            missing = sorted(set(P1_EXPECTED_CLAIMS.values()) - result_names)
            if missing:
                errors.append(
                    f"{label} immutable test results lack required passing claims: {missing}"
                )
        if results.get("taskId") != "P1-012" or results.get("passed") is not True:
            errors.append(f"{label} immutable test results are not a P1-012 PASS")
    if approval is not None and "Decision: approve " not in approval:
        errors.append(f"{label} immutable owner approval does not approve the task")
    for rel in P1_REVIEW_CANDIDATES:
        if _git_exists(root, commit, rel):
            errors.append(
                f"{label} independent review is present at immutable commit "
                f"but row says MISSING: {rel}"
            )


def _validate_p2_004(
    root: Path,
    dependency: dict[str, Any],
    commit: str,
    errors: list[str],
) -> None:
    label = "dependency P2-004"
    _exact_evidence_paths(dependency, P2_REQUIRED_EVIDENCE, label, errors)
    for rel in P2_REQUIRED_EVIDENCE:
        if not _git_exists(root, commit, rel):
            errors.append(
                f"{label} declared evidence is absent at implementation commit: {rel}"
            )

    manifest = _json_at(
        root, commit, "release/evidence/P2-004/manifest.json", label, errors
    )
    spike = _json_at(
        root, commit, "release/evidence/P2-004/technology-spike.json", label, errors
    )
    results = _json_at(
        root, commit, "release/evidence/P2-004/test-results.json", label, errors
    )

    if dependency.get("authoritativeStatus") != "BLOCKED":
        errors.append(f"{label}.authoritativeStatus must derive as BLOCKED")
    if dependency.get("decision") != MISSING_MEASUREMENT:
        errors.append(f"{label}.decision must derive as {MISSING_MEASUREMENT}")
    if dependency.get("review") != {
        "independentReview": "MISSING",
        "ownerApproval": "MISSING",
    }:
        errors.append(f"{label}.review does not match immutable pending review evidence")
    measurements = dependency.get("measurements")
    expected_measurements = {
        "memory": MISSING_MEASUREMENT,
        "packaging": MISSING_MEASUREMENT,
        "platformReceipts": {},
        "reliability": MISSING_MEASUREMENT,
        "startup": MISSING_MEASUREMENT,
    }
    if measurements != expected_measurements:
        errors.append(
            f"{label}.measurements do not match immutable source-only evidence"
        )

    if manifest is not None:
        expected_manifest = (
            manifest.get("taskId") == "P2-004"
            and manifest.get("status") == "source_only"
            and manifest.get("localResult") == "source_only"
            and manifest.get("ownerApproval") == {"status": "pending"}
            and manifest.get("independentReview") == {"status": "pending"}
            and manifest.get("platformReceipts") == {}
            and manifest.get("completedTaskPacket") is None
            and manifest.get("sourceOnlyIsNotBehavioralProof") is True
        )
        if not expected_manifest:
            errors.append(f"{label} manifest no longer proves source-only blocked state")
    if spike is not None:
        if (
            spike.get("completionEligible") is not False
            or spike.get("sourceOnly") is not True
            or spike.get("decision")
            != {"status": "blocked_external_tri_platform_measurement_required"}
        ):
            errors.append(
                f"{label} technology spike no longer proves missing measurement"
            )
    if results is not None:
        tests = results.get("tests")
        measured = (
            [
                item
                for item in tests
                if isinstance(item, dict)
                and item.get("name") == "measured automation-host comparison"
            ]
            if isinstance(tests, list)
            else []
        )
        if (
            results.get("taskId") != "P2-004"
            or results.get("status") != "source_only"
            or len(measured) != 1
            or measured[0].get("status") != "source_only"
            or measured[0].get("detail")
            != "blocked_external_tri_platform_measurement_required"
        ):
            errors.append(
                f"{label} immutable tests do not prove source-only measurement block"
            )


def _validate_dependency_semantics(
    root: Path,
    document: dict[str, Any],
    errors: list[str],
) -> None:
    dependencies = document.get("dependencies")
    if not isinstance(dependencies, list):
        return
    for dependency in dependencies:
        if not isinstance(dependency, dict):
            continue
        task_id = dependency.get("taskId")
        implementation = dependency.get("implementation")
        if not isinstance(implementation, dict):
            continue
        commit = implementation.get("commit")
        if not isinstance(commit, str) or GIT_OBJECT_RE.fullmatch(commit) is None:
            continue
        if task_id == "P1-012":
            _validate_p1_012(root, dependency, commit, errors)
        elif task_id == "P2-004":
            _validate_p2_004(root, dependency, commit, errors)


def validate_document(root: Path, document: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    bindings = collect_bindings(document, errors)
    if not bindings:
        errors.append("dependency document contains no Git bindings")
        return errors
    for label, commit, declared_tree in bindings:
        try:
            resolved_commit = _git(root, "rev-parse", "--verify", f"{commit}^{{commit}}")
            actual_tree = _git(root, "rev-parse", "--verify", f"{commit}^{{tree}}")
        except (OSError, subprocess.CalledProcessError):
            errors.append(f"{label} commit does not resolve in repository: {commit}")
            continue
        if resolved_commit != commit:
            errors.append(f"{label} does not resolve to the declared commit {commit}")
        if actual_tree != declared_tree:
            errors.append(
                f"{label} tree mismatch: declared {declared_tree}, actual {actual_tree}"
            )
    _validate_dependency_semantics(root, document, errors)
    return errors


def validate(root: Path) -> list[str]:
    path = root / DOCUMENT_PATH
    if path.is_symlink() or not path.is_file():
        return [f"missing dependency document {DOCUMENT_PATH}"]
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        return [f"dependency document is unreadable: {error}"]
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
    print("Worker D P3 dependency Git and semantic bindings: PASS")


if __name__ == "__main__":
    main()
