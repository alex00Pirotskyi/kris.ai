import 'dart:async';
import 'dart:io';

import 'chat_control_plane.dart';
import 'domain.dart';
import 'product_runtime.dart';
import 'self_awareness/capability_self_model.dart';
import 'self_awareness/operational_self_awareness.dart';

final class RuntimeCapabilityProvider
    implements KristinCapabilityProvider, KristinCapabilityHealthProvider {
  const RuntimeCapabilityProvider({
    required this.providerId,
    required this.descriptors,
    required this.resolver,
    this.healthResolver,
  });

  @override
  final String providerId;
  final List<CapabilityDescriptor> descriptors;
  final Future<CapabilityAvailability> Function(
    CapabilityDescriptor descriptor,
    ApplicationSnapshot snapshot,
  ) resolver;
  final Future<CapabilityHealth> Function(
    CapabilityDescriptor descriptor,
    ApplicationSnapshot snapshot,
    CapabilityAvailability availability,
  )? healthResolver;

  @override
  Iterable<CapabilityDescriptor> describeCapabilities() => descriptors;

  @override
  Future<CapabilityAvailability> resolveAvailability(
    CapabilityDescriptor descriptor,
    ApplicationSnapshot snapshot,
  ) =>
      resolver(descriptor, snapshot);

  @override
  Future<CapabilityHealth> resolveHealth(
    CapabilityDescriptor descriptor,
    ApplicationSnapshot snapshot,
    CapabilityAvailability availability,
  ) async {
    final custom = healthResolver;
    if (custom != null) return custom(descriptor, snapshot, availability);
    final now = snapshot.capturedAt;
    return CapabilityHealth(
      capabilityId: descriptor.id,
      state: availability.state == CapabilityAvailabilityState.available
          ? CapabilityHealthState.healthy
          : availability.state == CapabilityAvailabilityState.degraded
              ? CapabilityHealthState.degraded
              : CapabilityHealthState.unknown,
      reasons: const <String>[
        'Runtime provider has not reported a separate direct health probe yet.',
      ],
      observedAt: now,
      expiresAt: now.add(descriptor.healthFreshnessBudget),
      evidence: <KnowledgeEvidence>[
        KnowledgeEvidence(
          kind: KnowledgeEvidenceKind.inferred,
          source: '$providerId.availability',
          confidence: ObservationConfidence.medium,
          observedAt: now,
          expiresAt: now.add(descriptor.healthFreshnessBudget),
        ),
      ],
    );
  }
}

SelfModelSessionOverlay productSelfOverlay({
  String key = 'chat',
  ProjectRecord? selectedProject,
  ModelIdentity? selectedModel,
}) =>
    SelfModelSessionOverlay(
      key: key,
      selectedProject: selectedProject == null
          ? null
          : <String, Object?>{
              'id': selectedProject.id,
              'name': selectedProject.name,
              'rootPath': selectedProject.rootPath,
            },
      selectedModel: selectedModel == null
          ? null
          : <String, Object?>{
              'providerId': selectedModel.providerId,
              'name': selectedModel.name,
              'digest': selectedModel.digest,
              'exactId': selectedModel.exactId,
            },
    );

/// Authoritative bounded ProductRuntime adapter. Provider discovery is cached
/// independently from the five-second monitor tick and records each provider's
/// success/failure instead of treating an empty aggregate list as proof that
/// every provider was healthy.
final class ProductRuntimeSnapshotProvider implements ApplicationSnapshotProvider {
  ProductRuntimeSnapshotProvider({
    required this.runtime,
    this.maxProjects = 20,
    this.maxRuns = 10,
    this.maxModels = 30,
    this.modelDiscoveryBudget = const Duration(seconds: 20),
  });

  final ProductRuntime runtime;
  final int maxProjects;
  final int maxRuns;
  final int maxModels;
  final Duration modelDiscoveryBudget;

  DateTime? _modelCapturedAt;
  List<ModelIdentity> _modelCache = const <ModelIdentity>[];
  List<Map<String, Object?>> _providerCache = const <Map<String, Object?>>[];

