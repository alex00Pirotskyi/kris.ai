#!/usr/bin/env python3
from __future__ import annotations
import pathlib,re
R=pathlib.Path(__file__).resolve().parents[1]
def rd(p): return (R/p).read_text(encoding='utf-8')
def wr(p,s): (R/p).write_text(s,encoding='utf-8',newline='\n')
def rep(p,a,b):
 s=rd(p); n=s.count(a)
 if n!=1: raise SystemExit(f'{p}: target count {n}')
 wr(p,s.replace(a,b,1))
def rx(p,a,b):
 s=rd(p); u,n=re.subn(a,b,s,count=1,flags=re.S)
 if n!=1: raise SystemExit(f'{p}: regex target count {n}')
 wr(p,u)

approval='''class P1AuthorityOwnerApprovalRequestV2 {
  const P1AuthorityOwnerApprovalRequestV2({
    required this.requestId,
    required this.approvalId,
    required this.interactionNonce,
    required this.binding,
    required this.effectOperation,
    required this.payloadSha256,
    required this.uiSurfaceSha256,
    required this.confirmationTextSha256,
    required this.expiresAt,
    this.interactionType = 'native-owner-confirmation',
    this.userPresent = true,
    this.approvalScope = 'effect',
    this.approvalPolicy = 'boundedSession',
    this.ownerSessionId,
    this.behaviorSessionId,
  });

  final String requestId;
  final String approvalId;
  final String interactionNonce;
  final String interactionType;
  final Map<String, Object?> binding;
  final String effectOperation;
  final String payloadSha256;
  final String uiSurfaceSha256;
  final String confirmationTextSha256;
  final DateTime expiresAt;
  final bool userPresent;
  final String approvalScope;
  final String approvalPolicy;
  final String? ownerSessionId;
  final String? behaviorSessionId;

  void validate(DateTime now) {
    for (final value in <String>[requestId, approvalId, interactionNonce, effectOperation]) {
      if (!_p1aId.hasMatch(value)) throw StateError('p1a_owner_approval_identity_invalid');
    }
    final profile = binding['accessProfileId']?.toString() ?? '';
    final requiredBinding = <String>['runId','taskId','actorId','toolId','accessProfileId','capabilityId'];
    final sessionScope = approvalScope == 'owner-session';
    final maxLifetime = sessionScope ? const Duration(hours: 24) : const Duration(minutes: 15);
    final sessionId = ownerSessionId;
    if (!const <String>{'effect','owner-session'}.contains(approvalScope) ||
        !const <String>{'everyHighRiskEffect','destructiveOnly','boundedSession'}.contains(approvalPolicy) ||
        (sessionScope && (effectOperation != 'owner-session' || sessionId == null || !_p1aId.hasMatch(sessionId))) ||
        (!sessionScope && sessionId != null) ||
        interactionType != 'native-owner-confirmation' || !userPresent ||
        binding.length < requiredBinding.length ||
        requiredBinding.any((key) => !_p1aId.hasMatch(binding[key]?.toString() ?? '')) ||
        (profile != 'owner' && profile != 'owner_unattended') ||
        !_p1aHex64.hasMatch(payloadSha256) || !_p1aHex64.hasMatch(uiSurfaceSha256) ||
        !_p1aHex64.hasMatch(confirmationTextSha256) || !now.toUtc().isBefore(expiresAt.toUtc()) ||
        expiresAt.toUtc().difference(now.toUtc()) > maxLifetime) {
      throw StateError('p1a_owner_approval_limits_invalid');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion':'2.0.0','operation':p1aRecordOwnerApprovalOperationV2,'requestId':requestId,
    'approvalId':approvalId,'interactionNonce':interactionNonce,'interactionType':interactionType,
    'binding':binding,'effectOperation':effectOperation,'payloadSha256':payloadSha256,
    'uiSurfaceSha256':uiSurfaceSha256,'confirmationTextSha256':confirmationTextSha256,
    'userPresent':userPresent,'approvalScope':approvalScope,'approvalPolicy':approvalPolicy,
    if (ownerSessionId != null) 'ownerSessionId':ownerSessionId,
    'expiresAtEpochSeconds':expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000,
    if (behaviorSessionId != null) 'behaviorSessionId':behaviorSessionId,
  };
}'''
rx('lib/product/p1_authority_service_contract_v1.dart',r'class P1AuthorityOwnerApprovalRequestV2 \{.*?\n\}\n\nclass P1AuthorityEffectRequestV1',approval+'\n\nclass P1AuthorityEffectRequestV1')

