import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/extensions_index.dart';
import 'package:kristin_local_agent/product/models_research.dart';
import 'package:kristin_local_agent/product/planning_runtime.dart';
import 'package:kristin_local_agent/product/product_runtime.dart';
import 'package:kristin_local_agent/product/run_preflight.dart';
import 'package:kristin_local_agent/product/runner_tool_registry.dart';

void main() {
  final enabled = Platform.environment['KRISTIN_RUN_REAL_FLUTTER_SMOKE'] == '1';

  test(
    'real blank Flutter project converges in the active root without network',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'kristin-real-flutter-runner-smoke-',
      );
      final projectRoot = Directory(
        '${sandbox.path}${Platform.pathSeparator}project',
      );
      final dataRoot = Directory(
        '${sandbox.path}${Platform.pathSeparator}data',
      );
      await projectRoot.create(recursive: true);
      await dataRoot.create(recursive: true);
      final metadataRoot = Directory(
        '${projectRoot.path}${Platform.pathSeparator}.kristin',
      );
      await metadataRoot.create(recursive: true);
      await File(
        '${metadataRoot.path}${Platform.pathSeparator}blank-root-evidence.txt',
      ).writeAsString('Semantically blank selected Flutter project.\n');

      final model = ModelIdentity(
        providerId: 'ollama',
        name: 'recorded-flutter-smoke',
        digest: 'sha256:recorded-flutter-smoke',
        discoveredAt: DateTime.utc(2026, 8, 24),
      );
      final provider = _FlutterSmokeProvider(model);
      ProductRuntime? runtime;
      try {
        runtime = await ProductRuntime.initialize(dataRoot: dataRoot.path);
        expect(runtime.settings.localOnly, isTrue);
        expect(runtime.settings.allowPackageNetwork, isFalse);

        final coordinator = _recordedCoordinator(runtime, provider);
        final project = await runtime.addProject(
          name: 'synthetic_app',
          rootPath: projectRoot.path,
        );
        final prepared = await runtime.prepare(
          projectId: project.id,
          mode: CommandMode.build,
          request: 'Build a minimal Flutter application named synthetic_app '
              'in the active project root without network access. The app must '
              'render "Kristin real Flutter smoke" and pass analyzer and tests.',
          model: model,
        );
        var run = await coordinator.createRun(
          prepared,
          budget: AutonomyBudget.forPlan(prepared.plan),
        );
        await runtime.approve(
          runId: run.id,
          scopes: prepared.contract.requiredPermissions,
        );

        run = await coordinator.execute(run.id);

        if (run.state.name != 'succeeded') {
          final diagnosticEvidence = await runtime.evidenceForRun(run.id);
          final auditText = await runtime.repositories.auditFile.readAsString();
          final auditLines = const LineSplitter().convert(auditText);
          final auditTail = auditLines.length <= 40
              ? auditLines
              : auditLines.sublist(auditLines.length - 40);
          stderr.writeln('FLUTTER_SMOKE_RUN ${jsonEncode(run.toJson())}');
          stderr.writeln(
            'FLUTTER_SMOKE_EVIDENCE ${jsonEncode(diagnosticEvidence.map((item) => <String, dynamic>{
                  'kind': item.kind.name,
                  'payload': item.payload,
                }).toList(growable: false))}',
          );
          stderr.writeln('FLUTTER_SMOKE_AUDIT_TAIL ${jsonEncode(auditTail)}');
        }

        expect(
          run.state.name,
          'succeeded',
          reason:
              'runFailure=${run.failure}; items=${run.items.map((item) => '${item.item.title}:${item.state.name}:${item.attempts}:${item.lastError ?? ''}').join('|')}',
        );
        expect(provider.readinessRequests, 1);
        expect(provider.executionRequests, lessThanOrEqualTo(12));
        expect(
          await Directory(
            '${projectRoot.path}${Platform.pathSeparator}synthetic_app',
          ).exists(),
          isFalse,
        );
        final pubspec = await File(
          '${projectRoot.path}${Platform.pathSeparator}pubspec.yaml',
        ).readAsString();
        final mainSource = await File(
          '${projectRoot.path}${Platform.pathSeparator}lib'
          '${Platform.pathSeparator}main.dart',
        ).readAsString();
        expect(pubspec, contains('name: synthetic_app'));
        expect(mainSource, contains('Kristin real Flutter smoke'));

        final evidence = await runtime.evidenceForRun(run.id);
        final commandEvidence = evidence
            .where((item) => item.payload['tool']?.toString() == 'run_command')
            .toList(growable: false);
        final scaffold = commandEvidence.firstWhere((item) {
          final data = Map<String, dynamic>.from(
            item.payload['data']! as Map,
          );
          return data['blankProjectScaffoldNormalized'] == true;
        });
        final scaffoldData = Map<String, dynamic>.from(
          scaffold.payload['data']! as Map,
        );
        expect(scaffold.payload['ok'], isTrue);
        expect(scaffold.payload['mutated'], isTrue);
        expect(scaffoldData['workingDirectory'], projectRoot.path);
        expect(
          scaffoldData['arguments'],
          containsAll(<String>[
            'create',
            '.',
            '--no-pub',
            '--project-name',
            'synthetic_app',
          ]),
        );
        final scaffoldChanges =
            (scaffoldData['workspaceChanges'] as Map?)?['paths'];
        expect(scaffoldChanges, isA<List>());
        expect(
          (scaffoldChanges! as List).map((value) => value.toString()),
          containsAll(<String>['pubspec.yaml', 'lib/main.dart']),
        );

        final repair = commandEvidence.firstWhere((item) {
          final data = Map<String, dynamic>.from(
            item.payload['data']! as Map,
          );
          final args = (data['arguments'] as List?)
                  ?.map((value) => value.toString())
                  .toList() ??
              const <String>[];
          return const ListEquality<String>().equals(
            args,
            const <String>['tool/repair_smoke.dart'],
          );
        });
        final repairData = Map<String, dynamic>.from(
          repair.payload['data']! as Map,
        );
        expect(repair.payload['ok'], isTrue);
        expect(repair.payload['mutated'], isTrue);
        expect(repairData['duplicateExecutableRemoved'], isTrue);
        final repairChanges =
            (repairData['workspaceChanges'] as Map?)?['paths'];
        expect(repairChanges, isA<List>());
        expect(
          (repairChanges! as List).map((value) => value.toString()),
          containsAll(<String>[
            'pubspec.yaml',
            'lib/main.dart',
            'test/smoke_test.dart',
          ]),
        );

        final offlinePub = commandEvidence.firstWhere((item) {
          final data = Map<String, dynamic>.from(
            item.payload['data']! as Map,
          );
          final args = (data['arguments'] as List?)
                  ?.map((value) => value.toString())
                  .toList() ??
              const <String>[];
          return const ListEquality<String>().equals(
            args,
            const <String>['pub', 'get', '--offline'],
          );
        });
        expect(offlinePub.payload['ok'], isTrue);
        expect(
          evidence.any(
            (item) =>
                item.kind.name == 'verification' && item.payload['ok'] == true,
          ),
          isTrue,
        );

        final durable = await runtime.getRun(run.id);
        expect(durable, isNotNull);
        expect(durable!.state.name, 'succeeded');
      } finally {
        await runtime?.close();
        if (await sandbox.exists()) {
          await sandbox.delete(recursive: true);
        }
      }
    },
    skip: enabled
        ? false
        : 'Set KRISTIN_RUN_REAL_FLUTTER_SMOKE=1 for the real Flutter smoke.',
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

