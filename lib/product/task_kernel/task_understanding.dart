// Understanding: turning what a human said into a TaskSpecification.
//
// The product rule this file implements:
//
//     THE MODEL UNDERSTANDS THE HUMAN
//     DETERMINISTIC CODE VALIDATES THE INTERPRETATION
//
// Both halves matter. Without the first, "understanding" is keyword
// matching wearing a costume, and Chat can only honestly say "I
// interpreted this as". Without the second, a model's reading becomes
// authority -- and a sentence a model invented would decide what Kristin
// is allowed to do.
//
// So this is a hybrid:
//
//   /run @test8B          deterministic. The user already said exactly
//                         what they meant; calling a model to rediscover
//                         capability=project.run, target=test8B would be
//                         slower, less reliable, and no more correct.
//
//   @test8B               deterministic. A bare target is context, not a
//                         mutation request.
//
//   "hello"               deterministic. Conversation.
//
//   natural substantial   model, through a constrained structured
//   request               contract, then validated field by field here.
//
// Nothing the model returns is trusted as authority. It proposes
// structure; this file checks that structure against what actually
// exists.
import 'dart:async';
import 'dart:convert';

import '../chat_control_plane.dart';
import '../domain.dart';
import '../models_research.dart';
import '../storage_security.dart';
import 'planning_failures.dart';
import 'task_specification.dart';

/// How a [TaskSpecification] was produced, for honest UI wording.
enum UnderstandingPath {
  /// Deterministic parse. The UI must say "I interpreted this as ..."
  /// -- regex and command parsing are not semantic understanding.
  deterministic,

  /// A model read the request and deterministic code validated its
  /// reading. The UI may truthfully say "I understood ...".
  model,
}

/// The result of understanding one request.
class UnderstandingOutcome {
  const UnderstandingOutcome({
    required this.specification,
    required this.path,
    this.rejections = const <String>[],
    this.capabilityHints = const <String>[],
  });

  final TaskSpecification specification;
  final UnderstandingPath path;

  /// Everything the validator refused from a model proposal: invented
  /// targets, unknown capabilities, attempts to assert authority. Kept
  /// rather than silently dropped, so the refusal is auditable.
  final List<String> rejections;

  /// Model-proposed capability ids that survived validation against the
  /// governed registry.
  final List<String> capabilityHints;

  /// True when the UI may truthfully claim semantic understanding.
  bool get isSemantic => path == UnderstandingPath.model;
}

/// Deterministic understanding: builds a specification from an already
/// unambiguous input without invoking any model.
///
/// This exists so the kernel is universal without being wasteful. An
/// explicit command has already told us the capability and the target;
/// there is nothing left to understand.
class DeterministicUnderstanding {
  const DeterministicUnderstanding();

  /// Builds a specification from a compiled Chat decision.
  ///
  /// Every claim it produces is [EvidenceProvenance.userStated] (the
  /// user's own words) or [EvidenceProvenance.inferred] (derived by this
  /// deterministic code) -- never `assumed`, because nothing was guessed.
  UnderstandingOutcome understand(
    ChatInteractionDecision decision, {
    String? specificationId,
  }) {
    final capability = decision.capability;
    final request = decision.parsed.originalText.trim();
    final targets = <TaskTargetRef>[
      for (final target in decision.targets)
        TaskTargetRef(
          kind: target.type.name,
          value: target.id,
          displayName: target.displayName,
          // The target resolver already matched this against the real
          // known-target list, so it is observed, not asserted.
          provenance: EvidenceProvenance.observed,
          resolved: true,
        ),
    ];
    final questions = <UnresolvedQuestion>[
      for (final mention in decision.unresolvedMentions)
        UnresolvedQuestion(
          question: 'Which target does "@$mention" refer to?',
          blocking: true,
        ),
      if (decision.ambiguous && decision.unresolvedMentions.isEmpty)
        UnresolvedQuestion(
          question: 'Confirm this is the action you meant.',
          blocking: false,
        ),
    ];
    final specification = TaskSpecification(
      id: specificationId ?? newId('task_spec'),
      originalRequest: request,
      objective: decision.interpretedGoal.trim().isEmpty
          ? request
          : decision.interpretedGoal.trim(),
      targetRefs: targets,
      successCriteria: <SpecificationClaim>[
        if (capability != null)
          SpecificationClaim.inferred(
            '${capability.displayName} completes with objective evidence.',
            source: capability.id,
          ),
      ],
      unresolvedQuestions: questions,
      capabilityHints: <String>[if (capability != null) capability.id],
      source: TaskSpecificationSource.deterministic,
      confidence: 1.0,
    );
    return UnderstandingOutcome(
      specification: specification,
      path: UnderstandingPath.deterministic,
      capabilityHints: specification.capabilityHints,
    );
  }
}

