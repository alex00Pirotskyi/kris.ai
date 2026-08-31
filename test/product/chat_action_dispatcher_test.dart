import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/capability_doctor.dart';
import 'package:kristin_local_agent/product/chat_action_dispatcher.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/storage_security.dart';

final DateTime _fixedTime = DateTime.utc(2026, 1, 1);

/// Architectural Improvement #7's Stage 7: ChatActionDispatcher is
/// exercised through a fake at the canonical service boundary, never a
/// real ProductRuntime -- proving business logic lives outside the
/// Flutter UI and is directly testable without booting real project,
/// process, or model infrastructure.
class _FakeGateway implements ChatRuntimeGateway {
  final List<String> calls = <String>[];
  List<Map<String, String>> searchResults = <Map<String, String>>[
    <String, String>{
      'title': 'Flutter stable release notes',
      'url': 'https://flutter.dev',
      'snippet': 'Latest stable channel notes.',
    },
  ];
  String? archivedProjectId;
  ProjectRecord? provisioned;
  PreparedCommand? preparedCommand;

  @override
  Future<List<Map<String, String>>> searchWeb({
    required String query,
    int count = 10,
  }) async {
    calls.add('searchWeb:$query');
    return searchResults;
  }

  @override
  Future<void> archiveResearchIfProject({
    required String? projectId,
    required String query,
    required List<Map<String, String>> results,
  }) async {
    calls.add('archiveResearchIfProject:$projectId');
    archivedProjectId = projectId;
  }

  @override
  Future<ProjectDiagnosticReport> analyzeProject(String projectId) async {
    calls.add('analyzeProject:$projectId');
    return _report();
  }

  @override
  Future<ProjectDiagnosticReport> testProject(String projectId) async {
    calls.add('testProject:$projectId');
    return _report();
  }

  @override
  Future<ProjectDiagnosticReport> buildProject(String projectId) async {
    calls.add('buildProject:$projectId');
    return _report();
  }

  @override
  Future<ProjectProcessStatus> startProject(String projectId) async {
    calls.add('startProject:$projectId');
    return ProjectProcessStatus(
      projectId: projectId,
      processId: 'process-1',
      label: 'run',
      command: 'echo',
      pid: 1,
      running: true,
      startedAt: _fixedTime,
      outputTail: '',
      logFileName: 'process-1.log',
    );
  }

  @override
  Future<ProjectProcessStatus?> stopProject(String projectId) async {
    calls.add('stopProject:$projectId');
    return null;
  }

  @override
  Future<ProjectRecord> provisionProjectForRequest({
    required String request,
    String? suggestedName,
  }) async {
    calls.add('provisionProjectForRequest:$request');
    final now = DateTime.utc(2026);
    final project = provisioned ??
        ProjectRecord(
          id: 'new-project',
          name: suggestedName ?? 'New project',
          rootPath: '/tmp/new-project',
          createdAt: now,
          updatedAt: now,
        );
    return project;
  }

  @override
  Future<PreparedCommand> prepare({
    required String projectId,
    required CommandMode mode,
    required String request,
    required ModelIdentity model,
  }) async {
    calls.add('prepare:$projectId:$request');
    if (preparedCommand != null) return preparedCommand!;
    throw StateError('preparedCommand not set for this test');
  }

  @override
  Future<CapabilityDoctorReport> inspectCapabilities({
    String? projectId,
    List<ModelIdentity>? discoveredModels,
    CapabilityDoctorDepth depth = CapabilityDoctorDepth.quick,
  }) async {
    calls.add('inspectCapabilities:$projectId');
    return CapabilityDoctorReport(
      depth: depth,
      checks: const <CapabilityDoctorCheck>[
        CapabilityDoctorCheck(
          id: 'model',
          title: 'Model connected',
          status: CapabilityDoctorStatus.ready,
          message: 'ok',
          required: true,
        ),
      ],
      checkedAt: _fixedTime,
    );
  }

  ProjectDiagnosticReport _report() => ProjectDiagnosticReport(
        projectId: 'p1',
        projectType: 'Flutter',
        testCommand: 'flutter test',
        buildCommand: 'flutter build',
        runCommand: 'flutter run',
        checks: const <DiagnosticCheck>[
          DiagnosticCheck(
            id: 'ok',
            title: 'ok',
            status: DiagnosticStatus.passed,
            message: 'ok',
          ),
        ],
        generatedAt: _fixedTime,
      );
}

