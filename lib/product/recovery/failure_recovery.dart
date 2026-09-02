import 'dart:convert';

import '../crypto_utils.dart';
import '../self_awareness/capability_self_model.dart';
import '../self_awareness/operational_self_awareness.dart';

enum FailureSeverity { info, warning, error, critical }

enum FailureCategory {
  transient,
  provider,
  permission,
  configuration,
  dependency,
  process,
  browser,
  project,
  execution,
  verification,
  application,
  unknown,
}

enum Recoverability {
  unspecified,
  retryable,
  operational,
  configurable,
  repairable,
  selfRepairCandidate,
  terminal,
}

enum RecoveryLevel {
  terminal,
  l0Transient,
  l1Operational,
  l2Configuration,
  l3CodeRepair,
  l4SelfRepair,
}

enum RecoveryDecisionKind {
  retry,
  restart,
  reconfigure,
  repair,
  selfRepair,
  rollback,
  requestAuthority,
  askUser,
  abort,
  quarantine,
  degraded,
}

enum RecoveryAttemptState {
  proposed,
  running,
  verifying,
  succeeded,
  failed,
  escalated,
  rolledBack,
}

enum RecoveryExperienceOutcome {
  verified,
  failedVerification,
  actuationFailed,
  blocked,
  rolledBack,
  continuationFailed,
}

final class FailureEvent {
  FailureEvent({
    String? id,
    DateTime? timestamp,
    required this.severity,
    required this.category,
    required this.subsystem,
    required this.operation,
    required this.message,
    this.taskId,
    this.runId,
    this.workItemId,
    this.projectId,
    this.processId,
    this.modelExactId,
    this.errorCode,
    this.stackTrace,
    this.stdoutEvidence = const <String>[],
    this.stderrEvidence = const <String>[],
    this.expectedState,
    this.observedState,
    this.stateBefore = const <String, Object?>{},
    this.stateAfter = const <String, Object?>{},
    this.recentActions = const <Map<String, Object?>>[],
    this.recentChanges = const <Map<String, Object?>>[],
    this.capabilityId,
    this.requiredAuthority = const <String>{},
    this.recoverability = Recoverability.unspecified,
    this.evidenceReferences = const <String>[],
    this.parentFailureId,
    this.rootFailureId,
    String? recurrenceSignature,
  })  : id = id ?? newId('failure'),
        timestamp = timestamp ?? DateTime.now().toUtc(),
        recurrenceSignature = recurrenceSignature ??
            normalizeFailureSignature(
              category: category,
              subsystem: subsystem,
              operation: operation,
              code: errorCode,
              message: message,
            );

  final String id;
  final DateTime timestamp;
  final FailureSeverity severity;
  final FailureCategory category;
  final String subsystem;
  final String operation;
  final String message;
  final String? taskId;
  final String? runId;
  final String? workItemId;
  final String? projectId;
  final String? processId;
  final String? modelExactId;
  final String? errorCode;
  final String? stackTrace;
  final List<String> stdoutEvidence;
  final List<String> stderrEvidence;
  final String? expectedState;
  final String? observedState;
  final Map<String, Object?> stateBefore;
  final Map<String, Object?> stateAfter;
  final List<Map<String, Object?>> recentActions;
  final List<Map<String, Object?>> recentChanges;
  final String? capabilityId;
  final Set<String> requiredAuthority;
  final Recoverability recoverability;
  final List<String> evidenceReferences;
  final String? parentFailureId;
  final String? rootFailureId;
  final String recurrenceSignature;

  bool get retryable => recoverability == Recoverability.retryable;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'severity': severity.name,
        'category': category.name,
        'subsystem': subsystem,
        'operation': operation,
        'message': message,
        if (taskId != null) 'taskId': taskId,
        if (runId != null) 'runId': runId,
        if (workItemId != null) 'workItemId': workItemId,
        if (projectId != null) 'projectId': projectId,
        if (processId != null) 'processId': processId,
        if (modelExactId != null) 'modelExactId': modelExactId,
        if (errorCode != null) 'errorCode': errorCode,
        if (stackTrace != null) 'stackTrace': stackTrace,
        'stdoutEvidence': stdoutEvidence,
        'stderrEvidence': stderrEvidence,
        if (expectedState != null) 'expectedState': expectedState,
        if (observedState != null) 'observedState': observedState,
        'stateBefore': stateBefore,
        'stateAfter': stateAfter,
        'recentActions': recentActions,
        'recentChanges': recentChanges,
        if (capabilityId != null) 'capabilityId': capabilityId,
        'requiredAuthority': requiredAuthority.toList()..sort(),
        'recoverability': recoverability.name,
        'retryable': retryable,
        'evidenceReferences': evidenceReferences,
        if (parentFailureId != null) 'parentFailureId': parentFailureId,
        if (rootFailureId != null) 'rootFailureId': rootFailureId,
        'recurrenceSignature': recurrenceSignature,
      };

  factory FailureEvent.fromJson(Map<String, dynamic> json) => FailureEvent(
        id: json['id']?.toString(),
        timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '')?.toUtc(),
        severity: FailureSeverity.values
                .where((item) => item.name == json['severity']?.toString())
                .firstOrNull ??
            FailureSeverity.error,
        category: FailureCategory.values
                .where((item) => item.name == json['category']?.toString())
                .firstOrNull ??
            FailureCategory.unknown,
        subsystem: json['subsystem']?.toString() ?? 'unknown',
        operation: json['operation']?.toString() ?? 'unknown',
        message: json['message']?.toString() ?? '',
        taskId: json['taskId']?.toString(),
        runId: json['runId']?.toString(),
        workItemId: json['workItemId']?.toString(),
        projectId: json['projectId']?.toString(),
        processId: json['processId']?.toString(),
        modelExactId: json['modelExactId']?.toString(),
        errorCode: json['errorCode']?.toString(),
        stackTrace: json['stackTrace']?.toString(),
        stdoutEvidence: (json['stdoutEvidence'] as List? ?? const <Object>[])
            .map((item) => item.toString())
            .toList(growable: false),
        stderrEvidence: (json['stderrEvidence'] as List? ?? const <Object>[])
            .map((item) => item.toString())
            .toList(growable: false),
        expectedState: json['expectedState']?.toString(),
        observedState: json['observedState']?.toString(),
        stateBefore: json['stateBefore'] is Map
            ? Map<String, Object?>.from(json['stateBefore'] as Map)
            : const <String, Object?>{},
        stateAfter: json['stateAfter'] is Map
            ? Map<String, Object?>.from(json['stateAfter'] as Map)
            : const <String, Object?>{},
        capabilityId: json['capabilityId']?.toString(),
        requiredAuthority:
            (json['requiredAuthority'] as List? ?? const <Object>[])
                .map((item) => item.toString())
                .toSet(),
        recoverability: Recoverability.values
                .where((item) => item.name == json['recoverability']?.toString())
                .firstOrNull ??
            Recoverability.unspecified,
        evidenceReferences:
            (json['evidenceReferences'] as List? ?? const <Object>[])
                .map((item) => item.toString())
                .toList(growable: false),
        parentFailureId: json['parentFailureId']?.toString(),
        rootFailureId: json['rootFailureId']?.toString(),
        recurrenceSignature: json['recurrenceSignature']?.toString(),
      );
}

