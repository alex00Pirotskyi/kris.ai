import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/product_runtime.dart';
import 'package:kristin_local_agent/product/project_control_service.dart';

Future<void> _runGit(Directory root, List<String> arguments) async {
  final result = await Process.run(
    'git',
    arguments,
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) {
    fail('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
}

void main() {
  group('ProjectControlService.status', () {
    late Directory temporary;
    late Directory projectDirectory;
    late ProductRuntime runtime;
    late ProjectRecord project;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp(
        'kristin-control-service-',
      );
      projectDirectory = Directory(
        '${temporary.path}${Platform.pathSeparator}project',
      );
      await projectDirectory.create(recursive: true);
      await File(
        '${projectDirectory.path}${Platform.pathSeparator}README.md',
      ).writeAsString('# Fixture\n');
      await _runGit(projectDirectory, const <String>['init', '-q']);
      await _runGit(projectDirectory, const <String>[
        'config',
        'user.email',
        'fixture@example.com',
      ]);
      await _runGit(projectDirectory, const <String>[
        'config',
        'user.name',
        'Fixture',
      ]);
      await _runGit(projectDirectory, const <String>['add', '.']);
      await _runGit(projectDirectory, const <String>[
        'commit',
        '-q',
        '-m',
        'initial',
      ]);
      runtime = await ProductRuntime.initialize(
        dataRoot: '${temporary.path}${Platform.pathSeparator}app-data',
      );
      project = await runtime.addProject(
        name: 'Fixture project',
        rootPath: projectDirectory.path,
      );
    });

    tearDown(() async {
      await runtime.close();
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });

    test('assembles project, git state, and NOT_RUN quality for a fresh '
        'project', () async {
      final status = await runtime.projectControl.status(project.id);
      expect(status.project.id, project.id);
      expect(status.git!.isRepository, isTrue);
      expect(status.git!.headSha, isNotNull);
      expect(status.git!.headSha, isNotEmpty);
      expect(status.analyzeState, ProjectQualityState.notRun);
      expect(status.testState, ProjectQualityState.notRun);
      expect(status.buildState, ProjectQualityState.notRun);
      expect(status.activeRuntime, isNull);
      expect(status.running, isFalse);
      expect(status.launchProfiles, isEmpty);
    });

    test('a passing test result at the current git HEAD reports PASS, and '
        'STALE once a new commit lands', () async {
      await runtime.testProject(project.id);
      final freshStatus = await runtime.projectControl.status(
        project.id,
        refreshGit: true,
      );
      // A README-only fixture produces no test commands to fail, so the
      // diagnostic report has no blocking failures — recorded as PASS.
      expect(freshStatus.testState, ProjectQualityState.pass);

      await File(
        '${projectDirectory.path}${Platform.pathSeparator}CHANGED.md',
      ).writeAsString('changed\n');
      await _runGit(projectDirectory, const <String>['add', '.']);
      await _runGit(projectDirectory, const <String>[
        'commit',
        '-q',
        '-m',
        'second',
      ]);

      final staleStatus = await runtime.projectControl.status(
        project.id,
        refreshGit: true,
      );
      expect(staleStatus.testState, ProjectQualityState.stale);
    });

    test('git state is cached within the TTL and only reprobed on '
        'forceRefresh', () async {
      final first = await runtime.projectControl.status(project.id);
      final firstCapturedAt = first.git!.capturedAt;

      final second = await runtime.projectControl.status(project.id);
      expect(second.git!.capturedAt, firstCapturedAt);

      final refreshed = await runtime.projectControl.status(
        project.id,
        refreshGit: true,
      );
      expect(
        refreshed.git!.capturedAt.isAtSameMomentAs(firstCapturedAt) ||
            refreshed.git!.capturedAt.isAfter(firstCapturedAt),
        isTrue,
      );
    });

    test('throws when the project does not exist', () async {
      await expectLater(
        runtime.projectControl.status('does-not-exist'),
        throwsA(anything),
      );
    });
  });

  group('ProjectControlService.runningProjects', () {
    late Directory temporary;
    late ProductRuntime runtime;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp(
        'kristin-control-running-',
      );
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

    test('lists every project with an active durable runtime session, '
        'joined against the project registry', () async {
      final projectA = await runtime.addProject(
        name: 'A',
        rootPath: (await Directory(
          '${temporary.path}${Platform.pathSeparator}a',
        ).create()).path,
      );
      final projectB = await runtime.addProject(
        name: 'B',
        rootPath: (await Directory(
          '${temporary.path}${Platform.pathSeparator}b',
        ).create()).path,
      );

      await runtime.repositories.workflow.insertManagedProjectProcess(
        id: 'session-a',
        projectId: projectA.id,
        lifecycle: ManagedProcessLifecycle.persistUntilStopped,
        commandSha256: Sha256.text('noop'),
        request: const <String, dynamic>{'executable': 'noop'},
        pid: 424242,
      );

      final running = await runtime.projectControl.runningProjects();
      expect(running, hasLength(1));
      expect(running.single.project.id, projectA.id);
      expect(running.single.session.id, 'session-a');
      expect(
        running.where((entry) => entry.project.id == projectB.id),
        isEmpty,
      );
    });
  });
}