/// What deterministic code checks a model's proposal against.
///
/// Understanding may only refer to things that actually exist. This is
/// the context that says what "actually exists" means right now.
class UnderstandingContext {
  const UnderstandingContext({
    this.availableCapabilities = const <KristinCapability>[],
    this.knownTargets = const <ChatTarget>[],
    this.hasSelectedProject = false,
  });

  final List<KristinCapability> availableCapabilities;
  final List<ChatTarget> knownTargets;
  final bool hasSelectedProject;

  KristinCapability? capabilityById(String id) {
    for (final capability in availableCapabilities) {
      if (capability.id == id) return capability;
    }
    return null;
  }

  ChatTarget? targetByReference(String reference) {
    for (final target in knownTargets) {
      if (target.matches(reference) || target.id == reference) return target;
    }
    return null;
  }

  /// A compact, factual description of what Kristin can currently do,
  /// for the understanding prompt. The model is told what exists rather
  /// than left to invent it -- which is what makes the validator's job
  /// a check rather than a guessing game.
  String describeCapabilities() {
    if (availableCapabilities.isEmpty) return 'none';
    return availableCapabilities
        .map(
          (capability) => '- ${capability.id}: ${capability.description} '
              '(accepts: ${capability.acceptedTargetTypes.isEmpty ? 'no targets' : capability.acceptedTargetTypes.map((type) => type.name).join('/')})',
        )
        .join('\n');
  }

  String describeTargets() {
    if (knownTargets.isEmpty) return 'none';
    return knownTargets
        .map((target) => '- ${target.type.name}: ${target.id} '
            '(${target.displayName})')
        .join('\n');
  }
}

/// Model-backed semantic understanding for natural-language requests.
///
/// Calls the selected model through a constrained structured contract,
/// then hands the result to [UnderstandingValidator]. The model never
/// sees a path where its output becomes authority.
class ModelBackedUnderstanding {
  const ModelBackedUnderstanding({
    required this.generate,
    this.validator = const UnderstandingValidator(),
  });

  /// The model call. Injected rather than taken as a ModelRegistry so
  /// this stays a plain, deterministically-testable unit.
  final Future<ModelGenerationResult> Function(ModelGenerationRequest request)
      generate;

  final UnderstandingValidator validator;

  static const String _system = '''
You read a user's request to a local AI agent and return its structure.
You do NOT decide what the agent is allowed to do, and you do NOT grant
permission for anything. You only describe what the user asked for.

Return exactly one JSON object and no Markdown:
{
  "objective": "one sentence: what the user wants achieved",
  "subObjectives": ["independently satisfiable parts, if any"],
  "capabilityHints": ["capability ids from the AVAILABLE CAPABILITIES list only"],
  "targets": ["target ids from the KNOWN TARGETS list only"],
  "hardConstraints": ["things that must never be violated"],
  "preferences": ["things that are desirable but tradeable"],
  "successCriteria": ["what would establish this is done"],
  "assumptions": ["what you are assuming that the user did not state"],
  "unresolvedQuestions": ["ambiguities that materially change the work"],
  "requestedMethod": "an approach the user explicitly named, or empty",
  "prohibitedEffects": ["effects the user forbade"],
  "confidence": 0.0
}

Rules:
- A HARD CONSTRAINT is something the user actually stated must not be
  violated ("don't change the database"). Never invent one. If you are
  merely guessing, put it in assumptions instead.
- A PREFERENCE is tradeable ("keep the UI simple").
- Only use capability ids and target ids that appear in the lists below.
  If the request needs something not listed, say so in
  unresolvedQuestions. Never invent an id.
- Never include permissions, grants, authority, or approval in any field.
- confidence is your own honest confidence in this reading, 0.0 to 1.0.
''';

