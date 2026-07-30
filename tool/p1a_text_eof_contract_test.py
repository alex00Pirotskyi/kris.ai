#!/usr/bin/env python3
from __future__ import annotations

import argparse
import pathlib


def logical_lf(data: bytes) -> bytes:
    normalized = data.replace(b"\r\n", b"\n")
    if b"\r" in normalized:
        raise ValueError("mixed_or_bare_cr")
    return normalized


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    args = parser.parse_args()
    root = pathlib.Path(args.project).resolve()
    cmake_files = sorted((root / "authority_service").rglob("CMakeLists.txt"))
    if len(cmake_files) < 9:
        raise SystemExit(f"P1A text EOF contract expected at least 9 authority CMake files, found {len(cmake_files)}")
    failures: list[str] = []
    for path in cmake_files:
        relative = path.relative_to(root).as_posix()
        try:
            normalized = logical_lf(path.read_bytes())
        except ValueError:
            failures.append(f"{relative}: mixed or bare CR line ending")
            continue
        if not normalized.endswith(b"\n"):
            failures.append(f"{relative}: missing final newline")
        if normalized.endswith(b"\n\n"):
            failures.append(f"{relative}: extra blank line at EOF")
    if failures:
        raise SystemExit("P1A canonical text EOF violations:\n" + "\n".join(failures))
    print(f"P1A canonical text EOF contract: PASS ({len(cmake_files)} CMake files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
