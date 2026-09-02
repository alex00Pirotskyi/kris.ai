import 'dart:async';
import 'dart:convert';

import '../capability_invocation.dart';
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
enum AuthorityObservationState { notRequired, notEvaluated, absent, granted }
enum KnowledgeEvidenceKind { observed, configured, inferred, cached, unknown }
enum ObservationConfidence { certain, high, medium, low, unknown }
enum CapabilityHealthState { healthy, degraded, failing, unknown }

int _confidenceRank(ObservationConfidence value) => switch (value) {
      ObservationConfidence.certain => 4,
      ObservationConfidence.high => 3,
      ObservationConfidence.medium => 2,
      ObservationConfidence.low => 1,
      ObservationConfidence.unknown => 0,
    };

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

  bool get directlyObserved =>
      kind == KnowledgeEvidenceKind.observed ||
      kind == KnowledgeEvidenceKind.configured;

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'source': source,
        'confidence': confidence.name,
        'observedAt': observedAt.toIso8601String(),
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
        if (detail.isNotEmpty) 'detail': detail,
      };

  Map<String, Object?> semanticJson() => <String, Object?>{
        'kind': kind.name,
        'source': source,
        'confidence': confidence.name,
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

/// Canonical model-readable capability description. This says what exists;
/// it never claims the capability is currently healthy, available or granted.
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
    this.runnerToolName,
    this.recoveryParticipant = false,
    this.usageHints = const <String>[],
    this.providerId = 'unknown',
    this.freshnessBudget = const Duration(seconds: 10),
    this.healthFreshnessBudget = const Duration(seconds: 30),
    this.probeInterval = const Duration(seconds: 30),
    this.schemaVersion = 3,
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
  final String? runnerToolName;
  final bool recoveryParticipant;
  final List<String> usageHints;
  final String providerId;
  final Duration freshnessBudget;
  final Duration healthFreshnessBudget;
  final Duration probeInterval;
  final int schemaVersion;

  bool get authoritySensitive =>
      authorityClass == CapabilityAuthorityClass.owner ||
      authorityClass == CapabilityAuthorityClass.explicitApproval ||
      riskClass == CapabilityRiskClass.sensitive ||
      riskClass == CapabilityRiskClass.destructive;

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
        if (runnerToolName != null) 'runnerToolName': runnerToolName,
        'recoveryParticipant': recoveryParticipant,
        'usageHints': usageHints,
        'providerId': providerId,
        'freshnessBudgetMs': freshnessBudget.inMilliseconds,
        'healthFreshnessBudgetMs': healthFreshnessBudget.inMilliseconds,
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
    this.authorityObservation = AuthorityObservationState.notEvaluated,
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
  final AuthorityObservationState authorityObservation;
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

  ObservationConfidence get strongestConfidence {
    var best = ObservationConfidence.unknown;
    for (final item in evidence) {
      if (_confidenceRank(item.confidence) > _confidenceRank(best)) {
        best = item.confidence;
      }
    }
    return best;
  }

  bool get hasDirectEvidence => evidence.any((item) => item.directlyObserved);

  Map<String, Object?> toJson() => <String, Object?>{
        'capabilityId': capabilityId,
        'state': state.name,
        'usableNow': usableNow,
        'reasons': reasons,
        'missingPrerequisites': missingPrerequisites.toList()..sort(),
        'requiredAuthority': requiredAuthority.toList()..sort(),
        'currentAuthority': currentAuthority.toList()..sort(),
        'authorityObservation': authorityObservation.name,
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
    this.expiresAt,
    this.evidence = const <KnowledgeEvidence>[],
    this.latency,
  });

  final String capabilityId;
  final CapabilityHealthState state;
  final List<String> reasons;
  final DateTime? observedAt;
  final DateTime? lastVerifiedAt;
  final DateTime? expiresAt;
  final List<KnowledgeEvidence> evidence;
  final Duration? latency;

  bool get healthyEnough => state == CapabilityHealthState.healthy ||
      state == CapabilityHealthState.degraded;

  bool freshAt(DateTime now, Duration budget) {
    if (observedAt == null) return false;
    if (expiresAt != null && !now.isBefore(expiresAt!)) return false;
    if (budget == Duration.zero || now.difference(observedAt!) > budget) {
      return false;
    }
    return evidence.every((item) => item.isFreshAt(now));
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'capabilityId': capabilityId,
        'state': state.name,
        'reasons': reasons,
        if (observedAt != null) 'observedAt': observedAt!.toIso8601String(),
        if (lastVerifiedAt != null)
          'lastVerifiedAt': lastVerifiedAt!.toIso8601String(),
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
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

  bool get operationallyUsable => operationallyUsableAt(DateTime.now().toUtc());

  bool operationallyUsableAt(DateTime now) {
    if (!availability.usableNow ||
        !availability.freshAt(now, descriptor.freshnessBudget)) {
      return false;
    }
    if (descriptor.authoritySensitive &&
        availability.requiredAuthority.isNotEmpty &&
        availability.authorityObservation != AuthorityObservationState.granted) {
      return false;
    }
    final observedHealth = health;
    if (observedHealth == null) {
      return descriptor.riskClass == CapabilityRiskClass.none ||
          descriptor.riskClass == CapabilityRiskClass.readOnly;
    }
    if (observedHealth.state == CapabilityHealthState.failing) return false;
    if (observedHealth.state == CapabilityHealthState.unknown &&
        descriptor.riskClass != CapabilityRiskClass.none &&
        descriptor.riskClass != CapabilityRiskClass.readOnly) {
      return false;
    }
    if (descriptor.riskClass != CapabilityRiskClass.none &&
        descriptor.riskClass != CapabilityRiskClass.readOnly &&
        !observedHealth.freshAt(now, descriptor.healthFreshnessBudget)) {
      return false;
    }
    if (descriptor.riskClass == CapabilityRiskClass.sensitive ||
        descriptor.riskClass == CapabilityRiskClass.destructive) {
      if (!availability.hasDirectEvidence ||
          _confidenceRank(availability.strongestConfidence) <
              _confidenceRank(ObservationConfidence.high)) {
        return false;
      }
    }
    return true;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'descriptor': descriptor.toJson(),
        'availability': availability.toJson(),
        if (health != null) 'health': health!.toJson(),
        'operationallyUsable': operationallyUsable,
      };
}

