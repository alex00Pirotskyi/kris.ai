#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tool/p3_stage_browser_runtime_bundle.py'


class P3StageBrowserRuntimeBundleTest(unittest.TestCase):
    def _inputs(self, temp: pathlib.Path) -> tuple[pathlib.Path, pathlib.Path, pathlib.Path]:
        node = temp / ('node.exe' if sys.platform == 'win32' else 'node')
        node.write_bytes(b'fake-node\n')
        browser_root = temp / 'chromium-test'
        browser_root.mkdir()
        browser = browser_root / ('chrome.exe' if sys.platform == 'win32' else 'chrome')
        browser.write_bytes(b'fake-chromium\n')
        (browser_root / 'resources.pak').write_bytes(b'resource\n')
        return node, browser_root, browser

    def _stage(
        self,
        destination: pathlib.Path,
        node: pathlib.Path,
        browser_root: pathlib.Path,
        browser: pathlib.Path,
    ) -> tuple[subprocess.CompletedProcess[str], dict[str, object] | None]:
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                '--project',
                str(ROOT),
                '--destination',
                str(destination),
                '--node-executable',
                str(node),
                '--browser-root',
                str(browser_root),
                '--browser-executable',
                str(browser),
                '--source-commit',
                'a' * 40,
                '--source-tree',
                'b' * 40,
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            return result, None
        return result, json.loads(
            (destination / 'browser-runtime-manifest.v1.json').read_text(encoding='utf-8')
        )

    def test_stages_deterministic_application_owned_bundle(self) -> None:
        with tempfile.TemporaryDirectory(prefix='p3-stage-') as raw:
            temp = pathlib.Path(raw)
            node, browser_root, browser = self._inputs(temp)
            first = temp / 'bundle-a'
            second = temp / 'bundle-b'

            result_a, manifest_a = self._stage(first, node, browser_root, browser)
            result_b, manifest_b = self._stage(second, node, browser_root, browser)

            self.assertEqual(result_a.returncode, 0, result_a.stdout + result_a.stderr)
            self.assertEqual(result_b.returncode, 0, result_b.stdout + result_b.stderr)
            assert manifest_a is not None
            assert manifest_b is not None
            self.assertEqual(manifest_a, manifest_b)
            self.assertEqual(manifest_a['schemaVersion'], '1.0.0')
            self.assertEqual(manifest_a['bundleType'], 'kristin-p3-browser-runtime-v1')
            self.assertIs(manifest_a['applicationOwned'], True)
            self.assertIs(manifest_a['globalRuntimeRequired'], False)
            self.assertIs(manifest_a['browserNetworkInstallRequired'], False)
            identity = manifest_a['identity']
            self.assertEqual(identity['nodeVersion'], '24.18.0')
            self.assertEqual(identity['automationHostPackageVersion'], '2.0.0-p3.1')
            self.assertEqual(identity['playwrightCoreVersion'], '1.61.1')
            self.assertEqual(identity['browserEngine'], 'chromium')
            self.assertEqual(identity['browserRevision'], '1228')
            self.assertEqual(identity['browserVersion'], '149.0.7827.55')
            resources = manifest_a['resources']
            self.assertEqual(
                set(resources),
                {
                    'nodeExecutable',
                    'browserWorker',
                    'automationHostRoot',
                    'packageLock',
                    'browserExecutable',
                    'browserRoot',
                },
            )
            self.assertTrue((first / resources['nodeExecutable']['path']).is_file())
            self.assertTrue((first / resources['browserWorker']['path']).is_file())
            self.assertTrue((first / resources['browserExecutable']['path']).is_file())
            self.assertEqual(
                resources['packageLock']['sha256'],
                identity['packageLockSha256'],
            )

    def test_rejects_browser_executable_outside_browser_root(self) -> None:
        with tempfile.TemporaryDirectory(prefix='p3-stage-outside-') as raw:
            temp = pathlib.Path(raw)
            node, browser_root, _ = self._inputs(temp)
            outside = temp / ('outside.exe' if sys.platform == 'win32' else 'outside')
            outside.write_bytes(b'outside\n')
            result, manifest = self._stage(
                temp / 'bundle', node, browser_root, outside
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIsNone(manifest)
            self.assertIn(
                'browser executable must be inside browser root',
                result.stdout + result.stderr,
            )


if __name__ == '__main__':
    unittest.main()
