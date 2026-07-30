#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,pathlib,sys
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from p1a_evidence_contract import PLATFORMS,sha,validate_owner,validate_platform_receipt,validate_review

def main()->int:
    p=argparse.ArgumentParser();p.add_argument('--project',default='.');p.add_argument('--source-only',action='store_true');a=p.parse_args();root=pathlib.Path(a.project).resolve();manifest=json.loads((root/'release/evidence/P1A/manifest.json').read_text())
    if a.source_only:
        passed=manifest.get('status')=='BLOCKED' and manifest.get('completionClaim') is False and manifest.get('p2DependencySatisfied') is False and not manifest.get('completedTasks') and (root/'tasks/active/P1A-001.md').is_file() and (root/'tasks/active/.gitkeep').is_file() and not (root/'tasks/completed/P1A-001.md').exists();print(json.dumps({'phase':'P1A','status':'source_only','passed':passed,'completionClaim':False},sort_keys=True));return 0 if passed else 1
    commit=str(manifest.get('reviewedCommit',''));tree=str(manifest.get('reviewedTree',''));package=str(manifest.get('packageSha256',''));trust=root/'release/evidence/P1A/EVIDENCE_TRUST.json';trust_sha=sha(trust)
    if manifest.get('schemaVersion')!='3.0.0' or manifest.get('status')!='passed' or manifest.get('completionClaim') is not True or manifest.get('p2DependencySatisfied') is not True:raise SystemExit('P1A V63 aggregate closure invalid')
    rows={};paths=manifest.get('platformReceiptPath')
    if not isinstance(paths,dict) or set(paths)!=set(PLATFORMS):raise SystemExit('P1A aggregate platform paths invalid')
    for platform in PLATFORMS:
        rel=pathlib.PurePosixPath(str(paths[platform]))
        if rel.is_absolute() or '..' in rel.parts:raise SystemExit('P1A unsafe platform receipt path')
        path=(root/rel).resolve()
        if root not in path.parents:raise SystemExit('P1A platform receipt escapes project')
        rows[platform]=(path,validate_platform_receipt(path,commit=commit,tree=tree,package_sha256=package,trust_path=trust,require_live_github_success=False))
    digests={platform:sha(row[0]) for platform,row in sorted(rows.items())}
    if manifest.get('platformReceiptSha256')!=digests or manifest.get('platformEvidence')!={p:'passed' for p in PLATFORMS}:raise SystemExit('P1A aggregate platform binding invalid')
    graph=manifest.get('platformComponentGraph')
    if not isinstance(graph,dict) or set(graph)!=set(PLATFORMS):raise SystemExit('P1A aggregate component graph invalid')
    for platform,(_,body) in rows.items():
        expected={name:body[name]['sha256'] for name in ('runnerAttestation','buildProvenance','installerReceipt','keyProviderReceipt','workerDenialReceipt','serviceBehaviorReceipt','cleanupReceipt','githubApiVerification')}
        observed=graph.get(platform)
        if not isinstance(observed,dict) or any(observed.get(k)!=v for k,v in expected.items()) or not isinstance(observed.get('liveGithubSuccess'),dict):raise SystemExit('P1A component graph mismatch')
    validate_review(root/'release/evidence/P1A/INDEPENDENT_SECURITY_REVIEW.json',commit=commit,tree=tree,package=package,platform_digests=digests,trust_sha256=trust_sha,trust_path=trust);validate_owner(root/'release/evidence/P1A/OWNER_APPROVAL.json',commit=commit,tree=tree,package=package,platform_digests=digests,trust_sha256=trust_sha,trust_path=trust)
    task=json.loads((root/'release/evidence/P1A-001/manifest.json').read_text());tests=json.loads((root/'release/evidence/P1A-001/test-results.json').read_text())
    if task.get('status')!='passed' or task.get('completionClaim') is not True or tests.get('status')!='passed' or tests.get('completionEligible') is not True:raise SystemExit('P1A task evidence invalid')
    if not (root/'tasks/completed/P1A-001.md').is_file() or (root/'tasks/active/P1A-001.md').exists() or not (root/'tasks/active/.gitkeep').is_file():raise SystemExit('P1A task lifecycle invalid')
    print(json.dumps({'phase':'P1A','status':'passed','passed':True,'completionClaim':True,'reviewedCommit':commit},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
