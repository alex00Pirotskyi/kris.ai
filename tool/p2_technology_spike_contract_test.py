#!/usr/bin/env python3
"""Regression coverage for the governed P2-004 technology-spike handoff.

The test proves both fail-closed behavior when a candidate receipt is absent
and a complete pass path when three independently hashed candidate receipts
are supplied through the controlled task-runner environment.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import platform
import subprocess
import sys
import tempfile

PLATFORM = {
    "Windows": "windows",
    "Darwin": "macos",
    "Linux": "linux",
}[platform.system()]
CANDIDATES = [
    (
        "typescript-node-node-pty-with-native-lifecycle-adapters",
        "node-node-pty",
        "KRISTIN_P2_TECH_NODE_RECEIPT",
        30,
    ),
    (
        "native-platform-pty-supervisor",
        "native-pty-supervisor",
        "KRISTIN_P2_TECH_NATIVE_RECEIPT",
        20,
    ),
    (
        "dart-control-plane-native-pty-helper",
        "dart-independent-control-plane",
        "KRISTIN_P2_TECH_DART_RECEIPT",
        40,
    ),
]
EXPECTED_SELECTED = "native-platform-pty-supervisor"
BOUND_PATHS = {
    "tool/p2_task_platform_assertions.py",
    "tool/p2_technology_spike.py",
    "tool/p2_technology_spike_contract_test.py",
    "docs/operations/P2_TECHNOLOGY_CANDIDATE_RECEIPT_TEMPLATE.json",
    ".github/workflows/p2-owner-mode.yml",
    ".github/workflows/worker-a-p2-004-measurement-contract.yml",
}


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: pathlib.Path) -> str:
    return sha256_bytes(path.read_bytes())


def stable_hash(label: str) -> str:
    return sha256_bytes(label.encode("utf-8"))


def write_json(path: pathlib.Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def make_receipt(
    root: pathlib.Path,
    *,
    candidate_id: str,
    family: str,
    commit: str,
    metric_base: int,
) -> pathlib.Path:
    artifact_root = (root / candidate_id / "artifacts").resolve()
    artifact_root.mkdir(parents=True, exist_ok=True)
    rounds = []
    for round_id in (1, 2, 3):
        evidence = artifact_root / f"round-{round_id}.json"
        write_json(
            evidence,
            {
                "candidateId": candidate_id,
                "platform": PLATFORM,
                "roundId": round_id,
                "status": "passed",
            },
        )
        backlog = stable_hash(f"{candidate_id}:backlog:{round_id}")
        rounds.append(
            {
                "roundId": round_id,
                "status": "passed",
                "coldStartMs": metric_base + round_id,
                "steadyRssKiB": (metric_base * 100) + round_id,
                "packageSizeBytes": (metric_base * 1000) + round_id,
                "detachReconnect": {
                    "consumerDetached": True,
                    "outputWhileDetached": True,
                    "reconnectedByDurableCursor": True,
                    "backlogReplayExact": True,
                    "noDuplicationOrLoss": True,
                    "detachedCursor": round_id,
                    "reconnectCursor": round_id + 1,
                    "outputWhileDetachedBytes": round_id,
                    "expectedBacklogSha256": backlog,
                    "observedBacklogSha256": backlog,
                    "duplicateSequenceCount": 0,
                    "missingSequenceCount": 0,
                },
                "processTree": {
                    "descendantCreated": True,
                    "identityVerified": True,
                    "descendantProcessIdentities": [
                        {
                            "pid": 1000 + round_id,
                            "startIdentity": f"{candidate_id}:{round_id}",
                        }
                    ],
                    "terminationStatus": "killed",
                    "remainingDescendants": [],
                    "zeroSurvivingDescendants": True,
                },
                "evidencePath": evidence.name,
                "evidenceSha256": sha256_file(evidence),
            }
        )
    receipt = {
        "schemaVersion": "4.0.0",
        "receiptType": "p2-technology-candidate-observation-v4",
        "candidateId": candidate_id,
        "implementationFamily": family,
        "platform": PLATFORM,
        "commitSha": commit,
        "status": "passed",
        "sourceOnly": False,
        "independentlyExecuted": True,
        "sourceTreeSha256": stable_hash(f"{candidate_id}:source"),
        "implementationSha256": stable_hash(f"{candidate_id}:implementation"),
        "executableSha256": stable_hash(f"{candidate_id}:executable"),
        "buildReceiptSha256": stable_hash(f"{candidate_id}:build"),
        "packagingReceiptSha256": stable_hash(f"{candidate_id}:package"),
        "artifactRoot": str(artifact_root),
        "independentControlPlaneImplementation": candidate_id.startswith("dart-"),
        "delegatedProbeReceiptSha256": None,
        "rounds": rounds,
        "packaging": {
            "threePlatformReliable": True,
            "codeSigningImpactMeasured": True,
            "updaterImpactMeasured": True,
        },
        "platformFidelity": {
            "ptyInteractiveInput": True,
            "resize": True,
            "ansiUnicode": True,
        },
    }
    receipt_path = root / candidate_id / "receipt.json"
    write_json(receipt_path, receipt)
    return receipt_path.resolve()


def run_task(
    root: pathlib.Path,
    *,
    commit: str,
    artifact_root: pathlib.Path,
    environment: dict[str, str],
) -> tuple[subprocess.CompletedProcess[str], dict]:
    output = artifact_root / "task-results" / PLATFORM / "P2-004.json"
    command = [
        sys.executable,
        str(root / "tool/p2_task_platform_assertions.py"),
        "--project",
        str(root),
        "--task",
        "P2-004",
        "--commit-sha",
        commit,
        "--output",
        str(output),
        "--artifact-root",
        str(artifact_root),
        "--max-command-seconds",
        "120",
    ]
    completed = subprocess.run(
        command,
        text=True,
        capture_output=True,
        timeout=240,
        env=environment,
    )
    if not output.is_file():
        raise SystemExit(
            "P2-004 task runner did not emit a result\n"
            f"stdout={completed.stdout[-4000:]}\n"
            f"stderr={completed.stderr[-4000:]}"
        )
    return completed, json.loads(output.read_text(encoding="utf-8"))


def assert_template_and_registry(root: pathlib.Path) -> None:
    template = json.loads(
        (
            root
            / "docs/operations/P2_TECHNOLOGY_CANDIDATE_RECEIPT_TEMPLATE.json"
        ).read_text(encoding="utf-8")
    )
    rounds = template.get("rounds")
    if not isinstance(rounds, list) or [
        row.get("roundId") for row in rounds if isinstance(row, dict)
    ] != [1, 2, 3]:
        raise SystemExit("P2 technology receipt template must define rounds 1, 2, and 3")
    if len({row.get("evidencePath") for row in rounds}) != 3:
        raise SystemExit("P2 technology receipt template evidence paths must be unique")

    registry = json.loads(
        (root / "config/test_center_registry.v1.json").read_text(encoding="utf-8")
    )
    profile = next(
        (
            row
            for row in registry.get("projectTestProfiles", [])
            if isinstance(row, dict)
            and row.get("stableCheckId") == "tc.p2.acceptance-contract"
        ),
        None,
    )
    if not isinstance(profile, dict):
        raise SystemExit("canonical tc.p2.acceptance-contract profile missing")
    if not BOUND_PATHS <= set(profile.get("inputPaths", [])):
        raise SystemExit("P2-004 contract sources are not bound into Test Center inputs")
    if not BOUND_PATHS <= set(profile.get("affectedPaths", [])):
        raise SystemExit("P2-004 contract sources are not bound into affected selection")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    args = parser.parse_args()
    root = pathlib.Path(args.project).resolve()
    assert_template_and_registry(root)
    commit = "4" * 40

    with tempfile.TemporaryDirectory(prefix="p2-004-contract-") as raw:
        temp = pathlib.Path(raw).resolve()
        receipts: dict[str, pathlib.Path] = {}
        for candidate_id, family, env_name, metric_base in CANDIDATES:
            receipts[env_name] = make_receipt(
                temp,
                candidate_id=candidate_id,
                family=family,
                commit=commit,
                metric_base=metric_base,
            )

        base_environment = dict(os.environ)
        base_environment["KRISTIN_P2_COMMIT_SHA"] = commit

        blocked_environment = dict(base_environment)
        for env_name, receipt in receipts.items():
            if env_name != "KRISTIN_P2_TECH_DART_RECEIPT":
                blocked_environment[env_name] = str(receipt)
        blocked_process, blocked = run_task(
            root,
            commit=commit,
            artifact_root=temp / "blocked-artifact",
            environment=blocked_environment,
        )
        if blocked_process.returncode != 3 or blocked.get("status") != "blocked":
            raise SystemExit("missing P2-004 candidate receipt must fail closed")

        passing_environment = dict(base_environment)
        passing_environment.update(
            {env_name: str(receipt) for env_name, receipt in receipts.items()}
        )
        passed_process, passed = run_task(
            root,
            commit=commit,
            artifact_root=temp / "passed-artifact",
            environment=passing_environment,
        )
        if passed_process.returncode != 0 or passed.get("status") != "passed":
            raise SystemExit(
                "valid P2-004 candidate receipts did not traverse the task runner\n"
                f"stdout={passed_process.stdout[-4000:]}\n"
                f"stderr={passed_process.stderr[-4000:]}"
            )
        assertions = {
            row.get("assertionId"): row
            for row in passed.get("assertions", [])
            if isinstance(row, dict)
        }
        spike = assertions.get("p2-004.equivalent-platform-spike")
        if not isinstance(spike, dict) or spike.get("observedStatus") != "passed":
            raise SystemExit("P2-004 technology-spike assertion did not pass")
        observation_path = spike.get("observationArtifactPath")
        if not isinstance(observation_path, str):
            raise SystemExit("P2-004 normalized technology observation missing")
        observation = json.loads(
            (temp / "passed-artifact" / pathlib.PurePosixPath(observation_path)).read_text(
                encoding="utf-8"
            )
        )
        decision = observation.get("decision")
        if (
            not isinstance(decision, dict)
            or decision.get("status") != "platform_measurement_complete"
            or decision.get("selected") != EXPECTED_SELECTED
            or decision.get("requiresTriOsAggregation") is not True
        ):
            raise SystemExit("P2-004 deterministic measured selection is invalid")

    print("P2-004 technology-spike receipt bridge and fail-closed contract: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
