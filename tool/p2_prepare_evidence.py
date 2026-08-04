#!/usr/bin/env python3
"""Prepare source/local P2 evidence without any completion promotion."""
from __future__ import annotations

import json
import pathlib
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
TASKS = json.loads((ROOT / "config/p2_task_matrix.json").read_text(encoding="utf-8"))["tasks"]

COMMON_RUNTIME = [
    "lib/product/p2_runtime_composition.dart",
    "lib/product/p2_automation_host_process_client.dart",
    "lib/product/p2_effect_journal.dart",
    "test/product/p2_shipped_product_runtime_e2e_test.dart",
]
ARTIFACTS = {
    "P2-001": [
        "lib/product/p2_owner_mode.dart",
        "config/p2_owner_mode.v1.json",
        "lib/product/p2_owner_workspace.dart",
        "test/product/p2_owner_mode_test.dart",
        "test/product/p2_owner_workspace_test.dart",
    ],
    "P2-002": [
        "lib/product/p2_filesystem_service.dart",
        "lib/product/p2_desktop_effect_authorizers.dart",
        "test/product/p2_filesystem_service_test.dart",
        *COMMON_RUNTIME,
    ],
    "P2-003": [
        "lib/product/p2_finite_command_service.dart",
        "lib/product/p2_automation_command_service.dart",
        "lib/product/p2_effect_boundary.dart",
        "automation_host/src/host-operations.mjs",
        "test/product/p2_effect_boundary_test.dart",
        *COMMON_RUNTIME,
    ],
    "P2-004": [
        "docs/adr/ADR-0012-p2-automation-host.md",
        "tool/p2_technology_spike.py",
        "tool/p2_toolchains.py",
        "tool/p2_extend_toolchain_lock.py",
        "tool/p2_toolchain_extension_test.py",
        "tool/p2_evidence_contract.py",
        "tool/p2_evidence_contract_test.py",
        "tool/p2_contract_fixture_support.py",
        "tool/p2_strict_finalizer_contract_test.py",
        ".github/workflows/p2-owner-mode.yml",
        "automation_host/package.json",
        "automation_host/package-lock.json",
        "config/toolchains.lock.json",
        "config/p2_toolchain_extension.v1.template.json",
        "config/p2_runner_provisioning.v3.template.json",
        "config/p2_controlled_runner_policy.v5.template.json",
        "schemas/p2_runner_attestation_v5.schema.json",
        "schemas/p2_post_run_cleanup_v2.schema.json",
        "docs/operations/P2_TECHNOLOGY_CANDIDATE_RECEIPT_TEMPLATE.json",
    ],
    "P2-005": [
        "lib/product/p2_pty_service.dart",
        "lib/product/p2_runtime_composition.dart",
        "lib/product/p2_automation_host_process_client.dart",
        "automation_host/src/host.mjs",
        "automation_host/src/authenticated-ipc.mjs",
        "automation_host/src/windows-pty-broker.mjs",
        "test/product/p2_runtime_composition_test.dart",
        "test/product/p2_shipped_product_runtime_e2e_test.dart",
    ],
    "P2-006": [
        "lib/product/p2_process_tree.dart",
        "lib/product/p2_runtime_composition.dart",
        "automation_host/src/process-tree.mjs",
        "automation_host/src/windows-process-broker.mjs",
        "automation_host/native/windows/job_supervisor.cpp",
        "automation_host/native/posix/watchdog.c",
        "test/product/p2_shipped_product_runtime_e2e_test.dart",
    ],
    "P2-007": [
        "lib/product/p2_automation_host_operations.dart",
        "automation_host/src/host-operations.mjs",
        "config/p2_platform_operations.v1.json",
        "docs/architecture/P2_PLATFORM_SUPPORT_MATRIX.md",
        "test/product/p2_automation_host_operations_test.dart",
        *COMMON_RUNTIME,
    ],
    "P2-008": [
        "lib/product/p2_automation_host_operations.dart",
        "automation_host/src/host-operations.mjs",
        "docs/architecture/P2_PLATFORM_SUPPORT_MATRIX.md",
        "test/product/p2_automation_host_operations_test.dart",
        *COMMON_RUNTIME,
    ],
    "P2-009": [
        "lib/product/p2_automation_host_operations.dart",
        "automation_host/src/interactive-desktop-adapter.mjs",
        "automation_host/src/redaction.mjs",
        "test/product/p2_automation_host_operations_test.dart",
        *COMMON_RUNTIME,
    ],
    "P2-010": [
        "lib/product/p2_snapshot_undo.dart",
        "lib/product/p2_desktop_effect_authorizers.dart",
        "lib/product/p2_effect_journal.dart",
        "test/product/p2_snapshot_undo_test.dart",
        *COMMON_RUNTIME,
    ],
    "P2-011": [
        "lib/product/p2_emergency_watchdog.dart",
        "lib/product/p2_runtime_composition.dart",
        "automation_host/src/external-watchdog.mjs",
        "automation_host/native/windows/job_supervisor.cpp",
        "automation_host/native/posix/watchdog.c",
        "test/product/p2_shipped_product_runtime_e2e_test.dart",
    ],
    "P2-012": [
        "lib/product/p2_terminal_model.dart",
        "lib/product/p2_owner_workspace.dart",
        "test/product/p2_owner_workspace_test.dart",
        "test/product/p2_process_terminal_contract_test.dart",
    ],
    "P2-013": [
        "lib/product/p2_p1_authority_adapter.dart",
        "lib/product/p2_product_runtime_bootstrap.dart",
        "lib/product/p2_product_runtime_integration.dart",
        "lib/product/p2_managed_authorization_registry.dart",
        "test/product/p2_shipped_product_runtime_e2e_test.dart",
        "tool/p2_behavioral_gate.py",
        "tool/p2_task_fixture.py",
        "tool/p2_task_platform_assertions.py",
        "tool/p2_evidence_contract.py",
        "tool/p2_evidence_contract_test.py",
        "tool/p2_strict_finalizer_contract_test.py",
        "evals/fixtures/p2",
        "docs/security/P2_SECURITY_REVIEW_PACKET.md",
    ],
    "P2-014": ["docs/OWNER_MODE_OPERATOR_GUIDE.md"],
}


