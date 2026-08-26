#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import pathlib
import subprocess
import sys
import tempfile
import zipfile

EXPECTED_ZIP_SHA256 = "630390d620415fc08767fa9d637d7096a5979f42ca0bbafdccfa70d598944a9d"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("repository", nargs="?", default=".")
    parser.add_argument("--validate", action="store_true")
    args = parser.parse_args()

    repository = pathlib.Path(args.repository).resolve()
    payload_root = pathlib.Path(__file__).resolve().parent / "wave_a_payload"
    parts = sorted(payload_root.glob("part*.b64"))
    if not parts:
        raise RuntimeError("Wave A payload parts are missing")
    encoded = "".join(part.read_text(encoding="ascii").strip() for part in parts)
    payload = base64.b64decode(encoded, validate=True)
    actual = hashlib.sha256(payload).hexdigest()
    if actual != EXPECTED_ZIP_SHA256:
        raise RuntimeError(
            f"Wave A payload checksum mismatch: {actual} != {EXPECTED_ZIP_SHA256}"
        )

    with tempfile.TemporaryDirectory(prefix="kristin-wave-a-") as temporary:
        root = pathlib.Path(temporary)
        archive = root / "wave-a.zip"
        archive.write_bytes(payload)
        with zipfile.ZipFile(archive) as bundle:
            bundle.extractall(root)
        installer = root / "kris-wave-a" / "apply_wave_a.py"
        command = [
            sys.executable,
            str(installer),
            str(repository),
            "--no-refresh-manifest",
        ]
        if args.validate:
            command.append("--validate")
        subprocess.run(command, check=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(f"Wave A bootstrap failed: {error}", file=sys.stderr)
        raise