  Future<UnderstandingOutcome> understand({
    required String request,
    required ModelIdentity model,
    required UnderstandingContext context,
    String? specificationId,
    Future<void>? cancellation,
    bool Function()? isCancelled,
  }) async {
    final normalized = request.trim();
    if (normalized.isEmpty) {
      throw ProductException(
        'request_empty',
        'There is nothing to understand in an empty request.',
      );
    }
    final user = '''
USER REQUEST
$normalized

AVAILABLE CAPABILITIES
${context.describeCapabilities()}

KNOWN TARGETS
${context.describeTargets()}

A project is ${context.hasSelectedProject ? 'currently selected' : 'NOT currently selected'}.
''';
    final generation = await generate(
      ModelGenerationRequest(
        identity: model,
        systemPrompt: _system,
        userPrompt: user,
        commandId: newId('understanding'),
        temperature: 0.0,
        maxOutputTokens: 1536,
        cancellation: cancellation,
        isCancelled: isCancelled,
      ),
    );
    final proposal = _decode(generation.text);
    return validator.validate(
      proposal: proposal,
      request: normalized,
      context: context,
      specificationId: specificationId,
    );
  }

  Map<String, dynamic> _decode(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw ProductException(
        'model_response_invalid',
        'The model did not return a JSON understanding object.',
      );
    }
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is! Map) {
        throw ProductException(
          'model_response_invalid',
          'The model understanding response was not a JSON object.',
        );
      }
      return mapValue(decoded);
    } on FormatException catch (error) {
      throw ProductException(
        'model_response_invalid',
        'The model understanding response was not valid JSON.',
        details: <String, dynamic>{'error': error.message},
      );
    }
  }
}

/// The deterministic half of understanding.
///
/// Everything a model proposed is checked here before it can influence a
/// plan:
///
///   * every capability id must exist in the governed registry;
///   * every target must exist in the known-target list;
///   * a capability must actually accept the type of target named;
///   * no field may assert authority, permission, or approval;
///   * a "hard constraint" the model invented is demoted, because a
///     constraint the user never stated is an assumption.
///
/// Refusals are recorded in [UnderstandingOutcome.rejections] rather than
/// dropped, so what the model tried to do stays visible.
class UnderstandingValidator {
  const UnderstandingValidator();

  /// Words that indicate an attempt to assert authority rather than to
  /// describe a request. A model saying "grant project write permission"
  /// is not understanding, it is asking for power.
  static final RegExp _authorityLanguage = RegExp(
    r'\b(?:grant(?:ed|s|ing)?'
    r'|authoriz(?:e|es|ed|ation)'
    r'|permission(?:s)?\s+(?:is\s+|are\s+|was\s+|were\s+|been\s+)*(?:granted|approved|given|allowed)'
    r'|approve[sd]?\s+(?:the\s+)?(?:permission|scope|grant)'
    r'|bypass(?:es|ed)?\s+(?:permission|authority|approval)'
    r'|elevate[sd]?\s+privilege'
    r'|sudo|root\s+access|full\s+access|unrestricted\s+access)\b',
    caseSensitive: false,
  );

