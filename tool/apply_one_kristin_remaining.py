#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one replacement marker, found {count}: {old[:100]!r}")
    write(path, text.replace(old, new, 1))


def insert_before(path: str, marker: str, insertion: str) -> None:
    text = read(path)
    if text.count(marker) != 1:
        raise SystemExit(f"{path}: insertion marker not unique: {marker!r}")
    write(path, text.replace(marker, insertion + marker, 1))


def replace_between(path: str, start: str, end: str, replacement: str) -> None:
    text = read(path)
    start_at = text.find(start)
    if start_at < 0:
        raise SystemExit(f"{path}: start marker missing: {start!r}")
    end_at = text.find(end, start_at)
    if end_at < 0:
        raise SystemExit(f"{path}: end marker missing: {end!r}")
    write(path, text[:start_at] + replacement + text[end_at:])


# ---------------------------------------------------------------------------
# Deterministic utility.time owns timezone-database initialization.
# ---------------------------------------------------------------------------
replace_once(
    "lib/product/utility_time.dart",
    "import 'package:timezone/timezone.dart' as tz;\n",
    "import 'package:timezone/data/latest.dart' as tzdata;\n"
    "import 'package:timezone/timezone.dart' as tz;\n",
)
replace_once(
    "lib/product/utility_time.dart",
    "class UtilityTimeService {\n  UtilityTimeService({",
    "class UtilityTimeService {\n  static bool _timeZonesInitialized = false;\n\n"
    "  UtilityTimeService({",
)
replace_once(
    "lib/product/utility_time.dart",
    "  UtilityTimeResult currentTime(String requestedLocation) {\n    final requested = requestedLocation.trim();",
    "  UtilityTimeResult currentTime(String requestedLocation) {\n"
    "    _ensureTimeZonesInitialized();\n"
    "    final requested = requestedLocation.trim();",
)
replace_once(
    "lib/product/utility_time.dart",
    "    'nha trang': <String>['Asia/Ho_Chi_Minh'],\n    'sydney': <String>['Australia/Sydney'],",
    "    'nha trang': <String>['Asia/Ho_Chi_Minh'],\n"
    "    'bangkok': <String>['Asia/Bangkok'],\n"
    "    'thailand': <String>['Asia/Bangkok'],\n"
    "    'utc': <String>['Etc/UTC'],\n"
    "    'gmt': <String>['Etc/UTC'],\n"
    "    'sydney': <String>['Australia/Sydney'],",
)
insert_before(
    "lib/product/utility_time.dart",
    "  static String _normalize(String value) => value",
    "  static void _ensureTimeZonesInitialized() {\n"
    "    if (_timeZonesInitialized) return;\n"
    "    tzdata.initializeTimeZones();\n"
    "    _timeZonesInitialized = true;\n"
    "  }\n\n",
)

# ---------------------------------------------------------------------------
# utility.time becomes a first-class deterministic Chat capability.
# ---------------------------------------------------------------------------
replace_once(
    "lib/product/chat_control_plane.dart",
    "  researchSearch,\n\n  projectAnalyze,",
    "  researchSearch,\n\n  /// Deterministic timezone lookup. Never depends on web search.\n"
    "  utilityTime,\n\n  projectAnalyze,",
)
insert_before(
    "lib/product/chat_control_plane.dart",
    "  // 'analyze' and 'review' share one route",
    "  KristinCapability(\n"
    "    id: 'utility.time',\n"
    "    displayName: 'Time',\n"
    "    description: 'Return the current local time for an unambiguous city or IANA timezone.',\n"
    "    category: ChatCapabilityCategory.understand,\n"
    "    slashCommands: <String>['time', 'clock'],\n"
    "    mentionAliases: <String>['time'],\n"
    "    acceptedTargetTypes: <ChatTargetType>{},\n"
    "    actionClass: ChatActionClass.small,\n"
    "    riskClass: ChatRiskClass.none,\n"
    "    understandingPolicy: ChatUnderstandingPolicy.never,\n"
    "    planningPolicy: ChatPlanningPolicy.never,\n"
    "    route: ChatExecutionRoute.utilityTime,\n"
    "    preferredMode: CommandMode.ask,\n"
    "  ),\n",
)
insert_before(
    "lib/product/chat_control_plane.dart",
    "    if (_isInformationalLanguage(parsed.originalText)) {",
    "    final timeCapability = registry.byId('utility.time');\n"
    "    if (!parsed.hasExplicitCommand &&\n"
    "        timeCapability != null &&\n"
    "        _isTimeLanguage(parsed.originalText)) {\n"
    "      return _decision(\n"
    "        kind: ChatInteractionKind.action,\n"
    "        parsed: parsed,\n"
    "        capability: timeCapability,\n"
    "        targets: targets,\n"
    "        unresolved: unresolved,\n"
    "        goal: _goalFor(timeCapability, parsed, targets),\n"
    "        mode: CommandMode.ask,\n"
    "        risk: ChatRiskClass.none,\n"
    "        understanding: false,\n"
    "        plan: false,\n"
    "        ambiguous: false,\n"
    "      );\n"
    "    }\n\n",
)
insert_before(
    "lib/product/chat_control_plane.dart",
    "  KristinCapability? _naturalCapability(",
    "  bool _isTimeLanguage(String input) {\n"
    "    final value = _normalized(input);\n"
    "    if (!RegExp(r'\\btime\\b').hasMatch(value)) return false;\n"
    "    return RegExp(\n"
    "      r'\\b(?:time|local time)\\s+(?:in|at)\\s+[a-z0-9_+./ -]+'\n"
    "      r'|\\bwhat(?: is|s)?\\s+(?:the\\s+)?(?:local\\s+)?time\\s+(?:in|at)\\s+[a-z0-9_+./ -]+',\n"
    "    ).hasMatch(value);\n"
    "  }\n\n",
)
insert_before(
    "lib/product/chat_control_plane.dart",
    "      case 'research.search':",
    "      case 'utility.time':\n"
    "        return argument.isEmpty\n"
    "            ? 'Return the current local time for the requested location.'\n"
    "            : 'Return the current local time for $argument without using web search.';\n",
)