  @override
  Future<ApplicationSnapshot> capture({
    bool forceRefresh = false,
    SelfModelSessionOverlay overlay = const SelfModelSessionOverlay(),
  }) async {
    final now = DateTime.now().toUtc();
    final projects = await runtime.listProjects();
    final boundedProjects = projects
        .take(maxProjects)
        .map((project) => <String, Object?>{
              'id': project.id,
              'name': project.name,
              'rootPath': project.rootPath,
              'updatedAt': project.updatedAt.toIso8601String(),
            })
        .toList(growable: false);

    final runs = await runtime.listRuns(limit: maxRuns);
    final runState = <String, Object?>{
      'recent': runs
          .map((run) => <String, Object?>{
                'id': run.id,
                'status': run.state.name,
                'projectId': run.command.contract.projectId,
                'updatedAt': run.updatedAt.toIso8601String(),
              })
          .toList(growable: false),
    };

    await _refreshModels(now, forceRefresh: forceRefresh);
    final models = _modelCache.take(maxModels).toList(growable: false);
    final selectedModel = overlay.selectedModel;
    final selectedExactId = selectedModel?['exactId']?.toString();
    final selectedModelLive = selectedExactId != null &&
        models.any((model) => model.exactId == selectedExactId);
    final selectedProject = overlay.selectedProject;
    final selectedProjectId = selectedProject?['id']?.toString();
    final selectedProjectLive = selectedProjectId != null &&
        projects.any((project) => project.id == selectedProjectId);

    final browser = runtime.p3BrowserRuntime;
    final owner = runtime.p2OwnerMode;
    final recentFailures = runs
        .where((run) => run.state == RunState.failed)
        .take(5)
        .map((run) => <String, Object?>{
              'runId': run.id,
              'projectId': run.command.contract.projectId,
              'failure': run.failure ?? '',
              'updatedAt': run.updatedAt.toIso8601String(),
            })
        .toList(growable: false);

    final providerFailures = _providerCache
        .where((item) => item['status'] == 'failed')
        .length;
    final modelEvidenceConfidence = providerFailures == 0
        ? ObservationConfidence.high
        : ObservationConfidence.medium;

    return ApplicationSnapshot(
      capturedAt: now,
      applicationIdentity: 'kris.ai',
      platform: Platform.operatingSystem,
      build: <String, Object?>{'runtime': Platform.version},
      health: <String, Object?>{
        'runtimeOpen': true,
        'browserAvailable': browser.available,
        'ownerAvailable': owner.available,
        'ownerCompletionEligible': owner.completionEligible,
        'providerFailures': providerFailures,
      },
      selectedProject: selectedProject == null
          ? null
          : <String, Object?>{
              ...selectedProject,
              'known': selectedProjectLive,
            },
      knownProjects: boundedProjects,
      selectedModel: selectedModel == null
          ? null
          : <String, Object?>{
              ...selectedModel,
              'discovered': selectedModelLive,
            },
      availableModels: models
          .map((model) => <String, Object?>{
                'providerId': model.providerId,
                'name': model.name,
                'digest': model.digest,
                'exactId': model.exactId,
                'selected': model.exactId == selectedExactId,
              })
          .toList(growable: false),
      providers: List<Map<String, Object?>>.unmodifiable(_providerCache),
      runState: runState,
      authority: <String, Object?>{
        'ownerCompletionEligible': owner.completionEligible,
        'ownerSecureIsolationActive': owner.secureIsolationActive,
        // No operation-specific grant has been evaluated in a snapshot.
        'state': AuthorityObservationState.notEvaluated.name,
        'granted': const <String>[],
      },
      ownerMode: <String, Object?>{
        'available': owner.available,
        'completionEligible': owner.completionEligible,
        'secureIsolationActive': owner.secureIsolationActive,
        'diagnosticCode': owner.diagnosticCode,
        'provenance': owner.runtimeProvenance,
      },
      browser: <String, Object?>{
        'available': browser.available,
        'statusCode': browser.statusCode,
        'provenance': browser.provenance,
      },
      research: <String, Object?>{
        'service': runtime.research.runtimeType.toString(),
        'localOnly': runtime.settings.localOnly,
      },
      recentFailures: recentFailures,
      knowledgeEvidence: <String, KnowledgeEvidence>{
        'platform': KnowledgeEvidence(
          kind: KnowledgeEvidenceKind.observed,
          source: 'dart:io.Platform.operatingSystem',
          confidence: ObservationConfidence.certain,
          observedAt: now,
        ),
        'projects': KnowledgeEvidence(
          kind: KnowledgeEvidenceKind.observed,
          source: 'ProductRuntime.listProjects',
          confidence: ObservationConfidence.high,
          observedAt: now,
          expiresAt: now.add(const Duration(seconds: 15)),
        ),
        'runs': KnowledgeEvidence(
          kind: KnowledgeEvidenceKind.observed,
          source: 'ProductRuntime.listRuns',
          confidence: ObservationConfidence.high,
          observedAt: now,
          expiresAt: now.add(const Duration(seconds: 5)),
        ),
        'models': KnowledgeEvidence(
          kind: KnowledgeEvidenceKind.observed,
          source: 'ModelRegistry.providers.discover',
          confidence: modelEvidenceConfidence,
          observedAt: _modelCapturedAt ?? now,
          expiresAt: (_modelCapturedAt ?? now).add(modelDiscoveryBudget),
          detail: providerFailures == 0
              ? 'All configured providers completed discovery.'
              : '$providerFailures configured provider(s) failed discovery; failures are represented explicitly.',
        ),
        'browser': KnowledgeEvidence(
          kind: KnowledgeEvidenceKind.observed,
          source: 'ProductRuntime.p3BrowserRuntime',
          confidence: ObservationConfidence.high,
          observedAt: now,
          expiresAt: now.add(const Duration(seconds: 5)),
        ),
        'ownerMode': KnowledgeEvidence(
          kind: KnowledgeEvidenceKind.observed,
          source: 'ProductRuntime.p2OwnerMode',
          confidence: ObservationConfidence.high,
          observedAt: now,
          expiresAt: now.add(const Duration(seconds: 2)),
        ),
        'authority': KnowledgeEvidence(
          kind: KnowledgeEvidenceKind.observed,
          source: 'self_model.execution_authority_projection',
          confidence: ObservationConfidence.certain,
          observedAt: now,
          expiresAt: now,
          detail:
              'Operation authority has not been evaluated. Runtime availability is never treated as a grant.',
        ),
      },
    );
  }

