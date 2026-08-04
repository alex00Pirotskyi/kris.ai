#!/usr/bin/env python3
"""Resolve the exact current Actions job/runner from GitHub's API."""
from __future__ import annotations
import argparse,hashlib,json,os,pathlib,time,urllib.request,urllib.error
def required(k):
 v=os.environ.get(k,'').strip()
 if not v:raise SystemExit(f'{k} required')
 return v
def canonical(v):return (json.dumps(v,sort_keys=True,separators=(',',':'))+'\n').encode()
def main():
 a=argparse.ArgumentParser();a.add_argument('--output',required=True);a.add_argument('--github-env',required=True);a.add_argument('--platform',choices=('linux','macos','windows'),required=True);a.add_argument('--job-name',required=True);a.add_argument('--commit-sha',required=True);n=a.parse_args()
 repo=required('GITHUB_REPOSITORY');rid=required('GITHUB_RUN_ID');attempt=required('GITHUB_RUN_ATTEMPT');token=required('GITHUB_TOKEN');runner=required('RUNNER_NAME')
 if len(n.commit_sha)!=40:raise SystemExit('exact commit required')
 url=f'https://api.github.com/repos/{repo}/actions/runs/{rid}/attempts/{attempt}/jobs?per_page=100';selected=None;deadline=time.monotonic()+90;last=''
 while time.monotonic()<deadline:
  try:
   req=urllib.request.Request(url,headers={'Accept':'application/vnd.github+json','Authorization':f'Bearer {token}','X-GitHub-Api-Version':'2022-11-28','User-Agent':'kristin-p2-v63'})
   with urllib.request.urlopen(req,timeout=30) as r:data=json.loads(r.read())
   m=[j for j in data.get('jobs',[]) if j.get('name')==n.job_name and j.get('runner_name')==runner]
   if len(m)==1:selected=m[0];break
   last=f'matches={len(m)}'
  except Exception as e:last=repr(e)
  time.sleep(3)
 if selected is None:raise SystemExit(f'exact current GitHub job unresolved: {last}')
 labels=list(map(str,selected.get('labels') or []));need={'self-hosted','kristin-p2',n.platform,'interactive-desktop',{'linux':'ubuntu-24.04','macos':'macos-15','windows':'windows-2025'}[n.platform]}
 if not need.issubset(labels):raise SystemExit('GitHub job labels mismatch')
 runner_group=str(selected.get('runner_group_name') or '')
 if runner_group!='kristin-p2-controlled':raise SystemExit(f'unexpected P2 runner group: {runner_group!r}')
 row={'schemaVersion':'1.0.0','receiptType':'p2-github-job-identity-v1','repository':repo,'repositoryId':int(required('GITHUB_REPOSITORY_ID')),'workflowName':required('GITHUB_WORKFLOW'),'workflowPath':'.github/workflows/p2-owner-mode.yml','workflowRef':required('GITHUB_WORKFLOW_REF'),'workflowRunId':rid,'runAttempt':int(attempt),'jobName':n.job_name,'githubJobId':int(selected['id']),'sourceCommit':n.commit_sha,'runnerId':int(selected['runner_id']),'runnerName':str(selected['runner_name']),'runnerGroupId':int(selected['runner_group_id']),'runnerGroup':runner_group,'labels':labels,'platform':n.platform,'apiPayloadSha256':hashlib.sha256(canonical(selected)).hexdigest(),'status':'observed'}
 out=pathlib.Path(n.output).resolve();out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(row,indent=2,sort_keys=True)+'\n');d=hashlib.sha256(out.read_bytes()).hexdigest()
 with pathlib.Path(n.github_env).open('a',encoding='utf-8') as f:
  for k,v in {'KRISTIN_P2_GITHUB_JOB_ID':row['githubJobId'],'KRISTIN_P2_RUNNER_ID':row['runnerId'],'KRISTIN_P2_RUNNER_GROUP_ID':row['runnerGroupId'],'KRISTIN_P2_RUNNER_GROUP':row['runnerGroup'],'KRISTIN_P2_GITHUB_JOB_IDENTITY_RECEIPT':out,'KRISTIN_P2_GITHUB_JOB_IDENTITY_SHA256':d}.items():f.write(f'{k}={v}\n')
 print(json.dumps({'receipt':str(out),'sha256':d},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
