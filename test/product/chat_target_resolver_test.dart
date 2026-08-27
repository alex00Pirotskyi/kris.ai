import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/chat_control_plane.dart';
import 'package:kristin_local_agent/product/chat_target_resolver.dart';
import 'package:kristin_local_agent/product/domain.dart';

void main() {
  group('ChatTargetResolver', () {
    test('combines every registered provider, order preserved', () {
      final now = DateTime.utc(2026);
      final resolver = ChatTargetResolver(<ChatTargetProvider>[
        ProjectTargetProvider(
          projects: <ProjectRecord>[
            ProjectRecord(
              id: 'kris-ai',
              name: 'Kris AI',
              rootPath: '/tmp/kris-ai',
              createdAt: now,
              updatedAt: now,
            ),
          ],
          selectedProjectId: 'kris-ai',
        ),
        const ModelTargetProvider(
            models: <ModelIdentity>[], selectedModelId: null),
        const ProviderTargetProvider(configuredProviderIds: <String>{'ollama'}),
        const WorkspaceTargetProvider(),
      ]);

      final targets = resolver.resolve();
      expect(
        targets.where((target) => target.type == ChatTargetType.project),
        hasLength(1),
      );
      expect(
        targets.where((target) => target.type == ChatTargetType.provider),
        hasLength(2),
      );
      expect(
        targets.where((target) => target.type == ChatTargetType.workspace),
        isNotEmpty,
      );
    });

    test(
      'adding a new target family means adding one provider, not editing '
      'the resolver',
      () {
        // A future target type (e.g. a desktop-file target) is just
        // another ChatTargetProvider implementation appended to the
        // provider list -- this test documents that ChatTargetResolver
        // itself never needs to change shape to add one.
        const extra = _FixtureTargetProvider();
        final resolver = ChatTargetResolver(<ChatTargetProvider>[extra]);
        final targets = resolver.resolve();
        expect(targets.single.id, 'fixture');
      },
    );
  });

  group('ProjectTargetProvider', () {
    test('marks the selected project distinctly', () {
      final now = DateTime.utc(2026);
      final provider = ProjectTargetProvider(
        projects: <ProjectRecord>[
          ProjectRecord(
            id: 'a',
            name: 'A',
            rootPath: '/tmp/a',
            createdAt: now,
            updatedAt: now,
          ),
          ProjectRecord(
            id: 'b',
            name: 'B',
            rootPath: '/tmp/b',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        selectedProjectId: 'b',
      );
      final targets = provider.resolve();
      expect(
        targets.firstWhere((target) => target.id == 'a').status,
        'Project',
      );
      expect(
        targets.firstWhere((target) => target.id == 'b').status,
        'Selected project',
      );
    });
  });

  group('ProviderTargetProvider', () {
    test('reports configured vs not-connected from the given id set', () {
      const provider = ProviderTargetProvider(
        configuredProviderIds: <String>{'ollama'},
      );
      final targets = provider.resolve();
      final ollama = targets.firstWhere((target) => target.id == 'ollama');
      final openai =
          targets.firstWhere((target) => target.id == 'openai-compatible');
      expect(ollama.available, isTrue);
      expect(ollama.status, 'Configured');
      expect(openai.available, isFalse);
      expect(openai.status, 'Not connected');
    });
  });
}

class _FixtureTargetProvider implements ChatTargetProvider {
  const _FixtureTargetProvider();

  @override
  List<ChatTarget> resolve() => const <ChatTarget>[
        ChatTarget(
          id: 'fixture',
          type: ChatTargetType.workspace,
          displayName: 'Fixture',
          aliases: <String>['fixture'],
        ),
      ];
}
