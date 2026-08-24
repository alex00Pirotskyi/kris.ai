#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGER = ROOT / 'tool/v70_package_platform.py'


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f'P2_P3_PRODUCT_PACKAGING_FAIL {message}')


def load_packager():
    spec = importlib.util.spec_from_file_location('kristin_product_packager', PACKAGER)
    require(spec is not None and spec.loader is not None, 'packager import spec missing')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    module = load_packager()
    with tempfile.TemporaryDirectory() as temporary:
        root = pathlib.Path(temporary)
        app = root / 'app'
        app_source = root / 'Kristin.app'
        p2, p3 = module.product_runtime_destinations(app, app_source, 'macos')
        require(p2.as_posix().endswith('Kristin.app/Contents/Resources/runtime/p2/current'), 'macOS P2 destination drift')
        require(p3.as_posix().endswith('Kristin.app/Contents/Resources/runtime/p3/current'), 'macOS P3 destination drift')
        p2, p3 = module.product_runtime_destinations(app, app_source, 'windows')
        require(p2 == app / 'runtime/p2/current', 'Windows/Linux P2 destination drift')
        require(p3 == app / 'runtime/p3/current', 'Windows/Linux P3 destination drift')

        browser = root / 'browser'
        browser.mkdir()
        seen = {}

        def fake_runner(argv, **kwargs):
            seen['argv'] = list(argv)
            return subprocess.CompletedProcess(argv, 0, '', '')

        require(module.prepare_windows_browser_sandbox_acl(browser, platform='windows', runner=fake_runner), 'Windows ACL repair not invoked')
        command = ' '.join(seen['argv'])
        require('*S-1-15-2-1:(OI)(CI)(RX)' in command, 'AppContainer ACL missing')
        require('*S-1-15-2-2:(OI)(CI)(RX)' in command, 'restricted AppContainer ACL missing')
        require(module.prepare_windows_browser_sandbox_acl(browser, platform='linux', runner=fake_runner) is False, 'ACL repair must be Windows-only')

    source = PACKAGER.read_text(encoding='utf-8')
    require('--browser-runtime-stage' in source, 'browser stage argument missing')
    require('browserRuntimeIncluded' in source, 'product metadata browser truth missing')
    print('P2_P3_PRODUCT_PACKAGING_PASS')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
