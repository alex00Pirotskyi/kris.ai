from pathlib import Path

ROOT = Path('.')


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding='utf-8', newline='\n')


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}')
    write(path, text.replace(old, new, 1))


layout_path = 'lib/product/p5_information_architecture/p5_shell_layout.dart'
replace_once(
    layout_path,
    '    inspectorOpen: true,\n    activityDrawerOpen: true,\n',
    '    inspectorOpen: false,\n    activityDrawerOpen: false,\n',
)

workspace_path = 'lib/product/p5_information_architecture/p5_shell_workspace.dart'
replace_once(
    workspace_path,
    """            ] else
              _buildP5CollapsedActivityBar(context, state),
""",
    """            ],
""",
)
workspace = read(workspace_path)
start_marker = '  Widget _buildP5CollapsedActivityBar('
end_marker = '\n}\n\nclass _P5ResizeHandle'
start = workspace.find(start_marker)
end = workspace.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit('p5_shell_workspace.dart: collapsed activity bar span not found')
write(workspace_path, workspace[:start] + workspace[end:])

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

  test('P5-004 shell layout store round-trips app-owned state', () async {
    final root = await Directory.systemTemp.createTemp('p5-shell-layout-');
    addTearDown(() => root.delete(recursive: true));
    final store = P5ShellLayoutStore(applicationDataRoot: root);
    final state = P5ShellLayoutState.defaults.copyWith(
      leftRailWidth: 334,
      inspectorWidth: 377,
      activityDrawerHeight: 281,
      inspectorOpen: true,
      activityDrawerOpen: true,
    );
    expect(await store.load(), isNull);
    await store.save(state);
    expect(await store.load(), state);
    expect(await store.file.readAsString(), endsWith('\n'));
  });

  testWidgets('P5-004 wide shell resizes auxiliary panes across navigation',
      (tester) async {
    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller);

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
    expect(tester.takeException(), isNull);
  });

  testWidgets('P5-004 persisted layout restores on reopen', (tester) async {
    final root = await Directory.systemTemp.createTemp('p5-shell-reopen-');
    addTearDown(() => root.delete(recursive: true));
    final expected = P5ShellLayoutState.defaults.copyWith(
      leftRailWidth: 340,
      inspectorWidth: 390,
      activityDrawerHeight: 250,
      inspectorOpen: true,
      activityDrawerOpen: true,
    );
    final store = P5ShellLayoutStore(applicationDataRoot: root);
    await store.save(expected);

    final controller = P5InformationArchitectureController();
    addTearDown(controller.dispose);
    await pumpShell(tester, controller, persistenceRoot: root.path);
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 100; attempt += 1) {
        if (controller.shellLayout == expected) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pump();

    expect(controller.shellLayout, expected);
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
    await tester.pump();
    expect(find.byKey(const Key('p5-right-inspector')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
'''

write(
    'test/product/p5_information_architecture/p5_shell_layout_test.dart',
    shell_test,
)

source_contract_path = 'test/product/source_contract_test.dart'
source_anchor = """    test('release validator follows governed design-token modules', () {
"""
source_test = """    test('P5 shell persists explicit layout mutations without reserving closed panes', () {
      final layout = source(
        'lib/product/p5_information_architecture/p5_shell_layout.dart',
      );
      final shell = source(
        'lib/product/p5_information_architecture/p5_shell_workspace.dart',
      );
      expect(layout, contains('inspectorOpen: false'));
      expect(layout, contains('activityDrawerOpen: false'));
      expect(shell, contains('_scheduleP5ShellLayoutSave();'));
      expect(shell, contains('store.save(controller.shellLayout)'));
      expect(shell, contains("key: const Key('p5-right-inspector')"));
      expect(shell, contains("key: const Key('p5-activity-drawer')"));
    });

"""
replace_once(source_contract_path, source_anchor, source_test + source_anchor)

print('P5_004_LAYOUT_CONTRACT_FIX_APPLIED')
