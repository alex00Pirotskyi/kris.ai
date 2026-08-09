#!/usr/bin/env python3
"""Aggregate independently executed equivalent P2 automation-host candidates.

This tool never infers detach/reconnect or process-tree termination from a sleep,
a primary PID exit, or a wrapper's boolean. Each candidate must supply three
machine-observed rounds bound to the exact commit, platform, executable, build,
source, artifact graph, cursor/backlog replay, and zero-descendant kill result.
Missing or malformed observations produce a blocked decision.
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

CANDIDATES = {
    "typescript-node-node-pty-with-native-lifecycle-adapters": ("node-node-pty", "KRISTIN_P2_TECH_NODE_RECEIPT"),
    "native-platform-pty-supervisor": ("native-pty-supervisor", "KRISTIN_P2_TECH_NATIVE_RECEIPT"),
    "dart-control-plane-native-pty-helper": ("dart-independent-control-plane", "KRISTIN_P2_TECH_DART_RECEIPT"),
}
PLATFORM = {"Windows": "windows", "Darwin": "macos", "Linux": "linux"}.get(platform.system(), platform.system().lower())
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")


def sha(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def load(path: pathlib.Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("JSON object required")
    return value


def safe_relative(value: object) -> pathlib.PurePosixPath:
    text = str(value or "")
    path = pathlib.PurePosixPath(text)
    if not text or path.is_absolute() or ".." in path.parts or "\\" in text:
        raise ValueError(f"unsafe relative artifact path: {text!r}")
    return path


def validate_round(row: object, artifact_root: pathlib.Path, candidate_id: str, index: int) -> dict:
    if not isinstance(row, dict) or row.get("roundId") != index + 1 or row.get("status") != "passed":
        raise ValueError(f"{candidate_id}: exact passing round {index + 1} required")
    for key in ("coldStartMs", "steadyRssKiB", "packageSizeBytes"):
        if not isinstance(row.get(key), (int, float)) or row[key] <= 0:
            raise ValueError(f"{candidate_id}/round-{index + 1}: positive {key} required")
    detach = row.get("detachReconnect")
    if not isinstance(detach, dict):
        raise ValueError(f"{candidate_id}/round-{index + 1}: detach/reconnect proof missing")
    required_true = ("consumerDetached", "outputWhileDetached", "reconnectedByDurableCursor", "backlogReplayExact", "noDuplicationOrLoss")
    if any(detach.get(key) is not True for key in required_true):
        raise ValueError(f"{candidate_id}/round-{index + 1}: real detach/reconnect proof incomplete")
    if not isinstance(detach.get("detachedCursor"), int) or not isinstance(detach.get("reconnectCursor"), int) or detach["reconnectCursor"] < detach["detachedCursor"]:
        raise ValueError(f"{candidate_id}/round-{index + 1}: durable cursor proof invalid")
    if not isinstance(detach.get("outputWhileDetachedBytes"), int) or detach["outputWhileDetachedBytes"] <= 0:
        raise ValueError(f"{candidate_id}/round-{index + 1}: output while detached not observed")
    if HEX64.fullmatch(str(detach.get("expectedBacklogSha256", ""))) is None or detach.get("expectedBacklogSha256") != detach.get("observedBacklogSha256"):
        raise ValueError(f"{candidate_id}/round-{index + 1}: exact backlog replay digest required")
    if detach.get("duplicateSequenceCount") != 0 or detach.get("missingSequenceCount") != 0:
        raise ValueError(f"{candidate_id}/round-{index + 1}: reconnect duplication/loss observed")
    tree = row.get("processTree")
    if not isinstance(tree, dict) or tree.get("descendantCreated") is not True or tree.get("identityVerified") is not True:
        raise ValueError(f"{candidate_id}/round-{index + 1}: descendant identity proof missing")
    descendants = tree.get("descendantProcessIdentities")
    if not isinstance(descendants, list) or not descendants:
        raise ValueError(f"{candidate_id}/round-{index + 1}: descendant process identities required")
    if tree.get("terminationStatus") not in {"killed", "stopped"} or tree.get("remainingDescendants") != [] or tree.get("zeroSurvivingDescendants") is not True:
        raise ValueError(f"{candidate_id}/round-{index + 1}: complete process-tree termination not proved")
    evidence_path = artifact_root / safe_relative(row.get("evidencePath"))
    evidence_sha = str(row.get("evidenceSha256", ""))
    if HEX64.fullmatch(evidence_sha) is None or not evidence_path.is_file() or sha(evidence_path) != evidence_sha:
        raise ValueError(f"{candidate_id}/round-{index + 1}: evidence artifact binding invalid")
    return row


def validate_candidate(path: pathlib.Path, candidate_id: str, family: str, commit: str) -> dict:
    data = load(path)
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
    }
    for key, value in expected.items():
        if data.get(key) != value:
            raise ValueError(f"{candidate_id}: {key} expected {value!r}")
    for key in ("sourceTreeSha256", "implementationSha256", "executableSha256", "buildReceiptSha256", "packagingReceiptSha256"):
        if HEX64.fullmatch(str(data.get(key, ""))) is None:
            raise ValueError(f"{candidate_id}: {key} required")
    if candidate_id.endswith("dart-control-plane-native-pty-helper") or candidate_id.startswith("dart-"):
        if data.get("independentControlPlaneImplementation") is not True or data.get("delegatedProbeReceiptSha256") not in (None, ""):
            raise ValueError("Dart candidate must independently exercise lifecycle semantics, not republish a native probe")
    artifact_root = pathlib.Path(str(data.get("artifactRoot", "")))
    if not artifact_root.is_absolute() or not artifact_root.is_dir():
        raise ValueError(f"{candidate_id}: existing absolute artifact root required")
    rounds = data.get("rounds")
    if not isinstance(rounds, list) or len(rounds) != 3:
        raise ValueError(f"{candidate_id}: exactly three rounds required")
    observed = [validate_round(row, artifact_root, candidate_id, index) for index, row in enumerate(rounds)]
    packaging = data.get("packaging")
    if not isinstance(packaging, dict) or packaging.get("threePlatformReliable") is not True or packaging.get("codeSigningImpactMeasured") is not True or packaging.get("updaterImpactMeasured") is not True:
        raise ValueError(f"{candidate_id}: packaging/signing/updater measurements incomplete")
    fidelity = data.get("platformFidelity")
    if not isinstance(fidelity, dict) or fidelity.get("ptyInteractiveInput") is not True or fidelity.get("resize") is not True or fidelity.get("ansiUnicode") is not True:
        raise ValueError(f"{candidate_id}: platform PTY fidelity incomplete")
    return {
        "id": candidate_id,
        "implementationFamily": family,
        "status": "passed",
        "sourceReceiptPath": str(path),
        "sourceReceiptSha256": sha(path),
        "sourceTreeSha256": data["sourceTreeSha256"],
        "implementationSha256": data["implementationSha256"],
        "executableSha256": data["executableSha256"],
        "buildReceiptSha256": data["buildReceiptSha256"],
        "packagingReceiptSha256": data["packagingReceiptSha256"],
        "rounds": observed,
        "coldStartMs": {"median": statistics.median(float(row["coldStartMs"]) for row in observed)},
        "steadyRssKiB": statistics.median(float(row["steadyRssKiB"]) for row in observed),
        "packageSizeBytes": max(int(row["packageSizeBytes"]) for row in observed),
        "capabilities": {key: True for key in ("interactiveInput", "resize", "ansi", "unicode", "detachReconnect", "processTreeTermination")},
        "proofs": {key: True for key in ("consumerDetached", "outputWhileDetached", "reconnectCursorObserved", "backlogReplayExact", "noDuplicationOrLoss", "descendantProcessCreated", "descendantTerminated", "zeroSurvivingDescendants")},
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default=".")
    ap.add_argument("--output", required=True)
    ap.add_argument("--commit-sha", default=os.environ.get("KRISTIN_P2_COMMIT_SHA", ""))
    ap.add_argument("--candidate-receipt", action="append", default=[])
    ns = ap.parse_args()
    commit = ns.commit_sha.strip()
    if HEX40.fullmatch(commit) is None:
        raise SystemExit("exact candidate measurement commit required")
    supplied: dict[str, pathlib.Path] = {}
    for value in ns.candidate_receipt:
        candidate, separator, raw = value.partition("=")
        if not separator or candidate not in CANDIDATES:
            raise SystemExit(f"invalid candidate receipt argument: {value}")
        supplied[candidate] = pathlib.Path(raw).resolve()
    for candidate, (_, env_name) in CANDIDATES.items():
        raw = os.environ.get(env_name, "").strip()
        if raw and candidate not in supplied:
            supplied[candidate] = pathlib.Path(raw).resolve()

    candidates = []
    failures = []
    for candidate, (family, _) in CANDIDATES.items():
        path = supplied.get(candidate)
        try:
            if path is None or not path.is_file():
                raise ValueError("exact machine-observed candidate receipt missing")
            candidates.append(validate_candidate(path, candidate, family, commit))
        except Exception as exc:
            failures.append({"candidateId": candidate, "status": "blocked", "reason": str(exc)})

    implementation_hashes = {row["implementationSha256"] for row in candidates}
    distinct = len(implementation_hashes) == len(CANDIDATES)
    if candidates and not distinct:
        failures.append({"candidateId": "aggregate", "status": "blocked", "reason": "candidate implementations are not independently distinct"})
    complete = len(candidates) == len(CANDIDATES) and not failures and distinct
    selected = min(candidates, key=lambda row: (row["coldStartMs"]["median"], row["steadyRssKiB"], row["packageSizeBytes"]))["id"] if complete else None
    result = {
        "schemaVersion": "4.0.0",
        "measurementType": "p2-equivalent-pty-technology-spike-v4",
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "platform": PLATFORM,
        "commitSha": commit,
        "requiredCandidateIds": list(CANDIDATES),
        "candidates": candidates,
        "blockedCandidates": failures,
        "decision": {
            "status": "platform_measurement_complete" if complete else "blocked",
            "selected": selected,
            "requiresTriOsAggregation": True,
            "selectionMethod": "all-candidates-pass-then-measured-resource-order",
        },
    }
    out = pathlib.Path(ns.output).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result["decision"], sort_keys=True))
    return 0 if complete else 3


if __name__ == "__main__":
    raise SystemExit(main())
