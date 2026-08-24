#!/usr/bin/env python3
from __future__ import annotations
import pathlib,re
R=pathlib.Path(__file__).resolve().parents[1]
def rd(p): return (R/p).read_text(encoding='utf-8')
def wr(p,s): (R/p).write_text(s,encoding='utf-8',newline='\n')
def rep(p,a,b):
 s=rd(p);n=s.count(a)
 if n!=1: raise SystemExit(f'{p}: target count {n}: {a[:70]!r}')
 wr(p,s.replace(a,b,1))
def rx(p,a,b):
 s=rd(p);u,n=re.subn(a,b,s,count=1,flags=re.S)
 if n!=1: raise SystemExit(f'{p}: regex target count {n}: {a[:70]!r}')
 wr(p,u)

p='lib/product/p1_authority_service_contract_v1.dart'
approval="""class P1AuthorityOwnerApprovalRequestV2 {
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
    for (final value in <String>[
      requestId,
      approvalId,
      interactionNonce,
      effectOperation,
    ]) {
      if (!_p1aId.hasMatch(value)) {
        throw StateError('p1a_owner_approval_identity_invalid');
      }
    }
    final profile = binding['accessProfileId']?.toString() ?? '';
    final requiredBinding = <String>[
      'runId',
      'taskId',
      'actorId',
      'toolId',
      'accessProfileId',
      'capabilityId',
    ];
    final sessionScope = approvalScope == 'owner-session';
    final maxLifetime = sessionScope
        ? const Duration(hours: 24)
        : const Duration(minutes: 15);
    final sessionId = ownerSessionId;
    if (!const <String>{'effect', 'owner-session'}.contains(approvalScope) ||
        !const <String>{
          'everyHighRiskEffect',
          'destructiveOnly',
          'boundedSession',
        }.contains(approvalPolicy) ||
        (sessionScope &&
            (effectOperation != 'owner-session' ||
                sessionId == null ||
                !_p1aId.hasMatch(sessionId))) ||
        (!sessionScope && sessionId != null) ||
        interactionType != 'native-owner-confirmation' ||
        !userPresent ||
        binding.length < requiredBinding.length ||
        requiredBinding.any(
          (key) => !_p1aId.hasMatch(binding[key]?.toString() ?? ''),
        ) ||
        (profile != 'owner' && profile != 'owner_unattended') ||
        !_p1aHex64.hasMatch(payloadSha256) ||
        !_p1aHex64.hasMatch(uiSurfaceSha256) ||
        !_p1aHex64.hasMatch(confirmationTextSha256) ||
        !now.toUtc().isBefore(expiresAt.toUtc()) ||
        expiresAt.toUtc().difference(now.toUtc()) > maxLifetime) {
      throw StateError('p1a_owner_approval_limits_invalid');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': '2.0.0',
        'operation': p1aRecordOwnerApprovalOperationV2,
        'requestId': requestId,
        'approvalId': approvalId,
        'interactionNonce': interactionNonce,
        'interactionType': interactionType,
        'binding': binding,
        'effectOperation': effectOperation,
        'payloadSha256': payloadSha256,
        'uiSurfaceSha256': uiSurfaceSha256,
        'confirmationTextSha256': confirmationTextSha256,
        'userPresent': userPresent,
        'approvalScope': approvalScope,
        'approvalPolicy': approvalPolicy,
        if (ownerSessionId != null) 'ownerSessionId': ownerSessionId,
        'expiresAtEpochSeconds':
            expiresAt.toUtc().millisecondsSinceEpoch ~/ 1000,
        if (behaviorSessionId != null) 'behaviorSessionId': behaviorSessionId,
      };
}"""
effect="""class P1AuthorityEffectRequestV1 {
  const P1AuthorityEffectRequestV1({
    required this.requestId,
    required this.requestNonce,
    required this.runId,
    required this.taskId,
    required this.actorId,
    required this.toolId,
    required this.accessProfileId,
    required this.capabilityId,
    required this.operation,
    required this.payload,
    required this.payloadSha256,
    required this.ownerApprovalId,
    required this.workerSessionId,
    required this.channelId,
    required this.workerIdentity,
    required this.policyEffect,
    required this.requestedBudgets,
    required this.expectedRevocationEpoch,
    required this.deadline,
    this.ownerSessionId,
    this.behaviorSessionId,
  });

  final String requestId;
  final String requestNonce;
  final String runId;
  final String taskId;
  final String actorId;
  final String toolId;
  final String accessProfileId;
  final String capabilityId;
  final String operation;
  final Map<String, Object?> payload;
  final String payloadSha256;
  final String ownerApprovalId;
  final String workerSessionId;
  final String channelId;
  final Map<String, Object?> workerIdentity;
  final Map<String, Object?> policyEffect;
  final Map<String, Object?> requestedBudgets;
  final int expectedRevocationEpoch;
  final DateTime deadline;
  final String? ownerSessionId;
  final String? behaviorSessionId;

  void validate(DateTime now) {
    for (final value in <String>[
      requestId,
      requestNonce,
      runId,
      taskId,
      actorId,
      toolId,
      capabilityId,
      operation,
      ownerApprovalId,
      workerSessionId,
      channelId,
    ]) {
      if (!_p1aId.hasMatch(value)) {
        throw StateError('p1a_request_identity_invalid');
      }
    }
    if (accessProfileId != 'owner' && accessProfileId != 'owner_unattended') {
      throw StateError('p1a_owner_profile_required');
    }
    if ((ownerSessionId != null && !_p1aId.hasMatch(ownerSessionId!)) ||
        !_p1aHex64.hasMatch(payloadSha256) ||
        workerIdentity.isEmpty ||
        policyEffect.isEmpty ||
        requestedBudgets.isEmpty ||
        expectedRevocationEpoch < 0 ||
        !now.toUtc().isBefore(deadline.toUtc()) ||
        deadline.toUtc().difference(now.toUtc()) > const Duration(minutes: 2)) {
      throw StateError('p1a_request_limits_invalid');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': '2.0.0',
        'operation': p1aAuthorizeEffectOperationV1,
        'requestId': requestId,
        'requestNonce': requestNonce,
        'workerSessionId': workerSessionId,
        'channelId': channelId,
        'workerIdentity': workerIdentity,
        'effectOperation': operation,
        'binding': <String, Object?>{
          'runId': runId,
          'taskId': taskId,
          'actorId': actorId,
          'toolId': toolId,
          'accessProfileId': accessProfileId,
          'capabilityId': capabilityId,
        },
        'policyEffect': policyEffect,
        'requestedBudgets': requestedBudgets,
        'payload': payload,
        'payloadSha256': payloadSha256,
        'ownerApprovalId': ownerApprovalId,
        if (ownerSessionId != null) 'ownerSessionId': ownerSessionId,
        'expectedRevocationEpoch': expectedRevocationEpoch,
        'deadlineEpochSeconds': deadline.toUtc().millisecondsSinceEpoch ~/ 1000,
        if (behaviorSessionId != null) 'behaviorSessionId': behaviorSessionId,
      };
}"""
rx(p,r'class P1AuthorityOwnerApprovalRequestV2 \{.*?\n\}\n\nclass P1AuthorityEffectRequestV1',approval+'\n\nclass P1AuthorityEffectRequestV1')
rx(p,r'class P1AuthorityEffectRequestV1 \{.*?\n\}\n\nclass P1AuthorityEffectPermitV1',effect+'\n\nclass P1AuthorityEffectPermitV1')
handle="""final class P1AuthorityServiceHandleV1 {
  const P1AuthorityServiceHandleV1(this.service);
  final P1AuthorityServiceClientV1 service;

  bool get runtimeEligible {
    final provenance = service.provenance;
    return provenance['authorityType'] == 'p1-isolated-authority-service-v2' &&
        provenance['p1AmendmentSchemaVersion'] == '3.0.0' &&
        provenance['runtimeEligible'] == true &&
        provenance['securityIsolationActive'] == true &&
        provenance['privateAuthorityMaterialPresent'] == false &&
        provenance['arbitraryMessageSigningApi'] == false &&
        service.endpoint.osEnforcedIsolation &&
        service.endpoint.workerPrincipalSeparated &&
        service.endpoint.typedOperationsOnly &&
        service.endpoint.nonExportableKeys;
  }

  bool get completionEligible {
    final provenance = service.provenance;
    bool hash40(Object? value) =>
        _p1aHex40.hasMatch(value?.toString() ?? '');
    bool hash64(Object? value) =>
        _p1aHex64.hasMatch(value?.toString() ?? '');
    return service.completionEligible &&
        runtimeEligible &&
        provenance['p1AmendmentMerged'] == true &&
        provenance['independentP1aSecurityReviewApproved'] == true &&
        provenance['workerDenialTriPlatformPassed'] == true &&
        provenance['behavioralWindowsPassed'] == true &&
        provenance['behavioralMacosPassed'] == true &&
        provenance['behavioralLinuxPassed'] == true &&
        hash40(provenance['mergedCommit']) &&
        hash40(provenance['mergedTree']) &&
        hash64(provenance['aggregateManifestSha256']) &&
        hash64(provenance['platformReceiptSha256']) &&
        hash64(provenance['evidenceTrustSha256']) &&
        hash64(provenance['serviceBehaviorReceiptSha256']) &&
        hash64(provenance['workerDenialReceiptSha256']) &&
        hash64(provenance['workerLauncherSha256']) &&
        hash64(provenance['workerExecutableSha256']) &&
        hash64(provenance['workerIdentitySha256']) &&
        hash64(provenance['denialTranscriptSha256']) &&
        hash64(provenance['p1aPackageSha256']) &&
        provenance['completionEligible'] == true;
  }

  void validateForP2({bool allowQaPreview = false}) {
    service.endpoint.validate();
    final provenance = service.provenance;
    final qaPreviewAccepted = allowQaPreview &&
        provenance['qaPreview'] == true &&
        provenance['qaPreviewVersion'] == '1.0.0' &&
        provenance['qaPreviewFormalCompletion'] == false &&
        provenance['privateAuthorityMaterialPresent'] == false &&
        provenance['arbitraryMessageSigningApi'] == false &&
        service.endpoint.osEnforcedIsolation &&
        service.endpoint.workerPrincipalSeparated &&
        service.endpoint.typedOperationsOnly &&
        service.endpoint.nonExportableKeys;
    if (qaPreviewAccepted || runtimeEligible || completionEligible) return;
    throw StateError('p1a_service_not_runtime_eligible');
  }

  void validateCompletionEligibility() {
    service.endpoint.validate();
    if (!completionEligible) {
      throw StateError('p1a_service_not_completion_eligible');
    }
  }
}"""
rx(p,r'final class P1AuthorityServiceHandleV1 \{.*?\n\}\s*$',handle+'\n')

