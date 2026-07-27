#!/usr/bin/env python3
"""Offline behavioral contract gate for P0-006 repository governance."""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import re
import sys
from typing import Any

FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
REQUIRED_CHECKS = ("validate-ubuntu", "validate-windows", "validate-macos")


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str


def read(root: Path, relative: str) -> str:
    return (root / relative).read_text(encoding="utf-8")


def load_json(root: Path, relative: str) -> dict[str, Any]:
    value = json.loads(read(root, relative))
    if not isinstance(value, dict):
        raise AssertionError(f"{relative} root must be an object")
    return value


def case(name: str, action) -> Result:
    try:
        detail = action()
        return Result(name, True, str(detail))
    except BaseException as error:
        return Result(name, False, f"{type(error).__name__}: {error}")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def check_config(root: Path) -> str:
    config = load_json(root, "config/repository_governance.json")
    require(config.get("schemaVersion") == "1.0.0", "unexpected schemaVersion")
    require(config.get("milestone") == "P0-006", "milestone must be P0-006")
    ruleset = config.get("ruleset")
    require(isinstance(ruleset, dict), "ruleset must be an object")
    assert isinstance(ruleset, dict)
    require(ruleset.get("enforcement") == "active", "ruleset must be active")
    require(ruleset.get("include") == ["~DEFAULT_BRANCH"], "ruleset must target default branch")
    require(ruleset.get("bypassActors") == [], "ruleset must define no bypass actors")
    require(ruleset.get("requirePullRequest") is True, "pull request must be required")
    require(ruleset.get("requiredApprovingReviewCount") == 0, "solo mode must not require an impossible second-person approval")
    require(ruleset.get("dismissStaleReviewsOnPush") is True, "stale approvals must be dismissed")
    require(ruleset.get("requireLastPushApproval") is False, "solo mode cannot require last-push approval")
    require(ruleset.get("requiredReviewThreadResolution") is True, "review threads must resolve")
    require(ruleset.get("strictRequiredStatusChecks") is True, "strict status checks must be enabled")
    checks = ruleset.get("requiredStatusChecks")
    require(checks == list(REQUIRED_CHECKS), f"required checks must be {REQUIRED_CHECKS!r}")
    require(ruleset.get("blockDeletions") is True, "deletion must be blocked")
    require(ruleset.get("blockForcePushes") is True, "force pushes must be blocked")
    require(ruleset.get("requireLinearHistory") is True, "linear history must be required")
    require(set(ruleset.get("allowedMergeMethods") or []) == {"squash", "rebase"}, "merge methods must be squash/rebase")
    return "ruleset desired state is explicit and fail-closed"


def check_codeowners(root: Path) -> str:
    text = read(root, ".github/CODEOWNERS")
    required = (
        "* @alex00Pirotskyi",
        "/.github/",
        "/tool/",
        "/schemas/",
        "/migrations/",
        "/lib/product/",
        "/release/",
        "/docs/roadmap/",
        "/SECURITY.md",
        "/RELEASE.json",
        "/SOURCE_MANIFEST.sha256",
    )
    missing = [item for item in required if item not in text]
    require(not missing, f"missing CODEOWNERS coverage: {missing}")
    require("solo-maintainer" in text.lower(), "solo-maintainer prerequisite must be documented")
    return f"covered markers={len(required)}"


def check_pr_template(root: Path) -> str:
    text = read(root, ".github/pull_request_template.md")
    required = (
        "Roadmap work packet",
        "Platform impact",
        "Authority, privacy, and external-effect impact",
        "Behavioral tests",
        "Negative/error-path tests",
        "Windows lane",
        "macOS lane",
        "Linux lane",
        "Source manifest",
        "Solo-maintainer review",
        "Security reviewer required",
    )
    missing = [item for item in required if item not in text]
    require(not missing, f"PR template missing: {missing}")
    return "PR template requires task, platform, authority, evidence, and review data"


def check_issue_templates(root: Path) -> str:
    config = read(root, ".github/ISSUE_TEMPLATE/config.yml")
    engineering = read(root, ".github/ISSUE_TEMPLATE/engineering_task.yml")
    bug = read(root, ".github/ISSUE_TEMPLATE/bug_report.yml")
    require("security/advisories/new" in config, "private advisory link missing")
    require("roadmap task id" in engineering.lower(), "engineering task ID field missing")
    require("Windows, macOS, and Linux" in engineering, "platform parity field missing")
    require("removed credentials" in bug, "bug secret-redaction acknowledgment missing")
    return "private security and bounded engineering intake are configured"


