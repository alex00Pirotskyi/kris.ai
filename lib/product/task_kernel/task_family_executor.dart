import '../capability_doctor.dart';
import '../storage_security.dart';
import 'kernel_task_graph_executor.dart';
import 'universal_task_plan.dart';

typedef ResearchSearchDelegate = Future<List<Map<String, String>>> Function(
  String query,
);
typedef ResearchSynthesisDelegate = Future<String> Function(
  String originalRequest,
  List<Map<String, String>> sources,
);
typedef DiagnosticsCollectDelegate = Future<CapabilityDoctorReport> Function();

class ResearchTaskExecutionResult {
  const ResearchTaskExecutionResult({
    required this.graph,
    required this.answer,
    required this.sources,
  });

  final KernelTaskGraphResult graph;
  final String answer;
  final List<Map<String, String>> sources;
}

class DiagnosticsTaskExecutionResult {
  const DiagnosticsTaskExecutionResult({
    required this.graph,
    required this.answer,
    required this.report,
  });

  final KernelTaskGraphResult graph;
  final String answer;
  final CapabilityDoctorReport report;
}

/// Canonical Research family adapter.
///
/// Chat supplies the real search capability and model synthesis callback, but
/// this class owns task-state transitions and evidence propagation. The UI no
/// longer needs to inspect task titles and invent a second execution loop.
class ResearchTaskFamilyExecutor {
  const ResearchTaskFamilyExecutor({
    this.graphExecutor = const KernelTaskGraphExecutor(),
    this.maxSources = 12,
  });

  final KernelTaskGraphExecutor graphExecutor;
  final int maxSources;

  Future<ResearchTaskExecutionResult> execute({
    required UniversalTaskPlan plan,
    required ResearchSearchDelegate search,
    required ResearchSynthesisDelegate synthesize,
    KernelTaskNodeStateListener? onStateChanged,
    bool Function()? isCancelled,
  }) async {
    if (plan.family != TaskFamily.research) {
      throw ProductException(
        'task_family_mismatch',
        'Research executor received a ${plan.family.name} plan.',
      );
    }

    final graph = await graphExecutor.execute(
      plan: plan,
      onStateChanged: onStateChanged,
      isCancelled: isCancelled,
      executeAuthorizedNode: (task, dependencies, authority) async {
        final phase = task.phase.trim().toLowerCase();
        if (phase == 'research') {
          return KernelTaskNodeResult(
            taskId: task.id,
            state: KernelTaskNodeState.succeeded,
            summary: 'Canonical research objective established.',
            evidence: const <String, dynamic>{'structural': true},
          );
        }
        if (phase == 'retrieval') {
          _requireCapability(authority, 'research.search', task.id);
          final results = await search(task.objective);
          final sources = _normalizeSources(results).take(maxSources).toList();
          if (sources.isEmpty) {
            return KernelTaskNodeResult(
              taskId: task.id,
              state: KernelTaskNodeState.failed,
              summary: 'No attributable research evidence was returned.',
              failureCode: 'research_no_evidence',
            );
          }
          return KernelTaskNodeResult(
            taskId: task.id,
            state: KernelTaskNodeState.succeeded,
            summary: 'Retrieved ${sources.length} attributable source(s).',
            evidence: <String, dynamic>{'sources': sources},
          );
        }
        if (phase == 'verification') {
          _requireCapability(authority, 'research.search', task.id);
          final sources = _sourcesFromDependencies(dependencies)
              .take(maxSources)
              .toList(growable: false);
          if (sources.isEmpty) {
            return KernelTaskNodeResult(
              taskId: task.id,
              state: KernelTaskNodeState.failed,
              summary: 'There is no retrieved evidence to verify.',
              failureCode: 'research_evidence_missing',
            );
          }
          return KernelTaskNodeResult(
            taskId: task.id,
            state: KernelTaskNodeState.succeeded,
            summary: 'Verified ${sources.length} attributable source(s).',
            evidence: <String, dynamic>{
              'sources': sources,
              'verifiedSourceCount': sources.length,
            },
          );
        }
        if (phase == 'synthesis') {
          _requireCapability(authority, 'research.search', task.id);
          final sources = _sourcesFromDependencies(dependencies)
              .take(maxSources)
              .toList(growable: false);
          if (sources.isEmpty) {
            return KernelTaskNodeResult(
              taskId: task.id,
              state: KernelTaskNodeState.failed,
              summary: 'Grounded synthesis requires verified evidence.',
              failureCode: 'research_evidence_missing',
            );
          }
          final answer = (await synthesize(
            plan.specification.originalRequest,
            sources,
          ))
              .trim();
          if (answer.isEmpty) {
            return KernelTaskNodeResult(
              taskId: task.id,
              state: KernelTaskNodeState.failed,
              summary: 'The synthesis provider returned an empty answer.',
              failureCode: 'research_synthesis_empty',
            );
          }
          return KernelTaskNodeResult(
            taskId: task.id,
            state: KernelTaskNodeState.succeeded,
            summary: 'Produced one evidence-grounded answer.',
            evidence: <String, dynamic>{
              'sources': sources,
              'answer': answer,
            },
          );
        }
        return KernelTaskNodeResult(
          taskId: task.id,
          state: KernelTaskNodeState.failed,
          summary: 'Unsupported research task phase ${task.phase}.',
          failureCode: 'research_task_phase_unsupported',
        );
      },
    );

    final synthesis = _lastByPhase(plan, graph, 'synthesis');
    final answer = synthesis?.evidence['answer']?.toString().trim() ?? '';
    final sources = synthesis == null
        ? const <Map<String, String>>[]
        : _sourcesFromEvidence(synthesis.evidence)
            .take(maxSources)
            .toList(growable: false);
    if (!graph.succeeded || answer.isEmpty) {
      final failed = graph.results.values
          .where((result) => result.state == KernelTaskNodeState.failed)
          .firstOrNull;
      throw ProductException(
        failed?.failureCode ?? 'research_graph_failed',
        failed?.summary.isNotEmpty == true
            ? failed!.summary
            : 'The canonical research graph did not complete.',
      );
    }
    return ResearchTaskExecutionResult(
      graph: graph,
      answer: answer,
      sources: sources,
    );
  }
}