wr('lib/product/p2_owner_mode.dart',"""import 'dart:math';

enum P2OwnerApprovalPolicy { everyHighRiskEffect, destructiveOnly, boundedSession }
enum P2OwnerModeState { disabled, enabledInteractive, enabledUnattended }
class P2OwnerModeSettings {
  const P2OwnerModeSettings({required this.state,required this.approvalPolicy,required this.enabledAt,
    required this.dataBoundaryAcknowledged,this.sessionId,this.sessionExpiresAt});
  final P2OwnerModeState state;
  final P2OwnerApprovalPolicy approvalPolicy;
  final DateTime? enabledAt;
  final String? sessionId;
  final DateTime? sessionExpiresAt;
  final bool dataBoundaryAcknowledged;
  bool get enabled => state != P2OwnerModeState.disabled;
  bool get unattended => state == P2OwnerModeState.enabledUnattended;
  String get accessProfileId => switch (state) {
    P2OwnerModeState.enabledUnattended => 'owner_unattended',
    P2OwnerModeState.enabledInteractive => 'owner',
    P2OwnerModeState.disabled => 'chat',
  };
  String get persistentIndicator => enabled ? 'OWNER MODE — full current-account access' : 'Owner Mode off';
  String get safetyLabel => enabled
      ? 'Authorized effects can reach all resources available to this OS account.'
      : 'No Owner Mode host authority.';
  Map<String,Object?> toJson() => <String,Object?>{
    'schemaVersion':'1.1.0','state':state.name,'approvalPolicy':approvalPolicy.name,
    'enabledAt':enabledAt?.toUtc().toIso8601String(),'sessionId':sessionId,
    'sessionExpiresAt':sessionExpiresAt?.toUtc().toIso8601String(),
    'dataBoundaryAcknowledged':dataBoundaryAcknowledged,
  };
  factory P2OwnerModeSettings.disabled() => const P2OwnerModeSettings(
    state:P2OwnerModeState.disabled,approvalPolicy:P2OwnerApprovalPolicy.boundedSession,
    enabledAt:null,dataBoundaryAcknowledged:false,
  );
  P2OwnerModeSettings reset() => P2OwnerModeSettings.disabled();
}
typedef P2OwnerModeEnableAuthorizer = Future<void> Function(P2OwnerModeSettings settings);
class P2OwnerModeController {
  P2OwnerModeController(this.persist,this.clear,{this.authorizeEnable,this.clearAuthorization});
  final Future<void> Function(Map<String,Object?>) persist;
  final Future<void> Function() clear;
  final P2OwnerModeEnableAuthorizer? authorizeEnable;
  final Future<void> Function()? clearAuthorization;
  P2OwnerModeSettings current = P2OwnerModeSettings.disabled();
  static String _newSessionId() {
    final random=Random.secure();
    final bytes=List<int>.generate(24,(_)=>random.nextInt(256));
    return 'owner-session-${bytes.map((value)=>value.toRadixString(16).padLeft(2,'0')).join()}';
  }
  Future<void> enable({required bool unattended,required P2OwnerApprovalPolicy approvalPolicy,
    required bool acknowledged,DateTime? expiresAt}) async {
    if(!acknowledged) throw StateError('owner_data_boundary_acknowledgement_required');
    final now=DateTime.now().toUtc();
    final expiry=expiresAt?.toUtc() ?? now.add(unattended?const Duration(hours:24):const Duration(hours:8));
    if(!now.isBefore(expiry)||expiry.difference(now)>const Duration(hours:24)) {
      throw StateError('owner_session_expiry_invalid');
    }
    final next=P2OwnerModeSettings(
      state:unattended?P2OwnerModeState.enabledUnattended:P2OwnerModeState.enabledInteractive,
      approvalPolicy:approvalPolicy,enabledAt:now,sessionId:_newSessionId(),
      sessionExpiresAt:expiry,dataBoundaryAcknowledged:true,
    );
    try {await authorizeEnable?.call(next);await persist(next.toJson());current=next;}
    catch(_){await clearAuthorization?.call();rethrow;}
  }
  Future<void> disableAndReset() async {
    current=current.reset();
    try {await clearAuthorization?.call();} finally {await clear();}
  }
}
""")

