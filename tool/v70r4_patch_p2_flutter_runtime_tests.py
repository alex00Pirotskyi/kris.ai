#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import pathlib
import re


class PatchError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise PatchError(message)


def read(root: pathlib.Path, relative: str) -> str:
    path = root / relative
    if not path.is_file():
        fail(f"missing source: {relative}")
    return path.read_text(encoding="utf-8")


def write(root: pathlib.Path, relative: str, value: str) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value, encoding="utf-8")


def replace_once(source: str, old: str, new: str, label: str) -> tuple[str, bool]:
    count = source.count(old)
    if count == 1:
        return source.replace(old, new, 1), True
    if count == 0 and new in source:
        return source, False
    raise PatchError(f"{label}: expected exactly one old or one already-patched anchor; old={count}")


TEST_AUTHORITY = r'''final class TestEnvelopeAuthority implements P2AutomationEnvelopeAuthority {
  int _requests = 0;
  final Map<String, int> _grantUses = <String, int>{};
  final List<P2AutomationEnvelope> issued = <P2AutomationEnvelope>[];

  @override
  Future<P2AutomationEnvelope> issue({
    required P2EffectBinding binding,
    required String operation,
    required Map<String, Object?> payload,
    String? expectedGrantDigest,
    Duration deadline = const Duration(seconds: 30),
  }) async {
    _requests += 1;
    final now = DateTime.now().toUtc();
    final notBefore = now.subtract(const Duration(seconds: 1));
    final expiresAt = now.add(deadline);
    final requestId = 'request-$_requests';
    final externalGrantDigest = expectedGrantDigest?.toLowerCase();
    if (externalGrantDigest != null &&
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(externalGrantDigest)) {
      throw StateError('expected_grant_digest_invalid');
    }
    final grantId = externalGrantDigest == null
        ? 'grant-$_requests'
        : 'grant-${externalGrantDigest.substring(0, 16)}';
    final useNumber = (_grantUses[grantId] ?? 0) + 1;
    _grantUses[grantId] = useNumber;
    final maxUses = externalGrantDigest == null ? 1 : 64;
    final scope = <String, Object?>{
      'paths': <String, Object?>{
        'roots': <String>['/'],
      },
      'process': <String, Object?>{'operation': operation},
      'network': <String, Object?>{'destinations': <String>[]},
      'browser': <String, Object?>{'profiles': <String>[]},
      'secrets': <String, Object?>{
        'leaseIds': <String>[],
        'rawReveal': false,
      },
    };
    final grant = <String, Object?>{
      'schemaVersion': '2.0.0',
      'grantId': grantId,
      'issuer': <String, Object?>{
        'actorId': 'desktop_host',
        'authority': 'desktop_host:deterministic_policy',
      },
      'binding': <String, Object?>{
        'runId': binding.runId,
        'taskId': binding.taskId,
        'actorId': binding.actorId,
        'toolId': binding.toolId,
        'accessProfileId': binding.accessProfileId,
        'operation': operation,
      },
      'scope': scope,
      'budgets': <String, int>{'wallClockMs': 30000},
      'validity': <String, Object?>{
        'issuedAt': now.toIso8601String(),
        'notBefore': notBefore.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'maxUses': maxUses,
      },
      'nonce': 'test-nonce-${_requests.toString().padLeft(16, '0')}',
      'auth': <String, Object?>{
        'algorithm': 'hmac-sha256',
        'keyId': 'test-grant',
        'mac': 'a' * 64,
      },
    };
    final decision = <String, Object?>{
      'schemaVersion': '2.0.0',
      'decisionId': 'decision-$_requests',
      'status': 'allow',
      'binding': <String, Object?>{
        'runId': binding.runId,
        'taskId': binding.taskId,
        'actorId': binding.actorId,
        'toolId': binding.toolId,
        'accessProfileId': binding.accessProfileId,
        'capabilityId': binding.capabilityId,
      },
      'effectiveScope': scope,
    };
    final grantDigest =
        externalGrantDigest ?? Sha256.text(p2CanonicalJson(grant));
    final consumption = P2GrantConsumption(
      grantId: grantId,
      requestId: requestId,
      useNumber: useNumber,
      previousUseNumber: useNumber - 1,
      stateVersion: _requests,
      revocationEpoch: 1,
      consumedAt: now,
      auth: <String, String>{
        'algorithm': 'hmac-sha256',
        'keyId': 'test-consumption',
        'mac': 'b' * 64,
      },
    );
    final workerIdentity = <String, Object?>{
      'schemaVersion': '2.0.0',
      'platform': 'linux',
      'principalType': 'dedicated-uid',
      'sessionId': 'test-worker-session-000001',
      'pid': 4242,
      'startToken': 'start-4242',
      'workerUid': 65534,
      'workerGid': 65534,
      'noNewPrivileges': true,
      'namespaceIsolation': true,
      'authorityConnectionDenied': true,
      'authorityDenialCode': 'worker_principal_denied',
      'launcherSha256': '1' * 64,
      'nodeSha256': '2' * 64,
      'hostScriptSha256': '3' * 64,
      'workerPolicySha256': '4' * 64,
    };
    final workerIdentitySha256 =
        Sha256.text(p2CanonicalJson(workerIdentity));
    final authenticatedIpc = <String, Object?>{
      'schemaVersion': '2.0.0',
      'peerId': 'desktop-host',
      'channelId': 'test-channel-0000000000001',
      'requestId': requestId,
      'workerIdentitySha256': workerIdentitySha256,
      'workerCanIssue': false,
      'symmetricKeyMaterialTransferred': false,
    };
    final audit = <String, Object?>{
      'id': 'audit-$_requests',
      'digest': 'd' * 64,
      'sequence': _requests,
    };
    final authority = <String, Object?>{
      'authorityKind': 'p1-isolated-authority-service-v2',
      'sharedP1ControlPlane': true,
      'p2CanIssueGrants': false,
      'workerCanIssue': false,
      'osEnforcedIsolation': true,
      'workerDeniedByOs': true,
      'workerIdentitySha256': workerIdentitySha256,
      'instanceId': 'p1a-test-instance',
      'implementationSha256': 'e' * 64,
      'runtimeBuildSha256': 'f' * 64,
    };
    final proof = P2WorkerGrantProof(
      grantId: grantId,
      grantDigest: grantDigest,
      policyDecisionId: 'decision-$_requests',
      policyDecisionDigest: Sha256.text(p2CanonicalJson(decision)),
      scopeDigest: Sha256.text(p2CanonicalJson(scope)),
      notBefore: notBefore,
      expiresAt: expiresAt,
      useNumber: useNumber,
      maxUses: maxUses,
      revocationEpoch: 1,
      consumptionReceipt: consumption,
      capabilityGrant: grant,
      policyDecision: decision,
      authenticatedIpc: authenticatedIpc,
      auditCheckpoint: audit,
      authority: authority,
      workerIdentity: workerIdentity,
      workerIdentitySha256: workerIdentitySha256,
    );
    final payloadWithOperation = <String, Object?>{
      'operation': operation,
      ...payload,
    };
    final authorization = <String, Object?>{
      'runId': binding.runId,
      'taskId': binding.taskId,
      'actorId': binding.actorId,
      'toolId': binding.toolId,
      'accessProfileId': binding.accessProfileId,
      'capabilityId': binding.capabilityId,
      'operation': operation,
      ...proof.toJson(),
    };
    final permit = P2WorkerEffectPermitV1(
      permitId: 'permit-$_requests',
      workerSessionId: 'test-worker-session-000001',
      channelId: 'test-channel-0000000000001',
      workerIdentitySha256: workerIdentitySha256,
      peerId: 'desktop-host',
      requestId: requestId,
      operation: operation,
      binding: <String, Object?>{
        'runId': binding.runId,
        'taskId': binding.taskId,
        'actorId': binding.actorId,
        'toolId': binding.toolId,
        'accessProfileId': binding.accessProfileId,
        'capabilityId': binding.capabilityId,
      },
      authorizationSha256: Sha256.text(p2CanonicalJson(authorization)),
      payloadSha256: Sha256.text(p2CanonicalJson(payloadWithOperation)),
      grantId: grantId,
      grantDigest: grantDigest,
      policyDecisionId: 'decision-$_requests',
      policyDecisionDigest: proof.policyDecisionDigest,
      scopeDigest: proof.scopeDigest,
      consumptionReceiptSha256:
          Sha256.text(p2CanonicalJson(consumption.toJson())),
      useNumber: useNumber,
      maxUses: maxUses,
      revocationEpoch: 1,
      authoritativeStateVersion: _requests,
      auditCheckpointId: 'audit-$_requests',
      auditCheckpointSha256: 'd' * 64,
      sharedAuthorityInstanceId: 'p1a-test-instance',
      authorityImplementationSha256: 'e' * 64,
      runtimeBuildSha256: 'f' * 64,
      sourceCommit: '0000000000000000000000000000000000000000',
      sourceTree: '1111111111111111111111111111111111111111',
      issuedAt: now,
      notBefore: notBefore,
      expiresAt: expiresAt,
      signerKeyId: 'test-effect-permit',
      signatureBase64: 'A' * 96,
    );
    final envelope = P2AutomationEnvelope(
      requestId: requestId,
      deadline: expiresAt,
      binding: binding,
      grantProof: proof,
      operation: operation,
      payload: payloadWithOperation,
      effectPermit: permit,
    );
    envelope.validate();
    issued.add(envelope);
    return envelope;
  }
}

'''


