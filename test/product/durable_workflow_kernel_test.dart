import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/durable_workflow.dart';
import 'package:kristin_local_agent/product/storage_security.dart';
import 'package:kristin_local_agent/product/workspace_tools.dart';

void main() {
  group('v1.3 durable workflow kernel', () {
    late Directory root;
    late File databaseFile;
    late Directory backupDirectory;
    DurableWorkflowStore? store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('kristin-v130-kernel-');
      databaseFile = File(
        '${root.path}${Platform.pathSeparator}state'
        '${Platform.pathSeparator}workflow.sqlite3',
      );
      backupDirectory = Directory(
        '${root.path}${Platform.pathSeparator}migration-backups',
      );
    });

    tearDown(() async {
      await store?.close();
      store = null;
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('opens the generated schema and passes integrity verification',
        () async {
      store = await DurableWorkflowStore.open(
        databaseFile: databaseFile,
        migrationBackupDirectory: backupDirectory,
      );

      expect(store!.schemaVersion, generatedWorkflowSchemaVersionForTest);
      final report = await store!.verifyIntegrity();
      expect(report.ok, isTrue);
      expect(report.integrityResult.toLowerCase(), 'ok');
      expect(report.invalidRunHashes, 0);
      expect(report.invalidEventHashes, 0);
      expect(report.projectionMismatches, 0);
    });

    test('persists entity and document repositories transactionally', () async {
      store = await DurableWorkflowStore.open(
        databaseFile: databaseFile,
        migrationBackupDirectory: backupDirectory,
      );
      final projects = SqliteEntityRepository<ProjectRecord>(
        store: store!,
        collection: 'projects',
        fromJson: ProjectRecord.fromJson,
        toJson: (value) => value.toJson(),
        idOf: (value) => value.id,
      );
      final created = DateTime.utc(2026, 7, 22);
      final project = ProjectRecord(
        id: 'project-1',
        name: 'Durable project',
        rootPath: root.path,
        createdAt: created,
        updatedAt: created,
      );

      await projects.put(project);
      expect((await projects.get(project.id))?.name, project.name);
      await SqliteJsonDocument(store!, 'settings').write(
        <String, dynamic>{'localOnly': true, 'revision': 1},
      );
      expect(
        await store!.readDocument('settings'),
        <String, dynamic>{'localOnly': true, 'revision': 1},
      );
      await projects.remove(project.id);
      expect(await projects.get(project.id), isNull);
    });

    test('stores each run snapshot with append-only projection evidence',
        () async {
      store = await DurableWorkflowStore.open(
        databaseFile: databaseFile,
        migrationBackupDirectory: backupDirectory,
      );
      final running = _run(
        id: 'run-snapshot',
        state: RunState.running,
        itemState: WorkItemState.running,
      );
      final succeeded = running.copyWith(
        state: RunState.succeeded,
        items: <WorkItemProgress>[
          running.items.single.copyWith(
            state: WorkItemState.succeeded,
            completedAt: DateTime.utc(2026, 7, 22, 0, 2),
          ),
        ],
        completedAt: DateTime.utc(2026, 7, 22, 0, 2),
        summary: 'done',
      );

      await store!.saveRun(running);
      await store!.saveRun(succeeded);

      final loaded = await store!.getRun(running.id);
      expect(loaded?.state, RunState.succeeded);
      final events = await store!.eventsForRun(running.id);
      expect(events.map((event) => event.type),
          containsAllInOrder(<String>['run.snapshot', 'run.snapshot']));
      expect(events.last.stateVersion, 2);
      expect(events.last.data['snapshotSha256'],
          Sha256.text(canonicalJson(succeeded.toJson())));
      expect((await store!.verifyIntegrity()).ok, isTrue);
    });

    test('replays a completed operation and rejects key collisions', () async {
      store = await DurableWorkflowStore.open(
        databaseFile: databaseFile,
        migrationBackupDirectory: backupDirectory,
      );
      const key = 'operation-key';
      final acquired = await store!.claimOperation(
        key: key,
        runId: 'run-1',
        workItemId: 'task-1',
        attempt: 1,
        operation: 'tool:write_file',
        normalizedArgumentsSha256: List<String>.filled(64, 'a').join(),
        ownerId: 'owner-a',
        lease: const Duration(minutes: 2),
      );
      expect(acquired.kind, IdempotencyClaimKind.acquired);

      final busy = await store!.claimOperation(
        key: key,
        runId: 'run-1',
        workItemId: 'task-1',
        attempt: 1,
        operation: 'tool:write_file',
        normalizedArgumentsSha256: List<String>.filled(64, 'a').join(),
        ownerId: 'owner-b',
      );
      expect(busy.kind, IdempotencyClaimKind.busy);

      const result = <String, dynamic>{
        'ok': true,
        'summary': 'created',
        'data': <String, dynamic>{'path': 'result.md'},
        'mutated': true,
      };
      await store!.completeOperation(
        key: key,
        ownerId: 'owner-a',
        result: result,
      );
      final replay = await store!.claimOperation(
        key: key,
        runId: 'run-1',
        workItemId: 'task-1',
        attempt: 1,
        operation: 'tool:write_file',
        normalizedArgumentsSha256: List<String>.filled(64, 'a').join(),
        ownerId: 'owner-b',
      );
      expect(replay.kind, IdempotencyClaimKind.replay);
      expect(replay.result, result);

      await expectLater(
        store!.claimOperation(
          key: key,
          runId: 'run-1',
          workItemId: 'task-1',
          attempt: 1,
          operation: 'tool:write_file',
          normalizedArgumentsSha256: List<String>.filled(64, 'b').join(),
          ownerId: 'owner-c',
        ),
        throwsA(
          isA<WorkflowStorageException>().having(
            (error) => error.code,
            'code',
            'idempotency_key_collision',
          ),
        ),
      );
    });

    test('recovers a recorded file effect only after its lease expires',
        () async {
      store = await DurableWorkflowStore.open(
        databaseFile: databaseFile,
        migrationBackupDirectory: backupDirectory,
      );
      const key = 'effect-key';
      await store!.claimOperation(
        key: key,
        runId: 'run-effect',
        workItemId: 'task-effect',
        attempt: 1,
        operation: 'tool:write_file',
        normalizedArgumentsSha256: List<String>.filled(64, 'c').join(),
        ownerId: 'owner-a',
        lease: Duration.zero,
      );
      final effect = <String, dynamic>{
        'id': 'mutation-1',
        'operation': 'create',
        'relativePath': 'docs/result.md',
        'existed': false,
        'beforeHash': '',
        'afterHash': List<String>.filled(64, 'd').join(),
        'backupPath': '',
        'timestamp': '2026-07-22T00:00:00.000Z',
        'status': 'applied',
        'idempotencyKey': key,
        'workItemId': 'task-effect',
      };
      await store!.recordCompensation(
        runId: 'run-effect',
        mutationId: 'mutation-1',
        operation: 'create',
        relativePath: 'docs/result.md',
        status: 'applied',
        record: effect,
        workItemId: 'task-effect',
        idempotencyKey: key,
        afterSha256: List<String>.filled(64, 'd').join(),
      );

      final recovered = await store!.claimOperation(
        key: key,
        runId: 'run-effect',
        workItemId: 'task-effect',
        attempt: 1,
        operation: 'tool:write_file',
        normalizedArgumentsSha256: List<String>.filled(64, 'c').join(),
        ownerId: 'owner-b',
      );
      expect(recovered.kind, IdempotencyClaimKind.effectRecorded);
      expect(
          recovered.effect?['afterHash'], List<String>.filled(64, 'd').join());
      expect(recovered.recoveredLease, isTrue);
    });

    test('recovers committed runs and interrupts incomplete stale runs',
        () async {
      store = await DurableWorkflowStore.open(
        databaseFile: databaseFile,
        migrationBackupDirectory: backupDirectory,
      );
      final committed = _run(
        id: 'run-committed',
        state: RunState.running,
        itemState: WorkItemState.succeeded,
      );
      final incomplete = _run(
        id: 'run-incomplete',
        state: RunState.running,
        itemState: WorkItemState.running,
      );
      await store!.saveRun(committed);
      await store!.saveRun(incomplete);
      await store!.createCheckpoint(
        runId: committed.id,
        kind: 'workspace_committed',
        state: <String, dynamic>{'mutations': 1},
      );
      await store!.acquireRunLease(
        runId: committed.id,
        ownerId: 'dead-a',
        lease: Duration.zero,
      );
      await store!.acquireRunLease(
        runId: incomplete.id,
        ownerId: 'dead-b',
        lease: Duration.zero,
      );

      final recovered = await store!.recoverInFlightRuns();
      expect(recovered, hasLength(2));
      expect((await store!.getRun(committed.id))?.state, RunState.succeeded);
      expect((await store!.getRun(incomplete.id))?.state, RunState.interrupted);
    });

    test('migrates legacy JSON with byte-exact backups', () async {
      final legacyProjects = File(
        '${root.path}${Platform.pathSeparator}projects.json',
      );
      final legacySettings = File(
        '${root.path}${Platform.pathSeparator}settings.json',
      );
      final timestamp = DateTime.utc(2026, 7, 22).toIso8601String();
      await legacyProjects.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(<Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'legacy-project',
                'name': 'Legacy project',
                'rootPath': root.path,
                'createdAt': timestamp,
                'updatedAt': timestamp,
              },
            ])}\n',
        flush: true,
      );
      await legacySettings.writeAsString(
        '${jsonEncode(<String, dynamic>{'localOnly': true})}\n',
        flush: true,
      );
      final projectSha = Sha256.hex(await legacyProjects.readAsBytes());
      final settingsSha = Sha256.hex(await legacySettings.readAsBytes());

      store = await DurableWorkflowStore.open(
        databaseFile: databaseFile,
        migrationBackupDirectory: backupDirectory,
        legacyCollections: <String, File>{'projects': legacyProjects},
        legacyDocuments: <String, File>{'settings': legacySettings},
      );

      expect(
        (await store!.getEntity('projects', 'legacy-project'))?['name'],
        'Legacy project',
      );
      expect(await store!.readDocument('settings'),
          <String, dynamic>{'localOnly': true});
      final backups = await backupDirectory
          .list()
          .where((entity) => entity is File)
          .cast<File>()
          .toList();
      final hashes = <String>{
        for (final file in backups) Sha256.hex(await file.readAsBytes()),
      };
      expect(hashes, containsAll(<String>[projectSha, settingsSha]));
    });

    test('restores an existing database when a legacy import fails', () async {
      store = await DurableWorkflowStore.open(
        databaseFile: databaseFile,
        migrationBackupDirectory: backupDirectory,
      );
      await store!.putEntity(
        'projects',
        'sentinel',
        <String, dynamic>{'id': 'sentinel', 'name': 'Before import'},
      );
      await store!.close();
      store = null;
      final validProjects = File(
        '${root.path}${Platform.pathSeparator}valid-projects.json',
      );
      final corruptSettings = File(
        '${root.path}${Platform.pathSeparator}corrupt-settings.json',
      );
      await validProjects.writeAsString(
        '${jsonEncode(<Map<String, dynamic>>[
              <String, dynamic>{'id': 'partial', 'name': 'Must not survive'},
            ])}\n',
        flush: true,
      );
      await corruptSettings.writeAsString('{not-json', flush: true);

      await expectLater(
        DurableWorkflowStore.open(
          databaseFile: databaseFile,
          migrationBackupDirectory: backupDirectory,
          legacyCollections: <String, File>{'projects': validProjects},
          legacyDocuments: <String, File>{'settings': corruptSettings},
        ),
        throwsA(
          isA<WorkflowStorageException>().having(
            (error) => error.code,
            'code',
            'legacy_state_corrupt',
          ),
        ),
      );
      final restoredHash = Sha256.hex(await databaseFile.readAsBytes());
      final databaseBackupHashes = <String>{
        for (final entity in await backupDirectory.list().toList())
          if (entity is File && entity.path.contains('workflow.schema-'))
            Sha256.hex(await entity.readAsBytes()),
      };
      expect(databaseBackupHashes, contains(restoredHash));

      store = await DurableWorkflowStore.open(
        databaseFile: databaseFile,
        migrationBackupDirectory: backupDirectory,
      );
      expect((await store!.getEntity('projects', 'sentinel'))?['name'],
          'Before import');
      expect(await store!.getEntity('projects', 'partial'), isNull);
    });

    test('removes a newly created database when first import fails', () async {
      final corruptProjects = File(
        '${root.path}${Platform.pathSeparator}corrupt-projects.json',
      );
      await corruptProjects.writeAsString('[not-json', flush: true);

      await expectLater(
        DurableWorkflowStore.open(
          databaseFile: databaseFile,
          migrationBackupDirectory: backupDirectory,
          legacyCollections: <String, File>{'projects': corruptProjects},
        ),
        throwsA(
          isA<WorkflowStorageException>().having(
            (error) => error.code,
            'code',
            'legacy_state_corrupt',
          ),
        ),
      );
      expect(await databaseFile.exists(), isFalse);
      expect(await File('${databaseFile.path}-wal').exists(), isFalse);
      expect(await File('${databaseFile.path}-shm').exists(), isFalse);
    });

    test('journals a mutation before effect and supports explicit rollback',
        () async {
      store = await DurableWorkflowStore.open(
        databaseFile: databaseFile,
        migrationBackupDirectory: backupDirectory,
      );
      final project = Directory(
        '${root.path}${Platform.pathSeparator}project',
      );
      final checkpoints = Directory(
        '${root.path}${Platform.pathSeparator}checkpoints',
      );
      await project.create(recursive: true);
      final target = File(
        '${project.path}${Platform.pathSeparator}result.txt',
      );
      await target.writeAsString('before\n', flush: true);
      final redactor = SecretRedactor();
      final audit = AuditChain(
        File('${root.path}${Platform.pathSeparator}audit.jsonl'),
        redactor,
      );
      await audit.open();
      final boundary = await WorkspaceBoundary.open(project.path);
      final transaction = await WorkspaceTransaction.begin(
        runId: 'run-transaction',
        boundary: boundary,
        checkpointRoot: checkpoints,
        audit: audit,
        workflow: store,
      );
      final beforeHash = Sha256.hex(await target.readAsBytes());
      final record = await transaction.runOperation<MutationRecord>(
        idempotencyKey: 'transaction-operation-key',
        workItemId: 'task-1',
        action: () => transaction.writeText(
          relativePath: 'result.txt',
          content: 'after\n',
          expectedHash: beforeHash,
          expectedExists: true,
        ),
      );
      expect(record.status, 'applied');
      expect(await target.readAsString(), 'after\n');

      await transaction.rollback();
      expect(await target.readAsString(), 'before\n');
      expect(
        (await store!.latestCheckpoint(
          'run-transaction',
          kind: 'workspace_rolled_back',
        ))
            ?.kind,
        'workspace_rolled_back',
      );
    });
  });
}