  Future<void> _refreshModels(
    DateTime now, {
    required bool forceRefresh,
  }) async {
    final captured = _modelCapturedAt;
    if (!forceRefresh &&
        captured != null &&
        now.difference(captured) < modelDiscoveryBudget) {
      return;
    }
    final models = <ModelIdentity>[];
    final providers = <Map<String, Object?>>[];
    for (final provider in runtime.models.providers()) {
      final started = Stopwatch()..start();
      try {
        final discovered = await provider.discover().timeout(
              const Duration(seconds: 12),
            );
        started.stop();
        models.addAll(discovered);
        providers.add(<String, Object?>{
          'id': provider.id,
          'status': discovered.isEmpty ? 'empty' : 'available',
          'modelCount': discovered.length,
          'latencyMs': started.elapsedMilliseconds,
        });
      } catch (error) {
        started.stop();
        providers.add(<String, Object?>{
          'id': provider.id,
          'status': 'failed',
          'modelCount': 0,
          'latencyMs': started.elapsedMilliseconds,
          'error': runtime.redactor.redact('$error'),
        });
      }
    }
    models.sort((a, b) => a.exactId.compareTo(b.exactId));
    providers.sort(
      (a, b) => a['id'].toString().compareTo(b['id'].toString()),
    );
    _modelCache = List<ModelIdentity>.unmodifiable(models);
    _providerCache = List<Map<String, Object?>>.unmodifiable(providers);
    _modelCapturedAt = now;
  }
}

List<CapabilitySatisfactionStep> _projectSatisfactionPath() =>
    const <CapabilitySatisfactionStep>[
      CapabilitySatisfactionStep(
        id: 'select_project',
        description:
            'Select an existing project whose identity is present in the current project repository.',
        condition: 'The selected project exists in a fresh project snapshot.',
      ),
    ];

List<CapabilitySatisfactionStep> _modelSatisfactionPath() =>
    const <CapabilitySatisfactionStep>[
      CapabilitySatisfactionStep(
        id: 'select_live_model',
        description:
            'Select a model whose exact identity is present in fresh provider discovery.',
        condition: 'The selected model appears in a fresh provider observation.',
      ),
    ];

