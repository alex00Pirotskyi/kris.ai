#!/usr/bin/env python3
from __future__ import annotations
import argparse, pathlib

OLD = """ if 'P1AuthorityServiceHandleV1? get p1AuthorityService' not in source or 'P1AuthorityServiceConnectorRegistryV1.openIfInstalled()' not in source:\n  raise SystemExit('merged P1A ProductRuntime amendment is absent')"""
NEW = """ has_p1a_handle = 'P1AuthorityServiceHandleV1? get p1AuthorityService' in source\n connector_markers = (\n  'P1AuthorityServiceConnectorRegistryV1.openIfInstalled()',\n  'P1AuthorityServiceConnectorRegistryV1.openInstalledOrTest()',\n )\n if not has_p1a_handle or not any(marker in source for marker in connector_markers):\n  raise SystemExit('merged P1A ProductRuntime amendment is absent')"""

def main() -> int:
 ap=argparse.ArgumentParser();ap.add_argument('--project',default='.');a=ap.parse_args();root=pathlib.Path(a.project).resolve()
 patcher=root/'tool/p2_patch_application_composition.py';test=root/'tool/p2_patch_application_composition_test.py'
 if not patcher.is_file() or not test.is_file():raise SystemExit('P2 composition files missing')
 text=patcher.read_text(encoding='utf-8')
 if NEW not in text:
  if OLD not in text:raise SystemExit('P2 composition compatibility anchor missing')
  text=text.replace(OLD,NEW,1);patcher.write_text(text,encoding='utf-8')
 t=test.read_text(encoding='utf-8')
 if 'connector_method: str' not in t:
  t=t.replace('def run_case(minified: bool, typed_close: bool) -> None:', 'def run_case(minified: bool, typed_close: bool, connector_method: str) -> None:',1)
  t=t.replace('P1AuthorityServiceConnectorRegistryV1.openIfInstalled();', 'P1AuthorityServiceConnectorRegistryV1.{connector_method}();',1)
  t=t.replace('for typed_close in (False, True):\n            run_case(minified, typed_close)', 'for typed_close in (False, True):\n            for connector_method in ("openIfInstalled", "openInstalledOrTest"):\n                run_case(minified, typed_close, connector_method)',1)
  test.write_text(t,encoding='utf-8')
 # exact regression on current merged R15 shape
 fixture=root/'lib/product/product_runtime.dart'
 f=fixture.read_text(encoding='utf-8')
 if 'openInstalledOrTest()' not in f and 'openIfInstalled()' not in f:raise SystemExit('merged P1A connector marker absent after compatibility patch')
 print('P2 composition compatibility with merged P1A R15: PASS')
 return 0
if __name__=='__main__':raise SystemExit(main())
