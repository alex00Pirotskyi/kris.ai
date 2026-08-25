import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'api_server.dart';
import 'application_runtime_provisioner.dart';
import 'chat_studio.dart';
import 'p2_product_runtime_bootstrap.dart';
import 'p5_command_palette.dart';
import 'p5_design_tokens.dart';
import 'p5_global_autonomy.dart';
import 'p5_information_architecture/p5_controller.dart';
import 'p5_information_architecture/p5_models.dart';
import 'p5_information_architecture/p5_prototype.dart';
import 'product_runtime.dart';
import 'product_runtime_provisioning.dart';
import 'ui.dart' show P5ApplicationShellLayoutPersistence;

class ProvisioningKristinApp extends StatefulWidget {
  const ProvisioningKristinApp({super.key, required this.runtime});

  final ProductRuntime runtime;

  @override
  State<ProvisioningKristinApp> createState() => _ProvisioningKristinAppState();
}

class _ProvisioningKristinAppState extends State<ProvisioningKristinApp>
    with WidgetsBindingObserver {
  late final GovernedApiServer api = GovernedApiServer(widget.runtime);
  String? startupError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.runtime.settings.apiEnabled) {
      unawaited(
        api.start().catchError((Object failure) {
          if (!mounted) return;
          setState(() => startupError = '$failure');
        }),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(api.stop());
    unawaited(() async {
      await widget.runtime.closeRuntimeProvisioning();
      await widget.runtime.close();
    }());
    super.dispose();
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    return MaterialApp(
      title: 'Kristin Local Agent',
      debugShowCheckedModeBanner: false,
      theme: _runtimeTheme(
        Brightness.light,
        reducedMotion: reducedMotion,
      ),
      darkTheme: _runtimeTheme(
        Brightness.dark,
        reducedMotion: reducedMotion,
      ),
      highContrastTheme: _runtimeTheme(
        Brightness.light,
        highContrast: true,
        reducedMotion: reducedMotion,
      ),
      highContrastDarkTheme: _runtimeTheme(
        Brightness.dark,
        highContrast: true,
        reducedMotion: reducedMotion,
      ),
      themeMode: ThemeMode.system,
      themeAnimationDuration:
          P5DesignSystem.themeTransitionDuration(reducedMotion),
      themeAnimationCurve: Curves.easeOutCubic,
      home: _ProvisioningMainShell(
        runtime: widget.runtime,
        chat: ChatStudio(
          runtime: widget.runtime,
          api: api,
          startupError: startupError,
        ),
      ),
    );
  }
}

class _ProvisioningMainShell extends StatefulWidget {
  const _ProvisioningMainShell({
    required this.runtime,
    required this.chat,
  });

  final ProductRuntime runtime;
  final Widget chat;

  @override
  State<_ProvisioningMainShell> createState() => _ProvisioningMainShellState();
}

class _ProvisioningMainShellState extends State<_ProvisioningMainShell> {
  var _index = 0;
  late final P5InformationArchitectureController _experienceController;
  late P5GlobalAutonomyBinding _autonomyBinding;
  late P2ProductRuntimeOwnerModeHandle _ownerMode;
  StreamSubscription<ApplicationRuntimeProvisioningProgress>? _progress;

  bool _ownerPreparing = false;
  String _ownerPreparationMessage = 'Preparing local runtime...';
  double? _ownerProgress;
  String? _ownerFailure;
  String? _ownerDiagnostic;

  bool _webPreparing = false;
  bool _webReady = false;
  String _webPreparationMessage = 'Preparing browser runtime...';
  double? _webProgress;
  String? _webFailure;
  String? _webDiagnostic;

  @override
  void initState() {
    super.initState();
    _ownerMode = widget.runtime.provisionedOwnerMode;
    _webReady = widget.runtime.browserRuntimePrepared;
    _experienceController = P5InformationArchitectureController();
    _experienceController.addListener(_handleExperienceChange);
    _autonomyBinding = P5GlobalAutonomyController.product(
      runtime: widget.runtime,
      ownerMode: _ownerMode,
    );
    _progress = widget.runtime.runtimeProvisioningProgress.listen(
      _handleProvisioningProgress,
    );
  }

