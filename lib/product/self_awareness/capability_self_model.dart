import 'dart:convert';

import '../chat_control_plane.dart';

enum CapabilityRiskClass { none, readOnly, execution, mutation, sensitive, destructive }

enum CapabilityAvailabilityState {
  available,
  unavailable,
  blocked,
  prerequisiteMissing,
  projectRequired,
  modelProviderMissing,
  runtimeMissing,
  browserUnavailable,
  ownerAuthorityUnavailable,
  approvalRequired,
  additionalAuthorityRequired,
  degraded,
  temporarilyUnavailable,
  unsupportedPlatform,
}

enum CapabilityAuthorityClass { none, governed, owner, explicitApproval }

/// Canonical, model-readable description of a Kristin capability.
///
/// A descriptor says what exists. It does not say that the capability is
/// currently usable and, critically, it never grants execution authority.
final class CapabilityDescriptor {
  const CapabilityDescriptor({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.semanticPurpose = '',
    this.whenToUse = const <String>[],
    this.whenNotToUse = const <String>[],
    this.acceptedTargets = const <String>{},
    this.expectedInputs = const <String, String>{},
    this.outputs = const <String, String>{},
    this.sideEffects = const <String>[],
    this.riskClass = CapabilityRiskClass.none,
    this.readOnly = true,
    this.mutatesApplicationState = false,
    this.mutatesProjectState = false,
    this.mutatesHostState = false,
    this.authorityClass = CapabilityAuthorityClass.governed,
    this.permissionRequirements = const <String>{},
    this.networkRequired = false,
    this.filesystemRequired = false,
    this.processRequired = false,
    this.browserRequired = false,
    this.projectRequired = false,
    this.modelProviderRequired = false,
    this.dependencies = const <String>{},
    this.limitations = const <String>[],
    this.unsupportedConditions = const <String>[],
    this.recoverability = const <String>[],
    this.coordinator = false,
    this.directlyExecutable = false,
    this.recoveryParticipant = false,
    this.usageHints = const <String>[],
    this.providerId = 'unknown',
    this.schemaVersion = 1,
  });

  final String id;
  final String name;
  final String description;
  final String semanticPurpose;
  final String category;
  final List<String> whenToUse;
  final List<String> whenNotToUse;
  final Set<String> acceptedTargets;
  final Map<String, String> expectedInputs;
  final Map<String, String> outputs;
  final List<String> sideEffects;
  final CapabilityRiskClass riskClass;
  final bool readOnly;
  final bool mutatesApplicationState;
  final bool mutatesProjectState;
  final bool mutatesHostState;
  final CapabilityAuthorityClass authorityClass;
  final Set<String> permissionRequirements;
  final bool networkRequired;
  final bool filesystemRequired;
  final bool processRequired;
  final bool browserRequired;
  final bool projectRequired;
  final bool modelProviderRequired;
  final Set<String> dependencies;
  final List<String> limitations;
  final List<String> unsupportedConditions;
  final List<String> recoverability;
  final bool coordinator;
  final bool directlyExecutable;
  final bool recoveryParticipant;
  final List<String> usageHints;
  final String providerId;
  final int schemaVersion;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'description': description,
        if (semanticPurpose.isNotEmpty) 'semanticPurpose': semanticPurpose,
        'category': category,
        'whenToUse': whenToUse,
        'whenNotToUse': whenNotToUse,
        'acceptedTargets': acceptedTargets.toList()..sort(),
        'expectedInputs': expectedInputs,
        'outputs': outputs,
        'sideEffects': sideEffects,
        'riskClass': riskClass.name,
        'readOnly': readOnly,
        'mutatesApplicationState': mutatesApplicationState,
        'mutatesProjectState': mutatesProjectState,
        'mutatesHostState': mutatesHostState,
        'authorityClass': authorityClass.name,
        'permissionRequirements': permissionRequirements.toList()..sort(),
        'requirements': <String, bool>{
          'network': networkRequired,
          'filesystem': filesystemRequired,
          'process': processRequired,
          'browser': browserRequired,
          'project': projectRequired,
          'modelProvider': modelProviderRequired,
        },
        'dependencies': dependencies.toList()..sort(),
        'limitations': limitations,
        'unsupportedConditions': unsupportedConditions,
        'recoverability': recoverability,
        'coordinator': coordinator,
        'directlyExecutable': directlyExecutable,
        'recoveryParticipant': recoveryParticipant,
        'usageHints': usageHints,
        'providerId': providerId,
        'schemaVersion': schemaVersion,
      };
}

