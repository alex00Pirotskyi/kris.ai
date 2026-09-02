import 'dart:convert';

import '../crypto_utils.dart';
import '../self_awareness/capability_self_model.dart';

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
enum Recoverability { retryable, operational, configurable, repairable, selfRepairCandidate, terminal }

enum RecoveryLevel { l0Transient, l1Operational, l2Configuration, l3CodeRepair, l4SelfRepair }
enum RecoveryDecisionKind { retry, restart, reconfigure, repair, rollback, requestAuthority, askUser, abort, quarantine, degraded }

enum RecoveryAttemptState { proposed, running, verifying, succeeded, failed, escalated, rolledBack }

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
    this.recoverability = Recoverability.terminal,
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
  const FailureClassification({required this.recoverability, required this.level, required this.reason});
  final Recoverability recoverability;
  final RecoveryLevel level;
  final String reason;
}

final class FailureClassifier {
  const FailureClassifier();

  FailureClassification classify(FailureEvent failure) {
    if (failure.recoverability != Recoverability.terminal) {
      return FailureClassification(
        recoverability: failure.recoverability,
        level: _level(failure.recoverability),
        reason: 'Failure producer supplied an explicit recoverability classification.',
      );
    }
    switch (failure.category) {
      case FailureCategory.transient:
      case FailureCategory.provider:
        return const FailureClassification(
          recoverability: Recoverability.retryable,
          level: RecoveryLevel.l0Transient,
          reason: 'Transient/provider failures may be retried after refreshing state.',
        );
      case FailureCategory.process:
      case FailureCategory.browser:
        return const FailureClassification(
          recoverability: Recoverability.operational,
          level: RecoveryLevel.l1Operational,
          reason: 'The failed resource can be recreated or restarted without source repair.',
        );
      case FailureCategory.configuration:
      case FailureCategory.dependency:
        return const FailureClassification(
          recoverability: Recoverability.configurable,
          level: RecoveryLevel.l2Configuration,
          reason: 'Configuration or dependency state must change before retry.',
        );
      case FailureCategory.project:
      case FailureCategory.execution:
      case FailureCategory.verification:
        return const FailureClassification(
          recoverability: Recoverability.repairable,
          level: RecoveryLevel.l3CodeRepair,
          reason: 'The project requires diagnose/patch/verify work through the task kernel.',
        );
      case FailureCategory.application:
        return const FailureClassification(
          recoverability: Recoverability.selfRepairCandidate,
          level: RecoveryLevel.l4SelfRepair,
          reason: 'Application failure must cross the staged recovery-host boundary.',
        );
      case FailureCategory.permission:
      case FailureCategory.unknown:
        return const FailureClassification(
          recoverability: Recoverability.terminal,
          level: RecoveryLevel.l0Transient,
          reason: 'Automatic repair is not safe until authority or cause is established.',
        );
    }
  }

  RecoveryLevel _level(Recoverability value) => switch (value) {
        Recoverability.retryable => RecoveryLevel.l0Transient,
        Recoverability.operational => RecoveryLevel.l1Operational,
        Recoverability.configurable => RecoveryLevel.l2Configuration,
        Recoverability.repairable => RecoveryLevel.l3CodeRepair,
        Recoverability.selfRepairCandidate => RecoveryLevel.l4SelfRepair,
        Recoverability.terminal => RecoveryLevel.l0Transient,
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
      };
}

final class OperationTransition {
  const OperationTransition({required this.before, required this.after, this.changedFiles = const <String>[], this.resultEvidence = const <String>[]});
  final OperationalCheckpoint before;
  final OperationalCheckpoint after;
  final List<String> changedFiles;
  final List<String> resultEvidence;

