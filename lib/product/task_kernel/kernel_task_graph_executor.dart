import '../storage_security.dart';
import 'universal_task_plan.dart';

enum KernelTaskNodeState { queued, running, succeeded, failed, skipped }

class KernelTaskNodeResult {
  const KernelTaskNodeResult({
    required this.taskId,
    required this.state,
    this.summary = '',
    this.evidence = const <String, dynamic>{},
    this.failureCode,
  });

  final String taskId;
  final KernelTaskNodeState state;
  final String summary;
  final Map<String, dynamic> evidence;
  final String? failureCode;

  bool get succeeded => state == KernelTaskNodeState.succeeded;
}

class KernelTaskGraphResult {
  const KernelTaskGraphResult({
    required this.plan,
    required this.results,
  });

  final UniversalTaskPlan plan;
  final Map<String, KernelTaskNodeResult> results;

  bool get succeeded {
    for (final task in plan.tasks.where((task) => task.enabled && !task.manual)) {
      if (results[task.id]?.state != KernelTaskNodeState.succeeded) return false;
    }
    return true;
  }
}

typedef KernelTaskNodeExecutor = Future<KernelTaskNodeResult> Function(
  UniversalTask task,
  Map<String, KernelTaskNodeResult> dependencyResults,
);

/// Executes non-Runner task families from the same canonical DAG used by
/// planning and UI projection. Research/diagnostics/utilities bind their own
/// capability executor here instead of manually looping over plan titles.
class KernelTaskGraphExecutor {
  const KernelTaskGraphExecutor();

  Future<KernelTaskGraphResult> execute({
    required UniversalTaskPlan plan,
    required KernelTaskNodeExecutor executeNode,
    bool Function()? isCancelled,
  }) async {
    final validationErrors = plan.validate();
    if (validationErrors.isNotEmpty) {
      throw ProductException('task_plan_invalid', validationErrors.join(' '));
    }

    final enabled = <String, UniversalTask>{
      for (final task in plan.tasks.where((task) => task.enabled)) task.id: task,
    };
    final pending = enabled.keys.toSet();
    final results = <String, KernelTaskNodeResult>{};

    while (pending.isNotEmpty) {
      if (isCancelled?.call() == true) {
        throw ProductException('cancelled', 'Task graph execution was cancelled.');
      }

      final ready = pending
          .map((id) => enabled[id]!)
          .where(
            (task) => task.dependencies.every(
              (dependency) => !enabled.containsKey(dependency) ||
                  results.containsKey(dependency),
            ),
          )
          .toList(growable: false);
      if (ready.isEmpty) {
        throw ProductException(
          'task_plan_invalid',
          'The canonical task graph contains an unresolved dependency cycle.',
        );
      }

      for (final task in ready) {
        if (isCancelled?.call() == true) {
          throw ProductException('cancelled', 'Task graph execution was cancelled.');
        }
        final dependencies = <String, KernelTaskNodeResult>{
          for (final dependency in task.dependencies)
            if (results[dependency] != null) dependency: results[dependency]!,
        };
        final blockedByFailure = dependencies.values.any(
          (result) => result.state != KernelTaskNodeState.succeeded,
        );
        if (task.manual || blockedByFailure) {
          results[task.id] = KernelTaskNodeResult(
            taskId: task.id,
            state: KernelTaskNodeState.skipped,
            summary: task.manual
                ? 'Manual task not executed by the kernel executor.'
                : 'Skipped because a dependency did not succeed.',
          );
          pending.remove(task.id);
          continue;
        }

        KernelTaskNodeResult result;
        try {
          result = await executeNode(task, dependencies);
        } catch (error) {
          result = KernelTaskNodeResult(
            taskId: task.id,
            state: KernelTaskNodeState.failed,
            summary: '$error',
            failureCode: error is ProductException
                ? error.code
                : 'kernel_task_executor_failed',
          );
        }
        if (result.taskId != task.id) {
          throw ProductException(
            'kernel_task_result_mismatch',
            'Executor returned ${result.taskId} while ${task.id} was running.',
          );
        }
        results[task.id] = result;
        pending.remove(task.id);
      }
    }

    return KernelTaskGraphResult(
      plan: plan,
      results: Map<String, KernelTaskNodeResult>.unmodifiable(results),
    );
  }
}
