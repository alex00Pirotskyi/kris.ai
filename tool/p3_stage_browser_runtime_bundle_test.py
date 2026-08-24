#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

import p3_stage_browser_runtime_bundle as stage

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

    def _symlink(
        self,
        link: pathlib.Path,
        target: str,
        *,
        target_is_directory: bool = False,
    ) -> None:
        try:
            link.symlink_to(target, target_is_directory=target_is_directory)
        except (OSError, NotImplementedError) as error:
            self.skipTest(f'symlink creation unavailable: {error}')

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

    def test_copy_tree_omits_npm_bin_symlink_shims(self) -> None:
        with tempfile.TemporaryDirectory(prefix='p3-stage-npm-bin-') as raw:
            temp = pathlib.Path(raw)
            source = temp / 'automation-host'
            package = source / 'node_modules/playwright-core'
            package.mkdir(parents=True)
            (package / 'cli.js').write_text('cli\n', encoding='utf-8')
            bin_dir = source / 'node_modules/.bin'
            bin_dir.mkdir(parents=True)
            self._symlink(bin_dir / 'playwright-core', '../playwright-core/cli.js')
            destination = temp / 'bundle'

            stage.copy_tree(source, destination, include_node_modules=True)

            self.assertTrue((destination / 'node_modules/playwright-core/cli.js').is_file())
            self.assertFalse((destination / 'node_modules/.bin').exists())

    def test_copy_tree_rejects_unexpected_automation_symlink(self) -> None:
        with tempfile.TemporaryDirectory(prefix='p3-stage-automation-link-') as raw:
            temp = pathlib.Path(raw)
            source = temp / 'automation-host'
            source.mkdir()
            (source / 'real.txt').write_text('real\n', encoding='utf-8')
            self._symlink(source / 'unexpected-link', 'real.txt')

            with self.assertRaisesRegex(SystemExit, 'runtime symlink rejected'):
                stage.copy_tree(
                    source,
                    temp / 'bundle',
                    include_node_modules=True,
                )

    def test_browser_tree_preserves_framework_symlink_topology(self) -> None:
        with tempfile.TemporaryDirectory(prefix='p3-stage-browser-link-') as raw:
            temp = pathlib.Path(raw)
            source = temp / 'browser'
            framework = source / 'Google Chrome for Testing Framework.framework'
            version = framework / 'Versions/149.0.7827.55'
            version.mkdir(parents=True)
            executable = version / 'Google Chrome for Testing Framework'
            executable.write_bytes(b'framework\n')
            current = framework / 'Versions/Current'
            self._symlink(current, '149.0.7827.55', target_is_directory=True)
            root_executable = framework / 'Google Chrome for Testing Framework'
            self._symlink(
                root_executable,
                'Versions/Current/Google Chrome for Testing Framework',
            )
            destination = temp / 'bundle'

            stage.copy_tree(
                source,
                destination,
                include_node_modules=True,
                preserve_internal_symlinks=True,
            )

            staged_current = destination / current.relative_to(source)
            staged_root_executable = destination / root_executable.relative_to(source)
            self.assertTrue(staged_current.is_symlink())
            self.assertEqual(os.readlink(staged_current), '149.0.7827.55')
            self.assertTrue(staged_root_executable.is_symlink())
            self.assertEqual(
                os.readlink(staged_root_executable),
                'Versions/Current/Google Chrome for Testing Framework',
            )
            self.assertTrue(staged_root_executable.is_file())
            self.assertRegex(
                stage.tree_sha256(
                    destination,
                    allow_internal_symlinks=True,
                ),
                r'^[0-9a-f]{64}$',
            )
            with self.assertRaisesRegex(SystemExit, 'browser runtime symlink rejected'):
                stage.tree_sha256(destination)

    def test_browser_tree_symlink_target_changes_digest(self) -> None:
        with tempfile.TemporaryDirectory(prefix='p3-stage-browser-link-hash-') as raw:
            temp = pathlib.Path(raw)
            root = temp / 'browser'
            root.mkdir()
            (root / 'one').write_bytes(b'1')
            (root / 'two').write_bytes(b'2')
            link = root / 'current'
            self._symlink(link, 'one')
            first = stage.tree_sha256(root, allow_internal_symlinks=True)
            link.unlink()
            self._symlink(link, 'two')
            second = stage.tree_sha256(root, allow_internal_symlinks=True)
            self.assertNotEqual(first, second)

    def test_browser_tree_rejects_escaping_symlink(self) -> None:
        with tempfile.TemporaryDirectory(prefix='p3-stage-browser-escape-') as raw:
            temp = pathlib.Path(raw)
            source = temp / 'browser'
            source.mkdir()
            outside = temp / 'outside'
            outside.mkdir()
            self._symlink(source / 'escape', '../outside', target_is_directory=True)

            with self.assertRaisesRegex(SystemExit, 'escaping symlink rejected'):
                stage.copy_tree(
                    source,
                    temp / 'bundle',
                    include_node_modules=True,
                    preserve_internal_symlinks=True,
                )

    def test_browser_tree_rejects_symlink_cycle(self) -> None:
        with tempfile.TemporaryDirectory(prefix='p3-stage-browser-cycle-') as raw:
            temp = pathlib.Path(raw)
            source = temp / 'browser'
            source.mkdir()
            self._symlink(source / 'loop', '.', target_is_directory=True)

            with self.assertRaisesRegex(SystemExit, 'symlink cycle rejected'):
                stage.copy_tree(
                    source,
                    temp / 'bundle',
                    include_node_modules=True,
                    preserve_internal_symlinks=True,
                )

    def test_windows_sandbox_acl_grants_appcontainer_and_lpac_read_execute(self) -> None:
        with tempfile.TemporaryDirectory(prefix='p3-stage-windows-acl-') as raw:
            root = pathlib.Path(raw) / 'browser'
            root.mkdir()
            calls: list[tuple[list[str], dict[str, object]]] = []

            def runner(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
                calls.append((command, kwargs))
                return subprocess.CompletedProcess(command, 0, stdout='', stderr='')

            prepared = stage.prepare_windows_sandbox_acl(
                root,
                platform_name='nt',
                runner=runner,
            )

            self.assertIs(prepared, True)
            self.assertEqual(len(calls), 1)
            command, kwargs = calls[0]
            self.assertEqual(
                command,
                [
                    'icacls.exe',
                    str(root),
                    '/grant',
                    '*S-1-15-2-1:(OI)(CI)(RX)',
                    '*S-1-15-2-2:(OI)(CI)(RX)',
                    '/T',
                    '/Q',
                ],
            )
            self.assertEqual(
                kwargs,
                {'capture_output': True, 'text': True, 'check': False},
            )
            self.assertNotIn('no-sandbox', ' '.join(command).lower())

    def test_windows_sandbox_acl_is_noop_off_windows(self) -> None:
        with tempfile.TemporaryDirectory(prefix='p3-stage-posix-acl-') as raw:
            root = pathlib.Path(raw) / 'browser'
            root.mkdir()

            def runner(*args: object, **kwargs: object) -> subprocess.CompletedProcess[str]:
                raise AssertionError(f'unexpected runner call: {args!r} {kwargs!r}')

            self.assertIs(
                stage.prepare_windows_sandbox_acl(
                    root,
                    platform_name='posix',
                    runner=runner,
                ),
                False,
            )

    def test_windows_sandbox_acl_failure_aborts_staging(self) -> None:
        with tempfile.TemporaryDirectory(prefix='p3-stage-windows-acl-fail-') as raw:
            root = pathlib.Path(raw) / 'browser'
            root.mkdir()

            def runner(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
                return subprocess.CompletedProcess(
                    command,
                    5,
                    stdout='',
                    stderr='Access is denied.',
                )

            with self.assertRaisesRegex(
                SystemExit,
                'Windows browser sandbox ACL preparation failed: Access is denied',
            ):
                stage.prepare_windows_sandbox_acl(
                    root,
                    platform_name='nt',
                    runner=runner,
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
