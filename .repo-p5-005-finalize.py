from pathlib import Path

ROOT = Path('.')


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding='utf-8', newline='\n')


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}')
    write(path, text.replace(old, new, 1))


global_source = r'''import 'dart:async';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'p2_product_runtime_bootstrap.dart';
import 'product_runtime.dart';

const Set<RunState> _p5ActiveRunStates = <RunState>{
  RunState.awaitingApproval,
  RunState.queued,
  RunState.running,
  RunState.paused,
  RunState.cancelling,
};

const Set<RunState> _p5StoppableRunStates = <RunState>{
  RunState.awaitingApproval,
  RunState.queued,
  RunState.running,
  RunState.paused,
};

class P5GlobalAutonomyRunSession {
  const P5GlobalAutonomyRunSession({
    required this.id,
    required this.state,
    required this.modelLabel,
    required this.networkRequested,
  });

  final String id;
  final RunState state;
  final String modelLabel;
  final bool networkRequested;
}

abstract interface class P5GlobalAutonomyRunPort {
  Future<List<P5GlobalAutonomyRunSession>> listSessions();
  Future<void> pause(String runId);
  Future<void> cancel(String runId);
}

class P5ProductRuntimeGlobalAutonomyRunPort
    implements P5GlobalAutonomyRunPort {
  P5ProductRuntimeGlobalAutonomyRunPort(this._runtime);

  final ProductRuntime _runtime;

  @override
  Future<List<P5GlobalAutonomyRunSession>> listSessions() async {
    final runs = await _runtime.listRuns(limit: 100);
    return runs
        .map(
          (run) => P5GlobalAutonomyRunSession(
            id: run.id,
            state: run.state,
            modelLabel: run.command.model.exactId,
            networkRequested: run.command.contract.requiredPermissions.any(
              (scope) =>
                  scope == PermissionScope.networkResearch ||
                  scope == PermissionScope.networkPackages,
            ),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> pause(String runId) => _runtime.pause(runId);

  @override
  Future<void> cancel(String runId) => _runtime.cancel(runId);
}

class P5GlobalAutonomyOwnerSnapshot {
  const P5GlobalAutonomyOwnerSnapshot({
    required this.profileId,
    required this.ownerAvailable,
    required this.ownerEnabled,
    required this.terminalCount,
    required this.supervisedProcessTreeCount,
  });

  final String profileId;
  final bool ownerAvailable;
  final bool ownerEnabled;
  final int terminalCount;
  final int supervisedProcessTreeCount;
}

abstract interface class P5GlobalAutonomyOwnerPort {
  P5GlobalAutonomyOwnerSnapshot snapshot();
  Future<void> emergencyKillAll();
}

class P5OwnerModeGlobalAutonomyPort implements P5GlobalAutonomyOwnerPort {
  P5OwnerModeGlobalAutonomyPort(this._handle);

  final P2ProductRuntimeOwnerModeHandle _handle;

  @override
  P5GlobalAutonomyOwnerSnapshot snapshot() {
    final runtime = _handle.runtime;
    if (runtime == null) {
      return const P5GlobalAutonomyOwnerSnapshot(
        profileId: 'chat',
        ownerAvailable: false,
        ownerEnabled: false,
        terminalCount: 0,
        supervisedProcessTreeCount: 0,
      );
    }
    final settings = runtime.controller.current;
    final supervision = runtime.supervisionSnapshot();
    final rawWatchdogs = supervision['watchdogIds'];
    return P5GlobalAutonomyOwnerSnapshot(
      profileId: settings.accessProfileId,
      ownerAvailable: true,
      ownerEnabled: settings.enabled,
      terminalCount: runtime.terminalModel.tabs.length,
      supervisedProcessTreeCount:
          rawWatchdogs is List ? rawWatchdogs.length : 0,
    );
  }

  @override
  Future<void> emergencyKillAll() async {
    final runtime = _handle.runtime;
    if (runtime == null) {
      throw StateError('owner_runtime_unavailable');
    }
    await runtime.emergencyPauseAndKillAll();
  }
}

class P5GlobalAutonomySnapshot {
  const P5GlobalAutonomySnapshot({
    required this.profileLabel,
    required this.modelLabel,
    required this.activeRunCount,
    required this.ownerTerminalCount,
    required this.browserSessionCount,
    required this.supervisedProcessTreeCount,
    required this.takeoverLabel,
    required this.networkLabel,
    required this.canPause,
    required this.canStop,
    required this.canEmergencyKill,
  });

  factory P5GlobalAutonomySnapshot.initial() =>
      const P5GlobalAutonomySnapshot(
        profileLabel: 'chat',
        modelLabel: 'No active model',
        activeRunCount: 0,
        ownerTerminalCount: 0,
        browserSessionCount: 0,
        supervisedProcessTreeCount: 0,
        takeoverLabel: 'Not globally bound',
        networkLabel: 'Not requested',
        canPause: false,
        canStop: false,
        canEmergencyKill: false,
      );

  final String profileLabel;
  final String modelLabel;
  final int activeRunCount;
  final int ownerTerminalCount;
  final int browserSessionCount;
  final int supervisedProcessTreeCount;
  final String takeoverLabel;
  final String networkLabel;
  final bool canPause;
  final bool canStop;
  final bool canEmergencyKill;

  int get activeSessionCount =>
      activeRunCount + ownerTerminalCount + browserSessionCount;

  String get sessionBreakdown =>
      '$activeRunCount runs, $ownerTerminalCount terminals, '
      '$browserSessionCount browser sessions';
}

abstract class P5GlobalAutonomyBinding extends ChangeNotifier {
  P5GlobalAutonomySnapshot get snapshot;
  Future<void> refresh();
  Future<void> pauseActiveRuns();
  Future<void> stopActiveRuns();
  Future<void> emergencyKill();
  void updateBrowserSessionCount(int count);
  void registerBrowserEmergencyStop(Future<void> Function()? stop);
}

class P5GlobalAutonomyController extends P5GlobalAutonomyBinding {
  P5GlobalAutonomyController({
    required P5GlobalAutonomyOwnerPort ownerPort,
    P5GlobalAutonomyRunPort? runPort,
    Stream<Object?>? events,
    Duration? refreshInterval = const Duration(seconds: 1),
  })  : _ownerPort = ownerPort,
        _runPort = runPort {
    if (events != null) {
      _events = events.listen((_) => unawaited(refresh()));
    }
    if (refreshInterval != null) {
      _refreshTimer = Timer.periodic(
        refreshInterval,
        (_) => unawaited(refresh()),
      );
    }
    unawaited(refresh());
  }

  factory P5GlobalAutonomyController.product({
    ProductRuntime? runtime,
    required P2ProductRuntimeOwnerModeHandle ownerMode,
  }) =>
      P5GlobalAutonomyController(
        runPort: runtime == null
            ? null
            : P5ProductRuntimeGlobalAutonomyRunPort(runtime),
        ownerPort: P5OwnerModeGlobalAutonomyPort(ownerMode),
        events: runtime?.eventStream,
      );

  final P5GlobalAutonomyRunPort? _runPort;
  final P5GlobalAutonomyOwnerPort _ownerPort;
  StreamSubscription<Object?>? _events;
  Timer? _refreshTimer;
  P5GlobalAutonomySnapshot _snapshot = P5GlobalAutonomySnapshot.initial();
  int _browserSessionCount = 0;
  Future<void> Function()? _browserEmergencyStop;
  bool _refreshing = false;
  bool _disposed = false;

  @override
  P5GlobalAutonomySnapshot get snapshot => _snapshot;

  @override
  Future<void> refresh() async {
    if (_disposed || _refreshing) return;
    _refreshing = true;
    try {
      final sessions = await _listRunSessions();
      final active = sessions
          .where((session) => _p5ActiveRunStates.contains(session.state))
          .toList(growable: false);
      final owner = _ownerPort.snapshot();
      final running = active.any((session) => session.state == RunState.running);
      final stoppable =
          active.any((session) => _p5StoppableRunStates.contains(session.state));
      final model = active.isEmpty ? null : active.first.modelLabel;
      final networkRequested = active.any((session) => session.networkRequested);
      final profile = owner.ownerEnabled
          ? owner.profileId
          : active.isNotEmpty
              ? 'project'
              : 'chat';
      final network = owner.ownerEnabled
          ? 'Owner policy'
          : networkRequested
              ? 'Granted to active task'
              : _browserSessionCount > 0
                  ? 'Browser runtime active'
                  : 'Not requested';
      if (_disposed) return;
      _snapshot = P5GlobalAutonomySnapshot(
        profileLabel: profile,
        modelLabel: model == null || model.isEmpty ? 'No active model' : model,
        activeRunCount: active.length,
        ownerTerminalCount: owner.terminalCount,
        browserSessionCount: _browserSessionCount,
        supervisedProcessTreeCount: owner.supervisedProcessTreeCount,
        takeoverLabel: 'Not globally bound',
        networkLabel: network,
        canPause: running,
        canStop: stoppable,
        canEmergencyKill: stoppable ||
            owner.supervisedProcessTreeCount > 0 ||
            (_browserSessionCount > 0 && _browserEmergencyStop != null),
      );
      notifyListeners();
    } finally {
      _refreshing = false;
    }
  }

  Future<List<P5GlobalAutonomyRunSession>> _listRunSessions() async =>
      await _runPort?.listSessions() ?? const <P5GlobalAutonomyRunSession>[];

  @override
  Future<void> pauseActiveRuns() async {
    final port = _runPort;
    if (port == null) throw StateError('run_runtime_unavailable');
    final running = (await port.listSessions())
        .where((session) => session.state == RunState.running)
        .toList(growable: false);
    if (running.isEmpty) throw StateError('no_running_runs');
    var failures = 0;
    for (final session in running) {
      try {
        await port.pause(session.id);
      } catch (_) {
        failures++;
      }
    }
    await refresh();
    if (failures > 0) throw StateError('global_pause_partial_failure:$failures');
  }

  @override
  Future<void> stopActiveRuns() async {
    final port = _runPort;
    if (port == null) throw StateError('run_runtime_unavailable');
    final stoppable = (await port.listSessions())
        .where((session) => _p5StoppableRunStates.contains(session.state))
        .toList(growable: false);
    if (stoppable.isEmpty) throw StateError('no_stoppable_runs');
    var failures = 0;
    for (final session in stoppable) {
      try {
        await port.cancel(session.id);
      } catch (_) {
        failures++;
      }
    }
    await refresh();
    if (failures > 0) throw StateError('global_stop_partial_failure:$failures');
  }

  @override
  Future<void> emergencyKill() async {
    final port = _runPort;
    final sessions = await _listRunSessions();
    final stoppable = sessions
        .where((session) => _p5StoppableRunStates.contains(session.state))
        .toList(growable: false);
    final owner = _ownerPort.snapshot();
    var attempted = false;
    var failures = 0;

    final browserStop = _browserEmergencyStop;
    if (_browserSessionCount > 0 && browserStop != null) {
      attempted = true;
      try {
        await browserStop();
        _browserSessionCount = 0;
      } catch (_) {
        failures++;
      }
    }

    if (port != null && stoppable.isNotEmpty) {
      attempted = true;
      for (final session in stoppable) {
        try {
          await port.cancel(session.id);
        } catch (_) {
          failures++;
        }
      }
    }

    if (owner.supervisedProcessTreeCount > 0) {
      attempted = true;
      try {
        await _ownerPort.emergencyKillAll();
      } catch (_) {
        failures++;
      }
    }

    if (!attempted) throw StateError('no_active_session_to_kill');
    await refresh();
    if (failures > 0) {
      throw StateError('global_emergency_partial_failure:$failures');
    }
  }

  @override
  void updateBrowserSessionCount(int count) {
    final bounded = count < 0 ? 0 : count;
    if (_browserSessionCount == bounded) return;
    _browserSessionCount = bounded;
    unawaited(refresh());
  }

  @override
  void registerBrowserEmergencyStop(Future<void> Function()? stop) {
    _browserEmergencyStop = stop;
    unawaited(refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    final events = _events;
    if (events != null) unawaited(events.cancel());
    _events = null;
    _browserEmergencyStop = null;
    super.dispose();
  }
}

class P5GlobalAutonomyBar extends StatefulWidget {
  const P5GlobalAutonomyBar({
    super.key,
    required this.binding,
  });

  final P5GlobalAutonomyBinding binding;

  @override
  State<P5GlobalAutonomyBar> createState() => _P5GlobalAutonomyBarState();
}

class _P5GlobalAutonomyBarState extends State<P5GlobalAutonomyBar> {
  bool _busy = false;
  String? _errorCode;

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _errorCode = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _errorCode = _safeActionCode(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _safeActionCode(Object error) {
    if (error is ProductException) return error.code;
    if (error is StateError) {
      final value = error.message.toString();
      if (RegExp(r'^[A-Za-z0-9_.:-]{1,96}$').hasMatch(value)) return value;
    }
    return 'global_autonomy_action_failed';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.binding,
      builder: (context, _) {
        final snapshot = widget.binding.snapshot;
        return Material(
          key: const Key('p5-global-autonomy-bar'),
          elevation: 1,
          child: Semantics(
            container: true,
            liveRegion: true,
            label: 'Global autonomy status. Profile ${snapshot.profileLabel}. '
                'Model ${snapshot.modelLabel}. ${snapshot.sessionBreakdown}. '
                'Takeover ${snapshot.takeoverLabel}. Network ${snapshot.networkLabel}.',
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: <Widget>[
                    _P5AutonomyStatusChip(
                      key: const Key('p5-global-profile'),
                      icon: Icons.shield_outlined,
                      label: 'Profile: ${snapshot.profileLabel}',
                    ),
                    _P5AutonomyStatusChip(
                      key: const Key('p5-global-model'),
                      icon: Icons.memory_outlined,
                      label: 'Model: ${snapshot.modelLabel}',
                    ),
                    Tooltip(
                      message: snapshot.sessionBreakdown,
                      child: _P5AutonomyStatusChip(
                        key: const Key('p5-global-sessions'),
                        icon: Icons.hub_outlined,
                        label: 'Sessions: ${snapshot.activeSessionCount}',
                      ),
                    ),
                    _P5AutonomyStatusChip(
                      key: const Key('p5-global-takeover'),
                      icon: Icons.pan_tool_outlined,
                      label: 'Takeover: ${snapshot.takeoverLabel}',
                    ),
                    _P5AutonomyStatusChip(
                      key: const Key('p5-global-network'),
                      icon: Icons.public_outlined,
                      label: 'Network: ${snapshot.networkLabel}',
                    ),
                    const SizedBox(width: 8),
                    Center(
                      child: FilledButton.tonalIcon(
                        key: const Key('p5-global-pause'),
                        onPressed: _busy || !snapshot.canPause
                            ? null
                            : () => _perform(widget.binding.pauseActiveRuns),
                        icon: const Icon(Icons.pause),
                        label: const Text('Pause'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Center(
                      child: OutlinedButton.icon(
                        key: const Key('p5-global-stop'),
                        onPressed: _busy || !snapshot.canStop
                            ? null
                            : () => _perform(widget.binding.stopActiveRuns),
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Center(
                      child: FilledButton.icon(
                        key: const Key('p5-global-kill'),
                        onPressed: _busy || !snapshot.canEmergencyKill
                            ? null
                            : () => _perform(widget.binding.emergencyKill),
                        icon: const Icon(Icons.emergency_outlined),
                        label: const Text('Emergency kill'),
                      ),
                    ),
                    if (_busy) ...<Widget>[
                      const SizedBox(width: 10),
                      const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ],
                    if (_errorCode != null) ...<Widget>[
                      const SizedBox(width: 10),
                      Center(
                        child: Text(
                          _errorCode!,
                          key: const Key('p5-global-action-error'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _P5AutonomyStatusChip extends StatelessWidget {
  const _P5AutonomyStatusChip({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Chip(
            avatar: Icon(icon, size: 16),
            label: Text(label),
          ),
        ),
      );
}
'''
write('lib/product/p5_global_autonomy.dart', global_source)

