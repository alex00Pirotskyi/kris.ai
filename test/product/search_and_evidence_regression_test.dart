// Regression proofs for three defects that survived the existing suites.
//
// Each one was invisible for the same reason: the code path looked correct in
// isolation, and the fixture that exercised it happened to hide the failure.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/conversation_orchestrator.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/durable_workflow.dart';
import 'package:kristin_local_agent/product/planning_runtime.dart';
import 'package:kristin_local_agent/product/repository.dart';
import 'package:kristin_local_agent/product/research_search_provider.dart';

void main() {
  group('web-search snippet association', () {
    test('a snippet belongs to its own result, not to a list position', () {
      // The first result carries no snippet at all -- a sponsored or bare-URL
      // row. Zipping two independently collected lists by index hands the
      // second result's snippet to the first.
      final results = parseDuckDuckGoHtmlResults('''
        <html><body>
          <a class="result__a" href="https://first.example/a">First</a>
          <a class="result__a" href="https://second.example/b">Second</a>
          <a class="result__snippet">Snippet that describes the second result.</a>
          <a class="result__a" href="https://third.example/c">Third</a>
          <a class="result__snippet">Snippet that describes the third result.</a>
        </body></html>
      ''');

      expect(results, hasLength(3));
      expect(results[0].title, 'First');
      expect(results[0].snippet, isEmpty);
      expect(results[1].title, 'Second');
      expect(results[1].snippet, 'Snippet that describes the second result.');
      expect(results[2].title, 'Third');
      expect(results[2].snippet, 'Snippet that describes the third result.');
    });

    test('a rejected result does not shift later snippets', () {
      final results = parseDuckDuckGoHtmlResults('''
        <html><body>
          <a class="result__a" href="https://127.0.0.1/private">Private</a>
          <a class="result__snippet">Private snippet.</a>
          <a class="result__a" href="https://public.example/a">Public</a>
          <a class="result__snippet">Public snippet.</a>
        </body></html>
      ''');

      expect(results, hasLength(1));
      expect(results.single.title, 'Public');
      expect(results.single.snippet, 'Public snippet.');
    });

    test('snippets are read from non-anchor markup too', () {
      // Anchor-only snippet parsing left every result with an empty snippet
      // the moment the result page rendered snippets as another element, so
      // the synthesiser had titles and URLs and nothing to answer from.
      final results = parseDuckDuckGoHtmlResults('''
        <html><body>
          <a class="result__a" href="https://example.com/one">One</a>
          <div class="result__snippet">Body text for the first result.</div>
          <a class="result__a" href="https://example.com/two">Two</a>
          <td class="result__snippet">Body text for the second result.</td>
        </body></html>
      ''');

      expect(results, hasLength(2));
      expect(results[0].snippet, 'Body text for the first result.');
      expect(results[1].snippet, 'Body text for the second result.');
    });

    test('a result with no snippet anywhere stays empty rather than borrowing',
        () {
      final results = parseDuckDuckGoHtmlResults('''
        <html><body>
          <a class="result__a" href="https://example.com/only">Only</a>
        </body></html>
      ''');
      expect(results, hasLength(1));
      expect(results.single.snippet, isEmpty);
    });
  });

  group('grounded research answers', () {
    test('an ungrounded answer is never presented as the answer', () {
      final projected = ResearchAnswerProjector.project(
        '{"answer":"Insufficient evidence to determine the weather today in '
        'London.","grounded":false}',
      );

      expect(projected.answer, startsWith('Insufficient evidence'));
      expect(projected.grounded, isFalse);
      // The bug: `grounded` was only read when the answer text was empty, and
      // the envelope projector always produced answer text, so a false
      // verdict could never reach the caller.
      expect(projected.usable, isFalse);
    });

    test('a grounded answer is usable', () {
      final projected = ResearchAnswerProjector.project(
        '{"answer":"London is 14C and overcast.","grounded":true}',
      );
      expect(projected.usable, isTrue);
      expect(projected.answer, 'London is 14C and overcast.');
    });

    test('a missing verdict is treated as grounded, an empty answer is not',
        () {
      expect(
        ResearchAnswerProjector.project('{"answer":"A plain answer."}').usable,
        isTrue,
      );
      expect(
        ResearchAnswerProjector.project('{"answer":"","grounded":true}').usable,
        isFalse,
      );
    });

    test('non-envelope model text still projects as an answer', () {
      final projected = ResearchAnswerProjector.project('A bare sentence.');
      expect(projected.answer, 'A bare sentence.');
      expect(projected.usable, isTrue);
    });
  });

  group('scoped evidence lookup', () {
    late Directory root;
    late File databaseFile;
    late Directory backupDirectory;
    DurableWorkflowStore? store;

    setUp(() {
      root = Directory.systemTemp.createTempSync('kristin-scoped-evidence-');
      databaseFile = File('${root.path}${Platform.pathSeparator}workflow.db');
      backupDirectory = Directory(
        '${root.path}${Platform.pathSeparator}backups',
      )..createSync(recursive: true);
    });

    tearDown(() async {
      await store?.close();
      store = null;
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    EvidenceRecord evidenceFor(String runId, String id) => EvidenceRecord(
          id: id,
          runId: runId,
          workItemId: 'item-1',
          kind: EvidenceKind.model,
          summary: 'Model decision for $id.',
          payload: const <String, dynamic>{'responsePreview': 'preview'},
          hash: 'hash-$id',
          createdAt: DateTime.utc(2026, 9, 8),
        );

    test('one run is read without scanning every historical record', () async {
      store = await DurableWorkflowStore.open(
        databaseFile: databaseFile,
        migrationBackupDirectory: backupDirectory,
      );
      final evidence = SqliteEntityRepository<EvidenceRecord>(
        store: store!,
        collection: 'evidence',
        fromJson: EvidenceRecord.fromJson,
        toJson: (value) => value.toJson(),
        idOf: (value) => value.id,
      );

      for (var index = 0; index < 40; index++) {
        await evidence.put(evidenceFor('run-history-$index', 'old-$index'));
      }
      await evidence.put(evidenceFor('run-current', 'current-a'));
      await evidence.put(evidenceFor('run-current', 'current-b'));

      expect(evidence, isA<ScopedEntityQuery<EvidenceRecord>>());
      final scoped = await (evidence as ScopedEntityQuery<EvidenceRecord>)
          .whereFieldEquals('runId', 'run-current');

      expect(scoped.map((item) => item.id).toSet(), <String>{
        'current-a',
        'current-b',
      });
      expect((await evidence.all()).length, 42);
    });

    test('an unknown run scopes to nothing rather than everything', () async {
      store = await DurableWorkflowStore.open(
        databaseFile: databaseFile,
        migrationBackupDirectory: backupDirectory,
      );
      final evidence = SqliteEntityRepository<EvidenceRecord>(
        store: store!,
        collection: 'evidence',
        fromJson: EvidenceRecord.fromJson,
        toJson: (value) => value.toJson(),
        idOf: (value) => value.id,
      );
      await evidence.put(evidenceFor('run-a', 'a-1'));

      expect(
        await (evidence as ScopedEntityQuery<EvidenceRecord>)
            .whereFieldEquals('runId', 'run-missing'),
        isEmpty,
      );
    });

    test('a scoped query rejects an unsafe field name', () async {
      store = await DurableWorkflowStore.open(
        databaseFile: databaseFile,
        migrationBackupDirectory: backupDirectory,
      );
      await expectLater(
        store!.listEntitiesByJsonField('evidence', "runId') OR 1=1 --", 'x'),
        throwsA(isA<WorkflowStorageException>()),
      );
    });
  });

  group('scoped run listing', () {
    late Directory root;
    DurableWorkflowStore? store;

    setUp(() {
      root = Directory.systemTemp.createTempSync('kristin-scoped-runs-');
    });
    tearDown(() async {
      await store?.close();
      store = null;
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('the newest runs for one project are filtered and limited in SQL',
        () async {
      store = await DurableWorkflowStore.open(
        databaseFile: File('${root.path}${Platform.pathSeparator}runs.db'),
        migrationBackupDirectory: Directory(
          '${root.path}${Platform.pathSeparator}backups',
        )..createSync(recursive: true),
      );
      final runs = SqliteRunRepository(store!);

      for (var index = 0; index < 6; index++) {
        await store!.saveRun(
          runFixture(
            id: 'run-a-$index',
            projectId: 'project-a',
            updatedAt: DateTime.utc(2026, 9, 8, index),
          ),
        );
        await store!.saveRun(
          runFixture(
            id: 'run-b-$index',
            projectId: 'project-b',
            updatedAt: DateTime.utc(2026, 9, 8, index),
          ),
        );
      }

      expect(runs, isA<ScopedRunQuery>());
      final scoped = await (runs as ScopedRunQuery)
          .recentRuns(projectId: 'project-a', limit: 3);

      expect(scoped, hasLength(3));
      expect(
        scoped.every((run) => run.command.contract.projectId == 'project-a'),
        isTrue,
      );
      // Newest first, and the limit is applied by the query rather than after
      // every historical run has already been decoded.
      expect(scoped.first.id, 'run-a-5');
      expect((await runs.all()).length, 12);
    });
  });

  group('deterministic protocol fallback', () {
    const policy = ProtocolFallbackPolicy();

    WorkItem verificationItem({required Set<String> allowedTools}) => WorkItem(
          id: 'ensure-ready',
          title: 'Ensure project is ready',
          description:
              'Verify the project is set up correctly and accessible. Run a '
              'project analysis to ensure the project is ready for development.',
          dependencies: const <String>{},
          allowedTools: allowedTools,
          acceptanceCriteria: const <String>[
            'Project is analyzed without errors.'
          ],
        );

    test('a verification item is rescued by the analysis it asks for', () {
      // The single deterministic rescue used to go to list_directory, which
      // returns nothing on a newly created project, so the item could never
      // satisfy "project is analyzed without errors" and the run failed with
      // model_protocol_exhausted at step 0 of 4.
      final action = policy.actionFor(
        item: verificationItem(
          allowedTools: const <String>{
            'list_directory',
            'read_file',
            'write_file',
            'verify_project',
            'git_status',
          },
        ),
        request: 'create simple web page to show "Hello world"',
      );

      expect(action, isNotNull);
      expect(action!.tool, 'verify_project');
      expect(action.kind, 'tool');
      expect(action.arguments, isEmpty);
    });

    test('the listing fallback still applies when verification is not allowed',
        () {
      final action = policy.actionFor(
        item: verificationItem(
          allowedTools: const <String>{'list_directory', 'read_file'},
        ),
        request: 'create simple web page',
      );
      expect(action?.tool, 'list_directory');
    });

    test('a non-verification item is not diverted into verification', () {
      final action = policy.actionFor(
        item: const WorkItem(
          id: 'write-content',
          title: 'Write HTML content',
          description: 'Add the centered greeting markup to the page.',
          dependencies: <String>{},
          allowedTools: <String>{
            'list_directory',
            'read_file',
            'verify_project',
          },
          acceptanceCriteria: <String>['The page renders the greeting.'],
        ),
        request: 'create simple web page',
      );
      expect(action?.tool, 'list_directory');
    });

    test('an item with no usable tool has no fallback', () {
      final action = policy.actionFor(
        item: const WorkItem(
          id: 'no-tools',
          title: 'Ensure project is ready',
          description: 'Run a project analysis.',
          dependencies: <String>{},
          allowedTools: <String>{'replace_text'},
          acceptanceCriteria: <String>['Analyzed.'],
        ),
        request: 'create simple web page',
      );
      expect(action, isNull);
    });
  });
}

/// One minimal persisted run, distinguished only by id, project and recency --
/// which is all the scoped listing query is asked to get right.
RunRecord runFixture({
  required String id,
  required String projectId,
  required DateTime updatedAt,
}) {
  final created = DateTime.utc(2026, 9, 1);
  const item = WorkItem(
    id: 'task-1',
    title: 'Create result',
    description: 'Create one result artifact.',
    dependencies: <String>{},
    allowedTools: <String>{'write_file'},
    acceptanceCriteria: <String>['The result exists.'],
  );
  final contract = TaskContract(
    id: 'contract-$id',
    revision: 1,
    projectId: projectId,
    mode: CommandMode.build,
    request: 'Create result',
    acceptanceCriteria: const <AcceptanceCriterion>[
      AcceptanceCriterion(
        id: 'criterion-1',
        statement: 'The result file is created.',
        verification: 'Verify the file exists.',
      ),
    ],
    constraints: const <String>[],
    researchQuestions: const <String>[],
    requiredPermissions: const <PermissionScope>{PermissionScope.projectWrite},
    createdAt: created,
  );
  final plan = ExecutionPlan(
    id: 'plan-$id',
    contractId: contract.id,
    complexity: 1,
    rationale: 'One deterministic task.',
    items: const <WorkItem>[item],
    createdAt: created,
  );
  return RunRecord(
    id: id,
    command: PreparedCommand(
      id: 'command-$id',
      requestKey: 'request-$id',
      contract: contract,
      plan: plan,
      model: ModelIdentity(
        providerId: 'ollama',
        name: 'fixture',
        digest: 'fixture-digest',
        discoveredAt: created,
      ),
      createdAt: created,
    ),
    state: RunState.succeeded,
    items: const <WorkItemProgress>[
      WorkItemProgress(item: item, state: WorkItemState.succeeded, attempts: 1),
    ],
    budget: const AutonomyBudget(),
    createdAt: created,
    updatedAt: updatedAt,
    startedAt: created,
  );
}
