import 'dart:math';

import 'crypto_utils.dart';
import 'domain.dart';
import 'durable_workflow.dart';

enum AgentModelRole {
  router,
  spec,
  planner,
  executor,
  verifier,
  summarizer,
  research,
  safetyReviewer,
}

enum ModelDataBoundary { local, privateRemote, publicCloud }

enum ModelCircuitState { closed, open, halfOpen }

enum ConvergenceAction {
  continueExecution,
  compactAndRetry,
  requireDifferentAction,
  routeToVerifier,
  splitTask,
  askUser,
  offerStrongerModel,
  failConvergence,
}

enum ConvergenceProgressClass {
  positiveProgress,
  neutral,
  regression,
  oscillation,
  unknown,
}

class ModelRouteCandidate {
  const ModelRouteCandidate({
    required this.provider,
    required this.model,
    required this.roles,
    required this.dataBoundary,
    required this.contextTokens,
    required this.reliabilityScore,
    this.healthy = true,
    this.estimatedLatencyMs = 0,
    this.estimatedCostUsd = 0,
    this.circuit = ModelCircuitState.closed,
  });

  final String provider;
  final String model;
  final Set<AgentModelRole> roles;
  final ModelDataBoundary dataBoundary;
  final int contextTokens;
  final double reliabilityScore;
  final bool healthy;
  final int estimatedLatencyMs;
  final double estimatedCostUsd;
  final ModelCircuitState circuit;

  String get identity => '$provider/$model';
}

class ModelRoutePolicy {
  const ModelRoutePolicy({
    required this.localOnly,
    required this.approvedProviders,
    required this.approvedModels,
    required this.fallbackApproved,
    this.maximumDataBoundary = ModelDataBoundary.local,
  });

  final bool localOnly;
  final Set<String> approvedProviders;
  final Set<String> approvedModels;
  final bool fallbackApproved;
  final ModelDataBoundary maximumDataBoundary;
}

class ModelRouteRequest {
  const ModelRouteRequest({
    required this.role,
    required this.requiredContextTokens,
    required this.dataBoundary,
    this.complexity = 1,
    this.maxLatencyMs,
    this.maxEstimatedCostUsd,
    this.allowFallback = false,
  });

  final AgentModelRole role;
  final int requiredContextTokens;
  final ModelDataBoundary dataBoundary;
  final int complexity;
  final int? maxLatencyMs;
  final double? maxEstimatedCostUsd;
  final bool allowFallback;
}

class ModelRouteDecision {
  const ModelRouteDecision({
    required this.selected,
    required this.rejected,
    required this.approvalRequired,
    required this.decisionHash,
  });

  final ModelRouteCandidate? selected;
  final Map<String, List<String>> rejected;
  final bool approvalRequired;
  final String decisionHash;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'selected': selected == null
            ? null
            : <String, dynamic>{
                'provider': selected!.provider,
                'model': selected!.model,
                'identity': selected!.identity,
              },
        'rejected': rejected,
        'approvalRequired': approvalRequired,
        'decisionHash': decisionHash,
      };
}

class RoleBasedModelRouter {
  const RoleBasedModelRouter();

