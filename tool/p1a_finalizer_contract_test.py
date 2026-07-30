#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,pathlib,shutil,subprocess,sys,tempfile

def dump(path,value):
 path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')

def main():
 a=argparse.ArgumentParser();a.add_argument('--project',default='.');n=a.parse_args();source=pathlib.Path(n.project).resolve()
 with tempfile.TemporaryDirectory(prefix='p1a-v63-finalizer-contract-') as td:
  t=pathlib.Path(td);project=t/'project';shutil.copytree(source,project,ignore=shutil.ignore_patterns('__pycache__','*.pyc','build','.dart_tool'))
  shutil.rmtree(project/'tasks/completed',ignore_errors=True);(project/'tasks/completed').mkdir(parents=True)
  commit='a'*40;tree='b'*40;package='c'*64
  trust=t/'trust.json';dump(trust,{'schemaVersion':'1.0.0','trustType':'p1a-evidence-trust-v1','keys':{}})
  receipts=[]
  for platform in ('windows','macos','linux'):
   p=t/f'{platform}.json';dump(p,{'schemaVersion':'3.0.0','receiptType':'p1a-platform-behavioral-v3','phase':'P1A','platform':platform,'sourceCommit':commit,'sourceTree':tree,'packageSha256':package,'status':'passed','sourceOnly':False,'completionEligible':True,'syntheticContractFixture':True});receipts.append(p)
  review=t/'review.json';dump(review,{'schemaVersion':'3.0.0','independent':True,'decision':'approve','reviewedCommit':commit,'reviewedTree':tree,'packageSha256':package,'syntheticContractFixture':True})
  owner=t/'owner.json';dump(owner,{'schemaVersion':'3.0.0','approved':True,'reviewedCommit':commit,'reviewedTree':tree,'packageSha256':package,'syntheticContractFixture':True})
  command=[sys.executable,str(project/'tool/p1a_finalize_evidence.py'),'--project',str(project),'--reviewed-commit',commit,'--reviewed-tree',tree,'--package-sha256',package,'--security-review',str(review),'--owner-approval',str(owner),'--evidence-trust',str(trust),'--github-repo','owner/repo']
  for receipt in receipts:command.extend(['--platform-receipt',str(receipt)])
  result=subprocess.run(command,text=True,capture_output=True)
  if result.returncode==0:raise SystemExit('P1A finalizer promoted unsigned/synthetic receipts')
  if (project/'tasks/completed/P1A-001.md').exists():raise SystemExit('P1A completed packet created on rejected evidence')
  aggregate=json.loads((project/'release/evidence/P1A/manifest.json').read_text())
  if aggregate.get('completionClaim') is not False or aggregate.get('p2DependencySatisfied') is not False:raise SystemExit('P1A aggregate promoted on rejected evidence')
 print('P1A V63 strict finalizer no-promotion contract: PASS')
 return 0
if __name__=='__main__':raise SystemExit(main())
