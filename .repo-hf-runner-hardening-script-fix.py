from pathlib import Path

path = Path('.repo-hf-runner-hardening.py')
text = path.read_text(encoding='utf-8')
old = '''    count = text.count(old)\n    if count != 1:\n        raise SystemExit(f"anchor mismatch {path}: expected 1, got {count}: {old[:120]!r}")\n    file.write_text(text.replace(old, new, 1), encoding="utf-8")\n'''
new = '''    count = text.count(old)\n    managed_process_spawn = (\n        path == "lib/product/workspace_tools.dart"\n        and old.startswith("    final process = await Process.start(\\n")\n        and count == 2\n    )\n    if count != 1 and not managed_process_spawn:\n        raise SystemExit(f"anchor mismatch {path}: expected 1, got {count}: {old[:120]!r}")\n    file.write_text(text.replace(old, new, 1), encoding="utf-8")\n'''
if text.count(old) != 1:
    raise SystemExit(f'hardening helper anchor mismatch: {text.count(old)}')
text = text.replace(old, new, 1)

docs_old = '''"""- High-frequency model/tool presentation uses `LiveRunSignalBus`; durable transitions, receipts, and applied steering stay in `EventJournal`.\\n""",'''
docs_new = '''"""High-frequency model text and tool activity use `LiveRunSignalBus`. Durable state transitions, readiness receipts, work items, tools, evidence, verification, retries, and steering application remain in the event journal.\\n""",'''
if text.count(docs_old) != 1:
    raise SystemExit(f'hardening docs anchor mismatch: {text.count(docs_old)}')
text = text.replace(docs_old, docs_new, 1)
path.write_text(text, encoding='utf-8')
