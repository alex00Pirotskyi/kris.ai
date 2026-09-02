// The Universal Task Kernel.
//
// USER -> ONE KRISTIN CHAT -> UNDERSTANDING -> TASK SPECIFICATION ->
// COMPLEXITY ROUTER -> UNIVERSAL TASK KERNEL -> PLAN COMPILER -> AUTHORITY ->
// Runner / Research / Owner / Diagnostics / Browser.
//
// Self-awareness enters as planning knowledge. It may only narrow capabilities;
// it never expands the compiled Runner tool allow-list and never grants
// authority.
import '../capability_invocation.dart';
import '../chat_control_plane.dart';
import '../domain.dart';
import '../self_awareness/capability_self_model.dart';
import '../storage_security.dart';
import 'complexity_router.dart';
import 'plan_compiler.dart';
import 'plan_reconciliation.dart';
import 'planning_failures.dart';
import 'task_families.dart';
import 'task_specification.dart';
import 'task_understanding.dart';
import 'universal_task_plan.dart';

enum KernelPlanOrigin { planned, conservativeFallback }

typedef KernelLiveSelfModelResolver = Future<SelfModelPlanningContext> Function({
  required ProjectRecord? project,
  required ModelIdentity? model,
  required Set<String> relevantCapabilityIds,
});

/// Product composition may register a live self-model resolver for a kernel.
/// The kernel only intersects its caller-provided capability set with this
/// result, so a resolver can remove stale/unhealthy capabilities but can never
/// add capabilities the caller/catalog did not already allow.
final class KernelSelfModelRegistry {
  KernelSelfModelRegistry._();

  static final Expando<KernelLiveSelfModelResolver> _resolvers =
      Expando<KernelLiveSelfModelResolver>('kristin-kernel-self-model');

  static void register(
    UniversalTaskKernel kernel,
    KernelLiveSelfModelResolver resolver,
  ) {
    _resolvers[kernel] = resolver;
  }

  static Future<SelfModelPlanningContext?> resolve(
    UniversalTaskKernel kernel, {
    ProjectRecord? project,
    ModelIdentity? model,
    Set<String> relevantCapabilityIds = const <String>{},
  }) async {
    final resolver = _resolvers[kernel];
    if (resolver == null) return null;
    return resolver(
      project: project,
      model: model,
      relevantCapabilityIds: relevantCapabilityIds,
    );
  }
}

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
  final PlanningFailure? failure;
  bool get isConservative => origin == KernelPlanOrigin.conservativeFallback;
}

/// Everything the kernel knows about the current conversation.
///
/// [selfModel] is a bounded live projection of capability existence,
/// availability, blocking reasons and current authority. It is knowledge only.
/// [availableToolNames] remains the exact execution-tool boundary.
class KernelRequestContext {
  const KernelRequestContext({
    required this.decision,
    this.project,
    this.model,
    this.knownTargets = const <ChatTarget>[],
    this.availableCapabilities = kKristinCapabilities,
    this.availableToolNames = const <String>{},
    this.consumedCoordinatorCapabilities = const <String>{},
    this.selfModel,
    this.localOnly = false,
    this.maxLeafTasks = 25,
  });

  final ChatInteractionDecision decision;
  final ProjectRecord? project;
  final ModelIdentity? model;
  final List<ChatTarget> knownTargets;
  final List<KristinCapability> availableCapabilities;
  final Set<String> availableToolNames;
  final Set<String> consumedCoordinatorCapabilities;
  final SelfModelPlanningContext? selfModel;
  final bool localOnly;
  final int maxLeafTasks;

  Set<String> get liveAvailableCapabilityIds {
    final catalog = availableCapabilities.map((item) => item.id).toSet();
    final live = selfModel?.availableCapabilityIds;
    return live == null ? catalog : catalog.intersection(live);
  }

