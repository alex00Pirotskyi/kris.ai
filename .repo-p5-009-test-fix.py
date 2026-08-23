from pathlib import Path

path = Path('test/product/p5_information_architecture/p5_evidence_viewers_test.dart')
text = path.read_text(encoding='utf-8')
old = "    expect(find.text('Review navigation accessibility'), findsOneWidget);\n"
new = """    expect(\n      find.descendant(\n        of: find.byKey(const Key('p5-evidence-artifact-browser')),\n        matching: find.text('Review navigation accessibility'),\n      ),\n      findsOneWidget,\n    );\n"""
count = text.count(old)
if count != 2:
    raise SystemExit(f'expected exactly two ambiguous provenance assertions, found {count}')
path.write_text(text.replace(old, new), encoding='utf-8', newline='\n')
print('P5_009_FOCUSED_TEST_SELECTOR_FIX_APPLIED')
