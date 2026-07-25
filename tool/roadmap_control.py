#!/usr/bin/env python3
"""Bootstrap roadmap control plane for Kristin P0/P1.

The roadmap manifest is intentionally encoded as the JSON subset of YAML 1.2.
This keeps the bootstrap validator dependency-free while preserving a .yaml
machine-authority path. P24 may migrate it to a richer YAML toolchain.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass, asdict
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Any, Iterable

ALLOWED_STATUSES = (
    "NOT_STARTED",
    "READY",
    "IN_PROGRESS",
    "BLOCKED",
    "REVIEW",
    "DONE",
    "DEFERRED",
)
TASK_ID_RE = re.compile(r"^P(?P<phase>[01])-(?P<number>[0-9]{3})$")
TASK_ROW_RE = re.compile(
    r"^\| `(?P<id>P[01]-[0-9]{3})` \| (?P<title>.*?) \| `(?P<deps>.*?)` \| "
    r"(?P<output>.*?) \| (?P<done>.*?) \|\s*$"
)
STATUS_START = "<!-- ROADMAP_STATUS_TABLE_START -->"
STATUS_END = "<!-- ROADMAP_STATUS_TABLE_END -->"
NEXT_START = "<!-- ROADMAP_NEXT_READY_START -->"
NEXT_END = "<!-- ROADMAP_NEXT_READY_END -->"


class RoadmapError(RuntimeError):
    pass


@dataclass(frozen=True)
class Issue:
    severity: str
    code: str
    message: str
    path: str | None = None
    task_id: str | None = None

    def as_dict(self) -> dict[str, object]:
        return asdict(self)


def _duplicate_guard(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise RoadmapError(f"duplicate JSON/YAML object key: {key}")
        result[key] = value
    return result


def load_json_yaml(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_duplicate_guard)
    except (OSError, json.JSONDecodeError, RoadmapError) as error:
        raise RoadmapError(f"cannot parse {path}: {error}") from error
    if not isinstance(value, dict):
        raise RoadmapError(f"manifest root must be an object: {path}")
    return value


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def normalized_cell(value: str) -> str:
    return re.sub(r"\s+", " ", value.replace("`", "")).strip()


def parse_dependency_cell(value: str) -> list[str]:
    normalized = value.strip()
    if normalized.lower() == "none":
        return []
    return [item.strip().strip("`") for item in normalized.split(",") if item.strip()]


def parse_master_tasks(text: str, phases: Iterable[str] = ("P0", "P1")) -> list[dict[str, Any]]:
    allowed = set(phases)
    tasks: list[dict[str, Any]] = []
    for line in text.splitlines():
        match = TASK_ROW_RE.match(line)
        if match is None:
            continue
        task_id = match.group("id")
        phase = task_id.split("-", 1)[0]
        if phase not in allowed:
            continue
        tasks.append(
            {
                "id": task_id,
                "phase": phase,
                "title": normalized_cell(match.group("title")),
                "dependsOn": parse_dependency_cell(match.group("deps")),
                "requiredOutput": normalized_cell(match.group("output")),
                "doneWhen": normalized_cell(match.group("done")),
            }
        )
    return tasks


def parse_master_version(text: str) -> str | None:
    match = re.search(r"\*\*Roadmap version:\*\* `([^`]+)`", text)
    return match.group(1) if match else None


def safe_relative(value: str) -> bool:
    if not value or "\\" in value:
        return False
    path = Path(value)
    return not path.is_absolute() and ".." not in path.parts and value == path.as_posix()


def task_map(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    raw_tasks = manifest.get("tasks")
    if not isinstance(raw_tasks, list):
        return result
    for item in raw_tasks:
        if isinstance(item, dict) and isinstance(item.get("id"), str):
            result.setdefault(str(item["id"]), item)
    return result


def graph_fingerprint(tasks: Iterable[dict[str, Any]]) -> str:
    normalized = [
        {
            "id": task.get("id"),
            "phase": task.get("phase"),
            "title": task.get("title"),
            "dependsOn": list(task.get("dependsOn") or []),
            "requiredOutput": task.get("requiredOutput"),
            "doneWhen": task.get("doneWhen"),
        }
        for task in tasks
    ]
    normalized.sort(key=lambda item: str(item["id"]))
    return sha256_text(canonical_json(normalized))


def cycle_nodes(tasks: dict[str, dict[str, Any]]) -> list[str]:
    state: dict[str, int] = {}
    stack: list[str] = []
    found: list[str] = []

    def visit(task_id: str) -> bool:
        state[task_id] = 1
        stack.append(task_id)
        for dep in tasks[task_id].get("dependsOn") or []:
            if dep not in tasks:
                continue
            if state.get(dep, 0) == 0:
                if visit(dep):
                    return True
            elif state.get(dep) == 1:
                start = stack.index(dep)
                found.extend(stack[start:] + [dep])
                return True
        stack.pop()
        state[task_id] = 2
        return False

    for task_id in sorted(tasks):
        if state.get(task_id, 0) == 0 and visit(task_id):
            break
    return found


def parse_status_table(text: str) -> tuple[dict[str, str], list[str]]:
    if STATUS_START not in text or STATUS_END not in text:
        raise RoadmapError("STATUS.md is missing machine table markers")
    body = text.split(STATUS_START, 1)[1].split(STATUS_END, 1)[0]
    statuses: dict[str, str] = {}
    for line in body.splitlines():
        line = line.strip()
        if not line.startswith("|") or line.startswith("|---") or "Task" in line:
            continue
        cells = [item.strip() for item in line.strip("|").split("|")]
        if len(cells) < 2 or not TASK_ID_RE.match(cells[0]):
            continue
        if cells[0] in statuses:
            raise RoadmapError(f"duplicate task in STATUS.md: {cells[0]}")
        statuses[cells[0]] = cells[1].strip("`")
    if NEXT_START not in text or NEXT_END not in text:
        raise RoadmapError("STATUS.md is missing next-ready markers")
    next_body = text.split(NEXT_START, 1)[1].split(NEXT_END, 1)[0]
    next_ready = re.findall(r"`(P[01]-[0-9]{3})`", next_body)
    return statuses, next_ready


def authority_declarations(project: Path) -> list[tuple[str, str]]:
    declarations: list[tuple[str, str]] = []
    roadmap_dir = project / "docs" / "roadmap"
    if not roadmap_dir.is_dir():
        return declarations
    pattern = re.compile(r"(?:\*\*)?Roadmap authority:(?:\*\*)?\s*`?([A-Z_]+)`?", re.I)
    for path in sorted(roadmap_dir.glob("*.md")):
        text = path.read_text(encoding="utf-8", errors="replace")
        match = pattern.search(text)
        if match:
            declarations.append((path.relative_to(project).as_posix(), match.group(1).upper()))
    return declarations


def _add(issues: list[Issue], condition: bool, code: str, message: str, *, path: str | None = None, task_id: str | None = None, severity: str = "error") -> None:
    if not condition:
        issues.append(Issue(severity, code, message, path, task_id))


def validate_manifest_data(
    manifest: dict[str, Any],
    *,
    project: Path | None = None,
    master_text: str | None = None,
    status_text: str | None = None,
    strict: bool = True,
) -> list[Issue]:
    issues: list[Issue] = []
    _add(issues, manifest.get("schemaVersion") == "1.0.0", "schema_version", "schemaVersion must be 1.0.0")
    _add(issues, manifest.get("format") == "yaml-1.2-json-subset", "manifest_format", "format must be yaml-1.2-json-subset")
    _add(issues, manifest.get("statusValues") == list(ALLOWED_STATUSES), "status_values", "statusValues must exactly match the canonical status list")
    authority = manifest.get("authority")
    _add(issues, isinstance(authority, dict), "authority_missing", "authority must be an object")
    if isinstance(authority, dict):
        _add(issues, authority.get("human") == "docs/roadmap/MASTER.md", "human_authority", "human authority must be docs/roadmap/MASTER.md")
        _add(issues, authority.get("machine") == "docs/roadmap/roadmap.yaml", "machine_authority", "machine authority must be docs/roadmap/roadmap.yaml")
        _add(issues, authority.get("scope") == ["P0", "P1"], "bootstrap_scope", "bootstrap scope must be exactly P0 and P1")

    raw_tasks = manifest.get("tasks")
    _add(issues, isinstance(raw_tasks, list) and bool(raw_tasks), "tasks_missing", "tasks must be a non-empty list")
    if not isinstance(raw_tasks, list):
        return issues

    seen: set[str] = set()
    tasks: dict[str, dict[str, Any]] = {}
    for index, task in enumerate(raw_tasks):
        if not isinstance(task, dict):
            issues.append(Issue("error", "task_not_object", f"tasks[{index}] must be an object"))
            continue
        task_id = task.get("id")
        if not isinstance(task_id, str) or not TASK_ID_RE.match(task_id):
            issues.append(Issue("error", "task_id_invalid", f"tasks[{index}].id is invalid: {task_id!r}"))
            continue
        if task_id in seen:
            issues.append(Issue("error", "task_id_duplicate", f"duplicate task ID: {task_id}", task_id=task_id))
            continue
        seen.add(task_id)
        tasks[task_id] = task
        expected_phase = task_id.split("-", 1)[0]
        _add(issues, task.get("phase") == expected_phase, "task_phase", f"{task_id} phase must be {expected_phase}", task_id=task_id)
        _add(issues, isinstance(task.get("title"), str) and bool(str(task.get("title")).strip()), "task_title", f"{task_id} title is required", task_id=task_id)
        status = task.get("status")
        _add(issues, status in ALLOWED_STATUSES, "task_status_invalid", f"{task_id} has invalid status {status!r}", task_id=task_id)
        deps = task.get("dependsOn")
        _add(issues, isinstance(deps, list) and all(isinstance(item, str) for item in deps), "task_dependencies_type", f"{task_id} dependsOn must be a string list", task_id=task_id)
        if isinstance(deps, list):
            _add(issues, len(deps) == len(set(deps)), "task_dependency_duplicate", f"{task_id} contains duplicate dependencies", task_id=task_id)
            _add(issues, task_id not in deps, "task_dependency_self", f"{task_id} depends on itself", task_id=task_id)
        packet = task.get("packet")
        _add(issues, isinstance(packet, str) and safe_relative(packet), "task_packet_path", f"{task_id} packet path is unsafe or missing", task_id=task_id)
        evidence = task.get("evidence")
        _add(issues, isinstance(evidence, list) and all(isinstance(item, str) and safe_relative(item) for item in evidence), "task_evidence_path", f"{task_id} evidence paths are invalid", task_id=task_id)
        if status == "BLOCKED":
            _add(issues, isinstance(task.get("blocker"), str) and bool(task.get("blocker", "").strip()), "blocked_without_reason", f"{task_id} is BLOCKED without a blocker", task_id=task_id)
        if status == "DEFERRED":
            _add(issues, isinstance(task.get("deferredReason"), str) and bool(task.get("deferredReason", "").strip()), "deferred_without_reason", f"{task_id} is DEFERRED without a reason", task_id=task_id)

    for task_id, task in tasks.items():
        for dep in task.get("dependsOn") or []:
            _add(issues, dep in tasks, "dependency_missing", f"{task_id} depends on missing task {dep}", task_id=task_id)
    cycle = cycle_nodes(tasks)
    _add(issues, not cycle, "dependency_cycle", f"dependency cycle: {' -> '.join(cycle)}" if cycle else "")

    for task_id, task in tasks.items():
        status = task.get("status")
        deps = [tasks[item] for item in task.get("dependsOn") or [] if item in tasks]
        deps_done = all(item.get("status") == "DONE" for item in deps)
        if status in {"READY", "IN_PROGRESS", "REVIEW", "DONE"}:
            _add(issues, deps_done, "dependency_not_done", f"{task_id} is {status} before all dependencies are DONE", task_id=task_id)
        if status == "READY":
            _add(issues, deps_done, "ready_inconsistent", f"{task_id} READY state is inconsistent", task_id=task_id)
        if status == "NOT_STARTED" and deps_done:
            issues.append(Issue("error" if strict else "warning", "ready_task_not_marked", f"{task_id} has completed dependencies and must be READY, BLOCKED, DEFERRED, IN_PROGRESS, REVIEW, or DONE", task_id=task_id))
        if status in {"DONE", "REVIEW"}:
            evidence = task.get("evidence") or []
            _add(issues, bool(evidence), "evidence_required", f"{task_id} {status} requires at least one evidence reference", task_id=task_id)

    expected_ready = sorted(task_id for task_id, task in tasks.items() if task.get("status") == "READY")
    _add(issues, manifest.get("nextReady") == expected_ready, "next_ready_mismatch", f"nextReady must be {expected_ready}")
    expected_order = sorted(tasks, key=lambda item: (int(item[1]), int(item.split("-")[1])))
    _add(issues, manifest.get("taskOrder") == expected_order, "task_order_mismatch", "taskOrder must contain every task in deterministic P0/P1 order")
    _add(issues, manifest.get("taskGraphSha256") == graph_fingerprint(tasks.values()), "task_graph_hash", "taskGraphSha256 does not match the task graph")

    if master_text is not None:
        master_version = parse_master_version(master_text)
        _add(issues, master_version == manifest.get("roadmapVersion"), "roadmap_version_conflict", f"MASTER roadmap version {master_version!r} does not match manifest {manifest.get('roadmapVersion')!r}", path="docs/roadmap/MASTER.md")
        master_tasks = parse_master_tasks(master_text)
        master_by_id = {item["id"]: item for item in master_tasks}
        _add(issues, set(master_by_id) == set(tasks), "master_task_scope_conflict", "MASTER and manifest P0/P1 task sets differ", path="docs/roadmap/MASTER.md")
        for task_id in sorted(set(master_by_id) & set(tasks)):
            source = master_by_id[task_id]
            target = tasks[task_id]
            for key in ("phase", "title", "dependsOn", "requiredOutput", "doneWhen"):
                _add(issues, target.get(key) == source.get(key), "master_task_conflict", f"{task_id} {key} conflicts with MASTER", path="docs/roadmap/MASTER.md", task_id=task_id)
        if isinstance(authority, dict):
            _add(issues, authority.get("masterSha256") == sha256_text(master_text), "master_hash_conflict", "authority.masterSha256 does not match MASTER.md", path="docs/roadmap/MASTER.md")

    if status_text is not None:
        try:
            status_rows, next_rows = parse_status_table(status_text)
        except RoadmapError as error:
            issues.append(Issue("error", "status_parse", str(error), "docs/roadmap/STATUS.md"))
        else:
            expected_statuses = {task_id: str(task.get("status")) for task_id, task in tasks.items()}
            _add(issues, status_rows == expected_statuses, "status_manifest_conflict", "STATUS.md does not match roadmap.yaml", path="docs/roadmap/STATUS.md")
            _add(issues, next_rows == expected_ready, "status_next_ready_conflict", "STATUS.md next-ready list does not match roadmap.yaml", path="docs/roadmap/STATUS.md")

    if project is not None:
        for task_id, task in tasks.items():
            packet = task.get("packet")
            if isinstance(packet, str) and safe_relative(packet):
                _add(issues, (project / packet).is_file(), "task_packet_missing", f"{task_id} packet does not exist: {packet}", path=packet, task_id=task_id)
            if task.get("status") in {"DONE", "REVIEW"}:
                for evidence in task.get("evidence") or []:
                    _add(issues, (project / evidence).is_file(), "evidence_missing", f"{task_id} evidence does not exist: {evidence}", path=evidence, task_id=task_id)
        declarations = authority_declarations(project)
        human = [path for path, kind in declarations if kind == "HUMAN_CONSTITUTION"]
        machine_derived = [path for path, kind in declarations if kind == "DERIVED"]
        _add(issues, human == ["docs/roadmap/MASTER.md"], "authority_conflict", f"exactly MASTER.md must declare HUMAN_CONSTITUTION; found {human}")
        _add(issues, "docs/roadmap/STATUS.md" in machine_derived, "status_authority_label", "STATUS.md must declare DERIVED", path="docs/roadmap/STATUS.md")

    return issues


def validate_project(project: Path, *, strict: bool = True) -> dict[str, Any]:
    project = project.resolve()
    manifest_path = project / "docs" / "roadmap" / "roadmap.yaml"
    master_path = project / "docs" / "roadmap" / "MASTER.md"
    status_path = project / "docs" / "roadmap" / "STATUS.md"
    missing = [path for path in (manifest_path, master_path, status_path) if not path.is_file()]
    if missing:
        issues = [Issue("error", "control_file_missing", f"missing control file: {path.relative_to(project)}", path.relative_to(project).as_posix()) for path in missing]
        return _report(project, {}, issues, strict)
    try:
        manifest = load_json_yaml(manifest_path)
    except RoadmapError as error:
        return _report(project, {}, [Issue("error", "manifest_parse", str(error), "docs/roadmap/roadmap.yaml")], strict)
    issues = validate_manifest_data(
        manifest,
        project=project,
        master_text=master_path.read_text(encoding="utf-8"),
        status_text=status_path.read_text(encoding="utf-8"),
        strict=strict,
    )
    return _report(project, manifest, issues, strict)


def _report(project: Path, manifest: dict[str, Any], issues: list[Issue], strict: bool) -> dict[str, Any]:
    errors = [item for item in issues if item.severity == "error" or (strict and item.severity == "warning")]
    warnings = [item for item in issues if item.severity == "warning"]
    tasks = task_map(manifest)
    ready = sorted(task_id for task_id, task in tasks.items() if task.get("status") == "READY")
    return {
        "schemaVersion": "1.0.0",
        "gateId": "p0-008-roadmap-control-plane",
        "project": "<ROOT>",
        "roadmapVersion": manifest.get("roadmapVersion"),
        "scope": manifest.get("authority", {}).get("scope") if isinstance(manifest.get("authority"), dict) else None,
        "strict": strict,
        "passed": not errors,
        "taskCount": len(tasks),
        "readyCount": len(ready),
        "nextReady": ready,
        "errorCount": len(errors),
        "warningCount": len(warnings),
        "issues": [item.as_dict() for item in issues],
    }


def render_status_text(manifest: dict[str, Any]) -> str:
    tasks = task_map(manifest)
    lines = [
        "# Kristin Production Roadmap Status",
        "",
        "**Roadmap authority:** `DERIVED`",
        "**Human constitution:** `docs/roadmap/MASTER.md`",
        "**Machine authority:** `docs/roadmap/roadmap.yaml`",
        f"**Roadmap version:** `{manifest.get('roadmapVersion')}`",
        "**Bootstrap scope:** `P0` and `P1`",
        "",
        "> This file is generated from `roadmap.yaml`. Edit task status in the manifest through a reviewed work packet, then regenerate this ledger. GitHub issues may mirror this state but are not authoritative.",
        "",
        "## Task ledger",
        "",
        STATUS_START,
        "| Task | Status | Dependencies | Packet | Evidence |",
        "|---|---|---|---|---|",
    ]
    for task_id in manifest.get("taskOrder") or sorted(tasks):
        task = tasks[task_id]
        deps = ", ".join(f"`{item}`" for item in task.get("dependsOn") or []) or "none"
        evidence = "<br>".join(f"`{item}`" for item in task.get("evidence") or []) or "none"
        lines.append(f"| {task_id} | {task.get('status')} | {deps} | `{task.get('packet')}` | {evidence} |")
    lines.extend([STATUS_END, "", "## Next ready tasks", "", NEXT_START])
    ready = manifest.get("nextReady") or []
    if ready:
        for task_id in ready:
            task = tasks[task_id]
            lines.append(f"- `{task_id}` — {task.get('title')} (`{task.get('packet')}`)")
    else:
        lines.append("- None. Resolve the blockers or complete the task currently in review.")
    lines.extend([NEXT_END, "", "## Review and blocked work", ""])
    selected = [task for task in tasks.values() if task.get("status") in {"IN_PROGRESS", "REVIEW", "BLOCKED"}]
    if selected:
        for task in sorted(selected, key=lambda item: str(item.get("id"))):
            detail = task.get("blocker") or "Complete the packet acceptance criteria and independent review."
            lines.append(f"- `{task['id']}` **{task['status']}** — {detail}")
    else:
        lines.append("- None.")
    lines.extend([
        "",
        "## Fresh-session command",
        "",
        "```bash",
        "python3 tool/roadmap_control.py validate --project . --strict",
        "python3 tool/roadmap_control.py next --project . --json",
        "```",
        "",
    ])
    return "\n".join(lines)


def render_handoff_text(manifest: dict[str, Any]) -> str:
    tasks = task_map(manifest)
    ready = manifest.get("nextReady") or []
    review = sorted(task_id for task_id, task in tasks.items() if task.get("status") in {"IN_PROGRESS", "REVIEW"})
    lines = [
        "# Kristin Roadmap Handoff",
        "",
        "**Roadmap authority:** `DERIVED`",
        f"**Roadmap version:** `{manifest.get('roadmapVersion')}`",
        "",
        "## Startup sequence for a new AI session",
        "",
        "1. Read `docs/roadmap/MASTER.md`.",
        "2. Run `python3 tool/roadmap_control.py validate --project . --strict`.",
        "3. Run `python3 tool/roadmap_control.py next --project . --json`.",
        "4. Read the selected task packet, relevant ADRs, current risks, metrics, and evidence.",
        "5. Execute one task only and stop after writing evidence and updating the manifest.",
        "",
        "## Current review work",
        "",
    ]
    if review:
        for task_id in review:
            task = tasks[task_id]
            lines.append(f"- `{task_id}` — {task.get('title')} (`{task.get('packet')}`)")
    else:
        lines.append("- None.")
    lines.extend(["", "## Next ready tasks", ""])
    if ready:
        for task_id in ready:
            task = tasks[task_id]
            lines.append(f"- `{task_id}` — {task.get('title')} (`{task.get('packet')}`)")
    else:
        lines.append("- None.")
    lines.extend([
        "",
        "## Non-negotiable handoff rules",
        "",
        "- Never infer task completion from chat history.",
        "- Never mark `DONE` without the task's declared evidence and an independent review where required.",
        "- Never treat `STATUS.md` as independently editable authority; it must match `roadmap.yaml`.",
        "- Never begin P1 implementation while P0-008 remains `REVIEW`.",
        "- P24, not P0-008, owns the future all-task split, claim traceability, and bounded context-pack system.",
        "",
    ])
    return "\n".join(lines)


def command_validate(args: argparse.Namespace) -> int:
    report = validate_project(Path(args.project), strict=args.strict)
    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(f"Roadmap control: {'PASS' if report['passed'] else 'FAIL'}")
        print(f"Tasks: {report['taskCount']}  Ready: {report['readyCount']}  Errors: {report['errorCount']}  Warnings: {report['warningCount']}")
        for issue in report["issues"]:
            print(f"[{issue['severity'].upper()}] {issue['code']}: {issue['message']}")
        if report["nextReady"]:
            print("Next ready: " + ", ".join(report["nextReady"]))
    return 0 if report["passed"] else 1


def command_next(args: argparse.Namespace) -> int:
    project = Path(args.project).resolve()
    report = validate_project(project, strict=True)
    if not report["passed"]:
        print(json.dumps(report, indent=2, sort_keys=True) if args.json else "Roadmap is invalid; run validate.")
        return 1
    manifest = load_json_yaml(project / "docs/roadmap/roadmap.yaml")
    tasks = task_map(manifest)
    ready = [
        {
            "id": task_id,
            "title": tasks[task_id].get("title"),
            "packet": tasks[task_id].get("packet"),
            "requiredOutput": tasks[task_id].get("requiredOutput"),
            "doneWhen": tasks[task_id].get("doneWhen"),
        }
        for task_id in manifest.get("nextReady") or []
    ]
    payload = {"roadmapVersion": manifest.get("roadmapVersion"), "ready": ready}
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        for item in ready:
            print(f"{item['id']} — {item['title']} — {item['packet']}")
    return 0


def command_explain(args: argparse.Namespace) -> int:
    project = Path(args.project).resolve()
    report = validate_project(project, strict=True)
    if not report["passed"]:
        print("Roadmap is invalid; run validate.", file=sys.stderr)
        return 1
    manifest = load_json_yaml(project / "docs/roadmap/roadmap.yaml")
    tasks = task_map(manifest)
    task = tasks.get(args.task_id)
    if task is None:
        print(f"Unknown task: {args.task_id}", file=sys.stderr)
        return 2
    print(json.dumps(task, indent=2, sort_keys=True) if args.json else "\n".join([
        f"{task['id']} — {task['title']}",
        f"Status: {task['status']}",
        f"Dependencies: {', '.join(task.get('dependsOn') or []) or 'none'}",
        f"Packet: {task['packet']}",
        f"Required output: {task['requiredOutput']}",
        f"Done when: {task['doneWhen']}",
    ]))
    return 0


def command_render(args: argparse.Namespace) -> int:
    project = Path(args.project).resolve()
    manifest = load_json_yaml(project / "docs/roadmap/roadmap.yaml")
    status = render_status_text(manifest)
    handoff = render_handoff_text(manifest)
    if args.check:
        failures = []
        if (project / "docs/roadmap/STATUS.md").read_text(encoding="utf-8") != status:
            failures.append("docs/roadmap/STATUS.md")
        if (project / "docs/roadmap/HANDOFF.md").read_text(encoding="utf-8") != handoff:
            failures.append("docs/roadmap/HANDOFF.md")
        if failures:
            print("Generated control files are stale: " + ", ".join(failures), file=sys.stderr)
            return 1
        print("Generated roadmap control files are current.")
        return 0
    (project / "docs/roadmap/STATUS.md").write_text(status, encoding="utf-8")
    (project / "docs/roadmap/HANDOFF.md").write_text(handoff, encoding="utf-8")
    print("Rendered STATUS.md and HANDOFF.md.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    validate = sub.add_parser("validate")
    validate.add_argument("--project", default=".")
    validate.add_argument("--strict", action="store_true")
    validate.add_argument("--json", action="store_true")
    validate.set_defaults(handler=command_validate)
    next_parser = sub.add_parser("next")
    next_parser.add_argument("--project", default=".")
    next_parser.add_argument("--json", action="store_true")
    next_parser.set_defaults(handler=command_next)
    explain = sub.add_parser("explain")
    explain.add_argument("task_id")
    explain.add_argument("--project", default=".")
    explain.add_argument("--json", action="store_true")
    explain.set_defaults(handler=command_explain)
    render = sub.add_parser("render")
    render.add_argument("--project", default=".")
    render.add_argument("--check", action="store_true")
    render.set_defaults(handler=command_render)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    return int(args.handler(args))


if __name__ == "__main__":
    raise SystemExit(main())