# ---------------------------------------------------------------------------
# Shared imports for the Chat hotspot.
# ---------------------------------------------------------------------------
replace_once(
    "lib/product/chat_control_plane_studio.dart",
    "import 'task_kernel/task_families.dart';\n",
    "import 'task_kernel/task_families.dart';\n"
    "import 'task_kernel/task_family_executor.dart';\n"
    "import 'task_kernel/semantic_steering.dart';\n",
)
replace_once(
    "lib/product/chat_control_plane_studio.dart",
    "import 'ui_components.dart';\n",
    "import 'ui_components.dart';\nimport 'utility_time.dart';\n",
)

old_run_steering = """      if (!decision.explicitCommand && !decision.isInformational) {
        conversationSession.addUserMessage(request);
        composerController.clear();
        final steered = await _perform<dynamic>(
          'Applying your direction',
          () => runtime.steerRun(currentRun!.id, request),
        );
        if (steered != null) {
          _mutate(() {
            conversationSession.showLiveProgress(
              'Your new direction is queued for the next safe step.',
            );
          });
        }
        return;
      }
"""
new_run_steering = """      if (!decision.explicitCommand && !decision.isInformational) {
        await _applySemanticSteering(request);
        return;
      }
"""
replace_once(
    "lib/product/chat_control_plane_studio.dart",
    old_run_steering,
    new_run_steering,
)

# ---------------------------------------------------------------------------
# Defense-in-depth clarification guard and utility.time route.
# ---------------------------------------------------------------------------
replace_once(
    "lib/product/chat_control_plane_studio_actions.dart",
    "    if (decision == null || history == null) return;\n\n    if (decision.unresolvedMentions.isNotEmpty) {",
    "    if (decision == null || history == null) return;\n\n"
    "    if (routingDecision?.requiresClarification == true ||\n"
    "        taskSpecification?.blockingQuestions.isNotEmpty == true) {\n"
    "      final question = taskSpecification?.blockingQuestions.first.question ??\n"
    "          'I need one clarification before I can continue safely.';\n"
    "      _mutate(() {\n"
    "        status = 'Reply in Chat: $question';\n"
    "        error = null;\n"
    "      });\n"
    "      composerFocus.requestFocus();\n"
    "      return;\n"
    "    }\n\n"
    "    if (decision.unresolvedMentions.isNotEmpty) {",
)
replace_once(
    "lib/product/chat_control_plane_studio_actions.dart",
    "      case ChatExecutionRoute.researchSearch:\n        await _runResearchSearch(decision, project: project);\n        return;\n",
    "      case ChatExecutionRoute.researchSearch:\n"
    "        await _runResearchSearch(decision, project: project);\n"
    "        return;\n"
    "      case ChatExecutionRoute.utilityTime:\n"
    "        await _runUtilityTime(decision);\n"
    "        return;\n",
)

