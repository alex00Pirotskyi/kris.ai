// Architectural Improvement #5: extensible, collision-safe target resolution.
import 'chat_control_plane.dart';
import 'domain.dart';

abstract class ChatTargetProvider {
  List<ChatTarget> resolve();
}

/// Aggregates every registered target provider while protecting exact mention
/// resolution from provider-order collisions.
///
/// If two distinct targets advertise the same exact token (id, display name or
/// alias), that token is blocked on both candidates. The intent compiler then
/// sees the mention as unresolved instead of silently choosing whichever
/// provider happened to run first. Fuzzy autocomplete remains available, so the
/// user can still see and select a unique candidate token.
class ChatTargetResolver {
  const ChatTargetResolver(this.providers);

  final List<ChatTargetProvider> providers;

  List<ChatTarget> resolve() {
    final raw = <ChatTarget>[];
    for (final provider in providers) {
      raw.addAll(provider.resolve());
    }

    final ownersByToken = <String, Set<String>>{};
    for (final target in raw) {
      final identity = '${target.type.name}:${target.id}';
      for (final token in _exactTokens(target)) {
        ownersByToken.putIfAbsent(token, () => <String>{}).add(identity);
      }
    }
    final collisions = ownersByToken.entries
        .where((entry) => entry.value.length > 1)
        .map((entry) => entry.key)
        .toSet();
    if (collisions.isEmpty) {
      return List<ChatTarget>.unmodifiable(raw);
    }

    return List<ChatTarget>.unmodifiable(
      raw.map((target) {
        final blocked = _exactTokens(target).where(collisions.contains).toSet();
        if (blocked.isEmpty) return target;
        return _CollisionSafeChatTarget.from(target, blocked);
      }),
    );
  }

  static Set<String> _exactTokens(ChatTarget target) => <String>{
        chatTargetSlug(target.id),
        chatTargetSlug(target.displayName),
        ...target.aliases.map(chatTargetSlug),
      }..remove('');
}

class _CollisionSafeChatTarget extends ChatTarget {
  _CollisionSafeChatTarget.from(ChatTarget target, this.blockedTokens)
      : super(
          id: target.id,
          type: target.type,
          displayName: target.displayName,
          aliases: target.aliases,
          description: target.description,
          status: target.status,
          available: target.available,
        );

  final Set<String> blockedTokens;

  @override
  bool matches(String value) {
    if (blockedTokens.contains(chatTargetSlug(value))) return false;
    return super.matches(value);
  }
}

class ProjectTargetProvider implements ChatTargetProvider {
  const ProjectTargetProvider({
    required this.projects,
    required this.selectedProjectId,
  });

  final List<ProjectRecord> projects;
  final String? selectedProjectId;

  @override
  List<ChatTarget> resolve() => projects
      .map(
        (project) => ChatTarget(
          id: project.id,
          type: ChatTargetType.project,
          displayName: project.name,
          aliases: <String>[chatTargetSlug(project.name), project.id],
          description: 'Project',
          status:
              project.id == selectedProjectId ? 'Selected project' : 'Project',
        ),
      )
      .toList(growable: false);
}

class ModelTargetProvider implements ChatTargetProvider {
  const ModelTargetProvider({
    required this.models,
    required this.selectedModelId,
  });

  final List<ModelIdentity> models;
  final String? selectedModelId;

  @override
  List<ChatTarget> resolve() => models
      .map(
        (model) => ChatTarget(
          id: model.exactId,
          type: ChatTargetType.model,
          displayName: model.name,
          aliases: <String>[
            chatTargetSlug(model.name),
            model.name.toLowerCase(),
            model.exactId,
          ],
          description: model.providerId,
          status: model.exactId == selectedModelId
              ? 'Selected model'
              : 'Available model',
        ),
      )
      .toList(growable: false);
}

class ProviderTargetProvider implements ChatTargetProvider {
  const ProviderTargetProvider({required this.configuredProviderIds});

  final Set<String> configuredProviderIds;

  static const List<
      ({
        String id,
        String displayName,
        String description,
        List<String> aliases
      })> knownProviders = <({
    String id,
    String displayName,
    String description,
    List<String> aliases
  })>[
    (
      id: 'ollama',
      displayName: 'Ollama',
      description: 'Local model provider',
      aliases: <String>['ollama'],
    ),
    (
      id: 'openai-compatible',
      displayName: 'OpenAI-compatible',
      description: 'OpenAI-compatible model provider',
      aliases: <String>['openai', 'openai-compatible'],
    ),
  ];

  @override
  List<ChatTarget> resolve() => knownProviders
      .map(
        (provider) => ChatTarget(
          id: provider.id,
          type: ChatTargetType.provider,
          displayName: provider.displayName,
          aliases: provider.aliases,
          description: provider.description,
          status: configuredProviderIds.contains(provider.id)
              ? 'Configured'
              : 'Not connected',
          available: configuredProviderIds.contains(provider.id),
        ),
      )
      .toList(growable: false);
}

class WorkspaceTargetProvider implements ChatTargetProvider {
  const WorkspaceTargetProvider();

  @override
  List<ChatTarget> resolve() => const <ChatTarget>[
        ChatTarget(
          id: 'webstudio',
          type: ChatTargetType.workspace,
          displayName: 'Web Studio',
          aliases: <String>['webstudio'],
          description: 'Web deep-dive workspace',
        ),
        ChatTarget(
          id: 'web',
          type: ChatTargetType.workspace,
          displayName: 'Web',
          aliases: <String>['web'],
          description: 'Public-source research',
        ),
        ChatTarget(
          id: 'owner',
          type: ChatTargetType.capability,
          displayName: 'Owner Mode',
          aliases: <String>['owner'],
          description: 'Governed elevated execution mode',
        ),
        ChatTarget(
          id: 'project-manager',
          type: ChatTargetType.workspace,
          displayName: 'Project Manager',
          aliases: <String>['project-manager'],
          description: 'Persistent deep project controls',
        ),
      ];
}

String chatTargetSlug(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9._:-]+'), '-')
    .replaceAll(RegExp(r'-+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');
