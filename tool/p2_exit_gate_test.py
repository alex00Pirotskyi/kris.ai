#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,pathlib,subprocess,sys
from p2_evidence_contract import TASKS

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--project',default='.');ap.add_argument('--source-only',action='store_true');ap.add_argument('--reviewed-sha');ap.add_argument('--platform-receipt',action='append',default=[]);ns=ap.parse_args();root=pathlib.Path(ns.project).resolve()
 if not ns.source_only and (not ns.reviewed_sha or not ns.platform_receipt):
  aggregate_path=root/'release/evidence/P2/manifest.json'
  if aggregate_path.is_file():
   aggregate=json.loads(aggregate_path.read_text());ns.reviewed_sha=ns.reviewed_sha or aggregate.get('reviewedCommit');ns.platform_receipt=[row['path'] for row in aggregate.get('platformReceipts',{}).values()]
 for task in TASKS:
  cmd=[sys.executable,str(root/'tool/p2_task_gate.py'),'--project',str(root),'--task',task]
  if not ns.source_only:
   cmd+=['--require-behavioral','--reviewed-sha',ns.reviewed_sha or '']
   for path in ns.platform_receipt:cmd+=['--platform-receipt',path]
  subprocess.run(cmd,check=True)
  if not ns.source_only and not (root/'tasks/completed'/f'{task}.md').is_file():raise SystemExit(f'{task}: completed packet missing')
 guide=(root/'docs/OWNER_MODE_OPERATOR_GUIDE.md').read_text().lower()
 if 'not a sandbox' not in guide or 'full authority' not in guide:raise SystemExit('operator guide authority wording missing')
 if not ns.source_only:
  aggregate=json.loads((root/'release/evidence/P2/manifest.json').read_text())
  if aggregate.get('status')!='passed' or aggregate.get('reviewedCommit')!=ns.reviewed_sha:raise SystemExit('aggregate P2 manifest not exact/passed')
  accepted=root/'release/evidence/P2-004/ACCEPTED_ADR.json'
  if not accepted.is_file():raise SystemExit('P2-004 accepted ADR evidence missing')
  adr=json.loads(accepted.read_text())
  if adr.get('status')!='accepted' or adr.get('reviewedCommit')!=ns.reviewed_sha or set(adr.get('platformMeasurements',{}))!={'windows','macos','linux'}:raise SystemExit('P2-004 accepted ADR is not exact tri-OS evidence')
 print('P2 exit gate: PASS'+(' (source/local only; no completion claim)' if ns.source_only else ''))
 return 0
if __name__=='__main__':raise SystemExit(main())
