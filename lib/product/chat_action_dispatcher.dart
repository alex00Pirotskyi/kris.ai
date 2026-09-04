import 'dart:async';

import 'capability_doctor.dart';
import 'capability_invocation.dart';
import 'chat_control_plane.dart';
import 'crypto_utils.dart';
import 'domain.dart';
import 'product_runtime.dart';
import 'product_runtime_self_awareness.dart';
import 'recovery/product_runtime_recovery.dart';
import 'self_awareness/capability_self_model.dart';
import 'self_awareness/operational_self_awareness.dart';
import 'task_kernel/complexity_router.dart';
import 'task_kernel/task_families.dart';
import 'task_kernel/task_kernel.dart';
import 'task_kernel/task_specification.dart';

/// Minimal business gateway for direct Chat actions. UI code talks to this
/// surface instead of acquiring ProductRuntime internals itself.
abstract class ChatRuntimeGateway {
  Future<List<Map<String, String>>> searchWeb({
    required String query,
    int count = 10,
  });
  Future<void> archiveResearchIfProject({
    required String? projectId,
    required String query,
    required List<Map<String, String>> results,
  });
  Future<ProjectDiagnosticReport> analyzeProject(String projectId);
  Future<ProjectDiagnosticReport> testProject(String projectId);
  Future<ProjectDiagnosticReport> buildProject(String projectId);
  Future<ProjectProcessStatus> startProject(String projectId);
  Future<ProjectProcessStatus?> stopProject(String projectId);
  Future<ProjectRecord> provisionProjectForRequest({
    required String request,
    String? suggestedName,
  });
  Future<PreparedCommand> prepare({
    required String projectId,
    required CommandMode mode,
    required String request,
    required ModelIdentity model,
  });
  Future<CapabilityDoctorReport> inspectCapabilities({
    String? projectId,
    List<ModelIdentity>? discoveredModels,
    CapabilityDoctorDepth depth = CapabilityDoctorDepth.quick,
  });
}

/// Optional read-only self-awareness surface. It never executes an effect and
/// never converts descriptive authority state into a permission grant.
abstract interface class ChatSelfAwarenessGateway {
  Future<KristinSelfSnapshot> selfSnapshot({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    bool forceRefresh = false,
  });

  Future<SelfModelPlanningContext> selfPlanningContext({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    Set<String> relevantCapabilityIds = const <String>{},
  });

  Future<CapabilityRequirementReport> capabilityRequirements(
    String capabilityId, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  });

  Future<List<KnownCapability>> capabilitiesForObjective(
    String objective, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  });

  Future<List<SelfModelChange>> selfChangesSince(
    DateTime since, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  });

  Future<List<SelfInvariantViolation>> selfIntegrity({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  });

  Future<List<SelfConsistencyProbeResult>> runSelfConsistencyProbes({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  });
}

/// Optional production planning surface. It is deliberately separate from
/// ChatRuntimeGateway so existing small fakes remain source-compatible. The
/// production implementation supplies the live self-model to the real kernel.
abstract interface class ChatSelfAwarePlanningGateway {
  Future<KernelPreparedPlan> prepareThroughKernel({
    required TaskSpecification specification,
    required RoutingDecision routing,
    required ProjectRecord project,
    required CommandMode mode,
    ModelIdentity? model,
    Set<String> consumedCoordinatorCapabilities = const <String>{},
  });
}

class ChatResearchResult {
  const ChatResearchResult({required this.query, required this.results});
  final String query;
  final List<Map<String, String>> results;
}

class ChatActionDispatcher {
  const ChatActionDispatcher(
    this.runtime, {
    this.authorityResolver = const CapabilityAuthorityResolver(),
  });

  final ChatRuntimeGateway runtime;
  final CapabilityAuthorityResolver authorityResolver;

  ChatSelfAwarenessGateway get _selfGateway {
    final gateway = runtime;
    if (gateway is! ChatSelfAwarenessGateway) {
      throw StateError('chat_self_awareness_gateway_unavailable');
    }
    return gateway;
  }

  CapabilityAuthorityDecision authorize({
    required String capabilityId,
    Set<String> targetIds = const <String>{},
    Set<PermissionScope> requestedScopes = const <PermissionScope>{},
    bool modelProposed = false,
    String reason = '',
  }) => authorityResolver.resolve(
    CapabilityInvocation(
      capabilityId: capabilityId,
      targetIds: targetIds,
      requestedScopes: requestedScopes,
      modelProposed: modelProposed,
      reason: reason,
    ),
  );

