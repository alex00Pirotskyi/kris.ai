from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}: {old!r}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')


palette_path = Path('lib/product/p5_command_palette.dart')
if palette_path.exists():
    raise SystemExit(f'{palette_path}: refusing to overwrite existing source')
palette_path.write_text(r'''import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'p5_information_architecture/p5_models.dart';

enum P5CommandActionKind {
  shellDestination,
  experienceWorkspace,
  launchExperienceTask,
}

@immutable
class P5CommandDefinition {
  const P5CommandDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.keywords,
    required this.actionKind,
    this.shellIndex,
    this.workspace,
    this.shortcutLabel,
    this.shortcutSignature,
  });

  final String id;
  final String label;
  final String description;
  final List<String> keywords;
  final P5CommandActionKind actionKind;
  final int? shellIndex;
  final P5WorkspaceId? workspace;
  final String? shortcutLabel;
  final String? shortcutSignature;

  String get searchableText => <String>[
        id,
        label,
        description,
        ...keywords,
        if (shortcutLabel != null) shortcutLabel!,
      ].join(' ').toLowerCase();
}

class P5CommandCatalog {
  const P5CommandCatalog._();

  static final List<P5CommandDefinition> primary =
      List<P5CommandDefinition>.unmodifiable(_buildPrimary());

  static List<P5CommandDefinition> _buildPrimary() {
    final commands = <P5CommandDefinition>[
      const P5CommandDefinition(
        id: 'shell.chat',
        label: 'Open Chat',
        description: 'Switch to the primary Chat workspace.',
        keywords: <String>['conversation', 'assistant'],
        actionKind: P5CommandActionKind.shellDestination,
        shellIndex: 0,
        shortcutLabel: 'Ctrl/Cmd+1',
        shortcutSignature: 'primary+1',
      ),
      const P5CommandDefinition(
        id: 'shell.experience',
        label: 'Open Experience',
        description: 'Switch to the integrated Experience workspace.',
        keywords: <String>['workbench', 'task'],
        actionKind: P5CommandActionKind.shellDestination,
        shellIndex: 1,
        shortcutLabel: 'Ctrl/Cmd+2',
        shortcutSignature: 'primary+2',
      ),
      const P5CommandDefinition(
        id: 'shell.owner',
        label: 'Open Owner Mode',
        description: 'Switch to the real Owner Mode workspace.',
        keywords: <String>['terminal', 'admin', 'full access'],
        actionKind: P5CommandActionKind.shellDestination,
        shellIndex: 2,
        shortcutLabel: 'Ctrl/Cmd+3',
        shortcutSignature: 'primary+3',
      ),
      const P5CommandDefinition(
        id: 'experience.home',
        label: 'Experience: Home / Chat',
        description: 'Open the task composer and run controls.',
        keywords: <String>['home', 'composer', 'task'],
        actionKind: P5CommandActionKind.experienceWorkspace,
        workspace: P5WorkspaceId.homeChat,
        shortcutLabel: 'Alt+1',
        shortcutSignature: 'alt+1',
      ),
      const P5CommandDefinition(
        id: 'experience.projects',
        label: 'Experience: Projects',
        description: 'Open governed project context.',
        keywords: <String>['project', 'workspace'],
        actionKind: P5CommandActionKind.experienceWorkspace,
        workspace: P5WorkspaceId.projects,
        shortcutLabel: 'Alt+2',
        shortcutSignature: 'alt+2',
      ),
      const P5CommandDefinition(
        id: 'experience.runs',
        label: 'Experience: Runs / Activity',
        description: 'Open saved runs and the unified activity timeline.',
        keywords: <String>['runs', 'activity', 'timeline'],
        actionKind: P5CommandActionKind.experienceWorkspace,
        workspace: P5WorkspaceId.runsActivity,
        shortcutLabel: 'Alt+3',
        shortcutSignature: 'alt+3',
      ),
      const P5CommandDefinition(
        id: 'experience.verification',
        label: 'Experience: Verification Center',
        description: 'Open test and verification status.',
        keywords: <String>['verify', 'tests', 'evidence'],
        actionKind: P5CommandActionKind.experienceWorkspace,
        workspace: P5WorkspaceId.verificationCenter,
        shortcutLabel: 'Alt+4',
        shortcutSignature: 'alt+4',
      ),
      const P5CommandDefinition(
        id: 'experience.owner-status',
        label: 'Experience: Owner Mode status',
        description: 'Open the Experience-side Owner Mode status surface.',
        keywords: <String>['owner', 'status'],
        actionKind: P5CommandActionKind.experienceWorkspace,
        workspace: P5WorkspaceId.ownerMode,
        shortcutLabel: 'Alt+5',
        shortcutSignature: 'alt+5',
      ),
      const P5CommandDefinition(
        id: 'experience.settings',
        label: 'Experience: Settings / Diagnostics',
        description: 'Open settings and recovery diagnostics.',
        keywords: <String>['settings', 'doctor', 'diagnostics'],
        actionKind: P5CommandActionKind.experienceWorkspace,
        workspace: P5WorkspaceId.settingsDiagnostics,
        shortcutLabel: 'Alt+6',
        shortcutSignature: 'alt+6',
      ),
      const P5CommandDefinition(
        id: 'experience.evidence',
        label: 'Experience: Evidence',
        description: 'Open saved-run evidence and artifact viewers.',
        keywords: <String>['evidence', 'artifact', 'receipt', 'diff'],
        actionKind: P5CommandActionKind.experienceWorkspace,
        workspace: P5WorkspaceId.evidence,
        shortcutLabel: 'Alt+7',
        shortcutSignature: 'alt+7',
      ),
      const P5CommandDefinition(
        id: 'experience.models',
        label: 'Experience: Models / Providers',
        description: 'Open model and provider status.',
        keywords: <String>['model', 'provider', 'ollama'],
        actionKind: P5CommandActionKind.experienceWorkspace,
        workspace: P5WorkspaceId.modelsProviders,
        shortcutLabel: 'Alt+8',
        shortcutSignature: 'alt+8',
      ),
      const P5CommandDefinition(
        id: 'experience.capabilities',
        label: 'Experience: Capabilities / Integrations',
        description: 'Open capability support and dependency status.',
        keywords: <String>['capability', 'integration', 'support'],
        actionKind: P5CommandActionKind.experienceWorkspace,
        workspace: P5WorkspaceId.capabilitiesIntegrations,
        shortcutLabel: 'Alt+9',
        shortcutSignature: 'alt+9',
      ),
      const P5CommandDefinition(
        id: 'experience.web-studio',
        label: 'Experience: Web Studio',
        description: 'Open the application-owned browser and Web Studio surface.',
        keywords: <String>['browser', 'web', 'studio'],
        actionKind: P5CommandActionKind.experienceWorkspace,
        workspace: P5WorkspaceId.webStudio,
      ),
      const P5CommandDefinition(
        id: 'experience.launch-task',
        label: 'Launch current task',
        description: 'Use the existing Experience composer launch path.',
        keywords: <String>['run', 'start', 'execute', 'composer'],
        actionKind: P5CommandActionKind.launchExperienceTask,
        shortcutLabel: 'Ctrl/Cmd+Enter',
        shortcutSignature: 'primary+enter',
      ),
    ];
    validate(commands);
    return commands;
  }

  static List<P5CommandDefinition> search(
    String query, {
    Iterable<P5CommandDefinition>? commands,
  }) {
    final source = (commands ?? primary).toList(growable: false);
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    if (terms.isEmpty) {
      return source;
    }
    return source
        .where(
          (command) =>
              terms.every((term) => command.searchableText.contains(term)),
        )
        .toList(growable: false);
  }

  static void validate(Iterable<P5CommandDefinition> commands) {
    final ids = <String>{};
    final shortcuts = <String>{};
    for (final command in commands) {
      if (!ids.add(command.id)) {
        throw StateError('p5_command_id_conflict:${command.id}');
      }
      final signature = command.shortcutSignature;
      if (signature != null && signature.isNotEmpty && !shortcuts.add(signature)) {
        throw StateError('p5_command_shortcut_conflict:$signature');
      }
    }
  }
}

class P5OpenCommandPaletteIntent extends Intent {
  const P5OpenCommandPaletteIntent();
}

class P5SelectShellDestinationIntent extends Intent {
  const P5SelectShellDestinationIntent(this.index);

  final int index;
}

class P5CommandPaletteShortcutScope extends StatelessWidget {
  const P5CommandPaletteShortcutScope({
    super.key,
    required this.onOpenPalette,
    required this.onSelectShellDestination,
    required this.child,
  });

  final VoidCallback onOpenPalette;
  final ValueChanged<int> onSelectShellDestination;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            const P5OpenCommandPaletteIntent(),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            const P5OpenCommandPaletteIntent(),
        const SingleActivator(LogicalKeyboardKey.digit1, control: true):
            const P5SelectShellDestinationIntent(0),
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true):
            const P5SelectShellDestinationIntent(0),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true):
            const P5SelectShellDestinationIntent(1),
        const SingleActivator(LogicalKeyboardKey.digit2, meta: true):
            const P5SelectShellDestinationIntent(1),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true):
            const P5SelectShellDestinationIntent(2),
        const SingleActivator(LogicalKeyboardKey.digit3, meta: true):
            const P5SelectShellDestinationIntent(2),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          P5OpenCommandPaletteIntent:
              CallbackAction<P5OpenCommandPaletteIntent>(
            onInvoke: (_) {
              onOpenPalette();
              return null;
            },
          ),
          P5SelectShellDestinationIntent:
              CallbackAction<P5SelectShellDestinationIntent>(
            onInvoke: (intent) {
              onSelectShellDestination(intent.index);
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}

class _P5DismissCommandPaletteIntent extends Intent {
  const _P5DismissCommandPaletteIntent();
}

class P5CommandPaletteDialog extends StatefulWidget {
  const P5CommandPaletteDialog({
    super.key,
    required this.commands,
    required this.onSelected,
  });

  final List<P5CommandDefinition> commands;
  final ValueChanged<P5CommandDefinition> onSelected;

  @override
  State<P5CommandPaletteDialog> createState() => _P5CommandPaletteDialogState();
}

class _P5CommandPaletteDialogState extends State<P5CommandPaletteDialog> {
  final TextEditingController _query = TextEditingController();
  var _filtered = const <P5CommandDefinition>[];

  @override
  void initState() {
    super.initState();
    P5CommandCatalog.validate(widget.commands);
    _filtered = P5CommandCatalog.search('', commands: widget.commands);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _filter(String value) {
    setState(() {
      _filtered = P5CommandCatalog.search(value, commands: widget.commands);
    });
  }

  void _submitFirst() {
    if (_filtered.isNotEmpty) {
      widget.onSelected(_filtered.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape):
            _P5DismissCommandPaletteIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _P5DismissCommandPaletteIntent:
              CallbackAction<_P5DismissCommandPaletteIntent>(
            onInvoke: (_) {
              Navigator.of(context).maybePop();
              return null;
            },
          ),
        },
        child: Dialog(
          key: const Key('p5-command-palette'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 320,
              maxWidth: 640,
              minHeight: 320,
              maxHeight: 520,
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Command palette',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Search commands or shortcuts. Enter runs the first result; Escape closes.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('p5-command-query'),
                    controller: _query,
                    autofocus: true,
                    textInputAction: TextInputAction.go,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search commands',
                    ),
                    onChanged: _filter,
                    onSubmitted: (_) => _submitFirst(),
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '${_filtered.length} commands',
                      key: const Key('p5-command-result-count'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _filtered.isEmpty
                        ? const Center(
                            key: Key('p5-command-empty'),
                            child: Text('No matching commands'),
                          )
                        : ListView.builder(
                            key: const Key('p5-command-results'),
                            itemCount: _filtered.length,
                            itemBuilder: (context, index) {
                              final command = _filtered[index];
                              return ListTile(
                                key: Key('p5-command-${command.id}'),
                                title: Text(command.label),
                                subtitle: Text(command.description),
                                trailing: command.shortcutLabel == null
                                    ? null
                                    : Text(command.shortcutLabel!),
                                onTap: () => widget.onSelected(command),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
''', encoding='utf-8', newline='\n')

