// The canonical semantic domain boundary between "what the human said"
// and "what Kristin is going to do about it".
//
// Everything upstream of planning -- deterministic parsing of an explicit
// command, model-backed understanding of natural language, a Prompt Studio
// author editing a specification by hand -- produces exactly one of these.
// Everything downstream of it -- the complexity router, every task-family
// planner, the plan compiler -- consumes exactly one of these. No planner
// receives the raw request string as its only input, because flattening a
// structured request back into prose is precisely how a hard constraint
// ("don't touch the database") silently stops being a constraint.
//
// This file deliberately depends only on `domain.dart` primitives: the
// specification is a plain, serializable value type with no runtime,
// repository, model, or Flutter dependency, so it can be constructed in a
// test, round-tripped through JSON, edited in Prompt Studio, and attached
// to a Run without dragging infrastructure along with it.
import '../crypto_utils.dart';
import '../domain.dart';

/// Where a piece of a [TaskSpecification] came from, so a later decision
/// can tell a fact from a guess.
///
/// Kristin's product rule is that important decisions must not silently
/// promote an assumption into a fact. Provenance is what makes that
/// checkable rather than aspirational: [assumed] and [inferred] claims can
/// be surfaced for confirmation, [userStated] and [observed] claims cannot
/// be invented by a model, and [unknown] is an honest answer.
///
/// This is deliberately a small, extensible vocabulary rather than a
/// probabilistic world-state graph -- the graph is follow-up work, the
/// distinction is not.
enum EvidenceProvenance {
  /// The user said it, in this request or an earlier accepted turn.
  userStated,

  /// Kristin observed it from a governed capability: a file that exists,
  /// a diagnostic that ran, a search result that was retrieved.
  observed,

  /// Deterministically derived from something [userStated] or [observed]
  /// (for example: the capability implied by an explicit slash command).
  inferred,

  /// Currently believed but not established -- typically a model's
  /// reading of an ambiguous request. Never treat as fact.
  assumed,

  /// Explicitly not known. Present so that "we don't know" is
  /// representable instead of being encoded as a confident default.
  unknown,
}

/// One provenance-tagged statement inside a [TaskSpecification].
///
/// Constraints, criteria, and assumptions are claims, not strings: the
/// same sentence means something different when the user stated it than
/// when a model guessed it, and the planner is entitled to know which.
class SpecificationClaim {
  const SpecificationClaim({
    required this.statement,
    required this.provenance,
    this.source = '',
  });

  /// A [userStated] claim -- the strongest kind, and the only kind that
  /// may be created directly from the user's own words.
  const SpecificationClaim.stated(String statement, {String source = ''})
      : this(
          statement: statement,
          provenance: EvidenceProvenance.userStated,
          source: source,
        );

  /// A claim deterministic code derived from stated or observed material.
  const SpecificationClaim.inferred(String statement, {String source = ''})
      : this(
          statement: statement,
          provenance: EvidenceProvenance.inferred,
          source: source,
        );

  /// A claim a model proposed. Never authoritative on its own.
  const SpecificationClaim.assumed(String statement, {String source = ''})
      : this(
          statement: statement,
          provenance: EvidenceProvenance.assumed,
          source: source,
        );

  final String statement;
  final EvidenceProvenance provenance;

  /// Free-form attribution: which capability observed it, which model
  /// proposed it, which earlier turn stated it. Never used for authority.
  final String source;

  /// True when this claim may be relied on without further confirmation.
  /// A model's reading of an ambiguous sentence never qualifies.
  bool get isEstablished =>
      provenance == EvidenceProvenance.userStated ||
      provenance == EvidenceProvenance.observed;

  SpecificationClaim copyWith({
    String? statement,
    EvidenceProvenance? provenance,
    String? source,
  }) =>
      SpecificationClaim(
        statement: statement ?? this.statement,
        provenance: provenance ?? this.provenance,
        source: source ?? this.source,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'statement': statement,
        'provenance': provenance.name,
        if (source.isNotEmpty) 'source': source,
      };

