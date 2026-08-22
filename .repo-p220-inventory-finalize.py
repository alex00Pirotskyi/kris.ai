from pathlib import Path

ROOT = Path('.')
PATH = ROOT / 'test/product/source_contract_test.dart'
text = PATH.read_text(encoding='utf-8')
old = "        'lib/product/browser/browser_profile_store.dart',\n        'lib/product/browser/browser_replay.dart',\n        'lib/product/browser/browser_workspace.dart',\n"
new = "        'lib/product/browser/browser_profile_store.dart',\n        'lib/product/browser/browser_quality.dart',\n        'lib/product/browser/browser_replay.dart',\n        'lib/product/browser/browser_workspace.dart',\n"
count = text.count(old)
if count != 1:
    raise SystemExit(f'expected exactly one governed browser inventory anchor, found {count}')
if "'lib/product/browser/browser_quality.dart'" in text:
    raise SystemExit('browser_quality.dart is already governed; refusing duplicate authority edit')
PATH.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')
print('P220_GOVERNED_SOURCE_INVENTORY_REPAIRED')