p='lib/product/p2_owner_workspace.dart'
rep(p,'  var _approval = P2OwnerApprovalPolicy.everyHighRiskEffect;','  var _approval = P2OwnerApprovalPolicy.boundedSession;')
rep(p,"""          const Text(
            'Owner Mode can reach all files, applications, terminals, and '
            'account resources available to this OS account. It is not '
            'containment or isolation.',
          ),""","""          const Text(
            'Owner Mode can reach all files, applications, terminals, and '
            'account resources available to this OS account. Kristin keeps '
            'policy, grant, and signing authority isolated from automation '
            'workers while authorized effects still act with your account access.',
          ),""")
rep('test/product/p2_owner_workspace_test.dart',"    expect(find.textContaining('not containment or isolation'), findsOneWidget);","    expect(find.textContaining('signing authority isolated'), findsOneWidget);")

p='lib/product/p2_p1_authority_adapter.dart'
rep(p,"import 'p2_effect_boundary.dart';","import 'p2_effect_boundary.dart';\nimport 'p2_owner_mode.dart';")
rep(p,'  bool get _executionEligible => completionEligible || _qaPreview;',"""  bool get runtimeEligible =>
      service.provenance['runtimeEligible'] == true &&
      service.provenance['securityIsolationActive'] == true;
  bool get _executionEligible => completionEligible || runtimeEligible || _qaPreview;""")