rep('lib/product/p1_authority_service_contract_v1.dart',
'''    this.behaviorSessionId,
  });

  final String requestId;''',
'''    this.ownerSessionId,
    this.behaviorSessionId,
  });

  final String requestId;''')
rep('lib/product/p1_authority_service_contract_v1.dart',
'''  final DateTime deadline;
  final String? behaviorSessionId;

  void validate(DateTime now) {''',
'''  final DateTime deadline;
  final String? ownerSessionId;
  final String? behaviorSessionId;

  void validate(DateTime now) {''')
rep('lib/product/p1_authority_service_contract_v1.dart',
'''    if (!_p1aHex64.hasMatch(payloadSha256) ||
        workerIdentity.isEmpty ||''',
'''    if ((ownerSessionId != null && !_p1aId.hasMatch(ownerSessionId!)) ||
        !_p1aHex64.hasMatch(payloadSha256) ||
        workerIdentity.isEmpty ||''')
rep('lib/product/p1_authority_service_contract_v1.dart',
'''        'ownerApprovalId': ownerApprovalId,
        'expectedRevocationEpoch': expectedRevocationEpoch,''',
'''        'ownerApprovalId': ownerApprovalId,
        if (ownerSessionId != null) 'ownerSessionId': ownerSessionId,
        'expectedRevocationEpoch': expectedRevocationEpoch,''')

handle='''final class P1AuthorityServiceHandleV1 {
  const P1AuthorityServiceHandleV1(this.service);
  final P1AuthorityServiceClientV1 service;

  bool get runtimeEligible {
    final p = service.provenance;
    return p['authorityType'] == 'p1-isolated-authority-service-v2' &&
        p['p1AmendmentSchemaVersion'] == '3.0.0' && p['runtimeEligible'] == true &&
        p['securityIsolationActive'] == true && p['privateAuthorityMaterialPresent'] == false &&
        p['arbitraryMessageSigningApi'] == false && service.endpoint.osEnforcedIsolation &&
        service.endpoint.workerPrincipalSeparated && service.endpoint.typedOperationsOnly &&
        service.endpoint.nonExportableKeys;
  }

  bool get completionEligible {
    final p = service.provenance;
    bool h40(Object? v) => _p1aHex40.hasMatch(v?.toString() ?? '');
    bool h64(Object? v) => _p1aHex64.hasMatch(v?.toString() ?? '');
    return service.completionEligible && runtimeEligible && p['p1AmendmentMerged'] == true &&
        p['independentP1aSecurityReviewApproved'] == true && p['workerDenialTriPlatformPassed'] == true &&
        p['behavioralWindowsPassed'] == true && p['behavioralMacosPassed'] == true && p['behavioralLinuxPassed'] == true &&
        h40(p['mergedCommit']) && h40(p['mergedTree']) && h64(p['aggregateManifestSha256']) &&
        h64(p['platformReceiptSha256']) && h64(p['evidenceTrustSha256']) && h64(p['serviceBehaviorReceiptSha256']) &&
        h64(p['workerDenialReceiptSha256']) && h64(p['workerLauncherSha256']) && h64(p['workerExecutableSha256']) &&
        h64(p['workerIdentitySha256']) && h64(p['denialTranscriptSha256']) && h64(p['p1aPackageSha256']) &&
        p['completionEligible'] == true;
  }

  void validateForP2({bool allowQaPreview = false}) {
    service.endpoint.validate();
    final p = service.provenance;
    final qa = allowQaPreview && p['qaPreview'] == true && p['qaPreviewVersion'] == '1.0.0' &&
        p['qaPreviewFormalCompletion'] == false && p['privateAuthorityMaterialPresent'] == false &&
        p['arbitraryMessageSigningApi'] == false && service.endpoint.osEnforcedIsolation &&
        service.endpoint.workerPrincipalSeparated && service.endpoint.typedOperationsOnly && service.endpoint.nonExportableKeys;
    if (qa || runtimeEligible || completionEligible) return;
    throw StateError('p1a_service_not_runtime_eligible');
  }

  void validateCompletionEligibility() {
    service.endpoint.validate();
    if (!completionEligible) throw StateError('p1a_service_not_completion_eligible');
  }
}'''
rx('lib/product/p1_authority_service_contract_v1.dart',r'final class P1AuthorityServiceHandleV1 \{.*?\n\}\s*$',handle+'\n')

