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


def replace_span(path: str, start_marker: str, end_marker: str, replacement: str) -> None:
    text = read(path)
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f'{path}: start marker not found')
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f'{path}: end marker not found')
    write(path, text[:start] + replacement + text[end:])


shell_layout = r'''import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

@immutable
class P5ShellLayoutState {
  const P5ShellLayoutState({
    required this.leftRailWidth,
    required this.inspectorWidth,
    required this.activityDrawerHeight,
    required this.inspectorOpen,
    required this.activityDrawerOpen,
  });

  static const double minimumThreePaneWidth = 1180;
  static const double minimumLeftRailWidth = 220;
  static const double maximumLeftRailWidth = 360;
  static const double minimumInspectorWidth = 260;
  static const double maximumInspectorWidth = 420;
  static const double minimumActivityHeight = 140;
  static const double maximumActivityHeight = 360;

  static const P5ShellLayoutState defaults = P5ShellLayoutState(
    leftRailWidth: 276,
    inspectorWidth: 320,
    activityDrawerHeight: 220,
    inspectorOpen: true,
    activityDrawerOpen: true,
  );

  final double leftRailWidth;
  final double inspectorWidth;
  final double activityDrawerHeight;
  final bool inspectorOpen;
  final bool activityDrawerOpen;

  P5ShellLayoutState copyWith({
    double? leftRailWidth,
    double? inspectorWidth,
    double? activityDrawerHeight,
    bool? inspectorOpen,
    bool? activityDrawerOpen,
  }) {
    return P5ShellLayoutState(
      leftRailWidth: leftRailWidth ?? this.leftRailWidth,
      inspectorWidth: inspectorWidth ?? this.inspectorWidth,
      activityDrawerHeight: activityDrawerHeight ?? this.activityDrawerHeight,
      inspectorOpen: inspectorOpen ?? this.inspectorOpen,
      activityDrawerOpen: activityDrawerOpen ?? this.activityDrawerOpen,
    ).normalized();
  }

  P5ShellLayoutState normalized() {
    return P5ShellLayoutState(
      leftRailWidth: leftRailWidth
          .clamp(minimumLeftRailWidth, maximumLeftRailWidth)
          .toDouble(),
      inspectorWidth: inspectorWidth
          .clamp(minimumInspectorWidth, maximumInspectorWidth)
          .toDouble(),
      activityDrawerHeight: activityDrawerHeight
          .clamp(minimumActivityHeight, maximumActivityHeight)
          .toDouble(),
      inspectorOpen: inspectorOpen,
      activityDrawerOpen: activityDrawerOpen,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': 1,
        'leftRailWidth': leftRailWidth,
        'inspectorWidth': inspectorWidth,
        'activityDrawerHeight': activityDrawerHeight,
        'inspectorOpen': inspectorOpen,
        'activityDrawerOpen': activityDrawerOpen,
      };

  static P5ShellLayoutState fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('P5 shell layout must be an object.');
    }
    final json = value.map((key, item) => MapEntry(key.toString(), item));
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported P5 shell layout schema.');
    }
    double finiteNumber(String key) {
      final raw = json[key];
      if (raw is! num || !raw.isFinite) {
        throw FormatException('P5 shell layout $key must be finite.');
      }
      return raw.toDouble();
    }

    bool boolean(String key) {
      final raw = json[key];
      if (raw is! bool) {
        throw FormatException('P5 shell layout $key must be boolean.');
      }
      return raw;
    }

    return P5ShellLayoutState(
      leftRailWidth: finiteNumber('leftRailWidth'),
      inspectorWidth: finiteNumber('inspectorWidth'),
      activityDrawerHeight: finiteNumber('activityDrawerHeight'),
      inspectorOpen: boolean('inspectorOpen'),
      activityDrawerOpen: boolean('activityDrawerOpen'),
    ).normalized();
  }

  @override
  bool operator ==(Object other) =>
      other is P5ShellLayoutState &&
      other.leftRailWidth == leftRailWidth &&
      other.inspectorWidth == inspectorWidth &&
      other.activityDrawerHeight == activityDrawerHeight &&
      other.inspectorOpen == inspectorOpen &&
      other.activityDrawerOpen == activityDrawerOpen;

  @override
  int get hashCode => Object.hash(
        leftRailWidth,
        inspectorWidth,
        activityDrawerHeight,
        inspectorOpen,
        activityDrawerOpen,
      );
}

class P5ShellLayoutStore {
  P5ShellLayoutStore({required Directory applicationDataRoot})
      : _root = applicationDataRoot;

  final Directory _root;

  File get file => File(
        '${_root.path}${Platform.pathSeparator}ui'
        '${Platform.pathSeparator}p5-shell-layout.v1.json',
      );

  Future<P5ShellLayoutState?> load() async {
    final target = file;
    final type = await FileSystemEntity.type(target.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return null;
    }
    if (type != FileSystemEntityType.file) {
      throw const FileSystemException(
        'P5 shell layout path is not a regular file.',
      );
    }
    final decoded = jsonDecode(await target.readAsString());
    return P5ShellLayoutState.fromJson(decoded);
  }

  Future<void> save(P5ShellLayoutState state) async {
    final target = file;
    final directory = target.parent;
    await directory.create(recursive: true);
    final directoryType =
        await FileSystemEntity.type(directory.path, followLinks: false);
    if (directoryType != FileSystemEntityType.directory) {
      throw const FileSystemException(
        'P5 shell layout directory is not a regular directory.',
      );
    }
    final targetType =
        await FileSystemEntity.type(target.path, followLinks: false);
    if (targetType != FileSystemEntityType.notFound &&
        targetType != FileSystemEntityType.file) {
      throw const FileSystemException(
        'P5 shell layout target is not a regular file.',
      );
    }
    final temporary = File('${target.path}.tmp');
    final temporaryType =
        await FileSystemEntity.type(temporary.path, followLinks: false);
    if (temporaryType != FileSystemEntityType.notFound) {
      await temporary.delete(recursive: true);
    }
    final encoded = const JsonEncoder.withIndent('  ').convert(state.toJson());
    await temporary.writeAsString('$encoded\n', flush: true);
    if (await target.exists()) {
      await target.delete();
    }
    await temporary.rename(target.path);
  }
}
'''

