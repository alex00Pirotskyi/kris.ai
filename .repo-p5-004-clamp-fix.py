from pathlib import Path

path = Path('lib/product/p5_information_architecture/p5_shell_workspace.dart')
text = path.read_text(encoding='utf-8')
old = '''                height: layout.activityDrawerHeight.clamp(
                  P5ShellLayoutState.minimumActivityHeight,
                  (constraints.maxHeight * 0.55)
                      .clamp(
                        P5ShellLayoutState.minimumActivityHeight,
                        P5ShellLayoutState.maximumActivityHeight,
                      )
                      .toDouble(),
                ),
'''
new = '''                height: layout.activityDrawerHeight
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
'''
count = text.count(old)
if count != 1:
    raise SystemExit(f'expected one activity drawer clamp anchor, found {count}')
path.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')
print('P5_004_ACTIVITY_CLAMP_FIXED')