  Future<KristinSelfSnapshot> selfAwareness({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    bool forceRefresh = false,
  }) => _selfGateway.selfSnapshot(
    selectedProject: selectedProject,
    selectedModel: selectedModel,
    forceRefresh: forceRefresh,
  );

  Future<SelfModelPlanningContext> selfPlanningContext({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    Set<String> relevantCapabilityIds = const <String>{},
  }) => _selfGateway.selfPlanningContext(
    selectedProject: selectedProject,
    selectedModel: selectedModel,
    relevantCapabilityIds: relevantCapabilityIds,
  );

  Future<String> explainCapabilityAvailability(
    String capabilityId, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) async {
    final report = await capabilityRequirements(
      capabilityId,
      selectedProject: selectedProject,
      selectedModel: selectedModel,
    );
    return report.explanation;
  }

  Future<CapabilityRequirementReport> capabilityRequirements(
    String capabilityId, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) => _selfGateway.capabilityRequirements(
    capabilityId,
    selectedProject: selectedProject,
    selectedModel: selectedModel,
  );

  Future<List<KnownCapability>> capabilitiesForObjective(
    String objective, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) => _selfGateway.capabilitiesForObjective(
    objective,
    selectedProject: selectedProject,
    selectedModel: selectedModel,
  );

  Future<List<SelfModelChange>> selfChangesSince(
    DateTime since, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) => _selfGateway.selfChangesSince(
    since,
    selectedProject: selectedProject,
    selectedModel: selectedModel,
  );