  factory SpecificationClaim.fromJson(Map<String, dynamic> json) =>
      SpecificationClaim(
        statement: json['statement']?.toString() ?? '',
        provenance: EvidenceProvenance.values
                .where((item) => item.name == json['provenance']?.toString())
                .firstOrNull ??
            EvidenceProvenance.unknown,
        source: json['source']?.toString() ?? '',
      );

  @override
  String toString() => '$statement (${provenance.name})';
}

/// An ambiguity that materially affects the plan and has not been
/// resolved yet.
///
/// Kept structured rather than folded into the objective prose so the
/// router can decide whether to ask, and so Chat can render a real
/// clarification instead of guessing and hoping.
class UnresolvedQuestion {
  const UnresolvedQuestion({
    required this.question,
    this.options = const <String>[],
    this.blocking = false,
  });

  final String question;
  final List<String> options;

  /// True when planning cannot proceed safely without an answer. A
  /// non-blocking question is recorded, planned around with a stated
  /// assumption, and surfaced -- it never silently disappears.
  final bool blocking;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'question': question,
        if (options.isNotEmpty) 'options': options,
        'blocking': blocking,
      };

  factory UnresolvedQuestion.fromJson(Map<String, dynamic> json) =>
      UnresolvedQuestion(
        question: json['question']?.toString() ?? '',
        options: stringList(json['options']),
        blocking: json['blocking'] == true,
      );
}

/// A thing the request is about: a project, a file path, a model, a URL,
/// a search subject.
///
/// [kind] is intentionally an open string rather than an enum -- new task
/// families (Browser, later) introduce new reference kinds, and the kernel
/// must not need a new enum value to carry one. What is *not* open is
/// authority: a reference is a noun, never a permission. Resolving whether
/// Kristin may act on a target is [TaskAuthorityRequirement]'s job, and
/// ultimately the authority layer's.
class TaskTargetRef {
  const TaskTargetRef({
    required this.kind,
    required this.value,
    this.displayName = '',
    this.provenance = EvidenceProvenance.userStated,
    this.resolved = false,
  });

  final String kind;
  final String value;
  final String displayName;
  final EvidenceProvenance provenance;

  /// True once deterministic code has confirmed this target actually
  /// exists in the current context. A model asserting a target exists
  /// never sets this.
  final bool resolved;

  TaskTargetRef copyWith({
    String? kind,
    String? value,
    String? displayName,
    EvidenceProvenance? provenance,
    bool? resolved,
  }) =>
      TaskTargetRef(
        kind: kind ?? this.kind,
        value: value ?? this.value,
        displayName: displayName ?? this.displayName,
        provenance: provenance ?? this.provenance,
        resolved: resolved ?? this.resolved,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind,
        'value': value,
        if (displayName.isNotEmpty) 'displayName': displayName,
        'provenance': provenance.name,
        'resolved': resolved,
      };

  factory TaskTargetRef.fromJson(Map<String, dynamic> json) => TaskTargetRef(
        kind: json['kind']?.toString() ?? 'unknown',
        value: json['value']?.toString() ?? '',
        displayName: json['displayName']?.toString() ?? '',
        provenance: EvidenceProvenance.values
                .where((item) => item.name == json['provenance']?.toString())
                .firstOrNull ??
            EvidenceProvenance.unknown,
        resolved: json['resolved'] == true,
      );

  @override
  String toString() => '$kind:$value';
}

/// How a [TaskSpecification] came to exist.
enum TaskSpecificationSource {
  /// Built entirely by deterministic code from an explicit command,
  /// a bare target mention, or another unambiguous input. No model ran.
  deterministic,

  /// A model read the natural language and proposed structure, which
  /// deterministic code then validated. See `task_understanding.dart`.
  modelUnderstanding,

  /// A human authored or edited it directly (Prompt Studio).
  authored,
}