String normalizeFailureSignature({
  required FailureCategory category,
  required String subsystem,
  required String operation,
  String? code,
  required String message,
}) {
  final normalized = message
      .toLowerCase()
      .replaceAll(RegExp(r'0x[0-9a-f]+'), '<addr>')
      .replaceAll(RegExp(r'\b\d{2,}\b'), '<n>')
      .replaceAll(RegExp(r'[/\\][^\s]+'), '<path>')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return '${category.name}|$subsystem|$operation|${code ?? ''}|$normalized';
}

final class FailureClassification {
  const FailureClassification({
    required this.recoverability,
    required this.level,
    required this.reason,
  });
  final Recoverability recoverability;
  final RecoveryLevel level;
  final String reason;
}

final class FailureClassifier {
  const FailureClassifier();

  FailureClassification classify(FailureEvent failure) {
    if (failure.recoverability != Recoverability.unspecified) {
      return FailureClassification(
        recoverability: failure.recoverability,
        level: _level(failure.recoverability),
        reason:
            'Failure producer supplied an explicit recoverability classification.',
      );
    }
    switch (failure.category) {
      case FailureCategory.transient:
      case FailureCategory.provider:
        return const FailureClassification(
          recoverability: Recoverability.retryable,
          level: RecoveryLevel.l0Transient,
          reason:
              'Transient/provider failures may be retried after refreshing volatile state.',
        );
      case FailureCategory.process:
      case FailureCategory.browser:
        return const FailureClassification(
          recoverability: Recoverability.operational,
          level: RecoveryLevel.l1Operational,
          reason:
              'The failed disposable/runtime resource may be recreated without source repair.',
        );
      case FailureCategory.configuration:
      case FailureCategory.dependency:
        return const FailureClassification(
          recoverability: Recoverability.configurable,
          level: RecoveryLevel.l2Configuration,
          reason:
              'Configuration or dependency state must change before retry.',
        );
      case FailureCategory.project:
      case FailureCategory.execution:
      case FailureCategory.verification:
        return const FailureClassification(
          recoverability: Recoverability.repairable,
          level: RecoveryLevel.l3CodeRepair,
          reason:
              'The project requires diagnose/patch/verify work through the Universal Task Kernel.',
        );
      case FailureCategory.application:
        return const FailureClassification(
          recoverability: Recoverability.selfRepairCandidate,
          level: RecoveryLevel.l4SelfRepair,
          reason:
              'Application failure may only cross the staged recovery-host boundary.',
        );
      case FailureCategory.permission:
        return const FailureClassification(
          recoverability: Recoverability.terminal,
          level: RecoveryLevel.terminal,
          reason:
              'Permission failure cannot be retried until authority is explicitly evaluated.',
        );
      case FailureCategory.unknown:
        return const FailureClassification(
          recoverability: Recoverability.terminal,
          level: RecoveryLevel.terminal,
          reason:
              'Unknown failures are terminal for automatic recovery until cause is established.',
        );
    }
  }

  RecoveryLevel _level(Recoverability value) => switch (value) {
        Recoverability.unspecified => RecoveryLevel.terminal,
        Recoverability.retryable => RecoveryLevel.l0Transient,
        Recoverability.operational => RecoveryLevel.l1Operational,
        Recoverability.configurable => RecoveryLevel.l2Configuration,
        Recoverability.repairable => RecoveryLevel.l3CodeRepair,
        Recoverability.selfRepairCandidate => RecoveryLevel.l4SelfRepair,
        Recoverability.terminal => RecoveryLevel.terminal,
      };
}

final class OperationalCheckpoint {
  OperationalCheckpoint({
    String? id,
    DateTime? capturedAt,
    required this.operation,
    this.runId,
    this.taskId,
    this.projectId,
    this.sourceIdentity = const <String, Object?>{},
    this.processState = const <String, Object?>{},
    this.modelProviderState = const <String, Object?>{},
    this.capabilityState = const <String, Object?>{},
    this.configurationFingerprints = const <String, String>{},
    this.evidenceReferences = const <String>[],
  })  : id = id ?? newId('checkpoint'),
        capturedAt = capturedAt ?? DateTime.now().toUtc();

