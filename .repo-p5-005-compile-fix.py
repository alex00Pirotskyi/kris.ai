from pathlib import Path

path = Path('lib/product/p5_global_autonomy.dart')
text = path.read_text(encoding='utf-8')
old = "    if (error is ProductException) return error.code;\n"
if text.count(old) != 1:
    raise SystemExit(f'expected one ProductException branch, found {text.count(old)}')
path.write_text(text.replace(old, '', 1), encoding='utf-8', newline='\n')
print('P5_005_COMPILE_FIX_APPLIED')