# ---------------------------------------------------------------------------
# Replace the second, title-driven Research loop with the canonical family
# executor. A compact deterministic family plan is created even when the UI
# routing policy hides the graph for a simple one-fact search.
# ---------------------------------------------------------------------------
research_replacement = r'''  Future<void> _runResearchSearch(
    ChatInteractionDecision decision, {
    required ProjectRecord? project,
  }) async {
    final query = decision.parsed.arguments
        .replaceAll(RegExp(r'@[A-Za-z0-9][A-Za-z0-9._:-]*'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final effectiveQuery = query.isEmpty ? decision.parsed.originalText : query;
    final plan = await _researchPlan(decision);
    if (plan == null) {
      final deterministicTime = _timeEvidenceForResearch(effectiveQuery);
      final raw = deterministicTime != null
          ? <Map<String, String>>[deterministicTime]
          : (await _perform<ChatResearchResult>(
              'Searching current public sources',
              () => dispatcher.search(
                query: effectiveQuery,
                projectId: project?.id,
              ),
            ))
              ?.results;
      if (raw == null) return;
      if (raw.isEmpty) {
        _finishDirectAction(
          'No attributable evidence was found for "$effectiveQuery".',
        );
        return;
      }
      final answer = await _synthesizeResearchAnswer(
        effectiveQuery,
        ChatResearchResult(query: effectiveQuery, results: raw),
      );
      if (mounted) _finishDirectAction(answer);
      return;
    }

    final titles = <String, String>{
      for (final task in plan.tasks) task.id: task.title,
    };
    final execution = await _perform<ResearchTaskExecutionResult>(
      'Executing the research graph',
      () => const ResearchTaskFamilyExecutor().execute(
        plan: plan,
        onStateChanged: (node) {
          if (!mounted) return;
          _mutate(() {
            conversationSession.showLiveProgress(
              '${titles[node.taskId] ?? node.taskId} — ${node.state.name}',
            );
          });
        },
        search: (subject) async {
          final deterministicTime = _timeEvidenceForResearch(subject);
          if (deterministicTime != null) {
            return <Map<String, String>>[deterministicTime];
          }
          final result = await dispatcher.search(
            query: subject,
            projectId: project?.id,
          );
          return result.results;
        },
        synthesize: (request, sources) => _synthesizeResearchAnswer(
          request,
          ChatResearchResult(query: request, results: sources),
        ),
      ),
    );
    if (execution == null || !mounted) return;
    _mutate(() {
      canonicalPlan = plan;
      planningPath = ChatPlanningPath.model;
    });
    _finishDirectAction(execution.answer);
  }

  Future<UniversalTaskPlan?> _researchPlan(
    ChatInteractionDecision decision,
  ) async {
    final specification = taskSpecification ??
        const DeterministicUnderstanding().understand(decision).specification;
    final context = PlanningContext(
      project: selectedProject,
      model: selectedModel,
      availableCapabilityIds:
          kKristinCapabilities.map((item) => item.id).toSet(),
      availableToolNames: runtime.tools.names,
    );
    final routing = routingDecision;
    try {
      if (routing != null &&
          routing.family == TaskFamily.research &&
          routing.route != PlanningRoute.direct) {
        final result = await runtime.taskKernel.plan(
          specification: specification,
          routing: routing,
          context: context,
        );
        return result.plan;
      }
      return await const ResearchTaskFamilyPlanner().plan(
        specification: specification,
        route: PlanningRoute.compact,
        context: context,
      );
    } catch (failure) {
      _mutate(() {
        planningFailure = classifyPlanningFailure(failure);
      });
      return null;
    }
  }

'''
replace_between(
    "lib/product/chat_control_plane_studio_actions.dart",
    "  Future<void> _runResearchSearch(",
    "  /// Turns raw retrieved candidates",
    research_replacement,
)