wr('lib/product/p2_owner_mode.dart',"""import 'dart:math';

enum P2OwnerApprovalPolicy { everyHighRiskEffect, destructiveOnly, boundedSession }
enum P2OwnerModeState { disabled, enabledInteractive, enabledUnattended }

class P2OwnerModeSettings {
  const P2OwnerModeSettings({required this.state,required this.approvalPolicy,required this.enabledAt,
    required this.dataBoundaryAcknowledged,this.sessionId,this.sessionExpiresAt});
  final P2OwnerModeState state; final P2OwnerApprovalPolicy approvalPolicy; final DateTime? enabledAt;
  final String? sessionId; final DateTime? sessionExpiresAt; final bool dataBoundaryAcknowledged;
  bool get enabled => state != P2OwnerModeState.disabled;
  bool get unattended => state == P2OwnerModeState.enabledUnattended;
  String get accessProfileId => switch(state){P2OwnerModeState.enabledUnattended=>'owner_unattended',P2OwnerModeState.enabledInteractive=>'owner',P2OwnerModeState.disabled=>'chat'};
  String get persistentIndicator => enabled ? 'OWNER MODE — full current-account access' : 'Owner Mode off';
  String get safetyLabel => enabled ? 'Authorized effects can reach all resources available to this OS account.' : 'No Owner Mode host authority.';
  Map<String,Object?> toJson() => <String,Object?>{'schemaVersion':'1.1.0','state':state.name,'approvalPolicy':approvalPolicy.name,
    'enabledAt':enabledAt?.toUtc().toIso8601String(),'sessionId':sessionId,'sessionExpiresAt':sessionExpiresAt?.toUtc().toIso8601String(),
    'dataBoundaryAcknowledged':dataBoundaryAcknowledged};
  factory P2OwnerModeSettings.disabled()=>const P2OwnerModeSettings(state:P2OwnerModeState.disabled,
    approvalPolicy:P2OwnerApprovalPolicy.boundedSession,enabledAt:null,dataBoundaryAcknowledged:false);
  P2OwnerModeSettings reset()=>P2OwnerModeSettings.disabled();
}

typedef P2OwnerModeEnableAuthorizer = Future<void> Function(P2OwnerModeSettings settings);
class P2OwnerModeController {
  P2OwnerModeController(this.persist,this.clear,{this.authorizeEnable,this.clearAuthorization});
  final Future<void> Function(Map<String,Object?>) persist; final Future<void> Function() clear;
  final P2OwnerModeEnableAuthorizer? authorizeEnable; final Future<void> Function()? clearAuthorization;
  P2OwnerModeSettings current=P2OwnerModeSettings.disabled();
  static String _sessionId(){final r=Random.secure();final b=List<int>.generate(24,(_)=>r.nextInt(256));
    return 'owner-session-${b.map((v)=>v.toRadixString(16).padLeft(2,'0')).join()}';}
  Future<void> enable({required bool unattended,required P2OwnerApprovalPolicy approvalPolicy,required bool acknowledged,DateTime? expiresAt}) async {
    if(!acknowledged) throw StateError('owner_data_boundary_acknowledgement_required');
    final now=DateTime.now().toUtc(); final expiry=expiresAt?.toUtc() ?? now.add(unattended?const Duration(hours:24):const Duration(hours:8));
    if(!now.isBefore(expiry)||expiry.difference(now)>const Duration(hours:24)) throw StateError('owner_session_expiry_invalid');
    final next=P2OwnerModeSettings(state:unattended?P2OwnerModeState.enabledUnattended:P2OwnerModeState.enabledInteractive,
      approvalPolicy:approvalPolicy,enabledAt:now,sessionId:_sessionId(),sessionExpiresAt:expiry,dataBoundaryAcknowledged:true);
    try { await authorizeEnable?.call(next); await persist(next.toJson()); current=next; }
    catch(_){ await clearAuthorization?.call(); rethrow; }
  }
  Future<void> disableAndReset() async {current=current.reset();try{await clearAuthorization?.call();}finally{await clear();}}
}
""")
rep('lib/product/p2_owner_workspace.dart','  var _approval = P2OwnerApprovalPolicy.everyHighRiskEffect;','  var _approval = P2OwnerApprovalPolicy.boundedSession;')
rep('lib/product/p2_owner_workspace.dart',"""          const Text(
            'Owner Mode can reach all files, applications, terminals, and '
            'account resources available to this OS account. It is not '
            'containment or isolation.',
          ),""", """          const Text(
            'Owner Mode can reach all files, applications, terminals, and '
            'account resources available to this OS account. Kristin keeps '
            'policy, grant, and signing authority isolated from automation '
            'workers while authorized effects still act with your account access.',
          ),""")
