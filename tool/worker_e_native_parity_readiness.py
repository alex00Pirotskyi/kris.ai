#!/usr/bin/env python3
"""Read-only Worker E native parity readiness validator."""
from __future__ import annotations
import argparse, fnmatch, hashlib, json, re, sys
from pathlib import Path
from typing import Any, Iterable, Mapping

sys.dont_write_bytecode = True
_TOOL_DIR = str(Path(__file__).resolve().parent)
if _TOOL_DIR not in sys.path:
    sys.path.insert(0, _TOOL_DIR)
import worker_e_native_parity_model as _model
from worker_e_native_parity_model import *

_load = _model._load
_load_relative = _model._load_relative
_load_inventory = _model._load_inventory
_load_matrix = _model._load_matrix
_load_fixtures = _model._load_fixtures
_load_isolation = _model._load_isolation
_safe_relative = _model._safe_relative
_unique = _model._unique
_require_paths = _model._require_paths
_snapshot = _model._snapshot

def check_fixtures(project:Path)->None:
 d=_load_fixtures(project); rows=d.get("fixtures",[]); ids=[r.get("fixtureId") for r in rows]; _unique(ids,"fixture IDs")
 missing=REQUIRED_FIXTURES-set(ids)
 if missing or d.get("fixtureCount")!=len(rows):raise ReadinessError(f"required fixtures missing/count wrong: {sorted(missing)}")
 for f in ("noRealSecrets","noRealPrivilegedElevation","noDestructiveHostMutation","noExternalNetwork","boundedRuntime","boundedOutput","disposablePaths","deterministicInput","deterministicExpectedOutput"):
  if d.get("requirements",{}).get(f) is not True:raise ReadinessError(f"fixture requirement disabled: {f}")
 for r in rows:
  fid=r["fixtureId"]
  if not r.get("platformApplicability") or set(r["platformApplicability"])-PLATFORMS:raise ReadinessError(f"fixture platform invalid: {fid}")
  for f in ("semanticGoal","fixedInput","expectedCleanup","expectedProcessState","evidenceOutput","assuranceClass","mutationPolicy"):
   if f not in r:raise ReadinessError(f"fixture fields incomplete: {fid}")
  if (r.get("networkPolicy"),r.get("secretPolicy"),r.get("privilegePolicy"))!=("NO_EXTERNAL_NETWORK","NO_REAL_SECRETS","NO_REAL_PRIVILEGED_ELEVATION"):raise ReadinessError(f"fixture permits network, secret, or real elevation: {fid}")
  if r.get("behavioralPassClaimed") is not False or not set(r.get("behavioralExecution",{}).values())<= {"BLOCKED","NOT_IMPLEMENTED"}:raise ReadinessError(f"fixture behavior promoted: {fid}")
  if not _safe_relative(r["evidenceOutput"].get("destination",""),"fixture evidence destination").startswith("release/evidence/"):raise ReadinessError(f"fixture evidence escapes release/evidence: {fid}")

def check_isolation(project:Path)->None:
 d=_load_isolation(project); rows=d.get("tiers",[]); ids=[r.get("tierId") for r in rows]; _unique(ids,"isolation tier IDs")
 if d.get("isolationSupportClaimed") is not False or d.get("silentDowngradeAllowed") is not False or d.get("highAssurancePath",{}).get("status")!="NOT_IMPLEMENTED":raise ReadinessError("isolation falsely supported")
 if {r.get("platform") for r in rows}!=PLATFORMS:raise ReadinessError("isolation platform omission")
 for r in rows:
  tid=r["tierId"]
  if r.get("advertisedTier")!="NOT_ADVERTISED":raise ReadinessError(f"isolation tier advertised without proof: {tid}")
  if r.get("actualImplementation") not in CLASSES or r.get("behavioralEvidence") not in BEHAVIOR or r.get("supportClassification") not in SUPPORT:raise ReadinessError(f"isolation overclaim: {tid}")
  _require_paths(project,r.get("implementationPaths",[]),f"{tid} implementationPaths"); _require_paths(project,r.get("testPaths",[]),f"{tid} testPaths")

def check_devices(project:Path)->None:
 d=_load(project,"devices"); rows=d.get("deviceContracts",[])
 if set(d.get("honestStates",[]))!=DEVICE_STATES or {r.get("deviceClass") for r in rows}!={"printer","scanner","camera","microphone","serial","usb"}:raise ReadinessError("device vocabulary incomplete")
 for r in rows:
  c=r["deviceClass"]
  if set(r.get("allowedStates",[]))!=DEVICE_STATES or r.get("implementationClassification")!="NOT_IMPLEMENTED" or r.get("behavioralEvidenceClassification")!="NOT_IMPLEMENTED" or r.get("realDeviceAccessInOrdinaryCi") is not False or r.get("inventoryContract",{}).get("includePersonalIdentifiersDefault") is not False:raise ReadinessError(f"device support/privacy overclaim: {c}")
 if any(v is not False for v in d.get("ordinaryCi",{}).values()) or any(v is not False for v in d.get("claims",{}).values()):raise ReadinessError("real-device or completion claim")