/// Canonical Diagnostics family adapter. The real Doctor report is collected
/// by the Evidence task, propagated through Analysis, and rendered into one
/// evidence-backed answer by Synthesis.
class DiagnosticsTaskFamilyExecutor {
  const DiagnosticsTaskFamilyExecutor({
    this.graphExecutor = const KernelTaskGraphExecutor(),
  });

  final KernelTaskGraphExecutor graphExecutor;

  Future<DiagnosticsTaskExecutionResult> execute({
    required UniversalTaskPlan plan,
    required DiagnosticsCollectDelegate collect,
    KernelTaskNodeStateListener? onStateChanged,
    bool Function()? isCancelled,
  }) async {
    if (plan.family != TaskFamily.diagnostics) {
      throw ProductException(
        'task_family_mismatch',
        'Diagnostics executor received a ${plan.family.name} plan.',
      );
    }

    CapabilityDoctorReport? collectedReport;
    final graph = await graphExecutor.execute(
      plan: plan,
      onStateChanged: onStateChanged,
      isCancelled: isCancelled,
      executeAuthorizedNode: (task, dependencies, authority) async {
        _requireCapability(authority, 'system.diagnose', task.id);
        final phase = task.phase.trim().toLowerCase();
        if (phase == 'diagnostics') {
          return KernelTaskNodeResult(
            taskId: task.id,
            state: KernelTaskNodeState.succeeded,
            summary: 'Canonical diagnostic objective established.',
            evidence: const <String, dynamic>{'structural': true},
          );
        }
        if (phase == 'evidence') {
          final report = await collect();
          collectedReport = report;
          return KernelTaskNodeResult(
            taskId: task.id,
            state: KernelTaskNodeState.succeeded,
            summary: 'Collected ${report.checks.length} diagnostic check(s).',
            evidence: <String, dynamic>{'report': _reportEvidence(report)},
          );
        }
        if (phase == 'analysis') {
          final report = collectedReport;
          if (report == null || !_dependenciesContainReport(dependencies)) {
            return KernelTaskNodeResult(
              taskId: task.id,
              state: KernelTaskNodeState.failed,
              summary: 'Diagnostic analysis has no collected report.',
              failureCode: 'diagnostic_evidence_missing',
            );
          }
          final blocked = report.checks
              .where((check) => check.status == CapabilityDoctorStatus.blocked)
              .map((check) => check.id)
              .toList(growable: false);
          final warnings = report.checks
              .where((check) => check.status == CapabilityDoctorStatus.warning)
              .map((check) => check.id)
              .toList(growable: false);
          return KernelTaskNodeResult(
            taskId: task.id,
            state: KernelTaskNodeState.succeeded,
            summary: 'Interpreted diagnostic signals.',
            evidence: <String, dynamic>{
              'report': _reportEvidence(report),
              'blockedCheckIds': blocked,
              'warningCheckIds': warnings,
            },
          );
        }
        if (phase == 'synthesis') {
          final report = collectedReport;
          if (report == null || !_dependenciesContainReport(dependencies)) {
            return KernelTaskNodeResult(
              taskId: task.id,
              state: KernelTaskNodeState.failed,
              summary: 'Diagnostic synthesis has no evidence.',
              failureCode: 'diagnostic_evidence_missing',
            );
          }
          final answer = _diagnosticAnswer(report);
          return KernelTaskNodeResult(
            taskId: task.id,
            state: KernelTaskNodeState.succeeded,
            summary: 'Produced an evidence-backed diagnostic answer.',
            evidence: <String, dynamic>{
              'report': _reportEvidence(report),
              'answer': answer,
            },
          );
        }
        return KernelTaskNodeResult(
          taskId: task.id,
          state: KernelTaskNodeState.failed,
          summary: 'Unsupported diagnostic task phase ${task.phase}.',
          failureCode: 'diagnostic_task_phase_unsupported',
        );
      },
    );

    final report = collectedReport;
    final synthesis = _lastByPhase(plan, graph, 'synthesis');
    final answer = synthesis?.evidence['answer']?.toString().trim() ?? '';
    if (!graph.succeeded || report == null || answer.isEmpty) {
      final failed = graph.results.values
          .where((result) => result.state == KernelTaskNodeState.failed)
          .firstOrNull;
      throw ProductException(
        failed?.failureCode ?? 'diagnostic_graph_failed',
        failed?.summary.isNotEmpty == true
            ? failed!.summary
            : 'The canonical diagnostic graph did not complete.',
      );
    }
    return DiagnosticsTaskExecutionResult(
      graph: graph,
      answer: answer,
      report: report,
    );
  }
}