  Map<String, Object?> toJson() => <String, Object?>{
        'before': before.toJson(),
        'after': after.toJson(),
        'changedFiles': changedFiles,
        'resultEvidence': resultEvidence,
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

final class RecoveryAttempt {
  RecoveryAttempt({
    String? id,
    DateTime? startedAt,
    required this.failureId,
    required this.decision,
    required this.signature,
    this.state = RecoveryAttemptState.proposed,
    this.evidenceBefore = const <String>[],
    this.evidenceAfter = const <String>[],
    this.finishedAt,
  })  : id = id ?? newId('recovery_attempt'),
        startedAt = startedAt ?? DateTime.now().toUtc();

  final String id;
  final String failureId;
  final RecoveryDecision decision;
  final String signature;
  final DateTime startedAt;
  final RecoveryAttemptState state;
  final List<String> evidenceBefore;
  final List<String> evidenceAfter;
  final DateTime? finishedAt;

  bool get producedNewEvidence =>
      evidenceAfter.toSet().difference(evidenceBefore.toSet()).isNotEmpty;
}

final class RecoveryVerification {
  const RecoveryVerification({required this.passed, required this.check, required this.observed, this.evidenceReferences = const <String>[]});
  final bool passed;
  final String check;
  final String observed;
  final List<String> evidenceReferences;
}

final class RecoveryObjective {
  const RecoveryObjective({
    required this.failure,
    required this.level,
    required this.objective,
    required this.successCondition,
    required this.selfContext,
    this.originalRunId,
    this.originalTaskId,
  });
  final FailureEvent failure;
  final RecoveryLevel level;
  final String objective;
  final String successCondition;
  final SelfModelPlanningContext selfContext;
  final String? originalRunId;
  final String? originalTaskId;
}

abstract interface class FailureJournal {
  Future<void> recordFailure(FailureEvent event);
  Future<void> recordAttempt(RecoveryAttempt attempt);
}

abstract interface class RecoveryEventSink {
  Future<void> emit(String type, Map<String, Object?> payload);
}

abstract interface class RecoveryTaskRouter {
  /// Creates recovery work through the existing Universal Task Kernel. The
  /// implementation must preserve [originalRunId]/[originalTaskId] parentage.
  Future<String> createRecoveryWork(RecoveryObjective objective);
  Future<void> resumeOriginalTask({required String runId, String? taskId});
}

abstract interface class RecoveryActuator {
  Future<List<String>> perform(RecoveryDecision decision, FailureEvent failure);
  Future<void> rollback(RecoveryAttempt attempt);
}

abstract interface class RecoveryVerifier {
  Future<RecoveryVerification> verify(FailureEvent originalFailure);
}

final class RecoveryPolicy {
  const RecoveryPolicy({this.maxAttemptsPerFailure = 4, this.maxSameSignatureAttempts = 1});
  final int maxAttemptsPerFailure;
  final int maxSameSignatureAttempts;

  RecoveryDecision decide({
    required FailureEvent failure,
    required FailureClassification classification,
    required KristinSelfSnapshot self,
    required List<RecoveryAttempt> priorAttempts,
  }) {
    if (priorAttempts.length >= maxAttemptsPerFailure) {
      return RecoveryDecision(
        kind: RecoveryDecisionKind.askUser,
        level: classification.level,
        strategyId: 'bounded_attempts_exhausted',
        reason: 'Automatic recovery attempt budget is exhausted.',
      );
    }
    final signature = '${classification.level.name}:${failure.recurrenceSignature}';
    final repeated = priorAttempts.where((a) => a.signature == signature).length;
    if (repeated >= maxSameSignatureAttempts) {
      final next = _escalate(classification.level);
      if (next == null) {
        return RecoveryDecision(
          kind: RecoveryDecisionKind.askUser,
          level: classification.level,
          strategyId: 'no_material_progress',
          reason: 'The same strategy reproduced the same relevant failure state.',
        );
      }
      return _decisionFor(next, failure, escalated: true);
    }
    return _decisionFor(classification.level, failure);
  }

  RecoveryLevel? _escalate(RecoveryLevel level) => switch (level) {
        RecoveryLevel.l0Transient => RecoveryLevel.l1Operational,
        RecoveryLevel.l1Operational => RecoveryLevel.l2Configuration,
        RecoveryLevel.l2Configuration => RecoveryLevel.l3CodeRepair,
        RecoveryLevel.l3CodeRepair => null,
        RecoveryLevel.l4SelfRepair => null,
      };

  RecoveryDecision _decisionFor(RecoveryLevel level, FailureEvent failure, {bool escalated = false}) {
    final prefix = escalated ? 'Escalated after no material progress. ' : '';
    switch (level) {
      case RecoveryLevel.l0Transient:
        return RecoveryDecision(kind: RecoveryDecisionKind.retry, level: level, strategyId: 'refresh_and_retry', reason: '${prefix}Refresh volatile state and retry once.');
      case RecoveryLevel.l1Operational:
        return RecoveryDecision(kind: RecoveryDecisionKind.restart, level: level, strategyId: 'restart_resource', reason: '${prefix}Recreate or restart the failed disposable/runtime resource.');
      case RecoveryLevel.l2Configuration:
        return RecoveryDecision(kind: RecoveryDecisionKind.reconfigure, level: level, strategyId: 'repair_configuration', reason: '${prefix}Repair the prerequisite/configuration mismatch before retrying.', requiredAuthority: failure.requiredAuthority);
      case RecoveryLevel.l3CodeRepair:
        return RecoveryDecision(kind: RecoveryDecisionKind.repair, level: level, strategyId: 'kernel_code_repair', reason: '${prefix}Route inspect/reproduce/patch/analyze/test/rerun work through the Universal Task Kernel.', requiredCapabilities: const <String>{'agent.fix_project'});
      case RecoveryLevel.l4SelfRepair:
        return RecoveryDecision(kind: RecoveryDecisionKind.quarantine, level: level, strategyId: 'staged_self_repair', reason: '${prefix}Stage a candidate outside the executing primary process; activation requires recovery-host verification and rollback readiness.', requiredAuthority: const <String>{'owner.self_repair'});
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
    this.classifier = const FailureClassifier(),
    this.policy = const RecoveryPolicy(),
  });

  final KristinSelfModelService selfModel;
  final FailureJournal journal;
  final RecoveryEventSink events;
  final RecoveryTaskRouter router;
  final RecoveryActuator actuator;
  final RecoveryVerifier verifier;
  final FailureClassifier classifier;
  final RecoveryPolicy policy;
  final Map<String, List<RecoveryAttempt>> _attempts = <String, List<RecoveryAttempt>>{};

  Future<RecoveryVerification?> handle(FailureEvent failure) async {
    await journal.recordFailure(failure);
    await events.emit('failure_detected', failure.toJson());
    final classification = classifier.classify(failure);
    await events.emit('failure_classified', <String, Object?>{
      'failureId': failure.id,
      'recoverability': classification.recoverability.name,
      'level': classification.level.name,
      'reason': classification.reason,
    });
    final self = await selfModel.snapshot();
    final attempts = _attempts.putIfAbsent(failure.id, () => <RecoveryAttempt>[]);
    final decision = policy.decide(
      failure: failure,
      classification: classification,
      self: self,
      priorAttempts: attempts,
    );
    await events.emit('recovery_strategy_selected', <String, Object?>{
      'failureId': failure.id,
      'kind': decision.kind.name,
      'level': decision.level.name,
      'strategyId': decision.strategyId,
    });

    if (decision.kind == RecoveryDecisionKind.askUser ||
        decision.kind == RecoveryDecisionKind.abort ||
        decision.kind == RecoveryDecisionKind.quarantine) {
      await events.emit('recovery_escalated', <String, Object?>{
        'failureId': failure.id,
        'reason': decision.reason,
        'requiredAuthority': decision.requiredAuthority.toList(),
      });
      return null;
    }

    final signature = '${decision.level.name}:${failure.recurrenceSignature}';
    final attempt = RecoveryAttempt(
      failureId: failure.id,
      decision: decision,
      signature: signature,
      evidenceBefore: failure.evidenceReferences,
    );
    attempts.add(attempt);
    await journal.recordAttempt(attempt);
    await events.emit('recovery_started', <String, Object?>{
      'failureId': failure.id,
      'attemptId': attempt.id,
      'originalRunId': failure.runId,
      'originalTaskId': failure.taskId,
    });

    if (decision.kind == RecoveryDecisionKind.repair) {
      final context = await selfModel.planningContext(
        relevantCapabilityIds: <String>{
          if (failure.capabilityId != null) failure.capabilityId!,
          ...decision.requiredCapabilities,
        },
      );
      await router.createRecoveryWork(RecoveryObjective(
        failure: failure,
        level: decision.level,
        objective: 'Recover from ${failure.subsystem}/${failure.operation}: ${failure.message}',
        successCondition: failure.expectedState == null
            ? 'The original operation succeeds and its original failure signature is absent.'
            : 'Observed state matches: ${failure.expectedState}',
        selfContext: context,
        originalRunId: failure.runId,
        originalTaskId: failure.taskId,
      ));
    } else {
      await actuator.perform(decision, failure);
    }

    final verification = await verifier.verify(failure);
    await events.emit(verification.passed ? 'recovery_verified' : 'recovery_failed', <String, Object?>{
      'failureId': failure.id,
      'attemptId': attempt.id,
      'check': verification.check,
      'observed': verification.observed,
      'evidenceReferences': verification.evidenceReferences,
    });
    if (!verification.passed) return verification;

    if (failure.runId != null) {
      await router.resumeOriginalTask(runId: failure.runId!, taskId: failure.taskId);
      await events.emit('original_task_resumed', <String, Object?>{
        'failureId': failure.id,
        'runId': failure.runId!,
        if (failure.taskId != null) 'taskId': failure.taskId,
      });
    }
    return verification;
  }
}

String recoveryJson(FailureEvent failure) => jsonEncode(failure.toJson());