/// Conversation/session facts are an overlay, not global runtime truth.
final class SelfModelSessionOverlay {
  const SelfModelSessionOverlay({
    this.key = 'runtime',
    this.selectedProject,
    this.selectedModel,
  });

  final String key;
  final Map<String, Object?>? selectedProject;
  final Map<String, Object?>? selectedModel;

  String get cacheKey => '$key|${selectedProject?['id'] ?? ''}|${selectedModel?['exactId'] ?? ''}';
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
        ...semanticJson(),
        'knowledgeEvidence': knowledgeEvidence.map(
          (key, value) => MapEntry<String, Object?>(key, value.toJson()),
        ),
      };

  /// Semantic equality deliberately excludes re-observation timestamps.
  Map<String, Object?> semanticJson() => <String, Object?>{
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
          (key, value) => MapEntry<String, Object?>(key, value.semanticJson()),
        ),
      };

  String get semanticFingerprint => Sha256.text(canonicalJson(semanticJson()));
}

abstract interface class ApplicationSnapshotProvider {
  Future<ApplicationSnapshot> capture({
    bool forceRefresh = false,
    SelfModelSessionOverlay overlay = const SelfModelSessionOverlay(),
  });
}

abstract interface class KristinCapabilityProvider {
  String get providerId;
  Iterable<CapabilityDescriptor> describeCapabilities();
  Future<CapabilityAvailability> resolveAvailability(
    CapabilityDescriptor descriptor,
    ApplicationSnapshot snapshot,
  );
}

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

