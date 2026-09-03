import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/agent_decision_v3.dart';
import 'package:kristin_local_agent/product/agent_deferred_interaction.dart';
import 'package:kristin_local_agent/product/agent_protocol_v3.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/durable_workflow.dart';

void main() {
  group('agent deferred interaction persistence', () {
    late Directory root;
    late File databaseFile;
    late Directory backupDirectory;
    DurableWorkflowStore? workflow;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('kristin-deferred-agent-');
      databaseFile = File(
        '${root.path}${Platform.pathSeparator}state'
        '${Platform.pathSeparator}workflow.sqlite3',
      );
      backupDirectory = Directory(
        '${root.path}${Platform.pathSeparator}migration-backups',
      );
      workflow = await DurableWorkflowStore.open(
        databaseFile: databaseFile,
        migrationBackupDirectory: backupDirectory,
      );
    });

    tearDown(() async {
      await workflow?.close();
      workflow = null;
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('user takeover survives restart and response grants no authority',
        () async {
      final run = _run(id: 'run-user', state: RunState.running);
      await workflow!.saveRun(run);
      var interactions = AgentDeferredInteractionStore(workflow!);

      final pending = await interactions.persist(
        runId: run.id,
        workItemId: 'work-a',
        step: AgentProtocolV3DeferredStep(
          decision: AgentDecisionV3(
            kind: AgentDecisionV3Kind.userTakeover,
            question: 'Which target should I use?',
            reason: 'The target is ambiguous.',
          ),
        ),
      );

      expect(pending.pending, isTrue);
      expect(pending.awaitingUserResponse, isTrue);
      expect(pending.userResponseGrantsAuthority, isFalse);
      expect(pending.decision.question, 'Which target should I use?');

      await workflow!.close();
      workflow = await DurableWorkflowStore.open(
        databaseFile: databaseFile,
        migrationBackupDirectory: backupDirectory,
      );
      interactions = AgentDeferredInteractionStore(workflow!);

      final restored = await interactions.pendingForRun(run.id);
      expect(restored?.id, pending.id);
      expect(restored?.workItemId, 'work-a');
      expect(restored?.decision.kind, AgentDecisionV3Kind.userTakeover);

      final resolved = await interactions.recordUserResponse(
        runId: run.id,
        response: '  Use the staging target.  ',
      );
      expect(resolved.status, AgentDeferredInteractionStatus.resolved);
      expect(resolved.userResponse, 'Use the staging target.');
      expect(resolved.userResponseGrantsAuthority, isFalse);
      expect(await interactions.pendingForRun(run.id), isNull);
      expect((await workflow!.getRun(run.id))?.state, RunState.running);

      final events = await workflow!.eventsForRun(run.id);
      expect(
        events.map((event) => event.type),
        containsAllInOrder(<String>[
          'run.snapshot',
          'agent.deferred.requested',
          'agent.deferred.user_response_recorded',
        ]),
      );
      expect(events.last.data['grantsAuthority'], isFalse);
    });

    test('a run cannot accumulate two unresolved deferred interactions',
        () async {
      final run = _run(id: 'run-duplicate', state: RunState.running);
      await workflow!.saveRun(run);
      final interactions = AgentDeferredInteractionStore(workflow!);
      final first = AgentProtocolV3DeferredStep(
        decision: AgentDecisionV3(
          kind: AgentDecisionV3Kind.userTakeover,
          question: 'Choose one.',
        ),
      );
      final second = AgentProtocolV3DeferredStep(
        decision: AgentDecisionV3(
          kind: AgentDecisionV3Kind.wait,
          waitHandle: 'job-42',
        ),
      );

      await interactions.persist(
        runId: run.id,
        workItemId: 'work-a',
        step: first,
      );

      await expectLater(
        interactions.persist(
          runId: run.id,
          workItemId: 'work-a',
          step: second,
        ),
        throwsA(
          isA<AgentDeferredInteractionException>().having(
            (error) => error.code,
            'code',
            'agent_deferred_interaction_active',
          ),
        ),
      );
    });

    test('conversation input cannot resolve a durable wait', () async {
      final run = _run(id: 'run-wait', state: RunState.running);
      await workflow!.saveRun(run);
      final interactions = AgentDeferredInteractionStore(workflow!);
      await interactions.persist(
        runId: run.id,
        workItemId: 'work-a',
        step: AgentProtocolV3DeferredStep(
          decision: AgentDecisionV3(
            kind: AgentDecisionV3Kind.wait,
            waitUntil: DateTime.utc(2026, 8, 30),
            reason: 'Wait for the external window.',
          ),
        ),
      );

      await expectLater(
        interactions.recordUserResponse(
          runId: run.id,
          response: 'continue anyway',
        ),
        throwsA(
          isA<AgentDeferredInteractionException>().having(
            (error) => error.code,
            'code',
            'agent_deferred_user_response_not_allowed',
          ),
        ),
      );
      expect((await interactions.pendingForRun(run.id))?.pending, isTrue);
      expect((await workflow!.getRun(run.id))?.state, RunState.running);
    });
  });
}

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
            state: WorkItemState.running,
            attempts: 1,
            startedAt: DateTime.utc(2026, 8, 29),
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
