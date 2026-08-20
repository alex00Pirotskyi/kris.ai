from pathlib import Path

source_contract = Path('test/product/source_contract_test.dart')
text = source_contract.read_text()
anchor = """        'lib/product/browser/browser_runtime.dart',\n        'lib/product/browser/browser_runtime_bundle.dart',\n        'lib/product/browser/browser_runtime_process.dart',\n        'lib/product/chat_studio.dart',"""
replacement = """        'lib/product/browser/browser_runtime.dart',\n        'lib/product/browser/browser_runtime_bundle.dart',\n        'lib/product/browser/browser_runtime_process.dart',\n        'lib/product/browser/browser_control_plane.dart',\n        'lib/product/browser/browser_profile_store.dart',\n        'lib/product/browser/browser_replay.dart',\n        'lib/product/browser/browser_workspace.dart',\n        'lib/product/browser/web_preview.dart',\n        'lib/product/browser/web_studio.dart',\n        'lib/product/chat_studio.dart',"""
if replacement not in text:
    if anchor not in text:
        raise SystemExit('P3 source-contract anchor missing')
    text = text.replace(anchor, replacement, 1)
source_contract.write_text(text)

required = [
    'lib/product/browser/browser_control_plane.dart',
    'lib/product/browser/browser_profile_store.dart',
    'lib/product/browser/browser_replay.dart',
    'lib/product/browser/browser_workspace.dart',
    'lib/product/browser/web_preview.dart',
    'lib/product/browser/web_studio.dart',
    'test/product/browser/browser_phase_completion_test.dart',
    'test/product/browser/browser_security_suite_test.dart',
    'test/fixtures/p3_browser/index.html',
    'test/fixtures/p3_browser/fixture.js',
    'docs/recipes/P3_BROWSER_TASK_RECIPES.md',
]
for relative in required:
    if not Path(relative).is_file():
        raise SystemExit(f'missing P3 phase file: {relative}')