def check_ci(root: Path) -> str:
    ci = read(root, ".github/workflows/ci.yml")
    for name in REQUIRED_CHECKS:
        require(name in ci, f"stable CI check name missing: {name}")
    require("python tool/repository_governance_test.py" in ci, "governance test is not in CI")
    require("python tool/policy_support_test.py" in ci, "P0-005 policy gate is not in CI")
    format_marker = "tool/dart_format_scope.py --check" if "tool/dart_format_scope.py --check" in ci else "dart format"
    require("flutter pub get" in ci and ci.index("flutter pub get") < ci.index(format_marker), "dependency resolution must precede format")
    require("tool/dart_format_scope.py --check" in ci or "--set-exit-if-changed" in ci, "CI format gate must be non-mutating")
    return "CI exposes stable tri-OS check names and governance/policy gates"


def check_verify(root: Path) -> str:
    verify = read(root, "tool/verify.sh")
    required = (
        "tool/v1_trust_disablement_test.py",
        "tool/p0_003_repair_test.py",
        "tool/policy_support_test.py",
        "tool/repository_governance_test.py",
        "flutter pub get",
        "flutter analyze --no-pub --fatal-warnings --fatal-infos",
        "flutter test --no-pub --concurrency=1",
    )
    missing = [item for item in required if item not in verify]
    require(not missing, f"verify.sh missing merged gates: {missing}")
    format_marker = (
        "tool/dart_format_scope.py --check"
        if "tool/dart_format_scope.py --check" in verify
        else "dart format --output=none --set-exit-if-changed"
    )
    require(format_marker in verify, "verify.sh missing a non-mutating Dart format gate")
    require(verify.index("flutter pub get") < verify.index(format_marker), "verify dependency order is wrong")
    return "verification preserves P0-002/P0-003/P0-005/P0-006 gates"


def check_p0_003_evidence(root: Path) -> str:
    payload = load_json(root, "release/evidence/P0-003/ci_matrix.json")
    require(payload.get("milestone") == "P0-003", "matrix milestone mismatch")
    require(payload.get("status") == "passed", "P0-003 matrix status is not passed")
    commit = str(payload.get("commit") or "")
    require(FULL_SHA.fullmatch(commit) is not None, "matrix commit must be a full SHA")
    require(str(payload.get("workflowRunUrl") or "").startswith("https://"), "workflow URL missing")
    lanes = payload.get("lanes")
    require(isinstance(lanes, dict), "lanes must be an object")
    assert isinstance(lanes, dict)
    for lane, check_name in zip(("ubuntu", "windows", "macos"), REQUIRED_CHECKS):
        item = lanes.get(lane)
        require(isinstance(item, dict), f"{lane} lane missing")
        assert isinstance(item, dict)
        require(item.get("status") == "passed", f"{lane} status is not passed")
        require(item.get("nativeBuild") == "passed", f"{lane} native build is not passed")
        require(item.get("checkName") == check_name, f"{lane} checkName must be {check_name}")
        require(str(item.get("jobUrl") or "").startswith("https://"), f"{lane} job URL missing")
        require(bool(item.get("environmentEvidence")), f"{lane} environment evidence missing")
    return f"same-commit tri-OS evidence commit={commit}"


def check_remote_client(root: Path) -> str:
    source = read(root, "tool/github_governance.py")
    required = (
        "2026-03-10",
        "--confirm-solo-maintainer",
        "GITHUB_TOKEN",
        "Authorization",
        "rulesets",
        "github_governance_receipt.json",
        "token is read from",
    )
    missing = [item for item in required if item not in source]
    require(not missing, f"GitHub client missing markers: {missing}")
    forbidden = ("print(token", "logger.debug(token", "password=", "ghp_", "github_pat_")
    found = [item for item in forbidden if item in source]
    require(not found, f"possible credential exposure in client: {found}")
    return "remote applicator is explicit, versioned, and avoids token persistence"


