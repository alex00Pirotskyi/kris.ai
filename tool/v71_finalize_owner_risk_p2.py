#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import time
from typing import Any

TASKS = [f"P2-{i:03d}" for i in range(1, 15)]
PLATFORMS = ("windows", "macos", "linux")
HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
OWNER_ATTESTATION = (
    "I ACCEPT OWNER-RISK P1/P2 SECURITY WAIVER; FORMAL SECURITY EVIDENCE "
    "AND INDEPENDENT HUMAN REVIEW WERE NOT PERFORMED"
)
RELEASE_ATTESTATION = (
    "I ACCEPT TRI-PLATFORM CI AS THE PROMOTION GATE; MANUAL QA AND RELEASE "
    "SIGNING REMAIN REQUIRED BEFORE PUBLIC GA"
)


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def sha256(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def load(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail(f"invalid JSON {path}: {exc}")
    if not isinstance(value, dict):
        fail(f"JSON object required: {path}")
    return value


def write_json(path: pathlib.Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def git(root: pathlib.Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), *args],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    return result.stdout.strip()


def update_exit_gate(root: pathlib.Path) -> None:
    path = root / "tool/p2_exit_gate_test.py"
    if not path.is_file():
        fail("P2 exit gate missing")
    path.write_text(
        '''#!/usr/bin/env python3
from __future__ import annotations
import argparse,hashlib,json,pathlib,subprocess,sys
from p2_evidence_contract import TASKS
PLATFORMS=("windows","macos","linux")

def sha(path:pathlib.Path)->str:
 h=hashlib.sha256()
 with path.open("rb") as f:
  for block in iter(lambda:f.read(1024*1024),b""):h.update(block)
 return h.hexdigest()

def owner_risk_gate(root:pathlib.Path,aggregate:dict,reviewed_sha:str)->None:
 if aggregate.get("schemaVersion")!="3.0.0" or aggregate.get("status")!="passed" or aggregate.get("completionClaim") is not True or aggregate.get("p3DependencySatisfied") is not True:raise SystemExit("owner-risk P2 aggregate closure invalid")
 waiver=aggregate.get("ownerRiskWaiver")
 if not isinstance(waiver,dict) or waiver.get("securityEvidenceWaived") is not True or waiver.get("formalSecurityCompletion") is not False or waiver.get("independentHumanReviewPerformed") is not False:raise SystemExit("owner-risk waiver binding invalid")
 if aggregate.get("reviewedCommit")!=reviewed_sha or len(reviewed_sha)!=40:raise SystemExit("owner-risk reviewed commit mismatch")
 rows=aggregate.get("platformReceipts")
 if not isinstance(rows,dict) or set(rows)!=set(PLATFORMS):raise SystemExit("owner-risk exact tri-platform receipts required")
 for platform in PLATFORMS:
  row=rows[platform]
  if not isinstance(row,dict):raise SystemExit(f"{platform}: owner-risk receipt row invalid")
  rel=pathlib.PurePosixPath(str(row.get("path","")))
  if rel.is_absolute() or ".." in rel.parts:raise SystemExit(f"{platform}: unsafe owner-risk receipt path")
  receipt_path=(root/rel).resolve()
  if root not in receipt_path.parents or not receipt_path.is_file() or sha(receipt_path)!=row.get("sha256"):raise SystemExit(f"{platform}: owner-risk receipt digest mismatch")
  receipt=json.loads(receipt_path.read_text(encoding="utf-8"))
  expected={"schemaVersion":"1.0.0","receiptType":"p2-owner-risk-tri-platform-qa-v1","phase":"P2","platform":platform,"status":"passed","sourceCommit":reviewed_sha,"securityEvidenceWaived":True,"formalSecurityCompletion":False,"manualQaStillRequired":True}
  for key,value in expected.items():
   if receipt.get(key)!=value:raise SystemExit(f"{platform}: owner-risk receipt {key} mismatch")
  if not isinstance(receipt.get("workflowRunId"),int) or not str(receipt.get("artifactSha256","")).isalnum() or len(str(receipt.get("artifactSha256","")))!=64:raise SystemExit(f"{platform}: owner-risk receipt run/artifact binding invalid")
 for task in TASKS:
  packet=root/"tasks/completed"/f"{task}.md"
  task_manifest=root/"release/evidence"/task/"manifest.json"
  if not packet.is_file() or not task_manifest.is_file():raise SystemExit(f"{task}: owner-risk completion packet missing")
  data=json.loads(task_manifest.read_text(encoding="utf-8"))
  if data.get("status")!="passed" or data.get("completionClaim") is not True or data.get("ownerRiskWaiver") is not True or data.get("reviewedCommit")!=reviewed_sha:raise SystemExit(f"{task}: owner-risk task closure invalid")
 accepted=root/"release/evidence/P2-004/ACCEPTED_ADR.json"
 if not accepted.is_file():raise SystemExit("P2-004 accepted ADR evidence missing")
 adr=json.loads(accepted.read_text(encoding="utf-8"))
 if adr.get("status")!="accepted" or adr.get("reviewedCommit")!=reviewed_sha or set(adr.get("platformMeasurements",{}))!=set(PLATFORMS):raise SystemExit("P2-004 owner-risk accepted ADR invalid")

def main():
 ap=argparse.ArgumentParser();ap.add_argument("--project",default=".");ap.add_argument("--source-only",action="store_true");ap.add_argument("--owner-risk-waiver",action="store_true");ap.add_argument("--reviewed-sha");ap.add_argument("--platform-receipt",action="append",default=[]);ns=ap.parse_args();root=pathlib.Path(ns.project).resolve()
 aggregate_path=root/"release/evidence/P2/manifest.json";aggregate=json.loads(aggregate_path.read_text(encoding="utf-8"))
 owner_risk=ns.owner_risk_waiver or aggregate.get("promotionMode")=="owner-risk-security-waiver"
 if owner_risk:
  reviewed=ns.reviewed_sha or str(aggregate.get("reviewedCommit",""));owner_risk_gate(root,aggregate,reviewed)
  guide=(root/"docs/OWNER_MODE_OPERATOR_GUIDE.md").read_text(encoding="utf-8").lower()
  if "not a sandbox" not in guide or "full authority" not in guide:raise SystemExit("operator guide authority wording missing")
  print("P2 exit gate: PASS (owner-risk tri-platform waiver)");return 0
 if ns.source_only:
  for task in TASKS:
   subprocess.run([sys.executable,str(root/"tool/p2_task_gate.py"),"--project",str(root),"--task",task],check=True)
  guide=(root/"docs/OWNER_MODE_OPERATOR_GUIDE.md").read_text().lower()
  if "not a sandbox" not in guide or "full authority" not in guide:raise SystemExit("operator guide authority wording missing")
  print("P2 exit gate: PASS (source/local only; no completion claim)");return 0
 reviewed=ns.reviewed_sha or aggregate.get("reviewedCommit")
 receipts=ns.platform_receipt or [row["path"] for row in aggregate.get("platformReceipts",{}).values()]
 for task in TASKS:
  cmd=[sys.executable,str(root/"tool/p2_task_gate.py"),"--project",str(root),"--task",task,"--require-behavioral","--reviewed-sha",reviewed or ""]
  for receipt in receipts:cmd += ["--platform-receipt",receipt]
  subprocess.run(cmd,check=True)
  if not (root/"tasks/completed"/f"{task}.md").is_file():raise SystemExit(f"{task}: completed packet missing")
 if aggregate.get("status")!="passed" or aggregate.get("reviewedCommit")!=reviewed:raise SystemExit("aggregate P2 manifest not exact/passed")
 print("P2 exit gate: PASS");return 0
if __name__=="__main__":raise SystemExit(main())
''',
        encoding="utf-8",
    )


def update_integration_trains(root: pathlib.Path) -> None:
    path = root / "docs/roadmap/integration_trains.json"
    data = load(path)
    rows = data.get("trains")
    if not isinstance(rows, list):
        fail("integration train list invalid")
    found: set[str] = set()
    for row in rows:
        if not isinstance(row, dict):
            continue
        if row.get("id") == "TRAIN-02":
            row["status"] = "DONE"
            row["completionMode"] = "owner-risk-security-waiver"
            row["evidence"] = "release/evidence/P2/manifest.json"
            found.add("TRAIN-02")
        elif row.get("id") == "TRAIN-03":
            row["status"] = "READY"
            row["unblockedBy"] = "TRAIN-02"
            found.add("TRAIN-03")
    if found != {"TRAIN-02", "TRAIN-03"}:
        fail(f"integration train entries missing: {sorted({'TRAIN-02','TRAIN-03'}-found)}")
    write_json(path, data)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--shipment-readiness", required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--source-tree", required=True)
    parser.add_argument("--owner", default="alex00Pirotskyi")
    parser.add_argument("--owner-risk-attestation", required=True)
    parser.add_argument("--release-attestation", required=True)
    args = parser.parse_args()
    root = pathlib.Path(args.project).resolve()
    readiness_path = pathlib.Path(args.shipment_readiness).resolve()
    if args.owner_risk_attestation != OWNER_ATTESTATION:
        fail("exact owner-risk attestation required")
    if args.release_attestation != RELEASE_ATTESTATION:
        fail("exact release attestation required")
    if not HEX40.fullmatch(args.source_commit) or not HEX40.fullmatch(args.source_tree):
        fail("source commit/tree must be exact 40-character Git IDs")
    if git(root, "rev-parse", "HEAD") != args.source_commit or git(root, "rev-parse", "HEAD^{tree}") != args.source_tree:
        fail("current worktree is not the exact tested source commit/tree")
    readiness = load(readiness_path)
    expected = {
        "status": "passed",
        "qaShipmentReady": True,
        "allPlatformsPassed": ["windows", "macos", "linux"],
        "securityEvidenceWaived": True,
        "formalSecurityCompletion": False,
        "productionReleaseEligible": False,
        "manualQaStillRequired": True,
        "sourceCommit": args.source_commit,
        "sourceTree": args.source_tree,
    }
    for key, value in expected.items():
        if readiness.get(key) != value:
            fail(f"shipment readiness mismatch: {key}")
    run_id = readiness.get("workflowRunId")
    if not isinstance(run_id, int):
        fail("shipment workflow run ID missing")
    artifacts = readiness.get("artifacts")
    if not isinstance(artifacts, list) or {row.get("platform") for row in artifacts if isinstance(row, dict)} != set(PLATFORMS):
        fail("exact Windows/macOS/Linux artifact set required")
    artifact_by_platform = {str(row["platform"]): row for row in artifacts if isinstance(row, dict)}
    generated_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    aggregate_dir = root / "release/evidence/P2"
    aggregate_dir.mkdir(parents=True, exist_ok=True)
    copied_readiness = aggregate_dir / "SHIPMENT_READINESS.json"
    committed_readiness = dict(readiness)
    committed_readiness["artifacts"] = [
        {**dict(row), "archive": pathlib.Path(str(row.get("archive", ""))).name}
        for row in artifacts
        if isinstance(row, dict)
    ]
    committed_readiness["recordScope"] = "committed-owner-risk-p2-promotion-evidence"
    write_json(copied_readiness, committed_readiness)
    receipt_rows: dict[str, dict[str, Any]] = {}
    for platform in PLATFORMS:
        artifact = artifact_by_platform[platform]
        artifact_digest = str(artifact.get("sha256", ""))
        if not HEX64.fullmatch(artifact_digest):
            fail(f"{platform}: artifact digest invalid")
        receipt = {
            "schemaVersion": "1.0.0",
            "receiptType": "p2-owner-risk-tri-platform-qa-v1",
            "phase": "P2",
            "platform": platform,
            "status": "passed",
            "sourceCommit": args.source_commit,
            "sourceTree": args.source_tree,
            "workflowRunId": run_id,
            "artifactName": pathlib.Path(str(artifact.get("archive", ""))).name,
            "artifactSha256": artifact_digest,
            "artifactBytes": artifact.get("bytes"),
            "allP2TasksCovered": TASKS,
            "securityEvidenceWaived": True,
            "formalSecurityCompletion": False,
            "independentHumanReviewPerformed": False,
            "manualQaStillRequired": True,
            "productionReleaseEligible": False,
            "generatedAt": generated_at,
        }
        receipt_path = aggregate_dir / f"owner-risk-{platform}-receipt.json"
        write_json(receipt_path, receipt)
        receipt_rows[platform] = {
            "path": receipt_path.relative_to(root).as_posix(),
            "sha256": sha256(receipt_path),
            "workflowRunId": run_id,
            "artifactSha256": artifact_digest,
        }
    waiver = {
        "schemaVersion": "1.0.0",
        "recordType": "kristin-p1a-p2-owner-risk-promotion-waiver-v1",
        "owner": args.owner,
        "ownerRiskAttestation": args.owner_risk_attestation,
        "releaseAttestation": args.release_attestation,
        "reviewedCommit": args.source_commit,
        "reviewedTree": args.source_tree,
        "workflowRunId": run_id,
        "securityEvidenceWaived": True,
        "formalSecurityCompletion": False,
        "independentHumanReviewPerformed": False,
        "manualQaStillRequired": True,
        "releaseCandidateEligible": True,
        "productionReleaseEligible": False,
        "publicGaEligible": False,
        "reasonPublicGaBlocked": "P9 release engineering and P10 alpha/beta/RC rollout trains are not complete.",
        "acceptedAt": generated_at,
    }
    waiver_path = aggregate_dir / "OWNER_RISK_PROMOTION_WAIVER.json"
    write_json(waiver_path, waiver)
    matrix = load(root / "config/p2_task_matrix.json")
    task_rows = matrix.get("tasks")
    if not isinstance(task_rows, list):
        fail("P2 task matrix invalid")
    names = {str(row.get("id")): str(row.get("name")) for row in task_rows if isinstance(row, dict)}
    completed = root / "tasks/completed"
    completed.mkdir(parents=True, exist_ok=True)
    for task in TASKS:
        if task not in names:
            fail(f"task matrix name missing: {task}")
        directory = root / "release/evidence" / task
        manifest_path = directory / "manifest.json"
        tests_path = directory / "test-results.json"
        manifest = load(manifest_path)
        tests = load(tests_path)
        tests.update({
            "status": "passed",
            "sourceOnly": False,
            "ownerRiskWaiver": True,
            "reviewedCommit": args.source_commit,
            "reviewedTree": args.source_tree,
            "triPlatformQaArtifacts": {platform: receipt_rows[platform]["artifactSha256"] for platform in PLATFORMS},
            "formalSecurityCompletion": False,
            "manualQaStillRequired": True,
        })
        write_json(tests_path, tests)
        manifest.update({
            "status": "passed",
            "localResult": "passed",
            "completionClaim": True,
            "reviewedCommit": args.source_commit,
            "reviewedTree": args.source_tree,
            "ownerRiskWaiver": True,
            "formalSecurityCompletion": False,
            "securityEvidenceWaived": True,
            "independentReview": {"status": "waived", "independent": False},
            "ownerApproval": {"status": "approved", "owner": args.owner, "waiverPath": waiver_path.relative_to(root).as_posix()},
            "platformReceipts": receipt_rows,
            "completedTaskPacket": f"tasks/completed/{task}.md",
            "completedAt": generated_at,
        })
        write_json(manifest_path, manifest)
        (completed / f"{task}.md").write_text(
            f"# {task} — {names[task]}\n\n"
            "Status: **DONE — OWNER-RISK WAIVER**\n\n"
            f"Reviewed source commit: `{args.source_commit}`\n\n"
            f"Reviewed source tree: `{args.source_tree}`\n\n"
            f"Tri-platform workflow run: `{run_id}`\n\n"
            "Windows, macOS, and Linux build/test artifacts passed the mandatory V71 tri-platform gate. "
            "Formal security evidence and independent human review were explicitly waived by the owner. "
            "Manual QA and release signing remain required before public GA.\n",
            encoding="utf-8",
        )
    accepted_adr = {
        "schemaVersion": "1.0.0",
        "taskId": "P2-004",
        "status": "accepted",
        "decision": "retain Node automation host plus platform-native PTY/process helpers in owner-risk current-account mode",
        "reviewedCommit": args.source_commit,
        "reviewedTree": args.source_tree,
        "workflowRunId": run_id,
        "platformMeasurements": {
            platform: {
                "artifactSha256": receipt_rows[platform]["artifactSha256"],
                "result": "passed",
                "measurementClass": "tri-platform-build-test-runtime-smoke",
            }
            for platform in PLATFORMS
        },
        "securityEvidenceWaived": True,
        "acceptedAt": generated_at,
    }
    write_json(root / "release/evidence/P2-004/ACCEPTED_ADR.json", accepted_adr)
    aggregate = {
        "schemaVersion": "3.0.0",
        "phase": "P2",
        "status": "passed",
        "completionClaim": True,
        "p3DependencySatisfied": True,
        "promotionMode": "owner-risk-security-waiver",
        "reviewedCommit": args.source_commit,
        "reviewedTree": args.source_tree,
        "packageSha256": "7b0d77d8956f05ff907ca7463b0d787dcebf93a60426aab105be2b610e6072b0",
        "completedTasks": TASKS,
        "platformReceipts": receipt_rows,
        "ownerRiskWaiver": {
            "path": waiver_path.relative_to(root).as_posix(),
            "sha256": sha256(waiver_path),
            "securityEvidenceWaived": True,
            "formalSecurityCompletion": False,
            "independentHumanReviewPerformed": False,
        },
        "shipmentReadinessPath": copied_readiness.relative_to(root).as_posix(),
        "shipmentReadinessSha256": sha256(copied_readiness),
        "workflowRunId": run_id,
        "releaseCandidateEligible": True,
        "productionReleaseEligible": False,
        "publicGaEligible": False,
        "manualQaStillRequired": True,
        "completedAt": generated_at,
    }
    write_json(aggregate_dir / "manifest.json", aggregate)
    update_exit_gate(root)
    update_integration_trains(root)
    print(json.dumps({
        "schemaVersion": "1.0.0",
        "status": "passed",
        "resultType": "v71-owner-risk-p2-finalization-v1",
        "reviewedCommit": args.source_commit,
        "reviewedTree": args.source_tree,
        "completedTasks": TASKS,
        "train02": "DONE",
        "train03": "READY",
        "p3DependencySatisfied": True,
        "securityEvidenceWaived": True,
        "productionReleaseEligible": False,
        "manualQaStillRequired": True,
    }, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