  ModelRouteDecision route({
    required ModelRouteRequest request,
    required ModelRoutePolicy policy,
    required Iterable<ModelRouteCandidate> candidates,
  }) {
    final rejected = <String, List<String>>{};
    final eligible = <ModelRouteCandidate>[];
    for (final candidate in candidates) {
      final reasons = <String>[];
      if (!candidate.healthy) reasons.add('model_unhealthy');
      if (candidate.circuit == ModelCircuitState.open) {
        reasons.add('circuit_open');
      }
      if (!candidate.roles.contains(request.role)) {
        reasons.add('role_unsupported');
      }
      if (candidate.contextTokens < request.requiredContextTokens) {
        reasons.add('context_insufficient');
      }
      if (!policy.approvedProviders.contains(candidate.provider)) {
        reasons.add('provider_not_approved');
      }
      if (!policy.approvedModels.contains(candidate.identity)) {
        reasons.add('model_not_approved');
      }
      if (policy.localOnly &&
          candidate.dataBoundary != ModelDataBoundary.local) {
        reasons.add('local_only_policy');
      }
      if (candidate.dataBoundary.index > policy.maximumDataBoundary.index ||
          candidate.dataBoundary.index > request.dataBoundary.index) {
        reasons.add('data_boundary_exceeded');
      }
      if (request.maxLatencyMs != null &&
          candidate.estimatedLatencyMs > request.maxLatencyMs!) {
        reasons.add('latency_budget_exceeded');
      }
      if (request.maxEstimatedCostUsd != null &&
          candidate.estimatedCostUsd > request.maxEstimatedCostUsd!) {
        reasons.add('cost_budget_exceeded');
      }
      if (reasons.isEmpty) {
        eligible.add(candidate);
      } else {
        rejected[candidate.identity] = reasons;
      }
    }
    eligible.sort((left, right) {
      final reliability = right.reliabilityScore.compareTo(
        left.reliabilityScore,
      );
      if (reliability != 0) return reliability;
      final latency = left.estimatedLatencyMs.compareTo(
        right.estimatedLatencyMs,
      );
      if (latency != 0) return latency;
      final cost = left.estimatedCostUsd.compareTo(right.estimatedCostUsd);
      if (cost != 0) return cost;
      return left.identity.compareTo(right.identity);
    });
    final selected = eligible.firstOrNull;
    final approvalRequired =
        selected == null && request.allowFallback && !policy.fallbackApproved;
    final payload = <String, dynamic>{
      'request': <String, dynamic>{
        'role': request.role.name,
        'requiredContextTokens': request.requiredContextTokens,
        'dataBoundary': request.dataBoundary.name,
      },
      'selected': selected?.identity,
      'rejected': rejected,
      'approvalRequired': approvalRequired,
    };
    return ModelRouteDecision(
      selected: selected,
      rejected: rejected,
      approvalRequired: approvalRequired,
      decisionHash: Sha256.text(canonicalJson(payload)),
    );
  }
}

class SemanticProgressSnapshot {
  const SemanticProgressSnapshot({
    this.artifacts = const <String, String>{},
    this.evidenceIds = const <String>{},
    this.errorCodes = const <String>{},
    this.satisfiedCriteria = const <String>{},
    this.externalState = const <String>{},
    this.planHash,
    this.actionHash,
    this.resultHash,
  });

  final Map<String, String> artifacts;
  final Set<String> evidenceIds;
  final Set<String> errorCodes;
  final Set<String> satisfiedCriteria;
  final Set<String> externalState;
  final String? planHash;
  final String? actionHash;
  final String? resultHash;

  String get hash => Sha256.text(
        canonicalJson(<String, dynamic>{
          'artifacts': artifacts,
          'evidenceIds': evidenceIds.toList()..sort(),
          'errorCodes': errorCodes.toList()..sort(),
          'satisfiedCriteria': satisfiedCriteria.toList()..sort(),
          'externalState': externalState.toList()..sort(),
          'planHash': planHash,
          'actionHash': actionHash,
          'resultHash': resultHash,
        }),
      );
}

class SemanticProgressDelta {
  const SemanticProgressDelta({
    required this.newArtifacts,
    required this.changedArtifactHashes,
    required this.newEvidence,
    required this.resolvedErrors,
    required this.newErrors,
    required this.retainedErrors,
    required this.criteriaSatisfied,
    required this.criteriaRegressed,
    required this.newExternalState,
    required this.planRevised,
    required this.repeatedAction,
    required this.repeatedResult,
    required this.beforeHash,
    required this.afterHash,
  });

  final List<String> newArtifacts;
  final List<String> changedArtifactHashes;
  final List<String> newEvidence;
  final List<String> resolvedErrors;
  final List<String> newErrors;
  final List<String> retainedErrors;
  final List<String> criteriaSatisfied;
  final List<String> criteriaRegressed;
  final List<String> newExternalState;
  final bool planRevised;
  final bool repeatedAction;
  final bool repeatedResult;
  final String beforeHash;
  final String afterHash;

