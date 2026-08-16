#!/usr/bin/env python3
"""Forward-port the canonical P2 promotion-state gate onto current main."""
from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BRANCH = "agent/gpt-gold/gs-003c-p2-promotion-current-main"
BASE = "e4f66ce5a95870cad342bbf9aaf89f94dc768f58"
BASE_TREE = "db4c9218c6180d9b3613e6635d6213c85f49d9cd"
WORKFLOW = Path(".github/workflows/temp-gs003-p2-promotion-current-main.yml")
SCRIPT = Path("tool/temp_gs003_p2_promotion_current_main.py")
GATE = Path("tool/v71r12_exact_source_gate.py")
TEST = Path("tool/p2_promotion_state_test.py")
FINAL_PATHS = {
    "SOURCE_MANIFEST.sha256",
    GATE.as_posix(),
    TEST.as_posix(),
}
START_ANCHOR = (
    '        aggregate = load_json(project / "release/evidence/P2/manifest.json")\n'
)
END_ANCHOR = (
    '            step("P2 source-only exit", '
    '(python, "tool/p2_exit_gate_test.py", "--project", ".", "--source-only"), '
    'timeout=1800)\n'
)
REPLACEMENT = '''        aggregate = load_json(project / "release/evidence/P2/manifest.json")
        if aggregate.get("completionClaim") is True:
            step("P2 owner-risk completion exit", (python, "tool/p2_exit_gate_test.py", "--project", ".", "--owner-risk-waiver"), timeout=1800)
        else:
            state_output = step(
                "P2 canonical evidence state",
                (python, "tool/p2_evidence_state.py", "--project", "."),
                timeout=600,
            )
            try:
                canonical_state = json.loads(state_output)
            except json.JSONDecodeError as error:
                fail(f"P2 canonical evidence-state output invalid: {error}")
            expected_state = {
                "schemaVersion": "1.0.0",
                "phase": "P2",
                "status": "incomplete",
                "acceptedDecisionTasks": ["P2-004"],
                "behaviorCertifiedTasks": [],
                "platformQualified": False,
                "releaseSupported": False,
                "productionSupported": False,
                "gaPromoted": False,
                "canonicalTaskState": "release/evidence/P2-004/state.json",
                "canonicalPhaseState": "release/evidence/P2/state.json",
            }
            if canonical_state != expected_state:
                fail(f"P2 canonical evidence-state summary invalid: {canonical_state}")

            expected = [f"P2-{number:03d}" for number in range(1, 15)]
            matrix = load_json(project / "config/p2_task_matrix.json").get("tasks")
            ids = [row.get("id") for row in matrix] if isinstance(matrix, list) else []
            if ids != expected:
                fail(f"unexpected P2 task matrix: {ids}")

            phase_state = load_json(project / "release/evidence/P2/state.json")
            expected_task_states = {task_id: "source_only" for task_id in expected}
            expected_task_states["P2-004"] = "accepted_decision"
            if phase_state.get("taskStates") != expected_task_states:
                fail(f"P2 phase task-state map invalid: {phase_state.get('taskStates')}")

            for task_id in expected:
                if task_id == "P2-004":
                    task_state = load_json(
                        project / "release/evidence/P2-004/state.json"
                    )
                    expected_decision = {
                        "taskId": "P2-004",
                        "taskKind": "architecture_decision",
                        "recordRole": "active",
                        "status": "accepted_decision",
                        "claimLevel": "VERIFIED_SOURCE",
                        "productBehaviorObserved": False,
                        "phaseCompletionEligible": False,
                        "platformQualified": False,
                        "releaseSupported": False,
                        "productionSupported": False,
                    }
                    for key, expected_value in expected_decision.items():
                        if task_state.get(key) != expected_value:
                            fail(
                                f"P2-004 canonical decision {key} invalid: "
                                f"{task_state.get(key)!r}"
                            )
                    legacy = load_json(
                        project / "release/evidence/P2-004/manifest.json"
                    )
                    if not (
                        legacy.get("recordRole") == "historical"
                        and legacy.get("stateAuthority") is False
                        and legacy.get("supersededBy")
                        == "release/evidence/P2-004/state.json"
                    ):
                        fail("legacy P2-004 acceptance evidence remains state authority")
                    continue

                value = load_json(
                    project / "release/evidence" / task_id / "manifest.json"
                )
                if (
                    value.get("taskId") != task_id
                    or value.get("status") not in {"source_only", "failed"}
                ):
                    fail(f"committed unfinished P2 evidence invalid: {task_id}: {value}")
                if (
                    value.get("completedTaskPacket") is not None
                    or value.get("platformReceipts") not in ({}, None)
                ):
                    fail(f"committed unfinished P2 evidence overclaims completion: {task_id}")
                if re.fullmatch(
                    r"\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z",
                    str(value.get("generatedAt", "")),
                ) is None:
                    fail(f"committed P2 generatedAt invalid: {task_id}")

            if not (
                aggregate.get("status") == "source_only_not_complete"
                and aggregate.get("completedTasks") == []
                and aggregate.get("tasks") == expected
                and aggregate.get("recordRole") == "historical"
                and aggregate.get("stateAuthority") is False
                and aggregate.get("supersededBy")
                == "release/evidence/P2/state.json"
            ):
                fail(f"legacy P2 aggregate evidence invalid: {aggregate}")

            for task_id in expected:
                step(
                    f"{task_id} source task gate",
                    (
                        python,
                        "tool/p2_task_gate.py",
                        "--project",
                        ".",
                        "--task",
                        task_id,
                    ),
                    timeout=600,
                )
            step("P2 source-only exit", (python, "tool/p2_exit_gate_test.py", "--project", ".", "--source-only"), timeout=1800)
'''
TEST_CONTENT = '''#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import unittest

from p2_evidence_state import validate_repository


ROOT = Path(__file__).resolve().parents[1]


class P2PromotionStateTest(unittest.TestCase):
    def test_canonical_state_is_valid(self) -> None:
        result = validate_repository(ROOT)
        self.assertEqual(result["acceptedDecisionTasks"], ["P2-004"])
        self.assertEqual(result["behaviorCertifiedTasks"], [])
        self.assertFalse(result["platformQualified"])
        self.assertFalse(result["releaseSupported"])

    def test_exact_source_gate_uses_canonical_state(self) -> None:
        source = (ROOT / "tool/v71r12_exact_source_gate.py").read_text(
            encoding="utf-8"
        )
        self.assertIn("P2 canonical evidence state", source)
        self.assertIn("tool/p2_evidence_state.py", source)
        self.assertIn(
            'project / "release/evidence/P2-004/state.json"',
            source,
        )
        self.assertIn('if task_id == "P2-004":', source)
        self.assertIn("committed unfinished P2 evidence invalid", source)
        self.assertNotIn("committed P2 evidence invalid:", source)
        self.assertLess(
            source.index('if task_id == "P2-004":'),
            source.index("committed unfinished P2 evidence invalid"),
        )

    def test_unfinished_capabilities_remain_source_only(self) -> None:
        phase = json.loads(
            (ROOT / "release/evidence/P2/state.json").read_text(encoding="utf-8")
        )
        states = phase["taskStates"]
        self.assertEqual(states["P2-004"], "accepted_decision")
        for task_id, status in states.items():
            if task_id != "P2-004":
                self.assertEqual(status, "source_only", task_id)
        self.assertEqual(phase["behaviorCertifiedTasks"], [])
        self.assertFalse(phase["phaseCompletionEligible"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
'''


