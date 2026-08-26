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
  final ChatIntentCompiler intentCompiler = const ChatIntentCompiler();
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
  bool currentRunIsInformational = false;
  String liveAssistantProtocolText = '';
  String liveAssistantText = '';
  String liveProgressText = '';
  String liveToolName = '';
  String liveToolOutput = '';

  List<ChatAutocompleteSuggestion> suggestions =
      const <ChatAutocompleteSuggestion>[];
  int suggestionIndex = 0;

  ProductRuntime get runtime => widget.runtime;

  ProjectRecord? get selectedProject {
    for (final project in projects) {
      if (project.id == selectedProjectId) return project;
    }
    return null;
  }

  ModelIdentity? get selectedModel {
    for (final model in models) {
      if (model.exactId == selectedModelId) return model;
    }
    return null;
  }

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
      if (runActive) {
        unawaited(_refreshCurrentRun());
      }
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

  Future<T?> _perform<T>(
    String activity,
    Future<T> Function() action, {
    bool silent = false,
  }) async {
    if (!silent && mounted) {
      setState(() {
        busy = true;
        status = activity;
        error = null;
      });
    }
    try {
      return await action();
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = runtime.redactor.redact(
            ProductErrorNormalizer.userMessage(failure),
          );
          status = 'Kristin needs your help';
        });
      }
      return null;
    } finally {
      if (!silent && mounted) {
        setState(() => busy = false);
      }
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
        currentRunIsInformational = durable.command.contract.mode == CommandMode.ask;
        evidence = await runtime.evidenceForRun(durable.id);
        awaitingPermission = durable.state == RunState.awaitingApproval;
      }
      if (selectedProjectId != null) {
        projectProcessStatus =
            await runtime.projectProcessStatus(selectedProjectId!);
      }
    });
    if (mounted) {
      setState(() {
        loading = false;
        status = runActive ? 'Continuing active work' : 'Kristin is ready';
      });
    }
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
    final wasTerminal = runTerminal;
    final newTerminal = const <RunState>{
      RunState.succeeded,
      RunState.failed,
      RunState.cancelled,
    }.contains(refreshed.state);
    final loadedEvidence = newTerminal
        ? await runtime.evidenceForRun(refreshed.id)
        : evidence;
    if (!mounted) return;
    setState(() {
      currentRun = refreshed;
      evidence = loadedEvidence;
      if (!wasTerminal && newTerminal) {
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
    if (mounted && selectedProjectId == projectId) {
      setState(() => projectProcessStatus = process);
    }
  }

  void _onLiveSignal(LiveRunSignal signal) {
    if (!mounted || signal.runId != currentRun?.id) return;
    setState(() {
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
          liveAssistantText = currentRunIsInformational
              ? ConversationStreamProjector.visibleText(
                  liveAssistantProtocolText,
                )
              : '';
        case LiveRunSignalKind.modelProgress:
        case LiveRunSignalKind.phase:
        case LiveRunSignalKind.preflight:
          liveProgressText = signal.data['message']?.toString() ?? '';
        case LiveRunSignalKind.toolStarted:
          liveToolName = signal.data['tool']?.toString() ?? 'tool';
          liveToolOutput = '';
        case LiveRunSignalKind.toolOutput:
          liveToolName = signal.data['tool']?.toString() ?? liveToolName;
          final delta = signal.data['delta']?.toString() ?? '';
          liveToolOutput = '$liveToolOutput$delta';
          if (liveToolOutput.length > 12000) {
            liveToolOutput =
                liveToolOutput.substring(liveToolOutput.length - 12000);
          }
        case LiveRunSignalKind.toolCompleted:
          liveToolName = signal.data['tool']?.toString() ?? liveToolName;
          final output = signal.data['output']?.toString() ?? '';
          if (output.isNotEmpty) liveToolOutput = output;
        case LiveRunSignalKind.toolFailed:
          liveToolName = signal.data['tool']?.toString() ?? liveToolName;
          liveToolOutput = signal.data['detail']?.toString() ?? '';
        case LiveRunSignalKind.steeringQueued:
          liveProgressText = 'Your new direction is queued for the next safe step.';
        case LiveRunSignalKind.steeringApplied:
          liveProgressText = 'Your new direction was applied.';
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
    setState(() {
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
      final next = '${text.substring(0, match.start)}$replacement${text.substring(cursor)}';
      composerController.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(
          offset: match.start + replacement.length,
        ),
      );
    }
    setState(() {
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

    if (runActive) {
      final steeringDecision = intentCompiler.compile(
        request,
        inferredMode: resolveTaskMode(
          request: request,
          choice: SimpleTaskMode.auto,
          chosenMode: CommandMode.build,
        ),
        knownTargets: _knownTargets(),
      );
      if (!steeringDecision.isInformational) {
        transcript.add(_ChatLine.user(request));
        composerController.clear();
        final steered = await _perform<dynamic>(
          'Applying your direction',
          () => runtime.steerRun(currentRun!.id, request),
        );
        if (steered != null && mounted) {
          setState(() {
            liveProgressText = 'Your new direction is queued for the next safe step.';
          });
        }
        return;
      }
    }

    _archiveFinishedRun();
    transcript.add(_ChatLine.user(request));
    composerController.clear();
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

    if (decision.capability?.understandingPolicy ==
        ChatUnderstandingPolicy.never) {
      await _handleImmediateCapability(decision);
      return;
    }
    if (decision.isInformational) {
      await _answerInformational(decision);
      return;
    }

    setState(() {
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
      status = 'Reviewing what you asked me to do';
    });
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
    liveSignals.clear();
    liveAssistantProtocolText = '';
    liveAssistantText = '';
    liveProgressText = '';
    liveToolName = '';
    liveToolOutput = '';
  }

  Future<void> _handleImmediateCapability(
    ChatInteractionDecision decision,
  ) async {
    final id = decision.capability?.id;
    switch (id) {
      case 'new_chat':
        _newChat();
      case 'help':
        setState(() {
          transcript.add(
            _ChatLine.assistant(
              'I can build, fix, analyze, search, test, verify, run, stop, and operate projects from Chat. Try `/build`, `/search`, `/run @project`, `/verify @project`, or type `@` to reference a project, model, provider, or workspace.',
            ),
          );
        });
      case 'projects':
      case 'runs':
      case 'prompts':
      case 'knowledge':
      case 'logs':
        await _openAdvanced();
      default:
        await _answerInformational(decision);
    }
  }

  Future<void> _answerInformational(
    ChatInteractionDecision decision,
  ) async {
    final local = await _tryLocalAnswer(decision);
    if (local != null) {
      if (mounted) {
        setState(() {
          transcript.add(_ChatLine.assistant(local));
          status = 'Kristin is ready';
        });
      }
      return;
    }
    var model = selectedModel;
    if (model == null) {
      await _openSettings(initialSection: 1);
      model = selectedModel;
    }
    if (model == null) {
      _showError('Connect an AI model so Kristin can answer this question.');
      return;
    }
    final recentContext = _informationalContext();
    final result = await _perform<ModelGenerationResult>(
      'Answering',
      () => runtime.models.providerFor(model!).generate(
            ModelGenerationRequest(
              identity: model!,
              commandId: newId('chat_info'),
              systemPrompt:
                  'You are Kristin. Answer the user as a normal conversational assistant. This request is informational only: do not claim to execute tools, change files, start processes, or grant permissions. Be concise and useful. Return one JSON object with exactly one string field named "answer" and no markdown fence.',
              userPrompt: recentContext.isEmpty
                  ? decision.parsed.originalText
                  : '${decision.parsed.originalText}\n\nAvailable local status context:\n$recentContext',
              temperature: 0.2,
              maxOutputTokens: 1600,
              firstTokenTimeout: const Duration(minutes: 2),
              totalTimeout: const Duration(minutes: 4),
            ),
          ),
    );
    if (result == null || !mounted) return;
    var visible = ConversationStreamProjector.visibleText(result.text).trim();
    if (visible.isEmpty) {
      try {
        final decoded = jsonDecode(result.text);
        if (decoded is Map && decoded['answer'] is String) {
          visible = decoded['answer'].toString().trim();
        }
      } catch (_) {
        visible = result.text.trim();
      }
    }
    setState(() {
      transcript.add(_ChatLine.assistant(visible));
      status = 'Kristin is ready';
    });
  }

  String _informationalContext() {
    final buffer = StringBuffer();
    final project = selectedProject;
    if (project != null) buffer.writeln('Selected project: ${project.name}');
    final process = projectProcessStatus;
    if (process != null) {
      buffer.writeln(
        'Project process: ${process.running ? 'running' : 'not running'}${process.exitCode == null ? '' : ', last exit ${process.exitCode}'}.',
      );
    }
    final recent = runs.where((run) {
      return selectedProjectId == null ||
          run.command.contract.projectId == selectedProjectId;
    }).take(3);
    for (final run in recent) {
      buffer.writeln(
        'Recent run: ${run.command.contract.request} — ${run.state.name}${run.summary.trim().isEmpty ? '' : ': ${run.summary.trim()}'}',
      );
    }
    return buffer.toString().trim();
  }

  Future<String?> _tryLocalAnswer(ChatInteractionDecision decision) async {
    final text = decision.parsed.originalText.toLowerCase();
    final projectTarget = decision.targets
        .where((target) => target.type == ChatTargetType.project)
        .firstOrNull;
    if (projectTarget != null &&
        RegExp(r'\b(running|status|started|stopped|active)\b').hasMatch(text)) {
      final process = await runtime.projectProcessStatus(projectTarget.id);
      final project = projects
          .where((item) => item.id == projectTarget.id)
          .firstOrNull;
      final name = project?.name ?? projectTarget.displayName;
      if (process?.running == true) return '$name is running.';
      return '$name is not currently running.';
    }
    final providerTarget = decision.targets
        .where((target) => target.type == ChatTargetType.provider)
        .firstOrNull;
    if (providerTarget != null &&
        RegExp(r'\b(connected|configured|available|status)\b').hasMatch(text)) {
      return '${providerTarget.displayName}: ${providerTarget.status}.';
    }
    final modelTarget = decision.targets
        .where((target) => target.type == ChatTargetType.model)
        .firstOrNull;
    if (modelTarget != null &&
        RegExp(r'\b(available|connected|selected|status)\b').hasMatch(text)) {
      return '${modelTarget.displayName} is available${modelTarget.id == selectedModelId ? ' and selected' : ''}.';
    }
    if (text.contains('@owner')) {
      final owner = runtime.p2OwnerMode;
      return 'Owner Mode status: ${owner.statusCode}. It remains governed and is never enabled by mentioning it.';
    }
    return null;
  }

  Future<void> _continueUnderstanding() async {
    final decision = pendingDecision;
    final history = understandingHistory;
    if (decision == null || history == null) return;
    if (decision.unresolvedMentions.isNotEmpty) {
      _showError(
        'I cannot resolve ${decision.unresolvedMentions.map((value) => '@$value').join(', ')}. Adjust the request or choose a known target.',
      );
      return;
    }
    _applyDecisionTargets(decision);
    final capability = decision.capability;
    if (capability == null) {
      _showError('I need a clearer action before I can execute safely.');
      return;
    }
    if (decision.needsPlan) {
      await _preparePlan(history.current.acceptedRequest, decision);
      return;
    }
    await _executeSmallAction(decision, history.current.acceptedRequest);
  }

  void _applyDecisionTargets(ChatInteractionDecision decision) {
    final project = decision.targets
        .where((target) => target.type == ChatTargetType.project)
        .firstOrNull;
    if (project != null && projects.any((item) => item.id == project.id)) {
      selectedProjectId = project.id;
    }
    final model = decision.targets
        .where((target) => target.type == ChatTargetType.model)
        .firstOrNull;
    if (model != null && models.any((item) => item.exactId == model.id)) {
      selectedModelId = model.id;
    }
  }

  Future<void> _preparePlan(
    String request,
    ChatInteractionDecision decision,
  ) async {
    var project = selectedProject;
    if (project == null && decision.capability?.id == 'build') {
      project = await _perform<ProjectRecord>(
        'Creating the project workspace',
        () => runtime.provisionProjectForRequest(
          request: pendingDecision?.parsed.originalText ?? request,
        ),
      );
      if (project == null) return;
      projects = await runtime.listProjects();
      selectedProjectId = project.id;
    }
    if (project == null) {
      _showError('Choose or mention a project for this action.');
      return;
    }
    var model = selectedModel;
    if (model == null) {
      await _openSettings(initialSection: 1);
      model = selectedModel;
    }
    if (model == null) {
      _showError('Connect an AI model before Kristin creates the execution plan.');
      return;
    }
    final result = await _perform<PreparedCommand>(
      'Creating the execution plan',
      () => runtime.prepare(
        projectId: project!.id,
        mode: decision.mode,
        request: request,
        model: model!,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      prepared = result;
      pendingDecision = decision;
      awaitingPermission = false;
      planAdjusting = false;
      status = 'Plan ready for review';
    });
  }

  Future<void> _executeSmallAction(
    ChatInteractionDecision decision,
    String request,
  ) async {
    final capability = decision.capability;
    if (capability == null) return;
    final project = selectedProject;
    switch (capability.route) {
      case ChatExecutionRoute.projectAnalyze:
        if (project == null) return _showProjectNeeded();
        final report = await _perform<ProjectDiagnosticReport>(
          'Analyzing ${project.name}',
          () => runtime.analyzeProject(project.id),
        );
        if (report != null) _finishDirectAction(_diagnosticSummary('Analysis', report));
      case ChatExecutionRoute.projectTest:
        if (project == null) return _showProjectNeeded();
        final report = await _perform<ProjectDiagnosticReport>(
          'Testing ${project.name}',
          () => runtime.testProject(project.id),
        );
        if (report != null) _finishDirectAction(_diagnosticSummary('Tests', report));
      case ChatExecutionRoute.projectVerify:
        if (project == null) return _showProjectNeeded();
        final report = await _perform<ProjectDiagnosticReport>(
          'Verifying ${project.name}',
          () => runtime.testProject(project.id),
        );
        if (report != null) {
          _finishDirectAction(_diagnosticSummary('Verification', report));
        }
      case ChatExecutionRoute.projectBuild:
        if (project == null) return _showProjectNeeded();
        final report = await _perform<ProjectDiagnosticReport>(
          'Building ${project.name}',
          () => runtime.buildProject(project.id),
        );
        if (report != null) _finishDirectAction(_diagnosticSummary('Build', report));
      case ChatExecutionRoute.projectRun:
        if (project == null) return _showProjectNeeded();
        final process = await _perform<ProjectProcessStatus>(
          'Starting ${project.name}',
          () => runtime.startProject(project.id),
        );
        if (process != null) {
          projectProcessStatus = process;
          _finishDirectAction('${project.name} is running.');
        }
      case ChatExecutionRoute.projectStop:
        if (project == null) return _showProjectNeeded();
        final process = await _perform<ProjectProcessStatus?>(
          'Stopping ${project.name}',
          () => runtime.stopProject(project.id),
        );
        projectProcessStatus = process;
        _finishDirectAction('${project.name} is stopped.');
      case ChatExecutionRoute.projectRestart:
        if (project == null) return _showProjectNeeded();
        await _perform<ProjectProcessStatus?>(
          'Restarting ${project.name}',
          () async {
            await runtime.stopProject(project.id);
            return runtime.startProject(project.id);
          },
        ).then((process) {
          if (process != null) {
            projectProcessStatus = process;
            _finishDirectAction('${project.name} restarted and is running.');
          }
        });
      case ChatExecutionRoute.connectProvider:
        await _openSettings(initialSection: 1);
        _finishDirectAction('Provider settings are ready.');
      case ChatExecutionRoute.selectModel:
        final modelTarget = decision.targets
            .where((target) => target.type == ChatTargetType.model)
            .firstOrNull;
        if (modelTarget == null) {
          _showError('Mention the model you want to use, for example `/use @phi4-mini`.');
          return;
        }
        if (!models.any((model) => model.exactId == modelTarget.id)) {
          _showError('${modelTarget.displayName} is not currently available.');
          return;
        }
        setState(() => selectedModelId = modelTarget.id);
        _finishDirectAction('${modelTarget.displayName} will be used for the next eligible task.');
      case ChatExecutionRoute.ownerMode:
        await _openSettings();
        _finishDirectAction(
          'Owner Mode settings opened. Mentioning or confirming this action did not grant any new authority by itself.',
        );
      case ChatExecutionRoute.diagnose:
        final report = await _perform<CapabilityDoctorReport>(
          'Checking Kristin readiness',
          () => runtime.inspectCapabilities(
            projectId: selectedProjectId,
            depth: CapabilityDoctorDepth.full,
            discoveredModels: models,
          ),
        );
        if (report != null) {
          _finishDirectAction(
            report.coreReady
                ? 'Kristin readiness is healthy: ${report.readyCount}/${report.checks.length} checks ready.'
                : 'Kristin readiness needs attention: ${report.readyCount}/${report.checks.length} checks ready.',
          );
        }
      case ChatExecutionRoute.open:
        await _openAdvanced();
        _finishDirectAction('Opened the advanced workspace.');
      case ChatExecutionRoute.agent:
        await _prepareAgentAction(request, decision);
      case ChatExecutionRoute.navigation:
      case ChatExecutionRoute.help:
        await _handleImmediateCapability(decision);
    }
  }

  void _showProjectNeeded() {
    _showError('Choose or mention a project for this action.');
  }

  String _diagnosticSummary(String label, ProjectDiagnosticReport report) {
    final result = report.failed == 0 ? 'passed' : 'needs attention';
    return '$label $result: ${report.passed} passed, ${report.warnings} warnings, ${report.failed} failed.';
  }

  void _finishDirectAction(String message) {
    if (!mounted) return;
    setState(() {
      transcript.add(_ChatLine.assistant(message));
      pendingDecision = null;
      understandingHistory = null;
      prepared = null;
      awaitingPermission = false;
      activeRequest = '';
      status = 'Kristin is ready';
    });
  }

  Future<void> _prepareAgentAction(
    String request,
    ChatInteractionDecision decision,
  ) async {
    final project = selectedProject;
    if (project == null) {
      _showProjectNeeded();
      return;
    }
    var model = selectedModel;
    if (model == null) {
      await _openSettings(initialSection: 1);
      model = selectedModel;
    }
    if (model == null) {
      _showError('Connect an AI model before Kristin runs this action.');
      return;
    }
    var governedRequest = request;
    if (decision.capability?.id == 'search') {
      final query = decision.parsed.arguments
          .replaceAll(RegExp(r'@[A-Za-z0-9][A-Za-z0-9._:-]*'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      governedRequest =
          'Search current public sources for this request and return grounded findings with source provenance: ${query.isEmpty ? request : query}';
    }
    final command = await _perform<PreparedCommand>(
      'Preparing the action',
      () => runtime.prepare(
        projectId: project.id,
        mode: decision.mode,
        request: governedRequest,
        model: model!,
      ),
    );
    if (command == null || !mounted) return;
    setState(() {
      prepared = command;
      activeRequest = request;
      pendingDecision = decision;
      awaitingPermission = command.contract.requiredPermissions.isNotEmpty;
      status = awaitingPermission ? 'Permission review required' : 'Starting';
    });
    if (!awaitingPermission) await _startPrepared();
  }

  Future<void> _startPlan() async {
    final command = prepared;
    if (command == null) return;
    if (command.contract.requiredPermissions.isNotEmpty) {
      setState(() {
        awaitingPermission = true;
        status = 'Permission review required';
      });
      return;
    }
    await _startPrepared();
  }

  Future<void> _approvePermissions() async {
    if (prepared == null) return;
    setState(() => awaitingPermission = false);
    await _startPrepared();
  }

  Future<void> _startPrepared() async {
    final command = prepared;
    if (command == null) return;
    final run = await _perform<RunRecord>('Starting execution', () async {
      final created = await runtime.createRun(command.id);
      await runtime.approve(
        runId: created.id,
        scopes: Set<PermissionScope>.from(
          command.contract.requiredPermissions,
        ),
      );
      unawaited(runtime.execute(created.id));
      await Future<void>.delayed(const Duration(milliseconds: 180));
      return await runtime.getRun(created.id) ?? created;
    });
    if (run == null || !mounted) return;
    setState(() {
      currentRun = run;
      currentRunIsInformational = false;
      awaitingPermission = false;
      liveSignals.clear();
      liveAssistantProtocolText = '';
      liveAssistantText = '';
      liveProgressText = 'Starting the first safe step.';
      liveToolName = '';
      liveToolOutput = '';
      status = 'Kristin is working';
    });
  }

  Future<void> _adjustUnderstanding() async {
    final history = understandingHistory;
    final value = understandingAdjustmentController.text.trim();
    if (history == null || value.isEmpty) return;
    final revisedRequest = '${history.current.originalRequest}\n\nAdjustment: $value';
    final mode = resolveTaskMode(
      request: revisedRequest,
      choice: SimpleTaskMode.auto,
      chosenMode: CommandMode.build,
    );
    final revisedDecision = intentCompiler.compile(
      revisedRequest,
      inferredMode: mode,
      knownTargets: _knownTargets(),
    );
    setState(() {
      understandingHistory = history.adjust(value);
      pendingDecision = revisedDecision;
      understandingAdjustmentController.clear();
      understandingAdjusting = false;
      status = 'Understanding updated';
    });
  }

  void _tryAnotherInterpretation() {
    final history = understandingHistory;
    final decision = pendingDecision;
    if (history == null || decision == null) return;
    setState(() {
      understandingHistory = history.alternate(decision);
      status = 'Showing another interpretation of the same request';
    });
  }

  Future<void> _adjustPlan() async {
    final command = prepared;
    final decision = pendingDecision;
    final history = understandingHistory;
    final adjustment = planAdjustmentController.text.trim();
    if (command == null || decision == null || history == null || adjustment.isEmpty) {
      return;
    }
    final request =
        '${history.current.acceptedRequest}\n\nPlan adjustment: $adjustment';
    planAdjustmentController.clear();
    setState(() => planAdjusting = false);
    await _preparePlan(request, decision);
  }

  Future<void> _controlRun(String action) async {
    final run = currentRun;
    if (run == null) return;
    await _perform<void>(
      action == 'pause'
          ? 'Pausing'
          : action == 'resume'
              ? 'Resuming'
              : 'Stopping',
      () async {
        if (action == 'pause') {
          await runtime.pause(run.id);
        } else if (action == 'resume') {
          await runtime.resume(run.id);
        } else {
          await runtime.cancel(run.id);
        }
      },
    );
    await _refreshCurrentRun();
  }

  Future<void> _stopManagedProject() async {
    final project = selectedProject;
    if (project == null) return;
    final process = await _perform<ProjectProcessStatus?>(
      'Stopping ${project.name}',
      () => runtime.stopProject(project.id),
    );
    if (mounted) {
      setState(() {
        projectProcessStatus = process;
        status = '${project.name} stopped';
      });
    }
  }

  Future<void> _openAdvanced() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => ChatStudio(
          runtime: runtime,
          api: widget.api,
          startupError: widget.startupError,
        ),
      ),
    );
    await _reloadSelections();
  }

  Future<void> _openSettings({int initialSection = 0}) async {
    final result = await Navigator.of(context).push<AdvancedSettingsResult>(
      MaterialPageRoute<AdvancedSettingsResult>(
        builder: (context) => AdvancedSettingsPage(
          runtime: runtime,
          api: widget.api,
          startupError: widget.startupError,
          initialProjectId: selectedProjectId,
          initialModelId: selectedModelId,
          initialSection: initialSection,
        ),
      ),
    );
    await _reloadSelections(result: result);
  }

  Future<void> _reloadSelections({AdvancedSettingsResult? result}) async {
    final newProjects = await runtime.listProjects();
    final newModels = await runtime.discoverModels();
    if (!mounted) return;
    setState(() {
      projects = newProjects;
      models = newModels;
      if (result != null &&
          newProjects.any((item) => item.id == result.projectId)) {
        selectedProjectId = result.projectId;
      } else if (!newProjects.any((item) => item.id == selectedProjectId)) {
        selectedProjectId = newProjects.firstOrNull?.id;
      }
      if (result != null && newModels.any((item) => item.exactId == result.modelId)) {
        selectedModelId = result.modelId;
      } else if (!newModels.any((item) => item.exactId == selectedModelId)) {
        selectedModelId = newModels.firstOrNull?.exactId;
      }
    });
    await _refreshProjectProcess();
  }

  void _newChat() {
    setState(() {
      transcript.clear();
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
      suggestions = const <ChatAutocompleteSuggestion>[];
      understandingAdjusting = false;
      planAdjusting = false;
      detailsExpanded = false;
      error = null;
      status = 'New chat ready';
      composerController.clear();
    });
    composerFocus.requestFocus();
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      error = message;
      status = 'Kristin needs your help';
    });
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.auto_awesome),
            SizedBox(width: 9),
            Text('Kristin'),
          ],
        ),
        actions: <Widget>[
          if (selectedProject != null)
            _headerChip(Icons.folder_outlined, selectedProject!.name),
          if (selectedModel != null)
            _headerChip(Icons.memory_outlined, selectedModel!.name),
          IconButton(
            tooltip: 'Advanced workspaces',
            onPressed: busy ? null : _openAdvanced,
            icon: const Icon(Icons.dashboard_customize_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: busy ? null : _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                _statusStrip(),
                Expanded(
                  child: SelectionArea(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                      children: <Widget>[
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 860),
                            child: _conversation(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _composer(),
              ],
            ),
    );
  }

  Widget _headerChip(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Chip(
        avatar: Icon(icon, size: 16),
        label: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 150),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _statusStrip() {
    final startup = widget.startupError;
    if (startup == null && error == null && !busy && !runActive) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    final failing = startup != null || error != null;
    return Material(
      color: failing ? colors.errorContainer : colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Row(
          children: <Widget>[
            if (busy || runActive)
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(failing ? Icons.error_outline : Icons.info_outline, size: 18),
            const SizedBox(width: 9),
            Expanded(child: Text(startup ?? error ?? status)),
            if (error != null)
              IconButton(
                tooltip: 'Dismiss',
                onPressed: () => setState(() => error = null),
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }

  Widget _conversation() {
    final children = <Widget>[];
    if (transcript.isEmpty &&
        pendingDecision == null &&
        currentRun == null &&
        prepared == null) {
      children.add(_welcome());
    }
    for (final line in transcript) {
      children.add(_messageBubble(line));
      children.add(const SizedBox(height: 14));
    }
    if (understandingHistory != null && prepared == null && currentRun == null) {
      children.add(_understandingCard());
      children.add(const SizedBox(height: 14));
    }
    if (prepared != null && currentRun == null) {
      if (awaitingPermission) {
        children.add(_permissionCard());
      } else {
        children.add(_planCard());
      }
      children.add(const SizedBox(height: 14));
    }
    if (currentRun != null) {
      children.add(_runCard(currentRun!));
      if (runTerminal) ...<Widget>[
        const SizedBox(height: 14),
        children.add(_resultCard(currentRun!)),
      ];
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _welcome() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 70),
      child: Column(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              Icons.auto_awesome,
              size: 30,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'What can I help you with?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
          ),
          const SizedBox(height: 9),
          Text(
            'Ask normally, type / for actions, or use @ to reference a project, model, provider, or workspace.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            alignment: WrapAlignment.center,
            children: <Widget>[
              ActionChip(
                avatar: const Icon(Icons.build_outlined, size: 18),
                label: const Text('/build'),
                onPressed: () => _seedComposer('/build '),
              ),
              ActionChip(
                avatar: const Icon(Icons.search, size: 18),
                label: const Text('/search'),
                onPressed: () => _seedComposer('/search '),
              ),
              ActionChip(
                avatar: const Icon(Icons.play_arrow, size: 18),
                label: const Text('/run @'),
                onPressed: () => _seedComposer('/run @'),
              ),
              ActionChip(
                avatar: const Icon(Icons.verified_outlined, size: 18),
                label: const Text('/verify @'),
                onPressed: () => _seedComposer('/verify @'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _seedComposer(String value) {
    composerController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _updateSuggestions();
    composerFocus.requestFocus();
  }

  Widget _messageBubble(_ChatLine line) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment:
          line.assistant ? MainAxisAlignment.start : MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (line.assistant) ...<Widget>[
          CircleAvatar(
            radius: 16,
            backgroundColor: colors.primaryContainer,
            child: Icon(
              Icons.auto_awesome,
              size: 16,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 9),
        ],
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 700),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: line.assistant
                  ? colors.surfaceContainerLow
                  : colors.primaryContainer,
              borderRadius: BorderRadius.circular(17),
              border: line.assistant
                  ? Border.all(color: colors.outlineVariant)
                  : null,
            ),
            child: SelectableText(line.text),
          ),
        ),
      ],
    );
  }

  Widget _understandingCard() {
    final history = understandingHistory!;
    final decision = pendingDecision!;
    final draft = history.current;
    return _assistantCard(
      icon: Icons.psychology_alt_outlined,
      title: 'I understood:',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(draft.summary),
          if (decision.ambiguous) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              decision.unresolvedMentions.isEmpty
                  ? 'I can use the currently selected context, or you can adjust this interpretation.'
                  : 'I still need a valid target for ${decision.unresolvedMentions.map((value) => '@$value').join(', ')}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (understandingAdjusting) ...<Widget>[
            const SizedBox(height: 14),
            TextField(
              controller: understandingAdjustmentController,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'What should I change?',
              ),
              onSubmitted: (_) => _adjustUnderstanding(),
            ),
            const SizedBox(height: 9),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: busy ? null : _adjustUnderstanding,
                child: const Text('Update understanding'),
              ),
            ),
          ] else ...<Widget>[
            const SizedBox(height: 15),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton(
                  key: const Key('chat-understanding-continue'),
                  onPressed: busy ? null : _continueUnderstanding,
                  child: const Text('Continue'),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => understandingAdjusting = true),
                  child: const Text('Adjust'),
                ),
                TextButton(
                  onPressed: busy ? null : _tryAnotherInterpretation,
                  child: const Text('Try another interpretation'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _planCard() {
    final command = prepared!;
    return _assistantCard(
      icon: Icons.account_tree_outlined,
      title: 'Here’s my development plan:',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ...command.plan.items.indexed.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CircleAvatar(
                    radius: 12,
                    child: Text('${entry.$1 + 1}', style: const TextStyle(fontSize: 10)),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          entry.$2.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (entry.$2.description.trim().isNotEmpty)
                          Text(
                            entry.$2.description,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          if (planAdjusting) ...<Widget>[
            const SizedBox(height: 8),
            TextField(
              controller: planAdjustmentController,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'How should the plan change?'),
              onSubmitted: (_) => _adjustPlan(),
            ),
            const SizedBox(height: 9),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: busy ? null : _adjustPlan,
                child: const Text('Update plan'),
              ),
            ),
          ] else ...<Widget>[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  key: const Key('chat-plan-start'),
                  onPressed: busy ? null : _startPlan,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : () => setState(() => planAdjusting = true),
                  child: const Text('Adjust plan'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _permissionCard() {
    final command = prepared!;
    final groups = groupPermissions(command.contract.requiredPermissions);
    return _assistantCard(
      icon: Icons.shield_outlined,
      title: 'Permission needed',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            'Your understanding and plan approvals do not grant authority. This run needs the following governed access:',
          ),
          const SizedBox(height: 10),
          ...groups.map(
            (group) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(group.icon),
              title: Text(group.title),
              subtitle: Text(group.description),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.icon(
                key: const Key('chat-permission-allow'),
                onPressed: busy ? null : _approvePermissions,
                icon: const Icon(Icons.lock_open_outlined),
                label: const Text('Allow for this run'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                          awaitingPermission = false;
                          prepared = null;
                          pendingDecision = null;
                          understandingHistory = null;
                          transcript.add(
                            _ChatLine.assistant('I did not execute the action.'),
                          );
                        }),
                child: const Text('Go back'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _runCard(RunRecord run) {
    final done = run.items.where((item) => item.state == WorkItemState.succeeded).length;
    final total = run.items.isEmpty ? 1 : run.items.length;
    return _assistantCard(
      icon: run.state == RunState.succeeded
          ? Icons.check_circle_outline
          : Icons.auto_awesome,
      title: friendlyRunState(run.state),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LinearProgressIndicator(
            value: run.state == RunState.running && done == 0
                ? null
                : (done / total).clamp(0, 1).toDouble(),
          ),
          const SizedBox(height: 12),
          if (currentRunIsInformational && liveAssistantText.trim().isNotEmpty)
            SelectableText(liveAssistantText)
          else ...<Widget>[
            if (liveProgressText.trim().isNotEmpty) ...<Widget>[
              Text(liveProgressText),
              const SizedBox(height: 9),
            ],
            ...run.items.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: <Widget>[
                    _workStateIcon(item.state),
                    const SizedBox(width: 8),
                    Expanded(child: Text(item.item.title)),
                    Text(
                      friendlyWorkState(item.state),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          ExpansionTile(
            initiallyExpanded: detailsExpanded,
            onExpansionChanged: (value) => detailsExpanded = value,
            tilePadding: EdgeInsets.zero,
            title: const Text('Details'),
            subtitle: const Text('Model, tools, evidence, and technical output'),
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: <Widget>[
                    Chip(label: Text(run.command.model.name)),
                    Chip(label: Text('${run.toolCalls} tool calls')),
                    Chip(label: Text('${run.mutations} mutations')),
                    Chip(label: Text('${run.repairs} repairs')),
                    if (liveToolName.isNotEmpty) Chip(label: Text(liveToolName)),
                  ],
                ),
              ),
              if (liveToolOutput.trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                _technicalBox(liveToolOutput),
              ],
              if (evidence.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                ...evidence.take(10).map(
                  (item) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.verified_outlined, size: 18),
                    title: Text(item.summary),
                    subtitle: Text(item.kind.name),
                  ),
                ),
              ],
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (run.state == RunState.running)
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _controlRun('pause'),
                  icon: const Icon(Icons.pause),
                  label: const Text('Pause'),
                ),
              if (run.state == RunState.paused || run.state == RunState.interrupted)
                FilledButton.icon(
                  onPressed: busy ? null : () => _controlRun('resume'),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Resume'),
                ),
              if (runActive)
                TextButton.icon(
                  onPressed: busy ? null : () => _controlRun('cancel'),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop'),
                ),
              OutlinedButton.icon(
                onPressed: busy ? null : _openAdvanced,
                icon: const Icon(Icons.dashboard_customize_outlined),
                label: const Text('Project'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultCard(RunRecord run) {
    final success = run.state == RunState.succeeded;
    return _assistantCard(
      icon: success ? Icons.check_circle_outline : Icons.error_outline,
      title: success ? 'Result' : 'Needs attention',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SelectableText(_resultText(run)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (projectProcessStatus?.running == true)
                OutlinedButton.icon(
                  onPressed: busy ? null : _stopManagedProject,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop'),
                ),
              OutlinedButton.icon(
                onPressed: busy ? null : _openAdvanced,
                icon: const Icon(Icons.folder_outlined),
                label: const Text('Project'),
              ),
              FilledButton.tonalIcon(
                onPressed: _newChat,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('New chat'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _assistantCard({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CircleAvatar(
          radius: 16,
          backgroundColor: colors.primaryContainer,
          child: Icon(icon, size: 16, color: colors.onPrimaryContainer),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  child,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _workStateIcon(WorkItemState state) {
    if (state == WorkItemState.running) {
      return const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Icon(
      switch (state) {
        WorkItemState.succeeded => Icons.check_circle_outline,
        WorkItemState.failed => Icons.error_outline,
        WorkItemState.blocked => Icons.block_outlined,
        WorkItemState.awaitingApproval => Icons.lock_clock_outlined,
        WorkItemState.cancelled => Icons.cancel_outlined,
        WorkItemState.queued => Icons.radio_button_unchecked,
        WorkItemState.running => Icons.autorenew,
      },
      size: 18,
    );
  }

  Widget _technicalBox(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: SelectableText(
        value,
        maxLines: 12,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }

  Widget _composer() {
    final colors = Theme.of(context).colorScheme;
    final hasSuggestions = suggestions.isNotEmpty;
    return Material(
      elevation: 3,
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 14),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (hasSuggestions) _autocomplete(),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Shortcuts(
                          shortcuts: <ShortcutActivator, Intent>{
                            const SingleActivator(
                              LogicalKeyboardKey.enter,
                              control: true,
                            ): const _SubmitIntent(),
                            const SingleActivator(
                              LogicalKeyboardKey.enter,
                              meta: true,
                            ): const _SubmitIntent(),
                            if (hasSuggestions)
                              const SingleActivator(LogicalKeyboardKey.arrowDown):
                                  const _NextSuggestionIntent(),
                            if (hasSuggestions)
                              const SingleActivator(LogicalKeyboardKey.arrowUp):
                                  const _PreviousSuggestionIntent(),
                            if (hasSuggestions)
                              const SingleActivator(LogicalKeyboardKey.enter):
                                  const _AcceptSuggestionIntent(),
                            if (hasSuggestions)
                              const SingleActivator(LogicalKeyboardKey.escape):
                                  const _DismissSuggestionsIntent(),
                          },
                          child: Actions(
                            actions: <Type, Action<Intent>>{
                              _SubmitIntent: CallbackAction<_SubmitIntent>(
                                onInvoke: (_) {
                                  unawaited(_submit());
                                  return null;
                                },
                              ),
                              _NextSuggestionIntent:
                                  CallbackAction<_NextSuggestionIntent>(
                                onInvoke: (_) {
                                  setState(() {
                                    suggestionIndex =
                                        (suggestionIndex + 1) % suggestions.length;
                                  });
                                  return null;
                                },
                              ),
                              _PreviousSuggestionIntent:
                                  CallbackAction<_PreviousSuggestionIntent>(
                                onInvoke: (_) {
                                  setState(() {
                                    suggestionIndex =
                                        (suggestionIndex - 1 + suggestions.length) %
                                            suggestions.length;
                                  });
                                  return null;
                                },
                              ),
                              _AcceptSuggestionIntent:
                                  CallbackAction<_AcceptSuggestionIntent>(
                                onInvoke: (_) {
                                  _selectSuggestion(suggestions[suggestionIndex]);
                                  return null;
                                },
                              ),
                              _DismissSuggestionsIntent:
                                  CallbackAction<_DismissSuggestionsIntent>(
                                onInvoke: (_) {
                                  setState(() {
                                    suggestions =
                                        const <ChatAutocompleteSuggestion>[];
                                  });
                                  return null;
                                },
                              ),
                            },
                            child: TextField(
                              controller: composerController,
                              focusNode: composerFocus,
                              minLines: 1,
                              maxLines: 8,
                              textInputAction: TextInputAction.newline,
                              decoration: InputDecoration(
                                hintText: runActive
                                    ? 'Steer the active work…'
                                    : 'Message Kristin…',
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.fromLTRB(17, 15, 17, 8),
                              ),
                              onChanged: (_) => _updateSuggestions(),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(9, 0, 9, 9),
                          child: Row(
                            children: <Widget>[
                              Tooltip(
                                message: '/ chooses an action',
                                child: Text(
                                  '/ action',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Tooltip(
                                message: '@ chooses a project, model, provider, or workspace',
                                child: Text(
                                  '@ target',
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ),
                              const Spacer(),
                              IconButton.filled(
                                tooltip: 'Send',
                                onPressed: busy || composerController.text.trim().isEmpty
                                    ? null
                                    : _submit,
                                icon: busy
                                    ? const SizedBox.square(
                                        dimension: 17,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.arrow_upward),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _autocomplete() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      constraints: const BoxConstraints(maxHeight: 330),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: const <BoxShadow>[
          BoxShadow(blurRadius: 12, spreadRadius: 1, color: Color(0x18000000)),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: suggestions.length,
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          final selected = index == suggestionIndex;
          return Semantics(
            button: true,
            selected: selected,
            label: '${suggestion.label}. ${suggestion.description}',
            child: ListTile(
              selected: selected,
              selectedTileColor: colors.secondaryContainer,
              leading: Icon(
                suggestion.kind == ChatAutocompleteKind.command
                    ? Icons.bolt_outlined
                    : Icons.alternate_email,
              ),
              title: Text(
                suggestion.label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                suggestion.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _selectSuggestion(suggestion),
            ),
          );
        },
      ),
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

class _SubmitIntent extends Intent {
  const _SubmitIntent();
}

class _NextSuggestionIntent extends Intent {
  const _NextSuggestionIntent();
}

class _PreviousSuggestionIntent extends Intent {
  const _PreviousSuggestionIntent();
}

class _AcceptSuggestionIntent extends Intent {
  const _AcceptSuggestionIntent();
}

class _DismissSuggestionsIntent extends Intent {
  const _DismissSuggestionsIntent();
}

String _slug(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9._:-]+'), '-')
    .replaceAll(RegExp(r'-+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');
