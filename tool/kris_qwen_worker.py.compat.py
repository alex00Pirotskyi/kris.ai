#!/usr/bin/env python3
from __future__ import annotations

import pathlib


SOURCE = pathlib.Path(__file__).with_name("kris_qwen_worker.py")
TARGET_VERSION = "5.2.3"


def load_source() -> str:
    text = SOURCE.read_text(encoding="utf-8")

    new_version = f'SCRIPT_VERSION = "{TARGET_VERSION}"'
    if new_version not in text:
        old_versions = [
            marker
            for marker in (
                'SCRIPT_VERSION = "5.2.1"',
                'SCRIPT_VERSION = "5.2.2"',
            )
            if marker in text
        ]
        if len(old_versions) != 1 or text.count(old_versions[0]) != 1:
            raise SystemExit("KRIS_QWEN_COMPAT_ERROR: unsupported/ambiguous worker version")
        text = text.replace(old_versions[0], new_version, 1)

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

    old_fetch = (
        'def fetch_all(cfg: Config) -> None:\n'
        '    git(cfg.anchor, "fetch", "origin", "+refs/heads/*:refs/remotes/origin/*", "--prune", timeout=1800)\n'
    )
    new_fetch = (
        'def fetch_all(cfg: Config) -> None:\n'
        '    git(\n'
        '        cfg.anchor,\n'
        '        "fetch",\n'
        '        "origin",\n'
        '        "+refs/heads/*:refs/remotes/origin/*",\n'
        '        "+refs/pull/*/head:refs/remotes/origin/pull/*/head",\n'
        '        "--prune",\n'
        '        timeout=1800,\n'
        '    )\n'
    )
    if old_fetch in text:
        if text.count(old_fetch) != 1:
            raise SystemExit("KRIS_QWEN_COMPAT_ERROR: ambiguous heads-only fetch")
        text = text.replace(old_fetch, new_fetch, 1)
    elif "+refs/pull/*/head:refs/remotes/origin/pull/*/head" not in text:
        raise SystemExit("KRIS_QWEN_COMPAT_ERROR: immutable PR-head fetch missing")

    if old_cmp in text:
        raise SystemExit("KRIS_QWEN_COMPAT_ERROR: obsolete historical semaphore guard remains")
    if "+refs/pull/*/head:refs/remotes/origin/pull/*/head" not in text:
        raise SystemExit("KRIS_QWEN_COMPAT_ERROR: immutable PR-head fetch not installed")
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
