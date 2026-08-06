#!/usr/bin/env python3
"""Materialize the bounded Worker A P2-004 repair into an artifact checkout."""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
TEMP_SCRIPT = ROOT / "tool/_temp_materialize_p2_004_patch.py"
TEMP_WORKFLOW = ROOT / ".github/workflows/temp-worker-a-p2-004-patch-artifact.yml"


def replace_once(path: pathlib.Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"{path.relative_to(ROOT)}: expected one replacement target, found {count}"
        )
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def add_unique(values: list[str], additions: list[str]) -> None:
    for value in additions:
        if value not in values:
            values.append(value)


def patch_environment() -> None:
    replace_once(
        ROOT / "tool/p2_task_platform_assertions.py",
        '        "KRISTIN_P2_COMMIT_SHA", "GITHUB_RUN_ID", "GITHUB_JOB", "RUNNER_NAME",\n',
        '        "KRISTIN_P2_COMMIT_SHA",\n'
        '        "KRISTIN_P2_TECH_NODE_RECEIPT",\n'
        '        "KRISTIN_P2_TECH_NATIVE_RECEIPT",\n'
        '        "KRISTIN_P2_TECH_DART_RECEIPT",\n'
        '        "GITHUB_RUN_ID", "GITHUB_JOB", "RUNNER_NAME",\n',
    )


def patch_cli() -> None:
    replace_once(
        ROOT / "tool/p2_task_assertion_cli_test.py",
        '    print("P2 task assertion CLI all-task execution: PASS")\n'
        '    print(json.dumps(summaries, sort_keys=True))\n',
        '    technology_contract = root / "tool/p2_technology_spike_contract_test.py"\n'
        '    if not technology_contract.is_file():\n'
        '        raise SystemExit("P2-004 technology-spike contract regression missing")\n'
        '    technology = subprocess.run(\n'
        '        [sys.executable, str(technology_contract), "--project", str(root)],\n'
        '        text=True,\n'
        '        capture_output=True,\n'
        '        timeout=300,\n'
        '    )\n'
        '    if technology.returncode != 0:\n'
        '        raise SystemExit(\n'
        '            "P2-004 technology-spike contract regression failed\\n"\n'
        '            f"stdout={technology.stdout[-4000:]}\\n"\n'
        '            f"stderr={technology.stderr[-4000:]}"\n'
        '        )\n'
        '\n'
        '    print("P2 task assertion CLI all-task execution: PASS")\n'
        '    print(json.dumps(summaries, sort_keys=True))\n'
        '    print(technology.stdout.strip())\n',
    )


def patch_template() -> None:
    path = ROOT / "docs/operations/P2_TECHNOLOGY_CANDIDATE_RECEIPT_TEMPLATE.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    rounds = data.get("rounds")
    if not isinstance(rounds, list) or len(rounds) != 1:
        raise SystemExit("candidate receipt template historical shape drift")
    rows = []
    for number in (1, 2, 3):
        row = json.loads(json.dumps(rounds[0]))
        row["roundId"] = number
        row["evidencePath"] = f"round-{number}.json"
        rows.append(row)
    data["rounds"] = rows
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def patch_registry() -> None:
    path = ROOT / "config/test_center_registry.v1.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    mapping = next(
        row
        for row in data["affectedTestMappings"]
        if row["mappingId"] == "affected.p2.owner-mode-source"
    )
    add_unique(
        mapping["pathPatterns"],
        [
            "docs/operations/P2_TECHNOLOGY_CANDIDATE_RECEIPT_TEMPLATE.json",
            ".github/workflows/worker-a-p2-004-measurement-contract.yml",
        ],
    )
    profile = next(
        row
        for row in data["projectTestProfiles"]
        if row["stableCheckId"] == "tc.p2.acceptance-contract"
    )
    bound = [
        "tool/p2_task_platform_assertions.py",
        "tool/p2_technology_spike.py",
        "tool/p2_technology_spike_contract_test.py",
        "docs/operations/P2_TECHNOLOGY_CANDIDATE_RECEIPT_TEMPLATE.json",
        ".github/workflows/p2-owner-mode.yml",
        ".github/workflows/worker-a-p2-004-measurement-contract.yml",
    ]
    add_unique(profile["affectedPaths"], bound)
    add_unique(profile["inputPaths"], bound)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    patch_environment()
    patch_cli()
    patch_template()
    patch_registry()
    for temporary in (TEMP_SCRIPT, TEMP_WORKFLOW):
        if temporary.exists():
            temporary.unlink()
    subprocess.run(
        [sys.executable, str(ROOT / "tool/p1a_refresh_source_manifest.py"), "."],
        cwd=ROOT,
        check=True,
    )
    print("Worker A P2-004 repair artifact materialized")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