# ---------------------------------------------------------------------------
# Diagnostics now executes the same canonical DAG that planning produced.
# ---------------------------------------------------------------------------
diagnostics_replacement = r'''  Future<void> _runDiagnosticsThroughKernel() async {
    final plan = await _diagnosticsPlan();
    if (plan == null) {
      final report = await _perform<CapabilityDoctorReport>(
        'Checking Kristin readiness',
        () => dispatcher.diagnose(
          projectId: selectedProjectId,
          discoveredModels: models,
        ),
      );
      if (report == null) return;
      _finishDirectAction(_diagnosticReadinessAnswer(report));
      return;
    }

    final titles = <String, String>{
      for (final task in plan.tasks) task.id: task.title,
    };
    final execution = await _perform<DiagnosticsTaskExecutionResult>(
      'Executing the diagnostic graph',
      () => const DiagnosticsTaskFamilyExecutor().execute(
        plan: plan,
        onStateChanged: (node) {
          if (!mounted) return;
          _mutate(() {
            conversationSession.showLiveProgress(
              '${titles[node.taskId] ?? node.taskId} — ${node.state.name}',
            );
          });
        },
        collect: () => dispatcher.diagnose(
          projectId: selectedProjectId,
          discoveredModels: models,
        ),
      ),
    );
    if (execution == null || !mounted) return;
    _mutate(() {
      canonicalPlan = plan;
      planningPath = ChatPlanningPath.model;
    });
    _finishDirectAction(execution.answer);
  }

  Future<UniversalTaskPlan?> _diagnosticsPlan() async {
    final specification = taskSpecification;
    if (specification == null) return null;
    final context = PlanningContext(
      project: selectedProject,
      model: selectedModel,
      availableCapabilityIds:
          kKristinCapabilities.map((item) => item.id).toSet(),
      availableToolNames: runtime.tools.names,
    );
    final routing = routingDecision;
    try {
      if (routing != null &&
          routing.family == TaskFamily.diagnostics &&
          routing.route != PlanningRoute.direct) {
        final result = await runtime.taskKernel.plan(
          specification: specification,
          routing: routing,
          context: context,
        );
        return result.plan;
      }
      return await const DiagnosticsTaskFamilyPlanner().plan(
        specification: specification,
        route: PlanningRoute.compact,
        context: context,
      );
    } catch (failure) {
      _mutate(() {
        planningFailure = classifyPlanningFailure(failure);
      });
      return null;
    }
  }

  String _diagnosticReadinessAnswer(CapabilityDoctorReport report) {
    final failing = report.checks
        .where((check) => !check.ready)
        .map((check) => check.title)
        .take(4)
        .toList(growable: false);
    return report.coreReady
        ? 'Kristin readiness is healthy: ${report.readyCount}/${report.checks.length} checks ready.'
        : 'Kristin readiness needs attention: '
            '${report.readyCount}/${report.checks.length} checks ready. '
            'Not ready: ${failing.join(', ')}.';
  }

  Future<void> _runUtilityTime(ChatInteractionDecision decision) async {
    final location = _timeLocationFrom(decision.parsed);
    if (location == null) {
      _showError(
        'Name a city or IANA timezone, for example `/time New York` or `/time America/New_York`.',
      );
      return;
    }
    final result = await _perform<UtilityTimeResult>(
      'Reading deterministic timezone data',
      () async => _resolveUtilityTime(location),
    );
    if (result == null) return;
    _finishDirectAction(_formatUtilityTime(result));
  }

  Map<String, String>? _timeEvidenceForResearch(String text) {
    final location = _timeLocationFromText(text);
    if (location == null) return null;
    final result = _resolveUtilityTime(location);
    return <String, String>{
      'title': 'Deterministic local time — ${result.requestedLocation}',
      'url': 'kristin://utility.time/${Uri.encodeComponent(result.timeZoneId)}',
      'snippet': _formatUtilityTime(result),
    };
  }

  UtilityTimeResult _resolveUtilityTime(String location) {
    try {
      return UtilityTimeService().currentTime(location);
    } on UtilityTimeException catch (failure) {
      throw ProductException(
        failure.code,
        failure.message,
        details: <String, dynamic>{
          if (failure.candidates.isNotEmpty) 'candidates': failure.candidates,
        },
      );
    }
  }

  String? _timeLocationFrom(ParsedChatInput parsed) {
    if (parsed.hasExplicitCommand) {
      final explicit = parsed.arguments
          .replaceAll(RegExp(r'@[A-Za-z0-9][A-Za-z0-9._:-]*'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return explicit.isEmpty ? null : explicit;
    }
    return _timeLocationFromText(parsed.originalText);
  }

  String? _timeLocationFromText(String text) {
    final match = RegExp(
      r'\b(?:time|local time)\s+(?:in|at)\s+(.+?)(?:[?.!,;]|$)',
      caseSensitive: false,
    ).firstMatch(text.trim());
    if (match != null) return match.group(1)?.trim();
    final natural = RegExp(
      r'\bwhat(?:\s+is|\'s)?\s+(?:the\s+)?(?:local\s+)?time\s+(?:in|at)\s+(.+?)(?:[?.!,;]|$)',
      caseSensitive: false,
    ).firstMatch(text.trim());
    return natural?.group(1)?.trim();
  }

  String _formatUtilityTime(UtilityTimeResult result) {
    String two(int value) => value.toString().padLeft(2, '0');
    final local = result.localTime;
    final offsetMinutes = result.utcOffset.inMinutes;
    final sign = offsetMinutes < 0 ? '-' : '+';
    final absolute = offsetMinutes.abs();
    final offset = '$sign${two(absolute ~/ 60)}:${two(absolute % 60)}';
    return 'Current time in ${result.requestedLocation}: '
        '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)} '
        '${result.abbreviation} (UTC$offset, ${result.timeZoneId}).';
  }

  Future<void> _applySemanticSteering(String request) async {
    final run = currentRun;
    if (run == null) return;
    conversationSession.addUserMessage(request);
    composerController.clear();

    final specification = taskSpecification;
    final model = selectedModel;
    if (specification == null || model == null) {
      final queued = await _perform<dynamic>(
        'Applying your direction',
        () => runtime.steerRun(run.id, request),
      );
      if (queued != null) {
        _mutate(() {
          conversationSession.showLiveProgress(
            'Your direction is queued for the next safe step.',
          );
        });
      }
      return;
    }

    final routing = routingDecision;
    final coordinator = SemanticSteeringCoordinator();
    final classifier = ModelTaskSpecificationPatchClassifier(
      model: model,
      generate: (generation) => runtime.models.providerFor(model).generate(generation),
    );
    final semantic = await _perform<SemanticSteeringResult>(
      'Understanding your direction',
      () => coordinator.apply(
        specification: specification,
        userMessage: request,
        classifier: classifier,
        previousPlan: canonicalPlan,
        completed: completedTasks,
        replan: canonicalPlan != null && routing != null && routing.plans
            ? (revisedSpecification) async {
                final result = await runtime.taskKernel.plan(
                  specification: revisedSpecification,
                  routing: routing,
                  context: PlanningContext(
                    project: selectedProject,
                    model: model,
                    availableCapabilityIds:
                        kKristinCapabilities.map((item) => item.id).toSet(),
                    availableToolNames: runtime.tools.names,
                  ),
                );
                return result.plan;
              }
            : null,
      ),
    );
    if (semantic == null || !mounted) return;

    final queued = await _perform<dynamic>(
      'Applying your direction',
      () => runtime.steerRun(run.id, semantic.runnerInstruction),
    );
    if (queued == null || !mounted) return;
    _mutate(() {
      taskSpecification = semantic.specification;
      if (semantic.reconciliation != null) {
        canonicalPlan = semantic.reconciliation!.plan;
        lastReconciliation = semantic.reconciliation;
      }
      conversationSession.showLiveProgress(
        semantic.reconciliation == null
            ? 'Semantic ${semantic.patch.kind.name} direction queued for the next safe step.'
            : 'Semantic direction queued; ${semantic.reconciliation!.summary}.',
      );
      status = 'Active task updated without granting new authority';
    });
  }

'''
replace_between(
    "lib/product/chat_control_plane_studio_actions.dart",
    "  Future<void> _runDiagnosticsThroughKernel()",
    "  Future<void> _runDiagnosticAction(",
    diagnostics_replacement,
)

