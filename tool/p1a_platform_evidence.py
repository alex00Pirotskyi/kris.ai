#!/usr/bin/env python3
from __future__ import annotations
import argparse,hashlib,json,pathlib,re,subprocess,sys
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from p1a_signed_evidence import HEX40,HEX64,canonical_bytes,load_object,sha256_file,verify_ed25519_document,verify_service_ecdsa_receipt
PLATFORMS=('windows','macos','linux')
COMPONENTS=('runnerAttestation','buildProvenance','installerReceipt','keyProviderReceipt','workerDenialReceipt','serviceBehaviorReceipt','cleanupReceipt','githubApiVerification')

def verify_github_job_live(exact:dict,*,commit:str,github_repo:str|None=None,gh_executable:str='gh')->dict:
 repo=github_repo or str(exact.get('repository','')).strip()
 if not repo or repo!=str(exact.get('repository','')).strip():raise SystemExit('P1A GitHub repository binding invalid')
 run=str(exact.get('workflowRunId',''));attempt=str(exact.get('runAttempt',''));job_id=str(exact.get('githubJobId',''))
 if not run.isdigit() or not attempt.isdigit() or not job_id.isdigit():raise SystemExit('P1A GitHub run/job identity invalid')
 def api(endpoint:str)->dict:
  result=subprocess.run([gh_executable,'api',endpoint],capture_output=True,text=True)
  if result.returncode!=0:raise SystemExit('P1A live GitHub API verification failed: '+result.stderr[-500:])
  value=json.loads(result.stdout)
  if not isinstance(value,dict):raise SystemExit('P1A GitHub API object required')
  return value
 run_data=api(f'repos/{repo}/actions/runs/{run}/attempts/{attempt}')
 jobs=api(f'repos/{repo}/actions/runs/{run}/attempts/{attempt}/jobs?per_page=100').get('jobs',[])
 matches=[row for row in jobs if str(row.get('id'))==job_id]
 if len(matches)!=1:raise SystemExit('P1A exact GitHub job missing')
 job=matches[0]
 expected_job=str(exact.get('jobName',''));expected_workflow=str(exact.get('workflowPath',''))
 if run_data.get('head_sha')!=commit or run_data.get('status')!='completed' or run_data.get('conclusion')!='success':raise SystemExit('P1A exact workflow run is not successful')
 if job.get('status')!='completed' or job.get('conclusion')!='success' or str(job.get('name'))!=expected_job:raise SystemExit('P1A exact behavioral job is not successful')
 if str(job.get('runner_id'))!=str(exact.get('runnerId')) or str(job.get('runner_name'))!=str(exact.get('runnerName')):raise SystemExit('P1A GitHub runner identity mismatch')
 path=str(run_data.get('path') or '')
 if expected_workflow and path and not path.endswith(expected_workflow):raise SystemExit('P1A workflow path mismatch')
 return {'repository':repo,'workflowRunId':run,'runAttempt':attempt,'githubJobId':job_id,'headSha':commit,'workflowPath':expected_workflow,'jobName':expected_job,'conclusion':'success','runnerId':str(job.get('runner_id')),'runnerName':str(job.get('runner_name'))}

REQUIRED_SERVICE_EVENTS={'desktop-authenticated','worker-identity-claimed','worker-principal-denied','worker-identity-denial-bound','owner-approval-recorded','effect-authorized','effect-outcome-recorded','request-replay-denied','service-restarted'}
def canonical_directory_digest(root:pathlib.Path)->str:
 h=hashlib.sha256()
 for p in sorted((x for x in root.rglob('*') if x.is_file()),key=lambda x:x.relative_to(root).as_posix()):
  rel=p.relative_to(root).as_posix().encode();data=p.read_bytes();h.update(len(rel).to_bytes(8,'big'));h.update(rel);h.update(len(data).to_bytes(8,'big'));h.update(hashlib.sha256(data).digest())
 return h.hexdigest()
