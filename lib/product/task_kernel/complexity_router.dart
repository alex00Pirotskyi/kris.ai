// Adaptive complexity routing.
//
// Universal task planning does not mean planning everything. It means one
// place decides how much planning a request is worth, using the semantic
// structure of the specification rather than a keyword table or a task
// count someone picked.
//
//   hello                             -> direct   (conversation)
//   what is SQLite?                   -> direct   (information)
//   /run @test8B                      -> direct   (deterministic action)
//   create Desktop/testFF.txt "..."   -> compact  (tiny real graph)
//   weather in X and time in Y        -> compact  (two subgoals, hidden)
//   compare 20 laptop offers          -> graph
//   build a full application          -> graph
//
// The router returns a rationale alongside the route, because "why did it
// decide to plan / not plan" is a question the user and the developer
// both ask, and a bare enum cannot answer it.
import '../chat_control_plane.dart';
import 'task_specification.dart';
import 'universal_task_plan.dart';

/// The router's decision plus the reasoning that produced it.
class RoutingDecision {
  const RoutingDecision({
    required this.route,
    required this.family,
    required this.rationale,
    this.requiresClarification = false,
  });

  final PlanningRoute route;
  final TaskFamily family;
  final String rationale;

  /// True when a blocking ambiguity means Kristin should ask before
  /// planning at all.
  final bool requiresClarification;

  bool get plans => route != PlanningRoute.direct;
}

/// Decides how much planning a specification deserves, and which family
/// will execute it.
class ComplexityRouter {
  const ComplexityRouter({this.registry = const ChatCapabilityRegistry()});

  final ChatCapabilityRegistry registry;

  /// Maps a capability id to the family whose executor runs it. New
  /// families plug in here rather than growing a parallel planner.
  static const Map<String, TaskFamily> _familyByCapability =
      <String, TaskFamily>{
    'agent.create_project': TaskFamily.software,
    'agent.modify_project': TaskFamily.software,
    'agent.fix_project': TaskFamily.software,
    'project.build': TaskFamily.software,
    'research.search': TaskFamily.research,
    'system.diagnose': TaskFamily.diagnostics,
    'project.analyze': TaskFamily.diagnostics,
    'project.review': TaskFamily.diagnostics,
    'project.test': TaskFamily.diagnostics,
    'owner.mode': TaskFamily.owner,
  };

  /// The family that will execute [capabilityId], defaulting to software.
  TaskFamily familyFor(String capabilityId) =>
      _familyByCapability[capabilityId] ?? TaskFamily.software;

  RoutingDecision route({
    required TaskSpecification specification,
    required ChatInteractionDecision decision,
  }) {
    final capability = decision.capability;
    final family = familyFor(capability?.id ?? '');

    // A blocking ambiguity outranks everything: planning around a
    // question we know we cannot answer produces confident nonsense.
    if (specification.blockingQuestions.isNotEmpty) {
      return RoutingDecision(
        route: PlanningRoute.direct,
        family: family,
        rationale: 'A blocking ambiguity must be resolved before planning: '
            '${specification.blockingQuestions.first.question}',
        requiresClarification: true,
      );
    }

    // Conversation and information are not tasks.
    if (decision.kind == ChatInteractionKind.informational ||
        decision.kind == ChatInteractionKind.reference) {
      return RoutingDecision(
        route: PlanningRoute.direct,
        family: family,
        rationale: decision.kind == ChatInteractionKind.reference
            ? 'A bare target reference is context, not work.'
            : 'An informational message is answered directly.',
      );
    }

    if (capability == null) {
      return RoutingDecision(
        route: PlanningRoute.direct,
        family: family,
        rationale: 'No capability was identified, so there is nothing to '
            'decompose.',
      );
    }

    // An explicit deterministic invocation is already exactly specified.
    // "/run @test8B" needs authority, not a model-authored plan.
    if (decision.parsed.hasExplicitCommand &&
        capability.actionClass != ChatActionClass.substantial &&
        specification.subObjectives.isEmpty) {
      return RoutingDecision(
        route: PlanningRoute.direct,
        family: family,
        rationale: 'An explicit ${capability.canonicalSlash} invocation is '
            'already fully specified; authority still applies.',
      );
    }

    // A capability whose policy forbids planning is never planned, but
    // it can still carry a compact internal graph when the request has
    // real internal structure to verify (see the research example: two
    // independent facts, freshness, synthesis).
    if (capability.planningPolicy == ChatPlanningPolicy.never) {
      if (_hasInternalStructure(specification)) {
        return RoutingDecision(
          route: PlanningRoute.compact,
          family: family,
          rationale: 'The request has ${specification.subObjectives.length} '
              'independent sub-goals worth tracking and verifying, even '
              'though it is small enough to answer in one reply.',
        );
      }
      return RoutingDecision(
        route: PlanningRoute.direct,
        family: family,
        rationale: '${capability.displayName} is a direct capability with no '
            'internal structure to decompose.',
      );
    }

    // Substantial work: decide graph vs compact on the actual richness of
    // the specification, never on a fixed task count.
    final weight = _weigh(specification, capability);
    if (weight >= _graphThreshold) {
      return RoutingDecision(
        route: PlanningRoute.graph,
        family: family,
        rationale: 'The request carries enough scope, constraints, and '
            'verification surface (weight $weight) to be worth a reviewed '
            'task graph.',
      );
    }
    return RoutingDecision(
      route: PlanningRoute.compact,
      family: family,
      rationale: 'The request is small and well specified (weight $weight); '
          'a compact plan is enough.',
    );
  }

  /// True when a nominally-direct request nevertheless decomposes into
  /// independently satisfiable parts worth verifying separately.
  bool _hasInternalStructure(TaskSpecification specification) =>
      specification.subObjectives.length >= 2;

  /// Scores how much decomposition a request actually merits.
  ///
  /// Deliberately additive over semantic features of the specification --
  /// scope, sub-goals, constraints, criteria, uncertainty -- rather than
  /// over request length or a task-count threshold. A short sentence can
  /// be substantial ("build an MP3 converter with progress and download")
  /// and a long one can be trivial.
  /// The weight at or above which a reviewed task graph is worth its
  /// cost. Below it, a compact plan does the same job with less ceremony.
  static const int _graphThreshold = 4;

  int _weigh(
    TaskSpecification specification,
    KristinCapability capability,
  ) {
    var weight = 0;
    if (capability.actionClass == ChatActionClass.substantial) weight += 2;
    // Provisioning a brand-new project is inherently multi-stage --
    // scaffold, implement, verify -- in a way that changing one string in
    // an existing project is not.
    if (capability.route == ChatExecutionRoute.createProject) weight += 1;
    if (capability.riskClass == ChatRiskClass.mutation ||
        capability.riskClass == ChatRiskClass.destructive) {
      weight += 1;
    }
    if (specification.subObjectives.length >= 2) weight += 1;
    if (specification.subObjectives.length >= 4) weight += 1;
    if (specification.hardConstraints.isNotEmpty) weight += 1;
    if (specification.successCriteria.length >= 2) weight += 1;
    if (specification.unresolvedQuestions.isNotEmpty) weight += 1;
    // A reading Kristin is unsure of deserves a plan the user can check.
    if (specification.confidence < 0.6) weight += 1;
    return weight;
  }
}
