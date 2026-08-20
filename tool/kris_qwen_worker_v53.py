#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import runpy

TARGET_VERSION = "5.3.1"
ENTRY = pathlib.Path(__file__).with_name("kris_qwen_worker_v531.py")


def main() -> None:
    if not ENTRY.is_file():
        raise SystemExit("KRIS_QWEN_V53_FORWARD_ERROR: deterministic 5.3.1 worker entry is missing")
    runpy.run_path(str(ENTRY), run_name="__main__")


if __name__ == "__main__":
    main()
