#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MCP = ROOT / "lib/product/mcp_registry_v2.dart"
TEST = ROOT / "test/product/mcp_registry_v2_test.dart"


def splice(text: str, start: str, end: str, replacement: str, label: str) -> str:
    left = text.find(start)
    if left < 0:
        raise SystemExit(f"{label}: start marker missing")
    right = text.find(end, left)
    if right < 0:
        raise SystemExit(f"{label}: end marker missing")
    return text[:left] + replacement + text[right:]


def patch_registry() -> None:
    text = MCP.read_text(encoding="utf-8")

    grant_backend = r'''class McpExecutionGrantV2 {
  McpExecutionGrantV2({
    required this.projectId,
    required this.serverId,
    required Set<String> allowedTools,
    Set<String> allowedResources = const <String>{},
    Set<String> allowedPrompts = const <String>{},
    Set<String> allowedRoots = const <String>{},
    Set<String> allowedNetworkDestinations = const <String>{},
    Set<String> allowedSecretIds = const <String>{},
    this.allowOwnerHostExecution = false,
  })  : allowedTools = Set<String>.unmodifiable(allowedTools),
        allowedResources = Set<String>.unmodifiable(allowedResources),
        allowedPrompts = Set<String>.unmodifiable(allowedPrompts),
        allowedRoots = Set<String>.unmodifiable(allowedRoots),
        allowedNetworkDestinations =
            Set<String>.unmodifiable(allowedNetworkDestinations),
        allowedSecretIds = Set<String>.unmodifiable(allowedSecretIds);

  final String projectId;
  final String serverId;
  final Set<String> allowedTools;
  final Set<String> allowedResources;
  final Set<String> allowedPrompts;
  final Set<String> allowedRoots;
  final Set<String> allowedNetworkDestinations;
  final Set<String> allowedSecretIds;
  final bool allowOwnerHostExecution;
}

class McpBackendReceiptV2 {
  const McpBackendReceiptV2({
    required this.serverId,
    required this.backend,
    required this.running,
    required this.auditDetails,
  });

  final String serverId;
  final String backend;
  final bool running;
  final Map<String, Object?> auditDetails;
}

abstract interface class McpExecutionBackendV2 {
  bool get supportsIsolation;
  Future<McpBackendReceiptV2> start({
    required McpRegistryRecordV2 record,
    required McpExecutionGrantV2 grant,
  });
  Future<void> stop(String serverId);
  Future<bool> healthy(String serverId);
}

class McpUnavailableExecutionBackendV2 implements McpExecutionBackendV2 {
  const McpUnavailableExecutionBackendV2();

  @override
  bool get supportsIsolation => false;

  @override
  Future<McpBackendReceiptV2> start({
    required McpRegistryRecordV2 record,
    required McpExecutionGrantV2 grant,
  }) {
    throw ProductException(
      'mcp_execution_backend_unavailable',
      'No governed MCP execution backend is available for this platform/runtime.',
      details: <String, dynamic>{'serverId': record.id},
    );
  }

  @override
  Future<void> stop(String serverId) async {}

  @override
  Future<bool> healthy(String serverId) async => false;
}

'''
    text = splice(
        text,
        "class McpExecutionGrantV2 {",
        "class McpRegistryV2 {",
        grant_backend,
        "grant/backend section",
    )

    install_block = r'''  Future<McpRegistryRecordV2> _validatedCandidate({
    required String projectId,
    required Map<String, Object?> signedManifest,
  }) async {
    if (projectId.trim().isEmpty) {
      throw ProductException(
        'mcp_project_required',
        'A registered MCP server must be bound to a project.',
      );
    }
    final manifest = SignedManifestV2.fromJson(signedManifest);
    final body = manifest.body;
    if (body['schemaVersion'] != '2.0.0' ||
        body['intendedUse'] != 'mcp_server_descriptor' ||
        body['trustDomain'] != 'kristin.mcp') {
      throw ProductException(
        'mcp_descriptor_manifest_scope_invalid',
        'MCP descriptor manifest scope is invalid.',
      );
    }
    final keyId = body['keyId']?.toString() ?? '';
    final key = _trustedKeys[keyId];
    if (key == null || key.revoked) {
      throw ProductException(
        'mcp_descriptor_signer_untrusted',
        'MCP descriptor signer is unknown or revoked.',
      );
    }
    if (!manifest.verifyWithPublicKeyHex(key.publicKeyHex)) {
      throw ProductException(
        'mcp_descriptor_signature_invalid',
        'MCP descriptor signature verification failed.',
      );
    }
    final now = DateTime.now().toUtc();
    final issuedAt = DateTime.tryParse(
      body['issuedAt']?.toString() ?? '',
    )?.toUtc();
    final expiresAt = DateTime.tryParse(
      body['expiresAt']?.toString() ?? '',
    )?.toUtc();
    if (issuedAt == null ||
        expiresAt == null ||
        issuedAt.isAfter(now) ||
        !expiresAt.isAfter(now)) {
      throw ProductException(
        'mcp_descriptor_manifest_expired',
        'MCP descriptor manifest is not currently valid.',
      );
    }
    final rawPayload = body['payload'];
    if (rawPayload is! Map) {
      throw ProductException(
        'mcp_descriptor_payload_invalid',
        'MCP descriptor payload must be an object.',
      );
    }
    final payload = <String, Object?>{
      for (final entry in rawPayload.entries) entry.key.toString(): entry.value,
    };
    if (payload['schemaVersion'] != '1.0.0') {
      throw ProductException(
        'mcp_descriptor_payload_version_invalid',
        'MCP descriptor payload version is unsupported.',
      );
    }
    final descriptor = McpServerDescriptorV2.fromPayload(payload);
    final executable = File(descriptor.executablePath).absolute;
    if (!await executable.exists()) {
      throw ProductException(
        'mcp_executable_missing',
        'Registered MCP executable is unavailable.',
      );
    }
    final canonicalPath = await executable.resolveSymbolicLinks();
    final digest = Sha256.hex(await File(canonicalPath).readAsBytes());
    if (!constantTimeEquals(digest, descriptor.executableSha256)) {
      throw ProductException(
        'mcp_executable_changed',
        'MCP executable digest does not match the signed descriptor.',
      );
    }
    final normalizedDescriptor = McpServerDescriptorV2(
      id: descriptor.id,
      publisher: descriptor.publisher,
      version: descriptor.version,
      transport: descriptor.transport,
      executablePath: canonicalPath,
      executableSha256: descriptor.executableSha256,
      arguments: descriptor.arguments,
      tools: descriptor.tools,
      resources: descriptor.resources,
      prompts: descriptor.prompts,
      roots: descriptor.roots,
      networkDestinations: descriptor.networkDestinations,
      secretIds: descriptor.secretIds,
      retentionDays: descriptor.retentionDays,
      executionMode: descriptor.executionMode,
    );
    return McpRegistryRecordV2(
      id: descriptor.id,
      projectId: projectId,
      descriptor: normalizedDescriptor,
      manifestSha256: Sha256.text(canonicalJsonV2(signedManifest)),
      signerKeyId: keyId,
      state: McpLifecycleStateV2.installed,
      installedAt: now,
    );
  }

  Future<McpRegistryRecordV2> install({
    required String projectId,
    required Map<String, Object?> signedManifest,
  }) async {
    final record = await _validatedCandidate(
      projectId: projectId,
      signedManifest: signedManifest,
    );
    if (await _repository.get(record.id) != null) {
      throw ProductException(
        'mcp_server_already_registered',
        'Use the signed update flow for an existing MCP server identity.',
      );
    }
    await _repository.put(record);
    await audit.append('mcp.v2.installed', record.id, <String, dynamic>{
      'serverId': record.id,
      'projectId': projectId,
      'publisher': record.descriptor.publisher,
      'version': record.descriptor.version,
      'executionMode': record.descriptor.executionMode.name,
      'manifestSha256': record.manifestSha256,
    });
    return record;
  }

  Future<McpRegistryRecordV2> update({
    required String id,
    required Map<String, Object?> signedManifest,
  }) async {
    final current = await _required(id);
    if (current.state == McpLifecycleStateV2.revoked) {
      throw ProductException(
        'mcp_server_revoked',
        'A revoked MCP server identity cannot be updated in place.',
      );
    }
    if (current.state == McpLifecycleStateV2.running) {
      throw ProductException(
        'mcp_update_requires_stopped',
        'Stop the MCP server before applying a signed update.',
      );
    }
    final candidate = await _validatedCandidate(
      projectId: current.projectId,
      signedManifest: signedManifest,
    );
    if (candidate.id != current.id ||
        candidate.descriptor.publisher != current.descriptor.publisher) {
      throw ProductException(
        'mcp_update_identity_mismatch',
        'Signed MCP updates must preserve server and publisher identity.',
      );
    }
    if (!_isNewerVersion(
      candidate.descriptor.version,
      current.descriptor.version,
    )) {
      throw ProductException(
        'mcp_update_version_not_newer',
        'Signed MCP updates must advance the semantic version.',
      );
    }
    final scopeChanged =
        !_setsEqual(candidate.descriptor.tools, current.descriptor.tools) ||
        !_setsEqual(candidate.descriptor.resources, current.descriptor.resources) ||
        !_setsEqual(candidate.descriptor.prompts, current.descriptor.prompts) ||
        !_setsEqual(candidate.descriptor.roots, current.descriptor.roots) ||
        !_setsEqual(
          candidate.descriptor.networkDestinations,
          current.descriptor.networkDestinations,
        ) ||
        !_setsEqual(candidate.descriptor.secretIds, current.descriptor.secretIds) ||
        candidate.descriptor.executionMode != current.descriptor.executionMode;
    final next = McpRegistryRecordV2(
      id: current.id,
      projectId: current.projectId,
      descriptor: candidate.descriptor,
      manifestSha256: candidate.manifestSha256,
      signerKeyId: candidate.signerKeyId,
      state: McpLifecycleStateV2.disabled,
      installedAt: current.installedAt,
      updatedAt: DateTime.now().toUtc(),
    );
    await _repository.put(next);
    await audit.append('mcp.v2.updated', id, <String, dynamic>{
      'serverId': id,
      'oldVersion': current.descriptor.version,
      'newVersion': next.descriptor.version,
      'scopeChanged': scopeChanged,
      'reviewRequired': true,
      'state': next.state.name,
      'manifestSha256': next.manifestSha256,
    });
    return next;
  }

  static bool _setsEqual(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);

  static bool _isNewerVersion(String candidate, String current) {
    List<int>? parse(String value) {
      final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$').firstMatch(
        value.trim(),
      );
      if (match == null) {
        return null;
      }
      return <int>[
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      ];
    }

    final left = parse(candidate);
    final right = parse(current);
    if (left == null || right == null) {
      throw ProductException(
        'mcp_update_version_invalid',
        'MCP update versions must use semantic major.minor.patch form.',
      );
    }
    for (var index = 0; index < 3; index++) {
      if (left[index] > right[index]) {
        return true;
      }
      if (left[index] < right[index]) {
        return false;
      }
    }
    return false;
  }

'''
    text = splice(
        text,
        "  Future<McpRegistryRecordV2> install({",
        "  Future<McpRegistryRecordV2?> get(String id)",
        install_block,
        "install/update section",
    )

    lifecycle = r'''  Future<McpRegistryRecordV2> enable(String id) async {
    final current = await _required(id);
    if (current.state == McpLifecycleStateV2.running) {
      throw ProductException(
        'mcp_enable_requires_stopped',
        'A running MCP server must be stopped before enablement state can change.',
      );
    }
    return _transition(id, McpLifecycleStateV2.enabled, 'mcp.v2.enabled');
  }

  Future<McpRegistryRecordV2> stop(String id) async {
    final current = await _required(id);
    if (current.state != McpLifecycleStateV2.running) {
      throw ProductException(
        'mcp_stop_requires_running',
        'Only a running MCP server can be stopped.',
      );
    }
    await _backend.stop(id);
    return _transition(id, McpLifecycleStateV2.enabled, 'mcp.v2.stopped');
  }

  Future<McpRegistryRecordV2> disable(String id) async {
    final current = await _required(id);
    if (current.state == McpLifecycleStateV2.disabled) {
      return current;
    }
    if (current.state == McpLifecycleStateV2.running) {
      await _backend.stop(id);
    }
    return _transition(id, McpLifecycleStateV2.disabled, 'mcp.v2.disabled');
  }

  Future<McpRegistryRecordV2> revoke(String id) async {
    final current = await _required(id);
    if (current.state == McpLifecycleStateV2.revoked) {
      return current;
    }
    if (current.state == McpLifecycleStateV2.running) {
      await _backend.stop(id);
    }
    return _transition(id, McpLifecycleStateV2.revoked, 'mcp.v2.revoked');
  }

  Future<void> remove(String id) async {
    final current = await _required(id);
    if (current.state != McpLifecycleStateV2.revoked &&
        current.state != McpLifecycleStateV2.disabled) {
      throw ProductException(
        'mcp_remove_requires_disabled',
        'Disable or revoke the MCP server before removal.',
      );
    }
    await _backend.stop(id);
    await _repository.remove(id);
    await audit.append('mcp.v2.removed', id, <String, dynamic>{
      'serverId': id,
    });
  }

'''
    text = splice(
        text,
        "  Future<McpRegistryRecordV2> enable(String id)",
        "  Future<McpBackendReceiptV2> start({",
        lifecycle,
        "lifecycle section",
    )

    start_block = r'''  Future<McpBackendReceiptV2> start({
    required String id,
    required McpExecutionGrantV2 grant,
  }) async {
    final record = await _required(id);
    if (record.state != McpLifecycleStateV2.enabled) {
      throw ProductException(
        'mcp_server_not_enabled',
        'MCP server must be enabled before start.',
      );
    }
    if (grant.projectId != record.projectId || grant.serverId != record.id) {
      throw ProductException(
        'mcp_execution_grant_mismatch',
        'MCP execution grant identity mismatch.',
      );
    }
    bool within(Set<String> granted, Set<String> signed) =>
        signed.containsAll(granted);
    if (grant.allowedTools.isEmpty ||
        !within(grant.allowedTools, record.descriptor.tools) ||
        !within(grant.allowedResources, record.descriptor.resources) ||
        !within(grant.allowedPrompts, record.descriptor.prompts) ||
        !within(grant.allowedRoots, record.descriptor.roots) ||
        !within(
          grant.allowedNetworkDestinations,
          record.descriptor.networkDestinations,
        ) ||
        !within(grant.allowedSecretIds, record.descriptor.secretIds)) {
      throw ProductException(
        'mcp_execution_grant_scope_invalid',
        'MCP execution grant exceeds the signed descriptor.',
      );
    }
    if (record.descriptor.executionMode == McpExecutionModeV2.isolated &&
        !_backend.supportsIsolation) {
      throw ProductException(
        'mcp_isolation_backend_unavailable',
        'Untrusted MCP server requires isolation; no isolation backend is available.',
      );
    }
    if (record.descriptor.executionMode == McpExecutionModeV2.ownerHost &&
        !grant.allowOwnerHostExecution) {
      throw ProductException(
        'mcp_owner_host_grant_required',
        'Owner-host MCP execution requires an explicit grant.',
      );
    }
    final executable = File(record.descriptor.executablePath);
    if (!await executable.exists()) {
      await revoke(id);
      throw ProductException(
        'mcp_executable_missing',
        'Trusted MCP executable disappeared and the server was revoked.',
      );
    }
    final currentDigest = Sha256.hex(await executable.readAsBytes());
    if (!constantTimeEquals(
      currentDigest,
      record.descriptor.executableSha256,
    )) {
      await revoke(id);
      throw ProductException(
        'mcp_executable_changed',
        'MCP executable changed after trust and was revoked.',
      );
    }
    final receipt = await _backend.start(record: record, grant: grant);
    if (!receipt.running || receipt.serverId != record.id) {
      try {
        await _backend.stop(record.id);
      } catch (_) {}
      throw ProductException(
        'mcp_backend_receipt_invalid',
        'MCP backend did not attest the exact server as running.',
      );
    }
    final running = record.copyWith(
      state: McpLifecycleStateV2.running,
      updatedAt: DateTime.now().toUtc(),
    );
    await _repository.put(running);
    await audit.append('mcp.v2.started', id, <String, dynamic>{
      'serverId': id,
      'backend': receipt.backend,
      'executionMode': record.descriptor.executionMode.name,
      'allowedTools': grant.allowedTools.toList()..sort(),
      'allowedResources': grant.allowedResources.toList()..sort(),
      'allowedPrompts': grant.allowedPrompts.toList()..sort(),
      'allowedRoots': grant.allowedRoots.toList()..sort(),
      'allowedNetworkDestinations': grant.allowedNetworkDestinations.toList()
        ..sort(),
      'allowedSecretIds': grant.allowedSecretIds.toList()..sort(),
    });
    return receipt;
  }

'''
    text = splice(
        text,
        "  Future<McpBackendReceiptV2> start({",
        "  Future<bool> health(String id)",
        start_block,
        "start section",
    )

    health_transition = r'''  Future<bool> health(String id) async {
    final current = await _required(id);
    if (current.state != McpLifecycleStateV2.running) {
      return false;
    }
    return _backend.healthy(id);
  }

  Future<McpRegistryRecordV2> _transition(
    String id,
    McpLifecycleStateV2 state,
    String action,
  ) async {
    final current = await _required(id);
    if (current.state == state) {
      return current;
    }
    final allowed = switch (current.state) {
      McpLifecycleStateV2.installed => <McpLifecycleStateV2>{
          McpLifecycleStateV2.enabled,
          McpLifecycleStateV2.disabled,
          McpLifecycleStateV2.revoked,
        },
      McpLifecycleStateV2.enabled => <McpLifecycleStateV2>{
          McpLifecycleStateV2.disabled,
          McpLifecycleStateV2.revoked,
        },
      McpLifecycleStateV2.running => <McpLifecycleStateV2>{
          McpLifecycleStateV2.enabled,
          McpLifecycleStateV2.disabled,
          McpLifecycleStateV2.revoked,
        },
      McpLifecycleStateV2.disabled => <McpLifecycleStateV2>{
          McpLifecycleStateV2.enabled,
          McpLifecycleStateV2.revoked,
        },
      McpLifecycleStateV2.revoked => const <McpLifecycleStateV2>{},
    };
    if (!allowed.contains(state)) {
      final code = current.state == McpLifecycleStateV2.revoked
          ? 'mcp_server_revoked'
          : 'mcp_lifecycle_transition_invalid';
      throw ProductException(
        code,
        'MCP lifecycle transition ${current.state.name} -> ${state.name} is not allowed.',
      );
    }
    final next = current.copyWith(
      state: state,
      updatedAt: DateTime.now().toUtc(),
    );
    await _repository.put(next);
    await audit.append(action, id, <String, dynamic>{
      'serverId': id,
      'previousState': current.state.name,
      'state': state.name,
    });
    return next;
  }

'''
    text = splice(
        text,
        "  Future<bool> health(String id)",
        "  Future<McpRegistryRecordV2> _required(",
        health_transition,
        "health/transition section",
    )

    MCP.write_text(text, encoding="utf-8")


