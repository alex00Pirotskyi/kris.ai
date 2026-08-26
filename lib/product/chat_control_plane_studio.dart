import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_server.dart';
import 'capability_doctor.dart';
import 'chat_control_plane.dart';
import 'chat_studio.dart';
import 'conversation_orchestrator.dart';
import 'domain.dart';
import 'models_research.dart';
import 'product_error_normalizer.dart';
import 'product_runtime.dart';
import 'run_live_signals.dart';
import 'ui_advanced.dart';
import 'ui_components.dart';

part 'chat_control_plane_studio_actions.dart';
part 'chat_control_plane_studio_view.dart';

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
  final TextEditingController planAdjustmentController = TextEditingController();
  final FocusNode composerFocus = FocusNode();

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
  bool awaitingPermission = false;
  bool detailsExpanded = false;
  String status = 'Kristin is ready';
  String? error;

  List<ProjectRecord> projects = <ProjectRecord>[];
  List<ModelIdentity> models = <ModelIdentity>[];
  List<RunRecord> runs = <RunRecord>[];
  List<EvidenceRecord> evidence = <EvidenceRecord>[];
  String? selectedProjectId;
  String? selectedModelId;
  ProjectProcessStatus? projectProcessStatus;

  ChatInteractionDecision? pendingDecision;
  UnderstandingHistory? understandingHistory;
  PreparedCommand? prepared;
  RunRecord? currentRun;
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

  ProjectRecord? get selectedProject => projects
      .where((project) => project.id == selectedProjectId)
      .firstOrNull;

  ModelIdentity? get selectedModel =>
      models.where((model) => model.exactId == selectedModelId).firstOrNull;

  bool get runAwaitingApproval =>
      currentRun?.state == RunState.awaitingApproval;

  bool get runActive => currentRun != null &&
      const <RunState>{
        RunState.running,
        RunState.paused,
        RunState.cancelling,
        RunState.interrupted,
      }.contains(currentRun!.state);

  bool get runTerminal => currentRun != null &&
      const <RunState>{
        RunState.succeeded,
        RunState.failed,
        RunState.cancelled,
      }.contains(currentRun!.state);

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
        return const <RunState>{
          RunState.awaitingApproval,
          RunState.running,
          RunState.paused,
          RunState.interrupted,
        }.contains(run.state);
      }).firstOrNull;
      if (durable != null) {
        currentRun = durable;
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
      status = runAwaitingApproval
          ? 'Permission review required'
          : runActive
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
    final loadedEvidence = newTerminal
        ? await runtime.evidenceForRun(refreshed.id)
        : evidence;
    _mutate(() {
      currentRun = refreshed;
      evidence = loadedEvidence;
      awaitingPermission = refreshed.state == RunState.awaitingApproval;
      if (newTerminal) {
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

  List<ChatTarget> _knownTargets() {
    final targets = <ChatTarget>[];
    for (final project in projects) {
      targets.add(
        ChatTarget(
          id: project.id,
          type: ChatTargetType.project,
          displayName: project.name,
          aliases: <String>[_slug(project.name), project.id],
          description: 'Project',
          status: project.id == selectedProjectId ? 'Selected project' : 'Project',
        ),
      );
    }
    for (final model in models) {
      targets.add(
        ChatTarget(
          id: model.exactId,
          type: ChatTargetType.model,
          displayName: model.name,
          aliases: <String>[
            _slug(model.name),
            model.name.toLowerCase(),
            model.exactId,
          ],
          description: model.providerId,
          status: model.exactId == selectedModelId
              ? 'Selected model'
              : 'Available model',
        ),
      );
    }
    final providerIds = runtime.models.providers().map((item) => item.id).toSet();
    targets.addAll(<ChatTarget>[
      ChatTarget(
        id: 'ollama',
        type: ChatTargetType.provider,
        displayName: 'Ollama',
        aliases: const <String>['ollama'],
        description: 'Local model provider',
        status: providerIds.contains('ollama') ? 'Configured' : 'Not configured',
        available: providerIds.contains('ollama'),
      ),
      ChatTarget(
        id: 'openai-compatible',
        type: ChatTargetType.provider,
        displayName: 'OpenAI-compatible',
        aliases: const <String>['openai', 'openai-compatible'],
        description: 'OpenAI-compatible model provider',
        status: providerIds.contains('openai-compatible')
            ? 'Configured'
            : 'Not connected',
        available: providerIds.contains('openai-compatible'),
      ),
      const ChatTarget(
        id: 'webstudio',
        type: ChatTargetType.workspace,
        displayName: 'Web Studio',
        aliases: <String>['webstudio'],
        description: 'Web deep-dive workspace',
      ),
      const ChatTarget(
        id: 'web',
        type: ChatTargetType.workspace,
        displayName: 'Web',
        aliases: <String>['web'],
        description: 'Public-source research',
      ),
      const ChatTarget(
        id: 'owner',
        type: ChatTargetType.capability,
        displayName: 'Owner Mode',
        aliases: <String>['owner'],
        description: 'Governed elevated execution mode',
      ),
      const ChatTarget(
        id: 'project-manager',
        type: ChatTargetType.workspace,
        displayName: 'Project Manager',
        aliases: <String>['project-manager'],
        description: 'Persistent deep project controls',
      ),
    ]);
    return targets;
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
        selection: TextSelection.collapsed(offset: suggestion.insertText.length),
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

    if (runActive) {
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
    if (decision.isInformational) {
      await _answerInformational(decision);
      return;
    }

    _mutate(() {
      activeRequest = request;
      pendingDecision = decision;
      understandingHistory = UnderstandingHistory.initial(decision);
      prepared = null;
      currentRun = null;
      awaitingPermission = false;
      understandingAdjusting = false;
      planAdjusting = false;
      detailsExpanded = false;
      error = null;
      status = 'Review what Kristin understood';
    });
  }

  bool _isActiveRunCancellation(
    String request,
    ChatInteractionDecision decision,
  ) {
    if (decision.explicitCommand) return false;
    final value = request.trim().toLowerCase();
    return RegExp(
      r'^(?:please\s+)?(?:stop|cancel|abort)(?:\s+(?:this|the|current))?(?:\s+(?:task|run|work))?[.!]?$'
    ).hasMatch(value);
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

  factory _ChatLine.user(String text) => _ChatLine(assistant: false, text: text);
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
