from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import subprocess
import sys

root = Path('.').resolve()
policy_path = root / 'tool/source_tree_policy.py'
spec = importlib.util.spec_from_file_location('tmp_source_policy', policy_path)
if spec is None or spec.loader is None:
    raise SystemExit('cannot load source-tree policy')
policy = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = policy
spec.loader.exec_module(policy)

raw = subprocess.check_output(
    ['git', '-C', str(root), 'ls-files', '--cached', '--others', '--exclude-standard', '-z']
)
values = sorted(
    {
        item.decode('utf-8', errors='surrogateescape').replace('\\', '/')
        for item in raw.split(b'\0')
        if item
    }
)
excluded = {
    'SOURCE_MANIFEST.sha256',
    '.github/workflows/tmp-chat-takeover-bridge-verify.yml',
    'tool/tmp_chat_takeover_bridge_patch.py',
    'tool/tmp_chat_takeover_contract_fix.py',
    'tool/tmp_source_manifest_refresh.py',
}
paths = [
    relative
    for relative in values
    if relative not in excluded
    and not policy.is_generated_path(relative)
    and (root / relative).is_file()
]


def canonical(data: bytes) -> bytes:
    if b'\0' in data:
        return data
    try:
        data.decode('utf-8')
    except UnicodeDecodeError:
        return data
    return data.replace(b'\r\n', b'\n')


rows = []
for relative in paths:
    digest = hashlib.sha256(canonical((root / relative).read_bytes())).hexdigest()
    rows.append(f'{digest}  {relative}')
(root / 'SOURCE_MANIFEST.sha256').write_text(
    '\n'.join(rows) + '\n', encoding='utf-8', newline='\n'
)