  ConvergenceProgressClass get progressClass {
    final criteriaNet = criteriaSatisfied.length - criteriaRegressed.length;
    final errorNet = resolvedErrors.length - newErrors.length;
    if (criteriaRegressed.isNotEmpty && criteriaNet <= 0) {
      return ConvergenceProgressClass.regression;
    }
    if (criteriaNet < 0 || errorNet < 0) {
      return ConvergenceProgressClass.regression;
    }
    if (newErrors.isNotEmpty && resolvedErrors.isEmpty) {
      return ConvergenceProgressClass.regression;
    }
    final objectiveAdvance =
        criteriaNet > 0 || errorNet > 0 || newExternalState.isNotEmpty;
    if (objectiveAdvance) {
      return ConvergenceProgressClass.positiveProgress;
    }
    if (retainedErrors.isNotEmpty) {
      return ConvergenceProgressClass.neutral;
    }
    if (newArtifacts.isNotEmpty) {
      return ConvergenceProgressClass.positiveProgress;
    }
    if (changedArtifactHashes.isNotEmpty ||
        newEvidence.isNotEmpty ||
        planRevised ||
        beforeHash == afterHash ||
        repeatedAction ||
        repeatedResult) {
      return ConvergenceProgressClass.neutral;
    }
    return ConvergenceProgressClass.unknown;
  }

  bool get semanticProgress =>
      progressClass == ConvergenceProgressClass.positiveProgress;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'newArtifacts': newArtifacts,
        'changedArtifactHashes': changedArtifactHashes,
        'newEvidence': newEvidence,
        'resolvedErrors': resolvedErrors,
        'newErrors': newErrors,
        'retainedErrors': retainedErrors,
        'criteriaSatisfied': criteriaSatisfied,
        'criteriaRegressed': criteriaRegressed,
        'newExternalState': newExternalState,
        'planRevised': planRevised,
        'progressClass': progressClass.name,
        'semanticProgress': semanticProgress,
        'repeatedAction': repeatedAction,
        'repeatedResult': repeatedResult,
        'beforeHash': beforeHash,
        'afterHash': afterHash,
      };
}

class _ConvergenceTrackerState {
  String? lastAfterHash;
  String? lastFailureSignature;
  int sameFailureCount = 0;
  int sameActionSameStateCount = 0;
  final List<String> recentStates = <String>[];

  void reset() {
    lastAfterHash = null;
    lastFailureSignature = null;
    sameFailureCount = 0;
    sameActionSameStateCount = 0;
    recentStates.clear();
  }
}

class SemanticProgressEngine {
  SemanticProgressEngine();

  final Map<String, _ConvergenceTrackerState> _trackerStates =
      <String, _ConvergenceTrackerState>{};
  ConvergenceProgressClass _lastProgressClass =
      ConvergenceProgressClass.unknown;
  int _lastSameFailureCount = 0;
  int _lastSameActionSameStateCount = 0;
  bool _lastOscillating = false;

  ConvergenceProgressClass get lastProgressClass => _lastProgressClass;
  int get lastSameFailureCount => _lastSameFailureCount;
  int get lastSameActionSameStateCount => _lastSameActionSameStateCount;
  bool get lastOscillating => _lastOscillating;

  SemanticProgressDelta compare(
    SemanticProgressSnapshot before,
    SemanticProgressSnapshot after,
  ) {
    final newArtifacts = after.artifacts.keys
        .where((path) => !before.artifacts.containsKey(path))
        .toList()
      ..sort();
    final changed = after.artifacts.keys
        .where(
          (path) =>
              before.artifacts.containsKey(path) &&
              before.artifacts[path] != after.artifacts[path],
        )
        .toList()
      ..sort();
    List<String> added(Set<String> oldValues, Set<String> newValues) =>
        (newValues.difference(oldValues).toList()..sort());
    final delta = SemanticProgressDelta(
      newArtifacts: newArtifacts,
      changedArtifactHashes: changed,
      newEvidence: added(before.evidenceIds, after.evidenceIds),
      resolvedErrors: added(after.errorCodes, before.errorCodes),
      newErrors: added(before.errorCodes, after.errorCodes),
      retainedErrors: before.errorCodes.intersection(after.errorCodes).toList()
        ..sort(),
      criteriaSatisfied: added(
        before.satisfiedCriteria,
        after.satisfiedCriteria,
      ),
      criteriaRegressed: added(
        after.satisfiedCriteria,
        before.satisfiedCriteria,
      ),
      newExternalState: added(before.externalState, after.externalState),
      planRevised: before.planHash != null &&
          after.planHash != null &&
          before.planHash != after.planHash,
      repeatedAction:
          before.actionHash != null && before.actionHash == after.actionHash,
      repeatedResult:
          before.resultHash != null && before.resultHash == after.resultHash,
      beforeHash: before.hash,
      afterHash: after.hash,
    );
    _observe(before, after, delta);
    return delta;
  }

