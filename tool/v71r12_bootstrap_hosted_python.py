#!/usr/bin/env python3
"""Install and verify V71-R12 hosted Python test dependencies.

The exact source gate executes P1 Ed25519 reference tests. GitHub's clean
Python 3.13.5 environments do not include ``cryptography``, so the workflow
must provision it explicitly. This bootstrap is deliberately hash-locked,
wheel-only, index-neutral, and completion-ineligible.
"""
from __future__ import annotations

import argparse
import importlib.metadata
import json
import pathlib
import re
import subprocess
import sys
from typing import Any

REQUIREMENTS_RELATIVE = "config/v71r12_hosted_python_requirements.txt"
EXPECTED: dict[str, tuple[str, set[str]]] = {
    "cryptography": (
        "50.0.0",
        {
            "bd1c592e4d5974f0d08d4888e432157adba757c66da0246918e43677fafa2d30",
            "b42a28c1844fd9de8f3f7d540e36b66f3a9c83fceac7170ebc7a6a19edd9dcae",
            "031e2d5dd4bb9caa3ca9c82e5a197fd8ae680232cee62603d1a813f3f07e3d03",
        },
    ),
    "cffi": (
        "2.1.0",
        {
            "8e74a6135550c4748af665b1b1118b6aab33b1fc6a16f9aff630af107c3b4512",
            "799416bae98336e400981ff6e532d67d5c709cfb30afb79865a1315f94b0e224",
            "716ff8ec22f20b4d988b12884086bcef0fc99737043e503f7a3935a6be99b1ea",
        },
    ),
    "pycparser": (
        "3.0",
        {"b727414169a36b7d524c1c3e31839a521725078d7b2ff038656844266160a992"},
    ),
}
HEX64 = re.compile(r"^[0-9a-f]{64}$")


def fail(message: str) -> None:
    raise SystemExit("V71-R12 hosted Python bootstrap: " + message)


def parse_requirements(path: pathlib.Path) -> dict[str, dict[str, Any]]:
    raw = path.read_text(encoding="utf-8")
    if "\r" in raw or "http://" in raw or "https://" in raw or "--trusted-host" in raw:
        fail("requirements must be LF-only, hash-only, and index-neutral")
    logical = re.sub(r"\\\n[ \t]*", " ", raw)
    observed: dict[str, dict[str, Any]] = {}
    for source_line in logical.splitlines():
        line = source_line.strip()
        if not line or line.startswith("#"):
            continue
        match = re.match(r"^([A-Za-z0-9_.-]+)==([^\s]+)(.*)$", line)
        if match is None:
            fail(f"invalid requirement line: {source_line!r}")
        name = match.group(1).lower().replace("_", "-")
        version = match.group(2)
        hashes = set(re.findall(r"--hash=sha256:([0-9a-f]{64})(?:\s|$)", match.group(3)))
        remainder = re.sub(r"--hash=sha256:[0-9a-f]{64}(?:\s|$)", " ", match.group(3)).strip()
        if remainder:
            fail(f"unsupported requirement option for {name}: {remainder!r}")
        if name in observed or not hashes or any(HEX64.fullmatch(value) is None for value in hashes):
            fail(f"invalid or duplicate requirement: {name}")
        observed[name] = {"version": version, "hashes": hashes}
    if set(observed) != set(EXPECTED):
        fail(f"requirement package set mismatch: {sorted(observed)}")
    for name, (version, hashes) in EXPECTED.items():
        row = observed[name]
        if row["version"] != version:
            fail(f"requirement version mismatch for {name}: {row['version']} != {version}")
        if row["hashes"] != hashes:
            fail(f"requirement hash set mismatch for {name}: {sorted(row['hashes'])}")
    return observed


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if completed.returncode:
        fail(
            f"command failed ({completed.returncode}): {' '.join(command)}\n"
            + (completed.stdout or "")[-12000:]
        )
    return completed


def ed25519_smoke() -> dict[str, Any]:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

    seed = bytes(range(32))
    message = b"kristin-v71r12-hosted-ed25519-smoke"
    private = Ed25519PrivateKey.from_private_bytes(seed)
    public = private.public_key()
    signature = private.sign(message)
    public.verify(signature, message)
    raw_public = public.public_bytes(
        serialization.Encoding.Raw,
        serialization.PublicFormat.Raw,
    )
    if len(raw_public) != 32 or len(signature) != 64:
        fail("Ed25519 primitive returned an invalid encoded size")
    return {
        "ed25519SignVerify": True,
        "rawPublicKeyBytes": len(raw_public),
        "signatureBytes": len(signature),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--json-output")
    args = parser.parse_args()

    root = pathlib.Path(args.project).resolve()
    requirements = root / REQUIREMENTS_RELATIVE
    if not requirements.is_file():
        fail(f"requirements file missing: {REQUIREMENTS_RELATIVE}")
    parsed = parse_requirements(requirements)
    result: dict[str, Any] = {
        "schemaVersion": "1.0.0",
        "status": "validated" if args.validate_only else "installed-and-verified",
        "requirementsPath": REQUIREMENTS_RELATIVE,
        "packages": {name: parsed[name]["version"] for name in sorted(parsed)},
        "hashCount": sum(len(parsed[name]["hashes"]) for name in parsed),
        "wheelOnly": True,
        "hashLocked": True,
        "indexNeutral": True,
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
                "--only-binary=:all:",
                "--require-hashes",
                "--force-reinstall",
                "-r",
                str(requirements),
            ]
        )
        installed: dict[str, str] = {}
        for name, (expected_version, _) in EXPECTED.items():
            version = importlib.metadata.version(name)
            if version != expected_version:
                fail(f"installed distribution mismatch for {name}: {version} != {expected_version}")
            installed[name] = version
        run([sys.executable, "-m", "pip", "check"])
        result["installed"] = installed
        result.update(ed25519_smoke())
        result["pipCheck"] = True

    rendered = json.dumps(result, indent=2, sort_keys=True) + "\n"
    print(rendered, end="")
    if args.json_output:
        pathlib.Path(args.json_output).write_text(rendered, encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
