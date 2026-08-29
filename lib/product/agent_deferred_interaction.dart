import 'agent_decision_v3.dart';
import 'agent_protocol_v3.dart';
import 'domain.dart';
import 'durable_workflow.dart';

enum AgentDeferredInteractionStatus { pending, resolved }

class AgentDeferredInteractionException implements Exception {
  const AgentDeferredInteractionException(
    this.code,
    this.message, {
    this.details = const <String, dynamic>{},
  });

  final String code;
  final String message;
  final Map<String, dynamic> details;

  @override
  String toString() => '$code: $message';
}

/// Durable representation of a protocol-v3 control-flow decision.
///
/// User responses are captured as task context only. They never grant a tool,
/// permission, approval, or other execution authority.
class AgentDeferredInteraction {
  const AgentDeferredInteraction({
    required this.id,
    required this.runId,
    required this.workItemId,
    required this.decision,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.checkpointId,
    this.userResponse,
  });

  final String id;
  final String runId;
  final String workItemId;
  final AgentDecisionV3 decision;
  final AgentDeferredInteractionStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String checkpointId;
  final String? userResponse;

  bool get pending => status == AgentDeferredInteractionStatus.pending;
  bool get awaitingUserResponse =>
      pending && decision.kind == AgentDecisionV3Kind.userTakeover;

  /// Conversation input is not an authorization primitive.
  bool get userResponseGrantsAuthority => false;
}

/// Persists deferred protocol decisions independently from Runner effects.
///
/// This store deliberately does not mutate [RunState]. RunCoordinator owns the
/// durable transition to/from `paused` and the decision to resume a work item.
class AgentDeferredInteractionStore {
  AgentDeferredInteractionStore(this._workflow);

  static const String checkpointKind = 'agent_deferred_interaction_v1';
  static const int schemaVersion = 1;

  final DurableWorkflowStore _workflow;