replace_once(
    "lib/product/chat_control_plane_studio_actions.dart",
    "          initialProjectId: selectedProjectId,\n          initialModelId: selectedModelId,\n",
    "          initialProjectId: selectedProjectId,\n"
    "          initialModelId: selectedModelId,\n"
    "          conversationSession: conversationSession,\n",
)

# ---------------------------------------------------------------------------
# Advanced becomes a workspace view over the same canonical session. Its old
# composer remains for standalone uses of ChatStudio, but when opened from
# Kristin it is intentionally not reachable: conversation continues only in
# the canonical session via Back to Kristin.
# ---------------------------------------------------------------------------
replace_once(
    "lib/product/chat_studio.dart",
    "import 'models_research.dart';\n",
    "import 'models_research.dart';\nimport 'kristin_conversation_session.dart';\n",
)
replace_once(
    "lib/product/chat_studio.dart",
    "    this.initialProjectId,\n    this.initialModelId,\n  });",
    "    this.initialProjectId,\n"
    "    this.initialModelId,\n"
    "    this.conversationSession,\n"
    "  });",
)
replace_once(
    "lib/product/chat_studio.dart",
    "  /// Project/model selected in the canonical Kristin chat at the moment\n  /// this advanced workspace was opened, so it starts aligned with what\n  /// the user was just doing rather than re-deriving its own default\n  /// selection from scratch. Selections made while this workspace is open\n  /// are local to it -- they are not (yet) carried back to the canonical\n  /// chat on return; see chat_control_plane_studio_actions.dart's\n  /// `_openAdvanced` for the caller side of this boundary.\n  final String? initialProjectId;\n  final String? initialModelId;",
    "  /// Initial values for standalone Advanced launches. When\n"
    "  /// [conversationSession] is supplied, that session is authoritative.\n"
    "  final String? initialProjectId;\n"
    "  final String? initialModelId;\n\n"
    "  /// The canonical One-Kristin conversation session. Advanced opened\n"
    "  /// from Kristin shares project/model/run/prepared state with it and\n"
    "  /// exposes Back to Kristin instead of a second competing composer.\n"
    "  final KristinConversationSession? conversationSession;",
)
replace_once(
    "lib/product/chat_studio.dart",
    "  String? selectedProjectId;\n  String? selectedModelId;\n  String? selectedRunId;\n  String? selectedWorkItemId;\n  PreparedCommand? prepared;\n  RunRecord? currentRun;",
    "  String? _selectedProjectId;\n"
    "  String? get selectedProjectId =>\n"
    "      widget.conversationSession?.selectedProjectId ?? _selectedProjectId;\n"
    "  set selectedProjectId(String? value) {\n"
    "    _selectedProjectId = value;\n"
    "    widget.conversationSession?.selectProject(value);\n"
    "  }\n\n"
    "  String? _selectedModelId;\n"
    "  String? get selectedModelId =>\n"
    "      widget.conversationSession?.selectedModelId ?? _selectedModelId;\n"
    "  set selectedModelId(String? value) {\n"
    "    _selectedModelId = value;\n"
    "    widget.conversationSession?.selectModel(value);\n"
    "  }\n\n"
    "  String? selectedRunId;\n"
    "  String? selectedWorkItemId;\n"
    "  PreparedCommand? _prepared;\n"
    "  PreparedCommand? get prepared =>\n"
    "      widget.conversationSession?.prepared ?? _prepared;\n"
    "  set prepared(PreparedCommand? value) {\n"
    "    _prepared = value;\n"
    "    final session = widget.conversationSession;\n"
    "    if (session != null && !session.hasNonterminalRun) {\n"
    "      session.setPrepared(value);\n"
    "    }\n"
    "  }\n\n"
    "  RunRecord? _currentRun;\n"
    "  RunRecord? get currentRun =>\n"
    "      widget.conversationSession?.currentRun ?? _currentRun;\n"
    "  set currentRun(RunRecord? value) {\n"
    "    _currentRun = value;\n"
    "    final session = widget.conversationSession;\n"
    "    if (session == null) return;\n"
    "    final canonical = session.currentRun;\n"
    "    if (value == null) {\n"
    "      if (canonical != null && session.runTerminal) {\n"
    "        session.detachFinishedRun();\n"
    "      }\n"
    "      return;\n"
    "    }\n"
    "    if (canonical == null) {\n"
    "      session.restoreRun(value);\n"
    "    } else if (canonical.id == value.id) {\n"
    "      session.updateRun(value);\n"
    "    }\n"
    "  }",
)
replace_once(
    "lib/product/chat_studio.dart",
    "    super.initState();\n    selectedProjectId = widget.initialProjectId;\n    selectedModelId = widget.initialModelId;",
    "    super.initState();\n"
    "    if (widget.conversationSession != null) {\n"
    "      area = _StudioArea.projects;\n"
    "    }\n"
    "    selectedProjectId =\n"
    "        widget.conversationSession?.selectedProjectId ?? widget.initialProjectId;\n"
    "    selectedModelId =\n"
    "        widget.conversationSession?.selectedModelId ?? widget.initialModelId;",
)

