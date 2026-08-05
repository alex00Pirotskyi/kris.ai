#!/usr/bin/env python3
from __future__ import annotations
import argparse,hashlib,json,re,subprocess
from pathlib import Path
P=Path("release/evidence/worker-a/p1-p1a-p2-execution-package.json")
M=Path("release/evidence/worker-a/p1-p1a-p2-reuse-matrix.jsonl")
T=Path("release/evidence/worker-a/p1-p1a-p2-test-center.json")
H=Path("release/evidence/worker-a/compatibility-history.v1.json")
D=Path("docs/roadmap/progress/2026-08-05-worker-a-p1-p2-new-roadmap-execution.md")
S=Path("tool/worker_a_p1_p2_execution_contract_test.py")
CL={"REUSE_EXISTING_VERIFIED","REUSE_EXISTING_RETEST_REQUIRED","REPAIR_EXISTING","EXTEND_EXISTING","IMPLEMENT_MISSING","BLOCKED_BY_SHARED_CONTRACT","BLOCKED_EXTERNAL","OUT_OF_WORKER_A_LANE"}
PIN={"PROVISIONAL_EXECUTION_REFERENCE","NON_NORMATIVE","PENDING_WORKER_J_ADOPTION"}
ST={"PASS","FAIL","BLOCKED","SKIPPED","UNKNOWN","FLAKY","NOT_IMPLEMENTED"}
MOD={"P1-TRUST-AUTHORITY","P1-ACCESS-CAPABILITY-POLICY","P1-SIGNED-MANIFEST-TRUST","P1-AUDIT-THREAT-MODEL","P1-LOCAL-AUTHENTICATED-IPC","P1A-NATIVE-AUTHORITY-SERVICE","P1A-CROSS-LANGUAGE-TRUST","P1A-PLATFORM-BUILD-STARTUP","P1A-RUNTIME-SECURITY","P1A-SIGNED-EVIDENCE","P2-OWNER-MODE-SOURCE-CONTRACTS","P2-APPLICATION-COMPOSITION","P2-PLATFORM-BEHAVIORAL-CERTIFICATION","P2-CANONICAL-ACCEPTANCE","P2-CLEANUP-PROCESS-TERMINATION","P2-EVIDENCE-CERTIFICATION"}
SEM=re.compile(r"^[A-Z][A-Z0-9]*(?:-[A-Z0-9]+)+$")
SUPERSEDED="release/evidence/worker-a/test-center-v1/evidence-package.json"
STAGE1=("70bfeaaf62acad99bf4aa5195e97e5307c0d805f","04b4a452a31100ca7a82994749b78fcda3f61e25")
STAGE2=("e0f416f36b47cab13d15b8633ec2605a34bb4896","ff78974657c25ddc45f6597120fae4b857fe34e9")
def h(x:Path)->str:return hashlib.sha256(x.read_bytes()).hexdigest()
def ids(p:str,n:int)->set[str]:return {f"{p}-{i:03d}" for i in range(1,n+1)}
def main()->int:
 a=argparse.ArgumentParser();a.add_argument("--project",default=".");a.add_argument("--skip-git",action="store_true");o=a.parse_args();r=Path(o.project).resolve()
 paths=[r/x for x in (P,M,T,H,D,S)];before={str(x.relative_to(r)):h(x) for x in paths};e=[]
 def q(v:bool,m:str)->None:
  if not v:e.append(m)
 p=json.loads((r/P).read_text());raw=(r/P).read_text();q(p.get("schema")=="worker-a-p1-p1a-p2-execution-package/v1","package schema");q(p.get("normative") is False,"package authority")
 history=p.get("compatibility_history",{});q(history.get("status")=="SUPERSEDED_COMPATIBILITY_HISTORY","history status");q(history.get("normative") is False,"history authority");q(history.get("superseded_by")==SUPERSEDED,"history supersededBy");q(history.get("freeze_manifest")==H.as_posix(),"history manifest")
 q("bind in draft PR" not in raw,"candidate placeholder removed")
 binding=p.get("evidence",{}).get("exact_commit_binding",{});q((binding.get("implementation_candidate",{}).get("commit"),binding.get("implementation_candidate",{}).get("tree"))==STAGE1,"Stage 1 binding");q((binding.get("evidence_candidate",{}).get("commit"),binding.get("evidence_candidate",{}).get("tree"))==STAGE2,"Stage 2 binding")
 pin=p.get("pin",{});q(set(pin.get("classification",[]))==PIN,"pin");q(pin.get("human_roadmap_authority")=="docs/roadmap/MASTER.md","human authority")
 q(pin.get("latest_roadmap",{}).get("sha256")=="b9c9cf06e138bcc3231769409c989f2bec1e66b5499e25ab979ddf13c74cd97c","roadmap hash")
 q(pin.get("anarchy_reference",{}).get("commit")=="6b23beb64070932886e75a131580fbc6fda878b6","anarchy");q(pin.get("worker_j",{}).get("commit")=="45c435058b63e598223d7080c7ad8d229c5436c3","Worker J snapshot")
 q(p["artifacts"]["reuse_matrix"]["sha256"]==h(r/M),"matrix hash");q(p["artifacts"]["test_center"]["sha256"]==h(r/T),"test center hash");q(p["artifacts"]["compatibility_history"]["sha256"]==h(r/H),"history hash")
 hist=json.loads((r/H).read_text());q(hist.get("normative") is False,"freeze authority");q(hist.get("status")=="SUPERSEDED_COMPATIBILITY_HISTORY","freeze status");q(hist.get("supersededBy",{}).get("canonicalEvidence")==SUPERSEDED,"freeze supersededBy")
 covered={x.get("path") for x in hist.get("legacyArtifacts",[])};q({P.as_posix(),M.as_posix(),T.as_posix()}<=covered,"freeze coverage");q((hist.get("supersededBy",{}).get("implementationCandidate",{}).get("commit"),hist.get("supersededBy",{}).get("implementationCandidate",{}).get("tree"))==STAGE1,"freeze Stage 1");q((hist.get("supersededBy",{}).get("evidenceCandidate",{}).get("commit"),hist.get("supersededBy",{}).get("evidenceCandidate",{}).get("tree"))==STAGE2,"freeze Stage 2")
 lines=(r/M).read_text().splitlines();head=json.loads(lines[0]);fields=head["fields"];rows=[dict(zip(fields,json.loads(x))) for x in lines[1:]]
 for phase,n in (("P1",12),("P1A",13),("P2",14)):q({x["task_id"] for x in rows if x["task_id"].startswith(phase+"-")}==ids(phase,n),phase+" coverage")
 for x in rows:
  q(x["classification"] in CL,x["task_id"]+" class")
  for k in fields:q(x.get(k) not in (None,"",[]),x["task_id"]+" "+k)
 t=json.loads((r/T).read_text());q(t.get("normative") is False,"TC authority");mf=t["module_fields"];mods=[dict(zip(mf,x)) for x in t["modules"]]
 q({x["module_id"] for x in mods}==MOD,"modules")
 for x in mods:
  for i in x["test_ids"]:q(bool(SEM.fullmatch(i)),"test id "+i)
 cf=t["project_test_profile"]["fields"];checks=[dict(zip(cf,x)) for x in t["project_test_profile"]["checks"]];cids={x["check_id"] for x in checks};q("WORKER-A-EXECUTION-CONTRACT" in cids,"self check")
 for x in checks:q(x["mutation_policy"]=="READ_ONLY" and bool(SEM.fullmatch(x["check_id"])),"check "+x["check_id"])
 for paths0,checks0 in t["affected_test_mapping"]["rows"]:q(bool(paths0) and set(checks0)<=cids,"mapping")
 q(set(t["normalized_result_adapter"]["states"])==ST,"states");q(t["normalized_result_adapter"]["preserve_original_evidence"] is True,"evidence")
 q(p["certification"]["P2_aggregate"]["state"]=="BLOCKED" and p["certification"]["P2_aggregate"]["completion_claim"] is False,"P2 aggregate")
 safe=p["parallel_worker_safety"];q(safe=={"worker_j_files_touched":[],"worker_c_files_touched":[],"competing_authority_or_global_schema_created":False,"p3_work_introduced":False},"safety")
 text=(r/D).read_text()
 for x in PIN|{"BLOCKED_BY_SHARED_CONTRACT","BLOCKED_EXTERNAL","Take the repo. You are Worker A. Continue autonomously."}:q(x in text,"progress "+x)
 if not o.skip_git:
  for cmd in (["git","diff","--check"],["git","status","--porcelain"]):
   z=subprocess.run(cmd,cwd=r,capture_output=True,text=True);q(z.returncode==0 and not z.stdout.strip()," ".join(cmd))
 after={str(x.relative_to(r)):h(x) for x in paths};q(before==after,"mutation")
 out={"schema":"worker-a-p1-p2-execution-contract-result/v1","passed":not e,"failed_count":len(e),"errors":e,"artifact_sha256":after};print(json.dumps(out,indent=2,sort_keys=True));return 0 if not e else 1
if __name__=="__main__":raise SystemExit(main())
