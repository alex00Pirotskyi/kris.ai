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
old_receipt = """    expect(
      find.byKey(const Key('p5-evidence-artifact-receipt')),
      findsOneWidget,
    );
"""
new_receipt = """    await tester.drag(
      find.byKey(const Key('p5-evidence-artifact-list')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    await _tapKey(tester, const Key('p5-evidence-artifact-receipt'));
    expect(
      find.byKey(const Key('p5-evidence-viewer-receipt')),
      findsOneWidget,
    );
    expect(find.textContaining('run.p5-existing-001'), findsWidgets);
"""
receipt_count = text.count(old_receipt)
if receipt_count != 1:
    raise SystemExit(
        f'expected one post-reopen receipt materialization assertion, found {receipt_count}')
text = text.replace(old_receipt, new_receipt)
path.write_text(text, encoding='utf-8', newline='\n')
print('P5_009_FOCUSED_TEST_SELECTOR_AND_SCROLL_FIX_APPLIED')