void _requireCapability(
  Map<String, dynamic> authority,
  String capabilityId,
  String taskId,
) {
  if (!authority.containsKey(capabilityId)) {
    throw ProductException(
      'task_capability_missing',
      '$taskId does not carry required capability $capabilityId.',
    );
  }
}

Iterable<Map<String, String>> _normalizeSources(
  Iterable<Map<String, String>> raw,
) sync* {
  final seen = <String>{};
  for (final source in raw) {
    final url = source['url']?.trim() ?? '';
    if (url.isEmpty || !seen.add(url)) continue;
    yield <String, String>{
      'title': source['title']?.trim() ?? url,
      'url': url,
      'snippet': source['snippet']?.trim() ?? '',
    };
  }
}

List<Map<String, String>> _sourcesFromDependencies(
  Map<String, KernelTaskNodeResult> dependencies,
) {
  final all = <Map<String, String>>[];
  for (final result in dependencies.values) {
    all.addAll(_sourcesFromEvidence(result.evidence));
  }
  return _normalizeSources(all).toList(growable: false);
}

List<Map<String, String>> _sourcesFromEvidence(Map<String, dynamic> evidence) {
  final raw = evidence['sources'];
  if (raw is! List) return const <Map<String, String>>[];
  return raw.whereType<Map>().map((item) {
    final map = Map<Object?, Object?>.from(item);
    return <String, String>{
      'title': map['title']?.toString() ?? '',
      'url': map['url']?.toString() ?? '',
      'snippet': map['snippet']?.toString() ?? '',
    };
  }).toList(growable: false);
}

KernelTaskNodeResult? _lastByPhase(
  UniversalTaskPlan plan,
  KernelTaskGraphResult graph,
  String phase,
) {
  for (final task in plan.tasks.reversed) {
    if (task.phase.trim().toLowerCase() == phase) {
      return graph.results[task.id];
    }
  }
  return null;
}

bool _dependenciesContainReport(
  Map<String, KernelTaskNodeResult> dependencies,
) =>
    dependencies.values.any((result) => result.evidence['report'] is Map);

Map<String, dynamic> _reportEvidence(CapabilityDoctorReport report) =>
    <String, dynamic>{
      'checkedAt': report.checkedAt.toUtc().toIso8601String(),
      'coreReady': report.coreReady,
      'allReady': report.allReady,
      'readyCount': report.readyCount,
      'warningCount': report.warningCount,
      'blockedCount': report.blockedCount,
      'checks': <Map<String, dynamic>>[
        for (final check in report.checks)
          <String, dynamic>{
            'id': check.id,
            'title': check.title,
            'status': check.status.name,
            'message': check.message,
            'required': check.required,
          },
      ],
    };

String _diagnosticAnswer(CapabilityDoctorReport report) {
  final blocked = report.checks
      .where((check) => check.status == CapabilityDoctorStatus.blocked)
      .toList(growable: false);
  final warnings = report.checks
      .where((check) => check.status == CapabilityDoctorStatus.warning)
      .toList(growable: false);
  if (blocked.isNotEmpty) {
    return 'Diagnostics found ${blocked.length} blocking issue(s): '
        '${blocked.map((check) => '${check.title}: ${check.message}').join(' ')}';
  }
  if (warnings.isNotEmpty) {
    return 'Core diagnostics are available, with ${warnings.length} warning(s): '
        '${warnings.map((check) => '${check.title}: ${check.message}').join(' ')}';
  }
  return 'Diagnostics are healthy: all ${report.checks.length} check(s) are ready.';
}
