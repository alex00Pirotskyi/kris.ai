#!/usr/bin/env python3
"""Align the permanent Worker F workflow with the canonical root manifest path."""
from pathlib import Path

path = Path('.github/workflows/worker-f-p5-001-information-architecture.yml')
text = path.read_text(encoding='utf-8')
old = 'docs/roadmap/SOURCE_MANIFEST.sha256'
count = text.count(old)
if count != 1:
    raise RuntimeError(f'expected one stale source-manifest path, found {count}')
path.write_text(text.replace(old, 'SOURCE_MANIFEST.sha256'), encoding='utf-8')