final class ChatCapabilityProvider implements KristinCapabilityProvider {
  const ChatCapabilityProvider({
    required this.availabilityResolver,
    this.capabilities = kKristinCapabilities,
    this.authorityResolver = const CapabilityAuthorityResolver(),
  });

  final List<KristinCapability> capabilities;
  final CapabilityAuthorityResolver authorityResolver;
  final Future<CapabilityAvailability> Function(
    KristinCapability capability,
    CapabilityDescriptor descriptor,
    ApplicationSnapshot snapshot,
  ) availabilityResolver;

  @override
  String get providerId => 'chat.registry';

  static const Set<ChatExecutionRoute> _projectRequiredRoutes =
      <ChatExecutionRoute>{
    ChatExecutionRoute.modifyProject,
    ChatExecutionRoute.fixProject,
    ChatExecutionRoute.projectAnalyze,
    ChatExecutionRoute.projectTest,
    ChatExecutionRoute.projectBuild,
    ChatExecutionRoute.projectRun,
    ChatExecutionRoute.projectStop,
    ChatExecutionRoute.projectRestart,
  };

  @override
  Iterable<CapabilityDescriptor> describeCapabilities() => capabilities.map((c) {
        final mutating = c.riskClass == ChatRiskClass.mutation ||
            c.riskClass == ChatRiskClass.destructive;
        final authority = authorityResolver.resolve(
          CapabilityInvocation(capabilityId: c.id, reason: 'self_model.describe'),
        );
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
          projectRequired: _projectRequiredRoutes.contains(c.route),
          modelProviderRequired: c.actionClass == ChatActionClass.substantial,
          permissionRequirements:
              authority.requiredScopes.map((scope) => scope.name).toSet(),
          authorityClass: c.route == ChatExecutionRoute.ownerMode
              ? CapabilityAuthorityClass.owner
              : c.riskClass == ChatRiskClass.sensitive ||
                      c.riskClass == ChatRiskClass.destructive
                  ? CapabilityAuthorityClass.explicitApproval
                  : authority.requiredScopes.isEmpty
                      ? CapabilityAuthorityClass.none
                      : CapabilityAuthorityClass.governed,
          freshnessBudget: c.route == ChatExecutionRoute.ownerMode
              ? Duration.zero
              : const Duration(seconds: 10),
          healthFreshnessBudget: c.route == ChatExecutionRoute.ownerMode
              ? const Duration(seconds: 5)
              : const Duration(seconds: 30),
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
    required this.previousUsable,
    required this.nextUsable,
  });

  final String capabilityId;
  final CapabilityAvailabilityState? previousAvailability;
  final CapabilityAvailabilityState nextAvailability;
  final CapabilityHealthState? previousHealth;
  final CapabilityHealthState nextHealth;
  final bool previousUsable;
  final bool nextUsable;

  Map<String, Object?> toJson() => <String, Object?>{
        'capabilityId': capabilityId,
        if (previousAvailability != null)
          'previousAvailability': previousAvailability!.name,
        'nextAvailability': nextAvailability.name,
        if (previousHealth != null) 'previousHealth': previousHealth!.name,
        'nextHealth': nextHealth.name,
        'previousUsable': previousUsable,
        'nextUsable': nextUsable,
      };
}

final class SelfModelChange {
  SelfModelChange({
    String? id,
    DateTime? observedAt,
    required this.overlayKey,
    required this.source,
    required this.reason,
    required this.capabilityChanges,
    required this.applicationFieldsChanged,
  })  : id = id ?? newId('self_change'),
        observedAt = observedAt ?? DateTime.now().toUtc();

  final String id;
  final DateTime observedAt;
  final String overlayKey;
  final String source;
  final String reason;
  final List<CapabilityStateChange> capabilityChanges;
  final List<String> applicationFieldsChanged;