RunCoordinator _recordedCoordinator(
  ProductRuntime runtime,
  _FlutterSmokeProvider provider,
) {
  final registry = _RecordedModelRegistry(runtime, provider);
  final preflight = RunPreflightService(
    resolver: const RunCapabilityResolver(),
    settingsProvider: () => runtime.settings,
    modelProbe: (model, requirement) async {
      final stopwatch = Stopwatch()..start();
      final result = await provider.generate(
        ModelGenerationRequest(
          identity: model,
          systemPrompt:
              'You are a readiness probe. Return exactly {"status":"ready"}.',
          userPrompt: 'Return readiness JSON now.',
          commandId: 'real-flutter-smoke-preflight',
          temperature: 0,
          maxOutputTokens: 32,
          firstTokenTimeout: const Duration(seconds: 2),
          totalTimeout: const Duration(seconds: 2),
        ),
      );
      stopwatch.stop();
      return RunCapabilityProbeResult(
        key: requirement.key,
        label: requirement.label,
        ok: result.text.isNotEmpty,
        required: requirement.required,
        message: 'Recorded Flutter smoke model is ready.',
        durationMilliseconds: stopwatch.elapsedMilliseconds,
      );
    },
    browserProbe: (requirement) async => RunCapabilityProbeResult(
      key: requirement.key,
      label: requirement.label,
      ok: false,
      required: requirement.required,
      message: 'Browser is not used by the real Flutter Runner smoke.',
      durationMilliseconds: 0,
    ),
    researchSearchProbe: (run, requirement) async => RunCapabilityProbeResult(
      key: requirement.key,
      label: requirement.label,
      ok: false,
      required: requirement.required,
      message: 'Research is not used by the real Flutter Runner smoke.',
      durationMilliseconds: 0,
    ),
  );
  return RunCoordinator(
    directories: runtime.directories,
    repositories: runtime.repositories,
    modelRegistry: registry,
    permissions: runtime.permissions,
    secrets: runtime.secrets,
    research: runtime.research,
    knowledge: runtime.knowledge,
    tools: RunnerToolRegistry.standard(),
    audit: runtime.audit,
    events: runtime.events,
    settingsProvider: () => runtime.settings,
    redactor: runtime.redactor,
    deployment: runtime.deployment,
    managedProcesses: runtime.managedProcesses,
    sourceIndex: runtime.sourceIndex,
    skillRegistry: const SkillRegistry(),
    mcp: runtime.mcp,
    executionIntelligence: runtime.executionIntelligence,
    preflight: preflight,
    liveSignals: runtime.liveRunSignals,
    steering: runtime.runSteering,
  );
}