rep(p,'  Map<String, Object?>? _restrictedWorkerIdentity;',"""  Map<String, Object?>? _restrictedWorkerIdentity;
  P2OwnerModeSettings? _ownerModeSettings;
  String? _ownerSessionApprovalId;""")
anchor="""  @override
  Map<String, Object?>? lastAuthorityObservation(String taskId) =>
      _observations[taskId];
"""
extra="""
  Future<void> authorizeOwnerModeSettings(P2OwnerModeSettings settings) async {
    final sessionId=settings.sessionId;
    final expiresAt=settings.sessionExpiresAt;
    final now=DateTime.now().toUtc();
    if(!settings.enabled||!settings.dataBoundaryAcknowledged||sessionId==null||sessionId.isEmpty||
        expiresAt==null||!now.isBefore(expiresAt)||expiresAt.difference(now)>const Duration(hours:24)) {
      throw StateError('p1a_owner_session_settings_invalid');
    }
    final approvalId=_id('owner-session-approval');
    final binding=<String,Object?>{
      'runId':'owner-session','taskId':sessionId,'actorId':'desktop-owner','toolId':'owner-mode',
      'accessProfileId':settings.accessProfileId,'capabilityId':'owner-session',
    };
    final intent=<String,Object?>{
      'sessionId':sessionId,'accessProfileId':settings.accessProfileId,
      'approvalPolicy':settings.approvalPolicy.name,
      'enabledAt':settings.enabledAt?.toUtc().toIso8601String(),
      'expiresAt':expiresAt.toUtc().toIso8601String(),'fullCurrentAccountBoundary':true,
    };
    final request=P1AuthorityOwnerApprovalRequestV2(
      requestId:_id('owner-session-request'),approvalId:approvalId,
      interactionNonce:_id('owner-session-interaction'),binding:binding,
      effectOperation:'owner-session',payloadSha256:Sha256.text(p1aCanonicalJson(intent)),
      uiSurfaceSha256:Sha256.text('Kristin Owner Mode enable full current-account access'),
      confirmationTextSha256:Sha256.text('Enable ${settings.accessProfileId} through ${expiresAt.toIso8601String()}'),
      expiresAt:expiresAt,approvalScope:'owner-session',approvalPolicy:settings.approvalPolicy.name,
      ownerSessionId:sessionId,
    );
    request.validate(now);
    final recorded=await service.recordOwnerApproval(request);
    final approval=recorded['approval'];
    if(recorded['status']!='recorded'||approval is! Map||approval['approvalId']!=approvalId||
        approval['approvalScope']!='owner-session'||approval['ownerSessionId']!=sessionId) {
      throw StateError('p1a_owner_session_approval_not_recorded');
    }
    _ownerModeSettings=settings;
    _ownerSessionApprovalId=approvalId;
  }

  Future<void> clearOwnerModeSettings() async {
    _ownerModeSettings=null;
    _ownerSessionApprovalId=null;
  }

  bool _destructive(String operation) {
    final value=operation.toLowerCase();
    return const <String>['delete','remove','terminate','kill','uninstall','elevate','shutdown','reboot','format']
        .any(value.contains);
  }

  Future<String> _exactApproval({required String requestId,required P2EffectBinding binding,
    required String operation,required Map<String,Object?> payload,
    required P2OwnerModeSettings settings}) async {
    final now=DateTime.now().toUtc();
    final sessionExpiry=settings.sessionExpiresAt!;
    final candidate=now.add(const Duration(minutes:15));
    final expiresAt=candidate.isBefore(sessionExpiry)?candidate:sessionExpiry;
    final approvalId=_id('owner-effect-approval');
    final request=P1AuthorityOwnerApprovalRequestV2(
      requestId:requestId,approvalId:approvalId,interactionNonce:_id('owner-effect-interaction'),
      binding:<String,Object?>{
        'runId':binding.runId,'taskId':binding.taskId,'actorId':binding.actorId,
        'toolId':binding.toolId,'accessProfileId':binding.accessProfileId,
        'capabilityId':binding.capabilityId,
      },effectOperation:operation,payloadSha256:Sha256.text(p1aCanonicalJson(payload)),
      uiSurfaceSha256:Sha256.text('Kristin Owner Mode authorized session'),
      confirmationTextSha256:Sha256.text('Authorize $operation under ${settings.approvalPolicy.name}'),
      expiresAt:expiresAt,approvalScope:'effect',approvalPolicy:settings.approvalPolicy.name,
    );
    request.validate(now);
    final recorded=await service.recordOwnerApproval(request);
    if(recorded['status']!='recorded') throw StateError('p1a_owner_effect_approval_not_recorded');
    return approvalId;
  }
"""
rep(p,anchor,anchor+extra)
rep(p,"""    final exactPayload = <String, Object?>{'operation': operation, ...payload};
    final ownerApprovalId = exactPayload['ownerApprovalId']?.toString() ?? '';
    if (ownerApprovalId.isEmpty) {
      throw StateError('p1a_explicit_owner_approval_required');
    }
    final requestId = _id('p2-request');
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(deadline);
    final descriptor = P2P1OperationRegistry.descriptor(operation);""","""    final exactPayload = <String, Object?>{'operation': operation, ...payload};
    final requestId = _id('p2-request');
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(deadline);
    final settings=_ownerModeSettings;
    String ownerApprovalId;
    String? ownerSessionId;
    if(settings==null) {
      ownerApprovalId=exactPayload['ownerApprovalId']?.toString() ?? '';
      if(ownerApprovalId.isEmpty) throw StateError('p1a_owner_mode_not_enabled');
    } else {
      final sessionId=settings.sessionId;
      final sessionExpiry=settings.sessionExpiresAt;
      if(!settings.enabled||!settings.dataBoundaryAcknowledged||sessionId==null||sessionExpiry==null||
          !now.isBefore(sessionExpiry)||settings.accessProfileId!=binding.accessProfileId) {
        throw StateError('p1a_owner_session_not_active');
      }
      final useSession=settings.unattended||settings.approvalPolicy==P2OwnerApprovalPolicy.boundedSession||
          (settings.approvalPolicy==P2OwnerApprovalPolicy.destructiveOnly&&!_destructive(operation));
      if(useSession) {
        ownerApprovalId=_ownerSessionApprovalId ?? '';
        ownerSessionId=sessionId;
        if(ownerApprovalId.isEmpty) throw StateError('p1a_owner_session_approval_missing');
      } else {
        ownerApprovalId=await _exactApproval(requestId:requestId,binding:binding,operation:operation,
          payload:exactPayload,settings:settings);
      }
    }
    final descriptor = P2P1OperationRegistry.descriptor(operation);""")
