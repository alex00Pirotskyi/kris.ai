import 'dart:async';

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

class P5ProductRuntimeGlobalAutonomyRunPort implements P5GlobalAutonomyRunPort {
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

  factory P5GlobalAutonomySnapshot.initial() => const P5GlobalAutonomySnapshot(
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
    if (_disposed || _refreshing) {
      return;
    }
    _refreshing = true;
    try {
      final sessions = await _listRunSessions();
      final active = sessions
          .where((session) => _p5ActiveRunStates.contains(session.state))
          .toList(growable: false);
      final owner = _ownerPort.snapshot();
      final running =
          active.any((session) => session.state == RunState.running);
      final stoppable = active
          .any((session) => _p5StoppableRunStates.contains(session.state));
      final model = active.isEmpty ? null : active.first.modelLabel;
      final networkRequested =
          active.any((session) => session.networkRequested);
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
      if (_disposed) {
        return;
      }
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
    if (failures > 0) {
      throw StateError('global_pause_partial_failure:$failures');
    }
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
    if (failures > 0) {
      throw StateError('global_stop_partial_failure:$failures');
    }
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

    if (!attempted) {
      throw StateError('no_active_session_to_kill');
    }
    await refresh();
    if (failures > 0) {
      throw StateError('global_emergency_partial_failure:$failures');
    }
  }

  @override
  void updateBrowserSessionCount(int count) {
    final bounded = count < 0 ? 0 : count;
    if (_browserSessionCount == bounded) {
      return;
    }
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
    if (events != null) {
      unawaited(events.cancel());
    }
    _events = null;
    _browserEmergencyStop = null;
    super.dispose();
  }
}

class P5GlobalAutonomyBar extends StatefulWidget {
  const P5GlobalAutonomyBar({
    super.key,
    required this.binding,
    this.onOpenCommands,
  });

  final P5GlobalAutonomyBinding binding;
  final VoidCallback? onOpenCommands;

  @override
  State<P5GlobalAutonomyBar> createState() => _P5GlobalAutonomyBarState();
}

class _P5GlobalAutonomyBarState extends State<P5GlobalAutonomyBar> {
  bool _busy = false;
  String? _errorCode;

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
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
                child: Row(
                  children: <Widget>[
                    if (widget.onOpenCommands != null) ...<Widget>[
                      IconButton(
                        key: const Key('p5-command-palette-button'),
                        tooltip: 'Command palette (Ctrl/Cmd+K)',
                        onPressed: widget.onOpenCommands,
                        icon: const Icon(Icons.search),
                      ),
                      const VerticalDivider(width: 1),
                    ],
                    Expanded(
                      child: SingleChildScrollView(
                        key: const Key('p5-global-status-scroll'),
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
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
                                label:
                                    'Sessions: ${snapshot.activeSessionCount}',
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
                            if (_errorCode != null) ...<Widget>[
                              const SizedBox(width: 10),
                              Text(
                                _errorCode!,
                                key: const Key('p5-global-action-error'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_busy) ...<Widget>[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      key: const Key('p5-global-pause'),
                      onPressed: _busy || !snapshot.canPause
                          ? null
                          : () => _perform(widget.binding.pauseActiveRuns),
                      icon: const Icon(Icons.pause),
                      label: const Text('Pause'),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      key: const Key('p5-global-stop'),
                      onPressed: _busy || !snapshot.canStop
                          ? null
                          : () => _perform(widget.binding.stopActiveRuns),
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: FilledButton.icon(
                        key: const Key('p5-global-kill'),
                        onPressed: _busy || !snapshot.canEmergencyKill
                            ? null
                            : () => _perform(widget.binding.emergencyKill),
                        icon: const Icon(Icons.emergency_outlined),
                        label: const Text('Emergency kill'),
                      ),
                    ),
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