def main() -> int:
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    completed = ROOT / "tasks/completed"
    for packet in completed.glob("P2-*.md") if completed.exists() else []:
        packet.unlink()
    for task in TASKS:
        task_id = task["id"]
        directory = ROOT / "release/evidence" / task_id
        directory.mkdir(parents=True, exist_ok=True)
        test_path = directory / "test-results.json"
        tests = json.loads(test_path.read_text(encoding="utf-8")) if test_path.exists() else {
            "status": "not_tested",
            "tests": [],
        }
        local_status = tests.get("status", "not_tested")
        status = "failed" if local_status == "failed" else "source_only"
        inherited = {"config/toolchains.lock.json"}
        missing = [
            path for path in ARTIFACTS[task_id]
            if path not in inherited and not (ROOT / path).exists()
        ]
        if missing:
            raise SystemExit(f"{task_id}: declared implementation artifacts missing: {missing}")
        artifacts_text = "".join(f"- `{path}`\n" for path in ARTIFACTS[task_id])
        (directory / "IMPLEMENTATION.md").write_text(
            f"# {task_id} — {task['name']} implementation\n\n"
            f"## Contract\n\n{task['requiredOutput']}\n\n"
            f"## Done condition\n\n{task['doneWhen']}\n\n"
            f"## Governed artifacts\n\n{artifacts_text}\n"
            "## Assurance status\n\n"
            "V63 contains source/local gates and the production product-to-worker composition, but this task is not DONE. "
            "Completion requires task-specific exact-source Windows, macOS, and Linux product-path receipts from governed "
            "interactive desktop lanes, explicit owner approval, and an independent commit-bound security review. "
            "`source_only`, helper-only, `blocked`, `unsupported`, `skipped`, `absent`, malformed, and `not_tested` evidence can never become `passed`.\n",
            encoding="utf-8",
        )
        (directory / "OWNER_APPROVAL.md").write_text(
            f"# {task_id} owner approval\n\nStatus: **PENDING**\n\n"
            "Approval must be a separate JSON artifact bound to the exact reviewed commit, tree, V63 package digest, "
            "and the exact platform-receipt hashes. A command-line name is not approval.\n",
            encoding="utf-8",
        )
        (directory / "manifest.json").write_text(
            json.dumps(
                {
                    "schemaVersion": "2.0.0",
                    "taskId": task_id,
                    "name": task["name"],
                    "status": status,
                    "localResult": local_status,
                    "generatedAt": now,
                    "dependsOn": task["dependsOn"],
                    "artifacts": ARTIFACTS[task_id],
                    "testResults": f"release/evidence/{task_id}/test-results.json",
                    "ownerApproval": {"status": "pending"},
                    "independentReview": {"status": "pending"},
                    "platformReceipts": {},
                    "completedTaskPacket": None,
                    "sourceOnlyIsNotBehavioralProof": True,
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
    aggregate = ROOT / "release/evidence/P2"
    aggregate.mkdir(parents=True, exist_ok=True)
    (aggregate / "IMPLEMENTATION.md").write_text(
        "# P2 aggregate V63 corrective implementation\n\n"
        "The guarded P2 product runtime, authenticated worker/native composition, exact source inventories, immutable CI, "
        "task-specific receipt contract, independent-review template, and two-stage launcher are present. This source package does not claim P2 completion.\n",
        encoding="utf-8",
    )
    (aggregate / "OWNER_APPROVAL.md").write_text(
        "# P2 aggregate owner approval\n\nStatus: **PENDING**\n",
        encoding="utf-8",
    )
    (aggregate / "manifest.json").write_text(
        json.dumps(
            {
                "schemaVersion": "2.0.0",
                "phase": "P2",
                "status": "source_only_not_complete",
                "generatedAt": now,
                "tasks": [row["id"] for row in TASKS],
                "completedTasks": [],
                "triOsBehavioralEvidence": "pending",
                "ownerApproval": "pending",
                "independentSecurityReview": "pending",
                "sourceOnlyIsNotBehavioralProof": True,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print("P2 V63 evidence prepared without completion claims: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
