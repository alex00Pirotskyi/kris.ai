#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,pathlib,sys
from p2_evidence_contract import TASKS,PLATFORMS,validate_platform_receipt
REQ={
'P2-001':['lib/product/p2_owner_mode.dart','lib/product/p2_owner_workspace.dart','test/product/p2_owner_mode_test.dart','test/product/p2_owner_workspace_test.dart'],
'P2-002':['lib/product/p2_filesystem_service.dart','lib/product/p2_desktop_effect_authorizers.dart','lib/product/p2_runtime_composition.dart','test/product/p2_filesystem_service_test.dart','test/product/p2_shipped_product_runtime_e2e_test.dart'],
'P2-003':['lib/product/p2_finite_command_service.dart','lib/product/p2_automation_command_service.dart','lib/product/p2_effect_boundary.dart','lib/product/p2_p1_authority_adapter.dart','lib/product/p2_automation_host.dart','automation_host/src/host-operations.mjs','test/product/p2_effect_boundary_test.dart','test/product/p2_shipped_product_runtime_e2e_test.dart'],
'P2-004':['docs/adr/ADR-0012-p2-automation-host.md','tool/p2_technology_spike.py','tool/p2_extend_toolchain_lock.py','tool/p2_toolchain_extension_test.py','tool/p2_evidence_contract_test.py','tool/p2_strict_finalizer_contract_test.py','automation_host/package-lock.json','config/p2_toolchain_extension.v1.template.json','config/p2_runner_provisioning.v3.template.json','config/p2_controlled_runner_policy.v5.template.json','schemas/p2_runner_attestation_v5.schema.json','schemas/p2_post_run_cleanup_v2.schema.json','docs/operations/P2_TECHNOLOGY_CANDIDATE_RECEIPT_TEMPLATE.json'],
'P2-005':['lib/product/p2_pty_service.dart','lib/product/p2_runtime_composition.dart','lib/product/p2_automation_host_process_client.dart','automation_host/src/host.mjs','automation_host/src/authenticated-ipc.mjs','automation_host/src/windows-pty-broker.mjs','test/product/p2_runtime_composition_test.dart','test/product/p2_shipped_product_runtime_e2e_test.dart'],
'P2-006':['lib/product/p2_process_tree.dart','lib/product/p2_runtime_composition.dart','automation_host/src/process-tree.mjs','automation_host/src/windows-process-broker.mjs','automation_host/native/windows/job_supervisor.cpp','automation_host/native/posix/watchdog.c','test/product/p2_shipped_product_runtime_e2e_test.dart'],
'P2-007':['lib/product/p2_automation_host_operations.dart','automation_host/src/host-operations.mjs','docs/architecture/P2_PLATFORM_SUPPORT_MATRIX.md','test/product/p2_automation_host_operations_test.dart','test/product/p2_shipped_product_runtime_e2e_test.dart'],
'P2-008':['lib/product/p2_automation_host_operations.dart','automation_host/src/host-operations.mjs','docs/architecture/P2_PLATFORM_SUPPORT_MATRIX.md','test/product/p2_automation_host_operations_test.dart','test/product/p2_shipped_product_runtime_e2e_test.dart'],
'P2-009':['lib/product/p2_automation_host_operations.dart','automation_host/src/interactive-desktop-adapter.mjs','automation_host/src/redaction.mjs','test/product/p2_automation_host_operations_test.dart','test/product/p2_shipped_product_runtime_e2e_test.dart'],
'P2-010':['lib/product/p2_snapshot_undo.dart','lib/product/p2_desktop_effect_authorizers.dart','lib/product/p2_effect_journal.dart','lib/product/p2_runtime_composition.dart','test/product/p2_snapshot_undo_test.dart','test/product/p2_shipped_product_runtime_e2e_test.dart'],
'P2-011':['lib/product/p2_emergency_watchdog.dart','lib/product/p2_runtime_composition.dart','automation_host/src/external-watchdog.mjs','automation_host/native/posix/watchdog.c','automation_host/native/windows/job_supervisor.cpp','test/product/p2_shipped_product_runtime_e2e_test.dart'],
'P2-012':['lib/product/p2_terminal_model.dart','lib/product/p2_owner_workspace.dart','test/product/p2_owner_workspace_test.dart','test/product/p2_process_terminal_contract_test.dart'],
'P2-013':['lib/product/p2_p1_authority_adapter.dart','lib/product/p2_product_runtime_integration.dart','test/product/p2_shipped_product_runtime_e2e_test.dart','tool/p2_behavioral_gate.py','tool/p2_task_fixture.py','tool/p2_task_platform_assertions.py','tool/p2_evidence_contract.py','tool/p2_evidence_contract_test.py','tool/p2_strict_finalizer_contract_test.py','docs/security/P2_SECURITY_REVIEW_PACKET.md'],
'P2-014':['docs/OWNER_MODE_OPERATOR_GUIDE.md'],}
DEPS={'P2-005':['P2-004'],'P2-006':['P2-003','P2-005'],'P2-007':['P2-003'],'P2-008':['P2-003'],'P2-010':['P2-002','P2-003'],'P2-011':['P2-005','P2-006'],'P2-012':['P2-005','P2-006'],'P2-013':['P2-002','P2-003','P2-006','P2-011'],'P2-014':['P2-001','P2-013']}

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--project',default='.');ap.add_argument('--task',required=True,choices=TASKS);ap.add_argument('--reviewed-sha');ap.add_argument('--platform-receipt',action='append',default=[]);ap.add_argument('--require-behavioral',action='store_true');ns=ap.parse_args();root=pathlib.Path(ns.project).resolve();task=ns.task
 missing=[p for p in REQ[task] if not (root/p).is_file()]
 if missing:raise SystemExit(f'{task} missing: {missing}')
 evidence=root/'release/evidence'/task/'test-results.json'
 if not evidence.is_file():raise SystemExit(f'{task}: missing local test-results.json')
 local=json.loads(evidence.read_text())
 if local.get('status')=='failed':raise SystemExit(f'{task}: local/source gate failed')
 for dep in DEPS.get(task,[]):
  if not (root/'release/evidence'/dep/'manifest.json').is_file():raise SystemExit(f'{task}: dependency {dep} evidence missing')
 if ns.require_behavioral:
  if not ns.reviewed_sha or len(ns.platform_receipt)!=3:raise SystemExit('exact reviewed SHA and three platform receipts required')
  seen={}
  for raw in ns.platform_receipt:
   path=pathlib.Path(raw).resolve();receipt=validate_platform_receipt(path,commit_sha=ns.reviewed_sha);seen[receipt['platform']]=receipt
  if set(seen)!=set(PLATFORMS):raise SystemExit(f'{task}: exact Windows/macOS/Linux receipts required')
  for platform,receipt in seen.items():
   if receipt['taskAssertions'][task]['status']!='passed':raise SystemExit(f'{task}: {platform} task proof not passed')
 print(f'{task} gate: PASS'+(' (behavioral tri-OS)' if ns.require_behavioral else ' (source/local only)'))
 return 0
if __name__=='__main__':raise SystemExit(main())
