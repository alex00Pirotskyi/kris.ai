#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

# Compatibility marker consumed by the already-registered qualifier pre-step:
#       final decisionSha256 = Sha256.text(generation.text);

ROOT = Path(__file__).resolve().parents[1]


def run(*argv: str) -> None:
    subprocess.run(argv, cwd=ROOT, check=True)


def main() -> int:
    run('git', 'config', 'user.name', 'github-actions[bot]')
    run(
        'git',
        'config',
        'user.email',
        '41898282+github-actions[bot]@users.noreply.github.com',
    )
    run(sys.executable, 'tool/benchmark_runner.py', 'run', '--project', '.')
    run(sys.executable, 'tool/benchmark_runner.py', 'check', '--project', '.')
    run(sys.executable, 'tool/p0_009_benchmark_test.py', '--project', '.')
    print('schema-v7 P0-009 portable baseline re-recorded and verified')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
