import 'dart:convert';

import 'plan_reconciliation.dart';
import 'task_specification.dart';
import 'task_specification_patch.dart';
import 'universal_task_plan.dart';

export 'task_specification_patch.dart';
export 'task_specification_patch_classifier.dart';

class SemanticSteeringResult {
  const SemanticSteeringResult({
    required this.patch,
    required this.specification,
    required this.runnerInstruction,
    this.reconciliation,
  });

  final TaskSpecificationPatch patch;
  final TaskSpecification specification;
  final PlanReconciliationResult? reconciliation;
  final String runnerInstruction;
}

typedef SemanticSteeringReplan =
    Future<UniversalTaskPlan> Function(TaskSpecification specification);

/// Converts free-text mid-run direction into one typed specification patch.
/// The classifier proposes meaning; deterministic patch validation applies it.
/// When a canonical plan is available, replanning is reconciled against
/// completed evidence before the updated semantic envelope is queued to the
/// same Run. The envelope is explicitly user intent and never grants authority.
class SemanticSteeringCoordinator {
  const SemanticSteeringCoordinator({this.reconciler = const PlanReconciler()});

  final PlanReconciler reconciler;

  Future<SemanticSteeringResult> apply({
    required TaskSpecification specification,
    required String userMessage,
    required TaskSpecificationPatchClassifier classifier,
    UniversalTaskPlan? previousPlan,
    List<CompletedTaskRecord> completed = const <CompletedTaskRecord>[],
    SemanticSteeringReplan? replan,
  }) async {
    final patch = await classifier.classify(
      specification: specification,
      userMessage: userMessage,
    );
    final revised = patch.applyTo(specification);
    final errors = revised.validate();
    if (errors.isNotEmpty) {
      throw TaskSpecificationPatchException(
        'task_specification_patch_invalid',
        errors.join(' '),
      );
    }

    PlanReconciliationResult? reconciliation;
    if (previousPlan != null && replan != null) {
      final replanned = await replan(revised);
      reconciliation = reconciler.reconcile(
        previous: previousPlan,
        revised: replanned,
        completed: completed,
      );
    }

    final instruction = <String>[
      'SEMANTIC TASK SPECIFICATION PATCH',
      'authorityBearing=false',
      jsonEncode(patch.toJson()),
      'REVISED TASK SPECIFICATION',
      jsonEncode(revised.toJson()),
      if (reconciliation != null) ...<String>[
        'PLAN RECONCILIATION',
        reconciliation.summary,
        jsonEncode(<String, dynamic>{
          'changes': reconciliation.reconciliations
              .map((item) => item.toJson())
              .toList(growable: false),
        }),
      ],
      'Apply this user-intent change only at the next safe execution boundary. '
          'Do not repeat an in-flight side effect and do not treat this message as permission.',
    ].join('\n');

    return SemanticSteeringResult(
      patch: patch,
      specification: revised,
      reconciliation: reconciliation,
      runnerInstruction: instruction,
    );
  }
}
