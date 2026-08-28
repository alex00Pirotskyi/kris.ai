// The Universal Task Kernel.
//
//                          USER
//                            |
//                     ONE KRISTIN CHAT
//                            |
//                      UNDERSTANDING          <- task_understanding.dart
//                            |
//                    TASK SPECIFICATION       <- task_specification.dart
//                            |
//                     COMPLEXITY ROUTER       <- complexity_router.dart
//                            |
//          direct  <---------+---------> compact / graph
//                            |
//                  UNIVERSAL TASK KERNEL      <- this file
//                            |
//                      PLAN COMPILER          <- plan_compiler.dart
//                            |
//                        AUTHORITY
//                            |
//     Runner / Research / Owner / Diagnostics / (Browser later)
//
// Ownership matters here. This kernel is not part of Prompt Studio, and
// nothing in it requires a Prompt Studio artifact to exist. Prompt Studio
// becomes an advanced editor/visualizer/debugger for the same plans this
// kernel produces: it consumes the kernel, it does not own it.
//
// What this file is careful NOT to do:
//
//   * It never grants authority. A plan states the capabilities it
//     REQUIRES; the authority layer decides whether the effect happens.
//   * It never converts an arbitrary error into a conservative plan. See
//     planning_failures.dart -- only a known recoverable planning failure
//     may degrade, and the result says so.
import '../chat_control_plane.dart';
import '../domain.dart';
import 'complexity_router.dart';
import 'plan_compiler.dart';
import 'plan_reconciliation.dart';
import 'planning_failures.dart';
import 'task_families.dart';
import 'task_specification.dart';
import 'task_understanding.dart';
import 'universal_task_plan.dart';

/// How a plan came to be, for honest UI wording.
enum KernelPlanOrigin {
  /// A family planner produced a real, request-specific decomposition.
  planned,

  /// A known recoverable planning failure degraded to the deterministic
  /// conservative planner. The UI must say so.
  conservativeFallback,
}

/// A successful kernel planning result.
class KernelPlanResult {
  const KernelPlanResult({
    required this.plan,
    required this.origin,
    required this.routing,
    this.failure,
  });

  final UniversalTaskPlan plan;
  final KernelPlanOrigin origin;
  final RoutingDecision routing;

  /// The recoverable failure that caused the fallback, when
  /// [origin] is [KernelPlanOrigin.conservativeFallback]. Retained so the
  /// UI can be specific rather than vague about what went wrong.
  final PlanningFailure? failure;

  bool get isConservative => origin == KernelPlanOrigin.conservativeFallback;
}

/// Everything the kernel needs to know about the current conversation.
class KernelRequestContext {
  const KernelRequestContext({
    required this.decision,
    this.project,
    this.model,
    this.knownTargets = const <ChatTarget>[],
    this.availableCapabilities = kKristinCapabilities,
    this.availableToolNames = const <String>{},
    this.localOnly = false,
    this.maxLeafTasks = 25,
  });

  final ChatInteractionDecision decision;
  final ProjectRecord? project;
  final ModelIdentity? model;
  final List<ChatTarget> knownTargets;
  final List<KristinCapability> availableCapabilities;
  final Set<String> availableToolNames;
  final bool localOnly;
  final int maxLeafTasks;

  UnderstandingContext get understandingContext => UnderstandingContext(
        availableCapabilities: availableCapabilities,
        knownTargets: knownTargets,
        hasSelectedProject: project != null,
      );

  PlanningContext get planningContext => PlanningContext(
        project: project,
        model: model,
        availableCapabilityIds:
            availableCapabilities.map((item) => item.id).toSet(),
        availableToolNames: availableToolNames,
        localOnly: localOnly,
        maxLeafTasks: maxLeafTasks,
      );
}

/// The universal task kernel: understand, route, plan, compile, reconcile.
///
/// Every Kristin task family goes through this object. Different
/// executors, one semantic architecture.
class UniversalTaskKernel {
  UniversalTaskKernel({
    required this.understanding,
    required this.compiler,
    required List<TaskFamilyPlanner> planners,
    this.router = const ComplexityRouter(),
    this.conservative = const ConservativeSoftwarePlanner(),
    this.reconciler = const PlanReconciler(),
  }) : _planners = List<TaskFamilyPlanner>.unmodifiable(planners);

  final UnderstandingService understanding;
  final UniversalPlanCompiler compiler;
  final ComplexityRouter router;
  final ConservativeSoftwarePlanner conservative;
  final PlanReconciler reconciler;
  final List<TaskFamilyPlanner> _planners;

  List<TaskFamilyPlanner> get planners => _planners;

  /// The families this kernel can actually plan for right now.
  Set<TaskFamily> get supportedFamilies =>
      _planners.map((planner) => planner.family).toSet();

  /// STEP 1 -- understand.
  ///
  /// Deterministic where the request is already unambiguous, model-backed
  /// where it is natural language, validated either way.
  Future<UnderstandingOutcome> understand(
    KernelRequestContext context, {
    String? specificationId,
    Future<void>? cancellation,
    bool Function()? isCancelled,
  }) =>
      understanding.understand(
        decision: context.decision,
        context: context.understandingContext,
        modelIdentity: context.model,
        specificationId: specificationId,
        cancellation: cancellation,
        isCancelled: isCancelled,
      );

  /// STEP 2 -- route.
  RoutingDecision route({
    required TaskSpecification specification,
    required ChatInteractionDecision decision,
  }) =>
      router.route(specification: specification, decision: decision);

