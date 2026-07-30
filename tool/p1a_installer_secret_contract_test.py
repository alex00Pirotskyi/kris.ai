#!/usr/bin/env python3
from __future__ import annotations
import pathlib,re
root=pathlib.Path(__file__).resolve().parents[1]
files=[p for base in ('authority_service/install','authority_service/native','authority_service/connector','authority_service/worker_launcher') for p in (root/base).rglob('*') if p.is_file()]
text='\n'.join(p.read_text(errors='ignore') for p in files)
for forbidden in ('PEM_read'+'_PrivateKey','--key authority-key.pem','privateKeyBase64','BEGIN PRIVATE'+' KEY'):
 if forbidden in text:raise SystemExit(f'exportable/private key material forbidden: {forbidden}')
for marker in ('LoadCredential','MS_PLATFORM_CRYPTO_PROVIDER','kSecAttrTokenIDSecureEnclave','--permit-key-uri','NCRYPT_EXPORT_POLICY_PROPERTY'):
 if marker not in text:raise SystemExit(f'non-exportable/provider marker missing: {marker}')
for marker in ('systemctl enable --now','sc.exe create','SMAppService'):
 if marker not in text:raise SystemExit(f'production installer marker missing: {marker}')
for pattern in (r'echo\s+[^\n]*(secret|token|private.?key)',r'Write-Host\s+[^\n]*(secret|token|private.?key)'):
 if re.search(pattern,text,re.I):raise SystemExit('installer may log credential material')
print('P1A tri-platform installer/non-exportable-secret contract: PASS')