final class _RecordedModelRegistry extends ModelRegistry {
  _RecordedModelRegistry(ProductRuntime runtime, this.provider)
      : super(
          settings: runtime.settings,
          vault: runtime.secrets,
          redactor: runtime.redactor,
        );

  final LanguageModelProvider provider;

  @override
  List<LanguageModelProvider> providers() => <LanguageModelProvider>[provider];

  @override
  LanguageModelProvider providerFor(ModelIdentity identity) => provider;
}

final class _FlutterSmokeProvider implements LanguageModelProvider {
  _FlutterSmokeProvider(this.identity)
      : _actions = <String, List<Map<String, Object?>>>{
          'Inspect project and establish evidence baseline':
              <Map<String, Object?>>[
            <String, Object?>{
              'action': 'tool',
              'tool': 'list_directory',
              'arguments': <String, Object?>{
                'path': '.',
                'recursive': false,
                'maxEntries': 50,
              },
              'reason':
                  'Confirm that the selected app root has no application artifacts.',
            },
            <String, Object?>{
              'action': 'tool',
              'tool': 'inspect_file',
              'arguments': <String, Object?>{
                'path': '.kristin/blank-root-evidence.txt',
              },
              'reason':
                  'Hash the ignored Kristin metadata marker while the Flutter workspace remains semantically blank.',
            },
            <String, Object?>{
              'action': 'tool',
              'tool': 'index_project',
              'arguments': <String, Object?>{},
              'reason':
                  'Capture independent structural evidence for the semantically blank project root.',
            },
            <String, Object?>{
              'action': 'complete',
              'summary':
                  'The active app root contains no application artifacts and has independent hashed baseline evidence.',
            },
          ],
          'Implement requested product behavior': <Map<String, Object?>>[
            <String, Object?>{
              'action': 'tool',
              'tool': 'run_command',
              'arguments': <String, Object?>{
                'executable': 'flutter',
                'args': <String>[
                  'flutter',
                  'create',
                  'synthetic_app',
                  '--no-pub',
                ],
              },
              'reason':
                  'Scaffold Flutter through the finite command path; Runner must anchor it to the selected blank root.',
            },
            <String, Object?>{
              'action': 'tool',
              'tool': 'write_file',
              'arguments': <String, Object?>{
                'path': 'tool/repair_smoke.dart',
                'content': _repairSource,
              },
              'reason':
                  'Create a deterministic project-local repair script that removes generated pub dependencies.',
            },
            <String, Object?>{
              'action': 'tool',
              'tool': 'run_command',
              'arguments': <String, Object?>{
                'executable': 'dart',
                'args': <String>['dart', 'tool/repair_smoke.dart'],
              },
              'reason':
                  'Apply the deterministic SDK-only app and test fixture through finite process execution.',
            },
            <String, Object?>{
              'action': 'tool',
              'tool': 'run_command',
              'arguments': <String, Object?>{
                'executable': 'flutter',
                'args': <String>['pub', 'get', '--offline'],
              },
              'reason':
                  'Resolve only SDK dependencies from the local cache with network disabled.',
            },
            <String, Object?>{
              'action': 'tool',
              'tool': 'inspect_file',
              'arguments': <String, Object?>{'path': 'lib/main.dart'},
              'reason': 'Inspect the final Flutter application artifact.',
            },
            <String, Object?>{
              'action': 'complete',
              'summary':
                  'Flutter application exists in the active root with offline dependencies and inspected app source.',
            },
          ],
          'Verify acceptance criteria and repair defects':
              <Map<String, Object?>>[
            <String, Object?>{
              'action': 'tool',
              'tool': 'verify_project',
              'arguments': <String, Object?>{},
              'reason': 'Run the production Flutter analyzer and test profile.',
            },
            <String, Object?>{
              'action': 'complete',
              'summary': 'Flutter analyzer and tests passed.',
            },
          ],
        };