// Keep the expected schema version explicit in the behavioral test. The
// generator check and source contract make drift a reviewed change.
const int generatedWorkflowSchemaVersionForTest = 4;

RunRecord _run({
  required String id,
  required RunState state,
  required WorkItemState itemState,
}) {
  final created = DateTime.utc(2026, 7, 22);
  const item = WorkItem(
    id: 'task-1',
    title: 'Create result',
    description: 'Create and verify one result artifact.',
    dependencies: <String>{},
    allowedTools: <String>{'write_file'},
    acceptanceCriteria: <String>['The result exists and is verified.'],
    maxAttempts: 2,
  );
  final contract = TaskContract(
    id: 'contract-1',
    revision: 1,
    projectId: 'project-1',
    mode: CommandMode.build,
    request: 'Create result',
    acceptanceCriteria: const <AcceptanceCriterion>[
      AcceptanceCriterion(
        id: 'criterion-1',
        statement: 'The result file is created.',
        verification: 'Verify the file exists and contains the expected text.',
      ),
    ],
    constraints: const <String>[],
    researchQuestions: const <String>[],
    requiredPermissions: const <PermissionScope>{
      PermissionScope.projectWrite,
    },
    createdAt: created,
  );
  final plan = ExecutionPlan(
    id: 'plan-1',
    contractId: contract.id,
    complexity: 1,
    rationale: 'One deterministic task.',
    items: const <WorkItem>[item],
    createdAt: created,
  );
  final command = PreparedCommand(
    id: 'command-1',
    requestKey: 'request-1',
    contract: contract,
    plan: plan,
    model: ModelIdentity(
      providerId: 'ollama',
      name: 'fixture',
      digest: 'fixture-digest',
      discoveredAt: created,
    ),
    createdAt: created,
  );
  return RunRecord(
    id: id,
    command: command,
    state: state,
    items: <WorkItemProgress>[
      WorkItemProgress(
        item: item,
        state: itemState,
        attempts: itemState == WorkItemState.queued ? 0 : 1,
        startedAt: itemState == WorkItemState.queued ? null : created,
        completedAt: itemState == WorkItemState.succeeded ? created : null,
      ),
    ],
    budget: const AutonomyBudget(),
    createdAt: created,
    updatedAt: created,
    startedAt: state == RunState.awaitingApproval ? null : created,
  );
}