KristinCapabilityRegistry buildProductCapabilityRegistry(ProductRuntime runtime) {
  final registry = KristinCapabilityRegistry();
  registry.register(ChatCapabilityProvider(
    availabilityResolver: (capability, descriptor, snapshot) async {
      final evidence = <KnowledgeEvidence>[
        KnowledgeEvidence(
          kind: KnowledgeEvidenceKind.observed,
          source: 'product_runtime.chat_capability_resolver',
          confidence: ObservationConfidence.high,
          observedAt: snapshot.capturedAt,
          expiresAt: descriptor.freshnessBudget == Duration.zero
              ? snapshot.capturedAt
              : snapshot.capturedAt.add(descriptor.freshnessBudget),
        ),
      ];
      if (descriptor.projectRequired) {
        final selected = snapshot.selectedProject;
        if (selected == null || selected['known'] != true) {
          return CapabilityAvailability(
            capabilityId: descriptor.id,
            state: CapabilityAvailabilityState.projectRequired,
            reasons: const <String>[
              'A live selected project is required for this capability.',
            ],
            missingPrerequisites: const <String>{'selectedProject'},
            requiredAuthority: descriptor.permissionRequirements,
            authorityObservation: descriptor.permissionRequirements.isEmpty
                ? AuthorityObservationState.notRequired
                : AuthorityObservationState.notEvaluated,
            observedAt: snapshot.capturedAt,
            evidence: evidence,
            satisfactionPath: _projectSatisfactionPath(),
          );
        }
      }
      if (descriptor.modelProviderRequired) {
        final selected = snapshot.selectedModel;
        if (selected == null || selected['discovered'] != true) {
          return CapabilityAvailability(
            capabilityId: descriptor.id,
            state: CapabilityAvailabilityState.modelProviderMissing,
            reasons: <String>[
              selected == null
                  ? 'No model/provider is selected for substantial planning.'
                  : 'Selected model ${selected['exactId']} is not present in fresh provider discovery.',
            ],
            missingPrerequisites: const <String>{'liveSelectedModel'},
            requiredAuthority: descriptor.permissionRequirements,
            authorityObservation: descriptor.permissionRequirements.isEmpty
                ? AuthorityObservationState.notRequired
                : AuthorityObservationState.notEvaluated,
            observedAt: snapshot.capturedAt,
            evidence: evidence,
            satisfactionPath: _modelSatisfactionPath(),
          );
        }
      }
      if (capability.route == ChatExecutionRoute.researchSearch &&
          snapshot.research['localOnly'] == true) {
        return CapabilityAvailability(
          capabilityId: descriptor.id,
          state: CapabilityAvailabilityState.blocked,
          reasons: const <String>[
            'Web research is disabled by the current local-only setting.',
          ],
          missingPrerequisites: const <String>{'networkResearchEnabled'},
          requiredAuthority: descriptor.permissionRequirements,
          authorityObservation: AuthorityObservationState.notEvaluated,
          observedAt: snapshot.capturedAt,
          evidence: evidence,
          satisfactionPath: const <CapabilitySatisfactionStep>[
            CapabilitySatisfactionStep(
              id: 'enable_network_research',
              description:
                  'Change the governed local-only setting before attempting network research.',
              condition: 'Network research is enabled by user-controlled settings.',
              automatic: false,
            ),
          ],
        );
      }
      if (capability.route == ChatExecutionRoute.ownerMode) {
        final available = snapshot.ownerMode['available'] == true;
        final eligible = snapshot.ownerMode['completionEligible'] == true;
        return CapabilityAvailability(
          capabilityId: descriptor.id,
          state: !available
              ? CapabilityAvailabilityState.ownerAuthorityUnavailable
              : eligible
                  ? CapabilityAvailabilityState.approvalRequired
                  : CapabilityAvailabilityState.additionalAuthorityRequired,
          reasons: <String>[
            if (!available)
              'Owner Mode runtime is unavailable: ${snapshot.ownerMode['diagnosticCode']}.'
            else if (!eligible)
              'Owner Mode is present but its isolated authority service is not completion-eligible.'
            else
              'Owner Mode exists, but authority has not been evaluated for a concrete operation.',
          ],
          requiredAuthority: <String>{
            ...descriptor.permissionRequirements,
            'owner',
          },
          currentAuthority: const <String>{},
          authorityObservation: AuthorityObservationState.notEvaluated,
          observedAt: snapshot.capturedAt,
          evidence: evidence,
          satisfactionPath: const <CapabilitySatisfactionStep>[
            CapabilitySatisfactionStep(
              id: 'verify_owner_runtime',
              description:
                  'Verify that the isolated Owner runtime is available and completion-eligible.',
              condition: 'Owner runtime probe is healthy.',
            ),
            CapabilitySatisfactionStep(
              id: 'obtain_owner_grant',
              description:
                  'Evaluate and obtain explicit Owner authority for the specific operation.',
              condition:
                  'The authority service returns a valid per-operation grant.',
              requiredAuthority: <String>{'owner'},
              automatic: false,
            ),
          ],
        );
      }
      return CapabilityAvailability(
        capabilityId: descriptor.id,
        state: CapabilityAvailabilityState.available,
        reasons: const <String>['Runtime prerequisites are currently satisfied.'],
        requiredAuthority: descriptor.permissionRequirements,
        authorityObservation: descriptor.permissionRequirements.isEmpty
            ? AuthorityObservationState.notRequired
            : AuthorityObservationState.notEvaluated,
        observedAt: snapshot.capturedAt,
        evidence: evidence,
      );
    },
  ));

  registry.register(RuntimeCapabilityProvider(
    providerId: 'browser.runtime',
    descriptors: const <CapabilityDescriptor>[
      CapabilityDescriptor(
        id: 'browser.navigate',
        name: 'Browser navigation',
        description:
            'Open and inspect a public web page using the application-owned Browser runtime.',
        semanticPurpose:
            'Rendered-page observation for governed browsing/research flows.',
        category: 'connections',
        acceptedTargets: <String>{'url'},
        riskClass: CapabilityRiskClass.readOnly,
        readOnly: true,
        networkRequired: true,
        browserRequired: true,
        directlyExecutable: false,
        recoveryParticipant: true,
        limitations: <String>[
          'Availability depends on the packaged/provisioned Browser runtime.',
        ],
        freshnessBudget: Duration(seconds: 5),
        healthFreshnessBudget: Duration(seconds: 35),
        probeInterval: Duration(seconds: 30),
        providerId: 'browser.runtime',
      ),
    ],
    resolver: (descriptor, snapshot) async {
      final available = snapshot.browser['available'] == true;
      return CapabilityAvailability(
        capabilityId: descriptor.id,
        state: available
            ? CapabilityAvailabilityState.available
            : CapabilityAvailabilityState.browserUnavailable,
        reasons: <String>[
          available
              ? 'The application-owned Browser runtime is provisioned.'
              : 'Browser runtime unavailable: ${snapshot.browser['statusCode']}.',
        ],
        missingPrerequisites:
            available ? const <String>{} : const <String>{'browserRuntime'},
        authorityObservation: AuthorityObservationState.notRequired,
        observedAt: snapshot.capturedAt,
        evidence: <KnowledgeEvidence>[
          KnowledgeEvidence(
            kind: KnowledgeEvidenceKind.observed,
            source: 'ProductRuntime.p3BrowserRuntime',
            confidence: ObservationConfidence.high,
            observedAt: snapshot.capturedAt,
            expiresAt: snapshot.capturedAt.add(descriptor.freshnessBudget),
          ),
        ],
        satisfactionPath: available
            ? const <CapabilitySatisfactionStep>[]
            : const <CapabilitySatisfactionStep>[
                CapabilitySatisfactionStep(
                  id: 'provision_browser_runtime',
                  description:
                      'Provision or refresh the application-owned Browser runtime.',
                  condition: 'Browser runtime handle reports available.',
                ),
                CapabilitySatisfactionStep(
                  id: 'probe_browser_runtime',
                  description:
                      'Run a lightweight Browser startup/shutdown probe.',
                  condition: 'Browser consistency probe reports healthy.',
                ),
              ],
      );
    },
    healthResolver: (descriptor, snapshot, availability) async {
      final available = snapshot.browser['available'] == true;
      return CapabilityHealth(
        capabilityId: descriptor.id,
        state: available
            ? CapabilityHealthState.degraded
            : CapabilityHealthState.failing,
        reasons: <String>[
          available
              ? 'Browser bundle exists; the startup probe is the stronger health signal.'
              : 'Browser handle is not available: ${snapshot.browser['statusCode']}.',
        ],
        observedAt: snapshot.capturedAt,
        expiresAt: snapshot.capturedAt.add(descriptor.healthFreshnessBudget),
        evidence: <KnowledgeEvidence>[
          KnowledgeEvidence(
            kind: KnowledgeEvidenceKind.observed,
            source: 'ProductRuntime.p3BrowserRuntime.handle',
            confidence: ObservationConfidence.high,
            observedAt: snapshot.capturedAt,
            expiresAt:
                snapshot.capturedAt.add(descriptor.healthFreshnessBudget),
          ),
        ],
      );
    },
  ));

  registry.register(RuntimeCapabilityProvider(
    providerId: 'owner.recovery',
    descriptors: const <CapabilityDescriptor>[
      CapabilityDescriptor(
        id: 'owner.recovery.actuate',
        name: 'Owner recovery actuator',
        description:
            'Perform explicitly-authorized host-level recovery effects through Owner Mode.',
        semanticPurpose:
            'Controlled recovery actuator; capability knowledge never grants its authority.',
        category: 'system',
        riskClass: CapabilityRiskClass.sensitive,
        readOnly: false,
        mutatesHostState: true,
        authorityClass: CapabilityAuthorityClass.owner,
        permissionRequirements: <String>{'owner'},
        filesystemRequired: true,
        processRequired: true,
        directlyExecutable: false,
        recoveryParticipant: true,
        limitations: <String>[
          'Every effect remains subject to Owner Mode authority and approval policy.',
        ],
        freshnessBudget: Duration.zero,
        healthFreshnessBudget: Duration(seconds: 12),
        probeInterval: Duration(seconds: 10),
        providerId: 'owner.recovery',
      ),
    ],
    resolver: (descriptor, snapshot) async {
      final available = snapshot.ownerMode['available'] == true;
      final eligible = snapshot.ownerMode['completionEligible'] == true;
      return CapabilityAvailability(
        capabilityId: descriptor.id,
        state: !available
            ? CapabilityAvailabilityState.ownerAuthorityUnavailable
            : eligible
                ? CapabilityAvailabilityState.approvalRequired
                : CapabilityAvailabilityState.additionalAuthorityRequired,
        reasons: <String>[
          if (!available)
            'Owner Mode runtime is unavailable.'
          else if (!eligible)
            'Owner Mode exists but its isolated authority service is not completion-eligible.'
          else
            'Owner recovery exists, but operation authority has not been evaluated.',
        ],
        requiredAuthority: const <String>{'owner'},
        currentAuthority: const <String>{},
        authorityObservation: AuthorityObservationState.notEvaluated,
        observedAt: snapshot.capturedAt,
        evidence: <KnowledgeEvidence>[
          KnowledgeEvidence(
            kind: KnowledgeEvidenceKind.observed,
            source: 'ProductRuntime.p2OwnerMode',
            confidence: ObservationConfidence.high,
            observedAt: snapshot.capturedAt,
            expiresAt: snapshot.capturedAt,
          ),
        ],
        satisfactionPath: const <CapabilitySatisfactionStep>[
          CapabilitySatisfactionStep(
            id: 'verify_owner_runtime',
            description: 'Verify isolated Owner runtime readiness.',
            condition: 'Owner runtime is available and completion-eligible.',
          ),
          CapabilitySatisfactionStep(
            id: 'obtain_owner_authority',
            description:
                'Evaluate and obtain explicit authority for the concrete recovery operation.',
            condition: 'Authority service returns a valid grant.',
            requiredAuthority: <String>{'owner'},
            automatic: false,
          ),
        ],
      );
    },
    healthResolver: (descriptor, snapshot, availability) async {
      final available = snapshot.ownerMode['available'] == true;
      final eligible = snapshot.ownerMode['completionEligible'] == true;
      final isolated = snapshot.ownerMode['secureIsolationActive'] == true;
      return CapabilityHealth(
        capabilityId: descriptor.id,
        state: !available
            ? CapabilityHealthState.failing
            : eligible && isolated
                ? CapabilityHealthState.healthy
                : CapabilityHealthState.degraded,
        reasons: <String>[
          if (!available)
            'Owner runtime is unavailable.'
          else if (!eligible || !isolated)
            'Owner runtime exists but completion eligibility or secure isolation is not active.'
          else
            'Owner runtime is isolated and completion-eligible; operation authority is still separate.',
        ],
        observedAt: snapshot.capturedAt,
        lastVerifiedAt: snapshot.capturedAt,
        expiresAt: snapshot.capturedAt.add(descriptor.healthFreshnessBudget),
        evidence: <KnowledgeEvidence>[
          KnowledgeEvidence(
            kind: KnowledgeEvidenceKind.observed,
            source: 'ProductRuntime.p2OwnerMode.health',
            confidence: ObservationConfidence.high,
            observedAt: snapshot.capturedAt,
            expiresAt:
                snapshot.capturedAt.add(descriptor.healthFreshnessBudget),
          ),
        ],
      );
    },
  ));
  return registry;
}

