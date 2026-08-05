#!/usr/bin/env python3
from __future__ import annotations
import base64, hashlib, json, os, subprocess, sys, zlib
from pathlib import Path

BRANCH="agent/d/p3-readiness-fixtures"
S1="e7dee26404a11f076206251f619bfc3f9078753c"
S1_TREE="27a2d09ed4ed1d61775a74bccd6eac5aa4b739c6"
ALLOWED=sorted([
 "SOURCE_MANIFEST.sha256",
 "docs/roadmap/progress/2026-08-05-p3-001-readiness.md",
 "release/evidence/P3-001/READINESS.md",
 "release/evidence/P3-001/claim-boundary.json",
 "release/evidence/P3-001/manifest.json",
 "release/evidence/P3-001/test-center-registration.json",
 "tool/worker_d_p3_readiness.py",
 "tool/worker_d_p3_readiness_test.py",
])

def run(args,cwd,capture=False):
    p=subprocess.run(args,cwd=cwd,check=True,text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None)
    return p.stdout.strip() if capture else ""

def write(path,text):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(text,encoding="utf-8",newline="\n")

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    if len(sys.argv)!=2: raise SystemExit("usage: materialize_worker_d_stage2.py <project>")
    root=Path(sys.argv[1]).resolve()
    run(["git","config","core.autocrlf","false"],root)
    head=run(["git","rev-parse","HEAD"],root,True)
    tree=run(["git","rev-parse","HEAD^{tree}"],root,True)
    branch=run(["git","branch","--show-current"],root,True)
    if (branch,head,tree)!=(BRANCH,S1,S1_TREE): raise SystemExit(f"Stage 1 mismatch: {branch} {head}/{tree}")
    if run(["git","status","--porcelain"],root,True): raise SystemExit("dirty target checkout")

    manifest_path=root/"SOURCE_MANIFEST.sha256"
    s1_bytes=manifest_path.read_bytes()
    s1_sha=hashlib.sha256(s1_bytes).hexdigest()
    s1_blob=run(["git","hash-object","SOURCE_MANIFEST.sha256"],root,True)
    s1_entries=sum(bool(x.strip()) for x in s1_bytes.splitlines())

    packed=(Path(__file__).with_name("worker_d_stage2_payload.b64")).read_text(encoding="ascii").strip()
    payload=json.loads(zlib.decompress(base64.b64decode(packed)))
    for rel,text in payload["staticFiles"].items(): write(root/rel,text)

    evidence=payload["manifestBase"]
    evidence["artifacts"]=[{"path":rel,"sha256":sha(root/rel)} for rel in payload["artifactPaths"]]
    evidence["sourceManifestEvidence"]["stage1"].update(
        {"entryCount":s1_entries,"gitBlobSha1":s1_blob,"sha256":s1_sha})
    write(root/"release/evidence/P3-001/manifest.json",json.dumps(evidence,indent=2)+"\n")

    run([sys.executable,"-m","unittest","-v","tool/worker_d_p3_readiness_test.py"],root)
    run([sys.executable,"tool/worker_d_p3_readiness.py","--check","--project","."],root)
    run([sys.executable,"tool/test_center_contracts.py","check","--project","."],root)
    a=run([sys.executable,"tool/test_center_contracts.py","select-affected","--project",".",
           "release/evidence/P3-001/fixture-specification.json","tool/worker_d_p3_readiness.py"],root,True)
    b=run([sys.executable,"tool/test_center_contracts.py","select-affected","--project",".",
           "tool/worker_d_p3_readiness.py","release/evidence/P3-001/fixture-specification.json"],root,True)
    if a!=b: raise SystemExit("affected-test selection is order dependent")

    run([sys.executable,"tool/p1a_refresh_source_manifest.py","."],root)
    first=manifest_path.read_bytes()
    run([sys.executable,"tool/p1a_refresh_source_manifest.py","."],root)
    second=manifest_path.read_bytes()
    if first!=second: raise SystemExit("source manifest generations differ")
    s2_sha=hashlib.sha256(second).hexdigest()
    s2_entries=sum(bool(x.strip()) for x in second.splitlines())

    run([sys.executable,"tool/source_tree_policy.py","check","--project","."],root)
    run(["git","diff","--check"],root)
    changed=sorted(run(["git","diff","--name-only"],root,True).splitlines())
    if changed!=ALLOWED: raise SystemExit(f"unexpected changed paths: {changed}")

    run(["git","config","user.name","Worker D Evidence Binder"],root)
    run(["git","config","user.email","41898282+github-actions[bot]@users.noreply.github.com"],root)
    run(["git","add","--"]+ALLOWED,root)
    run(["git","diff","--cached","--check"],root)
    run(["git","commit","-m","docs(p3): bind Stage 1 readiness evidence"],root)
    s2=run(["git","rev-parse","HEAD"],root,True)
    s2_tree=run(["git","rev-parse","HEAD^{tree}"],root,True)
    if run(["git","rev-parse","HEAD^"],root,True)!=S1: raise SystemExit("unexpected Stage 2 parent")
    run(["git","push","origin",f"{s2}:refs/heads/{BRANCH}"],root)
    remote=run(["git","ls-remote","origin",f"refs/heads/{BRANCH}"],root,True).split()[0]
    if remote!=s2: raise SystemExit("remote Stage 2 head mismatch")
    if run(["git","status","--porcelain"],root,True): raise SystemExit("dirty checkout after push")

    pairs={
      "stage2_commit":s2,"stage2_tree":s2_tree,
      "stage1_manifest_sha256":s1_sha,"stage1_manifest_entries":str(s1_entries),
      "stage2_manifest_sha256":s2_sha,"stage2_manifest_entries":str(s2_entries)}
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"],"a",encoding="utf-8") as f:
            for k,v in pairs.items(): f.write(f"{k}={v}\n")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"],"a",encoding="utf-8") as f:
            f.write("# Worker D Stage 2 evidence publication\n\n")
            f.write(f"- Stage 1: `{S1}` / `{S1_TREE}`\n")
            f.write(f"- Stage 2: `{s2}` / `{s2_tree}`\n")
            f.write(f"- Stage 1 root manifest: `{s1_sha}` ({s1_entries} entries)\n")
            f.write(f"- Stage 2 root manifest: `{s2_sha}` ({s2_entries} entries)\n")
            f.write("- Canonical manifest generated twice byte-identically\n")
            f.write("- P3-001 remains dependency-blocked and unimplemented\n")
    for k,v in pairs.items(): print(f"{k.upper()}={v}")

if __name__=="__main__": main()
