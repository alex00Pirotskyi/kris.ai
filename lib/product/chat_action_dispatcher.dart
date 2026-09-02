// Business execution lives outside Flutter UI. This dispatcher remains a thin
// wrapper over canonical ProductRuntime services; self-awareness is read-only
// knowledge and does not create a second execution engine.
import 'capability_doctor.dart';
import 'capability_invocation.dart';
import 'domain.dart';
import 'product_runtime.dart';
import 'product_runtime_self_awareness.dart';
import 'self_awareness/capability_self_model.dart';

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
/// implement it; production does. No method on this interface performs effects.
abstract interface class ChatSelfAwarenessGateway {
  Future<KristinSelfSnapshot> selfSnapshot({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
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
  }) {
    final gateway = runtime;
    if (gateway is! ChatSelfAwarenessGateway) {
      throw StateError('chat_self_awareness_gateway_unavailable');
    }
    return gateway.selfSnapshot(
      selectedProject: selectedProject,
      selectedModel: selectedModel,
    );
  }

  Future<String> explainCapabilityAvailability(
    String capabilityId, {
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) async {
    final self = await selfAwareness(
      selectedProject: selectedProject,
      selectedModel: selectedModel,
    );
    final item = self.capability(capabilityId);
    if (item == null) {
      return 'Kristin does not currently know a capability named $capabilityId.';
    }
    final reasons = item.availability.reasons.isEmpty
        ? 'No additional reason was reported.'
        : item.availability.reasons.join(' ');
    return '$capabilityId is ${item.availability.state.name}. $reasons';
  }

  Future<ProjectDiagnosticReport> inspect(
    String projectId, {
    String capabilityId = 'project.analyze',
  }) {
    authorize(capabilityId: capabilityId, targetIds: <String>{projectId}, reason: 'chat_direct');
    return runtime.analyzeProject(projectId);
  }

  Future<ProjectDiagnosticReport> test(String projectId) {
    authorize(capabilityId: 'project.test', targetIds: <String>{projectId}, reason: 'chat_direct');
    return runtime.testProject(projectId);
  }

  Future<ProjectDiagnosticReport> build(String projectId) {
    authorize(capabilityId: 'project.build', targetIds: <String>{projectId}, reason: 'chat_direct');
    return runtime.buildProject(projectId);
  }

  Future<ProjectProcessStatus> run(String projectId) {
    authorize(capabilityId: 'project.run', targetIds: <String>{projectId}, reason: 'chat_direct');
    return runtime.startProject(projectId);
  }

  Future<ProjectProcessStatus?> stop(String projectId) {
    authorize(capabilityId: 'project.stop', targetIds: <String>{projectId}, reason: 'chat_direct');
    return runtime.stopProject(projectId);
  }

  Future<ProjectProcessStatus> restart(String projectId) async {
    authorize(capabilityId: 'project.restart', targetIds: <String>{projectId}, reason: 'chat_direct');
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

  @override
  Future<KristinSelfSnapshot> selfSnapshot({
    ProjectRecord? selectedProject,
    ModelIdentity? selectedModel,
  }) =>
      buildProductSelfModel(
        runtime,
        selectedProject: selectedProject,
        selectedModel: selectedModel,
      ).snapshot();

  @override
  Future<List<Map<String, String>>> searchWeb({
    required String query,
    int count = 10,
  }) =>
      runtime.searchWeb(query: query, count: count);

  @override
  Future<void> archiveResearchIfProject({
    required String? projectId,
    required String query,
    required List<Map<String, String>> results,
  }) async {
    if (projectId == null) return;
    await runtime.knowledge.addResearchSearch(
      projectId: projectId,
      query: query,
      results: results,
      provider: 'duckduckgo',
    );
  }

  @override
  Future<ProjectDiagnosticReport> analyzeProject(String projectId) =>
      runtime.analyzeProject(projectId);

  @override
  Future<ProjectDiagnosticReport> testProject(String projectId) =>
      runtime.testProject(projectId);

  @override
  Future<ProjectDiagnosticReport> buildProject(String projectId) =>
      runtime.buildProject(projectId);

  @override
  Future<ProjectProcessStatus> startProject(String projectId) =>
      runtime.startProject(projectId);

  @override
  Future<ProjectProcessStatus?> stopProject(String projectId) =>
      runtime.stopProject(projectId);

  @override
  Future<ProjectRecord> provisionProjectForRequest({
    required String request,
    String? suggestedName,
  }) =>
      runtime.provisionProjectForRequest(
        request: request,
        suggestedName: suggestedName,
      );

  @override
  Future<PreparedCommand> prepare({
    required String projectId,
    required CommandMode mode,
    required String request,
    required ModelIdentity model,
  }) =>
      runtime.prepare(
        projectId: projectId,
        mode: mode,
        request: request,
        model: model,
      );

  @override
  Future<CapabilityDoctorReport> inspectCapabilities({
    String? projectId,
    List<ModelIdentity>? discoveredModels,
    CapabilityDoctorDepth depth = CapabilityDoctorDepth.quick,
  }) =>
      runtime.inspectCapabilities(
        projectId: projectId,
        discoveredModels: discoveredModels,
        depth: depth,
      );
}
