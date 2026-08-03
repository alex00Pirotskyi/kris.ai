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
}

class P2TerminalModel {
  final List<P2TerminalTab> tabs = <P2TerminalTab>[];
  int selectedIndex = 0;

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

  P2TerminalTab? get selected => tabs.isEmpty ? null : tabs[selectedIndex];

  void add(P2TerminalTab tab) {
    tabs.add(tab);
    selectedIndex = tabs.length - 1;
  }

  void remove(String id) {
    tabs.removeWhere((tab) => tab.id == id);
    if (selectedIndex >= tabs.length) {
      selectedIndex = tabs.isEmpty ? 0 : tabs.length - 1;
    }
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
