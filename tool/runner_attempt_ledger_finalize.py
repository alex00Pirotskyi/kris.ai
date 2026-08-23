#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
_COMPAT = "      final decisionSha256 = Sha256.text(generation.text);"


def run(*args: str) -> None:
    subprocess.run(list(args), cwd=ROOT, check=True)


def main() -> int:
    run('git', 'config', 'user.name', 'github-actions[bot]')
    run(
        'git',
        'config',
        'user.email',
        '41898282+github-actions[bot]@users.noreply.github.com',
    )
    run(sys.executable, 'tool/dart_format_scope.py', '--project', '.', '--write')
    run(sys.executable, 'tool/dart_format_scope.py', '--project', '.', '--check')
    run(sys.executable, 'tool/p2_refresh_source_manifest.py', '.')
    run(sys.executable, 'tool/benchmark_runner.py', 'check', '--project', '.')
    run(sys.executable, 'tool/p0_010_generated_state_test.py', '--project', '.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
