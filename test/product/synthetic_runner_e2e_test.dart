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
  test(
    'blank project executes deterministic failure recovery through production Runner',
    () async {
      final sandbox = await Directory.systemTemp.createTemp(
        'kristin-synthetic-runner-e2e-',
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
      ).writeAsString('Semantically blank selected project.\n');

      final model = ModelIdentity(
        providerId: 'ollama',
        name: 'synthetic-runner',
        digest: 'sha256:synthetic-runner',
        discoveredAt: DateTime.utc(2026, 8, 24),
      );
      final provider = _ScriptedRunnerProvider(model);
      ProductRuntime? runtime;
      try {
        runtime = await ProductRuntime.initialize(dataRoot: dataRoot.path);
        final coordinator = _recordedCoordinator(runtime, provider);
        final project = await runtime.addProject(
          name: 'synthetic_app',
          rootPath: projectRoot.path,
        );
        final prepared = await runtime.prepare(
          projectId: project.id,
          mode: CommandMode.build,
          request: 'Build a synthetic app in the active project root. '
              'Create index.html containing "Kristin synthetic acceptance". '
              'Generate generated/result.txt from a finite command and verify the project.',
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
          final promptTail = provider.prompts.length <= 4
              ? provider.prompts
              : provider.prompts.sublist(provider.prompts.length - 4);
          stderr.writeln('SYNTHETIC_RUN_RECORD ${jsonEncode(run.toJson())}');
          stderr.writeln(
            'SYNTHETIC_RUN_EVIDENCE ${jsonEncode(diagnosticEvidence.map((item) => <String, dynamic>{
                  'kind': item.kind.name,
                  'payload': item.payload,
                }).toList(growable: false))}',
          );
          stderr.writeln('SYNTHETIC_RUN_AUDIT_TAIL ${jsonEncode(auditTail)}');
          stderr.writeln('SYNTHETIC_RUN_PROMPT_TAIL ${jsonEncode(promptTail)}');
        }

        expect(run.state.name, 'succeeded');
        expect(provider.readinessRequests, 1);
        expect(provider.executionRequests, lessThanOrEqualTo(13));
        expect(
          await File(
            '${projectRoot.path}${Platform.pathSeparator}index.html',
          ).readAsString(),
          contains('Kristin synthetic acceptance'),
        );
        expect(
          await File(
            '${projectRoot.path}${Platform.pathSeparator}generated'
            '${Platform.pathSeparator}result.txt',
          ).readAsString(),
          'Kristin synthetic acceptance\n',
        );
        expect(
          await Directory(
            '${projectRoot.path}${Platform.pathSeparator}synthetic_app',
          ).exists(),
          isFalse,
        );

        final evidence = await runtime.evidenceForRun(run.id);
        final commandEvidence = evidence
            .where((item) => item.payload['tool']?.toString() == 'run_command')
            .toList(growable: false);
        final failedCommands = commandEvidence
            .where((item) => item.payload['ok'] == false)
            .toList(growable: false);
        final successfulCommands = commandEvidence
            .where((item) => item.payload['ok'] == true)
            .toList(growable: false);

        expect(failedCommands, hasLength(2));
        expect(successfulCommands, hasLength(1));
        expect(successfulCommands.single.payload['mutated'], isTrue);
        final successfulData = Map<String, dynamic>.from(
          successfulCommands.single.payload['data']! as Map,
        );
        expect(successfulData['workingDirectory'], projectRoot.path);
        expect(
          successfulData['arguments'],
          orderedEquals(<String>['run', 'tool/generate.dart']),
        );
        final changedPaths =
            (successfulData['workspaceChanges'] as Map?)?['paths'];
        expect(changedPaths, isA<List>());
        expect(
          (changedPaths! as List).map((value) => value.toString()),
          containsAll(<String>['generated/result.txt', 'index.html']),
        );

        expect(
          evidence.any(
            (item) =>
                item.kind.name == 'verification' && item.payload['ok'] == true,
          ),
          isTrue,
        );
        expect(
          provider.prompts.any(
            (prompt) => prompt.contains('implementation_without_mutation'),
          ),
          isTrue,
        );
        final auditText = await runtime.repositories.auditFile.readAsString();
        expect(auditText, contains('tool.idempotency_replayed'));
        expect(
          auditText,
          contains('tool.run_command_workspace_delta_replayed'),
        );

        final durable = await runtime.getRun(run.id);
        expect(durable, isNotNull);
        expect(durable!.state.name, 'succeeded');
        expect(durable.mutations, greaterThanOrEqualTo(2));
      } finally {
        await runtime?.close();
        if (await sandbox.exists()) {
          await sandbox.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

RunCoordinator _recordedCoordinator(
  ProductRuntime runtime,
  _ScriptedRunnerProvider provider,
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
          commandId: 'synthetic-preflight',
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
        message: 'Recorded model provider is ready.',
        durationMilliseconds: stopwatch.elapsedMilliseconds,
      );
    },
    browserProbe: (requirement) async => RunCapabilityProbeResult(
      key: requirement.key,
      label: requirement.label,
      ok: false,
      required: requirement.required,
      message: 'Browser is intentionally unavailable in synthetic Runner E2E.',
      durationMilliseconds: 0,
    ),
    researchSearchProbe: (run, requirement) async => RunCapabilityProbeResult(
      key: requirement.key,
      label: requirement.label,
      ok: false,
      required: requirement.required,
      message: 'Research is intentionally unavailable in synthetic Runner E2E.',
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

final class _ScriptedRunnerProvider implements LanguageModelProvider {
  _ScriptedRunnerProvider(this.identity)
      : _actions = <String, List<Map<String, Object?>>>{
          'Inspect project and establish evidence baseline':
              <Map<String, Object?>>[
            <String, Object?>{
              'action': 'tool',
              'tool': 'inspect_file',
              'arguments': <String, Object?>{
                'path': '.kristin/blank-root-evidence.txt',
              },
              'reason':
                  'Hash the ignored Kristin metadata marker while the app workspace remains semantically blank.',
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
                'executable': 'dart',
                'args': <String>['run', 'tool/missing.dart'],
              },
              'reason': 'Exercise a deterministic failed command.',
            },
            <String, Object?>{
              'action': 'tool',
              'tool': 'run_command',
              'arguments': <String, Object?>{
                'executable': 'dart',
                'args': <String>['run', 'tool/missing.dart'],
              },
              'reason':
                  'Repeat the known failed branch; Runner must replay durable evidence.',
            },
            <String, Object?>{
              'action': 'tool',
              'tool': 'write_file',
              'arguments': <String, Object?>{
                'path': 'tool/generate.dart',
                'content': _generatorSource,
              },
              'reason':
                  'Prepare the deterministic fixture generator before testing completion.',
            },
            <String, Object?>{
              'action': 'complete',
              'summary':
                  'This must be rejected because the requested application artifacts have not been generated yet.',
            },
            <String, Object?>{
              'action': 'tool',
              'tool': 'run_command',
              'arguments': <String, Object?>{
                'executable': 'dart',
                'args': <String>['dart', 'run', 'tool/generate.dart'],
              },
              'reason':
                  'Run the fixture generator through finite command execution.',
            },
            <String, Object?>{
              'action': 'tool',
              'tool': 'inspect_file',
              'arguments': <String, Object?>{'path': 'index.html'},
              'reason': 'Inspect the acceptance artifact.',
            },
            <String, Object?>{
              'action': 'complete',
              'summary':
                  'Synthetic project created and inspected in the active root.',
            },
          ],
          'Verify acceptance criteria and repair defects':
              <Map<String, Object?>>[
            <String, Object?>{
              'action': 'tool',
              'tool': 'verify_project',
              'arguments': <String, Object?>{},
              'reason': 'Objectively verify the generated static project.',
            },
            <String, Object?>{
              'action': 'complete',
              'summary': 'Objective project verification passed.',
            },
          ],
        };

  static const String _generatorSource = '''
import 'dart:io';

void main() {
  Directory('generated').createSync(recursive: true);
  File('generated/result.txt').writeAsStringSync(
    'Kristin synthetic acceptance\\n',
  );
  File('index.html').writeAsStringSync("""
<!doctype html>
<html>
<body>
  <p>Kristin synthetic acceptance</p>
  <button id="counter" onclick="this.textContent = String(Number(this.textContent) + 1)">0</button>
</body>
</html>
""");
}
''';

  final ModelIdentity identity;
  final Map<String, List<Map<String, Object?>>> _actions;
  int readinessRequests = 0;
  int executionRequests = 0;
  final List<String> prompts = <String>[];

  @override
  String get id => 'recorded';

  @override
  Future<List<ModelIdentity>> discover() async => <ModelIdentity>[identity];

  @override
  LanguageModelProvider providerFor(ModelIdentity identity) => this;

  @override
  Future<ModelGenerationResult> generate(ModelGenerationRequest request) async {
    final startedAt = DateTime.now().toUtc();
    String text;
    if (request.systemPrompt.contains('readiness probe')) {
      readinessRequests++;
      text = '{"status":"ready"}';
    } else {
      executionRequests++;
      prompts.add(request.userPrompt);
      final entry = _actions.entries.where(
        (candidate) => request.systemPrompt.contains(
          'Work item: ${candidate.key}',
        ),
      );
      if (entry.isEmpty) {
        throw StateError('No scripted actions for current work item.');
      }
      final queue = entry.single.value;
      if (queue.isEmpty) {
        throw StateError('Script exhausted for ${entry.single.key}.');
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
      providerDetails: const <String, dynamic>{
        'provider': 'recorded-synthetic',
        'network': false,
      },
    );
  }
}
