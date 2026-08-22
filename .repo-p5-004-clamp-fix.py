from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one compatibility anchor, found {count}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')


workspace_path = 'lib/product/p5_information_architecture/p5_shell_workspace.dart'
replace_once(
    workspace_path,
    '''                height: layout.activityDrawerHeight.clamp(
                  P5ShellLayoutState.minimumActivityHeight,
                  (constraints.maxHeight * 0.55)
                      .clamp(
                        P5ShellLayoutState.minimumActivityHeight,
                        P5ShellLayoutState.maximumActivityHeight,
                      )
                      .toDouble(),
                ),
''',
    '''                height: layout.activityDrawerHeight
                    .clamp(
                      P5ShellLayoutState.minimumActivityHeight,
                      (constraints.maxHeight * 0.55)
                          .clamp(
                            P5ShellLayoutState.minimumActivityHeight,
                            P5ShellLayoutState.maximumActivityHeight,
                          )
                          .toDouble(),
                    )
                    .toDouble(),
''',
)
replace_once(
    workspace_path,
    '''  const _P5ResizeHandle._({
    super.key,
    required this.axis,
    required this.semanticsLabel,
    required this.onDrag,
  });

''',
    '',
)
replace_once(
    'lib/product/p5_information_architecture/p5_shell_layout.dart',
    "import 'dart:convert';\n\n",
    '',
)
print('P5_004_COMPATIBILITY_ANALYZER_FIXES_APPLIED')