shell_workspace = r'''part of 'p5_prototype.dart';

extension _P5ShellWorkspace on _P5InformationArchitecturePrototypeState {
  Future<void> _initializeP5ShellLayout() async {
    final rootPath = widget.layoutPersistenceRootPath;
    if (rootPath == null || rootPath.trim().isEmpty) {
      return;
    }
    final store = P5ShellLayoutStore(applicationDataRoot: Directory(rootPath));
    _shellLayoutStore = store;
    try {
      final restored = await store.load();
      if (!mounted || restored == null) {
        return;
      }
      controller.updateShellLayout(restored);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      controller.showRecoveryMessage(
        'Saved workspace layout could not be restored: $error',
      );
    }
  }

  void _scheduleP5ShellLayoutSave() {
    final store = _shellLayoutStore;
    if (store == null) {
      return;
    }
    _shellLayoutSaveDebounce?.cancel();
    _shellLayoutSaveDebounce = Timer(const Duration(milliseconds: 140), () {
      unawaited(
        store.save(controller.shellLayout).catchError((Object error) {
          if (mounted) {
            controller.showRecoveryMessage(
              'Workspace layout could not be saved: $error',
            );
          }
        }),
      );
    });
  }

  void _updateP5ShellLayout(P5ShellLayoutState next) {
    controller.updateShellLayout(next);
    _scheduleP5ShellLayoutSave();
  }

  Widget _buildP5ThreePaneBody(
    BuildContext context, {
    required bool compact,
    required P5PresentationState state,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = controller.shellLayout.normalized();
        final center = Column(
          key: const Key('p5-center-workspace'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _contextBar(context),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey<String>(
                  'workspace-content-${state.workspace.name}',
                ),
                child: _workspace(context, state.workspace),
              ),
            ),
          ],
        );
        final centerAndInspector = compact
            ? center
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    key: const Key('p5-left-rail'),
                    width: layout.leftRailWidth,
                    child: Material(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: SafeArea(
                        top: false,
                        child: _navigation(context),
                      ),
                    ),
                  ),
                  _P5ResizeHandle.vertical(
                    key: const Key('p5-left-resize-handle'),
                    semanticsLabel: 'Resize navigation rail',
                    onDrag: (delta) => _updateP5ShellLayout(
                      layout.copyWith(
                        leftRailWidth: layout.leftRailWidth + delta,
                      ),
                    ),
                  ),
                  Expanded(child: center),
                  if (layout.inspectorOpen) ...<Widget>[
                    _P5ResizeHandle.vertical(
                      key: const Key('p5-inspector-resize-handle'),
                      semanticsLabel: 'Resize inspector',
                      onDrag: (delta) => _updateP5ShellLayout(
                        layout.copyWith(
                          inspectorWidth: layout.inspectorWidth - delta,
                        ),
                      ),
                    ),
                    SizedBox(
                      key: const Key('p5-right-inspector'),
                      width: layout.inspectorWidth,
                      child: _buildP5Inspector(context, state),
                    ),
                  ],
                ],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: centerAndInspector),
            if (layout.activityDrawerOpen) ...<Widget>[
              _P5ResizeHandle.horizontal(
                key: const Key('p5-activity-resize-handle'),
                semanticsLabel: 'Resize activity drawer',
                onDrag: (delta) {
                  final maximum = (constraints.maxHeight * 0.55)
                      .clamp(
                        P5ShellLayoutState.minimumActivityHeight,
                        P5ShellLayoutState.maximumActivityHeight,
                      )
                      .toDouble();
                  _updateP5ShellLayout(
                    layout.copyWith(
                      activityDrawerHeight:
                          (layout.activityDrawerHeight - delta)
                              .clamp(
                                P5ShellLayoutState.minimumActivityHeight,
                                maximum,
                              )
                              .toDouble(),
                    ),
                  );
                },
              ),
              SizedBox(
                key: const Key('p5-activity-drawer'),
                height: layout.activityDrawerHeight.clamp(
                  P5ShellLayoutState.minimumActivityHeight,
                  (constraints.maxHeight * 0.55)
                      .clamp(
                        P5ShellLayoutState.minimumActivityHeight,
                        P5ShellLayoutState.maximumActivityHeight,
                      )
                      .toDouble(),
                ),
                child: _buildP5ActivityDrawer(context, state),
              ),
            ] else
              _buildP5CollapsedActivityBar(context, state),
          ],
        );
      },
    );
  }

  Widget _buildP5Inspector(BuildContext context, P5PresentationState state) {
    final project = P5PrototypeFixtures.projects
        .where((item) => item.id == state.selectedProjectId)
        .firstOrNull;
    final run = P5PrototypeFixtures.runs
        .where((item) => item.id == state.selectedRunId)
        .firstOrNull;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: SafeArea(
        top: false,
        child: ListView(
          key: const Key('p5-inspector-scroll'),
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.tune_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Inspector',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DomainCard(
              title: 'Workspace',
              value: state.workspace.label,
              detail: state.workspaceStates[state.workspace]?.label ?? 'READY',
              icon: _workspaceIcon(state.workspace),
            ),
            _DomainCard(
              title: 'Project',
              value: project?.name ?? 'No project',
              detail: project?.pathLabel ?? 'Choose a project to bind context.',
              icon: Icons.folder_outlined,
            ),
            _DomainCard(
              title: 'Run',
              value: run?.title ?? state.selectedRunId ?? 'No saved run',
              detail: state.runState.label,
              icon: Icons.play_circle_outline,
            ),
            _DomainCard(
              title: 'Owner Mode',
              value: _liveOwnerLabel,
              detail: 'Authority is unchanged by the Experience shell.',
              icon: Icons.admin_panel_settings_outlined,
            ),
            _DomainCard(
              title: 'Browser runtime',
              value: widget.browserRuntimeAvailable ? 'Available' : 'Unavailable',
              detail: widget.browserRuntimeStatusCode,
              icon: Icons.web_outlined,
            ),
            if (state.recoveryMessage != null) ...<Widget>[
              const SizedBox(height: 8),
              _BoundaryNotice(message: state.recoveryMessage!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildP5ActivityDrawer(
    BuildContext context,
    P5PresentationState state,
  ) {
    final runtimeActivity = _webActivity.reversed.take(8).toList(growable: false);
    final rows = <String>[
      'Workspace: ${state.workspace.label}',
      'Run state: ${state.runState.label}',
      if (state.recoveryMessage != null) 'Notice: ${state.recoveryMessage}',
      ...runtimeActivity.map((entry) => 'Browser: $entry'),
    ];
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _P5ActivityHeader(
            title: 'Activity',
            subtitle: runtimeActivity.isEmpty
                ? 'Live presentation state — no fabricated saved timeline'
                : '${runtimeActivity.length} recent browser runtime events',
            onToggle: () => _updateP5ShellLayout(
              controller.shellLayout.copyWith(activityDrawerOpen: false),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              key: const Key('p5-activity-list'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              itemCount: rows.length,
              itemBuilder: (context, index) => ListTile(
                dense: true,
                leading: const Icon(Icons.circle, size: 8),
                title: Text(rows[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildP5CollapsedActivityBar(
    BuildContext context,
    P5PresentationState state,
  ) {
    return Material(
      key: const Key('p5-activity-collapsed'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: () => _updateP5ShellLayout(
          controller.shellLayout.copyWith(activityDrawerOpen: true),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: <Widget>[
              const Icon(Icons.keyboard_arrow_up),
              const SizedBox(width: 8),
              const Text('Activity'),
              const Spacer(),
              Text(state.runState.label),
            ],
          ),
        ),
      ),
    );
  }
}

class _P5ResizeHandle extends StatelessWidget {
  const _P5ResizeHandle._({
    super.key,
    required this.axis,
    required this.semanticsLabel,
    required this.onDrag,
  });

  const _P5ResizeHandle.vertical({
    super.key,
    required this.semanticsLabel,
    required this.onDrag,
  }) : axis = Axis.vertical;

  const _P5ResizeHandle.horizontal({
    super.key,
    required this.semanticsLabel,
    required this.onDrag,
  }) : axis = Axis.horizontal;

  final Axis axis;
  final String semanticsLabel;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final vertical = axis == Axis.vertical;
    return Semantics(
      label: semanticsLabel,
      child: MouseRegion(
        cursor: vertical
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.resizeRow,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate:
              vertical ? (details) => onDrag(details.delta.dx) : null,
          onVerticalDragUpdate:
              vertical ? null : (details) => onDrag(details.delta.dy),
          child: SizedBox(
            width: vertical ? 8 : double.infinity,
            height: vertical ? double.infinity : 8,
            child: Center(
              child: Container(
                width: vertical ? 1 : 36,
                height: vertical ? 36 : 1,
                color: Theme.of(context).dividerColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _P5ActivityHeader extends StatelessWidget {
  const _P5ActivityHeader({
    required this.title,
    required this.subtitle,
    required this.onToggle,
  });

  final String title;
  final String subtitle;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: <Widget>[
          const Icon(Icons.timeline_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            key: const Key('p5-activity-collapse-button'),
            tooltip: 'Collapse activity drawer',
            onPressed: onToggle,
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
        ],
      ),
    );
  }
}
'''

