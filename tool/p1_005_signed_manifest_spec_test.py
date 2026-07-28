#!/usr/bin/env python3
from __future__ import annotations
import argparse,json
from pathlib import Path

def main():
 p=argparse.ArgumentParser(); p.add_argument('--project',default='.'); p.add_argument('--json-output'); a=p.parse_args(); root=Path(a.project).resolve(); results=[]
 def add(name,ok,detail): results.append({"name":name,"passed":bool(ok),"detail":detail})
 required=['schemas/signed_manifest_v2.schema.json','config/signed_manifest_v2.json','docs/adr/ADR-0003-signed-manifest-v2.md','docs/architecture/SIGNED_MANIFEST_V2.md','evals/fixtures/p1_005_signed_manifest_v2/negative_vectors.json','tasks/completed/P1-005.md','release/evidence/P1-005/manifest.json']
 missing=[x for x in required if not (root/x).is_file()]; add('Required P1-005 files',not missing,'all present' if not missing else str(missing))
 config=json.loads((root/'config/signed_manifest_v2.json').read_text()); schema=json.loads((root/'schemas/signed_manifest_v2.schema.json').read_text()); vectors=json.loads((root/'evals/fixtures/p1_005_signed_manifest_v2/negative_vectors.json').read_text())
 add('Ed25519 and canonical JSON specification',config.get('algorithm')=='Ed25519' and str(config.get('canonicalization','')).startswith('RFC8785'),'algorithm and canonicalization fixed')
 add('External trust roots',config.get('trustRoots')=='external_keyring_only' and all(x in config.get('forbiddenEnvelopeFields',[]) for x in ('privateKey','seed','keyMaterial')),'envelope cannot carry trust root')
 required_fields=set(schema.get('required',[])); add('Purpose, domain and expiry binding',{'keyId','intendedUse','trustDomain','issuedAt','expiresAt','signature'}<=required_fields,str(sorted(required_fields)))
 names={x['name'] for x in vectors.get('cases',[])}; add('Negative vector specification',{'payload_modified','expired','wrong_use','wrong_domain','revoked_key','v1_downgrade'}<=names,str(sorted(names)))
 roadmap=json.loads((root/'docs/roadmap/roadmap.yaml').read_text()); tasks={x['id']:x for x in roadmap['tasks']}; add('Roadmap state',tasks.get('P1-005',{}).get('status')=='DONE',f"P1-005={tasks.get('P1-005',{}).get('status')}")
 passed=all(x['passed'] for x in results); report={"schemaVersion":"1.0.0","taskId":"P1-005","caseCount":len(results),"passedCount":sum(x['passed'] for x in results),"failedCount":sum(not x['passed'] for x in results),"passed":passed,"results":results}; text=json.dumps(report,indent=2,sort_keys=True)+'\n'
 if a.json_output: out=root/a.json_output; out.parent.mkdir(parents=True,exist_ok=True); out.write_text(text,encoding='utf-8',newline='\n')
 print(text,end=''); return 0 if passed else 1
if __name__=='__main__': raise SystemExit(main())