def _compact(source: str) -> str:
    return re.sub(r"\s+", "", source)


def _test_authority_complete(source: str) -> bool:
    compact = _compact(source)
    required = (
        "finalMap<String,int>_grantUses=<String,int>{};",
        "finalexternalGrantDigest=expectedGrantDigest?.toLowerCase();",
        "expected_grant_digest_invalid",
        "finaluseNumber=(_grantUses[grantId]??0)+1;",
        "_grantUses[grantId]=useNumber;",
        "finalmaxUses=externalGrantDigest==null?1:64;",
        "externalGrantDigest??Sha256.text(p2CanonicalJson(grant))",
        "previousUseNumber:useNumber-1",
    )
    return all(marker in compact for marker in required)


def patch_test_authority(root: pathlib.Path) -> bool:
    relative = "test/product/p2_test_support.dart"
    source = read(root, relative)
    if _test_authority_complete(source):
        return False
    if "final Map<String, int> _grantUses" in source or "expected_grant_digest_invalid" in source:
        fail("test envelope authority is partially patched")
    start = source.find("final class TestEnvelopeAuthority implements P2AutomationEnvelopeAuthority {")
    end = source.find("typedef TestResponseBuilder", start)
    if start < 0 or end < 0:
        fail("test envelope authority anchors missing")
    write(root, relative, source[:start] + TEST_AUTHORITY + source[end:])
    return True


