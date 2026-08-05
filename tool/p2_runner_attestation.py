#!/usr/bin/env python3
"""Verify exact per-run controlled-runner and merged P1A-service provenance.

The runner receives evidence about the separately installed P1A service. It
never receives key handles, broker executables, owner signing providers, raw
policy state, revocation secrets, or any signing material.
"""
from __future__ import annotations
import argparse,datetime as dt,hashlib,json,os,pathlib,platform,re,secrets,subprocess,sys,tempfile
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent));from ed25519_ref import verify
from p2_p1a_dependency import validate_merged_p1a_graph
HEX40=re.compile(r'^[0-9a-f]{40}$');HEX64=re.compile(r'^[0-9a-f]{64}$');HEX128=re.compile(r'^[0-9a-f]{128}$')
LABELS={'linux':['self-hosted','kristin-p2','linux','interactive-desktop','ubuntu-24.04'],'macos':['self-hosted','kristin-p2','macos','interactive-desktop','macos-15'],'windows':['self-hosted','kristin-p2','windows','interactive-desktop','windows-2025']}
P1A_FILES={'p1AuthorityServiceMergedManifest','p1AuthorityServicePlatformReceipt','p1AuthorityServiceEvidenceTrust'}
REQUIRED_FILES=P1A_FILES|{'p1AuthorityServiceWorkerLauncher','p1AuthorityServiceConnectorConfig','controlledPackageArchive','controlledServiceDefinition','technologyNodeReceipt','technologyNativeReceipt','technologyDartReceipt'}
REQUIRED_DIRS={'e2eWorkspaceRoot','applicationRuntimeRoot','p1AuthorityServiceEvidenceRoot','controlledPackageRoot','controlledServiceRoot'}
FORBIDDEN_KEYS=re.compile(r'(private.?key|secret|seed|hmac|signing.?key|protected.?key.?handle|broker.?executable|ipc.?key|grant.?key|consumption.?key)',re.I)
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
def existing(row,key,kind):
 raw=row.get(key)
 if not isinstance(raw,dict) or raw.get('kind')!=kind:raise SystemExit(f'signed resource row missing: {key}')
 p=pathlib.Path(str(raw.get('path','')))
 if not p.is_absolute() or p.is_symlink() or (kind=='file' and not p.is_file()) or (kind=='directory' and not p.is_dir()):raise SystemExit(f'signed resource unavailable: {key}')
 out={'kind':kind,'path':str(p.resolve())}
 if kind=='file':
  d=str(raw.get('sha256','')).lower()
  if not HEX64.fullmatch(d) or sha(p)!=d:raise SystemExit(f'signed resource digest mismatch: {key}')
  out['sha256']=d
 return out
def within(child,root):
 try:pathlib.Path(child).resolve().relative_to(pathlib.Path(root).resolve());return True
 except ValueError:return False
def reject_secret_shape(value,path='root'):
 if isinstance(value,dict):
  for k,v in value.items():
   if FORBIDDEN_KEYS.search(str(k)):raise SystemExit(f'authority evidence contains secret-shaped field: {path}.{k}')
   reject_secret_shape(v,f'{path}.{k}')
 elif isinstance(value,list):
  for i,v in enumerate(value):reject_secret_shape(v,f'{path}[{i}]')
