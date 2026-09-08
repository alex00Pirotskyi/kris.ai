#!/usr/bin/env python3
"""Fail-closed source-contract test for the P26 Verification Center roadmap."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any


TASK_ORDER = [f"P26-{index:03d}" for index in range(1, 13)]
TASK_DEPS = {
    "P26-001": [],
    "P26-002": ["P26-001"],
    "P26-003": ["P26-001"],
    "P26-004": ["P26-002"],
    "P26-005": ["P26-002", "P26-004"],
    "P26-006": ["P26-004"],
    "P26-007": ["P26-002"],
    "P26-008": ["P26-003"],
    "P26-009": ["P26-003"],
    "P26-010": ["P26-003"],
    "P26-011": ["P26-003"],
    "P26-012": [
        "P26-005",
        "P26-006",
        "P26-007",
        "P26-008",
        "P26-009",
        "P26-010",
        "P26-011",
    ],
}

RESULT_STATES = [
    "PASS",
    "FAIL",
    "BLOCKED_ENVIRONMENT",
    "BLOCKED_PERMISSION",
    "NOT_RUN",
    "UNKNOWN",
]
MODES = ["ANALYZE_ONLY", "QUICK_CHECK", "DEEP_CHECK", "TEST_AND_REPAIR"]
CRITERIA_TYPES = ["STRUCTURED", "HUMAN", "AGENT_PROMPT"]
UPDATER_STAGES = ["CHECK", "DOWNLOAD", "INSTALL", "RESTART", "VERIFY", "ROLLBACK"]
COVERAGE_FORMATS = ["COBERTURA_XML", "LCOV", "NATIVE_SOURCE_MAP"]
PROFILE_IDS = [
    "contract",
    "deterministic",
    "behavioral-local",
    "web-fixture",
    "native-owner",
    "updater-operation",
    "dogfood-release",
]
CASE_IDS = [
    "p26-roadmap-contract",
    "p26-test-station-contract",
    "p26-deterministic-fixtures",
    "p26-behavioral-local",
    "p26-web-http-fixture",
    "p26-native-owner",
    "p26-updater-operation",
    "p26-kristin-dogfood",
]
GOVERNANCE_CASE_IDS = {"p26-roadmap-contract", "p26-test-station-contract"}
REQUIRED_TASK_SECTIONS = [
    "## Objective",
    "## Scope",
    "## Deliverables",
    "## Acceptance",
    "## Evidence",
    "## Stop policy",
]
REQUIRED_PATHS = [
    "docs/roadmap/P26_VERIFICATION_CENTER.md",
    "docs/roadmap/p26/manifest.v1.json",
    "docs/roadmap/p26/performance_budget.v1.json",
    "docs/roadmap/p26/verification_center_acceptance_contract.v1.json",
    "docs/roadmap/p26/verification_center_test_station.v1.json",
    "docs/roadmap/p26/test_center_registration.v1.json",
    "docs/roadmap/p26/assurance_bindings.v1.json",
    "docs/roadmap/decisions/ADR-P26-001-verification-center-architecture.md",
    "docs/testing/TEST_CENTER_P26_VERIFICATION_CENTER.md",
    "tool/p26_verification_center_roadmap_test.py",
    "tool/p26_verification_center_test_station.py",
] + [f"tasks/planned/{task_id}.md" for task_id in TASK_ORDER]

EXPECTED_BUDGET = {
    "uiAcknowledgementP95Ms": 100,
    "durableRunCreationP95Ms": 250,
    "firstVisibleActivityP95Ms": 500,
    "maximumInvisibleEventGapMs": 3000,
    "cancelAcknowledgementP95Ms": 250,
    "managedProcessTerminationP95Ms": 2000,
    "fixtureProjectDiscoveryP95Ms": 2000,
    "affectedSelectionP95Ms": 500,
    "exactReportLoadP95Ms": 1000,
    "coverageParse10MiBP95Ms": 3000,
    "repairAttemptsMax": 2,
    "silentRetriesMax": 0,
    "logPreviewBytesMax": 65536,
}


class Contract:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.errors: list[str] = []

    def fail(self, message: str) -> None:
        self.errors.append(message)

    def path(self, relative: str) -> Path:
        return self.root / relative

    def read_text(self, relative: str) -> str:
        path = self.path(relative)
        try:
            return path.read_text(encoding="utf-8")
        except OSError as exc:
            self.fail(f"cannot read {relative}: {exc}")
            return ""

    def read_json(self, relative: str) -> dict[str, Any]:
        text = self.read_text(relative)
        if not text:
            return {}
        try:
            value = json.loads(text)
        except json.JSONDecodeError as exc:
            self.fail(f"invalid JSON in {relative}: {exc}")
            return {}
        if not isinstance(value, dict):
            self.fail(f"{relative} must contain a JSON object")
            return {}
        return value

    def expect_equal(self, actual: Any, expected: Any, label: str) -> None:
        if actual != expected:
            self.fail(f"{label}: expected {expected!r}, got {actual!r}")

    def expect_true(self, value: Any, label: str) -> None:
        if value is not True:
            self.fail(f"{label}: expected true, got {value!r}")

    def check_required_paths(self) -> None:
        for relative in REQUIRED_PATHS:
            path = self.path(relative)
            if not path.is_file():
                self.fail(f"missing required file: {relative}")

    def check_manifest(self) -> dict[str, Any]:
        manifest = self.read_json("docs/roadmap/p26/manifest.v1.json")
        self.expect_equal(manifest.get("schemaVersion"), "1.0.0", "manifest schemaVersion")
        self.expect_equal(manifest.get("manifestId"), "p26.verification-center-v1", "manifestId")
        self.expect_equal(manifest.get("status"), "READY", "manifest status")
        self.expect_equal(manifest.get("taskOrder"), TASK_ORDER, "manifest taskOrder")
        self.expect_equal(manifest.get("nextReady"), ["P26-001"], "manifest nextReady")
        self.expect_equal(
            manifest.get("performanceBudget"),
            "docs/roadmap/p26/performance_budget.v1.json",
            "manifest performanceBudget",
        )

        authority = manifest.get("authority")
        if not isinstance(authority, dict):
            self.fail("manifest authority must be an object")
        else:
            self.expect_equal(
                authority.get("decision"),
                "docs/roadmap/decisions/ADR-P26-001-verification-center-architecture.md",
                "manifest authority decision",
            )
            self.expect_equal(
                authority.get("human"),
                "docs/roadmap/P26_VERIFICATION_CENTER.md",
                "manifest authority human",
            )
            self.expect_equal(
                authority.get("testStation"),
                "docs/roadmap/p26/verification_center_test_station.v1.json",
                "manifest authority testStation",
            )
            self.expect_equal(
                authority.get("acceptanceContract"),
                "docs/roadmap/p26/verification_center_acceptance_contract.v1.json",
                "manifest authority acceptanceContract",
            )

        tasks = manifest.get("tasks")
        if not isinstance(tasks, list):
            self.fail("manifest tasks must be an array")
            return manifest
        by_id: dict[str, dict[str, Any]] = {}
        for index, item in enumerate(tasks):
            if not isinstance(item, dict):
                self.fail(f"manifest tasks[{index}] must be an object")
                continue
            task_id = item.get("id")
            if not isinstance(task_id, str):
                self.fail(f"manifest tasks[{index}] has invalid id")
                continue
            if task_id in by_id:
                self.fail(f"manifest contains duplicate task {task_id}")
            by_id[task_id] = item
        self.expect_equal(list(by_id), TASK_ORDER, "manifest task record order")
        for task_id in TASK_ORDER:
            item = by_id.get(task_id)
            if item is None:
                self.fail(f"manifest missing task record {task_id}")
                continue
            self.expect_equal(item.get("dependsOn"), TASK_DEPS[task_id], f"{task_id} dependsOn")
            expected_status = "READY" if task_id == "P26-001" else "BLOCKED"
            self.expect_equal(item.get("status"), expected_status, f"{task_id} status")
            self.expect_equal(item.get("packet"), f"tasks/planned/{task_id}.md", f"{task_id} packet")
            if not isinstance(item.get("title"), str) or not item["title"].strip():
                self.fail(f"{task_id} title must be non-empty")
        self.check_dag(by_id)
        return manifest

    def check_dag(self, tasks: dict[str, dict[str, Any]]) -> None:
        state: dict[str, int] = {}

        def visit(task_id: str, stack: list[str]) -> None:
            marker = state.get(task_id, 0)
            if marker == 1:
                self.fail("task dependency cycle: " + " -> ".join(stack + [task_id]))
                return
            if marker == 2:
                return
            state[task_id] = 1
            for dependency in TASK_DEPS.get(task_id, []):
                if dependency not in tasks:
                    self.fail(f"{task_id} references missing dependency {dependency}")
                else:
                    visit(dependency, stack + [task_id])
            state[task_id] = 2

        for task_id in TASK_ORDER:
            visit(task_id, [])

    def check_task_packets(self) -> None:
        for task_id in TASK_ORDER:
            relative = f"tasks/planned/{task_id}.md"
            text = self.read_text(relative)
            if not text:
                continue
            first_line = text.splitlines()[0] if text.splitlines() else ""
            if not first_line.startswith(f"# {task_id} — "):
                self.fail(f"{relative}: title must start with '# {task_id} — '")
            expected_status = "READY" if task_id == "P26-001" else "BLOCKED"
            if f"**Status:** `{expected_status}`" not in text:
                self.fail(f"{relative}: expected status {expected_status}")
            for section in REQUIRED_TASK_SECTIONS:
                if section not in text:
                    self.fail(f"{relative}: missing section {section}")
            if "docs/roadmap/P26_VERIFICATION_CENTER.md" not in text:
                self.fail(f"{relative}: missing human authority")
            if "docs/roadmap/p26/manifest.v1.json" not in text:
                self.fail(f"{relative}: missing manifest authority")
            depends_match = re.search(r"^\*\*Depends on:\*\* (.+)$", text, re.MULTILINE)
            if not depends_match:
                self.fail(f"{relative}: missing dependency declaration")
                continue
            declared = depends_match.group(1)
            expected = TASK_DEPS[task_id]
            if not expected:
                if declared.strip() != "None":
                    self.fail(f"{relative}: P26-001 must declare no dependencies")
            else:
                found = re.findall(r"`(P26-\d{3})`", declared)
                if found != expected:
                    self.fail(f"{relative}: expected dependencies {expected!r}, got {found!r}")

    def check_acceptance(self) -> None:
        contract = self.read_json("docs/roadmap/p26/verification_center_acceptance_contract.v1.json")
        self.expect_equal(contract.get("schemaVersion"), "1.0.0", "acceptance schemaVersion")
        self.expect_equal(
            contract.get("contractId"),
            "p26.verification-center-acceptance-v1",
            "acceptance contractId",
        )
        self.expect_equal(contract.get("resultStates"), RESULT_STATES, "acceptance resultStates")
        self.expect_equal(contract.get("modes"), MODES, "acceptance modes")
        self.expect_equal(contract.get("criteriaTypes"), CRITERIA_TYPES, "acceptance criteriaTypes")
        self.expect_equal(contract.get("updaterStages"), UPDATER_STAGES, "acceptance updaterStages")

        semantics = contract.get("stateSemantics")
        if not isinstance(semantics, dict):
            self.fail("stateSemantics must be an object")
        else:
            self.expect_equal(semantics.get("passing"), ["PASS"], "stateSemantics passing")
            self.expect_equal(
                semantics.get("nonPassing"),
                RESULT_STATES[1:],
                "stateSemantics nonPassing",
            )
            self.expect_true(semantics.get("coercionForbidden"), "stateSemantics coercionForbidden")

        repair = contract.get("repairPolicy")
        if not isinstance(repair, dict):
            self.fail("repairPolicy must be an object")
        else:
            self.expect_equal(repair.get("maxAttempts"), 2, "repairPolicy maxAttempts")
            self.expect_equal(repair.get("silentRetries"), 0, "repairPolicy silentRetries")
            self.expect_true(repair.get("stopOnPass"), "repairPolicy stopOnPass")
            self.expect_true(
                repair.get("stopOnRepeatedNonProgress"),
                "repairPolicy stopOnRepeatedNonProgress",
            )

        project_config = contract.get("projectConfiguration")
        if not isinstance(project_config, dict):
            self.fail("projectConfiguration must be an object")
        else:
            self.expect_equal(
                project_config.get("directory"),
                ".prowork/verification/",
                "projectConfiguration directory",
            )
            self.expect_equal(
                project_config.get("discoveryRequired"),
                False,
                "projectConfiguration discoveryRequired",
            )
            self.expect_true(project_config.get("idempotent"), "projectConfiguration idempotent")
            self.expect_true(project_config.get("versioned"), "projectConfiguration versioned")

        action = contract.get("actionPolicy")
        if not isinstance(action, dict):
            self.fail("actionPolicy must be an object")
        else:
            self.expect_equal(
                action.get("analyzeOnlyMutation"),
                "FORBIDDEN",
                "actionPolicy analyzeOnlyMutation",
            )
            for key in (
                "destructiveActionsRequireConfirmation",
                "remoteActionsRequireConfirmation",
                "restartRequiresConfirmation",
                "rollbackRequiresConfirmation",
            ):
                self.expect_true(action.get(key), f"actionPolicy {key}")

        coverage = contract.get("coverage")
        if not isinstance(coverage, dict):
            self.fail("coverage must be an object")
        else:
            self.expect_equal(coverage.get("formats"), COVERAGE_FORMATS, "coverage formats")
            self.expect_equal(coverage.get("missingState"), "UNKNOWN", "coverage missingState")
            self.expect_equal(coverage.get("unmappableState"), "UNKNOWN", "coverage unmappableState")

    def check_budget(self) -> None:
        budget = self.read_json("docs/roadmap/p26/performance_budget.v1.json")
        self.expect_equal(budget.get("schemaVersion"), "1.0.0", "budget schemaVersion")
        self.expect_equal(
            budget.get("budgetId"),
            "p26.verification-center-performance-v1",
            "budgetId",
        )
        self.expect_equal(budget.get("metrics"), EXPECTED_BUDGET, "performance metrics")

    def check_station(self) -> None:
        station = self.read_json("docs/roadmap/p26/verification_center_test_station.v1.json")
        self.expect_equal(station.get("schemaVersion"), "1.0.0", "station schemaVersion")
        self.expect_equal(
            station.get("suiteId"),
            "p26.verification-center-test-station-v1",
            "station suiteId",
        )

        profiles = station.get("profiles")
        if not isinstance(profiles, list):
            self.fail("station profiles must be an array")
            profiles = []
        profile_ids = [item.get("profileId") for item in profiles if isinstance(item, dict)]
        self.expect_equal(profile_ids, PROFILE_IDS, "station profile IDs")

        cases = station.get("cases")
        if not isinstance(cases, list):
            self.fail("station cases must be an array")
            cases = []
        case_ids = [item.get("caseId") for item in cases if isinstance(item, dict)]
        self.expect_equal(case_ids, CASE_IDS, "station case IDs")
        seen_tests: set[str] = set()
        eligible: set[str] = set()
        for item in cases:
            if not isinstance(item, dict):
                self.fail("station case entry must be an object")
                continue
            case_id = item.get("caseId")
            test_id = item.get("testId")
            if not isinstance(test_id, str) or not test_id.startswith("tc.p26."):
                self.fail(f"station case {case_id!r} has invalid testId")
            elif test_id in seen_tests:
                self.fail(f"station contains duplicate testId {test_id}")
            else:
                seen_tests.add(test_id)
            command = item.get("command")
            if not isinstance(command, list) or not command or not all(isinstance(v, str) and v for v in command):
                self.fail(f"station case {case_id!r} must use non-empty argv")
            if item.get("completionEligible") is True:
                eligible.add(str(case_id))
            if case_id not in GOVERNANCE_CASE_IDS and item.get("completionEligible") is not False:
                self.fail(f"future station case {case_id!r} must be completion-ineligible")
            if case_id not in GOVERNANCE_CASE_IDS and not isinstance(item.get("implementationPath"), str):
                self.fail(f"future station case {case_id!r} must declare implementationPath")
        self.expect_equal(eligible, GOVERNANCE_CASE_IDS, "station completion-eligible cases")

        by_profile = {item.get("profileId"): item for item in profiles if isinstance(item, dict)}
        contract_profile = by_profile.get("contract")
        if not isinstance(contract_profile, dict):
            self.fail("station missing contract profile")
        else:
            self.expect_equal(
                contract_profile.get("caseIds"),
                ["p26-roadmap-contract", "p26-test-station-contract"],
                "contract profile caseIds",
            )

    def check_registration(self) -> None:
        registration = self.read_json("docs/roadmap/p26/test_center_registration.v1.json")
        self.expect_equal(registration.get("schemaVersion"), "1.0.0", "registration schemaVersion")
        module = registration.get("module")
        if not isinstance(module, dict):
            self.fail("registration module must be an object")
        else:
            self.expect_equal(module.get("moduleId"), "tm.p26.verification-center", "registration moduleId")
            self.expect_equal(
                module.get("assuranceClasses"),
                ["source_contract", "behavioral", "platform", "release"],
                "registration assuranceClasses",
            )

        tests = registration.get("testCases")
        if not isinstance(tests, list):
            self.fail("registration testCases must be an array")
            tests = []
        test_ids = [item.get("testId") for item in tests if isinstance(item, dict)]
        self.expect_equal(
            test_ids,
            ["tc.p26.roadmap-contract", "tc.p26.test-station-contract"],
            "registered governance test IDs",
        )
        for item in tests:
            if not isinstance(item, dict):
                continue
            self.expect_equal(item.get("moduleId"), "tm.p26.verification-center", "registered moduleId")
            self.expect_equal(item.get("assuranceClass"), "source_contract", "registered assuranceClass")
            self.expect_true(item.get("mandatory"), f"{item.get('testId')} mandatory")
            self.expect_equal(item.get("roadmapTaskIds"), ["P26-001"], f"{item.get('testId')} roadmapTaskIds")

        mapping = registration.get("affectedTestMapping")
        if not isinstance(mapping, dict):
            self.fail("registration affectedTestMapping must be an object")
        else:
            self.expect_equal(
                mapping.get("testIds"),
                ["tc.p26.roadmap-contract", "tc.p26.test-station-contract"],
                "affected-test mapping IDs",
            )
            patterns = mapping.get("pathPatterns")
            if not isinstance(patterns, list) or "docs/roadmap/p26/**" not in patterns:
                self.fail("affected-test mapping must include docs/roadmap/p26/**")

        bindings = self.read_json("docs/roadmap/p26/assurance_bindings.v1.json")
        self.expect_equal(bindings.get("schemaVersion"), "1.0.0", "assurance bindings schemaVersion")
        raw_bindings = bindings.get("testBindings")
        if not isinstance(raw_bindings, list):
            self.fail("assurance testBindings must be an array")
            raw_bindings = []
        pairs = {
            (item.get("testId"), item.get("levelId"))
            for item in raw_bindings
            if isinstance(item, dict)
        }
        expected_pairs = {
            ("tc.p26.roadmap-contract", "architecture_lint"),
            ("tc.p26.test-station-contract", "architecture_lint"),
            ("tc.p26.deterministic-fixtures", "unit"),
            ("tc.p26.behavioral-local", "integration"),
            ("tc.p26.web-http-fixture", "integration"),
            ("tc.p26.native-owner", "platform"),
            ("tc.p26.updater-operation", "platform"),
            ("tc.p26.kristin-dogfood", "release"),
        }
        self.expect_equal(pairs, expected_pairs, "assurance binding pairs")

    def check_human_contract(self) -> None:
        human = self.read_text("docs/roadmap/P26_VERIFICATION_CENTER.md")
        adr = self.read_text("docs/roadmap/decisions/ADR-P26-001-verification-center-architecture.md")
        test_doc = self.read_text("docs/testing/TEST_CENTER_P26_VERIFICATION_CENTER.md")
        for token in RESULT_STATES + MODES + CRITERIA_TYPES:
            if token not in human:
                self.fail(f"human roadmap missing required token {token}")
        for phrase in (
            ".prowork/verification/",
            "two repair attempts",
            "CHECK → DOWNLOAD → INSTALL → RESTART → VERIFY → ROLLBACK",
            "Cobertura XML",
            "LCOV",
            "Kristin dogfood",
            "release-blocking",
        ):
            if phrase not in human:
                self.fail(f"human roadmap missing required phrase {phrase!r}")
        for phrase in ("**Status:** `ACCEPTED`", "project-neutral", "only PASS passes"):
            if phrase not in adr:
                self.fail(f"ADR missing required phrase {phrase!r}")
        for test_id in ("tc.p26.roadmap-contract", "tc.p26.test-station-contract"):
            if test_id not in test_doc:
                self.fail(f"Test Center documentation missing {test_id}")

    def run(self) -> list[str]:
        self.check_required_paths()
        self.check_manifest()
        self.check_task_packets()
        self.check_acceptance()
        self.check_budget()
        self.check_station()
        self.check_registration()
        self.check_human_contract()
        return self.errors


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=".", help="Repository root")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable output")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    root = Path(args.project).expanduser().resolve()
    contract = Contract(root)
    errors = contract.run()
    payload = {
        "contract": "p26.verification-center-governance-v1",
        "project": str(root),
        "status": "FAIL" if errors else "PASS",
        "errors": errors,
    }
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    elif errors:
        print("P26_ROADMAP_FAIL")
        for error in errors:
            print(f"- {error}")
    else:
        print("P26_ROADMAP_PASS")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