  Future<AgentDeferredInteraction> persist({
    required String runId,
    required String workItemId,
    required AgentProtocolV3DeferredStep step,
  }) async {
    final run = await _requireActiveRun(runId, workItemId: workItemId);
    final existing = await pendingForRun(runId);
    if (existing != null) {
      throw AgentDeferredInteractionException(
        'agent_deferred_interaction_active',
        'Run $runId already has an unresolved deferred interaction.',
        details: <String, dynamic>{
          'runId': runId,
          'interactionId': existing.id,
          'workItemId': existing.workItemId,
          'decisionKind': existing.decision.kind.wireName,
        },
      );
    }

    final now = DateTime.now().toUtc();
    final interactionId = newId('agent_deferred');
    final checkpoint = await _workflow.createCheckpoint(
      runId: run.id,
      workItemId: workItemId,
      kind: checkpointKind,
      state: _state(
        interactionId: interactionId,
        status: AgentDeferredInteractionStatus.pending,
        decision: step.decision,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await _workflow.appendEvent(
      id: newId('event'),
      type: 'agent.deferred.requested',
      correlationId: run.id,
      runId: run.id,
      causationId: checkpoint.id,
      timestamp: now,
      data: <String, dynamic>{
        'interactionId': interactionId,
        'checkpointId': checkpoint.id,
        'workItemId': workItemId,
        'decision': step.decision.toJson(),
        'grantsAuthority': false,
      },
    );
    return _decode(checkpoint);
  }

  Future<AgentDeferredInteraction?> latestForRun(String runId) async {
    final checkpoint = await _workflow.latestCheckpoint(
      runId,
      kind: checkpointKind,
    );
    return checkpoint == null ? null : _decode(checkpoint);
  }

  Future<AgentDeferredInteraction?> pendingForRun(String runId) async {
    final latest = await latestForRun(runId);
    return latest != null && latest.pending ? latest : null;
  }

  Future<AgentDeferredInteraction> recordUserResponse({
    required String runId,
    required String response,
  }) async {
    final normalized = response.trim();
    if (normalized.isEmpty) {
      throw const AgentDeferredInteractionException(
        'agent_deferred_user_response_empty',
        'A deferred user response must not be empty.',
      );
    }

    final pending = await pendingForRun(runId);
    if (pending == null) {
      throw AgentDeferredInteractionException(
        'agent_deferred_interaction_missing',
        'Run $runId has no unresolved deferred interaction.',
        details: <String, dynamic>{'runId': runId},
      );
    }
    await _requireActiveRun(runId, workItemId: pending.workItemId);
    if (pending.decision.kind != AgentDecisionV3Kind.userTakeover) {
      throw AgentDeferredInteractionException(
        'agent_deferred_user_response_not_allowed',
        'Only a user_takeover interaction can be resolved by conversation input.',
        details: <String, dynamic>{
          'runId': runId,
          'interactionId': pending.id,
          'decisionKind': pending.decision.kind.wireName,
        },
      );
    }

    final now = DateTime.now().toUtc();
    final checkpoint = await _workflow.createCheckpoint(
      runId: runId,
      workItemId: pending.workItemId,
      kind: checkpointKind,
      state: _state(
        interactionId: pending.id,
        status: AgentDeferredInteractionStatus.resolved,
        decision: pending.decision,
        createdAt: pending.createdAt,
        updatedAt: now,
        userResponse: normalized,
      ),
    );
    await _workflow.appendEvent(
      id: newId('event'),
      type: 'agent.deferred.user_response_recorded',
      correlationId: runId,
      runId: runId,
      causationId: checkpoint.id,
      timestamp: now,
      data: <String, dynamic>{
        'interactionId': pending.id,
        'checkpointId': checkpoint.id,
        'workItemId': pending.workItemId,
        'userResponse': normalized,
        'grantsAuthority': false,
      },
    );
    return _decode(checkpoint);
  }

  Future<RunRecord> _requireActiveRun(
    String runId, {
    required String workItemId,
  }) async {
    final run = await _workflow.getRun(runId);
    if (run == null) {
      throw AgentDeferredInteractionException(
        'agent_deferred_run_missing',
        'Deferred interaction run $runId does not exist.',
        details: <String, dynamic>{'runId': runId},
      );
    }
    if (const <RunState>{
      RunState.succeeded,
      RunState.failed,
      RunState.cancelled,
    }.contains(run.state)) {
      throw AgentDeferredInteractionException(
        'agent_deferred_run_terminal',
        'A terminal run cannot accept a deferred interaction.',
        details: <String, dynamic>{
          'runId': runId,
          'state': run.state.name,
        },
      );
    }
    if (!run.items.any((progress) => progress.item.id == workItemId)) {
      throw AgentDeferredInteractionException(
        'agent_deferred_work_item_missing',
        'Work item $workItemId does not belong to run $runId.',
        details: <String, dynamic>{
          'runId': runId,
          'workItemId': workItemId,
        },
      );
    }
    return run;
  }

  Map<String, dynamic> _state({
    required String interactionId,
    required AgentDeferredInteractionStatus status,
    required AgentDecisionV3 decision,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? userResponse,
  }) =>
      <String, dynamic>{
        'schemaVersion': schemaVersion,
        'interactionId': interactionId,
        'status': status.name,
        'decision': decision.toJson(),
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        if (userResponse != null) 'userResponse': userResponse,
        'userResponseGrantsAuthority': false,
      };

  AgentDeferredInteraction _decode(WorkflowCheckpoint checkpoint) {
    final state = checkpoint.state;
    if (state['schemaVersion'] != schemaVersion) {
      throw _corrupt(checkpoint, 'schemaVersion');
    }
    final interactionId = state['interactionId']?.toString().trim() ?? '';
    final workItemId = checkpoint.workItemId?.trim() ?? '';
    if (interactionId.isEmpty || workItemId.isEmpty) {
      throw _corrupt(checkpoint, 'identity');
    }
    final status = switch (state['status']?.toString()) {
      'pending' => AgentDeferredInteractionStatus.pending,
      'resolved' => AgentDeferredInteractionStatus.resolved,
      _ => throw _corrupt(checkpoint, 'status'),
    };
    final rawDecision = state['decision'];
    if (rawDecision is! Map) {
      throw _corrupt(checkpoint, 'decision');
    }

    AgentDecisionV3 decision;
    try {
      decision = AgentDecisionV3.fromJson(
        rawDecision.map(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
    } on FormatException {
      throw _corrupt(checkpoint, 'decision');
    }
    if (!_isDeferred(decision.kind)) {
      throw _corrupt(checkpoint, 'decisionKind');
    }

    final createdAt = DateTime.tryParse(state['createdAt']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(state['updatedAt']?.toString() ?? '');
    if (createdAt == null || updatedAt == null) {
      throw _corrupt(checkpoint, 'timestamp');
    }
    final userResponse = state['userResponse']?.toString();
    if (status == AgentDeferredInteractionStatus.resolved &&
        decision.kind == AgentDecisionV3Kind.userTakeover &&
        (userResponse == null || userResponse.trim().isEmpty)) {
      throw _corrupt(checkpoint, 'userResponse');
    }
    if (state['userResponseGrantsAuthority'] != false) {
      throw _corrupt(checkpoint, 'userResponseGrantsAuthority');
    }

    return AgentDeferredInteraction(
      id: interactionId,
      runId: checkpoint.runId,
      workItemId: workItemId,
      decision: decision,
      status: status,
      createdAt: createdAt.toUtc(),
      updatedAt: updatedAt.toUtc(),
      checkpointId: checkpoint.id,
      userResponse: userResponse,
    );
  }

  bool _isDeferred(AgentDecisionV3Kind kind) =>
      kind == AgentDecisionV3Kind.userTakeover ||
      kind == AgentDecisionV3Kind.wait ||
      kind == AgentDecisionV3Kind.delegate;

  AgentDeferredInteractionException _corrupt(
    WorkflowCheckpoint checkpoint,
    String field,
  ) =>
      AgentDeferredInteractionException(
        'agent_deferred_checkpoint_corrupt',
        'Deferred interaction checkpoint ${checkpoint.id} is invalid.',
        details: <String, dynamic>{
          'runId': checkpoint.runId,
          'checkpointId': checkpoint.id,
          'field': field,
        },
      );
}
