#!/usr/bin/env python3
"""Verify a separately signed controlled-runner provisioning packet V3."""
from __future__ import annotations
import argparse, datetime as dt, hashlib, json, pathlib, re, sys
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from ed25519_ref import verify
HEX64=re.compile(r'^[0-9a-f]{64}$'); HEX128=re.compile(r'^[0-9a-f]{128}$')
LABELS={'linux':['self-hosted','kristin-p2','linux','interactive-desktop','ubuntu-24.04'],'macos':['self-hosted','kristin-p2','macos','interactive-desktop','macos-15'],'windows':['self-hosted','kristin-p2','windows','interactive-desktop','windows-2025']}
def canonical(v): return (json.dumps(v,sort_keys=True,separators=(',',':'),ensure_ascii=False)+'\n').encode()
def sha(p): return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def obj(p):
 v=json.loads(pathlib.Path(p).read_text(encoding='utf-8'))
 if not isinstance(v,dict): raise SystemExit(f'{p}: object required')
 return v
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--project',default='.');ap.add_argument('--packet',required=True);ap.add_argument('--trust-policy',required=True);ap.add_argument('--output',required=True);n=ap.parse_args()
 root=pathlib.Path(n.project).resolve(); packet=pathlib.Path(n.packet).resolve(); trustp=pathlib.Path(n.trust_policy).resolve(); out=pathlib.Path(n.output).resolve()
 for p in (packet,trustp):
  if not p.is_file(): raise SystemExit(f'missing external runner authority artifact: {p}')
  try:p.relative_to(root);raise SystemExit('runner authority artifacts must remain external to checkout')
  except ValueError:pass
 trust=obj(trustp); roots=set(map(str,trust.get('provisioningTrustRoots',[])))
 if trust.get('schemaVersion')!='1.0.0' or not roots or any(not HEX64.fullmatch(x) for x in roots): raise SystemExit('runner provisioning trust invalid')
 signed=obj(packet);body=dict(signed);sig=str(body.pop('signatureHex','')).lower();public=str(body.get('signerPublicKeyHex','')).lower()
 if public not in roots or not HEX128.fullmatch(sig) or not verify(bytes.fromhex(public),canonical(body),bytes.fromhex(sig)): raise SystemExit('runner provisioning signature invalid')
 if body.get('schemaVersion')!='3.0.0' or body.get('packetType')!='p2-controlled-runner-provisioning-v3': raise SystemExit('runner provisioning identity invalid')
 now=dt.datetime.now(dt.timezone.utc);issued=dt.datetime.fromisoformat(str(body.get('issuedAt','')).replace('Z','+00:00'));expires=dt.datetime.fromisoformat(str(body.get('expiresAt','')).replace('Z','+00:00'))
 if not issued<=now<expires or (expires-issued)>dt.timedelta(days=7): raise SystemExit('runner provisioning validity invalid')
 att_roots=sorted(set(map(str,body.get('attestationTrustRoots',[]))));cleanup_roots=sorted(set(map(str,body.get('cleanupTrustRoots',[]))))
 if not att_roots or not cleanup_roots or any(not HEX64.fullmatch(x) for x in att_roots+cleanup_roots): raise SystemExit('runner attestation/cleanup trust roots invalid')
 runners=body.get('runners')
 if not isinstance(runners,dict) or set(runners)!=set(LABELS): raise SystemExit('exact tri-platform runner set required')
 seen_ids=set();seen_names=set();normalized={}
 for platform,labels in LABELS.items():
  row=runners[platform]
  if not isinstance(row,dict): raise SystemExit(f'{platform}: runner row invalid')
  rid=row.get('runnerId');gid=row.get('runnerGroupId');name=str(row.get('runnerName',''))
  if not isinstance(rid,int) or rid<=0 or not isinstance(gid,int) or gid<=0 or rid in seen_ids or not name or name in seen_names: raise SystemExit(f'{platform}: runner identity invalid')
  seen_ids.add(rid);seen_names.add(name)
  if row.get('runnerGroup')!='kristin-p2-controlled' or row.get('labels')!=labels or row.get('ephemeralSessionRequired') is not True or row.get('noConcurrentUntrustedWorkload') is not True: raise SystemExit(f'{platform}: governed runner contract invalid')
  for key in ('hostImageSha256','configurationSha256','attestationProviderSha256','postRunCleanupProviderSha256'):
   if not HEX64.fullmatch(str(row.get(key,''))): raise SystemExit(f'{platform}: {key} required')
  for key in ('configurationReceiptPath','attestationProviderPath','postRunCleanupProviderPath'):
   p=pathlib.Path(str(row.get(key,'')))
   if not p.is_absolute(): raise SystemExit(f'{platform}: {key} must be external absolute path')
  if set(map(str,row.get('requiredPermissions',[])))!={'clipboard','screenCapture','activeWindow','accessibility'}: raise SystemExit(f'{platform}: permissions invalid')
  normalized[platform]=row
 review=str(body.get('independentReviewSha256',''))
 if not HEX64.fullmatch(review): raise SystemExit('independent runner provisioning review required')
 policy={'schemaVersion':'5.0.0','policyType':'p2-controlled-runner-policy-v5','provisioningPacketId':str(body.get('packetId','')),'provisioningPacketSha256':sha(packet),'provisioningSignerPublicKeyHex':public,'independentReviewSha256':review,'sourceCommitBinding':'exact-signed-attestation-per-workflow-run-attempt-job','postRunCleanupBinding':'exact-signed-cleanup-after-current-job','requiredRunnerGroup':'kristin-p2-controlled','requiredPermissions':['clipboard','screenCapture','activeWindow','accessibility'],'requireNoConcurrentUntrustedWorkload':True,'requireEphemeralSession':True,'maximumAttestationAgeSeconds':900,'maximumCleanupAgeSeconds':1800,'attestationTrustRoots':att_roots,'cleanupTrustRoots':cleanup_roots,'runners':normalized}
 try:out.relative_to(root);raise SystemExit('runtime runner policy must remain external to checkout')
 except ValueError:pass
 out.parent.mkdir(parents=True,exist_ok=True);out.write_text(json.dumps(policy,indent=2,sort_keys=True)+'\n',encoding='utf-8');print(json.dumps({'policy':str(out),'policySha256':sha(out)},sort_keys=True));return 0
if __name__=='__main__':raise SystemExit(main())