def _workspace_banner_complete(source: str) -> bool:
    compact = _compact(source)
    return (
        "elseconstTextButton(onPressed:null,child:Text('Reviewbelow'),)" in compact
        and "child:constText('Disableandreset')" in compact
    )


def _dart_tokens(source: str) -> list[str]:
    """Return Dart code tokens while ignoring strings and comments.

    This is intentionally a small structural lexer, not a Dart parser. It is
    sufficient for recognizing the governed list-if/Expanded/child shape and
    avoids treating comments or string literals as executable source.
    """
    tokens: list[str] = []
    index = 0
    length = len(source)
    while index < length:
        char = source[index]
        if char.isspace():
            index += 1
            continue
        if source.startswith("//", index):
            newline = source.find("\n", index + 2)
            index = length if newline < 0 else newline + 1
            continue
        if source.startswith("/*", index):
            depth = 1
            index += 2
            while index < length and depth:
                if source.startswith("/*", index):
                    depth += 1
                    index += 2
                elif source.startswith("*/", index):
                    depth -= 1
                    index += 2
                else:
                    index += 1
            if depth:
                fail("unterminated Dart block comment")
            continue

        raw = char in "rR" and index + 1 < length and source[index + 1] in "'\""
        quote_index = index + 1 if raw else index
        if source[quote_index] in "'\"":
            quote = source[quote_index]
            triple = source.startswith(quote * 3, quote_index)
            cursor = quote_index + (3 if triple else 1)
            while cursor < length:
                if triple and source.startswith(quote * 3, cursor):
                    cursor += 3
                    break
                if not triple and source[cursor] == quote:
                    cursor += 1
                    break
                if not raw and source[cursor] == "\\":
                    cursor += 2
                else:
                    cursor += 1
            else:
                fail("unterminated Dart string literal")
            tokens.append("<string>")
            index = cursor
            continue

        if char.isalpha() or char in "_$":
            cursor = index + 1
            while cursor < length and (
                source[cursor].isalnum() or source[cursor] in "_$"
            ):
                cursor += 1
            tokens.append(source[index:cursor])
            index = cursor
            continue

        tokens.append(char)
        index += 1
    return tokens


