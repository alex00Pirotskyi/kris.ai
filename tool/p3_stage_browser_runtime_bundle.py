#!/usr/bin/env python3
"""Stage the application-owned P3-001 Node + Chromium browser runtime bundle."""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import shutil
import stat

SKIP_PARTS = {'.git', '.dart_tool', 'build', '__pycache__'}
HEX40 = re.compile(r'^[0-9a-f]{40}$')
HEX64 = re.compile(r'^[0-9a-f]{64}$')


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def tree_sha256(root: pathlib.Path) -> str:
    rows: list[str] = []
    for item in sorted(root.rglob('*'), key=lambda value: value.as_posix()):
        if item.is_symlink():
            raise SystemExit(f'P3 browser runtime symlink rejected: {item}')
        if item.is_file():
            rows.append(
                f'{item.relative_to(root).as_posix()}\0{sha256_file(item)}'
            )
    return hashlib.sha256('\n'.join(rows).encode('utf-8')).hexdigest()


def copy_file(src: pathlib.Path, dst: pathlib.Path, executable: bool) -> dict[str, object]:
    src = src.resolve()
    if not src.is_file() or src.is_symlink():
        raise SystemExit(f'P3 runtime input missing/symlinked: {src}')
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    dst.chmod(0o755 if executable else 0o644)
    return {
        'kind': 'file',
        'path': dst.as_posix(),
        'sha256': sha256_file(dst),
        'bytes': dst.stat().st_size,
        'executable': bool(executable),
    }


def copy_tree(src: pathlib.Path, dst: pathlib.Path, *, include_node_modules: bool) -> None:
    if not src.is_dir() or src.is_symlink():
        raise SystemExit(f'P3 runtime tree missing/symlinked: {src}')
    for item in sorted(src.rglob('*'), key=lambda value: value.as_posix()):
        relative = item.relative_to(src)
        if any(part in SKIP_PARTS for part in relative.parts):
            continue
        if not include_node_modules and 'node_modules' in relative.parts:
            continue
        if item.is_symlink():
            raise SystemExit(f'P3 runtime symlink rejected: {item}')
        target = dst / relative
        if item.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        elif item.is_file():
            copy_file(item, target, bool(item.stat().st_mode & stat.S_IXUSR))


def relative_resource(row: dict[str, object], root: pathlib.Path) -> dict[str, object]:
    result = dict(row)
    result['path'] = pathlib.Path(str(result['path'])).relative_to(root).as_posix()
    return result


