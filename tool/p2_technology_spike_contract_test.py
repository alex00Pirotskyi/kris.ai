#!/usr/bin/env python3
"""Fail-closed regression for the governed P2-004 measurement handoff.

The regression traverses the real task runner and proves that candidate
observations are accepted only when they are uniquely identified, fresh,
contained under an authorized root, and bound to an independently pinned trust
manifest. Missing, duplicate, self-consistently tampered, replayed, out-of-root,
and symlink-escaping inputs must remain blocked.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import platform
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from typing import Any

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
TRUST_ENV_NAMES = {
    "KRISTIN_P2_TECH_NODE_RECEIPT",
    "KRISTIN_P2_TECH_NATIVE_RECEIPT",
    "KRISTIN_P2_TECH_DART_RECEIPT",
    "KRISTIN_P2_TECH_AUTHORIZED_ROOT",
    "KRISTIN_P2_TECH_TRUST_MANIFEST",
    "KRISTIN_P2_TECH_TRUST_MANIFEST_SHA256",
    "KRISTIN_P2_TECH_SESSION_ID",
    "KRISTIN_P2_TECH_NONCE",
    "GITHUB_RUN_ID",
    "GITHUB_RUN_ATTEMPT",
}
BOUND_PATHS = {
    "tool/p2_task_platform_assertions.py",
    "tool/p2_technology_spike.py",
    "tool/p2_technology_spike_contract_test.py",
    "docs/operations/P2_TECHNOLOGY_CANDIDATE_RECEIPT_TEMPLATE.json",
    "docs/operations/P2_TECHNOLOGY_MEASUREMENT_TRUST_TEMPLATE.json",
    ".github/workflows/p2-owner-mode.yml",
    ".github/workflows/worker-a-p2-004-measurement-contract.yml",
}


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: pathlib.Path) -> str:
    return sha256_bytes(path.read_bytes())


def stable_hash(label: str) -> str:
    return sha256_bytes(label.encode("utf-8"))


def format_utc(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec="seconds").replace(
        "+00:00", "Z"
    )


def write_json(path: pathlib.Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def read_json(path: pathlib.Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise SystemExit(f"JSON object required: {path}")
    return value


def relative(root: pathlib.Path, path: pathlib.Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


def make_bundle(
    case_root: pathlib.Path,
    *,
    commit: str,
    duplicate_round_identity: bool = False,
    stale: bool = False,
) -> dict[str, Any]:
    authorized_root = (case_root / "authorized").resolve()
    authorized_root.mkdir(parents=True, exist_ok=True)
    now = datetime.now(timezone.utc)
    if stale:
        issued_at = now - timedelta(hours=8)
        expires_at = now - timedelta(hours=7)
        observation_base = now - timedelta(hours=7, minutes=55)
    else:
        issued_at = now - timedelta(minutes=5)
        expires_at = now + timedelta(hours=1)
        observation_base = now - timedelta(minutes=4)

    session_id = f"p2-contract-{case_root.name}"
    run_id = "9001001"
    run_attempt = 1
    nonce = stable_hash(f"{session_id}:nonce")
    receipt_paths: dict[str, pathlib.Path] = {}
    trust_candidates: list[dict[str, Any]] = []

    for candidate_id, family, env_name, metric_base in CANDIDATES:
        candidate_root = authorized_root / candidate_id
        artifact_root = (candidate_root / "artifacts").resolve()
        artifact_root.mkdir(parents=True, exist_ok=True)
        rounds: list[dict[str, Any]] = []
        trusted_rounds: list[dict[str, Any]] = []
        first_round: dict[str, Any] | None = None
        first_evidence: pathlib.Path | None = None

        for round_id in (1, 2, 3):
            observed_at = observation_base + timedelta(seconds=round_id)
            observation_id = f"{candidate_id}:{PLATFORM}:{session_id}:round-{round_id}"
            evidence = artifact_root / f"round-{round_id}.json"
            write_json(
                evidence,
                {
                    "candidateId": candidate_id,
                    "platform": PLATFORM,
                    "measurementSessionId": session_id,
                    "workflowRunId": run_id,
                    "workflowRunAttempt": run_attempt,
                    "observationId": observation_id,
                    "observedAt": format_utc(observed_at),
                    "roundId": round_id,
                    "status": "passed",
                },
            )
            backlog = stable_hash(f"{candidate_id}:backlog:{round_id}")
            round_row: dict[str, Any] = {
                "roundId": round_id,
                "observationId": observation_id,
                "observedAt": format_utc(observed_at),
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
            trusted_evidence = evidence
            if duplicate_round_identity and candidate_id == CANDIDATES[0][0] and round_id == 2:
                if first_round is None or first_evidence is None:
                    raise SystemExit("duplicate fixture was not initialized")
                round_row["observationId"] = first_round["observationId"]
                round_row["observedAt"] = first_round["observedAt"]
                round_row["evidencePath"] = first_round["evidencePath"]
                round_row["evidenceSha256"] = first_round["evidenceSha256"]
                trusted_evidence = first_evidence
            if round_id == 1:
                first_round = dict(round_row)
                first_evidence = evidence
            rounds.append(round_row)
            trusted_rounds.append(
                {
                    "roundId": round_id,
                    "observationId": round_row["observationId"],
                    "observedAt": round_row["observedAt"],
                    "evidencePath": relative(authorized_root, trusted_evidence),
                    "evidenceSha256": round_row["evidenceSha256"],
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
            "measurementSessionId": session_id,
            "workflowRunId": run_id,
            "workflowRunAttempt": run_attempt,
            "nonce": nonce,
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
        receipt_path = candidate_root / "receipt.json"
        write_json(receipt_path, receipt)
        receipt_path = receipt_path.resolve()
        receipt_paths[env_name] = receipt_path
        trust_candidates.append(
            {
                "candidateId": candidate_id,
                "receiptPath": relative(authorized_root, receipt_path),
                "receiptSha256": sha256_file(receipt_path),
                "artifactRoot": relative(authorized_root, artifact_root),
                "rounds": trusted_rounds,
            }
        )

    manifest = {
        "schemaVersion": "1.0.0",
        "manifestType": "p2-technology-measurement-trust-v1",
        "platform": PLATFORM,
        "commitSha": commit,
        "measurementSessionId": session_id,
        "workflowRunId": run_id,
        "workflowRunAttempt": run_attempt,
        "nonce": nonce,
        "issuedAt": format_utc(issued_at),
        "expiresAt": format_utc(expires_at),
        "candidateReceipts": trust_candidates,
    }
    manifest_path = authorized_root / "measurement-trust.json"
    write_json(manifest_path, manifest)
    manifest_path = manifest_path.resolve()

    environment = clean_environment()
    environment.update(
        {
            "KRISTIN_P2_COMMIT_SHA": commit,
            "KRISTIN_P2_TECH_AUTHORIZED_ROOT": str(authorized_root),
            "KRISTIN_P2_TECH_TRUST_MANIFEST": str(manifest_path),
            "KRISTIN_P2_TECH_TRUST_MANIFEST_SHA256": sha256_file(manifest_path),
            "KRISTIN_P2_TECH_SESSION_ID": session_id,
            "KRISTIN_P2_TECH_NONCE": nonce,
            "GITHUB_RUN_ID": run_id,
            "GITHUB_RUN_ATTEMPT": str(run_attempt),
            **{name: str(path) for name, path in receipt_paths.items()},
        }
    )
    return {
        "authorizedRoot": authorized_root,
        "manifestPath": manifest_path,
        "environment": environment,
        "receiptPaths": receipt_paths,
    }


def clean_environment() -> dict[str, str]:
    environment = dict(os.environ)
    for name in TRUST_ENV_NAMES:
        environment.pop(name, None)
    return environment


def update_manifest_digest(bundle: dict[str, Any]) -> None:
    manifest_path = pathlib.Path(bundle["manifestPath"])
    bundle["environment"]["KRISTIN_P2_TECH_TRUST_MANIFEST_SHA256"] = sha256_file(
        manifest_path
    )


def run_task(
    root: pathlib.Path,
    *,
    commit: str,
    artifact_root: pathlib.Path,
    environment: dict[str, str],
) -> tuple[subprocess.CompletedProcess[str], dict[str, Any]]:
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
    return completed, read_json(output)


def assert_blocked(
    root: pathlib.Path,
    *,
    case_name: str,
    commit: str,
    bundle: dict[str, Any],
) -> None:
    process, result = run_task(
        root,
        commit=commit,
        artifact_root=pathlib.Path(bundle["authorizedRoot"]) / f"task-{case_name}",
        environment=dict(bundle["environment"]),
    )
    if process.returncode != 3 or result.get("status") != "blocked":
        raise SystemExit(
            f"{case_name}: untrusted P2-004 input must fail closed\n"
            f"stdout={process.stdout[-4000:]}\n"
            f"stderr={process.stderr[-4000:]}"
        )


def assert_template_and_registry(root: pathlib.Path) -> None:
    receipt_template = read_json(
        root / "docs/operations/P2_TECHNOLOGY_CANDIDATE_RECEIPT_TEMPLATE.json"
    )
    rounds = receipt_template.get("rounds")
    if not isinstance(rounds, list) or [
        row.get("roundId") for row in rounds if isinstance(row, dict)
    ] != [1, 2, 3]:
        raise SystemExit("P2 technology receipt template must define rounds 1, 2, and 3")
    for key in (
        "measurementSessionId",
        "workflowRunId",
        "workflowRunAttempt",
        "nonce",
    ):
        if key not in receipt_template:
            raise SystemExit(f"P2 technology receipt template missing {key}")
    if len({row.get("observationId") for row in rounds}) != 3:
        raise SystemExit("P2 technology receipt observation identities must be unique")
    if len({row.get("evidencePath") for row in rounds}) != 3:
        raise SystemExit("P2 technology receipt evidence paths must be unique")

    trust_template = read_json(
        root / "docs/operations/P2_TECHNOLOGY_MEASUREMENT_TRUST_TEMPLATE.json"
    )
    if (
        trust_template.get("schemaVersion") != "1.0.0"
        or trust_template.get("manifestType")
        != "p2-technology-measurement-trust-v1"
    ):
        raise SystemExit("P2 technology trust template identity invalid")
    trusted_candidates = trust_template.get("candidateReceipts")
    if not isinstance(trusted_candidates, list) or len(trusted_candidates) != 3:
        raise SystemExit("P2 technology trust template must bind all three candidates")

    registry = read_json(root / "config/test_center_registry.v1.json")
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


def tamper_self_consistently(bundle: dict[str, Any]) -> None:
    receipt_path = pathlib.Path(
        bundle["receiptPaths"]["KRISTIN_P2_TECH_NODE_RECEIPT"]
    )
    receipt = read_json(receipt_path)
    artifact_root = pathlib.Path(str(receipt["artifactRoot"]))
    evidence = artifact_root / str(receipt["rounds"][0]["evidencePath"])
    write_json(evidence, {"tampered": True, "stillSelfConsistent": True})
    receipt["rounds"][0]["evidenceSha256"] = sha256_file(evidence)
    write_json(receipt_path, receipt)
    # Deliberately do not update the independently pinned trust manifest/digest.


def move_receipt_outside_root(case_root: pathlib.Path, bundle: dict[str, Any]) -> None:
    source = pathlib.Path(
        bundle["receiptPaths"]["KRISTIN_P2_TECH_NODE_RECEIPT"]
    )
    outside = case_root / "outside-receipt.json"
    shutil.copy2(source, outside)
    bundle["environment"]["KRISTIN_P2_TECH_NODE_RECEIPT"] = str(outside.resolve())


def make_symlink_escape(case_root: pathlib.Path, bundle: dict[str, Any]) -> None:
    receipt_path = pathlib.Path(
        bundle["receiptPaths"]["KRISTIN_P2_TECH_NODE_RECEIPT"]
    )
    receipt = read_json(receipt_path)
    artifact_root = pathlib.Path(str(receipt["artifactRoot"]))
    evidence = artifact_root / str(receipt["rounds"][0]["evidencePath"])
    outside = (case_root / "outside-evidence.json").resolve()
    write_json(outside, {"outside": True, "status": "passed"})
    evidence.unlink()
    try:
        evidence.symlink_to(outside)
    except OSError as exc:
        raise SystemExit(
            f"platform could not create required symlink-escape regression fixture: {exc}"
        ) from exc
    escaped_sha = sha256_file(outside)
    receipt["rounds"][0]["evidenceSha256"] = escaped_sha
    write_json(receipt_path, receipt)

    manifest_path = pathlib.Path(bundle["manifestPath"])
    manifest = read_json(manifest_path)
    candidate = manifest["candidateReceipts"][0]
    candidate["receiptSha256"] = sha256_file(receipt_path)
    candidate["rounds"][0]["evidenceSha256"] = escaped_sha
    write_json(manifest_path, manifest)
    update_manifest_digest(bundle)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    args = parser.parse_args()
    root = pathlib.Path(args.project).resolve()
    assert_template_and_registry(root)
    commit = "4" * 40

    with tempfile.TemporaryDirectory(prefix="p2-004-trust-contract-") as raw:
        temp = pathlib.Path(raw).resolve()

        missing = make_bundle(temp / "missing", commit=commit)
        missing["environment"].pop("KRISTIN_P2_TECH_DART_RECEIPT", None)
        assert_blocked(
            root,
            case_name="missing-receipt",
            commit=commit,
            bundle=missing,
        )

        duplicate = make_bundle(
            temp / "duplicate",
            commit=commit,
            duplicate_round_identity=True,
        )
        assert_blocked(
            root,
            case_name="duplicate-round-identity",
            commit=commit,
            bundle=duplicate,
        )

        tampered = make_bundle(temp / "tampered", commit=commit)
        tamper_self_consistently(tampered)
        assert_blocked(
            root,
            case_name="self-consistent-tamper",
            commit=commit,
            bundle=tampered,
        )

        replayed = make_bundle(temp / "replayed", commit=commit, stale=True)
        assert_blocked(
            root,
            case_name="stale-replay",
            commit=commit,
            bundle=replayed,
        )

        out_of_root = make_bundle(temp / "out-of-root", commit=commit)
        move_receipt_outside_root(temp / "out-of-root", out_of_root)
        assert_blocked(
            root,
            case_name="out-of-root-receipt",
            commit=commit,
            bundle=out_of_root,
        )

        symlink_escape = make_bundle(temp / "symlink", commit=commit)
        make_symlink_escape(temp / "symlink", symlink_escape)
        assert_blocked(
            root,
            case_name="symlink-escape",
            commit=commit,
            bundle=symlink_escape,
        )

        passing = make_bundle(temp / "passing", commit=commit)
        passed_process, passed = run_task(
            root,
            commit=commit,
            artifact_root=pathlib.Path(passing["authorizedRoot"]) / "task-passing",
            environment=dict(passing["environment"]),
        )
        if passed_process.returncode != 0 or passed.get("status") != "passed":
            raise SystemExit(
                "valid trusted P2-004 candidate receipts did not traverse the task runner\n"
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
        observation = read_json(
            pathlib.Path(passing["authorizedRoot"])
            / "task-passing"
            / pathlib.PurePosixPath(observation_path)
        )
        decision = observation.get("decision")
        trust = observation.get("trust")
        if (
            not isinstance(decision, dict)
            or decision.get("status") != "platform_measurement_complete"
            or decision.get("selected") != EXPECTED_SELECTED
            or decision.get("requiresTriOsAggregation") is not True
            or not isinstance(trust, dict)
            or trust.get("measurementSessionId")
            != passing["environment"]["KRISTIN_P2_TECH_SESSION_ID"]
            or trust.get("workflowRunId") != passing["environment"]["GITHUB_RUN_ID"]
        ):
            raise SystemExit("P2-004 trusted deterministic measured selection is invalid")

    print(
        "P2-004 trusted receipt integrity, freshness, uniqueness, containment, "
        "and fail-closed contract: PASS"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
