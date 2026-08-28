// The canonical plan representation, shared by every task family.
//
// Two invariants define this file:
//
// 1. HIERARCHY SURVIVES. `phase`, `parentId` and `dependencies` are
//    first-class here and are carried through compilation into the
//    executable WorkItem, instead of being flattened into description
//    prose the way PromptPlanningService.compilePlan used to. The Runner
//    and the UI can both reason about stages because the stage is still
//    there.
//
// 2. ONE PLAN. The graph shown to the user and the graph the Runner
//    executes are projections of this single object, never two
//    independently-produced structures that happen to look alike. The
//    compiler is a pure function of this plan, so "what I showed you" and
//    "what I ran" cannot drift.
import '../crypto_utils.dart';
import '../domain.dart';
import 'task_specification.dart';

/// Which product family executes a task. Different families use different
/// executors; they do not use different semantic planning systems.
enum TaskFamily {
  /// Project create/modify/fix through the governed agent Runner.
  software,

  /// Retrieval and synthesis through the research capabilities.
  research,

  /// Health and capability inspection through the diagnostics capability.
  diagnostics,

  /// Effects outside the project boundary, subject to Owner authority.
  owner,

  /// Reserved seam. Browser Product Integration is deliberately not
  /// implemented here, but when it lands it compiles into this same plan
  /// rather than growing a parallel browser planner.
  browser,
}

/// How much planning a request actually deserves.
enum PlanningRoute {
  /// No plan at all: converse, or invoke one deterministic capability.
  direct,

  /// A small, deterministic task graph -- real structure, but not worth
  /// showing as a wall of task cards.
  compact,

  /// A full model-authored decomposition worth reviewing before running.
  graph,
}

/// One node of the canonical plan.
///
/// Mirrors PlanTaskRecord's semantics (deliberately: the software family
/// reuses PromptPlanningService's generator wholesale) while being usable
/// by families that never touch Prompt Studio.
class UniversalTask {
  const UniversalTask({
    required this.id,
    required this.title,
    required this.objective,
    required this.instructions,
    this.phase = 'Implementation',
    this.parentId,
    this.dependencies = const <String>{},
    this.acceptanceCriteria = const <String>[],
    this.verificationSteps = const <String>[],
    this.expectedArtifacts = const <String>[],
    this.allowedTools = const <String>{},
    this.requiredCapabilities = const <String>{},
    this.complexity = 3,
    this.effortPoints = 3,
    this.uncertainty = PlanUncertainty.medium,
    this.risk = PlanRisk.low,
    this.estimateConfidence = 0.7,
    this.maxAttempts = 2,
    this.enabled = true,
    this.manual = false,
    this.hidden = false,
    this.provenance = EvidenceProvenance.inferred,
  });

  final String id;
  final String title;
  final String objective;
  final String instructions;

  /// The stage this task belongs to. Preserved through compilation.
  final String phase;

  /// The parent task in the hierarchy, if any. Preserved through
  /// compilation.
  final String? parentId;

  final Set<String> dependencies;
  final List<String> acceptanceCriteria;
  final List<String> verificationSteps;
  final List<String> expectedArtifacts;
  final Set<String> allowedTools;

  /// Canonical capability ids this task needs. A *requirement*, never a
  /// grant -- the authority layer decides whether the effect is allowed.
  final Set<String> requiredCapabilities;

  final int complexity;
  final int effortPoints;
  final PlanUncertainty uncertainty;
  final PlanRisk risk;
  final double estimateConfidence;
  final int maxAttempts;
  final bool enabled;
  final bool manual;

  /// True for internal structure the user does not need to see (a compact
  /// research graph's individual retrieval steps, for example). Hidden
  /// tasks still execute and still verify; universal task planning is not
  /// the same thing as always displaying a plan.
  final bool hidden;

  /// Where this task's justification came from.
  final EvidenceProvenance provenance;

  /// A stable identity derived from what the task *is*, not from the id
  /// a generator happened to assign. Reconciliation matches on this, so
  /// a replan that re-emits the same work recognizes it as the same work.
  String get semanticKey => Sha256.text(
        canonicalJson(<String, dynamic>{
          'title': title.trim().toLowerCase(),
          'objective': objective.trim().toLowerCase(),
          'phase': phase.trim().toLowerCase(),
        }),
      );

