#!/usr/bin/env python3
from __future__ import annotations
from pathlib import Path
from source_tree_policy import is_generated_path
import hashlib,json,re
ROOT=Path(__file__).resolve().parents[1]
SKIP={'archive','.git','.dart_tool','build','dist','node_modules','__pycache__'}
EXT={'.dart','.yaml','.yml','.json','.md','.py','.sh','.ps1','.toml','.txt','.xml','.html','.js','.ts'}
patterns=[
 ('private_key',re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----')),
 ('openai_key',re.compile(r'\bsk-[A-Za-z0-9_-]{20,}\b')),
 ('github_token',re.compile(r'\bgh[pousr]_[A-Za-z0-9]{20,}\b')),
 ('telegram_token',re.compile(r'\b\d{7,12}:[A-Za-z0-9_-]{30,}\b')),
 ('aws_access_key',re.compile(r'\bAKIA[0-9A-Z]{16}\b')),
 ('generic_assignment',re.compile(r'(?i)\b(?:api[_-]?key|secret|password|access[_-]?token)\s*[:=]\s*["\'][^"\'\n]{16,}["\']')),
]
findings=[]
for p in sorted(ROOT.rglob('*')):
    if not p.is_file() or p.suffix.lower() not in EXT or is_generated_path(p.relative_to(ROOT)) or any(x in SKIP for x in p.relative_to(ROOT).parts):continue
    text=p.read_text(errors='replace')
    for kind,pat in patterns:
        for m in pat.finditer(text):
            value=m.group(0)
            # Documentation examples and explicit redacted placeholders are not credentials.
            lower=value.lower()
            if any(x in lower for x in ('<redacted>','example','placeholder','your_','${','environment:')):continue
            findings.append({'file':str(p.relative_to(ROOT)),'line':text.count('\n',0,m.start())+1,'kind':kind,'fingerprint':hashlib.sha256(value.encode()).hexdigest()[:16]})
report={'passed':not findings,'finding_count':len(findings),'findings':findings}
(ROOT/'release'/'SECRET_SCAN.json').write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
raise SystemExit(0 if not findings else 1)
