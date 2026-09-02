// Business execution lives outside Flutter UI. This dispatcher remains a thin
// wrapper over canonical ProductRuntime services; self-awareness is read-only
// knowledge and does not create a second execution engine.
import 'capability_doctor.dart';
import 'capability_invocation.dart';
import 'domain.dart';
import 'product_runtime.dart';
import 'product_runtime_self_awareness.dart';
import 'self_awareness/capability_self_model.dart';
import 'self_awareness/operational_self_awareness.dart';

abstract class ChatRuntimeGateway {
  Future<List<Map<String, String>>> searchWeb({required String query, int count});
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
    CapabilityDoctorDepth depth,
  });
}

/// Optional read-only surface. Existing ChatRuntimeGateway fakes do not need to
/// implement it; production does. None of these methods performs an effect or
/// converts capability knowledge into authority.
abstract interface class ChatSelfAwarenessGateway {
  Future<KristinSelfSnapshot> selfSnapshot({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    bool forceRefresh,
  });

  Future<SelfModelPlanningContext> selfPlanningContext({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    Set<String> relevantCapabilityIds,
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

  Future<List<SelfModelChange>> selfChangesSince(DateTime since);

  Future<List<SelfInvariantViolation>> selfIntegrity({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  });

  Future<List<SelfConsistencyProbeResult>> runSelfConsistencyProbes();
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
  }) =>
      authorityResolver.resolve(
        CapabilityInvocation(
          capabilityId: capabilityId,
          targetIds: targetIds,
          requestedScopes: requestedScopes,
          modelProposed: modelProposed,
          reason: reason,
        ),
      );

  /// Live application self-description for Chat informational turns.
  ///
  /// This deliberately does not call [authorize]: reading the bounded
  /// self-model is knowledge, not an effect. Authority contained in the result
  /// is descriptive only and never converted into a permission grant.
  Future<KristinSelfSnapshot> selfAwareness({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    bool forceRefresh = false,
  }) =>
      _selfGateway.selfSnapshot(
        selectedProject: selectedProject,
        selectedModel: selectedModel,
        forceRefresh: forceRefresh,
      );

