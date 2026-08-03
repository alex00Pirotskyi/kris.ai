#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,pathlib,re

def require(v,m):
 if not v:raise SystemExit(m)
def read(root,rel):
 p=root/rel;require(p.is_file(),f'missing: {rel}');return p.read_text(errors='ignore')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--project',default='.');ap.add_argument('--allow-unmerged-fixture',action='store_true');a=ap.parse_args();root=pathlib.Path(a.project).resolve()
 adapter=read(root,'lib/product/p2_p1_authority_adapter.dart');bootstrap=read(root,'lib/product/p2_product_runtime_bootstrap.dart');patcher=read(root,'tool/p2_patch_application_composition.py');stager=read(root,'tool/p2_stage_runtime_bundle.py');worker=read(root,'automation_host/src/authenticated-ipc.mjs')
 require("import 'p1_authority_service_contract_v1.dart';" in adapter and 'P2IsolatedP1AuthorityAdapter' in adapter,'P2 does not consume P1A contract')
 require('P1AuthorityServiceHandleV1? p1AuthorityService' in bootstrap,'P2 bootstrap does not require P1A handle')
 require('ProductRuntime.p1AuthorityService' in patcher and 'merged P1A ProductRuntime amendment is absent' in patcher,'P2 patcher does not require merged P1A')
 for forbidden in ('P1DesktopControlPlaneAuthorityV2','P1ProductRuntimeControlPlaneFactoryV2','DeterministicPolicyEngineV2(','P2DurableGrantUseLedger','P2P1ControlPlaneAuthority'):
  corpus='\n'.join([adapter,bootstrap,patcher,stager])
  require(forbidden not in corpus,f'P2 reintroduced P1 authority/broker surface: {forbidden}')
 require('messageBase64' not in adapter and 'messageBase64' not in bootstrap and 'messageBase64' not in patcher,'P2 exposes arbitrary-message signing request')
 require('crypto.createHmac' not in worker and 'crypto.verify' in worker and 'FORBIDDEN_AUTHORITY_KEYS' in worker,'worker is not public-verifier-only')
 require(not (root/'automation_host/src/p1-authority-crypto-broker.mjs').exists(),'worker-reachable broker file packaged')
 require(not (root/'tool/p2_stage_p1_security_bundle.py').exists(),'P2 security/key staging tool packaged')
 require(not (root/'lib/product/p2_protected_authority_broker.dart').exists(),'P2 protected authority broker packaged')
 p1_impl=[x.name for x in (root/'lib/product').glob('p1_*.dart') if x.name not in {'p1_authority_service_contract_v1.dart','p1_authority_service_product_runtime_v1.dart'}]
 require(not p1_impl,f'P2 carries concrete P1 implementation: {p1_impl}')
 if not a.allow_unmerged_fixture:
  manifest=root/'release/evidence/P1A/manifest.json';require(manifest.is_file(),'merged P1A evidence missing')
  data=json.loads(manifest.read_text());require(data.get('status')=='passed' and data.get('completionClaim') is True and data.get('p2DependencySatisfied') is True,'P1A is not merged/completion eligible')
 print('P2 isolated P1A-service dependency contract: PASS');return 0
if __name__=='__main__':raise SystemExit(main())
