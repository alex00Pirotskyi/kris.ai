#!/usr/bin/env python3
from __future__ import annotations
import argparse,json
from pathlib import Path
def main():
 p=argparse.ArgumentParser(); p.add_argument('--project',default='.'); p.add_argument('--json-output'); a=p.parse_args(); root=Path(a.project).resolve(); results=[]
 def add(n,o,d): results.append({"name":n,"passed":bool(o),"detail":d})
 config=json.loads((root/'config/tuf_trust.v1.json').read_text()); roles=config.get('roles',{})
 add('Four TUF top-level roles',set(roles)=={'root','targets','snapshot','timestamp'},str(sorted(roles)))
 add('Offline threshold root',roles.get('root',{}).get('offline') is True and roles.get('root',{}).get('threshold',0)>=2,str(roles.get('root')))
 add('Rollback freeze and mix-and-match defenses',{'rollback','freeze','mix_and_match'}<=set(config.get('protections',[])),str(config.get('protections')))
 docs=(root/'docs/adr/ADR-0006-update-system.md').read_text()+(root/'docs/security/TUF_KEY_CEREMONY.md').read_text(); add('Rotation and recovery runbooks',all(x in docs.lower() for x in ('root rotation','compromise','recovery','threshold')),'runbooks approved')
 tasks={x['id']:x for x in json.loads((root/'docs/roadmap/roadmap.yaml').read_text())['tasks']}; add('Roadmap state',tasks.get('P1-008',{}).get('status')=='DONE',f"P1-008={tasks.get('P1-008',{}).get('status')}")
 passed=all(x['passed'] for x in results); report={"schemaVersion":"1.0.0","taskId":"P1-008","caseCount":len(results),"passedCount":sum(x['passed'] for x in results),"failedCount":sum(not x['passed'] for x in results),"passed":passed,"results":results}; text=json.dumps(report,indent=2,sort_keys=True)+'\n'
 if a.json_output: out=root/a.json_output; out.parent.mkdir(parents=True,exist_ok=True); out.write_text(text,encoding='utf-8',newline='\n')
 print(text,end=''); return 0 if passed else 1
if __name__=='__main__': raise SystemExit(main())
