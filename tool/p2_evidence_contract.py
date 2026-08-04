#!/usr/bin/env python3
"""Strict P2 V63 evidence validator.

Behavioral closure requires exact task-specific observations from the shipped
ProductRuntime, the separately merged P1A isolated authority service, controlled
interactive runners, native lifecycle helpers, and signed post-run cleanup.
"""
from __future__ import annotations
import hashlib,json,pathlib,re,sys
TASKS=[f'P2-{i:03d}' for i in range(1,15)]
PLATFORMS=('windows','macos','linux')
HEX40=re.compile(r'^[0-9a-f]{40}$');HEX64=re.compile(r'^[0-9a-f]{64}$')
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from p2_p1a_dependency import validate_merged_p1a_graph
REQUIRED_ASSERTION_IDS={
'P2-001':{'p2-001.owner-state','p2-001.onboarding-workspace','p2-001.product-owner-mode-e2e'},
'P2-002':{'p2-002.filesystem-contract','p2-002.product-filesystem-e2e'},
'P2-003':{'p2-003.effect-boundary-binding','p2-003.desktop-durable-consumption','p2-003.product-finite-command-e2e'},
'P2-004':{'p2-004.equivalent-platform-spike','p2-004.governed-toolchain-extension'},
'P2-005':{'p2-005.product-composition-contract','p2-005.product-pty-e2e','p2-005.ipc-session-binding'},
'P2-006':{'p2-006.process-identity-contract','p2-006.product-tree-kill-e2e'},
'P2-007':{'p2-007.product-adapter-contract','p2-007.product-package-sdk-e2e'},
'P2-008':{'p2-008.product-adapter-contract','p2-008.product-service-application-e2e'},
'P2-009':{'p2-009.product-adapter-contract','p2-009.product-interactive-desktop-e2e','p2-009.redaction-no-log'},
'P2-010':{'p2-010.product-restore-contract','p2-010.product-restore-e2e'},
'P2-011':{'p2-011.product-watchdog-composition','p2-011.product-frozen-ui-watchdog-e2e'},
'P2-012':{'p2-012.workspace-actions-accessibility','p2-012.terminal-keyboard-contract','p2-012.product-terminal-workspace-e2e'},
'P2-013':{'p2-013.product-restart-replay-e2e','p2-013.restart-replay-state','p2-013.bounded-adversarial-fixture'},
'P2-014':{'p2-014.guide-ui-consistency'},
}
PRODUCT_ASSERTION_IDS={
'P2-001':'p2-001.product-owner-mode-e2e','P2-002':'p2-002.product-filesystem-e2e','P2-003':'p2-003.product-finite-command-e2e','P2-005':'p2-005.product-pty-e2e','P2-006':'p2-006.product-tree-kill-e2e','P2-007':'p2-007.product-package-sdk-e2e','P2-008':'p2-008.product-service-application-e2e','P2-009':'p2-009.product-interactive-desktop-e2e','P2-010':'p2-010.product-restore-e2e','P2-011':'p2-011.product-frozen-ui-watchdog-e2e','P2-012':'p2-012.product-terminal-workspace-e2e','P2-013':'p2-013.product-restart-replay-e2e'}

def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
def sha256_file(path:pathlib.Path)->str:
 h=hashlib.sha256()
 with path.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
def canonical_directory_digest(directory:pathlib.Path)->str:
 h=hashlib.sha256()
 for path in sorted((p for p in directory.rglob('*') if p.is_file()),key=lambda p:p.relative_to(directory).as_posix()):
  rel=path.relative_to(directory).as_posix().encode();h.update(len(rel).to_bytes(8,'big'));h.update(rel);h.update(path.stat().st_size.to_bytes(8,'big'));h.update(bytes.fromhex(sha256_file(path)))
 return h.hexdigest()
def load_json(path:pathlib.Path)->dict:
 try:value=json.loads(path.read_text(encoding='utf-8'))
 except Exception as e:raise SystemExit(f'invalid JSON {path}: {e}')
 if not isinstance(value,dict):raise SystemExit(f'{path}: object required')
 return value