  void _observe(
    SemanticProgressSnapshot before,
    SemanticProgressSnapshot after,
    SemanticProgressDelta delta,
  ) {
    final streamKey = after.planHash ?? before.planHash ?? '__default__';
    final state = _trackerStates.putIfAbsent(
      streamKey,
      _ConvergenceTrackerState.new,
    );
    if (state.lastAfterHash != null && state.lastAfterHash != before.hash) {
      state.reset();
    }
    if (state.recentStates.isEmpty) {
      state.recentStates.add(_materialStateHash(before));
    }

    if (delta.semanticProgress) {
      state.lastFailureSignature = null;
      state.sameFailureCount = 0;
      state.sameActionSameStateCount = 0;
    } else {
      final failureSignature = after.errorCodes.isEmpty
          ? ''
          : Sha256.text(
              canonicalJson(after.errorCodes.toList()..sort()),
            );
      if (failureSignature.isNotEmpty) {
        if (state.lastFailureSignature == failureSignature) {
          state.sameFailureCount++;
        } else {
          state.lastFailureSignature = failureSignature;
          state.sameFailureCount = 1;
        }
      }
      if (delta.repeatedAction &&
          _materialStateHash(before) == _materialStateHash(after)) {
        state.sameActionSameStateCount++;
      } else {
        state.sameActionSameStateCount = 0;
      }
    }

    state.recentStates.add(_materialStateHash(after));
    while (state.recentStates.length > 8) {
      state.recentStates.removeAt(0);
    }
    final oscillating = hasOscillation(state.recentStates);
    state.lastAfterHash = after.hash;
    _lastOscillating = oscillating;
    _lastSameFailureCount = state.sameFailureCount;
    _lastSameActionSameStateCount = state.sameActionSameStateCount;
    _lastProgressClass = oscillating && !delta.semanticProgress
        ? ConvergenceProgressClass.oscillation
        : delta.progressClass;
  }

  String _materialStateHash(SemanticProgressSnapshot snapshot) => Sha256.text(
        canonicalJson(<String, dynamic>{
          'artifacts': snapshot.artifacts,
          'errorCodes': snapshot.errorCodes.toList()..sort(),
          'satisfiedCriteria': snapshot.satisfiedCriteria.toList()..sort(),
          'externalState': snapshot.externalState.toList()..sort(),
        }),
      );

  bool hasOscillation(Iterable<String> recentStates) {
    final states = recentStates.toList(growable: false);
    if (states.length < 4) return false;
    final tail = states.sublist(max(0, states.length - 8));
    for (var cycle = 2; cycle <= min(3, tail.length ~/ 2); cycle++) {
      final start = tail.length - cycle * 2;
      var same = true;
      for (var index = 0; index < cycle; index++) {
        if (tail[start + index] != tail[start + cycle + index]) {
          same = false;
          break;
        }
      }
      if (same && tail.sublist(start, start + cycle).toSet().length > 1) {
        return true;
      }
    }
    return false;
  }
}

class ConvergenceDecision {
  const ConvergenceDecision({
    required this.action,
    required this.reason,
    required this.stalledTurns,
    this.stopReason = '',
    this.requiresApproval = false,
  });

  final ConvergenceAction action;
  final String reason;
  final int stalledTurns;
  final String stopReason;
  final bool requiresApproval;
  bool get terminal => action == ConvergenceAction.failConvergence;
  bool get permissionsUnchanged => true;
}

class ConvergenceController {
  const ConvergenceController({
    this.progressTracker,
    this.consecutiveNoProgressLimit = 3,
    this.sameFailureLimit = 3,
    this.sameActionSameStateLimit = 3,
  });

  final SemanticProgressEngine? progressTracker;
  final int consecutiveNoProgressLimit;
  final int sameFailureLimit;
  final int sameActionSameStateLimit;

