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
        raise SystemExit(f'{path}: expected one postpatch anchor, found {count}')
    write(path, text.replace(old, new, 1))


replace_once(
    'lib/product/p5_information_architecture/p5_shell_layout.dart',
    '''class P5ShellLayoutStore {
  P5ShellLayoutStore({required Directory applicationDataRoot})
      : _root = applicationDataRoot;

  final Directory _root;
''',
    '''abstract interface class P5ShellLayoutPersistence {
  Future<P5ShellLayoutState?> load();
  Future<void> save(P5ShellLayoutState state);
}

class P5ShellLayoutStore implements P5ShellLayoutPersistence {
  P5ShellLayoutStore({required String applicationDataRootPath})
      : _root = Directory(applicationDataRootPath);

  final Directory _root;
''',
)

replace_once(
    'lib/product/p5_information_architecture/p5_prototype.dart',
    "import 'dart:convert';\nimport 'dart:io';\n",
    "import 'dart:convert';\n",
)

replace_once(
    'lib/product/p5_information_architecture/p5_prototype.dart',
    '''    this.browserRuntimeProvenance = const <String, Object?>{},
    this.layoutPersistenceRootPath,
    this.onOpenOwnerMode,
''',
    '''    this.browserRuntimeProvenance = const <String, Object?>{},
    this.layoutPersistenceRootPath,
    this.layoutPersistence,
    this.onOpenOwnerMode,
''',
)

replace_once(
    'lib/product/p5_information_architecture/p5_prototype.dart',
    '''  final Map<String, Object?> browserRuntimeProvenance;
  final String? layoutPersistenceRootPath;
  final VoidCallback? onOpenOwnerMode;
''',
    '''  final Map<String, Object?> browserRuntimeProvenance;
  final String? layoutPersistenceRootPath;
  final P5ShellLayoutPersistence? layoutPersistence;
  final VoidCallback? onOpenOwnerMode;
''',
)

replace_once(
    'lib/product/p5_information_architecture/p5_prototype.dart',
    '''  P5ShellLayoutStore? _shellLayoutStore;
''',
    '''  P5ShellLayoutPersistence? _shellLayoutStore;
''',
)

replace_once(
    'lib/product/p5_information_architecture/p5_prototype.dart',
    '''      endDrawer: compact
          ? Drawer(
              child: _buildP5Inspector(context, state),
            )
          : null,
''',
    '''      endDrawer: compact
          ? Drawer(
              key: const Key('p5-right-inspector'),
              child: _buildP5Inspector(context, state),
            )
          : null,
''',
)

replace_once(
    'lib/product/p5_information_architecture/p5_shell_workspace.dart',
    '''  Future<void> _initializeP5ShellLayout() async {
    final rootPath = widget.layoutPersistenceRootPath;
    if (rootPath == null || rootPath.trim().isEmpty) {
      return;
    }
    final store = P5ShellLayoutStore(applicationDataRoot: Directory(rootPath));
    _shellLayoutStore = store;
''',
    '''  Future<void> _initializeP5ShellLayout() async {
    final rootPath = widget.layoutPersistenceRootPath;
    final store = widget.layoutPersistence ??
        (rootPath == null || rootPath.trim().isEmpty
            ? null
            : P5ShellLayoutStore(applicationDataRootPath: rootPath));
    if (store == null) {
      return;
    }
    _shellLayoutStore = store;
''',
)

