import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/conversation_orchestrator.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/run_execution_projection.dart';
import 'package:kristin_local_agent/product/run_live_signals.dart';
import 'package:kristin_local_agent/product/run_preflight.dart';
import 'package:kristin_local_agent/product/run_steering.dart';
import 'package:kristin_local_agent/product/storage_security.dart';

void main() {
  test('conversation orchestrator keeps hello on the fast chat path', () {
    const orchestrator = ConversationOrchestrator();
    final intent = orchestrator.classify('hello', CommandMode.ask);
    expect(intent.kind, ConversationIntentKind.conversation);
    expect(intent.needsClarification, isFalse);
    expect(intent.projectMayBeProvisioned, isFalse);
  });

  test('conversation stream projector hides protocol JSON while streaming', () {
    expect(
      ConversationStreamProjector.visibleText(
        '{"protocolVersion":"1.0.0","action":"complete","summary":"Hel',
      ),
      'Hel',
    );
    expect(
      ConversationStreamProjector.visibleText(
        '{"action":"complete","summary":"Hello\\nthere"}',
      ),
      'Hello\nthere',
    );
    expect(
      ConversationStreamProjector.visibleText('Hello directly'),
      'Hello directly',
    );
  });

  test('underspecified build naturally requests clarification', () {
    const orchestrator = ConversationOrchestrator();
    final intent = orchestrator.classify('build me an app', CommandMode.build);
    expect(intent.kind, ConversationIntentKind.buildNewProject);
    expect(intent.needsClarification, isTrue);
    expect(intent.projectMayBeProvisioned, isTrue);
  });

  test('specific Flutter build can proceed directly', () {
    const orchestrator = ConversationOrchestrator();
    final intent = orchestrator.classify(
      'Build a polished Flutter web converter app with no login, local state, responsive UI, and drag and drop.',
      CommandMode.build,
    );
    expect(intent.kind, ConversationIntentKind.buildNewProject);
    expect(intent.needsClarification, isFalse);
  });

  test('live signal bus preserves order and run filtering', () async {
    final bus = LiveRunSignalBus();
    addTearDown(bus.close);
    final received = <LiveRunSignal>[];
    final subscription = bus.forRun('run-a').listen(received.add);
    addTearDown(subscription.cancel);
    bus.publish(LiveRunSignal.phase(runId: 'run-a', phase: 'preflight'));
    bus.publish(LiveRunSignal.phase(runId: 'run-b', phase: 'execution'));
    bus.publish(LiveRunSignal.phase(runId: 'run-a', phase: 'execution'));
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(2));
    expect(received[0].sequence, lessThan(received[1].sequence));
  });

  test('steering is queued then consumed exactly once', () async {
    final bus = LiveRunSignalBus();
    addTearDown(bus.close);
    final steering = RunSteeringService(liveSignals: bus);
    final queued = steering.queue('run-a', 'keep everything local');
    expect(queued.text, 'keep everything local');
    final first = steering.takePending('run-a');
    final second = steering.takePending('run-a');
    expect(first, hasLength(1));
    expect(second, isEmpty);
  });

  test('capability resolver does not infer browser from web-app wording', () {
    const resolver = RunCapabilityResolver();
    final command = _command(
      request: 'Build a Flutter web app',
      mode: CommandMode.build,
    );
    final requirements = resolver.resolve(command);
    final keys = requirements.map((item) => item.key).toSet();
    expect(keys, contains('exec-flutter'));
    expect(keys, contains('exec-dart'));
    expect(keys, isNot(contains('browser')));
  });

  test('capability resolver requires browser only when the plan uses it', () {
    const resolver = RunCapabilityResolver();
    final command = _command(
      request: 'Validate the generated experience',
      mode: CommandMode.build,
      allowedTools: const <String>{
        'read_file',
        'write_file',
        'browser_navigate',
      },
    );
    final browser = resolver
        .resolve(command)
        .where((requirement) => requirement.key == 'browser')
        .single;
    expect(browser.required, isTrue);
    expect(browser.kind, RunCapabilityKind.browser);
  });

  test('capability resolver does not probe Flutter for hello', () {
    const resolver = RunCapabilityResolver();
    final command = _command(request: 'hello', mode: CommandMode.ask);
    final keys = resolver.resolve(command).map((item) => item.key).toSet();
    expect(keys, contains('model'));
    expect(keys, isNot(contains('exec-flutter')));
    expect(keys, isNot(contains('browser')));
  });

  test(
    'preflight blocks a required missing executable before execution',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'kristin-preflight-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final project = ProjectRecord(
        id: 'project',
        name: 'test',
        rootPath: root.path,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      final command = _command(
        request: 'Build a Flutter web app',
        mode: CommandMode.build,
      );
      final run = RunRecord(
        id: 'run',
        command: command,
        state: RunState.prepared,
        items: command.plan.items
            .map(
              (item) => WorkItemProgress(
                item: item,
                state: WorkItemState.queued,
                attempts: 0,
              ),
            )
            .toList(),
        budget: const AutonomyBudget(),
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      final service = RunPreflightService(
        resolver: const _MissingExecutableResolver(),
        modelProbe: (model, requirement) async => RunCapabilityProbeResult(
          key: requirement.key,
          label: requirement.label,
          ok: true,
          required: requirement.required,
          message: 'ready',
          durationMilliseconds: 1,
        ),
        browserProbe: (requirement) async => RunCapabilityProbeResult(
          key: requirement.key,
          label: requirement.label,
          ok: true,
          required: requirement.required,
          message: 'ready',
          durationMilliseconds: 1,
        ),
        researchSearchProbe: (run, requirement) async =>
            RunCapabilityProbeResult(
              key: requirement.key,
              label: requirement.label,
              ok: true,
              required: requirement.required,
              message: 'ready',
              durationMilliseconds: 1,
            ),
        settingsProvider: () =>
            const ProductSettings(localOnly: false, allowPackageNetwork: true),
      );
      final receipt = await service.check(run: run, project: project);
      expect(receipt.verdict, RunPreflightVerdict.blocked);
      expect(receipt.blockingFailures, isNotEmpty);
    },
  );

  test('research plans require a real search-provider capability', () {
    const resolver = RunCapabilityResolver();
    final command = _command(
      request: 'Research the current Flutter web documentation',
      mode: CommandMode.ask,
      allowedTools: const <String>{'research_search', 'research_fetch'},
      requiredPermissions: const <PermissionScope>{
        PermissionScope.networkResearch,
        PermissionScope.secretUse,
      },
    );
    final keys = resolver.resolve(command).map((item) => item.key).toSet();
    expect(keys, contains('research-search'));
    expect(keys, contains('research-network'));
  });

  test('local-only mode blocks required web search before execution', () async {
    final root = await Directory.systemTemp.createTemp(
      'kristin-search-preflight-',
    );
    addTearDown(() => root.delete(recursive: true));
    final project = ProjectRecord(
      id: 'project',
      name: 'test',
      rootPath: root.path,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    final command = _command(
      request: 'Research current Flutter docs',
      mode: CommandMode.ask,
      allowedTools: const <String>{'research_search'},
      requiredPermissions: const <PermissionScope>{
        PermissionScope.networkResearch,
        PermissionScope.secretUse,
      },
    );
    final run = RunRecord(
      id: 'run',
      command: command,
      state: RunState.prepared,
      items: command.plan.items
          .map(
            (item) => WorkItemProgress(
              item: item,
              state: WorkItemState.queued,
              attempts: 0,
            ),
          )
          .toList(),
      budget: const AutonomyBudget(),
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    var searchProbeCalled = false;
    final service = RunPreflightService(
      resolver: const RunCapabilityResolver(),
      modelProbe: (model, requirement) async => RunCapabilityProbeResult(
        key: requirement.key,
        label: requirement.label,
        ok: true,
        required: requirement.required,
        message: 'ready',
        durationMilliseconds: 1,
      ),
      browserProbe: (requirement) async => RunCapabilityProbeResult(
        key: requirement.key,
        label: requirement.label,
        ok: true,
        required: requirement.required,
        message: 'ready',
        durationMilliseconds: 1,
      ),
      researchSearchProbe: (run, requirement) async {
        searchProbeCalled = true;
        return RunCapabilityProbeResult(
          key: requirement.key,
          label: requirement.label,
          ok: true,
          required: requirement.required,
          message: 'ready',
          durationMilliseconds: 1,
        );
      },
      settingsProvider: () => const ProductSettings(localOnly: true),
    );
    final receipt = await service.check(run: run, project: project);
    expect(receipt.verdict, RunPreflightVerdict.blocked);
    expect(searchProbeCalled, isFalse);
  });

  test('manual task deserialization gives blank checkpoints a name', () {
    final task = PlanTaskRecord.fromJson(const <String, dynamic>{
      'id': 'manual-task',
      'title': '   ',
      'instructions': 'Wait for explicit user approval.',
      'manual': true,
    });
    expect(task.title, 'Manual checkpoint');
    expect(task.manual, isTrue);
  });

  test('blank non-manual task titles remain invalid', () {
    final task = PlanTaskRecord.fromJson(const <String, dynamic>{
      'id': 'non-manual-task',
      'title': '   ',
      'manual': false,
    });
    expect(task.title.trim(), isEmpty);
  });

  test('awaiting approval chat card is actionable and recovery-safe', () {
    final chatSource = File('lib/product/chat_studio.dart').readAsStringSync();
    final presentationSource = File(
      'lib/product/ui_components.dart',
    ).readAsStringSync();

    expect(
      presentationSource,
      contains("RunState.awaitingApproval => 'Approval required to continue'"),
    );
    expect(
      chatSource,
      contains("key: const Key('chat-run-approval-guidance')"),
    );
    expect(chatSource, contains("key: const Key('chat-run-approve-continue')"));
    expect(chatSource, contains("label: const Text('Review & continue')"));
    expect(chatSource, contains("'Starts after approval'"));
    expect(
      chatSource,
      contains('Nothing will execute until you approve this run.'),
    );
    expect(
      chatSource,
      contains(
        'approvedScopes.addAll(run.command.contract.requiredPermissions);',
      ),
    );
    expect(
      RegExp(r"liveAssistantProtocolText = '';").allMatches(chatSource).length,
      greaterThanOrEqualTo(5),
    );
  });

  test('timeline projection keeps durable and live activity together', () {
    final event = EventEnvelope(
      sequence: 1,
      id: 'event',
      type: 'run.preflight_started',
      correlationId: 'run',
      timestamp: DateTime.utc(2026, 8, 23, 1),
      data: const <String, dynamic>{'runId': 'run'},
    );
    final live = LiveRunSignal(
      sequence: 2,
      runId: 'run',
      kind: LiveRunSignalKind.modelProgress,
      timestamp: DateTime.utc(2026, 8, 23, 1, 0, 1),
      data: const <String, dynamic>{'message': 'Generating'},
    );
    final entries = RunExecutionProjection.merge(
      events: <EventEnvelope>[event],
      liveSignals: <LiveRunSignal>[live],
    );
    expect(entries, hasLength(2));
    expect(entries.first.category, RunTimelineCategory.preflight);
    expect(entries.last.category, RunTimelineCategory.model);
  });
}

class _MissingExecutableResolver extends RunCapabilityResolver {
  const _MissingExecutableResolver();

  @override
  List<RunCapabilityRequirement> resolve(PreparedCommand command) =>
      const <RunCapabilityRequirement>[
        RunCapabilityRequirement(
          key: 'exec-kristin-definitely-missing',
          label: 'missing executable',
          kind: RunCapabilityKind.executable,
          required: true,
          executable: 'kristin-definitely-missing-executable-xyz',
        ),
      ];
}

PreparedCommand _command({
  required String request,
  required CommandMode mode,
  Set<String>? allowedTools,
  Set<PermissionScope>? requiredPermissions,
}) {
  final model = ModelIdentity(
    providerId: 'ollama',
    name: 'phi4-mini:latest',
    digest: 'digest',
    discoveredAt: DateTime.utc(2026, 8, 23),
  );
  final contract = TaskContract(
    id: 'contract',
    revision: 2,
    projectId: 'project',
    mode: mode,
    request: request,
    acceptanceCriteria: <AcceptanceCriterion>[
      const AcceptanceCriterion(
        id: 'criterion',
        statement: 'The requested result is created and verified.',
        verification: 'Verify with a direct test.',
      ),
    ],
    constraints: const <String>[],
    researchQuestions: const <String>[],
    requiredPermissions:
        requiredPermissions ??
        (mode == CommandMode.build
            ? const <PermissionScope>{
                PermissionScope.projectRead,
                PermissionScope.projectWrite,
              }
            : const <PermissionScope>{}),
    createdAt: DateTime.utc(2026, 8, 23),
  );
  final item = WorkItem(
    id: 'work',
    title: 'Work',
    description: 'Complete the requested work.',
    dependencies: const <String>{},
    allowedTools:
        allowedTools ??
        (mode == CommandMode.ask
            ? const <String>{}
            : const <String>{'read_file', 'write_file', 'git_status'}),
    acceptanceCriteria: const <String>['Result is verified.'],
    maxAttempts: 2,
  );
  return PreparedCommand(
    id: 'command',
    requestKey: 'request-key',
    contract: contract,
    plan: ExecutionPlan(
      id: 'plan',
      contractId: contract.id,
      complexity: 2,
      rationale: 'test',
      items: <WorkItem>[item],
      createdAt: DateTime.utc(2026, 8, 23),
    ),
    model: model,
    createdAt: DateTime.utc(2026, 8, 23),
  );
}
