from pathlib import Path

path = Path('lib/product/p5_information_architecture/p5_verification_workspaces.dart')
text = path.read_text(encoding='utf-8')
line = '  Widget _ownerModeWorkspace(BuildContext context) {\n'
old = line + line
count = text.count(old)
if count != 1:
    raise SystemExit(f'expected exactly one duplicated owner-mode declaration, found {count}')
path.write_text(text.replace(old, line, 1), encoding='utf-8', newline='\n')