def _select_affected(changed:Iterable[str],mappings:Iterable[Mapping[str,Any]])->list[str]:
 paths=sorted({_safe_relative(p,"changed path") for p in changed}); selected=set()
 for m in sorted(mappings,key=lambda x:(x.get("priority",1000),x["mappingId"])):
  if any(any(fnmatch.fnmatchcase(p,q) for q in m["pathPatterns"]) and not any(fnmatch.fnmatchcase(p,q) for q in m.get("excludedPaths",[])) for p in paths):selected.update(m["testIds"])
 return sorted(selected)

def check_test_center(project:Path)->None:
 d=_load(project,"registry")
 if "tm.p11-readiness" not in {r.get("moduleId") for r in d.get("testModules",[])}:raise ReadinessError("Worker E Test Center module missing")
 cases=[r for r in d["testCases"] if r.get("moduleId")=="tm.p11-readiness"]; profiles=[r for r in d["projectTestProfiles"] if r.get("stableCheckId") in STABLE_IDS]
 if {r["testId"] for r in cases}!=STABLE_IDS or {r["stableCheckId"] for r in profiles}!=STABLE_IDS:raise ReadinessError("Worker E stable IDs incomplete")
 for r in cases:
  if r.get("assuranceClass")!="source_contract" or r.get("mandatory") is not True or r.get("roadmapTaskIds")!=["P11-001"]:raise ReadinessError(f"invalid source case: {r['testId']}")
 for r in profiles:
  tid=r["stableCheckId"]; expected=["python","tool/worker_e_native_parity_readiness.py","--check","--project",".","--test-id",tid]
  if r.get("argv")!=expected:raise ReadinessError(f"profile does not use structured bounded argv: {tid}")
  if r.get("workingDirectory")!="." or r.get("mutationPolicy")!="NON_MUTATING" or set(r.get("platforms",[]))!=PLATFORMS or r.get("expectedOutputs")!=[]:raise ReadinessError(f"invalid bounded profile: {tid}")
  if not _safe_relative(r.get("evidenceDestination",""),"evidenceDestination").startswith("release/evidence/"):raise ReadinessError(f"invalid evidence destination: {tid}")
  for f in ("inputPaths","affectedPaths"):
   for p in r.get(f,[]):_safe_relative(p,f)
  env=r.get("environmentAllowlist",[])
  if len(env)!=len(set(env)) or any(not re.fullmatch(r"[A-Z_][A-Z0-9_]*",x) for x in env):raise ReadinessError(f"invalid environment allowlist: {tid}")
 maps=[r for r in d["affectedTestMappings"] if str(r.get("mappingId","")).startswith("affected.p11-readiness")]; _unique([r["mappingId"] for r in maps],"Worker E affected mapping IDs")
 if len(maps)<12:raise ReadinessError("Worker E affected mappings incomplete")
 all_ids={r["testId"] for r in d["testCases"]}
 for m in maps:
  if not m.get("pathPatterns") or set(m["testIds"])-all_ids:raise ReadinessError(f"invalid mapping: {m['mappingId']}")
  for f in ("pathPatterns","excludedPaths"):
   for p in m.get(f,[]):_safe_relative(p,f)
 vectors=[["release/evidence/P11-001/dependency-status.json","tool/worker_e_native_parity_readiness.py"],["authority_service/native/windows/authority_service_windows.cpp","release/evidence/P11-001/platform-gap-matrix.json"],["release/evidence/P11-001/device-contract-readiness.json","release/evidence/P11-001/isolation-readiness.json"]]
 for v in vectors:
  if _select_affected(v,maps)!=_select_affected(reversed(v),reversed(maps)):raise ReadinessError(f"affected selection order-dependent: {v}")

def check_artifact_manifest(project:Path)->None:
 d=_load(project,"manifest"); rows=d.get("artifacts",[]); _unique([r.get("path") for r in rows],"manifest artifact paths")
 for r in rows:
  rel=_safe_relative(r["path"],"artifact path"); p=project/rel; digest=hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else ""
  if r.get("sha256")!=digest or not SHA64.fullmatch(str(r.get("sha256",""))):raise ReadinessError(f"manifest artifact digest mismatch: {rel}")
 _unique(d.get("ownedPaths",[]),"owned paths")
 for p in d.get("ownedPaths",[]):_safe_relative(p,"owned path")

