import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/agent_decision_v3.dart';
import 'package:kristin_local_agent/product/agent_deferred_interaction.dart';
import 'package:kristin_local_agent/product/chat_conversation_state.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/kristin_conversation_session.dart';
import 'package:kristin_local_agent/product/run_live_signals.dart';

void main() {
  test('selected project and model survive a genuinely new conversation', () {
    final session = KristinConversationSession();
    session.selectProject('project-a');
    session.selectModel('ollama/model-a');
    session.addUserMessage('hello');
    session.addAssistantMessage('Hi.');

    session.resetForNewConversation();

    expect(session.messages, isEmpty);
    expect(session.selectedProjectId, 'project-a');
    expect(session.selectedModelId, 'ollama/model-a');
    expect(session.state, isA<ChatIdle>());
  });

  test('finished run detach preserves transcript and selected context', () {
    final session = KristinConversationSession();
    session.addUserMessage('hello');
    session.addAssistantMessage('done');
    session.restoreRun(_run(id: 'run-a', state: RunState.running));
    session.recordLiveSignal(
      _signal('run-a', 1, LiveRunSignalKind.modelProgress),
    );
    session.updateRun(_run(id: 'run-a', state: RunState.succeeded));
    session.selectProject('project-after');
    session.selectModel('model-after');
    session.setComposerDraft('draft');

    expect(session.state, isA<ChatCompleted>());
    expect(session.detachFinishedRun(), isTrue);

    expect(session.messages.map((message) => message.text),
        <String>['hello', 'done']);
    expect(session.selectedProjectId, 'project-after');
    expect(session.selectedModelId, 'model-after');
    expect(session.composerDraft, isEmpty);
    expect(session.currentRun, isNull);
    expect(session.prepared, isNull);
    expect(session.deferredInteraction, isNull);
    expect(session.awaitingPermission, isFalse);
    expect(session.activeRequest, isEmpty);
    expect(session.liveSignals, isEmpty);
    expect(session.liveProgressText, isEmpty);
    expect(session.state, isA<ChatIdle>());
  });

  test('unfinished run detach fails closed without partial clearing', () {
    final session = KristinConversationSession();
    session.addUserMessage('keep this');
    session.restoreRun(_run(id: 'run-a', state: RunState.running));
    session.setComposerDraft('keep draft');
    session.recordLiveSignal(
      _signal('run-a', 1, LiveRunSignalKind.modelProgress),
    );

    expect(session.detachFinishedRun(), isFalse);

    expect(session.currentRun?.id, 'run-a');
    expect(session.messages.single.text, 'keep this');
    expect(session.composerDraft, 'keep draft');
    expect(session.prepared, isNotNull);
    expect(session.liveSignals, isNotEmpty);
    expect(session.state, isA<ChatExecuting>());
  });

  test('new governed request cannot orphan a non-terminal run', () {
    final session = KristinConversationSession();
    session.restoreRun(_run(id: 'run-a', state: RunState.running));

    expect(
      () => session.beginGovernedRequest('Build something else'),
      throwsA(
        isA<KristinConversationSessionException>().having(
          (error) => error.code,
          'code',
          'conversation_run_active',
        ),
      ),
    );
    expect(session.currentRun?.id, 'run-a');
  });

  test('prepared and queued runs remain protected as unfinished work', () {
    for (final state in <RunState>[RunState.prepared, RunState.queued]) {
      final session = KristinConversationSession();
      session.restoreRun(_run(id: 'run-${state.name}', state: state));

      expect(session.hasNonterminalRun, isTrue, reason: state.name);
      expect(
        session.resetForNewConversation,
        throwsA(
          isA<KristinConversationSessionException>().having(
            (error) => error.code,
            'code',
            'conversation_run_active',
          ),
        ),
        reason: state.name,
      );
    }
  });

  test('different run cannot replace unfinished run in one conversation', () {
    final session = KristinConversationSession();
    session.restoreRun(_run(id: 'run-a', state: RunState.paused));

    expect(
      () => session.restoreRun(_run(id: 'run-b', state: RunState.running)),
      throwsA(
        isA<KristinConversationSessionException>().having(
          (error) => error.code,
          'code',
          'conversation_run_mismatch',
        ),
      ),
    );
    expect(session.currentRun?.id, 'run-a');
  });

  test('pending user takeover is projected through the canonical session', () {
    final session = KristinConversationSession();
    session.restoreRun(_run(id: 'run-a', state: RunState.paused));
    session.setDeferredInteraction(
      _interaction(
        runId: 'run-a',
        status: AgentDeferredInteractionStatus.pending,
      ),
    );

    expect(session.awaitingUserInput, isTrue);
    expect(session.deferredUserPrompt, 'Which target should I use?');
    expect(session.deferredInteraction?.userResponseGrantsAuthority, isFalse);
  });

  test('deferred interaction cannot cross durable run identity', () {
    final session = KristinConversationSession();
    session.restoreRun(_run(id: 'run-a', state: RunState.paused));

    expect(
      () => session.setDeferredInteraction(
        _interaction(
          runId: 'run-b',
          status: AgentDeferredInteractionStatus.pending,
        ),
      ),
      throwsA(
        isA<KristinConversationSessionException>().having(
          (error) => error.code,
          'code',
          'conversation_deferred_run_mismatch',
        ),
      ),
    );
  });

  test('resolved takeover no longer projects as awaiting user input', () {
    final session = KristinConversationSession();
    session.restoreRun(_run(id: 'run-a', state: RunState.paused));
    session.setDeferredInteraction(
      _interaction(
        runId: 'run-a',
        status: AgentDeferredInteractionStatus.resolved,
        userResponse: 'Use staging.',
      ),
    );

    expect(session.awaitingUserInput, isFalse);
    expect(session.deferredUserPrompt, isNull);
  });

  test('terminal run refresh clears attached deferred interaction', () {
    final session = KristinConversationSession();
    session.restoreRun(_run(id: 'run-a', state: RunState.paused));
    session.setDeferredInteraction(
      _interaction(
        runId: 'run-a',
        status: AgentDeferredInteractionStatus.pending,
      ),
    );

    session.updateRun(_run(id: 'run-a', state: RunState.succeeded));

    expect(session.currentRun?.state, RunState.succeeded);
    expect(session.deferredInteraction, isNull);
    expect(session.awaitingUserInput, isFalse);
    expect(session.deferredUserPrompt, isNull);
  });

  test('awaiting approval run projects to the permission state', () {
    final session = KristinConversationSession();
    session.restoreRun(_run(id: 'run-a', state: RunState.awaitingApproval));

    expect(session.awaitingPermission, isTrue);
    expect(session.state, isA<ChatAwaitingPermission>());
  });

  test('live signals are run-scoped and bounded', () {
    final session = KristinConversationSession(maxLiveSignals: 2);
    session.restoreRun(_run(id: 'run-a', state: RunState.running));

    expect(
      session.recordLiveSignal(
        _signal('run-b', 1, LiveRunSignalKind.modelProgress),
      ),
      isFalse,
    );
    expect(session.liveSignals, isEmpty);

    expect(
      session.recordLiveSignal(_signal('run-a', 1, LiveRunSignalKind.phase)),
      isTrue,
    );
    expect(
      session.recordLiveSignal(
        _signal('run-a', 2, LiveRunSignalKind.modelProgress),
      ),
      isTrue,
    );
    expect(
      session.recordLiveSignal(
        _signal('run-a', 3, LiveRunSignalKind.heartbeat),
      ),
      isTrue,
    );

    expect(session.liveSignals, hasLength(2));
    expect(session.liveSignals.first.sequence, 2);
    expect(session.liveSignals.last.sequence, 3);
  });

  test('beginning live execution resets and primes the canonical projection',
      () {
    final session = KristinConversationSession();
    session.restoreRun(_run(id: 'run-a', state: RunState.running));
    session.recordLiveSignal(
      _signal('run-a', 1, LiveRunSignalKind.modelProgress),
    );

    expect(session.liveSignals, isNotEmpty);
    expect(session.liveProgressText, 'progress');

    session.beginLiveExecution();

    expect(session.liveSignals, isEmpty);
    expect(session.liveAssistantProtocolText, isEmpty);
    expect(session.liveAssistantText, isEmpty);
    expect(session.liveProgressText, 'Starting the first safe step.');
    expect(session.liveToolName, isEmpty);
    expect(session.liveToolOutput, isEmpty);

    session.showLiveProgress('Continuing with your answer.');
    expect(session.liveProgressText, 'Continuing with your answer.');
  });

  test('visible transcript is bounded and never accepts blank messages', () {
    final session = KristinConversationSession(maxMessages: 2);
    session.addUserMessage('one');
    session.addAssistantMessage('two');
    session.addUserMessage('three');

    expect(session.messages.map((item) => item.text), <String>['two', 'three']);
    expect(
      () => session.addAssistantMessage('   '),
      throwsA(
        isA<KristinConversationSessionException>().having(
          (error) => error.code,
          'code',
          'conversation_message_empty',
        ),
      ),
    );
  });
}

