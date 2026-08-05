#!/usr/bin/env python3
"""Atomically register Worker E records in canonical Test Center v1."""
from __future__ import annotations
import argparse,json,os,tempfile
from pathlib import Path
from typing import Any

REGISTRY=Path("config/test_center_registry.v1.json")
ROOT=Path("release/evidence/P11-001")
MODULE_ID="tm.p11-readiness"
CASE_META={"tc.p11.readiness.claim-boundary":{"displayName":"P11 claim boundary","purpose":"Reject P11-002+, P15, native parity, isolation, device, or release support claims."},"tc.p11.readiness.dependency-status":{"displayName":"P11 dependency status","purpose":"Validate exact P1-001, P2-004, and P1-012 dependency decisions without inferring completion from phase-level claims."},"tc.p11.readiness.device-contracts":{"displayName":"Device contract readiness","purpose":"Validate privacy-safe device states and keep P11-009 and P15-007 unclaimed."},"tc.p11.readiness.fixture-catalog":{"displayName":"Native conformance fixture catalog","purpose":"Validate deterministic bounded fixture specifications without executing privileged or personal-device behavior."},"tc.p11.readiness.isolation-inventory":{"displayName":"Isolation readiness inventory","purpose":"Validate advertised-versus-actual isolation tiers and reject source markers as support claims."},"tc.p11.readiness.native-capability-inventory":{"displayName":"Native capability inventory","purpose":"Validate unique native capability identities, repository paths, platform coverage, and source-versus-behavior classifications."},"tc.p11.readiness.no-silent-fallback":{"displayName":"No silent native fallback","purpose":"Reject silent downgrade into shell parsing, blind input, coordinate-only actions, unknown process identity, or unverified cleanup."},"tc.p11.readiness.nonmutation":{"displayName":"Worker E non-mutation","purpose":"Prove Worker E check mode leaves durable repository inputs byte-identical."},"tc.p11.readiness.platform-gap-matrix":{"displayName":"Platform semantic gap matrix","purpose":"Validate the platform-neutral semantic matrix while preserving Windows, macOS, and Linux truth."},"tc.p11.readiness.semantic-conformance":{"displayName":"Native semantic conformance contract","purpose":"Validate request, result, error, timeout, cancellation, cleanup, and evidence-receipt semantics."}}
MAPPINGS=[{"excludedPaths":["release/evidence/generated/**"],"mappingId":"affected.p11-readiness-dependencies","pathPatterns":["release/evidence/P11-001/dependency-status.json","docs/adr/ADR-0001-runtime-boundaries.md","docs/adr/ADR-0004-automation-host.md","docs/adr/ADR-0012-p2-automation-host.md","release/evidence/P1-001/**","release/evidence/P1-012/**","release/evidence/P2-004/**"],"priority":30,"testIds":["tc.p11.readiness.dependency-status","tc.p11.readiness.claim-boundary"]},{"excludedPaths":["release/evidence/generated/**"],"mappingId":"affected.p11-readiness-native-inventory","pathPatterns":["release/evidence/P11-001/native-capability-inventory.json","release/evidence/P11-001/native-capabilities/*.json"],"priority":31,"testIds":["tc.p11.readiness.native-capability-inventory","tc.p11.readiness.claim-boundary"]},{"excludedPaths":["release/evidence/generated/**"],"mappingId":"affected.p11-readiness-windows-capabilities","pathPatterns":["authority_service/native/windows/**","automation_host/src/windows-*.mjs","windows/**"],"priority":32,"testIds":["tc.p11.readiness.native-capability-inventory","tc.p11.readiness.platform-gap-matrix","tc.p11.readiness.semantic-conformance"]},{"excludedPaths":["release/evidence/generated/**"],"mappingId":"affected.p11-readiness-macos-capabilities","pathPatterns":["authority_service/native/macos/**","macos/**"],"priority":33,"testIds":["tc.p11.readiness.native-capability-inventory","tc.p11.readiness.platform-gap-matrix","tc.p11.readiness.semantic-conformance"]},{"excludedPaths":["release/evidence/generated/**"],"mappingId":"affected.p11-readiness-linux-capabilities","pathPatterns":["authority_service/native/linux/**","tool/sandbox_worker.py","tool/sandbox_worker_test.py","linux/**"],"priority":34,"testIds":["tc.p11.readiness.native-capability-inventory","tc.p11.readiness.platform-gap-matrix","tc.p11.readiness.semantic-conformance","tc.p11.readiness.isolation-inventory"]},{"excludedPaths":["release/evidence/generated/**"],"mappingId":"affected.p11-readiness-semantic-matrix","pathPatterns":["release/evidence/P11-001/platform-gap-matrix.json","release/evidence/P11-001/platform-gap-matrix/*.json"],"priority":35,"testIds":["tc.p11.readiness.platform-gap-matrix","tc.p11.readiness.semantic-conformance","tc.p11.readiness.no-silent-fallback","tc.p11.readiness.claim-boundary"]},{"excludedPaths":["release/evidence/generated/**"],"mappingId":"affected.p11-readiness-conformance-fixtures","pathPatterns":["release/evidence/P11-001/conformance-fixture-catalog.json","release/evidence/P11-001/conformance-fixtures/*.json","evals/fixtures/p11/**"],"priority":36,"testIds":["tc.p11.readiness.semantic-conformance","tc.p11.readiness.fixture-catalog","tc.p11.readiness.nonmutation"]},{"excludedPaths":["release/evidence/generated/**"],"mappingId":"affected.p11-readiness-isolation","pathPatterns":["release/evidence/P11-001/isolation-readiness.json","release/evidence/P11-001/isolation-tiers/*.json","tool/sandbox_worker.py","automation_host/src/process-tree.mjs"],"priority":37,"testIds":["tc.p11.readiness.no-silent-fallback","tc.p11.readiness.isolation-inventory","tc.p11.readiness.claim-boundary"]},{"excludedPaths":["release/evidence/generated/**"],"mappingId":"affected.p11-readiness-devices","pathPatterns":["release/evidence/P11-001/device-contract-readiness.json"],"priority":38,"testIds":["tc.p11.readiness.device-contracts","tc.p11.readiness.claim-boundary"]},{"mappingId":"affected.p11-readiness-validator","pathPatterns":["tool/worker_e_native_parity_readiness.py","tool/worker_e_native_parity_readiness_test.py",".github/workflows/worker-e-native-parity-readiness.yml","tool/worker_e_test_center_registration.py","tool/worker_e_native_parity_model.py","tool/worker_e_test_center_registration_test.py"],"priority":39,"testIds":["tc.p11.readiness.dependency-status","tc.p11.readiness.native-capability-inventory","tc.p11.readiness.platform-gap-matrix","tc.p11.readiness.semantic-conformance","tc.p11.readiness.fixture-catalog","tc.p11.readiness.no-silent-fallback","tc.p11.readiness.isolation-inventory","tc.p11.readiness.device-contracts","tc.p11.readiness.claim-boundary","tc.p11.readiness.nonmutation"]},{"mappingId":"affected.p11-readiness-test-center","pathPatterns":["config/test_center_registry.v1.json"],"priority":40,"testIds":["tc.p11.readiness.dependency-status","tc.p11.readiness.native-capability-inventory","tc.p11.readiness.platform-gap-matrix","tc.p11.readiness.semantic-conformance","tc.p11.readiness.fixture-catalog","tc.p11.readiness.no-silent-fallback","tc.p11.readiness.isolation-inventory","tc.p11.readiness.device-contracts","tc.p11.readiness.claim-boundary","tc.p11.readiness.nonmutation"]},{"mappingId":"affected.p11-readiness-conditional-adrs","pathPatterns":["docs/adr/P11-*.md","docs/architecture/P11-*.md"],"priority":41,"testIds":["tc.p11.readiness.dependency-status","tc.p11.readiness.platform-gap-matrix","tc.p11.readiness.semantic-conformance","tc.p11.readiness.no-silent-fallback","tc.p11.readiness.claim-boundary"]},{"excludedPaths":["release/evidence/generated/**"],"mappingId":"affected.p11-readiness-progress","pathPatterns":["docs/roadmap/progress/2026-08-05-p11-native-parity-readiness.md","release/evidence/P11-001/manifest.json"],"priority":42,"testIds":["tc.p11.readiness.dependency-status","tc.p11.readiness.claim-boundary","tc.p11.readiness.nonmutation"]}]