  final String id;
  final DateTime capturedAt;
  final String operation;
  final String? runId;
  final String? taskId;
  final String? projectId;
  final Map<String, Object?> sourceIdentity;
  final Map<String, Object?> processState;
  final Map<String, Object?> modelProviderState;
  final Map<String, Object?> capabilityState;
  final Map<String, String> configurationFingerprints;
  final List<String> evidenceReferences;

  String get semanticFingerprint => Sha256.text(jsonEncode(<String, Object?>{
        'operation': operation,
        'runId': runId,
        'taskId': taskId,
        'projectId': projectId,
        'sourceIdentity': sourceIdentity,
        'processState': processState,
        'modelProviderState': modelProviderState,
        'capabilityState': capabilityState,
        'configurationFingerprints': configurationFingerprints,
      }));

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'capturedAt': capturedAt.toIso8601String(),
        'operation': operation,
        if (runId != null) 'runId': runId,
        if (taskId != null) 'taskId': taskId,
        if (projectId != null) 'projectId': projectId,
        'sourceIdentity': sourceIdentity,
        'processState': processState,
        'modelProviderState': modelProviderState,
        'capabilityState': capabilityState,
        'configurationFingerprints': configurationFingerprints,
        'evidenceReferences': evidenceReferences,
        'semanticFingerprint': semanticFingerprint,
      };
}

final class OperationTransition {
  const OperationTransition({
    required this.before,
    required this.after,
    this.changedFiles = const <String>[],
    this.resultEvidence = const <String>[],
  });
  final OperationalCheckpoint before;
  final OperationalCheckpoint after;
  final List<String> changedFiles;
  final List<String> resultEvidence;

  bool get materialProgress =>
      before.semanticFingerprint != after.semanticFingerprint ||
      changedFiles.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'before': before.toJson(),
        'after': after.toJson(),
        'changedFiles': changedFiles,
        'resultEvidence': resultEvidence,
        'materialProgress': materialProgress,
      };
}

final class RecoveryDecision {
  const RecoveryDecision({
    required this.kind,
    required this.level,
    required this.strategyId,
    required this.reason,
    this.requiredCapabilities = const <String>{},
    this.requiredAuthority = const <String>{},
    this.destructive = false,
  });
  final RecoveryDecisionKind kind;
  final RecoveryLevel level;
  final String strategyId;
  final String reason;
  final Set<String> requiredCapabilities;
  final Set<String> requiredAuthority;
  final bool destructive;
}

final class RecoveryActionResult {
  const RecoveryActionResult({
    required this.summary,
    this.evidenceReferences = const <String>[],
    this.beforeFingerprint = '',
    this.afterFingerprint = '',
    this.materialProgress = false,
  });
  final String summary;
  final List<String> evidenceReferences;
  final String beforeFingerprint;
  final String afterFingerprint;
  final bool materialProgress;

  Map<String, Object?> toJson() => <String, Object?>{
        'summary': summary,
        'evidenceReferences': evidenceReferences,
        if (beforeFingerprint.isNotEmpty) 'beforeFingerprint': beforeFingerprint,
        if (afterFingerprint.isNotEmpty) 'afterFingerprint': afterFingerprint,
        'materialProgress': materialProgress,
      };
}

final class RecoveryAttempt {
  RecoveryAttempt({
    String? id,
    DateTime? startedAt,
    required this.failureId,
    required this.decision,
    required this.signature,
    this.state = RecoveryAttemptState.proposed,
    this.result,
    this.finishedAt,
  })  : id = id ?? newId('recovery_attempt'),
        startedAt = startedAt ?? DateTime.now().toUtc();

  final String id;
  final String failureId;
  final RecoveryDecision decision;
  final String signature;
  final DateTime startedAt;
  final RecoveryAttemptState state;
  final RecoveryActionResult? result;
  final DateTime? finishedAt;

  bool get producedMaterialProgress => result?.materialProgress == true;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'failureId': failureId,
        'strategyId': decision.strategyId,
        'level': decision.level.name,
        'kind': decision.kind.name,
        'signature': signature,
        'state': state.name,
        'startedAt': startedAt.toIso8601String(),
        if (result != null) 'result': result!.toJson(),
        if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
      };
}

final class RecoveryVerification {
  const RecoveryVerification({
    required this.passed,
    required this.check,
    required this.observed,
    this.evidenceReferences = const <String>[],
    this.materialProgress = false,
    this.rollbackRecommended = false,
  });
  final bool passed;
  final String check;
  final String observed;
  final List<String> evidenceReferences;
  final bool materialProgress;
  final bool rollbackRecommended;
}

final class RecoveryObjective {
  const RecoveryObjective({
    required this.failure,
    required this.level,
    required this.objective,
    required this.successCondition,
    required this.selfContext,
    required this.overlay,
    this.originalRunId,
    this.originalTaskId,
  });
  final FailureEvent failure;
  final RecoveryLevel level;
  final String objective;
  final String successCondition;
  final SelfModelPlanningContext selfContext;
  final SelfModelSessionOverlay overlay;
  final String? originalRunId;
  final String? originalTaskId;
}

final class RecoveryExperience {
  RecoveryExperience({
    String? id,
    DateTime? observedAt,
    required this.failureSignature,
    required this.strategyId,
    required this.level,
    required this.environmentFingerprint,
    required this.outcome,
    required this.producedProgress,
    this.failureId,
    this.attemptId,
    this.verificationCheck,
    this.verificationObserved,
    this.evidenceReferences = const <String>[],
  })  : id = id ?? newId('recovery_experience'),
        observedAt = observedAt ?? DateTime.now().toUtc();

