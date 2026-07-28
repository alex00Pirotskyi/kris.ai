#!/usr/bin/env python3
from __future__ import annotations
import argparse,json
from pathlib import Path
def main():
 p=argparse.ArgumentParser(); p.add_argument('--project',default='.'); p.add_argument('--json-output'); a=p.parse_args(); root=Path(a.project).resolve(); results=[]
 def add(n,o,d): results.append({"name":n,"passed":bool(o),"detail":d})
 value=json.loads((root/'docs/roadmap/integration_trains.json').read_text()); trains=value.get('trains',[])
 add('Exactly twelve integration trains',len(trains)==12,f"count={len(trains)}")
 add('Unique sequential train ids',[x.get('id') for x in trains]==[f'TRAIN-{i:02d}' for i in range(1,13)],str([x.get('id') for x in trains]))
 p1=set(next(x for x in trains if x['id']=='TRAIN-01').get('tasks',[])); add('P1 closure train contains every remaining P1 task',p1=={f'P1-{i:03d}' for i in range(4,13)},str(sorted(p1)))
 add('Canonical task graph preserved',value.get('canonicalTaskGraphPreserved') is True,'bundling changes PR cadence, not acceptance criteria')
 add('Next train ready',trains[0].get('status')=='DONE' and trains[1].get('status')=='READY','TRAIN-02 ready')
 passed=all(x['passed'] for x in results); report={"schemaVersion":"1.0.0","testId":"integration-trains","caseCount":len(results),"passedCount":sum(x['passed'] for x in results),"failedCount":sum(not x['passed'] for x in results),"passed":passed,"results":results}; text=json.dumps(report,indent=2,sort_keys=True)+'\n'
 if a.json_output: out=root/a.json_output; out.parent.mkdir(parents=True,exist_ok=True); out.write_text(text,encoding='utf-8',newline='\n')
 print(text,end=''); return 0 if passed else 1
if __name__=='__main__': raise SystemExit(main())