  UnderstandingOutcome validate({
    required Map<String, dynamic> proposal,
    required String request,
    required UnderstandingContext context,
    String? specificationId,
  }) {
    final rejections = <String>[];

    String cleanText(Object? value) => value?.toString().trim() ?? '';

    List<String> cleanList(Object? value, String field) {
      final result = <String>[];
      for (final item in stringList(value)) {
        final text = item.trim();
        if (text.isEmpty) continue;
        if (_authorityLanguage.hasMatch(text)) {
          // MODEL UNDERSTANDING != AUTHORIZATION. A proposal that tries
          // to hand itself power is refused outright, not sanitized into
          // something weaker and kept.
          rejections.add('$field: refused authority assertion "$text".');
          continue;
        }
        result.add(text);
      }
      return List<String>.unmodifiable(result);
    }

    final objective = cleanText(proposal['objective']);
    if (objective.isEmpty) {
      throw ProductException(
        'model_response_invalid',
        'The model understanding response had no objective.',
      );
    }
    if (_authorityLanguage.hasMatch(objective)) {
      throw ProductException(
        'model_response_invalid',
        'The model understanding response asserted authority in its '
            'objective rather than describing the request.',
      );
    }

    // Capabilities: a model-proposed capability is a hint, and it only
    // survives if the governed registry actually has it.
    final capabilityHints = <String>[];
    for (final id
        in cleanList(proposal['capabilityHints'], 'capabilityHints')) {
      final capability = context.capabilityById(id);
      if (capability == null) {
        rejections.add('capabilityHints: unknown capability "$id" ignored.');
        continue;
      }
      capabilityHints.add(capability.id);
    }

    // Targets: a model asserting a target exists never makes it exist.
    final targets = <TaskTargetRef>[];
    for (final reference in cleanList(proposal['targets'], 'targets')) {
      final target = context.targetByReference(reference);
      if (target == null) {
        rejections.add('targets: unknown target "$reference" ignored.');
        continue;
      }
      targets.add(
        TaskTargetRef(
          kind: target.type.name,
          value: target.id,
          displayName: target.displayName,
          provenance: EvidenceProvenance.observed,
          resolved: true,
        ),
      );
    }

    // A capability must be able to operate on the target it was paired
    // with. "Run this model" is not a thing, however confidently phrased.
    final usableCapabilities = <String>[];
    for (final id in capabilityHints) {
      final capability = context.capabilityById(id);
      if (capability == null) continue;
      if (targets.isEmpty) {
        if (!capability.availableWithoutTarget) {
          rejections.add(
            'capabilityHints: "$id" requires a target and none was '
            'resolved.',
          );
          continue;
        }
        usableCapabilities.add(id);
        continue;
      }
      final incompatible = targets
          .where(
            (target) => !capability.acceptedTargetTypes.any(
              (type) => type.name == target.kind,
            ),
          )
          .toList(growable: false);
      if (incompatible.length == targets.length) {
        rejections.add(
          'capabilityHints: "$id" cannot operate on '
          '${incompatible.map((target) => target.kind).toSet().join('/')}.',
        );
        continue;
      }
      usableCapabilities.add(id);
    }

    // Constraints. The critical demotion: a model may not manufacture an
    // inviolable rule. Only a constraint traceable to the user's own
    // words stays hard; anything else becomes an explicit assumption,
    // which is honest and still visible to the planner.
    final hardConstraints = <SpecificationClaim>[];
    final assumptions = <SpecificationClaim>[
      for (final item in cleanList(proposal['assumptions'], 'assumptions'))
        SpecificationClaim.assumed(item, source: 'understanding'),
    ];
    for (final item
        in cleanList(proposal['hardConstraints'], 'hardConstraints')) {
      if (_isTraceableToRequest(item, request)) {
        hardConstraints.add(
          SpecificationClaim.stated(item, source: 'understanding'),
        );
      } else {
        rejections.add(
          'hardConstraints: "$item" is not traceable to the request; '
          'recorded as an assumption instead.',
        );
        assumptions.add(
          SpecificationClaim.assumed(item, source: 'understanding'),
        );
      }
    }

    final preferences = <SpecificationClaim>[
      for (final item in cleanList(proposal['preferences'], 'preferences'))
        SpecificationClaim(
          statement: item,
          provenance: _isTraceableToRequest(item, request)
              ? EvidenceProvenance.userStated
              : EvidenceProvenance.inferred,
          source: 'understanding',
        ),
    ];
    final successCriteria = <SpecificationClaim>[
      for (final item
          in cleanList(proposal['successCriteria'], 'successCriteria'))
        SpecificationClaim.inferred(item, source: 'understanding'),
    ];
    final questions = <UnresolvedQuestion>[
      for (final item in cleanList(
        proposal['unresolvedQuestions'],
        'unresolvedQuestions',
      ))
        UnresolvedQuestion(question: item),
    ];

    final confidence =
        (double.tryParse(proposal['confidence']?.toString() ?? '') ?? 0.5)
            .clamp(0.0, 1.0)
            .toDouble();

    final specification = TaskSpecification(
      id: specificationId ?? newId('task_spec'),
      originalRequest: request,
      objective: objective,
      subObjectives: cleanList(proposal['subObjectives'], 'subObjectives'),
      targetRefs: targets,
      hardConstraints: hardConstraints,
      preferences: preferences,
      successCriteria: successCriteria,
      assumptions: assumptions,
      unresolvedQuestions: questions,
      requestedMethod: cleanText(proposal['requestedMethod']),
      prohibitedEffects:
          cleanList(proposal['prohibitedEffects'], 'prohibitedEffects'),
      capabilityHints: usableCapabilities,
      source: TaskSpecificationSource.modelUnderstanding,
      confidence: confidence,
    );
    final errors = specification.validate();
    if (errors.isNotEmpty) {
      throw ProductException(
        'model_response_invalid',
        'The validated understanding was not a usable specification: '
            '${errors.join(' ')}',
      );
    }
    return UnderstandingOutcome(
      specification: specification,
      path: UnderstandingPath.model,
      rejections: List<String>.unmodifiable(rejections),
      capabilityHints: usableCapabilities,
    );
  }

