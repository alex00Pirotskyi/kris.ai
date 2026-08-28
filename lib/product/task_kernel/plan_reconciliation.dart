// Plan reconciliation: replanning without throwing away finished work.
//
// The scenario this exists for:
//
//     ✓ inspect project
//     ✓ define architecture
//     ○ implement Firebase storage
//     ○ build result UI
//     ○ tests
//
//     user: "don't use Firebase"
//
// Regenerating the whole plan -- which is what plan adjustment did before
// -- discards two tasks that were completed, verified, and are still
// perfectly valid, and asks the user to watch them happen again. Worse, it
// loses the evidence they produced.
//
// This file is a real reconciliation seam with a deliberately
// conservative, deterministic strategy. It is not a graph-editing
// solver, and does not pretend to be:
//
//   PRESERVE   a completed task whose semantic identity reappears in the
//              new plan and whose assumptions have not been invalidated
//   INVALIDATE a completed task the new constraint contradicts -- its
//              evidence can no longer be trusted, so it is explicitly
//              invalidated rather than quietly kept
//   ADD        genuinely new work
//   DROP       work the new plan no longer contains
//
// The rule that matters: completed evidence-backed work is never erased
// silently, and a task whose assumptions changed is never silently kept.
import '../domain.dart';
import 'task_specification.dart';
import 'universal_task_plan.dart';

/// What happened to one task across a replan.
enum TaskReconciliationOutcome {
  /// Completed, still valid, carried forward with its evidence.
  preserved,

  /// Completed, but the new specification contradicts what it assumed,
  /// so its result can no longer be trusted. Explicitly invalidated.
  invalidated,

  /// Present in both plans and not yet done. Carried forward.
  carried,

  /// New work introduced by the replan.
  added,

  /// Work the new plan no longer contains.
  removed,
}

/// One task's fate, with the reason, so the UI can show what changed.
class TaskReconciliation {
  const TaskReconciliation({
    required this.taskId,
    required this.title,
    required this.outcome,
    required this.reason,
  });

  final String taskId;
  final String title;
  final TaskReconciliationOutcome outcome;
  final String reason;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'taskId': taskId,
        'title': title,
        'outcome': outcome.name,
        'reason': reason,
      };
}

/// A completed task and the evidence that it completed.
class CompletedTaskRecord {
  const CompletedTaskRecord({
    required this.taskId,
    required this.semanticKey,
    this.evidence = const <String, dynamic>{},
  });

  /// Builds a record from the canonical task that was completed, so the
  /// semantic key is derived the same way on both sides.
  factory CompletedTaskRecord.of(
    UniversalTask task, {
    Map<String, dynamic> evidence = const <String, dynamic>{},
  }) =>
      CompletedTaskRecord(
        taskId: task.id,
        semanticKey: task.semanticKey,
        evidence: evidence,
      );

  final String taskId;

  /// Content identity, so a replan that re-emits the same work under a
  /// new generated id still recognizes it as the same work.
  final String semanticKey;

  final Map<String, dynamic> evidence;

  bool get hasEvidence => evidence.isNotEmpty;
}

/// The reconciled plan plus the per-task record of what changed.
class PlanReconciliationResult {
  const PlanReconciliationResult({
    required this.plan,
    required this.reconciliations,
  });

  final UniversalTaskPlan plan;
  final List<TaskReconciliation> reconciliations;

  List<TaskReconciliation> withOutcome(TaskReconciliationOutcome outcome) =>
      reconciliations
          .where((item) => item.outcome == outcome)
          .toList(growable: false);

  List<TaskReconciliation> get preserved =>
      withOutcome(TaskReconciliationOutcome.preserved);
  List<TaskReconciliation> get invalidated =>
      withOutcome(TaskReconciliationOutcome.invalidated);
  List<TaskReconciliation> get added =>
      withOutcome(TaskReconciliationOutcome.added);
  List<TaskReconciliation> get removed =>
      withOutcome(TaskReconciliationOutcome.removed);

  /// A short human summary of the change, for Chat to show.
  String get summary {
    final parts = <String>[
      if (preserved.isNotEmpty) '${preserved.length} completed task(s) kept',
      if (invalidated.isNotEmpty)
        '${invalidated.length} completed task(s) invalidated',
      if (added.isNotEmpty) '${added.length} new task(s)',
      if (removed.isNotEmpty) '${removed.length} task(s) dropped',
    ];
    return parts.isEmpty ? 'The plan is unchanged.' : parts.join(', ');
  }
}

