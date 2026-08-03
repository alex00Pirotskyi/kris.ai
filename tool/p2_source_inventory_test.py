#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,pathlib
def require(v,m):
 if not v:raise SystemExit(m)
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--project',default='.');ap.add_argument('--allow-unmerged-fixture',action='store_true');a=ap.parse_args();root=pathlib.Path(a.project).resolve();data=json.loads((root/'config/p2_source_inventory.v1.json').read_text())
 production=data.get('productionDart');tests=data.get('testDart');require(isinstance(production,list) and isinstance(tests,list),'P2 inventories missing');require(len(production)==len(set(production)) and len(tests)==len(set(tests)),'duplicates')
 actual=sorted(x.relative_to(root).as_posix() for x in (root/'lib/product').glob('p2_*.dart'));actual_tests=sorted(x.relative_to(root).as_posix() for x in (root/'test/product').glob('p2_*.dart'))
 require(actual==sorted(production),f'P2 production inventory mismatch: {set(actual)^set(production)}');require(actual_tests==sorted(tests),f'P2 test inventory mismatch: {set(actual_tests)^set(tests)}')
 require(not list((root/'lib/product').glob('p1_desktop_control_plane*.dart')),'P2 package contains concrete P1 authority')
 if not a.allow_unmerged_fixture:
  for rel in data.get('requiredMergedP1aFiles',[]):require((root/rel).is_file(),f'merged P1A dependency missing: {rel}')
 shared=(root/'tool/p2_integrate_shared_surfaces.py').read_text();require('load_inventory(root)' in shared,'shared integration ignores inventory')
 for rel in production+tests:require((root/rel).is_file(),f'governed P2 source missing: {rel}')
 print(f'P2 exact governed source inventory: PASS ({len(actual)} production, {len(actual_tests)} tests; P1A external dependency)');return 0
if __name__=='__main__':raise SystemExit(main())
