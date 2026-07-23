import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/planning_runtime.dart';
import 'package:kristin_local_agent/product/ui_components.dart';

void main() {
  test('all governed command modes remain available', () {
    expect(
      CommandMode.values.map((mode) => mode.name),
      containsAll(<String>[
        'ask',
        'analyze',
        'plan',
        'build',
        'fix',
        'review',
        'run',
      ]),
    );
  });

  test('simple studio exposes only four primary destinations', () {
    expect(studioDestinations.length, 4);
    expect(
      studioDestinations.map((destination) => destination.label),
      <String>['New task', 'Activity', 'Projects', 'Templates'],
    );
  });

  test('templates cover the first six common jobs', () {
    expect(studioTemplates.length, greaterThanOrEqualTo(6));
    expect(
      studioTemplates.map((template) => template.id),
      containsAll(<String>[
        'website',
        'telegram_bot',
        'application',
        'fix_project',
        'improve_project',
        'ask_code',
      ]),
    );
  });

  test('auto mode resolves common requests without exposing engine jargon', () {
    expect(inferCommandMode('Fix the failing login test'), CommandMode.fix);
    expect(inferCommandMode('Explain how this API works?'), CommandMode.ask);
    expect(inferCommandMode('Create a Telegram bot'), CommandMode.build);
    expect(inferCommandMode('Review this project'), CommandMode.review);
    expect(inferCommandMode('hello'), CommandMode.ask);
    expect(inferCommandMode('Hi!'), CommandMode.ask);
    expect(
      resolveTaskMode(
        request: 'anything',
        choice: SimpleTaskMode.planOnly,
        chosenMode: CommandMode.build,
      ),
      CommandMode.plan,
    );
  });
  test('conversational requests use a single no-tool plan', () {
    final prepared = const ContractPlanner().prepare(
      project: ProjectRecord(
        id: 'project-test',
        name: 'Test project',
        rootPath: '.',
        createdAt: DateTime.utc(2026, 7, 16),
        updatedAt: DateTime.utc(2026, 7, 16),
      ),
      mode: CommandMode.ask,
      request: 'hello',
      model: ModelIdentity(
        providerId: 'ollama',
        name: 'test-model',
        digest: 'digest',
        discoveredAt: DateTime.utc(2026, 7, 16),
      ),
    );

    expect(prepared.contract.revision, 2);
    expect(prepared.contract.requiredPermissions, isEmpty);
    expect(prepared.plan.items, hasLength(1));
    expect(prepared.plan.items.single.allowedTools, isEmpty);
    expect(prepared.plan.items.single.title.toLowerCase(), contains('convers'));
    expect(
      prepared.plan.items.any(
        (item) => item.title.startsWith('Inspect project'),
      ),
      isFalse,
    );
  });

  test('agent action parser accepts common local-model response shapes', () {
    final completion = AgentAction.fromJson(<String, dynamic>{
      'action': 'final',
      'answer': 'Hello from Kristin.',
    });
    expect(completion.kind, 'complete');
    expect(completion.summary, 'Hello from Kristin.');

    final functionCall = AgentAction.fromJson(<String, dynamic>{
      'type': 'function_call',
      'function': <String, dynamic>{
        'name': 'read_file',
        'arguments': '{"path":"README.md"}',
      },
    });
    expect(functionCall.kind, 'tool');
    expect(functionCall.tool, 'read_file');
    expect(functionCall.arguments['path'], 'README.md');

    final compactTool = AgentAction.fromJson(<String, dynamic>{
      'action': 'tool',
      'name': 'list_directory',
      'path': '.',
    });
    expect(compactTool.kind, 'tool');
    expect(compactTool.tool, 'list_directory');
    expect(compactTool.arguments['path'], '.');
  });

  test('v1.1 Project Manager version constants are available', () {
    expect(kristinVersion, '1.3.0+130');
    expect(kristinReleaseChannel, 'preview');
  });
}