rep('test/product/p2_owner_workspace_test.dart',"    expect(find.textContaining('not containment or isolation'), findsOneWidget);","    expect(find.textContaining('signing authority isolated'), findsOneWidget);")

rep('lib/product/p2_p1_authority_adapter.dart',"import 'p2_effect_boundary.dart';","import 'p2_effect_boundary.dart';\nimport 'p2_owner_mode.dart';")
rep('lib/product/p2_p1_authority_adapter.dart','  bool get _executionEligible => completionEligible || _qaPreview;',"""  bool get runtimeEligible => service.provenance['runtimeEligible'] == true && service.provenance['securityIsolationActive'] == true;
  bool get _executionEligible => completionEligible || runtimeEligible || _qaPreview;""")
rep('lib/product/p2_p1_authority_adapter.dart','  Map<String, Object?>? _restrictedWorkerIdentity;',"""  Map<String, Object?>? _restrictedWorkerIdentity;
  P2OwnerModeSettings? _ownerModeSettings;
  String? _ownerSessionApprovalId;""")
anchor="""  @override
  Map<String, Object?>? lastAuthorityObservation(String taskId) =>
      _observations[taskId];
"""
extra="""
  Future<void> authorizeOwnerModeSettings(P2OwnerModeSettings settings) async {
    final sessionId=settings.sessionId; final expiresAt=settings.sessionExpiresAt; final now=DateTime.now().toUtc();
    if(!settings.enabled||!settings.dataBoundaryAcknowledged||sessionId==null||sessionId.isEmpty||expiresAt==null||
       !now.isBefore(expiresAt)||expiresAt.difference(now)>const Duration(hours:24)) throw StateError('p1a_owner_session_settings_invalid');
    final approvalId=_id('owner-session-approval');
    final binding=<String,Object?>{'runId':'owner-session','taskId':sessionId,'actorId':'desktop-owner','toolId':'owner-mode',
      'accessProfileId':settings.accessProfileId,'capabilityId':'owner-session'};
    final intent=<String,Object?>{'sessionId':sessionId,'accessProfileId':settings.accessProfileId,'approvalPolicy':settings.approvalPolicy.name,
      'enabledAt':settings.enabledAt?.toUtc().toIso8601String(),'expiresAt':expiresAt.toUtc().toIso8601String(),'fullCurrentAccountBoundary':true};
    final request=P1AuthorityOwnerApprovalRequestV2(requestId:_id('owner-session-request'),approvalId:approvalId,
      interactionNonce:_id('owner-session-interaction'),binding:binding,effectOperation:'owner-session',
      payloadSha256:Sha256.text(p1aCanonicalJson(intent)),uiSurfaceSha256:Sha256.text('Kristin Owner Mode enable full current-account access'),
      confirmationTextSha256:Sha256.text('Enable ${settings.accessProfileId} through ${expiresAt.toIso8601String()}'),expiresAt:expiresAt,
      approvalScope:'owner-session',approvalPolicy:settings.approvalPolicy.name,ownerSessionId:sessionId);
    request.validate(now); final recorded=await service.recordOwnerApproval(request); final approval=recorded['approval'];
    if(recorded['status']!='recorded'||approval is! Map||approval['approvalId']!=approvalId||approval['approvalScope']!='owner-session'||approval['ownerSessionId']!=sessionId)
      throw StateError('p1a_owner_session_approval_not_recorded');
    _ownerModeSettings=settings; _ownerSessionApprovalId=approvalId;
  }
  Future<void> clearOwnerModeSettings() async {_ownerModeSettings=null;_ownerSessionApprovalId=null;}
  bool _destructive(String operation){final s=operation.toLowerCase();return const <String>['delete','remove','terminate','kill','uninstall','elevate','shutdown','reboot','format'].any(s.contains);}
  Future<String> _exactApproval({required String requestId,required P2EffectBinding binding,required String operation,
    required Map<String,Object?> payload,required P2OwnerModeSettings settings}) async {
    final now=DateTime.now().toUtc();final sessionExpiry=settings.sessionExpiresAt!;final candidate=now.add(const Duration(minutes:15));
    final expiry=candidate.isBefore(sessionExpiry)?candidate:sessionExpiry;final id=_id('owner-effect-approval');
    final request=P1AuthorityOwnerApprovalRequestV2(requestId:requestId,approvalId:id,interactionNonce:_id('owner-effect-interaction'),
      binding:<String,Object?>{'runId':binding.runId,'taskId':binding.taskId,'actorId':binding.actorId,'toolId':binding.toolId,
        'accessProfileId':binding.accessProfileId,'capabilityId':binding.capabilityId},effectOperation:operation,
      payloadSha256:Sha256.text(p1aCanonicalJson(payload)),uiSurfaceSha256:Sha256.text('Kristin Owner Mode authorized session'),
      confirmationTextSha256:Sha256.text('Authorize $operation under ${settings.approvalPolicy.name}'),expiresAt:expiry,
      approvalScope:'effect',approvalPolicy:settings.approvalPolicy.name);
    request.validate(now);final recorded=await service.recordOwnerApproval(request);if(recorded['status']!='recorded') throw StateError('p1a_owner_effect_approval_not_recorded');return id;
  }
"""
rep('lib/product/p2_p1_authority_adapter.dart',anchor,anchor+extra)
rep('lib/product/p2_p1_authority_adapter.dart',"""    final exactPayload = <String, Object?>{'operation': operation, ...payload};
    final ownerApprovalId = exactPayload['ownerApprovalId']?.toString() ?? '';
    if (ownerApprovalId.isEmpty) {
      throw StateError('p1a_explicit_owner_approval_required');
    }
    final requestId = _id('p2-request');
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(deadline);
    final descriptor = P2P1OperationRegistry.descriptor(operation);""", """    final exactPayload = <String, Object?>{'operation': operation, ...payload};
    final requestId = _id('p2-request');
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(deadline);
    final settings=_ownerModeSettings; String ownerApprovalId; String? ownerSessionId;
    if(settings==null){ownerApprovalId=exactPayload['ownerApprovalId']?.toString() ?? '';if(ownerApprovalId.isEmpty) throw StateError('p1a_owner_mode_not_enabled');}
    else {final sessionId=settings.sessionId;final sessionExpiry=settings.sessionExpiresAt;
      if(!settings.enabled||!settings.dataBoundaryAcknowledged||sessionId==null||sessionExpiry==null||!now.isBefore(sessionExpiry)||settings.accessProfileId!=binding.accessProfileId)
        throw StateError('p1a_owner_session_not_active');
      final useSession=settings.unattended||settings.approvalPolicy==P2OwnerApprovalPolicy.boundedSession||
        (settings.approvalPolicy==P2OwnerApprovalPolicy.destructiveOnly&&!_destructive(operation));
      if(useSession){ownerApprovalId=_ownerSessionApprovalId ?? '';ownerSessionId=sessionId;if(ownerApprovalId.isEmpty) throw StateError('p1a_owner_session_approval_missing');}
      else {ownerApprovalId=await _exactApproval(requestId:requestId,binding:binding,operation:operation,payload:exactPayload,settings:settings);}}
    final descriptor = P2P1OperationRegistry.descriptor(operation);""")
