#!/usr/bin/env python3
"""Aggregate independently executed equivalent P2 automation-host candidates.

This tool never infers detach/reconnect or process-tree termination from a sleep,
a primary PID exit, or a wrapper's boolean. Each candidate must supply three
machine-observed rounds bound to the exact commit, platform, executable, build,
source, authorized artifact root, independently pinned trust manifest, fresh
measurement session, cursor/backlog replay, and zero-descendant kill result.
Missing, replayed, self-consistent-but-untrusted, aliased, or path-escaping
observations produce a blocked decision.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import platform
import re
import statistics
import time
from datetime import datetime, timedelta, timezone
from typing import Any

CANDIDATES = {
    "typescript-node-node-pty-with-native-lifecycle-adapters": (
        "node-node-pty",
        "KRISTIN_P2_TECH_NODE_RECEIPT",
    ),
    "native-platform-pty-supervisor": (
        "native-pty-supervisor",
        "KRISTIN_P2_TECH_NATIVE_RECEIPT",
    ),
    "dart-control-plane-native-pty-helper": (
        "dart-independent-control-plane",
        "KRISTIN_P2_TECH_DART_RECEIPT",
    ),
}
PLATFORM = {
    "Windows": "windows",
    "Darwin": "macos",
    "Linux": "linux",
}.get(platform.system(), platform.system().lower())
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
SAFE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
MAX_TRUST_LIFETIME = timedelta(hours=6)
MAX_CLOCK_SKEW = timedelta(minutes=5)


def sha(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def sha_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def load(path: pathlib.Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("JSON object required")
    return value


def safe_relative(value: object, *, label: str) -> pathlib.PurePosixPath:
    text = str(value or "")
    path = pathlib.PurePosixPath(text)
    if (
        not text
        or text in {".", ".."}
        or path.is_absolute()
        or ".." in path.parts
        or "\\" in text
    ):
        raise ValueError(f"{label}: unsafe relative path {text!r}")
    return path


def require_safe_id(value: object, *, label: str) -> str:
    text = str(value or "")
    if SAFE_ID.fullmatch(text) is None:
        raise ValueError(f"{label}: stable identifier required")
    return text


def require_hex64(value: object, *, label: str) -> str:
    text = str(value or "")
    if HEX64.fullmatch(text) is None:
        raise ValueError(f"{label}: exact 64-character SHA-256 required")
    return text


def parse_utc(value: object, *, label: str) -> datetime:
    text = str(value or "")
    if not text.endswith("Z"):
        raise ValueError(f"{label}: UTC timestamp ending in Z required")
    try:
        parsed = datetime.fromisoformat(text[:-1] + "+00:00")
    except ValueError as exc:
        raise ValueError(f"{label}: invalid UTC timestamp") from exc
    return parsed.astimezone(timezone.utc)


def resolve_authorized_root(value: object) -> pathlib.Path:
    raw = pathlib.Path(str(value or ""))
    if not raw.is_absolute():
        raise ValueError("absolute authorized measurement root required")
    if raw.is_symlink():
        raise ValueError("authorized measurement root may not be a symlink")
    try:
        resolved = raw.resolve(strict=True)
    except OSError as exc:
        raise ValueError("authorized measurement root does not exist") from exc
    if not resolved.is_dir():
        raise ValueError("authorized measurement root must be a directory")
    return resolved


def resolve_contained(
    raw: pathlib.Path,
    authorized_root: pathlib.Path,
    *,
    label: str,
    kind: str,
) -> pathlib.Path:
    if raw.is_symlink():
        raise ValueError(f"{label}: symlink path rejected")
    try:
        resolved = raw.resolve(strict=True)
    except OSError as exc:
        raise ValueError(f"{label}: path does not exist") from exc
    try:
        resolved.relative_to(authorized_root)
    except ValueError as exc:
        raise ValueError(f"{label}: path escaped authorized root") from exc
    if kind == "file" and not resolved.is_file():
        raise ValueError(f"{label}: regular file required")
    if kind == "directory" and not resolved.is_dir():
        raise ValueError(f"{label}: directory required")
    return resolved


def resolve_trusted_relative(
    value: object,
    authorized_root: pathlib.Path,
    *,
    label: str,
    kind: str,
) -> pathlib.Path:
    relative = safe_relative(value, label=label)
    return resolve_contained(
        authorized_root / pathlib.Path(relative.as_posix()),
        authorized_root,
        label=label,
        kind=kind,
    )


def load_trust_context(
    *,
    authorized_root_value: object,
    manifest_value: object,
    manifest_sha256: object,
    commit: str,
    measurement_session_id: object,
    workflow_run_id: object,
    workflow_run_attempt: object,
    measurement_nonce: object,
    now: datetime | None = None,
) -> dict[str, Any]:
    authorized_root = resolve_authorized_root(authorized_root_value)
    manifest_raw = pathlib.Path(str(manifest_value or ""))
    if not manifest_raw.is_absolute():
        raise ValueError("absolute trusted measurement manifest path required")
    manifest_path = resolve_contained(
        manifest_raw,
        authorized_root,
        label="trusted measurement manifest",
        kind="file",
    )
    expected_manifest_sha = require_hex64(
        manifest_sha256,
        label="trusted measurement manifest digest",
    )
    if sha(manifest_path) != expected_manifest_sha:
        raise ValueError("trusted measurement manifest digest mismatch")

    session_id = require_safe_id(
        measurement_session_id,
        label="expected measurement session",
    )
    run_id = require_safe_id(workflow_run_id, label="expected workflow run")
    try:
        run_attempt = int(str(workflow_run_attempt))
    except ValueError as exc:
        raise ValueError("expected positive workflow run attempt required") from exc
    if run_attempt <= 0:
        raise ValueError("expected positive workflow run attempt required")
    nonce = require_hex64(measurement_nonce, label="expected measurement nonce")

    data = load(manifest_path)
    expected = {
        "schemaVersion": "1.0.0",
        "manifestType": "p2-technology-measurement-trust-v1",
        "platform": PLATFORM,
        "commitSha": commit,
        "measurementSessionId": session_id,
        "workflowRunId": run_id,
        "workflowRunAttempt": run_attempt,
        "nonce": nonce,
    }
    for key, value in expected.items():
        if data.get(key) != value:
            raise ValueError(f"trusted measurement manifest: {key} expected {value!r}")

    issued_at = parse_utc(data.get("issuedAt"), label="trusted manifest issuedAt")
    expires_at = parse_utc(data.get("expiresAt"), label="trusted manifest expiresAt")
    current = now or datetime.now(timezone.utc)
    if expires_at <= issued_at:
        raise ValueError("trusted measurement manifest expiry must follow issuance")
    if expires_at - issued_at > MAX_TRUST_LIFETIME:
        raise ValueError("trusted measurement manifest lifetime exceeds six hours")
    if issued_at > current + MAX_CLOCK_SKEW:
        raise ValueError("trusted measurement manifest issuance is in the future")
    if expires_at <= current:
        raise ValueError("trusted measurement manifest is expired or replayed")

    candidates = data.get("candidateReceipts")
    required_ids = list(CANDIDATES)
    if (
        not isinstance(candidates, list)
        or [row.get("candidateId") for row in candidates if isinstance(row, dict)]
        != required_ids
    ):
        raise ValueError("trusted measurement manifest candidate set/order invalid")

    trusted_candidates: dict[str, dict[str, Any]] = {}
    receipt_paths: set[pathlib.Path] = set()
    receipt_digests: set[str] = set()
    evidence_paths: set[pathlib.Path] = set()
    evidence_digests: set[str] = set()
    observation_ids: set[str] = set()

    for candidate in candidates:
        if not isinstance(candidate, dict):
            raise ValueError("trusted candidate entry must be an object")
        candidate_id = str(candidate["candidateId"])
        receipt_path = resolve_trusted_relative(
            candidate.get("receiptPath"),
            authorized_root,
            label=f"{candidate_id}: trusted receipt",
            kind="file",
        )
        receipt_sha = require_hex64(
            candidate.get("receiptSha256"),
            label=f"{candidate_id}: trusted receipt digest",
        )
        if sha(receipt_path) != receipt_sha:
            raise ValueError(f"{candidate_id}: trusted receipt digest mismatch")
        artifact_root = resolve_trusted_relative(
            candidate.get("artifactRoot"),
            authorized_root,
            label=f"{candidate_id}: trusted artifact root",
            kind="directory",
        )
        if receipt_path in receipt_paths or receipt_sha in receipt_digests:
            raise ValueError("trusted candidate receipt identities must be distinct")
        receipt_paths.add(receipt_path)
        receipt_digests.add(receipt_sha)

        rounds = candidate.get("rounds")
        if not isinstance(rounds, list) or len(rounds) != 3:
            raise ValueError(f"{candidate_id}: trusted rounds 1, 2, and 3 required")
        trusted_rounds: list[dict[str, Any]] = []
        previous_observed_at: datetime | None = None
        for index, row in enumerate(rounds):
            if not isinstance(row, dict) or row.get("roundId") != index + 1:
                raise ValueError(
                    f"{candidate_id}: trusted round {index + 1} identity required"
                )
            observation_id = require_safe_id(
                row.get("observationId"),
                label=f"{candidate_id}/round-{index + 1}: observation identity",
            )
            observed_at = parse_utc(
                row.get("observedAt"),
                label=f"{candidate_id}/round-{index + 1}: observedAt",
            )
            if observed_at < issued_at or observed_at > expires_at:
                raise ValueError(
                    f"{candidate_id}/round-{index + 1}: observation outside trust window"
                )
            if observed_at > current + MAX_CLOCK_SKEW:
                raise ValueError(
                    f"{candidate_id}/round-{index + 1}: observation is in the future"
                )
            if previous_observed_at is not None and observed_at <= previous_observed_at:
                raise ValueError(
                    f"{candidate_id}: trusted round timestamps must be strictly increasing"
                )
            previous_observed_at = observed_at
            evidence_path = resolve_trusted_relative(
                row.get("evidencePath"),
                authorized_root,
                label=f"{candidate_id}/round-{index + 1}: trusted evidence",
                kind="file",
            )
            try:
                evidence_path.relative_to(artifact_root)
            except ValueError as exc:
                raise ValueError(
                    f"{candidate_id}/round-{index + 1}: evidence escaped candidate artifact root"
                ) from exc
            evidence_sha = require_hex64(
                row.get("evidenceSha256"),
                label=f"{candidate_id}/round-{index + 1}: trusted evidence digest",
            )
            if sha(evidence_path) != evidence_sha:
                raise ValueError(
                    f"{candidate_id}/round-{index + 1}: trusted evidence digest mismatch"
                )
            if observation_id in observation_ids:
                raise ValueError("trusted round observation identities must be distinct")
            if evidence_path in evidence_paths:
                raise ValueError("trusted round evidence paths must be distinct")
            if evidence_sha in evidence_digests:
                raise ValueError("trusted round evidence digests must be distinct")
            observation_ids.add(observation_id)
            evidence_paths.add(evidence_path)
            evidence_digests.add(evidence_sha)
            trusted_rounds.append(
                {
                    "roundId": index + 1,
                    "observationId": observation_id,
                    "observedAt": row["observedAt"],
                    "evidencePath": evidence_path,
                    "evidenceSha256": evidence_sha,
                }
            )

        trusted_candidates[candidate_id] = {
            "candidateId": candidate_id,
            "receiptPath": receipt_path,
            "receiptSha256": receipt_sha,
            "artifactRoot": artifact_root,
            "rounds": trusted_rounds,
        }

    return {
        "authorizedRoot": authorized_root,
        "manifestPath": manifest_path,
        "manifestSha256": expected_manifest_sha,
        "measurementSessionId": session_id,
        "workflowRunId": run_id,
        "workflowRunAttempt": run_attempt,
        "nonce": nonce,
        "issuedAt": data["issuedAt"],
        "expiresAt": data["expiresAt"],
        "candidates": trusted_candidates,
    }


def validate_round(
    row: object,
    artifact_root: pathlib.Path,
    authorized_root: pathlib.Path,
    candidate_id: str,
    index: int,
    trusted: dict[str, Any],
) -> dict[str, Any]:
    round_id = index + 1
    if (
        not isinstance(row, dict)
        or row.get("roundId") != round_id
        or row.get("status") != "passed"
    ):
        raise ValueError(f"{candidate_id}: exact passing round {round_id} required")
    for key in ("coldStartMs", "steadyRssKiB", "packageSizeBytes"):
        if not isinstance(row.get(key), (int, float)) or row[key] <= 0:
            raise ValueError(f"{candidate_id}/round-{round_id}: positive {key} required")
    if row.get("observationId") != trusted["observationId"]:
        raise ValueError(f"{candidate_id}/round-{round_id}: trusted observation identity mismatch")
    if row.get("observedAt") != trusted["observedAt"]:
        raise ValueError(f"{candidate_id}/round-{round_id}: trusted observation time mismatch")

    detach = row.get("detachReconnect")
    if not isinstance(detach, dict):
        raise ValueError(f"{candidate_id}/round-{round_id}: detach/reconnect proof missing")
    required_true = (
        "consumerDetached",
        "outputWhileDetached",
        "reconnectedByDurableCursor",
        "backlogReplayExact",
        "noDuplicationOrLoss",
    )
    if any(detach.get(key) is not True for key in required_true):
        raise ValueError(
            f"{candidate_id}/round-{round_id}: real detach/reconnect proof incomplete"
        )
    if (
        not isinstance(detach.get("detachedCursor"), int)
        or not isinstance(detach.get("reconnectCursor"), int)
        or detach["reconnectCursor"] < detach["detachedCursor"]
    ):
        raise ValueError(f"{candidate_id}/round-{round_id}: durable cursor proof invalid")
    if (
        not isinstance(detach.get("outputWhileDetachedBytes"), int)
        or detach["outputWhileDetachedBytes"] <= 0
    ):
        raise ValueError(
            f"{candidate_id}/round-{round_id}: output while detached not observed"
        )
    if (
        HEX64.fullmatch(str(detach.get("expectedBacklogSha256", ""))) is None
        or detach.get("expectedBacklogSha256")
        != detach.get("observedBacklogSha256")
    ):
        raise ValueError(
            f"{candidate_id}/round-{round_id}: exact backlog replay digest required"
        )
    if detach.get("duplicateSequenceCount") != 0 or detach.get("missingSequenceCount") != 0:
        raise ValueError(
            f"{candidate_id}/round-{round_id}: reconnect duplication/loss observed"
        )

    tree = row.get("processTree")
    if (
        not isinstance(tree, dict)
        or tree.get("descendantCreated") is not True
        or tree.get("identityVerified") is not True
    ):
        raise ValueError(f"{candidate_id}/round-{round_id}: descendant identity proof missing")
    descendants = tree.get("descendantProcessIdentities")
    if not isinstance(descendants, list) or not descendants:
        raise ValueError(
            f"{candidate_id}/round-{round_id}: descendant process identities required"
        )
    if (
        tree.get("terminationStatus") not in {"killed", "stopped"}
        or tree.get("remainingDescendants") != []
        or tree.get("zeroSurvivingDescendants") is not True
    ):
        raise ValueError(
            f"{candidate_id}/round-{round_id}: complete process-tree termination not proved"
        )

    evidence_relative = safe_relative(
        row.get("evidencePath"),
        label=f"{candidate_id}/round-{round_id}: receipt evidence",
    )
    evidence_path = resolve_contained(
        artifact_root / pathlib.Path(evidence_relative.as_posix()),
        authorized_root,
        label=f"{candidate_id}/round-{round_id}: receipt evidence",
        kind="file",
    )
    try:
        evidence_path.relative_to(artifact_root)
    except ValueError as exc:
        raise ValueError(
            f"{candidate_id}/round-{round_id}: receipt evidence escaped artifact root"
        ) from exc
    evidence_sha = require_hex64(
        row.get("evidenceSha256"),
        label=f"{candidate_id}/round-{round_id}: receipt evidence digest",
    )
    if evidence_path != trusted["evidencePath"]:
        raise ValueError(f"{candidate_id}/round-{round_id}: trusted evidence path mismatch")
    if evidence_sha != trusted["evidenceSha256"] or sha(evidence_path) != evidence_sha:
        raise ValueError(f"{candidate_id}/round-{round_id}: evidence artifact binding invalid")
    normalized = dict(row)
    normalized["evidencePath"] = trusted["evidencePath"].relative_to(
        authorized_root
    ).as_posix()
    normalized["evidenceSha256"] = trusted["evidenceSha256"]
    return normalized


def validate_candidate(
    path: pathlib.Path,
    candidate_id: str,
    family: str,
    commit: str,
    trust: dict[str, Any],
) -> dict[str, Any]:
    authorized_root = trust["authorizedRoot"]
    supplied_path = resolve_contained(
        path,
        authorized_root,
        label=f"{candidate_id}: supplied receipt",
        kind="file",
    )
    trusted = trust["candidates"][candidate_id]
    if supplied_path != trusted["receiptPath"]:
        raise ValueError(f"{candidate_id}: supplied receipt path is not trusted")
    if sha(supplied_path) != trusted["receiptSha256"]:
        raise ValueError(f"{candidate_id}: independently pinned receipt digest mismatch")

    data = load(supplied_path)
    expected = {
        "schemaVersion": "4.0.0",
        "receiptType": "p2-technology-candidate-observation-v4",
        "candidateId": candidate_id,
        "implementationFamily": family,
        "platform": PLATFORM,
        "commitSha": commit,
        "status": "passed",
        "sourceOnly": False,
        "independentlyExecuted": True,
        "measurementSessionId": trust["measurementSessionId"],
        "workflowRunId": trust["workflowRunId"],
        "workflowRunAttempt": trust["workflowRunAttempt"],
        "nonce": trust["nonce"],
    }
    for key, value in expected.items():
        if data.get(key) != value:
            raise ValueError(f"{candidate_id}: {key} expected {value!r}")
    for key in (
        "sourceTreeSha256",
        "implementationSha256",
        "executableSha256",
        "buildReceiptSha256",
        "packagingReceiptSha256",
    ):
        require_hex64(data.get(key), label=f"{candidate_id}: {key}")
    if candidate_id.startswith("dart-"):
        if (
            data.get("independentControlPlaneImplementation") is not True
            or data.get("delegatedProbeReceiptSha256") not in (None, "")
        ):
            raise ValueError(
                "Dart candidate must independently exercise lifecycle semantics, "
                "not republish a native probe"
            )

    artifact_raw = pathlib.Path(str(data.get("artifactRoot", "")))
    if not artifact_raw.is_absolute():
        raise ValueError(f"{candidate_id}: existing absolute artifact root required")
    artifact_root = resolve_contained(
        artifact_raw,
        authorized_root,
        label=f"{candidate_id}: receipt artifact root",
        kind="directory",
    )
    if artifact_root != trusted["artifactRoot"]:
        raise ValueError(f"{candidate_id}: artifact root does not match trusted manifest")

    rounds = data.get("rounds")
    if not isinstance(rounds, list) or len(rounds) != 3:
        raise ValueError(f"{candidate_id}: exactly three rounds required")
    observed = [
        validate_round(
            row,
            artifact_root,
            authorized_root,
            candidate_id,
            index,
            trusted["rounds"][index],
        )
        for index, row in enumerate(rounds)
    ]
    if len({row["observationId"] for row in observed}) != 3:
        raise ValueError(f"{candidate_id}: round observation identities must be distinct")
    if len({row["evidencePath"] for row in observed}) != 3:
        raise ValueError(f"{candidate_id}: round evidence paths must be distinct")
    if len({row["evidenceSha256"] for row in observed}) != 3:
        raise ValueError(f"{candidate_id}: round evidence digests must be distinct")

    packaging = data.get("packaging")
    if (
        not isinstance(packaging, dict)
        or packaging.get("threePlatformReliable") is not True
        or packaging.get("codeSigningImpactMeasured") is not True
        or packaging.get("updaterImpactMeasured") is not True
    ):
        raise ValueError(f"{candidate_id}: packaging/signing/updater measurements incomplete")
    fidelity = data.get("platformFidelity")
    if (
        not isinstance(fidelity, dict)
        or fidelity.get("ptyInteractiveInput") is not True
        or fidelity.get("resize") is not True
        or fidelity.get("ansiUnicode") is not True
    ):
        raise ValueError(f"{candidate_id}: platform PTY fidelity incomplete")

    return {
        "id": candidate_id,
        "implementationFamily": family,
        "status": "passed",
        "sourceReceiptPath": str(supplied_path),
        "sourceReceiptSha256": sha(supplied_path),
        "sourceTreeSha256": data["sourceTreeSha256"],
        "implementationSha256": data["implementationSha256"],
        "executableSha256": data["executableSha256"],
        "buildReceiptSha256": data["buildReceiptSha256"],
        "packagingReceiptSha256": data["packagingReceiptSha256"],
        "rounds": observed,
        "coldStartMs": {
            "median": statistics.median(float(row["coldStartMs"]) for row in observed)
        },
        "steadyRssKiB": statistics.median(
            float(row["steadyRssKiB"]) for row in observed
        ),
        "packageSizeBytes": max(int(row["packageSizeBytes"]) for row in observed),
        "capabilities": {
            key: True
            for key in (
                "interactiveInput",
                "resize",
                "ansi",
                "unicode",
                "detachReconnect",
                "processTreeTermination",
            )
        },
        "proofs": {
            key: True
            for key in (
                "consumerDetached",
                "outputWhileDetached",
                "reconnectCursorObserved",
                "backlogReplayExact",
                "noDuplicationOrLoss",
                "descendantProcessCreated",
                "descendantTerminated",
                "zeroSurvivingDescendants",
            )
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--output", required=True)
    parser.add_argument(
        "--commit-sha",
        default=os.environ.get("KRISTIN_P2_COMMIT_SHA", ""),
    )
    parser.add_argument("--candidate-receipt", action="append", default=[])
    parser.add_argument(
        "--authorized-root",
        default=os.environ.get("KRISTIN_P2_TECH_AUTHORIZED_ROOT", ""),
    )
    parser.add_argument(
        "--trust-manifest",
        default=os.environ.get("KRISTIN_P2_TECH_TRUST_MANIFEST", ""),
    )
    parser.add_argument(
        "--trust-manifest-sha256",
        default=os.environ.get("KRISTIN_P2_TECH_TRUST_MANIFEST_SHA256", ""),
    )
    parser.add_argument(
        "--measurement-session-id",
        default=os.environ.get("KRISTIN_P2_TECH_SESSION_ID", ""),
    )
    parser.add_argument(
        "--measurement-nonce",
        default=os.environ.get("KRISTIN_P2_TECH_NONCE", ""),
    )
    parser.add_argument(
        "--workflow-run-id",
        default=os.environ.get("GITHUB_RUN_ID", ""),
    )
    parser.add_argument(
        "--workflow-run-attempt",
        default=os.environ.get("GITHUB_RUN_ATTEMPT", ""),
    )
    args = parser.parse_args()

    commit = args.commit_sha.strip()
    if HEX40.fullmatch(commit) is None:
        raise SystemExit("exact candidate measurement commit required")

    supplied: dict[str, pathlib.Path] = {}
    for value in args.candidate_receipt:
        candidate, separator, raw = value.partition("=")
        if not separator or candidate not in CANDIDATES:
            raise SystemExit(f"invalid candidate receipt argument: {value}")
        supplied[candidate] = pathlib.Path(raw).resolve()
    for candidate, (_, env_name) in CANDIDATES.items():
        raw = os.environ.get(env_name, "").strip()
        if raw and candidate not in supplied:
            supplied[candidate] = pathlib.Path(raw).resolve()

    trust: dict[str, Any] | None = None
    trust_failure: str | None = None
    try:
        trust = load_trust_context(
            authorized_root_value=args.authorized_root,
            manifest_value=args.trust_manifest,
            manifest_sha256=args.trust_manifest_sha256,
            commit=commit,
            measurement_session_id=args.measurement_session_id,
            workflow_run_id=args.workflow_run_id,
            workflow_run_attempt=args.workflow_run_attempt,
            measurement_nonce=args.measurement_nonce,
        )
    except Exception as exc:
        trust_failure = str(exc)

    candidates: list[dict[str, Any]] = []
    failures: list[dict[str, Any]] = []
    for candidate, (family, _) in CANDIDATES.items():
        path = supplied.get(candidate)
        try:
            if trust is None:
                raise ValueError(
                    f"trusted measurement envelope invalid: {trust_failure or 'missing'}"
                )
            if path is None or not path.is_file():
                raise ValueError("exact machine-observed candidate receipt missing")
            candidates.append(validate_candidate(path, candidate, family, commit, trust))
        except Exception as exc:
            failures.append(
                {
                    "candidateId": candidate,
                    "status": "blocked",
                    "reason": str(exc),
                }
            )

    implementation_hashes = {row["implementationSha256"] for row in candidates}
    distinct = len(implementation_hashes) == len(CANDIDATES)
    if candidates and not distinct:
        failures.append(
            {
                "candidateId": "aggregate",
                "status": "blocked",
                "reason": "candidate implementations are not independently distinct",
            }
        )
    complete = len(candidates) == len(CANDIDATES) and not failures and distinct
    selected = (
        min(
            candidates,
            key=lambda row: (
                row["coldStartMs"]["median"],
                row["steadyRssKiB"],
                row["packageSizeBytes"],
            ),
        )["id"]
        if complete
        else None
    )
    trust_summary = (
        {
            "manifestSha256": trust["manifestSha256"],
            "measurementSessionId": trust["measurementSessionId"],
            "workflowRunId": trust["workflowRunId"],
            "workflowRunAttempt": trust["workflowRunAttempt"],
            "nonceSha256": sha_text(trust["nonce"]),
            "issuedAt": trust["issuedAt"],
            "expiresAt": trust["expiresAt"],
        }
        if trust is not None
        else {"status": "blocked", "reason": trust_failure or "missing"}
    )
    result = {
        "schemaVersion": "4.0.0",
        "measurementType": "p2-equivalent-pty-technology-spike-v4",
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "platform": PLATFORM,
        "commitSha": commit,
        "requiredCandidateIds": list(CANDIDATES),
        "trust": trust_summary,
        "candidates": candidates,
        "blockedCandidates": failures,
        "decision": {
            "status": "platform_measurement_complete" if complete else "blocked",
            "selected": selected,
            "requiresTriOsAggregation": True,
            "selectionMethod": "all-candidates-pass-then-measured-resource-order",
        },
    }
    output = pathlib.Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result["decision"], sort_keys=True))
    return 0 if complete else 3


if __name__ == "__main__":
    raise SystemExit(main())