def canonical_bytes(value:Any)->bytes:
 return (json.dumps(value,sort_keys=True,separators=(",",":"),ensure_ascii=False)+"\n").encode("utf-8")

def _load(project:Path,relative:Path)->dict[str,Any]:
 return json.loads((project/relative).read_text(encoding="utf-8"))

def _catalog_paths(project:Path,name:str)->list[str]:
 data=_load(project,ROOT/name)
 return [str(row["path"]) for row in data.get("catalogFiles",[])]

def _profiles(project:Path)->tuple[dict[str,list[str]],dict[str,list[str]]]:
 registry="config/test_center_registry.v1.json";manifest="release/evidence/P11-001/manifest.json"
 dep="release/evidence/P11-001/dependency-status.json"
 inv="release/evidence/P11-001/native-capability-inventory.json";inv_parts=_catalog_paths(project,"native-capability-inventory.json")
 matrix="release/evidence/P11-001/platform-gap-matrix.json";matrix_parts=_catalog_paths(project,"platform-gap-matrix.json")
 fixtures="release/evidence/P11-001/conformance-fixture-catalog.json";fixture_parts=_catalog_paths(project,"conformance-fixture-catalog.json")
 isolation="release/evidence/P11-001/isolation-readiness.json";isolation_parts=_catalog_paths(project,"isolation-readiness.json")
 devices="release/evidence/P11-001/device-contract-readiness.json"
 validator="tool/worker_e_native_parity_readiness.py";model="tool/worker_e_native_parity_model.py"
 tests="tool/worker_e_native_parity_readiness_test.py";registration_tests="tool/worker_e_test_center_registration_test.py";registrar="tool/worker_e_test_center_registration.py"
 progress="docs/roadmap/progress/2026-08-05-p11-native-parity-readiness.md"
 workflow=".github/workflows/worker-e-native-parity-readiness.yml"
 inputs={
  "tc.p11.readiness.dependency-status":[registry,dep,manifest,validator,model],
  "tc.p11.readiness.native-capability-inventory":[registry,inv,*inv_parts,manifest,validator,model],
  "tc.p11.readiness.platform-gap-matrix":[registry,matrix,*matrix_parts,manifest,validator,model],
  "tc.p11.readiness.semantic-conformance":[registry,matrix,*matrix_parts,manifest,validator,model],
  "tc.p11.readiness.fixture-catalog":[registry,fixtures,*fixture_parts,manifest,validator,model],
  "tc.p11.readiness.no-silent-fallback":[registry,matrix,*matrix_parts,manifest,validator,model],
  "tc.p11.readiness.isolation-inventory":[registry,isolation,*isolation_parts,manifest,validator,model],
  "tc.p11.readiness.device-contracts":[registry,devices,manifest,validator,model],
  "tc.p11.readiness.claim-boundary":[registry,dep,inv,matrix,isolation,devices,manifest,validator,model],
  "tc.p11.readiness.nonmutation":[registry,dep,inv,*inv_parts,matrix,*matrix_parts,fixtures,*fixture_parts,isolation,*isolation_parts,devices,manifest,validator,model,tests,registration_tests,registrar,progress,workflow],
 }
 affected={key:[path for path in value if path not in {registry,manifest}] for key,value in inputs.items()}
 return inputs,affected