  final String id;
  final DateTime observedAt;
  final String failureSignature;
  final String strategyId;
  final RecoveryLevel level;
  final String environmentFingerprint;
  final RecoveryExperienceOutcome outcome;
  final bool producedProgress;
  final String? failureId;
  final String? attemptId;
  final String? verificationCheck;
  final String? verificationObserved;
  final List<String> evidenceReferences;

  bool get verified => outcome == RecoveryExperienceOutcome.verified;
  bool get ineffective => !verified && !producedProgress;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'observedAt': observedAt.toIso8601String(),
        'failureSignature': failureSignature,
        'strategyId': strategyId,
        'level': level.name,
        'environmentFingerprint': environmentFingerprint,
        'outcome': outcome.name,
        'producedProgress': producedProgress,
        if (failureId != null) 'failureId': failureId,
        if (attemptId != null) 'attemptId': attemptId,
        if (verificationCheck != null) 'verificationCheck': verificationCheck,
        if (verificationObserved != null)
          'verificationObserved': verificationObserved,
        'evidenceReferences': evidenceReferences,
      };

  factory RecoveryExperience.fromJson(Map<String, dynamic> json) =>
      RecoveryExperience(
        id: json['id']?.toString(),
        observedAt:
            DateTime.tryParse(json['observedAt']?.toString() ?? '')?.toUtc(),
        failureSignature: json['failureSignature']?.toString() ?? '',
        strategyId: json['strategyId']?.toString() ?? '',
        level: RecoveryLevel.values
                .where((item) => item.name == json['level']?.toString())
                .firstOrNull ??
            RecoveryLevel.terminal,
        environmentFingerprint:
            json['environmentFingerprint']?.toString() ?? '',
        outcome: RecoveryExperienceOutcome.values
                .where((item) => item.name == json['outcome']?.toString())
                .firstOrNull ??
            RecoveryExperienceOutcome.blocked,
        producedProgress: json['producedProgress'] == true,
        failureId: json['failureId']?.toString(),
        attemptId: json['attemptId']?.toString(),
        verificationCheck: json['verificationCheck']?.toString(),
        verificationObserved: json['verificationObserved']?.toString(),
        evidenceReferences:
            (json['evidenceReferences'] as List? ?? const <Object>[])
                .map((item) => item.toString())
                .toList(growable: false),
      );
}

abstract interface class RecoveryExperienceStore {
  Future<void> record(RecoveryExperience experience);
  Future<List<RecoveryExperience>> find({
    required String failureSignature,
    String? environmentFingerprint,
  });
}

final class InMemoryRecoveryExperienceStore implements RecoveryExperienceStore {
  InMemoryRecoveryExperienceStore({this.maxRetained = 256});
  final int maxRetained;
  final List<RecoveryExperience> _items = <RecoveryExperience>[];

  @override
  Future<void> record(RecoveryExperience experience) async {
    _items.add(experience);
    if (_items.length > maxRetained) {
      _items.removeRange(0, _items.length - maxRetained);
    }
  }

  @override
  Future<List<RecoveryExperience>> find({
    required String failureSignature,
    String? environmentFingerprint,
  }) async =>
      List<RecoveryExperience>.unmodifiable(_items.where((item) {
        if (item.failureSignature != failureSignature) return false;
        return environmentFingerprint == null ||
            item.environmentFingerprint == environmentFingerprint;
      }));
}

String recoveryEnvironmentFingerprint(KristinSelfSnapshot self) {
  final app = self.application;
  return Sha256.text(jsonEncode(<String, Object?>{
    'platform': app.platform,
    'selectedProject': app.selectedProject?['id'],
    'selectedModel': app.selectedModel?['exactId'],
    'selectedModelDiscovered': app.selectedModel?['discovered'],
    'browser': <String, Object?>{
      'available': app.browser['available'],
      'statusCode': app.browser['statusCode'],
    },
    'ownerMode': <String, Object?>{
      'available': app.ownerMode['available'],
      'completionEligible': app.ownerMode['completionEligible'],
      'secureIsolationActive': app.ownerMode['secureIsolationActive'],
    },
    'providers': app.providers
        .map((item) => '${item['id']}:${item['status']}')
        .toList()
      ..sort(),
  }));
}

final class RecoveryAuthorityEvaluation {
  const RecoveryAuthorityEvaluation({
    required this.allowed,
    required this.reason,
    this.granted = const <String>{},
    this.missing = const <String>{},
    this.notEvaluated = const <String>{},
  });
  final bool allowed;
  final String reason;
  final Set<String> granted;
  final Set<String> missing;
  final Set<String> notEvaluated;
}

abstract interface class FailureJournal {
  Future<void> recordFailure(FailureEvent event);
  Future<void> recordAttempt(RecoveryAttempt attempt);
}

abstract interface class RecoveryEventSink {
  Future<void> emit(String type, Map<String, Object?> payload);
}

abstract interface class FailureSelfContextResolver {
  Future<SelfModelSessionOverlay> resolve(FailureEvent failure);
}

final class RuntimeOnlyFailureSelfContextResolver
    implements FailureSelfContextResolver {
  const RuntimeOnlyFailureSelfContextResolver();
  @override
  Future<SelfModelSessionOverlay> resolve(FailureEvent failure) async =>
      const SelfModelSessionOverlay();
}

abstract interface class RecoveryAuthorityGate {
  Future<RecoveryAuthorityEvaluation> evaluate(
    FailureEvent failure,
    RecoveryDecision decision,
  );
}

