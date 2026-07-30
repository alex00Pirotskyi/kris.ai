#!/usr/bin/env python3
"""Patch only the P1A service handle into shipped ProductRuntime.

This is a governed P1 amendment. It does not add P2 code and does not modify
historical P1-001..P1-012 task evidence.
"""
from __future__ import annotations
import argparse,hashlib,json,pathlib,re

def sha(text): return hashlib.sha256(text.encode()).hexdigest()

def insert_import(source,anchor,statement):
 if statement in source:return source
 if source.count(anchor)!=1:raise SystemExit(f'P1A ProductRuntime import anchor not exact: {anchor}')
 return source.replace(anchor,f"{anchor} {statement}",1)

def patch(path):
 source=path.read_text();before=sha(source)
 source=insert_import(source,"import 'workspace_tools.dart';","import 'p1_authority_service_contract_v1.dart'; import 'p1_authority_service_product_runtime_v1.dart';")
 field='P1AuthorityServiceProductRuntimeV1? _p1AuthorityServiceRuntime;'
 getter='P1AuthorityServiceHandleV1? get p1AuthorityService => _p1AuthorityServiceRuntime?.handle;'
 if field not in source:
  matches=list(re.finditer(r'final\s+RunCoordinator\s+runs\s*;',source))
  if len(matches)!=1:raise SystemExit('P1A ProductRuntime field anchor not exact')
  end=matches[0].end();source=source[:end]+f' {field} {getter}'+source[end:]
 init='runtime._p1AuthorityServiceRuntime = await P1AuthorityServiceConnectorRegistryV1.openInstalledOrTest();'
 if init not in source:
  anchor='await coordinator.reconcileInterruptedRuns();'
  if source.count(anchor)!=1:raise SystemExit('P1A ProductRuntime initialize anchor not exact')
  source=source.replace(anchor,f'{init} {anchor}',1)
 close='await _p1AuthorityServiceRuntime?.close();'
 if close not in source:
  matches=list(re.finditer(r'Future(?:<void>)?\s+close\s*\(\s*\)\s+async\s*\{',source))
  if len(matches)!=1:raise SystemExit('P1A ProductRuntime close anchor not exact')
  end=matches[0].end();source=source[:end]+f' {close}'+source[end:]
 for marker in (field,getter,init,close):
  if source.count(marker)!=1:raise SystemExit(f'P1A patch cardinality invalid: {marker}')
 path.write_text(source)
 return {'beforeSha256':before,'afterSha256':sha(source)}

def main():
 ap=argparse.ArgumentParser();ap.add_argument('--project',default='.');ap.add_argument('--output');a=ap.parse_args();root=pathlib.Path(a.project).resolve();target=root/'lib/product/product_runtime.dart'
 if not target.is_file():raise SystemExit('shipped ProductRuntime missing')
 report={'schemaVersion':'1.0.0','resultType':'p1a-product-runtime-patch-v1','productRuntime':patch(target),'field':'ProductRuntime.p1AuthorityService','p2CodeIntroduced':False,'historicalP1EvidenceModified':False,'completionClaim':False}
 out=pathlib.Path(a.output).resolve() if a.output else root/'release/evidence/P1A/product-runtime-patch.json';out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(json.dumps(report,sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
