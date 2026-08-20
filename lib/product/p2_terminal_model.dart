import 'package:flutter/foundation.dart';

enum P2TerminalAction {
  newTab,
  closeTab,
  nextTab,
  previousTab,
  focusSearch,
  copySelection,
  saveTranscript,
  sendInterrupt,
  terminate,
  detach,
  attach,
  emergencyKill,
}

class P2TerminalTab {
  const P2TerminalTab({
    required this.id,
    required this.title,
    required this.shell,
    required this.cwd,
    required this.runId,
    required this.taskId,
    required this.grantId,
    required this.attached,
    required this.accessibilityLabel,
  });

  final String id;
  final String title;
  final String shell;
  final String cwd;
  final String runId;
  final String taskId;
  final String grantId;
  final bool attached;
  final String accessibilityLabel;

  P2TerminalTab copyWith({
    String? title,
    bool? attached,
    String? accessibilityLabel,
  }) => P2TerminalTab(
    id: id,
    title: title ?? this.title,
    shell: shell,
    cwd: cwd,
    runId: runId,
    taskId: taskId,
    grantId: grantId,
    attached: attached ?? this.attached,
    accessibilityLabel: accessibilityLabel ?? this.accessibilityLabel,
  );
}

class P2TerminalModel extends ChangeNotifier {
  final List<P2TerminalTab> tabs = <P2TerminalTab>[];
  int _selectedIndex = 0;

  Map<P2TerminalAction, String> get shortcuts => const {
    P2TerminalAction.newTab: 'Ctrl+Shift+T',
    P2TerminalAction.closeTab: 'Ctrl+Shift+W',
    P2TerminalAction.focusSearch: 'Ctrl+Shift+F',
    P2TerminalAction.copySelection: 'Ctrl+Shift+C',
    P2TerminalAction.saveTranscript: 'Ctrl+Shift+S',
    P2TerminalAction.sendInterrupt: 'Ctrl+C',
    P2TerminalAction.terminate: 'Ctrl+Shift+X',
    P2TerminalAction.detach: 'Ctrl+Shift+D',
    P2TerminalAction.attach: 'Ctrl+Shift+A',
    P2TerminalAction.emergencyKill: 'Ctrl+Shift+K',
  };

  int get selectedIndex => _selectedIndex;

  set selectedIndex(int value) {
    if (tabs.isEmpty) {
      if (value != 0) throw RangeError.index(value, tabs, 'selectedIndex');
      _selectedIndex = 0;
      return;
    }
    if (value < 0 || value >= tabs.length) {
      throw RangeError.index(value, tabs, 'selectedIndex');
    }
    if (_selectedIndex == value) return;
    _selectedIndex = value;
    notifyListeners();
  }

  P2TerminalTab? get selected => tabs.isEmpty ? null : tabs[_selectedIndex];

  void add(P2TerminalTab tab) {
    if (tab.id.trim().isEmpty ||
        tabs.any((candidate) => candidate.id == tab.id)) {
      throw StateError('terminal_tab_identity_invalid');
    }
    tabs.add(tab);
    _selectedIndex = tabs.length - 1;
    notifyListeners();
  }

  void remove(String id) {
    final index = tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) return;
    tabs.removeAt(index);
    if (tabs.isEmpty) {
      _selectedIndex = 0;
    } else if (_selectedIndex >= tabs.length) {
      _selectedIndex = tabs.length - 1;
    } else if (index < _selectedIndex) {
      _selectedIndex -= 1;
    }
    notifyListeners();
  }

  void select(String id) {
    final index = tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) throw StateError('terminal_tab_unknown');
    selectedIndex = index;
  }

  void setAttached(String id, bool attached) {
    final index = tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) throw StateError('terminal_tab_unknown');
    final current = tabs[index];
    if (current.attached == attached) return;
    tabs[index] = current.copyWith(attached: attached);
    notifyListeners();
  }

  Iterable<P2TerminalTab> search(String query) => tabs.where(
    (tab) => <String>[
      tab.title,
      tab.shell,
      tab.cwd,
      tab.runId,
      tab.taskId,
      tab.grantId,
    ].join(' ').toLowerCase().contains(query.toLowerCase()),
  );
}