  bool get applicationChanged => applicationFieldsChanged.isNotEmpty;
  bool get material => capabilityChanges.isNotEmpty || applicationChanged;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'observedAt': observedAt.toIso8601String(),
        'overlayKey': overlayKey,
        'source': source,
        'reason': reason,
        'applicationChanged': applicationChanged,
        'applicationFieldsChanged': applicationFieldsChanged,
        'capabilityChanges': capabilityChanges.map((item) => item.toJson()).toList(),
      };
}

final class KristinSelfSnapshot {
  const KristinSelfSnapshot({
    required this.application,
    required this.capabilities,
    this.overlay = const SelfModelSessionOverlay(),
  });

  final ApplicationSnapshot application;
  final List<KnownCapability> capabilities;
  final SelfModelSessionOverlay overlay;

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
        'schemaVersion': 3,
        'identity': 'Kristin, the governed AI operating kris.ai',
        'overlayKey': overlay.cacheKey,
        'application': application.toJson(),
        'capabilities': capabilities.map((c) => c.toJson()).toList(),
      };
}

final class SelfModelPlanningContext {
  const SelfModelPlanningContext({
    required this.summary,
    required this.availableCapabilityIds,
    required this.blockedCapabilityReasons,
    required this.currentAuthority,
    required this.relevantCapabilities,
    this.freshnessWarnings = const <String>[],
    this.authorityNotEvaluated = const <String>{},
  });

  final String summary;
  final Set<String> availableCapabilityIds;
  final Map<String, String> blockedCapabilityReasons;
  final Set<String> currentAuthority;
  final Set<String> authorityNotEvaluated;
  final List<Map<String, Object?>> relevantCapabilities;
  final List<String> freshnessWarnings;

