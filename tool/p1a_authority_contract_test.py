#!/usr/bin/env python3
from __future__ import annotations
import argparse,pathlib

def require(value,message):
 if not value: raise SystemExit(message)

def main():
 a=argparse.ArgumentParser();a.add_argument('--project',default='.');n=a.parse_args();r=pathlib.Path(n.project).resolve()
 scan=[r/'lib',r/'authority_service',r/'config',r/'schemas']
 files=[x for base in scan if base.exists() for x in base.rglob('*') if x.is_file()]
 text='\n'.join(x.read_text(errors='ignore') for x in files)
 for forbidden in ('p1-authority-crypto-broker.mjs','messageBase64','privateKeyBase64','BEGIN PRIVATE KEY','authorize-effect-v1','PUBLIC_VERIFIER_BOOTSTRAP_V1','AUTHORIZE_EFFECT_V1'):
  require(forbidden not in text,f'forbidden/stale authority surface: {forbidden}')
 contract=(r/'lib/product/p1_authority_service_contract_v1.dart').read_text()
 for marker in ('authorize-effect-v2','record-effect-outcome-v2','describe-authority-v2','policyValidatedInsideService','grantValidatedInsideService','workerIdentity','nonExportableKeys'):
  require(marker in contract,f'Dart authority contract marker missing: {marker}')
 core=(r/'authority_service/native/common/authority_core_v2.hpp').read_text()
 for marker in ('evaluate_policy','kristin.capability-grant.v2','grantValidatedInsideService','useConsumedInsideService','revocationCheckedInsideService','auditAppendedInsideService','request_replay_detected','kAuthorizeV2','worker-identity-claimed','worker-identity-denial-bound','workerIdentityDenialBoundInsideService','authority_worker_identity_denial_mismatch'):
  require(marker in core,f'authority core marker missing: {marker}')
 linux=(r/'authority_service/native/linux/authority_service_linux.cpp').read_text()
 for marker in ('SO_PEERCRED','pkcs11:','tpm2:','desktop_executable_identity_mismatch','worker_principal_denied','authority_core'):
  require(marker in linux,f'Linux authority marker missing: {marker}')
 windows=(r/'authority_service/native/windows/authority_service_windows.cpp').read_text()
 for marker in ('CreateNamedPipeW','ConnectNamedPipe','GetNamedPipeClientProcessId','TokenIsAppContainer','MS_PLATFORM_CRYPTO_PROVIDER','NCryptSignHash','StartServiceCtrlDispatcherW'):
  require(marker in windows,f'Windows authority marker missing: {marker}')
 for stale in ('BLOCKED: Windows','return false; // fail closed until provisioned identities'):
  require(stale not in windows,'Windows authority remains a stub')
 mac=(r/'authority_service/native/macos/authority_service_macos.mm').read_text()
 for marker in ('xpc_connection_create_mach_service','XPC_CONNECTION_MACH_SERVICE_LISTENER','xpc_connection_get_audit_token','dlsym','kSecGuestAttributeAudit','SecCodeCheckValidity','kSecAttrTokenIDSecureEnclave','SecKeyCreateSignature'):
  require(marker in mac,f'macOS authority marker missing: {marker}')
 require('BLOCKED: macOS' not in mac,'macOS authority remains a stub')
 connector=(r/'lib/product/p1_authority_service_native_connector_v2.dart').read_text()
 for marker in ('DynamicLibrary.open','p1a_connector_configure','p1a_connector_request','p1a_connector_close'):
  require(marker in connector,f'concrete Flutter/native connector missing: {marker}')
 runtime=(r/'lib/product/p1_authority_service_product_runtime_v1.dart').read_text()
 require('openInstalledOrTest' in runtime and 'P1AuthorityNativeConnectorV2' in runtime,'ProductRuntime connector composition missing')
 patcher=(r/'tool/p1a_patch_product_runtime.py').read_text()
 require('openInstalledOrTest()' in patcher and 'openIfInstalled()' not in patcher,'ProductRuntime patcher registry API mismatch')
 tests='\n'.join(x.read_text() for x in (r/'test/product').glob('p1_authority_service_*_test.dart'))
 require('package:kristin_local_agent/' in tests and 'package:kris_studio_ai/' not in tests,'P1A Dart tests use the wrong package import')
 require('final DynamicLibrary _library;' not in connector,'unused DynamicLibrary lifetime field remains')
 workflow=(r/'.github/workflows/p1-authority-amendment.yml').read_text()
 require('integration/p1-authority-service-v63r15' in workflow,'P1A workflow does not trigger the V66-R3 R15 source branch')
 for marker in ("github.event_name == 'workflow_dispatch'", "github.ref == 'refs/heads/main'", 'inputs.source_sha == github.sha', 'inputs.package_sha256 == vars.KRISTIN_P1A_V66_PACKAGE_SHA256', 'github.actor == vars.KRISTIN_P1A_AUTHORIZED_ACTOR'):
  require(workflow.count(marker)==3,f'P1A controlled workflow boundary missing: {marker}')
 require(workflow.count('environment: p1a-controlled')==3,'P1A protected environment missing')
 require('KRISTIN_P1A_BEHAVIORAL_ENABLED' not in workflow,'unsafe repository-wide P1A behavioral toggle remains')
 evidence=(r/'tool/p1a_platform_evidence.py').read_text()
 for marker in ('workerPrincipalDeniedInsideService','workerIdentityDenialBoundInsideService','workerIdentityDenialBindingSha256','service/worker denial identity mismatch'):
  require(marker in evidence,f'P1A worker-denial evidence binding missing: {marker}')
 print('P1A V63 production typed isolated authority contract: PASS')
 return 0
if __name__=='__main__':raise SystemExit(main())