def safe_relative(value,label):
 text=str(value or '');p=pathlib.PurePosixPath(text)
 if not text or p.is_absolute() or '..' in p.parts or '\\' in text:raise SystemExit(f'unsafe {label}: {text!r}')
 return p
def artifact_file(root:pathlib.Path,row:dict,label:str)->pathlib.Path:
 if not isinstance(row,dict):raise SystemExit(f'{label}: object required')
 digest=str(row.get('sha256',''))
 if not HEX64.fullmatch(digest):raise SystemExit(f'{label}: SHA-256 required')
 p=root/safe_relative(row.get('path'),label+' path')
 if not p.is_file() or sha256_file(p)!=digest:raise SystemExit(f'{label}: artifact missing/digest mismatch')
 return p
def _synthetic(value):
 if isinstance(value,dict):return value.get('syntheticContractFixture') is True or any(_synthetic(v) for v in value.values())
 if isinstance(value,list):return any(_synthetic(v) for v in value)
 return False

def _task_postcondition(task,obs):
 effect=obs.get('osEffect') or {};post=obs.get('postcondition') or {}
 expected={
 'P2-001':('owner_mode_settings_enable_disable_reset',('explicitAcknowledgementRequired','fullCurrentAccountLabelObserved','notSandboxLabelObserved','persistentIndicatorObserved','disableResetObserved','settingsPersistedAfterReenable')),
 'P2-005':('interactive_pty_detach_reconnect',('consumerDetached','outputWhileDetached','backlogReplayExact','noDuplicationOrLoss')),
 'P2-006':('managed_process_tree_kill',('descendantProcessCreated','identityVerified','zeroSurvivingDescendants')),
 'P2-007':('controlled_target_host_package_lifecycle',('controlledTargetHost','dryRunObserved','installObserved','installedStateObserved','removeObserved','removedStateObserved','executableVersionProvenanceObserved')),
 'P2-008':('controlled_user_service_and_application_lifecycle',('startObserved','runningObserved','stopObserved','stoppedObserved','applicationOpenObserved','applicationCloseObserved')),
 'P2-009':('interactive_clipboard_screen_active_window',('clipboardRoundTrip','screenCaptured','activeWindowObserved','ordinaryLogContentAbsent')),
 'P2-010':('product_snapshot_restore',('restoredContent',)),
 'P2-011':('product_runtime_external_watchdog_kill_during_ui_freeze',('watchdogAutomaticallyArmed','heartbeatObserved','desktopHeartbeatFrozen','externalKillObserved','identityVerified','zeroSurvivingDescendants')),
 'P2-012':('shipped_terminal_workspace_managed_session',('tabCreatedFromManagedPty','shellAndCwdObserved','runTaskGrantIdentityObserved','searchObserved','accessibilityLabelObserved','keyboardEmergencyActionExposed','interruptObserved','terminateTreeObserved')),
 'P2-013':('production_authority_restart_replay_reconciliation',('firstDispatchSucceeded','durableConsumptionRecorded','durableStateVersionRecorded','productRuntimeRestarted','replayRejectedAfterRestart','reconciliationObserved')),
 }
 if task not in expected:return
 kind,keys=expected[task]
 if effect.get('kind')!=kind or any(post.get(k) is not True for k in keys):raise SystemExit(f'{task}: specialized product postcondition invalid')
 if task in ('P2-006','P2-011') and post.get('activeProcesses')!=0:raise SystemExit(f'{task}: active process count must be zero')
 if task=='P2-008' and post.get('elevationExercised') is not False:raise SystemExit('P2-008: elevation claim invalid')