old_content = """  Widget _content() => switch (area) {
        _StudioArea.chat => _chatPage(),
        _StudioArea.chats => _chatsPage(),
        _StudioArea.projects => _projectsPage(),
        _StudioArea.runs => _runsPage(),
        _StudioArea.promptStudio => _promptStudioPage(),
        _StudioArea.knowledge => _knowledgePage(),
        _StudioArea.skills => _skillsPage(),
        _StudioArea.logs => _logsPage(),
      };
"""
new_content = r'''  Widget _content() {
    final canonical = widget.conversationSession;
    final child = switch (area) {
      _StudioArea.chat => canonical == null ? _chatPage() : _canonicalKristinPage(),
      _StudioArea.chats => canonical == null ? _chatsPage() : _canonicalKristinPage(),
      _StudioArea.projects => _projectsPage(),
      _StudioArea.runs => _runsPage(),
      _StudioArea.promptStudio => _promptStudioPage(),
      _StudioArea.knowledge => _knowledgePage(),
      _StudioArea.skills => _skillsPage(),
      _StudioArea.logs => _logsPage(),
    };
    if (canonical == null) return child;
    return Column(
      children: <Widget>[
        Material(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Advanced tools — same Kristin session',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey<String>('back-to-kristin'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to Kristin'),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _canonicalKristinPage() {
    final session = widget.conversationSession!;
    final recent = session.messages.reversed.take(12).toList().reversed;
    final run = session.currentRun;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Text('Kristin conversation', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          'Advanced does not start a second conversation. Project, model, plan, Run, permission and pending-user-input state remain owned by the same Kristin session.',
        ),
        if (run != null) ...<Widget>[
          const SizedBox(height: 16),
          Text('Active Run: ${run.state.name} — ${run.command.contract.request}'),
        ],
        if (session.awaitingUserInput) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            session.deferredUserPrompt ?? 'Kristin needs your input before continuing.',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
        if (session.awaitingPermission) ...<Widget>[
          const SizedBox(height: 12),
          const Text('A governed permission decision is pending in Kristin.'),
        ],
        const SizedBox(height: 20),
        for (final message in recent)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('${message.assistant ? 'Kristin' : 'You'}: ${message.text}'),
          ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey<String>('canonical-back-to-kristin'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to Kristin'),
          ),
        ),
      ],
    );
  }
'''
replace_once("lib/product/chat_studio.dart", old_content, new_content)