  ConvergenceDecision decide({
    required int stalledTurns,
    required bool semanticProgress,
    required bool strongerModelAvailable,
    required bool strongerModelApproved,
    ConvergenceProgressClass? progressClass,
    int? sameFailureCount,
    int? sameActionSameStateCount,
    bool? oscillating,
  }) {
    final classification = progressClass ??
        progressTracker?.lastProgressClass ??
        (semanticProgress
            ? ConvergenceProgressClass.positiveProgress
            : ConvergenceProgressClass.neutral);
    final repeatedFailureCount =
        sameFailureCount ?? progressTracker?.lastSameFailureCount ?? 0;
    final repeatedActionCount = sameActionSameStateCount ??
        progressTracker?.lastSameActionSameStateCount ??
        0;
    final oscillationDetected =
        oscillating ?? progressTracker?.lastOscillating ?? false;
    if (classification == ConvergenceProgressClass.positiveProgress) {
      return const ConvergenceDecision(
        action: ConvergenceAction.continueExecution,
        reason: 'Objective progress was observed.',
        stalledTurns: 0,
      );
    }
    if (oscillationDetected ||
        classification == ConvergenceProgressClass.oscillation) {
      return ConvergenceDecision(
        action: ConvergenceAction.failConvergence,
        reason:
            'Work stopped because execution oscillated between previously seen states without net improvement.',
        stopReason: 'oscillation',
        stalledTurns: stalledTurns,
      );
    }
    if (repeatedFailureCount >= sameFailureLimit) {
      return ConvergenceDecision(
        action: ConvergenceAction.failConvergence,
        reason:
            'Work stopped because the same verification failure remained unchanged across $repeatedFailureCount recovery attempts.',
        stopReason: 'repeated_failure_no_progress',
        stalledTurns: stalledTurns,
      );
    }
    if (repeatedActionCount >= sameActionSameStateLimit) {
      return ConvergenceDecision(
        action: ConvergenceAction.failConvergence,
        reason:
            'Work stopped because execution repeated the same action without changing project state.',
        stopReason: 'repeated_action_same_state',
        stalledTurns: stalledTurns,
      );
    }
    if (stalledTurns >= consecutiveNoProgressLimit) {
      final regression = classification == ConvergenceProgressClass.regression;
      return ConvergenceDecision(
        action: ConvergenceAction.failConvergence,
        reason: regression
            ? 'Work stopped because repeated recovery attempts produced regressions without net objective improvement.'
            : 'Work stopped because $stalledTurns consecutive recovery attempts produced no objective progress.',
        stopReason: regression ? 'regression_no_progress' : 'no_progress',
        stalledTurns: stalledTurns,
      );
    }
    if (stalledTurns <= 1) {
      return ConvergenceDecision(
        action: ConvergenceAction.compactAndRetry,
        reason: 'First no-progress state: compact duplicate context.',
        stalledTurns: stalledTurns,
      );
    }
    if (strongerModelAvailable && strongerModelApproved) {
      return ConvergenceDecision(
        action: ConvergenceAction.offerStrongerModel,
        reason: 'Use the already approved fallback policy.',
        stalledTurns: stalledTurns,
      );
    }
    return ConvergenceDecision(
      action: ConvergenceAction.requireDifferentAction,
      reason:
          'Repeated no-progress requires a materially different governed action.',
      stalledTurns: stalledTurns,
    );
  }
}

class VerificationEvidence {
  const VerificationEvidence({
    required this.id,
    required this.kind,
    required this.passed,
    this.stale = false,
    this.independent = true,
    this.sha256 = '',
    this.validator = '',
    this.criterionIds = const <String>{},
  });

  final String id;
  final String kind;
  final bool passed;
  final bool stale;
  final bool independent;
  final String sha256;
  final String validator;
  final Set<String> criterionIds;

  bool get objective =>
      passed &&
      !stale &&
      independent &&
      criterionIds.isNotEmpty &&
      (sha256.trim().isNotEmpty || validator.trim().isNotEmpty);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind,
        'passed': passed,
        'stale': stale,
        'independent': independent,
        'sha256': sha256,
        'validator': validator,
        'criterionIds': criterionIds.toList()..sort(),
      };
}

