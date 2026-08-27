import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/process_identity.dart';
import 'package:kristin_local_agent/product/process_identity_linux.dart';
import 'package:kristin_local_agent/product/process_identity_windows.dart';
import 'package:kristin_local_agent/product/product_runtime.dart';
import 'package:kristin_local_agent/product/workspace_tools.dart';

/// Spawns a short-lived, cross-platform child process by pointing the Dart
/// SDK that is already running this test at a tiny throwaway script, rather
/// than depending on any platform-specific shell/sleep command.
Future<File> _writeSleeperScript(Directory dir, {int seconds = 20}) async {
  final file = File('${dir.path}${Platform.pathSeparator}sleeper.dart');
  await file.writeAsString('''
import 'dart:io';
Future<void> main() async {
  await Future<void>.delayed(const Duration(seconds: $seconds));
}
''');
  return file;
}

void main() {
  group('ManagedProcessLifecycle', () {
    late Directory root;
    late ManagedProcessService service;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('kristin-lifecycle-');
      service = ManagedProcessService(
        logDirectory: Directory(
          '${root.path}${Platform.pathSeparator}logs',
        ),
        redactor: SecretRedactor(),
      );
    });

    tearDown(() async {
      await service.stopAll();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test(
      'stopEphemeral terminates an ephemeral process but leaves a '
      'persistUntilStopped one running',
      () async {
        final script = await _writeSleeperScript(root);
        final ephemeral = await service.start(
          executable: 'dart',
          arguments: <String>[script.path],
          workingDirectory: root.path,
          environment: const <String, String>{},
          runId: 'run-1',
          workItemId: 'ephemeral',
        );
        final persistent = await service.start(
          executable: 'dart',
          arguments: <String>[script.path],
          workingDirectory: root.path,
          environment: const <String, String>{},
          runId: 'run-2',
          workItemId: 'persist-until-stopped',
          lifecycle: ManagedProcessLifecycle.persistUntilStopped,
        );

        await service.stopEphemeral();
        await Future<void>.delayed(const Duration(milliseconds: 200));

        final ephemeralStatus = await service.status(
          ephemeral['id']!.toString(),
        );
        final persistentStatus = await service.status(
          persistent['id']!.toString(),
        );
        expect(ephemeralStatus['running'], isFalse);
        expect(persistentStatus['running'], isTrue);

        // Clean up the still-running persistent process explicitly; it is
        // deliberately not touched by stopEphemeral/stopAll semantics that
        // matter for this test, but must not leak past it.
        await service.stop(persistent['id']!.toString());
      },
    );
  });

  group('ProcessIdentityProbe', () {
    test(
      'verify reports unverifiablePlatform when there is no recorded '
      'identity to compare against, regardless of platform',
      () async {
        const probe = ProcessIdentityProbe();
        expect(
          await probe.verify(1234, null),
          ProcessIdentityVerification.unverifiablePlatform,
        );
        expect(
          await probe.verify(1234, ''),
          ProcessIdentityVerification.unverifiablePlatform,
        );
      },
    );

    test(
      'a real running process is captured and verifies as alive; after it '
      'exits, the same recorded identity verifies as mismatchOrGone',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'kristin-identity-',
        );
        addTearDown(() async {
          if (await root.exists()) {
            await root.delete(recursive: true);
          }
        });
        final script = await _writeSleeperScript(root, seconds: 3);
        final process = await Process.start(
          'dart',
          <String>[script.path],
        );
        const probe = ProcessIdentityProbe();
        final token = await probe.capture(process.pid);
        expect(token, isNotNull);
        expect(
          await probe.verify(process.pid, token),
          ProcessIdentityVerification.alive,
        );

        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
        // Give the OS a brief moment to actually reap/reflect the exit.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(
          await probe.verify(process.pid, token),
          ProcessIdentityVerification.mismatchOrGone,
        );
      },
    );

    test(
      'readLinuxProcessIdentity parses /proc/<pid>/stat for a real pid',
      () async {
        final identity = await readLinuxProcessIdentity(pid);
        expect(identity, isNotNull);
        expect(identity!.pid, pid);
        expect(identity.isZombie, isFalse);
        expect(identity.token, 'linux:$pid:${identity.startTimeTicks}');
      },
      skip: Platform.isLinux ? null : 'Linux-only process identity reader',
    );

    test(
      'readWindowsProcessIdentity reads process creation time via '
      'kernel32.dll for a real pid',
      () {
        final identity = readWindowsProcessIdentity(pid);
        expect(identity, isNotNull);
        expect(identity!.pid, pid);
        expect(identity.token, 'windows:$pid:${identity.creationFileTime}');
      },
      skip: Platform.isWindows ? null : 'Windows-only process identity reader',
    );
  });

  group('ProductRuntime.reconcileProjectRuntimeSessions', () {
    late Directory temporary;
    late ProductRuntime runtime;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp(
        'kristin-reconcile-',
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

    test(
      'a session whose exact process identity still matches is left '
      'running, never silently trusted from a bare pid',
      () async {
        final script = await _writeSleeperScript(temporary);
        final process = await Process.start(
          'dart',
          <String>[script.path],
        );
        addTearDown(() => process.kill(ProcessSignal.sigkill));
        const probe = ProcessIdentityProbe();
        final identity = await probe.capture(process.pid);

        await runtime.repositories.workflow.insertManagedProjectProcess(
          id: 'reconcile-alive',
          projectId: 'project-x',
          lifecycle: ManagedProcessLifecycle.persistUntilStopped,
          commandSha256: Sha256.text('sleeper'),
          request: const <String, dynamic>{'executable': 'sleeper'},
          pid: process.pid,
          processIdentity: identity,
        );

        await runtime.reconcileProjectRuntimeSessions();

        final row = await runtime.repositories.workflow
            .getManagedProjectProcess('reconcile-alive');
        expect(row!.state, ProjectRuntimeState.running);
      },
      skip: Platform.isLinux || Platform.isWindows
          ? null
          : 'no process identity reader for this platform in Wave A',
    );

    test(
      'a session recorded with a mismatched/stale identity is reconciled '
      'to interrupted, never assumed alive',
      () async {
        await runtime.repositories.workflow.insertManagedProjectProcess(
          id: 'reconcile-stale',
          projectId: 'project-y',
          lifecycle: ManagedProcessLifecycle.persistUntilStopped,
          commandSha256: Sha256.text('gone'),
          request: const <String, dynamic>{'executable': 'gone'},
          pid: 999999,
          processIdentity: 'linux:999999:1',
        );

        await runtime.reconcileProjectRuntimeSessions();

        final row = await runtime.repositories.workflow
            .getManagedProjectProcess('reconcile-stale');
        expect(row!.state, ProjectRuntimeState.interrupted);
        expect(row.failureCode, isNotNull);
      },
    );

    test('a session with no recorded pid is reconciled to interrupted',
        () async {
      await runtime.repositories.workflow.insertManagedProjectProcess(
        id: 'reconcile-no-pid',
        projectId: 'project-z',
        lifecycle: ManagedProcessLifecycle.persistUntilStopped,
        commandSha256: Sha256.text('no-pid'),
        request: const <String, dynamic>{'executable': 'no-pid'},
      );

      await runtime.reconcileProjectRuntimeSessions();

      final row = await runtime.repositories.workflow
          .getManagedProjectProcess('reconcile-no-pid');
      expect(row!.state, ProjectRuntimeState.interrupted);
      expect(row.failureCode, 'process_pid_missing');
    });
  });

  group('ProductRuntime.startProject/stopProject durable persistence', () {
    late Directory temporary;
    late Directory projectDirectory;
    late ProductRuntime runtime;
    var runtimeClosed = false;

    setUp(() async {
      runtimeClosed = false;
      temporary = await Directory.systemTemp.createTemp(
        'kristin-start-stop-',
      );
      projectDirectory = Directory(
        '${temporary.path}${Platform.pathSeparator}project',
      );
      await projectDirectory.create(recursive: true);
      final script = await _writeSleeperScript(projectDirectory, seconds: 30);
      await File(
        '${projectDirectory.path}${Platform.pathSeparator}kristin.project.json',
      ).writeAsString(jsonEncodeCustomProfile(script.path));
      runtime = await ProductRuntime.initialize(
        dataRoot: '${temporary.path}${Platform.pathSeparator}app-data',
      );
    });

    tearDown(() async {
      if (!runtimeClosed) {
        await runtime.close();
      }
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });

    test(
      'starting a project writes a durable persist-until-stopped session, '
      'and stopping it marks that session stopped',
      () async {
        final project = await runtime.addProject(
          name: 'Sleeper project',
          rootPath: projectDirectory.path,
        );

        final status = await runtime.startProject(project.id);
        expect(status.running, isTrue);

        final sessions = await runtime.repositories.workflow
            .listManagedProjectProcesses(projectId: project.id);
        expect(sessions, hasLength(1));
        expect(sessions.first.state, ProjectRuntimeState.running);
        expect(
          sessions.first.lifecycle,
          ManagedProcessLifecycle.persistUntilStopped,
        );
        expect(sessions.first.pid, status.pid);
        expect(sessions.first.processIdentity, isNotNull);

        final launchProfiles =
            await runtime.repositories.workflow.listProjectLaunchProfiles(
          project.id,
        );
        expect(launchProfiles, hasLength(1));
        expect(launchProfiles.first.preferred, isTrue);

        final stopped = await runtime.stopProject(project.id);
        expect(stopped!.running, isFalse);

        final afterStop = await runtime.repositories.workflow
            .getManagedProjectProcess(sessions.first.id);
        expect(afterStop!.state, ProjectRuntimeState.stopped);
      },
    );

    test(
      'closing the runtime does not kill a persist-until-stopped project '
      'run (only ephemeral managed processes terminate with Kristin)',
      () async {
        final project = await runtime.addProject(
          name: 'Sleeper project',
          rootPath: projectDirectory.path,
        );
        final status = await runtime.startProject(project.id);

        await runtime.close();
        runtimeClosed = true;

        // The OS process must genuinely still be alive after "Kristin"
        // shuts down; verified independently of any in-app bookkeeping.
        const probe = ProcessIdentityProbe();
        final identityAfterClose = await probe.capture(status.pid);
        expect(identityAfterClose, isNotNull);

        Process.killPid(status.pid, ProcessSignal.sigkill);
      },
    );
  });
}

String jsonEncodeCustomProfile(String scriptPath) =>
    jsonEncode(<String, dynamic>{
      'type': 'custom-sleeper',
      'run': <String, dynamic>{
        'executable': 'dart',
        'arguments': <String>[scriptPath],
      },
    });