def _matching_paren(tokens: list[str], open_index: int) -> int:
    if open_index >= len(tokens) or tokens[open_index] != "(":
        fail("internal Dart token scan expected an opening parenthesis")
    depth = 0
    for index in range(open_index, len(tokens)):
        token = tokens[index]
        if token == "(":
            depth += 1
        elif token == ")":
            depth -= 1
            if depth == 0:
                return index
            if depth < 0:
                break
    fail("unbalanced Dart parentheses in owner workspace")


def _workspace_onboarding_occurrences(source: str) -> int:
    tokens = _dart_tokens(source)
    prefix = ["if", "(", "!", "state", ".", "enabled", ")", "Expanded", "("]
    count = 0
    for start in range(0, len(tokens) - len(prefix) + 1):
        if tokens[start : start + len(prefix)] != prefix:
            continue
        expanded_open = start + len(prefix) - 1
        expanded_close = _matching_paren(tokens, expanded_open)
        cursor = expanded_open + 1
        matched_child = False
        depth = 1
        while cursor < expanded_close:
            token = tokens[cursor]
            if token == "(":
                depth += 1
                cursor += 1
                continue
            if token == ")":
                depth -= 1
                cursor += 1
                continue
            if depth == 1 and tokens[cursor : cursor + 2] == ["child", ":"]:
                expression = cursor + 2
                expected = ["_buildOnboarding", "(", "context"]
                if tokens[expression : expression + len(expected)] == expected:
                    tail = expression + len(expected)
                    if tail < expanded_close and tokens[tail] == ",":
                        tail += 1
                    if tail < expanded_close and tokens[tail] == ")":
                        tail += 1
                        if tail == expanded_close or tokens[tail] == ",":
                            matched_child = True
                            break
            cursor += 1
        if matched_child:
            count += 1
    return count


def _workspace_onboarding_complete(source: str) -> bool:
    return _workspace_onboarding_occurrences(source) == 1


def patch_owner_workspace(root: pathlib.Path) -> bool:
    relative = "lib/product/p2_owner_workspace.dart"
    source = read(root, relative)
    changed = False
    old_actions = """                actions: <Widget>[
                  if (state.enabled)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(widget.controller.disableAndReset),
                      child: const Text('Disable and reset'),
                    ),
                ],
"""
    new_actions = """                actions: <Widget>[
                  if (state.enabled)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(widget.controller.disableAndReset),
                      child: const Text('Disable and reset'),
                    )
                  else
                    const TextButton(
                      onPressed: null,
                      child: Text('Review below'),
                    ),
                ],
"""
    if not _workspace_banner_complete(source):
        if "Review below" in source:
            fail("owner workspace banner is partially patched")
        source, did = replace_once(source, old_actions, new_actions, "owner workspace banner actions")
        changed |= did
    onboarding_occurrences = _workspace_onboarding_occurrences(source)
    if onboarding_occurrences > 1:
        fail(f"owner workspace bounded onboarding is duplicated: {onboarding_occurrences}")
    if onboarding_occurrences == 0:
        pattern = re.compile(
            r"(?m)^(?P<indent>[ \t]*)if\s*\(\s*!state\.enabled\s*\)\s*"
            r"_buildOnboarding\(\s*context\s*,?\s*\)\s*,\s*$"
        )
        matches = list(pattern.finditer(source))
        if len(matches) != 1:
            if "Expanded" in source and "_buildOnboarding" in source:
                fail("owner workspace bounded onboarding is partially patched")
            fail(f"owner workspace bounded onboarding: expected one syntax anchor, found {len(matches)}")
        indent = matches[0].group("indent")
        replacement = (
            f"{indent}if (!state.enabled)\n"
            f"{indent}  Expanded(\n"
            f"{indent}    child: _buildOnboarding(context),\n"
            f"{indent}  ),"
        )
        source = pattern.sub(replacement, source, count=1)
        changed = True
    if changed:
        write(root, relative, source)
    return changed


def patch_preview_inventory(root: pathlib.Path) -> bool:
    relative = "config/p2_source_inventory.v1.json"
    path = root / relative
    if not path.is_file():
        fail(f"missing source: {relative}")
    value = json.loads(path.read_text(encoding="utf-8"))
    tests = value.get("testDart")
    if not isinstance(tests, list):
        fail("P2 source inventory testDart is invalid")
    required = "test/product/p2_qa_preview_gate_test.dart"
    normalized = sorted({str(item).replace("\\", "/") for item in tests} | {required})
    if normalized == tests:
        return False
    value["testDart"] = normalized
    value["qaPreviewInventoryExtension"] = {
        "reason": "V69 creates the governed QA preview gate before Flutter source-contract tests run",
        "test": required,
        "formalCompletion": False,
        "mergeEligible": False,
    }
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return True


