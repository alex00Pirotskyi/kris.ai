#!/usr/bin/env python3
from __future__ import annotations
import copy
from p1a_signed_evidence import sign_document_for_contract_fixture,verify_ed25519_document

def rejected(fn,label):
 try:fn()
 except SystemExit:return
 raise SystemExit(f'{label}: forged evidence accepted')
body={'schemaVersion':'3.0.0','platform':'linux','status':'passed','completionEligible':True,'exactBinding':{'sourceCommit':'a'*40},'syntheticContractFixture':True}
good,trust=sign_document_for_contract_fixture(body,key_id='fixture',purpose='p1a-build-provenance')
verify_ed25519_document(good,trust,purpose='p1a-build-provenance')
bad=copy.deepcopy(good);bad['status']='failed';rejected(lambda:verify_ed25519_document(bad,trust,purpose='p1a-build-provenance'),'tamper')
unsigned=copy.deepcopy(good);unsigned.pop('signature');rejected(lambda:verify_ed25519_document(unsigned,trust,purpose='p1a-build-provenance'),'unsigned')
rejected(lambda:verify_ed25519_document(good,trust,purpose='p1a-platform-receipt'),'wrong-purpose')
print('P1A signed-evidence forgery rejection: PASS')
