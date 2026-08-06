#!/usr/bin/env python3
"""Deterministic mission execution control for the V3.2 ANARCHY overlay.

The live roadmap authority remains docs/roadmap/MASTER.md and the declared scope
of docs/roadmap/roadmap.yaml. This tool generates transferable mission views
from the normalized P00-P24 phase packets and validates claims/collisions.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import sys
from collections import defaultdict
from typing import Any

TASK_ID = re.compile(r"P\d+-\d+")
PHASE_ID = re.compile(r"^P(\d+)$")
CONFIG_PATH = pathlib.Path("config/mission_execution.v1.json")
PACKETS_PATH = pathlib.Path("docs/roadmap/anarchy/phases")
OUTPUT_PATH = pathlib.Path("docs/roadmap/missions")


def read_json(path: pathlib.Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def canonical_json(value: Any) -> str:
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def section(text: str, heading: str) -> str:
    marker = f"## {heading}"
    start = text.find(marker)
    if start < 0:
        return ""
    body_start = text.find("\n", start) + 1
    next_heading = text.find("\n## ", body_start)
    if next_heading < 0:
        next_heading = len(text)
    return text[body_start:next_heading].strip()


def frontmatter_value(text: str, key: str) -> str:
    match = re.search(rf"(?m)^{re.escape(key)}:\s*(.+?)\s*$", text)
    if not match:
        raise ValueError(f"missing frontmatter key {key}")
    return match.group(1).strip().strip('"')


def parse_task_row(line: str, packet: pathlib.Path) -> dict[str, Any] | None:
    if not line.startswith("|") or "`P" not in line:
        return None
    columns = [column.strip() for column in line.strip().strip("|").split("|")]
    if len(columns) != 5:
        raise ValueError(f"unexpected task table row in {packet}: {line}")
    match = TASK_ID.search(columns[0])
    if not match:
        return None
    task_id = match.group(0)
    dependencies = TASK_ID.findall(columns[2])
    return {
        "id": task_id,
        "title": columns[1].replace("`", ""),
        "dependencies": dependencies,
        "requiredOutput": columns[3].replace("`", ""),
        "doneWhen": columns[4].replace("`", ""),
    }


def bullet_lines(value: str) -> list[str]:
    return [line.strip()[2:].strip() for line in value.splitlines() if line.strip().startswith("- ")]


def parse_packets(project: pathlib.Path) -> dict[str, dict[str, Any]]:
    packet_dir = project / PACKETS_PATH
    paths = sorted(packet_dir.glob("P[0-9][0-9]-*.md"))
    if len(paths) != 25:
        raise ValueError(f"expected 25 phase packets, found {len(paths)}")
    phases: dict[str, dict[str, Any]] = {}
    for path in paths:
        text = path.read_text(encoding="utf-8")
        phase = frontmatter_value(text, "phase")
        if not PHASE_ID.match(phase):
            raise ValueError(f"invalid phase {phase} in {path}")
        tasks = []
        for line in section(text, "Task backlog").splitlines():
            task = parse_task_row(line, path)
            if task:
                task["phase"] = phase
                tasks.append(task)
        if not tasks:
            raise ValueError(f"no tasks parsed from {path}")
        phases[phase] = {
            "phase": phase,
            "title": frontmatter_value(text, "title"),
            "packet": path.relative_to(project).as_posix(),
            "executionViewStatus": frontmatter_value(text, "execution_view_status"),
            "testCenterModule": frontmatter_value(text, "test_center_module"),
            "purpose": section(text, "Purpose"),
            "currentExecutionView": section(text, "Current execution view"),
            "tasks": tasks,
            "testCenterDeliverables": bullet_lines(section(text, "Test Center deliverables")),
            "acceptanceScenarios": bullet_lines(section(text, "Acceptance scenarios")),
            "exitGate": bullet_lines(section(text, "Exit gate")),
            "parallelRules": bullet_lines(section(text, "Parallel execution rules")),
        }
    return phases


def static_prefix(pattern: str) -> str:
    return pattern.split("*", 1)[0].rstrip("/")


def has_path_collision(left: str, right: str) -> bool:
    a, b = static_prefix(left), static_prefix(right)
    return bool(a and b and (a == b or a.startswith(b + "/") or b.startswith(a + "/")))


def assert_acyclic(nodes: list[str], edges: dict[str, list[str]], label: str) -> None:
    visiting: set[str] = set()
    visited: set[str] = set()

    def walk(node: str, chain: list[str]) -> None:
        if node in visiting:
            raise ValueError(f"{label} cycle: {' -> '.join(chain + [node])}")
        if node in visited:
            return
        visiting.add(node)
        for dependency in edges.get(node, []):
            walk(dependency, chain + [node])
        visiting.remove(node)
        visited.add(node)

    for node in nodes:
        walk(node, [])


def build_model(project: pathlib.Path) -> dict[str, Any]:
    config = read_json(project / CONFIG_PATH)
    phases = parse_packets(project)
    missions = config["missions"]
    expected_ids = [f"MISSION-{index:03d}" for index in range(1, 16)]
    actual_ids = [mission["id"] for mission in missions]
    if actual_ids != expected_ids:
        raise ValueError(f"mission IDs must be {expected_ids}, got {actual_ids}")

    phase_owner: dict[str, str] = {}
    for mission in missions:
        for phase in mission["phases"]:
            if phase not in phases:
                raise ValueError(f"{mission['id']} references missing {phase}")
            if phase in phase_owner:
                raise ValueError(f"phase {phase} assigned twice")
            phase_owner[phase] = mission["id"]
    if set(phase_owner) != set(phases):
        raise ValueError(f"phase assignment mismatch: missing={sorted(set(phases)-set(phase_owner))}")

    tasks: dict[str, dict[str, Any]] = {}
    for phase in phases.values():
        for task in phase["tasks"]:
            if task["id"] in tasks:
                raise ValueError(f"duplicate task {task['id']}")
            task = dict(task)
            task["mission"] = phase_owner[task["phase"]]
            tasks[task["id"]] = task
    if len(tasks) != 359:
        raise ValueError(f"expected 359 roadmap tasks, found {len(tasks)}")

    task_edges: dict[str, list[str]] = {}
    for task in tasks.values():
        for dependency in task["dependencies"]:
            if dependency not in tasks:
                raise ValueError(f"{task['id']} references missing dependency {dependency}")
        task_edges[task["id"]] = task["dependencies"]
    assert_acyclic(sorted(tasks), task_edges, "roadmap task")

    mission_ids = set(actual_ids)
    entry_edges: dict[str, list[str]] = {}
    for mission in missions:
        dependencies = mission["entryDependsOn"]
        if mission["id"] in dependencies:
            raise ValueError(f"{mission['id']} depends on itself")
        unknown = set(dependencies) - mission_ids
        if unknown:
            raise ValueError(f"{mission['id']} has unknown entry dependencies {sorted(unknown)}")
        entry_edges[mission["id"]] = dependencies
    assert_acyclic(actual_ids, entry_edges, "mission entry")

    claims = config.get("activeClaims", [])
    claim_by_mission: dict[str, dict[str, Any]] = {}
    for claim in claims:
        mission_id = claim["mission"]
        if mission_id not in mission_ids:
            raise ValueError(f"claim references unknown mission {mission_id}")
        if mission_id in claim_by_mission:
            raise ValueError(f"multiple active claims for {mission_id}")
        claim_by_mission[mission_id] = claim
    for index, left in enumerate(claims):
        for right in claims[index + 1:]:
            for left_path in left.get("exclusivePaths", []):
                for right_path in right.get("exclusivePaths", []):
                    if has_path_collision(left_path, right_path):
                        raise ValueError(
                            f"exclusive path collision: {left['mission']} {left_path} vs "
                            f"{right['mission']} {right_path}"
                        )

    interlocks = []
    for task in tasks.values():
        for dependency in task["dependencies"]:
            source = tasks[dependency]
            if source["mission"] != task["mission"]:
                interlocks.append({
                    "task": task["id"],
                    "taskMission": task["mission"],
                    "dependsOnTask": dependency,
                    "dependsOnMission": source["mission"],
                })

    return {
        "config": config,
        "phases": phases,
        "missions": missions,
        "tasks": tasks,
        "phaseOwner": phase_owner,
        "entryEdges": entry_edges,
        "interlocks": sorted(interlocks, key=lambda item: (item["task"], item["dependsOnTask"])),
        "claims": claims,
        "claimByMission": claim_by_mission,
    }


def mission_markdown(model: dict[str, Any], mission: dict[str, Any]) -> str:
    claim = model["claimByMission"].get(mission["id"])
    lines = [
        f"# {mission['id']} — {mission['title']}",
        "",
        f"**Default executor:** Worker {mission['defaultWorker']}  ",
        f"**Priority:** `{mission['priority']}`  ",
        f"**Roadmap phases:** {', '.join(f'`{phase}`' for phase in mission['phases'])}  ",
        "**Authority:** execution overlay only; `docs/roadmap/MASTER.md` remains human authority.",
        "",
        "## Mission objective",
        "",
        mission["objective"],
        "",
        "## Transfer and resume protocol",
        "",
        "1. Re-resolve protected main, mission branch, PR, head/tree, CI, reviews, and dependency state.",
        "2. Load this contract, the mission state, active claim, latest checkpoint, entry graph, and task interlocks.",
        "3. Reuse valid implementation and evidence already present; never restart completed work without a proven defect.",
        "4. Select the highest-priority dependency-satisfied task or a clearly labeled dependency-safe source/fixture/documentation packet.",
        "5. Implement, test, document, commit, push, inspect exact-head CI, repair, obtain required independent review, and update state/checkpoint.",
        "6. Yield only with an exact continuation point or complete the mission and release its claim.",
        "",
        "## Current repository anchor",
        "",
    ]
    if claim:
        lines += [
            f"- Worker: `{claim['worker']}`",
            f"- Branch: `{claim['branch']}`",
            f"- Draft PR: `#{claim['pr']}`",
            f"- Observed head: `{claim['head']}`",
            f"- Observed tree: `{claim.get('tree') or 'UNRESOLVED'}`",
            f"- Current work: {claim['current']}",
            "- These are discovery anchors, not permission to skip live-state discovery.",
        ]
    else:
        lines += ["- No active claim. The mission is available only when its entry dependencies and ownership checks pass."]

    for phase_id in mission["phases"]:
        phase = model["phases"][phase_id]
        lines += [
            "",
            f"## {phase_id} — {phase['title']}",
            "",
            f"**Packet:** `{phase['packet']}`  ",
            f"**Current execution view:** `{phase['executionViewStatus']}`  ",
            f"**Test Center module:** `{phase['testCenterModule']}`",
            "",
            "### Purpose",
            "",
            phase["purpose"],
            "",
            "### Exact task program",
            "",
            "| Task | Work | Dependencies | Required output | Done when |",
            "|---|---|---|---|---|",
        ]
        for task in phase["tasks"]:
            dependencies = ", ".join(f"`{value}`" for value in task["dependencies"]) or "None"
            lines.append(
                f"| `{task['id']}` | {task['title']} | {dependencies} | "
                f"{task['requiredOutput']} | {task['doneWhen']} |"
            )
        lines += ["", "### Test Center deliverables", ""]
        lines += [f"- {value}" for value in phase["testCenterDeliverables"]]
        lines += ["", "### Acceptance scenarios", ""]
        lines += [f"- {value}" for value in phase["acceptanceScenarios"]]
        lines += ["", "### Exit gate", ""]
        lines += [f"- {value}" for value in phase["exitGate"]]

    mission_interlocks = [item for item in model["interlocks"] if item["taskMission"] == mission["id"]]
    lines += ["", "## Cross-mission task interlocks", ""]
    if mission_interlocks:
        lines += [
            f"- `{item['task']}` waits for `{item['dependsOnTask']}` from `{item['dependsOnMission']}`."
            for item in mission_interlocks
        ]
    else:
        lines += ["- No cross-mission task dependency is declared in the normalized roadmap packets."]

    lines += [
        "",
        "## Git, collision, and merge contract",
        "",
        "- One active claim per mission. A replacement worker must receive a recorded yield or transfer.",
        "- Do not edit another active mission's exclusive paths or shared authority without an explicit coordination packet.",
        "- Workers may commit, push, update their draft PR, and iterate CI inside their bounded claim.",
        "- No blanket right to bypass branch protection, required checks, security review, dependency gates, or roadmap authority.",
        "- A materially changed exact candidate invalidates commit-bound reviews and evidence.",
        "- Every significant push updates mission state and creates or supersedes a checkpoint.",
        "",
        "## Mission definition of done",
        "",
        "The mission is complete only when every assigned roadmap task is truthfully complete; applicable unit, contract, component, integration, negative, regression, platform, recovery, performance, acceptance, certification, and release gates pass; evidence and documentation are durable; required independent reviews bind the final exact commit/tree; and the integrated product capability works on every mandatory platform claimed by the roadmap.",
        "",
        "## Resume command",
        "",
        "```text",
        f"Take the repo. You are Worker {mission['defaultWorker']}. Take {mission['id']} and continue autonomously.",
        "```",
        "",
    ]
    return "\n".join(lines)


def schema_files() -> dict[str, str]:
    base = {"$schema": "https://json-schema.org/draft/2020-12/schema", "type": "object", "additionalProperties": True}
    return {
        "schemas/mission_registry.schema.json": canonical_json({**base, "required": ["schemaVersion", "missions"]}),
        "schemas/mission_state.schema.json": canonical_json({**base, "required": ["schemaVersion", "mission", "status"]}),
        "schemas/mission_claim.schema.json": canonical_json({**base, "required": ["schemaVersion", "mission", "worker", "branch"]}),
        "schemas/mission_checkpoint.schema.json": canonical_json({**base, "required": ["schemaVersion", "mission", "sequence", "nextAction"]}),
    }


def generated_files(model: dict[str, Any]) -> dict[str, str]:
    files: dict[str, str] = {}
    missions = model["missions"]
    claims = model["claimByMission"]
    registry_missions = []
    for mission in missions:
        task_count = sum(len(model["phases"][phase]["tasks"]) for phase in mission["phases"])
        registry_missions.append({
            **mission,
            "taskCount": task_count,
            "contract": f"docs/roadmap/missions/active/{mission['id']}.md",
            "state": f"docs/roadmap/missions/state/{mission['id']}.json",
            "activeClaim": claims.get(mission["id"]),
        })
        files[f"active/{mission['id']}.md"] = mission_markdown(model, mission)
        claim = claims.get(mission["id"])
        status = claim["status"] if claim else "AVAILABLE"
        state = {
            "schemaVersion": 1,
            "mission": mission["id"],
            "title": mission["title"],
            "status": status,
            "assignedWorker": claim["worker"] if claim else None,
            "current": claim["current"] if claim else "Await entry-dependency and ownership evaluation.",
            "branch": claim["branch"] if claim else None,
            "pullRequest": claim["pr"] if claim else None,
            "observedHead": claim["head"] if claim else None,
            "observedTree": claim.get("tree") if claim else None,
            "liveStateMustBeResolved": True,
            "nextAction": "Re-resolve live Git/PR/CI state, then continue the highest-priority dependency-satisfied task without restarting valid work." if claim else "Evaluate entry dependencies and create a collision-free claim.",
        }
        files[f"state/{mission['id']}.json"] = canonical_json(state)
        if claim:
            files[f"claims/{mission['id']}.claim.json"] = canonical_json({"schemaVersion": 1, **claim, "liveStateMustBeResolved": True})
            files[f"checkpoints/{mission['id']}-0001.json"] = canonical_json({
                "schemaVersion": 1,
                "mission": mission["id"],
                "sequence": 1,
                "worker": claim["worker"],
                "branch": claim["branch"],
                "pullRequest": claim["pr"],
                "observedHead": claim["head"],
                "observedTree": claim.get("tree"),
                "completed": ["Imported current worker branch, PR, exact-candidate narrative, blockers, and valid reusable work into mission state."],
                "validation": ["Mission generation and collision validation only; product claims remain unchanged."],
                "blockers": [claim["current"]],
                "nextAction": state["nextAction"],
                "supersededBy": None,
            })

    files["MISSION_REGISTRY.json"] = canonical_json({
        "schemaVersion": 1,
        "roadmapSource": model["config"]["authority"]["v32Source"],
        "authority": model["config"]["authority"],
        "missionCount": len(missions),
        "taskCount": len(model["tasks"]),
        "missions": registry_missions,
    })
    files["MISSION_DEPENDENCY_GRAPH.json"] = canonical_json({
        "schemaVersion": 1,
        "meaning": "Acyclic entry-frontier dependencies. Later exact cross-task dependencies are preserved in MISSION_INTERLOCKS.json.",
        "edges": model["entryEdges"],
    })
    files["MISSION_INTERLOCKS.json"] = canonical_json({"schemaVersion": 1, "count": len(model["interlocks"]), "interlocks": model["interlocks"]})
    files["ROADMAP_TASK_ASSIGNMENT.json"] = canonical_json({
        "schemaVersion": 1,
        "taskCount": len(model["tasks"]),
        "tasks": [model["tasks"][task_id] for task_id in sorted(model["tasks"])],
    })
    files["PHASE_INDEX.json"] = canonical_json({
        "schemaVersion": 1,
        "phases": [{"phase": phase, "mission": model["phaseOwner"][phase], **model["phases"][phase]} for phase in sorted(model["phases"], key=lambda value: int(value[1:]))],
    })
    files["CURRENT_REPO_STATE.json"] = canonical_json({"schemaVersion": 1, "discoveryAnchorsOnly": True, "claims": model["claims"]})

    dashboard = ["# Kristin mission execution dashboard", "", "All Git identities below are discovery anchors and must be re-resolved before writing.", "", "| Mission | Executor | Status | Phases | Current |", "|---|---|---|---|---|"]
    for mission in missions:
        claim = claims.get(mission["id"])
        dashboard.append(
            f"| `{mission['id']}` {mission['title']} | "
            f"{('Worker ' + claim['worker']) if claim else 'Unassigned'} | "
            f"`{claim['status'] if claim else 'AVAILABLE'}` | "
            f"{', '.join(mission['phases'])} | "
            f"{claim['current'] if claim else 'Await entry dependencies and claim'} |"
        )
    files["DASHBOARD.md"] = "\n".join(dashboard) + "\n"
    files["START_HERE.md"] = """# Mission execution — start here

