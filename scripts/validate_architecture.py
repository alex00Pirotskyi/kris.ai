#!/usr/bin/env python3
"""Offline governed-source checks for Kristin Local Agent v1.0.

This compatibility entry point delegates to the active Prompt-to-Task preview release
validator so older automation continues to use the same architecture, UX, and
security gates without duplicating Flutter SDK compilation checks.
"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
raise SystemExit(
    subprocess.call(
        [
            sys.executable,
            str(ROOT / 'tool' / 'validate_release.py'),
            '--skip-tests',
            '--skip-sdk',
        ],
        cwd=ROOT,
    )
)
