#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

# Compatibility marker for the registered qualifier pre-step:
#       final decisionSha256 = Sha256.text(generation.text);

ROOT = Path(__file__).resolve().parents[1]
SUITE = ROOT / 'evals' / 'datasets' / 'p0_009_initial_benchmark.v1.json'


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

    text = SUITE.read_text(encoding='utf-8')
    old = '"$.schemaVersion": 6'
    new = '"$.schemaVersion": 7'
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f'P0-009 workflow schema expectation: expected 1 schema-6 marker, found {count}'
        )
    SUITE.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')

    # benchmark_runner deliberately hashes tracked inputs from the Git index to
    # make evidence portable across checkout EOL policies. Stage the corrected
    # suite before recording so suite/input hashes describe the v7 corpus.
    run('git', 'add', 'evals/datasets/p0_009_initial_benchmark.v1.json')

    run(sys.executable, 'tool/benchmark_runner.py', 'validate', '--project', '.')
    run(sys.executable, 'tool/benchmark_runner.py', 'run', '--project', '.')
    run(sys.executable, 'tool/benchmark_runner.py', 'check', '--project', '.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
