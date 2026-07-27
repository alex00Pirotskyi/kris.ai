#!/usr/bin/env python3
from __future__ import annotations
import argparse,importlib.util,json,sys
from datetime import datetime,timezone
from pathlib import Path

def add(results,name,passed,detail): results.append({"name":name,"passed":bool(passed),"detail":detail})
def load(path,name):
 spec=importlib.util.spec_from_file_location(name,path)
 if spec is None or spec.loader is None: raise RuntimeError(f"cannot load {path}")
 module=importlib.util.module_from_spec(spec); sys.modules[name]=module; spec.loader.exec_module(module); return module

def main():
 parser=argparse.ArgumentParser(); parser.add_argument('--project',default='.'); parser.add_argument('--json-output'); args=parser.parse_args()
 root=Path(args.project).resolve(); results=[]
 required=['schemas/capability_grant_v2.schema.json','config/capability_grant.v2.json','docs/architecture/CAPABILITY_GRANT_V2.md','lib/product/capability_grant_v2.dart','test/product/capability_grant_v2_test.dart','tool/capability_grant_v2.py','tool/capability_grant_v2_test.py','evals/fixtures/p1_003_capability_grants/vectors.json','tasks/completed/P1-003.md','release/evidence/P1-003/manifest.json']
 missing=[x for x in required if not (root/x).is_file()]; add(results,'Required P1-003 files',not missing,'all present' if not missing else str(missing))
 module=load(root/'tool/capability_grant_v2.py','p1_003_grant'); fixture=json.loads((root/'evals/fixtures/p1_003_capability_grants/vectors.json').read_text(encoding='utf-8')); key={fixture['testKeyId']:b'fixture-only-not-a-secret'}; now=datetime.fromisoformat(fixture['fixedNow'].replace('Z','+00:00')).astimezone(timezone.utc)
 def verify(grant,ledger,invocation='inv-1',run='run-001'):
  return module.verify_and_consume(grant,keyring=key,ledger=ledger,expected_run_id=run,expected_task_id='task-001',expected_actor_id='owner_executor',expected_tool_id='filesystem.write',expected_access_profile_id='owner',invocation_id=invocation,now=now)
 verified=False
 try: verified=verify(fixture['validGrant'],module.GrantUseLedger())['grantId']=='grant-p1-003-001'
 except Exception: pass
 add(results,'Valid authenticated grant',verified,'external keyring verifies canonical envelope')
 observed={}
 for case in fixture['cases']:
  ledger=module.GrantUseLedger()
  try:
   if case['kind']=='context': verify(case['grant'],ledger,run=case['expectedRunId'])
   elif case['kind']=='replay': verify(case['grant'],ledger,case['invocationId']); verify(case['grant'],ledger,case['invocationId'])
   elif case['kind']=='exhaust': verify(case['grant'],ledger,case['firstInvocationId']); verify(case['grant'],ledger,case['secondInvocationId'])
   else: verify(case['grant'],ledger)
  except module.GrantVerificationError as error: observed[case['name']]=error.code
 expected={case['name']:case['expectedError'] for case in fixture['cases']}; add(results,'Modified expired replayed wrong-run grants rejected',observed==expected,str(observed))
 serialized=json.dumps(fixture['validGrant'],sort_keys=True); no_key='fixture-only-not-a-secret' not in serialized and all(x not in serialized for x in ('keyMaterial','secretValue','rawSecret','privateKey','signingKey')); add(results,'External issuer key boundary',no_key,'no key material in envelope')
 binding=fixture['validGrant']['binding']; scope=fixture['validGrant']['scope']; binding_ok=all(x in binding for x in ('runId','taskId','actorId','toolId','accessProfileId')); scope_ok=all(x in scope for x in ('paths','process','network','browser','secrets')) and scope['secrets'].get('rawReveal') is False; add(results,'Complete binding and scope',binding_ok and scope_ok,f"binding={sorted(binding)} scope={sorted(scope)}")
 dart=(root/'lib/product/capability_grant_v2.dart').read_text(encoding='utf-8')+(root/'test/product/capability_grant_v2_test.dart').read_text(encoding='utf-8'); add(results,'Dart structural contract',all(x in dart for x in ('CapabilityGrantV2.fromJson','requiresWorkerAuthentication','canonicalSigningPayload','raw secret reveal is forbidden')),'Dart model requires worker authentication')
 validator=(root/'tool/validate_release.py').read_text(encoding='utf-8'); source_contract=(root/'test/product/source_contract_test.dart').read_text(encoding='utf-8'); inventory=('lib/product/capability_grant_v2.dart' in validator and 'test/product/capability_grant_v2_test.dart' in validator and 'lib/product/capability_grant_v2.dart' in source_contract and 'test/product/capability_grant_v2_test.dart' not in source_contract); add(results,'Governed Dart inventories',inventory,'release and lib-only inventories remain distinct')
 roadmap=json.loads((root/'docs/roadmap/roadmap.yaml').read_text(encoding='utf-8')); tasks={x['id']:x for x in roadmap['tasks']}; ready=sorted(k for k,v in tasks.items() if v.get('status')=='READY'); state=tasks.get('P1-003',{}).get('status')=='DONE' and all(tasks.get(x,{}).get('status') in {'READY','DONE'} for x in ('P1-004','P1-005','P1-012')); add(results,'Roadmap state',state,f"P1-003={tasks.get('P1-003',{}).get('status')} ready={ready}")
 ci=(root/'.github/workflows/ci.yml').read_text(encoding='utf-8'); verify_source=(root/'tool/verify.sh').read_text(encoding='utf-8'); add(results,'CI and local verification','P1-003 capability grant v2' in ci and 'p1_003_capability_grant_test.py' in verify_source,'gates wired')
 add(results,'Release validation integration','tool/p1_003_capability_grant_test.py' in validator and 'schemas/capability_grant_v2.schema.json' in validator,'required files wired')
 passed=all(x['passed'] for x in results); report={'schemaVersion':'1.0.0','taskId':'P1-003','caseCount':len(results),'passedCount':sum(1 for x in results if x['passed']),'failedCount':sum(1 for x in results if not x['passed']),'passed':passed,'results':results}; text=json.dumps(report,indent=2,sort_keys=True)+'\n'
 if args.json_output:
  out=root/args.json_output; out.parent.mkdir(parents=True,exist_ok=True); out.write_text(text,encoding='utf-8',newline='\n')
 print(text,end=''); return 0 if passed else 1
if __name__=='__main__': raise SystemExit(main())