1. Read `docs/roadmap/MASTER.md` and the declared scope of `docs/roadmap/roadmap.yaml`.
2. Run `python tool/mission_control.py --project . validate`.
3. Run `python tool/mission_control.py --project . status`.
4. Resume with `python tool/mission_control.py --project . resume --mission MISSION-004 --worker C`.
5. Re-resolve the branch, PR, exact head/tree, CI, reviews, dependencies, and path ownership before editing.
6. Update state and add a checkpoint after every significant push or before yield/transfer.

A worker is replaceable. The mission contract, state, claim, checkpoint, evidence, branch, PR, and exact CI are durable memory.
"""
    files["WORKER_COMMANDS.md"] = """# Worker mission commands

```text
Take the repo. You are Worker A. Take MISSION-001 and continue autonomously.
Take the repo. You are Worker B. Take MISSION-002 and continue autonomously.
Take the repo. You are Worker C. Take MISSION-004 and continue autonomously.
Take the repo. You are Worker D. Take MISSION-003 and continue autonomously.
Take the repo. You are Worker E. Take MISSION-010 and continue autonomously.
Take the repo. You are Worker F. Take MISSION-005 and continue autonomously.
Take the repo. You are Worker J. Take MISSION-015 and continue autonomously.
```

For transfer: the current executor records a final checkpoint, changes state to `YIELDED`, removes or supersedes the active claim, and names the exact next action. The replacement creates a new claim after collision and live-state validation.
"""
    files["COLLISION_AND_MERGE_POLICY.md"] = """# Mission collision and merge policy

