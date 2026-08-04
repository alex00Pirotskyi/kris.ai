#!/usr/bin/env python3
from __future__ import annotations

import argparse

import copy
import json
import pathlib
import tempfile

from p2_contract_fixture_support import build_platform_receipt, write_json
from p2_evidence_contract import validate_platform_receipt


def expect_rejected(path: pathlib.Path, commit: str, label: str, *, allow_synthetic: bool = True) -> None:
    try:
        validate_platform_receipt(
            path,
            commit_sha=commit,
            allow_synthetic_contract_fixture=allow_synthetic,
        )
    except SystemExit:
        return
    raise AssertionError(f"forged receipt was accepted: {label}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', default='.')
    parser.parse_args()
    commit = "a" * 40
    with tempfile.TemporaryDirectory(prefix="p2-evidence-contract-") as temp_value:
        base = pathlib.Path(temp_value)
        positive = build_platform_receipt(base / "positive", "linux", commit)
        validate_platform_receipt(
            positive,
            commit_sha=commit,
            allow_synthetic_contract_fixture=True,
        )
        expect_rejected(positive, commit, "synthetic fixture release use", allow_synthetic=False)

        tamper = build_platform_receipt(base / "tamper", "linux", commit)
        artifact = tamper.parent / "artifact"
        target = next((artifact / "assertions").rglob("*.json"))
        target.write_bytes(target.read_bytes() + b" ")
        expect_rejected(tamper, commit, "artifact payload tamper")

        bad_digest = build_platform_receipt(base / "bad-digest", "linux", commit)
        data = json.loads(bad_digest.read_text(encoding="utf-8"))
        data["artifactSha256"] = "5" * 64
        write_json(bad_digest, data)
        expect_rejected(bad_digest, commit, "artifact digest mismatch")

        string_only = build_platform_receipt(base / "string-only", "linux", commit)
        data = json.loads(string_only.read_text(encoding="utf-8"))
        data["taskAssertions"]["P2-001"]["assertions"] = ["descriptive string only"]
        write_json(string_only, data)
        expect_rejected(string_only, commit, "string-only assertion")

        mock_product = build_platform_receipt(
            base / "mock-product", "linux", commit, product_adapter="P2Mock"
        )
        expect_rejected(mock_product, commit, "mock product adapter")

        source_only = build_platform_receipt(base / "source-only", "linux", commit)
        data = json.loads(source_only.read_text(encoding="utf-8"))
        data["taskAssertions"]["P2-001"]["status"] = "source_only"
        write_json(source_only, data)
        expect_rejected(source_only, commit, "source_only task")

        no_interactive = build_platform_receipt(base / "no-interactive", "linux", commit)
        data = json.loads(no_interactive.read_text(encoding="utf-8"))
        data["interactiveDesktopAttested"] = False
        write_json(no_interactive, data)
        expect_rejected(no_interactive, commit, "noninteractive hosted lane")

        missing_native = build_platform_receipt(base / "missing-native", "linux", commit)
        data = json.loads(missing_native.read_text(encoding="utf-8"))
        data["nativeRuntime"] = copy.deepcopy(data["nativeRuntime"])
        del data["nativeRuntime"]["binaries"]["posixWatchdog"]
        write_json(missing_native, data)
        expect_rejected(missing_native, commit, "missing native lifecycle helper")

    print("P2 evidence contract positive/tamper/forgery/native/interactive regression: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
