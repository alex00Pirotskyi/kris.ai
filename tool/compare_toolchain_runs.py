#!/usr/bin/env python3
"""Compare two P0-004 CI toolchain receipt sets."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

LANES = ("Linux", "Windows", "macOS")


def load_receipts(directory: Path) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for lane in LANES:
        path = directory / f"toolchain-{lane}.json"
        if not path.is_file():
            raise ValueError(f"missing receipt: {path}")
        payload = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(payload, dict) or payload.get("passed") is not True:
            raise ValueError(f"receipt is not passing: {path}")
        result[lane] = payload
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--first-dir", required=True)
    parser.add_argument("--second-dir", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--first-run-url")
    parser.add_argument("--second-run-url")
    args = parser.parse_args()

    first = load_receipts(Path(args.first_dir))
    second = load_receipts(Path(args.second_dir))
    comparisons: dict[str, Any] = {}
    passed = True
    for lane in LANES:
        first_fingerprint = first[lane].get("declaredInputFingerprint")
        second_fingerprint = second[lane].get("declaredInputFingerprint")
        lane_passed = bool(first_fingerprint) and first_fingerprint == second_fingerprint
        passed = passed and lane_passed
        comparisons[lane] = {
            "passed": lane_passed,
            "firstFingerprint": first_fingerprint,
            "secondFingerprint": second_fingerprint,
            "firstManifestSha256": first[lane].get("manifestSha256"),
            "secondManifestSha256": second[lane].get("manifestSha256"),
        }
    payload = {
        "schemaVersion": "1.0.0",
        "milestone": "P0-004",
        "passed": passed,
        "firstRunUrl": args.first_run_url,
        "secondRunUrl": args.second_run_url,
        "comparisons": comparisons,
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
