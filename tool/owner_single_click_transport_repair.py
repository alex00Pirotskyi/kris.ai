#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().with_name('owner_single_click_transport_fix.py')
text = path.read_text(encoding='utf-8')
start = text.find("rep(\n    'test/product/p2_single_click_owner_mode_test.dart',")
if start < 0:
    raise SystemExit('transport test patch block missing')
end = text.find("\n\nprint('OWNER_SINGLE_CLICK_TRANSPORT_FIX_OK')", start)
if end < 0:
    raise SystemExit('transport test patch terminator missing')
replacement = """rep(
    'test/product/p2_single_click_owner_mode_test.dart',
    "      expect(staging, contains('product-current-account'));",
    "      expect(staging, contains('product-current-account'));",
)"""
text = text[:start] + replacement + text[end:]
path.write_text(text, encoding='utf-8', newline='\n')
print('OWNER_SINGLE_CLICK_TRANSPORT_REPAIR_OK')
