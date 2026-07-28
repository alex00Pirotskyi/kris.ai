#!/usr/bin/env python3
from __future__ import annotations
import argparse,dataclasses,importlib.util,json,sys
from pathlib import Path
def load(path,name):
 spec=importlib.util.spec_from_file_location(name,path); m=importlib.util.module_from_spec(spec); sys.modules[name]=m; spec.loader.exec_module(m); return m
def main():
 p=argparse.ArgumentParser(); p.add_argument('--project',default='.'); p.add_argument('--json-output'); a=p.parse_args(); root=Path(a.project).resolve(); sys.path.insert(0,str(root/'tool')); results=[]
 def add(n,o,d): results.append({"name":n,"passed":bool(o),"detail":d})
 ed=load(root/'tool/ed25519_ref.py','ed_audit'); audit=load(root/'tool/signed_audit_checkpoint.py','audit')
 seed=bytes.fromhex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60'); public=ed.public_key(seed)
 c1=audit.create_checkpoint(sequence=1,event_count=10,previous_checkpoint_hash='',audit_head_hash='a'*64,key_id='k1',seed=seed)
 c2=audit.create_checkpoint(sequence=2,event_count=20,previous_checkpoint_hash=audit.checkpoint_hash(c1),audit_head_hash='b'*64,key_id='k1',seed=seed)
 good=audit.verify_chain([c1,c2],public_keys={'k1':public},expected_final_audit_head='b'*64); add('Valid signed checkpoint chain',good['checkpointCount']==2,str(good))
 observed={}
 mutations={
  'tamper':[dataclasses.replace(c1,audit_head_hash='c'*64),c2],
  'truncate':[c1],
  'reorder':[c2,c1],
  'signer':[dataclasses.replace(c1,key_id='other'),c2],
 }
 for name,items in mutations.items():
  try: audit.verify_chain(items,public_keys={'k1':public},expected_final_audit_head='b'*64)
  except audit.AuditCheckpointError as e: observed[name]=e.code
 add('Tamper truncate reorder signer substitution rejected',set(observed)==set(mutations),str(observed))
 tasks={x['id']:x for x in json.loads((root/'docs/roadmap/roadmap.yaml').read_text())['tasks']}; add('Roadmap state',tasks.get('P1-010',{}).get('status')=='DONE',f"P1-010={tasks.get('P1-010',{}).get('status')}")
 passed=all(x['passed'] for x in results); report={"schemaVersion":"1.0.0","taskId":"P1-010","caseCount":len(results),"passedCount":sum(x['passed'] for x in results),"failedCount":sum(not x['passed'] for x in results),"passed":passed,"results":results}; text=json.dumps(report,indent=2,sort_keys=True)+'\n'
 if a.json_output: out=root/a.json_output; out.parent.mkdir(parents=True,exist_ok=True); out.write_text(text,encoding='utf-8',newline='\n')
 print(text,end=''); return 0 if passed else 1
if __name__=='__main__': raise SystemExit(main())
