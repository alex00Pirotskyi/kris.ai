from pathlib import Path

path = Path('.repo-hf-runner-hardening.py')
text = path.read_text(encoding='utf-8')
old = '''    count = text.count(old)\n    if count != 1:\n        raise SystemExit(f"anchor mismatch {path}: expected 1, got {count}: {old[:120]!r}")\n    file.write_text(text.replace(old, new, 1), encoding="utf-8")\n'''
new = '''    count = text.count(old)\n    managed_process_spawn = (\n        path == "lib/product/workspace_tools.dart"\n        and old.startswith("    final process = await Process.start(\\n")\n        and count == 2\n    )\n    if count != 1 and not managed_process_spawn:\n        raise SystemExit(f"anchor mismatch {path}: expected 1, got {count}: {old[:120]!r}")\n    file.write_text(text.replace(old, new, 1), encoding="utf-8")\n'''
if text.count(old) != 1:
    raise SystemExit(f'hardening helper anchor mismatch: {text.count(old)}')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