def write_tests() -> None:
    TEST.write_text(r'''import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/durable_workflow.dart';
import 'package:kristin_local_agent/product/mcp_registry_v2.dart';
import 'package:kristin_local_agent/product/signed_manifest_v2.dart';
import 'package:kristin_local_agent/product/storage_security.dart';

void main() {
  group('P7 MCP registry v2 lifecycle and execution grants', () {
    late Directory root;
    late DurableWorkflowStore store;
    late AuditChain audit;
    late File executable;
    late _FakeBackend backend;
    late McpRegistryV2 registry;
    final seed = List<int>.generate(32, (index) => index);
    late String publicKeyHex;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('kristin-mcp-v2-');
      executable = File('${root.path}${Platform.pathSeparator}server.bin');
      await executable.writeAsString('trusted executable bytes', flush: true);
      store = await DurableWorkflowStore.open(
        databaseFile: File('${root.path}${Platform.pathSeparator}workflow.sqlite3'),
        migrationBackupDirectory: Directory(
          '${root.path}${Platform.pathSeparator}migration-backups',
        ),
      );
      audit = AuditChain(
        File('${root.path}${Platform.pathSeparator}audit.jsonl'),
        SecretRedactor(),
      );
      await audit.open();
      backend = _FakeBackend();
      publicKeyHex = bytesToHexV2(Ed25519Reference.publicKey(seed));
      registry = McpRegistryV2(
        workflow: store,
        audit: audit,
        trustedKeys: <String, McpDescriptorTrustKeyV2>{
          'mcp-test-key': McpDescriptorTrustKeyV2(
            keyId: 'mcp-test-key',
            publicKeyHex: publicKeyHex,
          ),
        },
        backend: backend,
      );
    });

    tearDown(() async {
      await store.close();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    Map<String, Object?> signedManifest(
      McpExecutionModeV2 mode, {
      String version = '1.2.3',
      List<String> tools = const <String>['safe.read', 'safe.search'],
      List<String> resources = const <String>['docs'],
      List<String> prompts = const <String>['summarize'],
      List<String> roots = const <String>['workspace'],
      List<String> networkDestinations = const <String>[],
      List<String> secretIds = const <String>[],
    }) {
      final body = <String, Object?>{
        'schemaVersion': '2.0.0',
        'keyId': 'mcp-test-key',
        'intendedUse': 'mcp_server_descriptor',
        'trustDomain': 'kristin.mcp',
        'issuedAt': '2026-01-01T00:00:00Z',
        'expiresAt': '2099-01-01T00:00:00Z',
        'payload': <String, Object?>{
          'schemaVersion': '1.0.0',
          'id': 'server.test',
          'publisher': 'example.publisher',
          'version': version,
          'transport': 'stdio',
          'executablePath': executable.path,
          'executableSha256': Sha256.hex(executable.readAsBytesSync()),
          'arguments': const <String>['--stdio'],
          'tools': tools,
          'resources': resources,
          'prompts': prompts,
          'roots': roots,
          'networkDestinations': networkDestinations,
          'secretIds': secretIds,
          'retentionDays': 7,
          'executionMode':
              mode == McpExecutionModeV2.isolated ? 'isolated' : 'owner_host',
        },
      };
      final signature = Ed25519Reference.sign(
        seed,
        utf8.encode(canonicalJsonV2(body)),
      );
      return <String, Object?>{
        ...body,
        'signature': bytesToHexV2(signature),
      };
    }

    McpExecutionGrantV2 grant({bool ownerHost = false}) => McpExecutionGrantV2(
          projectId: 'project-1',
          serverId: 'server.test',
          allowedTools: const <String>{'safe.read'},
          allowedResources: const <String>{'docs'},
          allowedPrompts: const <String>{'summarize'},
          allowedRoots: const <String>{'workspace'},
          allowOwnerHostExecution: ownerHost,
        );

    test('signed descriptor persists exact identity and starts installed', () async {
      final installed = await registry.install(
        projectId: 'project-1',
        signedManifest: signedManifest(McpExecutionModeV2.isolated),
      );
      expect(installed.state, McpLifecycleStateV2.installed);
      expect(installed.descriptor.publisher, 'example.publisher');
      expect(installed.descriptor.tools, contains('safe.read'));
      expect(installed.manifestSha256, hasLength(64));
    });

    test('tampered signed descriptor is rejected before registration', () async {
      final manifest = signedManifest(McpExecutionModeV2.isolated);
      final payload = Map<String, Object?>.from(manifest['payload']! as Map);
      payload['version'] = '9.9.9';
      manifest['payload'] = payload;
      await expectLater(
        registry.install(projectId: 'project-1', signedManifest: manifest),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'mcp_descriptor_signature_invalid',
          ),
        ),
      );
    });

    test('duplicate install is rejected and signed update requires review', () async {
      await registry.install(
        projectId: 'project-1',
        signedManifest: signedManifest(McpExecutionModeV2.isolated),
      );
      await expectLater(
        registry.install(
          projectId: 'project-1',
          signedManifest: signedManifest(McpExecutionModeV2.isolated),
        ),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'mcp_server_already_registered',
          ),
        ),
      );
      await registry.enable('server.test');
      final updated = await registry.update(
        id: 'server.test',
        signedManifest: signedManifest(
          McpExecutionModeV2.isolated,
          version: '1.3.0',
          tools: const <String>['safe.read'],
        ),
      );
      expect(updated.descriptor.version, '1.3.0');
      expect(updated.state, McpLifecycleStateV2.disabled);
      expect(updated.descriptor.tools, <String>{'safe.read'});
      await expectLater(
        registry.update(
          id: 'server.test',
          signedManifest: signedManifest(
            McpExecutionModeV2.isolated,
            version: '1.2.9',
          ),
        ),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'mcp_update_version_not_newer',
          ),
        ),
      );
    });

    test('isolated descriptor never falls back to host execution', () async {
      backend.supportsIsolationValue = false;
      await registry.install(
        projectId: 'project-1',
        signedManifest: signedManifest(McpExecutionModeV2.isolated),
      );
      await registry.enable('server.test');
      await expectLater(
        registry.start(id: 'server.test', grant: grant()),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'mcp_isolation_backend_unavailable',
          ),
        ),
      );
      expect(backend.started, isEmpty);
    });

    test('owner-host execution requires explicit owner-host grant', () async {
      await registry.install(
        projectId: 'project-1',
        signedManifest: signedManifest(McpExecutionModeV2.ownerHost),
      );
      await registry.enable('server.test');
      await expectLater(
        registry.start(id: 'server.test', grant: grant()),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'mcp_owner_host_grant_required',
          ),
        ),
      );
      final receipt = await registry.start(
        id: 'server.test',
        grant: grant(ownerHost: true),
      );
      expect(receipt.running, isTrue);
      expect(await registry.health('server.test'), isTrue);
      final stopped = await registry.stop('server.test');
      expect(stopped.state, McpLifecycleStateV2.enabled);
    });

    test('granular execution grant cannot exceed signed descriptor', () async {
      await registry.install(
        projectId: 'project-1',
        signedManifest: signedManifest(McpExecutionModeV2.isolated),
      );
      await registry.enable('server.test');
      final widened = McpExecutionGrantV2(
        projectId: 'project-1',
        serverId: 'server.test',
        allowedTools: const <String>{'safe.read'},
        allowedResources: const <String>{'docs'},
        allowedPrompts: const <String>{'summarize'},
        allowedRoots: const <String>{'workspace'},
        allowedSecretIds: const <String>{'secret.outside-descriptor'},
      );
      await expectLater(
        registry.start(id: 'server.test', grant: widened),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'mcp_execution_grant_scope_invalid',
          ),
        ),
      );
      expect(backend.started, isEmpty);
    });

    test('backend receives exact grant and malformed receipt fails closed', () async {
      await registry.install(
        projectId: 'project-1',
        signedManifest: signedManifest(McpExecutionModeV2.isolated),
      );
      await registry.enable('server.test');
      final exactGrant = grant();
      final receipt = await registry.start(id: 'server.test', grant: exactGrant);
      expect(receipt.running, isTrue);
      expect(backend.grants.single.allowedResources, <String>{'docs'});
      await registry.stop('server.test');

      backend.receiptServerId = 'another.server';
      await expectLater(
        registry.start(id: 'server.test', grant: exactGrant),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'mcp_backend_receipt_invalid',
          ),
        ),
      );
      expect((await registry.get('server.test'))?.state, McpLifecycleStateV2.enabled);
      expect(backend.stopped, isNotEmpty);
    });

    test('running server cannot be enabled without stopping backend', () async {
      await registry.install(
        projectId: 'project-1',
        signedManifest: signedManifest(McpExecutionModeV2.isolated),
      );
      await registry.enable('server.test');
      await registry.start(id: 'server.test', grant: grant());
      await expectLater(
        registry.enable('server.test'),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'mcp_enable_requires_stopped',
          ),
        ),
      );
      expect((await registry.get('server.test'))?.state, McpLifecycleStateV2.running);
      await registry.stop('server.test');
    });

    test('signed update is rejected while server is running', () async {
      await registry.install(
        projectId: 'project-1',
        signedManifest: signedManifest(McpExecutionModeV2.isolated),
      );
      await registry.enable('server.test');
      await registry.start(id: 'server.test', grant: grant());
      await expectLater(
        registry.update(
          id: 'server.test',
          signedManifest: signedManifest(
            McpExecutionModeV2.isolated,
            version: '1.3.0',
          ),
        ),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'mcp_update_requires_stopped',
          ),
        ),
      );
      await registry.stop('server.test');
    });

    test('executable identity drift revokes before execution', () async {
      await registry.install(
        projectId: 'project-1',
        signedManifest: signedManifest(McpExecutionModeV2.ownerHost),
      );
      await registry.enable('server.test');
      await executable.writeAsString('changed executable bytes', flush: true);
      await expectLater(
        registry.start(id: 'server.test', grant: grant(ownerHost: true)),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'mcp_executable_changed',
          ),
        ),
      );
      expect((await registry.get('server.test'))?.state, McpLifecycleStateV2.revoked);
    });
  });
}

final class _FakeBackend implements McpExecutionBackendV2 {
  bool supportsIsolationValue = true;
  final List<String> started = <String>[];
  final List<String> stopped = <String>[];
  final List<McpExecutionGrantV2> grants = <McpExecutionGrantV2>[];
  String? receiptServerId;
  bool receiptRunning = true;

  @override
  bool get supportsIsolation => supportsIsolationValue;

  @override
  Future<McpBackendReceiptV2> start({
    required McpRegistryRecordV2 record,
    required McpExecutionGrantV2 grant,
  }) async {
    started.add(record.id);
    grants.add(grant);
    return McpBackendReceiptV2(
      serverId: receiptServerId ?? record.id,
      backend: record.descriptor.executionMode.name,
      running: receiptRunning,
      auditDetails: const <String, Object?>{'fixture': true},
    );
  }

  @override
  Future<void> stop(String serverId) async {
    stopped.add(serverId);
  }

  @override
  Future<bool> healthy(String serverId) async =>
      started.contains(serverId) && !stopped.contains(serverId);
}
''', encoding="utf-8")


def main() -> int:
    patch_registry()
    write_tests()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