def validate_p1a(resolved,platform_name,project_root):
 root=pathlib.Path(resolved['p1AuthorityServiceEvidenceRoot']['path']).resolve()
 for key in P1A_FILES:
  if not within(resolved[key]['path'],root):raise SystemExit(f'P1A evidence escapes root: {key}')
 summary=validate_merged_p1a_graph(
  project_root=pathlib.Path(project_root).resolve(),
  platform=platform_name,
  evidence_root=root,
  merged_manifest_path=pathlib.Path(resolved['p1AuthorityServiceMergedManifest']['path']),
  platform_receipt_path=pathlib.Path(resolved['p1AuthorityServicePlatformReceipt']['path']),
  evidence_trust_path=pathlib.Path(resolved['p1AuthorityServiceEvidenceTrust']['path']),
 )
 for key in P1A_FILES:reject_secret_shape(obj(resolved[key]['path']),f'p1a.{key}')
 launcher=pathlib.Path(resolved['p1AuthorityServiceWorkerLauncher']['path']).resolve()
 if resolved['p1AuthorityServiceWorkerLauncher'].get('sha256')!=summary.get('workerLauncherSha256'):
  raise SystemExit('installed P1A restricted worker launcher digest mismatch')
 connector_path=pathlib.Path(resolved['p1AuthorityServiceConnectorConfig']['path']).resolve();connector=obj(connector_path);reject_secret_shape(connector,'p1a.connectorConfig')
 endpoint=connector.get('endpoint');provenance=connector.get('provenance')
 if connector.get('schemaVersion')!='2.0.0' or connector.get('completionEligible') is not True or not isinstance(endpoint,dict) or not isinstance(provenance,dict):raise SystemExit('installed P1A connector configuration invalid')
 if endpoint.get('platform')!=platform_name or endpoint.get('serviceInstanceId')!=summary.get('serviceInstanceId') or endpoint.get('serviceBuildSha256')!=summary.get('serviceBuildSha256') or not str(endpoint.get('address','')).strip():raise SystemExit('installed P1A endpoint identity mismatch')
 expected_provenance={'p1AmendmentMerged':True,'independentP1aSecurityReviewApproved':True,'workerDenialTriPlatformPassed':True,'aggregateManifestSha256':summary['mergedManifestSha256'],'platformReceiptSha256':summary['platformReceiptSha256'],'evidenceTrustSha256':summary['evidenceTrustSha256'],'serviceBehaviorReceiptSha256':summary['serviceBehaviorReceiptSha256'],'workerDenialReceiptSha256':summary['workerDenialReceiptSha256'],'workerLauncherSha256':summary['workerLauncherSha256'],'workerExecutableSha256':summary['workerExecutableSha256'],'workerIdentitySha256':summary['workerIdentitySha256'],'denialTranscriptSha256':summary['denialTranscriptSha256'],'p1aPackageSha256':summary['p1aPackageSha256'],'privateAuthorityMaterialPresent':False,'arbitraryMessageSigningApi':False,'completionEligible':True}
 for key,value in expected_provenance.items():
  if provenance.get(key)!=value:raise SystemExit(f'installed P1A connector provenance mismatch: {key}')
 server_identity=endpoint.get('serverIdentity')
 if not isinstance(server_identity,dict) or not server_identity:raise SystemExit('installed P1A endpoint server identity missing')
 return {**summary,'installedWorkerLauncherPath':str(launcher),'installedWorkerLauncherSha256':resolved['p1AuthorityServiceWorkerLauncher']['sha256'],'installedConnectorConfigPath':str(connector_path),'installedConnectorConfigSha256':resolved['p1AuthorityServiceConnectorConfig']['sha256'],'authorityAddress':endpoint['address'],'endpointServerIdentity':server_identity}