ui_path = 'lib/product/ui.dart'
replace_once(
    ui_path,
    "import 'p5_global_autonomy.dart';\nimport 'p5_information_architecture/p5_controller.dart';\n",
    "import 'p5_command_palette.dart';\nimport 'p5_global_autonomy.dart';\nimport 'p5_information_architecture/p5_controller.dart';\n",
)
replace_once(
    ui_path,
    """  @override
  Widget build(BuildContext context) {
    final qaPreview = widget.ownerMode.runtimeProvenance['qaPreview'] == true;
""",
    """  Future<void> _openCommandPalette() async {
    final command = await showDialog<P5CommandDefinition>(
      context: context,
      builder: (dialogContext) => P5CommandPaletteDialog(
        commands: P5CommandCatalog.primary,
        onSelected: (selected) => Navigator.of(dialogContext).pop(selected),
      ),
    );
    if (!mounted || command == null) {
      return;
    }
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

  @override
  Widget build(BuildContext context) {
    final qaPreview = widget.ownerMode.runtimeProvenance['qaPreview'] == true;
""",
)
replace_once(
    ui_path,
    '          P5GlobalAutonomyBar(binding: _autonomyBinding),\n',
    """          P5GlobalAutonomyBar(
            binding: _autonomyBinding,
            onOpenCommands: _openCommandPalette,
          ),
""",
)
replace_once(
    ui_path,
    """    if (!qaPreview) return shell;
    return Banner(
      message: 'OWNER-RISK QA — SECURITY EVIDENCE WAIVED',
      location: BannerLocation.topEnd,
      color: Colors.deepOrange,
      child: shell,
    );
""",
    """    final commandShell = P5CommandPaletteShortcutScope(
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
""",
)

