#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import runpy

TARGET_VERSION = "5.4.0"
HERE = pathlib.Path(__file__).resolve().parent
ENTRY = HERE / "kris_qwen_worker_v54.py"
ENGINEERING = HERE / "kris_qwen_engineering_env.py"
CATALOG = HERE.parent / "config/qwen_engineering_skills.v1.json"


def validate_dependencies() -> None:
    for path, label in (
        (ENTRY, "deterministic 5.4 worker entry"),
        (ENGINEERING, "5.4 engineering environment"),
        (CATALOG, "5.4 engineering skill catalog"),
    ):
        if not path.is_file():
            raise SystemExit(f"KRIS_QWEN_V53_FORWARD_ERROR: {label} is missing: {path}")
    try:
        catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemExit(f"KRIS_QWEN_V53_FORWARD_ERROR: engineering skill catalog is invalid: {exc}") from exc
    if catalog.get("schemaVersion") != "1.0.0" or not isinstance(catalog.get("skills"), list) or not catalog["skills"]:
        raise SystemExit("KRIS_QWEN_V53_FORWARD_ERROR: engineering skill catalog contract is invalid")


def main() -> None:
    validate_dependencies()
    runpy.run_path(str(ENTRY), run_name="__main__")


if __name__ == "__main__":
    main()
