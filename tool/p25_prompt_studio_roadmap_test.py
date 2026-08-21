#!/usr/bin/env python3
"""Validate the bounded P25 Prompt Studio roadmap extension."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


class P25Error(RuntimeError):
    pass


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise P25Error(f"cannot parse {path}: {error}") from error


def require(condition: bool, message: str) -> None:
    if not condition:
        raise P25Error(message)


def find_cycle(tasks: dict[str, dict[str, Any]]) -> list[str]:
    state: dict[str, int] = {}
    stack: list[str] = []

    def visit(task_id: str) -> list[str]:
        state[task_id] = 1
        stack.append(task_id)
        for dependency in tasks[task_id].get("dependsOn", []):
            if dependency not in tasks:
                continue
            if state.get(dependency, 0) == 0:
                result = visit(dependency)
                if result:
                    return result
            elif state.get(dependency) == 1:
                start = stack.index(dependency)
                return stack[start:] + [dependency]
        stack.pop()
        state[task_id] = 2
        return []

    for task_id in sorted(tasks):
        if state.get(task_id, 0) == 0:
            result = visit(task_id)
            if result:
                return result
    return []


def validate(project: Path) -> dict[str, Any]:
    required = [
        "docs/roadmap/P25_PROMPT_STUDIO_PRODUCT_RESCUE.md",
        "docs/roadmap/decisions/ADR-P25-001-prompt-studio-product-rescue.md",
        "docs/roadmap/p25/manifest.v1.json",
        "docs/roadmap/p25/performance_budget.v1.json",
        "docs/roadmap/p25/benchmark_corpus.v1.json",
        "docs/roadmap/p25/prompt_studio_test_station.v1.json",
        "docs/testing/TEST_CENTER_P25_PROMPT_STUDIO.md",
        "tool/p25_prompt_studio_roadmap_test.py",
        "tool/p25_prompt_studio_test_station.py",
    ]
    for relative in required:
        require((project / relative).is_file(), f"missing P25 path: {relative}")

    manifest = load_json(project / "docs/roadmap/p25/manifest.v1.json")
    expected_ids = [f"P25-{index:03d}" for index in range(1, 12)]
    tasks = {
        item["id"]: item
        for item in manifest.get("tasks", [])
        if isinstance(item, dict) and isinstance(item.get("id"), str)
    }
    require(manifest.get("taskOrder") == expected_ids, "taskOrder must be P25-001..P25-011")
    require(sorted(tasks) == expected_ids, "manifest must contain exactly eleven P25 tasks")
    require(manifest.get("nextReady") == ["P25-001"], "only P25-001 may initially be READY")
    for task_id in expected_ids:
        task = tasks[task_id]
        expected_status = "READY" if task_id == "P25-001" else "BLOCKED"
        require(task.get("status") == expected_status, f"{task_id} status must be {expected_status}")
        for dependency in task.get("dependsOn", []):
            require(dependency in tasks, f"{task_id} depends on missing {dependency}")
        packet = project / str(task.get("packet"))
        require(packet.is_file(), f"{task_id} packet is missing")
        text = packet.read_text(encoding="utf-8")
        require(f"# {task_id} " in text, f"{task_id} packet title is invalid")
        require("## Acceptance" in text, f"{task_id} lacks acceptance")
        require("## Evidence" in text, f"{task_id} lacks evidence")
    cycle = find_cycle(tasks)
    require(not cycle, f"P25 task cycle: {' -> '.join(cycle)}")

    budget = load_json(project / "docs/roadmap/p25/performance_budget.v1.json")
    expected_budget = {
        "uiAcknowledgementP95Ms": 100,
        "durableOperationCreationP95Ms": 250,
        "firstVisibleActivityP95Ms": 500,
        "maximumInvisibleEventGapMs": 3000,
        "cancelAcknowledgementP95Ms": 250,
        "providerCancellationP95Ms": 2000,
        "warmSimplePromptP50Ms": 20000,
        "warmSimplePromptP95Ms": 45000,
        "coldSimplePromptP95Ms": 90000,
        "normalFullGenerationCallsMax": 1,
        "fullRepairCallsMax": 1,
        "silentRetriesMax": 0,
    }
    require(budget.get("metrics") == expected_budget, "P25 performance budget drifted")

    corpus = load_json(project / "docs/roadmap/p25/benchmark_corpus.v1.json")
    counts: dict[str, int] = {}
    seen: set[str] = set()
    for case in corpus.get("cases", []):
        require(isinstance(case, dict), "benchmark case must be an object")
        case_id = str(case.get("id"))
        require(case_id not in seen, f"duplicate benchmark case {case_id}")
        seen.add(case_id)
        complexity = str(case.get("complexity"))
        counts[complexity] = counts.get(complexity, 0) + 1
        require(isinstance(case.get("goal"), str) and len(case["goal"]) >= 5, f"{case_id} goal invalid")
        require(case.get("expectedFullGenerationCalls") == 1, f"{case_id} call budget invalid")
    require(
        counts == {"simple": 20, "ambiguous": 10, "normal": 10, "complex": 5},
        f"benchmark counts invalid: {counts}",
    )

    station = load_json(project / "docs/roadmap/p25/prompt_studio_test_station.v1.json")
    profiles = {item["profileId"] for item in station.get("profiles", [])}
    require(
        profiles == {"contract", "latency-unit", "local-phi-cpu", "packaged-windows"},
        "P25 Test Station profiles are incomplete",
    )
    case_ids = {item["caseId"] for item in station.get("cases", [])}
    require(
        case_ids
        == {
            "p25-roadmap-contract",
            "p25-test-station-contract",
            "p25-latency-trace",
            "p25-owner-phi-benchmark",
            "p25-packaged-windows",
        },
        "P25 Test Station case set is invalid",
    )

    registry = load_json(project / "config/test_center_registry.v1.json")
    registered_cases = {item["testId"] for item in registry.get("testCases", [])}
    registered_profiles = {
        item["stableCheckId"] for item in registry.get("projectTestProfiles", [])
    }
    governance_ids = {
        "tc.p25.roadmap-contract",
        "tc.p25.test-station-contract",
    }
    require(governance_ids <= registered_cases, "P25 governance Test Center cases are missing")
    require(governance_ids <= registered_profiles, "P25 governance profiles are missing")
    hierarchy = load_json(project / "config/test_center_assurance_hierarchy.v1.json")
    bindings = {item["testId"]: item["levelId"] for item in hierarchy.get("testBindings", [])}
    for test_id in governance_ids:
        require(bindings.get(test_id) == "architecture_lint", f"{test_id} hierarchy binding invalid")

    master = (project / "docs/roadmap/MASTER.md").read_text(encoding="utf-8")
    roadmap = load_json(project / "docs/roadmap/roadmap.yaml")
    match = re.search(r"\*\*Roadmap version:\*\* `([^`]+)`", master)
    require(match is not None, "MASTER roadmap version is missing")
    require(roadmap.get("roadmapVersion") == match.group(1), "roadmap versions differ")
    require(
        roadmap.get("authority", {}).get("masterSha256")
        == hashlib.sha256(master.encode("utf-8")).hexdigest(),
        "roadmap masterSha256 is stale",
    )
    require("## P25 — Prompt Studio product rescue" in master, "MASTER lacks P25 extension")
    require(
        roadmap.get("authority", {}).get("scope") == ["P0", "P1"],
        "P25 must not silently widen the bootstrap machine-roadmap scope",
    )

    return {
        "schemaVersion": "1.0.0",
        "gateId": "p25-prompt-studio-roadmap",
        "passed": True,
        "taskCount": len(tasks),
        "ready": manifest.get("nextReady"),
        "benchmarkCounts": counts,
        "governanceTestIds": sorted(governance_ids),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    try:
        report = validate(Path(args.project).resolve())
    except P25Error as error:
        print(f"P25_ROADMAP_FAIL: {error}", file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(
            "P25_ROADMAP_PASS "
            f"tasks={report['taskCount']} ready={','.join(report['ready'])} "
            f"cases={sum(report['benchmarkCounts'].values())}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
