part of 'chat_control_plane_studio.dart';

extension _ChatControlPlaneActions on _ChatControlPlaneStudioState {
  Future<void> _handleImmediateCapability(
    ChatInteractionDecision decision,
  ) async {
    final id = decision.capability?.id;
    if (id == 'new_chat') {
      _newChat();
      return;
    }
    if (id == 'help') {
      _mutate(() {
        transcript.add(_ChatLine.assistant(_capabilityHelpText()));
        status = 'Kristin is ready';
      });
      return;
    }
    if (const <String>{
      'projects',
      'runs',
      'prompts',
      'knowledge',
      'logs',
    }.contains(id)) {
      await _openAdvanced();
      return;
    }
    await _answerInformational(decision);
  }

  String _capabilityHelpText() {
    return 'I can answer questions directly and operate Kristin from Chat. '
        'Core actions include /build, /fix, /search, /analyze, /test, /verify, '
        '/run, /stop, /restart, /connect, /use, /owner, and /diagnose. '
        'Use @ to target a project, model, provider, or workspace. '
        'Actions show what I understood before execution; substantial actions '
        'also show a plan; governed permissions remain a separate approval.';
  }

  Future<void> _answerInformational(
    ChatInteractionDecision decision,
  ) async {
    final local = await _tryLocalAnswer(decision);
    if (local != null) {
      _mutate(() {
        transcript.add(_ChatLine.assistant(local));
        status = 'Kristin is ready';
      });
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
    final activeModel = model;
    final result = await _perform<ModelGenerationResult>(
      'Answering',
      () => runtime.models.providerFor(activeModel).generate(
            ModelGenerationRequest(
              identity: activeModel,
              commandId: newId('chat_info'),
              systemPrompt:
                  'You are Kristin. Answer the user as a normal conversational assistant. '
                  'This request is informational only: do not claim to execute tools, '
                  'change files, start processes, or grant permissions. Be concise and '
                  'useful. Return one JSON object with exactly one string field named '
                  '"answer" and no markdown fence.',
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
    if (visible.isEmpty) visible = 'The model returned an empty answer.';
    _mutate(() {
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
        'Project process: ${process.running ? 'running' : 'not running'}'
        '${process.exitCode == null ? '' : ', last exit ${process.exitCode}'}.',
      );
    }
    final recent = runs.where((run) {
      return selectedProjectId == null ||
          run.command.contract.projectId == selectedProjectId;
    }).take(3);
    for (final run in recent) {
      buffer.writeln(
        'Recent run: ${run.command.contract.request} — ${run.state.name}'
        '${run.summary.trim().isEmpty ? '' : ': ${run.summary.trim()}'}',
      );
    }
    return buffer.toString().trim();
  }

  Future<String?> _tryLocalAnswer(ChatInteractionDecision decision) async {
    final text = decision.parsed.originalText.toLowerCase();
    if (RegExp(r'\bwhat can you do\b').hasMatch(text) ||
        text.trim() == 'help') {
      return _capabilityHelpText();
    }

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
      return '${modelTarget.displayName} is available'
          '${modelTarget.id == selectedModelId ? ' and selected' : ''}.';
    }

    if (text.contains('@owner') || text.contains('owner mode status')) {
      final owner = runtime.p2OwnerMode;
      return 'Owner Mode status: ${owner.statusCode}. Mentioning it never grants authority.';
    }
    return null;
  }

  Future<void> _continueUnderstanding() async {
    final decision = pendingDecision;
    final history = understandingHistory;
    if (decision == null || history == null) return;

    if (decision.unresolvedMentions.isNotEmpty) {
      _showError(
        'I cannot resolve ${decision.unresolvedMentions.map((value) => '@$value').join(', ')}. '
        'Adjust the request or choose a known target.',
      );
      return;
    }

    final capability = decision.capability;
    if (capability == null) {
      _showError('I need a clearer action before I can execute safely.');
      return;
    }
    final invalidTargets = decision.targets
        .where((target) => !capability.acceptsTarget(target.type))
        .toList(growable: false);
    if (invalidTargets.isNotEmpty) {
      _showError(
        '${capability.displayName} cannot target '
        '${invalidTargets.map((target) => '@${_slug(target.displayName)}').join(', ')}.',
      );
      return;
    }

    _applyDecisionTargets(decision);
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

  bool _shouldProvisionNewProject(ChatInteractionDecision decision) {
    if (decision.capability?.id != 'build') return false;
    if (decision.targets.any((target) => target.type == ChatTargetType.project)) {
      return false;
    }
    final original = decision.parsed.originalText.trim().toLowerCase();
    if (RegExp(
      r'\b(?:this|current|existing|selected)\s+(?:project|repo|repository|app|application|codebase)\b',
    ).hasMatch(original)) {
      return false;
    }
    if (decision.parsed.commandToken == 'create') return true;
    final requestText = decision.parsed.hasExplicitCommand
        ? decision.parsed.arguments.toLowerCase()
        : original;
    final outcome = RegExp(
      r'\b(?:app|application|website|site|tool|service|bot|dashboard|game|api|project)\b',
    ).hasMatch(requestText);
    final modification = RegExp(
      r'\b(?:add|change|update|refactor|migrate|rename|move|remove|delete|fix|repair)\b',
    ).hasMatch(requestText);
    final createVerb = RegExp(
      r'^(?:please\s+)?(?:can|could|would|will)?(?:\s+you)?\s*'
      r'(?:build|create|make|develop|implement)\b',
    ).hasMatch(original) || decision.parsed.hasExplicitCommand;
    return createVerb && outcome && !modification;
  }

  Future<void> _preparePlan(
    String request,
    ChatInteractionDecision decision,
  ) async {
    var project = selectedProject;
    if (_shouldProvisionNewProject(decision)) {
      project = await _perform<ProjectRecord>(
        'Creating the project workspace',
        () => runtime.provisionProjectForRequest(
          request: decision.parsed.originalText,
        ),
      );
      if (project == null || !mounted) return;
      projects = await runtime.listProjects();
      selectedProjectId = project.id;
    }
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
      _showError('Connect an AI model before Kristin creates the execution plan.');
      return;
    }

    final activeProject = project;
    final activeModel = model;
    final result = await _perform<PreparedCommand>(
      'Creating the execution plan',
      () => runtime.prepare(
        projectId: activeProject.id,
        mode: decision.mode,
        request: request,
        model: activeModel,
      ),
    );
    if (result == null || !mounted) return;
    _mutate(() {
      prepared = result;
      pendingDecision = decision;
      currentRun = null;
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
        if (project == null) {
          _showProjectNeeded();
          return;
        }
        await _runDiagnosticAction(
          label: 'Analysis',
          activity: 'Analyzing ${project.name}',
          action: () => runtime.analyzeProject(project.id),
        );
        return;
      case ChatExecutionRoute.projectTest:
        if (project == null) {
          _showProjectNeeded();
          return;
        }
        await _runDiagnosticAction(
          label: 'Tests',
          activity: 'Testing ${project.name}',
          action: () => runtime.testProject(project.id),
        );
        return;
      case ChatExecutionRoute.projectVerify:
        if (project == null) {
          _showProjectNeeded();
          return;
        }
        await _runDiagnosticAction(
          label: 'Verification',
          activity: 'Verifying ${project.name}',
          action: () => runtime.testProject(project.id),
        );
        return;
      case ChatExecutionRoute.projectBuild:
        if (project == null) {
          _showProjectNeeded();
          return;
        }
        await _runDiagnosticAction(
          label: 'Build',
          activity: 'Building ${project.name}',
          action: () => runtime.buildProject(project.id),
        );
        return;
      case ChatExecutionRoute.projectRun:
        if (project == null) {
          _showProjectNeeded();
          return;
        }
        final process = await _perform<ProjectProcessStatus>(
          'Starting ${project.name}',
          () => runtime.startProject(project.id),
        );
        if (process != null) {
          projectProcessStatus = process;
          _finishDirectAction('${project.name} is running.');
        }
        return;
      case ChatExecutionRoute.projectStop:
        if (project == null) {
          _showProjectNeeded();
          return;
        }
        final process = await _perform<ProjectProcessStatus?>(
          'Stopping ${project.name}',
          () => runtime.stopProject(project.id),
        );
        projectProcessStatus = process;
        if (error == null) _finishDirectAction('${project.name} is stopped.');
        return;
      case ChatExecutionRoute.projectRestart:
        if (project == null) {
          _showProjectNeeded();
          return;
        }
        final process = await _perform<ProjectProcessStatus>(
          'Restarting ${project.name}',
          () async {
            await runtime.stopProject(project.id);
            return runtime.startProject(project.id);
          },
        );
        if (process != null) {
          projectProcessStatus = process;
          _finishDirectAction('${project.name} restarted and is running.');
        }
        return;
      case ChatExecutionRoute.connectProvider:
        await _openSettings(initialSection: 1);
        _finishDirectAction('Provider settings are ready.');
        return;
      case ChatExecutionRoute.selectModel:
        final modelTarget = decision.targets
            .where((target) => target.type == ChatTargetType.model)
            .firstOrNull;
        if (modelTarget == null) {
          _showError(
            'Mention the model you want to use, for example `/use @phi4-mini`.',
          );
          return;
        }
        if (!models.any((model) => model.exactId == modelTarget.id)) {
          _showError('${modelTarget.displayName} is not currently available.');
          return;
        }
        _mutate(() => selectedModelId = modelTarget.id);
        _finishDirectAction(
          '${modelTarget.displayName} will be used for the next eligible task.',
        );
        return;
      case ChatExecutionRoute.ownerMode:
        _finishDirectAction(
          'Owner Mode remains governed. Open the Owner Mode workspace from the main navigation to prepare or use it; this chat confirmation granted no authority.',
        );
        return;
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
        return;
      case ChatExecutionRoute.open:
        await _openAdvanced();
        return;
      case ChatExecutionRoute.agent:
        await _prepareAgentAction(request, decision);
        return;
      case ChatExecutionRoute.navigation:
      case ChatExecutionRoute.help:
        await _handleImmediateCapability(decision);
        return;
    }
  }

  Future<void> _runDiagnosticAction({
    required String label,
    required String activity,
    required Future<ProjectDiagnosticReport> Function() action,
  }) async {
    final report = await _perform<ProjectDiagnosticReport>(activity, action);
    if (report != null) {
      _finishDirectAction(_diagnosticSummary(label, report));
    }
  }

  void _showProjectNeeded() {
    _showError('Choose or mention a project for this action.');
  }

  String _diagnosticSummary(String label, ProjectDiagnosticReport report) {
    final result = report.failed == 0 ? 'passed' : 'needs attention';
    return '$label $result: ${report.passed} passed, '
        '${report.warnings} warnings, ${report.failed} failed.';
  }

  void _finishDirectAction(String message) {
    _mutate(() {
      transcript.add(_ChatLine.assistant(message));
      pendingDecision = null;
      understandingHistory = null;
      prepared = null;
      currentRun = null;
      awaitingPermission = false;
      activeRequest = '';
      status = 'Kristin is ready';
    });
  }

  Future<void> _prepareAgentAction(
    String request,
    ChatInteractionDecision decision,
  ) async {
    var project = selectedProject;
    if (project == null && projects.isNotEmpty) {
      project = projects.first;
      selectedProjectId = project.id;
    }
    if (project == null) {
      _showError(
        'This governed action needs a project workspace. Add a project first; Kristin will not create an unrelated project just to satisfy the command.',
      );
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
          'Search current public sources for this request and return grounded findings with source provenance: '
          '${query.isEmpty ? request : query}';
    }

    final activeProject = project;
    final activeModel = model;
    final command = await _perform<PreparedCommand>(
      'Preparing the action',
      () => runtime.prepare(
        projectId: activeProject.id,
        mode: decision.mode,
        request: governedRequest,
        model: activeModel,
      ),
    );
    if (command == null || !mounted) return;
    _mutate(() {
      prepared = command;
      activeRequest = request;
      pendingDecision = decision;
      currentRun = null;
      awaitingPermission = command.contract.requiredPermissions.isNotEmpty;
      status = awaitingPermission ? 'Permission review required' : 'Starting';
    });
    if (!awaitingPermission) await _startPrepared();
  }

  Future<void> _startPlan() async {
    final command = prepared;
    if (command == null) return;
    if (command.contract.requiredPermissions.isNotEmpty) {
      _mutate(() {
        awaitingPermission = true;
        status = 'Permission review required';
      });
      return;
    }
    await _startPrepared();
  }

  Future<void> _approvePermissions() async {
    if (prepared == null) return;
    _mutate(() => awaitingPermission = false);
    await _startPrepared();
  }

  Future<void> _declinePermissions() async {
    final run = currentRun;
    if (run?.state == RunState.awaitingApproval) {
      await _perform<void>(
        'Declining the pending run',
        () => runtime.cancel(run!.id),
        silent: true,
      );
    }
    _mutate(() {
      transcript.add(_ChatLine.assistant('I did not execute the action.'));
      pendingDecision = null;
      understandingHistory = null;
      prepared = null;
      currentRun = null;
      awaitingPermission = false;
      activeRequest = '';
      status = 'Kristin is ready';
    });
  }

  Future<void> _startPrepared() async {
    final command = prepared;
    if (command == null) return;
    final started = await _perform<RunRecord>('Starting execution', () async {
      var run = currentRun;
      if (run == null ||
          run.command.id != command.id ||
          const <RunState>{
            RunState.succeeded,
            RunState.failed,
            RunState.cancelled,
          }.contains(run.state)) {
        run = await runtime.createRun(command.id);
      }
      await runtime.approve(
        runId: run.id,
        scopes: Set<PermissionScope>.from(
          command.contract.requiredPermissions,
        ),
      );
      currentRun = run;
      unawaited(runtime.execute(run.id));
      await Future<void>.delayed(const Duration(milliseconds: 180));
      return await runtime.getRun(run.id) ?? run;
    });
    if (started == null || !mounted) return;
    _mutate(() {
      currentRun = started;
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
    final values = <UnderstandingDraft>[
      ...history.revisions,
      UnderstandingDraft(
        originalRequest: history.current.originalRequest,
        acceptedRequest: revisedRequest,
        summary: revisedDecision.interpretedGoal,
        revision: history.current.revision + 1,
        alternativeIndex: history.current.alternativeIndex,
      ),
    ];
    if (values.length > 6) values.removeRange(0, values.length - 6);
    _mutate(() {
      understandingHistory =
          UnderstandingHistory(List<UnderstandingDraft>.unmodifiable(values));
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
    _mutate(() {
      understandingHistory = history.alternate(decision);
      status = 'Showing another interpretation of the same request';
    });
  }

  Future<void> _adjustPlan() async {
    final command = prepared;
    final decision = pendingDecision;
    final history = understandingHistory;
    final adjustment = planAdjustmentController.text.trim();
    if (command == null ||
        decision == null ||
        history == null ||
        adjustment.isEmpty) {
      return;
    }
    final request =
        '${history.current.acceptedRequest}\n\nPlan adjustment: $adjustment';
    planAdjustmentController.clear();
    _mutate(() => planAdjusting = false);
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
      _mutate(() {
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
    final newRuns = await runtime.listRuns(limit: 120);
    if (!mounted) return;
    _mutate(() {
      projects = newProjects;
      models = newModels;
      runs = newRuns;
      if (result != null &&
          newProjects.any((item) => item.id == result.projectId)) {
        selectedProjectId = result.projectId;
      } else if (!newProjects.any((item) => item.id == selectedProjectId)) {
        selectedProjectId = newProjects.firstOrNull?.id;
      }
      if (result != null &&
          newModels.any((item) => item.exactId == result.modelId)) {
        selectedModelId = result.modelId;
      } else if (!newModels.any((item) => item.exactId == selectedModelId)) {
        selectedModelId = newModels.firstOrNull?.exactId;
      }
    });
    await _refreshProjectProcess();
  }

  void _newChat() {
    if (currentRun != null && !runTerminal) {
      _showError(
        runAwaitingApproval
            ? 'Resolve the pending permission request before starting a new chat.'
            : 'Stop the active governed task before starting a new chat.',
      );
      return;
    }
    _mutate(() {
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
    _mutate(() {
      error = message;
      status = 'Kristin needs your help';
    });
  }
}
