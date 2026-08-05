#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import subprocess
import sys
import tempfile


def run_case(minified: bool, typed_close: bool, connector_method: str) -> None:
    with tempfile.TemporaryDirectory(prefix="p2-v63-composition-") as raw:
        root = pathlib.Path(raw)
        product = root / "lib/product"
        product.mkdir(parents=True)
        close_type = "Future<void>" if typed_close else "Future"
        runtime = f"""import 'workspace_tools.dart';
class ProductRuntime {{ final RunCoordinator runs; P1AuthorityServiceProductRuntimeV1? _p1AuthorityServiceRuntime; P1AuthorityServiceHandleV1? get p1AuthorityService => _p1AuthorityServiceRuntime?.handle; ProductRuntime(this.runs); static Future<ProductRuntime> initialize() async {{ late ProductRuntime runtime; final directories = D(); final coordinator = RunCoordinator(); runtime = ProductRuntime(coordinator); runtime._p1AuthorityServiceRuntime = await P1AuthorityServiceConnectorRegistryV1.{connector_method}(); await coordinator.reconcileInterruptedRuns(); return runtime; }} {close_type} close() async {{ await managedProcesses.stopAll(); }}}}"""
        ui = """import 'product_runtime.dart'; class K { Widget build(){ return MaterialApp(home: ChatStudio(runtime: widget.runtime, api: api, startupError: startupError,),); }}"""
        if minified:
            runtime = " ".join(runtime.split())
            ui = " ".join(ui.split())
        (product / "product_runtime.dart").write_text(runtime)
        (product / "ui.dart").write_text(ui)
        script = pathlib.Path(__file__).with_name("p2_patch_application_composition.py")
        command = [sys.executable, str(script), "--project", str(root)]
        first = subprocess.run(command, text=True, capture_output=True)
        if first.returncode:
            raise AssertionError(first.stderr or first.stdout)
        runtime_bytes = (product / "product_runtime.dart").read_bytes()
        ui_bytes = (product / "ui.dart").read_bytes()
        second = subprocess.run(command, text=True, capture_output=True)
        if second.returncode:
            raise AssertionError(second.stderr or second.stdout)
        assert runtime_bytes == (product / "product_runtime.dart").read_bytes()
        assert ui_bytes == (product / "ui.dart").read_bytes()
        text = runtime_bytes.decode()
        assert text.count("P2ProductRuntimeBootstrap.start") == 1
        assert text.count("P2ProductRuntimeOwnerModeHandle? _p2OwnerModeRuntime;") == 1
        assert text.count("P1AuthorityServiceHandleV1? get p1AuthorityService") == 1
        assert text.count("P2ProductRuntimeOwnerModeHandle get p2OwnerMode") == 1
        assert text.count("await _p2OwnerModeRuntime?.close();") == 1
        assert "P1P2ProductRuntimeComposition" not in text
        assert (product / "ui.dart").read_text().count("home: P2KristinShell(") == 1


def main() -> int:
    for minified in (False, True):
        for typed_close in (False, True):
            for connector_method in ("openIfInstalled", "openInstalledOrTest"):
                run_case(minified, typed_close, connector_method)
    print("P2 V63 ProductRuntime composition patch regression: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
