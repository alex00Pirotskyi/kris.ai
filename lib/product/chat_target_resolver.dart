// Architectural Improvement #5: extensible target resolution.
//
// The final product may eventually support many more @ target types
// (a desktop/downloads filesystem location, a running terminal, a
// browser window, ...). Adding one should mean writing one new
// ChatTargetProvider and registering it in the resolver's provider list
// -- never touching a growing central switch that already knows about
// every other target type. This module intentionally implements only
// the target types the product already has real data for (project,
// model, provider, workspace/capability navigation); it does not invent
// new target types ahead of the capabilities that would use them.
import 'chat_control_plane.dart';
import 'domain.dart';

/// Produces the [ChatTarget]s for one target family (projects, models,
/// providers, ...). A future target type is a new implementation of this
/// interface, not a change to [ChatTargetResolver] or to any capability
/// switch.
abstract class ChatTargetProvider {
  List<ChatTarget> resolve();
}

/// Aggregates every registered [ChatTargetProvider] into the flat target
/// list the intent compiler and autocomplete engine already consume.
class ChatTargetResolver {
  const ChatTargetResolver(this.providers);

  final List<ChatTargetProvider> providers;

  List<ChatTarget> resolve() {
    final targets = <ChatTarget>[];
    for (final provider in providers) {
      targets.addAll(provider.resolve());
    }
    return List<ChatTarget>.unmodifiable(targets);
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

/// The provider families the product currently exposes for connection.
/// A newly-supported provider is one more entry in [knownProviderIds],
/// not a new code path.
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

/// The fixed set of advanced-workspace/system targets Chat can already
/// mention or open (Web Studio, public research, Owner Mode, the
/// Project Manager workspace). Unlike projects/models/providers these
/// are not data-driven -- they are a short, stable list.
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