  Map<String, Object?> toJson() => <String, Object?>{
        'summary': summary,
        'availableCapabilityIds': availableCapabilityIds.toList()..sort(),
        'blockedCapabilityReasons': blockedCapabilityReasons,
        'currentAuthority': currentAuthority.toList()..sort(),
        'authorityNotEvaluated': authorityNotEvaluated.toList()..sort(),
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
    required this.requiredAuthority,
    required this.missingAuthority,
    required this.authorityObservation,
    required this.satisfactionPath,
    required this.explanation,
  });

  final String capabilityId;
  final bool known;
  final bool usableNow;
  final Set<String> missingPrerequisites;
  final Set<String> requiredAuthority;
  final Set<String> missingAuthority;
  final AuthorityObservationState authorityObservation;
  final List<CapabilitySatisfactionStep> satisfactionPath;
  final String explanation;

  Map<String, Object?> toJson() => <String, Object?>{
        'capabilityId': capabilityId,
        'known': known,
        'usableNow': usableNow,
        'missingPrerequisites': missingPrerequisites.toList()..sort(),
        'requiredAuthority': requiredAuthority.toList()..sort(),
        'missingAuthority': missingAuthority.toList()..sort(),
        'authorityObservation': authorityObservation.name,
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
  final Map<String, KristinSelfSnapshot> _lastSnapshots =
      <String, KristinSelfSnapshot>{};
  Future<void> _serial = Future<void>.value();

  Stream<SelfModelChange> get changes => _changeController.stream;

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _serial = _serial.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<KristinSelfSnapshot> snapshot({
    bool forceRefresh = false,
    String source = 'self_model.read',
    String reason = 'snapshot',
    SelfModelSessionOverlay overlay = const SelfModelSessionOverlay(),
  }) =>
      _synchronized(() => _snapshotUnlocked(
            forceRefresh: forceRefresh,
            source: source,
            reason: reason,
            overlay: overlay,
          ));

  Future<KristinSelfSnapshot> _snapshotUnlocked({
    required bool forceRefresh,
    required String source,
    required String reason,
    required SelfModelSessionOverlay overlay,
  }) async {
    final app = await application.capture(
      forceRefresh: forceRefresh,
      overlay: overlay,
    );
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
          overlay,
          forceRefresh: forceRefresh,
        );
        final health = await _resolveHealth(
          provider,
          descriptor,
          app,
          availability,
          now,
          overlay,
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
    final next = KristinSelfSnapshot(
      application: app,
      capabilities: resolved,
      overlay: overlay,
    );
    final key = overlay.cacheKey;
    _recordChange(_lastSnapshots[key], next, source: source, reason: reason);
    _lastSnapshots[key] = next;
    return next;
  }

  Future<KristinSelfSnapshot> refresh({
    String source = 'self_model.refresh',
    String reason = 'explicit_refresh',
    SelfModelSessionOverlay overlay = const SelfModelSessionOverlay(),
  }) =>
      _synchronized(() async {
        _clearOverlayCaches(overlay);
        return _snapshotUnlocked(
          forceRefresh: true,
          source: source,
          reason: reason,
          overlay: overlay,
        );
      });

  Future<KristinSelfSnapshot> notifyStateChanged({
    required String source,
    required String reason,
    SelfModelSessionOverlay overlay = const SelfModelSessionOverlay(),
  }) =>
      refresh(source: source, reason: reason, overlay: overlay);

  void recordHealthObservation(
    CapabilityHealth health, {
    SelfModelSessionOverlay overlay = const SelfModelSessionOverlay(),
  }) {
    final key = _cacheKey(overlay, health.capabilityId);
    _healthOverrides[key] = health;
    _healthCache.remove(key);
  }

  List<SelfModelChange> changesSince(
    DateTime since, {
    String? overlayKey,
  }) =>
      List<SelfModelChange>.unmodifiable(_recentChanges.where((change) {
        if (change.observedAt.isBefore(since)) return false;
        return overlayKey == null || change.overlayKey == overlayKey;
      }));

  Future<KnownCapability?> capability(
    String id, {
    bool forceRefresh = false,
    SelfModelSessionOverlay overlay = const SelfModelSessionOverlay(),
  }) async =>
      (await snapshot(forceRefresh: forceRefresh, overlay: overlay)).capability(id);

  Future<String> explainAvailability(
    String id, {
    SelfModelSessionOverlay overlay = const SelfModelSessionOverlay(),
  }) async {
    final item = await capability(id, overlay: overlay);
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
    final authorityText = state.requiredAuthority.isEmpty
        ? ''
        : ' Authority is ${state.authorityObservation.name}; required: ${state.requiredAuthority.join(', ')}.';
    return '$id is ${state.state.name}. $why $healthText$authorityText';
  }

  Future<SelfModelPlanningContext> planningContext({
    Set<String> relevantCapabilityIds = const <String>{},
    SelfModelSessionOverlay overlay = const SelfModelSessionOverlay(),
  }) async {
    final self = await snapshot(
      source: 'task_kernel',
      reason: 'planning_context',
      overlay: overlay,
    );
    final available = self.available.map((c) => c.descriptor.id).toSet();
    final blocked = <String, String>{};
    final freshnessWarnings = <String>[];
    final authorityNotEvaluated = <String>{};
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
        freshnessWarnings.add(
          '${item.descriptor.id}: availability observation is stale or execution-time only.',
        );
      }
      final health = item.health;
      if (health != null &&
          !health.freshAt(now, item.descriptor.healthFreshnessBudget)) {
        freshnessWarnings.add(
          '${item.descriptor.id}: health observation is stale or execution-time only.',
        );
      }
      if (item.availability.requiredAuthority.isNotEmpty &&
          item.availability.authorityObservation ==
              AuthorityObservationState.notEvaluated) {
        authorityNotEvaluated.add(item.descriptor.id);
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
      authorityNotEvaluated: authorityNotEvaluated,
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
    await _serial;
    await _changeController.close();
  }

  String _cacheKey(SelfModelSessionOverlay overlay, String capabilityId) =>
      '${overlay.cacheKey}|$capabilityId';

  void _clearOverlayCaches(SelfModelSessionOverlay overlay) {
    final prefix = '${overlay.cacheKey}|';
    _availabilityCache.removeWhere((key, _) => key.startsWith(prefix));
    _healthCache.removeWhere((key, _) => key.startsWith(prefix));
  }

  Future<CapabilityAvailability> _resolveAvailability(
    KristinCapabilityProvider provider,
    CapabilityDescriptor descriptor,
    ApplicationSnapshot app,
    DateTime now,
    SelfModelSessionOverlay overlay, {
    required bool forceRefresh,
  }) async {
    final key = _cacheKey(overlay, descriptor.id);
    final cached = _availabilityCache[key];
    if (!forceRefresh &&
        cached != null &&
        cached.freshAt(now, descriptor.freshnessBudget)) {
      return cached;
    }
    final value = await provider.resolveAvailability(descriptor, app);
    _availabilityCache[key] = value;
    return value;
  }

  Future<CapabilityHealth> _resolveHealth(
    KristinCapabilityProvider provider,
    CapabilityDescriptor descriptor,
    ApplicationSnapshot app,
    CapabilityAvailability availability,
    DateTime now,
    SelfModelSessionOverlay overlay, {
    required bool forceRefresh,
  }) async {
    final key = _cacheKey(overlay, descriptor.id);
    final override = _healthOverrides[key] ?? _healthOverrides[_cacheKey(const SelfModelSessionOverlay(), descriptor.id)];
    if (override != null &&
        override.freshAt(now, descriptor.healthFreshnessBudget)) {
      return override;
    }
    final cached = _healthCache[key];
    if (!forceRefresh &&
        cached != null &&
        cached.freshAt(now, descriptor.healthFreshnessBudget)) {
      return cached;
    }
    CapabilityHealth health;
    if (provider is KristinCapabilityHealthProvider) {
      health = await provider.resolveHealth(descriptor, app, availability);
    } else {
      final state = switch (availability.state) {
        CapabilityAvailabilityState.available => CapabilityHealthState.healthy,
        CapabilityAvailabilityState.degraded => CapabilityHealthState.degraded,
        CapabilityAvailabilityState.temporarilyUnavailable =>
          CapabilityHealthState.failing,
        _ => CapabilityHealthState.unknown,
      };
      final observedAt = availability.observedAt ?? app.capturedAt;
      health = CapabilityHealth(
        capabilityId: descriptor.id,
        state: state,
        reasons: <String>[
          state == CapabilityHealthState.healthy
              ? 'Health is inferred from fresh availability; no provider-specific failure is reported.'
              : 'Health is inferred from availability until a subsystem probe reports direct evidence.',
        ],
        observedAt: observedAt,
        expiresAt: observedAt.add(descriptor.healthFreshnessBudget),
        evidence: <KnowledgeEvidence>[
          KnowledgeEvidence(
            kind: KnowledgeEvidenceKind.inferred,
            source: '${descriptor.providerId}.availability',
            confidence: state == CapabilityHealthState.healthy
                ? ObservationConfidence.medium
                : ObservationConfidence.low,
            observedAt: observedAt,
            expiresAt: observedAt.add(descriptor.healthFreshnessBudget),
          ),
        ],
      );
    }
    _healthCache[key] = health;
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
          previousUsable: prior?.operationallyUsable ?? false,
          nextUsable: item.operationallyUsable,
        ));
      }
    }
    final previousApplication = previous.application.semanticJson();
    final nextApplication = next.application.semanticJson();
    final changedFields = <String>{
      ...previousApplication.keys,
      ...nextApplication.keys,
    }.where((key) {
      return canonicalJson(previousApplication[key]) !=
          canonicalJson(nextApplication[key]);
    }).toList()
      ..sort();
    final change = SelfModelChange(
      overlayKey: next.overlay.cacheKey,
      source: source,
      reason: reason,
      capabilityChanges: changes,
      applicationFieldsChanged: changedFields,
    );
    if (!change.material) return;
    _recentChanges.add(change);
    if (_recentChanges.length > maxRecentChanges) {
      _recentChanges.removeRange(0, _recentChanges.length - maxRecentChanges);
    }
    if (!_changeController.isClosed) _changeController.add(change);
  }
}

