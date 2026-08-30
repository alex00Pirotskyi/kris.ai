import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/chat_control_plane.dart';
import 'package:kristin_local_agent/product/chat_target_resolver.dart';

void main() {
  test('colliding exact mention never resolves by provider order', () {
    const first = _StaticProvider(<ChatTarget>[
      ChatTarget(
        id: 'project-a',
        type: ChatTargetType.project,
        displayName: 'Alpha',
        aliases: <String>['shared'],
      ),
    ]);
    const second = _StaticProvider(<ChatTarget>[
      ChatTarget(
        id: 'model-b',
        type: ChatTargetType.model,
        displayName: 'Beta',
        aliases: <String>['shared'],
      ),
    ]);

    for (final providers in <List<ChatTargetProvider>>[
      <ChatTargetProvider>[first, second],
      <ChatTargetProvider>[second, first],
    ]) {
      final known = ChatTargetResolver(providers).resolve();
      final decision = const ChatIntentCompiler().compile(
        '@shared',
        knownTargets: known,
      );

      expect(decision.targets, isEmpty);
      expect(decision.unresolvedMentions, <String>['shared']);
      expect(decision.ambiguous, isTrue);
      expect(known.where((target) => target.fuzzyMatches('shared')), hasLength(2));
    }
  });
}

class _StaticProvider implements ChatTargetProvider {
  const _StaticProvider(this.targets);

  final List<ChatTarget> targets;

  @override
  List<ChatTarget> resolve() => targets;
}
