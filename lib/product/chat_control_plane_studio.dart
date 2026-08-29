import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_server.dart';
import 'capability_doctor.dart';
import 'chat_action_dispatcher.dart';
import 'chat_control_plane.dart';
import 'chat_conversation_state.dart';
import 'chat_target_resolver.dart';
import 'chat_studio.dart';
import 'conversation_orchestrator.dart';
import 'domain.dart';
import 'kristin_conversation_session.dart';
import 'models_research.dart';
import 'product_error_normalizer.dart';
import 'product_runtime.dart';
import 'run_live_signals.dart';
import 'task_kernel/complexity_router.dart';
import 'task_kernel/plan_compiler.dart';
import 'task_kernel/task_families.dart';
import 'task_kernel/plan_reconciliation.dart';
import 'task_kernel/planning_failures.dart';
import 'task_kernel/task_kernel.dart';
import 'task_kernel/task_specification.dart';
import 'task_kernel/task_understanding.dart';
import 'task_kernel/universal_task_plan.dart';
import 'ui_advanced.dart';
import 'ui_components.dart';

part 'chat_control_plane_studio_actions.dart';
part 'chat_control_plane_studio_view.dart';

/// Which planner actually produced the currently prepared command, so the
/// UI never implies a detailed model-authored decomposition exists when a
/// deterministic fallback was used instead.
///
/// Chat plans through [UniversalTaskKernel] now, so this records the
/// kernel outcome rather than which of two services was called.
enum ChatPlanningPath {
  /// No multi-task plan was generated: the request routed to direct
  /// conversation or a direct deterministic capability invocation.
  deterministic,

  /// A family planner produced a real, request-specific task graph.
  model,

  /// A KNOWN RECOVERABLE planning failure degraded to the deterministic
  /// conservative inspect/implement/verify envelope. Every other failure
  /// kind surfaces as a failure instead of arriving here -- see
  /// task_kernel/planning_failures.dart.
  fallback,
}

class ChatControlPlaneStudio extends StatefulWidget {
  const ChatControlPlaneStudio({
    super.key,
    required this.runtime,
    required this.api,
    this.startupError,
  });

  final ProductRuntime runtime;
  final GovernedApiServer api;
  final String? startupError;

  @override
  State<ChatControlPlaneStudio> createState() => _ChatControlPlaneStudioState();
}

class _ChatControlPlaneStudioState extends State<ChatControlPlaneStudio> {
  final TextEditingController composerController = TextEditingController();
  final TextEditingController understandingAdjustmentController =
      TextEditingController();
  final TextEditingController planAdjustmentController =
      TextEditingController();
  final FocusNode composerFocus = FocusNode();
  final KristinConversationSession conversationSession =
      KristinConversationSession();

  final List<_ChatLine> transcript = <_ChatLine>[];
  final List<LiveRunSignal> liveSignals = <LiveRunSignal>[];
  final ChatIntentCompiler intentCompiler = const ChatIntentCompiler(
    policy: _StudioInteractionPolicy(),
  );
  final ChatAutocompleteEngine autocompleteEngine =
      const ChatAutocompleteEngine();

  StreamSubscription<LiveRunSignal>? liveSubscription;
  Timer? refreshTimer;

  bool loading = true;
  bool busy = false;
  bool understandingAdjusting = false;
  bool planAdjusting = false;
  bool detailsExpanded = false;
  String status = 'Kristin is ready';
  String? error;

  List<ProjectRecord> projects = <ProjectRecord>[];
  List<ModelIdentity> models = <ModelIdentity>[];
  List<RunRecord> runs = <RunRecord>[];
  List<EvidenceRecord> evidence = <EvidenceRecord>[];
  String? get selectedProjectId => conversationSession.selectedProjectId;
  set selectedProjectId(String? value) {
    conversationSession.selectProject(value);
  }

  String? get selectedModelId => conversationSession.selectedModelId;
  set selectedModelId(String? value) {
    conversationSession.selectModel(value);
  }

  ProjectProcessStatus? projectProcessStatus;

  ChatInteractionDecision? pendingDecision;
  UnderstandingHistory? understandingHistory;
  PreparedCommand? prepared;
  ChatPlanningPath planningPath = ChatPlanningPath.deterministic;

