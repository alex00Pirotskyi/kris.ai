#!/usr/bin/env python3
"""Invoke and verify separately signed exact-job post-run cleanup V2."""
from __future__ import annotations
import argparse,datetime as dt,hashlib,json,os,pathlib,re,subprocess,sys,tempfile
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent));from ed25519_ref import verify
HEX64=re.compile(r'^[0-9a-f]{64}$');HEX128=re.compile(r'^[0-9a-f]{128}$')
BINDING=('repository','repositoryId','workflowName','workflowPath','workflowFileSha256','workflowRef','workflowRunId','runAttempt','jobName','githubJobId','sourceCommit','runnerId','runnerName','runnerGroup','runnerGroupId','githubJobIdentitySha256','runnerEphemeralSessionId')
ASSERTIONS=('managedProcessTreesTerminated','zeroSurvivingDescendants','controlledUserServicesStoppedAndRemoved','controlledPackagesRemoved','clipboardTestDataCleared','screenArtifactsRemoved','authorityEvidenceArtifactsCleared','workspacesRemoved','noTestSecretsRemaining','noConcurrentUntrustedWorkload')
def canonical(v):return (json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False)+'\n').encode()
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def obj(p):
 v=json.loads(pathlib.Path(p).read_text(encoding='utf-8'))
 if not isinstance(v,dict):raise SystemExit(f'{p}: object required')
 return v
def env(k):
 v=os.environ.get(k,'').strip()
 if not v:raise SystemExit(f'{k} required')
 return v