  UniversalTask copyWith({
    String? id,
    String? title,
    String? objective,
    String? instructions,
    String? phase,
    String? parentId,
    bool clearParentId = false,
    Set<String>? dependencies,
    List<String>? acceptanceCriteria,
    List<String>? verificationSteps,
    List<String>? expectedArtifacts,
    Set<String>? allowedTools,
    Set<String>? requiredCapabilities,
    int? complexity,
    int? effortPoints,
    PlanUncertainty? uncertainty,
    PlanRisk? risk,
    double? estimateConfidence,
    int? maxAttempts,
    bool? enabled,
    bool? manual,
    bool? hidden,
    EvidenceProvenance? provenance,
  }) =>
      UniversalTask(
        id: id ?? this.id,
        title: title ?? this.title,
        objective: objective ?? this.objective,
        instructions: instructions ?? this.instructions,
        phase: phase ?? this.phase,
        parentId: clearParentId ? null : (parentId ?? this.parentId),
        dependencies: dependencies ?? this.dependencies,
        acceptanceCriteria: acceptanceCriteria ?? this.acceptanceCriteria,
        verificationSteps: verificationSteps ?? this.verificationSteps,
        expectedArtifacts: expectedArtifacts ?? this.expectedArtifacts,
        allowedTools: allowedTools ?? this.allowedTools,
        requiredCapabilities: requiredCapabilities ?? this.requiredCapabilities,
        complexity: complexity ?? this.complexity,
        effortPoints: effortPoints ?? this.effortPoints,
        uncertainty: uncertainty ?? this.uncertainty,
        risk: risk ?? this.risk,
        estimateConfidence: estimateConfidence ?? this.estimateConfidence,
        maxAttempts: maxAttempts ?? this.maxAttempts,
        enabled: enabled ?? this.enabled,
        manual: manual ?? this.manual,
        hidden: hidden ?? this.hidden,
        provenance: provenance ?? this.provenance,
      );

  /// Builds a canonical task from Prompt Studio's PlanTaskRecord without
  /// losing phase/parentId -- the adapter that lets the software family
  /// reuse the existing model planner unchanged.
  factory UniversalTask.fromPlanTask(
    PlanTaskRecord record, {
    Set<String> requiredCapabilities = const <String>{},
  }) =>
      UniversalTask(
        id: record.id,
        title: record.title,
        objective: record.objective,
        instructions: record.instructions,
        phase: record.phase,
        parentId: record.parentId,
        dependencies: record.dependencies,
        acceptanceCriteria: record.acceptanceCriteria,
        verificationSteps: record.verificationSteps,
        expectedArtifacts: record.expectedArtifacts,
        allowedTools: record.allowedTools,
        requiredCapabilities: requiredCapabilities,
        complexity: record.complexity,
        effortPoints: record.effortPoints,
        uncertainty: record.uncertainty,
        risk: record.risk,
        estimateConfidence: record.estimateConfidence,
        maxAttempts: record.maxAttempts,
        enabled: record.enabled,
        manual: record.manual,
        provenance: EvidenceProvenance.assumed,
      );

  /// Projects back into a PlanTaskRecord so Prompt Studio edits, displays
  /// and persists the very same plan Chat produced -- rather than forking
  /// a parallel copy of it.
  PlanTaskRecord toPlanTask() => PlanTaskRecord(
        id: id,
        phase: phase,
        parentId: parentId,
        title: title,
        objective: objective,
        instructions: instructions,
        dependencies: dependencies,
        acceptanceCriteria: acceptanceCriteria,
        verificationSteps: verificationSteps,
        expectedArtifacts: expectedArtifacts,
        allowedTools: allowedTools,
        complexity: complexity,
        effortPoints: effortPoints,
        uncertainty: uncertainty,
        risk: risk,
        estimateConfidence: estimateConfidence,
        expectedModelTurns: 2,
        expectedToolCalls: 4,
        maxAttempts: maxAttempts,
        enabled: enabled,
        manual: manual,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'objective': objective,
        'instructions': instructions,
        'phase': phase,
        'parentId': parentId,
        'dependencies': dependencies.toList()..sort(),
        'acceptanceCriteria': acceptanceCriteria,
        'verificationSteps': verificationSteps,
        'expectedArtifacts': expectedArtifacts,
        'allowedTools': allowedTools.toList()..sort(),
        'requiredCapabilities': requiredCapabilities.toList()..sort(),
        'complexity': complexity,
        'effortPoints': effortPoints,
        'uncertainty': uncertainty.name,
        'risk': risk.name,
        'estimateConfidence': estimateConfidence,
        'maxAttempts': maxAttempts,
        'enabled': enabled,
        'manual': manual,
        'hidden': hidden,
        'provenance': provenance.name,
      };

