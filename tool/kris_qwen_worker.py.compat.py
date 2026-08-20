#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import sys


SOURCE = pathlib.Path(__file__).with_name("kris_qwen_worker.py")
TARGET_VERSION = "5.2.2"


def load_source() -> str:
    text = SOURCE.read_text(encoding="utf-8")

    old_version = 'SCRIPT_VERSION = "5.2.1"'
    new_version = f'SCRIPT_VERSION = "{TARGET_VERSION}"'
    if old_version in text:
        if text.count(old_version) != 1:
            raise SystemExit("KRIS_QWEN_COMPAT_ERROR: ambiguous worker version marker")
        text = text.replace(old_version, new_version, 1)
    elif new_version not in text:
        raise SystemExit("KRIS_QWEN_COMPAT_ERROR: unsupported worker version")

    old_cmp = 'parsed["expiresAt"] <= parsed["refreshedAt"]'
    new_cmp = 'parsed["expiresAt"] < parsed["refreshedAt"]'
    if old_cmp in text:
        if text.count(old_cmp) != 1:
            raise SystemExit("KRIS_QWEN_COMPAT_ERROR: ambiguous historical semaphore guard")
        text = text.replace(old_cmp, new_cmp, 1)
        text = text.replace(
            "expiresAt must be later than refreshedAt",
            "expiresAt must not precede refreshedAt",
            1,
        )
    elif new_cmp not in text:
        raise SystemExit("KRIS_QWEN_COMPAT_ERROR: historical semaphore guard not found")

    if old_cmp in text:
        raise SystemExit("KRIS_QWEN_COMPAT_ERROR: obsolete historical semaphore guard remains")
    return text


def main() -> None:
    source = load_source()
    code = compile(source, str(SOURCE), "exec")
    scope = {
        "__name__": "__main__",
        "__file__": str(pathlib.Path(__file__).resolve()),
        "__package__": None,
        "__cached__": None,
    }
    exec(code, scope, scope)


if __name__ == "__main__":
    main()