def _validate_product(path,task,platform,commit):
 obs=load_json(path)
 expected={'schemaVersion':'2.0.0','resultType':'p2-shipped-product-observation-v2','taskId':task,'assertionId':f'p2-{task[3:]}.product-runtime-e2e','platform':platform,'commitSha':commit,'entryPoint':'ProductRuntime.initialize','applicationComposition':'ProductRuntime.p2OwnerMode','authorizationBoundary':'p1-isolated-authority-service-effect-permit-v2','status':'passed','sourceOnly':False,'fixtureAuthority':False,'completionEligible':True}
 for k,v in expected.items():
  if obs.get(k)!=v:raise SystemExit(f'{path}: product {k} mismatch')
 for k in ('applicationCompositionSha256','runnerAttestationSha256','toolchainExtensionFingerprint','nativeRuntimeManifestSha256'):
  if not HEX64.fullmatch(str(obs.get(k,''))):raise SystemExit(f'{path}: product {k} digest required')
 auth=obs.get('authority')
 if not isinstance(auth,dict):raise SystemExit(f'{path}: P1A authority observation required')
 exact={'authorityImplementation':'P1IsolatedAuthorityServiceV2','authorityKind':'p1-isolated-authority-service-v2','completionEligible':True,'p1aService':True,'p2AdapterDelegationOnly':True,'p2CanIssueGrants':False,'workerPublicVerifierOnly':True,'workerCanForgeAuthority':False,'workerCanReachAuthoritySigner':False,'workerDeniedByOs':True,'osEnforcedIsolation':True,'workerPrincipalSeparated':True,'typedOperationsOnly':True,'nonExportableKeys':True,'workerReceivesSymmetricAuthorityKeys':False,'workerReceivesPrivateSigningMaterial':False}
 for k,v in exact.items():
  if auth.get(k)!=v:raise SystemExit(f'{path}: authority {k} mismatch')
 for k in ('policyDecisionId','capabilityGrantId','authenticatedIpcChannelId','authenticatedIpcRequestId','auditCheckpointId','serviceInstanceId'):
  if not str(auth.get(k,'')).strip():raise SystemExit(f'{path}: authority {k} required')
 for k in ('policyDecisionSha256','capabilityGrantSha256','authenticatedIpcSha256','effectPermitSha256','auditCheckpointSha256','serviceBuildSha256','serviceEndpointAttestationSha256','p1aPlatformReceiptSha256','p1aEvidenceTrustSha256','p1aServiceBehaviorReceiptSha256','workerDenialReceiptSha256','p1aWorkerLauncherSha256','p1aWorkerExecutableSha256','p1aWorkerIdentitySha256','p1aDenialTranscriptSha256','p1aPackageSha256','p1AmendmentManifestSha256'):
  if not HEX64.fullmatch(str(auth.get(k,''))):raise SystemExit(f'{path}: authority {k} digest required')
 if not HEX64.fullmatch(str(auth.get('effectPermitSignerPublicKeySpkiSha256',''))):raise SystemExit(f'{path}: public permit verifier required')
 for k in ('durableConsumptionStateVersion','durableConsumptionUseNumber','revocationEpoch'):
  if not isinstance(auth.get(k),int) or auth[k]<0:raise SystemExit(f'{path}: authority counter {k} invalid')
 p1a=auth.get('p1aEvidence');approval=auth.get('approval');keys=auth.get('protectedKeys')
 if not isinstance(p1a,dict) or p1a.get('p1AmendmentMerged') is not True or p1a.get('independentP1aSecurityReviewApproved') is not True or p1a.get('workerDenialTriPlatformPassed') is not True:raise SystemExit(f'{path}: merged P1A evidence required')
 for k in ('aggregateManifestSha256','platformReceiptSha256','evidenceTrustSha256','serviceBehaviorReceiptSha256','workerDenialReceiptSha256','workerLauncherSha256','workerExecutableSha256','workerIdentitySha256','denialTranscriptSha256','p1aPackageSha256'):
  if not HEX64.fullmatch(str(p1a.get(k,''))):raise SystemExit(f'{path}: P1A evidence digest {k} required')
 if p1a.get('privateAuthorityMaterialPresent') is not False or p1a.get('arbitraryMessageSigningApi') is not False or p1a.get('completionEligible') is not True:raise SystemExit(f'{path}: P1A evidence authority boundary invalid')
 if not isinstance(approval,dict) or approval.get('completionEligible') is not True:raise SystemExit(f'{path}: owner approval required')
 if not isinstance(keys,dict) or keys.get('kind')!='non-exportable-service-owned-keys' or keys.get('completionEligible') is not True:raise SystemExit(f'{path}: service-owned non-exportable key proof required')
 if not str(obs.get('productionAdapter','')).startswith('ProductRuntime/'):raise SystemExit(f'{path}: shipped adapter required')
 receipt=obs.get('receipt');post=obs.get('postcondition');effect=obs.get('osEffect')
 if not isinstance(receipt,dict) or receipt.get('completionEligible') is not True or receipt.get('fixtureAuthority') is not False or receipt.get('targetHostOperation') is not True:raise SystemExit(f'{path}: target-host receipt required')
 if not isinstance(post,dict) or post.get('observed') is not True or not isinstance(effect,dict) or not effect:raise SystemExit(f'{path}: observed OS effect required')
 _task_postcondition(task,obs)
 return obs

