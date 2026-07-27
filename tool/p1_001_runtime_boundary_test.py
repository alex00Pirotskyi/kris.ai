#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, re, sys
from pathlib import Path

REQUIRED_PROCESSES={"desktop_host","owner_executor","automation_host","research_worker","sandbox_worker"}

def add(results,name,passed,detail): results.append({"name":name,"passed":bool(passed),"detail":detail})

def main():
 p=argparse.ArgumentParser(); p.add_argument("--project",default="."); p.add_argument("--json-output"); args=p.parse_args()
 root=Path(args.project).resolve(); results=[]
 required=[
  "docs/adr/ADR-0001-runtime-boundaries.md","docs/adr/ADR-0002-owner-mode.md","docs/adr/ADR-0004-automation-host.md",
  "docs/architecture/RUNTIME_BOUNDARY_MATRIX.md","config/runtime_boundaries.v1.json","schemas/runtime_boundary_contract.v1.json",
  "docs/roadmap/DECISIONS.md","tasks/completed/P1-001.md","release/evidence/P1-001/manifest.json",
 ]
 missing=[x for x in required if not (root/x).is_file()]; add(results,"Required P1-001 files",not missing,"all present" if not missing else "missing: "+str(missing))
 try: contract=json.loads((root/"config/runtime_boundaries.v1.json").read_text(encoding="utf-8"))
 except Exception as e: contract={}; add(results,"Contract parses",False,str(e))
 else: add(results,"Contract parses",True,"schemaVersion="+str(contract.get("schemaVersion")))
 add(results,"Mandatory synchronized platforms",contract.get("mandatoryPlatforms")==["windows","macos","linux"],str(contract.get("mandatoryPlatforms")))
 processes=contract.get("processes") if isinstance(contract.get("processes"),dict) else {}
 add(results,"Five process boundaries",set(processes)==REQUIRED_PROCESSES,"processes="+str(sorted(processes)))
 issuers=[k for k,v in processes.items() if isinstance(v,dict) and v.get("mayIssueCapabilityGrants") is True]
 add(results,"Single grant issuer",issuers==["desktop_host"],"issuers="+str(issuers))
 worker_db=[k for k,v in processes.items() if k!="desktop_host" and isinstance(v,dict) and v.get("mayReadCoreDatabase") is not False]
 add(results,"Workers cannot open core database",not worker_db,"violations="+str(worker_db))
 owner=processes.get("owner_executor",{}); add(results,"Owner Mode is explicit non-sandbox authority",owner.get("sandboxed") is False and owner.get("requiresGrantForEffects") is True,str(owner))
 research=processes.get("research_worker",{}); add(results,"Research content remains untrusted",research.get("contentTrust")=="untrusted",str(research.get("contentTrust")))
 sandbox=processes.get("sandbox_worker",{}); add(results,"Sandbox has no credentials",sandbox.get("credentialAccess")=="none" and sandbox.get("sandboxed") is True,str(sandbox))
 auth=contract.get("authority",{}); add(results,"Model and workers cannot grant authority",auth.get("modelMayGrantAuthority") is False and auth.get("workerMayGrantAuthority") is False,str(auth))
 ipc=contract.get("ipc",{}); ipc_ok=all(ipc.get(k) is True for k in ("versionedEnvelopeRequired","mutualAuthenticationRequired","peerIdentityRequired","requestIdRequired","runTaskGrantBindingRequired","payloadLimitsRequired"))
 add(results,"Authenticated typed IPC contract",ipc_ok,str(ipc))
 storage=contract.get("storage",{}); storage_ok=storage.get("workerDirectCoreDatabaseAccess") is False and storage.get("credentials")=="os_native_or_external_protected_store" and storage.get("immutableArtifacts")=="content_addressed_object_store"
 add(results,"Storage ownership contract",storage_ok,str(storage))
 adr_checks={
  "docs/adr/ADR-0001-runtime-boundaries.md":["Status:** ACCEPTED","workers never open it directly","Windows uses named pipes"],
  "docs/adr/ADR-0002-owner-mode.md":["Status:** ACCEPTED","Owner Mode is **not a sandbox**","cannot grant or widen authority"],
  "docs/adr/ADR-0004-automation-host.md":["Status:** ACCEPTED","technology-neutral **automation host boundary**","not policy authority"],
 }
 missing_anchors=[]
 for rel,anchors in adr_checks.items():
  text=(root/rel).read_text(encoding="utf-8") if (root/rel).is_file() else ""
  missing_anchors += [f"{rel}:{a}" for a in anchors if a not in text]
 add(results,"Accepted ADR anchors",not missing_anchors,"all present" if not missing_anchors else str(missing_anchors))
 decisions=(root/"docs/roadmap/DECISIONS.md").read_text(encoding="utf-8") if (root/"docs/roadmap/DECISIONS.md").is_file() else ""
 ledger_ok=all(re.search(rf"(?m)^[|] `{adr}` [|].*[|] ACCEPTED [|]",decisions) for adr in ("ADR-0001","ADR-0002","ADR-0004"))
 add(results,"Decision ledger accepted states",ledger_ok,"ADR-0001/0002/0004 accepted" if ledger_ok else "ledger drift")
 try: roadmap=json.loads((root/"docs/roadmap/roadmap.yaml").read_text(encoding="utf-8")); tasks={x["id"]:x for x in roadmap["tasks"]}
 except Exception as e: tasks={}; add(results,"Roadmap state",False,str(e))
 else:
  ready=sorted(tid for tid,t in tasks.items() if t.get("status")=="READY")
  p1_001_status=tasks.get("P1-001",{}).get("status")
  p1_002_status=tasks.get("P1-002",{}).get("status")
  p1_003_status=tasks.get("P1-003",{}).get("status")
  p1_005_status=tasks.get("P1-005",{}).get("status")
  good=(
   p1_001_status=="DONE"
   and p1_002_status in {"READY","DONE"}
   and p1_005_status in {"READY","DONE"}
   and (p1_002_status!="DONE" or p1_003_status in {"READY","DONE"})
  )
  add(results,"Roadmap state",good,f"P1-001={p1_001_status} P1-002={p1_002_status} P1-003={p1_003_status} P1-005={p1_005_status} ready={ready}")
 ci=(root/".github/workflows/ci.yml").read_text(encoding="utf-8")
 add(results,"CI integration","P1-001 runtime boundary contract" in ci,"workflow step present")
 verify=(root/"tool/verify.sh").read_text(encoding="utf-8")
 add(results,"Verification integration","p1_001_runtime_boundary_test.py" in verify,"verify step present")
 validator=(root/"tool/validate_release.py").read_text(encoding="utf-8")
 add(results,"Release validation integration","tool/p1_001_runtime_boundary_test.py" in validator,"required files include P1 gate")
 passed=all(x["passed"] for x in results); report={"schemaVersion":"1.0.0","taskId":"P1-001","caseCount":len(results),"passedCount":sum(1 for x in results if x["passed"]),"failedCount":sum(1 for x in results if not x["passed"]),"passed":passed,"results":results}
 text=json.dumps(report,indent=2,sort_keys=True)+"\n"
 if args.json_output:
  out=root/args.json_output; out.parent.mkdir(parents=True,exist_ok=True); out.write_text(text,encoding="utf-8",newline="\n")
 print(text,end="")
 return 0 if passed else 1
if __name__=="__main__": raise SystemExit(main())