rep(p,'      ownerApprovalId: ownerApprovalId,\n      workerSessionId: workerSessionId,','      ownerApprovalId: ownerApprovalId,\n      ownerSessionId: ownerSessionId,\n      workerSessionId: workerSessionId,')
rep(p,"""        'completionEligible': completionEligible,
        'qaPreview': _qaPreview,""","""        'completionEligible': completionEligible,
        'runtimeEligible': runtimeEligible,
        'secureIsolationActive': runtimeEligible || completionEligible,
        'productionCertificationComplete': completionEligible,
        'qaPreview': _qaPreview,""")

p='lib/product/p2_product_runtime_integration.dart'
rep(p,"""    final productionAuthority = authority.completionEligible &&
        authority.authorityKind == 'p1-isolated-authority-service-v2';
    final ownerRiskAuthority = authority.qaPreview &&""","""    final secureP1aAuthority =
        authority.authorityKind == 'p1-isolated-authority-service-v2' &&
            (authority.completionEligible ||
                authority.authorityProvenance['runtimeEligible'] == true) &&
            authority.authorityProvenance['secureIsolationActive'] != false;
    final ownerRiskAuthority = authority.qaPreview &&""")
rep(p,'    if (!(productionAuthority || ownerRiskAuthority)) {','    if (!(secureP1aAuthority || ownerRiskAuthority)) {')
rep(p,'    required Future<void> Function() clearOwnerSettings,\n    required String emergencyWatchdogId,','    required Future<void> Function() clearOwnerSettings,\n    P2OwnerModeEnableAuthorizer? authorizeOwnerModeEnable,\n    Future<void> Function()? clearOwnerModeAuthorization,\n    required String emergencyWatchdogId,')
rep(p,"""    final controller = P2OwnerModeController(
      persistOwnerSettings,
      clearOwnerSettings,
    );""","""    final controller = P2OwnerModeController(
      persistOwnerSettings,
      clearOwnerSettings,
      authorizeEnable: authorizeOwnerModeEnable,
      clearAuthorization: clearOwnerModeAuthorization,
    );""")
