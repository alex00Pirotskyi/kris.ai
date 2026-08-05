#!/usr/bin/env python3
"""Wire P2 into ProductRuntime only after the P1A amendment is present."""
from __future__ import annotations
import argparse,hashlib,json,pathlib,re,subprocess

def digest(text):return hashlib.sha256(text.encode()).hexdigest()
def insert_import(source,anchor,statement):
 if statement in source:return source
 if source.count(anchor)!=1:raise SystemExit(f'P2 composition import anchor not exact: {anchor}')
 return source.replace(anchor,f'{anchor} {statement}',1)
def patch_runtime(path):
 source=path.read_text();before=digest(source)
 has_p1a_handle = 'P1AuthorityServiceHandleV1? get p1AuthorityService' in source
 connector_markers = (
  'P1AuthorityServiceConnectorRegistryV1.openIfInstalled()',
  'P1AuthorityServiceConnectorRegistryV1.openInstalledOrTest()',
 )
 if not has_p1a_handle or not any(marker in source for marker in connector_markers):
  raise SystemExit('merged P1A ProductRuntime amendment is absent')
 source=insert_import(source,"import 'workspace_tools.dart';","import 'p2_product_runtime_bootstrap.dart';")
 field='P2ProductRuntimeOwnerModeHandle? _p2OwnerModeRuntime;'
 getter="P2ProductRuntimeOwnerModeHandle get p2OwnerMode => _p2OwnerModeRuntime ?? P2ProductRuntimeOwnerModeHandle.blocked('product_runtime_p2_not_initialized');"
 if field not in source:
  matches=list(re.finditer(r'final\s+RunCoordinator\s+runs\s*;',source))
  if len(matches)!=1:raise SystemExit('ProductRuntime RunCoordinator field anchor not exact')
  end=matches[0].end();source=source[:end]+f' {field} {getter}'+source[end:]
 init='runtime._p2OwnerModeRuntime = await P2ProductRuntimeBootstrap.start(dataRoot: directories.root, p1AuthorityService: runtime.p1AuthorityService);'
 if init not in source:
  anchor='await coordinator.reconcileInterruptedRuns();'
  if source.count(anchor)!=1:raise SystemExit('ProductRuntime reconciliation anchor not exact')
  source=source.replace(anchor,f'{init} {anchor}',1)
 close='await _p2OwnerModeRuntime?.close();'
 if close not in source:
  matches=list(re.finditer(r'Future(?:<void>)?\s+close\s*\(\s*\)\s+async\s*\{',source))
  if len(matches)!=1:raise SystemExit('ProductRuntime close anchor not exact')
  end=matches[0].end();source=source[:end]+f' {close}'+source[end:]
 for marker in (field,getter,init,close):
  if source.count(marker)!=1:raise SystemExit(f'ProductRuntime P2 cardinality invalid: {marker}')
 path.write_text(source);return {'beforeSha256':before,'afterSha256':digest(source)}
def patch_ui(path):
 source=path.read_text();before=digest(source);source=insert_import(source,"import 'product_runtime.dart';","import 'p2_app_shell.dart';")
 marker='home: P2KristinShell('
 if marker not in source:
  pattern=re.compile(r"home\s*:\s*ChatStudio\s*\(\s*runtime\s*:\s*widget\.runtime\s*,\s*api\s*:\s*api\s*,\s*startupError\s*:\s*startupError\s*,\s*\)\s*,",re.DOTALL)
  replacement="home: P2KristinShell(ownerMode: widget.runtime.p2OwnerMode,chat: ChatStudio(runtime: widget.runtime,api: api,startupError: startupError,),),"
  source,count=pattern.subn(replacement,source,count=1)
  if count!=1:raise SystemExit('KristinApp ChatStudio home anchor missing or ambiguous')
 if source.count(marker)!=1:raise SystemExit('KristinApp P2 shell cardinality invalid')
 path.write_text(source);return {'beforeSha256':before,'afterSha256':digest(source)}
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--project',default='.');ap.add_argument('--verify-only',action='store_true');ap.add_argument('--source-commit');ap.add_argument('--source-tree');ap.add_argument('--output');a=ap.parse_args();root=pathlib.Path(a.project).resolve();runtime=root/'lib/product/product_runtime.dart';ui=root/'lib/product/ui.dart'
 for path in (runtime,ui):
  if not path.is_file():raise SystemExit(f'required shipped source missing: {path.relative_to(root)}')
 report={'schemaVersion':'5.0.0','resultType':'p2-shipped-application-composition-patch-v5','productRuntime':patch_runtime(runtime),'applicationUi':patch_ui(ui),'entryPoint':'ProductRuntime.initialize','p1AuthorityField':'ProductRuntime.p1AuthorityService','p1AuthorityImplementation':'merged-P1A-isolated-service','p2CompositionField':'ProductRuntime.p2OwnerMode','p2Bootstrap':'P2ProductRuntimeBootstrap.start','p2CanConstructP1Authority':False,'p2StagesAuthorityBroker':False,'applicationOwnedRuntimeResources':True,'navigation':'KristinApp -> P2KristinShell -> Owner Mode','sourceCommit':a.source_commit or 'PENDING_SOURCE_COMMIT','sourceTree':a.source_tree or 'PENDING_SOURCE_TREE','fixtureAuthorityEligible':False,'lifecycleOwner':'ProductRuntime'}
 out=pathlib.Path(a.output).resolve() if a.output else None
 if out is None and not a.verify_only:out=root/'release/evidence/P2/application-composition.json'
 if out:out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
 print(json.dumps(report,sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