def run(*args: str, capture: bool = False) -> str:
    result = subprocess.run(
        list(args),
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(args)}\n"
            f"{result.stdout or ''}"
        )
    return (result.stdout or "").strip()


def verify_transport(trigger: str) -> None:
    if not re.fullmatch(r"[0-9a-f]{40}", trigger):
        raise RuntimeError("GITHUB_SHA is missing or invalid")
    if run("git", "branch", "--show-current", capture=True) != BRANCH:
        raise RuntimeError("unexpected branch")
    if run("git", "rev-parse", "HEAD", capture=True) != trigger:
        raise RuntimeError("checkout does not match exact trigger head")
    run("git", "merge-base", "--is-ancestor", BASE, trigger)
    if run("git", "rev-parse", f"{BASE}^{{tree}}", capture=True) != BASE_TREE:
        raise RuntimeError("protected-main base tree changed unexpectedly")
    if (ROOT / TEST).exists():
        raise RuntimeError("promotion-state test unexpectedly exists on protected main")


def patch_gate() -> None:
    path = ROOT / GATE
    content = path.read_text(encoding="utf-8")
    if content.count(START_ANCHOR) != 1 or content.count(END_ANCHOR) != 1:
        raise RuntimeError("exact P2 source-state block anchors are not unique")
    start = content.index(START_ANCHOR)
    end = content.index(END_ANCHOR, start) + len(END_ANCHOR)
    updated = content[:start] + REPLACEMENT + content[end:]
    if updated == content:
        raise RuntimeError("canonical P2 promotion patch made no change")
    path.write_text(updated, encoding="utf-8", newline="\n")
    (ROOT / TEST).write_text(TEST_CONTENT, encoding="utf-8", newline="\n")