def _validate_assertion(item,task,platform,commit,artifact_root):
 if not isinstance(item,dict):raise SystemExit(f'{task}/{platform}: object assertion required')
 required={'assertionId','taskId','platform','command','testSource','observedStatus','returnCode','resultHash','evidencePath','evidenceSha256'}
 if not required.issubset(item):raise SystemExit(f'{task}/{platform}: assertion fields missing')
 if item['taskId']!=task or item['platform']!=platform or item['observedStatus']!='passed' or item['returnCode']!=0:raise SystemExit(f'{task}/{platform}: assertion not observed PASS')
 if not isinstance(item['command'],list) or not item['command'] or not all(isinstance(x,str) and x for x in item['command']):raise SystemExit(f'{task}/{platform}: command vector required')
 if not str(item['testSource']).strip() or not HEX64.fullmatch(str(item['resultHash'])) or not HEX64.fullmatch(str(item['evidenceSha256'])):raise SystemExit(f'{task}/{platform}: assertion source/digest invalid')
 ep=artifact_root/safe_relative(item['evidencePath'],'assertion evidence')
 if not ep.is_file() or sha256_file(ep)!=item['evidenceSha256']:raise SystemExit(f'{task}/{platform}: assertion evidence mismatch')
 rec=load_json(ep)
 for k,v in {'schemaVersion':'1.0.0','assertionId':item['assertionId'],'taskId':task,'platform':platform,'commitSha':commit,'observedStatus':'passed','returnCode':0,'resultHash':item['resultHash']}.items():
  if rec.get(k)!=v:raise SystemExit(f'{ep}: assertion {k} mismatch')
 unsigned=dict(rec);provided=unsigned.pop('resultHash',None)
 if hashlib.sha256(canonical(unsigned)).hexdigest()!=provided or rec.get('command')!=item['command'] or rec.get('testSource')!=item['testSource']:raise SystemExit(f'{ep}: assertion result hash/binding mismatch')
 if PRODUCT_ASSERTION_IDS.get(task)==item['assertionId']:
  for k in ('observationArtifactPath','observationArtifactSha256'):
   if k not in item or rec.get(k)!=item.get(k):raise SystemExit(f'{ep}: product artifact binding missing')
  pp=artifact_root/safe_relative(item['observationArtifactPath'],'product observation');pd=str(item['observationArtifactSha256'])
  if not pp.is_file() or not HEX64.fullmatch(pd) or sha256_file(pp)!=pd:raise SystemExit(f'{ep}: product artifact mismatch')
  summary=rec.get('observation')
  if not isinstance(summary,dict) or summary.get('status')!='passed' or summary.get('taskAssertionId')!=item['assertionId']:raise SystemExit(f'{ep}: product validator summary missing')
  _validate_product(pp,task,platform,commit)
 return item

