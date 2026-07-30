#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import os
import pathlib
import re
import subprocess
import sys

EXPECTED_VERSION = "3.31.6"
EXPECTED_HASHES = {
    "bbaed969cef3c427f4f17591feb28db4ae595e3a4bbd45cb35522cee14df6a32",
    "da9d4fd9abd571fd016ddb27da0428b10277010b23bb21e3678f8b9e96e1686e",
    "1c8b05df0602365da91ee6a3336fe57525b137706c4ab5675498f662ae1dbcec",
    "2297e9591307d9c61e557efe737bcf4d7c13a30f1f860732f684a204fee24dca",
}


def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def fail(message: str) -> None:
    raise SystemExit("P1A hosted CMake bootstrap: " + message)


def parse_requirement(path: pathlib.Path) -> tuple[str, set[str]]:
    text = path.read_text(encoding="utf-8")
    versions = set(re.findall(r"(?m)^cmake==([^\s\\]+)", text))
    hashes = set(re.findall(r"--hash=sha256:([0-9a-f]{64})", text))
    if versions != {EXPECTED_VERSION}:
        fail(f"requirement version mismatch: {sorted(versions)}")
    if hashes != EXPECTED_HASHES:
        fail(f"requirement hash set mismatch: {sorted(hashes)}")
    if "--hash=" not in text or "http://" in text or "https://" in text:
        fail("requirements must be hash-only and index-neutral")
    return EXPECTED_VERSION, hashes


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if completed.returncode:
        fail(
            f"command failed ({completed.returncode}): {' '.join(command)}\n"
            + (completed.stdout or "")
            + (completed.stderr or "")
        )
    return completed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--github-path")
    parser.add_argument("--json-output")
    parser.add_argument("--validate-only", action="store_true")
    args = parser.parse_args()
    root = pathlib.Path(args.project).resolve()
    requirement = root / "config/p1a_hosted_cmake_requirements.txt"
    if not requirement.is_file():
        fail("requirements file missing")
    version, hashes = parse_requirement(requirement)
    result: dict[str, object] = {
        "schemaVersion": "1.0.0",
        "status": "validated" if args.validate_only else "installed",
        "version": version,
        "requirementsPath": requirement.relative_to(root).as_posix(),
        "requirementsSha256": sha256(requirement),
        "approvedWheelSha256": sorted(hashes),
        "provenanceClass": "github-hosted-source-build-not-completion-evidence",
        "completionEligible": False,
        "completionClaim": False,
    }
    if not args.validate_only:
        run(
            [
                sys.executable,
                "-m",
                "pip",
                "install",
                "--disable-pip-version-check",
                "--isolated",
                "--no-cache-dir",
                "--no-deps",
                "--only-binary=:all:",
                "--require-hashes",
                "--force-reinstall",
                "-r",
                str(requirement),
            ]
        )
        installed = importlib.metadata.version("cmake")
        if installed != version:
            fail(f"installed distribution mismatch: {installed} != {version}")
        try:
            import cmake  # type: ignore
        except Exception as exc:
            fail(f"cannot import installed cmake distribution: {exc}")
        bin_dir = pathlib.Path(str(cmake.CMAKE_BIN_DIR)).resolve()
        executable = bin_dir / ("cmake.exe" if os.name == "nt" else "cmake")
        if not executable.is_file():
            fail(f"installed CMake executable missing: {executable}")
        observed = run([str(executable), "--version"]).stdout.splitlines()[0].strip()
        if observed != f"cmake version {version}":
            fail(f"installed executable mismatch: {observed}")
        github_path = args.github_path or os.environ.get("GITHUB_PATH", "")
        if github_path:
            with pathlib.Path(github_path).open("a", encoding="utf-8", newline="\n") as handle:
                handle.write(str(bin_dir) + "\n")
        result.update(
            {
                "status": "installed-and-verified",
                "distributionVersion": installed,
                "binDirectory": str(bin_dir),
                "executable": str(executable),
                "executableSha256": sha256(executable),
                "githubPathUpdated": bool(github_path),
            }
        )
    rendered = json.dumps(result, indent=2, sort_keys=True) + "\n"
    print(rendered, end="")
    if args.json_output:
        pathlib.Path(args.json_output).write_text(rendered, encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
