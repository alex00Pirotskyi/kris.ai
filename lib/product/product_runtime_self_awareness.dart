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
      evidence: <KnowledgeEvidence>[
        KnowledgeEvidence(
          kind: KnowledgeEvidenceKind.inferred,
          source: '$providerId.availability',
          confidence: ObservationConfidence.medium,
          observedAt: now,
        ),
      ],
    );
  }
}

/// Authoritative bounded snapshot adapter for ProductRuntime.
///
/// Selection is session state supplied by Chat. Projects, runs, models,
/// Browser and Owner status come from canonical runtime owners. Field evidence
/// records how each important fact was learned so the model can distinguish
/// observation from inference or configuration.
final class ProductRuntimeSnapshotProvider implements ApplicationSnapshotProvider {
  const ProductRuntimeSnapshotProvider({
    required this.runtime,
    this.selectedProject,
    this.selectedModel,
    this.selectedProjectProvider,
    this.selectedModelProvider,
    this.maxProjects = 20,
    this.maxRuns = 10,
    this.maxModels = 30,
  });

  final ProductRuntime runtime;
  final ProjectRecord? selectedProject;
  final ModelIdentity? selectedModel;
  final ProjectRecord? Function()? selectedProjectProvider;
  final ModelIdentity? Function()? selectedModelProvider;
  final int maxProjects;
  final int maxRuns;
  final int maxModels;

  ProjectRecord? get _selectedProject =>
      selectedProjectProvider?.call() ?? selectedProject;
  ModelIdentity? get _selectedModel => selectedModelProvider?.call() ?? selectedModel;

  @override
  Future<ApplicationSnapshot> capture() async {
    final now = DateTime.now().toUtc();
    final projects = await runtime.listProjects();
    final boundedProjects = projects.take(maxProjects).map((project) =>
        <String, Object?>{
          'id': project.id,
          'name': project.name,
          'rootPath': project.rootPath,
          'updatedAt': project.updatedAt.toIso8601String(),
        }).toList(growable: false);

    final runs = await runtime.listRuns(limit: maxRuns);
    final runState = <String, Object?>{
      'recent': runs.map((run) => <String, Object?>{
        'id': run.id,
        'status': run.state.name,
        'projectId': run.command.contract.projectId,
        'updatedAt': run.updatedAt.toIso8601String(),
      }).toList(growable: false),
    };

    List<ModelIdentity> discoveredModels;
    try {
      discoveredModels = await runtime.discoverModels();
    } catch (_) {
      final selected = _selectedModel;
      discoveredModels = selected == null
          ? <ModelIdentity>[]
          : <ModelIdentity>[selected];
    }
    final boundedModels = discoveredModels.take(maxModels).toList(growable: false);
    final providersById = <String, Map<String, Object?>>{};
    for (final model in boundedModels) {
      providersById[model.providerId] = <String, Object?>{
        'id': model.providerId,
        'discovered': true,
      };
    }

    final browser = runtime.p3BrowserRuntime;
    final owner = runtime.p2OwnerMode;
    final activeProject = _selectedProject;
    final activeModel = _selectedModel;
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

    return ApplicationSnapshot(
      capturedAt: now,
      applicationIdentity: 'kris.ai',
      platform: Platform.operatingSystem,
      build: <String, Object?>{
        'runtime': Platform.version,
      },
      health: <String, Object?>{
        'runtimeOpen': true,
        'browserAvailable': browser.available,
        'ownerAvailable': owner.available,
        'ownerCompletionEligible': owner.completionEligible,
      },
      selectedProject: activeProject == null
          ? null
          : <String, Object?>{
              'id': activeProject.id,
              'name': activeProject.name,
              'rootPath': activeProject.rootPath,
            },
      knownProjects: boundedProjects,
      selectedModel: activeModel == null
          ? null
          : <String, Object?>{
              'providerId': activeModel.providerId,
              'name': activeModel.name,
              'digest': activeModel.digest,
              'exactId': activeModel.exactId,
            },
      availableModels: boundedModels
          .map((model) => <String, Object?>{
                'providerId': model.providerId,
                'name': model.name,
                'digest': model.digest,
                'exactId': model.exactId,
                'selected': model.exactId == activeModel?.exactId,
              })
          .toList(growable: false),
      providers: providersById.values.toList(growable: false),
      runState: runState,
      authority: <String, Object?>{
        'ownerCompletionEligible': owner.completionEligible,
        'ownerSecureIsolationActive': owner.secureIsolationActive,
        // Deliberately not a claim that Owner authority is granted to a run.
        // Per-operation grants remain an execution-time authority decision.
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
          source: 'ProductRuntime.discoverModels',
          confidence: ObservationConfidence.high,
          observedAt: now,
          expiresAt: now.add(const Duration(seconds: 20)),
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
          detail: 'No per-operation Owner grant is inferred from runtime availability.',
        ),
      },
    );
  }
}