def build_registry(current:dict[str,Any],project:Path)->dict[str,Any]:
 inputs,affected=_profiles(project)
 result={key:list(value) if isinstance(value,list) else value for key,value in current.items()}
 result["testModules"]=[row for row in result.get("testModules",[]) if row.get("moduleId")!=MODULE_ID]
 result["testCases"]=[row for row in result.get("testCases",[]) if row.get("moduleId")!=MODULE_ID]
 result["projectTestProfiles"]=[row for row in result.get("projectTestProfiles",[]) if not str(row.get("stableCheckId","")).startswith("tc.p11.readiness.")]
 result["affectedTestMappings"]=[row for row in result.get("affectedTestMappings",[]) if not str(row.get("mappingId","")).startswith("affected.p11-readiness")]
 result["testModules"].append({
  "moduleId":MODULE_ID,"displayName":"P11 Native Parity Readiness",
  "owner":"Worker E / native parity readiness",
  "purpose":"Validate dependency truth, cross-platform semantic inventories, deterministic conformance specifications, isolation and device claim boundaries, and non-mutation without promoting native platform support.",
  "assuranceClasses":["source_contract","behavioral","platform","release"],
 })
 for test_id,meta in CASE_META.items():
  result["testCases"].append({
   "testId":test_id,"moduleId":MODULE_ID,"displayName":meta["displayName"],
   "purpose":meta["purpose"],"assuranceClass":"source_contract","mandatory":True,
   "roadmapTaskIds":["P11-001"],
  })
  result["projectTestProfiles"].append({
   "stableCheckId":test_id,
   "argv":["python","tool/worker_e_native_parity_readiness.py","--check","--project",".","--test-id",test_id],
   "workingDirectory":".","mutationPolicy":"NON_MUTATING","inputPaths":inputs[test_id],
   "expectedOutputs":[],"environmentAllowlist":["CI","GITHUB_ACTIONS","RUNNER_ARCH","RUNNER_OS"],
   "timeoutSeconds":120,"platforms":["linux","macos","windows"],"assuranceClass":"source_contract",
   "affectedPaths":affected[test_id],
   "evidenceDestination":f"release/evidence/generated/worker-e/{test_id}.json",
  })
 result["affectedTestMappings"].extend(MAPPINGS)
 return result

