import 'dart:io';

import 'crypto_utils.dart';
import 'durable_workflow.dart';
import 'repository.dart';
import 'signed_manifest_v2.dart';
import 'storage_security.dart';

enum McpExecutionModeV2 { isolated, ownerHost }

enum McpLifecycleStateV2 { installed, enabled, running, disabled, revoked }

class McpDescriptorTrustKeyV2 {
  const McpDescriptorTrustKeyV2({
    required this.keyId,
    required this.publicKeyHex,
    this.revoked = false,
  });

  final String keyId;
  final String publicKeyHex;
  final bool revoked;
}

class McpServerDescriptorV2 {
  const McpServerDescriptorV2({
    required this.id,
    required this.publisher,
    required this.version,
    required this.transport,
    required this.executablePath,
    required this.executableSha256,
    required this.arguments,
    required this.tools,
    required this.resources,
    required this.prompts,
    required this.roots,
    required this.networkDestinations,
    required this.secretIds,
    required this.retentionDays,
    required this.executionMode,
  });

  final String id;
  final String publisher;
  final String version;
  final String transport;
  final String executablePath;
  final String executableSha256;
  final List<String> arguments;
  final Set<String> tools;
  final Set<String> resources;
  final Set<String> prompts;
  final Set<String> roots;
  final Set<String> networkDestinations;
  final Set<String> secretIds;
  final int retentionDays;
  final McpExecutionModeV2 executionMode;

  factory McpServerDescriptorV2.fromPayload(Map<String, Object?> payload) {
    String requiredString(String key) {
      final value = payload[key]?.toString().trim() ?? '';
      if (value.isEmpty) throw FormatException('mcp_descriptor_$key_required');
      return value;
    }

    Set<String> strings(String key) {
      final raw = payload[key];
      if (raw == null) return const <String>{};
      if (raw is! List) throw FormatException('mcp_descriptor_$key_invalid');
      final values = raw.map((item) => item.toString().trim()).where((item) => item.isNotEmpty).toList();
      if (values.toSet().length != values.length) {
        throw FormatException('mcp_descriptor_${key}_duplicates');
      }
      return Set<String>.unmodifiable(values);
    }

    final mode = switch (requiredString('executionMode')) {
      'isolated' => McpExecutionModeV2.isolated,
      'owner_host' => McpExecutionModeV2.ownerHost,
      _ => throw const FormatException('mcp_descriptor_execution_mode_invalid'),
    };
    final executableSha256 = requiredString('executableSha256').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(executableSha256)) {
      throw const FormatException('mcp_descriptor_executable_digest_invalid');
    }
    final transport = requiredString('transport');
    if (transport != 'stdio') {
      throw const FormatException('mcp_descriptor_transport_unsupported');
    }
    final tools = strings('tools');
    if (tools.isEmpty) throw const FormatException('mcp_descriptor_tools_required');
    final rawArguments = payload['arguments'];
    if (rawArguments != null && rawArguments is! List) {
      throw const FormatException('mcp_descriptor_arguments_invalid');
    }
    final arguments = rawArguments is List
        ? rawArguments.map((item) => item.toString()).toList(growable: false)
        : const <String>[];
    if (arguments.any((argument) => argument.contains('\u0000'))) {
      throw const FormatException('mcp_descriptor_argument_nul');
    }
    final retention = int.tryParse(payload['retentionDays']?.toString() ?? '') ?? 0;
    if (retention < 0 || retention > 3650) {
      throw const FormatException('mcp_descriptor_retention_invalid');
    }
    return McpServerDescriptorV2(
      id: requiredString('id'),
      publisher: requiredString('publisher'),
      version: requiredString('version'),
      transport: transport,
      executablePath: requiredString('executablePath'),
      executableSha256: executableSha256,
      arguments: List<String>.unmodifiable(arguments),
      tools: tools,
      resources: strings('resources'),
      prompts: strings('prompts'),
      roots: strings('roots'),
      networkDestinations: strings('networkDestinations'),
      secretIds: strings('secretIds'),
      retentionDays: retention,
      executionMode: mode,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'publisher': publisher,
        'version': version,
        'transport': transport,
        'executablePath': executablePath,
        'executableSha256': executableSha256,
        'arguments': arguments,
        'tools': tools.toList()..sort(),
        'resources': resources.toList()..sort(),
        'prompts': prompts.toList()..sort(),
        'roots': roots.toList()..sort(),
        'networkDestinations': networkDestinations.toList()..sort(),
        'secretIds': secretIds.toList()..sort(),
        'retentionDays': retentionDays,
        'executionMode': executionMode == McpExecutionModeV2.isolated ? 'isolated' : 'owner_host',
      };
}