/// One application-global observer per ProductRuntime. Session/project/model
/// selection is passed as an overlay to each query and is never stored here.
final class ProductSelfAwarenessRuntime {
  factory ProductSelfAwarenessRuntime.shared(ProductRuntime runtime) {
    final existing = _shared[runtime];
    if (existing != null) return existing;
    final created = ProductSelfAwarenessRuntime._(runtime);
    _shared[runtime] = created;
    return created;
  }

  ProductSelfAwarenessRuntime._(this.runtime) {
    snapshotProvider = ProductRuntimeSnapshotProvider(runtime: runtime);
    selfModel = KristinSelfModelService(
      registry: buildProductCapabilityRegistry(runtime),
      application: snapshotProvider,
    );
    queries = SelfAwarenessQueryService(selfModel);
    causalGraph = CausalStateGraph();
    integrity = SelfIntegrityMonitor(defaultKristinSelfInvariants());
    consistency = SelfConsistencyMonitor(
      selfModel: selfModel,
      probes: <SelfConsistencyProbe>[
        CallbackSelfConsistencyProbe(
          id: 'browser.runtime.startup',
          interval: const Duration(seconds: 30),
          callback: _probeBrowser,
        ),
        CallbackSelfConsistencyProbe(
          id: 'owner.runtime.readiness',
          interval: const Duration(seconds: 10),
          callback: _probeOwner,
        ),
        CallbackSelfConsistencyProbe(
          id: 'model.selection.discovery',
          interval: const Duration(seconds: 20),
          appliesTo: (overlay) => overlay.selectedModel != null,
          callback: _probeSelectedModel,
        ),
      ],
      onResult: (result) async {
        causalGraph.recordObservation(
          'self_probe.${result.probeId}',
          attributes: result.toJson(),
          confidence: result.status == ProbeStatus.skipped
              ? ObservationConfidence.low
              : ObservationConfidence.high,
        );
      },
    )..start(tick: const Duration(seconds: 5));
    _runtimeEvents = runtime.eventStream.listen(
      _scheduleRuntimeRefresh,
      onDone: () {
        _eventDebounce?.cancel();
        unawaited(consistency.close());
        unawaited(selfModel.close());
      },
    );
  }