class IndependentVerificationReport {
  const IndependentVerificationReport({
    required this.passed,
    required this.criteria,
    required this.unsupportedClaims,
    required this.evidenceHash,
    required this.reportHash,
  });

  final bool passed;
  final List<Map<String, dynamic>> criteria;
  final List<String> unsupportedClaims;
  final String evidenceHash;
  final String reportHash;
}

class IndependentVerifier {
  const IndependentVerifier();

  IndependentVerificationReport verify({
    required WorkItem item,
    required Iterable<VerificationEvidence> evidence,
    String executorSummary = '',
  }) {
    final usable = evidence
        .where((entry) => entry.objective && entry.kind != 'executor_summary')
        .toList();
    final criteria = <Map<String, dynamic>>[];
    for (var index = 0; index < item.acceptanceCriteria.length; index++) {
      final id = '${item.id}:criterion:${index + 1}';
      final matches =
          usable.where((entry) => entry.criterionIds.contains(id)).toList();
      criteria.add(<String, dynamic>{
        'criterionId': id,
        'status': matches.isEmpty ? 'unsupported' : 'passed',
        'evidenceIds': matches.map((entry) => entry.id).toList()..sort(),
        'reason': matches.isEmpty
            ? 'No objective, current evidence supports this criterion.'
            : 'Supported by objective evidence.',
      });
    }
    final unsupported = criteria
        .where((criterion) => criterion['status'] != 'passed')
        .map((criterion) => criterion['criterionId'].toString())
        .toList();
    if (executorSummary.trim().isNotEmpty && usable.isEmpty) {
      unsupported.add('executor_prose_is_not_evidence');
    }
    final evidenceValue = usable.map((entry) => entry.toJson()).toList();
    final evidenceHash = Sha256.text(canonicalJson(evidenceValue));
    final reportValue = <String, dynamic>{
      'passed': unsupported.isEmpty,
      'criteria': criteria,
      'unsupportedClaims': unsupported,
      'evidenceHash': evidenceHash,
    };
    return IndependentVerificationReport(
      passed: unsupported.isEmpty,
      criteria: criteria,
      unsupportedClaims: unsupported,
      evidenceHash: evidenceHash,
      reportHash: Sha256.text(canonicalJson(reportValue)),
    );
  }
}

class PhaseBudget {
  const PhaseBudget({
    required this.phase,
    required this.maxModelRequests,
    required this.maxToolCalls,
    required this.maxRepairs,
    required this.maxOutputTokens,
    required this.maxContextCharacters,
    required this.deadlineSeconds,
  });

  final String phase;
  final int maxModelRequests;
  final int maxToolCalls;
  final int maxRepairs;
  final int maxOutputTokens;
  final int maxContextCharacters;
  final int deadlineSeconds;

  static PhaseBudget defaults(String phase) {
    switch (phase.trim().toLowerCase()) {
      case 'routing':
        return const PhaseBudget(
          phase: 'routing',
          maxModelRequests: 1,
          maxToolCalls: 0,
          maxRepairs: 0,
          maxOutputTokens: 256,
          maxContextCharacters: 8000,
          deadlineSeconds: 30,
        );
      case 'planning':
        return const PhaseBudget(
          phase: 'planning',
          maxModelRequests: 3,
          maxToolCalls: 2,
          maxRepairs: 2,
          maxOutputTokens: 4096,
          maxContextCharacters: 48000,
          deadlineSeconds: 300,
        );
      case 'execution':
        return const PhaseBudget(
          phase: 'execution',
          maxModelRequests: 8,
          maxToolCalls: 16,
          maxRepairs: 24,
          maxOutputTokens: 2048,
          maxContextCharacters: 36000,
          deadlineSeconds: 900,
        );
      case 'verification':
        return const PhaseBudget(
          phase: 'verification',
          maxModelRequests: 3,
          maxToolCalls: 8,
          maxRepairs: 2,
          maxOutputTokens: 2048,
          maxContextCharacters: 32000,
          deadlineSeconds: 600,
        );
      case 'summarization':
        return const PhaseBudget(
          phase: 'summarization',
          maxModelRequests: 1,
          maxToolCalls: 0,
          maxRepairs: 0,
          maxOutputTokens: 1024,
          maxContextCharacters: 48000,
          deadlineSeconds: 90,
        );
      case 'research':
        return const PhaseBudget(
          phase: 'research',
          maxModelRequests: 4,
          maxToolCalls: 8,
          maxRepairs: 2,
          maxOutputTokens: 3072,
          maxContextCharacters: 40000,
          deadlineSeconds: 600,
        );
      case 'safety_review':
        return const PhaseBudget(
          phase: 'safety_review',
          maxModelRequests: 2,
          maxToolCalls: 0,
          maxRepairs: 1,
          maxOutputTokens: 1536,
          maxContextCharacters: 24000,
          deadlineSeconds: 180,
        );
      default:
        throw ArgumentError.value(phase, 'phase', 'Unknown execution phase.');
    }
  }

