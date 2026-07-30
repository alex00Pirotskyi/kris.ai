#!/usr/bin/env python3
from __future__ import annotations
import argparse,hashlib,json,os,pathlib,subprocess,sys
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from p1a_signed_evidence import canonical_bytes,sha256_file

def require(name):
    value=os.environ.get(name,'').strip()
    if not value:raise SystemExit(f'missing controlled behavioral variable: {name}')
    return value
def file_row(root:pathlib.Path,path:pathlib.Path):return {'path':path.relative_to(root).as_posix(),'sha256':sha256_file(path)}
def signed_provider(document:dict,*,purpose:str,platform:str)->dict:
    provider=require('KRISTIN_P1A_EVIDENCE_SIGNER');run=subprocess.run([provider,'sign','--purpose',purpose,'--platform',platform],input=canonical_bytes(document),capture_output=True)
    if run.returncode:raise SystemExit('external evidence signer failed')
    value=json.loads(run.stdout)
    if not isinstance(value,dict):raise SystemExit('external evidence signer object required')
    return value
def exact_binding(platform:str,project:pathlib.Path)->dict:
    return {'schemaVersion':'1.0.0','repository':require('GITHUB_REPOSITORY'),'repositoryId':int(require('GITHUB_REPOSITORY_ID')),'workflowName':require('GITHUB_WORKFLOW'),'workflowPath':'.github/workflows/p1-authority-amendment.yml','workflowRef':require('GITHUB_WORKFLOW_REF'),'gitRef':require('GITHUB_REF'),'workflowRunId':require('GITHUB_RUN_ID'),'runAttempt':int(require('GITHUB_RUN_ATTEMPT')),'jobName':require('GITHUB_JOB'),'githubJobId':int(require('KRISTIN_P1A_GITHUB_JOB_ID')),'sourceCommit':require('GITHUB_SHA'),'sourceTree':subprocess.check_output(['git','-C',str(project),'rev-parse','HEAD^{tree}'],text=True).strip(),'platform':platform,'runnerId':int(require('KRISTIN_P1A_RUNNER_ID')),'runnerName':require('RUNNER_NAME'),'runnerGroupId':int(require('KRISTIN_P1A_RUNNER_GROUP_ID')),'runnerGroup':require('KRISTIN_P1A_RUNNER_GROUP'),'runnerLabels':sorted(x for x in require('KRISTIN_P1A_RUNNER_LABELS').split(',') if x),'ephemeralSessionId':require('KRISTIN_P1A_RUNNER_EPHEMERAL_SESSION_ID')}
def main()->int:
    trust_path=pathlib.Path(require('KRISTIN_P1A_EVIDENCE_TRUST')).resolve();expected_trust=require('KRISTIN_P1A_EVIDENCE_TRUST_SHA256').lower()
    if not trust_path.is_file() or sha256_file(trust_path)!=expected_trust:raise SystemExit('controlled runner evidence trust does not match protected repository digest')
    p=argparse.ArgumentParser();p.add_argument('--project',required=True);p.add_argument('--platform',choices=('windows','macos','linux'),required=True);p.add_argument('--service-binary',required=True);p.add_argument('--connector',required=True);p.add_argument('--worker-launcher',required=True);p.add_argument('--installer',required=True);p.add_argument('--uninstaller',required=True);p.add_argument('--output',required=True);a=p.parse_args();project=pathlib.Path(a.project).resolve();output=pathlib.Path(a.output).resolve();artifact=output/'artifacts';artifact.mkdir(parents=True,exist_ok=True);exact=exact_binding(a.platform,project)
    provider=require('KRISTIN_P1A_RUNNER_ATTESTATION_PROVIDER');request={'schemaVersion':'1.0.0','operation':'run-p1a-v63-behavioral','platform':a.platform,'exactBinding':exact,'packageSha256':require('KRISTIN_P1A_PACKAGE_SHA256'),'serviceBinary':str(pathlib.Path(a.service_binary).resolve()),'connector':str(pathlib.Path(a.connector).resolve()),'workerLauncher':str(pathlib.Path(a.worker_launcher).resolve()),'installer':str(pathlib.Path(a.installer).resolve()),'uninstaller':str(pathlib.Path(a.uninstaller).resolve()),'artifactDirectory':str(artifact)}
    run=subprocess.run([provider,'execute-p1a-v63'],input=canonical_bytes(request),capture_output=True)
    if run.returncode:raise SystemExit('controlled runner behavioral provider failed: '+run.stderr.decode(errors='ignore')[-500:])
    result=json.loads(run.stdout)
    if not isinstance(result,dict) or result.get('status')!='passed':raise SystemExit('controlled runner behavioral provider did not pass')
    names=('runnerAttestation','buildProvenance','installerReceipt','keyProviderReceipt','workerDenialReceipt','serviceBehaviorReceipt','cleanupReceipt','githubApiVerification');components={}
    for name in names:
        path=artifact/f'{name}.json'
        if not path.is_file():raise SystemExit(f'missing controlled behavioral component: {name}')
        components[name]=file_row(artifact,path)
    digest=hashlib.sha256()
    for path in sorted((x for x in artifact.rglob('*') if x.is_file()),key=lambda x:x.relative_to(artifact).as_posix()):
        rel=path.relative_to(artifact).as_posix().encode();data=path.read_bytes();digest.update(len(rel).to_bytes(8,'big'));digest.update(rel);digest.update(len(data).to_bytes(8,'big'));digest.update(hashlib.sha256(data).digest())
    receipt={'schemaVersion':'3.0.0','receiptType':'p1a-platform-behavioral-v3','phase':'P1A','platform':a.platform,'sourceCommit':exact['sourceCommit'],'sourceTree':exact['sourceTree'],'packageSha256':require('KRISTIN_P1A_PACKAGE_SHA256'),'status':'passed','sourceOnly':False,'completionEligible':True,'syntheticContractFixture':False,'exactBinding':exact,'exactRunBindingSha256':hashlib.sha256(canonical_bytes(exact)).hexdigest(),'artifactRoot':'artifacts','artifactDigestAlgorithm':'canonical-unpacked-v1','artifactSha256':digest.hexdigest(),**components}
    receipt['signature']=signed_provider(receipt,purpose='p1a-platform-receipt',platform=a.platform)
    (output/f'{a.platform}.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n');print(json.dumps({'status':'passed','platform':a.platform,'receipt':str(output/f'{a.platform}.json')},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