ui_path = 'lib/product/ui.dart'
replace_once(
    ui_path,
    "import 'p5_design_tokens.dart';\n",
    "import 'p5_design_tokens.dart';\nimport 'p5_global_autonomy.dart';\n",
)
replace_once(
    ui_path,
    '''    this.runtime,
    required this.ownerMode,
    required this.chat,
  });

  final ProductRuntime? runtime;
  final P2ProductRuntimeOwnerModeHandle ownerMode;
  final Widget chat;
''',
    '''    this.runtime,
    required this.ownerMode,
    required this.chat,
    this.autonomyBinding,
  });

  final ProductRuntime? runtime;
  final P2ProductRuntimeOwnerModeHandle ownerMode;
  final Widget chat;
  final P5GlobalAutonomyBinding? autonomyBinding;
''',
)
replace_once(
    ui_path,
    '''  var _index = 0;
  late final P5InformationArchitectureController _experienceController;
''',
    '''  var _index = 0;
  late final P5InformationArchitectureController _experienceController;
  late final P5GlobalAutonomyBinding _autonomyBinding;
  late final bool _ownsAutonomyBinding;
''',
)
replace_once(
    ui_path,
    '''  void initState() {
    super.initState();
    _experienceController = P5InformationArchitectureController();
  }

  @override
  void dispose() {
    _experienceController.dispose();
    super.dispose();
  }
''',
    '''  void initState() {
    super.initState();
    _experienceController = P5InformationArchitectureController();
    _ownsAutonomyBinding = widget.autonomyBinding == null;
    _autonomyBinding = widget.autonomyBinding ??
        P5GlobalAutonomyController.product(
          runtime: widget.runtime,
          ownerMode: widget.ownerMode,
        );
  }

  @override
  void dispose() {
    if (_ownsAutonomyBinding) _autonomyBinding.dispose();
    _experienceController.dispose();
    super.dispose();
  }
''',
)
replace_once(
    ui_path,
    '''        controller: _experienceController,
        ownerMode: widget.ownerMode,
''',
    '''        controller: _experienceController,
        ownerMode: widget.ownerMode,
        globalAutonomy: _autonomyBinding,
''',
)
replace_once(
    ui_path,
    '''    final shell = Scaffold(
      body: wide
''',
    '''    final workspaceBody = wide
''',
)
replace_once(
    ui_path,
    '''          : IndexedStack(index: _index, children: pages),
      bottomNavigationBar: wide
''',
    '''          : IndexedStack(index: _index, children: pages);
    final shell = Scaffold(
      body: Column(
        children: <Widget>[
          P5GlobalAutonomyBar(binding: _autonomyBinding),
          Expanded(child: workspaceBody),
        ],
      ),
      bottomNavigationBar: wide
''',
)

