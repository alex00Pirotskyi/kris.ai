from pathlib import Path

for filename in (
    'lib/product/p5_information_architecture/p5_fixtures.dart',
    'lib/product/p5_information_architecture/p5_task_workspaces.dart',
):
    path = Path(filename)
    text = path.read_text(encoding='utf-8')
    escaped_count = text.count(r'\${')
    if escaped_count == 0:
        raise SystemExit(f'{filename}: expected generated interpolation escapes')
    text = text.replace(r'\${', '${')
    path.write_text(text, encoding='utf-8', newline='\n')

fixtures = Path('lib/product/p5_information_architecture/p5_fixtures.dart')
text = fixtures.read_text(encoding='utf-8')
old = """      throw RangeError.index(visibleIndex, List<int>.filled(visibleCount, 0));\n"""
new = """      throw RangeError.range(visibleIndex, 0, visibleCount - 1, 'visibleIndex');\n"""
count = text.count(old)
if count != 1:
    raise SystemExit(f'expected one timeline range guard, found {count}')
fixtures.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')

print('P5_008_GENERATION_FIX_APPLIED')
