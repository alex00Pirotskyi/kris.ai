#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile


def logical_lf(data: bytes) -> bytes:
    normalized = data.replace(b"\r\n", b"\n")
    if b"\r" in normalized:
        raise ValueError("mixed_or_bare_cr")
    return normalized


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _run_manifest_generator_contract(root: pathlib.Path) -> list[str]:
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="kristin-p1a-manifest-contract-") as temporary:
        fixture = pathlib.Path(temporary).resolve()
        (fixture / "tool").mkdir(parents=True)
        (fixture / "scripts").mkdir()
        (fixture / "fixtures").mkdir()

        for relative in (
            "tool/p1a_refresh_source_manifest.py",
            "tool/source_tree_policy.py",
        ):
            source = root / relative
            if not source.is_file():
                failures.append(f"manifest generator fixture source missing: {relative}")
                return failures
            target = fixture / relative
            shutil.copy2(source, target)

        crlf_text = b"@echo off\r\necho canonical text\r\n"
        nul_binary = b"\x00\xff\r\n"
        non_utf8 = b"\xff\r\n"
        (fixture / "scripts/crlf.cmd").write_bytes(crlf_text)
        (fixture / "fixtures/nul-binary.bin").write_bytes(nul_binary)
        (fixture / "fixtures/non-utf8.bin").write_bytes(non_utf8)

        subprocess.run(
            ["git", "init", "-q"],
            cwd=fixture,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        subprocess.run(
            ["git", "add", "tool", "scripts", "fixtures"],
            cwd=fixture,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )

        env = os.environ.copy()
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        command = [sys.executable, "tool/p1a_refresh_source_manifest.py", "."]
        subprocess.run(
            command,
            cwd=fixture,
            env=env,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        first = (fixture / "SOURCE_MANIFEST.sha256").read_bytes()
        subprocess.run(
            command,
            cwd=fixture,
            env=env,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        second = (fixture / "SOURCE_MANIFEST.sha256").read_bytes()

        if first != second:
            failures.append("source-manifest generator is not byte-identical across repeated runs")
        if b"\r" in second or not second.endswith(b"\n") or second.endswith(b"\n\n"):
            failures.append("source-manifest generator must serialize LF with exactly one terminal newline")

        rows: dict[str, str] = {}
        try:
            for line in second.decode("utf-8").splitlines():
                digest, relative = line.split("  ", 1)
                if relative in rows:
                    failures.append(f"duplicate generated source-manifest path: {relative}")
                rows[relative] = digest
        except (UnicodeDecodeError, ValueError):
            failures.append("generated source manifest is not canonical UTF-8 digest/path rows")
            return failures

        expected_paths = sorted(
            [
                "fixtures/non-utf8.bin",
                "fixtures/nul-binary.bin",
                "scripts/crlf.cmd",
                "tool/p1a_refresh_source_manifest.py",
                "tool/source_tree_policy.py",
            ]
        )
        if list(rows) != expected_paths:
            failures.append(
                "source-manifest generator path scope/order mismatch: "
                f"actual={list(rows)} expected={expected_paths}"
            )

        canonical_text = logical_lf(crlf_text)
        if _sha256(crlf_text) == _sha256(canonical_text):
            failures.append("CRLF regression fixture does not distinguish raw from canonical text identity")
        if rows.get("scripts/crlf.cmd") != _sha256(canonical_text):
            failures.append("UTF-8 CRLF text is not hashed using canonical LF source identity")
        if rows.get("fixtures/nul-binary.bin") != _sha256(nul_binary):
            failures.append("NUL-containing binary payload was altered before source hashing")
        if rows.get("fixtures/non-utf8.bin") != _sha256(non_utf8):
            failures.append("non-UTF-8 payload was altered before source hashing")

    return failures


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

    failures.extend(_run_manifest_generator_contract(root))
    if failures:
        raise SystemExit("P1A canonical text EOF/manifest violations:\n" + "\n".join(failures))
    print(
        "P1A canonical text EOF/manifest contract: PASS "
        f"({len(cmake_files)} CMake files; canonical source-manifest identity verified)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
