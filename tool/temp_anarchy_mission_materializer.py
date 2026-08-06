#!/usr/bin/env python3
"""Temporary fail-closed materializer for the reviewed mission-system package."""
from __future__ import annotations
import argparse, base64, hashlib, io, json, tarfile
from pathlib import Path, PurePosixPath

MANIFEST = Path('docs/roadmap/anarchy/materializer/manifest.json')
CHUNKS = Path('docs/roadmap/anarchy/materializer/chunks')


def safe_members(tf: tarfile.TarFile):
    for member in tf.getmembers():
        name = member.name.removeprefix('./')
        path = PurePosixPath(name)
        if not name or path.is_absolute() or '..' in path.parts:
            raise RuntimeError(f'unsafe archive path: {member.name!r}')
        if member.issym() or member.islnk() or member.isdev():
            raise RuntimeError(f'unsupported archive member: {member.name!r}')
        yield member


def main() -> int:
    parser=argparse.ArgumentParser()
    parser.add_argument('--project', default='.')
    args=parser.parse_args()
    root=Path(args.project).resolve()
    manifest=json.loads((root/MANIFEST).read_text(encoding='utf-8'))
    encoded=''.join((root/CHUNKS/name).read_text(encoding='ascii').strip() for name in manifest['parts'])
    if len(encoded) != manifest['base64Length']:
        raise RuntimeError('base64 length mismatch')
    archive=base64.b64decode(encoded, validate=True)
    if len(archive) != manifest['sizeBytes']:
        raise RuntimeError('archive size mismatch')
    digest=hashlib.sha256(archive).hexdigest()
    if digest != manifest['sha256']:
        raise RuntimeError(f'archive digest mismatch: {digest}')
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as tf:
        members=list(safe_members(tf))
        tf.extractall(root, members=members, filter='data')
    print(json.dumps({'materialized':len(members),'archiveSha256':digest},sort_keys=True))
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