class McpRegistryRecordV2 {
  const McpRegistryRecordV2({
    required this.id,
    required this.projectId,
    required this.descriptor,
    required this.manifestSha256,
    required this.signerKeyId,
    required this.state,
    required this.installedAt,
    this.updatedAt,
  });

  final String id;
  final String projectId;
  final McpServerDescriptorV2 descriptor;
  final String manifestSha256;
  final String signerKeyId;
  final McpLifecycleStateV2 state;
  final DateTime installedAt;
  final DateTime? updatedAt;

  McpRegistryRecordV2 copyWith({McpLifecycleStateV2? state, DateTime? updatedAt}) => McpRegistryRecordV2(
        id: id,
        projectId: projectId,
        descriptor: descriptor,
        manifestSha256: manifestSha256,
        signerKeyId: signerKeyId,
        state: state ?? this.state,
        installedAt: installedAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'projectId': projectId,
        'descriptor': descriptor.toJson(),
        'manifestSha256': manifestSha256,
        'signerKeyId': signerKeyId,
        'state': state.name,
        'installedAt': installedAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };

  factory McpRegistryRecordV2.fromJson(Map<String, dynamic> json) => McpRegistryRecordV2(
        id: json['id']?.toString() ?? '',
        projectId: json['projectId']?.toString() ?? '',
        descriptor: McpServerDescriptorV2.fromPayload(
          Map<String, Object?>.from(json['descriptor'] as Map? ?? const <String, Object?>{}),
        ),
        manifestSha256: json['manifestSha256']?.toString() ?? '',
        signerKeyId: json['signerKeyId']?.toString() ?? '',
        state: McpLifecycleStateV2.values.firstWhere(
          (candidate) => candidate.name == json['state']?.toString(),
          orElse: () => McpLifecycleStateV2.disabled,
        ),
        installedAt: DateTime.parse(json['installedAt'].toString()).toUtc(),
        updatedAt: json['updatedAt'] == null ? null : DateTime.parse(json['updatedAt'].toString()).toUtc(),
      );
}

class McpExecutionGrantV2 {
  const McpExecutionGrantV2({
    required this.projectId,
    required this.serverId,
    required this.allowedTools,
    this.allowOwnerHostExecution = false,
  });

  final String projectId;
  final String serverId;
  final Set<String> allowedTools;
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
  Future<McpBackendReceiptV2> start({required McpRegistryRecordV2 record});
  Future<void> stop(String serverId);
  Future<bool> healthy(String serverId);
}

class McpUnavailableExecutionBackendV2 implements McpExecutionBackendV2 {
  const McpUnavailableExecutionBackendV2();

  @override
  bool get supportsIsolation => false;

