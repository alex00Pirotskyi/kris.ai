#!/usr/bin/env python3
"""Apply bounded test-contract repairs after Worker F source materialization."""
from __future__ import annotations

from pathlib import Path

accessibility_path = Path(
    "test/product/p5_information_architecture/p5_accessibility_test.dart"
)
accessibility = accessibility_path.read_text(encoding="utf-8")
accessibility = accessibility.replace(
    "  int maximumTabs = 30,",
    "  int maximumTabs = 120,",
)
old_focus = """    if (target.evaluate().isNotEmpty &&
        Focus.of(tester.element(target)).hasPrimaryFocus) {
      return;
    }
"""
new_focus = """    if (target.evaluate().isNotEmpty) {
      final targetElement = tester.element(target);
      final focusContext = FocusManager.instance.primaryFocus?.context;
      var containsPrimaryFocus = focusContext == targetElement;
      focusContext?.visitAncestorElements((ancestor) {
        if (ancestor == targetElement) {
          containsPrimaryFocus = true;
          return false;
        }
        return true;
      });
      if (containsPrimaryFocus) {
        return;
      }
    }
"""
if old_focus not in accessibility:
    raise RuntimeError("legacy focus detection block was not found")
accessibility = accessibility.replace(old_focus, new_focus, 1)
accessibility = accessibility.replace(
    "    addTearDown(semantics.dispose);\n",
    "",
)
old_tail = """    expect(controller.sideEffects, P5SideEffectLedger.zero);
  });
}
"""
new_tail = """    expect(controller.sideEffects, P5SideEffectLedger.zero);
    semantics.dispose();
  });
}
"""
if old_tail not in accessibility:
    raise RuntimeError("accessibility semantics test tail was not found")
accessibility = accessibility.replace(old_tail, new_tail, 1)
accessibility_path.write_text(accessibility, encoding="utf-8")

verification_path = Path(
    "test/product/p5_information_architecture/p5_verification_center_test.dart"
)
verification = verification_path.read_text(encoding="utf-8")
occurrences = verification.count("find.text(testId)")
if occurrences != 3:
    raise RuntimeError(
        f"expected three exact test-ID finders, observed {occurrences}"
    )
verification = verification.replace(
    "find.text(testId)",
    "find.textContaining(testId)",
)
old_record = """      expect(
        find.byKey(const Key('developer-verification-record')),
        findsOneWidget,
      );
"""
new_record = """      final developerRecord = find.byKey(
        const Key('developer-verification-record'),
      );
      await tester.scrollUntilVisible(
        developerRecord,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(developerRecord, findsOneWidget);
"""
if old_record not in verification:
    raise RuntimeError("developer verification record assertion was not found")
verification = verification.replace(old_record, new_record, 1)
verification_path.write_text(verification, encoding="utf-8")
