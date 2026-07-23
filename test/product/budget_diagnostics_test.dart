import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/planning_runtime.dart';
import 'package:kristin_local_agent/product/product_runtime.dart';
import 'package:kristin_local_agent/product/storage_security.dart';
import 'package:kristin_local_agent/product/workspace_tools.dart';

void main() {
  group('repeated tool loop recovery', () {
    const policy = AgentLoopRecoveryPolicy();
    const baselineItem = WorkItem(
      id: 'work-baseline',
      title: 'Inspect project and establish evidence baseline',
      description:
          'Inspect relevant files, project type, Git state, and constraints.',
      dependencies: <String>{},
      allowedTools: <String>{
        'list_directory',
        'read_file',
        'inspect_file',
        'index_project',
        'git_status',
      },
      acceptanceCriteria: <String>[
        'Relevant existing behavior and files are identified with hashes.',
      ],
    );
    const listing = ToolLoopObservation(
      tool: 'list_directory',
      arguments: <String, dynamic>{
        'path': '.',
        'recursive': false,
        'maxEntries': 200,
      },
      result: ToolResult(
        ok: true,
        summary: 'Listed 3 entries.',
        data: <String, dynamic>{
          'entries': <Map<String, dynamic>>[
            <String, dynamic>{
              'path': '.env',
              'type': 'file',
              'bytes': 20,
            },
            <String, dynamic>{
              'path': 'README.md',
              'type': 'file',
              'bytes': 120,
            },
            <String, dynamic>{
              'path': 'pubspec.yaml',
              'type': 'file',
              'bytes': 300,
            },
          ],
        },
      ),
      actionFingerprint: 'action-list-root',
      outcomeFingerprint: 'outcome-list-root',
      mutationEpoch: 0,
      repetitions: 2,
    );

    test('redirects a duplicate listing to safe new evidence', () {
      final decision = policy.decide(
        item: baselineItem,
        repeated: listing,
        observations: const <ToolLoopObservation>[listing],
        usedRecoveryActions: const <String>{},
      );

      expect(decision.kind, AgentLoopRecoveryKind.redirect);
      expect(decision.action?.tool, 'inspect_file');
      expect(decision.action?.arguments['path'], 'README.md');
      expect(decision.action?.arguments['path'], isNot('.env'));
    });

    test('completes only after diverse objective baseline evidence', () {
      const inspected = ToolLoopObservation(
        tool: 'inspect_file',
        arguments: <String, dynamic>{'path': 'README.md'},
        result: ToolResult(
          ok: true,
          summary: 'Inspected README.md as markdown.',
          data: <String, dynamic>{
            'path': 'README.md',
            'sha256':
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          },
        ),
        actionFingerprint: 'action-inspect-readme',
        outcomeFingerprint: 'outcome-inspect-readme',
        mutationEpoch: 0,
      );
      const indexed = ToolLoopObservation(
        tool: 'index_project',
        arguments: <String, dynamic>{},
        result: ToolResult(
          ok: true,
          summary: 'Indexed 12 project files.',
          data: <String, dynamic>{'total': 12},
        ),
        actionFingerprint: 'action-index',
        outcomeFingerprint: 'outcome-index',
        mutationEpoch: 0,
      );

      final incomplete = policy.completionFor(
        item: baselineItem,
        observations: const <ToolLoopObservation>[listing, inspected],
      );
      final complete = policy.completionFor(
        item: baselineItem,
        observations: const <ToolLoopObservation>[
          listing,
          inspected,
          indexed,
        ],
      );

      expect(incomplete.kind, AgentLoopRecoveryKind.none);
      expect(complete.kind, AgentLoopRecoveryKind.complete);
      expect(complete.summary, contains('README.md'));
      expect(complete.summary, contains('SHA-256'));
      expect(complete.summary, contains('index_project'));
    });

    test('never auto-completes a general grounded answer task', () {
      const answerItem = WorkItem(
        id: 'work-answer',
        title: 'Answer from grounded context',
        description: 'Answer the user question from inspected project facts.',
        dependencies: <String>{},
        allowedTools: <String>{
          'list_directory',
          'inspect_file',
          'index_project',
        },
        acceptanceCriteria: <String>['The user question is answered.'],
      );
      const inspected = ToolLoopObservation(
        tool: 'inspect_file',
        arguments: <String, dynamic>{'path': 'README.md'},
        result: ToolResult(
          ok: true,
          summary: 'Inspected README.md.',
          data: <String, dynamic>{
            'path': 'README.md',
            'sha256':
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          },
        ),
        actionFingerprint: 'answer-inspect',
        outcomeFingerprint: 'answer-outcome',
        mutationEpoch: 0,
      );
      const indexed = ToolLoopObservation(
        tool: 'index_project',
        arguments: <String, dynamic>{},
        result: ToolResult(
          ok: true,
          summary: 'Indexed project.',
        ),
        actionFingerprint: 'answer-index',
        outcomeFingerprint: 'answer-index-outcome',
        mutationEpoch: 0,
      );

      final decision = policy.completionFor(
        item: answerItem,
        observations: const <ToolLoopObservation>[
          listing,
          inspected,
          indexed,
        ],
      );

      expect(decision.kind, AgentLoopRecoveryKind.none);
    });
  });

  group('budget-aware execution', () {
    test('plan budgets scale to the documented 100-task ceiling', () {
      ExecutionPlan plan(int count, int complexity) => ExecutionPlan(
            id: 'plan-$count',
            contractId: 'contract-$count',
            complexity: complexity,
            rationale: 'Budget fixture.',
            items: List<WorkItem>.generate(
              count,
              (index) => WorkItem(
                id: 'work-$index',
                title: 'Task $index',
                description: 'Complete bounded task $index.',
                dependencies: index == 0
                    ? const <String>{}
                    : <String>{'work-${index - 1}'},
                allowedTools: const <String>{'read_file'},
                acceptanceCriteria: const <String>['Evidence is recorded.'],
              ),
            ),
            createdAt: DateTime.utc(2026, 7, 17),
          );

      final small = AutonomyBudget.forPlan(plan(1, 2));
      final large = AutonomyBudget.forPlan(plan(100, 9));

      expect(small.maxModelRequests, 80);
      expect(small.maxAgentTurnsPerAttempt, 24);
      expect(large.maxModelRequests, 800);
      expect(large.maxToolCalls, 1600);
      expect(large.maxMutations, 500);
      expect(large.maxRepairs, 120);
      expect(large.maxWallTime, const Duration(hours: 12));
    });

    test('tool budgets are checked only when another governed tool is dispatched', () {
      final tools = ToolRegistry.standard();

      expect(tools.isMutatingTool('write_file'), isTrue);
      expect(tools.isMutatingTool('apply_patch'), isTrue);
      expect(tools.isMutatingTool('delete_file'), isTrue);
      expect(tools.isMutatingTool('read_file'), isFalse);
      expect(tools.isMutatingTool('verify_project'), isFalse);
    });


    test('tool descriptors expose required arguments and canonical examples', () {
      final tools = ToolRegistry.standard();
      final descriptor = tools.descriptors(
        allowlist: const <String>{'write_file'},
      ).single;
      final schema = descriptor['argumentSchema'] as Map<String, dynamic>;

      expect(schema['required'], containsAll(<String>['path', 'content']));
      expect(
        schema['example'],
        containsPair('path', 'src/app.js'),
      );
      expect(
        schema['example'],
        containsPair('content', 'export const ready = true;\n'),
      );
    });

    test('caller-supplied budgets are clamped to product safety bounds', () {
      final budget = AutonomyBudget.fromJson(<String, dynamic>{
        'maxModelRequests': 999999,
        'maxToolCalls': -1,
        'maxMutations': 999999,
        'maxRepairs': 999999,
        'maxConsecutiveFailures': 0,
        'maxAgentTurnsPerAttempt': 999,
        'minModelRequestsForRetry': 0,
        'maxRepeatedToolOutcomes': 1,
        'maxOutputBytes': 999999999,
        'maxWallTimeSeconds': 999999999,
      });

      expect(budget.maxModelRequests, 800);
      expect(budget.maxToolCalls, 1);
      expect(budget.maxMutations, 500);
      expect(budget.maxRepairs, 120);
      expect(budget.maxConsecutiveFailures, 1);
      expect(budget.maxAgentTurnsPerAttempt, 40);
      expect(budget.minModelRequestsForRetry, 1);
      expect(budget.maxRepeatedToolOutcomes, 2);
      expect(budget.maxOutputBytes, 16000000);
      expect(budget.maxWallTime, const Duration(hours: 12));
    });
  });

  group('v1.1.6 no-op mutation convergence', () {
    test('identical writes do not create rollback mutations or backups', () async {
      final temporary = await Directory.systemTemp.createTemp(
        'kristin-noop-mutation-',
      );
      try {
        final project = Directory(
          '${temporary.path}${Platform.pathSeparator}project',
        );
        final checkpoints = Directory(
          '${temporary.path}${Platform.pathSeparator}checkpoints',
        );
        await project.create(recursive: true);
        final file = File(
          '${project.path}${Platform.pathSeparator}README.md',
        );
        await file.writeAsString('# Already current\n');
        final boundary = await WorkspaceBoundary.open(project.path);
        final auditFile = File(
          '${temporary.path}${Platform.pathSeparator}logs'
          '${Platform.pathSeparator}audit.jsonl',
        );
        final audit = AuditChain(auditFile, SecretRedactor());
        await audit.open();
        final transaction = await WorkspaceTransaction.begin(
          runId: 'run-noop',
          boundary: boundary,
          checkpointRoot: checkpoints,
          audit: audit,
        );

        final record = await transaction.writeText(
          relativePath: 'README.md',
          content: '# Already current\n',
        );

        expect(record.operation, 'noop');
        expect(record.beforeHash, record.afterHash);
        expect(record.backupPath, isEmpty);
        expect(transaction.mutationCount, 0);
        expect(await file.readAsString(), '# Already current\n');
        final journal = File(
          '${checkpoints.path}${Platform.pathSeparator}run-noop'
          '${Platform.pathSeparator}journal.jsonl',
        );
        expect(await journal.exists(), isFalse);
        expect(await auditFile.readAsString(), contains('workspace.mutation_noop'));
      } finally {
        if (await temporary.exists()) {
          await temporary.delete(recursive: true);
        }
      }
    });

    test('create-only recovery cannot replace an uninspected artifact', () async {
      final temporary = await Directory.systemTemp.createTemp(
        'kristin-create-only-recovery-',
      );
      try {
        final project = Directory(
          '${temporary.path}${Platform.pathSeparator}project',
        );
        final checkpoints = Directory(
          '${temporary.path}${Platform.pathSeparator}checkpoints',
        );
        await project.create(recursive: true);
        final file = File(
          '${project.path}${Platform.pathSeparator}docs'
          '${Platform.pathSeparator}design'
          '${Platform.pathSeparator}wireframes.md',
        );
        await file.parent.create(recursive: true);
        await file.writeAsString('# User-authored design\n');
        final boundary = await WorkspaceBoundary.open(project.path);
        final audit = AuditChain(
          File(
            '${temporary.path}${Platform.pathSeparator}logs'
            '${Platform.pathSeparator}audit.jsonl',
          ),
          SecretRedactor(),
        );
        await audit.open();
        final transaction = await WorkspaceTransaction.begin(
          runId: 'run-create-only',
          boundary: boundary,
          checkpointRoot: checkpoints,
          audit: audit,
        );

        await expectLater(
          transaction.writeText(
            relativePath: 'docs/design/wireframes.md',
            content: '# Deterministic recovery draft\n',
            expectedExists: false,
          ),
          throwsA(
            isA<ProductException>().having(
              (error) => error.code,
              'code',
              'stale_existence',
            ),
          ),
        );

        expect(await file.readAsString(), '# User-authored design\n');
        expect(transaction.mutationCount, 0);
      } finally {
        if (await temporary.exists()) {
          await temporary.delete(recursive: true);
        }
      }
    });

    test('redirects repeated no-op writes to one artifact inspection', () {
      const item = WorkItem(
        id: 'write-artifact',
        title: 'Create project-local wireframes and user flows',
        description: 'Create `docs/design/wireframes.md`.',
        dependencies: <String>{},
        allowedTools: <String>{'write_file', 'inspect_file'},
        acceptanceCriteria: <String>['The artifact is inspected.'],
      );
      const repeated = ToolLoopObservation(
        tool: 'write_file',
        arguments: <String, dynamic>{
          'path': 'docs/design/wireframes.md',
          'content': '# Calculator wireframes',
        },
        result: ToolResult(
          ok: true,
          summary: 'No changes were needed.',
          data: <String, dynamic>{
            'path': 'docs/design/wireframes.md',
            'operation': 'noop',
          },
        ),
        actionFingerprint: 'write-noop',
        outcomeFingerprint: 'write-noop-result',
        mutationEpoch: 1,
        repetitions: 2,
      );

      final decision = const AgentLoopRecoveryPolicy().decide(
        item: item,
        repeated: repeated,
        observations: const <ToolLoopObservation>[repeated],
        usedRecoveryActions: const <String>{},
      );

      expect(decision.kind, AgentLoopRecoveryKind.redirect);
      expect(decision.action?.tool, 'inspect_file');
      expect(
        decision.action?.arguments['path'],
        'docs/design/wireframes.md',
      );
    });
  });

  group('fresh retry and diagnostic export', () {
    late Directory temporary;
    late Directory projectDirectory;
    late ProductRuntime runtime;
    late ProjectRecord project;
    late PreparedCommand command;
    late RunRecord failedRun;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp(
        'kristin-budget-diagnostics-',
      );
      projectDirectory = Directory(
        '${temporary.path}${Platform.pathSeparator}project',
      );
      await projectDirectory.create(recursive: true);
      await File(
        '${projectDirectory.path}${Platform.pathSeparator}README.md',
      ).writeAsString('# Fixture\n');
      runtime = await ProductRuntime.initialize(
        dataRoot: '${temporary.path}${Platform.pathSeparator}app-data',
      );
      project = await runtime.addProject(
        name: 'Budget fixture',
        rootPath: projectDirectory.path,
      );
      command = await runtime.prepare(
        projectId: project.id,
        mode: CommandMode.ask,
        request: 'Which file documents this project?',
        model: ModelIdentity(
          providerId: 'fixture',
          name: 'budget-model',
          digest: 'sha256:budget-fixture',
          discoveredAt: DateTime.utc(2026, 7, 17),
        ),
      );
      final run = await runtime.createRun(command.id);
      failedRun = run.copyWith(
        state: RunState.failed,
        items: run.items
            .map(
              (item) => item.copyWith(
                state: WorkItemState.failed,
                attempts: item.item.maxAttempts,
                lastError: 'agent_turn_limit: fixture loop',
                completedAt: DateTime.utc(2026, 7, 17),
              ),
            )
            .toList(growable: false),
        completedAt: DateTime.utc(2026, 7, 17),
        failure: 'token=supersecretvalue',
        modelRequests: run.budget.maxModelRequests,
        toolCalls: 12,
        repairs: run.budget.maxRepairs,
      );
      await runtime.repositories.runs.put(failedRun);
    });

    tearDown(() async {
      await runtime.close();
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });

    test('retry creates a linked run with fresh attempts and counters', () async {
      await expectLater(
        runtime.execute(failedRun.id),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'run_retry_required',
          ),
        ),
      );

      final retried = await runtime.retryRun(failedRun.id);

      expect(retried.id, isNot(failedRun.id));
      expect(retried.sourceRunId, failedRun.id);
      expect(retried.state, RunState.awaitingApproval);
      expect(retried.modelRequests, 0);
      expect(retried.toolCalls, 0);
      expect(retried.mutations, 0);
      expect(retried.repairs, 0);
      expect(retried.items.every((item) => item.attempts == 0), isTrue);
      expect(
        retried.budget.maxModelRequests,
        AutonomyBudget.forPlan(command.plan).maxModelRequests,
      );
    });

    test('all-logs bundle retains diagnostics while redacting source and secrets', () async {
      await runtime.repositories.evidence.put(
        EvidenceRecord(
          id: 'evidence-diagnostic-fixture',
          runId: failedRun.id,
          workItemId: failedRun.items.first.item.id,
          kind: EvidenceKind.model,
          summary: 'Model response fixture.',
          payload: const <String, dynamic>{
            'source': 'TOP_SECRET_SOURCE_PAYLOAD',
            'responsePreview': 'password=do-not-share',
            'responseCharacters': 21,
          },
          hash: Sha256.text('diagnostic fixture'),
          createdAt: DateTime.utc(2026, 7, 17),
        ),
      );
      await runtime.events.publish(
        'diagnostic.fixture',
        failedRun.id,
        <String, dynamic>{
          'runId': failedRun.id,
          'apiKey': 'diagnostic-key-value',
          'budget': failedRun.budget.toJson(),
        },
      );

      final bundle = await runtime.createSupportBundle(
        projectId: project.id,
        runId: failedRun.id,
        includeAllLogs: true,
      );
      final text = utf8.decode(await bundle.readAsBytes(), allowMalformed: true);

      expect(await bundle.exists(), isTrue);
      expect(bundle.path, endsWith('.zip'));
      expect(text, contains('kristin.diagnostics.bundle.v2'));
      expect(text, contains('runs-redacted.json'));
      expect(text, contains('evidence-redacted.json'));
      expect(text, contains('events-redacted.jsonl'));
      expect(text, contains('bundle-manifest.json'));
      expect(text, contains('run-diagnostic-summary.md'));
      expect(text, contains('maxModelRequests'));
      expect(text, isNot(contains('TOP_SECRET_SOURCE_PAYLOAD')));
      expect(text, isNot(contains('supersecretvalue')));
      expect(text, isNot(contains('do-not-share')));
      expect(text, isNot(contains('diagnostic-key-value')));
    });
  });
}