  static final Expando<ProductSelfAwarenessRuntime> _shared =
      Expando<ProductSelfAwarenessRuntime>('kristin-self-awareness');

  final ProductRuntime runtime;
  late final ProductRuntimeSnapshotProvider snapshotProvider;
  late final KristinSelfModelService selfModel;
  late final SelfAwarenessQueryService queries;
  late final CausalStateGraph causalGraph;
  late final SelfIntegrityMonitor integrity;
  late final SelfConsistencyMonitor consistency;
  StreamSubscription<EventEnvelope>? _runtimeEvents;
  Timer? _eventDebounce;
  EventEnvelope? _lastRuntimeEvent;
  final Map<String, List<SelfInvariantViolation>> _integrityByOverlay =
      <String, List<SelfInvariantViolation>>{};

  Stream<SelfModelChange> get changes => selfModel.changes;

  SelfModelSessionOverlay overlay({
    String key = 'chat',
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) =>
      productSelfOverlay(
        key: key,
        selectedProject: selectedProject,
        selectedModel: selectedModel,
      );

  Future<KristinSelfSnapshot> snapshot({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    String sessionKey = 'chat',
    bool forceRefresh = false,
  }) async {
    final session = overlay(
      key: sessionKey,
      selectedProject: selectedProject,
      selectedModel: selectedModel,
    );
    await consistency.runDue(overlay: session);
    final value = await selfModel.snapshot(
      forceRefresh: forceRefresh,
      source: 'product_runtime.self_awareness',
      reason: forceRefresh ? 'forced_snapshot' : 'snapshot',
      overlay: session,
    );
    _integrityByOverlay[session.cacheKey] = integrity.checkSnapshot(value);
    return value;
  }

  Future<SelfModelPlanningContext> planningContext({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    String sessionKey = 'chat',
    Set<String> relevantCapabilityIds = const <String>{},
  }) async {
    final session = overlay(
      key: sessionKey,
      selectedProject: selectedProject,
      selectedModel: selectedModel,
    );
    await consistency.runDue(overlay: session);
    return selfModel.planningContext(
      relevantCapabilityIds: relevantCapabilityIds,
      overlay: session,
    );
  }

  Future<CapabilityRequirementReport> requirementsFor(
    String capabilityId, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    String sessionKey = 'chat',
  }) {
    final session = overlay(
      key: sessionKey,
      selectedProject: selectedProject,
      selectedModel: selectedModel,
    );
    return queries.requirementsFor(capabilityId, overlay: session);
  }