  KernelRequestContext withSelfModel(SelfModelPlanningContext live) =>
      KernelRequestContext(
        decision: decision,
        project: project,
        model: model,
        knownTargets: knownTargets,
        availableCapabilities: availableCapabilities,
        availableToolNames: availableToolNames,
        consumedCoordinatorCapabilities: consumedCoordinatorCapabilities,
        selfModel: live,
        localOnly: localOnly,
        maxLeafTasks: maxLeafTasks,
      );

  UnderstandingContext get understandingContext => UnderstandingContext(
        availableCapabilities: availableCapabilities
            .where((item) => liveAvailableCapabilityIds.contains(item.id))
            .toList(growable: false),
        knownTargets: knownTargets,
        hasSelectedProject: project != null,
      );

  PlanningContext get planningContext => PlanningContext(
        project: project,
        model: model,
        availableCapabilityIds: liveAvailableCapabilityIds,
        availableToolNames: availableToolNames,
        consumedCoordinatorCapabilities: consumedCoordinatorCapabilities,
        localOnly: localOnly,
        maxLeafTasks: maxLeafTasks,
      );
}

class UniversalTaskKernel {
  UniversalTaskKernel({
    required this.understanding,
    required this.compiler,
    required List<TaskFamilyPlanner> planners,
    this.router = const ComplexityRouter(),
    this.conservative = const ConservativeSoftwarePlanner(),
    this.reconciler = const PlanReconciler(),
    this.authorityResolver = const CapabilityAuthorityResolver(),
  }) : _planners = List<TaskFamilyPlanner>.unmodifiable(planners);

  final UnderstandingService understanding;
  final UniversalPlanCompiler compiler;
  final ComplexityRouter router;
  final ConservativeSoftwarePlanner conservative;
  final PlanReconciler reconciler;
  final CapabilityAuthorityResolver authorityResolver;
  final List<TaskFamilyPlanner> _planners;

  List<TaskFamilyPlanner> get planners => _planners;
  Set<TaskFamily> get supportedFamilies =>
      _planners.map((planner) => planner.family).toSet();

  Future<UnderstandingOutcome> understand(
    KernelRequestContext context, {
    String? specificationId,
    Future<void>? cancellation,
    bool Function()? isCancelled,
  }) async {
    var effective = context;
    if (context.selfModel == null) {
      final relevant = <String>{
        if (context.decision.capability != null)
          context.decision.capability!.id,
      };
      final live = await KernelSelfModelRegistry.resolve(
        this,
        project: context.project,
        model: context.model,
        relevantCapabilityIds: relevant,
      );
      if (live != null) effective = context.withSelfModel(live);
    }
    return understanding.understand(
      decision: effective.decision,
      context: effective.understandingContext,
      modelIdentity: effective.model,
      specificationId: specificationId,
      cancellation: cancellation,
      isCancelled: isCancelled,
    );
  }