  Future<List<SelfInvariantViolation>> selfIntegrity({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) => _selfGateway.selfIntegrity(
    selectedProject: selectedProject,
    selectedModel: selectedModel,
  );

  Future<List<SelfConsistencyProbeResult>> runSelfConsistencyProbes({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) => _selfGateway.runSelfConsistencyProbes(
    selectedProject: selectedProject,
    selectedModel: selectedModel,
  );

  Future<KernelPreparedPlan> prepareThroughKernel({
    required TaskSpecification specification,
    required RoutingDecision routing,
    required ProjectRecord project,
    required CommandMode mode,
    ModelIdentity? model,
    Set<String> consumedCoordinatorCapabilities = const <String>{},
  }) {
    final gateway = runtime;
    if (gateway is! ChatSelfAwarePlanningGateway) {
      throw StateError('chat_self_aware_planning_gateway_unavailable');
    }
    return gateway.prepareThroughKernel(
      specification: specification,
      routing: routing,
      project: project,
      mode: mode,
      model: model,
      consumedCoordinatorCapabilities: consumedCoordinatorCapabilities,
    );
  }

  Future<ProjectDiagnosticReport> inspect(
    String projectId, {
    String capabilityId = 'project.analyze',
  }) {
    authorize(
      capabilityId: capabilityId,
      targetIds: <String>{projectId},
      reason: 'chat_direct',
    );
    return runtime.analyzeProject(projectId);
  }

  Future<ProjectDiagnosticReport> test(String projectId) {
    authorize(
      capabilityId: 'project.test',
      targetIds: <String>{projectId},
      reason: 'chat_direct',
    );
    return runtime.testProject(projectId);
  }

  Future<ProjectDiagnosticReport> build(String projectId) {
    authorize(
      capabilityId: 'project.build',
      targetIds: <String>{projectId},
      reason: 'chat_direct',
    );
    return runtime.buildProject(projectId);
  }

  Future<ProjectProcessStatus> run(String projectId) {
    authorize(
      capabilityId: 'project.run',
      targetIds: <String>{projectId},
      reason: 'chat_direct',
    );
    return runtime.startProject(projectId);
  }

  Future<ProjectProcessStatus?> stop(String projectId) {
    authorize(
      capabilityId: 'project.stop',
      targetIds: <String>{projectId},
      reason: 'chat_direct',
    );
    return runtime.stopProject(projectId);
  }

  Future<ProjectProcessStatus> restart(String projectId) async {
    authorize(
      capabilityId: 'project.restart',
      targetIds: <String>{projectId},
      reason: 'chat_direct',
    );
    await runtime.stopProject(projectId);
    return runtime.startProject(projectId);
  }

  Future<ChatResearchResult> search({
    required String query,
    String? projectId,
    int count = 10,
  }) async {
    authorize(
      capabilityId: 'research.search',
      targetIds: projectId == null ? const <String>{} : <String>{projectId},
      reason: 'chat_direct',
    );
    final results = await runtime.searchWeb(query: query, count: count);
    await runtime.archiveResearchIfProject(
      projectId: projectId,
      query: query,
      results: results,
    );
    return ChatResearchResult(query: query, results: results);
  }

  Future<CapabilityDoctorReport> diagnose({
    String? projectId,
    required List<ModelIdentity> discoveredModels,
  }) {
    authorize(
      capabilityId: 'system.diagnose',
      targetIds: projectId == null ? const <String>{} : <String>{projectId},
      reason: 'chat_direct',
    );
    return runtime.inspectCapabilities(
      projectId: projectId,
      discoveredModels: discoveredModels,
      depth: CapabilityDoctorDepth.full,
    );
  }

  Future<ProjectRecord?> resolveAgentProject({
    required String capabilityId,
    required ProjectRecord? selectedProject,
    required String originalRequest,
  }) async {
    authorize(
      capabilityId: capabilityId,
      targetIds: selectedProject == null
          ? const <String>{}
          : <String>{selectedProject.id},
      reason: 'chat_coordinator',
    );
    if (capabilityId == 'agent.create_project') {
      return runtime.provisionProjectForRequest(request: originalRequest);
    }
    return selectedProject;
  }

  Future<PreparedCommand> prepare({
    String capabilityId = 'agent.modify_project',
    required String projectId,
    required CommandMode mode,
    required String request,
    required ModelIdentity model,
  }) {
    authorize(
      capabilityId: capabilityId,
      targetIds: <String>{projectId},
      reason: 'chat_governed_prepare',
    );
    return runtime.prepare(
      projectId: projectId,
      mode: mode,
      request: request,
      model: model,
    );
  }
}

/// Production gateway and composition point for self-awareness plus autonomic
/// recovery. It remains a wrapper around canonical ProductRuntime behavior;
/// no second execution engine is introduced here.
class ProductRuntimeChatGateway
    implements
        ChatRuntimeGateway,
        ChatSelfAwarenessGateway,
        ChatSelfAwarePlanningGateway {
  ProductRuntimeChatGateway(this.runtime) {
    final live = ProductSelfAwarenessRuntime.shared(runtime);
    // Every kernel plan/understanding path now receives the same live
    // self-model intersection, including paths that still construct a plain
    // PlanningContext for compatibility. Exact Runner tools remain supplied
    // independently by those callers.
    KernelSelfModelRegistry.register(
      runtime.taskKernel,
      ({
        required ProjectRecord? project,
        required ModelIdentity? model,
        required Set<String> relevantCapabilityIds,
      }) => live.planningContext(
        selectedProject: project,
        selectedModel: model,
        sessionKey:
            'kernel:${project?.id ?? 'none'}:${model?.exactId ?? 'none'}',
        relevantCapabilityIds: relevantCapabilityIds,
      ),
    );
    ProductRuntimeAutonomicRecovery.shared(runtime);
  }

  final ProductRuntime runtime;

  ProductSelfAwarenessRuntime get awareness =>
      ProductSelfAwarenessRuntime.shared(runtime);
  ProductRuntimeAutonomicRecovery get autonomic =>
      ProductRuntimeAutonomicRecovery.shared(runtime);

  @override
  Future<KristinSelfSnapshot> selfSnapshot({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    bool forceRefresh = false,
  }) => awareness.snapshot(
    selectedProject: selectedProject,
    selectedModel: selectedModel,
    forceRefresh: forceRefresh,
  );

  @override
  Future<SelfModelPlanningContext> selfPlanningContext({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    Set<String> relevantCapabilityIds = const <String>{},
  }) => awareness.planningContext(
    selectedProject: selectedProject,
    selectedModel: selectedModel,
    relevantCapabilityIds: relevantCapabilityIds,
  );

  @override
  Future<CapabilityRequirementReport> capabilityRequirements(
    String capabilityId, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) => awareness.requirementsFor(
    capabilityId,
    selectedProject: selectedProject,
    selectedModel: selectedModel,
  );

  @override
  Future<List<KnownCapability>> capabilitiesForObjective(
    String objective, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) => awareness.capabilitiesFor(
    objective,
    selectedProject: selectedProject,
    selectedModel: selectedModel,
  );

  @override
  Future<List<SelfModelChange>> selfChangesSince(
    DateTime since, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) async => awareness.changesSince(
    since,
    selectedProject: selectedProject,
    selectedModel: selectedModel,
  );

  @override
  Future<List<SelfInvariantViolation>> selfIntegrity({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) => awareness.integrityReport(
    selectedProject: selectedProject,
    selectedModel: selectedModel,
  );

  @override
  Future<List<SelfConsistencyProbeResult>> runSelfConsistencyProbes({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) => awareness.runProbes(
    selectedProject: selectedProject,
    selectedModel: selectedModel,
    force: true,
  );

  @override
  Future<KernelPreparedPlan> prepareThroughKernel({
    required TaskSpecification specification,
    required RoutingDecision routing,
    required ProjectRecord project,
    required CommandMode mode,
    ModelIdentity? model,
    Set<String> consumedCoordinatorCapabilities = const <String>{},
  }) async {
    final consumed = <String>{
      ...consumedCoordinatorCapabilities,
      ...specification.capabilityHints.where(
        kCoordinatorCapabilityIds.contains,
      ),
    };
    final selfContext = await awareness.planningContext(
      selectedProject: project,
      selectedModel: model,
      relevantCapabilityIds: specification.capabilityHints.toSet(),
    );
    final result = await runtime.taskKernel.plan(
      specification: specification,
      routing: routing,
      context: PlanningContext(
        project: project,
        model: model,
        availableCapabilityIds: selfContext.availableCapabilityIds,
        availableToolNames: runtime.tools.names,
        consumedCoordinatorCapabilities: consumed,
        localOnly: runtime.settings.localOnly,
      ),
    );
    final compiled = runtime.taskKernel.compile(
      plan: result.plan,
      project: project,
      mode: mode,
      consumedCoordinatorCapabilities: consumed,
    );
    final prepared = PreparedCommand(
      id: newId('command'),
      requestKey: Sha256.text(
        canonicalJson(<String, dynamic>{
          'projectId': project.id,
          'specification': specification.contentKey,
          'planHash': result.plan.contentHash,
          'selectedTaskIds': compiled.selectedTaskIds.toList()..sort(),
          'mode': mode.name,
          'model': model?.toJson(),
          'selfAvailableCapabilities':
              selfContext.availableCapabilityIds.toList()..sort(),
        }),
      ),
      contract: compiled.contract,
      plan: compiled.plan,
      model:
          model ??
          ModelIdentity(
            providerId: 'none',
            name: 'unselected',
            digest: '',
            discoveredAt: DateTime.now().toUtc(),
          ),
      createdAt: DateTime.now().toUtc(),
    );
    final existing = (await runtime.repositories.commands.all())
        .where((item) => item.requestKey == prepared.requestKey)
        .firstOrNull;
    final command = existing ?? prepared;
    if (existing == null) {
      await runtime.repositories.commands.put(prepared);
      await runtime.audit
          .append('task_kernel.compiled', prepared.id, <String, dynamic>{
            'commandId': prepared.id,
            'projectId': project.id,
            'family': result.plan.family.name,
            'route': result.plan.route.name,
            'conservative': result.isConservative,
            'coordinatorCapabilitiesConsumed': consumed.toList()..sort(),
            'specificationSource': specification.source.name,
            'workItems': compiled.plan.items.length,
            'planHash': result.plan.contentHash,
            'selfModelFreshnessWarnings': selfContext.freshnessWarnings,
          });
      await runtime.events
          .publish('command.prepared', prepared.id, <String, dynamic>{
            'commandId': prepared.id,
            'projectId': project.id,
            'mode': compiled.contract.mode.name,
            'complexity': compiled.plan.complexity,
            'generatedTaskPlan': !result.isConservative,
            'taskFamily': result.plan.family.name,
            'selfAwarePlanning': true,
          });
    }
    return KernelPreparedPlan(
      command: command,
      canonical: result.plan,
      origin: result.origin,
      routing: routing,
      failure: result.failure,
    );
  }

  Future<T> _observe<T>(
    String operation,
    Map<String, Object?> attributes,
    Future<T> Function() action, {
    bool stateChanging = true,
    String? projectId,
    String? modelExactId,
    String? capabilityId,
  }) async {
    try {
      return await awareness.observeOperation(
        operation,
        attributes,
        action,
        stateChanging: stateChanging,
      );
    } catch (error) {
      // The visible operation still fails immediately. Autonomic recovery runs
      // under its own bounded supervisor against the same durable runtime.
      unawaited(
        autonomic.handleOperationalFailure(
          operation: operation,
          error: error,
          projectId: projectId,
          modelExactId: modelExactId,
          capabilityId: capabilityId,
        ),
      );
      rethrow;
    }
  }

  @override
  Future<List<Map<String, String>>> searchWeb({
    required String query,
    int count = 10,
  }) => _observe(
    'research.search',
    <String, Object?>{'query': query, 'count': count},
    () => runtime.searchWeb(query: query, count: count),
    stateChanging: false,
    capabilityId: 'research.search',
  );

  @override
  Future<void> archiveResearchIfProject({
    required String? projectId,
    required String query,
    required List<Map<String, String>> results,
  }) async {
    if (projectId == null) return;
    await _observe<void>(
      'research.archive',
      <String, Object?>{
        'projectId': projectId,
        'query': query,
        'resultCount': results.length,
      },
      () => runtime.knowledge.addResearchSearch(
        projectId: projectId,
        query: query,
        results: results,
        provider: 'duckduckgo',
      ),
      projectId: projectId,
    );
  }

  @override
  Future<ProjectDiagnosticReport> analyzeProject(String projectId) => _observe(
    'project.analyze',
    <String, Object?>{'projectId': projectId},
    () => runtime.analyzeProject(projectId),
    stateChanging: false,
    projectId: projectId,
    capabilityId: 'project.analyze',
  );

  @override
  Future<ProjectDiagnosticReport> testProject(String projectId) => _observe(
    'project.test',
    <String, Object?>{'projectId': projectId},
    () => runtime.testProject(projectId),
    stateChanging: false,
    projectId: projectId,
    capabilityId: 'project.test',
  );

  @override
  Future<ProjectDiagnosticReport> buildProject(String projectId) => _observe(
    'project.build',
    <String, Object?>{'projectId': projectId},
    () => runtime.buildProject(projectId),
    projectId: projectId,
    capabilityId: 'project.build',
  );

  @override
  Future<ProjectProcessStatus> startProject(String projectId) => _observe(
    'project.start',
    <String, Object?>{'projectId': projectId},
    () => runtime.startProject(projectId),
    projectId: projectId,
    capabilityId: 'project.run',
  );

  @override
  Future<ProjectProcessStatus?> stopProject(String projectId) => _observe(
    'project.stop',
    <String, Object?>{'projectId': projectId},
    () => runtime.stopProject(projectId),
    projectId: projectId,
    capabilityId: 'project.stop',
  );

  @override
  Future<ProjectRecord> provisionProjectForRequest({
    required String request,
    String? suggestedName,
  }) => _observe(
    'project.provision',
    <String, Object?>{
      'request': request,
      if (suggestedName != null) 'suggestedName': suggestedName,
    },
    () => runtime.provisionProjectForRequest(
      request: request,
      suggestedName: suggestedName,
    ),
    capabilityId: 'agent.create_project',
  );

  @override
  Future<PreparedCommand> prepare({
    required String projectId,
    required CommandMode mode,
    required String request,
    required ModelIdentity model,
  }) => _observe(
    'command.prepare',
    <String, Object?>{
      'projectId': projectId,
      'mode': mode.name,
      'model': model.exactId,
    },
    () => runtime.prepare(
      projectId: projectId,
      mode: mode,
      request: request,
      model: model,
    ),
    projectId: projectId,
    modelExactId: model.exactId,
  );

  @override
  Future<CapabilityDoctorReport> inspectCapabilities({
    String? projectId,
    List<ModelIdentity>? discoveredModels,
    CapabilityDoctorDepth depth = CapabilityDoctorDepth.quick,
  }) => _observe(
    'system.capability_doctor',
    <String, Object?>{
      if (projectId != null) 'projectId': projectId,
      'depth': depth.name,
    },
    () => runtime.inspectCapabilities(
      projectId: projectId,
      discoveredModels: discoveredModels,
      depth: depth,
    ),
    stateChanging: false,
    projectId: projectId,
    capabilityId: 'system.diagnose',
  );
}