final class SelfAwarenessQueryService {
  const SelfAwarenessQueryService(this.selfModel);

  final KristinSelfModelService selfModel;

  Future<String> explainCapability(
    String capabilityId, {
    SelfModelSessionOverlay overlay = const SelfModelSessionOverlay(),
  }) =>
      selfModel.explainAvailability(capabilityId, overlay: overlay);

  Future<CapabilityRequirementReport> requirementsFor(
    String capabilityId, {
    SelfModelSessionOverlay overlay = const SelfModelSessionOverlay(),
  }) async {
    final item = await selfModel.capability(
      capabilityId,
      forceRefresh: true,
      overlay: overlay,
    );
    if (item == null) {
      return const CapabilityRequirementReport(
        capabilityId: '',
        known: false,
        usableNow: false,
        missingPrerequisites: <String>{},
        requiredAuthority: <String>{},
        missingAuthority: <String>{},
        authorityObservation: AuthorityObservationState.notEvaluated,
        satisfactionPath: <CapabilitySatisfactionStep>[],
        explanation: 'Kristin does not currently know this capability.',
      );
    }
    final missingAuthority = item.availability.authorityObservation ==
            AuthorityObservationState.granted
        ? item.availability.requiredAuthority
            .difference(item.availability.currentAuthority)
        : item.availability.requiredAuthority;
    final path = item.availability.satisfactionPath.isNotEmpty
        ? item.availability.satisfactionPath
        : _derivedSatisfactionPath(item, missingAuthority);
    final authorityNote = item.availability.requiredAuthority.isEmpty
        ? ''
        : item.availability.authorityObservation ==
                AuthorityObservationState.notEvaluated
            ? ' Required authority is checked at execution time and has not been evaluated for a concrete operation.'
            : '';
    return CapabilityRequirementReport(
      capabilityId: capabilityId,
      known: true,
      usableNow: item.operationallyUsable,
      missingPrerequisites: item.availability.missingPrerequisites,
      requiredAuthority: item.availability.requiredAuthority,
      missingAuthority: missingAuthority,
      authorityObservation: item.availability.authorityObservation,
      satisfactionPath: path,
      explanation: item.operationallyUsable
          ? '$capabilityId is operationally usable now.$authorityNote'
          : '${item.availability.reasons.join(' ')} ${item.health?.reasons.join(' ') ?? ''}$authorityNote'.trim(),
    );
  }