# ---------------------------------------------------------------------------
# Semantic steering coordinator: typed patch -> replan -> reconciliation ->
# non-authority-bearing Runner instruction, all unit-testable outside Flutter.
# ---------------------------------------------------------------------------
write(
    "lib/product/task_kernel/semantic_steering.dart",
    r'''import 'dart:convert';

import 'plan_reconciliation.dart';
import 'task_specification.dart';
import 'task_specification_patch.dart';
import 'task_specification_patch_classifier.dart';
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

typedef SemanticSteeringReplan = Future<UniversalTaskPlan> Function(
  TaskSpecification specification,
);

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
''',
)

# ---------------------------------------------------------------------------
# Focused regression contracts for this final integration wave.
# ---------------------------------------------------------------------------
write(
    "test/product/task_kernel/semantic_steering_test.dart",
    r'''import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/task_kernel/plan_reconciliation.dart';
import 'package:kristin_local_agent/product/task_kernel/semantic_steering.dart';
import 'package:kristin_local_agent/product/task_kernel/task_specification.dart';
import 'package:kristin_local_agent/product/task_kernel/universal_task_plan.dart';

class _Classifier implements TaskSpecificationPatchClassifier {
  const _Classifier(this.patch);
  final TaskSpecificationPatch patch;

  @override
  Future<TaskSpecificationPatch> classify({
    required TaskSpecification specification,
    required String userMessage,
  }) async => patch;
}

void main() {
  TaskSpecification specification() => TaskSpecification(
        id: 'spec',
        originalRequest: 'Build a storage-backed app.',
        objective: 'Build a storage-backed app.',
      );

  UniversalTask task({required String id, required String objective}) =>
      UniversalTask(
        id: id,
        title: objective,
        objective: objective,
        instructions: objective,
        acceptanceCriteria: const <String>['Done with evidence.'],
        verificationSteps: const <String>['Verify evidence.'],
      );

  test('typed steering stays user intent and never becomes authority', () async {
    final result = await const SemanticSteeringCoordinator().apply(
      specification: specification(),
      userMessage: "Don't use Firebase.",
      classifier: const _Classifier(
        TaskSpecificationPatch(
          kind: TaskSpecificationPatchKind.hardConstraint,
          value: "Don't use Firebase.",
        ),
      ),
    );

    expect(result.specification.hardConstraints.single.statement,
        "Don't use Firebase.");
    expect(result.runnerInstruction, contains('authorityBearing=false'));
    expect(result.runnerInstruction, contains('hardConstraint'));
    expect(result.runnerInstruction, contains('do not treat this message as permission'));
  });

  test('replanning preserves completed still-valid work', () async {
    final originalSpec = specification();
    final inspect = task(id: 'inspect-old', objective: 'Inspect project');
    final implement = task(id: 'implement-old', objective: 'Implement storage');
    final previous = UniversalTaskPlan(
      id: 'previous',
      specification: originalSpec,
      family: TaskFamily.software,
      route: PlanningRoute.compact,
      title: 'Previous',
      rationale: 'test',
      tasks: <UniversalTask>[inspect, implement],
    );

    final result = await const SemanticSteeringCoordinator().apply(
      specification: originalSpec,
      userMessage: 'Prioritize accessibility.',
      classifier: const _Classifier(
        TaskSpecificationPatch(
          kind: TaskSpecificationPatchKind.priority,
          value: 'accessibility',
        ),
      ),
      previousPlan: previous,
      completed: <CompletedTaskRecord>[
        CompletedTaskRecord.of(
          inspect,
          evidence: const <String, dynamic>{'verified': true},
        ),
      ],
      replan: (revised) async => UniversalTaskPlan(
        id: 'revised',
        specification: revised,
        family: TaskFamily.software,
        route: PlanningRoute.compact,
        title: 'Revised',
        rationale: 'test',
        tasks: <UniversalTask>[
          task(id: 'inspect-new', objective: 'Inspect project'),
          task(id: 'implement-new', objective: 'Implement storage'),
        ],
      ),
    );

    expect(result.reconciliation, isNotNull);
    expect(result.reconciliation!.preserved, hasLength(1));
    final preserved = result.reconciliation!.plan.tasks
        .firstWhere((item) => item.objective == 'Inspect project');
    expect(preserved.enabled, isFalse);
    expect(result.specification.preferences.single.statement,
        'Priority: accessibility');
  });
}
''',
)