shell_test = r'''import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_prototype.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_shell_layout.dart';

Future<void> pumpShell(
  WidgetTester tester,
  P5InformationArchitectureController controller, {
  Size size = const Size(1440, 960),
  String? persistenceRoot,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: P5InformationArchitecturePrototype(
        controller: controller,
        layoutPersistenceRootPath: persistenceRoot,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('P5-004 shell layout snapshot is bounded and serializable', () {
    final state = P5ShellLayoutState.fromJson(<String, Object?>{
      'schemaVersion': 1,
      'leftRailWidth': 9999,
      'inspectorWidth': -1,
      'activityDrawerHeight': 9999,
      'inspectorOpen': false,
      'activityDrawerOpen': true,
    });
    expect(state.leftRailWidth, P5ShellLayoutState.maximumLeftRailWidth);
    expect(state.inspectorWidth, P5ShellLayoutState.minimumInspectorWidth);
    expect(
      state.activityDrawerHeight,
      P5ShellLayoutState.maximumActivityHeight,
    );
    expect(P5ShellLayoutState.fromJson(state.toJson()), state);
  });

  test('P5-004 shell layout store round-trips app-owned state', () async {
    final root = await Directory.systemTemp.createTemp('p5-shell-layout-');
    addTearDown(() => root.delete(recursive: true));
    final store = P5ShellLayoutStore(applicationDataRoot: root);
    final state = P5ShellLayoutState.defaults.copyWith(
      leftRailWidth: 334,
      inspectorWidth: 377,
      activityDrawerHeight: 281,
      inspectorOpen: false,
    );
    expect(await store.load(), isNull);
    await store.save(state);
    expect(await store.load(), state);
    expect(await store.file.readAsString(), endsWith('\n'));
  });

  testWidgets('P5-004 wide shell exposes four resizable regions and persists',
      (tester) async {
    final root = await Directory.systemTemp.createTemp('p5-shell-widget-');
    addTearDown(() => root.delete(recursive: true));
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, persistenceRoot: root.path);

    expect(find.byKey(const Key('p5-left-rail')), findsOneWidget);
    expect(find.byKey(const Key('p5-center-workspace')), findsOneWidget);
    expect(find.byKey(const Key('p5-right-inspector')), findsOneWidget);
    expect(find.byKey(const Key('p5-activity-drawer')), findsOneWidget);

    final original = tester.getSize(find.byKey(const Key('p5-left-rail'))).width;
    await tester.drag(
      find.byKey(const Key('p5-left-resize-handle')),
      const Offset(72, 0),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 220));
    final resized = tester.getSize(find.byKey(const Key('p5-left-rail'))).width;
    expect(resized, greaterThan(original));

    controller.selectWorkspace(P5WorkspaceId.projects);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('p5-left-rail'))).width,
      resized,
    );

    await tester.tap(find.byKey(const Key('p5-inspector-toggle')));
    await tester.pumpAndSettle(const Duration(milliseconds: 220));
    expect(find.byKey(const Key('p5-right-inspector')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle(const Duration(milliseconds: 220));

    final restoredController = P5InformationArchitectureController();
    addTearDown(restoredController.dispose);
    await pumpShell(
      tester,
      restoredController,
      persistenceRoot: root.path,
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 220));
    expect(restoredController.shellLayout.leftRailWidth, resized);
    expect(restoredController.shellLayout.inspectorOpen, isFalse);
  });

  testWidgets('P5-004 activity drawer collapses without losing workspace state',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..selectWorkspace(P5WorkspaceId.verificationCenter);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.byKey(const Key('p5-activity-drawer')), findsOneWidget);
    await tester.tap(find.byKey(const Key('p5-activity-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('p5-activity-drawer')), findsNothing);
    expect(find.byKey(const Key('p5-activity-collapsed')), findsOneWidget);
    expect(controller.state.workspace, P5WorkspaceId.verificationCenter);

    await tester.tap(find.byKey(const Key('p5-activity-collapsed')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('p5-activity-drawer')), findsOneWidget);
  });

  testWidgets('P5-004 compact shell preserves center and inspector access',
      (tester) async {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(860, 640));

    expect(find.byKey(const Key('p5-left-rail')), findsNothing);
    expect(find.byKey(const Key('p5-center-workspace')), findsOneWidget);
    expect(find.byKey(const Key('p5-right-inspector')), findsNothing);
    expect(find.byKey(const Key('p5-activity-drawer')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('p5-inspector-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('p5-right-inspector')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
'''