  Future<SelfModelPlanningContext> selfPlanningContext({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    Set<String> relevantCapabilityIds = const <String>{},
  }) =>
      _selfGateway.selfPlanningContext(
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
  }) =>
      _selfGateway.capabilityRequirements(
        capabilityId,
        selectedProject: selectedProject,
        selectedModel: selectedModel,
      );

  Future<List<KnownCapability>> capabilitiesForObjective(
    String objective, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) =>
      _selfGateway.capabilitiesForObjective(
        objective,
        selectedProject: selectedProject,
        selectedModel: selectedModel,
      );

  Future<List<SelfModelChange>> selfChangesSince(DateTime since) =>
      _selfGateway.selfChangesSince(since);

  Future<List<SelfInvariantViolation>> selfIntegrity({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) =>
      _selfGateway.selfIntegrity(
        selectedProject: selectedProject,
        selectedModel: selectedModel,
      );

  Future<List<SelfConsistencyProbeResult>> runSelfConsistencyProbes() =>
      _selfGateway.runSelfConsistencyProbes();

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

/// Production gateway. It is the composition point that makes the runtime
/// self-model available to Chat without teaching the UI about ProductRuntime.
class ProductRuntimeChatGateway
    implements ChatRuntimeGateway, ChatSelfAwarenessGateway {
  const ProductRuntimeChatGateway(this.runtime);
  final ProductRuntime runtime;

  ProductSelfAwarenessRuntime get awareness {
    final shared = ProductSelfAwarenessRuntime.shared(runtime);
    // One idempotent monitor per ProductRuntime. It begins when Chat first
    // touches the self-aware gateway and stops when the runtime event stream
    // closes. Probes remain observation-only.
    shared.consistency.start(tick: const Duration(seconds: 5));
    return shared;
  }

  @override
  Future<KristinSelfSnapshot> selfSnapshot({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    bool forceRefresh = false,
  }) =>
      awareness.snapshot(
        selectedProject: selectedProject,
        selectedModel: selectedModel,
        forceRefresh: forceRefresh,
      );

  @override
  Future<SelfModelPlanningContext> selfPlanningContext({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
    Set<String> relevantCapabilityIds = const <String>{},
  }) =>
      awareness.planningContext(
        selectedProject: selectedProject,
        selectedModel: selectedModel,
        relevantCapabilityIds: relevantCapabilityIds,
      );

  @override
  Future<CapabilityRequirementReport> capabilityRequirements(
    String capabilityId, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) =>
      awareness.requirementsFor(
        capabilityId,
        selectedProject: selectedProject,
        selectedModel: selectedModel,
      );

  @override
  Future<List<KnownCapability>> capabilitiesForObjective(
    String objective, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) =>
      awareness.capabilitiesFor(
        objective,
        selectedProject: selectedProject,
        selectedModel: selectedModel,
      );

  @override
  Future<List<SelfModelChange>> selfChangesSince(DateTime since) async =>
      awareness.changesSince(since);

  @override
  Future<List<SelfInvariantViolation>> selfIntegrity({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) =>
      awareness.integrityReport(
        selectedProject: selectedProject,
        selectedModel: selectedModel,
      );

  @override
  Future<List<SelfConsistencyProbeResult>> runSelfConsistencyProbes() =>
      awareness.runProbes(force: true);

  @override
  Future<List<Map<String, String>>> searchWeb({
    required String query,
    int count = 10,
  }) =>
      awareness.observeOperation(
        'research.search',
        <String, Object?>{'query': query, 'count': count},
        () => runtime.searchWeb(query: query, count: count),
        stateChanging: false,
      );

  @override
  Future<void> archiveResearchIfProject({
    required String? projectId,
    required String query,
    required List<Map<String, String>> results,
  }) async {
    if (projectId == null) return;
    await awareness.observeOperation<void>(
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
    );
  }

  @override
  Future<ProjectDiagnosticReport> analyzeProject(String projectId) =>
      awareness.observeOperation(
        'project.analyze',
        <String, Object?>{'projectId': projectId},
        () => runtime.analyzeProject(projectId),
        stateChanging: false,
      );

  @override
  Future<ProjectDiagnosticReport> testProject(String projectId) =>
      awareness.observeOperation(
        'project.test',
        <String, Object?>{'projectId': projectId},
        () => runtime.testProject(projectId),
        stateChanging: false,
      );

  @override
  Future<ProjectDiagnosticReport> buildProject(String projectId) =>
      awareness.observeOperation(
        'project.build',
        <String, Object?>{'projectId': projectId},
        () => runtime.buildProject(projectId),
      );

  @override
  Future<ProjectProcessStatus> startProject(String projectId) =>
      awareness.observeOperation(
        'project.start',
        <String, Object?>{'projectId': projectId},
        () => runtime.startProject(projectId),
      );

  @override
  Future<ProjectProcessStatus?> stopProject(String projectId) =>
      awareness.observeOperation(
        'project.stop',
        <String, Object?>{'projectId': projectId},
        () => runtime.stopProject(projectId),
      );

  @override
  Future<ProjectRecord> provisionProjectForRequest({
    required String request,
    String? suggestedName,
  }) =>
      awareness.observeOperation(
        'project.provision',
        <String, Object?>{
          'request': request,
          if (suggestedName != null) 'suggestedName': suggestedName,
        },
        () => runtime.provisionProjectForRequest(
          request: request,
          suggestedName: suggestedName,
        ),
      );

  @override
  Future<PreparedCommand> prepare({
    required String projectId,
    required CommandMode mode,
    required String request,
    required ModelIdentity model,
  }) =>
      awareness.observeOperation(
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
      );

  @override
  Future<CapabilityDoctorReport> inspectCapabilities({
    String? projectId,
    List<ModelIdentity>? discoveredModels,
    CapabilityDoctorDepth depth = CapabilityDoctorDepth.quick,
  }) =>
      awareness.observeOperation(
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
      );
}
