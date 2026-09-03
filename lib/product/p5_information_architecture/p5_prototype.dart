import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../browser/browser_runtime.dart';
import '../p2_product_runtime_bootstrap.dart';
import '../p5_global_autonomy.dart';

import 'p5_controller.dart';
import 'p5_fixtures.dart';
import 'p5_models.dart';
import 'p5_shell_layout.dart';

part 'p5_task_workspaces.dart';
part 'p5_verification_workspaces.dart';
part 'p5_support_workspaces.dart';
part 'p5_components.dart';
part 'p5_shell_workspace.dart';

class P5InformationArchitectureApp extends StatefulWidget {
  const P5InformationArchitectureApp({super.key, this.controller});

  final P5InformationArchitectureController? controller;

  @override
  State<P5InformationArchitectureApp> createState() =>
      _P5InformationArchitectureAppState();
}

class _P5InformationArchitectureAppState
    extends State<P5InformationArchitectureApp> {
  late final P5InformationArchitectureController controller;
  late final bool ownsController;

  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? P5InformationArchitectureController();
    ownsController = widget.controller == null;
  }

  @override
  void dispose() {
    if (ownsController) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xff6558d3));
    return MaterialApp(
      title: 'Kristin P5-001 IA Prototype',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: P5InformationArchitecturePrototype(controller: controller),
    );
  }
}

typedef P5BrowserSessionStarter = Future<P3BrowserSessionProcess> Function();

class P5InformationArchitecturePrototype extends StatefulWidget {
  const P5InformationArchitecturePrototype({
    super.key,
    required this.controller,
    this.ownerMode,
    this.browserSessionStarter,
    this.browserRuntimeAvailable = false,
    this.browserRuntimeStatusCode = 'p3_runtime_not_bound',
    this.browserRuntimeProvenance = const <String, Object?>{},
    this.layoutPersistence,
    this.globalAutonomy,
    this.onOpenOwnerMode,
  });

  final P5InformationArchitectureController controller;
  final P2ProductRuntimeOwnerModeHandle? ownerMode;
  final P5BrowserSessionStarter? browserSessionStarter;
  final bool browserRuntimeAvailable;
  final String browserRuntimeStatusCode;
  final Map<String, Object?> browserRuntimeProvenance;
  final P5ShellLayoutPersistence? layoutPersistence;
  final P5GlobalAutonomyBinding? globalAutonomy;
  final VoidCallback? onOpenOwnerMode;

  @override
  State<P5InformationArchitecturePrototype> createState() =>
      _P5InformationArchitecturePrototypeState();
}