AgentDeferredInteraction _interaction({
  required String runId,
  required AgentDeferredInteractionStatus status,
  String? userResponse,
}) =>
    AgentDeferredInteraction(
      id: 'interaction-a',
      runId: runId,
      workItemId: 'work-a',
      decision: AgentDecisionV3(
        kind: AgentDecisionV3Kind.userTakeover,
        question: 'Which target should I use?',
        reason: 'The target is ambiguous.',
      ),
      status: status,
      createdAt: DateTime.utc(2026, 8, 29),
      updatedAt: DateTime.utc(2026, 8, 29),
      checkpointId: 'checkpoint-a',
      userResponse: userResponse,
    );

LiveRunSignal _signal(String runId, int sequence, LiveRunSignalKind kind) =>
    LiveRunSignal(
      sequence: sequence,
      runId: runId,
      kind: kind,
      timestamp: DateTime.utc(2026, 8, 29, 1, 2, sequence),
      data: const <String, dynamic>{'message': 'progress'},
    );

RunRecord _run({required String id, required RunState state}) {
  final command = _command();
  return RunRecord(
    id: id,
    command: command,
    state: state,
    items: command.plan.items
        .map(
          (item) => WorkItemProgress(
            item: item,
            state: WorkItemState.queued,
            attempts: 0,
          ),
        )
        .toList(),
    budget: const AutonomyBudget(),
    createdAt: DateTime.utc(2026, 8, 29),
    updatedAt: DateTime.utc(2026, 8, 29),
  );
}