void main() {
  group('ChatActionDispatcher authority boundary', () {
    test('direct project action resolves authority before touching runtime', () async {
      final gateway = _FakeGateway();
      final dispatcher = ChatActionDispatcher(gateway);

      await expectLater(
        dispatcher.inspect('p1', capabilityId: 'not.a.capability'),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'capability_unknown',
          ),
        ),
      );

      expect(gateway.calls, isEmpty);
    });

    test('button/slash/natural-language source cannot change run authority', () {
      final dispatcher = ChatActionDispatcher(_FakeGateway());
      final fromSlash = dispatcher.authorize(
        capabilityId: 'project.run',
        targetIds: const <String>{'p1'},
        reason: 'slash',
      );
      final fromNaturalLanguage = dispatcher.authorize(
        capabilityId: 'project.run',
        targetIds: const <String>{'p1'},
        reason: 'natural_language',
      );
      final fromButton = dispatcher.authorize(
        capabilityId: 'project.run',
        targetIds: const <String>{'p1'},
        reason: 'button',
      );

      expect(fromSlash.requiredScopes, fromNaturalLanguage.requiredScopes);
      expect(fromSlash.requiredScopes, fromButton.requiredScopes);
      expect(fromSlash.requiredScopes, contains(PermissionScope.projectRead));
      expect(fromSlash.requiredScopes, contains(PermissionScope.executeManaged));
    });
  });

  group('ChatActionDispatcher.search', () {
    test('research.search never requires a project', () async {
      final gateway = _FakeGateway();
      final dispatcher = ChatActionDispatcher(gateway);

      final result = await dispatcher.search(query: 'latest Flutter release');

      expect(result.results, isNotEmpty);
      expect(gateway.calls, contains('searchWeb:latest Flutter release'));
      // archiveResearchIfProject is still called, but with a null
      // projectId -- the gateway itself is responsible for treating that
      // as a no-op. The dispatcher never blocks or fails without one.
      expect(gateway.archivedProjectId, isNull);
    });

    test('a project in scope enriches but never gates the search', () async {
      final gateway = _FakeGateway();
      final dispatcher = ChatActionDispatcher(gateway);

      await dispatcher.search(
        query: 'our SQLite architecture',
        projectId: 'kris-ai',
      );

      expect(gateway.archivedProjectId, 'kris-ai');
    });
  });

  group('ChatActionDispatcher small project actions', () {
    test('inspect/test/build/run/stop/restart delegate directly', () async {
      final gateway = _FakeGateway();
      final dispatcher = ChatActionDispatcher(gateway);

      await dispatcher.inspect('p1');
      await dispatcher.test('p1');
      await dispatcher.build('p1');
      await dispatcher.run('p1');
      await dispatcher.stop('p1');
      await dispatcher.restart('p1');

      expect(gateway.calls, <String>[
        'analyzeProject:p1',
        'testProject:p1',
        'buildProject:p1',
        'startProject:p1',
        'stopProject:p1',
        'stopProject:p1',
        'startProject:p1',
      ]);
    });
  });

  group('ChatActionDispatcher.resolveAgentProject', () {
    test(
      'agent.create_project always provisions a new project, never the '
      'selected one',
      () async {
        final gateway = _FakeGateway()
          ..provisioned = ProjectRecord(
            id: 'brand-new',
            name: 'Brand new',
            rootPath: '/tmp/brand-new',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          );
        final dispatcher = ChatActionDispatcher(gateway);
        final selected = ProjectRecord(
          id: 'existing',
          name: 'Existing',
          rootPath: '/tmp/existing',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );

        final resolved = await dispatcher.resolveAgentProject(
          capabilityId: 'agent.create_project',
          selectedProject: selected,
          originalRequest: 'build me a clock app',
        );

        expect(resolved?.id, 'brand-new');
        expect(gateway.calls,
            contains('provisionProjectForRequest:build me a clock app'));
      },
    );

    test(
      'agent.modify_project and agent.fix_project never provision -- '
      'they use whatever project is already selected',
      () async {
        final gateway = _FakeGateway();
        final dispatcher = ChatActionDispatcher(gateway);
        final selected = ProjectRecord(
          id: 'existing',
          name: 'Existing',
          rootPath: '/tmp/existing',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );

        for (final capabilityId in <String>[
          'agent.modify_project',
          'agent.fix_project',
        ]) {
          final resolved = await dispatcher.resolveAgentProject(
            capabilityId: capabilityId,
            selectedProject: selected,
            originalRequest: 'add dark mode',
          );
          expect(resolved?.id, 'existing', reason: capabilityId);
        }
        expect(
          gateway.calls
              .where((call) => call.startsWith('provisionProjectForRequest')),
          isEmpty,
        );
      },
    );

    test(
      'agent.modify_project with no selected project resolves to null '
      'rather than guessing one',
      () async {
        final dispatcher = ChatActionDispatcher(_FakeGateway());
        final resolved = await dispatcher.resolveAgentProject(
          capabilityId: 'agent.modify_project',
          selectedProject: null,
          originalRequest: 'add dark mode',
        );
        expect(resolved, isNull);
      },
    );
  });
}