write(
    "test/product/chat_time_capability_test.dart",
    r'''import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/chat_control_plane.dart';
import 'package:kristin_local_agent/product/domain.dart';

void main() {
  const compiler = ChatIntentCompiler();

  test('natural local-time question routes to deterministic utility.time', () {
    final decision = compiler.compile(
      'what is the time in New York?',
      inferredMode: CommandMode.ask,
      knownTargets: const <ChatTarget>[],
    );
    expect(decision.capability?.id, 'utility.time');
    expect(decision.needsPlan, isFalse);
    expect(decision.needsUnderstanding, isFalse);
    expect(decision.riskClass, ChatRiskClass.none);
  });

  test('/time is structurally deterministic', () {
    final decision = compiler.compile(
      '/time America/New_York',
      inferredMode: CommandMode.ask,
      knownTargets: const <ChatTarget>[],
    );
    expect(decision.capability?.id, 'utility.time');
    expect(decision.parsed.arguments, 'America/New_York');
    expect(decision.needsPlan, isFalse);
  });
}
''',
)

write(
    "test/product/one_kristin_advanced_source_contract_test.dart",
    r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Advanced opened from Kristin shares canonical session and has Back path', () {
    final advanced = File('lib/product/chat_studio.dart').readAsStringSync();
    final caller = File('lib/product/chat_control_plane_studio_actions.dart')
        .readAsStringSync();

    expect(advanced, contains('final KristinConversationSession? conversationSession;'));
    expect(advanced, contains("ValueKey<String>('back-to-kristin')"));
    expect(advanced, contains('same Kristin session'));
    expect(advanced, contains('canonical == null ? _chatPage() : _canonicalKristinPage()'));
    expect(caller, contains('conversationSession: conversationSession'));
  });
}
''',
)

# Strengthen utility-time test: service initializes itself and Bangkok is direct.
replace_once(
    "test/product/utility_time_test.dart",
    "import 'package:timezone/data/latest.dart' as tzdata;\n",
    "",
)
replace_once(
    "test/product/utility_time_test.dart",
    "  setUpAll(tzdata.initializeTimeZones);\n\n",
    "",
)
insert_before(
    "test/product/utility_time_test.dart",
    "  test('ambiguous abbreviation is not guessed'",
    "  test('service initializes timezone data and resolves Bangkok without search', () {\n"
    "    final service = UtilityTimeService(\n"
    "      clock: FixedKristinClock(DateTime.utc(2026, 8, 31, 12)),\n"
    "    );\n"
    "    final result = service.currentTime('Bangkok');\n"
    "    expect(result.timeZoneId, 'Asia/Bangkok');\n"
    "    expect(result.localTime.hour, 19);\n"
    "    expect(result.utcOffset.inHours, 7);\n"
    "  });\n\n",
)

print('Applied remaining One Kristin integration patches.')