prototype_path = 'lib/product/p5_information_architecture/p5_prototype.dart'
replace_once(
    prototype_path,
    "import '../p2_product_runtime_bootstrap.dart';\n",
    "import '../p2_product_runtime_bootstrap.dart';\nimport '../p5_global_autonomy.dart';\n",
)
replace_once(
    prototype_path,
    '''    this.layoutPersistence,
    this.onOpenOwnerMode,
  });
''',
    '''    this.layoutPersistence,
    this.globalAutonomy,
    this.onOpenOwnerMode,
  });
''',
)
replace_once(
    prototype_path,
    '''  final P5ShellLayoutPersistence? layoutPersistence;
  final VoidCallback? onOpenOwnerMode;
''',
    '''  final P5ShellLayoutPersistence? layoutPersistence;
  final P5GlobalAutonomyBinding? globalAutonomy;
  final VoidCallback? onOpenOwnerMode;
''',
)
replace_once(
    prototype_path,
    '''  void initState() {
    super.initState();
    unawaited(_initializeP5ShellLayout());
  }

  @override
  void dispose() {
    _shellLayoutSaveDebounce?.cancel();
    unawaited(_webBrowser?.close());
''',
    '''  void initState() {
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
''',
)

support_path = 'lib/product/p5_information_architecture/p5_support_workspaces.dart'
replace_once(
    support_path,
    '''  Future<void> _stopWebBrowser() =>
      _runWeb('browser service stopped', () async {
        final process = _webBrowser;
        _webBrowser = null;
        if (process != null) await process.close();
        if (!mounted) return;
        mutatePresentation(() {
          _webSessions = <P3BrowserSessionInfo>[];
          _webPages = <P3BrowserPageInfo>[];
          _webSelectedSessionId = null;
          _webSelectedPageId = null;
          _webObservation = null;
          _webDownloads = <P3BrowserDownloadReceipt>[];
          _webUploads = <P3BrowserUploadReceipt>[];
        });
      });
''',
    '''  Future<void> _stopWebBrowser() =>
      _runWeb('browser service stopped', _p5EmergencyStopBrowser);
''',
)
replace_once(
    support_path,
    '''      _webDownloads = downloads;
      _webUploads = uploads;
    });
  }

  Future<void> _openWebSession()''',
    '''      _webDownloads = downloads;
      _webUploads = uploads;
    });
    widget.globalAutonomy?.updateBrowserSessionCount(sessions.length);
  }

  Future<void> _openWebSession()''',
)

