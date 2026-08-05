#!/usr/bin/env python3
"""Create P2's independent toolchain-extension authority.

Historical `config/toolchains.lock.json` is read and fingerprinted but never
modified. The generated P2 manifest is versioned separately and can therefore
have its own exact tri-platform evidence without rewriting P0-004 history.
"""
from __future__ import annotations
import argparse, copy, hashlib, json, pathlib, re

NODE_VERSION = "24.18.0"
SETUP_PYTHON = {"release": "v7.0.0", "commit": "5fda3b95a4ea91299a34e894583c3862153e4b97"}
SETUP_NODE = {"release": "v6.4.0", "commit": "48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e"}
HOSTED = {"ubuntu": "ubuntu-24.04", "windows": "windows-2025", "macos": "macos-15"}
INTERACTIVE = {
    "ubuntu": ["self-hosted", "kristin-p2", "linux", "interactive-desktop", "ubuntu-24.04"],
    "windows": ["self-hosted", "kristin-p2", "windows", "interactive-desktop", "windows-2025"],
    "macos": ["self-hosted", "kristin-p2", "macos", "interactive-desktop", "macos-15"],
}

def canonical(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode()

def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024), b''): h.update(b)
    return h.hexdigest()

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--project',default='.'); ns=ap.parse_args()
    root=pathlib.Path(ns.project).resolve()
    p0_path=root/'config/toolchains.lock.json'
    out=root/'config/p2_toolchain_extension.v1.json'
    package_lock=root/'automation_host/package-lock.json'
    if not p0_path.is_file() or not package_lock.is_file():
        raise SystemExit('P0 toolchain authority and automation-host package lock are required')
    before=p0_path.read_bytes(); p0=json.loads(before)
    if p0.get('schemaVersion')!='1.0.0' or p0.get('milestone')!='P0-004':
        raise SystemExit('unexpected P0-004 toolchain authority')
    source=str(p0.get('sourceCommit',''))
    fingerprint=str(p0.get('declaredInputFingerprint',''))
    if re.fullmatch(r'[0-9a-f]{40}',source) is None or re.fullmatch(r'[0-9a-f]{64}',fingerprint) is None:
        raise SystemExit('P0-004 exact source/fingerprint missing')
    if p0.get('runners') != HOSTED:
        raise SystemExit('P0-004 runner pins differ from P2 base authority')
    base_action=p0.get('githubActions',{}).get('actions/setup-python',{})
    if base_action.get('commit') != SETUP_PYTHON['commit']:
        raise SystemExit('P0-004 setup-python pin differs from reviewed P2 extension')
    manifest={
      'schemaVersion':'1.0.0','authority':'P2-toolchain-extension-v1',
      'baseAuthority':{'path':'config/toolchains.lock.json','manifestSha256':hashlib.sha256(before).hexdigest(),'declaredInputFingerprint':fingerprint,'sourceCommit':source},
      'python':{'versionSource':'P0-004','version':str(p0.get('python',{}).get('version',''))},
      'flutter':copy.deepcopy(p0.get('flutter')),
      'dart':copy.deepcopy(p0.get('dart')),
      'node':{'version':NODE_VERSION},
      'githubActions':{'actions/setup-python':SETUP_PYTHON,'actions/setup-node':SETUP_NODE},
      'hostedRunnerPins':HOSTED,
      'interactiveRunnerLabels':INTERACTIVE,
      'automationHostPackageLock':{'path':'automation_host/package-lock.json','sha256':sha(package_lock)},
    }
    payload=copy.deepcopy(manifest)
    manifest['declaredInputFingerprint']=hashlib.sha256(canonical(payload)).hexdigest()
    for label, value in {
        'p2.python-version': manifest['python']['version'],
        'p2.node-version': manifest['node']['version'],
        'p2.flutter-version': str(manifest['flutter']['version']),
        'p2.dart-version': str(manifest['dart']['version']),
    }.items():
        if not value or not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?', value):
            raise SystemExit(f'exact governed version missing for {label}')
        (root/'config'/label).write_text(value+'\n', encoding='utf-8')
    out.write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    if p0_path.read_bytes()!=before:
        raise SystemExit('P0-004 toolchain authority changed while creating P2 extension')
    print(json.dumps({'path':str(out),'fingerprint':manifest['declaredInputFingerprint'],'p0Unchanged':True},sort_keys=True))
    return 0
if __name__=='__main__': raise SystemExit(main())
