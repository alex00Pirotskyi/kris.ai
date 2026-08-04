#!/usr/bin/env python3
from __future__ import annotations
import argparse,hashlib,json,pathlib,shutil

def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def obj(p):
 v=json.loads(pathlib.Path(p).read_text(encoding='utf-8'))
 if not isinstance(v,dict):raise SystemExit('object required')
 return v
def tree_digest(directory:pathlib.Path)->str:
 h=hashlib.sha256()
 for path in sorted((p for p in directory.rglob('*') if p.is_file()),key=lambda p:p.relative_to(directory).as_posix()):
  rel=path.relative_to(directory).as_posix().encode();content=path.read_bytes();h.update(len(rel).to_bytes(8,'big'));h.update(rel);h.update(len(content).to_bytes(8,'big'));h.update(hashlib.sha256(content).digest())
 return h.hexdigest()
def main():
 a=argparse.ArgumentParser();a.add_argument('--provisional',required=True);a.add_argument('--cleanup',required=True);a.add_argument('--output',required=True);n=a.parse_args()
 pp=pathlib.Path(n.provisional).resolve();cp=pathlib.Path(n.cleanup).resolve();out=pathlib.Path(n.output).resolve();pro=obj(pp);clean=obj(cp)
 if pp.parent!=cp.parent or out.parent!=pp.parent:raise SystemExit('platform receipts must share one receipt directory')
 artifact=out.parent/'artifact'
 if not artifact.is_dir() or artifact.is_symlink():raise SystemExit('separate immutable artifact root missing')
 if pro.get('schemaVersion')!='5.0.0' or pro.get('receiptType')!='p2-task-platform-provisional-v5' or pro.get('completionEligible') is not False or pro.get('postRunCleanupObserved') is not False:raise SystemExit('provisional V5 invalid')
 if clean.get('schemaVersion')!='2.0.0' or clean.get('receiptType')!='p2-validated-post-run-cleanup-v2' or clean.get('status')!='passed' or clean.get('completionEligibleForPlatformFinalization') is not True or clean.get('provisionalReceiptSha256')!=sha(pp) or clean.get('exactBinding')!=pro.get('exactBinding'):raise SystemExit('cleanup V2 binding invalid')
 assertions=clean.get('assertions')
 if not isinstance(assertions,dict) or assertions.get('authorityEvidenceArtifactsCleared') is not True:raise SystemExit('authority evidence cleanup assertion required')
 cleanup_target=artifact/'cleanup'/'validated-cleanup-v2.json';cleanup_target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(cp,cleanup_target)
 provisional_target=artifact/'receipts'/'provisional-v5.json';provisional_target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(pp,provisional_target)
 passed=pro.get('status')=='provisional_passed'
 final={**pro,'schemaVersion':'5.0.0','receiptType':'p2-task-platform-behavioral-v5','status':'passed' if passed else 'blocked','completionEligible':passed,'postRunCleanupObserved':True,'artifactRoot':'artifact','artifactSha256':tree_digest(artifact),'artifactDigestAlgorithm':'canonical-unpacked-v1','provisionalReceipt':{'path':provisional_target.relative_to(artifact).as_posix(),'sha256':sha(provisional_target)},'postRunCleanup':{'path':cleanup_target.relative_to(artifact).as_posix(),'sha256':sha(cleanup_target),'signedCleanupSha256':clean.get('signedCleanupSha256'),'status':'passed','assertions':assertions,'exactBinding':clean.get('exactBinding')}}
 out.write_text(json.dumps(final,indent=2,sort_keys=True)+'\n',encoding='utf-8');print(json.dumps({'receipt':str(out),'status':final['status'],'artifactSha256':final['artifactSha256'],'sha256':sha(out)},sort_keys=True));return 0 if passed else 3
if __name__=='__main__':raise SystemExit(main())
