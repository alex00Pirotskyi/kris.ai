#!/usr/bin/env python3
"""Executable Prompt Studio 2 and deterministic plan-compiler release gate."""
from __future__ import annotations

import argparse
import copy
import json
import subprocess
import sys
import tempfile
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Callable

import plan_compiler

ROOT = Path(__file__).resolve().parents[1]
FIX = ROOT / "test" / "product" / "fixtures" / "prompt_studio_v2"


@dataclass
class Result:
    name: str
    status: str
    detail: str


class Gate:
    def __init__(self) -> None:
        self.results: list[Result] = []

    def check(self, name: str, callback: Callable[[], str]) -> None:
        try:
            detail = callback()
        except Exception as exc:  # noqa: BLE001 - release gate must capture all failures
            self.results.append(Result(name, "failed", f"{type(exc).__name__}: {exc}"))
        else:
            self.results.append(Result(name, "passed", detail))

    @property
    def passed(self) -> bool:
        return all(item.status == "passed" for item in self.results)


def load(name: str) -> dict:
    return plan_compiler.read_json(FIX / name)


def assert_true(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def issue_codes(report: dict) -> set[str]:
    return {str(item.get("code")) for item in report.get("issues", [])}


def compile_fixture(count: int, *, plan: dict | None = None, spec: dict | None = None, policy: dict | None = None) -> dict:
    return plan_compiler.compile_plan(
        spec or load("specification.json"),
        plan or load(f"plan_{count:03d}.json"),
        policy=policy or load("policy.local_only.json"),
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json-output")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    gate = Gate()
    contracts = plan_compiler.load_contracts()

    def schemas_valid() -> str:
        failures: list[str] = []
        for name, schema in contracts.items():
            failures.extend(
                plan_compiler.validate_schema_contract(
                    schema,
                    document_name=name,
                )
            )
        assert_true(not failures, "; ".join(failures[:20]))
        return "all versioned JSON Schemas pass the in-repository structural validator"

    gate.check("Versioned Prompt Studio 2 schemas", schemas_valid)

    def fixtures_fresh() -> str:
        proc = subprocess.run(
            [sys.executable, str(ROOT / "tool" / "generate_prompt_studio_fixtures.py"), "--check"],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        assert_true(proc.returncode == 0, proc.stdout)
        return "generated 1/10/50/100-task fixtures match the checked-in corpus"

    gate.check("Generated fixture freshness", fixtures_fresh)

    def capability_tools_known() -> str:
        known = plan_compiler.tool_names(contracts["tools"])
        capabilities, _, _ = plan_compiler.capability_catalog(contracts["capabilities"])
        missing = sorted({tool for capability in capabilities.values() for tool in capability.tools} - known)
        assert_true(not missing, f"capability catalog references unknown tools: {missing}")
        return f"{len(capabilities)} capabilities map only to the {len(known)} governed tools"

    gate.check("Capability catalog tool coverage", capability_tools_known)

    spec = load("specification.json")
    gate.check(
        "Structured product specification schema",
        lambda: (
            "product specification validates with requirements, data policy, artifacts, criteria, tests, deployment boundary, and risk"
            if not plan_compiler.validate_document(spec, contracts["specification"], document_name="specification")
            else (_ for _ in ()).throw(AssertionError("specification fixture invalid"))
        ),
    )

    fixture_reports: dict[int, dict] = {}
    for count in (1, 10, 50, 100):
        def fixture_case(count: int = count) -> str:
            report = compile_fixture(count)
            fixture_reports[count] = report
            assert_true(report["executable"], f"fixture {count} was blocked: {report['issues'][:5]}")
            assert_true(report["simulation"]["readyTaskCount"] == count, "ready task count mismatch")
            assert_true(report["simulation"]["sideEffectsPerformed"] is False, "dry run performed a side effect")
            assert_true(len(report["topologicalOrder"]) == count, "topological order size mismatch")
            assert_true(report["quality"]["score"] == 100.0, "fixture quality regressed")
            return f"{count} tasks compiled and dry-ran with score 100, no side effects, and {report['simulation']['executionBatchCount']} batches"
        gate.check(f"{count}-task compile and dry-run fixture", fixture_case)

    def deterministic_output() -> str:
        first = compile_fixture(100)
        second = compile_fixture(100)
        assert_true(first == second, "identical inputs produced different reports")
        assert_true(first["outputHash"] == second["outputHash"], "output hashes differ")
        return f"identical 100-task inputs produced stable output hash {first['outputHash']}"

    gate.check("Deterministic compilation output", deterministic_output)

    def hierarchy_and_dependencies() -> str:
        report = fixture_reports.get(100) or compile_fixture(100)
        assert_true(report["topologicalOrder"] == [f"task_{index:03d}" for index in range(1, 101)], "unexpected topological order")
        plan = load("plan_100.json")
        assert_true(any(task["parentId"] for task in plan["tasks"]), "fixture lacks hierarchy")
        return "hierarchical parent links and dependency order are stable across 100 tasks"

    gate.check("Hierarchical planner ordering", hierarchy_and_dependencies)

    def local_only_clean() -> str:
        for count in (1, 10, 50, 100):
            report = fixture_reports.get(count) or compile_fixture(count)
            assert_true("local_only_external_claim" not in issue_codes(report), f"fixture {count} has external claim")
            assert_true(report["simulation"]["localOnly"] is True, "local-only policy not retained")
        return "all positive fixtures remain local-only with no external-service claim"

    gate.check("Local-only plan policy", local_only_clean)

    def missing_capability() -> str:
        plan = load("plan_001.json")
        plan["tasks"][0]["requiredCapabilities"].remove("project.mutate")
        report = compile_fixture(1, plan=plan)
        assert_true("required_capability_undeclared" in issue_codes(report), report["issues"])
        assert_true(not report["executable"], "missing capability did not block execution")
        return "inferred but undeclared mutation capability fails closed"

    gate.check("Missing required capability rejection", missing_capability)

    def unknown_tool() -> str:
        plan = load("plan_001.json")
        plan["tasks"][0]["allowedTools"].append("invented_super_tool")
        report = compile_fixture(1, plan=plan)
        assert_true("tool_unknown" in issue_codes(report), report["issues"])
        return "unknown model-invented tool is rejected"

    gate.check("Unknown tool rejection", unknown_tool)

    def network_blocked() -> str:
        plan = load("plan_001.json")
        task = plan["tasks"][0]
        task["taskType"] = "research"
        task["dataBoundary"] = "network"
        task["requiredCapabilities"] = ["knowledge.retrieve", "research.network", "project.inspect", "project.mutate"]
        task["allowedTools"] = ["knowledge_search", "research_fetch", "read_file", "write_file"]
        report = compile_fixture(1, plan=plan)
        assert_true("network_capability_blocked" in issue_codes(report), report["issues"])
        return "network capability is blocked under the product and compiler local-only policy"

    gate.check("Local-only network rejection", network_blocked)

    def sandbox_blocked() -> str:
        plan = load("plan_001.json")
        task = plan["tasks"][0]
        task["taskType"] = "test"
        task["requiredCapabilities"] = ["project.inspect", "project.verify", "project.mutate"]
        task["allowedTools"] = ["read_file", "run_command", "write_file"]
        report = compile_fixture(1, plan=plan)
        assert_true("sandbox_required" in issue_codes(report), report["issues"])
        return "process-backed verification is blocked because v1.4 sandbox availability is not claimed"

    gate.check("Sandbox prerequisite enforcement", sandbox_blocked)

    def legacy_override() -> str:
        plan = load("plan_001.json")
        task = plan["tasks"][0]
        task["taskType"] = "test"
        task["requiredCapabilities"] = ["project.inspect", "project.verify", "project.mutate"]
        task["allowedTools"] = ["read_file", "run_command", "write_file"]
        policy = load("policy.local_only.json")
        policy["legacyUnsandboxedExecutionApproved"] = True
        report = compile_fixture(1, plan=plan, policy=policy)
        assert_true("legacy_unsandboxed_execution" in issue_codes(report), report["issues"])
        assert_true(report["executable"], "explicit legacy override did not unblock the compatibility path")
        assert_true("legacy_unsandboxed_execution" in report["simulation"]["requiredApprovals"], "override approval not surfaced")
        return "explicit legacy override is auditable, warned, and included in required approvals"

    gate.check("Explicit legacy unsandboxed override", legacy_override)

    def artifact_validator_missing() -> str:
        plan = load("plan_001.json")
        artifact = plan["tasks"][0]["outputArtifacts"][0]
        artifact["validators"] = [{"id": "val_manual_only", "kind": "manual_review", "deterministic": False, "config": {}}]
        plan["tasks"][0]["acceptanceCriteria"][0]["evidenceValidatorIds"] = ["val_manual_only"]
        report = compile_fixture(1, plan=plan)
        assert_true("artifact_validator_missing" in issue_codes(report), report["issues"])
        return "required artifact without deterministic validator is rejected"

    gate.check("Artifact validator declaration gate", artifact_validator_missing)

    def acceptance_evidence_missing() -> str:
        plan = load("plan_001.json")
        plan["tasks"][0]["acceptanceCriteria"][0]["evidenceValidatorIds"] = ["validator_missing"]
        report = compile_fixture(1, plan=plan)
        assert_true("acceptance_evidence_missing" in issue_codes(report), report["issues"])
        return "acceptance criterion without resolvable evidence is rejected"

    gate.check("Acceptance evidence linkage gate", acceptance_evidence_missing)

    def stable_identity_integrity() -> str:
        duplicate_plan = load("plan_010.json")
        duplicate_plan["tasks"][1]["id"] = duplicate_plan["tasks"][0]["id"]
        duplicate_report = compile_fixture(10, plan=duplicate_plan)
        assert_true("task_id_duplicate" in issue_codes(duplicate_report), duplicate_report["issues"])
        assert_true(not duplicate_report["executable"], "duplicate task IDs did not block execution")

        invalid_spec = load("specification.json")
        duplicate_requirement = copy.deepcopy(invalid_spec["functionalRequirements"][0])
        invalid_spec["nonFunctionalRequirements"].append(duplicate_requirement)
        invalid_spec["acceptanceCriteria"][0]["requirementIds"].append("requirement_missing")
        invalid_spec["acceptanceCriteria"][0]["evidenceValidatorIds"].append("validator_missing")
        invalid_spec["acceptanceCriteria"].append(copy.deepcopy(invalid_spec["acceptanceCriteria"][0]))
        spec_report = compile_fixture(1, spec=invalid_spec)
        codes = issue_codes(spec_report)
        expected = {
            "requirement_id_duplicate",
            "criterion_id_duplicate",
            "criterion_requirement_missing",
            "criterion_validator_missing",
        }
        assert_true(expected <= codes, spec_report["issues"])
        assert_true(not spec_report["executable"], "broken specification references did not block execution")
        return "duplicate task/specification IDs and dangling criterion references fail closed"

    gate.check("Stable ID and reference integrity", stable_identity_integrity)

    def dependency_cycle() -> str:
        plan = load("plan_010.json")
        plan["tasks"][0]["dependencies"] = ["task_010"]
        report = compile_fixture(10, plan=plan)
        assert_true("dependency_cycle" in issue_codes(report), report["issues"])
        return "dependency cycle is detected deterministically"

    gate.check("Dependency cycle rejection", dependency_cycle)

    def parent_cycle() -> str:
        plan = load("plan_010.json")
        plan["tasks"][0]["parentId"] = "task_002"
        plan["tasks"][1]["parentId"] = "task_001"
        report = compile_fixture(10, plan=plan)
        assert_true("parent_cycle" in issue_codes(report), report["issues"])
        return "hierarchical parent cycle is detected deterministically"

    gate.check("Parent hierarchy cycle rejection", parent_cycle)

    def producer_conflict() -> str:
        plan = load("plan_010.json")
        first_path = plan["tasks"][0]["outputArtifacts"][0]["path"]
        second = plan["tasks"][1]
        second["dependencies"] = []
        second["outputArtifacts"][0]["path"] = first_path
        for validator in second["outputArtifacts"][0]["validators"]:
            validator["config"]["path"] = first_path
        report = compile_fixture(10, plan=plan)
        assert_true("artifact_path_producer_conflict" in issue_codes(report), report["issues"])
        return "concurrent artifact producers require an explicit dependency"

    gate.check("Artifact producer conflict rejection", producer_conflict)

    def self_modification() -> str:
        plan = load("plan_001.json")
        plan["tasks"][0]["targetScope"] = "host_application"
        report = compile_fixture(1, plan=plan)
        assert_true("self_modification_not_approved" in issue_codes(report), report["issues"])
        return "host-application self-modification is blocked without explicit approval"

    gate.check("Self-modification guard", self_modification)

    def human_workflow() -> str:
        plan = load("plan_001.json")
        plan["tasks"][0]["instructions"] += " Recruit participants and conduct user interviews."
        report = compile_fixture(1, plan=plan)
        assert_true("human_workflow_missing" in issue_codes(report), report["issues"])
        return "fabricated participant workflow is rejected unless modeled as manual"

    gate.check("Human workflow capability guard", human_workflow)

    def deployment_target() -> str:
        spec = load("specification.json")
        spec["dataPolicy"]["localOnly"] = False
        spec["deploymentBoundary"] = {"mode": "external_automated", "target": None, "approvalRequired": True}
        plan = load("plan_001.json")
        plan["localOnly"] = False
        task = plan["tasks"][0]
        task["taskType"] = "deployment"
        task["requiredCapabilities"] = ["deployment.package", "project.inspect", "project.mutate"]
        task["allowedTools"] = ["package_deployment", "read_file", "write_file"]
        policy = load("policy.local_only.json")
        policy.update({"localOnly": False, "sandboxAvailable": True, "networkAllowed": True})
        report = compile_fixture(1, plan=plan, spec=spec, policy=policy)
        assert_true("deployment_target_missing" in issue_codes(report), report["issues"])
        return "automated external deployment without a target is rejected"

    gate.check("Deployment target compiler gate", deployment_target)

    def plan_budget() -> str:
        policy = load("policy.local_only.json")
        policy["maxTotalToolCalls"] = 2
        report = compile_fixture(1, policy=policy)
        assert_true("plan_budget_exceeded" in issue_codes(report), report["issues"])
        return "aggregate plan budgets are checked before execution"

    gate.check("Plan budget preflight", plan_budget)

    def prompt_impact() -> str:
        comparison = plan_compiler.compare_prompt_versions(
            load("prompt.baseline.json"),
            load("prompt.candidate.json"),
            load("evaluation_dataset.json"),
        )
        assert_true(comparison["baseline"]["score"] == 25.0, comparison)
        assert_true(comparison["candidate"]["score"] == 100.0, comparison)
        assert_true(comparison["measuredImpact"]["scoreDelta"] == 75.0, comparison)
        return "prompt revision improves deterministic preflight score from 25.0 to 100.0 (+75.0)"

    gate.check("Measured prompt-version impact", prompt_impact)

    def plan_impact() -> str:
        baseline = load("plan_010.json")
        baseline["tasks"][0]["requiredCapabilities"].remove("project.mutate")
        candidate = load("plan_010.json")
        comparison = plan_compiler.compare_plans(
            load("specification.json"), baseline, candidate, policy=load("policy.local_only.json")
        )
        assert_true(comparison["measuredImpact"]["qualityScoreDelta"] > 0, comparison)
        assert_true(comparison["measuredImpact"]["errorDelta"] < 0, comparison)
        return f"plan repair changes quality by {comparison['measuredImpact']['qualityScoreDelta']} and errors by {comparison['measuredImpact']['errorDelta']}"

    gate.check("Measured plan-revision impact", plan_impact)

    def report_schema() -> str:
        report = fixture_reports.get(10) or compile_fixture(10)
        errors = plan_compiler.validate_document(report, contracts["report"], document_name="compilation_report")
        assert_true(not errors, errors)
        return "compiler output validates against plan_compilation_report.v1"

    gate.check("Compilation report output schema", report_schema)

    def cli_fail_closed() -> str:
        plan = load("plan_001.json")
        plan["tasks"][0]["requiredCapabilities"].remove("project.mutate")
        with tempfile.TemporaryDirectory(prefix="kristin-plan-compiler-") as temp:
            temp_path = Path(temp)
            bad_plan = temp_path / "bad-plan.json"
            output = temp_path / "report.json"
            bad_plan.write_text(json.dumps(plan), encoding="utf-8")
            proc = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "tool" / "plan_compiler.py"),
                    "compile",
                    "--spec", str(FIX / "specification.json"),
                    "--plan", str(bad_plan),
                    "--policy", str(FIX / "policy.local_only.json"),
                    "--output", str(output),
                    "--fail-on-errors",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            assert_true(proc.returncode == 2, f"expected exit 2, got {proc.returncode}: {proc.stdout}")
            assert_true(output.is_file(), "CLI did not preserve the diagnostic report")
        return "CLI returns exit 2 for a blocked plan while preserving the compilation report"

    gate.check("Compiler CLI fail-closed behavior", cli_fail_closed)

    payload = {
        "schema": "kristin.prompt-studio-v2.results.v1",
        "passed": gate.passed,
        "total": len(gate.results),
        "passedCount": sum(item.status == "passed" for item in gate.results),
        "failedCount": sum(item.status == "failed" for item in gate.results),
        "results": [asdict(item) for item in gate.results],
        "fixtureTaskCounts": [1, 10, 50, 100],
        "compilerVersion": plan_compiler.COMPILER_VERSION,
    }
    if args.json_output:
        path = Path(args.json_output)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    for result in gate.results:
        marker = "PASS" if result.status == "passed" else "FAIL"
        print(f"[{marker}] {result.name}: {result.detail}")
    print(f"Prompt Studio 2 gate: {payload['passedCount']}/{payload['total']} passed")
    return 0 if gate.passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
