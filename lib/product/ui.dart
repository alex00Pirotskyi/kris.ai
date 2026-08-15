import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_server.dart';
import 'chat_studio.dart';
import 'domain.dart';
import 'product_runtime.dart';
import 'p2_product_runtime_bootstrap.dart';
import 'p5_information_architecture/p5_controller.dart';
import 'p5_information_architecture/p5_prototype.dart';
import 'ui_advanced.dart';
import 'ui_components.dart';

class KristinApp extends StatefulWidget {
  const KristinApp({super.key, required this.runtime});

  final ProductRuntime runtime;

  @override
  State<KristinApp> createState() => _KristinAppState();
}

class _KristinAppState extends State<KristinApp> {
  late final GovernedApiServer api = GovernedApiServer(widget.runtime);
  String? startupError;

  @override
  void initState() {
    super.initState();
    if (widget.runtime.settings.apiEnabled) {
      unawaited(
        api.start().catchError((Object failure) {
          if (mounted) {
            setState(() {
              startupError = '$failure';
            });
          }
        }),
      );
    }
  }

  @override
  void dispose() {
    unawaited(api.stop());
    unawaited(widget.runtime.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kristin Local Agent',
      debugShowCheckedModeBanner: false,
      theme: _studioTheme(Brightness.light),
      darkTheme: _studioTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: KristinMainShell(
        ownerMode: widget.runtime.p2OwnerMode,
        chat: ChatStudio(
          runtime: widget.runtime,
          api: api,
          startupError: startupError,
        ),
      ),
    );
  }
}

class KristinMainShell extends StatefulWidget {
  const KristinMainShell({
    super.key,
    required this.ownerMode,
    required this.chat,
  });

  final P2ProductRuntimeOwnerModeHandle ownerMode;
  final Widget chat;

  @override
  State<KristinMainShell> createState() => _KristinMainShellState();
}

class _KristinMainShellState extends State<KristinMainShell> {
  var _index = 0;
  late final P5InformationArchitectureController _experienceController;

  @override
  void initState() {
    super.initState();
    _experienceController = P5InformationArchitectureController();
  }

  @override
  void dispose() {
    _experienceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final qaPreview = widget.ownerMode.runtimeProvenance['qaPreview'] == true;
    final ownerAvailable = widget.ownerMode.available;
    final pages = <Widget>[
      widget.chat,
      P5InformationArchitecturePrototype(
        controller: _experienceController,
      ),
      widget.ownerMode.buildWorkspace(
        key: const ValueKey<String>('kristin-owner-mode-workspace'),
      ),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final shell = Scaffold(
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                NavigationRail(
                  selectedIndex: _index,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: _selectDestination,
                  destinations: <NavigationRailDestination>[
                    const NavigationRailDestination(
                      icon: Icon(Icons.chat_bubble_outline),
                      selectedIcon: Icon(Icons.chat_bubble),
                      label: Text('Chat'),
                    ),
                    const NavigationRailDestination(
                      icon: Icon(Icons.dashboard_customize_outlined),
                      selectedIcon: Icon(Icons.dashboard_customize),
                      label: Text('Experience'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(
                        ownerAvailable
                            ? Icons.admin_panel_settings_outlined
                            : Icons.gpp_bad_outlined,
                      ),
                      selectedIcon: Icon(
                        ownerAvailable
                            ? Icons.admin_panel_settings
                            : Icons.gpp_bad,
                      ),
                      label: const Text('Owner Mode'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: IndexedStack(index: _index, children: pages),
                ),
              ],
            )
          : IndexedStack(index: _index, children: pages),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _selectDestination,
              destinations: <NavigationDestination>[
                const NavigationDestination(
                  icon: Icon(Icons.chat_bubble_outline),
                  selectedIcon: Icon(Icons.chat_bubble),
                  label: 'Chat',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.dashboard_customize_outlined),
                  selectedIcon: Icon(Icons.dashboard_customize),
                  label: 'Experience',
                ),
                NavigationDestination(
                  icon: Icon(
                    ownerAvailable
                        ? Icons.admin_panel_settings_outlined
                        : Icons.gpp_bad_outlined,
                  ),
                  selectedIcon: Icon(
                    ownerAvailable ? Icons.admin_panel_settings : Icons.gpp_bad,
                  ),
                  label: 'Owner Mode',
                ),
              ],
            ),
    );
    if (!qaPreview) return shell;
    return Banner(
      message: 'OWNER-RISK QA — SECURITY EVIDENCE WAIVED',
      location: BannerLocation.topEnd,
      color: Colors.deepOrange,
      child: shell,
    );
  }

  void _selectDestination(int value) {
    if (value == _index) return;
    setState(() => _index = value);
  }
}

ThemeData _studioTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff6558d3),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor:
        dark ? const Color(0xff111217) : const Color(0xfff8f7f4),
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? const Color(0xff111217) : const Color(0xfff8f7f4),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor:
          dark ? scheme.surfaceContainerHighest : scheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return TextStyle(
          fontWeight:
              states.contains(WidgetState.selected) ? FontWeight.w700 : null,
        );
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
  );
}

class SimpleStudio extends StatefulWidget {
  const SimpleStudio({
    super.key,
    required this.runtime,
    required this.api,
    this.startupError,
  });

  final ProductRuntime runtime;
  final GovernedApiServer api;
  final String? startupError;

  @override
  State<SimpleStudio> createState() => _SimpleStudioState();
}

class _SimpleStudioState extends State<SimpleStudio> {
  final TextEditingController requestController = TextEditingController();
  final TextEditingController followUpController = TextEditingController();
  final TextEditingController projectNameController = TextEditingController();
  final TextEditingController projectPathController = TextEditingController();
  final FocusNode requestFocus = FocusNode();

  StreamSubscription<EventEnvelope>? eventSubscription;
  Timer? refreshTimer;
  StudioSection section = StudioSection.newTask;
  WorkspaceView workspaceView = WorkspaceView.preview;
  InspectorSection inspectorSection = InspectorSection.summary;
  LogDetail logDetail = LogDetail.simple;
  SimpleTaskMode simpleTaskMode = SimpleTaskMode.auto;
  CommandMode chosenMode = CommandMode.build;
  bool busy = false;
  bool showAdvancedPlan = false;
  bool showGranularAccess = false;
  String status = 'Kristin is ready';
  String? error;
  List<ProjectRecord> projects = <ProjectRecord>[];
  List<ModelIdentity> models = <ModelIdentity>[];
  List<RunRecord> runs = <RunRecord>[];
  List<EvidenceRecord> evidence = <EvidenceRecord>[];
  List<EventEnvelope> recentEvents = <EventEnvelope>[];
  String? selectedProjectId;
  String? selectedModelId;
  String? selectedRunId;
  String? selectedFlowItemId;
  PreparedCommand? prepared;
  RunRecord? currentRun;
  final Set<PermissionScope> selectedAccessScopes = <PermissionScope>{};

  ProductRuntime get runtime => widget.runtime;

