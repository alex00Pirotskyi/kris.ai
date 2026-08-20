#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import runpy

TARGET_VERSION = "5.3.0"
ENTRY = pathlib.Path(__file__).with_name("kris_qwen_worker_v53.py")


def main() -> None:
    if not ENTRY.is_file():
        raise SystemExit("KRIS_QWEN_COMPAT_ERROR: deterministic 5.3 worker entry is missing")
    runpy.run_path(str(ENTRY), run_name="__main__")


if __name__ == "__main__":
    main()
