#!/usr/bin/env python3
"""One-shot GS-003 materializer for the current P2 promotion state gate."""
from __future__ import annotations

from pathlib import Path
import sys


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
                    r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z",
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


def main() -> int:
    project = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    path = project / "tool" / "v71r12_exact_source_gate.py"
    content = path.read_text(encoding="utf-8")
    if content.count(START_ANCHOR) != 1 or content.count(END_ANCHOR) != 1:
        raise SystemExit("exact P2 source-state block anchors are not unique")
    start = content.index(START_ANCHOR)
    end = content.index(END_ANCHOR, start) + len(END_ANCHOR)
    updated = content[:start] + REPLACEMENT + content[end:]
    if updated == content:
        raise SystemExit("GS-003 patch unexpectedly made no change")
    path.write_text(updated, encoding="utf-8", newline="\n")
    print("GS003_P2_PROMOTION_STATE_PATCHED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