rep(p,"        'ownerRiskQa': authority.qaPreview,\n      };","        'ownerRiskQa': authority.qaPreview,\n        'secureIsolationActive': authority.authorityProvenance['secureIsolationActive'] == true,\n        'productionCertificationComplete': authority.completionEligible,\n      };")

p='lib/product/p2_product_runtime_bootstrap.dart'
rep(p,"import 'p2_owner_workspace.dart';","import 'p2_owner_mode.dart';\nimport 'p2_owner_workspace.dart';")
rep(p,"""  bool get completionEligible =>
      runtime?.authority.completionEligible == true &&
      runtime?.authority.authorityKind == 'p1-isolated-authority-service-v2';
""","""  bool get completionEligible =>
      runtime?.authority.completionEligible == true &&
      runtime?.authority.authorityKind == 'p1-isolated-authority-service-v2';
  bool get secureIsolationActive =>
      runtime?.authority.authorityKind == 'p1-isolated-authority-service-v2' &&
      (runtime?.authority.authorityProvenance['runtimeEligible'] == true ||
          runtime?.authority.completionEligible == true);
""")
rep(p,"""      final P2RuntimeAuthority authority = ownerRiskQa
          ? P2OwnerRiskQaAuthority()
          : P2IsolatedP1AuthorityAdapter(
              p1AuthorityService!,
              qaPreview: qaPreview,
            );""","""      final P2IsolatedP1AuthorityAdapter? p1Adapter = ownerRiskQa
          ? null
          : P2IsolatedP1AuthorityAdapter(
              p1AuthorityService!,
              qaPreview: qaPreview,
            );
      final P2RuntimeAuthority authority =
          p1Adapter ?? P2OwnerRiskQaAuthority();""")
