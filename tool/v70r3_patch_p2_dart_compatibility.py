#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, pathlib, re

class PatchError(RuntimeError): pass

def fail(msg:str): raise PatchError(msg)

def read(root: pathlib.Path, rel:str)->str:
    p=root/rel
    if not p.is_file(): fail(f'missing source: {rel}')
    return p.read_text(encoding='utf-8')

def write(root:pathlib.Path, rel:str, text:str)->None:
    (root/rel).write_text(text,encoding='utf-8',newline='\n')

def replace_once(text:str, old:str, new:str, label:str)->str:
    if new in text:
        return text
    count=text.count(old)
    if count==0:
        fail(f'{label}: expected anchor missing')
    if count!=1:
        fail(f'{label}: expected exactly one anchor, found {count}')
    return text.replace(old,new,1)

def replace_count(text:str, old:str, new:str, count:int, label:str)->str:
    observed=text.count(old)
    if observed==0 and text.count(new)>=count: return text
    if observed!=count: fail(f'{label}: expected {count}, found {observed}')
    return text.replace(old,new)

def _already_compatible(root:pathlib.Path)->bool:
    """Recognize the full semantic R3 result independent of Dart formatting.

    The R3 patch is intentionally re-run after the owner-risk composition patch and
    again on every hosted platform.  Dart formatting may reflow expressions while
    preserving the corrected API usage, so exact replacement bytes are not a valid
    idempotence marker.  This gate returns true only when every governed R3 repair is
    present and every obsolete API marker is absent.  Partial states still fail closed
    in the normal per-file patch logic below.
    """
    required={
      'lib/product/p2_automation_host_process_client.dart':[
        "import 'p2_effect_boundary.dart';",
        'P2RestrictedWorkerIdentitySink identitySink',
        'identitySink.bindRestrictedWorkerIdentity(boundIdentity);',
        'Stream<Map<String, Object?>> get events',
      ],
      'lib/product/p2_effect_boundary.dart':["final grantScope = grant.toJson()['scope'];"],
      'lib/product/p2_filesystem_service.dart':['String _p2FileSystemEntityTypeName(FileSystemEntityType type)'],
      'lib/product/p2_owner_workspace.dart':['initialValue: _approval','label: tab.accessibilityLabel'],
      'lib/product/p2_p1_authority_adapter.dart':['final operationDescriptor = P2P1OperationRegistry.descriptor(operation);'],
      'lib/product/p2_product_runtime_integration.dart':["import 'p2_pty_service.dart';"],
      'test/product/p2_automation_host_operations_test.dart':[
        "p2CanonicalJson(item.toJson()['payload'])",
        'p2CanonicalJson(item.payload)',
      ],
      'test/product/p2_fixture_runtime_unit_test.dart':[
        "import 'package:kristin_local_agent/product/crypto_utils.dart';",
        'restrictedWorkerLauncherSha256:',
        'workerPolicySha256:',
        'nodeExecutableSha256:',
        'hostScriptSha256:',
        "applicationComposition: 'diagnostic-fixture-runtime'",
        'applicationCompositionSha256:',
        'runnerAttestationSha256:',
        'toolchainExtensionFingerprint:',
        'nativeRuntimeManifestSha256:',
        'fixtureAuthority: true',
        'completionEligible: false',
      ],
      'test/product/p2_test_support.dart':[
        'final Map<String, int> _grantUses',
        'expected_grant_digest_invalid',
      ],
    }
    forbidden={
      'lib/product/p2_automation_host_process_client.dart':[
        'provider.bindRestrictedWorkerIdentity(boundIdentity);',
        'provider as P2RestrictedWorkerIdentitySink',
      ],
      'lib/product/p2_effect_boundary.dart':['grant.scope'],
      'lib/product/p2_filesystem_service.dart':[
        'FileSystemEntityType.file.name',
        'FileSystemEntityType.directory.name',
        'FileSystemEntityType.notFound.name',
        'type.name',
      ],
      'lib/product/p2_owner_workspace.dart':[
        'semanticLabel: tab.accessibilityLabel',
        'DropdownButtonFormField<P2OwnerApprovalPolicy>(\n            value:',
      ],
      'lib/product/p2_p1_authority_adapter.dart':['final descriptor = descriptor(operation);'],
      'lib/product/p2_product_runtime_bootstrap.dart':["import 'p2_automation_host_operations.dart';"],
      'test/product/p2_automation_host_operations_test.dart':[
        'item.ipcEnvelope',
        "import 'package:kristin_local_agent/product/p2_host_operations.dart';",
      ],
      'test/product/p2_fixture_runtime_unit_test.dart':[
        'P2ProductAssertionEvidence.shippedEntryPoint',
        'runtimeComposition:',
        'authorityObservation:',
        'runnerProvenance:',
        "import 'package:kristin_local_agent/product/p2_host_operations.dart';",
      ],
      'test/product/p2_shipped_product_runtime_e2e_test.dart':['product!','owner!'],
      'test/product/p2_test_support.dart':[
        "if(expectedGrantDigest!=null && expectedGrantDigest!=grantDigest)",
      ],
    }
    for rel,tokens in required.items():
        text=read(root,rel)
        if any(token not in text for token in tokens):
            return False
    workspace=read(root,'lib/product/p2_owner_workspace.dart')
    if re.search(
        r"return\s+Semantics\(\s*label:\s*tab\.accessibilityLabel,\s*child:\s*ListTile\(",
        workspace,
        flags=re.DOTALL,
    ) is None:
        return False
    for rel,tokens in forbidden.items():
        text=read(root,rel)
        if any(token in text for token in tokens):
            return False
    return True

