#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,pathlib,shutil,sys
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from p1a_evidence_contract import PLATFORMS,sha,validate_owner,validate_platform_receipt,validate_review
from p1a_signed_evidence import HEX40,HEX64,sha256_file,validate_protected_evidence_trust

def main():
 a=argparse.ArgumentParser();a.add_argument('--project',default='.');a.add_argument('--reviewed-commit',required=True);a.add_argument('--reviewed-tree',required=True);a.add_argument('--package-sha256',required=True);a.add_argument('--platform-receipt',action='append',default=[]);a.add_argument('--security-review',required=True);a.add_argument('--owner-approval',required=True);a.add_argument('--evidence-trust',required=True);a.add_argument('--openssl',default='openssl');a.add_argument('--github-repo',required=True);a.add_argument('--gh',default='gh');n=a.parse_args()
 root=pathlib.Path(n.project).resolve();trust=pathlib.Path(n.evidence_trust).resolve()
 if not HEX40.fullmatch(n.reviewed_commit) or not HEX40.fullmatch(n.reviewed_tree) or not HEX64.fullmatch(n.package_sha256) or not trust.is_file():raise SystemExit('exact commit/tree/package/trust binding required')
 if len(n.platform_receipt)!=3:raise SystemExit('exact three platform receipts required')
 trust_binding=validate_protected_evidence_trust(trust,github_repo=n.github_repo,gh_executable=n.gh)
 rows={}
 for raw in n.platform_receipt:
  p=pathlib.Path(raw).resolve();d=validate_platform_receipt(p,commit=n.reviewed_commit,tree=n.reviewed_tree,package_sha256=n.package_sha256,trust_path=trust,openssl_executable=n.openssl,require_live_github_success=True,github_repo=n.github_repo,gh_executable=n.gh);platform=d['platform']
  if platform in rows:raise SystemExit('duplicate P1A platform receipt')
  rows[platform]=(p,d)
 if set(rows)!=set(PLATFORMS):raise SystemExit('Windows/macOS/Linux P1A evidence required')
 digests={k:sha(v[0]) for k,v in sorted(rows.items())};trust_sha=sha(trust)
 review=validate_review(n.security_review,commit=n.reviewed_commit,tree=n.reviewed_tree,package=n.package_sha256,platform_digests=digests,trust_sha256=trust_sha,trust_path=trust)
 owner=validate_owner(n.owner_approval,commit=n.reviewed_commit,tree=n.reviewed_tree,package=n.package_sha256,platform_digests=digests,trust_sha256=trust_sha,trust_path=trust)
 evidence=root/'release/evidence/P1A';platform_root=evidence/'platforms'/n.reviewed_commit
 component_graph={};receipt_paths={}
 for platform,(source,data) in rows.items():
  target_dir=platform_root/platform
  if target_dir.exists():shutil.rmtree(target_dir)
  target_dir.mkdir(parents=True,exist_ok=True)
  artifact_rel=pathlib.PurePosixPath(str(data.get('artifactRoot','')))
  if not str(artifact_rel) or artifact_rel.is_absolute() or '..' in artifact_rel.parts:raise SystemExit('unsafe P1A artifact root')
  artifact_source=(source.parent/artifact_rel).resolve()
  if not artifact_source.is_dir() or source.parent.resolve() not in artifact_source.parents:raise SystemExit('P1A artifact root unavailable')
  artifact_target=target_dir/artifact_rel
  shutil.copytree(artifact_source,artifact_target,symlinks=False)
  target=target_dir/'receipt.json';shutil.copyfile(source,target)
  receipt_paths[platform]=target.relative_to(root).as_posix()
  component_graph[platform]={name:data[name]['sha256'] for name in ('runnerAttestation','buildProvenance','installerReceipt','keyProviderReceipt','workerDenialReceipt','serviceBehaviorReceipt','cleanupReceipt','githubApiVerification')}
  component_graph[platform]['liveGithubSuccess']=data['liveGithubSuccess']
 shutil.copyfile(n.security_review,evidence/'INDEPENDENT_SECURITY_REVIEW.json');shutil.copyfile(n.owner_approval,evidence/'OWNER_APPROVAL.json');shutil.copyfile(trust,evidence/'EVIDENCE_TRUST.json')
 task=root/'release/evidence/P1A-001';task.mkdir(parents=True,exist_ok=True)
 test={'schemaVersion':'3.0.0','taskId':'P1A-001','status':'passed','passed':True,'completionEligible':True,'reviewedCommit':n.reviewed_commit,'reviewedTree':n.reviewed_tree,'platformReceiptSha256':digests,'platformComponentGraph':component_graph,'workerDenialTriPlatformPassed':True,'serviceGeneratedBehaviorTriPlatformPassed':True,'signedExactRunProvenancePassed':True,'independentSecurityReview':'approved'}
 (task/'test-results.json').write_text(json.dumps(test,indent=2,sort_keys=True)+'\n')
 manifest={'schemaVersion':'3.0.0','taskId':'P1A-001','status':'passed','completionClaim':True,'reviewedCommit':n.reviewed_commit,'reviewedTree':n.reviewed_tree,'packageSha256':n.package_sha256,'platformReceiptSha256':digests,'platformComponentGraph':component_graph,'evidenceTrustSha256':trust_sha,'evidenceTrustProtectedRepositoryBinding':trust_binding,'independentSecurityReview':'approved','ownerApproval':'approved'}
 (task/'manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
 aggregate={'schemaVersion':'3.0.0','phase':'P1A','status':'passed','completionClaim':True,'p2DependencySatisfied':True,'reviewedCommit':n.reviewed_commit,'reviewedTree':n.reviewed_tree,'packageSha256':n.package_sha256,'activeTasks':[],'completedTasks':['P1A-001'],'platformEvidence':{p:'passed' for p in PLATFORMS},'platformReceiptPath':receipt_paths,'platformReceiptSha256':digests,'platformComponentGraph':component_graph,'evidenceTrustPath':'release/evidence/P1A/EVIDENCE_TRUST.json','evidenceTrustSha256':trust_sha,'evidenceTrustProtectedRepositoryBinding':trust_binding,'independentSecurityReview':'approved','independentSecurityReviewSha256':sha(n.security_review),'ownerApproval':'approved','ownerApprovalSha256':sha(n.owner_approval),'requiredWorkflowJobs':['p1a-behavioral-windows','p1a-behavioral-macos','p1a-behavioral-linux']}
 (evidence/'manifest.json').write_text(json.dumps(aggregate,indent=2,sort_keys=True)+'\n')
 completed=root/'tasks/completed/P1A-001.md';completed.parent.mkdir(parents=True,exist_ok=True);completed.write_text(f'# P1A-001 — Isolated authority service V63\n\nStatus: DONE\n\nReviewed commit: `{n.reviewed_commit}`\nReviewed tree: `{n.reviewed_tree}`\n\nExact signed Windows/macOS/Linux service installation, non-exportable key, internal policy/grant/use/revocation/audit, production restricted-worker denial, restart replay, post-uninstall cleanup, independent security approval, and owner approval passed.\n')
 active=root/'tasks/active/P1A-001.md'
 if active.exists():active.unlink()
 (root/'tasks/active/.gitkeep').parent.mkdir(parents=True,exist_ok=True);(root/'tasks/active/.gitkeep').touch(exist_ok=True)
 print(json.dumps({'status':'passed','reviewedCommit':n.reviewed_commit,'platformReceiptSha256':digests,'evidenceTrustSha256':trust_sha,'evidenceTrustProtectedRepositoryBinding':trust_binding},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
