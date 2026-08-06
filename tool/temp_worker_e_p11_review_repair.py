#!/usr/bin/env python3
"""Bounded one-shot repair for MISSION-010 review findings.

This script is carried outside the product branch. It edits only the checked-out
Worker E candidate after the carrier has merged the exact Worker B owner head.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(".")
B_HEAD = "71770c8ced388d83a278d951fd45a07afdec84db"
B_TREE = "aad287d8e91efffe5816a92665e0c84fa3a0ac3d"
E_HEAD = "825769f639edb5db22b27a222cd5c1c57f4ed775"
E_TREE = "4fd309a006ff4b88c2293b7962c130b5998426ac"
NOW = "2026-08-06T20:30:18Z"
WORK_ID = "WRK-20260806T203018Z-9c4e7b21"


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8", newline="\n")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one exact match, found {count}")
    return text.replace(old, new, 1)


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n"


# Durable local evidence for owner handoff and the already-published scoped
# Worker J review. These records do not transfer authority or promote support.
handoff_path = "release/evidence/P11-001/test-center-owner-handoff.json"
worker_j_review_path = "release/evidence/P11-001/worker-j-activation-review.json"
write(
    handoff_path,
    canonical(
        {
            "schemaVersion": 1,
            "recordType": "TestCenterOwnerHandoff",
            "coordinationId": "MISSION-010-P11-001-TEST-CENTER-OWNER-HANDOFF",
            "mission": "MISSION-010",
            "task": "P11-001",
            "worker": "E",
            "workExecutionId": WORK_ID,
            "status": "OWNER_HANDOFF_PENDING",
            "workerERegistryMutationAllowed": False,
            "workerERegistryDiffRemoved": True,
            "ownerMission": "MISSION-002",
            "ownerWorker": "B",
            "ownerBranch": "agent/b/test-center-contracts-and-review",
            "observedOwnerCommit": B_HEAD,
            "observedOwnerTree": B_TREE,
            "sourceCandidate": {
                "commit": E_HEAD,
                "tree": E_TREE,
                "pullRequest": 71,
            },
            "sourceSpecification": "tool/worker_e_test_center_registration.py",
            "stableTestIdPrefix": "tc.p11.readiness.",
            "moduleId": "tm.p11-readiness",
            "supportPromotion": False,
            "mergeAuthorized": False,
            "nextAction": "MISSION-002 publishes the exact registry union on the owner branch and reviews the final Worker E integration candidate.",
        }
    ),
)
write(
    worker_j_review_path,
    canonical(
        {
            "schemaVersion": 1,
            "recordType": "IndependentReviewReference",
            "reviewerRole": "Worker J",
            "decision": "PASS",
            "reviewType": "NO_CONFLICT_AND_ACTIVATION_STATE",
            "reviewedCommit": E_HEAD,
            "reviewedTree": E_TREE,
            "reviewId": 4877897214,
            "artifactHash": "30fb523c62efa9d8968b8e8763f6033b8821cf8fc64a84844c23af49c075b6fb",
            "scopeExcludes": [
                "dependency owner approval",
                "Test Center owner approval",
                "native behavior security approval",
                "support promotion",
                "integration authorization",
                "merge authorization",
            ],
        }
    ),
)

# Refresh dependency evidence with explicit binding semantics.
dep_path = ROOT / "release/evidence/P11-001/dependency-status.json"
dep = json.loads(dep_path.read_text(encoding="utf-8"))
dep["generatedAt"] = NOW
dep["repositoryInputs"] = {
    "protectedMain": {
        "bindingKind": "ANCESTRY_BASE",
        "branch": "main",
        "commit": "0a4176bcbcb975684c3a590be652c9fffe1ce770",
        "tree": "641e11e63fa84f3a16dc4d74b418778839ce5bc2",
        "requiredAncestry": True,
        "role": "protected source authority ancestor",
    },
    "workerA": {
        "bindingKind": "IMMUTABLE_EVIDENCE_SNAPSHOT",
        "branch": "agent/a/p1-p2-new-roadmap-execution",
        "pr": 64,
        "commit": "89a15332019c73675a19cdacd7021fae2199d75e",
        "tree": "2ea1f8a718a69dba0120a4f98acb78053d6cebfb",
        "liveHeadClaimed": False,
        "role": "reviewed P1/P1A/P2 source evidence snapshot; not ancestry",
        "evidencePaths": [
            "docs/adr/ADR-0012-p2-automation-host.md",
            "release/evidence/P2-004/technology-spike.json",
            "release/evidence/P2-004/IMPLEMENTATION.md",
        ],
    },
    "workerB": {
        "bindingKind": "ANCESTRY_BASE",
        "branch": "agent/b/test-center-contracts-and-review",
        "pr": 65,
        "commit": B_HEAD,
        "tree": B_TREE,
        "requiredAncestry": True,
        "role": "current canonical Test Center owner ancestry",
    },
    "workerC": {
        "bindingKind": "HISTORICAL_CONTEXT",
        "branch": "agent/p4-001-search-provider-foundation",
        "pr": 62,
        "commit": "a608700a908042fedf18c8431402551da6853f7d",
        "tree": "e0e98e78032b8c8acef18a7331ee3c629f7f2297",
        "authoritative": False,
        "liveHeadClaimed": False,
        "role": "P4 context snapshot; not a P11 dependency or ancestry claim",
    },
    "workerD": {
        "bindingKind": "HISTORICAL_CONTEXT",
        "branch": "agent/d/p3-readiness-fixtures",
        "pr": 68,
        "commit": "7eecc840f68ca0dff13ab58c138845593254e390",
        "tree": "2080824a34956e3b202126a0a9bd61b4d645d338",
        "authoritative": False,
        "liveHeadClaimed": False,
        "role": "P3 context snapshot; no competing P11 architecture",
    },
    "workerI": {
        "bindingKind": "REVIEWER_AVAILABILITY",
        "activeBranch": None,
        "activePr": None,
        "resolution": "NO_GENUINELY_INDEPENDENT_WORKER_I_LANE_RESOLVED",
        "role": "independent native/security review remains externally blocked",
    },
    "workerJ": {
        "bindingKind": "IMMUTABLE_REVIEW_SNAPSHOT",
        "branch": "agent/j/P24-001-roadmap-as-data-adr",
        "pr": 66,
        "commit": "cb5e16c232c7a2309632a3fc0dcccd8d6e9d0bd7",
        "tree": "9497333f131ccddcb229aa5b179927aeac8dfd31",
        "liveHeadClaimed": False,
        "role": "exact no-conflict and activation-state PASS input",
        "evidencePaths": [worker_j_review_path],
    },
}
dep["reviewState"] = {
    "workerA": "OWNER_DECISION_PENDING",
    "workerB": "OWNER_PUBLICATION_AND_REVIEW_PENDING",
    "workerI": "REQUEST_CHANGES_RECORDED_BUT_GENUINE_INDEPENDENCE_UNSATISFIED",
    "workerJ": "PASS_NO_CONFLICT_AND_ACTIVATION_STATE_ONLY",
}
dep_path.write_text(canonical(dep), encoding="utf-8")

# Harden Git binding validation and distinguish owned from observed paths.
model_path = "tool/worker_e_native_parity_model.py"
model = read(model_path)
model = replace_once(
    model,
    "import argparse, fnmatch, hashlib, json, re, sys\n",
    "import argparse, fnmatch, hashlib, json, re, subprocess, sys\n",
    "model imports",
)
model = replace_once(
    model,
    ' "manifest":EVIDENCE_ROOT/"manifest.json",\n "registry":Path("config/test_center_registry.v1.json"),\n',
    ' "manifest":EVIDENCE_ROOT/"manifest.json",\n "handoff":EVIDENCE_ROOT/"test-center-owner-handoff.json",\n "workerJReview":EVIDENCE_ROOT/"worker-j-activation-review.json",\n "registry":Path("config/test_center_registry.v1.json"),\n',
    "model FILES",
)
durable_pattern = re.compile(r"WORKER_E_DURABLE_PATHS=\(.*?\n\)\nPLATFORMS=", re.S)
durable_replacement = '''WORKER_E_DURABLE_PATHS=(
 Path(".github/workflows/worker-e-native-parity-readiness.yml"),
 Path("docs/roadmap/progress/2026-08-05-p11-native-parity-readiness.md"),
 FILES["dependency"],FILES["inventory"],*INVENTORY_FRAGMENTS,
 FILES["matrix"],*MATRIX_FRAGMENTS,FILES["fixtures"],*FIXTURE_FRAGMENTS,
 FILES["isolation"],*ISOLATION_FRAGMENTS,FILES["devices"],FILES["handoff"],FILES["workerJReview"],FILES["manifest"],
 Path("tool/worker_e_native_parity_model.py"),
 Path("tool/worker_e_native_parity_readiness.py"),
 Path("tool/worker_e_native_parity_readiness_test.py"),
 Path("tool/worker_e_test_center_registration_test.py"),
 Path("tool/worker_e_test_center_registration.py"),
)
WORKER_E_OBSERVED_SHARED_PATHS=(FILES["registry"],)
WORKER_E_MANIFEST_PATHS=WORKER_E_DURABLE_PATHS+WORKER_E_OBSERVED_SHARED_PATHS
PLATFORMS='''
model, count = durable_pattern.subn(durable_replacement, model, count=1)
if count != 1:
    raise SystemExit(f"durable path block replacement count={count}")
model = replace_once(
    model,
    'def _snapshot(project:Path)->dict[str,str]:\n return {p.as_posix():hashlib.sha256((project/p).read_bytes()).hexdigest() if (project/p).is_file() else "<MISSING>" for p in WORKER_E_DURABLE_PATHS}\n',
    'def _snapshot(project:Path)->dict[str,str]:\n return {p.as_posix():hashlib.sha256((project/p).read_bytes()).hexdigest() if (project/p).is_file() else "<MISSING>" for p in WORKER_E_MANIFEST_PATHS}\n',
    "snapshot paths",
)
model = replace_once(
    model,
    " for p in WORKER_E_DURABLE_PATHS:\n",
    " for p in WORKER_E_MANIFEST_PATHS:\n",
    "source manifest paths",
)
dependency_pattern = re.compile(
    r"def check_dependency_status\(project:Path\)->None:\n.*?(?=\ndef check_inventory)",
    re.S,
)
dependency_replacement = r'''def _git_commit_tree(project:Path,commit:str)->str:
 try:
  return subprocess.check_output(["git","-C",str(project),"rev-parse",f"{commit}^{{tree}}"],stderr=subprocess.STDOUT,text=True).strip()
 except (OSError,subprocess.CalledProcessError) as error:
  raise ReadinessError(f"missing Git commit: {commit}") from error

def _git_is_ancestor(project:Path,ancestor:str)->bool:
 try:
  return subprocess.run(["git","-C",str(project),"merge-base","--is-ancestor",ancestor,"HEAD"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=False).returncode==0
 except OSError as error:
  raise ReadinessError(f"cannot evaluate Git ancestry for {ancestor}") from error

def _verify_repository_binding(project:Path,name:str,row:Mapping[str,Any])->None:
 kind=row.get("bindingKind")
 if kind=="REVIEWER_AVAILABILITY":
  if name!="workerI" or row.get("activeBranch") is not None or row.get("activePr") is not None:raise ReadinessError(f"{name} reviewer availability binding is invalid")
  return
 commit=str(row.get("commit",""));tree=str(row.get("tree",""))
 if not SHA40.fullmatch(commit) or not SHA40.fullmatch(tree):raise ReadinessError(f"{name} binding lacks exact commit/tree")
 if kind=="HISTORICAL_CONTEXT":
  if row.get("authoritative") is not False or row.get("liveHeadClaimed") is not False:raise ReadinessError(f"{name} historical context is ambiguous or authoritative")
  return
 actual_tree=_git_commit_tree(project,commit)
 if actual_tree!=tree:raise ReadinessError(f"{name} commit/tree mismatch: {commit} -> {actual_tree}, declared {tree}")
 if kind=="ANCESTRY_BASE":
  if row.get("requiredAncestry") is not True or not str(row.get("branch","")).strip():raise ReadinessError(f"{name} ancestry binding is incomplete")
  if not _git_is_ancestor(project,commit):raise ReadinessError(f"{name} required ancestry is missing: {commit}")
  return
 if kind in {"IMMUTABLE_EVIDENCE_SNAPSHOT","IMMUTABLE_REVIEW_SNAPSHOT"}:
  if row.get("liveHeadClaimed") is not False or not row.get("evidencePaths"):raise ReadinessError(f"{name} immutable snapshot lacks evidence or claims live state")
  _require_paths(project,row.get("evidencePaths",[]),f"{name} binding evidence")
  return
 if kind=="LIVE_HEAD_AT_CANDIDATE":
  if row.get("resolvedHead")!=commit or row.get("observedRemoteHead")!=commit:raise ReadinessError(f"{name} live head drifted from exact candidate binding")
  return
 raise ReadinessError(f"{name} has unknown or ambiguous bindingKind: {kind!r}")

def check_dependency_status(project:Path)->None:
 d=_load(project,"dependency");inputs=d.get("repositoryInputs",{})
 expected={"protectedMain","workerA","workerB","workerC","workerD","workerI","workerJ"}
 if set(inputs)!=expected:raise ReadinessError(f"repository input set changed: {sorted(inputs)}")
 for name,row in inputs.items():
  if not isinstance(row,Mapping):raise ReadinessError(f"{name} repository binding must be an object")
  _verify_repository_binding(project,name,row)
 if (d.get("activationLane"),d.get("classification"),d.get("p11ApprovalState"))!=("LANE_A","P11_NATIVE_READINESS_ACTIVE","P11-001_NOT_APPROVED"):raise ReadinessError("P2-004 blocker requires unapproved Lane A")
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
'''
model, count = dependency_pattern.subn(dependency_replacement, model, count=1)
if count != 1:
    raise SystemExit(f"dependency validator replacement count={count}")
write(model_path, model)

# Convert the registry utility to a read-only owner-handoff validator.
registration_path = "tool/worker_e_test_center_registration.py"
registration = read(registration_path)
registration = replace_once(
    registration,
    'ROOT=Path("release/evidence/P11-001")\n',
    'ROOT=Path("release/evidence/P11-001")\nHANDOFF=ROOT/"test-center-owner-handoff.json"\n',
    "registration handoff constant",
)
tail_pattern = re.compile(r"def register\(project:Path\)->dict\[str,Any\]:.*\Z", re.S)
tail_replacement = r'''def validate_handoff(project:Path)->dict[str,Any]:
 current=_load(project,REGISTRY);handoff=_load(project,HANDOFF)
 if handoff.get("status")!="OWNER_HANDOFF_PENDING" or handoff.get("workerERegistryMutationAllowed") is not False:raise ValueError("Worker E Test Center owner handoff is invalid")
 expected=build_registry(current,project)
 modules=[row for row in current.get("testModules",[]) if row.get("moduleId")==MODULE_ID]
 cases=[row for row in current.get("testCases",[]) if str(row.get("testId","")).startswith("tc.p11.readiness.")]
 profiles=[row for row in current.get("projectTestProfiles",[]) if str(row.get("stableCheckId","")).startswith("tc.p11.readiness.")]
 mappings=[row for row in current.get("affectedTestMappings",[]) if str(row.get("mappingId","")).startswith("affected.p11-readiness")]
 live_count=sum(map(len,(modules,cases,profiles,mappings)))
 if live_count==0:state="OWNER_HANDOFF_PENDING"
 elif current==expected:state="OWNER_PUBLICATION_PRESENT"
 else:raise ValueError("partial or stale Worker E Test Center owner publication")
 preview=canonical_bytes(expected)
 return {"resultState":"PASS","state":state,"registryMutated":False,"moduleId":MODULE_ID,"stableTestIds":sorted(CASE_META),"previewSha256":__import__("hashlib").sha256(preview).hexdigest(),"previewBytes":len(preview)}

def main()->int:
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--project",default=".");parser.add_argument("--check",action="store_true")
 args=parser.parse_args();project=Path(args.project).resolve()
 try:print(json.dumps(validate_handoff(project),sort_keys=True));return 0
 except (OSError,json.JSONDecodeError,KeyError,TypeError,ValueError) as error:print(json.dumps({"resultState":"ERROR","error":str(error)},sort_keys=True));return 2

if __name__=="__main__":raise SystemExit(main())
'''
registration, count = tail_pattern.subn(tail_replacement, registration, count=1)
if count != 1:
    raise SystemExit(f"registration tail replacement count={count}")
write(registration_path, registration)

# Validate the preview contract without requiring an unauthorized live registry mutation.
readiness_path = "tool/worker_e_native_parity_readiness.py"
readiness = read(readiness_path)
readiness = replace_once(
    readiness,
    "import worker_e_native_parity_model as _model\n",
    "import worker_e_native_parity_model as _model\nimport worker_e_test_center_registration as _registration\n",
    "readiness imports",
)
tc_pattern = re.compile(r"def check_test_center\(project:Path\)->None:\n.*?(?=\ndef check_artifact_manifest)", re.S)
tc_replacement = r'''def check_test_center(project:Path)->None:
 state=_registration.validate_handoff(project)
 if state.get("registryMutated") is not False:raise ReadinessError("Worker E registry mutation is forbidden")
 current=_load(project,"registry");d=_registration.build_registry(current,project)
 if "tm.p11-readiness" not in {r.get("moduleId") for r in d.get("testModules",[])}:raise ReadinessError("Worker E Test Center preview module missing")
 cases=[r for r in d["testCases"] if r.get("moduleId")=="tm.p11-readiness"];profiles=[r for r in d["projectTestProfiles"] if r.get("stableCheckId") in STABLE_IDS]
 if {r["testId"] for r in cases}!=STABLE_IDS or {r["stableCheckId"] for r in profiles}!=STABLE_IDS:raise ReadinessError("Worker E preview stable IDs incomplete")
 for r in cases:
  if r.get("assuranceClass")!="source_contract" or r.get("mandatory") is not True or r.get("roadmapTaskIds")!=["P11-001"]:raise ReadinessError(f"invalid source case: {r['testId']}")
 for r in profiles:
  tid=r["stableCheckId"];expected=["python","tool/worker_e_native_parity_readiness.py","--check","--project",".","--test-id",tid]
  if r.get("argv")!=expected:raise ReadinessError(f"profile does not use structured bounded argv: {tid}")
  if r.get("workingDirectory")!="." or r.get("mutationPolicy")!="NON_MUTATING" or set(r.get("platforms",[]))!=PLATFORMS or r.get("expectedOutputs")!=[]:raise ReadinessError(f"invalid bounded profile: {tid}")
 maps=[r for r in d["affectedTestMappings"] if str(r.get("mappingId","")).startswith("affected.p11-readiness")];_unique([r["mappingId"] for r in maps],"Worker E affected mapping IDs")
 if len(maps)<12:raise ReadinessError("Worker E affected mappings incomplete")
 all_ids={r["testId"] for r in d["testCases"]}
 for m in maps:
  if not m.get("pathPatterns") or set(m["testIds"])-all_ids:raise ReadinessError(f"invalid mapping: {m['mappingId']}")
 vectors=[["release/evidence/P11-001/dependency-status.json","tool/worker_e_native_parity_readiness.py"],["authority_service/native/windows/authority_service_windows.cpp","release/evidence/P11-001/platform-gap-matrix.json"],["release/evidence/P11-001/device-contract-readiness.json","release/evidence/P11-001/isolation-readiness.json"]]
 for v in vectors:
  if _select_affected(v,maps)!=_select_affected(reversed(v),reversed(maps)):raise ReadinessError(f"affected selection order-dependent: {v}")
'''
readiness, count = tc_pattern.subn(tc_replacement, readiness, count=1)
if count != 1:
    raise SystemExit(f"test-center validator replacement count={count}")
write(readiness_path, readiness)

# Replace registration regressions with owner-handoff/non-mutation checks.
write(
    "tool/worker_e_test_center_registration_test.py",
    '''#!/usr/bin/env python3
"Owner-handoff regressions for Worker E Test Center registration."
from __future__ import annotations
import importlib.util,json
from pathlib import Path
import shutil,sys,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
MODULE_PATH=ROOT/"tool"/"worker_e_test_center_registration.py"
SPEC=importlib.util.spec_from_file_location("worker_e_test_center_registration",MODULE_PATH);assert SPEC and SPEC.loader
registration=importlib.util.module_from_spec(SPEC);sys.modules[SPEC.name]=registration;SPEC.loader.exec_module(registration)
INDEX_PATHS=(Path("release/evidence/P11-001/native-capability-inventory.json"),Path("release/evidence/P11-001/platform-gap-matrix.json"),Path("release/evidence/P11-001/conformance-fixture-catalog.json"),Path("release/evidence/P11-001/isolation-readiness.json"))
class WorkerETestCenterHandoffTest(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix="worker-e-handoff-");self.project=Path(self.temp.name)
  for relative in (registration.REGISTRY,registration.HANDOFF,*INDEX_PATHS):
   source=ROOT/relative;target=self.project/relative;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
 def tearDown(self):self.temp.cleanup()
 def test_preview_is_deterministic_and_non_mutating(self):
  path=self.project/registration.REGISTRY;before=path.read_bytes();first=registration.validate_handoff(self.project);second=registration.validate_handoff(self.project)
  self.assertEqual(before,path.read_bytes());self.assertEqual(first,second);self.assertFalse(first["registryMutated"])
 def test_partial_owner_publication_is_rejected(self):
  path=self.project/registration.REGISTRY;data=json.loads(path.read_text());data["testModules"].append({"moduleId":registration.MODULE_ID});path.write_text(json.dumps(data),encoding="utf-8")
  with self.assertRaisesRegex(ValueError,"partial or stale"):registration.validate_handoff(self.project)
 def test_complete_owner_publication_is_accepted(self):
  path=self.project/registration.REGISTRY;data=json.loads(path.read_text());path.write_bytes(registration.canonical_bytes(registration.build_registry(data,self.project)))
  self.assertEqual("OWNER_PUBLICATION_PRESENT",registration.validate_handoff(self.project)["state"])
if __name__=="__main__":unittest.main(verbosity=2)
''',
)

# Extend semantic regressions with exact binding failures.
test_path = "tool/worker_e_native_parity_readiness_test.py"
tests = read(test_path)
tests = replace_once(tests, "import unittest\n", "import unittest\nfrom unittest import mock\n", "test imports")
tests = replace_once(
    tests,
    '        for key in ("dependency", "inventory", "matrix", "fixtures", "isolation", "devices", "manifest", "registry"):\n',
    '        for key in ("dependency", "inventory", "matrix", "fixtures", "isolation", "devices", "handoff", "workerJReview", "manifest", "registry"):\n',
    "test copied files",
)
tests = replace_once(
    tests,
    "        self.project = Path(self.temp.name)\n",
    "        self.project = Path(self.temp.name)\n        self.verify_binding = readiness._verify_repository_binding\n        self.binding_patch = mock.patch.object(readiness, \"_verify_repository_binding\")\n        self.binding_patch.start()\n",
    "test binding patch setup",
)
tests = replace_once(
    tests,
    "    def tearDown(self) -> None:\n        self.temp.cleanup()\n",
    "    def tearDown(self) -> None:\n        self.binding_patch.stop()\n        self.temp.cleanup()\n",
    "test binding patch teardown",
)
tests = replace_once(
    tests,
    "for relative in sorted(readiness.WORKER_E_DURABLE_PATHS, key=lambda item: item.as_posix()):\n",
    "for relative in sorted(readiness.WORKER_E_MANIFEST_PATHS, key=lambda item: item.as_posix()):\n",
    "test manifest paths",
)
new_tests = r'''
    def test_nonexistent_git_commit_is_rejected(self) -> None:
        row={"bindingKind":"ANCESTRY_BASE","branch":"main","commit":"1"*40,"tree":"2"*40,"requiredAncestry":True}
        with mock.patch.object(readiness,"_git_commit_tree",side_effect=readiness.ReadinessError("missing Git commit")):
            with self.assertRaisesRegex(readiness.ReadinessError,"missing Git commit"):self.verify_binding(self.project,"protectedMain",row)

    def test_mismatched_commit_tree_is_rejected(self) -> None:
        row={"bindingKind":"ANCESTRY_BASE","branch":"main","commit":"1"*40,"tree":"2"*40,"requiredAncestry":True}
        with mock.patch.object(readiness,"_git_commit_tree",return_value="3"*40):
            with self.assertRaisesRegex(readiness.ReadinessError,"commit/tree mismatch"):self.verify_binding(self.project,"protectedMain",row)

    def test_missing_required_ancestry_is_rejected(self) -> None:
        row={"bindingKind":"ANCESTRY_BASE","branch":"main","commit":"1"*40,"tree":"2"*40,"requiredAncestry":True}
        with mock.patch.object(readiness,"_git_commit_tree",return_value="2"*40),mock.patch.object(readiness,"_git_is_ancestor",return_value=False):
            with self.assertRaisesRegex(readiness.ReadinessError,"required ancestry is missing"):self.verify_binding(self.project,"workerB",row)

    def test_ambiguous_binding_kind_is_rejected(self) -> None:
        with self.assertRaisesRegex(readiness.ReadinessError,"unknown or ambiguous bindingKind"):self.verify_binding(self.project,"workerA",{"commit":"1"*40,"tree":"2"*40})

    def test_live_head_drift_is_rejected(self) -> None:
        row={"bindingKind":"LIVE_HEAD_AT_CANDIDATE","branch":"example","commit":"1"*40,"tree":"2"*40,"resolvedHead":"1"*40,"observedRemoteHead":"3"*40}
        with mock.patch.object(readiness,"_git_commit_tree",return_value="2"*40):
            with self.assertRaisesRegex(readiness.ReadinessError,"live head drifted"):self.verify_binding(self.project,"workerB",row)
'''
marker = '\n\nif __name__ == "__main__":\n'
if marker not in tests:
    raise SystemExit("test insertion marker missing")
tests = tests.replace(marker, "\n" + new_tests + marker, 1)
write(test_path, tests)

# Replace the self-publishing workflow with read-only exact-head validation.
workflow_lines = [
    "name: Worker E Native Parity Readiness",
    "",
    "on:",
    "  push:",
    "    branches:",
    "      - agent/e/native-parity-readiness",
    "  workflow_dispatch:",
    "",
    "permissions:",
    "  contents: read",
    "",
    "concurrency:",
    "  group: worker-e-native-parity-readiness-${{ github.ref }}",
    "  cancel-in-progress: false",
    "",
    "jobs:",
    "  validate:",
    "    name: Source verification (${{ matrix.platform }})",
    "    strategy:",
    "      fail-fast: false",
    "      matrix:",
    "        include:",
    "          - {platform: linux, os: ubuntu-24.04}",
    "          - {platform: windows, os: windows-2025}",
    "          - {platform: macos, os: macos-15}",
    "    runs-on: ${{ matrix.os }}",
    "    steps:",
    "      - name: Check out exact Worker E candidate",
    "        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1",
    "        with:",
    "          ref: ${{ github.sha }}",
    "          fetch-depth: 0",
    "          persist-credentials: false",
    "      - name: Set up Python",
    "        uses: actions/setup-python@5fda3b95a4ea91299a34e894583c3862153e4b97 # v7.0.0",
    "        with:",
    "          python-version: '3.12.10'",
    "      - name: Record exact identity",
    "        shell: bash",
    "        run: |",
    "          set -euo pipefail",
    "          test \"$(git rev-parse HEAD)\" = \"${GITHUB_SHA}\"",
    "          printf 'commit=%s\\ntree=%s\\n' \"$(git rev-parse HEAD)\" \"$(git rev-parse HEAD^{tree})\"",
    "      - name: Validate Worker E owner handoff and semantic regressions",
    "        shell: bash",
    "        run: |",
    "          python tool/worker_e_test_center_registration.py --check --project .",
    "          python -m unittest -v tool/worker_e_native_parity_readiness_test.py tool/worker_e_test_center_registration_test.py",
    "          python tool/worker_e_native_parity_readiness.py --check --project .",
    "      - name: Validate canonical Test Center and P8 hierarchy",
    "        shell: bash",
    "        run: |",
    "          python tool/test_center_contracts.py check --project .",
    "          python -m unittest -v tool/test_center_contracts_test.py",
    "          python tool/test_center_assurance_hierarchy.py check --project .",
    "          python -m unittest -v tool/test_center_assurance_hierarchy_test.py",
    "      - name: Prove source manifest and non-mutation",
    "        shell: bash",
    "        run: |",
    "          set -euo pipefail",
    "          cp SOURCE_MANIFEST.sha256 \"${RUNNER_TEMP}/SOURCE_MANIFEST.before\"",
    "          python tool/p1a_refresh_source_manifest.py .",
    "          cmp \"${RUNNER_TEMP}/SOURCE_MANIFEST.before\" SOURCE_MANIFEST.sha256",
    "          python tool/p1a_refresh_source_manifest.py .",
    "          cmp \"${RUNNER_TEMP}/SOURCE_MANIFEST.before\" SOURCE_MANIFEST.sha256",
    "          git diff --check",
    "          git diff --exit-code",
]
write(".github/workflows/worker-e-native-parity-readiness.yml", "\n".join(workflow_lines) + "\n")

progress_path = "docs/roadmap/progress/2026-08-05-p11-native-parity-readiness.md"
progress = read(progress_path)
section = "\n\n## 2026-08-06 exact review repair\n\nWorker I review findings are addressed at source level without promoting P11-001:\n\n- repository dependency bindings now distinguish ancestry, immutable evidence, historical context, reviewer availability, and live-head observations;\n- commit-to-tree and required-ancestry checks fail closed;\n- canonical Test Center registry mutation was removed from Worker E;\n- MISSION-002 remains the sole registry publisher through coordination `MISSION-010-P11-001-TEST-CENTER-OWNER-HANDOFF`;\n- the Worker E workflow is read-only and no longer self-publishes generated state;\n- P2-004 measurements, production native transports, genuine independent security approval, behavioral parity, platform support, release support, and merge authorization remain absent.\n"
if "## 2026-08-06 exact review repair" not in progress:
    write(progress_path, progress.rstrip() + section)

# Refresh the Worker E artifact and ownership manifest.
manifest_path = ROOT / "release/evidence/P11-001/manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
manifest["generatedAt"] = NOW
manifest["stage"] = "REVIEW_REPAIR_INTEGRATION_CANDIDATE"
manifest["base"] = {
    "branch": "agent/b/test-center-contracts-and-review",
    "commit": B_HEAD,
    "tree": B_TREE,
    "pullRequest": 65,
}
manifest["reviewState"] = {
    "workerADependencyVerification": "PENDING",
    "workerB": "OWNER_PUBLICATION_AND_REVIEW_PENDING",
    "workerEAuthoredReviewerPass": False,
    "workerI": "REQUEST_CHANGES_REPAIRED_SOURCE_GENUINE_INDEPENDENCE_PENDING",
    "workerJ": "PASS_NO_CONFLICT_AND_ACTIVATION_STATE_ONLY",
}
manifest["counts"]["semanticRegressionTests"] = 22
manifest["testCenter"]["publicationState"] = "OWNER_HANDOFF_PENDING"
manifest["testCenter"]["workerERegistryMutationAllowed"] = False
manifest["ownedPaths"] = [
    path for path in manifest.get("ownedPaths", [])
    if path != "config/test_center_registry.v1.json"
]
for permanent in (handoff_path, worker_j_review_path):
    if permanent not in manifest["ownedPaths"]:
        manifest["ownedPaths"].append(permanent)
artifacts = [
    item for item in manifest.get("artifacts", [])
    if item.get("path") != "config/test_center_registry.v1.json"
]
for permanent in (handoff_path, worker_j_review_path):
    if not any(item.get("path") == permanent for item in artifacts):
        artifacts.append({"path": permanent, "bytes": 0, "sha256": ""})
for item in artifacts:
    path = ROOT / item["path"]
    if not path.is_file():
        raise SystemExit(f"manifest artifact missing: {path}")
    payload = path.read_bytes()
    item["bytes"] = len(payload)
    item["sha256"] = hashlib.sha256(payload).hexdigest()
manifest["artifacts"] = sorted(artifacts, key=lambda item: item["path"])
manifest["ownedPaths"] = sorted(set(manifest["ownedPaths"]))
manifest_path.write_text(canonical(manifest), encoding="utf-8")

print(json.dumps({"resultState": "PASS", "workExecutionId": WORK_ID}, sort_keys=True))
