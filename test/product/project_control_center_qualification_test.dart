// Wave A mandatory behavioral qualification for the Project Manager
// redesign: a real Run -> restart -> Stop cycle, with no mocking of process
// spawning, process identity, or termination. This is the "Play button"
// acceptance criterion made concrete: build something, it appears runnable,
// pressing Run actually runs it, it survives Kristin restarting, and Stop
// actually terminates it at the OS level.
//
// The fixture project's "run" command is a small, real, bundled Dart HTTP
// server bound to a fixed, known localhost port -- proving the web-project
// health/URL acceptance criterion via a genuine TCP connection, without the
// qualification depending on any port-discovery/health-probing subsystem in
// product code (that remains explicitly out of Wave A's scope; see
// ProjectLaunchProfile.ports/healthChecks, which stay empty in this wave).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/process_identity.dart';
import 'package:kristin_local_agent/product/product_runtime.dart';

const int _fixtureServerPort = 18391;

Future<File> _writeHttpServerFixture(Directory root) async {
  final file = File('${root.path}${Platform.pathSeparator}server.dart');
  await file.writeAsString('''
import 'dart:io';

Future<void> main() async {
  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    $_fixtureServerPort,
  );
  await for (final request in server) {
    request.response.statusCode = 200;
    request.response.write('kristin-project-control-center-qualification');
    await request.response.close();
  }
}
''');
  return file;
}

Future<bool> _probeHttpHealthy(int port) async {
  try {
    final client = HttpClient();
    try {
      final request = await client
          .get('127.0.0.1', port, '/')
          .timeout(const Duration(seconds: 3));
      final response = await request.close().timeout(
            const Duration(seconds: 3),
          );
      final body = await response.transform(utf8.decoder).join();
      return response.statusCode == 200 &&
          body.contains('kristin-project-control-center-qualification');
    } finally {
      client.close(force: true);
    }
  } on SocketException {
    return false;
  } on HttpException {
    return false;
  } on TimeoutException {
    return false;
  }
}

Future<bool> _waitUntil(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 15),
  Duration interval = const Duration(milliseconds: 250),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) {
      return true;
    }
    await Future<void>.delayed(interval);
  }
  return false;
}

void main() {
  group('Project Control Center qualification: Run -> restart -> Stop', () {
    late Directory temporary;
    late Directory projectDirectory;
    late Directory dataRoot;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp(
        'kristin-pcc-qualification-',
      );
      projectDirectory = Directory(
        '${temporary.path}${Platform.pathSeparator}project',
      );
      await projectDirectory.create(recursive: true);
      dataRoot = Directory(
        '${temporary.path}${Platform.pathSeparator}app-data',
      );
      final server = await _writeHttpServerFixture(projectDirectory);
      await File(
        '${projectDirectory.path}${Platform.pathSeparator}kristin.project.json',
      ).writeAsString(
        jsonEncode(<String, dynamic>{
          'type': 'custom-web-fixture',
          'run': <String, dynamic>{
            // A bare, PATH-resolved command name -- not
            // Platform.resolvedExecutable, which under `flutter test` is
            // the Flutter engine's flutter_tester test host, not a
            // general-purpose Dart script runner. This also matches how
            // real launch profiles are expressed (a command name, not an
            // absolute VM path).
            'executable': 'dart',
            'arguments': <String>[server.path],
          },
        }),
      );
    });

    tearDown(() async {
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });

    test(
      'a project Kristin can build appears runnable, survives a Kristin '
      'restart as the exact same OS process, and Stop genuinely terminates '
      'it',
      () async {
        // --- "Kristin session 1": build/admit, Run, health-check --------
        var runtime = await ProductRuntime.initialize(
          dataRoot: dataRoot.path,
        );
        final project = await runtime.addProject(
          name: 'Qualification web fixture',
          rootPath: projectDirectory.path,
        );
        expect(project.admissionReason, ProjectAdmissionReason.userAdded);

        final started = await runtime.startProject(project.id);
        expect(started.running, isTrue);
        addTearDown(() => Process.killPid(started.pid, ProcessSignal.sigkill));

        final healthyAfterStart = await _waitUntil(
          () => _probeHttpHealthy(_fixtureServerPort),
        );
        expect(
          healthyAfterStart,
          isTrue,
          reason: 'the started process must actually be serving on its '
              'known port -- this is the "health endpoint/URL captured" '
              'acceptance criterion for a web project',
        );

        final sessionsAfterStart = await runtime.repositories.workflow
            .listManagedProjectProcesses(projectId: project.id);
        expect(sessionsAfterStart, hasLength(1));
        expect(sessionsAfterStart.first.state, ProjectRuntimeState.running);
        expect(
          sessionsAfterStart.first.lifecycle,
          ManagedProcessLifecycle.persistUntilStopped,
        );
        final sessionId = sessionsAfterStart.first.id;

        // --- Simulate a Kristin restart: close this runtime instance ----
        // without stopping the launched child, then open a fresh one
        // against the same durable database -- exactly what happens when
        // the application process exits and is relaunched.
        await runtime.close();

        final stillHealthyAfterClose = await _probeHttpHealthy(
          _fixtureServerPort,
        );
        expect(
          stillHealthyAfterClose,
          isTrue,
          reason: 'closing Kristin must not kill a persist-until-stopped '
              'Project Manager run',
        );

        // --- "Kristin session 2": relaunch, recover, verify identity -----
        runtime = await ProductRuntime.initialize(dataRoot: dataRoot.path);

        final recoveredSession = await runtime.repositories.workflow
            .getManagedProjectProcess(sessionId);
        expect(
          recoveredSession!.state,
          ProjectRuntimeState.running,
          reason: 'restart reconciliation must recognize the exact same '
              'process is still running, never silently trust a bare pid, '
              'and never falsely mark a genuinely-alive session interrupted',
        );
        expect(recoveredSession.pid, started.pid);

        const probe = ProcessIdentityProbe();
        final verification = await probe.verify(
          started.pid,
          recoveredSession.processIdentity,
        );
        expect(verification, ProcessIdentityVerification.alive);

        // --- Stop: real OS-level termination, not just a state flip -----
        final stopped = await runtime.stopProject(project.id);
        expect(stopped!.running, isFalse);

        final terminatedAtOsLevel = await _waitUntil(() async {
          final healthy = await _probeHttpHealthy(_fixtureServerPort);
          final identity = await probe.verify(
            started.pid,
            recoveredSession.processIdentity,
          );
          return !healthy && identity != ProcessIdentityVerification.alive;
        });
        expect(
          terminatedAtOsLevel,
          isTrue,
          reason: 'Stop must genuinely terminate the process tree -- '
              'verified independently via both the HTTP port and OS '
              'process identity, not just via Kristin\'s own bookkeeping',
        );

        final afterStop = await runtime.repositories.workflow
            .getManagedProjectProcess(sessionId);
        expect(afterStop!.state, ProjectRuntimeState.stopped);

        await runtime.close();
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
