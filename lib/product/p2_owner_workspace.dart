import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'p2_effect_boundary.dart';
import 'p2_emergency_watchdog.dart';
import 'p2_owner_mode.dart';
import 'p2_pty_service.dart';
import 'p2_terminal_model.dart';

abstract interface class P2OwnerWorkspaceActions {
  Stream<List<int>> output(P2TerminalTab tab, int fromCursor);
  Future<void> input(P2TerminalTab tab, List<int> bytes);
  Future<void> detach(P2TerminalTab tab);
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
  Stream<List<int>> output(P2TerminalTab tab, int fromCursor) {
    final authorization = authorizationFor(tab, 'pty.attach');
    return ptyBackend.output(
      tab.id,
      fromCursor,
      binding: authorization.binding,
      grantDigest: authorization.grantDigest,
    );
  }

  @override
  Future<void> input(P2TerminalTab tab, List<int> bytes) {
    final authorization = authorizationFor(tab, 'pty.input');
    return ptyBackend.input(
      tab.id,
      bytes,
      binding: authorization.binding,
      grantDigest: authorization.grantDigest,
    );
  }

  @override
  Future<void> detach(P2TerminalTab tab) {
    final authorization = authorizationFor(tab, 'pty.detach');
    return ptyBackend.detach(
      tab.id,
      binding: authorization.binding,
      grantDigest: authorization.grantDigest,
    );
  }

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
  static const int _terminalDisplayBudgetBytes = 512 * 1024;

  var _acknowledged = false;
  var _unattended = false;
  var _busy = false;
  var _approval = P2OwnerApprovalPolicy.everyHighRiskEffect;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _terminalInput = TextEditingController();
  final _terminalInputFocus = FocusNode();
  final _terminalScroll = ScrollController();
  final Map<String, _P2TerminalBuffer> _buffers = <String, _P2TerminalBuffer>{};
  final Map<String, StreamSubscription<List<int>>> _outputSubscriptions =
      <String, StreamSubscription<List<int>>>{};
  final Map<String, String> _connectionLabels = <String, String>{};
  final Map<String, String> _connectionErrors = <String, String>{};

  @override
  void initState() {
    super.initState();
    widget.terminalModel.addListener(_terminalModelChanged);
    _scheduleTerminalSync();
  }

