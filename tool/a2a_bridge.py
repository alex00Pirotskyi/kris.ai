#!/usr/bin/env python3
"""One-shot sandboxed A2A bridge used by interoperability_v19 tests."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys


def main() -> int:
    request_json = os.environ['KRISTIN_A2A_REQUEST_JSON']
    target = json.loads(os.environ['KRISTIN_A2A_TARGET_JSON'])
    executable = str(target['executable'])
    arguments = [str(item) for item in target.get('arguments') or []]
    environment = {
        'KRISTIN_A2A_REQUEST_JSON': request_json,
        'PATH': os.environ.get('PATH', '/usr/bin:/bin'),
        'LANG': os.environ.get('LANG', 'C.UTF-8'),
        'LC_ALL': os.environ.get('LC_ALL', os.environ.get('LANG', 'C.UTF-8')),
    }
    completed = subprocess.run(
        [executable, *arguments],
        cwd=str(Path('/workspace')),
        env=environment,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        errors='replace',
        check=False,
        timeout=20,
    )
    if completed.returncode != 0:
        raise RuntimeError((completed.stderr or completed.stdout or 'A2A agent failed')[-1200:])
    sys.stdout.write(completed.stdout.strip())
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
