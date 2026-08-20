from pathlib import Path

old_root = Path('test/fixtures/p3_browser')
new_root = Path('test/product/browser/fixtures/p3_browser')
if not old_root.is_dir():
    raise SystemExit('P3 old fixture directory missing')
new_root.mkdir(parents=True, exist_ok=True)
for name in ('index.html', 'fixture.js'):
    source = old_root / name
    if not source.is_file():
        raise SystemExit(f'P3 fixture missing: {name}')
    (new_root / name).write_bytes(source.read_bytes())
    source.unlink()
old_root.rmdir()
parent = old_root.parent
if parent.exists() and not any(parent.iterdir()):
    parent.rmdir()

security = Path('test/product/browser/browser_security_suite_test.dart')
text = security.read_text(encoding='utf-8')
old = 'test/fixtures/p3_browser/'
new = 'test/product/browser/fixtures/p3_browser/'
if text.count(old) != 2:
    raise SystemExit('P3 fixture reference count changed')
security.write_text(text.replace(old, new), encoding='utf-8', newline='\n')