def patch(root:pathlib.Path)->dict[str,object]:
    if _already_compatible(root):
        return {
          'schemaVersion':'1.0.0',
          'resultType':'v70r3-p2-dart-compatibility-patch-v1',
          'status':'passed',
          'changedFiles':[],
          'changedFileCount':0,
          'semanticStateRecognized':True,
          'completionClaim':False,
        }
    changed=[]
    def update(rel:str, fn):
        before=read(root,rel); after=fn(before)
        if after!=before:
            write(root,rel,after); changed.append(rel)

    def automation(t:str)->str:
        t=replace_once(t,"import 'p2_automation_host.dart';\n", "import 'p2_automation_host.dart';\nimport 'p2_effect_boundary.dart';\n",'automation effect binding import')
        old_identity = """      if (provider is P2RestrictedWorkerIdentitySink) {
        provider.bindRestrictedWorkerIdentity(boundIdentity);
      }
"""
        new_identity = """      if (provider case final P2RestrictedWorkerIdentitySink identitySink) {
        identitySink.bindRestrictedWorkerIdentity(boundIdentity);
      }
"""
        t=replace_once(t,old_identity,new_identity,'automation identity sink pattern')
        t=replace_once(t,'  Stream<Map<String, Object?>> get events => _events.stream;', '  @override\n  Stream<Map<String, Object?>> get events => _events.stream;','automation events override')
        t=replace_once(t,"    if (_closed) throw const P2AutomationHostException('automation_host_closed');", "    if (_closed) {\n      throw const P2AutomationHostException('automation_host_closed');\n    }",'automation closed braces')
        return t
    update('lib/product/p2_automation_host_process_client.dart',automation)

    def boundary(t:str)->str:
        old="""Object? _p2BoundaryCanonicalValue(Object? value) {
  if (value == null || value is String || value is bool || value is num) return value;
  if (value is List) return value.map<Object?>(_p2BoundaryCanonicalValue).toList(growable: false);
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{for (final key in keys) key: _p2BoundaryCanonicalValue(value[key])};
  }
  throw StateError('p2_boundary_non_json_value');
}
String p2BoundaryCanonicalJson(Object? value) => jsonEncode(_p2BoundaryCanonicalValue(value));
"""
        new="""Object? _p2BoundaryCanonicalValue(Object? value) {
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  if (value is List) {
    return value
        .map<Object?>(_p2BoundaryCanonicalValue)
        .toList(growable: false);
  }
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _p2BoundaryCanonicalValue(value[key]),
    };
  }
  throw StateError('p2_boundary_non_json_value');
}

String p2BoundaryCanonicalJson(Object? value) =>
    jsonEncode(_p2BoundaryCanonicalValue(value));
"""
        t=replace_once(t,old,new,'boundary canonical helper')
        old2="""    if (effectiveScope is Map && grant.scope is Map &&
        p2BoundaryCanonicalJson(effectiveScope) != p2BoundaryCanonicalJson(grant.scope)) {
      throw const P2AuthorizationException('scope_mismatch');
    }
"""
        new2="""    final grantScope = grant.toJson()['scope'];
    if (effectiveScope is Map &&
        grantScope is Map &&
        p2BoundaryCanonicalJson(effectiveScope) !=
            p2BoundaryCanonicalJson(grantScope)) {
      throw const P2AuthorizationException('scope_mismatch');
    }
"""
        t=replace_once(t,old2,new2,'boundary grant scope compatibility')
        return t
    update('lib/product/p2_effect_boundary.dart',boundary)

    def filesystem(t:str)->str:
        helper="""
String _p2FileSystemEntityTypeName(FileSystemEntityType type) {
  if (type == FileSystemEntityType.file) {
    return 'file';
  }
  if (type == FileSystemEntityType.directory) {
    return 'directory';
  }
  if (type == FileSystemEntityType.link) {
    return 'link';
  }
  if (type == FileSystemEntityType.notFound) {
    return 'notFound';
  }
  return 'unknown';
}
"""
        t=replace_once(t,"import 'p2_effect_journal.dart';\n", "import 'p2_effect_journal.dart';\n"+helper+'\n','filesystem type helper')
        t=replace_count(t,'type.name','_p2FileSystemEntityTypeName(type)',2,'filesystem dynamic type names')
        replacements={
          'FileSystemEntityType.file.name': "'file'",
          'FileSystemEntityType.directory.name': "'directory'",
          'FileSystemEntityType.notFound.name': "'notFound'",
        }
        for old,new in replacements.items(): t=t.replace(old,new)
        if re.search(r'FileSystemEntityType\.[A-Za-z]+\.name|\btype\.name\b',t): fail('filesystem legacy .name remains')
        return t
    update('lib/product/p2_filesystem_service.dart',filesystem)

    def workspace(t:str)->str:
        t=replace_once(t,'          DropdownButtonFormField<P2OwnerApprovalPolicy>(\n            value: _approval,','          DropdownButtonFormField<P2OwnerApprovalPolicy>(\n            initialValue: _approval,','workspace dropdown initial value')
        old="""                return ListTile(
                  selected: tab.id == selected?.id,
                  onTap: () {
                    final actualIndex = widget.terminalModel.tabs
                        .indexWhere((candidate) => candidate.id == tab.id);
                    if (actualIndex >= 0) {
                      setState(
                        () => widget.terminalModel.selectedIndex = actualIndex,
                      );
                    }
                  },
                  leading: const Icon(Icons.terminal),
                  title: Text(tab.title),
                  subtitle: Text(
                    '${tab.shell} • ${tab.cwd}\\n'
                    'run ${tab.runId} • task ${tab.taskId} • '
                    'grant ${tab.grantId}',
                  ),
                  trailing: Text(tab.attached ? 'Attached' : 'Detached'),
                  semanticLabel: tab.accessibilityLabel,
                );
"""
        new="""                return Semantics(
                  label: tab.accessibilityLabel,
                  child: ListTile(
                    selected: tab.id == selected?.id,
                    onTap: () {
                      final actualIndex = widget.terminalModel.tabs
                          .indexWhere((candidate) => candidate.id == tab.id);
                      if (actualIndex >= 0) {
                        setState(
                          () => widget.terminalModel.selectedIndex = actualIndex,
                        );
                      }
                    },
                    leading: const Icon(Icons.terminal),
                    title: Text(tab.title),
                    subtitle: Text(
                      '${tab.shell} • ${tab.cwd}\\n'
                      'run ${tab.runId} • task ${tab.taskId} • '
                      'grant ${tab.grantId}',
                    ),
                    trailing: Text(tab.attached ? 'Attached' : 'Detached'),
                  ),
                );
"""
        semantic_wrapper = re.search(
            r"return\s+Semantics\(\s*label:\s*tab\.accessibilityLabel,\s*child:\s*ListTile\(",
            t,
            flags=re.DOTALL,
        )
        if semantic_wrapper is None:
            t=replace_once(t,old,new,'workspace semantic wrapper')
        return t
    update('lib/product/p2_owner_workspace.dart',workspace)

    def adapter(t:str)->str:
        t=replace_once(t,"""        if (forbidden.hasMatch(entry.key.toString()) ||
            _containsForbiddenAuthorityMaterial(entry.value)) return true;
""","""        if (forbidden.hasMatch(entry.key.toString()) ||
            _containsForbiddenAuthorityMaterial(entry.value)) {
          return true;
        }
""",'adapter forbidden braces')
        t=replace_once(t,'    final descriptor = descriptor(operation);\n    return P2EffectBinding(', '    final operationDescriptor = P2P1OperationRegistry.descriptor(operation);\n    return P2EffectBinding(','adapter descriptor self shadow')
        t=t.replace('actorId: actorId ?? descriptor.actorId,','actorId: actorId ?? operationDescriptor.actorId,')
        t=t.replace('toolId: descriptor.toolId,','toolId: operationDescriptor.toolId,')
        t=t.replace('capabilityId: descriptor.capabilityId,','capabilityId: operationDescriptor.capabilityId,')
        return t
    update('lib/product/p2_p1_authority_adapter.dart',adapter)

    def bootstrap(t:str)->str:
        t=t.replace("import 'p2_automation_host_operations.dart';\n",'')
        t=replace_once(t,"    if (active != null) return active.buildWorkspace(key:key);", "    if (active != null) {\n      return active.buildWorkspace(key: key);\n    }",'bootstrap active workspace braces')
        t=replace_count(t,"    final active=runtime; if(active==null) throw StateError('owner_mode_runtime_unavailable');", "    final active = runtime;\n    if (active == null) {\n      throw StateError('owner_mode_runtime_unavailable');\n    }",2,'bootstrap owner runtime braces')
        one_line = "      if (p1AuthorityService == null) throw StateError('merged_p1a_service_unavailable');"
        braced = "      if (p1AuthorityService == null) {\n        throw StateError('merged_p1a_service_unavailable');\n      }"
        owner_risk = "      if (!ownerRiskQa) {\n        if (p1AuthorityService == null) {\n          throw StateError('merged_p1a_service_unavailable');\n        }"
        if one_line in t:
            t=t.replace(one_line,braced,1)
        elif braced in t or owner_risk in t:
            pass
        else:
            fail('bootstrap p1a compatibility boundary missing')
        t=replace_once(t,'          if(await file.exists()) await file.delete();','          if (await file.exists()) {\n            await file.delete();\n          }','bootstrap clear settings braces')
        t=replace_once(t,"    if(RegExp(r'(secret|token|password|credential|api.?key|private.?key|bearer)',caseSensitive:false).hasMatch(value)) return 'owner_runtime_start_failed_redacted';", "    if (RegExp(\n      r'(secret|token|password|credential|api.?key|private.?key|bearer)',\n      caseSensitive: false,\n    ).hasMatch(value)) {\n      return 'owner_runtime_start_failed_redacted';\n    }",'bootstrap safe failure braces')
        return t
    update('lib/product/p2_product_runtime_bootstrap.dart',bootstrap)

    def integration(t:str)->str:
        t=replace_once(t,"import 'p2_product_binding_context.dart';\n", "import 'p2_product_binding_context.dart';\nimport 'p2_pty_service.dart';\n",'runtime pty import')
        replacements={
          "    if (_closed) throw StateError('owner_runtime_closed');":"    if (_closed) {\n      throw StateError('owner_runtime_closed');\n    }",
          "    if (_closed || !_supervised.containsKey(watchdogId)) return;":"    if (_closed || !_supervised.containsKey(watchdogId)) {\n      return;\n    }",
          "    if (ids.isEmpty) throw StateError('no_supervised_process_tree');":"    if (ids.isEmpty) {\n      throw StateError('no_supervised_process_tree');\n    }",
          "      if (binding != null) await _persistLifecycle(binding, 'emergency_kill_requested');":"      if (binding != null) {\n        await _persistLifecycle(binding, 'emergency_kill_requested');\n      }",
          "    if (binding == null) return;":"    if (binding == null) {\n      return;\n    }",
          "    if (binding == null) throw StateError('watchdog_not_supervising');":"    if (binding == null) {\n      throw StateError('watchdog_not_supervising');\n    }",
          "      if (content.contains('completed')) await file.delete();":"      if (content.contains('completed')) {\n        await file.delete();\n      }",
          "    if (await file.exists()) await file.delete();":"    if (await file.exists()) {\n      await file.delete();\n    }",
          "    if (_closed) return;":"    if (_closed) {\n      return;\n    }",
        }
        for old,new in replacements.items():
            if old in t: t=t.replace(old,new)
        return t
    update('lib/product/p2_product_runtime_integration.dart',integration)

    def snapshot(t:str)->str:
        replacements={
          '    if (git.exitCode != 0) return null;':'    if (git.exitCode != 0) {\n      return null;\n    }',
          '      if (displacedExisting) await displaced.delete();':'      if (displacedExisting) {\n        await displaced.delete();\n      }',
          '      if (await staged.exists()) await staged.delete();':'      if (await staged.exists()) {\n        await staged.delete();\n      }',
          '        if (await target.exists()) await target.delete();':'        if (await target.exists()) {\n          await target.delete();\n        }',
          "    if (verify.exitCode != 0) throw StateError('git_checkpoint_missing');":"    if (verify.exitCode != 0) {\n      throw StateError('git_checkpoint_missing');\n    }",
          "    if (restore.exitCode != 0) throw StateError('git_checkpoint_restore_failed');":"    if (restore.exitCode != 0) {\n      throw StateError('git_checkpoint_restore_failed');\n    }",
        }
        for old,new in replacements.items():
            if old in t: t=t.replace(old,new)
        return t
    update('lib/product/p2_snapshot_undo.dart',snapshot)

    def automation_test(t:str)->str:
        t=t.replace("import 'package:kristin_local_agent/product/p2_host_operations.dart';\n",'')
        t=replace_once(t,"""      client.calls.every(
        (item) => item.ipcEnvelope.body['payload'] == item.payload,
      ),
""","""      client.calls.every(
        (item) => p2CanonicalJson(item.toJson()['payload']) ==
            p2CanonicalJson(item.payload),
      ),
""",'automation test envelope compatibility')
        return t
    update('test/product/p2_automation_host_operations_test.dart',automation_test)

    def fixture_test(t:str)->str:
        t=t.replace("import 'package:kristin_local_agent/product/p2_host_operations.dart';\n",'')
        t=replace_once(t,"import 'package:kristin_local_agent/product/p2_automation_host.dart';\n", "import 'package:kristin_local_agent/product/crypto_utils.dart';\nimport 'package:kristin_local_agent/product/p2_automation_host.dart';\n",'fixture crypto import')
        old="""              workingDirectory:
                  '${project.path}${Platform.pathSeparator}automation_host',
              bootstrapProvider: authority,
"""
        new="""              workingDirectory:
                  '${project.path}${Platform.pathSeparator}automation_host',
              restrictedWorkerLauncher: node,
              restrictedWorkerLauncherSha256:
                  Sha256.hex(File(node).readAsBytesSync()),
              workerPolicy: authorityScript.path,
              workerPolicySha256:
                  Sha256.hex(authorityScript.readAsBytesSync()),
              nodeExecutableSha256:
                  Sha256.hex(File(node).readAsBytesSync()),
              hostScriptSha256: Sha256.hex(hostScript.readAsBytesSync()),
              bootstrapProvider: authority,
"""
        t=replace_once(t,old,new,'fixture launch config compatibility')
        old2="""      final evidence = P2ProductAssertionEvidence(
        taskId: taskId,
        assertionId: 'p2-${taskId.substring(3)}.product-runtime-e2e',
        platform: _platformName(),
        commitSha: commitSha,
        entryPoint: P2ProductAssertionEvidence.shippedEntryPoint,
        runtimeComposition: <String, Object?>{
          'shippedProductRuntime': false,
          'applicationCompositionPatched': false,
          'ownerRuntime': 'isolated-fixture-harness',
          'fixtureAuthorityEligible': false,
          'watchdogAutomaticallyArmed': false,
        },
        authorizationBoundary: 'p1-isolated-authority-service-effect-permit-v2',
        authorityObservation: const <String, Object?>{
          'authorityImplementation': 'diagnostic-only',
          'authorityKind': 'unit-test-only',
          'completionEligible': false,
        },
        runnerProvenance: const <String, Object?>{
          'controlledRunnerAttested': false,
          'interactiveDesktopAttested': false,
        },
        productionAdapter: productionAdapter,
        osEffect: osEffect,
        postcondition: postcondition,
        receipt: receipt,
        status: status,
        sourceOnly: false,
        startedAt: startedAt,
        completedAt: DateTime.now().toUtc(),
      );
"""
        new2="""      final evidence = P2ProductAssertionEvidence(
        taskId: taskId,
        assertionId: 'p2-${taskId.substring(3)}.product-runtime-e2e',
        platform: _platformName(),
        commitSha: commitSha,
        entryPoint: entryPoint,
        applicationComposition: 'diagnostic-fixture-runtime',
        applicationCompositionSha256:
            Sha256.text('diagnostic-fixture-runtime'),
        authorizationBoundary: 'p1-isolated-authority-service-effect-permit-v2',
        authority: const <String, Object?>{
          'authorityImplementation': 'diagnostic-only',
          'authorityKind': 'unit-test-only',
          'completionEligible': false,
        },
        productionAdapter: productionAdapter,
        runnerAttestationSha256: '0' * 64,
        toolchainExtensionFingerprint: '0' * 64,
        nativeRuntimeManifestSha256: '0' * 64,
        osEffect: osEffect,
        postcondition: postcondition,
        receipt: receipt,
        status: status,
        sourceOnly: true,
        fixtureAuthority: true,
        completionEligible: false,
        startedAt: startedAt,
        completedAt: DateTime.now().toUtc(),
      );
"""
        t=replace_once(t,old2,new2,'fixture evidence compatibility')
        return t
    update('test/product/p2_fixture_runtime_unit_test.dart',fixture_test)

    def shipped_test(t:str)->str:
        t=t.replace('product!','product').replace('owner!','owner')
        return t
    update('test/product/p2_shipped_product_runtime_e2e_test.dart',shipped_test)

    def support(t:str)->str:
        if "final Map<String, int> _grantUses" in t and "expected_grant_digest_invalid" in t:
            return t
        t=replace_once(t,"    if(expectedGrantDigest!=null && expectedGrantDigest!=grantDigest) throw StateError('expected_grant_digest_mismatch');", "    if (expectedGrantDigest != null && expectedGrantDigest != grantDigest) {\n      throw StateError('expected_grant_digest_mismatch');\n    }",'test support braces')
        for ch in ['a','b','1','2','3','4','d','e','f','A']:
            t=t.replace("'${'"+ch+"'*64}'", "'"+ch+"' * 64")
        t=t.replace("'${'A'*96}'", "'A' * 96")
        return t
    update('test/product/p2_test_support.dart',support)

    # Fail closed on the exact obsolete API markers from the Windows analyzer log.
    forbidden={
      'lib/product/p2_automation_host_process_client.dart':['provider.bindRestrictedWorkerIdentity(boundIdentity);','provider as P2RestrictedWorkerIdentitySink'],
      'lib/product/p2_effect_boundary.dart':['grant.scope'],
      'lib/product/p2_filesystem_service.dart':['FileSystemEntityType.file.name','FileSystemEntityType.directory.name','FileSystemEntityType.notFound.name','type.name'],
      'lib/product/p2_owner_workspace.dart':['semanticLabel: tab.accessibilityLabel','DropdownButtonFormField<P2OwnerApprovalPolicy>(\n            value:'],
      'lib/product/p2_p1_authority_adapter.dart':['final descriptor = descriptor(operation);'],
      'test/product/p2_automation_host_operations_test.dart':['item.ipcEnvelope'],
      'test/product/p2_fixture_runtime_unit_test.dart':['P2ProductAssertionEvidence.shippedEntryPoint','runtimeComposition:','authorityObservation:','runnerProvenance:'],
      'test/product/p2_shipped_product_runtime_e2e_test.dart':['product!','owner!'],
    }
    for rel,markers in forbidden.items():
        text=read(root,rel)
        for marker in markers:
            if marker in text: fail(f'{rel}: obsolete marker remains: {marker}')
    result={'schemaVersion':'1.0.0','resultType':'v70r3-p2-dart-compatibility-patch-v1','status':'passed','changedFiles':sorted(changed),'changedFileCount':len(changed),'completionClaim':False}
    return result

def main()->int:
    ap=argparse.ArgumentParser(); ap.add_argument('--project',required=True,type=pathlib.Path); ap.add_argument('--json-output')
    a=ap.parse_args(); root=a.project.resolve(); result=patch(root); out=json.dumps(result,indent=2,sort_keys=True)+'\n'
    if a.json_output: pathlib.Path(a.json_output).write_text(out,encoding='utf-8')
    print(out,end=''); return 0
if __name__=='__main__':
    raise SystemExit(main())
