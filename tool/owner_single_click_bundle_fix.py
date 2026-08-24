#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def rep(path: str, old: str, new: str) -> None:
    p = ROOT / path
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, got {count}: {old[:120]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')


rep(
    'lib/product/p2_bundled_current_account_runtime.dart',
    "    if (bundled['schemaVersion'] != '3.0.0' ||\n        bundled['bundleType'] != 'kristin-p2-application-runtime-v3' ||\n        bundled['ownerRiskQa'] != true) {\n      return false;\n    }",
    "    if (bundled['schemaVersion'] != '3.0.0' ||\n        bundled['bundleType'] != 'kristin-p2-application-runtime-v3' ||\n        bundled['productCurrentAccount'] != true ||\n        bundled['ownerRiskQa'] != false) {\n      return false;\n    }",
)
rep(
    'lib/product/p2_bundled_current_account_runtime.dart',
    "    if (configured['productCurrentAccount'] != true ||\n        configured['ownerRiskQa'] != true) {",
    "    if (configured['productCurrentAccount'] != true ||\n        configured['ownerRiskQa'] != false) {",
)

print('OWNER_SINGLE_CLICK_BUNDLE_FIX_OK')
