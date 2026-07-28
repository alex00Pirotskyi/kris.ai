#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,subprocess,sys
from pathlib import Path
def main():
 p=argparse.ArgumentParser(); p.add_argument('--project',default='.'); p.add_argument('--json-output'); a=p.parse_args(); root=Path(a.project).resolve(); results=[]
 def add(n,o,d): results.append({"name":n,"passed":bool(o),"detail":d})
 roadmap=json.loads((root/'docs/roadmap/roadmap.yaml').read_text()); tasks={x['id']:x for x in roadmap['tasks']}; statuses={f'P1-{i:03d}':tasks.get(f'P1-{i:03d}',{}).get('status') for i in range(1,13)}
 add('P1-001 through P1-012 complete',all(v=='DONE' for v in statuses.values()),str(statuses))
 required=['config/access_profiles.v2.json','config/capability_grant.v2.json','config/policy_engine.v2.json','config/signed_manifest_v2.json','config/tuf_trust.v1.json','config/key_storage.v2.json','config/threat_model_v2.json','config/local_ipc.v1.json','release/evidence/P1/manifest.json']
 missing=[x for x in required if not (root/x).is_file()]; add('P1 closure evidence present',not missing,'all present' if not missing else str(missing))
 for script in ('p1_005_signed_manifest_spec_test.py','p1_006_cross_language_signing_test.py','p1_007_manifest_compatibility_test.py','p1_008_tuf_trust_test.py','p1_009_key_registry_test.py','p1_010_signed_audit_test.py','p1_011_threat_model_test.py','p1_012_local_ipc_test.py','integration_train_test.py'):
  result=subprocess.run([sys.executable,str(root/'tool'/script),'--project',str(root)],capture_output=True,text=True)
  add(script,result.returncode==0,(result.stdout+result.stderr)[-500:])
 closure=json.loads((root/'release/evidence/P1/manifest.json').read_text()); add('P1 exit-gate claims',all(closure.get('claims',{}).get(x) is True for x in ('singlePolicyModel','signedManifestCrossLanguage','externalTrustRoots','authenticatedLocalIpc','threatModelApproved','tufDesignApproved')),'all exit claims true')
 passed=all(x['passed'] for x in results); report={"schemaVersion":"1.0.0","phase":"P1","caseCount":len(results),"passedCount":sum(x['passed'] for x in results),"failedCount":sum(not x['passed'] for x in results),"passed":passed,"results":results}; text=json.dumps(report,indent=2,sort_keys=True)+'\n'
 if a.json_output: out=root/a.json_output; out.parent.mkdir(parents=True,exist_ok=True); out.write_text(text,encoding='utf-8',newline='\n')
 print(text,end=''); return 0 if passed else 1
if __name__=='__main__': raise SystemExit(main())