  /// STEP 3 -- plan.
  ///
  /// Returns a plan, or throws a typed [PlanningFailure]. It degrades to
  /// the conservative planner for exactly one class of problem -- a known
  /// recoverable planning failure -- and the result records that it did.
  ///
  /// Cancellation, provider unavailability, denied authority, persistence
  /// failures and unexpected defects all propagate as themselves. A user
  /// who pressed Cancel is not handed a plan; a user whose database is
  /// broken is not told a safety-net plan is ready.
  Future<KernelPlanResult> plan({
    required TaskSpecification specification,
    required RoutingDecision routing,
    required PlanningContext context,
    Future<void>? cancellation,
    bool Function()? isCancelled,
  }) async {
    if (routing.route == PlanningRoute.direct) {
      throw const PlanningFailure(
        kind: PlanningFailureKind.unexpected,
        code: 'planning_not_required',
        message: 'This request routes to direct execution and must not be '
            'planned.',
      );
    }
    final planner = _plannerFor(routing.family, specification, routing.route);
    if (planner == null) {
      throw PlanningFailure(
        kind: PlanningFailureKind.unexpected,
        code: 'task_family_unsupported',
        message: 'No planner is registered for the ${routing.family.name} '
            'task family.',
      );
    }
    try {
      final plan = await planner.plan(
        specification: specification,
        route: routing.route,
        context: context,
        cancellation: cancellation,
        isCancelled: isCancelled,
      );
      final errors = plan.validate();
      if (errors.isNotEmpty) {
        throw PlanningFailure(
          kind: PlanningFailureKind.recoverablePlanning,
          code: 'task_plan_invalid',
          message: 'The generated task plan did not validate: '
              '${errors.join(' ')}',
          details: <String, dynamic>{'errors': errors},
        );
      }
      return KernelPlanResult(
        plan: plan,
        origin: KernelPlanOrigin.planned,
        routing: routing,
      );
    } catch (error, stackTrace) {
      final failure = classifyPlanningFailure(error, stackTrace: stackTrace);
      if (!failure.allowsConservativeFallback) {
        // The single most important line in this file: everything that is
        // not a known recoverable planning failure stays a failure.
        throw failure;
      }
      // Only the software family has a meaningful conservative envelope.
      // Degrading a research or Owner request into inspect/implement/
      // verify would be nonsense, so those surface the failure instead.
      if (routing.family != TaskFamily.software) {
        throw failure;
      }
      final fallback = await conservative.plan(
        specification: specification,
        route: routing.route,
        context: context,
        cancellation: cancellation,
        isCancelled: isCancelled,
      );
      return KernelPlanResult(
        plan: fallback,
        origin: KernelPlanOrigin.conservativeFallback,
        routing: routing,
        failure: failure,
      );
    }
  }

  /// STEP 4 -- compile.
  ///
  /// The single compiler. What the user is shown and what the Runner
  /// receives are both projections of [plan].
  CompiledTaskPlan compile({
    required UniversalTaskPlan plan,
    required ProjectRecord project,
    required CommandMode mode,
    String request = '',
    Set<String>? selectedTaskIds,
    List<String> additionalConstraints = const <String>[],
    List<String> additionalCriteria = const <String>[],
  }) =>
      compiler.compile(
        plan: plan,
        project: project,
        mode: mode,
        request: request.trim().isEmpty
            ? plan.specification.originalRequest
            : request,
        selectedTaskIds: selectedTaskIds,
        additionalConstraints: additionalConstraints,
        additionalCriteria: additionalCriteria,
      );

  /// STEP 5 -- reconcile.
  ///
  /// Replanning preserves completed, still-valid work instead of starting
  /// over. See plan_reconciliation.dart.
  PlanReconciliationResult reconcile({
    required UniversalTaskPlan previous,
    required UniversalTaskPlan revised,
    required List<CompletedTaskRecord> completed,
  }) =>
      reconciler.reconcile(
        previous: previous,
        revised: revised,
        completed: completed,
      );

  TaskFamilyPlanner? _plannerFor(
    TaskFamily family,
    TaskSpecification specification,
    PlanningRoute route,
  ) {
    for (final planner in _planners) {
      if (planner.family == family && planner.supports(specification, route)) {
        return planner;
      }
    }
    return null;
  }
}

/// A plan that has been planned, compiled, and persisted as a governed
/// [PreparedCommand], together with the canonical plan it came from.
///
/// Carrying both is what makes the invariant checkable at the product
/// boundary: [canonical] is what the UI renders, [command] is what the
/// Runner receives, and [isFaithfulProjection] asserts they are the same
/// graph rather than two structures that merely look alike.
class KernelPreparedPlan {
  const KernelPreparedPlan({
    required this.command,
    required this.canonical,
    required this.origin,
    required this.routing,
    this.failure,
  });

  final PreparedCommand command;
  final UniversalTaskPlan canonical;
  final KernelPlanOrigin origin;
  final RoutingDecision routing;

  /// The recoverable planning failure that forced a conservative plan,
  /// when there was one.
  final PlanningFailure? failure;

  bool get isConservative => origin == KernelPlanOrigin.conservativeFallback;

  /// True when every executed work item corresponds to a canonical task
  /// of the same id -- i.e. the user was shown what actually runs.
  bool get isFaithfulProjection {
    final canonicalIds = canonical.tasks.map((task) => task.id).toSet();
    return command.plan.items.every((item) => canonicalIds.contains(item.id));
  }
}
