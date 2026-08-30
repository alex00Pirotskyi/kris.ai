import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/kristin_conversation_session.dart';
import 'package:kristin_local_agent/product/run_live_signals.dart';

void main() {
  test('failed tool detail is bounded by the live output budget', () {
    final session = KristinConversationSession(maxToolOutputCharacters: 5);
    session.restoreRun(_run());

    expect(
      session.recordLiveSignal(
        LiveRunSignal(
          sequence: 1,
          runId: 'run-a',
          kind: LiveRunSignalKind.toolFailed,
          timestamp: DateTime.utc(2026, 8, 30),
          data: const <String, dynamic>{
            'tool': 'write_file',
            'detail': '0123456789',
          },
        ),
      ),
      isTrue,
    );

    expect(session.liveToolName, 'write_file');
    expect(session.liveToolOutput, '56789');
  });
}

RunRecord _run() {
  final command = _command();
  return RunRecord(
    id: 'run-a',
    command: command,
    state: RunState.running,
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
    createdAt: DateTime.utc(2026, 8, 30),
    updatedAt: DateTime.utc(2026, 8, 30),
  );
}

PreparedCommand _command() {
  final model = ModelIdentity(
    providerId: 'ollama',
    name: 'model-a',
    digest: 'digest-a',
    discoveredAt: DateTime.utc(2026, 8, 30),
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
    requiredPermissions: const <PermissionScope>{PermissionScope.projectRead},
    createdAt: DateTime.utc(2026, 8, 30),
  );
  const item = WorkItem(
    id: 'work-a',
    title: 'Implement',
    description: 'Implement the requested feature.',
    dependencies: <String>{},
    allowedTools: <String>{'write_file'},
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
      createdAt: DateTime.utc(2026, 8, 30),
    ),
    model: model,
    createdAt: DateTime.utc(2026, 8, 30),
  );
}