def main():
 a=argparse.ArgumentParser();a.add_argument('--attestation-receipt',required=True);a.add_argument('--provisional-receipt',required=True);a.add_argument('--policy',required=True);a.add_argument('--output',required=True);a.add_argument('--provider-timeout-seconds',type=int,default=300);n=a.parse_args()
 ap=pathlib.Path(n.attestation_receipt).resolve();pp=pathlib.Path(n.provisional_receipt).resolve();polp=pathlib.Path(n.policy).resolve();out=pathlib.Path(n.output).resolve();att=obj(ap);pro=obj(pp);policy=obj(polp)
 if policy.get('schemaVersion')!='5.0.0' or policy.get('policyType')!='p2-controlled-runner-policy-v5' or policy.get('postRunCleanupBinding')!='exact-signed-cleanup-after-current-job':raise SystemExit('cleanup policy V5 invalid')
 if att.get('schemaVersion')!='5.0.0' or att.get('receiptType')!='p2-controlled-runner-attestation-receipt-v5' or att.get('status')!='passed' or att.get('postRunCleanupObserved') is not False:raise SystemExit('pre-run attestation V5 invalid')
 if pro.get('schemaVersion')!='5.0.0' or pro.get('receiptType')!='p2-task-platform-provisional-v5' or pro.get('completionEligible') is not False or pro.get('postRunCleanupObserved') is not False:raise SystemExit('provisional receipt V5 invalid')
 binding=dict(att.get('exactBinding') or {})
 if set(BINDING)-set(binding) or pro.get('exactBinding')!=binding:raise SystemExit('attestation/provisional exact binding mismatch')
 workflow_file=pathlib.Path(os.environ.get('GITHUB_WORKSPACE','')).resolve()/'.github/workflows/p2-owner-mode.yml'
 if not workflow_file.is_file():raise SystemExit('current workflow source unavailable for cleanup binding')
 current={'repository':env('GITHUB_REPOSITORY'),'repositoryId':int(env('GITHUB_REPOSITORY_ID')),'workflowName':env('GITHUB_WORKFLOW'),'workflowPath':'.github/workflows/p2-owner-mode.yml','workflowFileSha256':sha(workflow_file),'workflowRef':env('GITHUB_WORKFLOW_REF'),'workflowRunId':env('GITHUB_RUN_ID'),'runAttempt':int(env('GITHUB_RUN_ATTEMPT')),'jobName':env('GITHUB_JOB'),'githubJobId':int(env('KRISTIN_P2_GITHUB_JOB_ID')),'sourceCommit':env('GITHUB_SHA'),'runnerId':int(env('KRISTIN_P2_RUNNER_ID')),'runnerName':env('RUNNER_NAME'),'runnerGroup':env('KRISTIN_P2_RUNNER_GROUP'),'runnerGroupId':int(env('KRISTIN_P2_RUNNER_GROUP_ID')),'githubJobIdentitySha256':env('KRISTIN_P2_GITHUB_JOB_IDENTITY_SHA256'),'runnerEphemeralSessionId':env('KRISTIN_P2_RUNNER_EPHEMERAL_SESSION_ID')}
 for k,v in current.items():
  if binding.get(k)!=v:raise SystemExit(f'cleanup current-job binding mismatch: {k}')
 provider_row=att.get('postRunCleanupProvider');provider=pathlib.Path(str((provider_row or {}).get('path',''))).resolve();pd=str((provider_row or {}).get('sha256','')).lower()
 if not provider.is_file() or provider.is_symlink() or not HEX64.fullmatch(pd) or sha(provider)!=pd:raise SystemExit('cleanup provider unavailable/digest changed')
 managed={k:v for k,v in (att.get('resolvedResources') or {}).items() if k not in ('p1AuthorityServiceMergedManifest','p1AuthorityServicePlatformReceipt','p1AuthorityServiceEvidenceTrust')}
 request={'schemaVersion':'2.0.0','requestType':'p2-post-run-cleanup-v2',**binding,'platform':att.get('platform'),'attestationReceiptSha256':sha(ap),'provisionalReceiptSha256':sha(pp),'policySha256':sha(polp),'providerSha256':pd,'provisionalStatus':pro.get('status'),'managedResources':managed,'externalAuthorityEvidenceRoot':(att.get('resolvedRoots') or {}).get('p1AuthorityServiceEvidenceRoot'),'requestedAt':dt.datetime.now(dt.timezone.utc).isoformat()}
 with tempfile.TemporaryDirectory(prefix='p2-cleanup-v63-') as td:
  req=pathlib.Path(td)/'request.json';raw=pathlib.Path(td)/'signed.json';req.write_text(json.dumps(request,indent=2,sort_keys=True)+'\n')
  allowed={'PATH','Path','SystemRoot','WINDIR','HOME','USERPROFILE','TMP','TEMP','XDG_RUNTIME_DIR','DBUS_SESSION_BUS_ADDRESS','DISPLAY','WAYLAND_DISPLAY'}
  provider_argv=([sys.executable,str(provider)] if provider.suffix.lower()=='.py' else [str(provider)])+['--request',str(req),'--output',str(raw)]
  run=subprocess.run(provider_argv,stdin=subprocess.DEVNULL,capture_output=True,text=True,timeout=n.provider_timeout_seconds,env={k:v for k,v in os.environ.items() if k in allowed})
  if run.returncode!=0 or not raw.is_file() or raw.stat().st_size>1024*1024:raise SystemExit('post-run cleanup provider failed')
  signed=obj(raw);body=dict(signed);sig=str(body.pop('signatureHex','')).lower();public=str(body.get('publicKeyHex','')).lower()
  if public not in set(map(str,policy.get('cleanupTrustRoots',[]))) or not HEX128.fullmatch(sig) or not verify(bytes.fromhex(public),canonical(body),bytes.fromhex(sig)):raise SystemExit('cleanup signature invalid/untrusted')
  if body.get('schemaVersion')!='2.0.0' or body.get('cleanupType')!='p2-post-run-cleanup-receipt-v2' or body.get('status')!='passed':raise SystemExit('cleanup receipt V2 invalid')
  for k in BINDING:
   if body.get(k)!=binding.get(k):raise SystemExit(f'signed cleanup binding mismatch: {k}')
  for k,v in request.items():
   if k in ('schemaVersion','requestType'):continue
   if body.get(k)!=v:raise SystemExit(f'cleanup request binding mismatch: {k}')
  assertions=body.get('assertions')
  if not isinstance(assertions,dict) or any(assertions.get(k) is not True for k in ASSERTIONS):raise SystemExit('cleanup assertion absent/failed')
  started=dt.datetime.fromisoformat(str(body.get('startedAt','')).replace('Z','+00:00'));completed=dt.datetime.fromisoformat(str(body.get('completedAt','')).replace('Z','+00:00'));now=dt.datetime.now(dt.timezone.utc)
  if completed<started or completed>now+dt.timedelta(seconds=30) or (now-completed).total_seconds()>int(policy.get('maximumCleanupAgeSeconds',1800)):raise SystemExit('cleanup time invalid')
  receipt={'schemaVersion':'2.0.0','receiptType':'p2-validated-post-run-cleanup-v2','status':'passed','signedCleanup':{**body,'signatureHex':sig},'signedCleanupSha256':sha(raw),'attestationReceiptSha256':sha(ap),'provisionalReceiptSha256':sha(pp),'policySha256':sha(polp),'providerSha256':pd,'exactBinding':binding,'assertions':assertions,'completionEligibleForPlatformFinalization':True}
  out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n');print(json.dumps({'cleanupReceipt':str(out),'sha256':sha(out),'status':'passed'},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
