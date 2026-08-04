import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'p2_effect_boundary.dart';
import 'p2_emergency_watchdog.dart';
import 'p2_owner_mode.dart';
import 'p2_pty_service.dart';
import 'p2_terminal_model.dart';

abstract interface class P2OwnerWorkspaceActions {
  Future<void> copySelection(P2TerminalTab tab);
  Future<void> saveTranscript(P2TerminalTab tab);
  Future<void> interrupt(P2TerminalTab tab);
  Future<void> terminateTree(P2TerminalTab tab);
  Future<void> emergencyPauseAndKill();
}

class P2TerminalAuthorization {
  const P2TerminalAuthorization({
    required this.binding,
    required this.grantDigest,
  });

  final P2EffectBinding binding;
  final String grantDigest;
}

typedef P2TerminalAuthorizationResolver = P2TerminalAuthorization Function(
    P2TerminalTab tab, String operation);
typedef P2TerminalBytesReader = Future<List<int>> Function(P2TerminalTab tab);
typedef P2ClipboardTextWriter = Future<void> Function(String text);
typedef P2TranscriptFileWriter = Future<void> Function(
    P2TerminalTab tab, List<int> bytes);

/// Concrete UI-to-service bridge. Authorization is resolved per tab and the
/// PTY backend still verifies the exact grant/session binding on every call.
class P2OwnerWorkspaceServiceActions implements P2OwnerWorkspaceActions {
  P2OwnerWorkspaceServiceActions({
    required this.ptyBackend,
    required this.emergencyController,
    required this.watchdogId,
    required this.authorizationFor,
    required this.selectionBytes,
    required this.transcriptBytes,
    required this.writeClipboardText,
    required this.writeTranscriptFile,
    this.emergencyAction,
  });

  final P2PtyBackend ptyBackend;
  final P2EmergencyController emergencyController;
  final String watchdogId;
  final P2TerminalAuthorizationResolver authorizationFor;
  final P2TerminalBytesReader selectionBytes;
  final P2TerminalBytesReader transcriptBytes;
  final P2ClipboardTextWriter writeClipboardText;
  final P2TranscriptFileWriter writeTranscriptFile;
  final Future<void> Function()? emergencyAction;

  @override
  Future<void> copySelection(P2TerminalTab tab) async {
    final bytes = await selectionBytes(tab);
    await writeClipboardText(utf8.decode(bytes, allowMalformed: true));
  }

  @override
  Future<void> saveTranscript(P2TerminalTab tab) async {
    await writeTranscriptFile(tab, await transcriptBytes(tab));
  }

  @override
  Future<void> interrupt(P2TerminalTab tab) {
    final authorization = authorizationFor(tab, 'pty.interrupt');
    return ptyBackend.interrupt(
      tab.id,
      binding: authorization.binding,
      grantDigest: authorization.grantDigest,
    );
  }

  @override
  Future<void> terminateTree(P2TerminalTab tab) {
    final authorization = authorizationFor(tab, 'pty.terminate');
    return ptyBackend.terminate(
      tab.id,
      binding: authorization.binding,
      grantDigest: authorization.grantDigest,
    );
  }

  @override
  Future<void> emergencyPauseAndKill() {
    final action = emergencyAction;
    return action != null
        ? action()
        : emergencyController.pauseAndKill(watchdogId);
  }
}

class P2OwnerWorkspace extends StatefulWidget {
  const P2OwnerWorkspace({
    super.key,
    required this.controller,
    required this.terminalModel,
    required this.actions,
  });

  final P2OwnerModeController controller;
  final P2TerminalModel terminalModel;
  final P2OwnerWorkspaceActions actions;

  @override
  State<P2OwnerWorkspace> createState() => _P2OwnerWorkspaceState();
}

class _P2OwnerWorkspaceState extends State<P2OwnerWorkspace> {
  var _acknowledged = false;
  var _unattended = false;
  var _busy = false;
  var _approval = P2OwnerApprovalPolicy.everyHighRiskEffect;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enable() => _run(
        () => widget.controller.enable(
          unattended: _unattended,
          approvalPolicy: _approval,
          acknowledged: _acknowledged,
        ),
      );

