#!/usr/bin/env python3
import pathlib,subprocess,sys,tempfile
with tempfile.TemporaryDirectory(prefix='p1a-patch-') as td:
 r=pathlib.Path(td);p=r/'lib/product/product_runtime.dart';p.parent.mkdir(parents=True)
 p.write_text("import 'workspace_tools.dart';\nclass RunCoordinator{}\nclass ProductRuntime { final RunCoordinator runs; ProductRuntime(this.runs); static Future<ProductRuntime> initialize() async { final coordinator=RunCoordinator(); final runtime=ProductRuntime(coordinator); await coordinator.reconcileInterruptedRuns(); return runtime; } Future<void> close() async { } }\nextension on RunCoordinator { Future<void> reconcileInterruptedRuns() async {} }\n")
 script=pathlib.Path(__file__).with_name('p1a_patch_product_runtime.py')
 subprocess.check_call([sys.executable,str(script),'--project',str(r)])
 first=p.read_bytes();subprocess.check_call([sys.executable,str(script),'--project',str(r)]);assert p.read_bytes()==first
 text=p.read_text();assert text.count('P1AuthorityServiceProductRuntimeV1? _p1AuthorityServiceRuntime;')==1;assert text.count('P1AuthorityServiceConnectorRegistryV1.openInstalledOrTest()')==1;assert 'P2' not in text
print('P1A ProductRuntime patch regression: PASS')
