#!/usr/bin/env python3
from __future__ import annotations
import argparse,base64,hashlib,json,pathlib,subprocess,sys,tempfile
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from p1a_signed_evidence import canonical_bytes
p=argparse.ArgumentParser();p.add_argument('--input',required=True);p.add_argument('--output',required=True);p.add_argument('--purpose',required=True);p.add_argument('--signer',required=True);p.add_argument('--key-id',required=True);a=p.parse_args()
body=json.loads(pathlib.Path(a.input).read_text());body.pop('signature',None)
with tempfile.TemporaryDirectory(prefix='p1a-sign-') as td:
 data=pathlib.Path(td)/'body.bin';data.write_bytes(canonical_bytes(body))
 result=subprocess.run([a.signer,'--purpose',a.purpose,'--input',str(data)],capture_output=True)
 if result.returncode:raise SystemExit('external evidence signer failed')
 signature=result.stdout.strip()
 try:base64.b64decode(signature,validate=True)
 except Exception as e:raise SystemExit('external signer returned invalid base64') from e
message=canonical_bytes(body);body['signature']={'algorithm':'ed25519','keyId':a.key_id,'purpose':a.purpose,'signedSha256':hashlib.sha256(message).hexdigest(),'signatureBase64':signature.decode()}
pathlib.Path(a.output).write_text(json.dumps(body,indent=2,sort_keys=True)+'\n');print(a.output)