  /// The canonical semantic statement of the current request. Everything
  /// downstream -- routing, planning, compilation -- consumes this rather
  /// than re-reading the raw request string, so a hard constraint the
  /// user stated cannot silently stop being a constraint.
  TaskSpecification? taskSpecification;

  /// Whether the current [taskSpecification] came from real model-backed
  /// semantic understanding. Drives the understanding card's wording:
  /// "I understood" is only truthful when this is
  /// [UnderstandingPath.model]; regex matching stays "I interpreted this
  /// as".
  UnderstandingPath understandingPath = UnderstandingPath.deterministic;

  /// What the model proposed and deterministic validation refused
  /// (invented targets, unknown capabilities, attempts to assert
  /// authority). Kept visible rather than silently dropped.
  List<String> understandingRejections = const <String>[];

  /// How much planning the kernel decided this request deserves, and why.
  RoutingDecision? routingDecision;

  /// The canonical plan the currently prepared command was compiled from.
  /// The plan card renders this; the Runner executes its compilation.
  /// They are the same graph by construction.
  UniversalTaskPlan? canonicalPlan;

  /// The recoverable planning failure that forced a conservative plan,
  /// so the UI can say specifically what went wrong instead of vaguely.
  PlanningFailure? planningFailure;

  /// Canonical tasks already completed in this conversation, carried
  /// across a replan so finished work is preserved rather than redone.
  List<CompletedTaskRecord> completedTasks = const <CompletedTaskRecord>[];

  /// What the last replan changed, for the plan card to show.
  PlanReconciliationResult? lastReconciliation;
  String activeRequest = '';
  String liveAssistantProtocolText = '';
  String liveAssistantText = '';
  String liveProgressText = '';
  String liveToolName = '';
  String liveToolOutput = '';

  List<ChatAutocompleteSuggestion> suggestions =
      const <ChatAutocompleteSuggestion>[];
  int suggestionIndex = 0;

  ProductRuntime get runtime => widget.runtime;

  RunRecord? get currentRun => conversationSession.currentRun;
  set currentRun(RunRecord? value) {
    final existing = conversationSession.currentRun;
    if (value == null) {
      // Transitional compatibility for the remaining Chat fields: a legacy
      // null assignment may clear a finished/no-run association, but it can
      // never orphan unfinished durable work.
      if (!conversationSession.hasNonterminalRun) {
        conversationSession.resetForNewConversation();
      }
      return;
    }
    if (existing != null && existing.id == value.id) {
      conversationSession.updateRun(value);
    } else {
      conversationSession.restoreRun(value);
    }
  }

  bool get awaitingPermission => conversationSession.awaitingPermission;
  set awaitingPermission(bool value) {
    // A legacy side-action cleanup may request `false`, but durable run state
    // remains authoritative. Only a refreshed non-awaiting run (or no run)
    // may clear the permission projection.
    if (!value && conversationSession.runAwaitingApproval) {
      return;
    }
    conversationSession.setAwaitingPermission(value);
  }

  ChatActionDispatcher get dispatcher =>
      ChatActionDispatcher(ProductRuntimeChatGateway(runtime));

  ProjectRecord? get selectedProject =>
      projects.where((project) => project.id == selectedProjectId).firstOrNull;

  ModelIdentity? get selectedModel =>
      models.where((model) => model.exactId == selectedModelId).firstOrNull;

  bool get runAwaitingApproval => conversationSession.runAwaitingApproval;

  bool get runActive =>
      currentRun != null &&
      const <RunState>{
        RunState.running,
        RunState.paused,
        RunState.cancelling,
        RunState.interrupted,
      }.contains(currentRun!.state);

  /// True only while a run is genuinely executing right now. Unlike
  /// [runActive], this excludes [RunState.interrupted]: an interrupted run
  /// survived an app restart with nothing currently in flight, so it must
  /// stay resumable (Resume/Stop remain available wherever [runActive] is
  /// used for that) without silently absorbing ordinary chat messages as
  /// steering input into a task the user never asked to continue.
  bool get runExecuting => conversationSession.runExecuting;

