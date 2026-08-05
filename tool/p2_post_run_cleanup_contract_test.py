#!/usr/bin/env python3
from __future__ import annotations
import datetime as dt,hashlib,json,os,pathlib,subprocess,sys,tempfile
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from ed25519_ref import public_key,sign
SEED=bytes.fromhex('43'*32)
BINDING=('repository','repositoryId','workflowName','workflowPath','workflowFileSha256','workflowRef','workflowRunId','runAttempt','jobName','githubJobId','sourceCommit','runnerId','runnerName','runnerGroup','runnerGroupId','githubJobIdentitySha256','runnerEphemeralSessionId')
ASSERTIONS=('managedProcessTreesTerminated','zeroSurvivingDescendants','controlledUserServicesStoppedAndRemoved','controlledPackagesRemoved','clipboardTestDataCleared','screenArtifactsRemoved','authorityEvidenceArtifactsCleared','workspacesRemoved','noTestSecretsRemaining','noConcurrentUntrustedWorkload')
def canonical(v):return (json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False)+'\n').encode()
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def dump(p,v):pathlib.Path(p).parent.mkdir(parents=True,exist_ok=True);pathlib.Path(p).write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')
def main():
 with tempfile.TemporaryDirectory(prefix='p2-v63-cleanup-contract-') as td:
  t=pathlib.Path(td);project=t/'project';(project/'.github/workflows').mkdir(parents=True);workflow=project/'.github/workflows/p2-owner-mode.yml';workflow.write_text('name: P2 Owner Mode\n')
  provider=t/'provider.py'
  provider.write_text('''#!/usr/bin/env python3\nimport argparse,datetime as dt,json,pathlib,sys\nfrom cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey\nfrom cryptography.hazmat.primitives import serialization\nSEED=bytes.fromhex("43"*32)\nKEY=Ed25519PrivateKey.from_private_bytes(SEED)\ndef public_key(_seed):return KEY.public_key().public_bytes(serialization.Encoding.Raw,serialization.PublicFormat.Raw)\ndef sign(_seed,message):return KEY.sign(message)\ndef canonical(v):return (json.dumps(v,sort_keys=True,separators=(",",":"),ensure_ascii=False)+"\\n").encode()\na=argparse.ArgumentParser();a.add_argument("--request");a.add_argument("--output");n=a.parse_args();r=json.loads(pathlib.Path(n.request).read_text());now=dt.datetime.now(dt.timezone.utc).isoformat();keys=%r\nb={"schemaVersion":"2.0.0","cleanupType":"p2-post-run-cleanup-receipt-v2",**{k:r[k] for k in keys},"platform":r["platform"],"attestationReceiptSha256":r["attestationReceiptSha256"],"provisionalReceiptSha256":r["provisionalReceiptSha256"],"policySha256":r["policySha256"],"providerSha256":r["providerSha256"],"provisionalStatus":r["provisionalStatus"],"managedResources":r["managedResources"],"externalAuthorityEvidenceRoot":r["externalAuthorityEvidenceRoot"],"requestedAt":r["requestedAt"],"startedAt":now,"completedAt":now,"assertions":{k:True for k in %r},"status":"passed","publicKeyHex":public_key(SEED).hex()}\nb["signatureHex"]=sign(SEED,canonical(b)).hex();pathlib.Path(n.output).write_text(json.dumps(b,sort_keys=True,indent=2)+"\\n")\n'''%(BINDING,ASSERTIONS));provider.chmod(0o755)
  source='a'*40;digest='b'*64
  binding={'repository':'owner/repo','repositoryId':1,'workflowName':'P2 Owner Mode','workflowPath':'.github/workflows/p2-owner-mode.yml','workflowFileSha256':sha(workflow),'workflowRef':'owner/repo/.github/workflows/p2-owner-mode.yml@refs/heads/test','workflowRunId':'11','runAttempt':1,'jobName':'p2-behavioral-linux','githubJobId':22,'sourceCommit':source,'runnerId':33,'runnerName':'runner-linux','runnerGroup':'kristin-p2-controlled','runnerGroupId':44,'githubJobIdentitySha256':digest,'runnerEphemeralSessionId':'session-v63-linux'}
  p1a=t/'p1a';p1a.mkdir()
  managed=t/'managed';managed.mkdir()
  att={'schemaVersion':'5.0.0','receiptType':'p2-controlled-runner-attestation-receipt-v5','status':'passed','platform':'linux','exactBinding':binding,'resolvedResources':{'e2eWorkspaceRoot':{'kind':'directory','path':str(managed)}},'resolvedRoots':{'p1AuthorityServiceEvidenceRoot':str(p1a)},'p1AuthorityService':{'mergedManifestSha256':digest},'workerCannotAccessAuthorityService':True,'p2ReceivesAuthoritySecrets':False,'postRunCleanupProvider':{'path':str(provider),'sha256':sha(provider)},'postRunCleanupObserved':False,'completionEligibleForTaskClosure':False};attp=t/'att.json';dump(attp,att)
  provisional={'schemaVersion':'5.0.0','receiptType':'p2-task-platform-provisional-v5','phase':'P2','status':'provisional_passed','completionEligible':False,'postRunCleanupObserved':False,'exactBinding':binding,'taskAssertions':{'P2-001':{'status':'passed'}}};pp=t/'provisional.json';dump(pp,provisional)
  policy={'schemaVersion':'5.0.0','policyType':'p2-controlled-runner-policy-v5','postRunCleanupBinding':'exact-signed-cleanup-after-current-job','cleanupTrustRoots':[public_key(SEED).hex()],'maximumCleanupAgeSeconds':1800};pol=t/'policy.json';dump(pol,policy)
  env={**os.environ,'GITHUB_WORKSPACE':str(project),'GITHUB_REPOSITORY':binding['repository'],'GITHUB_REPOSITORY_ID':str(binding['repositoryId']),'GITHUB_WORKFLOW':binding['workflowName'],'GITHUB_WORKFLOW_REF':binding['workflowRef'],'GITHUB_RUN_ID':binding['workflowRunId'],'GITHUB_RUN_ATTEMPT':str(binding['runAttempt']),'GITHUB_JOB':binding['jobName'],'KRISTIN_P2_GITHUB_JOB_ID':str(binding['githubJobId']),'GITHUB_SHA':source,'KRISTIN_P2_RUNNER_ID':str(binding['runnerId']),'RUNNER_NAME':binding['runnerName'],'KRISTIN_P2_RUNNER_GROUP':binding['runnerGroup'],'KRISTIN_P2_RUNNER_GROUP_ID':str(binding['runnerGroupId']),'KRISTIN_P2_GITHUB_JOB_IDENTITY_SHA256':binding['githubJobIdentitySha256'],'KRISTIN_P2_RUNNER_EPHEMERAL_SESSION_ID':binding['runnerEphemeralSessionId']}
  cleanup=t/'cleanup.json';script=pathlib.Path(__file__).resolve().parent/'p2_post_run_cleanup.py'
  r=subprocess.run([sys.executable,str(script),'--attestation-receipt',str(attp),'--provisional-receipt',str(pp),'--policy',str(pol),'--output',str(cleanup)],env=env,capture_output=True,text=True)
  assert r.returncode==0,(r.stdout,r.stderr)
  row=json.loads(cleanup.read_text());assert row['receiptType']=='p2-validated-post-run-cleanup-v2' and row['assertions']['authorityEvidenceArtifactsCleared'] is True
  receipt_dir=t/'receipts';receipt_dir.mkdir();artifact=receipt_dir/'artifact';artifact.mkdir();pp2=receipt_dir/'provisional.json';cleanup2=receipt_dir/'cleanup.json';pp2.write_bytes(pp.read_bytes());cleanup2.write_bytes(cleanup.read_bytes())
  # Rebind cleanup digest after copy, because the validator intentionally binds exact bytes.
  c=json.loads(cleanup2.read_text());c['provisionalReceiptSha256']=sha(pp2);dump(cleanup2,c)
  final=receipt_dir/'final.json';finalizer=script.parent/'p2_finalize_platform_after_cleanup.py'
  q=subprocess.run([sys.executable,str(finalizer),'--provisional',str(pp2),'--cleanup',str(cleanup2),'--output',str(final)],capture_output=True,text=True)
  assert q.returncode==0,(q.stdout,q.stderr)
  out=json.loads(final.read_text());assert out['receiptType']=='p2-task-platform-behavioral-v5' and out['completionEligible'] is True
  bad=json.loads(cleanup2.read_text());bad['assertions']['authorityEvidenceArtifactsCleared']=False;dump(cleanup2,bad)
  rejected=subprocess.run([sys.executable,str(finalizer),'--provisional',str(pp2),'--cleanup',str(cleanup2),'--output',str(receipt_dir/'bad.json')],capture_output=True,text=True)
  assert rejected.returncode!=0
 print('P2 V63 exact post-run cleanup V2 contract: PASS')
 return 0
if __name__=='__main__':raise SystemExit(main())