def _validate_p1a_service(data,artifact_root,platform):
 service=data.get('p1AuthorityService')
 exact={'authorityType':'p1-isolated-authority-service-v2','completionEligible':True,'osEnforcedIsolation':True,'workerPrincipalSeparated':True,'typedOperationsOnly':True,'nonExportableKeys':True,'workerDeniedByOs':True,'workerCannotAccessAuthorityService':True,'p2DelegationOnly':True,'rawAuthoritySecretsIncluded':False}
 if not isinstance(service,dict):raise SystemExit('P1A authority service evidence required')
 for k,v in exact.items():
  if service.get(k)!=v:raise SystemExit(f'P1A service {k} mismatch')
 if not str(service.get('serviceInstanceId','')).strip() or not HEX64.fullmatch(str(service.get('serviceBuildSha256',''))):raise SystemExit('P1A service identity invalid')
 rows={k:service.get(k) for k in ('mergedManifest','platformReceipt','evidenceTrust')}
 paths={k:artifact_file(artifact_root,v,'P1A '+k) for k,v in rows.items()}
 root_row=service.get('evidenceRoot')
 if not isinstance(root_row,dict):raise SystemExit('P1A evidence root row required')
 evidence_root=(artifact_root/safe_relative(root_row.get('path'),'P1A evidence root')).resolve()
 if not evidence_root.is_dir() or artifact_root.resolve() not in evidence_root.parents:raise SystemExit('P1A evidence root unavailable')
 summary=validate_merged_p1a_graph(project_root=artifact_root,evidence_root=evidence_root,merged_manifest_path=paths['mergedManifest'],platform_receipt_path=paths['platformReceipt'],evidence_trust_path=paths['evidenceTrust'],platform=platform,enforce_manifest_path=False)
 expected={
  'serviceInstanceId':summary['serviceInstanceId'],'serviceBuildSha256':summary['serviceBuildSha256'],
  'workerLauncherSha256':summary['workerLauncherSha256'],'workerExecutableSha256':summary['workerExecutableSha256'],
  'workerIdentitySha256':summary['workerIdentitySha256'],'denialTranscriptSha256':summary['denialTranscriptSha256'],
  'serviceBehaviorReceiptSha256':summary['serviceBehaviorReceiptSha256'],'workerDenialReceiptSha256':summary['workerDenialReceiptSha256'],
  'p1aMergedCommit':summary['p1aMergedCommit'],'p1aMergedTree':summary['p1aMergedTree'],'p1aPackageSha256':summary['p1aPackageSha256'],
 }
 for key,value in expected.items():
  if service.get(key)!=value:raise SystemExit(f'P1A service signed graph mismatch: {key}')
 return service

