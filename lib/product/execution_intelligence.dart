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
  final List<String> criteriaSatisfied;
  final List<String> criteriaRegressed;
  final List<String> newExternalState;
  final bool planRevised;
  final bool repeatedAction;
  final bool repeatedResult;
  final String beforeHash;
  final String afterHash;

  bool get semanticProgress =>
      newArtifacts.isNotEmpty ||
      changedArtifactHashes.isNotEmpty ||
      newEvidence.isNotEmpty ||
      resolvedErrors.isNotEmpty ||
      criteriaSatisfied.isNotEmpty ||
      newExternalState.isNotEmpty ||
      planRevised;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'newArtifacts': newArtifacts,
        'changedArtifactHashes': changedArtifactHashes,
        'newEvidence': newEvidence,
        'resolvedErrors': resolvedErrors,
        'newErrors': newErrors,
        'criteriaSatisfied': criteriaSatisfied,
        'criteriaRegressed': criteriaRegressed,
        'newExternalState': newExternalState,
        'planRevised': planRevised,
        'semanticProgress': semanticProgress,
        'repeatedAction': repeatedAction,
        'repeatedResult': repeatedResult,
        'beforeHash': beforeHash,
        'afterHash': afterHash,
      };
}

class SemanticProgressEngine {
  const SemanticProgressEngine();

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
    return SemanticProgressDelta(
      newArtifacts: newArtifacts,
      changedArtifactHashes: changed,
      newEvidence: added(before.evidenceIds, after.evidenceIds),
      resolvedErrors: added(after.errorCodes, before.errorCodes),
      newErrors: added(before.errorCodes, after.errorCodes),
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
  }
}

class ConvergenceDecision {
  const ConvergenceDecision({
    required this.action,
    required this.reason,
    required this.stalledTurns,
    this.requiresApproval = false,
  });

  final ConvergenceAction action;
  final String reason;
  final int stalledTurns;
  final bool requiresApproval;
  bool get terminal => action == ConvergenceAction.failConvergence;
  bool get permissionsUnchanged => true;
}

class ConvergenceController {
  const ConvergenceController();

  ConvergenceDecision decide({
    required int stalledTurns,
    required bool semanticProgress,
    required bool strongerModelAvailable,
    required bool strongerModelApproved,
  }) {
    if (semanticProgress) {
      return const ConvergenceDecision(
        action: ConvergenceAction.continueExecution,
        reason: 'Durable semantic progress was observed.',
        stalledTurns: 0,
      );
    }
    if (stalledTurns <= 1) {
      return ConvergenceDecision(
        action: ConvergenceAction.compactAndRetry,
        reason: 'First no-progress state: compact duplicate context.',
        stalledTurns: stalledTurns,
      );
    }
    if (stalledTurns == 2) {
      return ConvergenceDecision(
        action: ConvergenceAction.requireDifferentAction,
        reason: 'Repeated action or result is not progress.',
        stalledTurns: stalledTurns,
      );
    }
    if (stalledTurns == 3) {
      return ConvergenceDecision(
        action: ConvergenceAction.routeToVerifier,
        reason: 'Use independent verification to resolve the state.',
        stalledTurns: stalledTurns,
      );
    }
    if (stalledTurns == 4) {
      return ConvergenceDecision(
        action: ConvergenceAction.splitTask,
        reason:
            'Split the blocked objective into independently verifiable work.',
        stalledTurns: stalledTurns,
      );
    }
    if (stalledTurns == 5) {
      return ConvergenceDecision(
        action: ConvergenceAction.askUser,
        reason: 'One bounded user decision is required.',
        stalledTurns: stalledTurns,
      );
    }
    if (stalledTurns == 6 && strongerModelAvailable) {
      return ConvergenceDecision(
        action: ConvergenceAction.offerStrongerModel,
        reason: strongerModelApproved
            ? 'Use the already approved fallback policy.'
            : 'Offer a stronger model without selecting it silently.',
        stalledTurns: stalledTurns,
        requiresApproval: !strongerModelApproved,
      );
    }
    return ConvergenceDecision(
      action: ConvergenceAction.failConvergence,
      reason:
          'Bounded convergence strategies were exhausted without semantic progress.',
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
          maxRepairs: 4,
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
        maxModelRequests: 4,
        maxToolCalls: 12,
        maxRepairs: 2,
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
  ExecutionIntelligenceService({required this.workflow});

  final DurableWorkflowStore workflow;
  final RoleBasedModelRouter router = const RoleBasedModelRouter();
  final SemanticProgressEngine progress = const SemanticProgressEngine();
  final ConvergenceController convergence = const ConvergenceController();
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
        delta: delta.toJson(),
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
