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


def replace_tail(path: str, marker: str, replacement: str) -> None:
    text = read(path)
    if text.count(marker) != 1:
        raise SystemExit(f'{path}: expected one tail marker')
    index = text.index(marker)
    write(path, text[:index] + replacement)


def replace_line_containing(path: str, needle: str, replacement: str) -> None:
    text = read(path)
    lines = text.splitlines()
    matches = [index for index, line in enumerate(lines) if needle in line]
    if len(matches) != 1:
        raise SystemExit(
            f'{path}: expected one line containing {needle!r}, found {len(matches)}'
        )
    index = matches[0]
    indent = lines[index][: len(lines[index]) - len(lines[index].lstrip())]
    lines[index] = indent + replacement
    write(path, '\n'.join(lines) + '\n')


layout_path = 'lib/product/p5_information_architecture/p5_shell_layout.dart'
replace_once(
    layout_path,
    "import 'dart:convert';\nimport 'dart:io';\n\nimport 'package:flutter/foundation.dart';\n",
    "import 'dart:convert';\n\nimport 'package:flutter/foundation.dart';\n",
)
replace_tail(
    layout_path,
    'class P5ShellLayoutStore {',
    '''abstract interface class P5ShellLayoutPersistence {
  Future<P5ShellLayoutState?> load();
  Future<void> save(P5ShellLayoutState state);
}
''',
)

prototype_path = 'lib/product/p5_information_architecture/p5_prototype.dart'
replace_once(
    prototype_path,
    "import 'dart:convert';\nimport 'dart:io';\n",
    "import 'dart:convert';\n",
)
replace_once(
    prototype_path,
    '''    this.browserRuntimeProvenance = const <String, Object?>{},
    this.layoutPersistenceRootPath,
    this.onOpenOwnerMode,
''',
    '''    this.browserRuntimeProvenance = const <String, Object?>{},
    this.layoutPersistence,
    this.onOpenOwnerMode,
''',
)
replace_once(
    prototype_path,
    '''  final Map<String, Object?> browserRuntimeProvenance;
  final String? layoutPersistenceRootPath;
  final VoidCallback? onOpenOwnerMode;
''',
    '''  final Map<String, Object?> browserRuntimeProvenance;
  final P5ShellLayoutPersistence? layoutPersistence;
  final VoidCallback? onOpenOwnerMode;
''',
)
replace_once(
    prototype_path,
    '  P5ShellLayoutStore? _shellLayoutStore;\n',
    '  P5ShellLayoutPersistence? _shellLayoutStore;\n',
)
replace_once(
    prototype_path,
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

workspace_path = 'lib/product/p5_information_architecture/p5_shell_workspace.dart'
replace_once(
    workspace_path,
    '''  Future<void> _initializeP5ShellLayout() async {
    final rootPath = widget.layoutPersistenceRootPath;
    if (rootPath == null || rootPath.trim().isEmpty) {
      return;
    }
    final store = P5ShellLayoutStore(applicationDataRoot: Directory(rootPath));
    _shellLayoutStore = store;
''',
    '''  Future<void> _initializeP5ShellLayout() async {
    final store = widget.layoutPersistence;
    if (store == null) {
      return;
    }
    _shellLayoutStore = store;
''',
)

ui_path = 'lib/product/ui.dart'
replace_once(
    ui_path,
    "import 'p5_information_architecture/p5_prototype.dart';\n",
    "import 'p5_information_architecture/p5_prototype.dart';\nimport 'p5_information_architecture/p5_shell_layout.dart';\n",
)
replace_line_containing(
    ui_path,
    'layoutPersistenceRootPath:',
    '''layoutPersistence: productRuntime == null
        ? null
        : P5ApplicationShellLayoutPersistence(
            applicationDataRoot: productRuntime.directories.root,
          ),''',
)

adapter = r'''class P5ApplicationShellLayoutPersistence
    implements P5ShellLayoutPersistence {
  P5ApplicationShellLayoutPersistence({required Directory applicationDataRoot})
      : _root = applicationDataRoot;

  final Directory _root;

  File get file => File(
        '${_root.path}${Platform.pathSeparator}ui'
        '${Platform.pathSeparator}p5-shell-layout.v1.json',
      );

  @override
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

  @override
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
replace_once(ui_path, 'ThemeData _studioTheme(\n', adapter + 'ThemeData _studioTheme(\n')

shell_test = r'''import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_controller.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_models.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_prototype.dart';
import 'package:kristin_local_agent/product/p5_information_architecture/p5_shell_layout.dart';
import 'package:kristin_local_agent/product/ui.dart';

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

  test('P5-004 application file adapter round-trips app-owned state', () async {
    final root = await Directory.systemTemp.createTemp('p5-shell-layout-');
    addTearDown(() => root.delete(recursive: true));
    final store = P5ApplicationShellLayoutPersistence(
      applicationDataRoot: root,
    );
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

print('P5_004_APP_OWNED_PERSISTENCE_POSTPATCH_APPLIED')