/// Reconciles a revised plan against the previous plan's completed work.
class PlanReconciler {
  const PlanReconciler();

  /// Merges [revised] onto [previous], preserving completed work that is
  /// still valid under the revised specification.
  ///
  /// [completed] carries the completed task ids and their evidence. A
  /// completed task is preserved when both hold:
  ///
  ///   * the revised plan still contains semantically the same task, and
  ///   * the revised specification does not contradict it.
  ///
  /// Anything else about a completed task is invalidated *explicitly* --
  /// never dropped in silence, because "we redid work you already paid
  /// for" and "we kept a result that is now wrong" are both bad, and only
  /// one of them is visible by accident.
  PlanReconciliationResult reconcile({
    required UniversalTaskPlan previous,
    required UniversalTaskPlan revised,
    required List<CompletedTaskRecord> completed,
  }) {
    final completedByKey = <String, CompletedTaskRecord>{
      for (final record in completed) record.semanticKey: record,
    };
    final previousByKey = <String, UniversalTask>{
      for (final task in previous.tasks) task.semanticKey: task,
    };
    final revisedByKey = <String, UniversalTask>{
      for (final task in revised.tasks) task.semanticKey: task,
    };
    final invalidators =
        _invalidatingTerms(previous.specification, revised.specification);

    final reconciliations = <TaskReconciliation>[];
    final tasks = <UniversalTask>[];
    // Maps a preserved previous-task id onto the revised id that replaces
    // it, so dependencies pointing at preserved work still resolve.
    final idRemap = <String, String>{};

    for (final task in revised.tasks) {
      final completion = completedByKey[task.semanticKey];
      final priorTask = previousByKey[task.semanticKey];
      if (completion == null) {
        reconciliations.add(
          TaskReconciliation(
            taskId: task.id,
            title: task.title,
            outcome: priorTask == null
                ? TaskReconciliationOutcome.added
                : TaskReconciliationOutcome.carried,
            reason: priorTask == null
                ? 'Introduced by the revised request.'
                : 'Still required and not yet completed.',
          ),
        );
        tasks.add(task);
        continue;
      }
      final contradiction = _contradicts(task, invalidators);
      if (contradiction != null) {
        // Completed, but the new constraint contradicts what it did. Its
        // evidence can no longer be trusted, so it is re-enabled as work
        // and the invalidation is stated.
        reconciliations.add(
          TaskReconciliation(
            taskId: task.id,
            title: task.title,
            outcome: TaskReconciliationOutcome.invalidated,
            reason: 'Completed earlier, but the revised request '
                'contradicts it ($contradiction); its result can no longer '
                'be trusted.',
          ),
        );
        tasks.add(task);
        continue;
      }
      idRemap[priorTask?.id ?? task.id] = task.id;
      reconciliations.add(
        TaskReconciliation(
          taskId: task.id,
          title: task.title,
          outcome: TaskReconciliationOutcome.preserved,
          reason: completion.hasEvidence
              ? 'Already completed with evidence and still valid; kept.'
              : 'Already completed and still valid; kept.',
        ),
      );
      // Preserved work is carried forward as satisfied: disabled so it is
      // not redone, and its dependents no longer wait on it.
      tasks.add(task.copyWith(enabled: false));
    }

    for (final task in previous.tasks) {
      if (revisedByKey.containsKey(task.semanticKey)) continue;
      final completion = completedByKey[task.semanticKey];
      if (completion != null && _contradicts(task, invalidators) == null) {
        // Completed, still valid, and simply absent from the revised
        // plan: keep the record of it rather than pretending it never
        // happened.
        reconciliations.add(
          TaskReconciliation(
            taskId: task.id,
            title: task.title,
            outcome: TaskReconciliationOutcome.preserved,
            reason: 'Completed earlier, unaffected by the revision, and '
                'preserved even though the revised plan does not repeat it.',
          ),
        );
        tasks.add(task.copyWith(enabled: false));
        continue;
      }
      reconciliations.add(
        TaskReconciliation(
          taskId: task.id,
          title: task.title,
          outcome: TaskReconciliationOutcome.removed,
          reason: completion == null
              ? 'No longer required by the revised request.'
              : 'Completed earlier, but the revised request removes and '
                  'contradicts it.',
        ),
      );
    }

    // Rewrite dependency and parent edges onto surviving ids, drop edges
    // to tasks that no longer exist, and DISCHARGE edges to preserved
    // work: a dependency that is already satisfied is not a dependency
    // any more, and leaving it in place would both block the graph and
    // fail validation ("depends on disabled task").
    final surviving = tasks.map((task) => task.id).toSet();
    final satisfied =
        tasks.where((task) => !task.enabled).map((task) => task.id).toSet();
    final merged = tasks
        .map(
          (task) => task.copyWith(
            dependencies: task.dependencies
                .map((id) => idRemap[id] ?? id)
                .where(surviving.contains)
                .where((id) => !satisfied.contains(id))
                .toSet(),
            parentId: () {
              final parentId = task.parentId;
              if (parentId == null) return null;
              final mapped = idRemap[parentId] ?? parentId;
              return surviving.contains(mapped) ? mapped : null;
            }(),
            clearParentId: task.parentId != null &&
                !surviving.contains(idRemap[task.parentId] ?? task.parentId),
          ),
        )
        .toList(growable: false);

    return PlanReconciliationResult(
      plan: revised.copyWith(
        id: newId('universal_plan'),
        tasks: merged,
        revision: previous.revision + 1,
        previousPlanId: previous.id,
      ),
      reconciliations: List<TaskReconciliation>.unmodifiable(reconciliations),
    );
  }