  @override
  void dispose() {
    _progress?.cancel();
    _experienceController.removeListener(_handleExperienceChange);
    _experienceController.dispose();
    _autonomyBinding.dispose();
    super.dispose();
  }

  void _handleExperienceChange() {
    if (_experienceController.state.workspace == P5WorkspaceId.webStudio &&
        !_webReady &&
        !_webPreparing &&
        _webFailure == null) {
      unawaited(_prepareWebStudio());
    }
  }

  void _handleProvisioningProgress(
    ApplicationRuntimeProvisioningProgress progress,
  ) {
    if (!mounted) return;
    setState(() {
      if (progress.kind == ApplicationRuntimeKind.p2) {
        _ownerPreparationMessage = progress.message;
        _ownerProgress = progress.fraction;
        if (progress.diagnosticCode != null) {
          _ownerDiagnostic = progress.diagnosticCode;
        }
      } else {
        _webPreparationMessage = progress.message;
        _webProgress = progress.fraction;
        if (progress.diagnosticCode != null) {
          _webDiagnostic = progress.diagnosticCode;
        }
      }
    });
  }

  Future<void> _openCommandPalette() async {
    final command = await showDialog<P5CommandDefinition>(
      context: context,
      builder: (dialogContext) => P5CommandPaletteDialog(
        commands: P5CommandCatalog.primary,
        onSelected: (selected) => Navigator.of(dialogContext).pop(selected),
      ),
    );
    if (!mounted || command == null) return;
    _invokeCommand(command);
  }

  void _invokeCommand(P5CommandDefinition command) {
    switch (command.actionKind) {
      case P5CommandActionKind.shellDestination:
        _selectDestination(command.shellIndex!);
      case P5CommandActionKind.experienceWorkspace:
        _selectDestination(1);
        _experienceController.selectWorkspace(command.workspace!);
      case P5CommandActionKind.launchExperienceTask:
        _selectDestination(1);
        _experienceController.selectWorkspace(P5WorkspaceId.homeChat);
        _experienceController.launchComposer();
    }
  }

  void _selectDestination(int value) {
    if (value != _index && mounted) {
      setState(() => _index = value);
    }
    if (value == 2 && !_ownerMode.available && !_ownerPreparing) {
      unawaited(_prepareOwnerMode());
    }
  }

