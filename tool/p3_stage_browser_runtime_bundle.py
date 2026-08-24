#!/usr/bin/env python3
"""Stage the application-owned P3-001 Node + Chromium browser runtime bundle."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import stat
import subprocess

SKIP_PARTS = {'.git', '.dart_tool', 'build', '__pycache__'}
HEX40 = re.compile(r'^[0-9a-f]{40}$')
HEX64 = re.compile(r'^[0-9a-f]{64}$')
WINDOWS_ALL_APPLICATION_PACKAGES_SID = '*S-1-15-2-1'
WINDOWS_ALL_RESTRICTED_APPLICATION_PACKAGES_SID = '*S-1-15-2-2'


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def is_npm_bin_shim(relative: pathlib.Path) -> bool:
    parts = relative.parts
    return any(
        parts[index] == 'node_modules' and parts[index + 1] == '.bin'
        for index in range(len(parts) - 1)
    )


def require_internal_relative_symlink(
    item: pathlib.Path, root: pathlib.Path
) -> pathlib.Path:
    raw_target = os.readlink(item)
    link_target = pathlib.Path(raw_target)
    if link_target.is_absolute():
        raise SystemExit(f'P3 runtime absolute symlink rejected: {item}')
    resolved_root = root.resolve()
    try:
        resolved_target = (item.parent / link_target).resolve(strict=True)
    except RuntimeError as error:
        raise SystemExit(f'P3 runtime symlink cycle rejected: {item}') from error
    except OSError as error:
        raise SystemExit(f'P3 runtime broken symlink rejected: {item}') from error
    try:
        resolved_target.relative_to(resolved_root)
    except ValueError as error:
        raise SystemExit(f'P3 runtime escaping symlink rejected: {item}') from error
    if resolved_target.is_dir():
        resolved_parent = item.parent.resolve()
        if resolved_target == resolved_parent or resolved_target in resolved_parent.parents:
            raise SystemExit(f'P3 runtime symlink cycle rejected: {item}')
    return resolved_target


def tree_sha256(
    root: pathlib.Path,
    *,
    allow_internal_symlinks: bool = False,
) -> str:
    rows: list[str] = []
    for item in sorted(root.rglob('*'), key=lambda value: value.as_posix()):
        relative = item.relative_to(root).as_posix()
        if item.is_symlink():
            if not allow_internal_symlinks:
                raise SystemExit(f'P3 browser runtime symlink rejected: {item}')
            require_internal_relative_symlink(item, root)
            target_sha = hashlib.sha256(os.readlink(item).encode('utf-8')).hexdigest()
            rows.append(f'{relative}\0@symlink\0{target_sha}')
        elif item.is_file():
            rows.append(f'{relative}\0{sha256_file(item)}')
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


def copy_tree(
    src: pathlib.Path,
    dst: pathlib.Path,
    *,
    include_node_modules: bool,
    preserve_internal_symlinks: bool = False,
) -> None:
    if not src.is_dir() or src.is_symlink():
        raise SystemExit(f'P3 runtime tree missing/symlinked: {src}')
    for item in sorted(src.rglob('*'), key=lambda value: value.as_posix()):
        relative = item.relative_to(src)
        if any(part in SKIP_PARTS for part in relative.parts):
            continue
        if not include_node_modules and 'node_modules' in relative.parts:
            continue
        if is_npm_bin_shim(relative):
            continue
        target = dst / relative
        if item.is_symlink():
            if not preserve_internal_symlinks:
                raise SystemExit(f'P3 runtime symlink rejected: {item}')
            resolved_target = require_internal_relative_symlink(item, src)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.symlink_to(
                os.readlink(item),
                target_is_directory=resolved_target.is_dir(),
            )
        elif item.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        elif item.is_file():
            copy_file(item, target, bool(item.stat().st_mode & stat.S_IXUSR))


def prepare_windows_sandbox_acl(
    root: pathlib.Path,
    *,
    platform_name: str | None = None,
    runner=subprocess.run,
) -> bool:
    platform = os.name if platform_name is None else platform_name
    if platform != 'nt':
        return False
    if not root.is_dir() or root.is_symlink():
        raise SystemExit(f'P3 Windows browser sandbox ACL root invalid: {root}')
    command = [
        'icacls.exe',
        str(root),
        '/grant',
        f'{WINDOWS_ALL_APPLICATION_PACKAGES_SID}:(OI)(CI)(RX)',
        f'{WINDOWS_ALL_RESTRICTED_APPLICATION_PACKAGES_SID}:(OI)(CI)(RX)',
        '/T',
        '/Q',
    ]
    result = runner(
        command,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        diagnostic = (result.stderr or result.stdout or '').replace('\x00', '').strip()
        if len(diagnostic) > 2048:
            diagnostic = diagnostic[-2048:]
        detail = diagnostic or f'exit={result.returncode}'
        raise SystemExit(
            f'P3 Windows browser sandbox ACL preparation failed: {detail}'
        )
    return True


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
    copy_tree(
        browser_root,
        staged_browser_root,
        include_node_modules=True,
        preserve_internal_symlinks=True,
    )
    prepare_windows_sandbox_acl(staged_browser_root)
    staged_browser_executable = staged_browser_root / browser_relative
    if not staged_browser_executable.is_file() or staged_browser_executable.is_symlink():
        raise SystemExit('staged browser executable missing/symlinked')
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
        'treeSha256': tree_sha256(
            staged_browser_root,
            allow_internal_symlinks=True,
        ),
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