def check_claim_boundary(project:Path)->None:
 dep=_load(project,"dependency"); matrix=_load(project,"matrix"); inv=_load(project,"inventory"); iso=_load(project,"isolation"); dev=_load(project,"devices"); man=_load(project,"manifest")
 a=dep.get("activationDecision",{}); forbidden=[a.get("p11_001AdrPreparationAuthorized"),a.get("p11_002PlusAuthorized"),a.get("p15Authorized"),a.get("productImplementationAuthorized"),inv.get("behavioralParityClaimed"),matrix.get("behavioralParityClaimed"),iso.get("isolationSupportClaimed"),dev.get("claims",{}).get("p11_009Complete"),dev.get("claims",{}).get("p15_007Complete"),dev.get("claims",{}).get("deviceAutomationSupported")]
 if any(v is not False for v in forbidden):raise ReadinessError("forbidden support/implementation claim")
 expected={"nativeReadiness":"SOURCE_FOUNDATION","nativeParity":"NOT_CLAIMED","ownerModeParity":"NOT_CLAIMED","isolation":"NOT_CLAIMED","devices":"NOT_CLAIMED","releaseSupport":"NOT_CLAIMED"}
 if matrix.get("claimBoundary")!=expected:raise ReadinessError("claim boundary changed")
 owned=set(man.get("ownedPaths",[]))
 if owned&{"docs/roadmap/MASTER.md","docs/roadmap/roadmap.yaml","docs/roadmap/STATUS.md","docs/roadmap/HANDOFF.md"} or any(p.startswith(("docs/roadmap/anarchy/","release/evidence/P4-001/","evals/fixtures/p3/")) for p in owned):raise ReadinessError("cross-worker/authority collision")
 for f in ("p11_001Done","p11_002PlusIntroduced","p15Introduced","nativeParityComplete","isolationSupported","deviceAutomationSupported","releaseSupported"):
  if man.get("claims",{}).get(f) is not False:raise ReadinessError(f"forbidden manifest claim: {f}")

def _run_selected(project:Path,test_id:str|None)->list[str]:
 checks={
 "tc.p11.readiness.dependency-status":("dependency-status",check_dependency_status),
 "tc.p11.readiness.native-capability-inventory":("native-capability-inventory",check_inventory),
 "tc.p11.readiness.platform-gap-matrix":("platform-gap-matrix",check_platform_matrix),
 "tc.p11.readiness.semantic-conformance":("semantic-conformance",check_platform_matrix),
 "tc.p11.readiness.fixture-catalog":("fixture-catalog",check_fixtures),
 "tc.p11.readiness.no-silent-fallback":("no-silent-fallback",check_no_silent_fallback),
 "tc.p11.readiness.isolation-inventory":("isolation-inventory",check_isolation),
 "tc.p11.readiness.device-contracts":("device-contracts",check_devices),
 "tc.p11.readiness.claim-boundary":("claim-boundary",check_claim_boundary),
 "tc.p11.readiness.nonmutation":("nonmutation",lambda p:None),
 }
 selected=[test_id] if test_id else sorted(checks); done=[]
 for tid in selected:
  if tid not in checks:raise ReadinessError(f"unknown stable test ID: {tid}")
  name,fn=checks[tid]; fn(project); done.append(name)
 check_test_center(project); check_artifact_manifest(project); check_source_manifest(project)
 return done

def check(project:Path,test_id:str|None=None)->dict[str,Any]:
 project=project.resolve(); before=_snapshot(project); done=_run_selected(project,test_id); after=_snapshot(project)
 if before!=after:raise ReadinessError(f"check mode mutated inputs: {sorted(k for k in before if before[k]!=after[k])}")
 return {"schemaVersion":"1.0.0","classification":"SOURCE_CONTRACT","resultState":"PASS","selectedTestId":test_id,"completedChecks":done,"platformBehavior":{"windows":"BLOCKED","macos":"BLOCKED","linux":"BLOCKED"},"certification":"NOT_EVALUATED","capabilitySupport":"SOURCE_FOUNDATION","mutatedPaths":[]}

def main()->int:
 p=argparse.ArgumentParser(description=__doc__); p.add_argument("--check",action="store_true"); p.add_argument("--project",default="."); p.add_argument("--test-id",choices=sorted(STABLE_IDS)); a=p.parse_args()
 if not a.check:print("write mode is intentionally unavailable; use --check",file=sys.stderr);return 2
 try:r=check(Path(a.project),a.test_id)
 except ReadinessError as e:print(json.dumps({"schemaVersion":"1.0.0","resultState":"FAIL","error":str(e)},indent=2,sort_keys=True));return 1
 print(json.dumps(r,indent=2,sort_keys=True));return 0
if __name__=="__main__":raise SystemExit(main())
