#!/usr/bin/env python3
"""Prove synthetic/forged evidence can never finalize P2.

Contract fixtures may exercise validator shape only when an explicit test-only
flag is supplied. The release finalizer never supplies that flag. This test
invokes the real finalizer with a fully populated synthetic graph and requires a
fail-closed result before any completed task packet or aggregate PASS appears.
"""
from __future__ import annotations

import argparse
import copy
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

from p2_contract_fixture_support import build_platform_receipt, write_json
from p2_evidence_contract import PLATFORMS, TASKS, sha256_file, validate_platform_receipt

COMMIT = "2" * 40
TREE = "3" * 40
PACKAGE = "4" * 64
BASE = "5" * 40
BASE_TREE = "6" * 40


def rejected(path: pathlib.Path, label: str, *, allow_synthetic: bool = False) -> None:
    try:
        validate_platform_receipt(
            path,
            commit_sha=COMMIT,
            allow_synthetic_contract_fixture=allow_synthetic,
        )
    except SystemExit:
        return
    raise SystemExit(f"{label}: forged/synthetic receipt was accepted")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    args = parser.parse_args()
    source = pathlib.Path(args.project).resolve()
    if not (source / "tool/p2_finalize_evidence.py").is_file():
        raise SystemExit("strict finalizer prerequisite missing")

    with tempfile.TemporaryDirectory(prefix="p2-v63-finalizer-contract-") as temp_value:
        temp = pathlib.Path(temp_value)
        project = temp / "project"
        shutil.copytree(
            source,
            project,
            ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".dart_tool", "build", "node_modules"),
        )
        shutil.rmtree(project / "tasks/completed", ignore_errors=True)
        (project / "tasks/completed").mkdir(parents=True, exist_ok=True)
        receipts_dir = temp / "receipts"
        receipts = [build_platform_receipt(receipts_dir, platform, COMMIT) for platform in PLATFORMS]

        # Contract fixtures still exercise the deep shape validator explicitly.
        for receipt in receipts:
            validate_platform_receipt(
                receipt,
                commit_sha=COMMIT,
                allow_synthetic_contract_fixture=True,
            )
            rejected(receipt, "synthetic release promotion")

        original = json.loads(receipts[0].read_text(encoding="utf-8"))
        variants = []
        string_only = copy.deepcopy(original)
        string_only["taskAssertions"]["P2-001"]["assertions"] = ["description only"]
        variants.append(("string-only", string_only))
        source_only = copy.deepcopy(original)
        source_only["sourceOnly"] = True
        variants.append(("source-only", source_only))
        noninteractive = copy.deepcopy(original)
        noninteractive["interactiveDesktopAttested"] = False
        variants.append(("noninteractive", noninteractive))
        for label, value in variants:
            target = temp / f"{label}.json"
            write_json(target, value)
            rejected(target, label, allow_synthetic=True)

        digests = {platform: sha256_file(path) for platform, path in zip(PLATFORMS, receipts, strict=True)}
        review_artifact = temp / "review.md"
        review_artifact.write_text("synthetic contract fixture only\n", encoding="utf-8")
        review = temp / "review.json"
        write_json(review, {
            "schemaVersion": "2.0.0", "independent": True,
            "reviewerName": "Synthetic Contract Reviewer",
            "reviewerOrganizationOrRelationship": "schema fixture",
            "decision": "approve", "reviewedCommit": COMMIT,
            "reviewedTree": TREE, "packageSha256": PACKAGE,
            "baseMainSha": BASE, "baseMainTree": BASE_TREE,
            "p1BaseVerificationSha256": "7" * 64,
            "platformReceiptSha256": digests,
            "criticalHighFindingsRemaining": [], "conditions": [],
            "satisfiedConditions": [],
            "reviewArtifactReference": str(review_artifact),
            "reviewArtifactSha256": sha256_file(review_artifact),
            "reviewDate": "2026-07-28T00:00:00Z",
            "syntheticContractFixture": True,
        })
        owner = temp / "owner.json"
        write_json(owner, {
            "schemaVersion": "1.0.0", "approved": True,
            "ownerName": "Synthetic Contract Owner",
            "approvedAt": "2026-07-28T00:00:00Z",
            "reviewedCommit": COMMIT, "reviewedTree": TREE,
            "packageSha256": PACKAGE,
            "baseMainSha": BASE, "baseMainTree": BASE_TREE,
            "p1BaseVerificationSha256": "7" * 64,
            "acknowledgesFullCurrentAccountAuthority": True,
            "acknowledgesNotSandboxed": True,
            "acknowledgesIndependentReviewAndExactReceipts": True,
            "syntheticContractFixture": True,
        })
        p1_base = temp / "p1-base.json"
        write_json(p1_base, {
            "schemaVersion":"3.0.0",
            "receiptType":"kristin-p1-p1a-exact-base-verification-v3",
            "status":"passed",
            "baseCommit":BASE,
            "baseTree":BASE_TREE,
            "aggregateManifestSha256":"a"*64,
            "executedExitResultSha256":"b"*64,
            "p1aStatus":"passed",
            "p1aCompletionClaim":True,
            "p1aDependencySatisfied":True,
            "p1aTaskCompleted":True,
            "p1aMergedMainCommit":BASE,
            "p1aAggregateManifestSha256":"8"*64,
            "p1aExecutedExitResultSha256":"9"*64,
            "p1aEvidenceTrustSha256":"c"*64,
            "p1aPlatformReceiptSha256":{platform: chr(100 + index) * 64 for index, platform in enumerate(PLATFORMS)},
            "p1aPlatformComponentGraph":{platform:{"runnerAttestation":chr(103 + index)*64,"buildProvenance":chr(106 + index)*64,"installerReceipt":chr(109 + index)*64,"serviceBehaviorReceipt":chr(112 + index)*64,"workerDenialReceipt":chr(115 + index)*64,"cleanupReceipt":chr(118 + index)*64} for index, platform in enumerate(PLATFORMS)},
            "p1aRequiredBehavioralJobs":["p1a-behavioral-windows","p1a-behavioral-macos","p1a-behavioral-linux"],
            "p1aIndependentSecurityReview":{"decision":"approve","artifactSha256":"f"*64},
        })
        p1_digest = sha256_file(p1_base)
        review_value = json.loads(review.read_text()); review_value["p1BaseVerificationSha256"] = p1_digest; write_json(review, review_value)
        owner_value = json.loads(owner.read_text()); owner_value["p1BaseVerificationSha256"] = p1_digest; write_json(owner, owner_value)
        command = [
            sys.executable, str(project / "tool/p2_finalize_evidence.py"),
            "--project", str(project), "--reviewed-sha", COMMIT,
            "--reviewed-tree", TREE, "--package-sha256", PACKAGE,
            "--owner-approval", str(owner), "--security-review", str(review),
            "--base-main-sha", BASE, "--base-main-tree", BASE_TREE,
            "--p1-base-verification", str(p1_base),
        ]
        for receipt in receipts:
            command.extend(["--platform-receipt", str(receipt)])
        completed = subprocess.run(command, text=True, capture_output=True)
        if completed.returncode == 0:
            raise SystemExit("strict finalizer accepted synthetic completion graph")
        packets = list((project / "tasks/completed").glob("P2-*.md"))
        if packets:
            raise SystemExit(f"strict finalizer created synthetic task packets: {packets}")
        aggregate_path = project / "release/evidence/P2/manifest.json"
        if aggregate_path.is_file():
            aggregate = json.loads(aggregate_path.read_text(encoding="utf-8"))
            if aggregate.get("status") == "passed":
                raise SystemExit("strict finalizer promoted synthetic aggregate to passed")
        for task in TASKS:
            manifest = project / "release/evidence" / task / "manifest.json"
            if manifest.is_file() and json.loads(manifest.read_text()).get("status") == "passed":
                raise SystemExit(f"strict finalizer promoted synthetic {task}")

    print("P2 V63 strict finalizer synthetic/forgery no-promotion contract: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