def resolve_p0_006_task(root: Path) -> tuple[str, str]:
    candidates = (
        "tasks/active/P0-006.md",
        "tasks/completed/P0-006.md",
        "tasks/blocked/P0-006.md",
    )
    present = [relative for relative in candidates if (root / relative).is_file()]
    require(len(present) == 1, f"expected exactly one P0-006 task packet, found: {present}")
    relative = present[0]
    return relative, read(root, relative)


def check_task_docs(root: Path) -> str:
    task_path, task = resolve_p0_006_task(root)
    policy = read(root, "docs/roadmap/REPOSITORY_GOVERNANCE.md")
    plan = read(root, "release/evidence/P0-006/IMPLEMENTATION_PLAN.md")
    require("same-commit" in task.lower(), "task lacks P0-003 dependency condition")
    require("does not satisfy P0-006" in plan, "plan must reject source-only completion")
    require("test pull request" in policy.lower(), "blocked/allowed merge demonstration missing")
    if task_path == "tasks/active/P0-006.md":
        require("REVIEW" in task, "active task must remain REVIEW until remote evidence")
        state = "review"
    elif task_path == "tasks/completed/P0-006.md":
        require("DONE" in task, "completed task packet must be DONE")
        require(
            re.search(r"release/evidence/P0/P0_EXIT_GATE_V[0-9]+[.]json", task) is not None,
            "completed task packet lacks P0 exit evidence",
        )
        for relative in (
            "release/evidence/P0-006/github_governance_receipt.json",
            "release/evidence/P0-006/github_governance_verification.json",
        ):
            payload = load_json(root, relative)
            require(payload.get("status") == "passed", f"governance closure evidence is not passed: {relative}")
        state = "done"
    else:
        raise AssertionError(f"P0-006 cannot close from blocked packet: {task_path}")
    return f"task packet={task_path} state={state}; remote enforcement remains evidenced"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--json-output")
    args = parser.parse_args()
    root = Path(args.project).expanduser().resolve()

    required_files = (
        "config/repository_governance.json",
        ".github/CODEOWNERS",
        ".github/pull_request_template.md",
        ".github/ISSUE_TEMPLATE/config.yml",
        ".github/ISSUE_TEMPLATE/engineering_task.yml",
        ".github/ISSUE_TEMPLATE/bug_report.yml",
        "docs/roadmap/REPOSITORY_GOVERNANCE.md",
        "release/evidence/P0-006/IMPLEMENTATION_PLAN.md",
        "tool/github_governance.py",
        "tool/github_governance_client_test.py",
        "tool/verify.sh",
        ".github/workflows/ci.yml",
        "release/evidence/P0-003/ci_matrix.json",
    )
    results: list[Result] = []
    missing = [item for item in required_files if not (root / item).is_file()]
    task_candidates = (
        "tasks/active/P0-006.md",
        "tasks/completed/P0-006.md",
        "tasks/blocked/P0-006.md",
    )
    task_present = [item for item in task_candidates if (root / item).is_file()]
    if len(task_present) != 1:
        missing.append(f"P0-006 task packet lifecycle ambiguity: {task_present}")
    results.append(Result("Required governance files", not missing, "all present" if not missing else f"missing: {missing}"))
    if not missing:
        results.extend(
            (
                case("Governance desired-state schema", lambda: check_config(root)),
                case("CODEOWNERS coverage", lambda: check_codeowners(root)),
                case("Pull-request template", lambda: check_pr_template(root)),
                case("Issue and security intake", lambda: check_issue_templates(root)),
                case("Stable CI and local gates", lambda: check_ci(root)),
                case("Merged verification ladder", lambda: check_verify(root)),
                case("P0-003 dependency evidence", lambda: check_p0_003_evidence(root)),
                case("Guarded GitHub client", lambda: check_remote_client(root)),
                case("Task and operator truth", lambda: check_task_docs(root)),
            )
        )
    passed = sum(1 for item in results if item.passed)
    payload = {
        "schemaVersion": "1.0.0",
        "milestone": "P0-006",
        "caseCount": len(results),
        "passedCount": passed,
        "failedCount": len(results) - passed,
        "passed": passed == len(results),
        "results": [asdict(item) for item in results],
    }
    rendered = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if args.json_output:
        output = Path(args.json_output)
        if not output.is_absolute():
            output = root / output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered, encoding="utf-8")
    sys.stdout.write(rendered)
    return 0 if payload["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