  RoutingDecision route({
    required TaskSpecification specification,
    required ChatInteractionDecision decision,
  }) =>
      router.route(specification: specification, decision: decision);

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
        message: 'This request routes to direct execution and must not be planned.',
      );
    }

    final live = await KernelSelfModelRegistry.resolve(
      this,
      project: context.project,
      model: context.model,
      relevantCapabilityIds: specification.capabilityHints.toSet(),
    );
    final effectiveContext = live == null
        ? context
        : PlanningContext(
            project: context.project,
            model: context.model,
            availableCapabilityIds: context.availableCapabilityIds
                .intersection(live.availableCapabilityIds),
            availableToolNames: context.availableToolNames,
            consumedCoordinatorCapabilities:
                context.consumedCoordinatorCapabilities,
            localOnly: context.localOnly,
            maxLeafTasks: context.maxLeafTasks,
          );

    final planner = _plannerFor(
      routing.family,
      specification,
      routing.route,
    );
    if (planner == null) {
      throw PlanningFailure(
        kind: PlanningFailureKind.unexpected,
        code: 'task_family_unsupported',
        message:
            'No planner is registered for the ${routing.family.name} task family.',
      );
    }
    try {
      final plan = await planner.plan(
        specification: specification,
        route: routing.route,
        context: effectiveContext,
        cancellation: cancellation,
        isCancelled: isCancelled,
      );
      final errors = plan.validate();
      if (errors.isNotEmpty) {
        throw PlanningFailure(
          kind: PlanningFailureKind.recoverablePlanning,
          code: 'task_plan_invalid',
          message:
              'The generated task plan did not validate: ${errors.join(' ')}',
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
      if (!failure.allowsConservativeFallback) throw failure;
      if (routing.family != TaskFamily.software) throw failure;
      final fallback = await conservative.plan(
        specification: specification,
        route: routing.route,
        context: effectiveContext,
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

  Future<KernelPlanResult> planWithRequestContext({
    required TaskSpecification specification,
    required RoutingDecision routing,
    required KernelRequestContext requestContext,
    Future<void>? cancellation,
    bool Function()? isCancelled,
  }) =>
      plan(
        specification: specification,
        routing: routing,
        context: requestContext.planningContext,
        cancellation: cancellation,
        isCancelled: isCancelled,
      );

  CompiledTaskPlan compile({
    required UniversalTaskPlan plan,
    required ProjectRecord project,
    required CommandMode mode,
    String request = '',
    Set<String>? selectedTaskIds,
    List<String> additionalConstraints = const <String>[],
    List<String> additionalCriteria = const <String>[],
    Set<String> consumedCoordinatorCapabilities = const <String>{},
  }) {
    final compiled = compiler.compile(
      plan: plan,
      project: project,
      mode: mode,
      request: request.trim().isEmpty
          ? plan.specification.originalRequest
          : request,
      selectedTaskIds: selectedTaskIds,
      additionalConstraints: additionalConstraints,
      additionalCriteria: additionalCriteria,
      consumedCoordinatorCapabilities: consumedCoordinatorCapabilities,
    );
    _validateCompiledCapabilityAuthority(compiled);
    return compiled;
  }

  void _validateCompiledCapabilityAuthority(CompiledTaskPlan compiled) {
    final authorityScopes = <PermissionScope>{};
    final capabilityIds = <String>{};
    for (final task in compiled.canonical.tasks) {
      if (!task.enabled || !compiled.selectedTaskIds.contains(task.id)) {
        continue;
      }
      final required = task.requiredCapabilities.toList()..sort();
      for (final capabilityId in required) {
        final decision = authorityResolver.resolve(
          CapabilityInvocation(
            capabilityId: capabilityId,
            modelProposed: true,
            targetIds: <String>{compiled.contract.projectId},
            reason: 'compiled_task:${task.id}',
          ),
        );
        capabilityIds.add(capabilityId);
        authorityScopes.addAll(decision.requiredScopes);
      }
    }
    final missing = authorityScopes
        .difference(compiled.contract.requiredPermissions)
        .toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));
    if (missing.isNotEmpty) {
      throw ProductException(
        'capability_authority_not_compiled',
        'The executable plan requires capability authority that is absent from its permission contract: ${missing.map((scope) => scope.name).join(', ')}.',
        details: <String, dynamic>{
          'capabilityIds': capabilityIds.toList()..sort(),
          'missingScopes': missing.map((scope) => scope.name).toList(),
          'contractScopes': compiled.contract.requiredPermissions
              .map((scope) => scope.name)
              .toList()
            ..sort(),
        },
      );
    }
  }

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
  final PlanningFailure? failure;
  bool get isConservative => origin == KernelPlanOrigin.conservativeFallback;
  bool get isFaithfulProjection {
    final canonicalIds = canonical.tasks.map((task) => task.id).toSet();
    return command.plan.items.every((item) => canonicalIds.contains(item.id));
  }
}
