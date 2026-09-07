#!/usr/bin/env python3
"""Always-on Product hardening. Inspect exact current Product source/tests inside allowedPaths, identify one concrete correctness, performance, reliability, UX-facing behavior, or missing-regression defect that can be proven locally, and implement the smallest durable code/test fix. Do not create documentation-only, formatting-only, governance-only, or no-op changes."""
from __future__ import annotations
import argparse, fnmatch, hashlib, json, re, sys
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import Any, Iterable, Mapping
sys.dont_write_bytecode = True

# Import the model directly since we're in the same directory
sys.path.insert(0, str(Path(__file__).parent))
from worker_e_native_parity_model import (
    EVIDENCE_ROOT, FILES, INVENTORY_FRAGMENTS, MATRIX_FRAGMENTS,
    FIXTURE_FRAGMENTS, ISOLATION_FRAGMENTS, WORKER_E_DURABLE_PATHS,
    PLATFORMS, CLASSES, BEHAVIOR, SUPPORT, STABLE_IDS,
    REQUIRED_OPERATIONS, REQUIRED_FIXTURES, DEVICE_STATES, FALLBACKS,
    SHA40, SHA64, ReadinessError, _load, _safe_relative, _load_relative,
    _load_inventory, _load_matrix, _load_fixtures, _load_isolation,
    _unique, _require_paths, _snapshot, check_source_manifest,
    check_dependency_status, check_inventory, check_platform_matrix,
    check_no_silent_fallback
)


class ReadinessError(ValueError): pass

def _load(project:Path,key:str)->Any:
    try:
        return json.loads((project/FILES[key]).read_text(encoding="utf-8"))
    except (OSError,json.JSONDecodeError) as e:
        raise ReadinessError(f"cannot load {FILES[key]}: {e}") from e

def _safe_relative(value:str,field:str="path")->str:
    raw=str(value).replace("\\", "/").strip()
    while raw.startswith("./"):raw=raw[2:]
    p=PurePosixPath(raw); w=PureWindowsPath(raw)
    if not raw or raw=="." or raw.startswith("/") or p.is_absolute() or w.is_absolute() or w.drive or ".." in p.parts or ".." in w.parts or "\0" in raw:
        raise ReadinessError(f"{field} must be repository-relative: {value!r}")
    return p.as_posix()

def _load_relative(project:Path,relative:str,field:str)->Any:
    rel=_safe_relative(relative,field); path=project/rel
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError,json.JSONDecodeError) as e:
        raise ReadinessError(f"cannot load {rel}: {e}") from e

def _load_inventory(project:Path)->dict[str,Any]:
    d=dict(_load(project,"inventory")); refs=d.get("catalogFiles",[])
    if not refs:raise ReadinessError("native inventory fragment index incomplete")
    rows=[]; platforms=set()
    for ref in refs:
        platform=ref.get("platform"); fragment=_load_relative(project,ref.get("path",""),f"{platform} capability file")
        if platform not in PLATFORMS or fragment.get("platform")!=platform:raise ReadinessError(f"capability fragment platform mismatch: {platform}")
        values=fragment.get("capabilities",[])
        if ref.get("count")!=len(values) or any(r.get("platform")!=platform for r in values):raise ReadinessError(f"capability fragment count/platform mismatch: {platform}")
        platforms.add(platform);rows.extend(values)
    if platforms!=PLATFORMS:raise ReadinessError("native inventory platform omission")
    d["capabilities"]=rows
    if d.get("capabilityCount")!=len(rows):raise ReadinessError("native capability count mismatch")
    return d

def _load_matrix(project:Path)->dict[str,Any]:
    d=dict(_load(project,"matrix")); refs=d.get("catalogFiles",[])
    if not refs:raise ReadinessError("semantic matrix fragment index incomplete")
    rows=[]; groups=set()
    for ref in refs:
        group=ref.get("group"); fragment=_load_relative(project,ref.get("path",""),f"{group} matrix file")
        if fragment.get("group")!=group:raise ReadinessError(f"matrix fragment group mismatch: {group}")
        values=fragment.get("operations",[])
        if ref.get("count")!=len(values):raise ReadinessError(f"matrix fragment count mismatch: {group}")
        groups.add(group);rows.extend(values)
    if groups!={"process-filesystem","desktop-lifecycle","security-device"}:raise ReadinessError("semantic matrix group omission")
    d["operations"]=rows
    if d.get("operationCount")!=len(rows):raise ReadinessError("semantic operation count mismatch")
    return d

