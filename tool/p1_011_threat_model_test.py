#!/usr/bin/env python3
from __future__ import annotations
import argparse,json
from pathlib import Path
def main():
 p=argparse.ArgumentParser(); p.add_argument('--project',default='.'); p.add_argument('--json-output'); a=p.parse_args(); root=Path(a.project).resolve(); results=[]
 def add(n,o,d): results.append({"name":n,"passed":bool(o),"detail":d})
 model=json.loads((root/'config/threat_model_v2.json').read_text()); boundaries=model.get('boundaries',[])
 missing_owner=[x.get('id') for x in boundaries if not x.get('owner')]; missing_test=[x.get('id') for x in boundaries if not x.get('test') or not (root/x['test']).is_file()]
 add('Every boundary has an owner',not missing_owner,str(missing_owner))
 add('Every high-risk boundary has a planned executable test',not missing_test,str(missing_test))
 ids={x.get('id') for x in boundaries}; add('Required agentic boundaries covered',{'model_to_policy','policy_to_worker','worker_ipc','manifest_trust','key_storage','audit_chain','web_content','owner_executor','updater','mcp_a2a'}<=ids,str(sorted(ids)))
 docs=(root/'docs/THREAT_MODEL_V2.md').read_text().lower(); add('Prompt injection and confused deputy documented',all(x in docs for x in ('prompt injection','confused deputy','secret','revocation','rollback')),'threat model complete')
 tasks={x['id']:x for x in json.loads((root/'docs/roadmap/roadmap.yaml').read_text())['tasks']}; add('Roadmap state',tasks.get('P1-011',{}).get('status')=='DONE',f"P1-011={tasks.get('P1-011',{}).get('status')}")
 passed=all(x['passed'] for x in results); report={"schemaVersion":"1.0.0","taskId":"P1-011","caseCount":len(results),"passedCount":sum(x['passed'] for x in results),"failedCount":sum(not x['passed'] for x in results),"passed":passed,"results":results}; text=json.dumps(report,indent=2,sort_keys=True)+'\n'
 if a.json_output: out=root/a.json_output; out.parent.mkdir(parents=True,exist_ok=True); out.write_text(text,encoding='utf-8',newline='\n')
 print(text,end=''); return 0 if passed else 1
if __name__=='__main__': raise SystemExit(main())
