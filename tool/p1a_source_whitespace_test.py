#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib
import subprocess

TEXT_SUFFIXES = {
    '.md', '.dart', '.py', '.json', '.yaml', '.yml', '.sh', '.ps1',
    '.cpp', '.hpp', '.h', '.mm', '.in', '.entitlements', '.txt',
}


def _git_paths(root: pathlib.Path, args: list[str]) -> set[str]:
    result = subprocess.run(
        ['git', '-C', str(root), *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return {line.strip() for line in result.stdout.splitlines() if line.strip()}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', required=True)
    args = parser.parse_args()
    root = pathlib.Path(args.project).resolve()

    if not (root / '.git').exists():
        probe = subprocess.run(
            ['git', '-C', str(root), 'rev-parse', '--is-inside-work-tree'],
            capture_output=True,
            text=True,
        )
        if probe.returncode != 0 or probe.stdout.strip() != 'true':
            raise SystemExit(f'P1A whitespace check requires a Git worktree: {root}')

    governed = set()
    governed.update(_git_paths(root, ['diff', '--name-only', '--relative']))
    governed.update(_git_paths(root, ['diff', '--cached', '--name-only', '--relative']))
    governed.update(_git_paths(root, ['ls-files', '--others', '--exclude-standard']))

    failures: list[str] = []
    checked = 0
    for relative in sorted(governed):
        path = root / pathlib.PurePosixPath(relative)
        if not path.is_file() or path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        if any(part in {'.git', '.dart_tool', 'build', 'node_modules'} for part in path.parts):
            continue
        try:
            raw = path.read_bytes()
            normalized = raw.replace(b'\r\n', b'\n')
            if b'\r' in normalized:
                failures.append(f'{relative}: mixed or bare CR line ending')
            if normalized and not normalized.endswith(b'\n'):
                failures.append(f'{relative}: missing final newline')
            if normalized.endswith(b'\n\n'):
                failures.append(f'{relative}: extra blank line at EOF')
            lines = raw.decode('utf-8').splitlines()
        except UnicodeDecodeError:
            continue
        checked += 1
        for number, line in enumerate(lines, start=1):
            if line.endswith((' ', '\t')):
                failures.append(f'{relative}:{number}: trailing whitespace')

    if failures:
        raise SystemExit('P1A source whitespace violations:\n' + '\n'.join(failures))
    print(f'P1A source whitespace contract: PASS ({checked} changed text files)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