class _P5InformationArchitecturePrototypeState
    extends State<P5InformationArchitecturePrototype> {
  late final TextEditingController _taskController = TextEditingController(
    text: widget.controller.state.taskDraft,
  );
  late final TextEditingController _composerAttachmentsController =
      TextEditingController(
        text: widget.controller.state.attachments.join('\n'),
      );
  late final TextEditingController _composerCriteriaController =
      TextEditingController(
        text: widget.controller.state.acceptanceCriteria.join('\n'),
      );
  final TextEditingController _webProfileController = TextEditingController(
    text: 'work',
  );
  final TextEditingController _webUrlController = TextEditingController(
    text: 'http://127.0.0.1:3000/',
  );
  final TextEditingController _webLocatorController = TextEditingController(
    text: 'body',
  );
  final TextEditingController _webRoleController = TextEditingController(
    text: 'button',
  );
  final TextEditingController _webActionValueController =
      TextEditingController();
  final TextEditingController _webTargetController = TextEditingController();
  final TextEditingController _webUploadPathController =
      TextEditingController();
  final TextEditingController _webUploadNameController = TextEditingController(
    text: 'upload.bin',
  );
  final TextEditingController _webUploadMimeController = TextEditingController(
    text: 'application/octet-stream',
  );

  P3BrowserSessionProcess? _webBrowser;
  P3BrowserSessionKind _webSessionKind = P3BrowserSessionKind.ephemeral;
  P3BrowserActionKind _webAction = P3BrowserActionKind.click;
  String _webLocatorStrategy = 'css';
  String _webPanel = 'Browser';
  bool _webDownloadsEnabled = true;
  bool _webUploadsEnabled = true;
  bool _webBusy = false;
  String? _webError;
  List<P3BrowserSessionInfo> _webSessions = <P3BrowserSessionInfo>[];
  List<P3BrowserPageInfo> _webPages = <P3BrowserPageInfo>[];
  String? _webSelectedSessionId;
  String? _webSelectedPageId;
  P3BrowserPageObservation? _webObservation;
  List<P3BrowserDownloadReceipt> _webDownloads = <P3BrowserDownloadReceipt>[];
  List<P3BrowserUploadReceipt> _webUploads = <P3BrowserUploadReceipt>[];
  final List<String> _webActivity = <String>[];
  P5ShellLayoutPersistence? _shellLayoutStore;
  Timer? _shellLayoutSaveDebounce;
  P5TimelineCategory? _timelineFilter;

  P5InformationArchitectureController get controller => widget.controller;

  void mutatePresentation(VoidCallback update) {
    if (!mounted) {
      return;
    }
    setState(update);
  }

  String get _liveOwnerLabel {
    final handle = widget.ownerMode;
    if (handle == null) return controller.state.ownerModeState.label;
    if (!handle.available) return 'Unavailable';
    final settings = handle.runtime!.controller.current;
    if (!settings.enabled) return 'Available, off';
    return settings.unattended ? 'Enabled unattended' : 'Enabled';
  }

  @override
  void initState() {
    super.initState();
    widget.globalAutonomy?.registerBrowserEmergencyStop(
      _p5EmergencyStopBrowser,
    );
    unawaited(_initializeP5ShellLayout());
  }

  Future<void> _p5EmergencyStopBrowser() async {
    final process = _webBrowser;
    _webBrowser = null;
    if (process != null) await process.close();
    if (mounted) {
      mutatePresentation(() {
        _webSessions = <P3BrowserSessionInfo>[];
        _webPages = <P3BrowserPageInfo>[];
        _webSelectedSessionId = null;
        _webSelectedPageId = null;
        _webObservation = null;
        _webDownloads = <P3BrowserDownloadReceipt>[];
        _webUploads = <P3BrowserUploadReceipt>[];
      });
    }
    widget.globalAutonomy?.updateBrowserSessionCount(0);
  }

  @override
  void dispose() {
    widget.globalAutonomy?.registerBrowserEmergencyStop(null);
    widget.globalAutonomy?.updateBrowserSessionCount(0);
    _shellLayoutSaveDebounce?.cancel();
    unawaited(_webBrowser?.close());
    _taskController.dispose();
    _composerAttachmentsController.dispose();
    _composerCriteriaController.dispose();
    _webProfileController.dispose();
    _webUrlController.dispose();
    _webLocatorController.dispose();
    _webRoleController.dispose();
    _webActionValueController.dispose();
    _webTargetController.dispose();
    _webUploadPathController.dispose();
    _webUploadNameController.dispose();
    _webUploadMimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.escape): const _P5BackIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
            const _P5BackIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            const _P5ForwardIntent(),
        const SingleActivator(LogicalKeyboardKey.digit1, alt: true):
            const _P5WorkspaceIntent(P5WorkspaceId.homeChat),
        const SingleActivator(LogicalKeyboardKey.digit2, alt: true):
            const _P5WorkspaceIntent(P5WorkspaceId.projects),
        const SingleActivator(LogicalKeyboardKey.digit3, alt: true):
            const _P5WorkspaceIntent(P5WorkspaceId.runsActivity),
        const SingleActivator(LogicalKeyboardKey.digit4, alt: true):
            const _P5WorkspaceIntent(P5WorkspaceId.verificationCenter),
        const SingleActivator(LogicalKeyboardKey.digit5, alt: true):
            const _P5WorkspaceIntent(P5WorkspaceId.ownerMode),
        const SingleActivator(LogicalKeyboardKey.digit6, alt: true):
            const _P5WorkspaceIntent(P5WorkspaceId.settingsDiagnostics),
        const SingleActivator(LogicalKeyboardKey.digit7, alt: true):
            const _P5WorkspaceIntent(P5WorkspaceId.evidence),
        const SingleActivator(LogicalKeyboardKey.digit8, alt: true):
            const _P5WorkspaceIntent(P5WorkspaceId.modelsProviders),
        const SingleActivator(LogicalKeyboardKey.digit9, alt: true):
            const _P5WorkspaceIntent(P5WorkspaceId.capabilitiesIntegrations),
        const SingleActivator(
          LogicalKeyboardKey.keyV,
          control: true,
          shift: true,
        ): const _P5WorkspaceIntent(
          P5WorkspaceId.verificationCenter,
        ),
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            const _P5LaunchComposerIntent(),
        const SingleActivator(LogicalKeyboardKey.enter, meta: true):
            const _P5LaunchComposerIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _P5BackIntent: CallbackAction<_P5BackIntent>(
            onInvoke: (_) {
              controller.back();
              return null;
            },
          ),
          _P5ForwardIntent: CallbackAction<_P5ForwardIntent>(
            onInvoke: (_) {
              controller.forward();
              return null;
            },
          ),
          _P5WorkspaceIntent: CallbackAction<_P5WorkspaceIntent>(
            onInvoke: (intent) {
              controller.selectWorkspace(intent.workspace);
              return null;
            },
          ),
          _P5LaunchComposerIntent: CallbackAction<_P5LaunchComposerIntent>(
            onInvoke: (_) {
              if (controller.state.workspace == P5WorkspaceId.homeChat) {
                controller.launchComposer();
              }
              return null;
            },
          ),
        },
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => _buildShell(context),
          ),
        ),
      ),
    );
  }

  Widget _buildShell(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width <
        P5ShellLayoutState.minimumThreePaneWidth;
    final state = controller.state;
    final accessibilityCompact =
        MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return Scaffold(
      drawer: compact
          ? Drawer(
              child: SafeArea(
                child: _navigation(context, closeDrawerAfterSelection: true),
              ),
            )
          : null,
      endDrawer: compact
          ? Drawer(
              key: const Key('p5-right-inspector'),
              child: _buildP5Inspector(context, state),
            )
          : null,
      appBar: AppBar(
        titleSpacing: compact ? 0 : 20,
        toolbarHeight: accessibilityCompact ? 72 : null,
        title: accessibilityCompact
            ? Text(
                state.workspace.label,
                key: const Key('workspace-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    state.workspace.label,
                    key: const Key('workspace-title'),
                  ),
                  Text(
                    widget.ownerMode == null &&
                            widget.browserSessionStarter == null
                        ? 'P5 presentation prototype — runtime not bound'
                        : 'Experience workspace — live P2/P3 runtime integration',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
        actions: <Widget>[
          if (accessibilityCompact)
            PopupMenuButton<String>(
              key: const Key('p5-history-menu'),
              tooltip: 'Navigation history',
              icon: const Icon(Icons.history),
              onSelected: (value) {
                if (value == 'back') controller.back();
                if (value == 'forward') controller.forward();
              },
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'back',
                  enabled: controller.canGoBack,
                  child: const Text('Back'),
                ),
                PopupMenuItem<String>(
                  value: 'forward',
                  enabled: controller.canGoForward,
                  child: const Text('Forward'),
                ),
              ],
            )
          else ...<Widget>[
            IconButton(
              key: const Key('history-back'),
              tooltip: 'Back (Escape or Alt+Left)',
              onPressed: controller.canGoBack ? controller.back : null,
              icon: const Icon(Icons.arrow_back),
            ),
            IconButton(
              key: const Key('history-forward'),
              tooltip: 'Forward (Alt+Right)',
              onPressed: controller.canGoForward ? controller.forward : null,
              icon: const Icon(Icons.arrow_forward),
            ),
          ],
          Builder(
            builder: (buttonContext) => IconButton(
              key: const Key('p5-inspector-toggle'),
              tooltip: compact
                  ? 'Open inspector'
                  : controller.shellLayout.inspectorOpen
                  ? 'Hide inspector'
                  : 'Show inspector',
              onPressed: compact
                  ? () => Scaffold.of(buttonContext).openEndDrawer()
                  : () => _updateP5ShellLayout(
                      controller.shellLayout.copyWith(
                        inspectorOpen: !controller.shellLayout.inspectorOpen,
                      ),
                    ),
              icon: const Icon(Icons.tune_outlined),
            ),
          ),
          IconButton(
            key: const Key('p5-activity-toggle'),
            tooltip: controller.shellLayout.activityDrawerOpen
                ? 'Collapse activity drawer'
                : 'Expand activity drawer',
            onPressed: () => _updateP5ShellLayout(
              controller.shellLayout.copyWith(
                activityDrawerOpen: !controller.shellLayout.activityDrawerOpen,
              ),
            ),
            icon: const Icon(Icons.timeline_outlined),
          ),
          if (!compact && !accessibilityCompact) _experienceSelector(context),
          if (!accessibilityCompact) const SizedBox(width: 8),
          Semantics(
            liveRegion: true,
            label: 'Owner Mode status: $_liveOwnerLabel.',
            child: accessibilityCompact
                ? IconButton(
                    key: const Key('global-owner-status'),
                    tooltip: 'Owner Mode: $_liveOwnerLabel',
                    onPressed: widget.onOpenOwnerMode,
                    icon: const Icon(Icons.admin_panel_settings_outlined),
                  )
                : _StatusChip(
                    key: const Key('global-owner-status'),
                    label: 'Owner: $_liveOwnerLabel',
                    icon: Icons.admin_panel_settings_outlined,
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildP5ThreePaneBody(context, compact: compact, state: state),
    );
  }

  Widget _experienceSelector(BuildContext context) {
    return Semantics(
      label: 'Experience level. Presentation only.',
      child: DropdownButtonHideUnderline(
        child: DropdownButton<P5ExperienceLevel>(
          key: const Key('experience-level-selector'),
          value: controller.state.experienceLevel,
          items: P5ExperienceLevel.values
              .map(
                (level) => DropdownMenuItem<P5ExperienceLevel>(
                  value: level,
                  child: Text(level.label),
                ),
              )
              .toList(growable: false),
          onChanged: (level) {
            if (level != null) {
              controller.changeExperienceLevel(level);
            }
          },
        ),
      ),
    );
  }

  Widget _navigation(
    BuildContext context, {
    bool closeDrawerAfterSelection = false,
  }) {
    final state = controller.state;
    final items = controller.visibleWorkspaces;
    return ListView(
      key: const Key('global-navigation'),
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Kristin', style: Theme.of(context).textTheme.headlineSmall),
              Text('${state.experienceLevel.label} presentation'),
            ],
          ),
        ),
        for (var index = 0; index < items.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Semantics(
              button: true,
              selected: items[index].id == state.workspace,
              label:
                  '${items[index].id.label} workspace, shortcut Alt+${_shortcutFor(items[index].id)}',
              child: ListTile(
                key: Key('workspace-nav-${items[index].id.name}'),
                selected: items[index].id == state.workspace,
                leading: Icon(_workspaceIcon(items[index].id)),
                title: Text(items[index].id.label),
                subtitle: state.experienceLevel == P5ExperienceLevel.developer
                    ? Text(items[index].description, maxLines: 2)
                    : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: () {
                  controller.selectWorkspace(items[index].id);
                  if (closeDrawerAfterSelection) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
          ),
        const Divider(),
        const ListTile(
          dense: true,
          leading: Icon(Icons.keyboard_alt_outlined),
          title: Text('Keyboard'),
          subtitle: Text('Alt+1…9 workspaces • Escape back'),
        ),
        const ListTile(
          dense: true,
          leading: Icon(Icons.shield_outlined),
          title: Text('Authority unchanged'),
          subtitle: Text('Experience level controls presentation only.'),
        ),
      ],
    );
  }

  Widget _contextBar(BuildContext context) {
    final state = controller.state;
    final project = P5PrototypeFixtures.projects
        .where((item) => item.id == state.selectedProjectId)
        .firstOrNull;
    final run = P5PrototypeFixtures.runs
        .where((item) => item.id == state.selectedRunId)
        .firstOrNull;
    return Semantics(
      liveRegion: true,
      label: <String>[
        'Selected project: ${project?.name ?? 'none'}',
        'Selected run: ${run?.title ?? state.selectedRunId ?? 'none'}',
        'Run state: ${state.runState.label}',
      ].join('. '),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              _StatusChip(
                key: const Key('selected-project-chip'),
                label: project?.name ?? 'No project',
                icon: Icons.folder_outlined,
              ),
              _StatusChip(
                key: const Key('selected-run-chip'),
                label: run?.title ?? state.selectedRunId ?? 'No run',
                icon: Icons.play_circle_outline,
              ),
              _StatusChip(
                key: const Key('run-state-chip'),
                label: state.runState.label,
                icon: Icons.timeline_outlined,
              ),
              _StatusChip(
                label: widget.browserSessionStarter == null
                    ? 'Local in-memory fixtures'
                    : 'Live ProductRuntime',
                icon: widget.browserSessionStarter == null
                    ? Icons.memory_outlined
                    : Icons.hub_outlined,
              ),
              if (state.recoveryMessage != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Text(
                    state.recoveryMessage!,
                    key: const Key('recovery-message'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _workspace(BuildContext context, P5WorkspaceId workspace) {
    return switch (workspace) {
      P5WorkspaceId.homeChat => _homeWorkspace(context),
      P5WorkspaceId.projects => _projectsWorkspace(context),
      P5WorkspaceId.runsActivity => _runsWorkspace(context),
      P5WorkspaceId.verificationCenter => _verificationWorkspace(context),
      P5WorkspaceId.evidence => _evidenceWorkspace(context),
      P5WorkspaceId.ownerMode => _ownerModeWorkspace(context),
      P5WorkspaceId.modelsProviders => _modelsWorkspace(context),
      P5WorkspaceId.capabilitiesIntegrations => _capabilitiesWorkspace(context),
      P5WorkspaceId.settingsDiagnostics => _settingsWorkspace(context),
      P5WorkspaceId.webStudio => _webStudioWorkspace(context),
      P5WorkspaceId.searchResearch => _futureCapabilityWorkspace(
        context,
        workspace,
      ),
      P5WorkspaceId.nativeAutomation => _futureCapabilityWorkspace(
        context,
        workspace,
      ),
      P5WorkspaceId.devices => _futureCapabilityWorkspace(context, workspace),
    };
  }
}