final class CapabilityAvailability {
  const CapabilityAvailability({
    required this.capabilityId,
    required this.state,
    this.reasons = const <String>[],
    this.missingPrerequisites = const <String>{},
    this.requiredAuthority = const <String>{},
    this.currentAuthority = const <String>{},
    this.retryAfter,
    this.observedAt,
  });

  final String capabilityId;
  final CapabilityAvailabilityState state;
  final List<String> reasons;
  final Set<String> missingPrerequisites;
  final Set<String> requiredAuthority;
  final Set<String> currentAuthority;
  final DateTime? retryAfter;
  final DateTime? observedAt;

  bool get usableNow => state == CapabilityAvailabilityState.available ||
      state == CapabilityAvailabilityState.degraded;
  bool get knownButAuthorityBlocked =>
      state == CapabilityAvailabilityState.approvalRequired ||
      state == CapabilityAvailabilityState.additionalAuthorityRequired ||
      state == CapabilityAvailabilityState.ownerAuthorityUnavailable;

  Map<String, Object?> toJson() => <String, Object?>{
        'capabilityId': capabilityId,
        'state': state.name,
        'usableNow': usableNow,
        'reasons': reasons,
        'missingPrerequisites': missingPrerequisites.toList()..sort(),
        'requiredAuthority': requiredAuthority.toList()..sort(),
        'currentAuthority': currentAuthority.toList()..sort(),
        if (retryAfter != null) 'retryAfter': retryAfter!.toIso8601String(),
        if (observedAt != null) 'observedAt': observedAt!.toIso8601String(),
      };
}

final class KnownCapability {
  const KnownCapability({required this.descriptor, required this.availability});
  final CapabilityDescriptor descriptor;
  final CapabilityAvailability availability;
  Map<String, Object?> toJson() => <String, Object?>{
        'descriptor': descriptor.toJson(),
        'availability': availability.toJson(),
      };
}

/// Bounded runtime state assembled from authoritative product/domain services.
final class ApplicationSnapshot {
  const ApplicationSnapshot({
    required this.capturedAt,
    required this.applicationIdentity,
    required this.platform,
    this.build = const <String, Object?>{},
    this.health = const <String, Object?>{},
    this.selectedProject,
    this.knownProjects = const <Map<String, Object?>>[],
    this.selectedModel,
    this.availableModels = const <Map<String, Object?>>[],
    this.providers = const <Map<String, Object?>>[],
    this.runState = const <String, Object?>{},
    this.authority = const <String, Object?>{},
    this.ownerMode = const <String, Object?>{},
    this.processes = const <Map<String, Object?>>[],
    this.browser = const <String, Object?>{},
    this.research = const <String, Object?>{},
    this.dependencies = const <Map<String, Object?>>[],
    this.recentFailures = const <Map<String, Object?>>[],
    this.recentActions = const <Map<String, Object?>>[],
  });

  final DateTime capturedAt;
  final String applicationIdentity;
  final String platform;
  final Map<String, Object?> build;
  final Map<String, Object?> health;
  final Map<String, Object?>? selectedProject;
  final List<Map<String, Object?>> knownProjects;
  final Map<String, Object?>? selectedModel;
  final List<Map<String, Object?>> availableModels;
  final List<Map<String, Object?>> providers;
  final Map<String, Object?> runState;
  final Map<String, Object?> authority;
  final Map<String, Object?> ownerMode;
  final List<Map<String, Object?>> processes;
  final Map<String, Object?> browser;
  final Map<String, Object?> research;
  final List<Map<String, Object?>> dependencies;
  final List<Map<String, Object?>> recentFailures;
  final List<Map<String, Object?>> recentActions;

  Map<String, Object?> toJson() => <String, Object?>{
        'capturedAt': capturedAt.toIso8601String(),
        'applicationIdentity': applicationIdentity,
        'platform': platform,
        'build': build,
        'health': health,
        if (selectedProject != null) 'selectedProject': selectedProject,
        'knownProjects': knownProjects,
        if (selectedModel != null) 'selectedModel': selectedModel,
        'availableModels': availableModels,
        'providers': providers,
        'runState': runState,
        'authority': authority,
        'ownerMode': ownerMode,
        'processes': processes,
        'browser': browser,
        'research': research,
        'dependencies': dependencies,
        'recentFailures': recentFailures,
        'recentActions': recentActions,
      };
}