  @override
  void didUpdateWidget(covariant P2OwnerWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.terminalModel, widget.terminalModel)) {
      oldWidget.terminalModel.removeListener(_terminalModelChanged);
      widget.terminalModel.addListener(_terminalModelChanged);
      _scheduleTerminalSync();
    }
  }

  @override
  void dispose() {
    widget.terminalModel.removeListener(_terminalModelChanged);
    for (final subscription in _outputSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _outputSubscriptions.clear();
    _search.dispose();
    _searchFocus.dispose();
    _terminalInput.dispose();
    _terminalInputFocus.dispose();
    _terminalScroll.dispose();
    super.dispose();
  }

  void _terminalModelChanged() {
    if (!mounted) return;
    setState(() {});
    _scheduleTerminalSync();
  }

  void _scheduleTerminalSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_syncTerminalStreams());
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scheduleTerminalSync();
      }
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

  Future<void> _syncTerminalStreams() async {
    final tabsById = <String, P2TerminalTab>{
      for (final tab in widget.terminalModel.tabs) tab.id: tab,
    };
    final enabled = widget.controller.current.enabled;
    final staleIds = _outputSubscriptions.keys
        .where((id) => !enabled || tabsById[id]?.attached != true)
        .toList(growable: false);
    for (final id in staleIds) {
      await _cancelLocalOutput(id);
    }
    if (!enabled) return;
    for (final tab in tabsById.values) {
      if (tab.attached) _ensureOutput(tab);
    }
  }

  void _ensureOutput(P2TerminalTab tab) {
    if (_outputSubscriptions.containsKey(tab.id)) return;
    final buffer = _buffers.putIfAbsent(tab.id, _P2TerminalBuffer.new);
    _connectionLabels[tab.id] = 'Attaching…';
    _connectionErrors.remove(tab.id);
    late final Stream<List<int>> stream;
    try {
      stream = widget.actions.output(tab, buffer.cursor);
    } catch (error) {
      _recordOutputFailure(tab.id, error);
      return;
    }
    late final StreamSubscription<List<int>> subscription;
    subscription = stream.listen(
      (bytes) {
        buffer.append(bytes, maxBytes: _terminalDisplayBudgetBytes);
        _connectionLabels[tab.id] = 'Attached';
        _connectionErrors.remove(tab.id);
        if (mounted) {
          setState(() {});
          if (_selected?.id == tab.id) _scrollTerminalToEnd();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_outputSubscriptions[tab.id], subscription)) {
          _outputSubscriptions.remove(tab.id);
        }
        _recordOutputFailure(tab.id, error);
      },
      onDone: () {
        if (identical(_outputSubscriptions[tab.id], subscription)) {
          _outputSubscriptions.remove(tab.id);
        }
        _connectionLabels[tab.id] = 'Disconnected';
        final exists = widget.terminalModel.tabs.any(
          (candidate) => candidate.id == tab.id,
        );
        if (exists &&
            widget.terminalModel.tabs
                .firstWhere((candidate) => candidate.id == tab.id)
                .attached) {
          widget.terminalModel.setAttached(tab.id, false);
        } else if (mounted) {
          setState(() {});
        }
      },
      cancelOnError: true,
    );
    _outputSubscriptions[tab.id] = subscription;
    if (mounted) setState(() {});
  }

  void _recordOutputFailure(String tabId, Object error) {
    _connectionLabels[tabId] = 'Connection error';
    _connectionErrors[tabId] = error.toString();
    final exists = widget.terminalModel.tabs.any(
      (candidate) => candidate.id == tabId,
    );
    if (exists &&
        widget.terminalModel.tabs
            .firstWhere((candidate) => candidate.id == tabId)
            .attached) {
      widget.terminalModel.setAttached(tabId, false);
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _cancelLocalOutput(String tabId) async {
    final subscription = _outputSubscriptions.remove(tabId);
    if (subscription != null) await subscription.cancel();
  }

  Future<void> _attachSelected() async {
    final selected = _selected;
    if (selected == null || selected.attached) return;
    widget.terminalModel.setAttached(selected.id, true);
    await _syncTerminalStreams();
    _terminalInputFocus.requestFocus();
  }

  Future<void> _detachSelected() async {
    final selected = _selected;
    if (selected == null || !selected.attached) return;
    await widget.actions.detach(selected);
    await _cancelLocalOutput(selected.id);
    widget.terminalModel.setAttached(selected.id, false);
    _connectionLabels[selected.id] = 'Detached';
    if (mounted) setState(() {});
  }

  Future<void> _sendInput() async {
    final selected = _selected;
    if (selected == null || !selected.attached || _busy) return;
    final text = _terminalInput.text;
    final bytes = <int>[...utf8.encode(text), 13];
    await _run(() => widget.actions.input(selected, bytes));
    if (mounted) {
      _terminalInput.clear();
      _terminalInputFocus.requestFocus();
    }
  }

  void _scrollTerminalToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_terminalScroll.hasClients) return;
      _terminalScroll.jumpTo(_terminalScroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.current;
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true):
            _P2SearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, control: true, shift: true):
            _P2KillIntent(),
        SingleActivator(LogicalKeyboardKey.keyD, control: true, shift: true):
            _P2DetachIntent(),
        SingleActivator(LogicalKeyboardKey.keyA, control: true, shift: true):
            _P2AttachIntent(),
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
          _P2DetachIntent: CallbackAction<_P2DetachIntent>(
            onInvoke: (_) {
              _run(_detachSelected);
              return null;
            },
          ),
          _P2AttachIntent: CallbackAction<_P2AttachIntent>(
            onInvoke: (_) {
              _run(_attachSelected);
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useSideBySide = constraints.maxWidth >= 900 ||
                  (constraints.maxWidth >= 720 && constraints.maxHeight < 420);
              if (useSideBySide) {
                final tabListWidth =
                    constraints.maxWidth >= 900 ? 330.0 : 260.0;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(width: tabListWidth, child: _buildTabList(tabs)),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildTerminalPane(context)),
                  ],
                );
              }
              final tabListHeight = constraints.maxHeight < 360 ? 96.0 : 180.0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(height: tabListHeight, child: _buildTabList(tabs)),
                  const Divider(height: 1),
                  Expanded(child: _buildTerminalPane(context)),
                ],
              );
            },
          ),
        ),
        _buildTerminalActions(),
      ],
    );
  }

  Widget _buildTabList(List<P2TerminalTab> tabs) {
    final selected = _selected;
    return Semantics(
      label: 'Owner Mode terminal tabs',
      child: ListView.builder(
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          final tab = tabs[index];
          return Semantics(
            label: tab.accessibilityLabel,
            child: ListTile(
              selected: tab.id == selected?.id,
              onTap: () => widget.terminalModel.select(tab.id),
              leading: const Icon(Icons.terminal),
              title: Text(tab.title),
              subtitle: Text(
                '${tab.shell} • ${tab.cwd}\n'
                'run ${tab.runId} • task ${tab.taskId} • grant ${tab.grantId}',
              ),
              trailing: Text(tab.attached ? 'Attached' : 'Detached'),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTerminalPane(BuildContext context) {
    final selected = _selected;
    if (selected == null) {
      return const Center(
        child: Text('No managed terminal session is active.'),
      );
    }
    final buffer = _buffers.putIfAbsent(selected.id, _P2TerminalBuffer.new);
    final connection = _connectionLabels[selected.id] ??
        (selected.attached ? 'Attached' : 'Detached');
    final connectionError = _connectionErrors[selected.id];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                selected.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(selected.shell),
              Text(selected.cwd),
              Semantics(
                liveRegion: true,
                label: 'Terminal connection $connection',
                child: Chip(label: Text(connection)),
              ),
            ],
          ),
          if (connectionError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                connectionError,
                key: const Key('owner-terminal-connection-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (buffer.droppedBytes > 0)
            Text(
              '${buffer.droppedBytes} earlier terminal bytes are hidden to keep the UI responsive.',
              key: const Key('owner-terminal-truncated'),
            ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Scrollbar(
                controller: _terminalScroll,
                child: SingleChildScrollView(
                  controller: _terminalScroll,
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: SelectableText(
                      buffer.text.isEmpty
                          ? 'Waiting for terminal output…'
                          : buffer.text,
                      key: const Key('owner-terminal-output'),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: const Key('owner-terminal-input'),
                  controller: _terminalInput,
                  focusNode: _terminalInputFocus,
                  enabled: selected.attached && !_busy,
                  maxLength: 16 * 1024,
                  maxLines: 3,
                  minLines: 1,
                  onSubmitted: (_) => unawaited(_sendInput()),
                  decoration: const InputDecoration(
                    labelText: 'Terminal input',
                    hintText: 'Type a command and press Enter',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Send terminal input',
                onPressed:
                    selected.attached && !_busy ? () => _sendInput() : null,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalActions() {
    final selected = _selected;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 4,
          runSpacing: 4,
          children: <Widget>[
            TextButton.icon(
              onPressed: selected == null || selected.attached || _busy
                  ? null
                  : () => _run(_attachSelected),
              icon: const Icon(Icons.link),
              label: const Text('Attach'),
            ),
            TextButton.icon(
              onPressed: selected == null || !selected.attached || _busy
                  ? null
                  : () => _run(_detachSelected),
              icon: const Icon(Icons.link_off),
              label: const Text('Detach'),
            ),
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
              onPressed: selected == null || !selected.attached || _busy
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
    );
  }
}

final class _P2TerminalBuffer {
  final List<int> bytes = <int>[];
  int cursor = 0;
  int droppedBytes = 0;

  String get text => utf8.decode(bytes, allowMalformed: true);

  void append(List<int> chunk, {required int maxBytes}) {
    cursor += chunk.length;
    bytes.addAll(chunk);
    if (bytes.length <= maxBytes) return;
    final excess = bytes.length - maxBytes;
    bytes.removeRange(0, excess);
    droppedBytes += excess;
  }
}

class _P2SearchIntent extends Intent {
  const _P2SearchIntent();
}

class _P2KillIntent extends Intent {
  const _P2KillIntent();
}

class _P2DetachIntent extends Intent {
  const _P2DetachIntent();
}

class _P2AttachIntent extends Intent {
  const _P2AttachIntent();
}
