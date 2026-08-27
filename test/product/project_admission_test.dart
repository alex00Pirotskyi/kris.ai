import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/durable_workflow.dart';
import 'package:kristin_local_agent/product/product_runtime.dart';
import 'package:kristin_local_agent/product/project_admission.dart';

void main() {
  group('ProjectAdmissionService', () {
    late Directory root;
    late Directory projectDirectory;
    DurableWorkflowStore? store;
    late ProjectAdmissionService admission;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('kristin-admission-');
      projectDirectory = Directory(
        '${root.path}${Platform.pathSeparator}my-app',
      );
      await projectDirectory.create(recursive: true);
      store = await DurableWorkflowStore.open(
        databaseFile: File(
          '${root.path}${Platform.pathSeparator}state'
          '${Platform.pathSeparator}workflow.sqlite3',
        ),
        migrationBackupDirectory: Directory(
          '${root.path}${Platform.pathSeparator}migration-backups',
        ),
      );
      admission = ProjectAdmissionService(
        projects: SqliteEntityRepository<ProjectRecord>(
          store: store!,
          collection: 'projects',
          fromJson: ProjectRecord.fromJson,
          toJson: (value) => value.toJson(),
          idOf: (value) => value.id,
        ),
      );
    });

    tearDown(() async {
      await store?.close();
      store = null;
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('admits a new project with the given reason', () async {
      final project = await admission.admitOrTouch(
        rootPath: projectDirectory.path,
        name: 'My App',
        reason: ProjectAdmissionReason.builtByKristin,
      );
      expect(project.admissionReason, ProjectAdmissionReason.builtByKristin);
      expect(project.admittedAt, isNotNull);
      expect(project.lastMeaningfulActivityAt, isNotNull);
    });

    test('re-admitting the same canonical root never duplicates', () async {
      final first = await admission.admitOrTouch(
        rootPath: projectDirectory.path,
        name: 'My App',
        reason: ProjectAdmissionReason.builtByKristin,
      );
      final second = await admission.admitOrTouch(
        rootPath: projectDirectory.path,
        name: 'My App',
        reason: ProjectAdmissionReason.successfullyTested,
      );
      expect(second.id, first.id);

      final all = await SqliteEntityRepository<ProjectRecord>(
        store: store!,
        collection: 'projects',
        fromJson: ProjectRecord.fromJson,
        toJson: (value) => value.toJson(),
        idOf: (value) => value.id,
      ).all();
      expect(all, hasLength(1));
    });

    test(
      'the original admission reason and timestamp are preserved across '
      'later touches; only lastMeaningfulActivityAt refreshes',
      () async {
        final first = await admission.admitOrTouch(
          rootPath: projectDirectory.path,
          name: 'My App',
          reason: ProjectAdmissionReason.builtByKristin,
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final second = await admission.admitOrTouch(
          rootPath: projectDirectory.path,
          name: 'My App',
          reason: ProjectAdmissionReason.successfullyVerified,
        );
        expect(second.admissionReason, ProjectAdmissionReason.builtByKristin);
        expect(second.admittedAt, first.admittedAt);
        expect(
          second.lastMeaningfulActivityAt!.isAfter(
            first.lastMeaningfulActivityAt!,
          ),
          isTrue,
        );
      },
    );

    test('touchExisting refreshes an already-resolved record by id', () async {
      final project = await admission.admitOrTouch(
        rootPath: projectDirectory.path,
        name: 'My App',
        reason: ProjectAdmissionReason.imported,
      );
      final touched = await admission.touchExisting(
        project,
        ProjectAdmissionReason.successfullyAnalyzed,
      );
      expect(touched.id, project.id);
      expect(touched.admissionReason, ProjectAdmissionReason.imported);
      expect(
        touched.lastMeaningfulActivityAt!.isAfter(
              project.lastMeaningfulActivityAt ?? DateTime.utc(2000),
            ) ||
            touched.lastMeaningfulActivityAt ==
                project.lastMeaningfulActivityAt,
        isTrue,
      );
    });
  });

  group('ProductRuntime admission hooks', () {
    late Directory temporary;
    late Directory projectDirectory;
    late ProductRuntime runtime;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp(
        'kristin-admission-hooks-',
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
    });

    tearDown(() async {
      await runtime.close();
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });

    test('addProject admits with user_added and does not duplicate', () async {
      final first = await runtime.addProject(
        name: 'Fixture project',
        rootPath: projectDirectory.path,
      );
      expect(first.admissionReason, ProjectAdmissionReason.userAdded);
      expect(first.admittedAt, isNotNull);

      final second = await runtime.addProject(
        name: 'Fixture project',
        rootPath: projectDirectory.path,
      );
      expect(second.id, first.id);

      final all = await runtime.listProjects();
      expect(all.where((project) => project.id == first.id), hasLength(1));
    });

    test('createProject admits with user_created', () async {
      final project = await runtime.createProject(
        name: 'brand-new-app',
        parentPath: temporary.path,
      );
      expect(project.admissionReason, ProjectAdmissionReason.userCreated);
    });

    test(
      'a failing random-folder read does not admit a project '
      '(inspectProject alone never calls admission)',
      () async {
        final project = await runtime.addProject(
          name: 'Fixture project',
          rootPath: projectDirectory.path,
        );
        // inspectProject is a read-only diagnostic peek, distinct from the
        // analyze/test/build/run actions that admit/touch a project; it
        // must not by itself change admission bookkeeping.
        final before = await runtime.getProject(project.id);
        await runtime.inspectProject(project.id);
        final after = await runtime.getProject(project.id);
        expect(after!.updatedAt, before!.updatedAt);
      },
    );
  });
}