  /// True whenever a durable run exists and has not reached a terminal
  /// state -- including [RunState.awaitingApproval] and
  /// [RunState.interrupted], neither of which [runExecuting] covers. A new
  /// message arriving while this is true must never silently discard the
  /// association (clearing `currentRun` as a side effect of starting an
  /// unrelated request): it must be treated as an informational side
  /// conversation, a steer/control of this same run, a clarification, or an
  /// explicit cancel/decline before anything else starts.
  bool get hasNonterminalRun => conversationSession.hasNonterminalRun;

  bool get runTerminal => conversationSession.runTerminal;

  @override
  void initState() {
    super.initState();
    liveSubscription = runtime.liveRunStream.listen(_onLiveSignal);
    refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (runActive) unawaited(_refreshCurrentRun());
      if (projectProcessStatus?.running == true) {
        unawaited(_refreshProjectProcess());
      }
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    liveSubscription?.cancel();
    refreshTimer?.cancel();
    composerController.dispose();
    understandingAdjustmentController.dispose();
    planAdjustmentController.dispose();
    composerFocus.dispose();
    super.dispose();
  }

  void _mutate(VoidCallback action) {
    if (mounted) setState(action);
  }

  Future<T?> _perform<T>(
    String activity,
    Future<T> Function() action, {
    bool silent = false,
  }) async {
    if (!silent) {
      _mutate(() {
        busy = true;
        status = activity;
        error = null;
      });
    }
    try {
      return await action();
    } catch (failure) {
      _mutate(() {
        error = runtime.redactor.redact(
          ProductErrorNormalizer.userMessage(failure),
        );
        status = 'Kristin needs your help';
      });
      return null;
    } finally {
      if (!silent) _mutate(() => busy = false);
    }
  }

  Future<void> _load() async {
    await _perform<void>('Opening Kristin', () async {
      projects = await runtime.listProjects();
      models = await runtime.discoverModels();
      runs = await runtime.listRuns(limit: 120);
      selectedProjectId ??= projects.firstOrNull?.id;
      selectedModelId ??= models.firstOrNull?.exactId;

      final durable = runs.where((run) {
        return !const <RunState>{
          RunState.succeeded,
          RunState.failed,
          RunState.cancelled,
        }.contains(run.state);
      }).firstOrNull;
      if (durable != null) {
        currentRun = durable;
        conversationSession.setDeferredInteraction(
          await runtime.latestDeferredInteraction(durable.id),
        );
        prepared = durable.command;
        activeRequest = durable.command.contract.request;
        selectedProjectId = durable.command.contract.projectId;
        selectedModelId = durable.command.model.exactId;
        evidence = await runtime.evidenceForRun(durable.id);
        awaitingPermission = durable.state == RunState.awaitingApproval;
      }
      if (selectedProjectId != null) {
        projectProcessStatus =
            await runtime.projectProcessStatus(selectedProjectId!);
      }
    });
    _mutate(() {
      loading = false;
      status = conversationSession.awaitingUserInput
          ? conversationSession.deferredUserPrompt ??
              'Kristin needs your input before continuing.'
          : runAwaitingApproval
              ? 'Permission review required'
              : runExecuting
                  ? 'Continuing active work'
                  : 'Kristin is ready';
    });
  }

  Future<void> _refreshCurrentRun() async {
    final run = currentRun;
    if (run == null) return;
    final refreshed = await _perform<RunRecord?>(
      'Refreshing execution',
      () => runtime.getRun(run.id),
      silent: true,
    );
    if (refreshed == null || !mounted) return;
    final newTerminal = const <RunState>{
      RunState.succeeded,
      RunState.failed,
      RunState.cancelled,
    }.contains(refreshed.state);
    final loadedEvidence =
        newTerminal ? await runtime.evidenceForRun(refreshed.id) : evidence;
    final deferred = newTerminal
        ? null
        : await runtime.latestDeferredInteraction(refreshed.id);
    _mutate(() {
      currentRun = refreshed;
      conversationSession.setDeferredInteraction(deferred);
      evidence = loadedEvidence;
      // Completed work is recorded against the canonical plan as it
      // happens, so a later replan can preserve it instead of asking the
      // user to watch finished tasks run a second time.
      completedTasks = _completedTasksFrom(refreshed);
      awaitingPermission = refreshed.state == RunState.awaitingApproval;
      if (conversationSession.awaitingUserInput) {
        status = conversationSession.deferredUserPrompt ??
            'Kristin needs your input before continuing.';
      } else if (newTerminal) {
        status = refreshed.state == RunState.succeeded
            ? 'Finished and verified'
            : 'Execution stopped safely';
      }
    });
  }