  P2TerminalTab? get _selected => widget.terminalModel.selected;

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.current;
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true):
            _P2SearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, control: true, shift: true):
            _P2KillIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _P2SearchIntent: CallbackAction<_P2SearchIntent>(
            onInvoke: (_) {
              _searchFocus.requestFocus();
              return null;
            },
          ),
          _P2KillIntent: CallbackAction<_P2KillIntent>(
            onInvoke: (_) {
              _run(widget.actions.emergencyPauseAndKill);
              return null;
            },
          ),
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              liveRegion: true,
              label: state.persistentIndicator,
              child: MaterialBanner(
                content: Text(
                  '${state.persistentIndicator}\n${state.safetyLabel}',
                ),
                leading: Icon(
                  state.enabled
                      ? Icons.admin_panel_settings
                      : Icons.shield_outlined,
                ),
                actions: <Widget>[
                  if (state.enabled)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(widget.controller.disableAndReset),
                      child: const Text('Disable and reset'),
                    )
                  else
                    const TextButton(
                      onPressed: null,
                      child: Text('Review below'),
                    ),
                ],
              ),
            ),
            if (!state.enabled) Expanded(child: _buildOnboarding(context)),
            if (state.enabled) Expanded(child: _buildTerminal(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildOnboarding(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          Text(
            'Enable Owner Mode',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'Owner Mode can reach all files, applications, terminals, and '
            'account resources available to this OS account. It is not '
            'containment or isolation.',
          ),
          CheckboxListTile(
            value: _acknowledged,
            onChanged: _busy
                ? null
                : (value) => setState(() => _acknowledged = value ?? false),
            title: const Text(
              'I understand the full-current-account data boundary',
            ),
          ),
          SwitchListTile(
            value: _unattended,
            onChanged:
                _busy ? null : (value) => setState(() => _unattended = value),
            title: const Text('Owner unattended'),
            subtitle: const Text(
              'Stricter secret and elevation boundaries still apply.',
            ),
          ),
          DropdownButtonFormField<P2OwnerApprovalPolicy>(
            initialValue: _approval,
            decoration: const InputDecoration(labelText: 'Approval policy'),
            items: P2OwnerApprovalPolicy.values
                .map(
                  (value) => DropdownMenuItem<P2OwnerApprovalPolicy>(
                    value: value,
                    child: Text(value.name),
                  ),
                )
                .toList(growable: false),
            onChanged: _busy
                ? null
                : (value) => setState(() => _approval = value ?? _approval),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _acknowledged && !_busy ? _enable : null,
            icon: const Icon(Icons.warning_amber),
            label: const Text('Enable full Owner Mode'),
          ),
        ],
      );

  Widget _buildTerminal(BuildContext context) {
    final tabs = _search.text.isEmpty
        ? widget.terminalModel.tabs
        : widget.terminalModel.search(_search.text).toList(growable: false);
    final selected = _selected;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _search,
            focusNode: _searchFocus,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search terminal tabs and run identities',
            ),
          ),
        ),
        Expanded(
          child: Semantics(
            label: 'Owner Mode terminal tabs',
            child: ListView.builder(
              itemCount: tabs.length,
              itemBuilder: (context, index) {
                final tab = tabs[index];
                return Semantics(
                  label: tab.accessibilityLabel,
                  child: ListTile(
                    selected: tab.id == selected?.id,
                    onTap: () {
                      final actualIndex = widget.terminalModel.tabs.indexWhere(
                        (candidate) => candidate.id == tab.id,
                      );
                      if (actualIndex >= 0) {
                        setState(
                          () =>
                              widget.terminalModel.selectedIndex = actualIndex,
                        );
                      }
                    },
                    leading: const Icon(Icons.terminal),
                    title: Text(tab.title),
                    subtitle: Text(
                      '${tab.shell} • ${tab.cwd}\n'
                      'run ${tab.runId} • task ${tab.taskId} • '
                      'grant ${tab.grantId}',
                    ),
                    trailing: Text(tab.attached ? 'Attached' : 'Detached'),
                  ),
                );
              },
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Wrap(
            alignment: WrapAlignment.end,
            children: <Widget>[
              TextButton.icon(
                onPressed: selected == null || _busy
                    ? null
                    : () => _run(() => widget.actions.copySelection(selected)),
                icon: const Icon(Icons.content_copy),
                label: const Text('Copy'),
              ),
              TextButton.icon(
                onPressed: selected == null || _busy
                    ? null
                    : () => _run(() => widget.actions.saveTranscript(selected)),
                icon: const Icon(Icons.save_alt),
                label: const Text('Save transcript'),
              ),
              TextButton.icon(
                onPressed: selected == null || _busy
                    ? null
                    : () => _run(() => widget.actions.interrupt(selected)),
                icon: const Icon(Icons.keyboard_command_key),
                label: const Text('Interrupt'),
              ),
              FilledButton.tonalIcon(
                onPressed: selected == null || _busy
                    ? null
                    : () => _run(() => widget.actions.terminateTree(selected)),
                icon: const Icon(Icons.stop_circle),
                label: const Text('Terminate tree'),
              ),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(widget.actions.emergencyPauseAndKill),
                icon: const Icon(Icons.emergency),
                label: const Text('Emergency pause and kill'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _P2SearchIntent extends Intent {
  const _P2SearchIntent();
}

class _P2KillIntent extends Intent {
  const _P2KillIntent();
}
