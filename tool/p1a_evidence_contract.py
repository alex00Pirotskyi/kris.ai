#!/usr/bin/env python3
from __future__ import annotations
import hashlib,pathlib,sys
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from p1a_platform_evidence import PLATFORMS,validate_platform_receipt
from p1a_signed_evidence import HEX40,HEX64,load_object,sha256_file,verify_ed25519_document

def sha(path):return sha256_file(pathlib.Path(path))
def canonical_directory_digest(root:pathlib.Path)->str:
    h=hashlib.sha256()
    for path in sorted((p for p in root.rglob('*') if p.is_file()),key=lambda p:p.relative_to(root).as_posix()):
        rel=path.relative_to(root).as_posix().encode();data=path.read_bytes();h.update(len(rel).to_bytes(8,'big'));h.update(rel);h.update(len(data).to_bytes(8,'big'));h.update(hashlib.sha256(data).digest())
    return h.hexdigest()
def _bound(data:dict,*,commit:str,tree:str,package:str,platform_digests:dict,trust_sha256:str)->None:
    if data.get('reviewedCommit')!=commit or data.get('reviewedTree')!=tree or data.get('packageSha256')!=package or data.get('platformReceiptSha256')!=platform_digests or data.get('evidenceTrustSha256')!=trust_sha256:raise SystemExit('P1A exact evidence graph binding mismatch')
def validate_review(path,*,commit,tree,package,platform_digests,trust_sha256,trust_path):
    data=load_object(pathlib.Path(path));trust=load_object(pathlib.Path(trust_path))
    if data.get('schemaVersion')!='3.0.0' or data.get('reviewType')!='p1a-independent-security-review-v3' or data.get('platform')!='aggregate' or data.get('independent') is not True or data.get('decision')!='approve' or data.get('syntheticContractFixture') is True:raise SystemExit('independent P1A V63 approval required')
    _bound(data,commit=commit,tree=tree,package=package,platform_digests=platform_digests,trust_sha256=trust_sha256)
    verify_ed25519_document(data,trust,purpose='p1a-independent-security-review')
    if data.get('criticalHighFindingsRemaining')!=[] or not str(data.get('reviewer','')).strip() or data.get('conditions')!=data.get('satisfiedConditions'):raise SystemExit('P1A review findings/conditions invalid')
    artifact=pathlib.Path(str(data.get('reviewArtifactPath',''))).resolve()
    if not artifact.is_file() or sha(artifact)!=data.get('reviewArtifactSha256'):raise SystemExit('P1A review artifact invalid')
    return data
def validate_owner(path,*,commit,tree,package,platform_digests,trust_sha256,trust_path):
    data=load_object(pathlib.Path(path));trust=load_object(pathlib.Path(trust_path))
    if data.get('schemaVersion')!='3.0.0' or data.get('approvalType')!='p1a-owner-approval-v3' or data.get('platform')!='aggregate' or data.get('approved') is not True or data.get('syntheticContractFixture') is True:raise SystemExit('P1A V63 owner approval required')
    _bound(data,commit=commit,tree=tree,package=package,platform_digests=platform_digests,trust_sha256=trust_sha256)
    verify_ed25519_document(data,trust,purpose='p1a-owner-approval')
    for key in ('acknowledgesAuthorityServiceTCB','acknowledgesSeparateOsIdentity','acknowledgesPlatformInstallation','acknowledgesP2DependencyImpact','acknowledgesNonExportablePlatformKeys','acknowledgesRestrictedWorkerPrincipal'):
        if data.get(key) is not True:raise SystemExit(f'P1A owner acknowledgement missing: {key}')
    if not str(data.get('owner','')).strip():raise SystemExit('P1A owner identity missing')
    return data
