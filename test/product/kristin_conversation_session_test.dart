import 'package:flutter_test/flutter_test.dart';
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