  /// Whether a claimed constraint is actually grounded in what the user
  /// wrote.
  ///
  /// Deliberately a lexical overlap check rather than another model call:
  /// the whole point of this layer is that it is deterministic and
  /// cheap to audit. It is a floor, not a semantic judge -- a model that
  /// paraphrases the user's own words keeps its constraint, and a model
  /// that invents a rule out of nothing does not.
  bool _isTraceableToRequest(String claim, String request) {
    final haystack = request.toLowerCase();
    final words = claim
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((word) => word.length > 3 && !_stopWords.contains(word))
        .toList(growable: false);
    if (words.isEmpty) return false;
    final matched = words.where(haystack.contains).length;
    return matched * 2 >= words.length;
  }

  static const Set<String> _stopWords = <String>{
    'must',
    'should',
    'never',
    'always',
    'this',
    'that',
    'with',
    'without',
    'from',
    'into',
    'them',
    'they',
    'have',
    'been',
    'will',
    'does',
    'when',
    'than',
    'then',
    'only',
    'also',
    'user',
    'users',
    'thing',
    'things',
  };
}

/// Chooses between the deterministic and model-backed paths, and turns
/// any understanding failure into a typed [PlanningFailure].
class UnderstandingService {
  const UnderstandingService({
    this.deterministic = const DeterministicUnderstanding(),
    this.model,
  });

  final DeterministicUnderstanding deterministic;

  /// Null when no model is available; understanding then stays
  /// deterministic and Chat keeps saying "I interpreted this as".
  final ModelBackedUnderstanding? model;

  /// True when a request warrants real semantic understanding.
  ///
  /// An explicit command, a bare target mention, and an informational
  /// message are all already unambiguous -- spending a model call to
  /// rediscover what the user literally typed adds latency and a failure
  /// mode without adding correctness.
  bool warrantsModelUnderstanding(ChatInteractionDecision decision) {
    if (model == null) return false;
    if (decision.parsed.hasExplicitCommand) return false;
    if (decision.kind == ChatInteractionKind.reference) return false;
    if (decision.kind == ChatInteractionKind.informational) return false;
    final capability = decision.capability;
    if (capability == null) return false;
    if (capability.understandingPolicy == ChatUnderstandingPolicy.never) {
      return false;
    }
    return true;
  }

  Future<UnderstandingOutcome> understand({
    required ChatInteractionDecision decision,
    required UnderstandingContext context,
    ModelIdentity? modelIdentity,
    String? specificationId,
    Future<void>? cancellation,
    bool Function()? isCancelled,
  }) async {
    final backing = model;
    if (backing == null ||
        modelIdentity == null ||
        !warrantsModelUnderstanding(decision)) {
      return deterministic.understand(
        decision,
        specificationId: specificationId,
      );
    }
    try {
      final outcome = await backing.understand(
        request: decision.parsed.originalText,
        model: modelIdentity,
        context: context,
        specificationId: specificationId,
        cancellation: cancellation,
        isCancelled: isCancelled,
      );
      // Deterministic parsing still contributes what it knows for
      // certain: targets Chat already resolved are observed facts, and a
      // model omitting one must not erase it.
      return _mergeDeterministicFacts(outcome, decision);
    } catch (error, stackTrace) {
      final failure = classifyPlanningFailure(error, stackTrace: stackTrace);
      // An understanding failure that is genuinely about the model's
      // response degrades to the deterministic reading -- which is
      // honest, because Chat then says "interpreted", not "understood".
      // Every other kind of failure is a real failure and propagates.
      if (failure.allowsConservativeFallback) {
        return deterministic.understand(
          decision,
          specificationId: specificationId,
        );
      }
      throw failure;
    }
  }

  UnderstandingOutcome _mergeDeterministicFacts(
    UnderstandingOutcome outcome,
    ChatInteractionDecision decision,
  ) {
    final existing =
        outcome.specification.targetRefs.map((item) => item.value).toSet();
    final merged = <TaskTargetRef>[
      ...outcome.specification.targetRefs,
      for (final target in decision.targets)
        if (!existing.contains(target.id))
          TaskTargetRef(
            kind: target.type.name,
            value: target.id,
            displayName: target.displayName,
            provenance: EvidenceProvenance.observed,
            resolved: true,
          ),
    ];
    final questions = <UnresolvedQuestion>[
      ...outcome.specification.unresolvedQuestions,
      for (final mention in decision.unresolvedMentions)
        UnresolvedQuestion(
          question: 'Which target does "@$mention" refer to?',
          blocking: true,
        ),
    ];
    return UnderstandingOutcome(
      specification: outcome.specification.copyWith(
        targetRefs: merged,
        unresolvedQuestions: questions,
      ),
      path: outcome.path,
      rejections: outcome.rejections,
      capabilityHints: outcome.capabilityHints,
    );
  }
}