abstract interface class ApplicationSnapshotProvider {
  Future<ApplicationSnapshot> capture();
}

/// Provider-owned capability registration seam. New subsystems register their
/// provider here instead of extending a central switch/catalog.
abstract interface class KristinCapabilityProvider {
  String get providerId;
  Iterable<CapabilityDescriptor> describeCapabilities();
  Future<CapabilityAvailability> resolveAvailability(
    CapabilityDescriptor descriptor,
    ApplicationSnapshot snapshot,
  );
}

final class KristinCapabilityRegistry {
  final Map<String, KristinCapabilityProvider> _providers =
      <String, KristinCapabilityProvider>{};

  void register(KristinCapabilityProvider provider) {
    if (_providers.containsKey(provider.providerId)) {
      throw StateError('duplicate_capability_provider:${provider.providerId}');
    }
    _providers[provider.providerId] = provider;
  }

  void unregister(String providerId) => _providers.remove(providerId);
  Iterable<KristinCapabilityProvider> get providers => _providers.values;
}

/// Adapter for the existing Chat capability registry. This is intentionally a
/// provider, not the final self model: subsystem-specific providers can add
/// richer runtime-owned capabilities without growing one global switch.
final class ChatCapabilityProvider implements KristinCapabilityProvider {
  const ChatCapabilityProvider({
    required this.availabilityResolver,
    this.capabilities = kKristinCapabilities,
  });

  final List<KristinCapability> capabilities;
  final Future<CapabilityAvailability> Function(
    KristinCapability capability,
    CapabilityDescriptor descriptor,
    ApplicationSnapshot snapshot,
  ) availabilityResolver;

  @override
  String get providerId => 'chat.registry';

  @override
  Iterable<CapabilityDescriptor> describeCapabilities() => capabilities.map((c) {
        final mutating = c.riskClass == ChatRiskClass.mutation ||
            c.riskClass == ChatRiskClass.destructive;
        return CapabilityDescriptor(
          id: c.id,
          name: c.displayName,
          description: c.description,
          semanticPurpose: c.description,
          category: c.category.name,
          acceptedTargets: c.acceptedTargetTypes.map((e) => e.name).toSet(),
          riskClass: CapabilityRiskClass.values.firstWhere(
            (v) => v.name == c.riskClass.name,
            orElse: () => CapabilityRiskClass.none,
          ),
          readOnly: !mutating && c.riskClass != ChatRiskClass.execution,
          mutatesProjectState: mutating,
          coordinator: c.isCoordinatorCapability,
          directlyExecutable: !c.isCoordinatorCapability,
          projectRequired: !c.availableWithoutTarget &&
              c.acceptedTargetTypes.contains(ChatTargetType.project),
          modelProviderRequired: c.actionClass == ChatActionClass.substantial,
          authorityClass: c.riskClass == ChatRiskClass.sensitive ||
                  c.riskClass == ChatRiskClass.destructive
              ? CapabilityAuthorityClass.explicitApproval
              : CapabilityAuthorityClass.governed,
          providerId: providerId,
        );
      });

  @override
  Future<CapabilityAvailability> resolveAvailability(
    CapabilityDescriptor descriptor,
    ApplicationSnapshot snapshot,
  ) {
    final capability = capabilities.firstWhere((c) => c.id == descriptor.id);
    return availabilityResolver(capability, descriptor, snapshot);
  }
}

/// Immutable, bounded self-model result used by Chat and planning.
final class KristinSelfSnapshot {
  const KristinSelfSnapshot({
    required this.application,
    required this.capabilities,
  });

  final ApplicationSnapshot application;
  final List<KnownCapability> capabilities;

  Iterable<KnownCapability> get available =>
      capabilities.where((c) => c.availability.usableNow);
  Iterable<KnownCapability> get blocked =>
      capabilities.where((c) => !c.availability.usableNow);