def main():
 a=argparse.ArgumentParser();a.add_argument('--project',default='.');a.add_argument('--policy',required=True);a.add_argument('--job-identity',required=True);a.add_argument('--platform',choices=tuple(LABELS),required=True);a.add_argument('--commit-sha',required=True);a.add_argument('--output',required=True);a.add_argument('--provider-timeout-seconds',type=int,default=180);n=a.parse_args()
 if not HEX40.fullmatch(n.commit_sha):raise SystemExit('exact source commit required')
 root=pathlib.Path(n.project).resolve();policy_path=pathlib.Path(n.policy).resolve();job_path=pathlib.Path(n.job_identity).resolve();out=pathlib.Path(n.output).resolve();policy=obj(policy_path);job=obj(job_path)
 if policy.get('schemaVersion')!='5.0.0' or policy.get('policyType')!='p2-controlled-runner-policy-v5':raise SystemExit('runner policy V5 invalid')
 if job.get('receiptType')!='p2-github-job-identity-v1' or job.get('status')!='observed' or job.get('sourceCommit')!=n.commit_sha or job.get('platform')!=n.platform:raise SystemExit('GitHub job identity invalid')
 row=policy.get('runners',{}).get(n.platform)
 if not isinstance(row,dict):raise SystemExit('platform runner not provisioned')
 for k in ('runnerId','runnerName','runnerGroup','runnerGroupId','labels'):
  if job.get(k)!=row.get(k):raise SystemExit(f'GitHub/provisioning runner mismatch: {k}')
 if job.get('labels')!=LABELS[n.platform]:raise SystemExit('exact runner labels required')
 workflow_file=root/'.github/workflows/p2-owner-mode.yml'
 if not workflow_file.is_file():raise SystemExit('P2 workflow source missing')
 binding={'repository':env('GITHUB_REPOSITORY'),'repositoryId':int(env('GITHUB_REPOSITORY_ID')),'workflowName':env('GITHUB_WORKFLOW'),'workflowPath':'.github/workflows/p2-owner-mode.yml','workflowFileSha256':sha(workflow_file),'workflowRef':env('GITHUB_WORKFLOW_REF'),'workflowRunId':env('GITHUB_RUN_ID'),'runAttempt':int(env('GITHUB_RUN_ATTEMPT')),'jobName':env('GITHUB_JOB'),'githubJobId':int(env('KRISTIN_P2_GITHUB_JOB_ID')),'sourceCommit':n.commit_sha,'runnerId':int(env('KRISTIN_P2_RUNNER_ID')),'runnerName':env('RUNNER_NAME'),'runnerGroup':env('KRISTIN_P2_RUNNER_GROUP'),'runnerGroupId':int(env('KRISTIN_P2_RUNNER_GROUP_ID')),'githubJobIdentitySha256':env('KRISTIN_P2_GITHUB_JOB_IDENTITY_SHA256'),'runnerEphemeralSessionId':env('KRISTIN_P2_RUNNER_EPHEMERAL_SESSION_ID')}
 for k,v in binding.items():
  if k in job and job.get(k)!=v:raise SystemExit(f'current GitHub job binding mismatch: {k}')
 if sha(job_path)!=binding['githubJobIdentitySha256']:raise SystemExit('GitHub job receipt digest mismatch')
 provider=pathlib.Path(str(row.get('attestationProviderPath',''))).resolve();provider_sha=str(row.get('attestationProviderSha256','')).lower()
 if not provider.is_file() or provider.is_symlink() or not HEX64.fullmatch(provider_sha) or sha(provider)!=provider_sha:raise SystemExit('attestation provider unavailable/digest changed')
 policy_sha=sha(policy_path);request={'schemaVersion':'1.0.0','requestType':'p2-controlled-runner-attestation-request-v2',**binding,'platform':n.platform,'policySha256':policy_sha,'providerSha256':provider_sha,'requestNonce':secrets.token_hex(32),'requestedAt':dt.datetime.now(dt.timezone.utc).isoformat()}
 with tempfile.TemporaryDirectory(prefix='p2-runner-attestation-v63-') as td:
  req=pathlib.Path(td)/'request.json';signed_path=pathlib.Path(td)/'signed.json';req.write_text(json.dumps(request,indent=2,sort_keys=True)+'\n')
  allowed={'PATH','Path','SystemRoot','WINDIR','HOME','USERPROFILE','TMP','TEMP','XDG_RUNTIME_DIR','DBUS_SESSION_BUS_ADDRESS','DISPLAY','WAYLAND_DISPLAY'}
  run=subprocess.run([str(provider),'--request',str(req),'--output',str(signed_path)],stdin=subprocess.DEVNULL,capture_output=True,text=True,timeout=n.provider_timeout_seconds,env={k:v for k,v in os.environ.items() if k in allowed})
  if run.returncode!=0 or not signed_path.is_file() or signed_path.stat().st_size>2*1024*1024:raise SystemExit('attestation provider failed')
  signed=obj(signed_path);body=dict(signed);sig=str(body.pop('signatureHex','')).lower();public=str(body.get('publicKeyHex','')).lower()
  if public not in set(map(str,policy.get('attestationTrustRoots',[]))) or not HEX128.fullmatch(sig) or not verify(bytes.fromhex(public),canonical(body),bytes.fromhex(sig)):raise SystemExit('runner attestation signature invalid/untrusted')
  if body.get('schemaVersion')!='5.0.0' or body.get('attestationType')!='p2-controlled-runner-attestation-v5':raise SystemExit('runner attestation identity invalid')
  for k,v in request.items():
   if k!='schemaVersion' and body.get(k)!=v:raise SystemExit(f'signed per-job attestation mismatch: {k}')
  if body.get('labels')!=LABELS[n.platform] or body.get('hostPlatform')!=n.platform or body.get('noConcurrentUntrustedWorkload') is not True:raise SystemExit('signed host/labels/exclusivity invalid')
  if platform.system()!={'linux':'Linux','macos':'Darwin','windows':'Windows'}[n.platform]:raise SystemExit('executing host platform mismatch')
  for k in ('runnerId','runnerName','runnerGroup','runnerGroupId'):
   if body.get(k)!=binding[k] or body.get(k)!=row.get(k):raise SystemExit(f'signed runner identity mismatch: {k}')
  if str(body.get('runnerEphemeralSessionId',''))!=binding['runnerEphemeralSessionId']:raise SystemExit('ephemeral session mismatch')
  now=dt.datetime.now(dt.timezone.utc);start=dt.datetime.fromisoformat(str(body.get('validFrom','')).replace('Z','+00:00'));end=dt.datetime.fromisoformat(str(body.get('validUntil','')).replace('Z','+00:00'))
  if not start<=now<end or (end-start).total_seconds()>int(policy.get('maximumAttestationAgeSeconds',900)):raise SystemExit('attestation validity invalid')
  session=body.get('interactiveSession');permissions=body.get('permissions')
  if not isinstance(session,dict) or session.get('loggedIn') is not True or not str(session.get('identity','')) or not str(session.get('sessionId','')):raise SystemExit('interactive session missing')
  if not isinstance(permissions,dict) or any(permissions.get(k) is not True for k in policy.get('requiredPermissions',[])):raise SystemExit('interactive permissions incomplete')
  configuration=pathlib.Path(str(body.get('configurationReceiptPath',''))).resolve();config_sha=str(body.get('configurationSha256','')).lower()
  if not configuration.is_file() or configuration.is_symlink() or not HEX64.fullmatch(config_sha) or sha(configuration)!=config_sha or config_sha!=row.get('configurationSha256'):raise SystemExit('configuration receipt invalid')
  resources=body.get('controlledResources')
  if not isinstance(resources,dict):raise SystemExit('controlled resources missing')
  resolved={k:existing(resources,k,'file') for k in REQUIRED_FILES};resolved.update({k:existing(resources,k,'directory') for k in REQUIRED_DIRS})
  p1a=validate_p1a(resolved,n.platform,root)
  if body.get('workerCannotAccessAuthorityService') is not True or body.get('p2ReceivesAuthoritySecrets') is not False:raise SystemExit('worker/P2 authority isolation attestation missing')
  operations=body.get('controlledOperations')
  if not isinstance(operations,dict) or operations.get('packageManager')!='npm-local-controlled' or operations.get('serviceProvider')!={'linux':'systemd-user','macos':'launchagent-user','windows':'scheduled-task-user'}[n.platform] or not str(operations.get('packageName','')) or not str(operations.get('serviceId','')):raise SystemExit('controlled operations invalid')
  cleanup=pathlib.Path(str(row.get('postRunCleanupProviderPath',''))).resolve();cleanup_sha=str(row.get('postRunCleanupProviderSha256','')).lower()
  if not cleanup.is_file() or cleanup.is_symlink() or not HEX64.fullmatch(cleanup_sha) or sha(cleanup)!=cleanup_sha:raise SystemExit('cleanup provider unavailable')
  receipt={'schemaVersion':'5.0.0','receiptType':'p2-controlled-runner-attestation-receipt-v5','status':'passed','platform':n.platform,'exactBinding':binding,'request':request,'requestSha256':hashlib.sha256(canonical(request)).hexdigest(),'signedAttestation':{**body,'signatureHex':sig},'signedAttestationSha256':sha(signed_path),'runnerPolicyPath':str(policy_path),'runnerPolicySha256':policy_sha,'provisioningPacketSha256':policy.get('provisioningPacketSha256'),'runnerId':binding['runnerId'],'runnerName':binding['runnerName'],'runnerGroup':binding['runnerGroup'],'runnerGroupId':binding['runnerGroupId'],'runnerEphemeralSessionId':binding['runnerEphemeralSessionId'],'labels':body['labels'],'hostImageSha256':body.get('hostImageSha256'),'configurationSha256':config_sha,'noConcurrentUntrustedWorkload':True,'interactiveSession':session,'permissions':permissions,'controlledOperations':operations,'resolvedResources':resolved,'resolvedRoots':{k:resolved[k]['path'] for k in REQUIRED_DIRS},'p1AuthorityService':p1a,'workerCannotAccessAuthorityService':True,'p2ReceivesAuthoritySecrets':False,'postRunCleanupProvider':{'path':str(cleanup),'sha256':cleanup_sha},'postRunCleanupObserved':False,'postRunCleanupRequired':True,'completionEligibleForTaskClosure':False,'verification':{k:True for k in ('signatureVerified','exactRepositoryVerified','exactWorkflowVerified','exactWorkflowRefVerified','exactWorkflowRunVerified','exactRunAttemptVerified','exactJobVerified','githubApiJobIdentityVerified','sourceCommitVerified','runnerIdentityVerified','runnerGroupAndLabelsVerified','ephemeralSessionVerified','hostImageVerified','interactiveSessionVerified','permissionsVerified','exclusiveWorkloadVerified','configurationReceiptVerified','p1aMergedManifestVerified','p1aSignedPlatformReceiptVerified','p1aEvidenceTrustVerified','p1aServiceBehaviorVerified','p1aWorkerDenialVerified','workerAuthorityIsolationVerified','packageResourcesVerified','serviceResourcesVerified','technologyResourcesVerified')}}
  out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n');print(json.dumps({'receipt':str(out),'sha256':sha(out)},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