main_shell_test = r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_product_runtime_bootstrap.dart';
import 'package:kristin_local_agent/product/p5_global_autonomy.dart';
import 'package:kristin_local_agent/product/ui.dart';

class _ShellAutonomyBinding extends P5GlobalAutonomyBinding {
  @override
  P5GlobalAutonomySnapshot snapshot = const P5GlobalAutonomySnapshot(
    profileLabel: 'project',
    modelLabel: 'local/test-model@sha256',
    activeRunCount: 1,
    ownerTerminalCount: 0,
    browserSessionCount: 0,
    supervisedProcessTreeCount: 0,
    takeoverLabel: 'Not globally bound',
    networkLabel: 'Not requested',
    canPause: true,
    canStop: true,
    canEmergencyKill: true,
  );

  @override
  Future<void> emergencyKill() async {}

  @override
  Future<void> pauseActiveRuns() async {}

  @override
  Future<void> refresh() async {}

  @override
  void registerBrowserEmergencyStop(Future<void> Function()? stop) {}

  @override
  Future<void> stopActiveRuns() async {}

  @override
  void updateBrowserSessionCount(int count) {}
}

void main() {
  testWidgets('main shell exposes persistent autonomy, chat, experience, and Owner Mode',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final ownerMode = P2ProductRuntimeOwnerModeHandle.blocked(
      'Bad state: merged_p1a_service_unavailable',
    );
    final autonomy = _ShellAutonomyBinding();
    addTearDown(autonomy.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: KristinMainShell(
          ownerMode: ownerMode,
          autonomyBinding: autonomy,
          chat: const Center(child: Text('Chat surface')),
        ),
      ),
    );

    expect(find.byKey(const Key('p5-global-autonomy-bar')), findsOneWidget);
    expect(find.byKey(const Key('p5-global-profile')), findsOneWidget);
    expect(find.text('Chat surface'), findsOneWidget);

    await tester.tap(find.text('Experience'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workspace-title')), findsOneWidget);
    expect(find.byKey(const Key('p5-global-autonomy-bar')), findsOneWidget);

    await tester.tap(find.text('Owner Mode'));
    await tester.pumpAndSettle();
    expect(find.text('Owner Mode is unavailable'), findsOneWidget);
    expect(find.byKey(const Key('p5-global-autonomy-bar')), findsOneWidget);
    expect(
      find.textContaining('Diagnostic: merged_p1a_service_unavailable'),
      findsOneWidget,
    );
    expect(find.textContaining('Bad state'), findsNothing);
  });
}
'''
write('test/product/p5_main_shell_integration_test.dart', main_shell_test)

controller_test = r'''import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/p5_global_autonomy.dart';

