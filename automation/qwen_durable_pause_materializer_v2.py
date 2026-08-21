#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import sys

import qwen_durable_pause_materializer as base


def materialize(project: pathlib.Path) -> None:
    base.materialize(project)
    test_path = project / "tool/kris_qwen_control_compat_test.py"
    text = test_path.read_text(encoding="utf-8")
    broken = (
        "                '{\"schemaVersion\":1,\"autoRunEnabled\":\"yes\"}"
        + "\n"
        + "',\n"
    )
    fixed = (
        "                '{\"schemaVersion\":1,\"autoRunEnabled\":\"yes\"}'"
        " + chr(10),\n"
    )
    count = text.count(broken)
    if count != 1:
        raise SystemExit(
            f"generated invalid-state fixture: expected one anchor, found {count}"
        )
    test_path.write_text(
        text.replace(broken, fixed, 1),
        encoding="utf-8",
        newline="\n",
    )


if __name__ == "__main__":
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    materialize(root)