write('lib/product/p5_information_architecture/p5_shell_layout.dart', shell_layout)
write('lib/product/p5_information_architecture/p5_shell_workspace.dart', shell_workspace)
write(
    'test/product/p5_information_architecture/p5_shell_layout_test.dart',
    shell_test,
)

replace_once(
    'lib/product/p5_information_architecture/p5_controller.dart',
    "import 'p5_models.dart';\n",
    "import 'p5_models.dart';\nimport 'p5_shell_layout.dart';\n",
)
replace_once(
    'lib/product/p5_information_architecture/p5_controller.dart',
    """class P5InformationArchitectureController extends ChangeNotifier {
  P5InformationArchitectureController({P5PresentationState? initialState})
      : _state = initialState ?? P5PrototypeFixtures.initialState();

  P5PresentationState _state;
  P5PresentationState get state => _state;
""",
    """class P5InformationArchitectureController extends ChangeNotifier {
  P5InformationArchitectureController({
    P5PresentationState? initialState,
    P5ShellLayoutState? initialShellLayout,
  })  : _state = initialState ?? P5PrototypeFixtures.initialState(),
        _shellLayout = initialShellLayout ?? P5ShellLayoutState.defaults;

  P5PresentationState _state;
  P5ShellLayoutState _shellLayout;
  P5PresentationState get state => _state;
  P5ShellLayoutState get shellLayout => _shellLayout;

  void updateShellLayout(P5ShellLayoutState next) {
    final normalized = next.normalized();
    if (_shellLayout == normalized) {
      return;
    }
    _shellLayout = normalized;
    notifyListeners();
  }
""",
)

