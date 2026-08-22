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

replace_once(
    'test/product/p5_information_architecture/p5_shell_layout_test.dart',
    'P5ShellLayoutStore(applicationDataRoot: root)',
    'P5ShellLayoutStore(applicationDataRootPath: root.path)',
)
replace_once(
    'test/product/p5_information_architecture/p5_shell_layout_test.dart',
    'P5ShellLayoutStore(applicationDataRoot: root)',
    'P5ShellLayoutStore(applicationDataRootPath: root.path)',
)

print('P5_004_BOUNDARY_COMPACT_POSTPATCH_APPLIED')