def register(project:Path)->dict[str,Any]:
 path=project/REGISTRY;current=json.loads(path.read_text(encoding="utf-8"))
 expected=canonical_bytes(build_registry(current,project));before=path.read_bytes()
 if before==expected:return {"changed":False,"path":REGISTRY.as_posix(),"bytes":len(expected)}
 fd,name=tempfile.mkstemp(prefix=".worker-e-test-center-",suffix=".tmp",dir=path.parent)
 try:
  with os.fdopen(fd,"wb") as handle:
   handle.write(expected);handle.flush();os.fsync(handle.fileno())
  os.replace(name,path)
 finally:
  try:os.unlink(name)
  except FileNotFoundError:pass
 return {"changed":True,"path":REGISTRY.as_posix(),"bytes":len(expected)}

def main()->int:
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--project",default=".");parser.add_argument("--check",action="store_true")
 args=parser.parse_args();project=Path(args.project).resolve();path=project/REGISTRY
 try:
  current=json.loads(path.read_text(encoding="utf-8"));expected=canonical_bytes(build_registry(current,project))
  if args.check:
   if path.read_bytes()!=expected:
    print(json.dumps({"resultState":"FAIL","error":"Worker E Test Center registration is stale"},sort_keys=True));return 1
   print(json.dumps({"resultState":"PASS","changed":False,"path":REGISTRY.as_posix()},sort_keys=True));return 0
  print(json.dumps({"resultState":"PASS",**register(project)},sort_keys=True));return 0
 except (OSError,json.JSONDecodeError,KeyError,TypeError,ValueError) as error:
  print(json.dumps({"resultState":"ERROR","error":str(error)},sort_keys=True));return 2

if __name__=="__main__":raise SystemExit(main())