  static const String _repairSource = r"""
import 'dart:io';

void main() {
  final analysis = File('analysis_options.yaml');
  if (analysis.existsSync()) {
    analysis.deleteSync();
  }
  File('pubspec.yaml').writeAsStringSync('''
name: synthetic_app
description: Deterministic Kristin Runner smoke fixture.
publish_to: none
version: 1.0.0+1
environment:
  sdk: '>=3.5.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  flutter_test:
    sdk: flutter
flutter:
  uses-material-design: true
''');
  Directory('lib').createSync(recursive: true);
  File('lib/main.dart').writeAsStringSync(r'''
import 'package:flutter/material.dart';

void main() => runApp(const SmokeApp());

class SmokeApp extends StatelessWidget {
  const SmokeApp({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Kristin real Flutter smoke')),
        ),
      );
}
''');
  Directory('test').createSync(recursive: true);
  File('test/smoke_test.dart').writeAsStringSync(r'''
import 'package:flutter_test/flutter_test.dart';
import 'package:synthetic_app/main.dart';

void main() {
  testWidgets('renders deterministic smoke marker', (tester) async {
    await tester.pumpWidget(const SmokeApp());
    expect(find.text('Kristin real Flutter smoke'), findsOneWidget);
  });
}
''');
}
""";

  final ModelIdentity identity;
  final Map<String, List<Map<String, Object?>>> _actions;
  int readinessRequests = 0;
  int executionRequests = 0;

  @override
  String get id => 'recorded-flutter-smoke';

  @override
  Future<List<ModelIdentity>> discover() async => <ModelIdentity>[identity];

  @override
  Future<ModelGenerationResult> generate(ModelGenerationRequest request) async {
    final startedAt = DateTime.now().toUtc();
    String text;
    if (request.systemPrompt.contains('readiness probe')) {
      readinessRequests++;
      text = '{"status":"ready"}';
    } else {
      executionRequests++;
      final entry = _actions.entries.where(
        (candidate) => request.systemPrompt.contains(
          'Work item: ${candidate.key}',
        ),
      );
      if (entry.isEmpty) {
        throw StateError('No scripted action for current Flutter smoke item.');
      }
      final queue = entry.single.value;
      if (queue.isEmpty) {
        throw StateError(
          'Flutter smoke script exhausted for ${entry.single.key}.',
        );
      }
      text = jsonEncode(queue.removeAt(0));
    }
    request.reportTextDelta(text);
    final firstTokenAt = DateTime.now().toUtc();
    return ModelGenerationResult(
      text: text,
      identity: request.identity,
      startedAt: startedAt,
      firstTokenAt: firstTokenAt,
      completedAt: DateTime.now().toUtc(),
      inputTokens: 0,
      outputTokens: 0,
      providerDetails: const <String, Object?>{
        'provider': 'recorded-real-flutter-smoke',
        'network': false,
      },
    );
  }
}

final class ListEquality<T> {
  const ListEquality();

  bool equals(List<T> left, List<T> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
}
