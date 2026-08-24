#!/usr/bin/env python3
from __future__ import annotations
import pathlib
R=pathlib.Path(__file__).resolve().parents[1]
def rep(path,old,new):
 p=R/path;s=p.read_text(encoding='utf-8');n=s.count(old)
 if n!=1: raise SystemExit(f'{path}: target count {n}: {old!r}')
 p.write_text(s.replace(old,new,1),encoding='utf-8',newline='\n')
rep('lib/product/p2_owner_mode.dart',
"    if(!acknowledged) throw StateError('owner_data_boundary_acknowledgement_required');",
"    if (!acknowledged) {\n      throw StateError('owner_data_boundary_acknowledgement_required');\n    }")
rep('lib/product/p2_p1_authority_adapter.dart',
"    if(recorded['status']!='recorded') throw StateError('p1a_owner_effect_approval_not_recorded');",
"    if (recorded['status'] != 'recorded') {\n      throw StateError('p1a_owner_effect_approval_not_recorded');\n    }")
rep('lib/product/p2_p1_authority_adapter.dart',
"      if(ownerApprovalId.isEmpty) throw StateError('p1a_owner_mode_not_enabled');",
"      if (ownerApprovalId.isEmpty) {\n        throw StateError('p1a_owner_mode_not_enabled');\n      }")
rep('lib/product/p2_p1_authority_adapter.dart',
"        if(ownerApprovalId.isEmpty) throw StateError('p1a_owner_session_approval_missing');",
"        if (ownerApprovalId.isEmpty) {\n          throw StateError('p1a_owner_session_approval_missing');\n        }")
rep('lib/product/p2_product_runtime_bootstrap.dart',"import 'p2_owner_mode.dart';\n",'')
print('P1A_LINT_FIX_OK')
