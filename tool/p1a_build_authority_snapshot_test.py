#!/usr/bin/env python3
from __future__ import annotations
import json,pathlib,subprocess,tempfile
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='p1a-snapshot-test-') as td:
 p=pathlib.Path(td);(p/'config').mkdir();(p/'.git').mkdir()
 (p/'config/access_profiles.v2.json').write_text(json.dumps({'profiles':{'owner':{'capabilities':['fs']},'owner_unattended':{'capabilities':['fs']},'isolated_untrusted':{'capabilities':[]}}}))
 (p/'config/policy_engine.v2.json').write_text(json.dumps({'revision':'r1','capabilities':{'fs':{'domain':'filesystem','actions':['read']}},'activeOverlays':[]}))
 out=p/'snapshot.json';cmd=['python',str(root/'tool/p1a_build_authority_snapshot.py'),'--project',str(p),'--output',str(out),'--service-instance-id','p1a-test','--service-build-sha256','a'*64,'--runtime-build-sha256','b'*64,'--source-commit','c'*40,'--source-tree','d'*40,'--current-account-root','/tmp']
 subprocess.check_call(cmd);d=json.loads(out.read_text());assert d['schemaVersion']=='2.0.0' and d['profiles']['owner'] and len(d['policySnapshotSha256'])==64
 altered=json.loads(out.read_text());altered['capabilities']['fs']['actions'].append('write');assert altered['policySnapshotSha256']==d['policySnapshotSha256']
print('P1A deterministic authority snapshot test: PASS')
