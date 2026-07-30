#!/usr/bin/env python3
from __future__ import annotations
import argparse,hashlib,json,pathlib

def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()
def main()->int:
    p=argparse.ArgumentParser();p.add_argument('--project',default='.');p.add_argument('--output',required=True);p.add_argument('--service-instance-id',required=True);p.add_argument('--service-build-sha256',required=True);p.add_argument('--runtime-build-sha256',required=True);p.add_argument('--source-commit',required=True);p.add_argument('--source-tree',required=True);p.add_argument('--current-account-root',action='append',default=[]);a=p.parse_args();root=pathlib.Path(a.project).resolve();profiles=json.loads((root/'config/access_profiles.v2.json').read_text());policy=json.loads((root/'config/policy_engine.v2.json').read_text())
    body={'schemaVersion':'2.0.0','policyRevision':str(policy.get('revision','unknown')),'profiles':profiles.get('profiles',profiles),'capabilities':policy.get('capabilities',{}),'activeOverlays':policy.get('activeOverlays',[]),'serviceInstanceId':a.service_instance_id,'serviceBuildSha256':a.service_build_sha256,'runtimeBuildSha256':a.runtime_build_sha256,'sourceCommit':a.source_commit,'sourceTree':a.source_tree,'currentAccountRoots':a.current_account_root,'maxRequestBytes':16777216,'maxDeadlineSeconds':120,'permitTtlSeconds':90,'behaviorEvidenceEnabled':False,'grantKeyId':'p1a-grant-v2','ownerApprovalKeyId':'p1a-owner-approval-v2'}
    body['policySnapshotSha256']=hashlib.sha256(canonical({k:v for k,v in body.items() if k!='policySnapshotSha256'})).hexdigest();path=pathlib.Path(a.output);path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(body,indent=2,sort_keys=True)+'\n');print(path);return 0
if __name__=='__main__':raise SystemExit(main())