def validate_platform_receipt(path:pathlib.Path,*,commit_sha:str,allow_synthetic_contract_fixture:bool=False)->dict:
 path=path.resolve();data=load_json(path)
 if data.get('schemaVersion')!='5.0.0' or data.get('receiptType')!='p2-task-platform-behavioral-v5' or data.get('phase')!='P2':raise SystemExit(f'{path}: V63 behavioral receipt required')
 platform=data.get('platform')
 if platform not in PLATFORMS or data.get('commitSha')!=commit_sha or not HEX40.fullmatch(commit_sha):raise SystemExit(f'{path}: platform/commit binding invalid')
 if data.get('status')!='passed' or data.get('sourceOnly') is not False or data.get('completionEligible') is not True or data.get('postRunCleanupObserved') is not True or data.get('interactiveDesktopAttested') is not True or data.get('behavioralLaneAttested') is not True:raise SystemExit(f'{path}: completion-eligible observed platform PASS required')
 artifact_root=path.parent/safe_relative(data.get('artifactRoot'),'artifactRoot')
 if not artifact_root.is_dir() or artifact_root.is_symlink() or data.get('artifactDigestAlgorithm')!='canonical-unpacked-v1' or canonical_directory_digest(artifact_root)!=data.get('artifactSha256'):raise SystemExit(f'{path}: canonical artifact binding invalid')
 exact=data.get('exactBinding')
 if not isinstance(exact,dict) or exact.get('sourceCommit')!=commit_sha or str(exact.get('workflowRunId'))!=str(data.get('workflowRunId')) or exact.get('jobName')!=data.get('jobName') or not isinstance(exact.get('runAttempt'),int) or exact['runAttempt']<1 or not isinstance(exact.get('githubJobId'),int):raise SystemExit(f'{path}: exact run/job binding invalid')
 app=data.get('applicationComposition')
 if not isinstance(app,dict) or app.get('entryPoint')!='ProductRuntime.initialize' or app.get('p2CompositionField')!='ProductRuntime.p2OwnerMode' or app.get('p1AuthorityField')!='ProductRuntime.p1AuthorityService' or app.get('p1AuthorityImplementation')!='merged-P1A-isolated-service' or not HEX64.fullmatch(str(app.get('sha256',''))):raise SystemExit(f'{path}: shipped P1A/P2 composition invalid')
 runtime=data.get('applicationRuntime')
 if not isinstance(runtime,dict) or runtime.get('sourceCheckoutIndependent') is not True or any(not HEX64.fullmatch(str(runtime.get(k,''))) for k in ('manifestSha256','runtimeBuildSha256')):raise SystemExit(f'{path}: application runtime invalid')
 _validate_p1a_service(data,artifact_root,platform)
 runner=data.get('runnerAttestation')
 if not isinstance(runner,dict) or not HEX64.fullmatch(str(runner.get('sha256',''))) or not HEX64.fullmatch(str(runner.get('configurationSha256',''))) or not isinstance(runner.get('runnerId'),int) or runner.get('runnerGroup')!='kristin-p2-controlled' or not str(runner.get('runnerEphemeralSessionId','')):raise SystemExit(f'{path}: runner attestation invalid')
 verification=runner.get('verification')
 if not isinstance(verification,dict) or not verification or any(v is not True for v in verification.values()):raise SystemExit(f'{path}: runner verification incomplete')
 if runner.get('workerCannotAccessAuthorityService') is not True or runner.get('p2ReceivesAuthoritySecrets') is not False:raise SystemExit(f'{path}: worker authority isolation missing')
 cleanup=data.get('postRunCleanup')
 if not isinstance(cleanup,dict) or cleanup.get('status')!='passed' or cleanup.get('exactBinding')!=exact:raise SystemExit(f'{path}: exact post-run cleanup missing')
 cleanup_path=artifact_file(artifact_root,cleanup,'post-run cleanup')
 cleanup_body=load_json(cleanup_path);assertions=cleanup.get('assertions')
 required_cleanup=('managedProcessTreesTerminated','zeroSurvivingDescendants','controlledUserServicesStoppedAndRemoved','controlledPackagesRemoved','clipboardTestDataCleared','screenArtifactsRemoved','authorityEvidenceArtifactsCleared','workspacesRemoved','noTestSecretsRemaining','noConcurrentUntrustedWorkload')
 if not isinstance(assertions,dict) or any(assertions.get(k) is not True for k in required_cleanup) or cleanup_body.get('status')!='passed':raise SystemExit(f'{path}: cleanup assertions incomplete')
 native=data.get('nativeRuntime')
 if not isinstance(native,dict) or not HEX64.fullmatch(str(native.get('manifestSha256',''))) or not isinstance(native.get('binaries'),dict):raise SystemExit(f'{path}: native runtime invalid')
 required_bin='windowsJobSupervisor' if platform=='windows' else 'posixWatchdog'
 for key in ('nativePtyProbe',required_bin):
  row=native['binaries'].get(key)
  artifact_file(artifact_root,row,f'native binary {key}')
 tasks=data.get('taskAssertions')
 if not isinstance(tasks,dict) or set(tasks)!=set(TASKS):raise SystemExit(f'{path}: exact task set required')
 for task in TASKS:
  row=tasks[task]
  if not isinstance(row,dict) or row.get('status')!='passed' or row.get('sourceOnly') is not False or row.get('runnerReturnCode')!=0 or not HEX64.fullmatch(str(row.get('taskResultSha256',''))):raise SystemExit(f'{path}: {task} observed result invalid')
  task_path=artifact_root/safe_relative(row.get('taskResultPath'),f'{task} task result')
  if not task_path.is_file() or sha256_file(task_path)!=row['taskResultSha256']:raise SystemExit(f'{path}: {task} task result mismatch')
  task_body=load_json(task_path)
  if task_body.get('taskId')!=task or task_body.get('platform')!=platform or task_body.get('commitSha')!=commit_sha or task_body.get('status')!='passed' or task_body.get('sourceOnly') is not False or task_body.get('productPathRequired') is not (task in PRODUCT_ASSERTION_IDS):raise SystemExit(f'{task_path}: task result invalid')
  assertions=row.get('assertions')
  if not isinstance(assertions,list) or {a.get('assertionId') for a in assertions if isinstance(a,dict)}!=REQUIRED_ASSERTION_IDS[task]:raise SystemExit(f'{path}: {task} exact assertion set required')
  for item in assertions:_validate_assertion(item,task,platform,commit_sha,artifact_root)
 if _synthetic(data) and not allow_synthetic_contract_fixture:raise SystemExit(f'{path}: synthetic contract fixture cannot be release evidence')
 return data