shell_test = r'''import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_prototype.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_shell_layout.dart';

final class _MemoryShellLayoutPersistence
    implements P5ShellLayoutPersistence {
  _MemoryShellLayoutPersistence(this.value);

  P5ShellLayoutState? value;
  int saveCount = 0;

  @override
  Future<P5ShellLayoutState?> load() =>
      SynchronousFuture<P5ShellLayoutState?>(value);

  @override
  Future<void> save(P5ShellLayoutState state) async {
    value = state;
    saveCount += 1;
  }
}

Future<void> pumpShell(
  WidgetTester tester,
  P5InformationArchitectureController controller, {
  Size size = const Size(1440, 960),
  String? persistenceRoot,
  P5ShellLayoutPersistence? persistence,
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
        layoutPersistence: persistence,
      ),
    ),
  );
  await tester.pump();
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
    expect(P5ShellLayoutState.defaults.inspectorOpen, isFalse);
    expect(P5ShellLayoutState.defaults.activityDrawerOpen, isFalse);
  });

  test('P5-004 shell layout file store round-trips app-owned state', () async {
    final root = await Directory.systemTemp.createTemp('p5-shell-layout-');
    addTearDown(() => root.delete(recursive: true));
    final store = P5ShellLayoutStore(applicationDataRootPath: root.path);
    final state = P5ShellLayoutState.defaults.copyWith(
      leftRailWidth: 334,
      inspectorWidth: 377,
      activityDrawerHeight: 281,
      inspectorOpen: true,
      activityDrawerOpen: true,
    );
    expect(await store.load(), isNull);
    await store.save(state);
    expect((await store.load())?.toJson(), state.toJson());
    expect(await store.file.readAsString(), endsWith('\n'));
  });

  testWidgets('P5-004 wide shell resizes and persists across navigation',
      (tester) async {
    final persistence = _MemoryShellLayoutPersistence(null);
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, persistence: persistence);

    expect(find.byKey(const Key('p5-left-rail')), findsOneWidget);
    expect(find.byKey(const Key('p5-center-workspace')), findsOneWidget);
    expect(find.byKey(const Key('p5-right-inspector')), findsNothing);
    expect(find.byKey(const Key('p5-activity-drawer')), findsNothing);

    await tester.tap(find.byKey(const Key('p5-inspector-toggle')));
    await tester.pump();
    final inspector = find.byKey(const Key('p5-right-inspector'));
    expect(inspector, findsOneWidget);
    final originalInspector = tester.getSize(inspector).width;
    await tester.drag(
      find.byKey(const Key('p5-inspector-resize-handle')),
      const Offset(-60, 0),
    );
    await tester.pump();
    final resizedInspector = tester.getSize(inspector).width;
    expect(resizedInspector, greaterThan(originalInspector));

    await tester.tap(find.byKey(const Key('p5-activity-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('p5-activity-drawer')), findsOneWidget);
    expect(find.byKey(const Key('p5-activity-resize-handle')), findsOneWidget);

    final rail = find.byKey(const Key('p5-left-rail'));
    final originalRail = tester.getSize(rail).width;
    await tester.drag(
      find.byKey(const Key('p5-left-resize-handle')),
      const Offset(72, 0),
    );
    await tester.pump();
    final resizedRail = tester.getSize(rail).width;
    expect(resizedRail, greaterThan(originalRail));

    controller.selectWorkspace(P5WorkspaceId.projects);
    await tester.pump();
    expect(tester.getSize(rail).width, resizedRail);
    expect(tester.getSize(inspector).width, resizedInspector);
    expect(controller.shellLayout.inspectorOpen, isTrue);
    expect(controller.shellLayout.activityDrawerOpen, isTrue);

    await tester.pump(const Duration(milliseconds: 180));
    await tester.pump();
    expect(persistence.saveCount, greaterThan(0));
    expect(persistence.value?.toJson(), controller.shellLayout.toJson());
    expect(tester.takeException(), isNull);
  });

  testWidgets('P5-004 persisted layout restores through persistence contract',
      (tester) async {
    final expected = P5ShellLayoutState.defaults.copyWith(
      leftRailWidth: 340,
      inspectorWidth: 390,
      activityDrawerHeight: 250,
      inspectorOpen: true,
      activityDrawerOpen: true,
    );
    final persistence = _MemoryShellLayoutPersistence(expected);
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);

    await pumpShell(tester, controller, persistence: persistence);

    expect(controller.state.recoveryMessage, isNull);
    expect(controller.shellLayout.toJson(), expected.toJson());
    expect(
      tester.getSize(find.byKey(const Key('p5-left-rail'))).width,
      expected.leftRailWidth,
    );
    expect(
      tester.getSize(find.byKey(const Key('p5-right-inspector'))).width,
      expected.inspectorWidth,
    );
    expect(
      tester.getSize(find.byKey(const Key('p5-activity-drawer'))).height,
      expected.activityDrawerHeight,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('P5-004 activity drawer toggles without losing workspace state',
      (tester) async {
    final controller = P5InformationArchitectureController()
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..selectWorkspace(P5WorkspaceId.verificationCenter);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.byKey(const Key('p5-activity-drawer')), findsNothing);
    await tester.tap(find.byKey(const Key('p5-activity-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('p5-activity-drawer')), findsOneWidget);
    expect(controller.state.workspace, P5WorkspaceId.verificationCenter);

    await tester.tap(find.byKey(const Key('p5-activity-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('p5-activity-drawer')), findsNothing);
    expect(controller.state.workspace, P5WorkspaceId.verificationCenter);
  });

  testWidgets('P5-004 compact shell preserves center and drawer access',
      (tester) async {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, size: const Size(860, 640));

    expect(find.byKey(const Key('p5-left-rail')), findsNothing);
    expect(find.byKey(const Key('p5-center-workspace')), findsOneWidget);
    expect(find.byKey(const Key('p5-right-inspector')), findsNothing);
    expect(find.byKey(const Key('p5-activity-drawer')), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('p5-activity-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('p5-activity-drawer')), findsOneWidget);
    await tester.tap(find.byKey(const Key('p5-activity-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('p5-activity-drawer')), findsNothing);

    await tester.tap(find.byKey(const Key('p5-inspector-toggle')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('p5-right-inspector')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
'''

write(
    'test/product/p5_information_architecture/p5_shell_layout_test.dart',
    shell_test,
)

print('P5_004_PERSISTENCE_BOUNDARY_POSTPATCH_APPLIED')