  static PhaseBudget localExecution() => const PhaseBudget(
        phase: 'execution',
        maxModelRequests: 8,
        maxToolCalls: 16,
        maxRepairs: 24,
        maxOutputTokens: 1280,
        maxContextCharacters: 16000,
        deadlineSeconds: 600,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'phase': phase,
        'maxModelRequests': maxModelRequests,
        'maxToolCalls': maxToolCalls,
        'maxRepairs': maxRepairs,
        'maxOutputTokens': maxOutputTokens,
        'maxContextCharacters': maxContextCharacters,
        'deadlineSeconds': deadlineSeconds,
        'repairBudgetSemantic': 'outer_recovery_fuse',
        'consecutiveNoProgressLimit': 3,
      };
}

class ContextCompactor {
  const ContextCompactor();

  List<Map<String, dynamic>> compact(
    Iterable<Map<String, dynamic>> history, {
    int maximumRecords = 24,
  }) {
    final deduplicated = <String, Map<String, dynamic>>{};
    for (final record in history) {
      final normalized = <String, dynamic>{
        for (final entry in record.entries)
          if (!const <String>{
            'turn',
            'toolRepair',
            'protocolRepair',
            'coordinatorCorrection',
          }.contains(entry.key))
            entry.key: entry.value,
      };
      deduplicated[Sha256.text(canonicalJson(normalized))] = normalized;
    }
    final values = deduplicated.values.toList();
    final start = max(0, values.length - maximumRecords);
    return values.sublist(start);
  }
}

class ExecutionIntelligenceService {
  ExecutionIntelligenceService({required this.workflow}) {
    convergence = ConvergenceController(progressTracker: progress);
  }

  final DurableWorkflowStore workflow;
  final RoleBasedModelRouter router = const RoleBasedModelRouter();
  final SemanticProgressEngine progress = SemanticProgressEngine();
  late final ConvergenceController convergence;
  final IndependentVerifier verifier = const IndependentVerifier();
  final ContextCompactor compactor = const ContextCompactor();

  Future<void> recordProgress({
    required String runId,
    required String workItemId,
    required int attempt,
    required int turn,
    required SemanticProgressDelta delta,
    required ConvergenceDecision decision,
  }) =>
      workflow.appendSemanticProgress(
        runId: runId,
        workItemId: workItemId,
        attempt: attempt,
        turn: turn,
        beforeSha256: delta.beforeHash,
        afterSha256: delta.afterHash,
        delta: <String, dynamic>{
          ...delta.toJson(),
          'trackedProgressClass': progress.lastProgressClass.name,
          'sameFailureCount': progress.lastSameFailureCount,
          'sameActionSameStateCount': progress.lastSameActionSameStateCount,
          'oscillating': progress.lastOscillating,
          'stopReason': decision.stopReason,
        },
        semanticProgress: delta.semanticProgress,
        strategyAction: decision.action.name,
      );

  Future<void> recordVerification({
    required String runId,
    required String workItemId,
    required int attempt,
    required IndependentVerificationReport report,
  }) =>
      workflow.appendVerificationReport(
        runId: runId,
        workItemId: workItemId,
        attempt: attempt,
        evidenceSha256: report.evidenceHash,
        report: <String, dynamic>{
          'passed': report.passed,
          'criteria': report.criteria,
          'unsupportedClaims': report.unsupportedClaims,
          'evidenceHash': report.evidenceHash,
          'reportHash': report.reportHash,
        },
        passed: report.passed,
      );
}