PreparedCommand _command() {
  final model = ModelIdentity(
    providerId: 'ollama',
    name: 'model-a',
    digest: 'digest-a',
    discoveredAt: DateTime.utc(2026, 8, 29),
  );
  final contract = TaskContract(
    id: 'contract-a',
    revision: 3,
    projectId: 'project-a',
    mode: CommandMode.build,
    request: 'Build the requested feature.',
    acceptanceCriteria: const <AcceptanceCriterion>[
      AcceptanceCriterion(
        id: 'criterion-a',
        statement: 'The requested feature exists.',
        verification: 'Verify it directly.',
      ),
    ],
    constraints: const <String>[],
    researchQuestions: const <String>[],
    requiredPermissions: const <PermissionScope>{
      PermissionScope.projectRead,
      PermissionScope.projectWrite,
    },
    createdAt: DateTime.utc(2026, 8, 29),
  );
  const item = WorkItem(
    id: 'work-a',
    title: 'Implement',
    description: 'Implement the requested feature.',
    dependencies: <String>{},
    allowedTools: <String>{'read_file', 'write_file'},
    acceptanceCriteria: <String>['The requested feature exists.'],
    maxAttempts: 2,
  );
  return PreparedCommand(
    id: 'command-a',
    requestKey: 'request-key-a',
    contract: contract,
    plan: ExecutionPlan(
      id: 'plan-a',
      contractId: contract.id,
      complexity: 2,
      rationale: 'test',
      items: const <WorkItem>[item],
      createdAt: DateTime.utc(2026, 8, 29),
    ),
    model: model,
    createdAt: DateTime.utc(2026, 8, 29),
  );
}
