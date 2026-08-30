import 'planning_failures.dart';

class PlanCompileRepairOutcome<TPlan, TCompiled> {
  const PlanCompileRepairOutcome({
    required this.plan,
    required this.compiled,
    required this.repaired,
    this.firstFailure,
  });

  final TPlan plan;
  final TCompiled compiled;
  final bool repaired;
  final PlanningFailure? firstFailure;
}

typedef PlanCompileAttempt<TPlan, TCompiled> = TCompiled Function(TPlan plan);
typedef PlanCompileDiagnosticRepair<TPlan> = Future<TPlan> Function(
  TPlan rejectedPlan,
  PlanningFailure compileFailure,
);

/// Exactly one bounded repair for a plan that generated successfully but
/// failed deterministic compilation.
///
/// Generation-level repair already exists in PromptPlanningService. This seam
/// covers the distinct failure boundary that comes afterwards: compiler
/// diagnostics are fed back to the planner once, the repaired plan is compiled
/// once, and any second failure propagates. Cancellation, provider, authority,
/// persistence, and unexpected failures never enter the repair path.
class BoundedPlanCompileRepair<TPlan, TCompiled> {
  const BoundedPlanCompileRepair();

  Future<PlanCompileRepairOutcome<TPlan, TCompiled>> run({
    required TPlan plan,
    required PlanCompileAttempt<TPlan, TCompiled> compile,
    required PlanCompileDiagnosticRepair<TPlan> repair,
  }) async {
    try {
      return PlanCompileRepairOutcome<TPlan, TCompiled>(
        plan: plan,
        compiled: compile(plan),
        repaired: false,
      );
    } catch (error, stackTrace) {
      final first = classifyPlanningFailure(error, stackTrace: stackTrace);
      if (!first.allowsConservativeFallback) throw first;
      final repairedPlan = await repair(plan, first);
      try {
        return PlanCompileRepairOutcome<TPlan, TCompiled>(
          plan: repairedPlan,
          compiled: compile(repairedPlan),
          repaired: true,
          firstFailure: first,
        );
      } catch (secondError, secondStackTrace) {
        throw classifyPlanningFailure(
          secondError,
          stackTrace: secondStackTrace,
        );
      }
    }
  }
}
