#!/usr/bin/env python3
from __future__ import annotations
import argparse,importlib.util,json,sys
from pathlib import Path

def load(path):
 spec=importlib.util.spec_from_file_location('compat',path); m=importlib.util.module_from_spec(spec); sys.modules['compat']=m; spec.loader.exec_module(m); return m

def main():
 p=argparse.ArgumentParser(); p.add_argument('--project',default='.'); p.add_argument('--json-output'); a=p.parse_args(); root=Path(a.project).resolve(); results=[]
 def add(n,o,d): results.append({"name":n,"passed":bool(o),"detail":d})
 m=load(root/'tool/manifest_compatibility_v2.py'); observed={}
 cases={'v1':{'schemaVersion':'1.0.0'},'mixed':{'schemaVersion':'2.0.0','hmac':'attacker'},'unknown':{'schemaVersion':'3.0.0'}}
 for name,value in cases.items():
  try: m.classify_manifest(value)
  except m.ManifestCompatibilityError as e: observed[name]=e.code
 add('Downgrade and mixed-format rejection',observed=={'v1':'v1_trust_disabled','mixed':'mixed_format_rejected','unknown':'unsupported_manifest_version'},str(observed))
 add('Clean v2 accepted',m.classify_manifest({'schemaVersion':'2.0.0'})=='signed_manifest_v2','v2 accepted')
 legacy=(root/'tool/interoperability_v19.py').read_text(); add('Legacy production trust remains disabled','v1_trust_disabled' in legacy,'P0-002 invariant preserved')
 tasks={x['id']:x for x in json.loads((root/'docs/roadmap/roadmap.yaml').read_text())['tasks']}; add('Roadmap state',tasks.get('P1-007',{}).get('status')=='DONE',f"P1-007={tasks.get('P1-007',{}).get('status')}")
 passed=all(x['passed'] for x in results); report={"schemaVersion":"1.0.0","taskId":"P1-007","caseCount":len(results),"passedCount":sum(x['passed'] for x in results),"failedCount":sum(not x['passed'] for x in results),"passed":passed,"results":results}; text=json.dumps(report,indent=2,sort_keys=True)+'\n'
 if a.json_output: out=root/a.json_output; out.parent.mkdir(parents=True,exist_ok=True); out.write_text(text,encoding='utf-8',newline='\n')
 print(text,end=''); return 0 if passed else 1
if __name__=='__main__': raise SystemExit(main())
