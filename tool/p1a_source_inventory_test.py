#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,pathlib

def files(root:pathlib.Path, base:str, *, exclude_tests:bool=False):
 out=[]
 p=root/base
 if not p.exists(): return out
 for x in p.rglob('*'):
  if not x.is_file() or '__pycache__' in x.parts or x.suffix in {'.pyc','.pyo'}: continue
  rel=x.relative_to(root).as_posix()
  if exclude_tests and '/tests/' in '/'+rel: continue
  out.append(rel)
 return sorted(out)

def main():
 a=argparse.ArgumentParser();a.add_argument('--project',default='.');n=a.parse_args();r=pathlib.Path(n.project).resolve()
 d=json.loads((r/'config/p1a_source_inventory.v1.json').read_text())
 for group in ('productionDart','testDart','authoritySources','authorityTests','toolSources'):
  values=d.get(group);assert isinstance(values,list) and len(values)==len(set(values)),group
  for rel in values: assert (r/rel).is_file(),rel
 actual_prod=sorted(x.relative_to(r).as_posix() for x in (r/'lib/product').glob('p1_authority_service_*.dart'))
 actual_test=sorted(x.relative_to(r).as_posix() for x in (r/'test/product').glob('p1_authority_service_*.dart'))
 actual_tests=files(r,'authority_service/tests')
 all_authority=files(r,'authority_service')
 actual_sources=sorted(set(all_authority)-set(actual_tests))
 actual_tools=sorted(x.relative_to(r).as_posix() for x in (r/'tool').glob('p1a_*.py'))
 assert actual_prod==sorted(d['productionDart']),(actual_prod,d['productionDart'])
 assert actual_test==sorted(d['testDart']),(actual_test,d['testDart'])
 assert actual_sources==sorted(d['authoritySources']),(set(actual_sources)^set(d['authoritySources']))
 assert actual_tests==sorted(d['authorityTests']),(set(actual_tests)^set(d['authorityTests']))
 assert actual_tools==sorted(d['toolSources']),(set(actual_tools)^set(d['toolSources']))
 print(f'P1A source inventory: PASS ({len(actual_prod)} production Dart, {len(actual_test)} Dart tests, {len(actual_sources)} authority sources, {len(actual_tests)} behavioral/support tests, {len(actual_tools)} tools)')
 return 0
if __name__=='__main__':raise SystemExit(main())
