import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/chat_control_plane.dart';

void main() {
  const compiler = ChatIntentCompiler();
  const project = ChatTarget(
    id: 'project-alpha',
    type: ChatTargetType.project,
    displayName: 'Alpha',
    aliases: <String>['alpha'],
  );
  const model = ChatTarget(
    id: 'provider/alpha',
    type: ChatTargetType.model,
    displayName: 'Alpha',
    aliases: <String>['alpha'],
  );

  test('bare colliding alias is ambiguous instead of first-provider-wins', () {
    final result = compiler.compile(
      '@alpha',
      knownTargets: const <ChatTarget>[project, model],
    );
    expect(result.targets, isEmpty);
    expect(result.unresolvedMentions, contains('alpha'));
    expect(result.ambiguous, isTrue);
  });

  test('/run filters collision candidates to project targets', () {
    final result = compiler.compile(
      '/run @alpha',
      knownTargets: const <ChatTarget>[model, project],
    );
    expect(result.capability?.id, 'project.run');
    expect(result.targets.single.id, project.id);
    expect(result.unresolvedMentions, isEmpty);
  });

  test('/use filters collision candidates to model/provider targets', () {
    final result = compiler.compile(
      '/use @alpha',
      knownTargets: const <ChatTarget>[project, model],
    );
    expect(result.capability?.id, 'model.select');
    expect(result.targets.single.id, model.id);
    expect(result.unresolvedMentions, isEmpty);
  });

  test('same-type collisions still require clarification', () {
    const otherProject = ChatTarget(
      id: 'project-alpha-2',
      type: ChatTargetType.project,
      displayName: 'Alpha Two',
      aliases: <String>['alpha'],
    );
    final result = compiler.compile(
      '/run @alpha',
      knownTargets: const <ChatTarget>[project, otherProject],
    );
    expect(result.targets, isEmpty);
    expect(result.unresolvedMentions, contains('alpha'));
    expect(result.ambiguous, isTrue);
  });
}
