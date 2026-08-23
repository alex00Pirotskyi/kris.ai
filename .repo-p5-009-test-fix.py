from pathlib import Path

path = Path('test/product/p5_information_architecture/p5_evidence_viewers_test.dart')
text = path.read_text(encoding='utf-8')
old_title = "    expect(find.text('Review navigation accessibility'), findsOneWidget);\n"
new_title = """    expect(\n      find.descendant(\n        of: find.byKey(const Key('p5-evidence-artifact-browser')),\n        matching: find.text('Review navigation accessibility'),\n      ),\n      findsOneWidget,\n    );\n"""
title_count = text.count(old_title)
if title_count != 2:
    raise SystemExit(
        f'expected exactly two ambiguous provenance assertions, found {title_count}')
text = text.replace(old_title, new_title)

old_initial_receipt = "    await _tapKey(tester, const Key('p5-evidence-artifact-receipt'));\n"
new_initial_receipt = """    await tester.scrollUntilVisible(\n      find.byKey(const Key('p5-evidence-artifact-receipt')),\n      120,\n      scrollable: find.byKey(const Key('p5-evidence-artifact-list')),\n    );\n    await _tapKey(tester, const Key('p5-evidence-artifact-receipt'));\n"""
initial_receipt_count = text.count(old_initial_receipt)
if initial_receipt_count != 1:
    raise SystemExit(
        f'expected one initial lazy receipt tap, found {initial_receipt_count}')
text = text.replace(old_initial_receipt, new_initial_receipt)

old_reopen_receipt = """    expect(
      find.byKey(const Key('p5-evidence-artifact-receipt')),
      findsOneWidget,
    );
"""
new_reopen_receipt = """    await tester.scrollUntilVisible(
      find.byKey(const Key('p5-evidence-artifact-receipt')),
      120,
      scrollable: find.byKey(const Key('p5-evidence-artifact-list')),
    );
    await _tapKey(tester, const Key('p5-evidence-artifact-receipt'));
    expect(
      find.byKey(const Key('p5-evidence-viewer-receipt')),
      findsOneWidget,
    );
    expect(find.textContaining('run.p5-existing-001'), findsWidgets);
"""
reopen_receipt_count = text.count(old_reopen_receipt)
if reopen_receipt_count != 1:
    raise SystemExit(
        f'expected one post-reopen receipt assertion, found {reopen_receipt_count}')
text = text.replace(old_reopen_receipt, new_reopen_receipt)

path.write_text(text, encoding='utf-8', newline='\n')
print('P5_009_FOCUSED_TEST_PROVENANCE_LAZY_SCROLL_FIX_APPLIED')