  factory UniversalTask.fromJson(Map<String, dynamic> json) {
    final parentId = json['parentId']?.toString().trim() ?? '';
    return UniversalTask(
      id: json['id']?.toString() ?? newId('task'),
      title: json['title']?.toString() ?? 'Task',
      objective: json['objective']?.toString() ?? '',
      instructions: json['instructions']?.toString() ?? '',
      phase: json['phase']?.toString() ?? 'Implementation',
      parentId: parentId.isEmpty ? null : parentId,
      dependencies: stringList(json['dependencies']).toSet(),
      acceptanceCriteria: stringList(json['acceptanceCriteria']),
      verificationSteps: stringList(json['verificationSteps']),
      expectedArtifacts: stringList(json['expectedArtifacts']),
      allowedTools: stringList(json['allowedTools']).toSet(),
      requiredCapabilities: stringList(json['requiredCapabilities']).toSet(),
      complexity: (int.tryParse(json['complexity']?.toString() ?? '') ?? 3)
          .clamp(1, 10)
          .toInt(),
      effortPoints: int.tryParse(json['effortPoints']?.toString() ?? '') ?? 3,
      uncertainty: PlanUncertainty.values
              .where((item) => item.name == json['uncertainty']?.toString())
              .firstOrNull ??
          PlanUncertainty.medium,
      risk: PlanRisk.values
              .where((item) => item.name == json['risk']?.toString())
              .firstOrNull ??
          PlanRisk.low,
      estimateConfidence:
          (double.tryParse(json['estimateConfidence']?.toString() ?? '') ?? 0.7)
              .clamp(0.0, 1.0)
              .toDouble(),
      maxAttempts: (int.tryParse(json['maxAttempts']?.toString() ?? '') ?? 2)
          .clamp(1, 3)
          .toInt(),
      enabled: json['enabled'] != false,
      manual: json['manual'] == true,
      hidden: json['hidden'] == true,
      provenance: EvidenceProvenance.values
              .where((item) => item.name == json['provenance']?.toString())
              .firstOrNull ??
          EvidenceProvenance.inferred,
    );
  }
}