def require_json(path: pathlib.Path) -> dict[str, object]:
    try:
        value = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f'invalid JSON {path}: {error}') from error
    if not isinstance(value, dict):
        raise SystemExit(f'JSON object required: {path}')
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', default='.')
    parser.add_argument('--destination', required=True)
    parser.add_argument('--node-executable', required=True)
    parser.add_argument('--browser-root', required=True)
    parser.add_argument('--browser-executable', required=True)
    parser.add_argument('--source-commit', required=True)
    parser.add_argument('--source-tree', required=True)
    args = parser.parse_args()

    project = pathlib.Path(args.project).resolve()
    destination = pathlib.Path(args.destination).resolve()
    node_executable = pathlib.Path(args.node_executable).resolve()
    browser_root = pathlib.Path(args.browser_root).resolve()
    browser_executable = pathlib.Path(args.browser_executable).resolve()

    if not HEX40.fullmatch(args.source_commit) or not HEX40.fullmatch(args.source_tree):
        raise SystemExit('exact 40-hex source commit/tree required')
    if destination == project or project in destination.parents:
        raise SystemExit('P3 runtime destination must be outside governed source')
    if not browser_root.is_dir() or browser_root.is_symlink():
        raise SystemExit('browser root missing or symlinked')
    if not browser_executable.is_file() or browser_executable.is_symlink():
        raise SystemExit('browser executable missing or symlinked')
    try:
        browser_relative = browser_executable.relative_to(browser_root)
    except ValueError as error:
        raise SystemExit('browser executable must be inside browser root') from error

    package_json = require_json(project / 'automation_host/package.json')
    package_lock_path = project / 'automation_host/package-lock.json'
    browser_lock = require_json(project / 'config/p3.browser-runtime-lock.json')
    expected_lock_sha = str(browser_lock.get('packageLockSha256', '')).lower()
    if not HEX64.fullmatch(expected_lock_sha):
        raise SystemExit('P3 package-lock identity missing')
    if sha256_file(package_lock_path) != expected_lock_sha:
        raise SystemExit('P3 package-lock SHA mismatch')
    if (
        browser_lock.get('schemaVersion') != '1.0.0'
        or browser_lock.get('nodeVersion') != '24.18.0'
        or browser_lock.get('automationHostPackageVersion') != package_json.get('version')
        or browser_lock.get('playwrightCoreVersion') != package_json.get('dependencies', {}).get('playwright-core')
        or browser_lock.get('browserEngine') != 'chromium'
        or not str(browser_lock.get('browserRevision', '')).strip()
        or not str(browser_lock.get('browserVersion', '')).strip()
        or browser_lock.get('browserInstallPhase') != 'packaging_only'
        or browser_lock.get('runtimeBrowserNetworkInstall') is not False
        or browser_lock.get('globalNodeRuntimeRequired') is not False
    ):
        raise SystemExit('P3 browser lock identity invalid')

    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True, mode=0o755)

    resources: dict[str, dict[str, object]] = {}
    staged_node = destination / 'node' / node_executable.name
    resources['nodeExecutable'] = relative_resource(
        copy_file(node_executable, staged_node, True), destination
    )

    automation_source = project / 'automation_host'
    automation_target = destination / 'automation_host'
    copy_tree(automation_source, automation_target, include_node_modules=True)
    worker = automation_target / 'src/browser-runtime.mjs'
    package_lock = automation_target / 'package-lock.json'
    if not worker.is_file() or not package_lock.is_file():
        raise SystemExit('P3 automation host worker/package lock missing after staging')
    resources['browserWorker'] = {
        'kind': 'file',
        'path': worker.relative_to(destination).as_posix(),
        'sha256': sha256_file(worker),
        'bytes': worker.stat().st_size,
        'executable': False,
    }
    resources['automationHostRoot'] = {
        'kind': 'directory',
        'path': automation_target.relative_to(destination).as_posix(),
        'treeSha256': tree_sha256(automation_target),
    }
    resources['packageLock'] = {
        'kind': 'file',
        'path': package_lock.relative_to(destination).as_posix(),
        'sha256': sha256_file(package_lock),
        'bytes': package_lock.stat().st_size,
        'executable': False,
    }

    staged_browser_root = destination / 'browser'
    copy_tree(browser_root, staged_browser_root, include_node_modules=True)
    staged_browser_executable = staged_browser_root / browser_relative
    if not staged_browser_executable.is_file():
        raise SystemExit('staged browser executable missing')
    staged_browser_executable.chmod(0o755)
    resources['browserExecutable'] = {
        'kind': 'file',
        'path': staged_browser_executable.relative_to(destination).as_posix(),
        'sha256': sha256_file(staged_browser_executable),
        'bytes': staged_browser_executable.stat().st_size,
        'executable': True,
    }
    resources['browserRoot'] = {
        'kind': 'directory',
        'path': staged_browser_root.relative_to(destination).as_posix(),
        'treeSha256': tree_sha256(staged_browser_root),
    }

    build_rows = [
        f'{key}\0{json.dumps(value, sort_keys=True, separators=(",", ":"))}'
        for key, value in sorted(resources.items())
    ]
    build_rows.extend(
        [
            args.source_commit,
            args.source_tree,
            expected_lock_sha,
            str(browser_lock['browserRevision']),
        ]
    )
    runtime_build_sha = hashlib.sha256('\n'.join(build_rows).encode('utf-8')).hexdigest()
    manifest = {
        'schemaVersion': '1.0.0',
        'bundleType': 'kristin-p3-browser-runtime-v1',
        'applicationOwned': True,
        'workingDirectoryIndependent': True,
        'currentWorkingDirectoryUsed': False,
        'globalRuntimeRequired': False,
        'browserNetworkInstallRequired': False,
        'identity': {
            'sourceCommit': args.source_commit,
            'sourceTree': args.source_tree,
            'runtimeBuildSha256': runtime_build_sha,
            'packageLockSha256': expected_lock_sha,
            'nodeVersion': str(browser_lock['nodeVersion']),
            'automationHostPackageVersion': str(browser_lock['automationHostPackageVersion']),
            'browserEngine': 'chromium',
            'browserRevision': str(browser_lock['browserRevision']),
            'browserVersion': str(browser_lock['browserVersion']),
            'playwrightCoreVersion': str(browser_lock['playwrightCoreVersion']),
        },
        'resources': resources,
    }
    manifest_path = destination / 'browser-runtime-manifest.v1.json'
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + '\n', encoding='utf-8'
    )
    manifest_path.chmod(0o644)
    print(
        json.dumps(
            {
                'runtimeRoot': str(destination),
                'manifest': str(manifest_path),
                'manifestSha256': sha256_file(manifest_path),
                'runtimeBuildSha256': runtime_build_sha,
                'browserRevision': browser_lock['browserRevision'],
                'browserVersion': browser_lock['browserVersion'],
                'packageLockSha256': expected_lock_sha,
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