replace_once(
    'lib/product/p5_information_architecture/p5_prototype.dart',
    "import 'dart:convert';\n",
    "import 'dart:convert';\nimport 'dart:io';\n",
)
replace_once(
    'lib/product/p5_information_architecture/p5_prototype.dart',
    "import 'p5_models.dart';\n",
    "import 'p5_models.dart';\nimport 'p5_shell_layout.dart';\n",
)
replace_once(
    'lib/product/p5_information_architecture/p5_prototype.dart',
    "part 'p5_components.dart';\n",
    "part 'p5_components.dart';\npart 'p5_shell_workspace.dart';\n",
)
replace_once(
    'lib/product/p5_information_architecture/p5_prototype.dart',
    """    this.browserRuntimeProvenance = const <String, Object?>{},
    this.onOpenOwnerMode,
  });
""",
    """    this.browserRuntimeProvenance = const <String, Object?>{},
    this.layoutPersistenceRootPath,
    this.onOpenOwnerMode,
  });
""",
)
replace_once(
    'lib/product/p5_information_architecture/p5_prototype.dart',
    """  final Map<String, Object?> browserRuntimeProvenance;
  final VoidCallback? onOpenOwnerMode;
""",
    """  final Map<String, Object?> browserRuntimeProvenance;
  final String? layoutPersistenceRootPath;
  final VoidCallback? onOpenOwnerMode;
""",
)
replace_once(
    'lib/product/p5_information_architecture/p5_prototype.dart',
    """  final List<String> _webActivity = <String>[];

  P5InformationArchitectureController get controller => widget.controller;
""",
    """  final List<String> _webActivity = <String>[];
  P5ShellLayoutStore? _shellLayoutStore;
  Timer? _shellLayoutSaveDebounce;

  P5InformationArchitectureController get controller => widget.controller;
""",
)
replace_once(
    'lib/product/p5_information_architecture/p5_prototype.dart',
    """  @override
  void dispose() {
""",
    """  @override
  void initState() {
    super.initState();
    unawaited(_initializeP5ShellLayout());
  }

  @override
  void dispose() {
    _shellLayoutSaveDebounce?.cancel();
""",
)
replace_once(
    'lib/product/p5_information_architecture/p5_prototype.dart',
    """  Widget _buildShell(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 900;
    final state = controller.state;
""",
    """  Widget _buildShell(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <
        P5ShellLayoutState.minimumThreePaneWidth;
    final state = controller.state;
""",
)
replace_once(
    'lib/product/p5_information_architecture/p5_prototype.dart',
    """      drawer: compact
          ? Drawer(
              child: SafeArea(
                child: _navigation(context, closeDrawerAfterSelection: true),
              ),
            )
          : null,
      appBar: AppBar(
""",
    """      drawer: compact
          ? Drawer(
              child: SafeArea(
                child: _navigation(context, closeDrawerAfterSelection: true),
              ),
            )
          : null,
      endDrawer: compact
          ? Drawer(
              child: _buildP5Inspector(context, state),
            )
          : null,
      appBar: AppBar(
""",
)
replace_once(
    'lib/product/p5_information_architecture/p5_prototype.dart',
    """          IconButton(
            key: const Key('history-forward'),
            tooltip: 'Forward (Alt+Right)',
            onPressed: controller.canGoForward ? controller.forward : null,
            icon: const Icon(Icons.arrow_forward),
          ),
          if (!compact) _experienceSelector(context),
""",
    """          IconButton(
            key: const Key('history-forward'),
            tooltip: 'Forward (Alt+Right)',
            onPressed: controller.canGoForward ? controller.forward : null,
            icon: const Icon(Icons.arrow_forward),
          ),
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
                activityDrawerOpen:
                    !controller.shellLayout.activityDrawerOpen,
              ),
            ),
            icon: const Icon(Icons.timeline_outlined),
          ),
          if (!compact) _experienceSelector(context),
""",
)
replace_span(
    'lib/product/p5_information_architecture/p5_prototype.dart',
    '      body: Row(\n',
    '    );\n  }\n\n  Widget _experienceSelector',
    "      body: _buildP5ThreePaneBody(\n        context,\n        compact: compact,\n        state: state,\n      ),\n",
)

replace_once(
    'lib/product/ui.dart',
    """        browserRuntimeProvenance: productRuntime?.p3BrowserRuntime.provenance ??
            const <String, Object?>{},
        browserSessionStarter: productRuntime == null
""",
    """        browserRuntimeProvenance: productRuntime?.p3BrowserRuntime.provenance ??
            const <String, Object?>{},
        layoutPersistenceRootPath: productRuntime?.directories.root.path,
        browserSessionStarter: productRuntime == null
""",
)

replace_once(
    'test/product/source_contract_test.dart',
    """        'lib/product/p5_information_architecture/p5_prototype.dart',
        'lib/product/p5_information_architecture/p5_support_workspaces.dart',
""",
    """        'lib/product/p5_information_architecture/p5_prototype.dart',
        'lib/product/p5_information_architecture/p5_shell_layout.dart',
        'lib/product/p5_information_architecture/p5_shell_workspace.dart',
        'lib/product/p5_information_architecture/p5_support_workspaces.dart',
""",
)

print('P5_004_THREE_PANE_PATCH_APPLIED')