def _load_fixtures(project:Path)->dict[str,Any]:
    d=dict(_load(project,"fixtures")); refs=d.get("catalogFiles",[])
    if not refs:raise ReadinessError("fixture catalog fragment index incomplete")
    rows=[]
    for ref in refs:
        fragment=_load_relative(project,ref.get("path",""),"fixture catalog file");values=fragment.get("fixtures",[])
        if ref.get("count")!=len(values):raise ReadinessError("fixture fragment count mismatch")
        rows.extend(values)
    d["fixtures"]=rows
    if d.get("fixtureCount")!=len(rows):raise ReadinessError("fixture catalog count mismatch")
    return d

def _load_isolation(project:Path)->dict[str,Any]:
    d=dict(_load(project,"isolation")); refs=d.get("catalogFiles",[])
    if not refs:raise ReadinessError("isolation fragment index incomplete")
    rows=[];platforms=set()
    for ref in refs:
        platform=ref.get("platform");fragment=_load_relative(project,ref.get("path",""),f"{platform} isolation file")
        if platform not in PLATFORMS or fragment.get("platform")!=platform:raise ReadinessError(f"isolation fragment platform mismatch: {platform}")
        values=fragment.get("tiers",[])
        if ref.get("count")!=len(values) or any(r.get("platform")!=platform for r in values):raise ReadinessError(f"isolation fragment count/platform mismatch: {platform}")
        platforms.add(platform);rows.extend(values)
    if platforms!=PLATFORMS:raise ReadinessError("isolation platform omission")
    d["tiers"]=rows
    return d

def _unique(values:list[str],label:str)->None:
    dup=sorted({v for v in values if values.count(v)>1})
    if dup:raise ReadinessError(f"duplicate {label}: {dup}")

def _require_paths(project:Path,values:Iterable[str],field:str)->None:
    for value in values:
        rel=_safe_relative(value,field)
        if not (project/rel).exists():raise ReadinessError(f"{field} does not exist: {rel}")

def _snapshot(project:Path)->dict[str,str]:
    return {p.as_posix():hashlib.sha256((project/p).read_bytes()).hexdigest() if (project/p).is_file() else "<MISSING>" for p in WORKER_E_DURABLE_PATHS}

def check_source_manifest(project:Path)->None:
    path=project/"SOURCE_MANIFEST.sha256"
    if not path.is_file():raise ReadinessError("SOURCE_MANIFEST.sha256 is missing")
    entries={}
    for line in path.read_text(encoding="utf-8").splitlines():
        m=re.fullmatch(r"([0-9a-f]{64})  (.+)",line)
        if not m:raise ReadinessError(f"invalid source manifest line: {line!r}")
        rel=_safe_relative(m.group(2),"source manifest path")
        if rel in entries:raise ReadinessError(f"duplicate source manifest path: {rel}")
        entries[rel]=m.group(1)
    for p in WORKER_E_DURABLE_PATHS:
        rel=p.as_posix(); expected=hashlib.sha256((project/p).read_bytes()).hexdigest()
        if entries.get(rel)!=expected:raise ReadinessError(f"source manifest mismatch for {rel}: expected {expected}, got {entries.get(rel)}")

def check_dependency_status(project:Path)->None:
    d=_load(project,"dependency"); inputs=d.get("repositoryInputs",{})
    for name in ("protectedMain","workerA","workerB","workerC","workerD","workerJ"):
        row=inputs.get(name)
        if not isinstance(row,Mapping) or not SHA40.fullmatch(str(row.get("commit",""))):raise ReadinessError(f"{name} commit is not exact")
        if row.get("tree") is not None and not SHA40.fullmatch(str(row["tree"])):raise ReadinessError(f"{name} tree is not exact")
    if (d.get("activationLane"),d.get("classification"),d.get("p11ApprovalState"))!=("LANE_A","P11_NATIVE_READINESS_ACTIVE","P11-001_NOT_APPROVED"):
        raise ReadinessError("P2-004 blocker requires unapproved Lane A")
    decisions={r["taskId"]:r["decision"] for r in d.get("dependencies",[])}
    if decisions!={"P1-001":"READY","P2-004":"MISSING_EVIDENCE","P1-012":"MISSING_IMPLEMENTATION"}:raise ReadinessError(f"dependency decisions changed: {decisions}")
    p2=next(r for r in d["dependencies"] if r["taskId"]=="P2-004")
    blockers={"STARTUP_LATENCY_NOT_MEASURED","STEADY_STATE_MEMORY_NOT_MEASURED","PACKAGING_NOT_PROVEN","RESTART_RECOVERY_NOT_EXERCISED","IPC_FRICTION_NOT_MEASURED","MACOS_NOT_EXECUTED","WINDOWS_NOT_EXECUTED","DECISION_PROVISIONAL"}
    if not blockers<=set(p2.get("blockers",[])):raise ReadinessError("P2-004 blockers incomplete")
    for r in d["dependencies"]:_require_paths(project,r.get("evidencePaths",[]),f"{r['taskId']} evidencePath")
    a=d.get("activationDecision",{})
    for f in ("p11_001AdrPreparationAuthorized","p11_002PlusAuthorized","p15Authorized","productImplementationAuthorized"):
        if a.get(f) is not False:raise ReadinessError(f"forbidden authorization: {f}")
    if d.get("authority",{}).get("authorityModified") is not False:raise ReadinessError("roadmap authority modified")

