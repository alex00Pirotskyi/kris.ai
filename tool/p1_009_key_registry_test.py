#!/usr/bin/env python3
from __future__ import annotations
import argparse,importlib.util,json,sys
from pathlib import Path
def load(path):
 spec=importlib.util.spec_from_file_location('keys',path); m=importlib.util.module_from_spec(spec); sys.modules['keys']=m; spec.loader.exec_module(m); return m
def main():
 p=argparse.ArgumentParser(); p.add_argument('--project',default='.'); p.add_argument('--json-output'); a=p.parse_args(); root=Path(a.project).resolve(); results=[]
 def add(n,o,d): results.append({"name":n,"passed":bool(o),"detail":d})
 m=load(root/'tool/key_registry_v2.py'); h=m.ProtectedKeyHandle('k1','manifest_signing','ephemeral_test','vault://test/k1','aa','kristin.test'); r=m.ProtectedKeyRegistry(); r.register(h)
 exported=json.dumps(r.export_public_registry()).lower(); add('No private material in registry export',all(x not in exported for x in ('privatekey','seed','keymaterial','rawsecret','secret=')),exported)
 add('Purpose and trust-domain binding',r.resolve('k1',purpose='manifest_signing',trust_domain='kristin.test').key_id=='k1','resolved exact handle')
 r.revoke('k1'); revoked=False
 try: r.resolve('k1',purpose='manifest_signing',trust_domain='kristin.test')
 except m.KeyRegistryError as e: revoked=e.code=='key_revoked'
 add('Revocation fails closed',revoked,'revoked key rejected')
 config=json.loads((root/'config/key_storage.v2.json').read_text()); add('OS protected providers declared',set(config.get('providers',{}))=={'windows','macos','linux','external'},str(config.get('providers')))
 tasks={x['id']:x for x in json.loads((root/'docs/roadmap/roadmap.yaml').read_text())['tasks']}; add('Roadmap state',tasks.get('P1-009',{}).get('status')=='DONE',f"P1-009={tasks.get('P1-009',{}).get('status')}")
 passed=all(x['passed'] for x in results); report={"schemaVersion":"1.0.0","taskId":"P1-009","caseCount":len(results),"passedCount":sum(x['passed'] for x in results),"failedCount":sum(not x['passed'] for x in results),"passed":passed,"results":results}; text=json.dumps(report,indent=2,sort_keys=True)+'\n'
 if a.json_output: out=root/a.json_output; out.parent.mkdir(parents=True,exist_ok=True); out.write_text(text,encoding='utf-8',newline='\n')
 print(text,end=''); return 0 if passed else 1
if __name__=='__main__': raise SystemExit(main())