  @override
  Future<McpBackendReceiptV2> start({required McpRegistryRecordV2 record}) {
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

class McpRegistryV2 {
  McpRegistryV2({
    required DurableWorkflowStore workflow,
    required this.audit,
    required Map<String, McpDescriptorTrustKeyV2> trustedKeys,
    McpExecutionBackendV2 backend = const McpUnavailableExecutionBackendV2(),
  })  : _trustedKeys = Map<String, McpDescriptorTrustKeyV2>.unmodifiable(trustedKeys),
        _backend = backend,
        _repository = SqliteEntityRepository<McpRegistryRecordV2>(
          store: workflow,
          collection: 'mcp_registry_v2',
          fromJson: McpRegistryRecordV2.fromJson,
          toJson: (value) => value.toJson(),
          idOf: (value) => value.id,
        );

  final AuditChain audit;
  final Map<String, McpDescriptorTrustKeyV2> _trustedKeys;
  final McpExecutionBackendV2 _backend;
  final EntityRepository<McpRegistryRecordV2> _repository;

  Future<McpRegistryRecordV2> install({
    required String projectId,
    required Map<String, Object?> signedManifest,
  }) async {
    final manifest = SignedManifestV2.fromJson(signedManifest);
    final body = manifest.body;
    if (body['schemaVersion'] != '2.0.0' ||
        body['intendedUse'] != 'mcp_server_descriptor' ||
        body['trustDomain'] != 'kristin.mcp') {
      throw ProductException('mcp_descriptor_manifest_scope_invalid', 'MCP descriptor manifest scope is invalid.');
    }
    final keyId = body['keyId']?.toString() ?? '';
    final key = _trustedKeys[keyId];
    if (key == null || key.revoked) {
      throw ProductException('mcp_descriptor_signer_untrusted', 'MCP descriptor signer is unknown or revoked.');
    }
    if (!manifest.verifyWithPublicKeyHex(key.publicKeyHex)) {
      throw ProductException('mcp_descriptor_signature_invalid', 'MCP descriptor signature verification failed.');
    }
    final now = DateTime.now().toUtc();
    final issuedAt = DateTime.tryParse(body['issuedAt']?.toString() ?? '')?.toUtc();
    final expiresAt = DateTime.tryParse(body['expiresAt']?.toString() ?? '')?.toUtc();
    if (issuedAt == null || expiresAt == null || issuedAt.isAfter(now) || !expiresAt.isAfter(now)) {
      throw ProductException('mcp_descriptor_manifest_expired', 'MCP descriptor manifest is not currently valid.');
    }
    final rawPayload = body['payload'];
    if (rawPayload is! Map) {
      throw ProductException('mcp_descriptor_payload_invalid', 'MCP descriptor payload must be an object.');
    }
    final payload = <String, Object?>{for (final entry in rawPayload.entries) entry.key.toString(): entry.value};
    if (payload['schemaVersion'] != '1.0.0') {
      throw ProductException('mcp_descriptor_payload_version_invalid', 'MCP descriptor payload version is unsupported.');
    }
    final descriptor = McpServerDescriptorV2.fromPayload(payload);
    final executable = File(descriptor.executablePath).absolute;
    if (!await executable.exists()) {
      throw ProductException('mcp_executable_missing', 'Registered MCP executable is unavailable.');
    }
    final canonicalPath = await executable.resolveSymbolicLinks();
    final digest = Sha256.hex(await File(canonicalPath).readAsBytes());
    if (!constantTimeEquals(digest, descriptor.executableSha256)) {
      throw ProductException('mcp_executable_changed', 'MCP executable digest does not match the signed descriptor.');
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
    final record = McpRegistryRecordV2(
      id: descriptor.id,
      projectId: projectId,
      descriptor: normalizedDescriptor,
      manifestSha256: Sha256.text(canonicalJsonV2(signedManifest)),
      signerKeyId: keyId,
      state: McpLifecycleStateV2.installed,
      installedAt: now,
    );
    await _repository.put(record);
    await audit.append('mcp.v2.installed', record.id, <String, dynamic>{
      'serverId': record.id,
      'projectId': projectId,
      'publisher': descriptor.publisher,
      'version': descriptor.version,
      'executionMode': descriptor.executionMode.name,
      'manifestSha256': record.manifestSha256,
    });
    return record;
  }

  Future<McpRegistryRecordV2?> get(String id) => _repository.get(id);
  Future<List<McpRegistryRecordV2>> all() => _repository.all();

  Future<McpRegistryRecordV2> enable(String id) => _transition(id, McpLifecycleStateV2.enabled, 'mcp.v2.enabled');

  Future<McpRegistryRecordV2> disable(String id) async {
    await _backend.stop(id);
    return _transition(id, McpLifecycleStateV2.disabled, 'mcp.v2.disabled');
  }

  Future<McpRegistryRecordV2> revoke(String id) async {
    await _backend.stop(id);
    return _transition(id, McpLifecycleStateV2.revoked, 'mcp.v2.revoked');
  }

  Future<void> remove(String id) async {
    final current = await _required(id);
    if (current.state != McpLifecycleStateV2.revoked && current.state != McpLifecycleStateV2.disabled) {
      throw ProductException('mcp_remove_requires_disabled', 'Disable or revoke the MCP server before removal.');
    }
    await _backend.stop(id);
    await _repository.remove(id);
    await audit.append('mcp.v2.removed', id, <String, dynamic>{'serverId': id});
  }

  Future<McpBackendReceiptV2> start({
    required String id,
    required McpExecutionGrantV2 grant,
  }) async {
    final record = await _required(id);
    if (record.state != McpLifecycleStateV2.enabled) {
      throw ProductException('mcp_server_not_enabled', 'MCP server must be enabled before start.');
    }
    if (grant.projectId != record.projectId || grant.serverId != record.id) {
      throw ProductException('mcp_execution_grant_mismatch', 'MCP execution grant identity mismatch.');
    }
    if (!record.descriptor.tools.containsAll(grant.allowedTools) || grant.allowedTools.isEmpty) {
      throw ProductException('mcp_execution_grant_scope_invalid', 'MCP execution grant exceeds the signed tool descriptor.');
    }
    if (record.descriptor.executionMode == McpExecutionModeV2.isolated && !_backend.supportsIsolation) {
      throw ProductException('mcp_isolation_backend_unavailable', 'Untrusted MCP server requires isolation; no isolation backend is available.');
    }
    if (record.descriptor.executionMode == McpExecutionModeV2.ownerHost && !grant.allowOwnerHostExecution) {
      throw ProductException('mcp_owner_host_grant_required', 'Owner-host MCP execution requires an explicit grant.');
    }
    final currentDigest = Sha256.hex(await File(record.descriptor.executablePath).readAsBytes());
    if (!constantTimeEquals(currentDigest, record.descriptor.executableSha256)) {
      await revoke(id);
      throw ProductException('mcp_executable_changed', 'MCP executable changed after trust and was revoked.');
    }
    final receipt = await _backend.start(record: record);
    final running = record.copyWith(state: McpLifecycleStateV2.running, updatedAt: DateTime.now().toUtc());
    await _repository.put(running);
    await audit.append('mcp.v2.started', id, <String, dynamic>{
      'serverId': id,
      'backend': receipt.backend,
      'executionMode': record.descriptor.executionMode.name,
      'allowedTools': grant.allowedTools.toList()..sort(),
    });
    return receipt;
  }

  Future<bool> health(String id) async {
    final current = await _required(id);
    if (current.state != McpLifecycleStateV2.running) return false;
    return _backend.healthy(id);
  }

  Future<McpRegistryRecordV2> _transition(String id, McpLifecycleStateV2 state, String action) async {
    final current = await _required(id);
    if (current.state == McpLifecycleStateV2.revoked && state != McpLifecycleStateV2.revoked) {
      throw ProductException('mcp_server_revoked', 'A revoked MCP server cannot be re-enabled.');
    }
    final next = current.copyWith(state: state, updatedAt: DateTime.now().toUtc());
    await _repository.put(next);
    await audit.append(action, id, <String, dynamic>{'serverId': id, 'state': state.name});
    return next;
  }

  Future<McpRegistryRecordV2> _required(String id) async {
    final record = await _repository.get(id);
    if (record == null) throw ProductException('mcp_server_unregistered', 'MCP server is not registered.');
    return record;
  }
}