  Future<void> _refreshProjectProcess() async {
    final projectId = selectedProjectId;
    if (projectId == null) return;
    final process = await _perform<ProjectProcessStatus?>(
      'Refreshing project process',
      () => runtime.projectProcessStatus(projectId),
      silent: true,
    );
    if (selectedProjectId == projectId) {
      _mutate(() => projectProcessStatus = process);
    }
  }

  void _onLiveSignal(LiveRunSignal signal) {
    if (!mounted || signal.runId != currentRun?.id) return;
    _mutate(() {
      liveSignals.add(signal);
      if (liveSignals.length > 600) {
        liveSignals.removeRange(0, liveSignals.length - 600);
      }
      switch (signal.kind) {
        case LiveRunSignalKind.modelTextDelta:
          final delta = signal.data['delta']?.toString() ?? '';
          liveAssistantProtocolText = '$liveAssistantProtocolText$delta';
          if (liveAssistantProtocolText.length > 18000) {
            liveAssistantProtocolText = liveAssistantProtocolText.substring(
              liveAssistantProtocolText.length - 18000,
            );
          }
          liveAssistantText = ConversationStreamProjector.visibleText(
            liveAssistantProtocolText,
          );
          break;
        case LiveRunSignalKind.modelProgress:
        case LiveRunSignalKind.phase:
        case LiveRunSignalKind.preflight:
          liveProgressText = signal.data['message']?.toString() ?? '';
          break;
        case LiveRunSignalKind.toolStarted:
          liveToolName = signal.data['tool']?.toString() ?? 'tool';
          liveToolOutput = '';
          break;
        case LiveRunSignalKind.toolOutput:
          liveToolName = signal.data['tool']?.toString() ?? liveToolName;
          final delta = signal.data['delta']?.toString() ?? '';
          liveToolOutput = '$liveToolOutput$delta';
          if (liveToolOutput.length > 12000) {
            liveToolOutput =
                liveToolOutput.substring(liveToolOutput.length - 12000);
          }
          break;
        case LiveRunSignalKind.toolCompleted:
          liveToolName = signal.data['tool']?.toString() ?? liveToolName;
          final output = signal.data['output']?.toString() ?? '';
          if (output.isNotEmpty) liveToolOutput = output;
          break;
        case LiveRunSignalKind.toolFailed:
          liveToolName = signal.data['tool']?.toString() ?? liveToolName;
          liveToolOutput = signal.data['detail']?.toString() ?? '';
          break;
        case LiveRunSignalKind.steeringQueued:
          liveProgressText =
              'Your new direction is queued for the next safe step.';
          break;
        case LiveRunSignalKind.steeringApplied:
          liveProgressText = 'Your new direction was applied.';
          break;
        case LiveRunSignalKind.heartbeat:
          break;
      }
    });
  }

  /// Adding a future target type (a filesystem location, a terminal, a
  /// browser window, ...) means writing one new [ChatTargetProvider] and
  /// listing it here -- see Architectural Improvement #5.
  List<ChatTarget> _knownTargets() {
    final providerIds =
        runtime.models.providers().map((item) => item.id).toSet();
    return ChatTargetResolver(<ChatTargetProvider>[
      ProjectTargetProvider(
        projects: projects,
        selectedProjectId: selectedProjectId,
      ),
      ModelTargetProvider(models: models, selectedModelId: selectedModelId),
      ProviderTargetProvider(configuredProviderIds: providerIds),
      const WorkspaceTargetProvider(),
    ]).resolve();
  }

  void _updateSuggestions() {
    final value = composerController.value;
    final next = autocompleteEngine.suggestions(
      text: value.text,
      cursorOffset: value.selection.isValid
          ? value.selection.baseOffset
          : value.text.length,
      targets: _knownTargets(),
    );
    _mutate(() {
      suggestions = next;
      suggestionIndex = 0;
    });
  }

