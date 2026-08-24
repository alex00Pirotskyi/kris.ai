import 'dart:convert';
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
        databaseFile:
            File('${root.path}${Platform.pathSeparator}workflow.sqlite3'),
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

    test('signed descriptor persists exact identity and starts installed',
        () async {
      final installed = await registry.install(
        projectId: 'project-1',
        signedManifest: signedManifest(McpExecutionModeV2.isolated),
      );
      expect(installed.state, McpLifecycleStateV2.installed);
      expect(installed.descriptor.publisher, 'example.publisher');
      expect(installed.descriptor.tools, contains('safe.read'));
      expect(installed.manifestSha256, hasLength(64));
    });

    test('tampered signed descriptor is rejected before registration',
        () async {
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

    test('duplicate install is rejected and signed update requires review',
        () async {
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

    test('backend receives exact grant and malformed receipt fails closed',
        () async {
      await registry.install(
        projectId: 'project-1',
        signedManifest: signedManifest(McpExecutionModeV2.isolated),
      );
      await registry.enable('server.test');
      final exactGrant = grant();
      final receipt =
          await registry.start(id: 'server.test', grant: exactGrant);
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
      expect((await registry.get('server.test'))?.state,
          McpLifecycleStateV2.enabled);
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
      expect((await registry.get('server.test'))?.state,
          McpLifecycleStateV2.running);
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
      expect((await registry.get('server.test'))?.state,
          McpLifecycleStateV2.revoked);
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
