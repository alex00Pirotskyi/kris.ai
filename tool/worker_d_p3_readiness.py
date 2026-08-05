#!/usr/bin/env python3
"""Validate Worker D P3 readiness records without mutating the repository."""
from __future__ import annotations
import argparse, hashlib, json, re
from pathlib import Path, PurePosixPath

SHA40=re.compile(r"^[0-9a-f]{40}$")
SHA64=re.compile(r"^[0-9a-f]{64}$")
TEST_ID=re.compile(r"^tc\.[a-z0-9]+(?:[._-][a-z0-9]+)*\.[a-z0-9]+(?:[._-][a-z0-9]+)*$")
ALLOWED_BLOCKERS={"MISSING_IMPLEMENTATION","MISSING_ADR","MISSING_MEASUREMENT","MISSING_EXACT_SHA_EVIDENCE","STALE_EVIDENCE","MISSING_INDEPENDENT_REVIEW","CONFLICTING_ARCHITECTURE_DECISION","BLOCKED_EXTERNAL","READY"}
ALLOWED_EVIDENCE={"MEASURED","SOURCE_DERIVED","NOT_RUN","BLOCKED","NOT_APPLICABLE"}
FORBIDDEN_URL=re.compile(r"https?://",re.I)
SECRET_KEYS=re.compile(r"(password|secret|token|api[_-]?key|credential)",re.I)

def load(root, rel):
    return json.loads((root/rel).read_text(encoding="utf-8"))
def canonical(v):
    return json.dumps(v,sort_keys=True,separators=(",",":")).encode()
def relative(value):
    p=PurePosixPath(str(value).replace("\\","/"))
    return bool(value) and not p.is_absolute() and ".." not in p.parts
def walk(v,path=""):
    if isinstance(v,dict):
        for k,x in v.items():
            yield from walk(x,f"{path}/{k}")
    elif isinstance(v,list):
        for i,x in enumerate(v):
            yield from walk(x,f"{path}/{i}")
    else:
        yield path,v

def validate(root:Path)->list[str]:
    errors=[]
    dep=load(root,"release/evidence/P3-001/dependency-status.json")
    for item in dep["dependencies"]:
        for key in ("commit","tree"):
            value=item["implementation"][key]
            if not SHA40.fullmatch(value): errors.append(f"{item['taskId']} invalid {key}")
        if item["decision"] not in ALLOWED_BLOCKERS: errors.append(f"{item['taskId']} invalid decision")
    for b in dep["activation"]["blockers"]:
        if b not in ALLOWED_BLOCKERS: errors.append(f"invalid blocker {b}")
    if dep["activation"]["p3_001ImplementationAuthorized"] is not False:
        errors.append("P3-001 must remain unauthorized")
    matrix=load(root,"release/evidence/P3-001/runtime-candidate-matrix.json")
    ids=[c["candidateId"] for c in matrix["candidates"]]
    if len(ids)!=len(set(ids)): errors.append("duplicate candidate IDs")
    for c in matrix["candidates"]:
        for field,m in c["measurements"].items():
            if m["classification"] not in ALLOWED_EVIDENCE:
                errors.append(f"invalid evidence class {c['candidateId']} {field}")
    spec=load(root,"release/evidence/P3-001/fixture-specification.json")
    fids=[]; routes=[]; checks=[]
    for f in spec["fixtures"]:
        fids.append(f["fixtureId"]); routes.append(f["localRoute"]); checks.append(f["deterministicChecksum"])
        copy=dict(f); supplied=copy.pop("deterministicChecksum")
        actual=hashlib.sha256(canonical(copy)).hexdigest()
        if supplied!=actual: errors.append(f"fixture checksum mismatch {f['fixtureId']}")
        if f["networkPolicy"]["external"]!="DENY": errors.append(f"external network not denied {f['fixtureId']}")
        if not relative(f["localRoute"].lstrip("/")): errors.append(f"invalid route {f['fixtureId']}")
        for path,val in walk(f):
            if isinstance(val,str) and FORBIDDEN_URL.search(val): errors.append(f"external URL {f['fixtureId']} {path}")
            if SECRET_KEYS.search(path) and val not in (False,None,""): errors.append(f"credential-like field {f['fixtureId']} {path}")
        if f["limits"]["maxRequestBytes"]>1048576 or f["limits"]["maxResponseBytes"]>1048576:
            errors.append(f"unbounded fixture {f['fixtureId']}")
    if len(fids)!=len(set(fids)): errors.append("duplicate fixture IDs")
    if len(routes)!=len(set(routes)): errors.append("duplicate fixture routes")
    if len(checks)!=len(set(checks)): errors.append("duplicate fixture checksums")
    if spec["p3_016Claimed"] is not False: errors.append("P3-016 claim must be false")
    tc=load(root,"release/evidence/P3-001/test-center-registration.json")
    if len(tc["stableTestIds"])!=len(set(tc["stableTestIds"])): errors.append("duplicate test IDs")
    for tid in tc["stableTestIds"]:
        if not TEST_ID.fullmatch(tid): errors.append(f"invalid test ID {tid}")
    claim=load(root,"release/evidence/P3-001/claim-boundary.json")
    if claim["supportState"]!="SOURCE_FOUNDATION": errors.append("support state inflation")
    forbidden_states={"BEHAVIOR_SUPPORTED","PLATFORM_SUPPORTED","RELEASE_SUPPORTED"}
    if any(v in forbidden_states for _,v in walk(claim)): errors.append("claim boundary inflated")
    owned_files=[
      "docs/roadmap/progress/2026-08-05-p3-001-readiness.md",
      "release/evidence/P3-001/READINESS.md",
      "release/evidence/P3-001/dependency-status.json",
      "release/evidence/P3-001/runtime-candidate-matrix.json",
      "release/evidence/P3-001/packaging-readiness-contract.json",
      "release/evidence/P3-001/fixture-specification.json",
      "release/evidence/P3-001/test-center-registration.json",
      "release/evidence/P3-001/claim-boundary.json",
    ]
    for rel in owned_files:
        if not (root/rel).is_file(): errors.append(f"missing {rel}")
    forbidden_roots=("lib/product/browser","tool/browser_session","tool/browser_actions","automation_host/browser")
    for rel in forbidden_roots:
        if (root/rel).exists(): errors.append(f"P3-002+ or runtime implementation present: {rel}")
    return errors

def main():
    p=argparse.ArgumentParser()
    p.add_argument("--check",action="store_true")
    p.add_argument("--project",default=".")
    args=p.parse_args()
    if not args.check: raise SystemExit("--check is required; this validator is non-mutating")
    errors=validate(Path(args.project).resolve())
    if errors:
        print("\n".join(f"FAIL {e}" for e in errors))
        raise SystemExit(1)
    print("Worker D P3 readiness: PASS")
if __name__=="__main__": main()
