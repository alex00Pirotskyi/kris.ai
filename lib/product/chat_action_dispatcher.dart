// Architectural Improvement #7: business execution lives outside the
// Flutter UI. ChatActionDispatcher is a plain Dart, non-widget class --
// it never imports `package:flutter/material.dart`, never touches
// BuildContext/Navigator, and never mutates widget state directly. The
// Flutter UI (chat_control_plane_studio_actions.dart) calls into this
// dispatcher and only handles: collecting text, displaying messages,
// rendering progress, and navigation.
//
// This is deliberately NOT a second execution engine (see the module
// docs on ChatExecutionRoute in chat_control_plane.dart): every method
// here is a thin, directly-testable wrapper around an existing canonical
// ProductRuntime capability. Nothing here re-implements build/test/run,
// invents a parallel permission model, or bypasses
// ProductRuntime.prepare's governed plan/permission/execution pipeline.
import 'capability_doctor.dart';
import 'domain.dart';
import 'product_runtime.dart';

/// The narrow seam ChatActionDispatcher needs from ProductRuntime.
/// Keeping this interface small (rather than depending on the concrete,
/// very large ProductRuntime class) is what makes the dispatcher
/// fakeable in tests without booting real project/process/model
/// infrastructure -- see Architectural Improvement #7's Stage 7
/// ("action dispatcher tests ... use fakes at canonical service
/// boundaries").
abstract class ChatRuntimeGateway {
  /// Architectural Improvement #9: deliberately takes no projectId --
  /// research must not require a project.
  Future<List<Map<String, String>>> searchWeb({
    required String query,
    int count,
  });

  /// Archives a completed search as project knowledge when a project is
  /// in scope. A no-op when [projectId] is null: research is optionally
  /// enriched by a project, never gated by one.
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

/// A completed web search, ready for Chat to present. Carries no
/// project-scoping requirement -- see [ChatRuntimeGateway.searchWeb].
class ChatResearchResult {
  const ChatResearchResult({required this.query, required this.results});

  final String query;
  final List<Map<String, String>> results;
}

class ChatActionDispatcher {
  const ChatActionDispatcher(this.runtime);

  final ChatRuntimeGateway runtime;

  Future<ProjectDiagnosticReport> inspect(String projectId) =>
      runtime.analyzeProject(projectId);

  Future<ProjectDiagnosticReport> test(String projectId) =>
      runtime.testProject(projectId);

  Future<ProjectDiagnosticReport> build(String projectId) =>
      runtime.buildProject(projectId);

  Future<ProjectProcessStatus> run(String projectId) =>
      runtime.startProject(projectId);

  Future<ProjectProcessStatus?> stop(String projectId) =>
      runtime.stopProject(projectId);

  Future<ProjectProcessStatus> restart(String projectId) async {
    await runtime.stopProject(projectId);
    return runtime.startProject(projectId);
  }

  /// research.search: never requires a project (Architectural Improvement
  /// #9). [projectId], when supplied, only enriches the result with
  /// project-scoped knowledge archiving; it is never required to proceed.
  Future<ChatResearchResult> search({
    required String query,
    String? projectId,
    int count = 10,
  }) async {
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
  }) =>
      runtime.inspectCapabilities(
        projectId: projectId,
        discoveredModels: discoveredModels,
        depth: CapabilityDoctorDepth.full,
      );

  /// Resolves the project a substantial agent action (create/modify/fix)
  /// should target. Only `agent.create_project` ever provisions a new
  /// project; every other capability id must already have a resolvable
  /// project (Architectural Improvement #8 -- create and modify/fix are
  /// never the same runtime decision).
  Future<ProjectRecord?> resolveAgentProject({
    required String capabilityId,
    required ProjectRecord? selectedProject,
    required String originalRequest,
  }) async {
    if (capabilityId == 'agent.create_project') {
      return runtime.provisionProjectForRequest(request: originalRequest);
    }
    return selectedProject;
  }

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
}

/// The production [ChatRuntimeGateway], delegating every call to the real
/// canonical [ProductRuntime]. This is the only place chat_control_plane*
/// code should construct a [ChatActionDispatcher] from a live runtime.
class ProductRuntimeChatGateway implements ChatRuntimeGateway {
  const ProductRuntimeChatGateway(this.runtime);

  final ProductRuntime runtime;

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
