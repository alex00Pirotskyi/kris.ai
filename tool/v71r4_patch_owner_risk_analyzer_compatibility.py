#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, pathlib, re

class PatchError(RuntimeError): pass

def fail(message:str)->None: raise PatchError(message)
def read(root:pathlib.Path, rel:str)->str:
    path=root/rel
    if not path.is_file(): fail(f'missing source: {rel}')
    return path.read_text(encoding='utf-8')
def write(root:pathlib.Path, rel:str, text:str)->None:
    (root/rel).write_text(text,encoding='utf-8',newline='\n')

def _adapter_complete(text:str)->bool:
    return all(token in text for token in (
        'Map<String, Object?>? lastAuthorityObservation(String taskId);',
        '@override\n  bool get qaPreview => _qaPreview;',
        '@override\n  Map<String, Object?>? lastAuthorityObservation(String taskId)',
    ))

def _owner_complete(text:str)->bool:
    required=(
        'final Map<String, Map<String, Object?>> _observations',
        '@override\n  Map<String, Object?>? lastAuthorityObservation(String taskId)',
        "'completionEligible': false,",
        "'durableConsumptionStateVersion': _uses,",
        "'durableConsumptionUseNumber': useNumber,",
        "'securityEvidenceWaived': true,",
        "'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'",
        "'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'",
    )
    forbidden=(
        "import 'p2_automation_host_process_client.dart';",
        "if (identity == null) throw StateError('owner_risk_worker_identity_not_bound');",
        "'${'a' * 64}'", "'${'b' * 64}'", "'${'d' * 64}'",
        "'${'e' * 64}'", "'${'f' * 64}'", "'${'A' * 96}'",
    )
    return all(token in text for token in required) and not any(token in text for token in forbidden)

def patch(root:pathlib.Path)->dict[str,object]:
    adapter_rel='lib/product/p2_p1_authority_adapter.dart'
    owner_rel='lib/product/p2_owner_risk_authority.dart'
    adapter=read(root,adapter_rel); owner=read(root,owner_rel)
    if _adapter_complete(adapter) and _owner_complete(owner):
        return {'schemaVersion':'1.0.0','resultType':'v71r4-owner-risk-analyzer-compatibility-v1','status':'passed','changedFiles':[],'changedFileCount':0,'semanticStateRecognized':True,'runtimeAuthorityObservationContract':True,'ownerRiskAnalyzerCleanContract':True,'completionClaim':False}
    changed=[]

    # Shared runtime authority observation API.
    if 'Map<String, Object?>? lastAuthorityObservation(String taskId);' not in adapter:
        anchor='  bool get qaPreview;\n}'
        if adapter.count(anchor)!=1: fail('runtime authority observation interface anchor changed')
        adapter=adapter.replace(anchor,"  bool get qaPreview;\n  Map<String, Object?>? lastAuthorityObservation(String taskId);\n}",1)
    if '@override\n  bool get qaPreview => _qaPreview;' not in adapter:
        anchor='  bool get qaPreview => _qaPreview;'
        if adapter.count(anchor)!=1: fail('isolated adapter qaPreview anchor changed')
        adapter=adapter.replace(anchor,'  @override\n  bool get qaPreview => _qaPreview;',1)
    if '@override\n  Map<String, Object?>? lastAuthorityObservation(String taskId)' not in adapter:
        anchor='  Map<String, Object?>? lastAuthorityObservation(String taskId) =>\n      _observations[taskId];'
        if adapter.count(anchor)!=1: fail('isolated adapter observation anchor changed')
        adapter=adapter.replace(anchor,'  @override\n  Map<String, Object?>? lastAuthorityObservation(String taskId) =>\n      _observations[taskId];',1)
    if not _adapter_complete(adapter): fail('runtime authority observation contract incomplete after patch')
    write(root,adapter_rel,adapter); changed.append(adapter_rel)

    # Owner-risk authority generated source analyzer/runtime compatibility.
    owner=owner.replace("import 'p2_automation_host_process_client.dart';\n",'',1)
    if 'final Map<String, Map<String, Object?>> _observations' not in owner:
        anchor='  final Map<String, int> _grantUses = <String, int>{};\n'
        if owner.count(anchor)!=1: fail('owner-risk observation map anchor changed')
        owner=owner.replace(anchor,anchor+'  final Map<String, Map<String, Object?>> _observations =\n      <String, Map<String, Object?>>{};\n',1)
    if '@override\n  Map<String, Object?>? lastAuthorityObservation(String taskId)' not in owner:
        anchor='  @override\n  bool get qaPreview => true;\n'
        if owner.count(anchor)!=1: fail('owner-risk observation method anchor changed')
        owner=owner.replace(anchor,anchor+'\n  @override\n  Map<String, Object?>? lastAuthorityObservation(String taskId) =>\n      _observations[taskId];\n',1)
    owner=owner.replace("    if (identity == null) throw StateError('owner_risk_worker_identity_not_bound');", "    if (identity == null) {\n      throw StateError('owner_risk_worker_identity_not_bound');\n    }",1)
    literals={
      "'${'a' * 64}'":"'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'",
      "'${'b' * 64}'":"'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'",
      "'${'d' * 64}'":"'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'",
      "'${'e' * 64}'":"'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'",
      "'${'f' * 64}'":"'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'",
      "'${'A' * 96}'":"'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'",
    }
    for old,new in literals.items(): owner=owner.replace(old,new)
    if "_observations[binding.taskId]" not in owner:
        anchor='    envelope.validate();\n    return envelope;'
        if owner.count(anchor)!=1: fail('owner-risk observation recording anchor changed')
        observation="""    envelope.validate();
    _observations[binding.taskId] = Map<String, Object?>.unmodifiable(
      <String, Object?>{
        'schemaVersion': '1.0.0',
        'taskId': binding.taskId,
        'operation': operation,
        'authorityKind': authorityKind,
        'authorityImplementation': authorityImplementation,
        'completionEligible': false,
        'qaPreview': true,
        'securityEvidenceWaived': true,
        'currentAccountAuthority': true,
        'durableConsumptionStateVersion': _uses,
        'durableConsumptionUseNumber': useNumber,
        'revocationEpoch': 1,
        'requestId': requestId,
        'grantId': grantId,
        'grantDigest': grantDigest,
        'workerIdentitySha256': workerIdentitySha256,
        'p2CanIssueGrants': false,
        'workerCanIssue': false,
        'workerDeniedByOs': false,
        'osEnforcedIsolation': false,
      },
    );
    return envelope;"""
        owner=owner.replace(anchor,observation,1)
    if not _owner_complete(owner): fail('owner-risk analyzer/runtime contract incomplete after patch')
    write(root,owner_rel,owner); changed.append(owner_rel)
    return {'schemaVersion':'1.0.0','resultType':'v71r4-owner-risk-analyzer-compatibility-v1','status':'passed','changedFiles':changed,'changedFileCount':len(changed),'semanticStateRecognized':False,'runtimeAuthorityObservationContract':True,'ownerRiskAnalyzerCleanContract':True,'completionClaim':False}

def main()->int:
    ap=argparse.ArgumentParser(); ap.add_argument('--project',default='.'); ap.add_argument('--json-output'); a=ap.parse_args()
    result=patch(pathlib.Path(a.project).resolve()); out=json.dumps(result,indent=2,sort_keys=True)+'\n'
    if a.json_output:pathlib.Path(a.json_output).write_text(out,encoding='utf-8')
    print(out,end=''); return 0
if __name__=='__main__': raise SystemExit(main())