def component(root:pathlib.Path,row:object,label:str)->tuple[pathlib.Path,dict]:
 if not isinstance(row,dict):raise SystemExit(f'{label}: component object required')
 rel=pathlib.PurePosixPath(str(row.get('path','')))
 if rel.is_absolute() or '..' in rel.parts:raise SystemExit(f'{label}: unsafe component path')
 path=(root/rel).resolve()
 if root.resolve() not in path.parents or not path.is_file() or sha256_file(path)!=row.get('sha256'):raise SystemExit(f'{label}: component digest mismatch')
 return path,load_object(path)
def validate_signed_component(path:pathlib.Path,body:dict,trust:dict,purpose:str,platform:str,exact:dict)->None:
 verify_ed25519_document(body,trust,purpose=purpose)
 if body.get('status')!='passed' or body.get('platform')!=platform or body.get('exactBinding')!=exact or body.get('completionEligible') is not True:raise SystemExit(f'{path}: signed component binding invalid')
def validate_platform_receipt(path:pathlib.Path,*,commit:str,tree:str,package_sha256:str,trust_path:pathlib.Path,allow_synthetic:bool=False,openssl_executable:str='openssl',require_live_github_success:bool=False,github_repo:str|None=None,gh_executable:str='gh')->dict:
 path=path.resolve();data=load_object(path);trust=load_object(trust_path.resolve())
 if data.get('schemaVersion')!='3.0.0' or data.get('receiptType')!='p1a-platform-behavioral-v3' or data.get('phase')!='P1A':raise SystemExit(f'{path}: P1A V63 receipt required')
 platform=data.get('platform');exact=data.get('exactBinding')
 if platform not in PLATFORMS or data.get('sourceCommit')!=commit or data.get('sourceTree')!=tree or data.get('packageSha256')!=package_sha256 or not HEX40.fullmatch(commit) or not HEX40.fullmatch(tree) or not HEX64.fullmatch(package_sha256):raise SystemExit(f'{path}: exact source/package binding invalid')
 if data.get('status')!='passed' or data.get('sourceOnly') is not False or data.get('completionEligible') is not True:raise SystemExit(f'{path}: completion-eligible PASS required')
 if data.get('syntheticContractFixture') is True and not allow_synthetic:raise SystemExit(f'{path}: synthetic receipt forbidden')
 if not isinstance(exact,dict) or exact.get('sourceCommit')!=commit or exact.get('sourceTree')!=tree or exact.get('platform')!=platform:raise SystemExit(f'{path}: exact run binding invalid')
 verify_ed25519_document(data,trust,purpose='p1a-platform-receipt')
 artifact_root=(path.parent/pathlib.PurePosixPath(str(data.get('artifactRoot','')))).resolve()
 if not artifact_root.is_dir() or artifact_root.is_symlink() or path.parent.resolve() not in artifact_root.parents:raise SystemExit(f'{path}: artifact root invalid')
 if data.get('artifactDigestAlgorithm')!='canonical-unpacked-v1' or canonical_directory_digest(artifact_root)!=data.get('artifactSha256'):raise SystemExit(f'{path}: artifact digest mismatch')
 rows={name:component(artifact_root,data.get(name),name) for name in COMPONENTS}
 build=rows['buildProvenance'][1]
 required_build_digests=('serviceBinarySha256','connectorLibrarySha256','workerLauncherSha256','installerSha256','uninstallerSha256','sourceInventorySha256','reproducibleBuildInputsSha256')
 for key in required_build_digests:
  if not HEX64.fullmatch(str(build.get(key,''))):raise SystemExit(f'{path}: native build provenance digest missing: {key}')
 toolchains=build.get('toolchains')
 if not isinstance(toolchains,dict):raise SystemExit(f'{path}: governed native toolchain provenance missing')
 for key in ('python','cmake','compiler'):
  row=toolchains.get(key)
  if not isinstance(row,dict) or not str(row.get('version','')).strip() or not HEX64.fullmatch(str(row.get('executableSha256',''))):raise SystemExit(f'{path}: exact governed toolchain identity missing: {key}')
 for name,purpose in (('runnerAttestation','p1a-runner-attestation-receipt'),('buildProvenance','p1a-build-provenance'),('installerReceipt','p1a-installer-receipt'),('keyProviderReceipt','p1a-key-provider-receipt'),('workerDenialReceipt','p1a-worker-denial-receipt'),('cleanupReceipt','p1a-cleanup-receipt'),('githubApiVerification','p1a-github-api-verification')):
  validate_signed_component(rows[name][0],rows[name][1],trust,purpose,platform,exact)
 service=rows['serviceBehaviorReceipt'][1]
 if service.get('schemaVersion')!='2.0.0' or service.get('receiptType')!='p1a-service-behavior-v2' or service.get('sourceCommit')!=commit or service.get('sourceTree')!=tree or service.get('exactRunBindingSha256')!=data.get('exactRunBindingSha256') or service.get('completionEligible') is not True:raise SystemExit(f'{path}: service behavior receipt binding invalid')
 verify_service_ecdsa_receipt(service,openssl_executable=openssl_executable)
 session=service.get('behaviorSession');events=session.get('events') if isinstance(session,dict) else None
 observed={row.get('event') for row in events if isinstance(row,dict)} if isinstance(events,list) else set()
 if not REQUIRED_SERVICE_EVENTS.issubset(observed):raise SystemExit(f'{path}: service internal event proof incomplete')
 if any(service.get(key) is not value for key,value in {'typedOperationsOnly':True,'arbitraryMessageSigningApi':False,'policyValidatedInsideService':True,'grantIssuedInsideService':True,'grantValidatedInsideService':True,'useConsumedInsideService':True,'revocationCheckedInsideService':True,'auditAppendedInsideService':True,'workerPrincipalDeniedInsideService':True,'workerIdentityDenialBoundInsideService':True,'replayAfterRestartDenied':True,'nonExportableKey':True}.items()):raise SystemExit(f'{path}: service authority claims invalid')
 for key in ('workerIdentitySha256','workerDenialPeerEvidenceSha256','workerIdentityDenialBindingSha256'):
  if not HEX64.fullmatch(str(service.get(key,''))):raise SystemExit(f'{path}: service worker-denial binding digest missing: {key}')
 denial=rows['workerDenialReceipt'][1]
 required_denial={'productionRestrictedLauncherUsed':True,'exactWorkerPrincipalObserved':True,'authorityConnectionDenied':True,'authorityKeyReadDenied':True,'osKeyStoreSigningDenied':True,'arbitraryMessageSigningDenied':True,'workerIdentityBoundToSession':True}
 if any(denial.get(k) is not v for k,v in required_denial.items()):raise SystemExit(f'{path}: exact production worker denial incomplete')
 for key in ('launcherSha256','workerExecutableSha256','workerIdentitySha256','denialTranscriptSha256'):
  if not HEX64.fullmatch(str(denial.get(key,''))):raise SystemExit(f'{path}: worker denial digest missing: {key}')
 if service.get('workerIdentitySha256')!=denial.get('workerIdentitySha256'):raise SystemExit(f'{path}: service/worker denial identity mismatch')
 expected_denial_binding=hashlib.sha256((str(service['workerIdentitySha256'])+'|'+str(service['workerDenialPeerEvidenceSha256'])+'|'+str(service.get('behaviorSessionId',''))).encode()).hexdigest()
 if service.get('workerIdentityDenialBindingSha256')!=expected_denial_binding:raise SystemExit(f'{path}: service worker-denial binding mismatch')
 keyp=rows['keyProviderReceipt'][1]
 if keyp.get('providerBacked') is not True or keyp.get('privateExportAttempted') is not True or keyp.get('privateExportDenied') is not True or keyp.get('serviceOnlyAclObserved') is not True:raise SystemExit(f'{path}: key provider proof incomplete')
 installer=rows['installerReceipt'][1]
 if installer.get('serviceInstalled') is not True or installer.get('separateServiceIdentity') is not True or installer.get('connectorInstalled') is not True or installer.get('workerLauncherInstalled') is not True or installer.get('rollbackAvailable') is not True:raise SystemExit(f'{path}: installer proof incomplete')
 cross={
  'installerSha256':build['installerSha256'],'uninstallerSha256':build['uninstallerSha256'],
  'installedServiceSha256':build['serviceBinarySha256'],'installedConnectorSha256':build['connectorLibrarySha256'],
  'installedWorkerLauncherSha256':build['workerLauncherSha256'],
 }
 for key,value in cross.items():
  if installer.get(key)!=value:raise SystemExit(f'{path}: installer/build provenance mismatch: {key}')
 if service.get('serviceBuildSha256')!=build['serviceBinarySha256'] and service.get('serviceBinarySha256')!=build['serviceBinarySha256']:raise SystemExit(f'{path}: service/build provenance mismatch')
 if denial.get('launcherSha256')!=build['workerLauncherSha256']:raise SystemExit(f'{path}: worker launcher/build provenance mismatch')
 provider_attestation=str(keyp.get('providerAttestationSha256',''))
 signing_provenance=str(keyp.get('signingOperationProvenanceSha256',''))
 if not HEX64.fullmatch(provider_attestation) or not HEX64.fullmatch(signing_provenance) or not str(keyp.get('providerName','')).strip() or not str(keyp.get('keyId','')).strip():raise SystemExit(f'{path}: non-exportable key provider provenance incomplete')
 signature=service.get('signature')
 if not isinstance(signature,dict) or signature.get('providerAttestationSha256')!=provider_attestation:raise SystemExit(f'{path}: service/key-provider attestation mismatch')
 cleanup=rows['cleanupReceipt'][1]
 if cleanup.get('uninstallerSha256')!=build['uninstallerSha256'] or cleanup.get('postRunCleanup') is not True:raise SystemExit(f'{path}: cleanup/uninstaller provenance mismatch')
 for k in ('serviceUninstalled','workerLauncherRemoved','connectorRemoved','testKeyRemoved','zeroManagedProcesses','zeroOrphanedProcesses','temporaryAuthorityStateRemoved'):
  if cleanup.get(k) is not True:raise SystemExit(f'{path}: cleanup proof missing: {k}')
 github=rows['githubApiVerification'][1]
 if github.get('repository')!=exact.get('repository') or str(github.get('workflowRunId'))!=str(exact.get('workflowRunId')) or str(github.get('runAttempt'))!=str(exact.get('runAttempt')) or str(github.get('githubJobId'))!=str(exact.get('githubJobId')) or github.get('headSha')!=commit:raise SystemExit(f'{path}: GitHub API identity capture mismatch')
 # The behavioral job can only capture itself while still running. Completion is never inferred from that capture.
 if github.get('statusAtCapture') not in ('in_progress','completed'):raise SystemExit(f'{path}: GitHub API capture status invalid')
 if github.get('conclusion') not in (None,'success'):raise SystemExit(f'{path}: GitHub API capture contains a non-success conclusion')
 if require_live_github_success:
  data['liveGithubSuccess']=verify_github_job_live(exact,commit=commit,github_repo=github_repo,gh_executable=gh_executable)
 return data

def main()->int:
 p=argparse.ArgumentParser();p.add_argument('--receipt',required=True);p.add_argument('--commit',required=True);p.add_argument('--tree',required=True);p.add_argument('--package-sha256',required=True);p.add_argument('--trust',required=True);p.add_argument('--openssl',default='openssl');p.add_argument('--require-live-github-success',action='store_true');p.add_argument('--github-repo');p.add_argument('--gh',default='gh');a=p.parse_args()
 data=validate_platform_receipt(pathlib.Path(a.receipt),commit=a.commit,tree=a.tree,package_sha256=a.package_sha256,trust_path=pathlib.Path(a.trust),openssl_executable=a.openssl,require_live_github_success=a.require_live_github_success,github_repo=a.github_repo,gh_executable=a.gh);print(json.dumps({'status':'passed','platform':data['platform'],'receiptSha256':sha256_file(pathlib.Path(a.receipt))},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