rep('lib/product/p2_p1_authority_adapter.dart','      ownerApprovalId: ownerApprovalId,\n      workerSessionId: workerSessionId,','      ownerApprovalId: ownerApprovalId,\n      ownerSessionId: ownerSessionId,\n      workerSessionId: workerSessionId,')
rep('lib/product/p2_p1_authority_adapter.dart',"""        'completionEligible': completionEligible,
        'qaPreview': _qaPreview,""","""        'completionEligible': completionEligible,
        'runtimeEligible': runtimeEligible,
        'secureIsolationActive': runtimeEligible || completionEligible,
        'productionCertificationComplete': completionEligible,
        'qaPreview': _qaPreview,""")

rep('lib/product/p2_product_runtime_integration.dart',"""    final productionAuthority = authority.completionEligible &&
        authority.authorityKind == 'p1-isolated-authority-service-v2';
    final ownerRiskAuthority = authority.qaPreview &&""","""    final secureP1aAuthority = authority.authorityKind == 'p1-isolated-authority-service-v2' &&
        (authority.completionEligible || authority.authorityProvenance['runtimeEligible'] == true) &&
        authority.authorityProvenance['secureIsolationActive'] != false;
    final ownerRiskAuthority = authority.qaPreview &&""")
rep('lib/product/p2_product_runtime_integration.dart','    if (!(productionAuthority || ownerRiskAuthority)) {','    if (!(secureP1aAuthority || ownerRiskAuthority)) {')
rep('lib/product/p2_product_runtime_integration.dart','    required Future<void> Function() clearOwnerSettings,\n    required String emergencyWatchdogId,','    required Future<void> Function() clearOwnerSettings,\n    P2OwnerModeEnableAuthorizer? authorizeOwnerModeEnable,\n    Future<void> Function()? clearOwnerModeAuthorization,\n    required String emergencyWatchdogId,')
rep('lib/product/p2_product_runtime_integration.dart',"""    final controller = P2OwnerModeController(
      persistOwnerSettings,
      clearOwnerSettings,
    );""","""    final controller = P2OwnerModeController(persistOwnerSettings,clearOwnerSettings,
      authorizeEnable: authorizeOwnerModeEnable,clearAuthorization: clearOwnerModeAuthorization);""")