  KnownCapability? capability(String id) {
    for (final item in capabilities) {
      if (item.descriptor.id == id) return item;
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': 1,
        'identity': 'Kristin, the governed AI operating kris.ai',
        'application': application.toJson(),
        'capabilities': capabilities.map((c) => c.toJson()).toList(),
      };
}

/// Compact planning projection. This is knowledge only; [allowedRunnerTools]
/// remains the executor-specific allow-list and is never derived from known
/// coordinator capabilities.
final class SelfModelPlanningContext {
  const SelfModelPlanningContext({
    required this.summary,
    required this.availableCapabilityIds,
    required this.blockedCapabilityReasons,
    required this.currentAuthority,
    required this.relevantCapabilities,
  });

  final String summary;
  final Set<String> availableCapabilityIds;
  final Map<String, String> blockedCapabilityReasons;
  final Set<String> currentAuthority;
  final List<Map<String, Object?>> relevantCapabilities;

  Map<String, Object?> toJson() => <String, Object?>{
        'summary': summary,
        'availableCapabilityIds': availableCapabilityIds.toList()..sort(),
        'blockedCapabilityReasons': blockedCapabilityReasons,
        'currentAuthority': currentAuthority.toList()..sort(),
        'relevantCapabilities': relevantCapabilities,
      };
}

final class KristinSelfModelService {
  KristinSelfModelService({
    required this.registry,
    required this.application,
    this.maxDetailedCapabilities = 12,
  });

  final KristinCapabilityRegistry registry;
  final ApplicationSnapshotProvider application;
  final int maxDetailedCapabilities;

  Future<KristinSelfSnapshot> snapshot() async {
    final app = await application.capture();
    final resolved = <KnownCapability>[];
    final ids = <String>{};
    for (final provider in registry.providers) {
      for (final descriptor in provider.describeCapabilities()) {
        if (!ids.add(descriptor.id)) {
          throw StateError('duplicate_capability_id:${descriptor.id}');
        }
        final availability =
            await provider.resolveAvailability(descriptor, app);
        resolved.add(KnownCapability(
          descriptor: descriptor,
          availability: availability,
        ));
      }
    }
    resolved.sort((a, b) => a.descriptor.id.compareTo(b.descriptor.id));
    return KristinSelfSnapshot(application: app, capabilities: resolved);
  }

  Future<KnownCapability?> capability(String id) async =>
      (await snapshot()).capability(id);

  Future<String> explainAvailability(String id) async {
    final item = await capability(id);
    if (item == null) return 'Kristin does not currently know a capability named $id.';
    final state = item.availability;
    if (state.usableNow) return '$id is ${state.state.name}.';
    final why = state.reasons.isEmpty ? 'No additional reason was reported.' : state.reasons.join(' ');
    return '$id is ${state.state.name}. $why';
  }

  Future<SelfModelPlanningContext> planningContext({
    Set<String> relevantCapabilityIds = const <String>{},
  }) async {
    final self = await snapshot();
    final available = self.available.map((c) => c.descriptor.id).toSet();
    final blocked = <String, String>{};
    for (final item in self.blocked) {
      blocked[item.descriptor.id] = item.availability.reasons.join(' ');
    }
    final relevant = self.capabilities.where((item) {
      return relevantCapabilityIds.isEmpty ||
          relevantCapabilityIds.contains(item.descriptor.id);
    }).take(maxDetailedCapabilities).map((item) => item.toJson()).toList();
    final authority = <String>{};
    final rawAuthority = self.application.authority['granted'];
    if (rawAuthority is Iterable) authority.addAll(rawAuthority.map((e) => e.toString()));
    return SelfModelPlanningContext(
      summary: renderSummary(self),
      availableCapabilityIds: available,
      blockedCapabilityReasons: blocked,
      currentAuthority: authority,
      relevantCapabilities: relevant,
    );
  }

  String renderSummary(KristinSelfSnapshot self) {
    final blocked = self.blocked.take(5).map((item) {
      final reason = item.availability.reasons.isEmpty
          ? item.availability.state.name
          : item.availability.reasons.first;
      return '${item.descriptor.id}: $reason';
    }).join('; ');
    return 'Identity: Kristin, governed AI in ${self.application.applicationIdentity}. '
        'Platform: ${self.application.platform}. '
        'Capabilities: ${self.available.length} available, ${self.blocked.length} blocked. '
        '${blocked.isEmpty ? '' : 'Key blockers: $blocked.'}';
  }

  String renderMachineReadable(KristinSelfSnapshot self) => jsonEncode(self.toJson());
}