def _chat_first_contract_complete(source: str) -> bool:
    compact = _compact(source)
    required = (
        "finalp2Shell=source('lib/product/p2_app_shell.dart');",
        "expect(ui,contains('home:P2KristinShell('));",
        "expect(ui,contains('chat:ChatStudio('));",
        "expect(p2Shell,contains('var_index=0;'));",
        "expect(p2Shell,contains('widget.chat,'));",
    )
    return all(marker in compact for marker in required)


def patch_chat_first_contract(root: pathlib.Path) -> bool:
    relative = "test/product/source_contract_test.dart"
    source = read(root, relative)
    if _chat_first_contract_complete(source):
        return False
    if "final p2Shell" in source or "home: P2KristinShell(" in source:
        fail("chat-first P2 shell contract is partially patched")
    old = """      final ui = source('lib/product/ui.dart');
      final chat = source('lib/product/chat_studio.dart');
      expect(ui, contains('home: ChatStudio('));
      expect(chat, contains("label: 'Chats'"));
"""
    new = """      final ui = source('lib/product/ui.dart');
      final chat = source('lib/product/chat_studio.dart');
      final p2Shell = source('lib/product/p2_app_shell.dart');
      expect(ui, contains('home: P2KristinShell('));
      expect(ui, contains('chat: ChatStudio('));
      expect(p2Shell, contains('var _index = 0;'));
      expect(p2Shell, contains('widget.chat,'));
      expect(chat, contains("label: 'Chats'"));
"""
    updated, changed = replace_once(source, old, new, "chat-first P2 shell contract")
    if changed:
        write(root, relative, updated)
    return changed


def r4_semantic_state(root: pathlib.Path) -> dict[str, bool]:
    inventory = json.loads(read(root, "config/p2_source_inventory.v1.json"))
    tests = inventory.get("testDart")
    return {
        "testAuthority": _test_authority_complete(read(root, "test/product/p2_test_support.dart")),
        "ownerWorkspaceBanner": _workspace_banner_complete(read(root, "lib/product/p2_owner_workspace.dart")),
        "ownerWorkspaceOnboarding": _workspace_onboarding_complete(read(root, "lib/product/p2_owner_workspace.dart")),
        "qaPreviewInventory": isinstance(tests, list) and "test/product/p2_qa_preview_gate_test.dart" in tests,
        "chatFirstContract": _chat_first_contract_complete(read(root, "test/product/source_contract_test.dart")),
    }


def patch(root: pathlib.Path) -> dict[str, object]:
    root = root.resolve()
    changed: list[str] = []
    operations = (
        ("test/product/p2_test_support.dart", patch_test_authority),
        ("lib/product/p2_owner_workspace.dart", patch_owner_workspace),
        ("config/p2_source_inventory.v1.json", patch_preview_inventory),
        ("test/product/source_contract_test.dart", patch_chat_first_contract),
    )
    for relative, operation in operations:
        if operation(root):
            changed.append(relative)
    semantic = r4_semantic_state(root)
    if not all(semantic.values()):
        fail(f"R4 semantic state incomplete after patch: {semantic}")
    return {
        "schemaVersion": "1.0.0",
        "resultType": "v70r4-p2-flutter-runtime-test-compatibility-patch-v1",
        "status": "passed",
        "changedFileCount": len(changed),
        "changedFiles": changed,
        "semanticStateRecognized": len(changed) == 0,
        "semanticFilesRecognized": sorted(key for key, value in semantic.items() if value),
        "allFourR4FilesCovered": True,
        "grantReuseBookkeepingFixed": True,
        "ownerWorkspaceLayoutFixed": True,
        "ownerWorkspaceOnboardingSyntaxAware": True,
        "ownerWorkspaceCompactExpandedRecognized": True,
        "ownerWorkspaceTrailingCommaIndependent": True,
        "qaPreviewInventoryFixed": True,
        "chatFirstP2ShellContractFixed": True,
        "testSuppressionAdded": False,
        "completionClaim": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--json-output")
    args = parser.parse_args()
    try:
        result = patch(pathlib.Path(args.project))
    except (PatchError, OSError, ValueError, json.JSONDecodeError) as exc:
        raise SystemExit(f"ERROR: {exc}") from exc
    output = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.json_output:
        pathlib.Path(args.json_output).write_text(output, encoding="utf-8")
    print(output, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
