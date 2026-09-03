import 'package:flutter/material.dart';
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
        description:
            'Open the application-owned browser and Web Studio surface.',
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
      if (signature != null &&
          signature.isNotEmpty &&
          !shortcuts.add(signature)) {
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