def validate_review(path:pathlib.Path,*,reviewed_commit:str,reviewed_tree:str,package_sha256:str,platform_receipt_digests:dict[str,str],base_main_sha:str,base_main_tree:str,p1_base_verification_sha256:str)->dict:
 data=load_json(path)
 if data.get('schemaVersion')!='2.0.0' or data.get('independent') is not True or data.get('decision') not in ('approve','approve_with_conditions') or not str(data.get('reviewerName','')).strip() or not str(data.get('reviewerOrganizationOrRelationship','')).strip():raise SystemExit('independent security review invalid')
 expected={'reviewedCommit':reviewed_commit,'reviewedTree':reviewed_tree,'packageSha256':package_sha256,'baseMainSha':base_main_sha,'baseMainTree':base_main_tree,'p1BaseVerificationSha256':p1_base_verification_sha256,'platformReceiptSha256':platform_receipt_digests}
 for k,v in expected.items():
  if data.get(k)!=v:raise SystemExit(f'independent review exact binding mismatch: {k}')
 if data.get('criticalHighFindingsRemaining') not in ([],None):raise SystemExit('unresolved critical/high findings')
 conditions=data.get('conditions',[]);satisfied=data.get('satisfiedConditions',[])
 if not isinstance(conditions,list) or not isinstance(satisfied,list) or not set(conditions).issubset(set(satisfied)):raise SystemExit('review conditions unsatisfied')
 ref=pathlib.Path(str(data.get('reviewArtifactReference','')))
 if not ref.is_absolute():ref=(path.parent/ref).resolve()
 if not ref.is_file() or sha256_file(ref)!=data.get('reviewArtifactSha256'):raise SystemExit('external review artifact binding invalid')
 if data.get('syntheticContractFixture') is True:raise SystemExit('synthetic review forbidden')
 return data

def validate_owner_approval(path:pathlib.Path,*,reviewed_commit:str,reviewed_tree:str,package_sha256:str,base_main_sha:str,base_main_tree:str,p1_base_verification_sha256:str)->dict:
 data=load_json(path)
 expected={'approved':True,'reviewedCommit':reviewed_commit,'reviewedTree':reviewed_tree,'packageSha256':package_sha256,'baseMainSha':base_main_sha,'baseMainTree':base_main_tree,'p1BaseVerificationSha256':p1_base_verification_sha256,'acknowledgesFullCurrentAccountAuthority':True,'acknowledgesNotSandboxed':True,'acknowledgesIndependentReviewAndExactReceipts':True}
 for k,v in expected.items():
  if data.get(k)!=v:raise SystemExit(f'owner approval mismatch: {k}')
 if not str(data.get('ownerName','')).strip() or not str(data.get('approvedAt','')).strip() or data.get('syntheticContractFixture') is True:raise SystemExit('owner approval identity invalid')
 return data