  Future<List<KnownCapability>> capabilitiesFor(
    String objective, {
    SelfModelSessionOverlay overlay = const SelfModelSessionOverlay(),
  }) async {
    final self = await selfModel.snapshot(
      source: 'self_awareness.query',
      reason: 'capabilities_for_objective',
      overlay: overlay,
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

  List<SelfModelChange> whatChangedSince(
    DateTime since, {
    String? overlayKey,
  }) =>
      selfModel.changesSince(since, overlayKey: overlayKey);

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
        description:
            'Provision and successfully probe the application-owned Browser runtime.',
        condition: 'Browser runtime probe is healthy.',
      ));
    }
    if (item.descriptor.modelProviderRequired) {
      steps.add(const CapabilitySatisfactionStep(
        id: 'verify_model_provider',
        description:
            'Select a model whose exact identity is present in fresh provider discovery.',
        condition: 'Selected model resolves to a live provider observation.',
      ));
    }
    if (missingAuthority.isNotEmpty) {
      steps.add(CapabilitySatisfactionStep(
        id: 'obtain_explicit_authority',
        description:
            'Evaluate and obtain the missing governed authority for the concrete operation.',
        condition:
            'Authority service reports the required grant for this operation.',
        requiredAuthority: missingAuthority,
        automatic: false,
        safe: true,
      ));
    }
    return List<CapabilitySatisfactionStep>.unmodifiable(steps);
  }
}
