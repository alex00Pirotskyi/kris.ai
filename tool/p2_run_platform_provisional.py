#!/usr/bin/env python3
"""Run platform evidence and guarantee a cleanup-bindable provisional V5 receipt."""
from __future__ import annotations
import argparse,hashlib,json,pathlib,subprocess,sys,time
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def obj(p):
 v=json.loads(pathlib.Path(p).read_text(encoding='utf-8'))
 if not isinstance(v,dict):raise SystemExit(f'{p}: object required')
 return v
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--project',default='.');ap.add_argument('--output',required=True);ap.add_argument('--workflow-run-id',required=True);ap.add_argument('--job-name',required=True);ap.add_argument('--artifact-name',required=True);ap.add_argument('--commit-sha',required=True);ap.add_argument('--runner-attestation',required=True);ns=ap.parse_args()
 root=pathlib.Path(ns.project).resolve();output=pathlib.Path(ns.output).resolve();att=pathlib.Path(ns.runner_attestation).resolve();output.parent.mkdir(parents=True,exist_ok=True)
 command=[sys.executable,str(root/'tool/p2_platform_ci.py'),'--project',str(root),'--output',str(output),'--workflow-run-id',ns.workflow_run_id,'--job-name',ns.job_name,'--artifact-name',ns.artifact_name,'--commit-sha',ns.commit_sha,'--runner-attestation',str(att),'--require-all']
 completed=subprocess.run(command,cwd=root,text=True,capture_output=True,stdin=subprocess.DEVNULL)
 if output.is_file():print(json.dumps({'returnCode':completed.returncode,'provisional':str(output),'sha256':sha(output)},sort_keys=True));return 0
 attestation=obj(att);exact=attestation.get('exactBinding')
 if attestation.get('receiptType')!='p2-controlled-runner-attestation-receipt-v5' or not isinstance(exact,dict):raise SystemExit('cannot emit failure receipt without exact V5 attestation binding')
 failure={'schemaVersion':'5.0.0','receiptType':'p2-task-platform-provisional-v5','phase':'P2','generatedAt':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'platform':attestation.get('platform'),'commitSha':ns.commit_sha,'workflowName':'P2 Owner Mode','workflowRunId':ns.workflow_run_id,'runAttempt':exact.get('runAttempt'),'jobName':ns.job_name,'artifactName':ns.artifact_name,'status':'provisional_blocked','sourceOnly':False,'completionEligible':False,'postRunCleanupRequired':True,'postRunCleanupObserved':False,'exactBinding':exact,'runnerAttestation':{'path':str(att),'sha256':sha(att),'runnerId':attestation.get('runnerId'),'runnerName':attestation.get('runnerName'),'runnerGroup':attestation.get('runnerGroup'),'runnerEphemeralSessionId':attestation.get('runnerEphemeralSessionId'),'workerCannotAccessAuthorityService':attestation.get('workerCannotAccessAuthorityService'),'p2ReceivesAuthoritySecrets':attestation.get('p2ReceivesAuthoritySecrets'),'postRunCleanupObserved':False},'p1AuthorityService':attestation.get('p1AuthorityService'),'taskAssertions':{},'failure':{'returnCode':completed.returncode,'stdoutSha256':hashlib.sha256(completed.stdout.encode('utf-8','replace')).hexdigest(),'stderrSha256':hashlib.sha256(completed.stderr.encode('utf-8','replace')).hexdigest()}}
 output.write_text(json.dumps(failure,indent=2,sort_keys=True)+'\n',encoding='utf-8');print(json.dumps({'returnCode':completed.returncode,'provisional':str(output),'status':'provisional_blocked'},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
