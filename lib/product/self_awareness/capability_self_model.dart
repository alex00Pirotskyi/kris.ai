import 'dart:async';
import 'dart:convert';

import '../chat_control_plane.dart';
import '../crypto_utils.dart';

enum CapabilityRiskClass {
  none,
  readOnly,
  execution,
  mutation,
  sensitive,
  destructive,
}

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

enum KnowledgeEvidenceKind { observed, configured, inferred, cached, unknown }

enum ObservationConfidence { certain, high, medium, low, unknown }

enum CapabilityHealthState { healthy, degraded, failing, unknown }

final class KnowledgeEvidence {
  KnowledgeEvidence({
    required this.kind,
    required this.source,
    this.confidence = ObservationConfidence.medium,
    DateTime? observedAt,
    this.expiresAt,
    this.detail = '',
  }) : observedAt = observedAt ?? DateTime.now().toUtc();

  final KnowledgeEvidenceKind kind;
  final String source;
  final ObservationConfidence confidence;
  final DateTime observedAt;
  final DateTime? expiresAt;
  final String detail;

  bool isFreshAt(DateTime now) => expiresAt == null || now.isBefore(expiresAt!);

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'source': source,
        'confidence': confidence.name,
        'observedAt': observedAt.toIso8601String(),
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
        if (detail.isNotEmpty) 'detail': detail,
      };
}

final class CapabilitySatisfactionStep {
  const CapabilitySatisfactionStep({
    required this.id,
    required this.description,
    required this.condition,
    this.capabilityId,
    this.requiredAuthority = const <String>{},
    this.automatic = false,
    this.safe = true,
  });

  final String id;
  final String description;
  final String condition;
  final String? capabilityId;
  final Set<String> requiredAuthority;
  final bool automatic;
  final bool safe;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'description': description,
        'condition': condition,
        if (capabilityId != null) 'capabilityId': capabilityId,
        'requiredAuthority': requiredAuthority.toList()..sort(),
        'automatic': automatic,
        'safe': safe,
      };
}

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
    this.freshnessBudget = const Duration(seconds: 10),
    this.probeInterval = const Duration(seconds: 30),
    this.schemaVersion = 2,
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
  final Duration freshnessBudget;
  final Duration probeInterval;
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
        'freshnessBudgetMs': freshnessBudget.inMilliseconds,
        'probeIntervalMs': probeInterval.inMilliseconds,
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
    this.evidence = const <KnowledgeEvidence>[],
    this.satisfactionPath = const <CapabilitySatisfactionStep>[],
  });

  final String capabilityId;
  final CapabilityAvailabilityState state;
  final List<String> reasons;
  final Set<String> missingPrerequisites;
  final Set<String> requiredAuthority;
  final Set<String> currentAuthority;
  final DateTime? retryAfter;
  final DateTime? observedAt;
  final List<KnowledgeEvidence> evidence;
  final List<CapabilitySatisfactionStep> satisfactionPath;

  bool get usableNow => state == CapabilityAvailabilityState.available ||
      state == CapabilityAvailabilityState.degraded;

  bool get knownButAuthorityBlocked =>
      state == CapabilityAvailabilityState.approvalRequired ||
      state == CapabilityAvailabilityState.additionalAuthorityRequired ||
      state == CapabilityAvailabilityState.ownerAuthorityUnavailable;

  bool freshAt(DateTime now, Duration budget) {
    if (budget == Duration.zero || observedAt == null) return false;
    if (now.difference(observedAt!) > budget) return false;
    return evidence.every((item) => item.isFreshAt(now));
  }

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
        'evidence': evidence.map((item) => item.toJson()).toList(),
        'satisfactionPath': satisfactionPath.map((item) => item.toJson()).toList(),
      };
}

final class CapabilityHealth {
  const CapabilityHealth({
    required this.capabilityId,
    required this.state,
    this.reasons = const <String>[],
    this.observedAt,
    this.lastVerifiedAt,
    this.evidence = const <KnowledgeEvidence>[],
    this.latency,
  });

  final String capabilityId;
  final CapabilityHealthState state;
  final List<String> reasons;
  final DateTime? observedAt;
  final DateTime? lastVerifiedAt;
  final List<KnowledgeEvidence> evidence;
  final Duration? latency;