- One active claim per mission; no silent takeover.
- Exclusive paths may not overlap across active claims.
- Shared authorities require an explicit coordination packet and owner review.
- Workers may commit, push, maintain draft PRs, and repair CI inside their claim.
- A worker may merge only when branch protection, required checks, mission validation, evidence, dependency gates, exact-SHA reviews, security boundaries, and the mission integration gate all pass.
- No mission grants a bypass of roadmap authority, Test Center authority, security review, platform truth, release truth, or GitHub rulesets.
- A changed exact head invalidates commit-bound review and evidence unless the governing contract explicitly proves otherwise.
"""
    files.update(schema_files())
    return files


def bootstrap(project: pathlib.Path, check: bool) -> None:
    model = build_model(project)
    desired = generated_files(model)
    output = project / OUTPUT_PATH
    mismatches = []
    for relative, content in desired.items():
        path = output / relative
        if check:
            if not path.is_file() or path.read_text(encoding="utf-8") != content:
                mismatches.append(path.relative_to(project).as_posix())
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
    if check and mismatches:
        raise ValueError("generated mission files differ: " + ", ".join(mismatches))
    print(f"mission bootstrap {'verified' if check else 'wrote'} {len(desired)} files")


def validate(project: pathlib.Path) -> None:
    model = build_model(project)
    if (project / OUTPUT_PATH).is_dir():
        bootstrap(project, check=True)
    source = model["config"]["authority"]["v32Source"]
    print(
        "MISSION_EXECUTION_VALID "
        f"phases={len(model['phases'])} tasks={len(model['tasks'])} "
        f"missions={len(model['missions'])} interlocks={len(model['interlocks'])} "
        f"claims={len(model['claims'])} roadmap_sha256={source['sha256']}"
    )


def status(project: pathlib.Path) -> None:
    model = build_model(project)
    for mission in model["missions"]:
        claim = model["claimByMission"].get(mission["id"])
        print(
            f"{mission['id']}\t{claim['status'] if claim else 'AVAILABLE'}\t"
            f"{('Worker ' + claim['worker']) if claim else 'UNASSIGNED'}\t"
            f"{','.join(mission['phases'])}\t{mission['title']}"
        )


def resume(project: pathlib.Path, mission_id: str, worker: str) -> None:
    model = build_model(project)
    mission = next((item for item in model["missions"] if item["id"] == mission_id), None)
    if mission is None:
        raise ValueError(f"unknown mission {mission_id}")
    claim = model["claimByMission"].get(mission_id)
    if claim and claim["worker"] != worker:
        raise ValueError(f"{mission_id} is actively claimed by Worker {claim['worker']}; record a yield/transfer before Worker {worker} resumes")
    print(f"MISSION: {mission_id} — {mission['title']}")
    print(f"EXECUTOR: Worker {worker}")
    print(f"CONTRACT: docs/roadmap/missions/active/{mission_id}.md")
    print(f"STATE: docs/roadmap/missions/state/{mission_id}.json")
    print(f"CLAIM: docs/roadmap/missions/claims/{mission_id}.claim.json" if claim else "CLAIM: create after dependency and collision validation")
    print("REQUIRED FIRST ACTION: re-resolve protected main, mission branch/PR/head/tree, CI, reviews, dependencies, and ownership")
    if claim:
        print(f"OBSERVED BRANCH: {claim['branch']}")
        print(f"OBSERVED PR: #{claim['pr']}")
        print(f"CURRENT: {claim['current']}")
    print("NEXT: continue the highest-priority dependency-satisfied task; reuse valid work; update state/checkpoint after the next significant push")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("validate")
    bootstrap_parser = subparsers.add_parser("bootstrap")
    bootstrap_parser.add_argument("--check", action="store_true")
    subparsers.add_parser("status")
    resume_parser = subparsers.add_parser("resume")
    resume_parser.add_argument("--mission", required=True)
    resume_parser.add_argument("--worker", required=True)
    args = parser.parse_args()
    project = pathlib.Path(args.project).resolve()
    try:
        if args.command == "validate":
            validate(project)
        elif args.command == "bootstrap":
            bootstrap(project, check=args.check)
        elif args.command == "status":
            status(project)
        elif args.command == "resume":
            resume(project, args.mission, args.worker)
        return 0
    except Exception as error:
        print(f"MISSION_EXECUTION_ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