  Future<List<KnownCapability>> capabilitiesFor(
    String objective, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    String sessionKey = 'chat',
  }) {
    final session = overlay(
      key: sessionKey,
      selectedProject: selectedProject,
      selectedModel: selectedModel,
    );
    return queries.capabilitiesFor(objective, overlay: session);
  }

  List<SelfModelChange> changesSince(
    DateTime since, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    String sessionKey = 'chat',
  }) {
    final session = overlay(
      key: sessionKey,
      selectedProject: selectedProject,
      selectedModel: selectedModel,
    );
    return queries.whatChangedSince(since, overlayKey: session.cacheKey);
  }

  Future<List<SelfInvariantViolation>> integrityReport({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    String sessionKey = 'chat',
  }) async {
    final value = await snapshot(
      selectedProject: selectedProject,
      selectedModel: selectedModel,
      sessionKey: sessionKey,
      forceRefresh: true,
    );
    final session = value.overlay.cacheKey;
    final violations = integrity.checkSnapshot(value);
    _integrityByOverlay[session] = violations;
    return List<SelfInvariantViolation>.unmodifiable(violations);
  }

  Future<List<SelfConsistencyProbeResult>> runProbes({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    String sessionKey = 'chat',
    bool force = true,
  }) =>
      consistency.runDue(
        force: force,
        overlay: overlay(
          key: sessionKey,
          selectedProject: selectedProject,
          selectedModel: selectedModel,
        ),
      );

  Future<T> observeOperation<T>(
    String operation,
    Map<String, Object?> attributes,
    Future<T> Function() action, {
    bool stateChanging = true,
  }) async {
    final actionNode = causalGraph.recordAction(operation, attributes: attributes);
    try {
      final result = await action();
      if (stateChanging) {
        causalGraph.recordStateChange(
          '$operation.completed',
          causedBy: <String>[actionNode.id],
          attributes: attributes,
        );
        await selfModel.notifyStateChanged(
          source: 'product_runtime.operation',
          reason: operation,
        );
      } else {
        causalGraph.recordObservation(
          '$operation.observed',
          observedAfter: <String>[actionNode.id],
          attributes: attributes,
        );
      }
      return result;
    } catch (error) {
      causalGraph.recordFailure(
        '$operation.failed',
        causedBy: <String>[actionNode.id],
        attributes: <String, Object?>{
          ...attributes,
          'errorType': error.runtimeType.toString(),
          'error': runtime.redactor.redact('$error'),
        },
      );
      await selfModel.notifyStateChanged(
        source: 'product_runtime.operation_failure',
        reason: operation,
      );
      rethrow;
    }
  }

  void _scheduleRuntimeRefresh(EventEnvelope event) {
    _lastRuntimeEvent = event;
    _eventDebounce?.cancel();
    _eventDebounce = Timer(const Duration(milliseconds: 150), () {
      final latest = _lastRuntimeEvent;
      if (latest != null) unawaited(_processRuntimeEvent(latest));
    });
  }

  Future<void> _processRuntimeEvent(EventEnvelope event) async {
    causalGraph.recordObservation(
      'runtime.event.${event.type}',
      attributes: <String, Object?>{
        'sequence': event.sequence,
        'type': event.type,
        'correlationId': event.correlationId,
      },
      confidence: ObservationConfidence.high,
    );
    const runtimeOverlay = SelfModelSessionOverlay();
    await consistency.runDue(overlay: runtimeOverlay);
    final latest = await selfModel.notifyStateChanged(
      source: 'runtime.event.${event.type}',
      reason: 'durable_runtime_event',
      overlay: runtimeOverlay,
    );
    _integrityByOverlay[runtimeOverlay.cacheKey] =
        integrity.checkSnapshot(latest);
  }

  Future<SelfConsistencyProbeResult> _probeBrowser(
    KristinSelfSnapshot snapshot,
    SelfModelSessionOverlay overlay,
  ) async {
    final browser = runtime.p3BrowserRuntime;
    final affected = snapshot.capabilities
        .where((item) => item.descriptor.browserRequired)
        .map((item) => item.descriptor.id)
        .toSet()
      ..add('browser.navigate');
    if (!browser.available) {
      return SelfConsistencyProbeResult(
        probeId: 'browser.runtime.startup',
        capabilityIds: affected,
        status: ProbeStatus.failing,
        message: 'Browser runtime is unavailable: ${browser.statusCode}.',
        validFor: const Duration(seconds: 35),
      );
    }
    final watch = Stopwatch()..start();
    try {
      await browser.probe(startupTimeout: const Duration(seconds: 10));
      watch.stop();
      return SelfConsistencyProbeResult(
        probeId: 'browser.runtime.startup',
        capabilityIds: affected,
        status: ProbeStatus.healthy,
        message: 'Browser startup/shutdown probe completed successfully.',
        latency: watch.elapsed,
        validFor: const Duration(seconds: 35),
      );
    } catch (error) {
      watch.stop();
      return SelfConsistencyProbeResult(
        probeId: 'browser.runtime.startup',
        capabilityIds: affected,
        status: ProbeStatus.failing,
        message: 'Browser probe failed: ${runtime.redactor.redact('$error')}',
        latency: watch.elapsed,
        validFor: const Duration(seconds: 35),
      );
    }
  }

  Future<SelfConsistencyProbeResult> _probeOwner(
    KristinSelfSnapshot snapshot,
    SelfModelSessionOverlay overlay,
  ) async {
    final owner = runtime.p2OwnerMode;
    final affected = snapshot.capabilities
        .where((item) =>
            item.descriptor.authorityClass == CapabilityAuthorityClass.owner)
        .map((item) => item.descriptor.id)
        .toSet()
      ..add('owner.recovery.actuate');
    if (!owner.available) {
      return SelfConsistencyProbeResult(
        probeId: 'owner.runtime.readiness',
        capabilityIds: affected,
        status: ProbeStatus.failing,
        message: 'Owner runtime is unavailable: ${owner.diagnosticCode}.',
        validFor: const Duration(seconds: 12),
      );
    }
    if (!owner.completionEligible || !owner.secureIsolationActive) {
      return SelfConsistencyProbeResult(
        probeId: 'owner.runtime.readiness',
        capabilityIds: affected,
        status: ProbeStatus.degraded,
        message:
            'Owner runtime exists but completion eligibility or secure isolation is not active.',
        validFor: const Duration(seconds: 12),
      );
    }
    return SelfConsistencyProbeResult(
      probeId: 'owner.runtime.readiness',
      capabilityIds: affected,
      status: ProbeStatus.healthy,
      message:
          'Owner runtime is isolated and completion-eligible; this observation grants no operation authority.',
      validFor: const Duration(seconds: 12),
    );
  }

  Future<SelfConsistencyProbeResult> _probeSelectedModel(
    KristinSelfSnapshot snapshot,
    SelfModelSessionOverlay overlay,
  ) async {
    final selected = overlay.selectedModel;
    if (selected == null) {
      return SelfConsistencyProbeResult(
        probeId: 'model.selection.discovery',
        status: ProbeStatus.skipped,
        message: 'No model is selected, so there is no model identity to probe.',
      );
    }
    final exactId = selected['exactId']?.toString() ?? '';
    final affected = snapshot.capabilities
        .where((item) => item.descriptor.modelProviderRequired)
        .map((item) => item.descriptor.id)
        .toSet();
    final watch = Stopwatch()..start();
    try {
      final refreshed = await snapshotProvider.capture(
        forceRefresh: true,
        overlay: overlay,
      );
      final present = refreshed.availableModels
          .any((model) => model['exactId']?.toString() == exactId);
      watch.stop();
      return SelfConsistencyProbeResult(
        probeId: 'model.selection.discovery',
        capabilityIds: affected,
        status: present ? ProbeStatus.healthy : ProbeStatus.failing,
        message: present
            ? 'Selected model $exactId is present in fresh provider discovery.'
            : 'Selected model $exactId is no longer present in provider discovery.',
        latency: watch.elapsed,
        validFor: const Duration(seconds: 25),
        attributes: <String, Object?>{'selectedModel': exactId},
      );
    } catch (error) {
      watch.stop();
      return SelfConsistencyProbeResult(
        probeId: 'model.selection.discovery',
        capabilityIds: affected,
        status: ProbeStatus.failing,
        message:
            'Selected model discovery probe failed: ${runtime.redactor.redact('$error')}',
        latency: watch.elapsed,
        validFor: const Duration(seconds: 25),
        attributes: <String, Object?>{'selectedModel': exactId},
      );
    }
  }
}

/// One-shot adapter retained for narrow callers. Stateful product flows should
/// use ProductSelfAwarenessRuntime.shared so history/probes remain continuous.
KristinSelfModelService buildProductSelfModel(
  ProductRuntime runtime, {
  ProjectRecord? selectedProject,
  ModelIdentity? selectedModel,
}) {
  final provider = ProductRuntimeSnapshotProvider(runtime: runtime);
  return KristinSelfModelService(
    registry: buildProductCapabilityRegistry(runtime),
    application: _FixedOverlaySnapshotProvider(
      provider,
      productSelfOverlay(
        selectedProject: selectedProject,
        selectedModel: selectedModel,
      ),
    ),
  );
}

final class _FixedOverlaySnapshotProvider implements ApplicationSnapshotProvider {
  const _FixedOverlaySnapshotProvider(this.delegate, this.fixedOverlay);
  final ApplicationSnapshotProvider delegate;
  final SelfModelSessionOverlay fixedOverlay;

  @override
  Future<ApplicationSnapshot> capture({
    bool forceRefresh = false,
    SelfModelSessionOverlay overlay = const SelfModelSessionOverlay(),
  }) =>
      delegate.capture(forceRefresh: forceRefresh, overlay: fixedOverlay);
}
