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
    '''  static const P5ShellLayoutState defaults = P5ShellLayoutState(
    leftRailWidth: 276,
    inspectorWidth: 320,
    activityDrawerHeight: 220,
    inspectorOpen: true,
    activityDrawerOpen: true,
  );
''',
    '''  static const P5ShellLayoutState defaults = P5ShellLayoutState(
    leftRailWidth: 276,
    inspectorWidth: 320,
    activityDrawerHeight: 220,
    inspectorOpen: true,
    activityDrawerOpen: false,
  );
''',
)

replace_once(
    'lib/product/p5_information_architecture/p5_shell_layout.dart',
    '''class P5ShellLayoutStore {
  P5ShellLayoutStore({required Directory applicationDataRoot})
      : _root = applicationDataRoot;

  final Directory _root;
''',
    '''class P5ShellLayoutStore {
  P5ShellLayoutStore({required String applicationDataRootPath})
      : _root = Directory(applicationDataRootPath);

  final Directory _root;
''',
)

replace_once(
    'lib/product/p5_information_architecture/p5_shell_workspace.dart',
    '''    final store = P5ShellLayoutStore(applicationDataRoot: Directory(rootPath));
''',
    '''    final store = P5ShellLayoutStore(applicationDataRootPath: rootPath);
''',
)

replace_once(
    'lib/product/p5_information_architecture/p5_prototype.dart',
    "import 'dart:convert';\nimport 'dart:io';\n",
    "import 'dart:convert';\n",
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
  await tester.pump();
  if (persistenceRoot != null) {
    for (var attempt = 0; attempt < 12; attempt += 1) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }
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
    final store = P5ShellLayoutStore(applicationDataRootPath: root.path);
    final state = P5ShellLayoutState.defaults.copyWith(
      leftRailWidth: 334,
      inspectorWidth: 377,
      activityDrawerHeight: 281,
      inspectorOpen: false,
      activityDrawerOpen: true,
    );
    expect(await store.load(), isNull);
    await store.save(state);
    expect(await store.load(), state);
    expect(await store.file.readAsString(), endsWith('\n'));
  });

  testWidgets('P5-004 wide shell exposes resizable persistent regions',
      (tester) async {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.byKey(const Key('p5-left-rail')), findsOneWidget);
    expect(find.byKey(const Key('p5-center-workspace')), findsOneWidget);
    expect(find.byKey(const Key('p5-right-inspector')), findsOneWidget);
    expect(find.byKey(const Key('p5-activity-collapsed')), findsOneWidget);

    final original = tester.getSize(find.byKey(const Key('p5-left-rail'))).width;
    await tester.drag(
      find.byKey(const Key('p5-left-resize-handle')),
      const Offset(72, 0),
    );
    await tester.pump();
    final resized = tester.getSize(find.byKey(const Key('p5-left-rail'))).width;
    expect(resized, greaterThan(original));

    controller.selectWorkspace(P5WorkspaceId.projects);
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const Key('p5-left-rail'))).width,
      resized,
    );

    await tester.tap(find.byKey(const Key('p5-inspector-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('p5-right-inspector')), findsNothing);
  });

  testWidgets('P5-004 persisted shell state restores on initialization',
      (tester) async {
    final root = await Directory.systemTemp.createTemp('p5-shell-restore-');
    addTearDown(() => root.delete(recursive: true));
    final store = P5ShellLayoutStore(applicationDataRootPath: root.path);
    final saved = P5ShellLayoutState.defaults.copyWith(
      leftRailWidth: 334,
      inspectorWidth: 377,
      activityDrawerHeight: 281,
      inspectorOpen: false,
      activityDrawerOpen: false,
    );
    await tester.runAsync(() => store.save(saved));

    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, persistenceRoot: root.path);

    expect(controller.shellLayout.leftRailWidth, saved.leftRailWidth);
    expect(controller.shellLayout.inspectorWidth, saved.inspectorWidth);
    expect(controller.shellLayout.inspectorOpen, isFalse);
    expect(find.byKey(const Key('p5-right-inspector')), findsNothing);
  });

  testWidgets('P5-004 activity drawer collapses without losing workspace state',
      (tester) async {
    final controller = P5InformationArchitectureController(
      initialShellLayout:
          P5ShellLayoutState.defaults.copyWith(activityDrawerOpen: true),
    )
      ..changeExperienceLevel(P5ExperienceLevel.advanced)
      ..selectWorkspace(P5WorkspaceId.verificationCenter);
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

    expect(find.byKey(const Key('p5-activity-drawer')), findsOneWidget);
    await tester.tap(find.byKey(const Key('p5-activity-toggle')));
    await tester.pump();
    expect(find.byKey(const Key('p5-activity-drawer')), findsNothing);
    expect(find.byKey(const Key('p5-activity-collapsed')), findsOneWidget);
    expect(controller.state.workspace, P5WorkspaceId.verificationCenter);

    await tester.tap(find.byKey(const Key('p5-activity-collapsed')));
    await tester.pump();
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
    expect(find.byKey(const Key('p5-activity-collapsed')), findsOneWidget);
    expect(tester.takeException(), isNull);

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

print('P5_004_POSTPATCH_APPLIED')
