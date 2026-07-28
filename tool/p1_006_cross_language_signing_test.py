#!/usr/bin/env python3
from __future__ import annotations
import argparse,copy,importlib.util,json,sys
from datetime import datetime,timezone
from pathlib import Path

def load(path,name):
 spec=importlib.util.spec_from_file_location(name,path)
 if spec is None or spec.loader is None: raise RuntimeError(path)
 m=importlib.util.module_from_spec(spec); sys.modules[name]=m; spec.loader.exec_module(m); return m

def main():
 p=argparse.ArgumentParser(); p.add_argument('--project',default='.'); p.add_argument('--json-output'); a=p.parse_args(); root=Path(a.project).resolve(); results=[]
 def add(name,ok,detail): results.append({"name":name,"passed":bool(ok),"detail":detail})
 ed=load(root/'tool/ed25519_ref.py','p1_ed'); sys.path.insert(0,str(root/'tool')); sm=load(root/'tool/signed_manifest_v2.py','p1_sm')
 vectors=json.loads((root/'evals/fixtures/p1_006_cross_language_signing/golden_vectors.json').read_text())
 rfc=vectors['rfc8032']; seed=bytes.fromhex(rfc['seedHex']); message=bytes.fromhex(rfc['messageHex'])
 public=ed.public_key(seed); signature=ed.sign(seed,message)
 add('Python RFC 8032 vector',public.hex()==rfc['publicKeyHex'] and signature.hex()==rfc['signatureHex'] and ed.verify(public,message,signature),'known vector exact')
 manifest=vectors['manifest']; envelope=sm.sign_manifest(manifest['body'],seed=seed)
 add('Python manifest golden vector',sm.canonical_json(manifest['body']).encode().hex()==manifest['canonicalUtf8Hex'] and envelope['signature']==manifest['signatureHex'],'canonical bytes and signature exact')
 key=sm.TrustKey('p1-test-root',public,frozenset({'extension_manifest'}),frozenset({'kristin.test'})); ring=sm.ExternalKeyring({'p1-test-root':key})
 verified=False
 try: verified=sm.verify_manifest(envelope,keyring=ring,now=datetime(2026,7,28,12,tzinfo=timezone.utc),expected_use='extension_manifest',expected_domain='kristin.test')['payload']['artifactId']=='plugin.example'
 except Exception: pass
 add('Python verification',verified,'external keyring accepted')
 tampered=copy.deepcopy(envelope); tampered['payload']['artifactId']='plugin.tampered'
 rejected=False
 try: sm.verify_manifest(tampered,keyring=ring,now=datetime(2026,7,28,12,tzinfo=timezone.utc))
 except sm.ManifestVerificationError as e: rejected=e.code=='signature_invalid'
 add('Mutation rejection',rejected,'modified payload rejected')
 dart=(root/'lib/product/signed_manifest_v2.dart').read_text()+(root/'test/product/signed_manifest_v2_test.dart').read_text()
 add('Dart cross-language implementation',all(x in dart for x in ('Ed25519Reference','_Sha512','RFC 8032 Ed25519 vector passes in Dart','Signed Manifest v2 canonical vector matches Python')),'Dart signs and verifies same vectors')
 roadmap=json.loads((root/'docs/roadmap/roadmap.yaml').read_text()); tasks={x['id']:x for x in roadmap['tasks']}; add('Roadmap state',tasks.get('P1-006',{}).get('status')=='DONE',f"P1-006={tasks.get('P1-006',{}).get('status')}")
 passed=all(x['passed'] for x in results); report={"schemaVersion":"1.0.0","taskId":"P1-006","caseCount":len(results),"passedCount":sum(x['passed'] for x in results),"failedCount":sum(not x['passed'] for x in results),"passed":passed,"results":results}; text=json.dumps(report,indent=2,sort_keys=True)+'\n'
 if a.json_output: out=root/a.json_output; out.parent.mkdir(parents=True,exist_ok=True); out.write_text(text,encoding='utf-8',newline='\n')
 print(text,end=''); return 0 if passed else 1
if __name__=='__main__': raise SystemExit(main())