List<CapabilitySatisfactionStep> _projectSatisfactionPath() =>
    const <CapabilitySatisfactionStep>[
      CapabilitySatisfactionStep(
        id: 'select_project',
        description: 'Select or create the project that the capability will target.',
        condition: 'A current project is selected and present in the project repository.',
      ),
    ];

List<CapabilitySatisfactionStep> _modelSatisfactionPath() =>
    const <CapabilitySatisfactionStep>[
      CapabilitySatisfactionStep(
        id: 'select_live_model',
        description: 'Select a model discovered from a currently reachable provider.',
        condition: 'The selected model appears in a fresh provider discovery observation.',
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
      if (descriptor.projectRequired && snapshot.selectedProject == null) {
        return CapabilityAvailability(
          capabilityId: descriptor.id,
          state: CapabilityAvailabilityState.projectRequired,
          reasons: const <String>['No project is selected for this session.'],
          missingPrerequisites: const <String>{'selectedProject'},
          observedAt: snapshot.capturedAt,
          evidence: evidence,
          satisfactionPath: _projectSatisfactionPath(),
        );
      }
      if (descriptor.modelProviderRequired && snapshot.selectedModel == null) {
        return CapabilityAvailability(
          capabilityId: descriptor.id,
          state: CapabilityAvailabilityState.modelProviderMissing,
          reasons: const <String>[
            'No live model/provider is selected for substantial planning.',
          ],
          missingPrerequisites: const <String>{'selectedModel'},
          observedAt: snapshot.capturedAt,
          evidence: evidence,
          satisfactionPath: _modelSatisfactionPath(),
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
              'Owner Mode exists, but Owner authority is not automatically granted to this operation.',
          ],
          requiredAuthority: const <String>{'owner'},
          currentAuthority: const <String>{},
          observedAt: snapshot.capturedAt,
          evidence: evidence,
          satisfactionPath: const <CapabilitySatisfactionStep>[
            CapabilitySatisfactionStep(
              id: 'verify_owner_runtime',
              description: 'Verify that the isolated Owner runtime is available and completion-eligible.',
              condition: 'Owner runtime health observation is healthy.',
            ),
            CapabilitySatisfactionStep(
              id: 'obtain_owner_grant',
              description: 'Obtain explicit Owner authority for the specific operation.',
              condition: 'The authority service returns a valid per-operation grant.',
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
            'Open and inspect a public web page using the provisioned application-owned Browser runtime.',
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
                  description: 'Provision or refresh the application-owned Browser runtime.',
                  condition: 'Browser runtime handle reports available.',
                ),
                CapabilitySatisfactionStep(
                  id: 'probe_browser_runtime',
                  description: 'Run a lightweight Browser startup/shutdown probe.',
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
            ? CapabilityHealthState.healthy
            : CapabilityHealthState.failing,
        reasons: <String>[
          available
              ? 'Browser handle is provisioned; a periodic consistency probe provides stronger verification.'
              : 'Browser handle is not available: ${snapshot.browser['statusCode']}.',
        ],
        observedAt: snapshot.capturedAt,
        evidence: <KnowledgeEvidence>[
          KnowledgeEvidence(
            kind: KnowledgeEvidenceKind.observed,
            source: 'ProductRuntime.p3BrowserRuntime.handle',
            confidence: ObservationConfidence.high,
            observedAt: snapshot.capturedAt,
            expiresAt: snapshot.capturedAt.add(descriptor.freshnessBudget),
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
            'Owner recovery exists but requires an explicit per-operation authority grant.',
        ],
        requiredAuthority: const <String>{'owner'},
        currentAuthority: const <String>{},
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
            description: 'Obtain explicit authority for the concrete recovery operation.',
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
      return CapabilityHealth(
        capabilityId: descriptor.id,
        state: !available
            ? CapabilityHealthState.failing
            : eligible
                ? CapabilityHealthState.healthy
                : CapabilityHealthState.degraded,
        reasons: <String>[
          if (!available)
            'Owner runtime is unavailable.'
          else if (!eligible)
            'Owner runtime exists but is not completion-eligible.'
          else
            'Owner runtime is available and completion-eligible; operation authority is still separate.',
        ],
        observedAt: snapshot.capturedAt,
        lastVerifiedAt: snapshot.capturedAt,
        evidence: <KnowledgeEvidence>[
          KnowledgeEvidence(
            kind: KnowledgeEvidenceKind.observed,
            source: 'ProductRuntime.p2OwnerMode.health',
            confidence: ObservationConfidence.high,
            observedAt: snapshot.capturedAt,
            expiresAt: snapshot.capturedAt,
          ),
        ],
      );
    },
  ));
  return registry;
}

/// Shared live self-awareness runtime for one ProductRuntime instance.
///
/// It listens to the durable runtime event stream, debounces refreshes, runs
/// due read-only consistency probes, records causal observations, and updates
/// the bounded self-model. It never exposes an execution or authority grant
/// primitive.
final class ProductSelfAwarenessRuntime {
  factory ProductSelfAwarenessRuntime.shared(ProductRuntime runtime) {
    final existing = _shared[runtime];
    if (existing != null) return existing;
    final created = ProductSelfAwarenessRuntime._(runtime);
    _shared[runtime] = created;
    return created;
  }

  ProductSelfAwarenessRuntime._(this.runtime) {
    snapshotProvider = ProductRuntimeSnapshotProvider(
      runtime: runtime,
      selectedProjectProvider: () => _selectedProject,
      selectedModelProvider: () => _selectedModel,
    );
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
    );
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
  ProjectRecord? _selectedProject;
  ModelIdentity? _selectedModel;
  List<SelfInvariantViolation> _lastIntegrityViolations =
      const <SelfInvariantViolation>[];

  Stream<SelfModelChange> get changes => selfModel.changes;
  List<SelfInvariantViolation> get lastIntegrityViolations =>
      List<SelfInvariantViolation>.unmodifiable(_lastIntegrityViolations);

  void setSelection({ProjectRecord? project, ModelIdentity? model}) {
    _selectedProject = project;
    _selectedModel = model;
  }

  Future<KristinSelfSnapshot> snapshot({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    bool forceRefresh = false,
  }) async {
    setSelection(project: selectedProject, model: selectedModel);
    await consistency.runDue();
    final snapshot = await selfModel.snapshot(
      forceRefresh: forceRefresh,
      source: 'product_runtime.self_awareness',
      reason: forceRefresh ? 'forced_snapshot' : 'snapshot',
    );
    _lastIntegrityViolations = integrity.checkSnapshot(snapshot);
    return snapshot;
  }

  Future<SelfModelPlanningContext> planningContext({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    Set<String> relevantCapabilityIds = const <String>{},
  }) async {
    setSelection(project: selectedProject, model: selectedModel);
    await consistency.runDue();
    return selfModel.planningContext(
      relevantCapabilityIds: relevantCapabilityIds,
    );
  }

  Future<CapabilityRequirementReport> requirementsFor(
    String capabilityId, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) async {
    setSelection(project: selectedProject, model: selectedModel);
    return queries.requirementsFor(capabilityId);
  }

  Future<List<KnownCapability>> capabilitiesFor(
    String objective, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) async {
    setSelection(project: selectedProject, model: selectedModel);
    return queries.capabilitiesFor(objective);
  }

  List<SelfModelChange> changesSince(DateTime since) =>
      queries.whatChangedSince(since);

  Future<List<SelfInvariantViolation>> integrityReport({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) async {
    final snapshot = await this.snapshot(
      selectedProject: selectedProject,
      selectedModel: selectedModel,
      forceRefresh: true,
    );
    _lastIntegrityViolations = integrity.checkSnapshot(snapshot);
    return lastIntegrityViolations;
  }

  Future<List<SelfConsistencyProbeResult>> runProbes({bool force = true}) async {
    final results = await consistency.runDue(force: force);
    if (results.isNotEmpty) {
      await selfModel.notifyStateChanged(
        source: 'self_consistency_monitor',
        reason: 'probe_results_updated',
      );
    }
    return results;
  }

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
          'error': '$error',
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
    await consistency.runDue();
    await selfModel.notifyStateChanged(
      source: 'runtime.event.${event.type}',
      reason: 'durable_runtime_event',
    );
    final latest = await selfModel.snapshot(
      source: 'runtime.event.integrity',
      reason: event.type,
    );
    _lastIntegrityViolations = integrity.checkSnapshot(latest);
  }

  Future<SelfConsistencyProbeResult> _probeBrowser(
    KristinSelfSnapshot snapshot,
  ) async {
    final browser = runtime.p3BrowserRuntime;
    if (!browser.available) {
      return SelfConsistencyProbeResult(
        probeId: 'browser.runtime.startup',
        capabilityId: 'browser.navigate',
        status: ProbeStatus.failing,
        message: 'Browser runtime is unavailable: ${browser.statusCode}.',
      );
    }
    final watch = Stopwatch()..start();
    try {
      await browser.probe(startupTimeout: const Duration(seconds: 10));
      watch.stop();
      return SelfConsistencyProbeResult(
        probeId: 'browser.runtime.startup',
        capabilityId: 'browser.navigate',
        status: ProbeStatus.healthy,
        message: 'Browser startup/shutdown probe completed successfully.',
        latency: watch.elapsed,
      );
    } catch (error) {
      watch.stop();
      return SelfConsistencyProbeResult(
        probeId: 'browser.runtime.startup',
        capabilityId: 'browser.navigate',
        status: ProbeStatus.failing,
        message: 'Browser probe failed: $error',
        latency: watch.elapsed,
      );
    }
  }

  Future<SelfConsistencyProbeResult> _probeOwner(
    KristinSelfSnapshot snapshot,
  ) async {
    final owner = runtime.p2OwnerMode;
    if (!owner.available) {
      return SelfConsistencyProbeResult(
        probeId: 'owner.runtime.readiness',
        capabilityId: 'owner.recovery.actuate',
        status: ProbeStatus.failing,
        message: 'Owner runtime is unavailable: ${owner.diagnosticCode}.',
      );
    }
    if (!owner.completionEligible || !owner.secureIsolationActive) {
      return SelfConsistencyProbeResult(
        probeId: 'owner.runtime.readiness',
        capabilityId: 'owner.recovery.actuate',
        status: ProbeStatus.degraded,
        message:
            'Owner runtime exists but completion eligibility or secure isolation is not active.',
      );
    }
    return SelfConsistencyProbeResult(
      probeId: 'owner.runtime.readiness',
      capabilityId: 'owner.recovery.actuate',
      status: ProbeStatus.healthy,
      message:
          'Owner runtime is isolated and completion-eligible; this observation does not grant operation authority.',
    );
  }

  Future<SelfConsistencyProbeResult> _probeSelectedModel(
    KristinSelfSnapshot snapshot,
  ) async {
    final selected = _selectedModel;
    if (selected == null) {
      return SelfConsistencyProbeResult(
        probeId: 'model.selection.discovery',
        status: ProbeStatus.skipped,
        message: 'No model is selected, so there is no model identity to probe.',
      );
    }
    final watch = Stopwatch()..start();
    try {
      final discovered = await runtime.discoverModels();
      final present = discovered.any((model) => model.exactId == selected.exactId);
      watch.stop();
      return SelfConsistencyProbeResult(
        probeId: 'model.selection.discovery',
        status: present ? ProbeStatus.healthy : ProbeStatus.failing,
        message: present
            ? 'Selected model ${selected.exactId} is present in fresh provider discovery.'
            : 'Selected model ${selected.exactId} is no longer present in provider discovery.',
        latency: watch.elapsed,
        attributes: <String, Object?>{'selectedModel': selected.exactId},
      );
    } catch (error) {
      watch.stop();
      return SelfConsistencyProbeResult(
        probeId: 'model.selection.discovery',
        status: ProbeStatus.failing,
        message: 'Selected model discovery probe failed: $error',
        latency: watch.elapsed,
        attributes: <String, Object?>{'selectedModel': selected.exactId},
      );
    }
  }
}

/// Product composition entry point for one-shot consumers. Stateful Chat
/// consumers should use [ProductSelfAwarenessRuntime.shared] so changes,
/// causal history and probe evidence survive across turns.
KristinSelfModelService buildProductSelfModel(
  ProductRuntime runtime, {
  ProjectRecord? selectedProject,
  ModelIdentity? selectedModel,
}) =>
    KristinSelfModelService(
      registry: buildProductCapabilityRegistry(runtime),
      application: ProductRuntimeSnapshotProvider(
        runtime: runtime,
        selectedProject: selectedProject,
        selectedModel: selectedModel,
      ),
    );