final class FailClosedRecoveryAuthorityGate implements RecoveryAuthorityGate {
  const FailClosedRecoveryAuthorityGate();
  @override
  Future<RecoveryAuthorityEvaluation> evaluate(
    FailureEvent failure,
    RecoveryDecision decision,
  ) async {
    if (decision.requiredAuthority.isEmpty) {
      return const RecoveryAuthorityEvaluation(
        allowed: true,
        reason: 'No additional authority is required by this strategy.',
      );
    }
    return RecoveryAuthorityEvaluation(
      allowed: false,
      reason: 'Required recovery authority has not been evaluated.',
      notEvaluated: decision.requiredAuthority,
    );
  }
}

abstract interface class RecoveryTaskRouter {
  /// This future must represent terminal recovery work, not merely creation of
  /// a queued task. Verification starts only after this future resolves.
  Future<RecoveryActionResult> runRecoveryWork(RecoveryObjective objective);
  Future<RecoveryActionResult> continueOriginalTask(FailureEvent failure);
}

abstract interface class RecoveryActuator {
  Future<RecoveryActionResult> perform(
    RecoveryDecision decision,
    FailureEvent failure,
  );
  Future<RecoveryActionResult> rollback(
    RecoveryDecision decision,
    FailureEvent failure,
    RecoveryActionResult action,
  );
}

abstract interface class RecoveryVerifier {
  Future<RecoveryVerification> verify(
    FailureEvent originalFailure,
    RecoveryActionResult action,
  );
}

abstract interface class RecoverySelfRepairCoordinator {
  Future<RecoveryActionResult> perform(
    RecoveryDecision decision,
    FailureEvent failure,
  );
}

final class RecoveryPolicy {
  const RecoveryPolicy({
    this.maxAttemptsPerFailureSignature = 4,
    this.maxSameStrategyAttempts = 1,
  });
  final int maxAttemptsPerFailureSignature;
  final int maxSameStrategyAttempts;

  RecoveryDecision decide({
    required FailureEvent failure,
    required FailureClassification classification,
    required KristinSelfSnapshot self,
    required List<RecoveryAttempt> priorAttempts,
    List<RecoveryExperience> priorExperiences = const <RecoveryExperience>[],
    String environmentFingerprint = '',
  }) {
    if (classification.recoverability == Recoverability.terminal ||
        classification.level == RecoveryLevel.terminal) {
      if (failure.requiredAuthority.isNotEmpty) {
        return RecoveryDecision(
          kind: RecoveryDecisionKind.requestAuthority,
          level: RecoveryLevel.terminal,
          strategyId: 'authority_required',
          reason:
              'Automatic recovery is stopped until required authority is explicitly evaluated.',
          requiredAuthority: failure.requiredAuthority,
        );
      }
      return RecoveryDecision(
        kind: RecoveryDecisionKind.askUser,
        level: RecoveryLevel.terminal,
        strategyId: failure.category == FailureCategory.permission
            ? 'permission_requirement_unknown'
            : 'terminal_unknown_cause',
        reason: failure.category == FailureCategory.permission
            ? 'A permission failure occurred, but the exact required authority was not captured; automatic retry is forbidden.'
            : 'Automatic recovery is unsafe until the terminal/unknown cause is established.',
      );
    }

    if (priorAttempts.length >= maxAttemptsPerFailureSignature) {
      return RecoveryDecision(
        kind: RecoveryDecisionKind.askUser,
        level: classification.level,
        strategyId: 'bounded_attempts_exhausted',
        reason: 'Automatic recovery attempt budget is exhausted.',
      );
    }

    for (final candidate in _strategyLadder(classification.level, failure)) {
      final repeated = priorAttempts
          .where((attempt) => attempt.decision.strategyId == candidate.strategyId)
          .length;
      final learnedIneffective = priorExperiences.any((experience) {
        return experience.failureSignature == failure.recurrenceSignature &&
            experience.strategyId == candidate.strategyId &&
            (environmentFingerprint.isEmpty ||
                experience.environmentFingerprint == environmentFingerprint) &&
            experience.ineffective;
      });
      if (repeated >= maxSameStrategyAttempts || learnedIneffective) continue;
      return candidate;
    }

    return RecoveryDecision(
      kind: RecoveryDecisionKind.askUser,
      level: classification.level,
      strategyId: 'no_untried_safe_strategy',
      reason:
          'Every bounded safe recovery strategy for this signature/environment has already failed without material progress.',
    );
  }

  List<RecoveryDecision> _strategyLadder(
    RecoveryLevel level,
    FailureEvent failure,
  ) {
    if (level == RecoveryLevel.l4SelfRepair) {
      return const <RecoveryDecision>[
        RecoveryDecision(
          kind: RecoveryDecisionKind.selfRepair,
          level: RecoveryLevel.l4SelfRepair,
          strategyId: 'staged_self_repair',
          reason:
              'Use the independent recovery host to stage, qualify, activate, verify and roll back a candidate.',
          requiredCapabilities: <String>{'owner.recovery.actuate'},
          requiredAuthority: <String>{'owner', 'owner.self_repair'},
          destructive: true,
        ),
      ];
    }
    const levels = <RecoveryLevel>[
      RecoveryLevel.l0Transient,
      RecoveryLevel.l1Operational,
      RecoveryLevel.l2Configuration,
      RecoveryLevel.l3CodeRepair,
    ];
    final start = levels.indexOf(level);
    if (start < 0) return const <RecoveryDecision>[];
    return <RecoveryDecision>[
      for (var index = start; index < levels.length; index++)
        _decisionFor(levels[index], failure, escalated: index > start),
    ];
  }

