#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, pathlib, re

def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
    return h.hexdigest()

def version(value,label):
    value=str(value or '').lstrip('v')
    if re.fullmatch(r'\d+(?:\.\d+){1,3}(?:[-+][0-9A-Za-z.-]+)?',value) is None:
        raise SystemExit(f'exact {label} version missing')
    return value

def load(root):
    p0p=root/'config/toolchains.lock.json'; p2p=root/'config/p2_toolchain_extension.v1.json'
    if not p0p.is_file() or not p2p.is_file(): raise SystemExit('P0 and P2 toolchain authorities required')
    p0=json.loads(p0p.read_text()); p2=json.loads(p2p.read_text())
    base=p2.get('baseAuthority',{})
    if base.get('manifestSha256')!=sha(p0p) or base.get('declaredInputFingerprint')!=p0.get('declaredInputFingerprint') or base.get('sourceCommit')!=p0.get('sourceCommit'):
        raise SystemExit('P2 toolchain extension base binding mismatch')
    package=root/p2['automationHostPackageLock']['path']
    if p2['automationHostPackageLock']['sha256']!=sha(package): raise SystemExit('automation-host package lock drift')
    return {'python':version(p0.get('python',{}).get('version'),'python'),'flutter':version(p0.get('flutter',{}).get('version'),'flutter'),'dart':version(p0.get('dart',{}).get('version'),'dart'),'node':version(p2.get('node',{}).get('version'),'node'),'p2_fingerprint':p2['declaredInputFingerprint']}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--project',default='.'); ap.add_argument('--github-output'); ns=ap.parse_args()
    values=load(pathlib.Path(ns.project).resolve())
    text=''.join(f'{k}={v}\n' for k,v in values.items())
    if ns.github_output: pathlib.Path(ns.github_output).open('a',encoding='utf-8').write(text)
    else: print(json.dumps(values,sort_keys=True))
    return 0
if __name__=='__main__': raise SystemExit(main())