  void _selectSuggestion(ChatAutocompleteSuggestion suggestion) {
    final text = composerController.text;
    final selection = composerController.selection;
    final cursor = selection.isValid ? selection.baseOffset : text.length;
    final prefix = text.substring(0, cursor);
    if (suggestion.kind == ChatAutocompleteKind.command) {
      composerController.value = TextEditingValue(
        text: suggestion.insertText,
        selection:
            TextSelection.collapsed(offset: suggestion.insertText.length),
      );
    } else {
      final match = RegExp(r'@[A-Za-z0-9._:-]*$').firstMatch(prefix);
      if (match == null) return;
      final replacement = suggestion.insertText;
      final next =
          '${text.substring(0, match.start)}$replacement${text.substring(cursor)}';
      composerController.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(
          offset: match.start + replacement.length,
        ),
      );
    }
    _mutate(() {
      suggestions = const <ChatAutocompleteSuggestion>[];
      suggestionIndex = 0;
    });
    composerFocus.requestFocus();
  }

  Future<void> _submit() async {
    final request = composerController.text.trim();
    if (request.isEmpty || busy) return;
    if (suggestions.isNotEmpty) {
      _selectSuggestion(suggestions[suggestionIndex]);
      return;
    }

    final mode = resolveTaskMode(
      request: request,
      choice: SimpleTaskMode.auto,
      chosenMode: CommandMode.build,
    );
    final decision = intentCompiler.compile(
      request,
      inferredMode: mode,
      knownTargets: _knownTargets(),
    );

    if (conversationSession.awaitingUserInput) {
      final run = currentRun;
      if (run == null) {
        conversationSession.setDeferredInteraction(null);
      } else if (_isActiveRunCancellation(request, decision)) {
        transcript.add(_ChatLine.user(request));
        composerController.clear();
        await _controlRun('cancel');
        return;
      } else {
        transcript.add(_ChatLine.user(request));
        composerController.clear();
        final resolved = await _perform(
          'Recording your answer',
          () => runtime.recordDeferredUserResponse(
            runId: run.id,
            response: request,
          ),
        );
        if (resolved == null || !mounted) return;
        _mutate(() {
          conversationSession.setDeferredInteraction(resolved);
          liveProgressText = 'Continuing with your answer.';
          status = 'Continuing with your answer';
        });
        await _perform<void>(
          'Continuing with your answer',
          () => runtime.resume(run.id),
        );
        await _refreshCurrentRun();
        return;
      }
    }

    if (runExecuting) {
      if (_isActiveRunCancellation(request, decision)) {
        transcript.add(_ChatLine.user(request));
        composerController.clear();
        await _controlRun('cancel');
        return;
      }
      if (!decision.explicitCommand && !decision.isInformational) {
        transcript.add(_ChatLine.user(request));
        composerController.clear();
        final steered = await _perform<dynamic>(
          'Applying your direction',
          () => runtime.steerRun(currentRun!.id, request),
        );
        if (steered != null) {
          _mutate(() {
            liveProgressText =
                'Your new direction is queued for the next safe step.';
          });
        }
        return;
      }
      if (decision.explicitCommand && !decision.isInformational) {
        transcript.add(_ChatLine.user(request));
        transcript.add(
          _ChatLine.assistant(
            'A governed task is already active. Pause or stop it before starting a separate command, or describe a steering change in plain language.',
          ),
        );
        composerController.clear();
        _mutate(() => status = 'Active task preserved');
        return;
      }
    }

    // A durable run that is awaitingApproval or interrupted is not caught
    // by runExecuting above (it isn't live), but it must still never be
    // silently abandoned: an unrelated new actionable request must not
    // clear currentRun and forget it. Informational side conversation and
    // zero-risk navigation both remain allowed alongside it.
    if (hasNonterminalRun) {
      if (_isActiveRunCancellation(request, decision)) {
        transcript.add(_ChatLine.user(request));
        composerController.clear();
        await _controlRun('cancel');
        return;
      }
      final safeAlongsidePendingRun = decision.isInformational ||
          (decision.capability != null &&
              decision.capability!.riskClass == ChatRiskClass.none);
      if (!safeAlongsidePendingRun) {
        transcript.add(_ChatLine.user(request));
        transcript.add(_ChatLine.assistant(_pendingRunMessage()));
        composerController.clear();
        _mutate(() => status = 'Pending task preserved');
        return;
      }
    }

    _archiveFinishedRun();
    transcript.add(_ChatLine.user(request));
    composerController.clear();

    if (decision.explicitCommand && decision.capability == null) {
      _mutate(() {
        transcript.add(
          _ChatLine.assistant(
            'I do not know /${decision.parsed.commandToken}. Type / to see the available actions.',
          ),
        );
        status = 'Kristin is ready';
      });
      return;
    }

    if (decision.capability?.understandingPolicy ==
        ChatUnderstandingPolicy.never) {
      await _handleImmediateCapability(decision);
      return;
    }
    if (decision.kind == ChatInteractionKind.reference) {
      await _answerTargetReference(decision);
      return;
    }
    if (decision.isInformational) {
      await _answerInformational(decision);
      return;
    }

    // UNDERSTANDING. The model reads the human; deterministic code
    // validates the reading (see task_kernel/task_understanding.dart).
    // An explicit command, a bare mention or an informational message
    // never reaches here, so no model call is spent rediscovering what
    // the user literally typed.
    final outcome = await _understandRequest(decision);
    if (outcome == null || !mounted) return;

    _mutate(() {
      activeRequest = request;
      pendingDecision = decision;
      understandingHistory = UnderstandingHistory.initial(decision);
      taskSpecification = outcome.specification;
      understandingPath = outcome.path;
      understandingRejections = outcome.rejections;
      routingDecision = runtime.taskKernel.route(
        specification: outcome.specification,
        decision: decision,
      );
      canonicalPlan = null;
      planningFailure = null;
      lastReconciliation = null;
      completedTasks = const <CompletedTaskRecord>[];
      planningPath = ChatPlanningPath.deterministic;
      prepared = null;
      currentRun = null;
      awaitingPermission = false;
      understandingAdjusting = false;
      planAdjusting = false;
      detailsExpanded = false;
      error = null;
      status = outcome.isSemantic
          ? 'Review what Kristin understood'
          : 'Review how Kristin interpreted this';
    });
  }

  /// Runs the kernel's understanding step, mapping a failure onto the
  /// typed taxonomy rather than silently continuing with a guess.
  ///
  /// A failure that is genuinely about the model's *response* already
  /// degrades to the deterministic reading inside the kernel (and Chat
  /// then honestly says "interpreted", not "understood"). What arrives
  /// here is a real failure -- cancellation, an unreachable provider, a
  /// denied authority, a broken store -- and it is reported as one.
  Future<UnderstandingOutcome?> _understandRequest(
    ChatInteractionDecision decision,
  ) async {
    final kernel = runtime.taskKernel;
    final context = KernelRequestContext(
      decision: decision,
      project: selectedProject,
      model: selectedModel,
      knownTargets: _knownTargets(),
      availableToolNames: runtime.tools.names,
    );
    if (!kernel.understanding.warrantsModelUnderstanding(decision) ||
        selectedModel == null) {
      // Deterministic and synchronous: no spinner, no latency.
      return kernel.understanding.deterministic.understand(decision);
    }
    _mutate(() {
      busy = true;
      status = 'Understanding your request';
      error = null;
    });
    try {
      return await kernel.understand(context);
    } catch (thrown, stackTrace) {
      final failure = classifyPlanningFailure(thrown, stackTrace: stackTrace);
      switch (failure.kind) {
        case PlanningFailureKind.cancelled:
          _mutate(() {
            status = 'Cancelled';
            error = null;
          });
          return null;
        case PlanningFailureKind.providerUnavailable:
          // Understanding is the one step with a real deterministic
          // alternative, and Kristin used it exclusively until now. An
          // unreachable model must not make Chat unusable: fall back to
          // the deterministic reading, which is exactly what happens when
          // no model is connected at all. The card then says "I
          // interpreted this as", so the degrade is visible rather than
          // silently passed off as understanding.
          _mutate(() {
            status = 'Interpreting without the model '
                '(${failure.message})';
            error = null;
          });
          return kernel.understanding.deterministic.understand(decision);
        case PlanningFailureKind.permissionDenied:
        case PlanningFailureKind.persistenceFailure:
        case PlanningFailureKind.recoverablePlanning:
        case PlanningFailureKind.unexpected:
          // These mean something is genuinely broken or refused.
          // Proceeding on a guess would hide it.
          _mutate(() {
            error = runtime.redactor.redact(
              'I could not read your request safely: ${failure.message} '
              '(${failure.code})',
            );
            status = 'Kristin needs your help';
          });
          return null;
      }
    } finally {
      _mutate(() => busy = false);
    }
  }

  /// The canonical tasks this run has actually finished, with their
  /// evidence, keyed by semantic identity so a replan recognizes the same
  /// work even when the new plan assigns it a different generated id.
  List<CompletedTaskRecord> _completedTasksFrom(RunRecord run) {
    final plan = canonicalPlan;
    if (plan == null) return const <CompletedTaskRecord>[];
    final byId = <String, UniversalTask>{
      for (final task in plan.tasks) task.id: task,
    };
    final completed = <CompletedTaskRecord>[];
    for (final progress in run.items) {
      if (progress.state != WorkItemState.succeeded) continue;
      final task = byId[progress.item.id];
      if (task == null) continue;
      completed.add(
        CompletedTaskRecord.of(
          task,
          evidence: <String, dynamic>{
            'runId': run.id,
            'attempts': progress.attempts,
            if (progress.completedAt != null)
              'completedAt': progress.completedAt!.toIso8601String(),
          },
        ),
      );
    }
    return List<CompletedTaskRecord>.unmodifiable(completed);
  }

  bool _isActiveRunCancellation(
    String request,
    ChatInteractionDecision decision,
  ) {
    if (decision.explicitCommand) return false;
    final value = request.trim().toLowerCase();
    return RegExp(
            r'^(?:please\s+)?(?:stop|cancel|abort)(?:\s+(?:this|the|current))?(?:\s+(?:task|run|work))?[.!]?$')
        .hasMatch(value);
  }

  String _pendingRunMessage() {
    final goal = activeRequest.trim();
    final about = goal.isEmpty ? 'the current task' : '"$goal"';
    if (currentRun?.state == RunState.awaitingApproval) {
      return 'There is a pending permission decision on $about. Approve or '
          'decline it above, or tell me what to change, before I start '
          'something else.';
    }
    return 'There is unfinished work on $about waiting to be resumed or '
        'stopped. Use Resume or Stop above, or tell me what to change, '
        'before I start something else.';
  }

  void _archiveFinishedRun() {
    final run = currentRun;
    if (run == null || !runTerminal) return;
    final text = _resultText(run);
    if (text.trim().isNotEmpty) transcript.add(_ChatLine.assistant(text));
    pendingDecision = null;
    understandingHistory = null;
    prepared = null;
    currentRun = null;
    awaitingPermission = false;
    activeRequest = '';
    liveSignals.clear();
    liveAssistantProtocolText = '';
    liveAssistantText = '';
    liveProgressText = '';
    liveToolName = '';
    liveToolOutput = '';
  }

  String _resultText(RunRecord run) {
    if (run.summary.trim().isNotEmpty) return run.summary.trim();
    if (run.failure?.trim().isNotEmpty == true) return run.failure!.trim();
    return switch (run.state) {
      RunState.succeeded => 'The task completed successfully.',
      RunState.cancelled => 'The task stopped safely.',
      RunState.failed => 'The task needs attention.',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) => _buildStudio();
}

class _StudioInteractionPolicy extends ChatInteractionPolicy {
  const _StudioInteractionPolicy();

  @override
  bool needsPlan(
    KristinCapability capability,
    ParsedChatInput parsed, {
    required bool naturalLanguage,
  }) {
    if (capability.actionClass == ChatActionClass.substantial) return true;
    return super.needsPlan(
      capability,
      parsed,
      naturalLanguage: naturalLanguage,
    );
  }
}

class _ChatLine {
  const _ChatLine({required this.assistant, required this.text});

  factory _ChatLine.user(String text) =>
      _ChatLine(assistant: false, text: text);
  factory _ChatLine.assistant(String text) =>
      _ChatLine(assistant: true, text: text);

  final bool assistant;
  final String text;
}

String _slug(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9._:-]+'), '-')
    .replaceAll(RegExp(r'-+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');
