#!/usr/bin/env python3
from __future__ import annotations
import base64,hashlib,json,pathlib,re,subprocess
HEX40=re.compile(r'^[0-9a-f]{40}$');HEX64=re.compile(r'^[0-9a-f]{64}$')

def canonical_bytes(value:object)->bytes:
    return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode('utf-8')
def sha256_file(path:pathlib.Path)->str:return hashlib.sha256(path.read_bytes()).hexdigest()
def load_object(path:pathlib.Path)->dict:
    value=json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(value,dict):raise SystemExit(f'{path}: JSON object required')
    return value
def _unsigned(document:dict)->dict:return {k:v for k,v in document.items() if k!='signature'}
def _key(trust:dict,key_id:str,purpose:str,platform:str|None)->dict:
    if trust.get('schemaVersion')!='1.0.0' or trust.get('trustType')!='p1a-evidence-trust-v1' or trust.get('completionEligible') is not True:raise SystemExit('P1A completion-eligible evidence trust identity invalid')
    rows=[row for row in trust.get('keys',[]) if isinstance(row,dict) and row.get('keyId')==key_id]
    if len(rows)!=1:raise SystemExit('P1A evidence signer not trusted')
    row=rows[0]
    if purpose not in row.get('purposes',[]):raise SystemExit('P1A signer purpose not trusted')
    if platform and platform not in row.get('platforms',[]):raise SystemExit('P1A signer platform not trusted')
    return row
def _node_verify(*,algorithm:str,public_key_b64:str,message:bytes,signature_b64:str)->None:
    script="""const crypto=require('crypto');const [algorithm,pub,msg,sig]=process.argv.slice(1);const key=algorithm==='ed25519'?crypto.createPublicKey({key:Buffer.concat([Buffer.from('302a300506032b6570032100','hex'),Buffer.from(pub,'base64')]),format:'der',type:'spki'}):crypto.createPublicKey({key:Buffer.from(pub,'base64'),format:'der',type:'spki'});const ok=algorithm==='ed25519'?crypto.verify(null,Buffer.from(msg,'base64'),key,Buffer.from(sig,'base64')):crypto.verify('sha256',Buffer.from(msg,'base64'),key,Buffer.from(sig,'base64'));process.exit(ok?0:3);"""
    run=subprocess.run(['node','-e',script,algorithm,public_key_b64,base64.b64encode(message).decode(),signature_b64],capture_output=True,text=True)
    if run.returncode:raise SystemExit('P1A evidence signature invalid')
def verify_ed25519_document(document:dict,trust:dict,*,purpose:str)->None:
    signature=document.get('signature')
    if not isinstance(signature,dict) or signature.get('algorithm')!='ed25519' or signature.get('purpose')!=purpose:raise SystemExit('P1A signed component signature metadata invalid')
    key_id=str(signature.get('keyId',''));platform=str(document.get('platform','')) or None;row=_key(trust,key_id,purpose,platform)
    public=str(row.get('publicKeyBase64',''));sig=str(signature.get('signatureBase64',''));digest=str(signature.get('signedSha256',''));message=canonical_bytes(_unsigned(document))
    if not HEX64.fullmatch(digest) or hashlib.sha256(message).hexdigest()!=digest:raise SystemExit('P1A signed component digest invalid')
    if row.get('algorithm')!='ed25519' or len(public)<40 or len(sig)<40:raise SystemExit('P1A evidence key/signature shape invalid')
    _node_verify(algorithm='ed25519',public_key_b64=public,message=message,signature_b64=sig)
def verify_service_ecdsa_receipt(document:dict,*,openssl_executable:str='openssl')->None:
    del openssl_executable
    signature=document.get('signature')
    if not isinstance(signature,dict) or signature.get('algorithm')!='ecdsa-p256-sha256' or signature.get('nonExportable') is not True or signature.get('privateExportDenied') is not True:raise SystemExit('P1A service receipt key attestation invalid')
    public=str(signature.get('publicKeySpkiBase64',''));sig=str(signature.get('signatureBase64',''));att=str(signature.get('providerAttestationSha256',''))
    if len(public)<80 or len(sig)<40 or not HEX64.fullmatch(att):raise SystemExit('P1A service receipt signature shape invalid')
    _node_verify(algorithm='ecdsa-p256-sha256',public_key_b64=public,message=canonical_bytes(_unsigned(document)),signature_b64=sig)
def sign_document_for_contract_fixture(document:dict,private_key_seed:bytes|None=None,*,key_id:str,purpose:str)->tuple[dict,dict]:
    seed=private_key_seed or hashlib.sha256(b'p1a-contract-fixture').digest()
    script="""const crypto=require('crypto');const seed=Buffer.from(process.argv[1],'base64');const body=Buffer.from(process.argv[2],'base64');const prefix=Buffer.from('302e020100300506032b657004220420','hex');const key=crypto.createPrivateKey({key:Buffer.concat([prefix,seed]),format:'der',type:'pkcs8'});const pub=crypto.createPublicKey(key).export({format:'der',type:'spki'}).subarray(-32);const sig=crypto.sign(null,body,key);console.log(JSON.stringify({publicKeyBase64:pub.toString('base64'),signatureBase64:sig.toString('base64')}));"""
    message=canonical_bytes(document);run=subprocess.run(['node','-e',script,base64.b64encode(seed).decode(),base64.b64encode(message).decode()],capture_output=True,text=True,check=True);signed=dict(document);result=json.loads(run.stdout);signed['signature']={'algorithm':'ed25519','keyId':key_id,'purpose':purpose,'signedSha256':hashlib.sha256(message).hexdigest(),'signatureBase64':result['signatureBase64']};trust={'schemaVersion':'1.0.0','trustType':'p1a-evidence-trust-v1','completionEligible':True,'keys':[{'keyId':key_id,'algorithm':'ed25519','publicKeyBase64':result['publicKeyBase64'],'purposes':[purpose],'platforms':[str(document.get('platform','linux'))]}]};return signed,trust


def validate_protected_evidence_trust(
    trust_path:pathlib.Path,
    *,
    github_repo:str,
    gh_executable:str='gh',
    variable_name:str='KRISTIN_P1A_V66_EVIDENCE_TRUST_SHA256',
)->dict:
    trust=load_object(trust_path)
    if trust.get('schemaVersion')!='1.0.0' or trust.get('trustType')!='p1a-evidence-trust-v1' or trust.get('completionEligible') is not True:
        raise SystemExit('P1A protected evidence trust identity invalid')
    binding=trust.get('protectedRepositoryBinding')
    if not isinstance(binding,dict):raise SystemExit('P1A protected evidence trust binding missing')
    if binding.get('repository')!=github_repo or binding.get('variableName')!=variable_name or binding.get('required') is not True:
        raise SystemExit('P1A protected evidence trust repository binding invalid')
    digest=sha256_file(trust_path)
    run=subprocess.run([gh_executable,'api',f'repos/{github_repo}/actions/variables/{variable_name}','--jq','.value'],capture_output=True,text=True)
    if run.returncode:raise SystemExit('P1A protected evidence trust variable unavailable')
    configured=run.stdout.strip().lower()
    if not HEX64.fullmatch(configured) or configured!=digest:
        raise SystemExit('P1A evidence trust does not match protected repository trust root')
    return {'repository':github_repo,'variableName':variable_name,'trustSha256':digest,'protectedRepositoryBindingVerified':True}