class _FakeRunPort implements P5GlobalAutonomyRunPort {
  _FakeRunPort(this.sessions);

  final List<P5GlobalAutonomyRunSession> sessions;
  final List<String> paused = <String>[];
  final List<String> cancelled = <String>[];

  @override
  Future<void> cancel(String runId) async {
    cancelled.add(runId);
    _replaceState(runId, RunState.cancelling);
  }

  @override
  Future<List<P5GlobalAutonomyRunSession>> listSessions() async =>
      List<P5GlobalAutonomyRunSession>.of(sessions);

  @override
  Future<void> pause(String runId) async {
    paused.add(runId);
    _replaceState(runId, RunState.paused);
  }

  void _replaceState(String id, RunState state) {
    final index = sessions.indexWhere((session) => session.id == id);
    final current = sessions[index];
    sessions[index] = P5GlobalAutonomyRunSession(
      id: current.id,
      state: state,
      modelLabel: current.modelLabel,
      networkRequested: current.networkRequested,
    );
  }
}

class _FakeOwnerPort implements P5GlobalAutonomyOwnerPort {
  _FakeOwnerPort(this.value);

  P5GlobalAutonomyOwnerSnapshot value;
  int emergencyCalls = 0;

  @override
  Future<void> emergencyKillAll() async {
    emergencyCalls++;
    value = P5GlobalAutonomyOwnerSnapshot(
      profileId: value.profileId,
      ownerAvailable: value.ownerAvailable,
      ownerEnabled: value.ownerEnabled,
      terminalCount: value.terminalCount,
      supervisedProcessTreeCount: 0,
    );
  }

