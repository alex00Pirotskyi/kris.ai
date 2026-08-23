import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/durable_workflow.dart';
import 'package:kristin_local_agent/product/mcp_registry_v2.dart';
import 'package:kristin_local_agent/product/signed_manifest_v2.dart';
import 'package:kristin_local_agent/product/storage_security.dart';

void main() {
  group('P7-002/P7-003/P7-004 MCP registry v2', () {
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
      if (await root.exists()) await root.delete(recursive: true);
    });

    Map<String, Object?> signedManifest(McpExecutionModeV2 mode) {
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
          'version': '1.2.3',
          'transport': 'stdio',
          'executablePath': executable.path,
          'executableSha256': Sha256.hex(executable.readAsBytesSync()),
          'arguments': const <String>['--stdio'],
          'tools': const <String>['safe.read', 'safe.search'],
          'resources': const <String>['docs'],
          'prompts': const <String>['summarize'],
          'roots': const <String>['workspace'],
          'networkDestinations': const <String>[],
          'secretIds': const <String>[],
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

    test('signed descriptor persists exact identity and starts disabled', () async {
      final installed = await registry.install(
        projectId: 'project-1',
        signedManifest: signedManifest(McpExecutionModeV2.isolated),
      );
      expect(installed.state, McpLifecycleStateV2.installed);
      expect(installed.descriptor.publisher, 'example.publisher');
      expect(installed.descriptor.tools, contains('safe.read'));
      expect(installed.manifestSha256, hasLength(64));
      expect((await registry.get('server.test'))?.descriptor.version, '1.2.3');
    });

    test('tampered signed descriptor is rejected before registration', () async {
      final manifest = signedManifest(McpExecutionModeV2.isolated);
      final payload = Map<String, Object?>.from(manifest['payload']! as Map);
      payload['version'] = '9.9.9';
      manifest['payload'] = payload;
      expect(
        () => registry.install(projectId: 'project-1', signedManifest: manifest),
        throwsA(
          isA<ProductException>().having(
            (error) => error.code,
            'code',
            'mcp_descriptor_signature_invalid',
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
      expect(
        () => registry.start(
          id: 'server.test',
          grant: const McpExecutionGrantV2(
            projectId: 'project-1',
            serverId: 'server.test',
            allowedTools: <String>{'safe.read'},
          ),
        ),
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

    test('owner-host execution requires an explicit grant and is auditable', () async {
      await registry.install(
        projectId: 'project-1',
        signedManifest: signedManifest(McpExecutionModeV2.ownerHost),
      );
      await registry.enable('server.test');
      expect(
        () => registry.start(
          id: 'server.test',
          grant: const McpExecutionGrantV2(
            projectId: 'project-1',
            serverId: 'server.test',
            allowedTools: <String>{'safe.read'},
          ),
        ),
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
        grant: const McpExecutionGrantV2(
          projectId: 'project-1',
          serverId: 'server.test',
          allowedTools: <String>{'safe.read'},
          allowOwnerHostExecution: true,
        ),
      );
      expect(receipt.running, isTrue);
      expect(await registry.health('server.test'), isTrue);
      expect(backend.started, <String>['server.test']);
      await registry.disable('server.test');
      expect(backend.stopped, contains('server.test'));
    });

    test('executable identity drift revokes the server before execution', () async {
      await registry.install(
        projectId: 'project-1',
        signedManifest: signedManifest(McpExecutionModeV2.ownerHost),
      );
      await registry.enable('server.test');
      await executable.writeAsString('changed executable bytes', flush: true);
      expect(
        () => registry.start(
          id: 'server.test',
          grant: const McpExecutionGrantV2(
            projectId: 'project-1',
            serverId: 'server.test',
            allowedTools: <String>{'safe.read'},
            allowOwnerHostExecution: true,
          ),
        ),
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

  @override
  bool get supportsIsolation => supportsIsolationValue;

  @override
  Future<McpBackendReceiptV2> start({required McpRegistryRecordV2 record}) async {
    started.add(record.id);
    return McpBackendReceiptV2(
      serverId: record.id,
      backend: record.descriptor.executionMode.name,
      running: true,
      auditDetails: const <String, Object?>{'fixture': true},
    );
  }

  @override
  Future<void> stop(String serverId) async {
    stopped.add(serverId);
  }

  @override
  Future<bool> healthy(String serverId) async => started.contains(serverId) && !stopped.contains(serverId);
}