  RecoveryDecision _decisionFor(
    RecoveryLevel level,
    FailureEvent failure, {
    bool escalated = false,
  }) {
    final prefix = escalated ? 'Escalated after no material progress. ' : '';
    switch (level) {
      case RecoveryLevel.l0Transient:
        return RecoveryDecision(
          kind: RecoveryDecisionKind.retry,
          level: level,
          strategyId: 'refresh_and_retry',
          reason: '${prefix}Refresh volatile state and retry once.',
          requiredAuthority: failure.requiredAuthority,
        );
      case RecoveryLevel.l1Operational:
        return RecoveryDecision(
          kind: RecoveryDecisionKind.restart,
          level: level,
          strategyId: 'restart_resource',
          reason:
              '${prefix}Recreate or restart the failed disposable/runtime resource.',
          requiredAuthority: failure.requiredAuthority,
        );
      case RecoveryLevel.l2Configuration:
        return RecoveryDecision(
          kind: RecoveryDecisionKind.reconfigure,
          level: level,
          strategyId: 'repair_configuration',
          reason:
              '${prefix}Repair a known-safe prerequisite/configuration mismatch before retrying.',
          requiredAuthority: failure.requiredAuthority,
        );
      case RecoveryLevel.l3CodeRepair:
        return RecoveryDecision(
          kind: RecoveryDecisionKind.repair,
          level: level,
          strategyId: 'kernel_code_repair',
          reason:
              '${prefix}Route diagnose/patch/analyze/test/rerun work through the Universal Task Kernel.',
          requiredCapabilities: const <String>{'agent.fix_project'},
        );
      case RecoveryLevel.l4SelfRepair:
      case RecoveryLevel.terminal:
        throw StateError('recovery_strategy_level_invalid:${level.name}');
    }
  }
}

final class FailureSupervisor {
  FailureSupervisor({
    required this.selfModel,
    required this.journal,
    required this.events,
    required this.router,
    required this.actuator,
    required this.verifier,
    required this.authority,
    this.selfRepair,
    this.selfContext = const RuntimeOnlyFailureSelfContextResolver(),
    RecoveryExperienceStore? experiences,
    this.causalGraph,
    this.classifier = const FailureClassifier(),
    this.policy = const RecoveryPolicy(),
  }) : experiences = experiences ?? InMemoryRecoveryExperienceStore();

  final KristinSelfModelService selfModel;
  final FailureJournal journal;
  final RecoveryEventSink events;
  final RecoveryTaskRouter router;
  final RecoveryActuator actuator;
  final RecoveryVerifier verifier;
  final RecoveryAuthorityGate authority;
  final RecoverySelfRepairCoordinator? selfRepair;
  final FailureSelfContextResolver selfContext;
  final RecoveryExperienceStore experiences;
  final CausalStateGraph? causalGraph;
  final FailureClassifier classifier;
  final RecoveryPolicy policy;
  final Map<String, List<RecoveryAttempt>> _attemptsBySignature =
      <String, List<RecoveryAttempt>>{};