def remove_transport() -> None:
    for relative in (WORKFLOW, SCRIPT):
        path = ROOT / relative
        if not path.is_file():
            raise RuntimeError(f"missing temporary path: {relative}")
        path.unlink()


def refresh_manifest_twice() -> None:
    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    first = (ROOT / "SOURCE_MANIFEST.sha256").read_bytes()
    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    if (ROOT / "SOURCE_MANIFEST.sha256").read_bytes() != first:
        raise RuntimeError("SOURCE_MANIFEST.sha256 is not byte-stable")
    run("python3", "tool/p1a_text_eof_contract_test.py", "--project", ".")


def validate() -> None:
    patch_gate()
    run("python3", "-m", "py_compile", GATE.as_posix(), TEST.as_posix())
    run("python3", "tool/p2_evidence_state.py", "--project", ".")
    run("python3", "tool/p2_evidence_state_test.py")
    run("python3", TEST.as_posix())
    remove_transport()
    refresh_manifest_twice()
    run("python3", "tool/p2_evidence_state.py", "--project", ".")
    run("python3", "tool/p2_evidence_state_test.py")
    run("python3", TEST.as_posix())
    run("ruby", "tool/workflow_integrity_test.rb", ".")
    run("git", "diff", "--check")


def prove_scope() -> list[str]:
    run("git", "add", "-A")
    run("git", "diff", "--cached", "--check")
    paths = run(
        "git",
        "diff",
        "--cached",
        "--name-only",
        BASE,
        "--",
        capture=True,
    ).splitlines()
    if set(paths) != FINAL_PATHS:
        raise RuntimeError(
            f"exact promotion-repair scope mismatch: expected {sorted(FINAL_PATHS)}, got {paths}"
        )
    for temporary in (WORKFLOW.as_posix(), SCRIPT.as_posix()):
        if temporary in paths or (ROOT / temporary).exists():
            raise RuntimeError(f"temporary finalizer survived: {temporary}")
    return paths


def publish(paths: list[str]) -> None:
    run("git", "config", "user.name", "github-actions[bot]")
    run(
        "git",
        "config",
        "user.email",
        "41898282+github-actions[bot]@users.noreply.github.com",
    )
    run(
        "git",
        "commit",
        "-m",
        "fix(p2): use canonical evidence state in owner-risk gate",
        "-m",
        "Treat P2-004 as an accepted architecture decision at VERIFIED_SOURCE "
        "while keeping P2-005/P2-006 uncertified and P2 incomplete. Historical "
        "evidence remains validated but cannot override active state.",
    )
    run("git", "diff", "--exit-code")
    run("git", "diff", "--cached", "--exit-code")
    if run("git", "status", "--porcelain=v1", capture=True):
        raise RuntimeError("final promotion-repair candidate worktree is dirty")
    head = run("git", "rev-parse", "HEAD", capture=True)
    tree = run("git", "rev-parse", "HEAD^{tree}", capture=True)
    run("git", "push", "origin", f"HEAD:refs/heads/{BRANCH}")
    print(f"P2_PROMOTION_FINAL_COMMIT={head}")
    print(f"P2_PROMOTION_FINAL_TREE={tree}")
    print("P2_PROMOTION_FINAL_PATHS=" + ",".join(paths))


def main() -> int:
    trigger = os.environ.get("GITHUB_SHA", "").strip()
    verify_transport(trigger)
    validate()
    publish(prove_scope())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
