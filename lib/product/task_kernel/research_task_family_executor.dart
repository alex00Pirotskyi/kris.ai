import '../crypto_utils.dart';
import '../domain.dart';
import '../repository.dart';
import '../storage_security.dart';
import 'task_family_execution.dart';
import 'universal_task_plan.dart';

class ResearchTaskFamilyExecutionResult {
  const ResearchTaskFamilyExecutionResult({
    required this.execution,
    required this.answer,
    required this.evidence,
  });

  final TaskFamilyExecutionRecord execution;
  final String answer;
  final List<Map<String, String>> evidence;
}

/// Executes the canonical Research task graph without a project workspace.
///
/// This is deliberately not the Runner: the Runner owns project-bound model
/// and tool execution with workspace transactions. Research is a read-only
/// task family whose executor performs governed public retrieval and synthesis
/// against the SAME UniversalTaskPlan. Optional [projectId] only archives the
/// resulting search; it never gates execution.
class ResearchTaskFamilyExecutor {
  ResearchTaskFamilyExecutor({
    required this.repository,
    required this.events,
    required this.audit,
  });

  final EntityRepository<TaskFamilyExecutionRecord> repository;
  final EventJournal events;
  final AuditChain audit;

  Future<ResearchTaskFamilyExecutionResult> execute({
    required UniversalTaskPlan plan,
    required String request,
    required Future<List<Map<String, String>>> Function(String query) search,
    required Future<Map<String, String>> Function(String url) fetch,
    required Future<String> Function(
      String request,
      List<Map<String, String>> evidence,
    ) synthesize,
    String? projectId,
    Future<void> Function(
      String query,
      List<Map<String, String>> results,
    )? archive,
    String? sourceExecutionId,
  }) async {
    if (plan.family != TaskFamily.research) {
      throw ProductException(
        'task_family_executor_mismatch',
        'Research executor received a ${plan.family.name} plan.',
      );
    }
    final now = DateTime.now().toUtc();
    var execution = TaskFamilyExecutionRecord(
      id: newId('family_execution'),
      family: TaskFamily.research,
      planId: plan.id,
      specificationId: plan.specification.id,
      request: request,
      projectId: projectId,
      sourceExecutionId: sourceExecutionId,
      planSnapshot: plan,
      state: TaskFamilyExecutionState.running,
      tasks: <TaskFamilyTaskProgress>[
        for (final task in plan.tasks)
          TaskFamilyTaskProgress(
            taskId: task.id,
            title: task.title,
            phase: task.phase,
            state: TaskFamilyTaskState.queued,
          ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    await _persist(execution, 'task_family.execution_started');

    final evidence = <Map<String, String>>[];
    final seen = <String>{};
    try {
      final retrievals = plan.tasks
          .where((task) => task.phase == 'Retrieval')
          .toList(growable: false);
      for (final task in retrievals) {
        execution = await _setTask(
          execution,
          task.id,
          TaskFamilyTaskState.running,
          startedAt: DateTime.now().toUtc(),
        );
        final subject = task.title.startsWith('Obtain ')
            ? task.title.substring('Obtain '.length).trim()
            : task.objective.trim();
        final results = await search(subject.isEmpty ? request : subject);
        if (archive != null) {
          final archiveQuery = subject.isEmpty ? request : subject;
          try {
            await archive(archiveQuery, results);
          } catch (failure) {
            // Optional project knowledge enrichment must never erase valid
            // network evidence. Persist a warning on the task-family execution
            // and audit only redaction-safe structural diagnostics.
            await audit.append(
              'task_family.research_archive_failed',
              execution.id,
              <String, dynamic>{
                'executionId': execution.id,
                'projectId': execution.projectId,
                'queryHash': Sha256.text(archiveQuery),
                'resultCount': results.length,
                'failureType': failure.runtimeType.toString(),
                'warning': 'optional_archive_failed',
                'answerPreserved': true,
              },
            );
            await events.publish(
              'task_family.research_archive_failed',
              execution.id,
              <String, dynamic>{
                'executionId': execution.id,
                'projectId': execution.projectId,
                'queryHash': Sha256.text(archiveQuery),
                'warning': 'optional_archive_failed',
                'answerPreserved': true,
              },
            );
          }
        }
        var grounded = 0;
        for (final result in results.take(5)) {
          final url = result['url']?.trim() ?? '';
          if (url.isEmpty || !seen.add(url)) continue;
          try {
            final fetched = await fetch(url);
            final normalized = <String, String>{
              'taskId': task.id,
              'query': subject,
              'title': fetched['title'] ?? result['title'] ?? '',
              'url': fetched['url'] ?? url,
              'description': result['description'] ?? '',
              'contentHash': fetched['contentHash'] ?? '',
              'fetchedAt': fetched['fetchedAt'] ?? '',
              'excerpt': fetched['excerpt'] ?? '',
            };
            if ((normalized['contentHash'] ?? '').isEmpty) continue;
            evidence.add(normalized);
            grounded += 1;
            if (grounded >= 2) break;
          } catch (_) {
            // One candidate failing to fetch does not erase other grounded
            // candidates. The task fails only if none can be established.
          }
        }
        if (grounded == 0) {
          throw ProductException(
            'research_evidence_missing',
            'No attributable source could be fetched for "$subject".',
            details: <String, dynamic>{
              'executionId': execution.id,
              'taskId': task.id,
            },
          );
        }
        execution = await _setTask(
          execution,
          task.id,
          TaskFamilyTaskState.succeeded,
          resultCount: grounded,
          completedAt: DateTime.now().toUtc(),
          evidence: evidence,
        );
      }

      for (final task
          in plan.tasks.where((task) => task.phase == 'Verification')) {
        execution = await _setTask(
          execution,
          task.id,
          TaskFamilyTaskState.running,
          startedAt: DateTime.now().toUtc(),
        );
        final invalid = evidence.where((item) {
          final uri = Uri.tryParse(item['url'] ?? '');
          return uri == null ||
              uri.scheme != 'https' ||
              (item['contentHash'] ?? '').isEmpty ||
              DateTime.tryParse(item['fetchedAt'] ?? '') == null;
        }).toList(growable: false);
        if (evidence.isEmpty || invalid.isNotEmpty) {
          throw ProductException(
            'research_grounding_invalid',
            'Retrieved research evidence did not pass deterministic grounding checks.',
          );
        }
        execution = await _setTask(
          execution,
          task.id,
          TaskFamilyTaskState.succeeded,
          resultCount: evidence.length,
          completedAt: DateTime.now().toUtc(),
        );
      }

      final answer = await synthesize(request, evidence);
      if (answer.trim().isEmpty) {
        throw ProductException(
          'research_synthesis_empty',
          'Research synthesis returned an empty answer.',
        );
      }
      for (final task
          in plan.tasks.where((task) => task.phase == 'Synthesis')) {
        execution = await _setTask(
          execution,
          task.id,
          TaskFamilyTaskState.succeeded,
          resultCount: evidence.length,
          startedAt: DateTime.now().toUtc(),
          completedAt: DateTime.now().toUtc(),
        );
      }
      // Root/coordination tasks are bookkeeping, not independent retrieval
      // effects. Mark them complete only after every child phase succeeded.
      for (final task in plan.tasks.where(
        (task) => !const <String>{'Retrieval', 'Verification', 'Synthesis'}
            .contains(task.phase),
      )) {
        execution = await _setTask(
          execution,
          task.id,
          TaskFamilyTaskState.succeeded,
          resultCount: evidence.length,
          startedAt: execution.createdAt,
          completedAt: DateTime.now().toUtc(),
        );
      }
      final completed = DateTime.now().toUtc();
      execution = execution.copyWith(
        state: TaskFamilyExecutionState.succeeded,
        evidence: List<Map<String, String>>.unmodifiable(evidence),
        answer: answer.trim(),
        updatedAt: completed,
        completedAt: completed,
      );
      await _persist(execution, 'task_family.execution_succeeded');
      return ResearchTaskFamilyExecutionResult(
        execution: execution,
        answer: answer.trim(),
        evidence: execution.evidence,
      );
    } catch (error) {
      final completed = DateTime.now().toUtc();
      execution = execution.copyWith(
        state: TaskFamilyExecutionState.failed,
        evidence: List<Map<String, String>>.unmodifiable(evidence),
        failure: '$error',
        updatedAt: completed,
        completedAt: completed,
      );
      await _persist(execution, 'task_family.execution_failed');
      rethrow;
    }
  }

  Future<List<TaskFamilyExecutionRecord>> reconcileInterrupted() async {
    final running = (await repository.all())
        .where((value) => value.state == TaskFamilyExecutionState.running)
        .toList(growable: false);
    final reconciled = <TaskFamilyExecutionRecord>[];
    for (final value in running) {
      final now = DateTime.now().toUtc();
      final tasks = <TaskFamilyTaskProgress>[
        for (final task in value.tasks)
          task.state == TaskFamilyTaskState.running
              ? task.copyWith(
                  state: TaskFamilyTaskState.failed,
                  failure: 'Interrupted by application restart.',
                  completedAt: now,
                )
              : task,
      ];
      final interrupted = value.copyWith(
        state: TaskFamilyExecutionState.interrupted,
        tasks: List<TaskFamilyTaskProgress>.unmodifiable(tasks),
        failure:
            'research_interrupted: Application restarted before this research execution completed.',
        updatedAt: now,
        completedAt: now,
      );
      await _persist(interrupted, 'task_family.execution_interrupted');
      reconciled.add(interrupted);
    }
    return List<TaskFamilyExecutionRecord>.unmodifiable(reconciled);
  }

  Future<ResearchTaskFamilyExecutionResult> retry({
    required TaskFamilyExecutionRecord source,
    required Future<List<Map<String, String>>> Function(String query) search,
    required Future<Map<String, String>> Function(String url) fetch,
    required Future<String> Function(
      String request,
      List<Map<String, String>> evidence,
    ) synthesize,
    Future<void> Function(
      String query,
      List<Map<String, String>> results,
    )? archive,
  }) {
    if (!const <TaskFamilyExecutionState>{
      TaskFamilyExecutionState.interrupted,
      TaskFamilyExecutionState.failed,
    }.contains(source.state)) {
      throw ProductException(
        'research_retry_state_invalid',
        'Only interrupted or failed Research executions can be retried.',
      );
    }
    final plan = source.planSnapshot;
    if (plan == null) {
      throw ProductException(
        'research_retry_plan_missing',
        'This Research execution predates durable plan snapshots and cannot be retried safely.',
      );
    }
    return execute(
      plan: plan,
      request: source.request,
      projectId: source.projectId,
      sourceExecutionId: source.id,
      search: search,
      fetch: fetch,
      synthesize: synthesize,
      archive: archive,
    );
  }

  Future<TaskFamilyExecutionRecord> _setTask(
    TaskFamilyExecutionRecord execution,
    String taskId,
    TaskFamilyTaskState state, {
    int? resultCount,
    DateTime? startedAt,
    DateTime? completedAt,
    List<Map<String, String>>? evidence,
  }) async {
    final tasks = <TaskFamilyTaskProgress>[
      for (final progress in execution.tasks)
        progress.taskId == taskId
            ? progress.copyWith(
                state: state,
                resultCount: resultCount,
                startedAt: startedAt,
                completedAt: completedAt,
              )
            : progress,
    ];
    final updated = execution.copyWith(
      tasks: List<TaskFamilyTaskProgress>.unmodifiable(tasks),
      evidence: evidence == null
          ? execution.evidence
          : List<Map<String, String>>.unmodifiable(evidence),
      updatedAt: DateTime.now().toUtc(),
    );
    await repository.put(updated);
    await events.publish(
        'task_family.task_${state.name}', execution.id, <String, dynamic>{
      'executionId': execution.id,
      'taskId': taskId,
      'family': execution.family.name,
      'state': state.name,
      if (resultCount != null) 'resultCount': resultCount,
    });
    return updated;
  }

  Future<void> _persist(
    TaskFamilyExecutionRecord execution,
    String eventType,
  ) async {
    await repository.put(execution);
    await audit.append(eventType, execution.id, <String, dynamic>{
      'executionId': execution.id,
      'family': execution.family.name,
      'planId': execution.planId,
      'specificationId': execution.specificationId,
      'projectId': execution.projectId,
      'state': execution.state.name,
      'taskCount': execution.tasks.length,
      'evidenceCount': execution.evidence.length,
    });
    await events.publish(eventType, execution.id, <String, dynamic>{
      'executionId': execution.id,
      'family': execution.family.name,
      'planId': execution.planId,
      'projectId': execution.projectId,
      'state': execution.state.name,
      'taskCount': execution.tasks.length,
      'evidenceCount': execution.evidence.length,
    });
  }
}