autonomy_path = 'lib/product/p5_global_autonomy.dart'
replace_once(
    autonomy_path,
    """  const P5GlobalAutonomyBar({
    super.key,
    required this.binding,
  });

  final P5GlobalAutonomyBinding binding;
""",
    """  const P5GlobalAutonomyBar({
    super.key,
    required this.binding,
    this.onOpenCommands,
  });

  final P5GlobalAutonomyBinding binding;
  final VoidCallback? onOpenCommands;
""",
)
replace_once(
    autonomy_path,
    """                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: SingleChildScrollView(
                        key: const Key('p5-global-status-scroll'),
""",
    """                child: Row(
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
""",
)

source_contract_path = 'test/product/source_contract_test.dart'
replace_once(
    source_contract_path,
    "        'lib/product/p5_design_tokens.dart',\n        'lib/product/p5_global_autonomy.dart',\n",
    "        'lib/product/p5_command_palette.dart',\n        'lib/product/p5_design_tokens.dart',\n        'lib/product/p5_global_autonomy.dart',\n",
)

test_path = Path('test/product/p5_command_palette_test.dart')
if test_path.exists():
    raise SystemExit(f'{test_path}: refusing to overwrite existing test')
test_path.write_text(r'''import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_command_palette.dart';
import 'package:kristin_local_agent/product/p5_global_autonomy.dart';

class _PaletteBinding extends P5GlobalAutonomyBinding {
  @override
  P5GlobalAutonomySnapshot get snapshot => P5GlobalAutonomySnapshot.initial();

  @override
  Future<void> emergencyKill() async {}

  @override
  Future<void> pauseActiveRuns() async {}

  @override
  void registerBrowserEmergencyStop(Future<void> Function()? stop) {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> stopActiveRuns() async {}

  @override
  void updateBrowserSessionCount(int count) {}
}

void main() {
  test('P5-010 catalog is searchable and shortcut-conflict free', () {
    P5CommandCatalog.validate(P5CommandCatalog.primary);
    expect(P5CommandCatalog.search('owner mode').first.id, 'shell.owner');
    expect(P5CommandCatalog.search('saved runs').first.id, 'experience.runs');
    expect(P5CommandCatalog.search('receipt').first.id, 'experience.evidence');
    expect(P5CommandCatalog.search('Ctrl/Cmd+Enter').single.id,
        'experience.launch-task');
    expect(P5CommandCatalog.search('no-such-command'), isEmpty);
  });

  test('P5-010 rejects duplicate command ids and shortcut signatures', () {
    const duplicateShortcut = <P5CommandDefinition>[
      P5CommandDefinition(
        id: 'one',
        label: 'One',
        description: 'One',
        keywords: <String>[],
        actionKind: P5CommandActionKind.shellDestination,
        shellIndex: 0,
        shortcutSignature: 'primary+1',
      ),
      P5CommandDefinition(
        id: 'two',
        label: 'Two',
        description: 'Two',
        keywords: <String>[],
        actionKind: P5CommandActionKind.shellDestination,
        shellIndex: 1,
        shortcutSignature: 'primary+1',
      ),
    ];
    expect(
      () => P5CommandCatalog.validate(duplicateShortcut),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'p5_command_shortcut_conflict:primary+1',
        ),
      ),
    );

    const duplicateId = <P5CommandDefinition>[
      P5CommandDefinition(
        id: 'same',
        label: 'One',
        description: 'One',
        keywords: <String>[],
        actionKind: P5CommandActionKind.shellDestination,
        shellIndex: 0,
      ),
      P5CommandDefinition(
        id: 'same',
        label: 'Two',
        description: 'Two',
        keywords: <String>[],
        actionKind: P5CommandActionKind.shellDestination,
        shellIndex: 1,
      ),
    ];
    expect(
      () => P5CommandCatalog.validate(duplicateId),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'p5_command_id_conflict:same',
        ),
      ),
    );
  });

  testWidgets('P5-010 palette search launches first result with Enter',
      (tester) async {
    P5CommandDefinition? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: P5CommandPaletteDialog(
            commands: P5CommandCatalog.primary,
            onSelected: (command) => selected = command,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('p5-command-query')),
      'owner mode',
    );
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();

    expect(selected?.id, 'shell.owner');
    expect(find.text('Ctrl/Cmd+3'), findsOneWidget);
  });

  testWidgets('P5-010 global shortcuts open palette and switch shell',
      (tester) async {
    var paletteOpenCount = 0;
    var selectedShell = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: P5CommandPaletteShortcutScope(
          onOpenPalette: () => paletteOpenCount++,
          onSelectShellDestination: (index) => selectedShell = index,
          child: const Focus(
            autofocus: true,
            child: SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(paletteOpenCount, 1);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(selectedShell, 1);
  });

  testWidgets('P5-010 palette is discoverable without hiding autonomy controls',
      (tester) async {
    final binding = _PaletteBinding();
    addTearDown(binding.dispose);
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: P5GlobalAutonomyBar(
            binding: binding,
            onOpenCommands: () => opens++,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('p5-command-palette-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('p5-global-status-scroll')), findsOneWidget);
    expect(find.byKey(const Key('p5-global-emergency')), findsOneWidget);
    await tester.tap(find.byKey(const Key('p5-command-palette-button')));
    expect(opens, 1);
  });
}
''', encoding='utf-8', newline='\n')
