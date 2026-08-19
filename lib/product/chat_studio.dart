import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_server.dart';
import 'domain.dart';
import 'extensions_index.dart';
import 'models_research.dart';
import 'product_runtime.dart';
import 'prompt_planning.dart';
import 'storage_security.dart';
import 'ui_advanced.dart';
import 'ui_components.dart';

enum _StudioArea {
  chat,
  chats,
  projects,
  runs,
  promptStudio,
  knowledge,
  skills,
  logs,
}

enum _LogView { simple, technical, raw }

enum _KnowledgeView { overview, sources, notes, memory }

enum _PromptStudioOperationKind {
  clarification,
  generate,
  improve,
  simplify,
  addDetail,
  taskPlan,
}

class _NavigationItem {
  const _NavigationItem({
    required this.area,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final _StudioArea area;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const List<_NavigationItem> _primaryItems = <_NavigationItem>[
  _NavigationItem(
    area: _StudioArea.chats,
    label: 'Chats',
    icon: Icons.chat_bubble_outline,
    selectedIcon: Icons.chat_bubble,
  ),
  _NavigationItem(
    area: _StudioArea.projects,
    label: 'Project Manager',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard,
  ),
];

const List<_NavigationItem> _buildItems = <_NavigationItem>[
  _NavigationItem(
    area: _StudioArea.runs,
    label: 'Runs',
    icon: Icons.account_tree_outlined,
    selectedIcon: Icons.account_tree,
  ),
  _NavigationItem(
    area: _StudioArea.promptStudio,
    label: 'Prompt Studio',
    icon: Icons.edit_note_outlined,
    selectedIcon: Icons.edit_note,
  ),
  _NavigationItem(
    area: _StudioArea.knowledge,
    label: 'Knowledge',
    icon: Icons.library_books_outlined,
    selectedIcon: Icons.library_books,
  ),
  _NavigationItem(
    area: _StudioArea.skills,
    label: 'Skills',
    icon: Icons.extension_outlined,
    selectedIcon: Icons.extension,
  ),
  _NavigationItem(
    area: _StudioArea.logs,
    label: 'Logs',
    icon: Icons.terminal_outlined,
    selectedIcon: Icons.terminal,
  ),
];

class ChatStudio extends StatefulWidget {
  const ChatStudio({
    super.key,
    required this.runtime,
    required this.api,
    this.startupError,
  });

  final ProductRuntime runtime;
  final GovernedApiServer api;
  final String? startupError;

  @override
  State<ChatStudio> createState() => _ChatStudioState();
}

class _ChatStudioState extends State<ChatStudio> {
  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey promptStudioOperationKey = GlobalKey();
  final TextEditingController composerController = TextEditingController();
  final TextEditingController chatSearchController = TextEditingController();
  final TextEditingController knowledgeSearchController =
      TextEditingController();
  final TextEditingController logSearchController = TextEditingController();
  final TextEditingController promptGoalController = TextEditingController();
  final TextEditingController promptFeedbackController =
      TextEditingController();
  final FocusNode composerFocus = FocusNode();

  StreamSubscription<EventEnvelope>? eventSubscription;
  Timer? refreshTimer;

  _StudioArea area = _StudioArea.chat;
  _LogView logView = _LogView.simple;
  _KnowledgeView knowledgeView = _KnowledgeView.overview;
  SimpleTaskMode taskMode = SimpleTaskMode.auto;
  CommandMode chosenMode = CommandMode.build;
  bool buildMenuExpanded = true;
  bool busy = false;
  bool loading = true;
  String status = 'Kristin is ready';
  String? error;

  List<ProjectRecord> projects = <ProjectRecord>[];
  List<ModelIdentity> models = <ModelIdentity>[];
  List<RunRecord> runs = <RunRecord>[];
  List<EvidenceRecord> evidence = <EvidenceRecord>[];
  List<EventEnvelope> events = <EventEnvelope>[];
  List<PromptTemplateRecord> prompts = <PromptTemplateRecord>[];
  PromptStudioDraft? generatedPromptDraft;
  PromptTemplateRecord? generatedPromptRecord;
  PromptVersionRecord? generatedPromptVersion;
  TaskPlanRecord? generatedTaskPlan;
  PlanningDepth generatedPlanningDepth = PlanningDepth.auto;
  int generatedMaxTasks = 7;
  Completer<void>? promptGenerationCancellation;
  Stopwatch? promptGenerationStopwatch;
  String promptGenerationStage = 'idle';
  String promptGenerationMessage = '';
  String promptGenerationPreview = '';
  int promptGenerationCharacters = 0;
  int promptGenerationAttempt = 1;
  int promptGenerationMaxAttempts = 1;
  _PromptStudioOperationKind? promptStudioOperationKind;
  PromptClarificationSession? promptClarificationSession;
  Map<String, String> promptClarificationAnswers = <String, String>{};
  String promptClarificationGoal = '';
  List<KnowledgeEntry> knowledge = <KnowledgeEntry>[];
  List<ResearchArchiveRecord> researchArchive = <ResearchArchiveRecord>[];
  List<MemoryEpisode> memoryEpisodes = <MemoryEpisode>[];
  KnowledgeStats? knowledgeStatsValue;
  KnowledgeRetrieval? knowledgeRetrieval;
  String? lastKnowledgeExportPath;
  List<SkillPackage> skills = <SkillPackage>[];

  String? selectedProjectId;
  String? selectedModelId;
  String? selectedRunId;
  String? selectedWorkItemId;
  PreparedCommand? prepared;
  RunRecord? currentRun;
  ProjectDiagnosticReport? diagnosticReport;
  ProjectProcessStatus? projectProcessStatusValue;
  Map<String, dynamic>? auditReport;
  String? lastSupportBundlePath;
  final Set<PermissionScope> approvedScopes = <PermissionScope>{};

  ProductRuntime get runtime => widget.runtime;

  bool get promptGenerationActive => promptGenerationCancellation != null;

  Duration get promptGenerationElapsed =>
      promptGenerationStopwatch?.elapsed ?? Duration.zero;

  ProjectRecord? get selectedProject =>
      projects.where((project) => project.id == selectedProjectId).firstOrNull;

  ModelIdentity? get selectedModel =>
      models.where((model) => model.exactId == selectedModelId).firstOrNull;

  List<RunRecord> get visibleRuns {
    final projectId = selectedProjectId;
    if (projectId == null) {
      return runs;
    }
    return runs
        .where((run) => run.command.contract.projectId == projectId)
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    skills = runtime.listBuiltInSkills();
    eventSubscription = runtime.eventStream.listen(_onEvent);
    refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final run = currentRun;
      if (mounted &&
          run != null &&
          const <RunState>{
            RunState.running,
            RunState.paused,
            RunState.cancelling,
            RunState.interrupted,
          }.contains(run.state)) {
        unawaited(_refreshRuns(silent: true));
      }
      if (mounted && projectProcessStatusValue?.running == true) {
        unawaited(_refreshProjectProcess(silent: true));
      }
      if (mounted && promptGenerationActive) {
        setState(() {});
      }
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    eventSubscription?.cancel();
    refreshTimer?.cancel();
    final promptCancellation = promptGenerationCancellation;
    if (promptCancellation != null && !promptCancellation.isCompleted) {
      promptCancellation.complete();
    }
    composerController.dispose();
    chatSearchController.dispose();
    knowledgeSearchController.dispose();
    logSearchController.dispose();
    promptGoalController.dispose();
    promptFeedbackController.dispose();
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
      final result = await action();
      if (!silent && mounted) {
        setState(() {
          status = '$activity completed';
        });
      }
      return result;
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = runtime.redactor.redact('$failure');
          status = 'Kristin needs your help';
        });
      }
      return null;
    } finally {
      if (!silent && mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  Future<void> _load() async {
    await _perform<void>('Opening your workspace', () async {
      projects = await runtime.listProjects();
      selectedProjectId ??= projects.firstOrNull?.id;
      models = await runtime.discoverModels();
      selectedModelId ??= models.firstOrNull?.exactId;
      runs = await runtime.listRuns(limit: 250);
      prompts = await runtime.listPrompts();
      events = await runtime.events.after(0, limit: 600);
      if (selectedProjectId != null) {
        final projectId = selectedProjectId!;
        knowledge = await runtime.listKnowledge(projectId);
        researchArchive = await runtime.listResearchArchive(projectId);
        memoryEpisodes = await runtime.listMemoryEpisodes(projectId);
        knowledgeStatsValue = await runtime.knowledgeStats(projectId);
        diagnosticReport = await runtime.inspectProject(
          projectId,
          modelReady: models.isNotEmpty,
        );
        projectProcessStatusValue = await runtime.projectProcessStatus(
          projectId,
        );
      }
    });
    if (mounted) {
      setState(() {
        loading = false;
      });
    }
  }

  void _onEvent(EventEnvelope event) {
    if (!mounted) {
      return;
    }
    setState(() {
      events.add(event);
      if (events.length > 600) {
        events.removeRange(0, events.length - 600);
      }
      status = _humanEvent(event);
    });
    if (event.type.startsWith('run.') ||
        event.type.startsWith('work_item.') ||
        event.type == 'evidence.recorded') {
      unawaited(_refreshRuns(silent: true));
    }
    if (event.type.startsWith('knowledge.') ||
        event.type.startsWith('research.') ||
        event.type.startsWith('memory.')) {
      unawaited(_refreshKnowledge(silent: true));
    }
    if (event.type.startsWith('prompt.')) {
      unawaited(_refreshPrompts(silent: true));
    }
    if (event.type.startsWith('project.')) {
      unawaited(_refreshProjectManager(silent: true));
    }
  }

  Future<void> _refreshRuns({bool silent = false}) async {
    await _perform<void>('Refreshing runs', () async {
      runs = await runtime.listRuns(limit: 250);
      final runId = selectedRunId ?? currentRun?.id;
      if (runId != null) {
        final refreshed = await runtime.getRun(runId);
        if (refreshed != null) {
          currentRun = refreshed;
          selectedRunId = refreshed.id;
          evidence = await runtime.evidenceForRun(refreshed.id);
        }
      }
    }, silent: silent);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _refreshKnowledge({bool silent = false}) async {
    final projectId = selectedProjectId;
    if (projectId == null) {
      if (mounted) {
        setState(() {
          knowledge = <KnowledgeEntry>[];
          researchArchive = <ResearchArchiveRecord>[];
          memoryEpisodes = <MemoryEpisode>[];
          knowledgeStatsValue = null;
          knowledgeRetrieval = null;
        });
      }
      return;
    }
    var loaded = false;
    var loadedKnowledge = <KnowledgeEntry>[];
    var loadedArchive = <ResearchArchiveRecord>[];
    var loadedEpisodes = <MemoryEpisode>[];
    KnowledgeStats? loadedStats;
    await _perform<void>('Refreshing knowledge and memory', () async {
      loadedKnowledge = await runtime.listKnowledge(projectId);
      loadedArchive = await runtime.listResearchArchive(projectId);
      loadedEpisodes = await runtime.listMemoryEpisodes(projectId);
      loadedStats = await runtime.knowledgeStats(projectId);
      loaded = true;
    }, silent: silent);
    if (mounted && loaded && selectedProjectId == projectId) {
      setState(() {
        knowledge = loadedKnowledge;
        researchArchive = loadedArchive;
        memoryEpisodes = loadedEpisodes;
        knowledgeStatsValue = loadedStats;
      });
    }
  }

  Future<void> _refreshPrompts({bool silent = false}) async {
    await _perform<void>('Refreshing prompts', () async {
      prompts = await runtime.listPrompts();
    }, silent: silent);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _refreshProjectManager({bool silent = false}) async {
    final projectId = selectedProjectId;
    if (projectId == null) {
      if (mounted) {
        setState(() {
          diagnosticReport = null;
          projectProcessStatusValue = null;
        });
      }
      return;
    }
    ProjectDiagnosticReport? loadedReport;
    ProjectProcessStatus? loadedProcess;
    var loaded = false;
    await _perform<void>('Refreshing Project Manager', () async {
      loadedReport = await runtime.inspectProject(
        projectId,
        modelReady: models.isNotEmpty,
      );
      loadedProcess = await runtime.projectProcessStatus(projectId);
      loaded = true;
    }, silent: silent);
    if (mounted && loaded && selectedProjectId == projectId) {
      setState(() {
        diagnosticReport = loadedReport;
        projectProcessStatusValue = loadedProcess;
      });
    }
  }

  Future<void> _refreshProjectProcess({bool silent = false}) async {
    final projectId = selectedProjectId;
    if (projectId == null) {
      return;
    }
    ProjectProcessStatus? loaded;
    var completed = false;
    await _perform<void>('Refreshing project process', () async {
      loaded = await runtime.projectProcessStatus(projectId);
      completed = true;
    }, silent: silent);
    if (mounted && completed && selectedProjectId == projectId) {
      setState(() {
        projectProcessStatusValue = loaded;
      });
    }
  }

  Future<void> _selectProject(String? projectId) async {
    if (projectId == selectedProjectId) {
      return;
    }
    setState(() {
      selectedProjectId = projectId;
      currentRun = null;
      selectedRunId = null;
      selectedWorkItemId = null;
      prepared = null;
      evidence = <EvidenceRecord>[];
      diagnosticReport = null;
      projectProcessStatusValue = null;
      knowledgeRetrieval = null;
      knowledgeSearchController.clear();
      approvedScopes.clear();
    });
    await Future.wait(<Future<void>>[
      _refreshKnowledge(silent: true),
      _refreshProjectManager(silent: true),
    ]);
  }

  Future<void> _selectRun(RunRecord run, {bool openChat = false}) async {
    final projectId = run.command.contract.projectId;
    setState(() {
      selectedProjectId = projectId;
      selectedRunId = run.id;
      selectedWorkItemId = run.items.firstOrNull?.item.id;
      currentRun = run;
      prepared = run.command;
      composerController.text = run.command.contract.request;
      if (openChat) {
        area = _StudioArea.chat;
      }
    });
    final loaded = await runtime.evidenceForRun(run.id);
    if (mounted) {
      setState(() {
        evidence = loaded;
      });
    }
    await _refreshKnowledge(silent: true);
  }

  void _newChat() {
    setState(() {
      area = _StudioArea.chat;
      prepared = null;
      currentRun = null;
      selectedRunId = null;
      selectedWorkItemId = null;
      evidence = <EvidenceRecord>[];
      approvedScopes.clear();
      composerController.clear();
      error = null;
      status = 'New chat ready';
    });
    composerFocus.requestFocus();
  }

  Future<void> _submitComposer() async {
    final request = composerController.text.trim();
    if (request.isEmpty || busy) {
      return;
    }
    if (request.startsWith('/')) {
      final handled = await _handleSlashCommand(request);
      if (handled) {
        return;
      }
    }
    await _prepareRequest(request);
  }

  Future<bool> _handleSlashCommand(String input) async {
    final command = input.split(RegExp(r'\s+')).first.toLowerCase();
    switch (command) {
      case '/new':
        _newChat();
        return true;
      case '/projects':
      case '/project':
      case '/manager':
        setState(() => area = _StudioArea.projects);
        return true;
      case '/runs':
        setState(() => area = _StudioArea.runs);
        return true;
      case '/prompts':
        setState(() => area = _StudioArea.promptStudio);
        return true;
      case '/knowledge':
        setState(() {
          knowledgeView = _KnowledgeView.overview;
          area = _StudioArea.knowledge;
        });
        return true;
      case '/sources':
        setState(() {
          knowledgeView = _KnowledgeView.sources;
          area = _StudioArea.knowledge;
        });
        return true;
      case '/memory':
        setState(() {
          knowledgeView = _KnowledgeView.memory;
          area = _StudioArea.knowledge;
        });
        return true;
      case '/logs':
        setState(() => area = _StudioArea.logs);
        return true;
      case '/doctor':
        await _runDoctor();
        return true;
      case '/test':
        await _runProjectTests();
        return true;
      case '/analyze':
        await _runProjectAnalysis();
        return true;
      case '/build':
        await _runProjectBuild();
        return true;
      case '/run':
        await _startManagedProject();
        return true;
      case '/stop':
        await _stopManagedProject();
        return true;
      default:
        return false;
    }
  }

  Future<void> _prepareRequest(String request) async {
    final project = selectedProject;
    final model = selectedModel;
    if (project == null) {
      setState(() {
        area = _StudioArea.projects;
        error = 'Add or select a project first.';
      });
      return;
    }
    if (model == null) {
      await _openSettings(initialSection: 1);
      if (selectedModel == null) {
        _showError('Connect an AI model before starting a chat task.');
        return;
      }
    }
    final activeModel = selectedModel;
    if (activeModel == null) {
      return;
    }
    final result = await _perform<PreparedCommand>(
      'Creating a clear plan',
      () => runtime.prepare(
        projectId: project.id,
        mode: resolveTaskMode(
          request: request,
          choice: taskMode,
          chosenMode: chosenMode,
        ),
        request: request,
        model: activeModel,
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      area = _StudioArea.chat;
      prepared = result;
      currentRun = null;
      selectedRunId = null;
      selectedWorkItemId = null;
      evidence = <EvidenceRecord>[];
      approvedScopes
        ..clear()
        ..addAll(result.contract.requiredPermissions);
      status = result.contract.requiredPermissions.isEmpty
          ? 'Starting response'
          : 'Plan ready for review';
    });
    if (result.contract.mode == CommandMode.ask &&
        isConversationalRequest(request) &&
        result.contract.requiredPermissions.isEmpty) {
      await _startPrepared();
    }
  }

  Future<void> _startPrepared() async {
    final command = prepared;
    if (command == null) {
      await _submitComposer();
      return;
    }
    if (!approvedScopes.containsAll(command.contract.requiredPermissions)) {
      _showError(
        'Re-enable every required access group or change the request.',
      );
      return;
    }
    final confirmed = await _confirmAccess(
      command.contract.requiredPermissions,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final started = await _perform<RunRecord>('Starting the task', () async {
      var run = currentRun;
      if (run == null || run.command.id != command.id) {
        run = await runtime.createRun(command.id);
      }
      await runtime.approve(
        runId: run.id,
        scopes: Set<PermissionScope>.from(command.contract.requiredPermissions),
      );
      currentRun = run;
      selectedRunId = run.id;
      selectedWorkItemId = run.items.firstOrNull?.item.id;
      evidence = <EvidenceRecord>[];
      unawaited(runtime.execute(run.id));
      await Future<void>.delayed(const Duration(milliseconds: 180));
      return await runtime.getRun(run.id) ?? run;
    });
    if (started != null && mounted) {
      setState(() {
        currentRun = started;
        selectedRunId = started.id;
      });
      await _refreshRuns(silent: true);
    }
  }

  Future<bool> _confirmAccess(Set<PermissionScope> scopes) async {
    final highRisk = groupPermissions(
      scopes,
    ).where((group) => group.highRisk).toList(growable: false);
    if (highRisk.isEmpty) {
      return true;
    }
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.shield_outlined),
            title: const Text('Review sensitive access'),
            content: SizedBox(
              width: 560,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'This task includes actions that can change files, run software, use the network, or publish artifacts. Access remains tied to this project and task.',
                  ),
                  const SizedBox(height: 12),
                  ...highRisk.map(
                    (group) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(group.icon),
                      title: Text(group.title),
                      subtitle: Text(group.description),
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Go back'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.lock_open_outlined),
                label: const Text('Allow for this run'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _controlRun(String action) async {
    final run = currentRun;
    if (run == null) {
      return;
    }
    await _perform<void>(
      action == 'pause'
          ? 'Pausing the run'
          : action == 'resume'
              ? 'Resuming the run'
              : 'Stopping the run',
      () async {
        if (action == 'pause') {
          await runtime.pause(run.id);
        } else if (action == 'resume') {
          await runtime.resume(run.id);
        } else {
          await runtime.cancel(run.id);
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
        currentRun = await runtime.getRun(run.id) ?? run;
      },
    );
    await _refreshRuns(silent: true);
  }

  Future<void> _retryRun() async {
    final run = currentRun;
    if (run == null) {
      return;
    }
    final retried = await _perform<RunRecord>(
      'Retrying as a fresh run',
      () async {
        final fresh = await runtime.retryRun(run.id);
        await runtime.approve(
          runId: fresh.id,
          scopes: Set<PermissionScope>.from(
            fresh.command.contract.requiredPermissions,
          ),
        );
        unawaited(runtime.execute(fresh.id));
        await Future<void>.delayed(const Duration(milliseconds: 180));
        return await runtime.getRun(fresh.id) ?? fresh;
      },
    );
    if (retried != null && mounted) {
      setState(() {
        currentRun = retried;
        selectedRunId = retried.id;
        selectedWorkItemId = retried.items.firstOrNull?.item.id;
      });
      await _refreshRuns(silent: true);
    }
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
    projects = await runtime.listProjects();
    models = await runtime.discoverModels();
    if (result != null) {
      if (projects.any((project) => project.id == result.projectId)) {
        selectedProjectId = result.projectId;
      }
      if (models.any((model) => model.exactId == result.modelId)) {
        selectedModelId = result.modelId;
      }
    }
    await _refreshRuns(silent: true);
    await _refreshKnowledge(silent: true);
    if (mounted) {
      setState(() {});
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      error = message;
      status = 'Kristin needs your help';
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 920;
    return Scaffold(
      key: scaffoldKey,
      appBar: compact
          ? AppBar(
              titleSpacing: 4,
              title: Text(_areaTitle(area)),
              leading: IconButton(
                tooltip: 'Menu',
                onPressed: () => scaffoldKey.currentState?.openDrawer(),
                icon: const Icon(Icons.menu),
              ),
              actions: <Widget>[
                _modelHealthButton(),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: busy ? null : () => _openSettings(),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            )
          : null,
      drawer: compact
          ? Drawer(child: SafeArea(child: _navigation(compact: true)))
          : null,
      body: Row(
        children: <Widget>[
          if (!compact) ...<Widget>[
            SizedBox(width: 266, child: _navigation(compact: false)),
            const VerticalDivider(width: 1),
          ],
          Expanded(
            child: Column(
              children: <Widget>[
                _statusStrip(),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : _content(),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: area == _StudioArea.chat
          ? null
          : FloatingActionButton.extended(
              onPressed: _newChat,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('New chat'),
            ),
    );
  }

  Widget _navigation({required bool compact}) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Kristin',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Local Agent · $kristinVersion preview',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () {
                if (compact) {
                  Navigator.of(context).pop();
                }
                _newChat();
              },
              icon: const Icon(Icons.add),
              label: const Text('New chat'),
            ),
            const SizedBox(height: 12),
            ..._primaryItems.map((item) => _navTile(item, compact: compact)),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  buildMenuExpanded = !buildMenuExpanded;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'BUILD & DEBUG',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                              color: colors.onSurfaceVariant,
                            ),
                      ),
                    ),
                    Icon(
                      buildMenuExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 19,
                    ),
                  ],
                ),
              ),
            ),
            if (buildMenuExpanded)
              ..._buildItems.map((item) => _navTile(item, compact: compact)),
            const SizedBox(height: 8),
            if (runs.isNotEmpty) ...<Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 5),
                child: Text(
                  'RECENT',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ),
              ...runs
                  .take(3)
                  .map((run) => _recentChatTile(run, compact: compact)),
            ],
            const Spacer(),
            if (selectedProject != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.folder_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'Project',
                            style: TextStyle(fontSize: 10.5),
                          ),
                          Text(
                            selectedProject!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ListTile(
              dense: true,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: busy
                  ? null
                  : () {
                      if (compact) {
                        Navigator.of(context).pop();
                      }
                      _openSettings();
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _navTile(_NavigationItem item, {required bool compact}) {
    final selected = area == item.area;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: colors.secondaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(selected ? item.selectedIcon : item.icon, size: 21),
        title: Text(
          item.label,
          style: TextStyle(fontWeight: selected ? FontWeight.w700 : null),
        ),
        trailing: item.area == _StudioArea.runs &&
                visibleRuns.any((run) => run.state == RunState.running)
            ? const SizedBox.square(
                dimension: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
        onTap: () {
          if (compact) {
            Navigator.of(context).pop();
          }
          setState(() {
            area = item.area;
          });
        },
      ),
    );
  }

  Widget _recentChatTile(RunRecord run, {required bool compact}) {
    final selected = selectedRunId == run.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        dense: true,
        selected: selected,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        leading: _runStateIcon(run.state, size: 18),
        title: Text(
          run.command.contract.request,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13),
        ),
        onTap: () {
          if (compact) {
            Navigator.of(context).pop();
          }
          unawaited(_selectRun(run, openChat: true));
        },
      ),
    );
  }

  Widget _modelHealthButton() {
    final ready = selectedModel != null;
    return IconButton(
      tooltip: ready ? 'AI model ready' : 'Connect an AI model',
      onPressed: () => _openSettings(initialSection: 1),
      icon: Badge(
        backgroundColor: ready
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error,
        smallSize: 8,
        child: const Icon(Icons.memory_outlined),
      ),
    );
  }

  Widget _statusStrip() {
    final startup = widget.startupError;
    final active = currentRun != null &&
        const <RunState>{
          RunState.running,
          RunState.paused,
          RunState.cancelling,
          RunState.interrupted,
        }.contains(currentRun!.state);
    if (!busy && error == null && startup == null && !active) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    final failing = error != null || startup != null;
    return Material(
      color: failing ? colors.errorContainer : colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: <Widget>[
            if (busy || currentRun?.state == RunState.running)
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                failing ? Icons.error_outline : Icons.info_outline,
                size: 18,
              ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                startup ?? error ?? status,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
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

  Widget _content() => switch (area) {
        _StudioArea.chat => _chatPage(),
        _StudioArea.chats => _chatsPage(),
        _StudioArea.projects => _projectsPage(),
        _StudioArea.runs => _runsPage(),
        _StudioArea.promptStudio => _promptStudioPage(),
        _StudioArea.knowledge => _knowledgePage(),
        _StudioArea.skills => _skillsPage(),
        _StudioArea.logs => _logsPage(),
      };

  Widget _chatPage() {
    return Column(
      children: <Widget>[
        _chatHeader(),
        const Divider(height: 1),
        Expanded(
          child: SelectionArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              children: <Widget>[
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: _chatConversation(),
                  ),
                ),
              ],
            ),
          ),
        ),
        _composer(),
      ],
    );
  }

  Widget _chatHeader() {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _selectorChip(
                    icon: Icons.folder_outlined,
                    label: selectedProject?.name ?? 'Choose project',
                    onTap: () => setState(() => area = _StudioArea.projects),
                  ),
                  _selectorChip(
                    icon: Icons.memory_outlined,
                    label: selectedModel?.name ?? 'Connect model',
                    onTap: () => _openSettings(initialSection: 1),
                  ),
                  PopupMenuButton<SimpleTaskMode>(
                    tooltip: 'Task mode',
                    initialValue: taskMode,
                    onSelected: (value) => setState(() => taskMode = value),
                    itemBuilder: (context) => SimpleTaskMode.values
                        .map(
                          (mode) => PopupMenuItem<SimpleTaskMode>(
                            value: mode,
                            child: Text(simpleModeLabel(mode)),
                          ),
                        )
                        .toList(),
                    child: _selectorChipBody(
                      Icons.tune,
                      simpleModeLabel(taskMode),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Open run view',
              onPressed: currentRun == null
                  ? null
                  : () => setState(() => area = _StudioArea.runs),
              icon: const Icon(Icons.account_tree_outlined),
            ),
            IconButton(
              tooltip: 'New chat',
              onPressed: _newChat,
              icon: const Icon(Icons.add_comment_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectorChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: _selectorChipBody(icon, label),
    );
  }

  Widget _selectorChipBody(IconData icon, String label) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatConversation() {
    if (prepared == null && currentRun == null) {
      return _emptyChat();
    }
    final command = currentRun?.command ?? prepared!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _messageBubble(assistant: false, child: Text(command.contract.request)),
        const SizedBox(height: 18),
        if (currentRun == null)
          _planMessage(command)
        else
          _runMessage(currentRun!),
        const SizedBox(height: 18),
        if (currentRun != null &&
            const <RunState>{
              RunState.succeeded,
              RunState.failed,
              RunState.cancelled,
            }.contains(currentRun!.state))
          _resultMessage(currentRun!),
      ],
    );
  }

  Widget _emptyChat() {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 44),
      child: Column(
        children: <Widget>[
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(21),
            ),
            child: Icon(
              Icons.auto_awesome,
              size: 30,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            selectedProject == null
                ? 'Start with a project'
                : 'What are we building?',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 9),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Text(
              selectedProject == null
                  ? 'Add an existing folder or create a new project. Then ask in plain language.'
                  : 'Ask a question, create something, fix an error, or open Project Manager with /manager. Use /analyze, /test, /build, /run, and /stop for direct project actions.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 28),
          if (selectedProject == null)
            FilledButton.icon(
              onPressed: () => setState(() => area = _StudioArea.projects),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Add a project'),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: studioTemplates.take(4).map((template) {
                return ActionChip(
                  avatar: Icon(template.icon, size: 18),
                  label: Text(template.title),
                  onPressed: () {
                    setState(() {
                      composerController.text = template.prompt;
                      taskMode = SimpleTaskMode.choose;
                      chosenMode = template.suggestedMode;
                    });
                    composerFocus.requestFocus();
                  },
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _messageBubble({required bool assistant, required Widget child}) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment:
          assistant ? MainAxisAlignment.start : MainAxisAlignment.end,
      children: <Widget>[
        if (assistant) ...<Widget>[
          CircleAvatar(
            radius: 17,
            backgroundColor: colors.primaryContainer,
            child: Icon(
              Icons.auto_awesome,
              size: 17,
              color: colors.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 760),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: assistant
                  ? colors.surfaceContainerLow
                  : colors.primaryContainer,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(assistant ? 5 : 18),
                bottomRight: Radius.circular(assistant ? 18 : 5),
              ),
              border:
                  assistant ? Border.all(color: colors.outlineVariant) : null,
            ),
            child: child,
          ),
        ),
      ],
    );
  }

  Widget _planMessage(PreparedCommand command) {
    final permissions = groupPermissions(command.contract.requiredPermissions);
    return _messageBubble(
      assistant: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Here is the plan',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              _statusPill(
                jobSizeLabel(command.plan.complexity),
                Icons.auto_awesome_outlined,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(command.plan.rationale),
          const SizedBox(height: 16),
          ...command.plan.items.indexed.map((entry) {
            final index = entry.$1;
            final item = entry.$2;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CircleAvatar(
                    radius: 13,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (item.description.isNotEmpty)
                          Text(
                            item.description,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          if (permissions.isNotEmpty) ...<Widget>[
            const Divider(height: 26),
            const Text(
              'Access needed for this run',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...permissions.map(
              (group) => CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: group.scopes.every(approvedScopes.contains),
                secondary: Icon(group.icon, size: 20),
                title: Text(group.title),
                subtitle: Text(group.description),
                onChanged: (enabled) {
                  setState(() {
                    if (enabled == true) {
                      approvedScopes.addAll(group.scopes);
                    } else {
                      approvedScopes.removeAll(group.scopes);
                    }
                  });
                },
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: <Widget>[
              FilledButton.icon(
                onPressed: busy ? null : _startPrepared,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start task'),
              ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        setState(() {
                          prepared = null;
                          approvedScopes.clear();
                        });
                        composerFocus.requestFocus();
                      },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit request'),
              ),
              TextButton.icon(
                onPressed: () => setState(() => area = _StudioArea.runs),
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Open flow'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _runMessage(RunRecord run) {
    final completed =
        run.items.where((item) => item.state == WorkItemState.succeeded).length;
    final total = run.items.isEmpty ? 1 : run.items.length;
    final progress = completed / total;
    return _messageBubble(
      assistant: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              _runStateIcon(run.state),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  friendlyRunState(run.state),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Text('$completed / ${run.items.length}'),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: run.state == RunState.running && completed == 0
                ? null
                : progress.clamp(0, 1).toDouble(),
          ),
          const SizedBox(height: 14),
          ...run.items.map(
            (progressItem) => InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                setState(() {
                  selectedWorkItemId = progressItem.item.id;
                  area = _StudioArea.runs;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: <Widget>[
                    _workStateIcon(progressItem.state),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        progressItem.item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      friendlyWorkState(progressItem.state),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
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
              if (run.state == RunState.paused ||
                  run.state == RunState.interrupted)
                FilledButton.icon(
                  onPressed: busy ? null : () => _controlRun('resume'),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Resume'),
                ),
              if (const <RunState>{
                RunState.running,
                RunState.paused,
                RunState.interrupted,
              }.contains(run.state))
                TextButton.icon(
                  onPressed: busy ? null : () => _controlRun('cancel'),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop'),
                ),
              if (run.state == RunState.failed)
                FilledButton.icon(
                  onPressed: busy ? null : _retryRun,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              OutlinedButton.icon(
                onPressed: () => setState(() => area = _StudioArea.runs),
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('View run'),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() => area = _StudioArea.logs),
                icon: const Icon(Icons.terminal_outlined),
                label: const Text('Open logs'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultMessage(RunRecord run) {
    final successful = run.state == RunState.succeeded;
    final summary = run.summary.trim().isNotEmpty
        ? run.summary.trim()
        : run.failure?.trim().isNotEmpty == true
            ? run.failure!.trim()
            : successful
                ? 'The run completed. Open the run view to inspect evidence and artifacts.'
                : 'The run stopped before all work completed.';
    final artifacts = evidence
        .where(
          (item) => <EvidenceKind>{
            EvidenceKind.mutation,
            EvidenceKind.deployment,
            EvidenceKind.test,
            EvidenceKind.verification,
          }.contains(item.kind),
        )
        .take(8)
        .toList();
    final citations = _runKnowledgeCitations();
    return _messageBubble(
      assistant: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                successful ? Icons.check_circle_outline : Icons.error_outline,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  successful ? 'Task completed' : 'Task needs attention',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(summary),
          if (citations.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'Sources and run memory consulted',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    knowledgeView = _KnowledgeView.overview;
                    area = _StudioArea.knowledge;
                  }),
                  child: const Text('Open library'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ...citations.map((hit) {
              final label = hit.citation;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                title: Text(hit.title),
                subtitle: Text(
                  '${_knowledgeKindLabel(hit.kind)} · relevance ${(hit.score * 100).round()}%${hit.sourceUrl.isEmpty ? '' : '\n${hit.sourceUrl}'}',
                ),
                trailing: IconButton(
                  tooltip: 'Copy citation',
                  onPressed: () => Clipboard.setData(
                    ClipboardData(
                      text:
                          '[$label] ${hit.title}\n${hit.sourceUrl}\n${hit.snippet}',
                    ),
                  ),
                  icon: const Icon(Icons.copy_outlined),
                ),
              );
            }),
          ],
          if (artifacts.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            const Text(
              'Evidence',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            ...artifacts.map(
              (item) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(_evidenceIcon(item.kind), size: 19),
                title: Text(item.summary),
                subtitle: Text(item.kind.name),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: _newChat,
                icon: const Icon(Icons.add_comment_outlined),
                label: const Text('New chat'),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() => area = _StudioArea.runs),
                icon: const Icon(Icons.account_tree_outlined),
                label: const Text('Inspect run'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<KnowledgeSearchHit> _runKnowledgeCitations() {
    final records = evidence
        .where((item) => item.kind == EvidenceKind.knowledge)
        .toList(growable: false)
        .reversed;
    for (final item in records) {
      try {
        final retrieval = KnowledgeRetrieval.fromJson(item.payload);
        if (retrieval.hits.isNotEmpty) {
          // Run summaries come from the latest completed work item, so preserve
          // that retrieval's exact K1..Kn marker mapping.
          return retrieval.hits.take(8).toList(growable: false);
        }
      } catch (_) {
        // Older evidence records may not use the v0.9 retrieval schema.
      }
    }
    return const <KnowledgeSearchHit>[];
  }

  Widget _composer() {
    final colors = Theme.of(context).colorScheme;
    return Material(
      elevation: 2,
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Shortcuts(
                      shortcuts: const <ShortcutActivator, Intent>{
                        SingleActivator(
                          LogicalKeyboardKey.enter,
                          control: true,
                        ): ActivateIntent(),
                        SingleActivator(LogicalKeyboardKey.enter, meta: true):
                            ActivateIntent(),
                      },
                      child: Actions(
                        actions: <Type, Action<Intent>>{
                          ActivateIntent: CallbackAction<ActivateIntent>(
                            onInvoke: (_) {
                              unawaited(_submitComposer());
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
                          decoration: const InputDecoration(
                            hintText:
                                'Ask Kristin anything about this project…',
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.fromLTRB(17, 15, 17, 8),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Row(
                        children: <Widget>[
                          IconButton(
                            tooltip: 'Use project files and knowledge',
                            onPressed: selectedProject == null
                                ? null
                                : _showContextHelp,
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                          PopupMenuButton<CommandMode>(
                            tooltip: 'Choose exact mode',
                            enabled: taskMode == SimpleTaskMode.choose,
                            initialValue: chosenMode,
                            onSelected: (value) =>
                                setState(() => chosenMode = value),
                            itemBuilder: (context) => CommandMode.values
                                .map(
                                  (mode) => PopupMenuItem<CommandMode>(
                                    value: mode,
                                    child: Text(modeLabel(mode)),
                                  ),
                                )
                                .toList(),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 7,
                              ),
                              child: Text(
                                taskMode == SimpleTaskMode.choose
                                    ? modeLabel(chosenMode)
                                    : 'Auto mode',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (composerController.text.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                'Ctrl/⌘ + Enter',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ),
                          IconButton.filled(
                            tooltip: prepared == null
                                ? 'Create plan'
                                : 'Send request',
                            onPressed:
                                busy || composerController.text.trim().isEmpty
                                    ? null
                                    : _submitComposer,
                            icon: busy
                                ? const SizedBox.square(
                                    dimension: 17,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.arrow_upward),
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
      ),
    );
  }

  Future<void> _showContextHelp() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Project context',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Kristin can inspect files inside the selected project and retrieve saved knowledge after you approve the plan. Mention a relative file path in your message to focus the task.',
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.library_books_outlined),
                title: const Text('Open project knowledge'),
                subtitle: Text('${knowledge.length} saved entries'),
                onTap: () {
                  Navigator.of(context).pop();
                  setState(() => area = _StudioArea.knowledge);
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(selectedProject?.name ?? 'No project'),
                subtitle: Text(selectedProject?.rootPath ?? ''),
                onTap: selectedProject == null
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: selectedProject!.rootPath),
                        );
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chatsPage() {
    final query = chatSearchController.text.trim().toLowerCase();
    final items = runs.where((run) {
      if (query.isEmpty) {
        return true;
      }
      final project = projects
          .where(
            (candidate) => candidate.id == run.command.contract.projectId,
          )
          .firstOrNull;
      return run.command.contract.request.toLowerCase().contains(query) ||
          run.summary.toLowerCase().contains(query) ||
          (project?.name.toLowerCase().contains(query) ?? false);
    }).toList(growable: false);
    return _page(
      maxWidth: 1120,
      children: <Widget>[
        _pageHeader(
          title: 'Chats',
          subtitle:
              'Every task stays connected to its plan, run, evidence, sources, and logs.',
          actions: <Widget>[
            FilledButton.icon(
              onPressed: _newChat,
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('New chat'),
            ),
          ],
        ),
        TextField(
          controller: chatSearchController,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Search chats',
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    onPressed: () {
                      chatSearchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (items.isEmpty)
          _emptyPanel(
            icon: Icons.chat_bubble_outline,
            title: runs.isEmpty ? 'No chats yet' : 'No matching chats',
            message: runs.isEmpty
                ? 'Start with a question or task. The conversation and execution record will appear here.'
                : 'Try a different search.',
            actionLabel: runs.isEmpty ? 'Start a chat' : null,
            onAction: runs.isEmpty ? _newChat : null,
          )
        else
          ...items.map((run) => _chatHistoryCard(run)),
      ],
    );
  }

  Widget _chatHistoryCard(RunRecord run) {
    final project = projects
        .where((candidate) => candidate.id == run.command.contract.projectId)
        .firstOrNull;
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => unawaited(_selectRun(run, openChat: true)),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(child: _runStateIcon(run.state)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      run.command.contract.request,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 8,
                      runSpacing: 7,
                      children: <Widget>[
                        _statusPill(
                          friendlyRunState(run.state),
                          _runStateIconData(run.state),
                        ),
                        if (project != null)
                          _statusPill(project.name, Icons.folder_outlined),
                        _statusPill(
                          modeLabel(run.command.contract.mode),
                          Icons.tune,
                        ),
                        _statusPill(_timeLabel(run.updatedAt), Icons.schedule),
                      ],
                    ),
                    if (run.summary.trim().isNotEmpty) ...<Widget>[
                      const SizedBox(height: 9),
                      Text(
                        run.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _projectsPage() {
    final selected = selectedProject;
    return _page(
      maxWidth: 1180,
      children: <Widget>[
        _pageHeader(
          title: 'Project Manager',
          subtitle:
              'Open, inspect, analyze, test, build, run, stop, and debug each project from one workspace.',
          actions: <Widget>[
            OutlinedButton.icon(
              onPressed: busy ? null : _addExistingProject,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Add existing'),
            ),
            FilledButton.icon(
              onPressed: busy ? null : _createProject,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Create project'),
            ),
          ],
        ),
        if (projects.isEmpty)
          _emptyPanel(
            icon: Icons.folder_open_outlined,
            title: 'No projects yet',
            message:
                'Add an existing folder or create a clean project. Kristin never needs access to your entire computer.',
            actionLabel: 'Add an existing folder',
            onAction: _addExistingProject,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth >= 880
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: projects.map((project) {
                  final active = project.id == selectedProjectId;
                  return SizedBox(
                    width: cardWidth,
                    child: _projectCard(project, active: active),
                  );
                }).toList(),
              );
            },
          ),
        if (selected != null) _projectControlCenter(selected),
      ],
    );
  }

  Widget _projectCard(ProjectRecord project, {required bool active}) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: active ? colors.secondaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(active ? Icons.folder : Icons.folder_outlined),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                if (active) _statusPill('Active', Icons.check_circle_outline),
              ],
            ),
            const SizedBox(height: 9),
            SelectableText(
              project.rootPath,
              maxLines: 2,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: active
                      ? null
                      : () => unawaited(_selectProject(project.id)),
                  child: Text(active ? 'Selected' : 'Use project'),
                ),
                IconButton(
                  tooltip: 'Copy path',
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: project.rootPath),
                    );
                    if (mounted) {
                      setState(() => status = 'Project path copied');
                    }
                  },
                  icon: const Icon(Icons.copy_outlined),
                ),
                IconButton(
                  tooltip: 'Remove registration',
                  onPressed: busy ? null : () => _removeProject(project),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _projectControlCenter(ProjectRecord project) {
    final report =
        diagnosticReport?.projectId == project.id ? diagnosticReport : null;
    final process = projectProcessStatusValue?.projectId == project.id
        ? projectProcessStatusValue
        : null;
    final running = process?.running == true;
    final recentRuns = visibleRuns.take(5).toList(growable: false);
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.space_dashboard_outlined,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            project.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            project.rootPath,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (running)
                      _statusPill('Running', Icons.play_circle_fill)
                    else if (process != null)
                      _statusPill(
                        process.exitCode == 0
                            ? 'Last run finished'
                            : 'Last run exited ${process.exitCode ?? ''}'
                                .trim(),
                        process.exitCode == 0
                            ? Icons.check_circle_outline
                            : Icons.stop_circle_outlined,
                      )
                    else if (report != null)
                      _diagnosticSummaryPill(report),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  'Project actions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  'These actions use the detected project profile. Analyze, Test, and Build are bounded foreground checks. Run starts one tracked process that can be stopped here.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: busy ? null : _runDoctor,
                      icon: const Icon(Icons.health_and_safety_outlined),
                      label: const Text('Doctor'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : _runProjectAnalysis,
                      icon: const Icon(Icons.analytics_outlined),
                      label: const Text('Analyze'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : _runProjectTests,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Test'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : _runProjectBuild,
                      icon: const Icon(Icons.build_outlined),
                      label: const Text('Build'),
                    ),
                    FilledButton.icon(
                      onPressed: busy || running ? null : _startManagedProject,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Run'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy || !running ? null : _stopManagedProject,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Stop'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _newChat,
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Ask Kristin'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => area = _StudioArea.runs),
                      icon: const Icon(Icons.account_tree_outlined),
                      label: const Text('Open runs'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _createSupportBundle,
                      icon: const Icon(Icons.archive_outlined),
                      label: const Text('Save logs'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (process != null) ...<Widget>[
          _projectProcessCard(process),
          const SizedBox(height: 14),
        ],
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Detected project profile',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Kristin detects common toolchains automatically. Add `kristin.project.json` to override Analyze, Test, Build, or Run safely.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh project profile',
                      onPressed: busy
                          ? null
                          : () => unawaited(
                                _refreshProjectManager(silent: false),
                              ),
                      icon: const Icon(Icons.refresh),
                    ),
                    if (report != null) _diagnosticSummaryPill(report),
                  ],
                ),
                if (report == null) ...<Widget>[
                  const SizedBox(height: 18),
                  const LinearProgressIndicator(),
                ] else ...<Widget>[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _statusPill(report.projectType, Icons.category_outlined),
                      if (report.analyzeCommand.isNotEmpty)
                        _statusPill('Analyze ready', Icons.analytics_outlined),
                      if (report.testCommand.isNotEmpty)
                        _statusPill('Test ready', Icons.fact_check_outlined),
                      if (report.buildCommand.isNotEmpty)
                        _statusPill('Build ready', Icons.build_outlined),
                      if (report.runCommand.isNotEmpty)
                        _statusPill('Run ready', Icons.play_circle_outline),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...report.checks.map(_diagnosticCheckTile),
                  if (report.analyzeCommand.isNotEmpty)
                    _commandBox('Analyze', report.analyzeCommand),
                  if (report.testCommand.isNotEmpty)
                    _commandBox('Test', report.testCommand),
                  if (report.buildCommand.isNotEmpty)
                    _commandBox('Build', report.buildCommand),
                  if (report.runCommand.isNotEmpty)
                    _commandBox('Run', report.runCommand),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Recent agent runs',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => area = _StudioArea.runs),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('View all'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (recentRuns.isEmpty)
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.history_toggle_off_outlined),
                    title: Text('No agent runs for this project yet'),
                    subtitle: Text(
                      'Ask Kristin in Chat or execute a Prompt Studio plan.',
                    ),
                  )
                else
                  ...recentRuns.map(
                    (run) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: _runStateIcon(run.state),
                      title: Text(
                        run.command.contract.request,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${friendlyRunState(run.state)} • ${_timeLabel(run.updatedAt)}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => unawaited(_selectRun(run)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (lastSupportBundlePath != null) ...<Widget>[
          const SizedBox(height: 14),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Latest diagnostic bundle'),
              subtitle: SelectableText(lastSupportBundlePath!),
              trailing: IconButton(
                tooltip: 'Copy path',
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: lastSupportBundlePath!),
                ),
                icon: const Icon(Icons.copy_outlined),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _projectProcessCard(ProjectProcessStatus process) {
    final running = process.running;
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: running ? colors.primaryContainer.withValues(alpha: 0.35) : null,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  running ? Icons.play_circle_fill : Icons.stop_circle_outlined,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        running
                            ? 'Project process is running'
                            : 'Project process finished',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'PID ${process.pid} • started ${_timeLabel(process.startedAt)}${process.exitCode == null ? '' : ' • exit ${process.exitCode}'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (running)
                  OutlinedButton.icon(
                    onPressed: busy ? null : _stopManagedProject,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : _startManagedProject,
                    icon: const Icon(Icons.replay),
                    label: const Text('Run again'),
                  ),
              ],
            ),
            if (process.command.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              _commandBox('Run', process.command),
            ],
            const SizedBox(height: 10),
            Text(
              'Live output',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            _codeBox(
              process.outputTail.trim().isEmpty
                  ? running
                      ? 'Process started. Waiting for output…'
                      : 'No output was captured.'
                  : process.outputTail,
              maxLines: 16,
            ),
            if (process.logFileName.isNotEmpty) ...<Widget>[
              const SizedBox(height: 7),
              Text(
                'Managed log: ${process.logFileName}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _diagnosticSummaryPill(ProjectDiagnosticReport report) {
    final failed = report.failed > 0;
    final warning = !failed && report.warnings > 0;
    return _statusPill(
      failed
          ? '${report.failed} failed'
          : warning
              ? '${report.warnings} warnings'
              : '${report.passed} passed',
      failed
          ? Icons.error_outline
          : warning
              ? Icons.warning_amber_outlined
              : Icons.check_circle_outline,
    );
  }

  Widget _diagnosticCheckTile(DiagnosticCheck check) {
    final icon = switch (check.status) {
      DiagnosticStatus.passed => Icons.check_circle_outline,
      DiagnosticStatus.warning => Icons.warning_amber_outlined,
      DiagnosticStatus.failed => Icons.error_outline,
      DiagnosticStatus.skipped => Icons.do_not_disturb_alt_outlined,
    };
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 10),
      leading: Icon(icon),
      title: Text(check.title),
      subtitle: Text(check.message),
      trailing: check.output.isEmpty ? null : const Icon(Icons.expand_more),
      children: check.output.isEmpty
          ? const <Widget>[]
          : <Widget>[_codeBox(check.output)],
    );
  }

  Widget _commandBox(String label, String command) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 54,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          Expanded(child: _codeBox(command, maxLines: 4)),
          IconButton(
            tooltip: 'Copy command',
            onPressed: () => Clipboard.setData(ClipboardData(text: command)),
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
      ),
    );
  }

  Future<void> _runDoctor() async {
    final project = selectedProject;
    if (project == null) {
      _showError('Select a project first.');
      setState(() => area = _StudioArea.projects);
      return;
    }
    final report = await _perform<ProjectDiagnosticReport>(
      'Checking project health',
      () => runtime.inspectProject(project.id, modelReady: models.isNotEmpty),
    );
    if (report != null && mounted) {
      setState(() {
        diagnosticReport = report;
        area = _StudioArea.projects;
        composerController.text = '/doctor';
      });
    }
  }

  Future<void> _runProjectTests() async {
    final project = selectedProject;
    if (project == null) {
      _showError('Select a project first.');
      setState(() => area = _StudioArea.projects);
      return;
    }
    var inspected = diagnosticReport;
    if (inspected == null || inspected.projectId != project.id) {
      inspected = await _perform<ProjectDiagnosticReport>(
        'Inspecting the project test profile',
        () => runtime.inspectProject(project.id, modelReady: models.isNotEmpty),
      );
    }
    if (inspected == null || !mounted) {
      return;
    }
    if (inspected.testCommand.isEmpty) {
      setState(() {
        diagnosticReport = inspected;
        area = _StudioArea.projects;
      });
      _showError(
        'No safe quick-test command was detected. Add kristin.project.json to define one.',
      );
      return;
    }
    final testCommand = inspected.testCommand;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.fact_check_outlined),
            title: const Text('Run project quick tests?'),
            content: SizedBox(
              width: 620,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'Kristin will execute the following detected commands inside the selected project with bounded output and a timeout. The AI model is not involved. Project tools can still create their normal caches or build outputs.',
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    testCommand,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Run tests'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      return;
    }
    final report = await _perform<ProjectDiagnosticReport>(
      'Running project quick tests',
      () => runtime.testProject(project.id),
    );
    if (report != null && mounted) {
      setState(() {
        diagnosticReport = report;
        area = _StudioArea.projects;
        composerController.text = '/test';
      });
    }
  }

  Future<ProjectDiagnosticReport?> _projectProfileForAction(
    ProjectRecord project,
  ) async {
    final current = diagnosticReport;
    if (current != null && current.projectId == project.id) {
      return current;
    }
    return _perform<ProjectDiagnosticReport>(
      'Detecting project commands',
      () => runtime.inspectProject(project.id, modelReady: models.isNotEmpty),
    );
  }

  Future<bool> _confirmProjectCommand({
    required String title,
    required String message,
    required String command,
    required String actionLabel,
    IconData icon = Icons.terminal_outlined,
  }) async {
    if (!mounted) {
      return false;
    }
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: Icon(icon),
            title: Text(title),
            content: SizedBox(
              width: 640,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(message),
                  const SizedBox(height: 12),
                  SelectableText(
                    command,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(actionLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _runProjectAnalysis() async {
    final project = selectedProject;
    if (project == null) {
      _showError('Select a project first.');
      setState(() => area = _StudioArea.projects);
      return;
    }
    final profile = await _projectProfileForAction(project);
    if (profile == null || !mounted) {
      return;
    }
    if (profile.analyzeCommand.isEmpty) {
      setState(() {
        diagnosticReport = profile;
        area = _StudioArea.projects;
      });
      _showError(
        'No safe analysis command was detected. Add an analyze entry to kristin.project.json.',
      );
      return;
    }
    final confirmed = await _confirmProjectCommand(
      title: 'Analyze ${project.name}?',
      message:
          'Kristin will run this detected analysis command inside the selected project with bounded output and a timeout. The AI model is not involved.',
      command: profile.analyzeCommand,
      actionLabel: 'Analyze project',
      icon: Icons.analytics_outlined,
    );
    if (!confirmed) {
      return;
    }
    final report = await _perform<ProjectDiagnosticReport>(
      'Analyzing ${project.name}',
      () => runtime.analyzeProject(project.id),
    );
    if (report != null && mounted) {
      setState(() {
        diagnosticReport = report;
        area = _StudioArea.projects;
        composerController.text = '/analyze';
      });
    }
  }

  Future<void> _runProjectBuild() async {
    final project = selectedProject;
    if (project == null) {
      _showError('Select a project first.');
      setState(() => area = _StudioArea.projects);
      return;
    }
    final profile = await _projectProfileForAction(project);
    if (profile == null || !mounted) {
      return;
    }
    if (profile.buildCommand.isEmpty) {
      setState(() {
        diagnosticReport = profile;
        area = _StudioArea.projects;
      });
      _showError(
        'No safe build command was detected. Add a build entry to kristin.project.json.',
      );
      return;
    }
    final confirmed = await _confirmProjectCommand(
      title: 'Build ${project.name}?',
      message:
          'Kristin will run this detected build command inside the selected project with bounded output and a timeout. The AI model is not involved.',
      command: profile.buildCommand,
      actionLabel: 'Build project',
      icon: Icons.build_outlined,
    );
    if (!confirmed) {
      return;
    }
    final report = await _perform<ProjectDiagnosticReport>(
      'Building ${project.name}',
      () => runtime.buildProject(project.id),
    );
    if (report != null && mounted) {
      setState(() {
        diagnosticReport = report;
        area = _StudioArea.projects;
        composerController.text = '/build';
      });
    }
  }

  Future<void> _startManagedProject() async {
    final project = selectedProject;
    if (project == null) {
      _showError('Select a project first.');
      setState(() => area = _StudioArea.projects);
      return;
    }
    final current = await runtime.projectProcessStatus(project.id);
    if (current?.running == true) {
      if (mounted) {
        setState(() {
          projectProcessStatusValue = current;
          area = _StudioArea.projects;
          status = '${project.name} is already running';
        });
      }
      return;
    }
    final profile = await _projectProfileForAction(project);
    if (profile == null || !mounted) {
      return;
    }
    if (profile.runCommand.isEmpty) {
      setState(() {
        diagnosticReport = profile;
        area = _StudioArea.projects;
      });
      _showError(
        'No managed run command was detected. Add a run entry to kristin.project.json.',
      );
      return;
    }
    final confirmed = await _confirmProjectCommand(
      title: 'Run ${project.name}?',
      message:
          'Kristin will start this command as a managed project process. Output stays visible here and Stop will terminate the tracked process.',
      command: profile.runCommand,
      actionLabel: 'Run project',
      icon: Icons.play_circle_outline,
    );
    if (!confirmed) {
      return;
    }
    final process = await _perform<ProjectProcessStatus>(
      'Starting ${project.name}',
      () => runtime.startProject(project.id),
    );
    if (process != null && mounted) {
      setState(() {
        projectProcessStatusValue = process;
        area = _StudioArea.projects;
        composerController.text = '/run';
      });
    }
  }

  Future<void> _stopManagedProject() async {
    final project = selectedProject;
    if (project == null) {
      _showError('Select a project first.');
      setState(() => area = _StudioArea.projects);
      return;
    }
    final process = await _perform<ProjectProcessStatus?>(
      'Stopping ${project.name}',
      () => runtime.stopProject(project.id),
    );
    if (mounted) {
      setState(() {
        projectProcessStatusValue = process;
        area = _StudioArea.projects;
        composerController.text = '/stop';
      });
      if (process == null) {
        _showError('No managed project process is currently running.');
      }
    }
  }

  Future<void> _addExistingProject() async {
    final picked = await runtime.pickProjectFolder(
      prompt: 'Choose an existing project folder',
    );
    if (!mounted) {
      return;
    }
    final pathController = TextEditingController(text: picked ?? '');
    final nameController = TextEditingController();
    final values = await showDialog<({String path, String name})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.folder_open_outlined),
        title: const Text('Add an existing project'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: pathController,
                autofocus: picked == null,
                decoration: const InputDecoration(
                  labelText: 'Project folder path',
                  hintText: r'C:\work\my-project or /home/me/my-project',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Display name (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop((
              path: pathController.text.trim(),
              name: nameController.text.trim(),
            )),
            child: const Text('Add project'),
          ),
        ],
      ),
    );
    pathController.dispose();
    nameController.dispose();
    if (values == null || values.path.isEmpty) {
      return;
    }
    final project = await _perform<ProjectRecord>(
      'Adding the project',
      () => runtime.addProject(name: values.name, rootPath: values.path),
    );
    if (project != null && mounted) {
      projects = await runtime.listProjects();
      setState(() {
        selectedProjectId = project.id;
        diagnosticReport = null;
      });
      await _refreshKnowledge(silent: true);
      await _runDoctor();
    }
  }

  Future<void> _createProject() async {
    final picked = await runtime.pickProjectFolder(
      prompt: 'Choose the parent folder for the new project',
    );
    if (!mounted) {
      return;
    }
    final parentController = TextEditingController(text: picked ?? '');
    final nameController = TextEditingController();
    final values = await showDialog<({String parent, String name})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.create_new_folder_outlined),
        title: const Text('Create a project'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Project name',
                  hintText: 'customer-portal',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: parentController,
                decoration: const InputDecoration(labelText: 'Parent folder'),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop((
              parent: parentController.text.trim(),
              name: nameController.text.trim(),
            )),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    parentController.dispose();
    nameController.dispose();
    if (values == null || values.parent.isEmpty || values.name.isEmpty) {
      return;
    }
    final project = await _perform<ProjectRecord>(
      'Creating the project',
      () => runtime.createProject(name: values.name, parentPath: values.parent),
    );
    if (project != null && mounted) {
      projects = await runtime.listProjects();
      setState(() {
        selectedProjectId = project.id;
        diagnosticReport = null;
      });
      await _refreshKnowledge(silent: true);
      _newChat();
    }
  }

  Future<void> _removeProject(ProjectRecord project) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Remove project registration?'),
            content: Text(
              'Kristin will forget the registration for “${project.name}”. Project files are not deleted.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Remove'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      return;
    }
    await _perform<void>(
      'Removing project registration',
      () => runtime.removeProject(project.id),
    );
    projects = await runtime.listProjects();
    if (mounted) {
      setState(() {
        if (selectedProjectId == project.id) {
          selectedProjectId = projects.firstOrNull?.id;
          prepared = null;
          currentRun = null;
          selectedRunId = null;
          diagnosticReport = null;
        }
      });
    }
    await _refreshKnowledge(silent: true);
  }

  Widget _runsPage() {
    final run = currentRun ?? visibleRuns.firstOrNull;
    if (run != null && currentRun == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && currentRun == null) {
          unawaited(_selectRun(run));
        }
      });
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 880;
        if (compact) {
          return _page(
            maxWidth: 1000,
            children: <Widget>[
              _pageHeader(
                title: 'Runs',
                subtitle:
                    'Watch every task, inspect each step, retry failures, and open the exact logs and evidence.',
              ),
              _runPicker(),
              if (run == null)
                _emptyPanel(
                  icon: Icons.account_tree_outlined,
                  title: 'No runs yet',
                  message:
                      'Start a task from chat to see its execution flow here.',
                  actionLabel: 'Start a chat',
                  onAction: _newChat,
                )
              else ...<Widget>[
                _runOverview(run),
                _runGraphPanel(run),
                _workItemInspector(run),
              ],
            ],
          );
        }
        return Row(
          children: <Widget>[
            SizedBox(
              width: 330,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'Runs',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Refresh',
                            onPressed: busy ? null : _refreshRuns,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(child: _runList()),
                  ],
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: run == null
                  ? Center(
                      child: _emptyPanel(
                        icon: Icons.account_tree_outlined,
                        title: 'No runs yet',
                        message:
                            'Start a task from chat to see its execution flow here.',
                        actionLabel: 'Start a chat',
                        onAction: _newChat,
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: <Widget>[
                        _runOverview(run),
                        const SizedBox(height: 14),
                        _runGraphPanel(run),
                        const SizedBox(height: 14),
                        _workItemInspector(run),
                        const SizedBox(height: 70),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _runPicker() {
    return DropdownButtonFormField<String>(
      initialValue: visibleRuns.any((run) => run.id == selectedRunId)
          ? selectedRunId
          : visibleRuns.firstOrNull?.id,
      decoration: const InputDecoration(
        labelText: 'Run',
        prefixIcon: Icon(Icons.account_tree_outlined),
      ),
      items: visibleRuns
          .map(
            (run) => DropdownMenuItem<String>(
              value: run.id,
              child: Text(
                run.command.contract.request,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (id) {
        final run = visibleRuns.where((item) => item.id == id).firstOrNull;
        if (run != null) {
          unawaited(_selectRun(run));
        }
      },
    );
  }

  Widget _runList() {
    if (visibleRuns.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No runs for this project.', textAlign: TextAlign.center),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: visibleRuns.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final run = visibleRuns[index];
        final selected = run.id == selectedRunId;
        return ListTile(
          selected: selected,
          selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: _runStateIcon(run.state, size: 20),
          title: Text(
            run.command.contract.request,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: selected ? FontWeight.w700 : null),
          ),
          subtitle: Text(
            '${friendlyRunState(run.state)} · ${_timeLabel(run.updatedAt)}',
            maxLines: 1,
          ),
          onTap: () => unawaited(_selectRun(run)),
        );
      },
    );
  }

  Widget _runOverview(RunRecord run) {
    final project = projects
        .where((candidate) => candidate.id == run.command.contract.projectId)
        .firstOrNull;
    final done =
        run.items.where((item) => item.state == WorkItemState.succeeded).length;
    final total = run.items.isEmpty ? 1 : run.items.length;
    final duration = run.startedAt == null
        ? null
        : (run.completedAt ?? DateTime.now().toUtc()).difference(
            run.startedAt!,
          );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _runStateIcon(run.state, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        run.command.contract.request,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 7),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          _statusPill(
                            friendlyRunState(run.state),
                            _runStateIconData(run.state),
                          ),
                          if (project != null)
                            _statusPill(project.name, Icons.folder_outlined),
                          _statusPill(
                            run.command.model.name,
                            Icons.memory_outlined,
                          ),
                          if (duration != null)
                            _statusPill(
                              _durationLabel(duration),
                              Icons.timer_outlined,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Run actions',
                  onSelected: (value) {
                    if (value == 'chat') {
                      setState(() => area = _StudioArea.chat);
                    } else if (value == 'logs') {
                      setState(() => area = _StudioArea.logs);
                    } else if (value == 'copy') {
                      Clipboard.setData(ClipboardData(text: run.id));
                    }
                  },
                  itemBuilder: (context) => const <PopupMenuEntry<String>>[
                    PopupMenuItem(value: 'chat', child: Text('Open chat')),
                    PopupMenuItem(value: 'logs', child: Text('Open logs')),
                    PopupMenuItem(value: 'copy', child: Text('Copy run ID')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: run.state == RunState.running && done == 0
                  ? null
                  : (done / total).clamp(0, 1).toDouble(),
            ),
            const SizedBox(height: 8),
            Text(
              '$done of ${run.items.length} steps complete · ${run.toolCalls} tool calls · ${run.mutations} mutations · ${run.repairs} repairs',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (run.failure?.trim().isNotEmpty == true) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(runtime.redactor.redact(run.failure!)),
              ),
            ],
            const SizedBox(height: 12),
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
                if (run.state == RunState.paused ||
                    run.state == RunState.interrupted)
                  FilledButton.icon(
                    onPressed: busy ? null : () => _controlRun('resume'),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Resume'),
                  ),
                if (const <RunState>{
                  RunState.running,
                  RunState.paused,
                  RunState.interrupted,
                }.contains(run.state))
                  TextButton.icon(
                    onPressed: busy ? null : () => _controlRun('cancel'),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop'),
                  ),
                if (run.state == RunState.failed)
                  FilledButton.icon(
                    onPressed: busy ? null : _retryRun,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry failed run'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _runGraphPanel(RunRecord run) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 12, 11),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Execution flow',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Text(
                        'Pan and zoom. Select a node to inspect its inputs, tools, evidence, attempts, and logs.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh run',
                  onPressed: busy ? null : _refreshRuns,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 440,
            child: _RunGraph(
              run: run,
              selectedWorkItemId: selectedWorkItemId,
              onSelected: (id) => setState(() => selectedWorkItemId = id),
            ),
          ),
        ],
      ),
    );
  }

  Widget _workItemInspector(RunRecord run) {
    final selected = run.items
            .where((item) => item.item.id == selectedWorkItemId)
            .firstOrNull ??
        run.items.firstOrNull;
    if (selected == null) {
      return const SizedBox.shrink();
    }
    final itemEvidence = evidence
        .where((item) => item.workItemId == selected.item.id)
        .toList(growable: false);
    final itemEvents = _eventsForRun(run)
        .where(
          (event) => event.data['workItemId']?.toString() == selected.item.id,
        )
        .toList(growable: false);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                _workStateIcon(selected.state, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        selected.item.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(friendlyWorkState(selected.state)),
                    ],
                  ),
                ),
                _statusPill(
                  '${selected.attempts}/${selected.item.maxAttempts} attempts',
                  Icons.refresh,
                ),
              ],
            ),
            const SizedBox(height: 13),
            Text(selected.item.description),
            if (selected.item.dependencies.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                'Depends on: ${selected.item.dependencies.join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 14),
            const Text(
              'Allowed tools',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: selected.item.allowedTools
                  .map((tool) => Chip(label: Text(tool)))
                  .toList(),
            ),
            if (selected.item.acceptanceCriteria.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              const Text(
                'Acceptance criteria',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ...selected.item.acceptanceCriteria.map(
                (criterion) => Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Icon(Icons.check_circle_outline, size: 17),
                      ),
                      const SizedBox(width: 7),
                      Expanded(child: Text(criterion)),
                    ],
                  ),
                ),
              ),
            ],
            if (selected.lastError?.trim().isNotEmpty == true) ...<Widget>[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(runtime.redactor.redact(selected.lastError!)),
              ),
            ],
            const Divider(height: 28),
            Text(
              'Evidence (${itemEvidence.length})',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            if (itemEvidence.isEmpty)
              const Text('No evidence has been recorded for this step yet.')
            else
              ...itemEvidence.map(
                (item) => ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 10),
                  leading: Icon(_evidenceIcon(item.kind)),
                  title: Text(item.summary),
                  subtitle: Text(
                    '${item.kind.name} · ${_timeLabel(item.createdAt)}',
                  ),
                  children: <Widget>[
                    _codeBox(
                      const JsonEncoder.withIndent('  ').convert(item.payload),
                      maxLines: 18,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Step logs (${itemEvents.length})',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            if (itemEvents.isEmpty)
              const Text('No correlated events for this step yet.')
            else
              ...itemEvents.reversed.take(20).map(
                    (event) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_eventIcon(event.type), size: 18),
                      title: Text(_humanEvent(event)),
                      subtitle: Text(
                        '${event.type} · #${event.sequence} · ${_timeLabel(event.timestamp)}',
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  void _beginPromptStudioOperation(
    _PromptStudioOperationKind kind,
    Completer<void> cancellation,
    Stopwatch stopwatch,
    String message,
  ) {
    setState(() {
      busy = true;
      error = null;
      status = message;
      promptStudioOperationKind = kind;
      promptGenerationCancellation = cancellation;
      promptGenerationStopwatch = stopwatch;
      promptGenerationStage = 'starting';
      promptGenerationMessage = message;
      promptGenerationPreview = '';
      promptGenerationCharacters = 0;
      promptGenerationAttempt = 1;
      promptGenerationMaxAttempts = 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final operationContext = promptStudioOperationKey.currentContext;
      if (operationContext != null) {
        Scrollable.ensureVisible(
          operationContext,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: 0.12,
        );
      }
    });
  }

  void _updatePromptStudioProgress(
    Completer<void> cancellation,
    ModelGenerationProgress progress,
  ) {
    if (!mounted || !identical(promptGenerationCancellation, cancellation)) {
      return;
    }
    setState(() {
      if (progress.stage.contains('repair_started')) {
        promptGenerationPreview = '';
        promptGenerationCharacters = 0;
      }
      promptGenerationStage = progress.stage;
      promptGenerationMessage = progress.message;
      promptGenerationAttempt = progress.attempt;
      promptGenerationMaxAttempts = progress.maxAttempts;
      status = progress.message;
    });
  }

  void _appendPromptStudioDelta(
    Completer<void> cancellation,
    String delta,
  ) {
    if (!mounted ||
        delta.isEmpty ||
        !identical(promptGenerationCancellation, cancellation)) {
      return;
    }
    setState(() {
      promptGenerationCharacters += delta.length;
      final combined = '$promptGenerationPreview$delta';
      promptGenerationPreview = combined.length <= 1800
          ? combined
          : combined.substring(combined.length - 1800);
      promptGenerationStage = 'streaming';
      promptGenerationMessage = switch (promptStudioOperationKind) {
        _PromptStudioOperationKind.clarification =>
          'Kristin is shaping the answer choices.',
        _PromptStudioOperationKind.taskPlan => 'The task graph is arriving.',
        _ => 'The prompt draft is arriving.',
      };
    });
  }

  void _finishPromptStudioOperation(
    Completer<void> cancellation,
    Stopwatch stopwatch,
  ) {
    stopwatch.stop();
    if (!mounted || !identical(promptGenerationCancellation, cancellation)) {
      return;
    }
    setState(() {
      busy = false;
      promptGenerationCancellation = null;
      promptGenerationStopwatch = null;
      promptStudioOperationKind = null;
    });
  }

  Future<void> _startPromptStudioFlow() async {
    if (promptGenerationActive) {
      return;
    }
    var model = selectedModel;
    if (model == null) {
      await _openSettings(initialSection: 1);
      model = selectedModel;
    }
    final activeModel = model;
    if (activeModel == null) {
      _showError('Connect and select an AI model before shaping the idea.');
      return;
    }
    final goal = promptGoalController.text.trim();
    if (goal.length < 5) {
      _showError('Describe the idea before Kristin prepares the decisions.');
      return;
    }
    final existing = promptClarificationSession;
    final session = existing != null && promptClarificationGoal == goal
        ? existing
        : await _generatePromptClarification(activeModel, goal);
    if (session == null || !mounted) {
      return;
    }
    final answers = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PromptClarificationDialog(
        session: session,
        initialAnswers: promptClarificationAnswers,
      ),
    );
    if (answers == null || !mounted) {
      setState(() {
        status = 'Choices are ready whenever you want to continue';
      });
      return;
    }
    setState(() {
      promptClarificationSession = session;
      promptClarificationAnswers = Map<String, String>.from(answers);
      promptClarificationGoal = goal;
      generatedPromptVersion = null;
      generatedTaskPlan = null;
    });
    await _generateStudioPrompt(
      PromptGenerationAction.generate,
      clarification: session,
      clarificationAnswers: answers,
    );
  }

  Future<PromptClarificationSession?> _generatePromptClarification(
    ModelIdentity model,
    String goal,
  ) async {
    final cancellation = Completer<void>();
    final stopwatch = Stopwatch()..start();
    _beginPromptStudioOperation(
      _PromptStudioOperationKind.clarification,
      cancellation,
      stopwatch,
      'Finding the decisions that matter',
    );
    try {
      final session = await runtime.generatePromptClarification(
        goal: goal,
        model: model,
        cancellation: cancellation.future,
        isCancelled: () => cancellation.isCompleted,
        onProgress: (progress) =>
            _updatePromptStudioProgress(cancellation, progress),
        onTextDelta: (delta) => _appendPromptStudioDelta(cancellation, delta),
      );
      if (!mounted || cancellation.isCompleted) {
        return null;
      }
      setState(() {
        promptClarificationSession = session;
        promptClarificationAnswers = <String, String>{};
        promptClarificationGoal = goal;
        status = '${session.questions.length} focused choices are ready';
      });
      return session;
    } on ProductException catch (failure) {
      if (!mounted) {
        return null;
      }
      setState(() {
        if (failure.code == 'cancelled' || cancellation.isCompleted) {
          status = 'Prompt Studio stopped';
          error = null;
        } else {
          error = runtime.redactor.redact('$failure');
          status = 'Kristin needs your help';
        }
      });
      return null;
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = runtime.redactor.redact('$failure');
          status = 'Kristin needs your help';
        });
      }
      return null;
    } finally {
      _finishPromptStudioOperation(cancellation, stopwatch);
    }
  }

  Future<void> _editPromptClarification() async {
    final session = promptClarificationSession;
    if (session == null || promptGenerationActive) {
      return;
    }
    final answers = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PromptClarificationDialog(
        session: session,
        initialAnswers: promptClarificationAnswers,
      ),
    );
    if (answers == null || !mounted) {
      return;
    }
    setState(() {
      promptClarificationAnswers = Map<String, String>.from(answers);
      generatedPromptVersion = null;
      generatedTaskPlan = null;
    });
    await _generateStudioPrompt(
      PromptGenerationAction.generate,
      clarification: session,
      clarificationAnswers: answers,
    );
  }

  void _onPromptGoalChanged(String value) {
    final normalized = value.trim();
    final stale = promptClarificationGoal.isNotEmpty &&
        normalized != promptClarificationGoal;
    setState(() {
      if (stale) {
        promptClarificationSession = null;
        promptClarificationAnswers = <String, String>{};
        promptClarificationGoal = '';
        generatedPromptDraft = null;
        generatedPromptRecord = null;
        generatedPromptVersion = null;
        generatedTaskPlan = null;
        promptFeedbackController.clear();
        status = 'Idea changed — Kristin will prepare fresh choices';
      }
    });
  }

  void _resetPromptStudioSession() {
    if (promptGenerationActive) {
      _cancelStudioPromptGeneration();
    }
    setState(() {
      promptGoalController.clear();
      promptFeedbackController.clear();
      promptClarificationSession = null;
      promptClarificationAnswers = <String, String>{};
      promptClarificationGoal = '';
      generatedPromptDraft = null;
      generatedPromptRecord = null;
      generatedPromptVersion = null;
      generatedTaskPlan = null;
      prepared = null;
      error = null;
      status = 'Start with a new idea';
    });
  }

  Future<void> _generateStudioPrompt(
    PromptGenerationAction action, {
    String feedback = '',
    PromptClarificationSession? clarification,
    Map<String, String> clarificationAnswers = const <String, String>{},
  }) async {
    if (promptGenerationActive) {
      return;
    }
    var model = selectedModel;
    if (model == null) {
      await _openSettings(initialSection: 1);
      model = selectedModel;
    }
    final activeModel = model;
    if (activeModel == null) {
      _showError('Connect and select an AI model before generating a prompt.');
      return;
    }
    final goal = promptGoalController.text.trim();
    final activeClarification = clarification ?? promptClarificationSession;
    final activeAnswers = clarificationAnswers.isNotEmpty
        ? clarificationAnswers
        : promptClarificationAnswers;
    final kind = switch (action) {
      PromptGenerationAction.generate => _PromptStudioOperationKind.generate,
      PromptGenerationAction.improve => _PromptStudioOperationKind.improve,
      PromptGenerationAction.simplify => _PromptStudioOperationKind.simplify,
      PromptGenerationAction.addDetail => _PromptStudioOperationKind.addDetail,
    };
    final startingMessage = switch (action) {
      PromptGenerationAction.generate =>
        'Writing the final prompt from your choices',
      PromptGenerationAction.improve => 'Improving the prompt with AI',
      PromptGenerationAction.simplify => 'Simplifying the prompt',
      PromptGenerationAction.addDetail => 'Adding useful detail',
    };
    final cancellation = Completer<void>();
    final stopwatch = Stopwatch()..start();
    _beginPromptStudioOperation(
      kind,
      cancellation,
      stopwatch,
      startingMessage,
    );
    try {
      final draft = await runtime.generatePromptDraft(
        goal: goal,
        model: activeModel,
        action: action,
        current: generatedPromptDraft,
        feedback: feedback,
        clarification: activeClarification,
        clarificationAnswers: activeAnswers,
        cancellation: cancellation.future,
        isCancelled: () => cancellation.isCompleted,
        onProgress: (progress) =>
            _updatePromptStudioProgress(cancellation, progress),
        onTextDelta: (delta) => _appendPromptStudioDelta(cancellation, delta),
      );
      if (!mounted || cancellation.isCompleted) {
        return;
      }
      setState(() {
        generatedPromptDraft = draft;
        generatedPromptVersion = null;
        generatedTaskPlan = null;
        promptFeedbackController.clear();
        status = action == PromptGenerationAction.generate
            ? 'Final prompt ready for review'
            : 'Prompt revision ready for review';
      });
    } on ProductException catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (failure.code == 'cancelled' || cancellation.isCompleted) {
          status = 'Prompt Studio stopped';
          error = null;
        } else {
          error = runtime.redactor.redact('$failure');
          status = 'Kristin needs your help';
        }
      });
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = runtime.redactor.redact('$failure');
          status = 'Kristin needs your help';
        });
      }
    } finally {
      _finishPromptStudioOperation(cancellation, stopwatch);
    }
  }

  void _cancelStudioPromptGeneration() {
    final cancellation = promptGenerationCancellation;
    if (cancellation == null || cancellation.isCompleted) {
      return;
    }
    cancellation.complete();
    if (mounted) {
      setState(() {
        status = 'Stopping the active Prompt Studio operation';
        promptGenerationMessage = 'Cancelling the active model request safely.';
      });
    }
  }

  void _applyPromptFeedback() {
    final feedback = promptFeedbackController.text.trim();
    if (feedback.isEmpty) {
      _showError('Answer a question or describe the change you want first.');
      return;
    }
    unawaited(
      _generateStudioPrompt(PromptGenerationAction.improve, feedback: feedback),
    );
  }

  Future<void> _editGeneratedPromptDraft() async {
    final draft = generatedPromptDraft;
    if (draft == null) {
      return;
    }
    final result = await showDialog<_PromptDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PromptEditorDialog(generatedDraft: draft),
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      generatedPromptDraft = draft.copyWith(
        title: result.title,
        purpose: result.description,
        systemPrompt: result.systemPrompt,
        userPrompt: result.userPrompt,
        variables: result.variables,
        mode: result.mode,
      );
      generatedPromptVersion = null;
      generatedTaskPlan = null;
      status = 'Prompt changes are ready to save';
    });
  }

  Future<PromptVersionRecord?> _saveGeneratedPromptDraft() async {
    final draft = generatedPromptDraft;
    final model = selectedModel;
    if (draft == null || model == null) {
      _showError('Generate a prompt and select a model first.');
      return null;
    }
    final saved = await _perform<
        ({PromptTemplateRecord prompt, PromptVersionRecord version})>(
      'Saving immutable prompt version',
      () => runtime.saveGeneratedPrompt(
        id: generatedPromptRecord?.id,
        goal: promptGoalController.text.trim(),
        draft: draft,
        model: model,
        action: generatedPromptRecord == null
            ? PromptGenerationAction.generate
            : PromptGenerationAction.improve,
        createdBy: 'user-reviewed-model',
      ),
    );
    if (saved == null || !mounted) {
      return null;
    }
    setState(() {
      generatedPromptRecord = saved.prompt;
      generatedPromptVersion = saved.version;
      status = 'Prompt version ${saved.version.versionNumber} saved';
    });
    await _refreshPrompts(silent: true);
    return saved.version;
  }

  Future<void> _generateStudioTaskPlan() async {
    if (promptGenerationActive) {
      return;
    }
    final project = selectedProject;
    final model = selectedModel;
    if (project == null) {
      _showError('Select a project before generating an executable task plan.');
      return;
    }
    if (model == null) {
      _showError('Select an AI model before generating a task plan.');
      return;
    }
    var version = generatedPromptVersion;
    version ??= await _saveGeneratedPromptDraft();
    if (version == null || !mounted) {
      return;
    }
    final cancellation = Completer<void>();
    final stopwatch = Stopwatch()..start();
    _beginPromptStudioOperation(
      _PromptStudioOperationKind.taskPlan,
      cancellation,
      stopwatch,
      'Turning the prompt into a compact task graph',
    );
    try {
      final plan = await runtime.generateTaskPlan(
        promptVersion: version,
        projectId: project.id,
        model: model,
        depth: generatedPlanningDepth,
        maxLeafTasks: generatedMaxTasks,
        cancellation: cancellation.future,
        isCancelled: () => cancellation.isCompleted,
        onProgress: (progress) =>
            _updatePromptStudioProgress(cancellation, progress),
        onTextDelta: (delta) => _appendPromptStudioDelta(cancellation, delta),
      );
      if (!mounted || cancellation.isCompleted) {
        return;
      }
      setState(() {
        generatedTaskPlan = plan;
        status = '${plan.tasks.length} validated tasks ready for review';
      });
    } on ProductException catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (failure.code == 'cancelled' || cancellation.isCompleted) {
          status = 'Task-plan generation stopped';
          error = null;
        } else {
          error = runtime.redactor.redact('$failure');
          status = 'Kristin needs your help';
        }
      });
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = runtime.redactor.redact('$failure');
          status = 'Kristin needs your help';
        });
      }
    } finally {
      _finishPromptStudioOperation(cancellation, stopwatch);
    }
  }

  Future<void> _editGeneratedPlanTask(PlanTaskRecord task) async {
    final plan = generatedTaskPlan;
    if (plan == null) {
      return;
    }
    final edited = await showDialog<PlanTaskRecord>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PlanTaskEditorDialog(
        task: task,
        availableTaskIds: plan.tasks
            .where((candidate) => candidate.id != task.id)
            .map((candidate) => candidate.id)
            .toSet(),
      ),
    );
    if (edited == null || !mounted) {
      return;
    }
    final tasks = plan.tasks
        .map((candidate) => candidate.id == task.id ? edited : candidate)
        .toList(growable: false);
    final updated = await _perform<TaskPlanRecord>(
      'Validating and saving a new task-plan revision',
      () => runtime.updateTaskPlan(plan, tasks: tasks),
    );
    if (updated == null || !mounted) {
      return;
    }
    setState(() {
      generatedTaskPlan = updated;
      prepared = null;
      currentRun = null;
      selectedRunId = null;
      status = 'Task plan v${updated.revision} saved';
    });
  }

  Future<void> _prepareStudioTaskPlan({
    Set<String>? selectedTaskIds,
    bool start = false,
  }) async {
    final plan = generatedTaskPlan;
    final version = generatedPromptVersion;
    final project = selectedProject;
    final model = selectedModel;
    if (plan == null || version == null || project == null || model == null) {
      _showError('Generate and save a task plan before running it.');
      return;
    }
    final command = await _perform<PreparedCommand>(
      selectedTaskIds == null
          ? 'Compiling the approved task plan'
          : 'Compiling the selected task and dependencies',
      () => runtime.prepareTaskPlan(
        plan: plan,
        promptVersion: version,
        projectId: project.id,
        model: model,
        selectedTaskIds: selectedTaskIds,
      ),
    );
    if (command == null || !mounted) {
      return;
    }
    setState(() {
      prepared = command;
      currentRun = null;
      selectedRunId = null;
      selectedWorkItemId = null;
      evidence = <EvidenceRecord>[];
      approvedScopes
        ..clear()
        ..addAll(command.contract.requiredPermissions);
      area = _StudioArea.chat;
      status = start
          ? 'Generated task plan ready to start'
          : 'Generated task plan ready for review';
    });
    if (start) {
      await _startPrepared();
    }
  }

  void _useGeneratedPromptInChat() {
    final draft = generatedPromptDraft;
    if (draft == null) {
      return;
    }
    setState(() {
      composerController.text = draft.renderForChat();
      chosenMode = draft.mode;
      taskMode = SimpleTaskMode.choose;
      area = _StudioArea.chat;
      prepared = null;
      currentRun = null;
      selectedRunId = null;
    });
    composerFocus.requestFocus();
  }

  Widget _aiPromptComposerCard() {
    final model = selectedModel;
    final hasPendingChoices = promptClarificationSession != null &&
        promptClarificationAnswers.isEmpty;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.lightbulb_outline),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Start with the outcome',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Kristin first turns ambiguity into 2–5 concrete choices. After you answer, it writes the final prompt instead of guessing silently.',
                      ),
                    ],
                  ),
                ),
                _statusPill(
                  model?.name ?? 'No model selected',
                  model == null
                      ? Icons.warning_amber_outlined
                      : Icons.memory_outlined,
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: promptGoalController,
              onChanged: _onPromptGoalChanged,
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: 'Describe the result you want',
                hintText:
                    'Example: Build a polished local desktop calculator with scientific functions, keyboard support, tests, and a clear run guide.',
                helperText:
                    'You do not need to specify every detail — the next step asks only the decisions that matter.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: busy ? null : _startPromptStudioFlow,
                  icon: const Icon(Icons.tune),
                  label: Text(
                    hasPendingChoices
                        ? 'Answer ${promptClarificationSession!.questions.length} choices'
                        : 'Shape this idea',
                  ),
                ),
                if (model == null)
                  OutlinedButton.icon(
                    onPressed:
                        busy ? null : () => _openSettings(initialSection: 1),
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Connect model'),
                  ),
                if (promptClarificationSession != null)
                  TextButton.icon(
                    onPressed: busy ? null : _editPromptClarification,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Review choices'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _promptGenerationStatusCard() {
    final elapsed = promptGenerationElapsed;
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    final attempt = promptGenerationMaxAttempts > 1
        ? ' · attempt $promptGenerationAttempt/$promptGenerationMaxAttempts'
        : '';
    final kind = promptStudioOperationKind;
    final label = switch (kind) {
      _PromptStudioOperationKind.clarification => 'Preparing choices',
      _PromptStudioOperationKind.generate => 'Writing final prompt',
      _PromptStudioOperationKind.improve => 'Improving prompt',
      _PromptStudioOperationKind.simplify => 'Simplifying prompt',
      _PromptStudioOperationKind.addDetail => 'Adding detail',
      _PromptStudioOperationKind.taskPlan => 'Building task plan',
      null => 'Prompt Studio',
    };
    final icon = switch (kind) {
      _PromptStudioOperationKind.clarification => Icons.tune,
      _PromptStudioOperationKind.taskPlan => Icons.account_tree_outlined,
      _ => Icons.auto_awesome,
    };
    final previewLabel = switch (kind) {
      _PromptStudioOperationKind.clarification => 'Live choice draft',
      _PromptStudioOperationKind.taskPlan => 'Live task-plan draft',
      _ => 'Live prompt draft',
    };
    final progress = _promptStudioStageProgress(promptGenerationStage);
    return Card(
      key: promptStudioOperationKey,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        label,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        promptGenerationMessage.isEmpty
                            ? 'Preparing the selected model.'
                            : promptGenerationMessage,
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: promptGenerationCancellation?.isCompleted == true
                      ? null
                      : _cancelStudioPromptGeneration,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _statusPill(
                  promptGenerationStage.replaceAll('_', ' '),
                  Icons.sync,
                ),
                _statusPill('$minutes:$seconds$attempt', Icons.timer_outlined),
                _statusPill(
                  '$promptGenerationCharacters streamed characters',
                  Icons.data_object,
                ),
              ],
            ),
            if (promptGenerationPreview.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 13),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                initiallyExpanded: kind == _PromptStudioOperationKind.taskPlan,
                leading: const Icon(Icons.visibility_outlined),
                title: Text(previewLabel),
                subtitle: const Text(
                  'Partial structured output; the final result is validated before use.',
                ),
                children: <Widget>[
                  _codeBox(promptGenerationPreview, maxLines: 10),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  double? _promptStudioStageProgress(String stage) {
    final value = stage.toLowerCase();
    if (value.contains('ready') || value.contains('completed')) {
      return 1;
    }
    if (value.contains('validat')) {
      return 0.86;
    }
    if (value.contains('first_token') || value.contains('stream')) {
      return 0.58;
    }
    if (value.contains('generation_started') ||
        value.contains('draft_generation') ||
        value.contains('plan_generation')) {
      return 0.42;
    }
    if (value.contains('load') || value.contains('request_open')) {
      return 0.28;
    }
    if (value.contains('clarification_started') || value == 'starting') {
      return 0.12;
    }
    return null;
  }

  Widget _generatedPromptCard(PromptStudioDraft draft) {
    final version = generatedPromptVersion;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.edit_note_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        draft.title,
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 5),
                      Text(draft.purpose),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    _statusPill(modeLabel(draft.mode), Icons.tune_outlined),
                    _statusPill(
                      version == null
                          ? 'Unsaved draft'
                          : 'Prompt v${version.versionNumber}',
                      version == null
                          ? Icons.edit_outlined
                          : Icons.verified_outlined,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (promptClarificationAnswers.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.checklist_rtl_outlined),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '${promptClarificationAnswers.length} product decisions are embedded in this prompt.',
                      ),
                    ),
                    TextButton(
                      onPressed: busy ? null : _editPromptClarification,
                      child: const Text('Edit choices'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            Text(
              'Acceptance criteria',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 7),
            ...draft.acceptanceCriteria.take(8).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.check_circle_outline, size: 18),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(item)),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 10),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              leading: const Icon(Icons.code_outlined),
              title: const Text('Inspect the full prompt'),
              subtitle: const Text(
                'System instructions, task template, variables, guardrails, and expected output.',
              ),
              children: <Widget>[
                _codeBox(
                  'SYSTEM\n${draft.systemPrompt}\n\nUSER TEMPLATE\n${draft.userPrompt}',
                  maxLines: 18,
                ),
                if (draft.variables.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: draft.variables
                        .map((variable) => Chip(label: Text('{{$variable}}')))
                        .toList(),
                  ),
                ],
              ],
            ),
            const Divider(height: 30),
            TextField(
              controller: promptFeedbackController,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Direct revision request',
                hintText:
                    'Example: Keep the scope Windows-only, reduce the first release to four screens, and strengthen offline tests.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: busy ? null : _applyPromptFeedback,
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text('Apply revision'),
                ),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _generateStudioPrompt(
                            PromptGenerationAction.improve,
                          ),
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: const Text('Improve with AI'),
                ),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _generateStudioPrompt(
                            PromptGenerationAction.simplify,
                          ),
                  icon: const Icon(Icons.compress_outlined),
                  label: const Text('Simplify'),
                ),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _generateStudioPrompt(
                            PromptGenerationAction.addDetail,
                          ),
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('Add useful detail'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : _editGeneratedPromptDraft,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit manually'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: busy ? null : _generateStudioTaskPlan,
                  icon: const Icon(Icons.account_tree_outlined),
                  label: const Text('Build task plan'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _saveGeneratedPromptDraft(),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    version == null
                        ? 'Save prompt version'
                        : 'Save new version',
                  ),
                ),
                TextButton.icon(
                  onPressed: _useGeneratedPromptInChat,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Use in chat'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _generatedTaskPlanCard(TaskPlanRecord plan) {
    final phases = <String, List<PlanTaskRecord>>{};
    for (final task in plan.tasks) {
      phases.putIfAbsent(task.phase, () => <PlanTaskRecord>[]).add(task);
    }
    final active = currentRun != null &&
        const <RunState>{
          RunState.running,
          RunState.paused,
          RunState.cancelling,
        }.contains(currentRun!.state);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.account_tree_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        plan.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(plan.rationale),
                    ],
                  ),
                ),
                _statusPill(
                  '${plan.enabledTasks.length}/${plan.tasks.length} tasks',
                  Icons.task_alt,
                ),
                const SizedBox(width: 6),
                _statusPill('Plan v${plan.revision}', Icons.history_outlined),
              ],
            ),
            const SizedBox(height: 13),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: <Widget>[
                Chip(label: Text('${plan.totalEffortPoints} effort points')),
                Chip(label: Text('Max complexity ${plan.maxComplexity}/10')),
                Chip(label: Text('${plan.highRiskTasks} high-risk')),
                Chip(label: Text('${phases.length} phases')),
                Chip(label: Text('${plan.depth.name} depth')),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: busy || active
                      ? null
                      : () => _prepareStudioTaskPlan(start: true),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Run all tasks'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _prepareStudioTaskPlan(),
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('Review execution plan'),
                ),
                if (active)
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _controlRun('cancel'),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop all running tasks'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...phases.entries.map(
              (entry) => Card(
                margin: const EdgeInsets.only(top: 8),
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                child: ExpansionTile(
                  initiallyExpanded: phases.length <= 4,
                  leading: const Icon(Icons.folder_copy_outlined),
                  title: Text(
                    entry.key,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${entry.value.where((task) => task.enabled).length}/${entry.value.length} enabled tasks',
                  ),
                  children: entry.value.map((task) {
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text('${plan.tasks.indexOf(task) + 1}'),
                      ),
                      title: Text(task.title),
                      subtitle: Text(
                        '${task.objective}\n${task.enabled ? 'Enabled' : 'Disabled'}${task.manual ? ' · manual' : ''} · Complexity ${task.complexity}/10 · ${task.effortPoints} points · ${task.risk.name} risk · ${(task.estimateConfidence * 100).round()}% confidence'
                        '${task.dependencies.isEmpty ? '' : '\nDepends on: ${task.dependencies.join(', ')}'}',
                      ),
                      isThreeLine: true,
                      enabled: task.enabled,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Tooltip(
                            message:
                                'Edit this task and save a new plan revision',
                            child: IconButton(
                              onPressed: busy
                                  ? null
                                  : () => _editGeneratedPlanTask(task),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          ),
                          Tooltip(
                            message: task.enabled
                                ? 'Run selected task + dependencies'
                                : 'Enable this task before running it',
                            child: IconButton(
                              onPressed: busy || active || !task.enabled
                                  ? null
                                  : () => _prepareStudioTaskPlan(
                                        selectedTaskIds: <String>{task.id},
                                        start: true,
                                      ),
                              icon: const Icon(Icons.play_circle_outline),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _promptStudioPage() {
    return _page(
      maxWidth: 1280,
      children: <Widget>[
        _pageHeader(
          title: 'Prompt Studio',
          subtitle:
              'A question-first workbench: clarify the important choices, generate a final prompt, shape a visible task graph, then run it under Kristin’s governed controls.',
          actions: <Widget>[
            OutlinedButton.icon(
              onPressed: busy ? null : _resetPromptStudioSession,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Start over'),
            ),
            FilledButton.tonalIcon(
              onPressed: busy ? null : () => _editPrompt(),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Manual prompt'),
            ),
          ],
        ),
        _promptStudioJourneyCard(),
        _promptStudioWorkbench(),
        _promptStudioLibraryCard(),
      ],
    );
  }

  Widget _promptStudioJourneyCard() {
    final hasIdea = promptGoalController.text.trim().isNotEmpty;
    final hasChoices = promptClarificationAnswers.isNotEmpty;
    final hasPrompt = generatedPromptDraft != null;
    final hasPlan = generatedTaskPlan != null;
    final steps = <({String label, String detail, bool done, bool active})>[
      (
        label: 'Idea',
        detail: 'Describe the outcome',
        done: hasIdea,
        active: !hasChoices,
      ),
      (
        label: 'Choices',
        detail: 'Answer 2–5 decisions',
        done: hasChoices,
        active: hasIdea && !hasPrompt,
      ),
      (
        label: 'Prompt',
        detail: 'Review and refine',
        done: hasPrompt,
        active: hasChoices && !hasPlan,
      ),
      (
        label: 'Tasks',
        detail: 'Validate the run graph',
        done: hasPlan,
        active: hasPrompt,
      ),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 760
                ? (constraints.maxWidth - 30) / 4
                : constraints.maxWidth;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                for (var index = 0; index < steps.length; index++)
                  SizedBox(
                    width: width,
                    child: _promptStudioJourneyStep(
                      index + 1,
                      steps[index].label,
                      steps[index].detail,
                      done: steps[index].done,
                      active: steps[index].active,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _promptStudioJourneyStep(
    int number,
    String label,
    String detail, {
    required bool done,
    required bool active,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: done
            ? colors.primaryContainer.withValues(alpha: 0.55)
            : active
                ? colors.secondaryContainer.withValues(alpha: 0.55)
                : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 16,
            child: done ? const Icon(Icons.check, size: 18) : Text('$number'),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                Text(detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _promptStudioWorkbench() {
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _aiPromptComposerCard(),
        if (promptClarificationAnswers.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          _promptDecisionSummaryCard(),
        ],
        if (promptGenerationActive) ...<Widget>[
          const SizedBox(height: 14),
          _promptGenerationStatusCard(),
        ],
        if (generatedPromptDraft != null) ...<Widget>[
          const SizedBox(height: 14),
          _generatedPromptCard(generatedPromptDraft!),
        ],
        if (generatedTaskPlan != null) ...<Widget>[
          const SizedBox(height: 14),
          _generatedTaskPlanCard(generatedTaskPlan!),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 980) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              main,
              const SizedBox(height: 14),
              _promptStudioControlRail(),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(flex: 7, child: main),
            const SizedBox(width: 16),
            SizedBox(width: 310, child: _promptStudioControlRail()),
          ],
        );
      },
    );
  }

  Widget _promptDecisionSummaryCard() {
    final session = promptClarificationSession;
    if (session == null) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.fact_check_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Decisions captured',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      if (session.brief.isNotEmpty) Text(session.brief),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: busy ? null : _editPromptClarification,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...session.questions.map((question) {
              final answer = promptClarificationAnswers[question.id] ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.arrow_right, size: 19),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            question.question,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(answer),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _promptStudioControlRail() {
    final project = selectedProject;
    final model = selectedModel;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Session controls',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 12),
            _statusPill(
              project?.name ?? 'No project selected',
              Icons.folder_outlined,
            ),
            const SizedBox(height: 8),
            _statusPill(
              model?.name ?? 'No model selected',
              Icons.memory_outlined,
            ),
            const Divider(height: 26),
            DropdownButtonFormField<PlanningDepth>(
              initialValue: generatedPlanningDepth,
              decoration: const InputDecoration(
                labelText: 'Planning depth',
                prefixIcon: Icon(Icons.layers_outlined),
              ),
              items: PlanningDepth.values
                  .map(
                    (item) => DropdownMenuItem<PlanningDepth>(
                      value: item,
                      child: Text(item.name),
                    ),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => generatedPlanningDepth = value);
                      }
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: generatedMaxTasks,
              decoration: const InputDecoration(
                labelText: 'Task ceiling',
                prefixIcon: Icon(Icons.format_list_numbered),
              ),
              items: const <int>[1, 3, 5, 7, 10, 15, 25]
                  .map(
                    (value) => DropdownMenuItem<int>(
                      value: value,
                      child: Text('$value task${value == 1 ? '' : 's'}'),
                    ),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => generatedMaxTasks = value);
                      }
                    },
            ),
            const Divider(height: 26),
            const Text(
              'Optimized local path',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 7),
            const Text(
              '• Choice pass: up to 1,024 tokens\n'
              '• Prompt pass: up to 2,048 tokens\n'
              '• One bounded repair only\n'
              '• Active Ollama session is reused',
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: busy ? null : () => _openSettings(initialSection: 1),
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Model settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _promptStudioLibraryCard() {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: const Icon(Icons.library_books_outlined),
        title: const Text(
          'Prompt library',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          '${prompts.length} saved prompts · ${studioTemplates.length} starter templates',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: <Widget>[
          if (prompts.isEmpty)
            _emptyPanel(
              icon: Icons.edit_note_outlined,
              title: 'No saved prompts yet',
              message:
                  'Save the generated prompt when it becomes a reusable workflow.',
              actionLabel: 'Create manually',
              onAction: _editPrompt,
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 820
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: prompts
                      .map(
                        (prompt) => SizedBox(
                          width: width,
                          child: _promptCard(prompt),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          const Divider(height: 30),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Starter ideas',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          ...studioTemplates.map(
            (template) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(template.icon),
              title: Text(template.title),
              subtitle: Text(template.description),
              trailing: OutlinedButton(
                onPressed: busy
                    ? null
                    : () {
                        promptGoalController.text = template.prompt;
                        _onPromptGoalChanged(template.prompt);
                      },
                child: const Text('Use as idea'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _promptCard(PromptTemplateRecord prompt) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.edit_note_outlined),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    prompt.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                _statusPill('v${prompt.version}', Icons.history),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      _editPrompt(prompt: prompt);
                    } else if (value == 'delete') {
                      _deletePrompt(prompt);
                    } else if (value == 'copy') {
                      Clipboard.setData(
                        ClipboardData(text: prompt.renderForChat()),
                      );
                    }
                  },
                  itemBuilder: (context) => const <PopupMenuEntry<String>>[
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(
                      value: 'copy',
                      child: Text('Copy rendered prompt'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            if (prompt.description.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(prompt.description),
            ],
            const SizedBox(height: 11),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                Chip(label: Text(modeLabel(prompt.mode))),
                ...prompt.variables.map(
                  (variable) => Chip(label: Text('{{$variable}}')),
                ),
                ...prompt.tags.map((tag) => Chip(label: Text(tag))),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              prompt.userPrompt,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: () => _usePrompt(prompt),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Use in chat'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _editPrompt(prompt: prompt),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _usePrompt(PromptTemplateRecord prompt) {
    setState(() {
      composerController.text = prompt.renderForChat();
      taskMode = SimpleTaskMode.choose;
      chosenMode = prompt.mode;
      area = _StudioArea.chat;
      prepared = null;
      currentRun = null;
      selectedRunId = null;
    });
    composerFocus.requestFocus();
  }

  Future<void> _editPrompt({
    PromptTemplateRecord? prompt,
    StudioTemplate? template,
  }) async {
    final result = await showDialog<_PromptDraft>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _PromptEditorDialog(prompt: prompt, template: template),
    );
    if (result == null) {
      return;
    }
    final saved = await _perform<PromptTemplateRecord>(
      prompt == null ? 'Saving prompt' : 'Saving prompt version',
      () => runtime.savePrompt(
        id: prompt?.id,
        title: result.title,
        description: result.description,
        systemPrompt: result.systemPrompt,
        userPrompt: result.userPrompt,
        variables: result.variables,
        tags: result.tags,
        mode: result.mode,
      ),
    );
    if (saved != null) {
      await _refreshPrompts(silent: true);
    }
  }

  Future<void> _deletePrompt(PromptTemplateRecord prompt) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete prompt?'),
            content: Text(
              'Delete “${prompt.title}” and its saved configuration?',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      return;
    }
    await _perform<void>(
      'Deleting prompt',
      () => runtime.deletePrompt(prompt.id),
    );
    await _refreshPrompts(silent: true);
  }

  Widget _knowledgePage() {
    final project = selectedProject;
    final stats = knowledgeStatsValue;
    final notes = knowledge
        .where((entry) => entry.kind == KnowledgeKind.note)
        .toList(growable: false);
    final pinnedEntries =
        knowledge.where((entry) => entry.pinned).toList(growable: false);
    final pinnedEpisodes = memoryEpisodes
        .where((episode) => episode.pinned)
        .toList(growable: false);
    return _page(
      maxWidth: 1220,
      children: <Widget>[
        _pageHeader(
          title: 'Knowledge & memory',
          subtitle:
              'Search local notes, immutable research snapshots, and lessons from previous governed runs. Every retrieved excerpt has an inspectable citation.',
          actions: <Widget>[
            OutlinedButton.icon(
              onPressed: project == null || busy ? null : _rebuildKnowledge,
              icon: const Icon(Icons.refresh),
              label: const Text('Reindex'),
            ),
            OutlinedButton.icon(
              onPressed: project == null || busy ? null : _exportKnowledge,
              icon: const Icon(Icons.archive_outlined),
              label: const Text('Export'),
            ),
            FilledButton.icon(
              onPressed: project == null || busy ? null : _addKnowledgeNote,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Add note'),
            ),
          ],
        ),
        if (project == null)
          _emptyPanel(
            icon: Icons.folder_outlined,
            title: 'Choose a project',
            message:
                'Knowledge, research, and run memory are isolated by project so unrelated work does not share context.',
            actionLabel: 'Open projects',
            onAction: () => setState(() => area = _StudioArea.projects),
          )
        else ...<Widget>[
          _metricRow(<_MetricData>[
            _MetricData(
              label: 'Research sources',
              value:
                  '${stats?.researchSources ?? researchArchive.where((item) => item.kind == ResearchArchiveKind.source).length}',
              icon: Icons.language_outlined,
            ),
            _MetricData(
              label: 'Search snapshots',
              value:
                  '${stats?.searchSnapshots ?? researchArchive.where((item) => item.kind == ResearchArchiveKind.search).length}',
              icon: Icons.search,
            ),
            _MetricData(
              label: 'Run memories',
              value: '${stats?.episodes ?? memoryEpisodes.length}',
              icon: Icons.history_outlined,
            ),
            _MetricData(
              label: 'Indexed excerpts',
              value: '${stats?.indexedChunks ?? 0}',
              icon: Icons.search,
            ),
          ]),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.inventory_2_outlined),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            const Expanded(
                              child: Text(
                                'Local evidence library',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            Text(
                              _formatBytes(stats?.archiveBytes ?? 0),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Raw responses and extracted text are stored as content-addressed objects. Search combines lexical relevance, a local semantic signal, recency, trust, and pinned items without sending the index to a cloud service.',
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          '${runtime.directories.root.path}/research-archive',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (lastKnowledgeExportPath != null) ...<Widget>[
                          const SizedBox(height: 8),
                          SelectableText(
                            'Latest export: $lastKnowledgeExportPath',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: busy ? null : _refreshKnowledge,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          ),
          TextField(
            controller: knowledgeSearchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search sources, notes, and previous run lessons',
              helperText:
                  'Press Enter to retrieve ranked excerpts. Results use citation labels such as K1 and K2.',
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (knowledgeSearchController.text.trim().isNotEmpty)
                    IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        knowledgeSearchController.clear();
                        setState(() => knowledgeRetrieval = null);
                      },
                      icon: const Icon(Icons.close),
                    ),
                  IconButton(
                    tooltip: 'Search knowledge',
                    onPressed: busy ? null : _runKnowledgeSearch,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ],
              ),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _runKnowledgeSearch(),
          ),
          if (knowledgeRetrieval != null)
            _knowledgeSearchResults(knowledgeRetrieval!),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _KnowledgeView.values
                .map(
                  (view) => ChoiceChip(
                    selected: knowledgeView == view,
                    avatar: Icon(_knowledgeViewIcon(view), size: 18),
                    label: Text(_knowledgeViewLabel(view)),
                    onSelected: (_) => setState(() => knowledgeView = view),
                  ),
                )
                .toList(),
          ),
          if (knowledgeView == _KnowledgeView.overview) ...<Widget>[
            if (pinnedEntries.isNotEmpty ||
                pinnedEpisodes.isNotEmpty) ...<Widget>[
              _sectionTitle(
                'Pinned context',
                Icons.center_focus_strong_outlined,
              ),
              ...pinnedEntries.take(4).map(_knowledgeCard),
              ...pinnedEpisodes.take(4).map(_memoryEpisodeCard),
            ],
            _sectionTitle('Recent research', Icons.language_outlined),
            if (researchArchive.isEmpty)
              _emptyPanel(
                icon: Icons.search,
                title: 'No archived research yet',
                message:
                    'Ask Kristin to research a public HTTPS source. The fetched response, extracted text, hashes, redirects, and metadata will be retained here.',
              )
            else
              ...researchArchive.take(5).map(_researchArchiveCard),
            _sectionTitle('Recent run memory', Icons.history_outlined),
            if (memoryEpisodes.isEmpty)
              _emptyPanel(
                icon: Icons.history_outlined,
                title: 'No completed run memories yet',
                message:
                    'Successful, failed, cancelled, and recovered runs become project-scoped episodes with outcomes, changed files, validation evidence, and lessons.',
              )
            else
              ...memoryEpisodes.take(5).map(_memoryEpisodeCard),
          ] else if (knowledgeView == _KnowledgeView.sources) ...<Widget>[
            _sectionTitle('Research archive', Icons.inventory_2_outlined),
            if (researchArchive.isEmpty)
              _emptyPanel(
                icon: Icons.language_outlined,
                title: 'Research archive is empty',
                message:
                    'Approved web fetches and search snapshots will appear here as immutable provenance records.',
              )
            else
              ...researchArchive.map(_researchArchiveCard),
          ] else if (knowledgeView == _KnowledgeView.notes) ...<Widget>[
            _sectionTitle('Project notes', Icons.note_alt_outlined),
            if (notes.isEmpty)
              _emptyPanel(
                icon: Icons.note_add_outlined,
                title: 'No project notes yet',
                message:
                    'Save requirements, decisions, terminology, constraints, and verified facts for later retrieval.',
                actionLabel: 'Add a note',
                onAction: _addKnowledgeNote,
              )
            else
              ...notes.map(_knowledgeCard),
          ] else ...<Widget>[
            _sectionTitle('Episodic run memory', Icons.history_outlined),
            if (memoryEpisodes.isEmpty)
              _emptyPanel(
                icon: Icons.history_outlined,
                title: 'No run memory yet',
                message:
                    'Complete a governed task and Kristin will preserve the request, outcome, verification, changed files, and failure lessons for future retrieval.',
              )
            else
              ...memoryEpisodes.map(_memoryEpisodeCard),
          ],
        ],
      ],
    );
  }

  Widget _sectionTitle(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );

  Widget _knowledgeSearchResults(KnowledgeRetrieval retrieval) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.search),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        retrieval.query.isEmpty
                            ? 'Latest indexed context'
                            : 'Results for “${retrieval.query}”',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${retrieval.hits.length} excerpts · ${retrieval.documentsScanned} records · ${retrieval.chunksScanned} chunks scanned locally',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Clear results',
                  onPressed: () => setState(() => knowledgeRetrieval = null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (retrieval.hits.isEmpty) ...<Widget>[
              const SizedBox(height: 14),
              const Text(
                'No matching excerpts were found. Add a note, complete a run, archive research, or try broader terms.',
              ),
            ] else ...<Widget>[
              const SizedBox(height: 12),
              ...retrieval.hits.map(_knowledgeSearchHitCard),
            ],
          ],
        ),
      ),
    );
  }

  Widget _knowledgeSearchHitCard(KnowledgeSearchHit hit) {
    final percent = (hit.score * 100).clamp(0.0, 100.0).toDouble().round();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hit.citation,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 9),
              Icon(_knowledgeKindIcon(hit.kind), size: 20),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      hit.title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${_knowledgeKindLabel(hit.kind)} · relevance $percent% · ${_timeLabel(hit.capturedAt)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copy citation excerpt',
                onPressed: () => Clipboard.setData(
                  ClipboardData(
                    text:
                        '[${hit.citation}] ${hit.title}\n${hit.sourceUrl}\n${hit.snippet}',
                  ),
                ),
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(hit.snippet),
          if (hit.sourceUrl.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            SelectableText(
              hit.sourceUrl,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              Chip(label: Text('lexical ${(hit.lexicalScore * 100).round()}%')),
              Chip(
                label: Text('semantic ${(hit.semanticScore * 100).round()}%'),
              ),
              Chip(label: Text('recency ${(hit.recencyScore * 100).round()}%')),
              if (hit.trust.isNotEmpty) Chip(label: Text(hit.trust)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _knowledgeCard(KnowledgeEntry entry) {
    final archived = entry.kind != KnowledgeKind.note;
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: Icon(_knowledgeKindIcon(entry.kind)),
        title: Text(
          entry.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${_knowledgeKindLabel(entry.kind)} · ${_timeLabel(entry.updatedAt)}${entry.pinned ? ' · pinned' : ''}',
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'pin') {
              _toggleKnowledgePin(entry);
            } else if (value == 'copy') {
              Clipboard.setData(ClipboardData(text: entry.content));
            } else if (value == 'source' && entry.sourceUrl.isNotEmpty) {
              Clipboard.setData(ClipboardData(text: entry.sourceUrl));
            } else if (value == 'use') {
              setState(() {
                composerController.text =
                    'Use this project knowledge while answering my next request:\n\n${entry.title}\n${entry.content}';
                area = _StudioArea.chat;
              });
              composerFocus.requestFocus();
            } else if (value == 'delete') {
              _deleteKnowledge(entry);
            }
          },
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            PopupMenuItem(
              value: 'pin',
              child: Text(entry.pinned ? 'Unpin' : 'Pin for retrieval'),
            ),
            const PopupMenuItem(value: 'use', child: Text('Use in chat')),
            const PopupMenuItem(value: 'copy', child: Text('Copy content')),
            if (entry.sourceUrl.isNotEmpty)
              const PopupMenuItem(
                value: 'source',
                child: Text('Copy source URL'),
              ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'delete',
              child: Text(archived ? 'Remove from retrieval' : 'Delete note'),
            ),
          ],
        ),
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                if (entry.pinned)
                  const Chip(
                    avatar: Icon(Icons.center_focus_strong_outlined, size: 16),
                    label: Text('pinned'),
                  ),
                ...entry.tags.map((tag) => Chip(label: Text(tag))),
              ],
            ),
          ),
          if (entry.sourceUrl.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                entry.sourceUrl,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(entry.content),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              'SHA-256: ${entry.contentHash}${entry.archiveId.isEmpty ? '' : '\nArchive: ${entry.archiveId}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (archived) ...<Widget>[
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'External content is treated as untrusted data, never as agent instructions.',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _researchArchiveCard(ResearchArchiveRecord record) {
    final isSearch = record.kind == ResearchArchiveKind.search;
    final destination =
        record.finalUrl.isNotEmpty ? record.finalUrl : record.requestedUrl;
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: Icon(isSearch ? Icons.search : Icons.language_outlined),
        title: Text(
          record.title.isEmpty
              ? (isSearch ? 'Search snapshot' : destination)
              : record.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${isSearch ? '${record.resultCount} results' : '${record.statusCode} · ${record.mimeType}'} · ${_timeLabel(record.capturedAt)} · ${_formatBytes(record.byteLength)}',
        ),
        trailing: IconButton(
          tooltip: 'Copy provenance',
          onPressed: () => Clipboard.setData(
            ClipboardData(text: _archiveProvenance(record)),
          ),
          icon: const Icon(Icons.copy_outlined),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              _archiveProvenance(record),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (record.redirectChain.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Redirect chain (${record.redirectChain.length})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ...record.redirectChain.map(
              (item) => Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(item),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _memoryEpisodeCard(MemoryEpisode episode) {
    final succeeded = episode.outcome == RunState.succeeded;
    final title = episode.request.trim().isEmpty
        ? 'Run ${episode.runId}'
        : episode.request.trim();
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        leading: Icon(
          succeeded ? Icons.check_circle_outline : Icons.error_outline,
        ),
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${friendlyRunState(episode.outcome)} · ${episode.mode.name} · ${_timeLabel(episode.completedAt)}${episode.pinned ? ' · pinned' : ''}',
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'pin') {
              _toggleMemoryPin(episode);
            } else if (value == 'copy') {
              Clipboard.setData(ClipboardData(text: episode.lessons));
            } else if (value == 'chat') {
              setState(() {
                composerController.text =
                    'Review this prior run and help me improve or continue it:\n\nRequest: ${episode.request}\nOutcome: ${episode.outcome.name}\nLessons: ${episode.lessons}';
                area = _StudioArea.chat;
              });
              composerFocus.requestFocus();
            } else if (value == 'run') {
              final match =
                  runs.where((run) => run.id == episode.runId).firstOrNull;
              if (match != null) {
                _selectRun(match);
                setState(() => area = _StudioArea.runs);
              }
            }
          },
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            PopupMenuItem(
              value: 'pin',
              child: Text(episode.pinned ? 'Unpin' : 'Pin for retrieval'),
            ),
            const PopupMenuItem(value: 'chat', child: Text('Continue in chat')),
            const PopupMenuItem(value: 'copy', child: Text('Copy lessons')),
            const PopupMenuItem(
              value: 'run',
              child: Text('Inspect original run'),
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: <Widget>[
          if (episode.summary.trim().isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(episode.summary),
            ),
          if (episode.failure.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Failure: ${episode.failure}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Lessons',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 5),
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(episode.lessons),
          ),
          if (episode.filesChanged.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Changed files (${episode.filesChanged.length})',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ...episode.filesChanged.take(30).map(
                  (path) => Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(path),
                  ),
                ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                Chip(label: Text('${episode.modelRequests} model calls')),
                Chip(label: Text('${episode.toolCalls} tool calls')),
                Chip(label: Text('${episode.mutations} mutations')),
                Chip(label: Text('${episode.repairs} repairs')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runKnowledgeSearch() async {
    final projectId = selectedProjectId;
    if (projectId == null) {
      return;
    }
    final query = knowledgeSearchController.text.trim();
    if (query.isEmpty) {
      setState(() => knowledgeRetrieval = null);
      return;
    }
    final result = await _perform<KnowledgeRetrieval>(
      'Searching local knowledge',
      () => runtime.searchKnowledge(
        projectId,
        query,
        limit: 12,
        includeEpisodes: true,
        includeUnsuccessfulEpisodes: isFailureInvestigationRequest(query),
      ),
    );
    if (result != null && mounted) {
      setState(() => knowledgeRetrieval = result);
    }
  }

  Future<void> _rebuildKnowledge() async {
    final projectId = selectedProjectId;
    if (projectId == null) {
      return;
    }
    final count = await _perform<int>(
      'Rebuilding local knowledge index',
      () => runtime.rebuildKnowledgeIndex(projectId),
    );
    if (count != null) {
      await _refreshKnowledge(silent: true);
      if (mounted) {
        setState(() => status = 'Indexed $count knowledge and memory excerpts');
      }
    }
  }

  Future<void> _exportKnowledge() async {
    final projectId = selectedProjectId;
    if (projectId == null) {
      return;
    }
    final file = await _perform<File>(
      'Creating portable knowledge archive',
      () => runtime.exportKnowledge(projectId),
    );
    if (file != null && mounted) {
      setState(() {
        lastKnowledgeExportPath = file.path;
        status = 'Knowledge export created';
      });
    }
  }

  Future<void> _toggleKnowledgePin(KnowledgeEntry entry) async {
    final updated = await _perform<KnowledgeEntry>(
      entry.pinned ? 'Unpinning knowledge' : 'Pinning knowledge',
      () => runtime.setKnowledgePinned(entry.id, !entry.pinned),
    );
    if (updated != null) {
      await _refreshKnowledge(silent: true);
    }
  }

  Future<void> _toggleMemoryPin(MemoryEpisode episode) async {
    final updated = await _perform<MemoryEpisode>(
      episode.pinned ? 'Unpinning run memory' : 'Pinning run memory',
      () => runtime.setMemoryPinned(episode.id, !episode.pinned),
    );
    if (updated != null) {
      await _refreshKnowledge(silent: true);
    }
  }

  String _archiveProvenance(ResearchArchiveRecord record) {
    final buffer = StringBuffer()
      ..writeln('Archive ID: ${record.id}')
      ..writeln('Type: ${record.kind.name}')
      ..writeln('Captured: ${record.capturedAt.toUtc().toIso8601String()}')
      ..writeln('Provider: ${record.provider}')
      ..writeln('Requested URL: ${record.requestedUrl}')
      ..writeln('Final URL: ${record.finalUrl}')
      ..writeln('Status: ${record.statusCode}')
      ..writeln('MIME type: ${record.mimeType}')
      ..writeln('Content hash: ${record.contentHash}')
      ..writeln('Raw hash: ${record.rawContentHash}')
      ..writeln('Raw object: ${record.rawObjectPath}')
      ..writeln('Text object: ${record.textObjectPath}');
    if (record.query.isNotEmpty) {
      buffer.writeln('Query: ${record.query}');
    }
    return buffer.toString().trim();
  }

  IconData _knowledgeViewIcon(_KnowledgeView view) => switch (view) {
        _KnowledgeView.overview => Icons.dashboard_outlined,
        _KnowledgeView.sources => Icons.language_outlined,
        _KnowledgeView.notes => Icons.note_alt_outlined,
        _KnowledgeView.memory => Icons.history_outlined,
      };

  String _knowledgeViewLabel(_KnowledgeView view) => switch (view) {
        _KnowledgeView.overview => 'Overview',
        _KnowledgeView.sources => 'Sources',
        _KnowledgeView.notes => 'Notes',
        _KnowledgeView.memory => 'Run memory',
      };

  IconData _knowledgeKindIcon(KnowledgeKind kind) => switch (kind) {
        KnowledgeKind.note => Icons.note_alt_outlined,
        KnowledgeKind.researchSource => Icons.language_outlined,
        KnowledgeKind.researchSearch => Icons.search,
        KnowledgeKind.episode => Icons.history_outlined,
      };

  String _knowledgeKindLabel(KnowledgeKind kind) => switch (kind) {
        KnowledgeKind.note => 'Project note',
        KnowledgeKind.researchSource => 'Archived source',
        KnowledgeKind.researchSearch => 'Search snapshot',
        KnowledgeKind.episode => 'Prior run memory',
      };

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GiB';
  }

  Future<void> _addKnowledgeNote() async {
    final project = selectedProject;
    if (project == null) {
      return;
    }
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final tagsController = TextEditingController();
    final result =
        await showDialog<({String title, String content, Set<String> tags})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.note_add_outlined),
        title: const Text('Add project knowledge'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                minLines: 5,
                maxLines: 12,
                decoration: const InputDecoration(
                  labelText: 'Content',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags',
                  hintText: 'architecture, customer, decision',
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop((
              title: titleController.text.trim(),
              content: contentController.text.trim(),
              tags: tagsController.text
                  .split(',')
                  .map((tag) => tag.trim().toLowerCase())
                  .where((tag) => tag.isNotEmpty)
                  .toSet(),
            )),
            child: const Text('Save note'),
          ),
        ],
      ),
    );
    titleController.dispose();
    contentController.dispose();
    tagsController.dispose();
    if (result == null || result.title.isEmpty || result.content.isEmpty) {
      return;
    }
    final saved = await _perform<KnowledgeEntry>(
      'Saving project knowledge',
      () => runtime.addKnowledge(
        projectId: project.id,
        title: result.title,
        content: result.content,
        tags: result.tags,
      ),
    );
    if (saved != null) {
      await _refreshKnowledge(silent: true);
    }
  }

  Future<void> _deleteKnowledge(KnowledgeEntry entry) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete knowledge entry?'),
            content: Text(
              'Delete “${entry.title}” from this project’s knowledge?',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      return;
    }
    await _perform<void>(
      'Deleting knowledge entry',
      () => runtime.deleteKnowledge(entry.id),
    );
    await _refreshKnowledge(silent: true);
  }

  Widget _skillsPage() {
    return _page(
      maxWidth: 1120,
      children: <Widget>[
        _pageHeader(
          title: 'Skills',
          subtitle:
              'Reusable product-authored procedures guide the agent without expanding project paths, tools, permissions, or budgets.',
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.verified_user_outlined),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Controlled learning',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'Kristin can reuse archived project knowledge today. Automatic self-modification is intentionally disabled. A future learned skill should be proposed as a draft, replay-tested, reviewed, versioned, and reversible before activation.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        ...skills.map(_skillCard),
      ],
    );
  }

  Widget _skillCard(SkillPackage skill) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: const Icon(Icons.extension_outlined),
        title: Text(
          skill.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(skill.id),
        trailing: _statusPill('Built in', Icons.lock_outline),
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Text(skill.instructions),
          ),
          const SizedBox(height: 13),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Triggers',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: skill.triggers
                  .map((trigger) => Chip(label: Text(trigger)))
                  .toList(),
            ),
          ),
          const SizedBox(height: 13),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Recommended tools',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: skill.recommendedTools
                  .map((tool) => Chip(label: Text(tool)))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _logsPage() {
    final query = logSearchController.text.trim().toLowerCase();
    final runId = selectedRunId;
    final filtered = events.where((event) {
      if (runId != null &&
          event.correlationId != runId &&
          event.data['runId']?.toString() != runId) {
        return false;
      }
      if (query.isEmpty) {
        return true;
      }
      return event.type.toLowerCase().contains(query) ||
          event.correlationId.toLowerCase().contains(query) ||
          jsonEncode(event.data).toLowerCase().contains(query) ||
          _humanEvent(event).toLowerCase().contains(query);
    }).toList(growable: false);
    return _page(
      maxWidth: 1240,
      children: <Widget>[
        _pageHeader(
          title: 'Logs',
          subtitle:
              'Start simple, expand to technical detail, or inspect raw structured events with shared run and work-item IDs.',
          actions: <Widget>[
            OutlinedButton.icon(
              onPressed: busy ? null : _verifyAudit,
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Verify audit'),
            ),
            FilledButton.icon(
              onPressed: busy ? null : _createSupportBundle,
              icon: const Icon(Icons.archive_outlined),
              label: const Text('Save all logs'),
            ),
          ],
        ),
        if (auditReport != null)
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(
                auditReport?['valid'] == true
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
              ),
              title: Text(
                auditReport?['valid'] == true
                    ? 'Audit chain verified'
                    : 'Audit verification found a problem',
              ),
              subtitle: Text(
                const JsonEncoder.withIndent(' ').convert(auditReport),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        if (lastSupportBundlePath != null)
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Diagnostic log bundle created'),
              subtitle: SelectableText(lastSupportBundlePath!),
              trailing: IconButton(
                tooltip: 'Copy path',
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: lastSupportBundlePath!),
                ),
                icon: const Icon(Icons.copy_outlined),
              ),
            ),
          ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                const Text(
                  'Detail:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                ..._LogView.values.map(
                  (view) => ChoiceChip(
                    selected: logView == view,
                    label: Text(switch (view) {
                      _LogView.simple => 'Simple',
                      _LogView.technical => 'Technical',
                      _LogView.raw => 'Raw JSON',
                    }),
                    onSelected: (_) => setState(() => logView = view),
                  ),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  selected: selectedRunId == null,
                  label: const Text('All events'),
                  onSelected: (_) => setState(() => selectedRunId = null),
                ),
                if (currentRun != null)
                  ChoiceChip(
                    selected: selectedRunId == currentRun!.id,
                    label: const Text('Current run only'),
                    onSelected: (_) =>
                        setState(() => selectedRunId = currentRun!.id),
                  ),
              ],
            ),
          ),
        ),
        TextField(
          controller: logSearchController,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Search type, message, run ID, work item, or payload',
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    onPressed: () {
                      logSearchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (filtered.isEmpty)
          _emptyPanel(
            icon: Icons.terminal_outlined,
            title: events.isEmpty ? 'No events yet' : 'No matching log events',
            message: events.isEmpty
                ? 'Run a task or a project diagnostic to create correlated events.'
                : 'Change the search or switch to all events.',
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: filtered.reversed.take(300).map((event) {
                return _logEventTile(event);
              }).toList(),
            ),
          ),
      ],
    );
  }

  Widget _logEventTile(EventEnvelope event) {
    final raw = const JsonEncoder.withIndent(' ').convert(event.toJson());
    final technical = <String>[
      event.type,
      'sequence=${event.sequence}',
      'correlation=${event.correlationId}',
      if (event.data['runId'] != null) 'run=${event.data['runId']}',
      if (event.data['workItemId'] != null)
        'workItem=${event.data['workItemId']}',
    ].join(' · ');
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      leading: Icon(_eventIcon(event.type), size: 20),
      title: Text(
        logView == _LogView.raw ? event.type : _humanEvent(event),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        logView == _LogView.simple
            ? _timeLabel(event.timestamp)
            : '$technical · ${event.timestamp.toLocal().toIso8601String()}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: 'Copy event',
        onPressed: () => Clipboard.setData(ClipboardData(text: raw)),
        icon: const Icon(Icons.copy_outlined, size: 19),
      ),
      children: <Widget>[
        if (logView == _LogView.simple)
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Event type: ${event.type}'),
          )
        else
          _codeBox(
            logView == _LogView.technical
                ? const JsonEncoder.withIndent(' ').convert(event.data)
                : raw,
            maxLines: 22,
          ),
      ],
    );
  }

  Future<void> _verifyAudit() async {
    final result = await _perform<Map<String, dynamic>>(
      'Verifying audit chain',
      runtime.verifyAudit,
    );
    if (result != null && mounted) {
      setState(() => auditReport = result);
    }
  }

  Future<void> _createSupportBundle() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            icon: const Icon(Icons.archive_outlined),
            title: const Text('Save all diagnostic logs?'),
            content: const SizedBox(
              width: 560,
              child: Text(
                'Kristin will create a redacted ZIP containing retained events, audit records, run state, evidence metadata, budget counters, and bounded process logs. Source-like payloads are replaced by hashes, but the archive can still contain project names, request text, URLs, relative paths, command output, error messages, and model-response previews. Review it before sharing.',
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.save_alt_outlined),
                label: const Text('Save all logs'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) {
      return;
    }
    final file = await _perform<dynamic>(
      'Saving redacted diagnostic logs',
      () => runtime.createSupportBundle(
        projectId: selectedProject?.id,
        runId: selectedRunId ?? currentRun?.id,
        includeAllLogs: true,
      ),
    );
    if (file != null && mounted) {
      setState(() {
        lastSupportBundlePath = file.path.toString();
      });
    }
  }

  Widget _page({required double maxWidth, required List<Widget> children}) {
    return ListView(
      padding: const EdgeInsets.all(22),
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ...children.expand(
                  (child) => <Widget>[child, const SizedBox(height: 14)],
                ),
                const SizedBox(height: 70),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _pageHeader({
    required String title,
    required String subtitle,
    List<Widget> actions = const <Widget>[],
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 680;
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        );
        if (compact || actions.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              text,
              if (actions.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: text),
            const SizedBox(width: 20),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        );
      },
    );
  }

  Widget _emptyPanel({
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: <Widget>[
            Icon(icon, size: 38, color: colors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Text(message, textAlign: TextAlign.center),
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metricRow(List<_MetricData> metrics) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 760
            ? (constraints.maxWidth - (metrics.length - 1) * 10) /
                metrics.length
            : constraints.maxWidth;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: width,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: <Widget>[
                          Icon(metric.icon),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  metric.value,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                Text(metric.label),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _statusPill(String label, IconData icon) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _codeBox(String value, {int maxLines = 12}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: SelectableText(
        value,
        maxLines: maxLines,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }

  List<EventEnvelope> _eventsForRun(RunRecord run) => events.where((event) {
        return event.correlationId == run.id ||
            event.data['runId']?.toString() == run.id;
      }).toList(growable: false);

  String _humanEvent(EventEnvelope event) {
    final type = event.type;
    if (type == 'run.created') {
      return 'Run created';
    }
    if (type == 'run.approved') {
      return 'Access approved for the run';
    }
    if (type == 'run.started') {
      return 'Kristin started working';
    }
    if (type == 'run.paused') {
      return 'Run paused';
    }
    if (type == 'run.resumed') {
      return 'Run resumed';
    }
    if (type == 'run.succeeded') {
      return 'Run completed successfully';
    }
    if (type == 'run.failed') {
      return 'Run failed';
    }
    if (type == 'run.cancelled') {
      return 'Run stopped';
    }
    if (type == 'work_item.started') {
      return 'Started ${event.data['title'] ?? 'a work item'}';
    }
    if (type == 'work_item.succeeded') {
      return 'Completed ${event.data['title'] ?? 'a work item'}';
    }
    if (type == 'work_item.failed') {
      return 'A work item needs attention';
    }
    if (type == 'tool.started') {
      return 'Running ${event.data['tool'] ?? 'a tool'}';
    }
    if (type == 'tool.completed') {
      return 'Completed ${event.data['tool'] ?? 'a tool'}';
    }
    if (type == 'evidence.recorded') {
      return 'Evidence recorded';
    }
    if (type == 'diagnostics.started') {
      return 'Project tests started';
    }
    if (type == 'diagnostics.completed') {
      return 'Project diagnostics completed';
    }
    if (type == 'research.fetch.completed') {
      return 'Web source archived';
    }
    if (type == 'prompt.saved') {
      return 'Prompt version saved';
    }
    return type.replaceAll('.', ' ');
  }

  String _areaTitle(_StudioArea value) => switch (value) {
        _StudioArea.chat => 'New chat',
        _StudioArea.chats => 'Chats',
        _StudioArea.projects => 'Project Manager',
        _StudioArea.runs => 'Runs',
        _StudioArea.promptStudio => 'Prompt Studio',
        _StudioArea.knowledge => 'Knowledge',
        _StudioArea.skills => 'Skills',
        _StudioArea.logs => 'Logs',
      };

  String _timeLabel(DateTime value) {
    final local = value.toLocal();
    final difference = DateTime.now().difference(local);
    if (difference.inMinutes < 1) {
      return 'just now';
    }
    if (difference.inHours < 1) {
      return '${difference.inMinutes} min ago';
    }
    if (difference.inDays < 1) {
      return '${difference.inHours} h ago';
    }
    if (difference.inDays < 7) {
      return '${difference.inDays} d ago';
    }
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  String _durationLabel(Duration value) {
    if (value.inSeconds < 60) {
      return '${value.inSeconds}s';
    }
    if (value.inMinutes < 60) {
      return '${value.inMinutes}m ${value.inSeconds.remainder(60)}s';
    }
    return '${value.inHours}h ${value.inMinutes.remainder(60)}m';
  }

  Widget _runStateIcon(RunState state, {double size = 22}) {
    final colors = Theme.of(context).colorScheme;
    final icon = _runStateIconData(state);
    final color = switch (state) {
      RunState.succeeded => colors.primary,
      RunState.failed => colors.error,
      RunState.running => colors.tertiary,
      RunState.paused || RunState.interrupted => colors.secondary,
      _ => colors.onSurfaceVariant,
    };
    if (state == RunState.running) {
      return SizedBox.square(
        dimension: size,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
    }
    return Icon(icon, size: size, color: color);
  }

  IconData _runStateIconData(RunState state) => switch (state) {
        RunState.prepared => Icons.description_outlined,
        RunState.awaitingApproval => Icons.lock_clock_outlined,
        RunState.queued => Icons.schedule,
        RunState.running => Icons.autorenew,
        RunState.paused => Icons.pause_circle_outline,
        RunState.cancelling => Icons.stop_circle_outlined,
        RunState.cancelled => Icons.cancel_outlined,
        RunState.succeeded => Icons.check_circle_outline,
        RunState.failed => Icons.error_outline,
        RunState.interrupted => Icons.restart_alt,
      };

  Widget _workStateIcon(WorkItemState state, {double size = 20}) {
    final icon = switch (state) {
      WorkItemState.queued => Icons.radio_button_unchecked,
      WorkItemState.running => Icons.autorenew,
      WorkItemState.blocked => Icons.block_outlined,
      WorkItemState.awaitingApproval => Icons.lock_clock_outlined,
      WorkItemState.succeeded => Icons.check_circle_outline,
      WorkItemState.failed => Icons.error_outline,
      WorkItemState.cancelled => Icons.cancel_outlined,
    };
    if (state == WorkItemState.running) {
      return SizedBox.square(
        dimension: size,
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Icon(icon, size: size);
  }

  IconData _eventIcon(String type) {
    if (type.startsWith('run.')) {
      return Icons.play_circle_outline;
    }
    if (type.startsWith('work_item.')) {
      return Icons.account_tree_outlined;
    }
    if (type.startsWith('tool.')) {
      return Icons.build_outlined;
    }
    if (type.startsWith('research.')) {
      return Icons.language_outlined;
    }
    if (type.startsWith('knowledge.')) {
      return Icons.library_books_outlined;
    }
    if (type.startsWith('memory.')) {
      return Icons.history_outlined;
    }
    if (type.startsWith('diagnostics.')) {
      return Icons.health_and_safety_outlined;
    }
    if (type.startsWith('prompt.')) {
      return Icons.edit_note_outlined;
    }
    if (type.startsWith('project.')) {
      return Icons.folder_outlined;
    }
    if (type.startsWith('audit.')) {
      return Icons.verified_user_outlined;
    }
    return Icons.circle_outlined;
  }

  IconData _evidenceIcon(EvidenceKind kind) => switch (kind) {
        EvidenceKind.model => Icons.memory_outlined,
        EvidenceKind.knowledge => Icons.search,
        EvidenceKind.research => Icons.language_outlined,
        EvidenceKind.mutation => Icons.difference_outlined,
        EvidenceKind.command => Icons.terminal_outlined,
        EvidenceKind.test => Icons.fact_check_outlined,
        EvidenceKind.verification => Icons.verified_outlined,
        EvidenceKind.deployment => Icons.inventory_2_outlined,
        EvidenceKind.audit => Icons.verified_user_outlined,
      };
}

class _PromptClarificationDialog extends StatefulWidget {
  const _PromptClarificationDialog({
    required this.session,
    required this.initialAnswers,
  });

  final PromptClarificationSession session;
  final Map<String, String> initialAnswers;

  @override
  State<_PromptClarificationDialog> createState() =>
      _PromptClarificationDialogState();
}

class _PromptClarificationDialogState
    extends State<_PromptClarificationDialog> {
  static const String otherId = '__other__';

  final Map<String, String> selectedOptionIds = <String, String>{};
  final Map<String, TextEditingController> otherControllers =
      <String, TextEditingController>{};
  int currentIndex = 0;

  @override
  void initState() {
    super.initState();
    for (final question in widget.session.questions) {
      final initial = widget.initialAnswers[question.id]?.trim() ?? '';
      final matching = question.options
          .where((option) => option.label == initial)
          .firstOrNull;
      if (matching != null) {
        selectedOptionIds[question.id] = matching.id;
        otherControllers[question.id] = TextEditingController();
      } else if (initial.isNotEmpty) {
        selectedOptionIds[question.id] = otherId;
        otherControllers[question.id] = TextEditingController(text: initial);
      } else {
        selectedOptionIds[question.id] = question.recommendedOption.id;
        otherControllers[question.id] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (final controller in otherControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _answerFor(PromptClarificationQuestion question) {
    final selected = selectedOptionIds[question.id];
    if (selected == otherId) {
      return otherControllers[question.id]?.text.trim() ?? '';
    }
    return question.options
            .where((option) => option.id == selected)
            .firstOrNull
            ?.label ??
        '';
  }

  bool get _currentComplete =>
      _answerFor(widget.session.questions[currentIndex]).isNotEmpty;

  void _useRecommendedForAll() {
    setState(() {
      for (final question in widget.session.questions) {
        selectedOptionIds[question.id] = question.recommendedOption.id;
        otherControllers[question.id]?.clear();
      }
    });
  }

  void _continue() {
    if (!_currentComplete) {
      return;
    }
    if (currentIndex < widget.session.questions.length - 1) {
      setState(() => currentIndex++);
      return;
    }
    final answers = <String, String>{
      for (final question in widget.session.questions)
        question.id: _answerFor(question),
    };
    if (answers.values.any((answer) => answer.trim().isEmpty)) {
      return;
    }
    Navigator.of(context).pop(answers);
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.session.questions[currentIndex];
    final selected = selectedOptionIds[question.id];
    final progress = (currentIndex + 1) / widget.session.questions.length;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Row(
        children: <Widget>[
          const Icon(Icons.tune),
          const SizedBox(width: 10),
          const Expanded(child: Text('Shape the final prompt')),
          TextButton.icon(
            onPressed: _useRecommendedForAll,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: const Text('Use smart defaults'),
          ),
        ],
      ),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 8),
              Text(
                'Decision ${currentIndex + 1} of ${widget.session.questions.length}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 14),
              Text(
                question.question,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              if (question.whyItMatters.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(question.whyItMatters),
              ],
              const SizedBox(height: 16),
              ...question.options.map((option) {
                final active = selected == option.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Card(
                    margin: EdgeInsets.zero,
                    color: active
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerLow,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() {
                        selectedOptionIds[question.id] = option.id;
                      }),
                      child: Padding(
                        padding: const EdgeInsets.all(13),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(
                              active
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          option.label,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      if (option.recommended)
                                        const Chip(
                                          visualDensity: VisualDensity.compact,
                                          label: Text('Recommended'),
                                        ),
                                    ],
                                  ),
                                  if (option.description.isNotEmpty)
                                    Text(option.description),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              Card(
                margin: EdgeInsets.zero,
                color: selected == otherId
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerLow,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() {
                    selectedOptionIds[question.id] = otherId;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.all(13),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          selected == otherId
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Other — write my own answer',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (selected == otherId) ...<Widget>[
                const SizedBox(height: 10),
                TextField(
                  controller: otherControllers[question.id],
                  autofocus: true,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Your answer',
                    hintText: 'Describe the choice Kristin should use.',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (currentIndex > 0)
          OutlinedButton.icon(
            onPressed: () => setState(() => currentIndex--),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
          ),
        FilledButton.icon(
          onPressed: _currentComplete ? _continue : null,
          icon: Icon(
            currentIndex == widget.session.questions.length - 1
                ? Icons.auto_awesome
                : Icons.arrow_forward,
          ),
          label: Text(
            currentIndex == widget.session.questions.length - 1
                ? 'Generate final prompt'
                : 'Next choice',
          ),
        ),
      ],
    );
  }
}

class _MetricData {
  const _MetricData({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;
}

class _PlanTaskEditorDialog extends StatefulWidget {
  const _PlanTaskEditorDialog({
    required this.task,
    required this.availableTaskIds,
  });

  final PlanTaskRecord task;
  final Set<String> availableTaskIds;

  @override
  State<_PlanTaskEditorDialog> createState() => _PlanTaskEditorDialogState();
}

class _PlanTaskEditorDialogState extends State<_PlanTaskEditorDialog> {
  late final TextEditingController titleController;
  late final TextEditingController phaseController;
  late final TextEditingController objectiveController;
  late final TextEditingController instructionsController;
  late final TextEditingController dependenciesController;
  late final TextEditingController acceptanceController;
  late final TextEditingController verificationController;
  late final TextEditingController artifactsController;
  late final TextEditingController toolsController;
  late int complexity;
  late int effortPoints;
  late PlanUncertainty uncertainty;
  late PlanRisk risk;
  late double confidence;
  late int modelTurns;
  late int toolCalls;
  late int maxAttempts;
  late bool enabled;
  late bool manual;
  String error = '';

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    titleController = TextEditingController(text: task.title);
    phaseController = TextEditingController(text: task.phase);
    objectiveController = TextEditingController(text: task.objective);
    instructionsController = TextEditingController(text: task.instructions);
    dependenciesController = TextEditingController(
      text: (task.dependencies.toList()..sort()).join(', '),
    );
    acceptanceController = TextEditingController(
      text: task.acceptanceCriteria.join('\n'),
    );
    verificationController = TextEditingController(
      text: task.verificationSteps.join('\n'),
    );
    artifactsController = TextEditingController(
      text: task.expectedArtifacts.join('\n'),
    );
    toolsController = TextEditingController(
      text: (task.allowedTools.toList()..sort()).join(', '),
    );
    complexity = task.complexity;
    effortPoints = task.effortPoints;
    uncertainty = task.uncertainty;
    risk = task.risk;
    confidence = task.estimateConfidence;
    modelTurns = task.expectedModelTurns;
    toolCalls = task.expectedToolCalls;
    maxAttempts = task.maxAttempts;
    enabled = task.enabled;
    manual = task.manual;
  }

  @override
  void dispose() {
    titleController.dispose();
    phaseController.dispose();
    objectiveController.dispose();
    instructionsController.dispose();
    dependenciesController.dispose();
    acceptanceController.dispose();
    verificationController.dispose();
    artifactsController.dispose();
    toolsController.dispose();
    super.dispose();
  }

  List<String> _lines(String value) => value
      .split(RegExp(r'[\r\n]+'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);

  Set<String> _csv(String value) => value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toSet();

  void _save() {
    final title = titleController.text.trim();
    final instructions = instructionsController.text.trim();
    final dependencies = _csv(dependenciesController.text);
    final invalidDependencies = dependencies.difference(
      widget.availableTaskIds,
    );
    if (title.isEmpty || instructions.isEmpty) {
      setState(() => error = 'A task needs a title and instructions.');
      return;
    }
    if (invalidDependencies.isNotEmpty) {
      setState(
        () => error =
            'Unknown dependencies: ${invalidDependencies.toList()..sort()}',
      );
      return;
    }
    final acceptance = _lines(acceptanceController.text);
    final verification = _lines(verificationController.text);
    if (!manual && (acceptance.isEmpty || verification.isEmpty)) {
      setState(
        () => error =
            'Automated tasks need at least one acceptance criterion and verification step.',
      );
      return;
    }
    Navigator.of(context).pop(
      widget.task.copyWith(
        phase: phaseController.text.trim().isEmpty
            ? 'Implementation'
            : phaseController.text.trim(),
        title: title,
        objective: objectiveController.text.trim(),
        instructions: instructions,
        dependencies: dependencies,
        acceptanceCriteria: acceptance,
        verificationSteps: verification,
        expectedArtifacts: _lines(artifactsController.text),
        allowedTools: _csv(toolsController.text),
        complexity: complexity,
        effortPoints: effortPoints,
        uncertainty: uncertainty,
        risk: risk,
        estimateConfidence: confidence,
        expectedModelTurns: modelTurns,
        expectedToolCalls: toolCalls,
        maxAttempts: maxAttempts,
        enabled: enabled,
        manual: manual,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effortChoices = <int>{1, 2, 3, 5, 8, 13, effortPoints}.toList()
      ..sort();
    final modelTurnChoices = <int>{
      1,
      2,
      3,
      4,
      5,
      8,
      12,
      20,
      modelTurns,
    }.toList()
      ..sort();
    final toolCallChoices = <int>{
      0,
      1,
      2,
      4,
      8,
      12,
      20,
      40,
      80,
      toolCalls,
    }.toList()
      ..sort();
    return AlertDialog(
      icon: const Icon(Icons.task_alt_outlined),
      title: Text('Edit ${widget.task.id}'),
      content: SizedBox(
        width: 820,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (error.isNotEmpty) ...<Widget>[
                MaterialBanner(
                  content: Text(error),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => setState(() => error = ''),
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: titleController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Task title',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: phaseController,
                      decoration: const InputDecoration(labelText: 'Phase'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: objectiveController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Objective',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: instructionsController,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Instructions',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: dependenciesController,
                decoration: InputDecoration(
                  labelText: 'Dependencies',
                  helperText: widget.availableTaskIds.isEmpty
                      ? 'No other task IDs are available.'
                      : 'Comma-separated IDs. Available: ${(widget.availableTaskIds.toList()..sort()).take(12).join(', ')}',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: acceptanceController,
                      minLines: 4,
                      maxLines: 10,
                      decoration: const InputDecoration(
                        labelText: 'Acceptance criteria',
                        helperText: 'One measurable criterion per line.',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: verificationController,
                      minLines: 4,
                      maxLines: 10,
                      decoration: const InputDecoration(
                        labelText: 'Verification steps',
                        helperText: 'One test or inspection per line.',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: artifactsController,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Expected artifacts',
                        helperText: 'One expected file or result per line.',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: toolsController,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Proposed governed tools',
                        helperText:
                            'Comma-separated names. Unknown tools are removed during compilation.',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Complexity: $complexity/10'),
              Slider(
                value: complexity.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: '$complexity',
                onChanged: (value) =>
                    setState(() => complexity = value.round()),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: effortPoints,
                      decoration: const InputDecoration(
                        labelText: 'Effort points',
                      ),
                      items: effortChoices
                          .map(
                            (value) => DropdownMenuItem<int>(
                              value: value,
                              child: Text('$value'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => effortPoints = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<PlanRisk>(
                      initialValue: risk,
                      decoration: const InputDecoration(labelText: 'Risk'),
                      items: PlanRisk.values
                          .map(
                            (value) => DropdownMenuItem<PlanRisk>(
                              value: value,
                              child: Text(value.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => risk = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<PlanUncertainty>(
                      initialValue: uncertainty,
                      decoration: const InputDecoration(
                        labelText: 'Uncertainty',
                      ),
                      items: PlanUncertainty.values
                          .map(
                            (value) => DropdownMenuItem<PlanUncertainty>(
                              value: value,
                              child: Text(value.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => uncertainty = value);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Estimate confidence: ${(confidence * 100).round()}%'),
              Slider(
                value: confidence,
                min: 0.1,
                max: 1,
                divisions: 9,
                label: '${(confidence * 100).round()}%',
                onChanged: (value) => setState(() => confidence = value),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: modelTurns,
                      decoration: const InputDecoration(
                        labelText: 'Expected model turns',
                      ),
                      items: modelTurnChoices
                          .map(
                            (value) => DropdownMenuItem<int>(
                              value: value,
                              child: Text('$value'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => modelTurns = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: toolCalls,
                      decoration: const InputDecoration(
                        labelText: 'Expected tool calls',
                      ),
                      items: toolCallChoices
                          .map(
                            (value) => DropdownMenuItem<int>(
                              value: value,
                              child: Text('$value'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => toolCalls = value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: maxAttempts,
                      decoration: const InputDecoration(
                        labelText: 'Maximum attempts',
                      ),
                      items: const <int>[1, 2, 3]
                          .map(
                            (value) => DropdownMenuItem<int>(
                              value: value,
                              child: Text('$value'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => maxAttempts = value);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                title: const Text('Enabled in this plan'),
                subtitle: const Text(
                  'Disabled tasks remain visible but are not compiled or executed.',
                ),
                onChanged: (value) => setState(() => enabled = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: manual,
                title: const Text('Manual checkpoint'),
                subtitle: const Text(
                  'Manual tasks must be resolved or disabled before execution.',
                ),
                onChanged: (value) => setState(() => manual = value),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save new plan revision'),
        ),
      ],
    );
  }
}

class _PromptDraft {
  const _PromptDraft({
    required this.title,
    required this.description,
    required this.systemPrompt,
    required this.userPrompt,
    required this.variables,
    required this.tags,
    required this.mode,
  });

  final String title;
  final String description;
  final String systemPrompt;
  final String userPrompt;
  final List<String> variables;
  final Set<String> tags;
  final CommandMode mode;
}

class _PromptEditorDialog extends StatefulWidget {
  const _PromptEditorDialog({this.prompt, this.template, this.generatedDraft});

  final PromptTemplateRecord? prompt;
  final StudioTemplate? template;
  final PromptStudioDraft? generatedDraft;

  @override
  State<_PromptEditorDialog> createState() => _PromptEditorDialogState();
}

class _PromptEditorDialogState extends State<_PromptEditorDialog> {
  late final TextEditingController titleController;
  late final TextEditingController descriptionController;
  late final TextEditingController systemController;
  late final TextEditingController userController;
  late final TextEditingController variablesController;
  late final TextEditingController tagsController;
  late CommandMode mode;
  bool preview = false;

  @override
  void initState() {
    super.initState();
    final prompt = widget.prompt;
    final template = widget.template;
    final generated = widget.generatedDraft;
    titleController = TextEditingController(
      text: generated?.title ?? prompt?.title ?? template?.title ?? '',
    );
    descriptionController = TextEditingController(
      text: generated?.purpose ??
          prompt?.description ??
          template?.description ??
          '',
    );
    systemController = TextEditingController(
      text: generated?.systemPrompt ??
          prompt?.systemPrompt ??
          'Work carefully inside the selected project. Use tools only when permitted. Verify important results and explain failures clearly.',
    );
    userController = TextEditingController(
      text:
          generated?.userPrompt ?? prompt?.userPrompt ?? template?.prompt ?? '',
    );
    variablesController = TextEditingController(
      text:
          generated?.variables.join(', ') ?? prompt?.variables.join(', ') ?? '',
    );
    tagsController = TextEditingController(
      text: prompt?.tags.join(', ') ?? template?.tags.join(', ') ?? '',
    );
    mode = generated?.mode ??
        prompt?.mode ??
        template?.suggestedMode ??
        CommandMode.build;
  }

  @override
  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    systemController.dispose();
    userController.dispose();
    variablesController.dispose();
    tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rendered = <String>[
      if (systemController.text.trim().isNotEmpty)
        'Instructions for this task:\n${systemController.text.trim()}',
      if (userController.text.trim().isNotEmpty)
        'Request:\n${userController.text.trim()}',
    ].join('\n\n');
    return AlertDialog(
      icon: const Icon(Icons.edit_note_outlined),
      title: Text(
        widget.generatedDraft != null
            ? 'Adjust generated prompt'
            : widget.prompt == null
                ? 'Create prompt'
                : 'Edit prompt',
      ),
      content: SizedBox(
        width: 780,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  ChoiceChip(
                    selected: !preview,
                    label: const Text('Edit'),
                    onSelected: (_) => setState(() => preview = false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    selected: preview,
                    label: const Text('Preview'),
                    onSelected: (_) => setState(() => preview = true),
                  ),
                  const Spacer(),
                  if (widget.prompt != null)
                    Chip(label: Text('Current v${widget.prompt!.version}')),
                ],
              ),
              const SizedBox(height: 14),
              if (preview)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: SelectableText(rendered),
                )
              else ...<Widget>[
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Prompt name'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<CommandMode>(
                  initialValue: mode,
                  decoration: const InputDecoration(labelText: 'Task mode'),
                  items: CommandMode.values
                      .map(
                        (item) => DropdownMenuItem<CommandMode>(
                          value: item,
                          child: Text(modeLabel(item)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => mode = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: systemController,
                  minLines: 4,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'System instructions',
                    alignLabelWithHint: true,
                    helperText:
                        'Describe behavior, constraints, quality bar, and safety expectations.',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: userController,
                  minLines: 5,
                  maxLines: 14,
                  decoration: const InputDecoration(
                    labelText: 'User prompt template',
                    alignLabelWithHint: true,
                    helperText: 'Use variables such as {{project_name}}.',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: variablesController,
                  decoration: const InputDecoration(
                    labelText: 'Variables',
                    hintText: 'project_name, audience, output_format',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tagsController,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    hintText: 'website, review, customer',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: titleController.text.trim().isEmpty ||
                  userController.text.trim().isEmpty
              ? null
              : () {
                  Navigator.of(context).pop(
                    _PromptDraft(
                      title: titleController.text.trim(),
                      description: descriptionController.text.trim(),
                      systemPrompt: systemController.text.trim(),
                      userPrompt: userController.text.trim(),
                      variables: variablesController.text
                          .split(',')
                          .map((value) => value.trim())
                          .where((value) => value.isNotEmpty)
                          .toSet()
                          .toList(),
                      tags: tagsController.text
                          .split(',')
                          .map((value) => value.trim().toLowerCase())
                          .where((value) => value.isNotEmpty)
                          .toSet(),
                      mode: mode,
                    ),
                  );
                },
          icon: const Icon(Icons.save_outlined),
          label: Text(
            widget.generatedDraft != null
                ? 'Apply changes'
                : widget.prompt == null
                    ? 'Save prompt'
                    : 'Save new version',
          ),
        ),
      ],
    );
  }
}

class _RunGraph extends StatefulWidget {
  const _RunGraph({
    required this.run,
    required this.selectedWorkItemId,
    required this.onSelected,
  });

  final RunRecord run;
  final String? selectedWorkItemId;
  final ValueChanged<String> onSelected;

  @override
  State<_RunGraph> createState() => _RunGraphState();
}

class _RunGraphState extends State<_RunGraph> {
  final TransformationController transformationController =
      TransformationController();

  @override
  void dispose() {
    transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.run.items;
    if (items.isEmpty) {
      return const Center(child: Text('This run has no work items.'));
    }
    const nodeWidth = 178.0;
    const nodeHeight = 116.0;
    const horizontalGap = 78.0;
    const left = 70.0;
    const top = 68.0;
    final positions = <String, Offset>{};
    for (var index = 0; index < items.length; index++) {
      final row = index % 2;
      positions[items[index].item.id] = Offset(
        left + index * (nodeWidth + horizontalGap),
        top + row * 150,
      );
    }
    final canvasWidth = left * 2 +
        items.length * nodeWidth +
        (items.length - 1) * horizontalGap;
    const canvasHeight = 390.0;
    final colors = Theme.of(context).colorScheme;
    return Stack(
      children: <Widget>[
        InteractiveViewer(
          transformationController: transformationController,
          constrained: false,
          minScale: 0.45,
          maxScale: 2.2,
          boundaryMargin: const EdgeInsets.all(220),
          child: SizedBox(
            width: canvasWidth < 760 ? 760 : canvasWidth,
            height: canvasHeight,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(
                    painter: _RunConnectionPainter(
                      items: items,
                      positions: positions,
                      nodeWidth: nodeWidth,
                      nodeHeight: nodeHeight,
                      lineColor: colors.outlineVariant,
                      activeColor: colors.primary,
                    ),
                  ),
                ),
                ...items.map((progress) {
                  final position = positions[progress.item.id]!;
                  final selected =
                      widget.selectedWorkItemId == progress.item.id;
                  return Positioned(
                    left: position.dx,
                    top: position.dy,
                    width: nodeWidth,
                    height: nodeHeight,
                    child: _RunNode(
                      progress: progress,
                      selected: selected,
                      onTap: () => widget.onSelected(progress.item.id),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        Positioned(
          right: 10,
          bottom: 10,
          child: Card(
            margin: EdgeInsets.zero,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: 'Zoom out',
                  onPressed: () => _zoom(0.82),
                  icon: const Icon(Icons.remove),
                ),
                IconButton(
                  tooltip: 'Reset view',
                  onPressed: () {
                    transformationController.value = Matrix4.identity();
                  },
                  icon: const Icon(Icons.center_focus_strong_outlined),
                ),
                IconButton(
                  tooltip: 'Zoom in',
                  onPressed: () => _zoom(1.22),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _zoom(double factor) {
    final matrix = transformationController.value.clone();
    matrix.scaleByDouble(factor, factor, factor, 1.0);
    transformationController.value = matrix;
  }
}

class _RunNode extends StatelessWidget {
  const _RunNode({
    required this.progress,
    required this.selected,
    required this.onTap,
  });

  final WorkItemProgress progress;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final statusColor = switch (progress.state) {
      WorkItemState.succeeded => colors.primary,
      WorkItemState.failed => colors.error,
      WorkItemState.running => colors.tertiary,
      _ => colors.onSurfaceVariant,
    };
    return Material(
      color: selected ? colors.secondaryContainer : colors.surface,
      elevation: selected ? 5 : 2,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (progress.state == WorkItemState.running)
                    SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: statusColor,
                      ),
                    )
                  else
                    Icon(
                      switch (progress.state) {
                        WorkItemState.succeeded => Icons.check_circle,
                        WorkItemState.failed => Icons.error,
                        WorkItemState.blocked => Icons.block,
                        WorkItemState.awaitingApproval => Icons.lock_clock,
                        WorkItemState.cancelled => Icons.cancel,
                        _ => Icons.radio_button_unchecked,
                      },
                      size: 18,
                      color: statusColor,
                    ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      friendlyWorkState(progress.state),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                  Text(
                    '${progress.attempts}/${progress.item.maxAttempts}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                progress.item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                '${progress.item.allowedTools.length} tools · ${progress.item.dependencies.length} deps',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunConnectionPainter extends CustomPainter {
  _RunConnectionPainter({
    required this.items,
    required this.positions,
    required this.nodeWidth,
    required this.nodeHeight,
    required this.lineColor,
    required this.activeColor,
  });

  final List<WorkItemProgress> items;
  final Map<String, Offset> positions;
  final double nodeWidth;
  final double nodeHeight;
  final Color lineColor;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final byId = <String, WorkItemProgress>{
      for (final item in items) item.item.id: item,
    };
    for (var index = 0; index < items.length; index++) {
      final target = items[index];
      final dependencies = target.item.dependencies.isEmpty && index > 0
          ? <String>{items[index - 1].item.id}
          : target.item.dependencies;
      for (final dependencyId in dependencies) {
        final startPosition = positions[dependencyId];
        final endPosition = positions[target.item.id];
        if (startPosition == null || endPosition == null) {
          continue;
        }
        final start = Offset(
          startPosition.dx + nodeWidth,
          startPosition.dy + nodeHeight / 2,
        );
        final end = Offset(endPosition.dx, endPosition.dy + nodeHeight / 2);
        final dependency = byId[dependencyId];
        final active = dependency?.state == WorkItemState.succeeded ||
            dependency?.state == WorkItemState.running;
        final paint = Paint()
          ..color = active ? activeColor : lineColor
          ..strokeWidth = active ? 2.3 : 1.7
          ..style = PaintingStyle.stroke;
        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(
            start.dx + 34,
            start.dy,
            end.dx - 34,
            end.dy,
            end.dx,
            end.dy,
          );
        canvas.drawPath(path, paint);
        final arrow = Path()
          ..moveTo(end.dx - 8, end.dy - 5)
          ..lineTo(end.dx, end.dy)
          ..lineTo(end.dx - 8, end.dy + 5);
        canvas.drawPath(arrow, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RunConnectionPainter oldDelegate) {
    return oldDelegate.items != items ||
        oldDelegate.positions != positions ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.lineColor != lineColor;
  }
}