/// The canonical task graph: one specification, one family, one route,
/// one set of hierarchical tasks.
class UniversalTaskPlan {
  UniversalTaskPlan({
    required this.id,
    required this.specification,
    required this.family,
    required this.route,
    required this.title,
    required this.rationale,
    required this.tasks,
    this.revision = 1,
    this.previousPlanId,
    this.conservative = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  final String id;

  /// The specification this plan answers. Travels *with* the plan: the
  /// hard constraint that produced a task is still attached to the plan
  /// that contains it, all the way to execution and verification.
  final TaskSpecification specification;

  final TaskFamily family;
  final PlanningRoute route;
  final String title;
  final String rationale;
  final List<UniversalTask> tasks;
  final int revision;
  final String? previousPlanId;

  /// True when this plan came from the deterministic conservative planner
  /// after a recoverable planning failure, rather than from a real
  /// decomposition. The UI must say so rather than implying detail that
  /// was never generated.
  final bool conservative;

  final DateTime createdAt;

  List<UniversalTask> get enabledTasks =>
      tasks.where((task) => task.enabled).toList(growable: false);

  /// The tasks worth showing the user. A compact research graph executes
  /// four steps and shows none of them; a substantial software plan shows
  /// all of them. Same plan, different presentation.
  List<UniversalTask> get visibleTasks =>
      enabledTasks.where((task) => !task.hidden).toList(growable: false);

  /// Root tasks (no parent), in plan order.
  List<UniversalTask> get roots =>
      tasks.where((task) => task.parentId == null).toList(growable: false);

  /// Direct children of [id], in plan order.
  List<UniversalTask> childrenOf(String id) =>
      tasks.where((task) => task.parentId == id).toList(growable: false);

  /// Distinct phases in first-appearance order -- the stage grouping the
  /// UI renders and the Runner can reason about.
  List<String> get phases {
    final seen = <String>{};
    final ordered = <String>[];
    for (final task in tasks) {
      if (seen.add(task.phase)) ordered.add(task.phase);
    }
    return List<String>.unmodifiable(ordered);
  }

  int get maxComplexity => enabledTasks.isEmpty
      ? 1
      : enabledTasks
          .map((task) => task.complexity)
          .reduce((a, b) => a > b ? a : b);

  /// Every capability any enabled task requires. The kernel intersects
  /// this with the governed registry; it never treats it as a grant.
  Set<String> get requiredCapabilities => <String>{
        for (final task in enabledTasks) ...task.requiredCapabilities,
      };

  String get contentHash => Sha256.text(
        canonicalJson(<String, dynamic>{
          'specification': specification.contentKey,
          'family': family.name,
          'route': route.name,
          'title': title,
          'tasks': tasks.map((task) => task.toJson()).toList(),
        }),
      );

  List<String> validate() {
    final errors = <String>[];
    if (title.trim().isEmpty) {
      errors.add('A task plan needs a title.');
    }
    if (tasks.isEmpty) {
      errors.add('A task plan must contain at least one task.');
    }
    final ids = tasks.map((task) => task.id).toList(growable: false);
    if (ids.toSet().length != ids.length) {
      errors.add('Task IDs must be unique.');
    }
    final byId = <String, UniversalTask>{
      for (final task in tasks) task.id: task,
    };
    for (final task in tasks) {
      if (task.title.trim().isEmpty || task.instructions.trim().isEmpty) {
        errors.add('${task.id} requires a title and instructions.');
      }
      if (!task.manual && task.acceptanceCriteria.isEmpty) {
        errors.add('${task.id} needs measurable acceptance criteria.');
      }
      if (!task.manual && task.verificationSteps.isEmpty) {
        errors.add('${task.id} needs at least one verification step.');
      }
      final parentId = task.parentId;
      if (parentId != null) {
        if (parentId == task.id) {
          errors.add('${task.id} cannot be its own parent.');
        } else if (!byId.containsKey(parentId)) {
          errors.add('${task.id} references missing parent $parentId.');
        }
      }
      for (final dependency in task.dependencies) {
        final target = byId[dependency];
        if (target == null) {
          errors.add('${task.id} references missing dependency $dependency.');
        } else if (task.enabled && !target.enabled) {
          errors.add('${task.id} depends on disabled task $dependency.');
        }
        if (dependency == task.id) {
          errors.add('${task.id} cannot depend on itself.');
        }
      }
    }
    if (_hasCycle(byId, (task) => task.dependencies)) {
      errors.add('The task plan contains a dependency cycle.');
    }
    if (_hasCycle(
      byId,
      (task) =>
          task.parentId == null ? const <String>{} : <String>{task.parentId!},
    )) {
      errors.add('The task plan contains a parent hierarchy cycle.');
    }
    return errors;
  }

  static bool _hasCycle(
    Map<String, UniversalTask> byId,
    Set<String> Function(UniversalTask task) edges,
  ) {
    final visited = <String>{};
    final active = <String>{};
    bool walk(String id) {
      if (active.contains(id)) return true;
      if (visited.contains(id)) return false;
      final task = byId[id];
      if (task == null) return false;
      active.add(id);
      for (final next in edges(task)) {
        if (byId.containsKey(next) && walk(next)) return true;
      }
      active.remove(id);
      visited.add(id);
      return false;
    }

    return byId.keys.any(walk);
  }

  UniversalTaskPlan copyWith({
    String? id,
    TaskSpecification? specification,
    TaskFamily? family,
    PlanningRoute? route,
    String? title,
    String? rationale,
    List<UniversalTask>? tasks,
    int? revision,
    String? previousPlanId,
    bool? conservative,
    DateTime? createdAt,
  }) =>
      UniversalTaskPlan(
        id: id ?? this.id,
        specification: specification ?? this.specification,
        family: family ?? this.family,
        route: route ?? this.route,
        title: title ?? this.title,
        rationale: rationale ?? this.rationale,
        tasks: tasks ?? this.tasks,
        revision: revision ?? this.revision,
        previousPlanId: previousPlanId ?? this.previousPlanId,
        conservative: conservative ?? this.conservative,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'specification': specification.toJson(),
        'family': family.name,
        'route': route.name,
        'title': title,
        'rationale': rationale,
        'tasks': tasks.map((task) => task.toJson()).toList(),
        'revision': revision,
        'previousPlanId': previousPlanId,
        'conservative': conservative,
        'contentHash': contentHash,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory UniversalTaskPlan.fromJson(Map<String, dynamic> json) =>
      UniversalTaskPlan(
        id: json['id']?.toString() ?? newId('universal_plan'),
        specification:
            TaskSpecification.fromJson(mapValue(json['specification'])),
        family: TaskFamily.values
                .where((item) => item.name == json['family']?.toString())
                .firstOrNull ??
            TaskFamily.software,
        route: PlanningRoute.values
                .where((item) => item.name == json['route']?.toString())
                .firstOrNull ??
            PlanningRoute.graph,
        title: json['title']?.toString() ?? 'Task plan',
        rationale: json['rationale']?.toString() ?? '',
        tasks:
            (json['tasks'] is List ? json['tasks'] as List : const <Object>[])
                .whereType<Map>()
                .map((item) => UniversalTask.fromJson(mapValue(item)))
                .toList(growable: false),
        revision: int.tryParse(json['revision']?.toString() ?? '') ?? 1,
        previousPlanId: json['previousPlanId']?.toString(),
        conservative: json['conservative'] == true,
        createdAt: parseUtc(json['createdAt'], fallback: DateTime.now()),
      );
}
