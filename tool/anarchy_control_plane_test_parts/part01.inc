#!/usr/bin/env python3
"""Deterministic P24-001 ANARCHY control-plane regression suite."""
from __future__ import annotations

import copy
from contextlib import contextmanager
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).with_name("anarchy_control_plane.py")
ROOT = MODULE_PATH.parent.parent
FIXTURES = ROOT / "test/anarchy_control_plane/fixtures"

spec = importlib.util.spec_from_file_location("anarchy_control_plane", MODULE_PATH)
assert spec is not None and spec.loader is not None
acp = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = acp
spec.loader.exec_module(acp)


def canonical(value: object) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def write(path: Path, content: str | bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(content, bytes):
        path.write_bytes(content)
    else:
        path.write_text(content, encoding="utf-8", newline="\n")


def read_json(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: object) -> None:
    write(path, canonical(value))


def run(*args: str, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)


def task_count_for_phase(number: int) -> int:
    return 15 if number <= 8 else 14


def phase_name(number: int) -> str:
    return f"P{number:02d}-phase-{number:02d}.md"


def task_id(phase: int, number: int) -> str:
    return f"P{phase}-{number:03d}"


def make_phase(number: int) -> str:
    phase = f"P{number}"
    rows: list[str] = []
    for item in range(1, task_count_for_phase(number) + 1):
        current = task_id(number, item)
        if number == 0 and item == 1:
            deps = "none"
        elif item == 1:
            deps = task_id(number - 1, 1)
        else:
            deps = task_id(number, item - 1)
        rows.append(
            f"| `{current}` | Task {current} | `{deps}` | Required output for {current}. | Acceptance criteria for {current}. |"
        )
    return "\n".join(
        [
            "---",
            f"phase: {phase}",
            f'title: "Synthetic phase {phase}"',
            "execution_view_status: PROPOSAL",
            "primary_workers: [J]",
            'test_center_module: "External Worker B reference"',
            "source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md",
            "live_authority: ../../MASTER.md",
            "---",
            "",
            f"# {phase}",
            "",
            "## Task backlog",
            "",
            acp.TASK_TABLE_HEADER,
            acp.TASK_TABLE_SEPARATOR,
            *rows,
            "",
            "## Test Center deliverables",
            "",
            "Worker B owns canonical horizontal testing contracts.",
            "",
        ]
    )


def make_worker(letter: str) -> str:
    return "\n".join(
        [
            "---",
            f"worker: {letter}",
            f'role: "Synthetic Worker {letter}"',
            "status: READY",
            f'branch: "agent/{letter.lower()}/synthetic"',
            f'active_task: "Synthetic lane {letter}"',
            'last_anchor: "none"',
            'reviewer: "Worker B"',
            "---",
            "",
            f"# Worker {letter}",
            "",
            "## Phase lane",
            "",
            f"- [`P24`](../phases/{phase_name(24)}) — Synthetic P24",
            "",
            "## Exact next actions",
            "",
            "1. Resolve live state.",
            "",
        ]
    )


def synthetic_source_policy() -> str:
    return """#!/usr/bin/env python3\nfrom __future__ import annotations\n\ndef is_generated_path(relative):\n    value=str(relative).replace('\\\\','/').lower()\n    return '/__pycache__/' in '/'+value or value.endswith(('.pyc','.pyo')) or value.startswith('.git/')\n"""


def synthetic_manifest_generator() -> str:
    return """#!/usr/bin/env python3\nfrom __future__ import annotations\nimport hashlib,importlib.util,pathlib,subprocess,sys\nroot=pathlib.Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()\npath=root/'tool/source_tree_policy.py'\nspec=importlib.util.spec_from_file_location('policy',path);policy=importlib.util.module_from_spec(spec);spec.loader.exec_module(policy)\nraw=subprocess.check_output(['git','-C',str(root),'ls-files','--cached','--others','--exclude-standard','-z'])\npaths=sorted({x.decode('utf-8',errors='surrogateescape').replace('\\\\','/') for x in raw.split(b'\\0') if x})\nlines=[]\nfor rel in paths:\n    if rel=='SOURCE_MANIFEST.sha256' or policy.is_generated_path(rel): continue\n    p=root/rel\n    if p.is_file(): lines.append(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {rel}')\n(root/'SOURCE_MANIFEST.sha256').write_text('\\n'.join(lines)+'\\n',encoding='utf-8',newline='\\n')\n"""


def valid_directives() -> dict[str, object]:
    return {
        "schemaVersion": "1.0.0",
        "classification": "PROPOSED_RECONCILIATION_DECISIONS_NOT_TASK_STATUS_AUTHORITY",
        "directives": [
            {
                "id": f"ANARCHY-DIR-{index:03d}",
                "source": f"docs/roadmap/anarchy/source#{index}",
                "repositoryEquivalent": "synthetic equivalent",
                "decision": "ACCEPT_WITH_CHANGES",
                "rationale": "Synthetic bounded decision.",
                "dependency": "P24-001 adoption review",
                "affected": [],
                "migrationAction": "Validate without promoting authority.",
                "rollbackAction": "Remove generated proposal view.",
                "validation": "deterministic fixture",
            }
            for index in range(1, 16)
        ],
    }


def valid_ledger() -> dict[str, object]:
    return {
        "schemaVersion": "1.0.0",
        "classification": "APPEND_ONLY_MIGRATION_OBSERVATION_NOT_TASK_STATUS_AUTHORITY",
        "task": "P24-001",
        "worker": "J",
        "events": [
            {
                "sequence": 1,
                "kind": "LIVE_BASELINE",
                "evidence": "docs/roadmap/anarchy/migration/BASELINE.json",
            }
        ],
        "pending": ["Worker B exact-head review", "Worker I exact-head review"],
    }


def valid_claim() -> dict[str, object]:
    return {
        "schemaVersion": "1.0.0",
        "recordType": "AnarchyClaim",
        "task": "P24-001",
        "worker": "J",
        "state": "CLAIMED",
        "branch": "agent/j/P24-001-roadmap-as-data-adr",
        "base": {"commit": "1" * 40, "tree": "2" * 40},
        "claimedPaths": ["docs/roadmap/anarchy/migration/**", "tool/anarchy_control_plane.py"],
        "sharedContracts": ["docs/roadmap/anarchy/migration/**"],
        "reviewerRoles": ["Worker B", "Worker I"],
        "nextAction": "Push the complete candidate and open the stacked draft PR.",
        "continuity": {
            "lastVerifiedHead": "3" * 40,
            "lastVerifiedTree": "4" * 40,
            "safeTakeover": "Only after a bound yield.",
        },
    }


def valid_checkpoint() -> dict[str, object]:
    workers: list[dict[str, object]] = []
    for index in range(10):
        letter = chr(ord("A") + index)
        workers.append(
            {
                "worker": letter,
                "state": "ACTIVE" if letter in {"C", "J"} else "READY",
                "lane": f"Synthetic lane {letter}",
                "taskOrHoldReason": f"Synthetic task {letter}",
                "branch": f"agent/{letter.lower()}/synthetic",
                "base": {"commit": "NOT_CREATED", "tree": "NOT_CREATED"},
                "ownedPaths": [f"synthetic/{letter}/**"],
                "forbiddenPaths": ["product/runtime/**"],
                "sharedContracts": [f"synthetic-contract-{letter}"],
                "reviewer": "Worker B",
                "dependency": "Synthetic dependency statement.",
                "nextAction": f"Continue synthetic Worker {letter} lane.",
            }
        )
    return {
        "schemaVersion": "1.0.0",
        "recordType": "WorkerCoordinationCheckpoint",
        "classification": "ADOPTION_REVIEW_COORDINATION_NOT_TASK_AUTHORITY",
        "workers": workers,
    }


def build_contract() -> dict[str, object]:
    source = read_json(ROOT / acp.CONTRACT_PATH)
    # Keep the production contract shape but point evidence at synthetic files.
    result = copy.deepcopy(source)
    result["taskRecords"] = [
        {
            "task": "P24-001",
            "roadmapStatus": "IN_PROGRESS",
            "workerRuntimeStatus": "VERIFYING",
            "testExecutionResult": "PASS",
            "certificationStatus": "PARTIAL",
            "capabilitySupportStatus": "SOURCE_FOUNDATION",
            "completionClaim": False,
            "evidenceBindings": [
                {"path": "docs/roadmap/anarchy/migration/P24-001_RECONCILIATION_ADR.md", "classification": "SOURCE_FOUNDATION"}
            ],
        },
        {
            "task": "P2-001",
            "roadmapStatus": "IN_PROGRESS",
            "workerRuntimeStatus": "CAPABILITY_BLOCKED",
            "testExecutionResult": "PASS",
            "certificationStatus": "PARTIAL",
            "capabilitySupportStatus": "SOURCE_FOUNDATION",
            "completionClaim": False,
            "evidenceBindings": [
                {"path": "docs/roadmap/anarchy/migration/BASELINE.json", "classification": "SOURCE_ONLY"},
                {"path": "docs/roadmap/anarchy/migration/BASELINE.json", "classification": "HOSTED_CI"},
            ],
        },
    ]
    return result


def initialize_git(root: Path) -> None:
    run("git", "init", "-q", cwd=root)
    run("git", "config", "user.name", "P24 Test", cwd=root)
    run("git", "config", "user.email", "p24@example.invalid", cwd=root)


def commit_all(root: Path, message: str = "fixture") -> None:
    run("git", "add", ".", cwd=root)
    run("git", "commit", "-q", "-m", message, cwd=root)

