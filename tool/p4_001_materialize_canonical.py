#!/usr/bin/env python3
"""One-shot governed materializer for P4-001 canonical Test Center integration."""
from __future__ import annotations

import base64
import gzip
import hashlib
import json
import pathlib
import subprocess
import sys

PROJECT = pathlib.Path(__file__).resolve().parents[1]
EXPECTED_HISTORICAL_SHA256 = "49a8cd1a01c6c5250bb16a6d2b449f1546c58f0d3ed9240303446bc605dc965a"
PART_GLOB = "p4_001_materialize_payload.part*"
STALE_PATHS = (
    ".github/workflows/p4-001-finalize-evidence.yml",
    ".github/workflows/p4-001-pr-handoff.yml",
    ".github/workflows/p4-001-publish-candidate.yml",
    "tool/p4_001_materialize_canonical.py",
)


def run(*argv: str) -> None:
    subprocess.run(argv, cwd=PROJECT, check=True)


def main() -> int:
    historical_source = PROJECT / "release/evidence/P4-001/test-center-handoff.json"
    historical_bytes = historical_source.read_bytes()
    observed = hashlib.sha256(historical_bytes).hexdigest()
    if observed != EXPECTED_HISTORICAL_SHA256:
        raise SystemExit(
            f"provisional handoff bytes changed: expected={EXPECTED_HISTORICAL_SHA256}, observed={observed}"
        )
    historical_target = (
        PROJECT
        / "release/evidence/P4-001/history/test-center-handoff.provisional.0.1.1.json"
    )
    historical_target.parent.mkdir(parents=True, exist_ok=True)
    historical_target.write_bytes(historical_bytes)

    part_paths = sorted((PROJECT / "tool").glob(PART_GLOB))
    if not part_paths:
        raise SystemExit("canonical payload parts are missing")
    encoded = "".join(path.read_text(encoding="ascii") for path in part_paths)
    documents = json.loads(gzip.decompress(base64.b64decode(encoded)))
    if not isinstance(documents, dict):
        raise SystemExit("canonical payload must be an object")
    for relative, file_content in documents.items():
        target = PROJECT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(file_content, encoding="utf-8", newline="\n")

    # Use one canonical module identity in both executable and unittest imports.
    adapter_path = PROJECT / "tool/p4_001_test_center_v1.py"
    adapter_text = adapter_path.read_text(encoding="utf-8")
    old_import = (
        "sys.path.insert(0, str(Path(__file__).resolve().parent))\n"
        "import test_center_contracts as canonical\n"
    )
    new_import = (
        "PROJECT_ROOT = Path(__file__).resolve().parents[1]\n"
        "sys.path.insert(0, str(PROJECT_ROOT))\n"
        "from tool import test_center_contracts as canonical\n"
    )
    if old_import not in adapter_text:
        raise SystemExit("canonical adapter import anchor is missing")
    adapter_path.write_text(
        adapter_text.replace(old_import, new_import, 1),
        encoding="utf-8",
        newline="\n",
    )

    for relative in STALE_PATHS:
        target = PROJECT / relative
        if target.exists():
            target.unlink()
    for path in part_paths:
        path.unlink()

    run(sys.executable, "tool/test_center_contracts.py", "check", "--project", ".")
    run(sys.executable, "-m", "unittest", "-v", "tool/test_center_contracts_test.py")
    run(sys.executable, "tool/p4_001_test_center_v1.py", "check", "--project", ".")
    run(sys.executable, "-m", "unittest", "-v", "tool/p4_001_test_center_v1_test.py")
    run(
        sys.executable,
        "tool/p4_001_search_provider_test.py",
        "--project",
        ".",
        "--json-output",
        str(PROJECT / "release/evidence/generated/P4-001/materialization-source-result.json"),
    )
    generated_result = PROJECT / "release/evidence/generated/P4-001/materialization-source-result.json"
    if generated_result.exists():
        generated_result.unlink()
    generated_dir = PROJECT / "release/evidence/generated/P4-001"
    if generated_dir.exists() and not any(generated_dir.iterdir()):
        generated_dir.rmdir()

    run(sys.executable, "tool/p1a_refresh_source_manifest.py", ".")
    first = (PROJECT / "SOURCE_MANIFEST.sha256").read_bytes()
    run(sys.executable, "tool/p1a_refresh_source_manifest.py", ".")
    second = (PROJECT / "SOURCE_MANIFEST.sha256").read_bytes()
    if first != second:
        raise SystemExit("source manifest second generation is not byte-identical")
    run(sys.executable, "tool/roadmap_control.py", "validate", "--project", ".", "--strict")
    run(sys.executable, "tool/generated_state_guard.py", "audit", "--project", ".", "--strict")
    run(sys.executable, "tool/source_tree_policy_test.py")
    run("git", "diff", "--check")
    print(
        json.dumps(
            {
                "status": "PASS",
                "canonicalContractStatus": "CANONICAL_TEST_CENTER_V1",
                "historicalHandoffSha256": observed,
                "sourceManifestSha256": hashlib.sha256(second).hexdigest(),
                "materializedPathCount": len(documents),
                "payloadPartCount": len(part_paths),
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
