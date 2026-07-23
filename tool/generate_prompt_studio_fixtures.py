#!/usr/bin/env python3
"""Generate deterministic Prompt Studio 2 fixtures for 1/10/50/100 tasks."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "test" / "product" / "fixtures" / "prompt_studio_v2"
COUNTS = (1, 10, 50, 100)


def render(value: object) -> str:
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def specification() -> dict[str, Any]:
    return {
        "schemaVersion": "2.0.0",
        "id": "spec_fixture_product",
        "title": "Deterministic local artifact fixture",
        "problemStatement": "Create a bounded set of project-local Markdown artifacts so plan compilation, dependency ordering, capability checks, and validation declarations can be tested without external services.",
        "targetUsers": ["Kristin release engineers", "Prompt Studio maintainers"],
        "functionalRequirements": [
            {"id": "req_artifacts", "statement": "The plan must produce the requested number of distinct project-local artifacts.", "priority": "must", "source": "v1.5 release gate"},
            {"id": "req_validation", "statement": "Every required artifact must declare deterministic validation evidence.", "priority": "must", "source": "v1.5 release gate"},
            {"id": "req_local", "statement": "The plan must remain local-only and make no unsupported external-service claims.", "priority": "must", "source": "roadmap policy"},
        ],
        "nonFunctionalRequirements": [
            {"id": "nfr_determinism", "statement": "Compiling identical inputs must produce the same output hash.", "priority": "must", "source": "release reproducibility"},
            {"id": "nfr_scale", "statement": "The compiler must support plans containing from one through one hundred tasks.", "priority": "must", "source": "v1.5 exit gate"},
        ],
        "excludedScope": ["External deployment", "Live web research", "Unsandboxed command execution"],
        "assumptions": ["The governed project file tools are available.", "The compilation run performs no side effects."],
        "clarificationQuestions": [],
        "targetPlatforms": ["Windows", "macOS", "Linux"],
        "dataPolicy": {
            "localOnly": True,
            "sensitivity": "internal",
            "allowedProviders": ["local"],
            "retention": "project",
            "allowNetworkResearch": False,
            "allowSecretUse": False,
        },
        "artifacts": [
            {
                "id": "artifact_compilation_report",
                "type": "test_report",
                "path": "artifacts/plan-compilation-report.json",
                "description": "Machine-readable compilation and dry-run report.",
                "required": True,
                "sensitivity": "internal",
                "validators": [
                    {"id": "val_report_exists", "kind": "file_exists", "deterministic": True, "config": {"path": "artifacts/plan-compilation-report.json"}},
                    {"id": "val_report_schema", "kind": "json_schema", "deterministic": True, "config": {"schema": "schemas/plan_compilation_report.v1.json"}},
                ],
            }
        ],
        "acceptanceCriteria": [
            {
                "id": "criterion_report_valid",
                "statement": "The compilation report exists and validates against its versioned schema.",
                "evidenceValidatorIds": ["val_report_exists", "val_report_schema"],
                "requirementIds": ["req_validation", "nfr_determinism"],
            }
        ],
        "testStrategy": [
            "Compile and dry-run 1-, 10-, 50-, and 100-task plans.",
            "Compile malformed plans and confirm deterministic fail-closed issue codes.",
            "Compile identical inputs twice and compare output hashes.",
        ],
        "deploymentBoundary": {"mode": "none", "target": None, "approvalRequired": False},
        "riskClassification": "low",
        "metadata": {"fixture": True, "milestone": "1.5.0"},
    }


def task(index: int, count: int) -> dict[str, Any]:
    task_id = f"task_{index:03d}"
    phase_size = 10
    phase_number = (index - 1) // phase_size + 1
    phase_start = (phase_number - 1) * phase_size + 1
    parent_id = None if index == phase_start else f"task_{phase_start:03d}"
    dependencies = [] if index == 1 else [f"task_{index - 1:03d}"]
    path = f"artifacts/generated/{task_id}.md"
    exists_id = f"val_{task_id}_exists"
    nonempty_id = f"val_{task_id}_nonempty"
    return {
        "id": task_id,
        "parentId": parent_id,
        "phase": f"Phase {phase_number:02d}",
        "order": index,
        "title": f"Create local artifact {index} of {count}",
        "objective": f"Produce deterministic project-local Markdown artifact {task_id} with bounded content.",
        "instructions": f"Inspect relevant project context, create {path}, and include the task identifier plus a concise completion summary. Do not use network services or run external commands.",
        "taskType": "implementation",
        "dependencies": dependencies,
        "requiredCapabilities": ["project.inspect", "project.mutate"],
        "allowedTools": ["inspect_file", "read_file", "write_file"],
        "inputArtifacts": [],
        "outputArtifacts": [
            {
                "id": f"artifact_{task_id}",
                "type": "document",
                "path": path,
                "description": f"Deterministic Markdown artifact produced by {task_id}.",
                "required": True,
                "sensitivity": "internal",
                "validators": [
                    {"id": exists_id, "kind": "file_exists", "deterministic": True, "config": {"path": path}},
                    {"id": nonempty_id, "kind": "non_empty", "deterministic": True, "config": {"path": path, "minBytes": 20}},
                ],
            }
        ],
        "acceptanceCriteria": [
            {
                "id": f"criterion_{task_id}",
                "statement": f"Artifact {path} exists and contains non-empty deterministic content.",
                "evidenceValidatorIds": [exists_id, nonempty_id],
                "requirementIds": ["req_artifacts", "req_validation"],
            }
        ],
        "verification": [],
        "dataBoundary": "project",
        "targetScope": "project",
        "complexity": 1 + ((index - 1) % 5),
        "effortPoints": [1, 2, 3, 5, 8][(index - 1) % 5],
        "uncertainty": "low" if index % 7 else "medium",
        "risk": "low",
        "estimateConfidence": 0.92,
        "budgets": {"modelTurns": 1, "toolCalls": 3, "outputBytes": 4096},
        "retryPolicy": {"maxAttempts": 2, "retryableClasses": ["provider_transient", "schema_repair", "tool_input_repair", "project_state_conflict"]},
        "stopPolicy": {"maxNonProgressTurns": 2, "onPolicyRejection": "stop", "onAmbiguousSideEffect": "stop"},
        "enabled": True,
        "manual": False,
    }


def plan(count: int) -> dict[str, Any]:
    return {
        "schemaVersion": "2.0.0",
        "id": f"plan_fixture_{count:03d}",
        "specificationId": "spec_fixture_product",
        "promptVersionId": "prompt_version_fixture_v2",
        "title": f"Deterministic {count}-task compilation fixture",
        "rationale": "Exercise schema validation, hierarchy, dependency ordering, capability coverage, artifact declarations, and local-only policy at the requested plan size.",
        "localOnly": True,
        "tasks": [task(index, count) for index in range(1, count + 1)],
        "metadata": {"fixtureTaskCount": count, "dryRunOnly": True},
    }


def baseline_prompt() -> dict[str, Any]:
    return {
        "title": "Make project files",
        "purpose": "Create some files for a project.",
        "systemPrompt": "Help with the request and provide a useful result.",
        "userPrompt": "Build {{thing}}.",
        "variables": ["thing"],
        "assumptions": [],
        "clarifyingQuestions": [],
        "acceptanceCriteria": ["The result looks good."],
        "outputExpectations": ["Some files"],
        "guardrails": [],
        "stopConditions": [],
        "evaluationCases": [],
        "mode": "build",
    }


def candidate_prompt() -> dict[str, Any]:
    return {
        "title": "Compile a deterministic local-only artifact plan",
        "purpose": "Create project-local artifacts through a deterministic, capability-checked plan without unsupported external claims.",
        "systemPrompt": "Act as a local-only implementation planner. Declare every artifact, deterministic validator, required capability, allowed tool, dependency, retry boundary, and stop condition. Never claim a public URL or external deployment.",
        "userPrompt": "For {{project_name}}, produce {{artifact_count}} project-local artifacts and a machine-readable compilation report. Keep all work inside the selected project.",
        "variables": ["project_name", "artifact_count"],
        "assumptions": ["Governed project file tools are available."],
        "clarifyingQuestions": ["Which project-relative output directory should contain the artifacts?"],
        "acceptanceCriteria": [
            "Validate every required artifact with deterministic file-exists and non-empty evidence.",
            "Validate that every executable task declares capabilities covered by allowed tools.",
            "Validate that the plan contains no unsupported external-service or public-hosting claim.",
        ],
        "outputExpectations": ["Versioned product specification", "Compiled task plan", "Artifact validation declarations", "Dry-run report"],
        "guardrails": ["Local-only data boundary", "No secrets", "No external deployment", "No unsandboxed process execution"],
        "stopConditions": ["Stop on policy rejection", "Stop when a capability lacks an authorized tool", "Ask for review before any external action"],
        "evaluationCases": ["One-task plan", "Ten-task plan", "Fifty-task plan", "One-hundred-task plan"],
        "mode": "build",
    }


def evaluation_dataset() -> dict[str, Any]:
    common = {
        "variables": {"project_name": "fixture", "artifact_count": "10"},
        "requiredTerms": ["local-only", "deterministic", "artifact", "capability"],
        "forbiddenTerms": ["guaranteed public url", "silently widen permissions"],
        "requiredVariables": ["project_name", "artifact_count"],
        "requiredCriterionTerms": ["validate", "allowed tools", "external-service"],
        "expectedMode": "build",
        "weight": 1.0,
        "tags": ["local-only", "compiler"],
    }
    return {
        "schemaVersion": "1.0.0",
        "id": "eval_prompt_studio_v2",
        "title": "Prompt Studio 2 deterministic preflight dataset",
        "promptId": "prompt_studio_v2_fixture",
        "cases": [
            {"id": "case_atomic_plan", "input": "Compile one local artifact task.", **common},
            {"id": "case_large_plan", "input": "Compile one hundred local artifact tasks.", **common},
            {"id": "case_policy_guard", "input": "Reject external hosting in local-only mode.", **common},
        ],
    }


def policy() -> dict[str, Any]:
    return {
        "localOnly": True,
        "sandboxAvailable": False,
        "legacyUnsandboxedExecutionApproved": False,
        "networkAllowed": False,
        "humanWorkflowAvailable": False,
        "selfModificationApproved": False,
        "deploymentTarget": None,
        "maxTasks": 100,
        "maxTotalModelTurns": 1200,
        "maxTotalToolCalls": 5000,
        "maxTotalOutputBytes": 500000000,
    }


def generated_files() -> dict[Path, str]:
    values: dict[Path, str] = {
        FIXTURES / "specification.json": render(specification()),
        FIXTURES / "policy.local_only.json": render(policy()),
        FIXTURES / "prompt.baseline.json": render(baseline_prompt()),
        FIXTURES / "prompt.candidate.json": render(candidate_prompt()),
        FIXTURES / "evaluation_dataset.json": render(evaluation_dataset()),
    }
    for count in COUNTS:
        values[FIXTURES / f"plan_{count:03d}.json"] = render(plan(count))
    return values


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    failures: list[str] = []
    for path, content in generated_files().items():
        if args.check:
            if not path.is_file() or path.read_text(encoding="utf-8") != content:
                failures.append(str(path.relative_to(ROOT)))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")
    if failures:
        print("stale Prompt Studio 2 fixtures:")
        for failure in failures:
            print(f"- {failure}")
        return 1
    if not args.check:
        print(f"generated {len(generated_files())} fixture files in {FIXTURES.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