rep('lib/product/p2_product_runtime_integration.dart',"        'ownerRiskQa': authority.qaPreview,\n      };","        'ownerRiskQa': authority.qaPreview,\n        'secureIsolationActive': authority.authorityProvenance['secureIsolationActive'] == true,\n        'productionCertificationComplete': authority.completionEligible,\n      };")

rep('lib/product/p2_product_runtime_bootstrap.dart',"import 'p2_owner_workspace.dart';","import 'p2_owner_mode.dart';\nimport 'p2_owner_workspace.dart';")
rep('lib/product/p2_product_runtime_bootstrap.dart',"""  bool get completionEligible =>
      runtime?.authority.completionEligible == true &&
      runtime?.authority.authorityKind == 'p1-isolated-authority-service-v2';
""","""  bool get completionEligible => runtime?.authority.completionEligible == true && runtime?.authority.authorityKind == 'p1-isolated-authority-service-v2';
  bool get secureIsolationActive => runtime?.authority.authorityKind == 'p1-isolated-authority-service-v2' &&
      (runtime?.authority.authorityProvenance['runtimeEligible'] == true || runtime?.authority.completionEligible == true);
""")
rep('lib/product/p2_product_runtime_bootstrap.dart',"""      final P2RuntimeAuthority authority = ownerRiskQa
          ? P2OwnerRiskQaAuthority()
          : P2IsolatedP1AuthorityAdapter(
              p1AuthorityService!,
              qaPreview: qaPreview,
            );""","""      final P2IsolatedP1AuthorityAdapter? p1Adapter = ownerRiskQa ? null : P2IsolatedP1AuthorityAdapter(p1AuthorityService!,qaPreview:qaPreview);
      final P2RuntimeAuthority authority = p1Adapter ?? P2OwnerRiskQaAuthority();""")
rep('lib/product/p2_product_runtime_bootstrap.dart','      final runtime = await P2ProductRuntimeOwnerMode.start(\n        stateDirectory:','      P2ProductRuntimeOwnerMode? activeOwnerRuntime;\n      final runtime = await P2ProductRuntimeOwnerMode.start(\n        stateDirectory:')
rep('lib/product/p2_product_runtime_bootstrap.dart',"            accessProfileId: 'owner',\n            operation: operation,","            accessProfileId: activeOwnerRuntime?.controller.current.accessProfileId ?? 'owner',\n            operation: operation,")
rep('lib/product/p2_product_runtime_bootstrap.dart',"""        clearOwnerSettings: () async {
          final file = File(
            '${authorityDirectory.path}${Platform.pathSeparator}owner-mode.v1.json',
          );
          if (await file.exists()) {
            await file.delete();
          }
        },
        emergencyWatchdogId:""","""        clearOwnerSettings: () async {
          final file = File('${authorityDirectory.path}${Platform.pathSeparator}owner-mode.v1.json');
          if (await file.exists()) await file.delete();
        },
        authorizeOwnerModeEnable: p1Adapter?.authorizeOwnerModeSettings,
        clearOwnerModeAuthorization: p1Adapter?.clearOwnerModeSettings,
        emergencyWatchdogId:""")
rep('lib/product/p2_product_runtime_bootstrap.dart','      );\n      return P2ProductRuntimeOwnerModeHandle.active(runtime);','      );\n      activeOwnerRuntime = runtime;\n      return P2ProductRuntimeOwnerModeHandle.active(runtime);')
print('P1A_DART_PATCH_OK')