/// The canonical, semantically structured statement of what the user
/// wants -- the single input every planner in Kristin accepts.
///
/// The distinctions this type preserves are the whole point of it:
///
///   objective         what the user wants achieved
///   hardConstraints   must never be violated, at any cost
///   preferences       traded off when they conflict with the objective
///   successCriteria   what establishes that this is actually done
///   assumptions       currently believed, not guaranteed
///   unresolvedQuestions  ambiguity that still matters
///   prohibitedEffects effects that must not happen even if a plan wants them
///
/// "Make this app faster but don't change the database and keep the UI
/// simple" is three different kinds of statement, and a planner that
/// receives them as one string has already lost the constraint.
class TaskSpecification {
  TaskSpecification({
    required this.id,
    required this.originalRequest,
    required this.objective,
    this.subObjectives = const <String>[],
    this.targetRefs = const <TaskTargetRef>[],
    this.hardConstraints = const <SpecificationClaim>[],
    this.preferences = const <SpecificationClaim>[],
    this.successCriteria = const <SpecificationClaim>[],
    this.assumptions = const <SpecificationClaim>[],
    this.unresolvedQuestions = const <UnresolvedQuestion>[],
    this.requestedMethod = '',
    this.prohibitedEffects = const <String>[],
    this.contextRefs = const <String>[],
    this.capabilityHints = const <String>[],
    this.source = TaskSpecificationSource.deterministic,
    this.confidence = 1.0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().toUtc();

  final String id;

  /// The user's exact words. Retained verbatim for evidence and for
  /// display -- never re-parsed as a substitute for the fields below.
  final String originalRequest;

  /// What the user wants achieved, in one outcome-shaped sentence.
  final String objective;

  /// Independently satisfiable parts of the objective ("current Nha Trang
  /// weather", "current New York time"). Drives compact decomposition.
  final List<String> subObjectives;

  final List<TaskTargetRef> targetRefs;

  /// Inviolable. A plan that violates one of these is wrong, not
  /// merely suboptimal.
  final List<SpecificationClaim> hardConstraints;

  /// Desirable. May be traded off against the objective, and the
  /// trade-off should be visible when it happens.
  final List<SpecificationClaim> preferences;

  final List<SpecificationClaim> successCriteria;
  final List<SpecificationClaim> assumptions;
  final List<UnresolvedQuestion> unresolvedQuestions;

  /// An explicitly requested approach ("use SQLite", "with Flutter web").
  /// Distinct from a preference: the user named the method, not the taste.
  final String requestedMethod;

  /// Effects that must not occur. Expressed as effects rather than as
  /// prose so the authority layer can reason about them.
  final List<String> prohibitedEffects;

  /// Opaque references to supporting context (knowledge entries, prior
  /// run ids, conversation ids).
  final List<String> contextRefs;

  /// Capability ids Understanding believes are relevant. A *hint*: the
  /// kernel intersects these with the governed registry and never treats
  /// a model-proposed capability as granted.
  final List<String> capabilityHints;

  final TaskSpecificationSource source;

  /// Understanding's own confidence, in [0,1]. Deterministic
  /// specifications are 1.0 because nothing was guessed.
  final double confidence;

  final DateTime createdAt;

  /// True when a model's reading contributed to this specification, and
  /// therefore when the UI may truthfully say "I understood ..." rather
  /// than the weaker, honest "I interpreted this as ...".
  bool get hasSemanticUnderstanding =>
      source == TaskSpecificationSource.modelUnderstanding;

  /// Questions that must be answered before planning can safely proceed.
  List<UnresolvedQuestion> get blockingQuestions => unresolvedQuestions
      .where((question) => question.blocking)
      .toList(growable: false);

  /// A stable content identity for this specification, independent of
  /// [id] and [createdAt]. Two understandings of the same request with
  /// the same structure share a key -- which is what lets reconciliation
  /// recognize "the same work" across a replan.
  String get contentKey => Sha256.text(
        canonicalJson(<String, dynamic>{
          'objective': objective.trim().toLowerCase(),
          'subObjectives': subObjectives
              .map((item) => item.trim().toLowerCase())
              .toList(growable: false)
            ..sort(),
          'hardConstraints': hardConstraints
              .map((item) => item.statement.trim().toLowerCase())
              .toList(growable: false)
            ..sort(),
          'targets': targetRefs.map((item) => item.toString()).toList()..sort(),
          'requestedMethod': requestedMethod.trim().toLowerCase(),
        }),
      );

  List<String> validate() {
    final errors = <String>[];
    if (id.trim().isEmpty) {
      errors.add('A task specification requires an id.');
    }
    if (originalRequest.trim().isEmpty) {
      errors.add('A task specification must retain the original request.');
    }
    if (objective.trim().length < 3) {
      errors.add('A task specification requires a stated objective.');
    }
    if (confidence < 0 || confidence > 1) {
      errors.add('Confidence must be between 0 and 1.');
    }
    for (final constraint in hardConstraints) {
      if (constraint.statement.trim().isEmpty) {
        errors.add('Hard constraints must be non-empty statements.');
      }
      // A hard constraint is inviolable, so it may never rest on a guess:
      // if a model merely assumed it, it belongs in preferences or in an
      // unresolved question, not in the set the planner may not violate.
      if (constraint.provenance == EvidenceProvenance.assumed ||
          constraint.provenance == EvidenceProvenance.unknown) {
        errors.add(
          'Hard constraint "${constraint.statement}" is not established '
          '(${constraint.provenance.name}); it cannot be treated as '
          'inviolable.',
        );
      }
    }
    for (final target in targetRefs) {
      if (target.value.trim().isEmpty) {
        errors.add('Every target reference requires a value.');
      }
    }
    for (final question in unresolvedQuestions) {
      if (question.question.trim().isEmpty) {
        errors.add('Unresolved questions must be non-empty.');
      }
    }
    return errors;
  }

  TaskSpecification copyWith({
    String? id,
    String? originalRequest,
    String? objective,
    List<String>? subObjectives,
    List<TaskTargetRef>? targetRefs,
    List<SpecificationClaim>? hardConstraints,
    List<SpecificationClaim>? preferences,
    List<SpecificationClaim>? successCriteria,
    List<SpecificationClaim>? assumptions,
    List<UnresolvedQuestion>? unresolvedQuestions,
    String? requestedMethod,
    List<String>? prohibitedEffects,
    List<String>? contextRefs,
    List<String>? capabilityHints,
    TaskSpecificationSource? source,
    double? confidence,
    DateTime? createdAt,
  }) =>
      TaskSpecification(
        id: id ?? this.id,
        originalRequest: originalRequest ?? this.originalRequest,
        objective: objective ?? this.objective,
        subObjectives: subObjectives ?? this.subObjectives,
        targetRefs: targetRefs ?? this.targetRefs,
        hardConstraints: hardConstraints ?? this.hardConstraints,
        preferences: preferences ?? this.preferences,
        successCriteria: successCriteria ?? this.successCriteria,
        assumptions: assumptions ?? this.assumptions,
        unresolvedQuestions: unresolvedQuestions ?? this.unresolvedQuestions,
        requestedMethod: requestedMethod ?? this.requestedMethod,
        prohibitedEffects: prohibitedEffects ?? this.prohibitedEffects,
        contextRefs: contextRefs ?? this.contextRefs,
        capabilityHints: capabilityHints ?? this.capabilityHints,
        source: source ?? this.source,
        confidence: confidence ?? this.confidence,
        createdAt: createdAt ?? this.createdAt,
      );

  /// Renders the specification for a planning model, preserving the
  /// semantic sections rather than collapsing them into prose.
  ///
  /// This is the only sanctioned way to hand a specification to a model:
  /// it keeps hard constraints labelled as hard constraints all the way
  /// into the prompt, which is what stops a planner from quietly
  /// optimizing one away.
  String renderForPlanner() {
    String block(String heading, Iterable<String> lines) {
      final items = lines
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
      if (items.isEmpty) return '';
      return '$heading\n${items.map((item) => '- $item').join('\n')}';
    }

    final sections = <String>[
      'OBJECTIVE\n${objective.trim()}',
      block('SUB-OBJECTIVES', subObjectives),
      block(
        'HARD CONSTRAINTS (never violate these)',
        hardConstraints.map((item) => item.statement),
      ),
      block(
        'PREFERENCES (trade off only when they conflict with the objective)',
        preferences.map((item) => item.statement),
      ),
      block(
        'SUCCESS CRITERIA',
        successCriteria.map((item) => item.statement),
      ),
      block(
        'ASSUMPTIONS (believed, not established)',
        assumptions.map((item) => item.statement),
      ),
      block(
        'OPEN QUESTIONS (do not silently answer these)',
        unresolvedQuestions.map((item) => item.question),
      ),
      block('PROHIBITED EFFECTS', prohibitedEffects),
      if (requestedMethod.trim().isNotEmpty)
        'REQUESTED METHOD\n${requestedMethod.trim()}',
      block('TARGETS', targetRefs.map((item) => '${item.kind}: ${item.value}')),
      'ORIGINAL REQUEST\n${originalRequest.trim()}',
    ];
    return sections.where((section) => section.isNotEmpty).join('\n\n');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'originalRequest': originalRequest,
        'objective': objective,
        'subObjectives': subObjectives,
        'targetRefs': targetRefs.map((item) => item.toJson()).toList(),
        'hardConstraints':
            hardConstraints.map((item) => item.toJson()).toList(),
        'preferences': preferences.map((item) => item.toJson()).toList(),
        'successCriteria':
            successCriteria.map((item) => item.toJson()).toList(),
        'assumptions': assumptions.map((item) => item.toJson()).toList(),
        'unresolvedQuestions':
            unresolvedQuestions.map((item) => item.toJson()).toList(),
        'requestedMethod': requestedMethod,
        'prohibitedEffects': prohibitedEffects,
        'contextRefs': contextRefs,
        'capabilityHints': capabilityHints,
        'source': source.name,
        'confidence': confidence,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  factory TaskSpecification.fromJson(Map<String, dynamic> json) {
    List<SpecificationClaim> claims(Object? raw) =>
        (raw is List ? raw : const <Object>[])
            .whereType<Map>()
            .map((item) => SpecificationClaim.fromJson(mapValue(item)))
            .toList(growable: false);
    return TaskSpecification(
      id: json['id']?.toString() ?? newId('task_spec'),
      originalRequest: json['originalRequest']?.toString() ?? '',
      objective: json['objective']?.toString() ?? '',
      subObjectives: stringList(json['subObjectives']),
      targetRefs: (json['targetRefs'] is List
              ? json['targetRefs'] as List
              : const <Object>[])
          .whereType<Map>()
          .map((item) => TaskTargetRef.fromJson(mapValue(item)))
          .toList(growable: false),
      hardConstraints: claims(json['hardConstraints']),
      preferences: claims(json['preferences']),
      successCriteria: claims(json['successCriteria']),
      assumptions: claims(json['assumptions']),
      unresolvedQuestions: (json['unresolvedQuestions'] is List
              ? json['unresolvedQuestions'] as List
              : const <Object>[])
          .whereType<Map>()
          .map((item) => UnresolvedQuestion.fromJson(mapValue(item)))
          .toList(growable: false),
      requestedMethod: json['requestedMethod']?.toString() ?? '',
      prohibitedEffects: stringList(json['prohibitedEffects']),
      contextRefs: stringList(json['contextRefs']),
      capabilityHints: stringList(json['capabilityHints']),
      source: TaskSpecificationSource.values
              .where((item) => item.name == json['source']?.toString())
              .firstOrNull ??
          TaskSpecificationSource.deterministic,
      confidence: (double.tryParse(json['confidence']?.toString() ?? '') ?? 1.0)
          .clamp(0.0, 1.0)
          .toDouble(),
      createdAt: parseUtc(json['createdAt'], fallback: DateTime.now()),
    );
  }
}
