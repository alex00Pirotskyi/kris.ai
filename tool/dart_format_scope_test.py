#!/usr/bin/env python3
"""Standard-library regression tests for the handwritten Dart format scope."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest


MODULE_PATH = Path(__file__).with_name("dart_format_scope.py")
SPEC = importlib.util.spec_from_file_location("dart_format_scope", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
SCOPE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SCOPE)


class DartFormatScopeTest(unittest.TestCase):
    def test_generated_contracts_are_never_selected(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kristin-format-scope-") as temp:
            root = Path(temp)
            paths = (
                "lib/product/handwritten.dart",
                "lib/product/generated/v170_contracts.g.dart",
                "lib/product/other.freezed.dart",
                "lib/generated_plugin_registrant.dart",
                "test/product/handwritten_test.dart",
                "test/generated/mock.g.dart",
                "tool/prune_stale_legacy.dart",
                "build/copied.dart",
                ".dart_tool/cache.dart",
            )
            for relative in paths:
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("void main() {}\n", encoding="utf-8")

            selected = SCOPE.collect_dart_files(root)
            self.assertEqual(
                selected,
                [
                    "lib/product/handwritten.dart",
                    "test/product/handwritten_test.dart",
                    "tool/prune_stale_legacy.dart",
                ],
            )

    def test_batches_preserve_order_and_all_values(self) -> None:
        values = [f"lib/file_{index:03d}.dart" for index in range(250)]
        batches = list(SCOPE.batched(values))
        self.assertGreater(len(batches), 1)
        self.assertEqual([item for batch in batches for item in batch], values)
        self.assertTrue(all(len(batch) <= SCOPE.MAX_BATCH_FILES for batch in batches))


if __name__ == "__main__":
    unittest.main(verbosity=2)
