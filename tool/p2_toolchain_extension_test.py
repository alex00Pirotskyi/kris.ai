#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, pathlib, re, shutil, subprocess, sys, tempfile
EXPECTED={'ubuntu':'ubuntu-24.04','windows':'windows-2025','macos':'macos-15'}
SETUP_PYTHON='5fda3b95a4ea91299a34e894583c3862153e4b97'
SETUP_NODE='48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def require(v,m):
    if not v: raise SystemExit(m)
def validate(root:pathlib.Path):
    p0p=root/'config/toolchains.lock.json'; p2p=root/'config/p2_toolchain_extension.v1.json'; workflow=(root/'.github/workflows/p2-owner-mode.yml').read_text()
    before=p0p.read_bytes(); p0=json.loads(before); p2=json.loads(p2p.read_text())
    require(p2.get('authority')=='P2-toolchain-extension-v1','wrong P2 toolchain authority')
    require(p2['baseAuthority']['manifestSha256']==sha(p0p),'P2 base manifest digest mismatch')
    require(p2['baseAuthority']['declaredInputFingerprint']==p0.get('declaredInputFingerprint'),'P2 base fingerprint mismatch')
    require(p2.get('hostedRunnerPins')==EXPECTED,'P2 hosted runner pins mismatch')
    require(p2['githubActions']['actions/setup-python']['commit']==SETUP_PYTHON,'setup-python pin mismatch')
    require(p2['githubActions']['actions/setup-node']['commit']==SETUP_NODE,'setup-node pin mismatch')
    for action,commit in [('actions/setup-python',SETUP_PYTHON),('actions/setup-node',SETUP_NODE)]: require(f'uses: {action}@{commit}' in workflow,f'{action} immutable pin missing')
    require(not re.search(r'(?<!check-)\b(?:ubuntu|windows|macos)-latest\b', workflow),'floating runner remains')
    require('npm ci' in workflow,'npm ci missing')
    require('tool/p2_runner_attestation.py' in workflow,'runner attestation gate missing')
    for name, expected in [('p2.python-version', p2['python']['version']), ('p2.node-version', p2['node']['version']), ('p2.flutter-version', p2['flutter']['version']), ('p2.dart-version', p2['dart']['version'])]:
        require((root/'config'/name).read_text().strip()==expected, f'{name} mismatch')
    require('python-version-file: config/p2.python-version' in workflow, 'governed Python version file missing')
    require('node-version-file: config/p2.node-version' in workflow, 'governed Node version file missing')
    for marker in ("github.event_name == 'workflow_dispatch'", "github.ref == 'refs/heads/main'", 'inputs.source_sha == github.sha', 'inputs.package_sha256 == vars.KRISTIN_P2_V66_PACKAGE_SHA256', 'github.actor == vars.KRISTIN_P2_AUTHORIZED_ACTOR'):
        require(workflow.count(marker)==3, f'P2 controlled workflow boundary missing: {marker}')
    require(workflow.count('environment: p2-controlled')==3, 'P2 protected environment missing')
    require(p0p.read_bytes()==before,'historical P0-004 authority changed')
def synthetic(source:pathlib.Path):
    with tempfile.TemporaryDirectory(prefix='p2-toolchain-extension-') as raw:
        root=pathlib.Path(raw); (root/'config').mkdir(); (root/'.github/workflows').mkdir(parents=True); (root/'automation_host').mkdir()
        p0={'schemaVersion':'1.0.0','milestone':'P0-004','sourceCommit':'0'*40,'declaredInputFingerprint':'1'*64,'python':{'version':'3.13.5'},'flutter':{'version':'3.35.0'},'dart':{'version':'3.9.0'},'runners':EXPECTED,'githubActions':{'actions/setup-python':{'release':'v7.0.0','commit':SETUP_PYTHON}}}
        (root/'config/toolchains.lock.json').write_text(json.dumps(p0,indent=2)+'\n')
        shutil.copy2(source/'automation_host/package-lock.json',root/'automation_host/package-lock.json')
        shutil.copy2(source/'.github/workflows/p2-owner-mode.yml',root/'.github/workflows/p2-owner-mode.yml')
        subprocess.check_call([sys.executable,str(source/'tool/p2_extend_toolchain_lock.py'),'--project',str(root)])
        validate(root)
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--project',default='.'); ns=ap.parse_args(); root=pathlib.Path(ns.project).resolve()
    if (root/'config/toolchains.lock.json').is_file():
        if not (root/'config/p2_toolchain_extension.v1.json').is_file(): subprocess.check_call([sys.executable,str(root/'tool/p2_extend_toolchain_lock.py'),'--project',str(root)])
        validate(root)
    else: synthetic(root)
    print('P2 separate toolchain-extension authority and immutable P0 binding: PASS'); return 0
if __name__=='__main__': raise SystemExit(main())