  ProjectRecord? get selectedProject =>
      projects.where((project) => project.id == selectedProjectId).firstOrNull;

  ModelIdentity? get selectedModel =>
      models.where((model) => model.exactId == selectedModelId).firstOrNull;

  @override
  void initState() {
    super.initState();
    eventSubscription = runtime.eventStream.listen(_handleEvent);
    refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final run = currentRun;
      if (mounted &&
          run != null &&
          <RunState>{
            RunState.running,
            RunState.paused,
            RunState.cancelling,
            RunState.interrupted,
          }.contains(run.state)) {
        unawaited(_refreshRuns(silent: true));
      }
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    eventSubscription?.cancel();
    refreshTimer?.cancel();
    requestController.dispose();
    followUpController.dispose();
    projectNameController.dispose();
    projectPathController.dispose();
    requestFocus.dispose();
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
        error = null;
        status = activity;
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
      if (selectedProjectId == null ||
          !projects.any((project) => project.id == selectedProjectId)) {
        selectedProjectId = projects.firstOrNull?.id;
      }
      await _refreshModels(silent: true);
      await _refreshRuns(silent: true);
      recentEvents = await runtime.events.after(0, limit: 300);
    });
    if (mounted) {
      setState(() {});
    }
  }

  void _handleEvent(EventEnvelope event) {
    if (!mounted) {
      return;
    }
    setState(() {
      recentEvents.add(event);
      if (recentEvents.length > 300) {
        recentEvents.removeRange(0, recentEvents.length - 300);
      }
      status = humanEventText(event, run: currentRun);
    });
    if (event.type.startsWith('run.') ||
        event.type.startsWith('work_item.') ||
        event.type == 'evidence.recorded') {
      unawaited(_refreshRuns(silent: true));
    }
  }

  Future<void> _refreshModels({bool silent = false}) async {
    await _perform<void>('Finding your AI models', () async {
      models = await runtime.discoverModels();
      if (selectedModelId == null ||
          !models.any((model) => model.exactId == selectedModelId)) {
        selectedModelId = models.firstOrNull?.exactId;
      }
    }, silent: silent);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _refreshRuns({bool silent = false}) async {
    await _perform<void>('Refreshing activity', () async {
      runs = await runtime.listRuns(projectId: selectedProjectId);
      final id = selectedRunId ?? currentRun?.id;
      if (id != null) {
        final refreshed = await runtime.getRun(id);
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

  Future<void> _selectProject(String? projectId) async {
    if (projectId == selectedProjectId) {
      return;
    }
    setState(() {
      selectedProjectId = projectId;
      prepared = null;
      currentRun = null;
      selectedRunId = null;
      evidence = <EvidenceRecord>[];
      selectedAccessScopes.clear();
      showAdvancedPlan = false;
    });
    await _refreshRuns(silent: true);
  }

  Future<void> _preparePlan() async {
    final project = selectedProject;
    final model = selectedModel;
    final request = requestController.text.trim();
    if (project == null) {
      _showError('Choose a project folder first.');
      return;
    }
    if (model == null) {
      _showError('Connect an AI model in Settings first.');
      return;
    }
    if (request.length < 3) {
      _showError('Tell Kristin what you would like to make or change.');
      requestFocus.requestFocus();
      return;
    }
    final result = await _perform<PreparedCommand>('Creating a clear plan', () {
      return runtime.prepare(
        projectId: project.id,
        mode: resolveTaskMode(
          request: request,
          choice: simpleTaskMode,
          chosenMode: chosenMode,
        ),
        request: request,
        model: model,
      );
    });
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      prepared = result;
      currentRun = null;
      selectedRunId = null;
      evidence = <EvidenceRecord>[];
      selectedAccessScopes
        ..clear()
        ..addAll(result.contract.requiredPermissions);
      showAdvancedPlan = false;
      showGranularAccess = false;
      workspaceView = WorkspaceView.preview;
    });
  }

  Future<void> _allowAndStart() async {
    final command = prepared;
    if (command == null) {
      await _preparePlan();
      return;
    }
    final required = command.contract.requiredPermissions;
    if (!selectedAccessScopes.containsAll(required)) {
      _showError(
        'This plan needs every listed access group. Re-enable it or change the request.',
      );
      return;
    }
    final confirmed = await _confirmHighRiskAccess(required);
    if (!confirmed || !mounted) {
      return;
    }
    final started = await _perform<RunRecord>('Starting your task', () async {
      var run = currentRun;
      if (run == null || run.command.id != command.id) {
        run = await runtime.createRun(command.id);
      }
      await runtime.approve(
        runId: run.id,
        scopes: Set<PermissionScope>.from(required),
      );
      currentRun = run;
      selectedRunId = run.id;
      evidence = <EvidenceRecord>[];
      unawaited(runtime.execute(run.id));
      await Future<void>.delayed(const Duration(milliseconds: 180));
      return await runtime.getRun(run.id) ?? run;
    });
    if (started == null || !mounted) {
      return;
    }
    setState(() {
      currentRun = started;
      selectedRunId = started.id;
    });
    await _refreshRuns(silent: true);
  }

  Future<bool> _confirmHighRiskAccess(Set<PermissionScope> required) async {
    final highRiskGroups = groupPermissions(
      required,
    ).where((group) => group.highRisk).toList(growable: false);
    if (highRiskGroups.isEmpty) {
      return true;
    }
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              icon: const Icon(Icons.shield_outlined),
              title: const Text('One more safety check'),
              content: SizedBox(
                width: 580,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'This task includes an action that deserves extra attention. '
                      'It is still limited to this project and this exact task.',
                    ),
                    const SizedBox(height: 14),
                    ...highRiskGroups.map((group) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(group.icon),
                        title: Text(group.title),
                        subtitle: Text(group.description),
                      );
                    }),
                    const SizedBox(height: 8),
                    const Text(
                      'Kristin will create checkpoints before file changes, redact '
                      'secret values, and stop rather than expand this access.',
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(false);
                  },
                  child: const Text('Go back'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(dialogContext).pop(true);
                  },
                  icon: const Icon(Icons.lock_open_outlined),
                  label: const Text('Allow once'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _retryCurrentRun() async {
    final run = currentRun;
    if (run == null) {
      return;
    }
    final retried = await _perform<RunRecord>(
      'Trying the task again as a fresh run',
      () async {
        final fresh = await runtime.retryRun(run.id);
        final required = fresh.command.contract.requiredPermissions;
        await runtime.approve(
          runId: fresh.id,
          scopes: Set<PermissionScope>.from(required),
        );
        unawaited(runtime.execute(fresh.id));
        await Future<void>.delayed(const Duration(milliseconds: 180));
        return await runtime.getRun(fresh.id) ?? fresh;
      },
    );
    if (retried != null && mounted) {
      setState(() {
        currentRun = retried;
      });
      await _refreshRuns(silent: true);
    }
  }

  Future<void> _controlRun(String action) async {
    final run = currentRun;
    if (run == null) {
      return;
    }
    await _perform<void>(
      switch (action) {
        'pause' => 'Pausing safely',
        'resume' => 'Continuing your task',
        _ => 'Stopping safely',
      },
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

  Future<void> _selectRun(RunRecord run) async {
    setState(() {
      selectedRunId = run.id;
      currentRun = run;
      inspectorSection = InspectorSection.summary;
      evidence = <EvidenceRecord>[];
    });
    final loadedEvidence = await runtime.evidenceForRun(run.id);
    if (mounted) {
      setState(() {
        evidence = loadedEvidence;
      });
    }
  }

  Future<void> _addProject() async {
    final added = await _perform<ProjectRecord>('Adding your project', () {
      return runtime.addProject(
        name: projectNameController.text,
        rootPath: projectPathController.text,
      );
    });
    if (added == null || !mounted) {
      return;
    }
    projects = await runtime.listProjects();
    projectNameController.clear();
    projectPathController.clear();
    await _selectProject(added.id);
    if (mounted) {
      setState(() {
        section = StudioSection.newTask;
      });
    }
  }

  Future<void> _removeProject(ProjectRecord project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove this project from Kristin?'),
          content: Text(
            'Only the registration for “${project.name}” will be removed. Its files will never be deleted.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Keep project'),
            ),
            FilledButton.tonal(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Remove registration'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await _perform<void>('Removing the project registration', () async {
      await runtime.removeProject(project.id);
      projects = await runtime.listProjects();
      if (selectedProjectId == project.id) {
        selectedProjectId = projects.firstOrNull?.id;
        prepared = null;
        currentRun = null;
        selectedRunId = null;
      }
    });
    await _refreshRuns(silent: true);
  }

  void _useTemplate(StudioTemplate template) {
    requestController.text = template.prompt;
    simpleTaskMode = SimpleTaskMode.choose;
    chosenMode = template.suggestedMode;
    _resetTask(keepRequest: true);
    setState(() {
      section = StudioSection.newTask;
      status = '${template.title} template is ready';
    });
    requestFocus.requestFocus();
  }

  void _resetTask({bool keepRequest = false}) {
    setState(() {
      if (!keepRequest) {
        requestController.clear();
      }
      followUpController.clear();
      prepared = null;
      currentRun = null;
      selectedRunId = null;
      selectedFlowItemId = null;
      evidence = <EvidenceRecord>[];
      selectedAccessScopes.clear();
      showAdvancedPlan = false;
      showGranularAccess = false;
      workspaceView = WorkspaceView.preview;
      error = null;
      status = 'Kristin is ready';
    });
  }

  void _startFollowUp() {
    final followUp = followUpController.text.trim();
    final run = currentRun;
    if (followUp.isEmpty || run == null) {
      return;
    }
    requestController.text =
        '${run.command.contract.request}\n\nFollow-up request: $followUp';
    simpleTaskMode = SimpleTaskMode.auto;
    _resetTask(keepRequest: true);
    setState(() {
      section = StudioSection.newTask;
      status = 'Your follow-up is ready to review';
    });
    requestFocus.requestFocus();
  }

  Future<void> _openSettings({int initialSection = 0}) async {
    final result = await Navigator.of(context).push<AdvancedSettingsResult>(
      MaterialPageRoute<AdvancedSettingsResult>(
        builder: (context) {
          return AdvancedSettingsPage(
            runtime: runtime,
            api: widget.api,
            startupError: widget.startupError,
            initialProjectId: selectedProjectId,
            initialModelId: selectedModelId,
            initialSection: initialSection,
          );
        },
      ),
    );
    projects = await runtime.listProjects();
    await _refreshModels(silent: true);
    if (result != null) {
      if (projects.any((project) => project.id == result.projectId)) {
        selectedProjectId = result.projectId;
      }
      if (models.any((model) => model.exactId == result.modelId)) {
        selectedModelId = result.modelId;
      }
    }
    await _refreshRuns(silent: true);
    if (mounted) {
      setState(() {});
    }
  }

  void _showError(String message) {
    setState(() {
      error = message;
      status = 'Kristin needs your help';
    });
  }

  Future<void> _copyProjectPath() async {
    final project = selectedProject;
    if (project == null) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: project.rootPath));
    if (mounted) {
      setState(() {
        status = 'Project path copied';
      });
    }
  }

  Future<void> _showHelp() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Kristin is simple to use'),
          content: const SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _HelpStep(
                  number: '1',
                  title: 'Choose a project',
                  message:
                      'Kristin can work only inside the folder you choose.',
                ),
                _HelpStep(
                  number: '2',
                  title: 'Describe the result',
                  message:
                      'Write what you want in normal language or start from a template.',
                ),
                _HelpStep(
                  number: '3',
                  title: 'Review and allow',
                  message:
                      'Kristin shows a plan and asks before reading, changing, downloading, running, or publishing anything.',
                ),
              ],
            ),
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 900;
    final selectedIndex = studioDestinations.indexWhere(
      (destination) => destination.section == section,
    );
    return Scaffold(
      appBar: compact
          ? AppBar(
              title: Text(_sectionTitle(section)),
              actions: <Widget>[
                IconButton(
                  tooltip: 'Settings',
                  onPressed: busy ? null : () => _openSettings(),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
            )
          : null,
      body: Row(
        children: <Widget>[
          if (!compact) _sidebar(),
          if (!compact) const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: <Widget>[
                _statusBar(),
                Expanded(child: _content()),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: compact
          ? NavigationBar(
              selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
              onDestinationSelected: (index) {
                setState(() {
                  section = studioDestinations[index].section;
                });
              },
              destinations: studioDestinations.map((destination) {
                return NavigationDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: destination.label,
                );
              }).toList(),
            )
          : null,
      floatingActionButton: section == StudioSection.newTask
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                setState(() {
                  section = StudioSection.newTask;
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('New task'),
            ),
    );
  }

  Widget _sidebar() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 242,
      color: colors.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Kristin',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 19,
                            ),
                          ),
                          Text('Simple Studio', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              ...studioDestinations.map((destination) {
                final selected = destination.section == section;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: ListTile(
                    selected: selected,
                    selectedTileColor: colors.secondaryContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    leading: Icon(
                      selected ? destination.selectedIcon : destination.icon,
                    ),
                    title: Text(
                      destination.label,
                      style: TextStyle(
                        fontWeight: selected ? FontWeight.w700 : null,
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        section = destination.section;
                      });
                    },
                  ),
                );
              }),
              const Spacer(),
              if (selectedProject != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: <Widget>[
                        const Icon(Icons.folder_outlined, size: 19),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                'Working in',
                                style: TextStyle(fontSize: 11),
                              ),
                              Text(
                                selectedProject!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Settings'),
                onTap: busy ? null : () => _openSettings(),
              ),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: const Icon(Icons.help_outline),
                title: const Text('Help'),
                onTap: _showHelp,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBar() {
    final startup = widget.startupError;
    final activeRun = currentRun != null &&
        <RunState>{
          RunState.running,
          RunState.paused,
          RunState.cancelling,
          RunState.interrupted,
        }.contains(currentRun!.state);
    if (!busy && error == null && startup == null && !activeRun) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: error != null || startup != null
          ? colors.errorContainer
          : colors.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        child: Row(
          children: <Widget>[
            if (busy || currentRun?.state == RunState.running)
              const SizedBox.square(
                dimension: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                error != null || startup != null
                    ? Icons.error_outline
                    : Icons.pause_circle_outline,
                size: 18,
              ),
            const SizedBox(width: 10),
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
                onPressed: () {
                  setState(() {
                    error = null;
                  });
                },
                icon: const Icon(Icons.close),
              ),
          ],
        ),
      ),
    );
  }

  Widget _content() => switch (section) {
        StudioSection.newTask => _newTaskPage(),
        StudioSection.activity => _activityPage(),
        StudioSection.projects => _projectsPage(),
        StudioSection.templates => _templatesPage(),
      };

  Widget _newTaskPage() {
    return _pageScroll(<Widget>[
      StudioPageHeader(
        title: 'What would you like Kristin to make?',
        subtitle:
            'Describe the result in your own words. Kristin will choose the right mode, make a safe plan, and show every important step.',
        centered: prepared == null && currentRun == null,
        trailing: prepared == null && currentRun == null
            ? null
            : TextButton.icon(
                onPressed: busy ? null : _resetTask,
                icon: const Icon(Icons.add),
                label: const Text('New task'),
              ),
      ),
      if (projects.isEmpty)
        EmptyStateCard(
          icon: Icons.folder_open_outlined,
          title: 'Choose a safe project folder',
          message:
              'Kristin works only inside a folder you register. Existing files stay protected by checkpoints and project boundaries.',
          action: FilledButton.icon(
            onPressed: () {
              setState(() {
                section = StudioSection.projects;
              });
            },
            icon: const Icon(Icons.folder_open),
            label: const Text('Add a project'),
          ),
        )
      else if (models.isEmpty)
        EmptyStateCard(
          icon: Icons.memory_outlined,
          title: 'Connect an AI model',
          message:
              'Kristin found no installed model. Start Ollama or configure a compatible provider in Settings.',
          action: FilledButton.icon(
            onPressed: () => _openSettings(initialSection: 1),
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Open AI settings'),
          ),
        )
      else ...<Widget>[
        _taskContextBar(),
        if (prepared == null && currentRun == null) _quickStartGrid(),
        _composer(),
        if (prepared != null && currentRun == null) _friendlyPlan(),
        if (currentRun != null) _executionWorkspace(currentRun!),
      ],
    ], maxWidth: 1180);
  }

  Widget _taskContextBar() {
    final project = selectedProject;
    final model = selectedModel;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.folder_outlined, size: 18),
              const SizedBox(width: 8),
              const Text('Working in: '),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: project?.id,
                  isDense: true,
                  borderRadius: BorderRadius.circular(14),
                  items: projects.map((item) {
                    return DropdownMenuItem<String>(
                      value: item.id,
                      child: Text(item.name, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: busy ? null : _selectProject,
                ),
              ),
            ],
          ),
        ),
        StatusPill(
          label: model == null ? 'Auto AI unavailable' : 'Auto AI ready',
          icon: model == null ? Icons.memory_outlined : Icons.auto_awesome,
          emphasis: model != null,
        ),
        TextButton.icon(
          onPressed: busy ? null : () => _openSettings(initialSection: 1),
          icon: const Icon(Icons.tune, size: 18),
          label: const Text('More options'),
        ),
      ],
    );
  }

  Widget _quickStartGrid() {
    final quick = studioTemplates.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Start with an idea',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: quick.map((template) {
            return QuickTemplateCard(
              template: template,
              compact: true,
              onTap: () {
                _useTemplate(template);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _composer() {
    return StudioPanel(
      emphasized: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: requestController,
            focusNode: requestFocus,
            onChanged: (_) {
              setState(() {});
            },
            minLines: 4,
            maxLines: 12,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText:
                  'Describe what you want Kristin to create, fix, review, or explain…',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.all(4),
            ),
          ),
          const Divider(height: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              TextButton.icon(
                onPressed: selectedProjectId == null
                    ? null
                    : () {
                        unawaited(_openSettings(initialSection: 2));
                      },
                icon: const Icon(Icons.menu_book_outlined, size: 19),
                label: const Text('Add sources'),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<SimpleTaskMode>(
                  value: simpleTaskMode,
                  borderRadius: BorderRadius.circular(14),
                  items: SimpleTaskMode.values.map((choice) {
                    return DropdownMenuItem<SimpleTaskMode>(
                      value: choice,
                      child: Text(simpleModeLabel(choice)),
                    );
                  }).toList(),
                  onChanged: busy
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              simpleTaskMode = value;
                            });
                          }
                        },
                ),
              ),
              if (simpleTaskMode == SimpleTaskMode.choose)
                DropdownButtonHideUnderline(
                  child: DropdownButton<CommandMode>(
                    value: chosenMode,
                    borderRadius: BorderRadius.circular(14),
                    items: CommandMode.values.map((mode) {
                      return DropdownMenuItem<CommandMode>(
                        value: mode,
                        child: Text(modeLabel(mode)),
                      );
                    }).toList(),
                    onChanged: busy
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() {
                                chosenMode = value;
                              });
                            }
                          },
                  ),
                ),
              const SizedBox(width: 6),
              FilledButton.icon(
                onPressed: busy ||
                        selectedProject == null ||
                        selectedModel == null ||
                        requestController.text.trim().isEmpty
                    ? null
                    : _preparePlan,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_forward),
                label: const Text('Start'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _friendlyPlan() {
    final command = prepared!;
    final required = command.contract.requiredPermissions;
    final groups = groupPermissions(required);
    final allSelected = selectedAccessScopes.containsAll(required);
    return StudioPanel(
      emphasized: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  Icons.route_outlined,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Kristin’s plan',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'A checkpoint will be created before any project change.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: <Widget>[
                  StatusPill(
                    label: jobSizeLabel(command.plan.complexity),
                    icon: Icons.straighten_outlined,
                  ),
                  StatusPill(
                    label: modeLabel(command.contract.mode),
                    icon: Icons.auto_awesome_outlined,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...command.plan.items.take(5).toList().asMap().entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.secondaryContainer,
                    child: Text(
                      '${entry.key + 1}',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          entry.value.title,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.value.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          if (command.plan.items.length > 5)
            Text(
              '+ ${command.plan.items.length - 5} more protected steps',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const Divider(height: 30),
          Text(
            'Access needed',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Kristin can use only the access shown below, only for this project and this task.',
          ),
          const SizedBox(height: 12),
          ...groups.map((group) {
            final selected = selectedAccessScopes.containsAll(group.scopes);
            return CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: selected,
              secondary: Icon(group.icon),
              title: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text(group.title),
                  if (group.highRisk)
                    const StatusPill(
                      label: 'Extra approval',
                      icon: Icons.shield_outlined,
                    ),
                ],
              ),
              subtitle: Text(group.description),
              controlAffinity: ListTileControlAffinity.trailing,
              onChanged: busy
                  ? null
                  : (value) {
                      setState(() {
                        if (value == true) {
                          selectedAccessScopes.addAll(group.scopes);
                        } else {
                          selectedAccessScopes.removeAll(group.scopes);
                        }
                      });
                    },
            );
          }),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Kristin cannot:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 7),
                Text('• Read files outside this project'),
                Text('• Reveal saved secret values'),
                Text('• Publish or deploy without the required approval'),
              ],
            ),
          ),
          if (!allSelected) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              'This plan cannot run until every required access group is enabled. Change the request to remove access you do not want to grant.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: <Widget>[
              FilledButton.icon(
                onPressed: busy || !allSelected ? null : _allowAndStart,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Allow once and start'),
              ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () {
                        setState(() {
                          prepared = null;
                          selectedAccessScopes.clear();
                        });
                        requestFocus.requestFocus();
                      },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Change request'),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    showAdvancedPlan = !showAdvancedPlan;
                  });
                },
                icon: Icon(
                  showAdvancedPlan ? Icons.expand_less : Icons.expand_more,
                ),
                label: const Text('Advanced details'),
              ),
            ],
          ),
          if (showAdvancedPlan) ...<Widget>[
            const Divider(height: 30),
            _advancedPlanDetails(command),
          ],
        ],
      ),
    );
  }

  Widget _advancedPlanDetails(PreparedCommand command) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Technical contract',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        SelectableText(
          'Mode: ${command.contract.mode.name}\n'
          'Complexity: ${command.plan.complexity}/10\n'
          'Exact model: ${command.model.exactId}\n'
          'Contract revision: ${command.contract.revision}',
        ),
        const SizedBox(height: 16),
        Text(
          'Acceptance criteria',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        ...command.contract.acceptanceCriteria.map((criterion) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(
              criterion.isMeasurable
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_outlined,
            ),
            title: Text(criterion.statement),
            subtitle: Text(criterion.verification),
          );
        }),
        if (command.contract.constraints.isNotEmpty) ...<Widget>[
          Text(
            'Constraints',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          ...command.contract.constraints.map((constraint) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.shield_outlined),
              title: Text(constraint),
            );
          }),
        ],
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () {
            setState(() {
              showGranularAccess = !showGranularAccess;
            });
          },
          icon: Icon(
            showGranularAccess ? Icons.expand_less : Icons.expand_more,
          ),
          label: const Text('Show granular permission scopes'),
        ),
        if (showGranularAccess)
          SelectableText(
            command.contract.requiredPermissions
                .map((scope) => scope.name)
                .join('\n'),
          ),
      ],
    );
  }

  Widget _executionWorkspace(RunRecord run) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (<RunState>{
          RunState.succeeded,
          RunState.failed,
          RunState.cancelled,
        }.contains(run.state))
          _resultCard(run),
        StudioPanel(
          child: FivePhaseProgress(prepared: prepared, run: run),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final split = constraints.maxWidth >= 980;
            final conversation = _conversationPanel(run);
            final output = _outputPanel(run);
            if (!split) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  conversation,
                  const SizedBox(height: 14),
                  output,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 5, child: conversation),
                const SizedBox(width: 14),
                Expanded(flex: 7, child: output),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _resultCard(RunRecord run) {
    final success = run.state == RunState.succeeded;
    final cancelled = run.state == RunState.cancelled;
    final colors = Theme.of(context).colorScheme;
    final paths = _artifactPaths(evidence);
    final tests = _testEvidence(evidence);
    return Card(
      color: success
          ? colors.primaryContainer
          : cancelled
              ? colors.surfaceContainerHighest
              : colors.errorContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  success
                      ? Icons.check_circle
                      : cancelled
                          ? Icons.stop_circle_outlined
                          : Icons.error_outline,
                  size: 30,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    success
                        ? 'Done — your result is ready'
                        : cancelled
                            ? 'The task stopped safely'
                            : 'Kristin stopped safely',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              success
                  ? (run.summary.trim().isEmpty
                      ? 'All protected steps and checks completed.'
                      : run.summary)
                  : cancelled
                      ? 'Your saved checkpoint and completed evidence remain available.'
                      : '${run.failure ?? 'A verification step could not be completed.'}\nYour previous files were restored when required.',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                StatusPill(
                  label: '${paths.length} files referenced',
                  icon: Icons.description_outlined,
                ),
                StatusPill(
                  label: '${tests.length} checks recorded',
                  icon: Icons.fact_check_outlined,
                ),
                StatusPill(
                  label: '${evidence.length} evidence records',
                  icon: Icons.verified_outlined,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: selectedProject == null ? null : _copyProjectPath,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Copy project path'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      workspaceView = WorkspaceView.changes;
                    });
                  },
                  icon: const Icon(Icons.difference_outlined),
                  label: const Text('See changes'),
                ),
                if (!success)
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : _retryCurrentRun,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Let Kristin try again'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _conversationPanel(RunRecord run) {
    final events = _eventsForRun(run).reversed.take(10).toList().reversed;
    return StudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.secondaryContainer,
                child: Icon(
                  Icons.auto_awesome,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Kristin',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      friendlyRunState(run.state),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _runStatePill(run.state),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            constraints: const BoxConstraints(minHeight: 260, maxHeight: 420),
            child: events.isEmpty
                ? const Center(
                    child: Text('Kristin is getting the first step ready.'),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: events.map((event) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Icon(
                                _eventIcon(event.type),
                                size: 17,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(humanEventText(event, run: run)),
                                  const SizedBox(height: 2),
                                  Text(
                                    _timeLabel(event.timestamp),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const Divider(height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: run.state == RunState.running && !busy
                    ? () {
                        unawaited(_controlRun('pause'));
                      }
                    : null,
                icon: const Icon(Icons.pause),
                label: const Text('Pause'),
              ),
              OutlinedButton.icon(
                onPressed: <RunState>{
                          RunState.paused,
                          RunState.interrupted,
                        }.contains(run.state) &&
                        !busy
                    ? () {
                        unawaited(_controlRun('resume'));
                      }
                    : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Continue'),
              ),
              OutlinedButton.icon(
                onPressed: <RunState>{
                          RunState.running,
                          RunState.paused,
                          RunState.cancelling,
                        }.contains(run.state) &&
                        !busy
                    ? () {
                        unawaited(_controlRun('cancel'));
                      }
                    : null,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop'),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    section = StudioSection.activity;
                    inspectorSection = InspectorSection.logs;
                  });
                },
                icon: const Icon(Icons.tune_outlined),
                label: const Text('Details'),
              ),
            ],
          ),
          if (<RunState>{
            RunState.succeeded,
            RunState.failed,
            RunState.cancelled,
          }.contains(run.state)) ...<Widget>[
            const SizedBox(height: 16),
            TextField(
              controller: followUpController,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'Ask Kristin to change or improve something…',
                suffixIcon: IconButton(
                  tooltip: 'Create follow-up task',
                  onPressed: followUpController.text.trim().isEmpty
                      ? null
                      : _startFollowUp,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
              onChanged: (_) {
                setState(() {});
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _outputPanel(RunRecord run) {
    return StudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: WorkspaceView.values.map((view) {
                return Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: ChoiceChip(
                    selected: workspaceView == view,
                    avatar: Icon(_workspaceIcon(view), size: 17),
                    label: Text(_workspaceLabel(view)),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          workspaceView = view;
                        });
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 26),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: KeyedSubtree(
              key: ValueKey<WorkspaceView>(workspaceView),
              child: switch (workspaceView) {
                WorkspaceView.preview => _previewView(run),
                WorkspaceView.files => _filesView(),
                WorkspaceView.changes => _evidenceView(
                    _mutationEvidence(evidence),
                    emptyTitle: 'No file changes recorded yet',
                    emptyMessage:
                        'Changed files will appear here as Kristin works.',
                  ),
                WorkspaceView.tests => _evidenceView(
                    _testEvidence(evidence),
                    emptyTitle: 'No test results recorded yet',
                    emptyMessage:
                        'Build, test, and verification evidence will appear here.',
                  ),
                WorkspaceView.flow => _flowView(run),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewView(RunRecord run) {
    final latest = evidence.reversed.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          run.state == RunState.succeeded ? 'Result' : 'Live output',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Text(
          run.summary.trim().isEmpty
              ? 'Kristin is collecting verified output for this task.'
              : run.summary,
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            StatusPill(
              label: '${run.items.length} steps',
              icon: Icons.route_outlined,
            ),
            StatusPill(
              label: '${run.mutations} mutations',
              icon: Icons.edit_note_outlined,
            ),
            StatusPill(
              label: '${run.repairs} repairs',
              icon: Icons.build_outlined,
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (latest.isEmpty)
          const EmptyStateCard(
            icon: Icons.auto_awesome_outlined,
            title: 'Output is on the way',
            message:
                'Verified summaries, changed files, tests, and packages will appear as each step finishes.',
          )
        else ...<Widget>[
          Text(
            'Latest verified output',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...latest.map((item) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_evidenceIcon(item.kind)),
              title: Text(item.summary),
              subtitle: Text(_timeLabel(item.createdAt)),
            );
          }),
        ],
      ],
    );
  }

  Widget _filesView() {
    final paths = _artifactPaths(evidence);
    if (paths.isEmpty) {
      return const EmptyStateCard(
        icon: Icons.description_outlined,
        title: 'No files referenced yet',
        message:
            'Files created, changed, tested, or packaged will be listed here.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Files',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ...paths.map((path) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: SelectableText(path),
          );
        }),
      ],
    );
  }

  Widget _evidenceView(
    List<EvidenceRecord> items, {
    required String emptyTitle,
    required String emptyMessage,
  }) {
    if (items.isEmpty) {
      return EmptyStateCard(
        icon: Icons.fact_check_outlined,
        title: emptyTitle,
        message: emptyMessage,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items.reversed.map((item) {
        return ExpansionTile(
          tilePadding: EdgeInsets.zero,
          leading: Icon(_evidenceIcon(item.kind)),
          title: Text(item.summary),
          subtitle: Text(_timeLabel(item.createdAt)),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 14),
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(item.payload),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _flowView(RunRecord run) {
    final selected = run.items
        .where((progress) => progress.item.id == selectedFlowItemId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'How the task flows',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Select a step to inspect its purpose, checks, and allowed tools.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: run.items.map((progress) {
            return FlowNode(
              title: progress.item.title,
              state: progress.state,
              onTap: () {
                setState(() {
                  selectedFlowItemId = progress.item.id;
                });
              },
            );
          }).toList(),
        ),
        if (selected != null) ...<Widget>[
          const Divider(height: 30),
          Text(
            selected.item.title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(selected.item.description),
          const SizedBox(height: 10),
          Text('State: ${friendlyWorkState(selected.state)}'),
          Text('Attempts: ${selected.attempts}/${selected.item.maxAttempts}'),
          if (selected.lastError != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              selected.lastError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 10),
          SelectableText(
            'Allowed tools: ${selected.item.allowedTools.join(', ')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _activityPage() {
    return _pageScroll(<Widget>[
      StudioPageHeader(
        title: 'Activity',
        subtitle:
            'See what Kristin did, what changed, which checks passed, and the full redacted execution trail.',
        trailing: OutlinedButton.icon(
          onPressed: busy
              ? null
              : () {
                  unawaited(_refreshRuns());
                },
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      ),
      if (projects.isNotEmpty) _taskContextBar(),
      if (runs.isEmpty)
        EmptyStateCard(
          icon: Icons.history_outlined,
          title: 'No activity yet',
          message:
              'Start a task and its friendly progress, evidence, changes, and logs will appear here.',
          action: FilledButton.icon(
            onPressed: () {
              setState(() {
                section = StudioSection.newTask;
              });
            },
            icon: const Icon(Icons.add),
            label: const Text('Start a task'),
          ),
        )
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final split = constraints.maxWidth >= 980;
            final list = _runList();
            final inspector = currentRun == null
                ? const EmptyStateCard(
                    icon: Icons.touch_app_outlined,
                    title: 'Choose an activity',
                    message:
                        'Select a task to inspect its result and execution details.',
                  )
                : _activityInspector(currentRun!);
            if (!split) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[list, const SizedBox(height: 14), inspector],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(width: 360, child: list),
                const SizedBox(width: 14),
                Expanded(child: inspector),
              ],
            );
          },
        ),
    ], maxWidth: 1280);
  }

  Widget _runList() {
    return StudioPanel(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Text(
              'Recent tasks',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          ...runs.map((run) {
            final selected = selectedRunId == run.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: ListTile(
                selected: selected,
                selectedTileColor: Theme.of(
                  context,
                ).colorScheme.secondaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                leading: _runStateIcon(run.state),
                title: Text(
                  run.command.contract.request,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${friendlyRunState(run.state)} · ${_timeLabel(run.updatedAt)}',
                ),
                onTap: () {
                  unawaited(_selectRun(run));
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _activityInspector(RunRecord run) {
    return StudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _runStateIcon(run.state, size: 28),
              const SizedBox(width: 10),
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
                    const SizedBox(height: 4),
                    Text(friendlyRunState(run.state)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: InspectorSection.values.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(right: 7),
                  child: ChoiceChip(
                    selected: inspectorSection == item,
                    label: Text(_inspectorLabel(item)),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          inspectorSection = item;
                        });
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 26),
          switch (inspectorSection) {
            InspectorSection.summary => _activitySummary(run),
            InspectorSection.steps => _activitySteps(run),
            InspectorSection.changes => _evidenceView(
                _mutationEvidence(evidence),
                emptyTitle: 'No changes recorded',
                emptyMessage: 'This task did not record project mutations.',
              ),
            InspectorSection.tests => _evidenceView(
                _testEvidence(evidence),
                emptyTitle: 'No checks recorded',
                emptyMessage: 'This task did not record test evidence.',
              ),
            InspectorSection.sources => _evidenceView(
                evidence
                    .where((item) => item.kind == EvidenceKind.research)
                    .toList(),
                emptyTitle: 'No web sources used',
                emptyMessage:
                    'This task used local project context and did not fetch research.',
              ),
            InspectorSection.logs => _logsView(run),
          },
        ],
      ),
    );
  }

  Widget _activitySummary(RunRecord run) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (run.summary.isNotEmpty) Text(run.summary),
        if (run.failure != null) ...<Widget>[
          Text(
            run.failure!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            StatusPill(
              label: modeLabel(run.command.contract.mode),
              icon: Icons.auto_awesome_outlined,
            ),
            StatusPill(
              label: '${run.items.length} steps',
              icon: Icons.route_outlined,
            ),
            StatusPill(
              label: '${run.toolCalls} tool calls',
              icon: Icons.build_outlined,
            ),
            StatusPill(
              label: '${run.modelRequests} AI turns',
              icon: Icons.memory_outlined,
            ),
          ],
        ),
        const SizedBox(height: 18),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Technical identity'),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SelectableText(
                'Run: ${run.id}\n'
                'Command: ${run.command.id}\n'
                'Exact model: ${run.command.model.exactId}\n'
                'Created: ${run.createdAt.toLocal()}\n'
                'Updated: ${run.updatedAt.toLocal()}',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _activitySteps(RunRecord run) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: run.items.map((progress) {
        return ExpansionTile(
          tilePadding: EdgeInsets.zero,
          leading: _workStateIcon(progress.state),
          title: Text(progress.item.title),
          subtitle: Text(
            '${friendlyWorkState(progress.state)} · attempts ${progress.attempts}/${progress.item.maxAttempts}',
          ),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(progress.item.description),
                  if (progress.lastError != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      progress.lastError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SelectableText(
                    'Allowed tools: ${progress.item.allowedTools.join(', ')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _logsView(RunRecord run) {
    final events = _eventsForRun(run);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SegmentedButton<LogDetail>(
          segments: const <ButtonSegment<LogDetail>>[
            ButtonSegment<LogDetail>(
              value: LogDetail.simple,
              label: Text('Simple'),
              icon: Icon(Icons.chat_bubble_outline),
            ),
            ButtonSegment<LogDetail>(
              value: LogDetail.technical,
              label: Text('Technical'),
              icon: Icon(Icons.terminal_outlined),
            ),
            ButtonSegment<LogDetail>(
              value: LogDetail.raw,
              label: Text('Raw'),
              icon: Icon(Icons.data_object),
            ),
          ],
          selected: <LogDetail>{logDetail},
          onSelectionChanged: (selection) {
            setState(() {
              logDetail = selection.first;
            });
          },
        ),
        const SizedBox(height: 16),
        if (events.isEmpty)
          const Text('No run events are available.')
        else
          ...events.reversed.map((event) {
            final text = switch (logDetail) {
              LogDetail.simple => humanEventText(event, run: run),
              LogDetail.technical =>
                '${event.type} · ${event.timestamp.toLocal()} · ${event.correlationId}',
              LogDetail.raw => runtime.redactor.redact(
                  const JsonEncoder.withIndent('  ').convert(event.toJson()),
                ),
            };
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SelectableText(
                text,
                style: logDetail == LogDetail.raw
                    ? const TextStyle(fontFamily: 'monospace', fontSize: 12)
                    : null,
              ),
            );
          }),
      ],
    );
  }

  Widget _projectsPage() {
    return _pageScroll(<Widget>[
      const StudioPageHeader(
        title: 'Projects',
        subtitle:
            'A project is the safe folder where Kristin can read, create, test, and package work. Files outside it remain unavailable.',
      ),
      StudioPanel(
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          initiallyExpanded: projects.isEmpty,
          leading: const Icon(Icons.create_new_folder_outlined),
          title: const Text('Open an existing folder'),
          subtitle: const Text(
            'Register a local folder without moving or deleting its files.',
          ),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    controller: projectNameController,
                    decoration: const InputDecoration(
                      labelText: 'Project name',
                      hintText: 'My Telegram bot',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: projectPathController,
                    decoration: const InputDecoration(
                      labelText: 'Existing folder path',
                      hintText: r'C:\dev\my_project',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: busy ? null : _addProject,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Add project'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (projects.isEmpty)
        const EmptyStateCard(
          icon: Icons.folder_open_outlined,
          title: 'No projects yet',
          message:
              'Add one existing folder. Kristin will use it as a strict safety boundary.',
        )
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final cardWidth = width >= 1000
                ? (width - 28) / 3
                : width >= 640
                    ? (width - 14) / 2
                    : width;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: projects.map((project) {
                final selected = project.id == selectedProjectId;
                return SizedBox(
                  width: cardWidth,
                  child: Card(
                    color: selected
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(
                                selected
                                    ? Icons.folder_special
                                    : Icons.folder_outlined,
                                size: 28,
                              ),
                              const Spacer(),
                              if (selected)
                                const StatusPill(
                                  label: 'Active',
                                  icon: Icons.check,
                                  emphasis: true,
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            project.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
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
                                onPressed: busy
                                    ? null
                                    : () {
                                        unawaited(_selectProject(project.id));
                                      },
                                child: Text(
                                  selected
                                      ? 'Using this project'
                                      : 'Use project',
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove registration',
                                onPressed: busy
                                    ? null
                                    : () {
                                        unawaited(_removeProject(project));
                                      },
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      if (selectedProject != null)
        StudioPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                selectedProject!.name,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'This folder is the boundary for task files, checkpoints, permissions, knowledge, processes, and integrations.',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        section = StudioSection.newTask;
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('New task here'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _copyProjectPath,
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copy folder path'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        section = StudioSection.activity;
                      });
                    },
                    icon: const Icon(Icons.history),
                    label: const Text('See activity'),
                  ),
                ],
              ),
            ],
          ),
        ),
    ], maxWidth: 1180);
  }

  Widget _templatesPage() {
    return _pageScroll(<Widget>[
      const StudioPageHeader(
        title: 'Templates',
        subtitle:
            'Begin with a proven request, then describe your exact idea. Templates choose a sensible mode but never bypass planning or approval.',
      ),
      LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final cardWidth = width >= 1000
              ? (width - 28) / 3
              : width >= 650
                  ? (width - 14) / 2
                  : width;
          return Wrap(
            spacing: 14,
            runSpacing: 14,
            children: studioTemplates.map((template) {
              return SizedBox(
                width: cardWidth,
                child: QuickTemplateCard(
                  template: template,
                  onTap: () {
                    _useTemplate(template);
                  },
                ),
              );
            }).toList(),
          );
        },
      ),
      const StudioPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'What happens after choosing a template?',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            SizedBox(height: 10),
            Text('1. Kristin fills the request with a strong starting point.'),
            Text('2. You change any words you want.'),
            Text(
              '3. Kristin creates a friendly plan and shows required access.',
            ),
            Text('4. Work starts only after you approve that exact plan.'),
          ],
        ),
      ),
    ], maxWidth: 1180);
  }

  Widget _pageScroll(List<Widget> children, {required double maxWidth}) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                ...children.expand((widget) {
                  return <Widget>[widget, const SizedBox(height: 16)];
                }),
                const SizedBox(height: 70),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<EventEnvelope> _eventsForRun(RunRecord run) {
    return recentEvents.where((event) {
      return event.correlationId == run.id ||
          event.data['runId']?.toString() == run.id;
    }).toList(growable: false);
  }

  List<EvidenceRecord> _mutationEvidence(List<EvidenceRecord> items) {
    return items.where((item) {
      return item.kind == EvidenceKind.mutation ||
          item.summary.toLowerCase().contains('file') ||
          item.summary.toLowerCase().contains('patch');
    }).toList();
  }

  List<EvidenceRecord> _testEvidence(List<EvidenceRecord> items) {
    return items.where((item) {
      final summary = item.summary.toLowerCase();
      return <EvidenceKind>{
            EvidenceKind.test,
            EvidenceKind.verification,
          }.contains(item.kind) ||
          summary.contains('test') ||
          summary.contains('verify') ||
          summary.contains('analysis') ||
          summary.contains('build');
    }).toList();
  }

  List<String> _artifactPaths(List<EvidenceRecord> items) {
    final paths = <String>{};

    void visit(Object? value, {String key = ''}) {
      if (value is Map) {
        for (final entry in value.entries) {
          visit(entry.value, key: entry.key.toString());
        }
      } else if (value is List) {
        for (final item in value) {
          visit(item, key: key);
        }
      } else if (value is String) {
        final lower = key.toLowerCase();
        final pathKey = lower.contains('path') ||
            lower.contains('file') ||
            lower.contains('target') ||
            lower.contains('artifact');
        final looksLikePath = value.contains('/') || value.contains('\\');
        final looksLikeUrl =
            value.startsWith('http://') || value.startsWith('https://');
        if (pathKey && looksLikePath && !looksLikeUrl && value.length < 500) {
          paths.add(value);
        }
      }
    }

    for (final item in items) {
      visit(item.payload);
    }
    final ordered = paths.toList()..sort();
    return ordered;
  }

  Widget _runStatePill(RunState state) {
    return StatusPill(
      label: friendlyRunState(state),
      icon: _runStateIconData(state),
      emphasis: state == RunState.running || state == RunState.succeeded,
    );
  }

  Widget _runStateIcon(RunState state, {double size = 22}) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (state) {
      RunState.succeeded => colors.primary,
      RunState.failed => colors.error,
      RunState.cancelled => colors.onSurfaceVariant,
      RunState.running => colors.secondary,
      RunState.paused => colors.tertiary,
      _ => colors.onSurfaceVariant,
    };
    return Icon(_runStateIconData(state), color: color, size: size);
  }

  IconData _runStateIconData(RunState state) => switch (state) {
        RunState.succeeded => Icons.check_circle,
        RunState.failed => Icons.error,
        RunState.cancelled => Icons.stop_circle,
        RunState.running => Icons.play_circle,
        RunState.paused => Icons.pause_circle,
        RunState.interrupted => Icons.power_settings_new,
        RunState.awaitingApproval => Icons.front_hand_outlined,
        RunState.cancelling => Icons.pending,
        RunState.queued => Icons.schedule,
        RunState.prepared => Icons.fact_check_outlined,
      };

  Widget _workStateIcon(WorkItemState state) {
    return Icon(switch (state) {
      WorkItemState.succeeded => Icons.check_circle_outline,
      WorkItemState.failed => Icons.error_outline,
      WorkItemState.running => Icons.autorenew,
      WorkItemState.blocked => Icons.block,
      WorkItemState.cancelled => Icons.stop_circle_outlined,
      WorkItemState.awaitingApproval => Icons.front_hand_outlined,
      WorkItemState.queued => Icons.radio_button_unchecked,
    });
  }

  IconData _eventIcon(String type) {
    if (type.contains('failed')) {
      return Icons.error_outline;
    }
    if (type.contains('succeeded')) {
      return Icons.check_circle_outline;
    }
    if (type.contains('started')) {
      return Icons.play_circle_outline;
    }
    if (type.contains('evidence')) {
      return Icons.verified_outlined;
    }
    return Icons.circle_outlined;
  }

  IconData _evidenceIcon(EvidenceKind kind) => switch (kind) {
        EvidenceKind.model => Icons.memory_outlined,
        EvidenceKind.knowledge => Icons.search,
        EvidenceKind.research => Icons.public_outlined,
        EvidenceKind.mutation => Icons.edit_note_outlined,
        EvidenceKind.command => Icons.terminal_outlined,
        EvidenceKind.test => Icons.science_outlined,
        EvidenceKind.verification => Icons.fact_check_outlined,
        EvidenceKind.deployment => Icons.archive_outlined,
        EvidenceKind.audit => Icons.verified_user_outlined,
      };

  IconData _workspaceIcon(WorkspaceView view) => switch (view) {
        WorkspaceView.preview => Icons.visibility_outlined,
        WorkspaceView.files => Icons.description_outlined,
        WorkspaceView.changes => Icons.difference_outlined,
        WorkspaceView.tests => Icons.fact_check_outlined,
        WorkspaceView.flow => Icons.account_tree_outlined,
      };

  String _workspaceLabel(WorkspaceView view) => switch (view) {
        WorkspaceView.preview => 'Preview',
        WorkspaceView.files => 'Files',
        WorkspaceView.changes => 'Changes',
        WorkspaceView.tests => 'Tests',
        WorkspaceView.flow => 'Flow',
      };

  String _inspectorLabel(InspectorSection item) => switch (item) {
        InspectorSection.summary => 'Summary',
        InspectorSection.steps => 'Steps',
        InspectorSection.changes => 'Changes',
        InspectorSection.tests => 'Tests',
        InspectorSection.sources => 'Sources',
        InspectorSection.logs => 'Logs',
      };

  String _sectionTitle(StudioSection value) => switch (value) {
        StudioSection.newTask => 'New task',
        StudioSection.activity => 'Activity',
        StudioSection.projects => 'Projects',
        StudioSection.templates => 'Templates',
      };

  String _timeLabel(DateTime value) {
    final local = value.toLocal();
    final now = DateTime.now();
    final difference = now.difference(local);
    if (difference.inMinutes < 1) {
      return 'just now';
    }
    if (difference.inHours < 1) {
      return '${difference.inMinutes} min ago';
    }
    if (difference.inDays < 1) {
      return '${difference.inHours} h ago';
    }
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}

class _HelpStep extends StatelessWidget {
  const _HelpStep({
    required this.number,
    required this.title,
    required this.message,
  });

  final String number;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 16,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              number,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