rep(p,'      final runtime = await P2ProductRuntimeOwnerMode.start(\n        stateDirectory:','      P2ProductRuntimeOwnerMode? activeOwnerRuntime;\n      final runtime = await P2ProductRuntimeOwnerMode.start(\n        stateDirectory:')
rep(p,"            accessProfileId: 'owner',\n            operation: operation,","            accessProfileId:\n                activeOwnerRuntime?.controller.current.accessProfileId ?? 'owner',\n            operation: operation,")
rep(p,"""        clearOwnerSettings: () async {
          final file = File(
            '${authorityDirectory.path}${Platform.pathSeparator}owner-mode.v1.json',
          );
          if (await file.exists()) {
            await file.delete();
          }
        },
        emergencyWatchdogId:""","""        clearOwnerSettings: () async {
          final file = File(
            '${authorityDirectory.path}${Platform.pathSeparator}owner-mode.v1.json',
          );
          if (await file.exists()) {
            await file.delete();
          }
        },
        authorizeOwnerModeEnable: p1Adapter?.authorizeOwnerModeSettings,
        clearOwnerModeAuthorization: p1Adapter?.clearOwnerModeSettings,
        emergencyWatchdogId:""")
rep(p,'      );\n      return P2ProductRuntimeOwnerModeHandle.active(runtime);','      );\n      activeOwnerRuntime = runtime;\n      return P2ProductRuntimeOwnerModeHandle.active(runtime);')
print('P1A_DART_V2_OK')