  Future<RecoveryVerification?> handle(FailureEvent failure) async {
    final failureNode = causalGraph?.recordFailure(
      '${failure.subsystem}.${failure.operation}',
      attributes: failure.toJson(),
      evidenceReferences: failure.evidenceReferences,
      confidence: ObservationConfidence.medium,
    );
    await journal.recordFailure(failure);
    await events.emit('failure_detected', failure.toJson());

    final classification = classifier.classify(failure);
    await events.emit('failure_classified', <String, Object?>{
      'failureId': failure.id,
      'recoverability': classification.recoverability.name,
      'level': classification.level.name,
      'reason': classification.reason,
    });

    final overlay = await selfContext.resolve(failure);
    final self = await selfModel.snapshot(
      forceRefresh: true,
      source: 'failure_supervisor',
      reason: 'recovery_decision',
      overlay: overlay,
    );
    final environmentFingerprint = recoveryEnvironmentFingerprint(self);
    final learned = await experiences.find(
      failureSignature: failure.recurrenceSignature,
      environmentFingerprint: environmentFingerprint,
    );
    final attempts = _attemptsBySignature.putIfAbsent(
      failure.rootFailureId ?? failure.recurrenceSignature,
      () => <RecoveryAttempt>[],
    );
    final decision = policy.decide(
      failure: failure,
      classification: classification,
      self: self,
      priorAttempts: attempts,
      priorExperiences: learned,
      environmentFingerprint: environmentFingerprint,
    );
    await events.emit('recovery_strategy_selected', <String, Object?>{
      'failureId': failure.id,
      'kind': decision.kind.name,
      'level': decision.level.name,
      'strategyId': decision.strategyId,
      'environmentFingerprint': environmentFingerprint,
      'priorExperiences': learned.length,
    });

    if (const <RecoveryDecisionKind>{
      RecoveryDecisionKind.askUser,
      RecoveryDecisionKind.abort,
      RecoveryDecisionKind.quarantine,
      RecoveryDecisionKind.requestAuthority,
    }.contains(decision.kind)) {
      await _recordBlocked(
        failure,
        decision,
        environmentFingerprint,
        reason: decision.reason,
      );
      return null;
    }

    final preflight = await _preflightDecision(
      decision,
      self,
      overlay,
      failure,
      environmentFingerprint,
    );
    if (preflight != null) return preflight;

    final attempt = RecoveryAttempt(
      failureId: failure.id,
      decision: decision,
      signature: '${decision.level.name}:${failure.recurrenceSignature}',
      state: RecoveryAttemptState.running,
    );
    attempts.add(attempt);
    await journal.recordAttempt(attempt);
    await events.emit('recovery_started', <String, Object?>{
      'failureId': failure.id,
      'attemptId': attempt.id,
      'strategyId': decision.strategyId,
      'originalRunId': failure.runId,
      'originalTaskId': failure.taskId,
    });

    RecoveryActionResult action;
    try {
      if (decision.kind == RecoveryDecisionKind.repair) {
        final context = await selfModel.planningContext(
          relevantCapabilityIds: <String>{
            if (failure.capabilityId != null) failure.capabilityId!,
            ...decision.requiredCapabilities,
          },
          overlay: overlay,
        );
        action = await router.runRecoveryWork(
          RecoveryObjective(
            failure: failure,
            level: decision.level,
            objective:
                'Recover from ${failure.subsystem}/${failure.operation}: ${failure.message}',
            successCondition: failure.expectedState == null
                ? 'The original operation succeeds and its original failure signature is absent.'
                : 'Observed state matches: ${failure.expectedState}',
            selfContext: context,
            overlay: overlay,
            originalRunId: failure.runId,
            originalTaskId: failure.taskId,
          ),
        );
      } else if (decision.kind == RecoveryDecisionKind.selfRepair) {
        final coordinator = selfRepair;
        if (coordinator == null) {
          await _recordBlocked(
            failure,
            decision,
            environmentFingerprint,
            reason:
                'No governed staged self-repair coordinator is installed in the independent recovery boundary.',
          );
          return const RecoveryVerification(
            passed: false,
            check: 'self_repair_boundary',
            observed: 'Staged self-repair boundary is unavailable.',
          );
        }
        action = await coordinator.perform(decision, failure);
      } else {
        action = await actuator.perform(decision, failure);
      }
    } catch (error) {
      final failed = RecoveryAttempt(
        id: attempt.id,
        startedAt: attempt.startedAt,
        failureId: attempt.failureId,
        decision: attempt.decision,
        signature: attempt.signature,
        state: RecoveryAttemptState.failed,
        finishedAt: DateTime.now().toUtc(),
      );
      attempts[attempts.indexOf(attempt)] = failed;
      await journal.recordAttempt(failed);
      await experiences.record(RecoveryExperience(
        failureSignature: failure.recurrenceSignature,
        strategyId: decision.strategyId,
        level: decision.level,
        environmentFingerprint: environmentFingerprint,
        outcome: RecoveryExperienceOutcome.actuationFailed,
        producedProgress: false,
        failureId: failure.id,
        attemptId: attempt.id,
        evidenceReferences: failure.evidenceReferences,
      ));
      causalGraph?.recordFailure(
        'recovery.${decision.strategyId}.failed',
        causedBy:
            failureNode == null ? const <String>[] : <String>[failureNode.id],
        attributes: <String, Object?>{
          'failureId': failure.id,
          'attemptId': attempt.id,
          'error': '$error',
        },
      );
      await events.emit('recovery_actuation_failed', <String, Object?>{
        'failureId': failure.id,
        'attemptId': attempt.id,
        'strategyId': decision.strategyId,
        'error': '$error',
      });
      return RecoveryVerification(
        passed: false,
        check: 'recovery_actuation',
        observed: 'Recovery actuation failed: $error',
      );
    }

    final verifying = RecoveryAttempt(
      id: attempt.id,
      startedAt: attempt.startedAt,
      failureId: attempt.failureId,
      decision: attempt.decision,
      signature: attempt.signature,
      state: RecoveryAttemptState.verifying,
      result: action,
    );
    attempts[attempts.indexOf(attempt)] = verifying;
    await journal.recordAttempt(verifying);

    final verification = await verifier.verify(failure, action);
    var completed = RecoveryAttempt(
      id: attempt.id,
      startedAt: attempt.startedAt,
      failureId: attempt.failureId,
      decision: attempt.decision,
      signature: attempt.signature,
      state: verification.passed
          ? RecoveryAttemptState.succeeded
          : RecoveryAttemptState.failed,
      result: RecoveryActionResult(
        summary: action.summary,
        evidenceReferences: <String>[
          ...action.evidenceReferences,
          ...verification.evidenceReferences,
        ],
        beforeFingerprint: action.beforeFingerprint,
        afterFingerprint: action.afterFingerprint,
        materialProgress:
            action.materialProgress || verification.materialProgress,
      ),
      finishedAt: DateTime.now().toUtc(),
    );
    attempts[attempts.indexOf(verifying)] = completed;
    await journal.recordAttempt(completed);

    if (!verification.passed &&
        verification.rollbackRecommended &&
        decision.kind != RecoveryDecisionKind.repair &&
        decision.kind != RecoveryDecisionKind.selfRepair) {
      try {
        final rolledBack = await actuator.rollback(decision, failure, action);
        completed = RecoveryAttempt(
          id: completed.id,
          startedAt: completed.startedAt,
          failureId: completed.failureId,
          decision: completed.decision,
          signature: completed.signature,
          state: RecoveryAttemptState.rolledBack,
          result: rolledBack,
          finishedAt: DateTime.now().toUtc(),
        );
        final index = attempts.indexWhere((item) => item.id == completed.id);
        if (index >= 0) attempts[index] = completed;
        await journal.recordAttempt(completed);
        await events.emit('recovery_rolled_back', <String, Object?>{
          'failureId': failure.id,
          'attemptId': completed.id,
          ...rolledBack.toJson(),
        });
      } catch (rollbackError) {
        await events.emit('recovery_rollback_failed', <String, Object?>{
          'failureId': failure.id,
          'attemptId': completed.id,
          'error': '$rollbackError',
        });
      }
    }

    final producedProgress =
        completed.result?.materialProgress == true || verification.passed;
    await experiences.record(RecoveryExperience(
      failureSignature: failure.recurrenceSignature,
      strategyId: decision.strategyId,
      level: decision.level,
      environmentFingerprint: environmentFingerprint,
      outcome: verification.passed
          ? RecoveryExperienceOutcome.verified
          : completed.state == RecoveryAttemptState.rolledBack
              ? RecoveryExperienceOutcome.rolledBack
              : RecoveryExperienceOutcome.failedVerification,
      producedProgress: producedProgress,
      failureId: failure.id,
      attemptId: attempt.id,
      verificationCheck: verification.check,
      verificationObserved: verification.observed,
      evidenceReferences:
          completed.result?.evidenceReferences ?? verification.evidenceReferences,
    ));

    await events.emit(
      verification.passed ? 'recovery_verified' : 'recovery_failed',
      <String, Object?>{
        'failureId': failure.id,
        'attemptId': attempt.id,
        'check': verification.check,
        'observed': verification.observed,
        'materialProgress': producedProgress,
        'evidenceReferences': verification.evidenceReferences,
      },
    );
    if (!verification.passed) return verification;

    causalGraph?.recordRecovery(
      'recovery.${decision.strategyId}.verified',
      recovers: failureNode == null ? const <String>[] : <String>[failureNode.id],
      attributes: <String, Object?>{
        'failureId': failure.id,
        'attemptId': attempt.id,
        'verification': verification.check,
      },
    );

    if (failure.runId != null) {
      try {
        final continuation = await router.continueOriginalTask(failure);
        await events.emit('original_task_resumed', <String, Object?>{
          'failureId': failure.id,
          'runId': failure.runId!,
          if (failure.taskId != null) 'taskId': failure.taskId,
          ...continuation.toJson(),
        });
      } catch (error) {
        await experiences.record(RecoveryExperience(
          failureSignature: failure.recurrenceSignature,
          strategyId: '${decision.strategyId}.continuation',
          level: decision.level,
          environmentFingerprint: environmentFingerprint,
          outcome: RecoveryExperienceOutcome.continuationFailed,
          producedProgress: true,
          failureId: failure.id,
          attemptId: attempt.id,
          verificationCheck: verification.check,
          verificationObserved:
              'Recovery verified but continuation failed: $error',
          evidenceReferences: verification.evidenceReferences,
        ));
        await events.emit('original_task_resume_failed', <String, Object?>{
          'failureId': failure.id,
          'runId': failure.runId!,
          'error': '$error',
        });
        return RecoveryVerification(
          passed: false,
          check: 'original_task_continuity',
          observed:
              'Recovery verified, but the original task could not continue: $error',
          evidenceReferences: verification.evidenceReferences,
          materialProgress: true,
        );
      }
    }
    return verification;
  }