def check_inventory(project:Path)->None:
    d=_load_inventory(project); rows=d.get("capabilities",[]); ids=[r.get("capabilityId","") for r in rows]
    _unique(ids,"capability IDs")
    if not rows or {r.get("platform") for r in rows}!=PLATFORMS:raise ReadinessError("native inventory platform omission")
    for r in rows:
        cid=r.get("capabilityId")
        for f in ("implementationClassification","testClassification","behavioralEvidenceClassification"):
            if r.get(f) not in CLASSES:raise ReadinessError(f"invalid {f} for {cid}")
        if r.get("behavioralEvidenceClassification") not in BEHAVIOR:raise ReadinessError(f"behavior support inferred from source for {cid}")
        if r.get("supportClassification") not in SUPPORT:raise ReadinessError(f"platform/release support overclaim for {cid}")
        for f in ("implementationPaths","testPaths","evidencePaths"):_require_paths(project,r.get(f,[]),f"{cid} {f}")
        for f in ("semanticPurpose","knownGap","owner","nextAction"):
            if not str(r.get(f,"")) .strip():raise ReadinessError(f"{f} empty for {cid}")
    if d.get("behavioralParityClaimed") is not False or d.get("supportClaim")!="SOURCE_FOUNDATION":raise ReadinessError("native parity/support overclaim")

def check_platform_matrix(project:Path)->None:
    d=_load_matrix(project)
    if set(d.get("mandatoryDesktopPlatforms",[]))!=PLATFORMS or d.get("platformDeferred")!=[]:raise ReadinessError("mandatory desktop platform deferred")
    rows=d.get("operations",[]); names=[r.get("operation") for r in rows]; _unique(names,"semantic operations")
    missing=REQUIRED_OPERATIONS-set(names)
    if missing:raise ReadinessError(f"semantic operations missing: {sorted(missing)}")
    for r in rows:
        op=r["operation"]; details=r.get("platformSpecificDetails",{})
        if r.get("sameSemanticMeaning") is not True or set(details)!=PLATFORMS:raise ReadinessError(f"platform omission for {op}")
        if (r.get("unsupportedState"),r.get("blockedState"))!=("UNSUPPORTED","BLOCKED"):raise ReadinessError(f"state collapse for {op}")
        if r.get("timeout",{}).get("mustNotReportSuccess") is not True or r.get("cleanup",{}).get("completeRequiresVerification") is not True:raise ReadinessError(f"timeout/cleanup ambiguity for {op}")
        needed={"operation","requestedSemanticTier","actualSemanticTier","platform","status","cleanupState","verificationMethod","supportImpact"}
        if not needed<=set(r.get("evidenceReceipt",{}).get("fields",[])):raise ReadinessError(f"receipt incomplete for {op}")
        for p,v in details.items():
            if v.get("implementationClassification") not in CLASSES or v.get("behavioralEvidence") not in BEHAVIOR or v.get("supportClassification") not in SUPPORT:raise ReadinessError(f"truth overclaim for {op} on {p}")
    if d.get("behavioralParityClaimed") is not False:raise ReadinessError("platform parity falsely claimed")

def check_no_silent_fallback(project:Path)->None:
    f=_load(project,"matrix").get("fallbackContract",{})
    if f.get("silentFallbackAllowed") is not False or f.get("requestedTierMaySilentlyDowngrade") is not False:raise ReadinessError("silent fallback is allowed")
    needed={"requestedSemanticTier","actualSemanticTier","reasonForFallback","risk","verificationMethod","supportImpact"}
    if not needed<=set(f.get("requiredFields",[])):raise ReadinessError("fallback fields incomplete")
    if not FALLBACKS<=set(f.get("forbiddenSilentDegradations",[])):raise ReadinessError("forbidden silent degradation list incomplete")

def check_all(project:Path)->None:
    check_source_manifest(project)
    check_dependency_status(project)
    check_inventory(project)
    check_platform_matrix(project)
    check_no_silent_fallback(project)

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=".")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    project = Path(args.project)
    if args.check:
        try:
            check_all(project)
            print(json.dumps({"resultState": "PASS", "schemaVersion": "1.0.0"}))
        except ReadinessError as e:
            print(json.dumps({"resultState": "FAIL", "error": str(e), "schemaVersion": "1.0.0"}))
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
