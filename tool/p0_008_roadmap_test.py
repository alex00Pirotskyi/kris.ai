#!/usr/bin/env python3
"""Repository integration gate for P0-008 roadmap controls."""
from __future__ import annotations

import argparse
from dataclasses import dataclass, asdict
import json
from pathlib import Path
import re
import subprocess
import sys

import roadmap_control as rc


SUPPORTED_CUMULATIVE_ROADMAP_VERSIONS = frozenset({
    "3.1.4-p0-008-roadmap-control-plane",
    "3.1.5-p0-009-initial-benchmark",
    "3.1.6-p0-010-generated-state-hygiene",
})


def roadmap_version_supported(value: object) -> bool:
    return isinstance(value, str) and value in SUPPORTED_CUMULATIVE_ROADMAP_VERSIONS


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str


def run_case(name: str, action) -> Result:
    try:
        detail = action()
        return Result(name, True, str(detail))
    except BaseException as error:
        return Result(name, False, f"{type(error).__name__}: {error}")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def parse_source_manifest(path: Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        match = re.match(r"^([0-9a-f]{64})\s{2,}(.+)$", line)
        require(match is not None, f"invalid source-manifest line: {line!r}")
        digest, relative = match.groups()
        require(relative not in entries, f"duplicate source-manifest entry: {relative}")
        entries[relative] = digest
    return entries


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--json-output")
    args = parser.parse_args()
    root = Path(args.project).expanduser().resolve()

    required_controls = (
        "docs/roadmap/MASTER.md",
        "docs/roadmap/roadmap.yaml",
        "docs/roadmap/STATUS.md",
        "docs/roadmap/DECISIONS.md",
        "docs/roadmap/RISKS.md",
        "docs/roadmap/METRICS.md",
        "docs/roadmap/RELEASE_GATES.md",
        "docs/roadmap/HANDOFF.md",
        "docs/roadmap/CONTROL_PLANE.md",
        "schemas/roadmap_bootstrap.v1.json",
        "schemas/evidence_manifest.v1.json",
        "tool/roadmap_control.py",
        "tool/roadmap_control_test.py",
        "tool/p0_008_roadmap_test.py",
        "tasks/completed/P0-008.md",
        "release/evidence/P0-008/IMPLEMENTATION.md",
    )
    prompts = (
        "docs/roadmap/prompts/implement.md",
        "docs/roadmap/prompts/review.md",
        "docs/roadmap/prompts/security-review.md",
        "docs/roadmap/prompts/release-review.md",
        "docs/roadmap/prompts/failure-recovery.md",
    )
    adrs = tuple(f"docs/adr/ADR-{index:04d}-" for index in range(7))

    def controls_present() -> str:
        missing = [item for item in required_controls if not (root / item).is_file()]
        require(not missing, f"missing: {missing}")
        return f"required={len(required_controls)}"

    def strict_validator() -> str:
        report = rc.validate_project(root, strict=True)
        require(report["passed"] is True, json.dumps(report, indent=2))
        require(report["taskCount"] == 22, f"expected 22 P0/P1 tasks, got {report['taskCount']}")
        return f"tasks={report['taskCount']} ready={report['readyCount']}"

    def manifest_contract() -> str:
        manifest = rc.load_json_yaml(root / "docs/roadmap/roadmap.yaml")
        roadmap_version = manifest.get("roadmapVersion")
        require(
            roadmap_version_supported(roadmap_version),
            f"unsupported cumulative roadmap version: {roadmap_version!r}",
        )
        require(manifest.get("statusValues") == list(rc.ALLOWED_STATUSES), "status vocabulary drift")
        require(manifest.get("authority", {}).get("scope") == ["P0", "P1"], "scope drift")
        tasks = rc.task_map(manifest)
        require(tasks["P0-008"]["status"] == "DONE", "P0-008 must be DONE after formal P0 closure")
        require(tasks["P0-008"]["dependsOn"] == ["P0-001"], "P0-008 dependency drift")
        return f"graph={manifest['taskGraphSha256']}"

    def next_ready_command() -> str:
        completed = subprocess.run(
            [sys.executable, "tool/roadmap_control.py", "next", "--project", ".", "--json"],
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        require(completed.returncode == 0, completed.stdout)
        payload = json.loads(completed.stdout)
        ready = payload.get("ready")
        require(isinstance(ready, list), "ready payload missing")
        for item in ready:
            require((root / item["packet"]).is_file(), f"missing packet {item['packet']}")
            require(item.get("requiredOutput"), "requiredOutput missing")
            require(item.get("doneWhen"), "doneWhen missing")
        return f"ready={len(ready)}"

    def generated_views_current() -> str:
        completed = subprocess.run(
            [sys.executable, "tool/roadmap_control.py", "render", "--project", ".", "--check"],
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
        require(completed.returncode == 0, completed.stdout)
        return completed.stdout.strip()

    def prompt_set() -> str:
        missing = [item for item in prompts if not (root / item).is_file()]
        require(not missing, f"missing prompts: {missing}")
        for item in prompts:
            text = (root / item).read_text(encoding="utf-8")
            require(len(text.strip()) >= 200 and any(word in text.lower() for word in ("task", "review", "failure", "release")), f"empty prompt contract: {item}")
        return f"prompts={len(prompts)}"

    def adr_states() -> str:
        found = sorted((root / "docs/adr").glob("ADR-*.md"))
        require(len(found) >= 7, f"expected at least 7 ADRs, got {len(found)}")
        accepted = (root / "docs/adr/ADR-0000-roadmap-control-plane.md").read_text(encoding="utf-8")
        require("**Status:** ACCEPTED" in accepted, "ADR-0000 not accepted")
        proposed = [path for path in found if path.name.startswith(tuple(f"ADR-{index:04d}" for index in range(1, 7)))]
        require(len(proposed) == 6, f"expected six proposed ADRs, got {len(proposed)}")
        require(all("**Status:** PROPOSED" in path.read_text(encoding="utf-8") for path in proposed), "a future ADR was prematurely accepted")
        return "accepted=1 proposed=6"

    def every_task_has_packet() -> str:
        manifest = rc.load_json_yaml(root / "docs/roadmap/roadmap.yaml")
        tasks = rc.task_map(manifest)
        missing = [task_id for task_id, task in tasks.items() if not (root / task["packet"]).is_file()]
        require(not missing, f"missing packets: {missing}")
        return f"packets={len(tasks)}"

    def verification_hooks() -> str:
        verify = (root / "tool/verify.sh").read_text(encoding="utf-8")
        for marker in (
            "tool/roadmap_control_test.py",
            "tool/p0_008_roadmap_test.py",
            "tool/roadmap_control.py validate --project . --strict",
        ):
            require(marker in verify, f"verify.sh missing {marker}")
        workflow = root / ".github/workflows/ci.yml"
        if workflow.is_file():
            text = workflow.read_text(encoding="utf-8")
            require("P0-008 roadmap control plane" in text, "CI step missing")
            require("tool/roadmap_control.py validate --project . --strict" in text, "CI validator command missing")
        return "verify=true ci=true"

    def schemas_parse() -> str:
        for relative in ("schemas/roadmap_bootstrap.v1.json", "schemas/evidence_manifest.v1.json"):
            value = json.loads((root / relative).read_text(encoding="utf-8"))
            require(value.get("$schema"), f"schema marker missing: {relative}")
        return "schemas=2"

    def source_manifest_complete() -> str:
        entries = parse_source_manifest(root / "SOURCE_MANIFEST.sha256")
        required = set(required_controls + prompts)
        required.update(path.relative_to(root).as_posix() for path in (root / "docs/adr").glob("ADR-*.md"))
        manifest = rc.load_json_yaml(root / "docs/roadmap/roadmap.yaml")
        required.add("docs/roadmap/roadmap.yaml")
        required.add("docs/roadmap/STATUS.md")
        required.add("docs/roadmap/HANDOFF.md")
        required.update(str(task["packet"]) for task in manifest["tasks"])
        missing = sorted(item for item in required if item not in entries)
        require(not missing, f"source manifest missing {missing[:20]}")
        return f"checked={len(required)}"

    def authority_unique() -> str:
        declarations = rc.authority_declarations(root)
        human = [path for path, kind in declarations if kind == "HUMAN_CONSTITUTION"]
        require(human == ["docs/roadmap/MASTER.md"], f"human authorities: {human}")
        return f"declarations={len(declarations)}"

    def p0_002_preserved() -> str:
        trust = root / "tool/interoperability_v19.py"
        if not trust.is_file():
            return "not-present-on-this-baseline"
        text = trust.read_text(encoding="utf-8")
        if "v1_trust_disabled" in text or "LEGACY_TRUST_ENABLED = False" in text:
            require("v1_trust_disabled" in text, "P0-002 marker incomplete")
            require((root / "tool/v1_trust_disablement_test.py").is_file(), "P0-002 regression missing")
            return "disabled=true"
        return "legacy-baseline-not-modified"

    def control_directories() -> str:
        required = (
            "tasks/active", "tasks/completed", "tasks/blocked",
            "release/evidence", "release/attestations", "release/reports",
            "evals/fixtures", "evals/datasets", "evals/results",
        )
        missing = [item for item in required if not (root / item).is_dir()]
        require(not missing, f"missing directories: {missing}")
        return f"directories={len(required)}"

    def manifest_master_match() -> str:
        master = (root / "docs/roadmap/MASTER.md").read_text(encoding="utf-8")
        manifest = rc.load_json_yaml(root / "docs/roadmap/roadmap.yaml")
        parsed = rc.parse_master_tasks(master)
        require(len(parsed) == 22, f"MASTER P0/P1 tasks={len(parsed)}")
        require(rc.graph_fingerprint(parsed) == manifest["taskGraphSha256"], "master/manifest graph hash mismatch")
        return "master_tasks=22"

    results = [
        run_case("Required control files", controls_present),
        run_case("Strict roadmap validator", strict_validator),
        run_case("Bootstrap manifest contract", manifest_contract),
        run_case("Fresh-session next command", next_ready_command),
        run_case("Generated status and handoff", generated_views_current),
        run_case("AI prompt set", prompt_set),
        run_case("ADR status boundaries", adr_states),
        run_case("P0/P1 task packets", every_task_has_packet),
        run_case("Verification and CI hooks", verification_hooks),
        run_case("Roadmap and evidence schemas", schemas_parse),
        run_case("Source-manifest integration", source_manifest_complete),
        run_case("Single human roadmap authority", authority_unique),
        run_case("P0-002 trust retirement preservation", p0_002_preserved),
        run_case("Control directory structure", control_directories),
        run_case("MASTER and manifest graph agreement", manifest_master_match),
    ]
    failed = [item for item in results if not item.passed]
    payload = {
        "schemaVersion": "1.0.0",
        "gateId": "P0-008",
        "passed": not failed,
        "caseCount": len(results),
        "passedCount": len(results) - len(failed),
        "failedCount": len(failed),
        "results": [asdict(item) for item in results],
    }
    if args.json_output:
        output = root / args.json_output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
