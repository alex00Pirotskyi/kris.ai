#!/usr/bin/env python3
from __future__ import annotations
import argparse,pathlib

def need(value:bool,message:str)->None:
    if not value: raise SystemExit(message)

def main()->int:
    parser=argparse.ArgumentParser();parser.add_argument('--project',default='.');args=parser.parse_args()
    root=pathlib.Path(args.project).resolve()
    strict=(root/'authority_service/native/common/strict_json.hpp').read_text()
    core=(root/'authority_service/native/common/authority_core_v2.hpp').read_text()
    linux=(root/'authority_service/native/linux/authority_service_linux.cpp').read_text()
    windows=(root/'authority_service/native/windows/authority_service_windows.cpp').read_text()
    macos=(root/'authority_service/native/macos/authority_service_macos.mm').read_text()
    regression=(root/'authority_service/native/common/authority_core_regression_test.cpp').read_text()
    need('value(const char* v)' in strict and 'value(std::string_view v)' in strict,'C-string JSON constructor repair missing')
    need('explicit value(bool v)' in strict,'JSON bool constructor must remain non-ambiguous')
    for marker in ('requestId",json::value(request_id)','authority_owner_approval_payload_mismatch','authority_owner_approval_binding_mismatch','authority_owner_approval_operation_mismatch','authority_owner_approval_peer_mismatch'):
        need(marker in core,f'owner approval exact-binding marker missing: {marker}')
    need('owner_approval_id + "|" + approval_digest' in core and 'request_id + "|" + request_nonce' not in core,'approval one-use grant binding missing')
    need('part == ".."' in core and 'normalize_policy_path' in core,'lexical traversal rejection missing')
    need('hmac_secret_for_purpose' in core and 'kOwnerApprovalHmacPurpose' in core,'HMAC purpose authority missing')
    for name,text in (('linux',linux),('windows',windows),('macos',macos)):
        need('hmac_secret_for_purpose(purpose)' in text and 'key_id.find("owner")' not in text,f'{name} HMAC secret selection is key-name dependent')
    need('load_authority_config(c.policy)' in windows and 'load_authority_config(config_path)' not in windows,'Windows policy snapshot path repair missing')
    need('load_authority_config(cfg.policy)' in macos and 'load_authority_config(path)' not in macos,'macOS policy snapshot path repair missing')
    need('xpc_connection_set_target_queue(peer,dispatch_get_main_queue())' in macos,'macOS authority state serialization missing')
    for marker in ('json_literal_constructor_regression','authority_grant_exhausted','authority_owner_approval_payload_mismatch','policy_path_outside_current_account'):
        need(marker in regression,f'native core regression marker missing: {marker}')
    for platform in ('linux','windows','macos'):
        cmake=(root/f'authority_service/native/{platform}/CMakeLists.txt').read_text()
        need('kristin_p1a_authority_core_regression' in cmake,f'{platform} native core regression target missing')
    print('P1A V63-R15 retained R14 runtime security regression contract: PASS')
    return 0
if __name__=='__main__': raise SystemExit(main())