  bool get healthyEnough =>
      state == CapabilityHealthState.healthy ||
      state == CapabilityHealthState.degraded ||
      state == CapabilityHealthState.unknown;

  bool freshAt(DateTime now, Duration budget) {
    if (budget == Duration.zero || observedAt == null) return false;
    if (now.difference(observedAt!) > budget) return false;
    return evidence.every((item) => item.isFreshAt(now));
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'capabilityId': capabilityId,
        'state': state.name,
        'reasons': reasons,
        if (observedAt != null) 'observedAt': observedAt!.toIso8601String(),
        if (lastVerifiedAt != null)
          'lastVerifiedAt': lastVerifiedAt!.toIso8601String(),
        if (latency != null) 'latencyMs': latency!.inMilliseconds,
        'evidence': evidence.map((item) => item.toJson()).toList(),
      };
}

final class KnownCapability {
  const KnownCapability({
    required this.descriptor,
    required this.availability,
    this.health,
  });

  final CapabilityDescriptor descriptor;
  final CapabilityAvailability availability;
  final CapabilityHealth? health;

  bool get operationallyUsable =>
      availability.usableNow && (health?.healthyEnough ?? true);

  Map<String, Object?> toJson() => <String, Object?>{
        'descriptor': descriptor.toJson(),
        'availability': availability.toJson(),
        if (health != null) 'health': health!.toJson(),
        'operationallyUsable': operationallyUsable,
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
    this.knowledgeEvidence = const <String, KnowledgeEvidence>{},
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
  final Map<String, KnowledgeEvidence> knowledgeEvidence;

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
        'knowledgeEvidence': knowledgeEvidence.map(
          (key, value) => MapEntry<String, Object?>(key, value.toJson()),
        ),
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

/// Optional provider surface for health. Availability answers whether a
/// capability may be used; health answers whether the underlying facility is
/// currently behaving well enough to rely on.
abstract interface class KristinCapabilityHealthProvider {
  Future<CapabilityHealth> resolveHealth(
    CapabilityDescriptor descriptor,
    ApplicationSnapshot snapshot,
    CapabilityAvailability availability,
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
          authorityClass: c.route == ChatExecutionRoute.ownerMode
              ? CapabilityAuthorityClass.owner
              : c.riskClass == ChatRiskClass.sensitive ||
                      c.riskClass == ChatRiskClass.destructive
                  ? CapabilityAuthorityClass.explicitApproval
                  : CapabilityAuthorityClass.governed,
          freshnessBudget: c.route == ChatExecutionRoute.ownerMode
              ? Duration.zero
              : const Duration(seconds: 10),
          probeInterval: c.route == ChatExecutionRoute.ownerMode
              ? const Duration(seconds: 5)
              : const Duration(seconds: 30),
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

final class CapabilityStateChange {
  const CapabilityStateChange({
    required this.capabilityId,
    required this.previousAvailability,
    required this.nextAvailability,
    required this.previousHealth,
    required this.nextHealth,
  });

  final CapabilityAvailabilityState? previousAvailability;
  final CapabilityAvailabilityState nextAvailability;
  final CapabilityHealthState? previousHealth;
  final CapabilityHealthState nextHealth;
  final String capabilityId;

  Map<String, Object?> toJson() => <String, Object?>{
        'capabilityId': capabilityId,
        if (previousAvailability != null)
          'previousAvailability': previousAvailability!.name,
        'nextAvailability': nextAvailability.name,
        if (previousHealth != null) 'previousHealth': previousHealth!.name,
        'nextHealth': nextHealth.name,
      };
}

final class SelfModelChange {
  SelfModelChange({
    String? id,
    DateTime? observedAt,
    required this.source,
    required this.reason,
    required this.capabilityChanges,
    required this.applicationChanged,
  })  : id = id ?? newId('self_change'),
        observedAt = observedAt ?? DateTime.now().toUtc();

  final String id;
  final DateTime observedAt;
  final String source;
  final String reason;
  final List<CapabilityStateChange> capabilityChanges;
  final bool applicationChanged;

  bool get material => capabilityChanges.isNotEmpty || applicationChanged;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'observedAt': observedAt.toIso8601String(),
        'source': source,
        'reason': reason,
        'applicationChanged': applicationChanged,
        'capabilityChanges': capabilityChanges.map((item) => item.toJson()).toList(),
      };
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
      capabilities.where((c) => c.operationallyUsable);
  Iterable<KnownCapability> get blocked =>
      capabilities.where((c) => !c.operationallyUsable);

  KnownCapability? capability(String id) {
    for (final item in capabilities) {
      if (item.descriptor.id == id) return item;
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': 2,
        'identity': 'Kristin, the governed AI operating kris.ai',
        'application': application.toJson(),
        'capabilities': capabilities.map((c) => c.toJson()).toList(),
      };
}

/// Compact planning projection. This is knowledge only; Runner tool names
/// remain an executor-specific allow-list and are never derived from known
/// coordinator capabilities.
final class SelfModelPlanningContext {
  const SelfModelPlanningContext({
    required this.summary,
    required this.availableCapabilityIds,
    required this.blockedCapabilityReasons,
    required this.currentAuthority,
    required this.relevantCapabilities,
    this.freshnessWarnings = const <String>[],
  });

  final String summary;
  final Set<String> availableCapabilityIds;
  final Map<String, String> blockedCapabilityReasons;
  final Set<String> currentAuthority;
  final List<Map<String, Object?>> relevantCapabilities;
  final List<String> freshnessWarnings;

  Map<String, Object?> toJson() => <String, Object?>{
        'summary': summary,
        'availableCapabilityIds': availableCapabilityIds.toList()..sort(),
        'blockedCapabilityReasons': blockedCapabilityReasons,
        'currentAuthority': currentAuthority.toList()..sort(),
        'relevantCapabilities': relevantCapabilities,
        'freshnessWarnings': freshnessWarnings,
      };
}

final class CapabilityRequirementReport {
  const CapabilityRequirementReport({
    required this.capabilityId,
    required this.known,
    required this.usableNow,
    required this.missingPrerequisites,
    required this.missingAuthority,
    required this.satisfactionPath,
    required this.explanation,
  });

  final String capabilityId;
  final bool known;
  final bool usableNow;
  final Set<String> missingPrerequisites;
  final Set<String> missingAuthority;
  final List<CapabilitySatisfactionStep> satisfactionPath;
  final String explanation;

  Map<String, Object?> toJson() => <String, Object?>{
        'capabilityId': capabilityId,
        'known': known,
        'usableNow': usableNow,
        'missingPrerequisites': missingPrerequisites.toList()..sort(),
        'missingAuthority': missingAuthority.toList()..sort(),
        'satisfactionPath': satisfactionPath.map((item) => item.toJson()).toList(),
        'explanation': explanation,
      };
}

final class KristinSelfModelService {
  KristinSelfModelService({
    required this.registry,
    required this.application,
    this.maxDetailedCapabilities = 12,
    this.maxRecentChanges = 100,
  });

  final KristinCapabilityRegistry registry;
  final ApplicationSnapshotProvider application;
  final int maxDetailedCapabilities;
  final int maxRecentChanges;
  final StreamController<SelfModelChange> _changeController =
      StreamController<SelfModelChange>.broadcast(sync: true);
  final Map<String, CapabilityAvailability> _availabilityCache =
      <String, CapabilityAvailability>{};
  final Map<String, CapabilityHealth> _healthCache = <String, CapabilityHealth>{};
  final Map<String, CapabilityHealth> _healthOverrides =
      <String, CapabilityHealth>{};
  final List<SelfModelChange> _recentChanges = <SelfModelChange>[];
  KristinSelfSnapshot? _lastSnapshot;

  Stream<SelfModelChange> get changes => _changeController.stream;

  Future<KristinSelfSnapshot> snapshot({
    bool forceRefresh = false,
    String source = 'self_model.read',
    String reason = 'snapshot',
  }) async {
    final app = await application.capture();
    final resolved = <KnownCapability>[];
    final ids = <String>{};
    final now = DateTime.now().toUtc();
    for (final provider in registry.providers) {
      for (final descriptor in provider.describeCapabilities()) {
        if (!ids.add(descriptor.id)) {
          throw StateError('duplicate_capability_id:${descriptor.id}');
        }
        final availability = await _resolveAvailability(
          provider,
          descriptor,
          app,
          now,
          forceRefresh: forceRefresh,
        );
        final health = await _resolveHealth(
          provider,
          descriptor,
          app,
          availability,
          now,
          forceRefresh: forceRefresh,
        );
        resolved.add(KnownCapability(
          descriptor: descriptor,
          availability: availability,
          health: health,
        ));
      }
    }
    resolved.sort((a, b) => a.descriptor.id.compareTo(b.descriptor.id));
    final next = KristinSelfSnapshot(application: app, capabilities: resolved);
    _recordChange(_lastSnapshot, next, source: source, reason: reason);
    _lastSnapshot = next;
    return next;
  }

  Future<KristinSelfSnapshot> refresh({
    String source = 'self_model.refresh',
    String reason = 'explicit_refresh',
  }) {
    _availabilityCache.clear();
    _healthCache.clear();
    return snapshot(forceRefresh: true, source: source, reason: reason);
  }

  Future<KristinSelfSnapshot> notifyStateChanged({
    required String source,
    required String reason,
  }) =>
      refresh(source: source, reason: reason);

  void recordHealthObservation(CapabilityHealth health) {
    _healthOverrides[health.capabilityId] = health;
    _healthCache.remove(health.capabilityId);
  }

  List<SelfModelChange> changesSince(DateTime since) => List<SelfModelChange>.unmodifiable(
        _recentChanges.where((change) => !change.observedAt.isBefore(since)),
      );

  Future<KnownCapability?> capability(String id, {bool forceRefresh = false}) async =>
      (await snapshot(forceRefresh: forceRefresh)).capability(id);

  Future<String> explainAvailability(String id) async {
    final item = await capability(id);
    if (item == null) {
      return 'Kristin does not currently know a capability named $id.';
    }
    final state = item.availability;
    final health = item.health;
    final why = state.reasons.isEmpty
        ? 'No additional availability reason was reported.'
        : state.reasons.join(' ');
    final healthText = health == null
        ? 'Health is unknown.'
        : 'Health is ${health.state.name}${health.reasons.isEmpty ? '.' : ': ${health.reasons.join(' ')}'}';
    return '$id is ${state.state.name}. $why $healthText';
  }

  Future<SelfModelPlanningContext> planningContext({
    Set<String> relevantCapabilityIds = const <String>{},
  }) async {
    final self = await snapshot(
      source: 'task_kernel',
      reason: 'planning_context',
    );
    final available = self.available.map((c) => c.descriptor.id).toSet();
    final blocked = <String, String>{};
    final freshnessWarnings = <String>[];
    final now = DateTime.now().toUtc();
    for (final item in self.blocked) {
      final reasons = <String>[
        ...item.availability.reasons,
        ...?item.health?.reasons,
      ];
      blocked[item.descriptor.id] = reasons.isEmpty
          ? item.availability.state.name
          : reasons.join(' ');
    }
    for (final item in self.capabilities) {
      if (!item.availability.freshAt(now, item.descriptor.freshnessBudget)) {
        freshnessWarnings.add('${item.descriptor.id}: availability observation is stale or execution-time only.');
      }
      final health = item.health;
      if (health != null && !health.freshAt(now, item.descriptor.freshnessBudget)) {
        freshnessWarnings.add('${item.descriptor.id}: health observation is stale or execution-time only.');
      }
    }
    final relevant = self.capabilities.where((item) {
      return relevantCapabilityIds.isEmpty ||
          relevantCapabilityIds.contains(item.descriptor.id);
    }).take(maxDetailedCapabilities).map((item) => item.toJson()).toList();
    final authority = <String>{};
    final rawAuthority = self.application.authority['granted'];
    if (rawAuthority is Iterable) {
      authority.addAll(rawAuthority.map((e) => e.toString()));
    }
    return SelfModelPlanningContext(
      summary: renderSummary(self),
      availableCapabilityIds: available,
      blockedCapabilityReasons: blocked,
      currentAuthority: authority,
      relevantCapabilities: relevant,
      freshnessWarnings: freshnessWarnings.take(12).toList(growable: false),
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
        'Capabilities: ${self.available.length} operational, ${self.blocked.length} blocked or unhealthy. '
        '${blocked.isEmpty ? '' : 'Key blockers: $blocked.'}';
  }

  String renderMachineReadable(KristinSelfSnapshot self) => jsonEncode(self.toJson());

  Future<void> close() async {
    await _changeController.close();
  }

  Future<CapabilityAvailability> _resolveAvailability(
    KristinCapabilityProvider provider,
    CapabilityDescriptor descriptor,
    ApplicationSnapshot app,
    DateTime now, {
    required bool forceRefresh,
  }) async {
    final cached = _availabilityCache[descriptor.id];
    if (!forceRefresh && cached != null && cached.freshAt(now, descriptor.freshnessBudget)) {
      return cached;
    }
    final value = await provider.resolveAvailability(descriptor, app);
    _availabilityCache[descriptor.id] = value;
    return value;
  }

  Future<CapabilityHealth> _resolveHealth(
    KristinCapabilityProvider provider,
    CapabilityDescriptor descriptor,
    ApplicationSnapshot app,
    CapabilityAvailability availability,
    DateTime now, {
    required bool forceRefresh,
  }) async {
    final override = _healthOverrides[descriptor.id];
    if (override != null && override.freshAt(now, descriptor.freshnessBudget)) {
      return override;
    }
    final cached = _healthCache[descriptor.id];
    if (!forceRefresh && cached != null && cached.freshAt(now, descriptor.freshnessBudget)) {
      return cached;
    }
    CapabilityHealth health;
    if (provider is KristinCapabilityHealthProvider) {
      health = await provider.resolveHealth(descriptor, app, availability);
    } else {
      final state = switch (availability.state) {
        CapabilityAvailabilityState.available => CapabilityHealthState.healthy,
        CapabilityAvailabilityState.degraded => CapabilityHealthState.degraded,
        CapabilityAvailabilityState.temporarilyUnavailable => CapabilityHealthState.failing,
        _ => CapabilityHealthState.unknown,
      };
      health = CapabilityHealth(
        capabilityId: descriptor.id,
        state: state,
        reasons: <String>[
          state == CapabilityHealthState.healthy
              ? 'No provider-specific health failure is currently reported.'
              : 'Health is inferred from availability until a subsystem probe reports direct evidence.',
        ],
        observedAt: availability.observedAt ?? app.capturedAt,
        evidence: <KnowledgeEvidence>[
          KnowledgeEvidence(
            kind: KnowledgeEvidenceKind.inferred,
            source: '${descriptor.providerId}.availability',
            confidence: state == CapabilityHealthState.healthy
                ? ObservationConfidence.medium
                : ObservationConfidence.low,
            observedAt: availability.observedAt ?? app.capturedAt,
          ),
        ],
      );
    }
    _healthCache[descriptor.id] = health;
    return health;
  }

  void _recordChange(
    KristinSelfSnapshot? previous,
    KristinSelfSnapshot next, {
    required String source,
    required String reason,
  }) {
    if (previous == null) return;
    final changes = <CapabilityStateChange>[];
    final previousById = <String, KnownCapability>{
      for (final item in previous.capabilities) item.descriptor.id: item,
    };
    for (final item in next.capabilities) {
      final prior = previousById[item.descriptor.id];
      final nextHealth = item.health?.state ?? CapabilityHealthState.unknown;
      final priorHealth = prior?.health?.state ?? CapabilityHealthState.unknown;
      if (prior == null ||
          prior.availability.state != item.availability.state ||
          priorHealth != nextHealth ||
          prior.operationallyUsable != item.operationallyUsable) {
        changes.add(CapabilityStateChange(
          capabilityId: item.descriptor.id,
          previousAvailability: prior?.availability.state,
          nextAvailability: item.availability.state,
          previousHealth: prior?.health?.state,
          nextHealth: nextHealth,
        ));
      }
    }
    final previousApplication = Map<String, Object?>.from(previous.application.toJson())
      ..remove('capturedAt');
    final nextApplication = Map<String, Object?>.from(next.application.toJson())
      ..remove('capturedAt');
    final applicationChanged = jsonEncode(previousApplication) != jsonEncode(nextApplication);
    final change = SelfModelChange(
      source: source,
      reason: reason,
      capabilityChanges: changes,
      applicationChanged: applicationChanged,
    );
    if (!change.material) return;
    _recentChanges.add(change);
    if (_recentChanges.length > maxRecentChanges) {
      _recentChanges.removeRange(0, _recentChanges.length - maxRecentChanges);
    }
    if (!_changeController.isClosed) _changeController.add(change);
  }
}

/// Deterministic read-only reasoning API over the same self-model used by
/// planning. It answers questions about capability state without introducing
/// another planner or execution path.
final class SelfAwarenessQueryService {
  const SelfAwarenessQueryService(this.selfModel);

  final KristinSelfModelService selfModel;

  Future<String> explainCapability(String capabilityId) =>
      selfModel.explainAvailability(capabilityId);

  Future<CapabilityRequirementReport> requirementsFor(String capabilityId) async {
    final item = await selfModel.capability(capabilityId, forceRefresh: true);
    if (item == null) {
      return CapabilityRequirementReport(
        capabilityId: capabilityId,
        known: false,
        usableNow: false,
        missingPrerequisites: const <String>{},
        missingAuthority: const <String>{},
        satisfactionPath: const <CapabilitySatisfactionStep>[],
        explanation: 'Kristin does not currently know this capability.',
      );
    }
    final missingAuthority = item.availability.requiredAuthority
        .difference(item.availability.currentAuthority);
    final path = item.availability.satisfactionPath.isNotEmpty
        ? item.availability.satisfactionPath
        : _derivedSatisfactionPath(item, missingAuthority);
    return CapabilityRequirementReport(
      capabilityId: capabilityId,
      known: true,
      usableNow: item.operationallyUsable,
      missingPrerequisites: item.availability.missingPrerequisites,
      missingAuthority: missingAuthority,
      satisfactionPath: path,
      explanation: item.operationallyUsable
          ? '$capabilityId is operationally usable now.'
          : '${item.availability.reasons.join(' ')} ${item.health?.reasons.join(' ') ?? ''}'.trim(),
    );
  }

  Future<List<KnownCapability>> capabilitiesFor(String objective) async {
    final self = await selfModel.snapshot(
      source: 'self_awareness.query',
      reason: 'capabilities_for_objective',
    );
    final tokens = objective
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9_.:-]+'))
        .where((token) => token.length > 2)
        .toSet();
    if (tokens.isEmpty) return const <KnownCapability>[];
    int score(KnownCapability item) {
      final haystack = <String>[
        item.descriptor.id,
        item.descriptor.name,
        item.descriptor.description,
        item.descriptor.semanticPurpose,
        item.descriptor.category,
        ...item.descriptor.whenToUse,
        ...item.descriptor.usageHints,
      ].join(' ').toLowerCase();
      return tokens.where(haystack.contains).length;
    }

    final ranked = self.capabilities.where((item) => score(item) > 0).toList()
      ..sort((left, right) {
        final byScore = score(right).compareTo(score(left));
        if (byScore != 0) return byScore;
        if (left.operationallyUsable != right.operationallyUsable) {
          return left.operationallyUsable ? -1 : 1;
        }
        return left.descriptor.id.compareTo(right.descriptor.id);
      });
    return List<KnownCapability>.unmodifiable(ranked.take(12));
  }

  List<SelfModelChange> whatChangedSince(DateTime since) =>
      selfModel.changesSince(since);

  List<CapabilitySatisfactionStep> _derivedSatisfactionPath(
    KnownCapability item,
    Set<String> missingAuthority,
  ) {
    final steps = <CapabilitySatisfactionStep>[];
    for (final prerequisite in item.availability.missingPrerequisites) {
      steps.add(CapabilitySatisfactionStep(
        id: 'satisfy_$prerequisite',
        description: 'Satisfy prerequisite: $prerequisite.',
        condition: '$prerequisite is present and freshly observed.',
      ));
    }
    if (item.descriptor.browserRequired) {
      steps.add(const CapabilitySatisfactionStep(
        id: 'verify_browser_runtime',
        description: 'Provision and successfully probe the application-owned Browser runtime.',
        condition: 'Browser runtime probe is healthy.',
      ));
    }
    if (item.descriptor.modelProviderRequired) {
      steps.add(const CapabilitySatisfactionStep(
        id: 'verify_model_provider',
        description: 'Select a model whose provider is currently discoverable and responsive.',
        condition: 'Selected model resolves to a live provider observation.',
      ));
    }
    if (missingAuthority.isNotEmpty) {
      steps.add(CapabilitySatisfactionStep(
        id: 'obtain_explicit_authority',
        description: 'Obtain the missing governed authority at execution time.',
        condition: 'Authority service reports the required grant for this operation.',
        requiredAuthority: missingAuthority,
        automatic: false,
        safe: true,
      ));
    }
    return List<CapabilitySatisfactionStep>.unmodifiable(steps);
  }
}