  /// Terms the revision newly forbids.
  ///
  /// Built from what the revised specification prohibits or constrains
  /// that the previous one did not -- "don't use Firebase" yields
  /// "firebase". Deliberately lexical and deterministic: this is a
  /// conservative safety check, and its failure mode is invalidating a
  /// task that could have been kept, which costs time rather than
  /// correctness.
  Set<String> _invalidatingTerms(
    TaskSpecification previous,
    TaskSpecification revised,
  ) {
    final before = <String>{
      ...previous.hardConstraints.map((claim) => claim.statement.toLowerCase()),
      ...previous.prohibitedEffects.map((item) => item.toLowerCase()),
    };
    final added = <String>[
      for (final claim in revised.hardConstraints)
        if (!before.contains(claim.statement.toLowerCase())) claim.statement,
      for (final effect in revised.prohibitedEffects)
        if (!before.contains(effect.toLowerCase())) effect,
    ];
    final terms = <String>{};
    for (final statement in added) {
      for (final raw
          in statement.toLowerCase().split(RegExp(r'[^a-z0-9.+#-]+'))) {
        // Interior punctuation is meaningful ("c++", "c#", ".net"), but
        // trailing sentence punctuation is not: without this trim the term
        // from "Do not use Firebase." is "firebase." and never matches the
        // task titled "Implement Firebase storage".
        final word = raw.replaceAll(RegExp(r'^[.+#-]+|[.+#-]+$'), '');
        // Keep only content-bearing words: a constraint's own scaffolding
        // ("do", "not", "use") matches everything and would invalidate the
        // entire plan.
        if (word.length < 4) continue;
        if (_constraintScaffolding.contains(word)) continue;
        terms.add(word);
      }
    }
    return terms;
  }

  /// The term that makes [task] untrustworthy under the revision, or null.
  String? _contradicts(UniversalTask task, Set<String> invalidators) {
    if (invalidators.isEmpty) return null;
    final haystack = <String>[
      task.title,
      task.objective,
      task.instructions,
      task.phase,
      ...task.expectedArtifacts,
      ...task.acceptanceCriteria,
    ].join(' ').toLowerCase();
    for (final term in invalidators) {
      if (haystack.contains(term)) return term;
    }
    return null;
  }

  static const Set<String> _constraintScaffolding = <String>{
    'must',
    'should',
    'never',
    'always',
    'avoid',
    'without',
    'change',
    'changed',
    'modify',
    'modified',
    'touch',
    'using',
    'used',
    'requirement',
    'constraint',
    'please',
    'instead',
    'anything',
    'something',
    'stop',
    'condition',
  };
}