  Future<void> _prepareOwnerMode({bool repair = false}) async {
    if (_ownerPreparing) return;
    setState(() {
      _ownerPreparing = true;
      _ownerFailure = null;
      _ownerDiagnostic = null;
      _ownerProgress = null;
      _ownerPreparationMessage = 'Preparing local runtime...';
    });
    try {
      final owner = await widget.runtime.ensureOwnerModeReady(repair: repair);
      if (!mounted) return;
      final previousBinding = _autonomyBinding;
      setState(() {
        _ownerMode = owner;
        _ownerPreparing = false;
        _ownerProgress = 1;
        _ownerPreparationMessage = 'Owner Mode ready.';
        _autonomyBinding = P5GlobalAutonomyController.product(
          runtime: widget.runtime,
          ownerMode: owner,
        );
      });
      previousBinding.dispose();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _ownerPreparing = false;
        _ownerFailure = "Owner Mode couldn't be prepared.";
        _ownerDiagnostic = _diagnosticCode(error);
      });
    }
  }

  Future<void> _prepareWebStudio({bool repair = false}) async {
    if (_webPreparing) return;
    setState(() {
      _webPreparing = true;
      _webFailure = null;
      _webDiagnostic = null;
      _webProgress = null;
      _webPreparationMessage = 'Preparing browser runtime...';
    });
    try {
      await widget.runtime.ensureBrowserRuntimeReady(repair: repair);
      if (!mounted) return;
      setState(() {
        _webPreparing = false;
        _webReady = true;
        _webProgress = 1;
        _webPreparationMessage = 'Web Studio ready.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _webPreparing = false;
        _webReady = false;
        _webFailure = "Web Studio couldn't be prepared.";
        _webDiagnostic = _diagnosticCode(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownerAvailable = _ownerMode.available;
    final qaPreview = _ownerMode.runtimeProvenance['qaPreview'] == true;
    final pages = <Widget>[
      widget.chat,
      _experiencePage(),
      _ownerPage(),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final workspaceBody = wide
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
                      _ownerPreparing
                          ? Icons.hourglass_top
                          : ownerAvailable
                              ? Icons.admin_panel_settings_outlined
                              : Icons.admin_panel_settings_outlined,
                    ),
                    selectedIcon: Icon(
                      _ownerPreparing
                          ? Icons.hourglass_top
                          : Icons.admin_panel_settings,
                    ),
                    label: const Text('Owner Mode'),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: IndexedStack(index: _index, children: pages)),
            ],
          )
        : IndexedStack(index: _index, children: pages);
    final shell = Scaffold(
      body: Column(
        children: <Widget>[
          P5GlobalAutonomyBar(
            binding: _autonomyBinding,
            onOpenCommands: _openCommandPalette,
          ),
          Expanded(child: workspaceBody),
        ],
      ),
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
                    _ownerPreparing
                        ? Icons.hourglass_top
                        : Icons.admin_panel_settings_outlined,
                  ),
                  selectedIcon: Icon(
                    _ownerPreparing
                        ? Icons.hourglass_top
                        : Icons.admin_panel_settings,
                  ),
                  label: 'Owner Mode',
                ),
              ],
            ),
    );
    final commandShell = P5CommandPaletteShortcutScope(
      onOpenPalette: _openCommandPalette,
      onSelectShellDestination: _selectDestination,
      child: shell,
    );
    if (!qaPreview) return commandShell;
    return Banner(
      message: 'OWNER-RISK QA — SECURITY EVIDENCE WAIVED',
      location: BannerLocation.topEnd,
      color: Colors.deepOrange,
      child: commandShell,
    );
  }

  Widget _ownerPage() {
    if (_ownerPreparing) {
      return _RuntimePreparingView(
        key: const ValueKey<String>('owner-runtime-preparing'),
        title: 'Preparing Owner Mode',
        message: _ownerPreparationMessage,
        progress: _ownerProgress,
        icon: Icons.admin_panel_settings_outlined,
      );
    }
    if (_ownerMode.available) {
      return _ownerMode.buildWorkspace(
        key: const ValueKey<String>('kristin-owner-mode-workspace'),
      );
    }
    if (_ownerFailure != null) {
      return _RuntimeFailureView(
        key: const ValueKey<String>('owner-runtime-failure'),
        title: _ownerFailure!,
        onRetry: () => _prepareOwnerMode(repair: true),
        diagnosticCode: _ownerDiagnostic,
      );
    }
    return _RuntimePreparingView(
      key: const ValueKey<String>('owner-runtime-awaiting-request'),
      title: 'Owner Mode',
      message: 'Open Owner Mode to prepare its local runtime.',
      progress: null,
      icon: Icons.admin_panel_settings_outlined,
    );
  }

  Widget _experiencePage() {
    final prototype = P5InformationArchitecturePrototype(
      controller: _experienceController,
      ownerMode: _ownerMode,
      globalAutonomy: _autonomyBinding,
      browserRuntimeAvailable: _webReady || _webPreparing,
      browserRuntimeStatusCode: _webReady
          ? 'p3_browser_runtime_available'
          : _webPreparing
              ? 'p3_runtime_preparing'
              : _webFailure == null
                  ? 'p3_runtime_provisionable'
                  : 'p3_runtime_prepare_failed',
      browserRuntimeProvenance: <String, Object?>{
        ...widget.runtime.p3BrowserRuntime.provenance,
        'provisionable': true,
        'prepared': _webReady,
        'preparing': _webPreparing,
        if (_webDiagnostic != null) 'diagnosticCode': _webDiagnostic,
      },
      layoutPersistence: P5ApplicationShellLayoutPersistence(
        applicationDataRoot: widget.runtime.directories.root,
      ),
      browserSessionStarter: () =>
          widget.runtime.startProvisionedBrowserSessions(
        stateDirectory: Directory(
          '${widget.runtime.directories.cache.path}${Platform.pathSeparator}'
          'p5-web-studio-browser',
        ),
        requestTimeout: const Duration(seconds: 60),
      ),
      onOpenOwnerMode: () => _selectDestination(2),
    );
    if (_experienceController.state.workspace != P5WorkspaceId.webStudio ||
        (!_webPreparing && _webFailure == null)) {
      return prototype;
    }
    return Stack(
      children: <Widget>[
        Positioned.fill(child: prototype),
        Align(
          alignment: Alignment.topCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: _webPreparing
                  ? _RuntimeStatusBanner(
                      key: const ValueKey<String>('web-runtime-preparing'),
                      title: 'Preparing Web Studio...',
                      message: _webPreparationMessage,
                      progress: _webProgress,
                    )
                  : _RuntimeStatusBanner.failure(
                      key: const ValueKey<String>('web-runtime-failure'),
                      title: _webFailure!,
                      diagnosticCode: _webDiagnostic,
                      onRetry: () => _prepareWebStudio(repair: true),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  static String _diagnosticCode(Object error) {
    final value = error is StateError ? error.message.toString() : '$error';
    final normalized = value
        .replaceAll(RegExp(r'[^A-Za-z0-9_.:-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (normalized.isEmpty) return 'runtime_provisioning_failed';
    return normalized.length <= 180 ? normalized : normalized.substring(0, 180);
  }
}

class _RuntimePreparingView extends StatelessWidget {
  const _RuntimePreparingView({
    super.key,
    required this.title,
    required this.message,
    required this.progress,
    required this.icon,
  });

  final String title;
  final String message;
  final double? progress;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 54),
                const SizedBox(height: 22),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 22),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 10),
                Text(
                  'Kristin is preparing the application-owned runtime. No manual install is required.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RuntimeFailureView extends StatelessWidget {
  const _RuntimeFailureView({
    super.key,
    required this.title,
    required this.onRetry,
    required this.diagnosticCode,
  });

  final String title;
  final VoidCallback onRetry;
  final String? diagnosticCode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Owner Mode')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.error_outline, size: 52),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Kristin could not safely finish preparing the local runtime.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const ValueKey<String>('owner-runtime-retry'),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
                if (diagnosticCode != null) ...<Widget>[
                  const SizedBox(height: 14),
                  ExpansionTile(
                    key: const ValueKey<String>('owner-runtime-diagnostics'),
                    title: const Text('Diagnostics'),
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: SelectableText(diagnosticCode!),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RuntimeStatusBanner extends StatelessWidget {
  const _RuntimeStatusBanner({
    super.key,
    required this.title,
    required this.message,
    required this.progress,
  })  : diagnosticCode = null,
        onRetry = null,
        failure = false;

  const _RuntimeStatusBanner.failure({
    super.key,
    required this.title,
    required this.diagnosticCode,
    required this.onRetry,
  })  : message =
            'Kristin could not safely finish preparing the browser runtime.',
        progress = null,
        failure = true;

  final String title;
  final String message;
  final double? progress;
  final String? diagnosticCode;
  final VoidCallback? onRetry;
  final bool failure;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      color: failure ? colors.errorContainer : colors.surfaceContainerHighest,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (failure)
                    const Icon(Icons.error_outline)
                  else
                    const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
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
                        Text(message),
                      ],
                    ),
                  ),
                  if (onRetry != null)
                    FilledButton.tonalIcon(
                      key: const ValueKey<String>('web-runtime-retry'),
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                ],
              ),
              if (!failure) ...<Widget>[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: progress),
              ],
              if (diagnosticCode != null) ...<Widget>[
                const SizedBox(height: 8),
                ExpansionTile(
                  key: const ValueKey<String>('web-runtime-diagnostics'),
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Diagnostics'),
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(diagnosticCode!),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

ThemeData _runtimeTheme(
  Brightness brightness, {
  bool highContrast = false,
  bool reducedMotion = false,
}) {
  return P5DesignSystem.theme(
    brightness: brightness,
    highContrast: highContrast,
    reducedMotion: reducedMotion,
  );
}