  @override
  P5GlobalAutonomyOwnerSnapshot snapshot() => value;
}

P5GlobalAutonomyRunSession session(
  String id,
  RunState state, {
  bool network = false,
}) =>
    P5GlobalAutonomyRunSession(
      id: id,
      state: state,
      modelLabel: 'ollama/test-model@digest',
      networkRequested: network,
    );

void main() {
  test('P5-005 controller reports real port state and delegates controls', () async {
    final runs = _FakeRunPort(<P5GlobalAutonomyRunSession>[
      session('run-a', RunState.running, network: true),
      session('run-b', RunState.paused),
      session('run-c', RunState.queued),
      session('run-d', RunState.succeeded),
    ]);
    final owner = _FakeOwnerPort(
      const P5GlobalAutonomyOwnerSnapshot(
        profileId: 'owner',
        ownerAvailable: true,
        ownerEnabled: true,
        terminalCount: 1,
        supervisedProcessTreeCount: 1,
      ),
    );
    final controller = P5GlobalAutonomyController(
      runPort: runs,
      ownerPort: owner,
      refreshInterval: null,
    );
    addTearDown(controller.dispose);
    var browserStops = 0;
    controller.registerBrowserEmergencyStop(() async => browserStops++);
    controller.updateBrowserSessionCount(2);
    await controller.refresh();

    expect(controller.snapshot.profileLabel, 'owner');
    expect(controller.snapshot.modelLabel, 'ollama/test-model@digest');
    expect(controller.snapshot.activeRunCount, 3);
    expect(controller.snapshot.activeSessionCount, 6);
    expect(controller.snapshot.networkLabel, 'Owner policy');
    expect(controller.snapshot.takeoverLabel, 'Not globally bound');
    expect(controller.snapshot.canPause, isTrue);
    expect(controller.snapshot.canStop, isTrue);
    expect(controller.snapshot.canEmergencyKill, isTrue);

    await controller.pauseActiveRuns();
    expect(runs.paused, <String>['run-a']);

    await controller.stopActiveRuns();
    expect(runs.cancelled.toSet(), <String>{'run-a', 'run-b', 'run-c'});

    await controller.emergencyKill();
    expect(browserStops, 1);
    expect(owner.emergencyCalls, 1);
  });

  testWidgets('P5-005 bar exposes status and real action bindings', (tester) async {
    final runs = _FakeRunPort(<P5GlobalAutonomyRunSession>[
      session('run-a', RunState.running),
    ]);
    final owner = _FakeOwnerPort(
      const P5GlobalAutonomyOwnerSnapshot(
        profileId: 'chat',
        ownerAvailable: true,
        ownerEnabled: false,
        terminalCount: 0,
        supervisedProcessTreeCount: 0,
      ),
    );
    final controller = P5GlobalAutonomyController(
      runPort: runs,
      ownerPort: owner,
      refreshInterval: null,
    );
    addTearDown(controller.dispose);
    await controller.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: P5GlobalAutonomyBar(binding: controller),
        ),
      ),
    );

    expect(find.byKey(const Key('p5-global-profile')), findsOneWidget);
    expect(find.byKey(const Key('p5-global-model')), findsOneWidget);
    expect(find.byKey(const Key('p5-global-sessions')), findsOneWidget);
    expect(find.byKey(const Key('p5-global-takeover')), findsOneWidget);
    expect(find.byKey(const Key('p5-global-network')), findsOneWidget);

    await tester.tap(find.byKey(const Key('p5-global-pause')));
    await tester.pumpAndSettle();
    expect(runs.paused, <String>['run-a']);

    await tester.tap(find.byKey(const Key('p5-global-stop')));
    await tester.pumpAndSettle();
    expect(runs.cancelled, <String>['run-a']);
  });
}
'''
write('test/product/p5_global_autonomy_test.dart', controller_test)

source_contract_path = 'test/product/source_contract_test.dart'
replace_once(
    source_contract_path,
    "        'lib/product/p5_design_tokens.dart',\n",
    "        'lib/product/p5_design_tokens.dart',\n        'lib/product/p5_global_autonomy.dart',\n",
)
replace_once(
    source_contract_path,
    "    test('release validator follows governed design-token modules', () {\n",
    '''    test('P5 global autonomy is shell-owned and delegates governed runtime effects', () {
      final ui = source('lib/product/ui.dart');
      final autonomy = source('lib/product/p5_global_autonomy.dart');
      final prototype = source(
        'lib/product/p5_information_architecture/p5_prototype.dart',
      );
      expect(ui, contains('P5GlobalAutonomyBar(binding: _autonomyBinding)'));
      expect(ui, contains('globalAutonomy: _autonomyBinding'));
      expect(autonomy, contains('_runtime.pause(runId)'));
      expect(autonomy, contains('_runtime.cancel(runId)'));
      expect(autonomy, contains('emergencyPauseAndKillAll()'));
      expect(autonomy, contains("takeoverLabel: 'Not globally bound'"));
      expect(prototype, contains('registerBrowserEmergencyStop'));
      expect(prototype, contains('updateBrowserSessionCount(0)'));
    });

    test('release validator follows governed design-token modules', () {
''',
)

print('P5_005_GLOBAL_AUTONOMY_PATCH_APPLIED')