  Future<RecoveryVerification?> _preflightDecision(
    RecoveryDecision decision,
    KristinSelfSnapshot self,
    SelfModelSessionOverlay overlay,
    FailureEvent failure,
    String environmentFingerprint,
  ) async {
    final blockedCapabilities = <String, Map<String, Object?>>{};
    final query = SelfAwarenessQueryService(selfModel);
    for (final capabilityId in decision.requiredCapabilities) {
      final capability = self.capability(capabilityId);
      if (_facilityReadyForAuthorityCheck(capability)) continue;
      final requirements = await query.requirementsFor(
        capabilityId,
        overlay: overlay,
      );
      blockedCapabilities[capabilityId] = requirements.toJson();
    }

    final authorityDecision = await authority.evaluate(failure, decision);
    if (blockedCapabilities.isEmpty && authorityDecision.allowed) return null;

    final reason = blockedCapabilities.isNotEmpty
        ? 'Recovery capability facilities or prerequisites are not currently ready.'
        : authorityDecision.reason;
    await events.emit('recovery_preflight_blocked', <String, Object?>{
      'failureId': failure.id,
      'strategyId': decision.strategyId,
      'reason': reason,
      'blockedCapabilities': blockedCapabilities,
      'missingAuthority': authorityDecision.missing.toList()..sort(),
      'authorityNotEvaluated': authorityDecision.notEvaluated.toList()..sort(),
    });
    await experiences.record(RecoveryExperience(
      failureSignature: failure.recurrenceSignature,
      strategyId: decision.strategyId,
      level: decision.level,
      environmentFingerprint: environmentFingerprint,
      outcome: RecoveryExperienceOutcome.blocked,
      producedProgress: false,
      failureId: failure.id,
      evidenceReferences: failure.evidenceReferences,
    ));
    return RecoveryVerification(
      passed: false,
      check: 'recovery_preflight',
      observed: reason,
      evidenceReferences: failure.evidenceReferences,
    );
  }

  bool _facilityReadyForAuthorityCheck(KnownCapability? capability) {
    if (capability == null) return false;
    if (capability.operationallyUsable) return true;
    if (capability.availability.missingPrerequisites.isNotEmpty) return false;
    if (capability.health?.state == CapabilityHealthState.failing) return false;
    final authorityOnlyBlock = capability.availability.knownButAuthorityBlocked ||
        (capability.availability.requiredAuthority.isNotEmpty &&
            capability.availability.authorityObservation ==
                AuthorityObservationState.notEvaluated);
    return authorityOnlyBlock;
  }

  Future<void> _recordBlocked(
    FailureEvent failure,
    RecoveryDecision decision,
    String environmentFingerprint, {
    required String reason,
  }) async {
    await events.emit('recovery_escalated', <String, Object?>{
      'failureId': failure.id,
      'reason': reason,
      'kind': decision.kind.name,
      'requiredAuthority': decision.requiredAuthority.toList()..sort(),
    });
    await experiences.record(RecoveryExperience(
      failureSignature: failure.recurrenceSignature,
      strategyId: decision.strategyId,
      level: decision.level,
      environmentFingerprint: environmentFingerprint,
      outcome: RecoveryExperienceOutcome.blocked,
      producedProgress: false,
      failureId: failure.id,
      evidenceReferences: failure.evidenceReferences,
    ));
  }
}

String recoveryJson(FailureEvent failure) => jsonEncode(failure.toJson());
