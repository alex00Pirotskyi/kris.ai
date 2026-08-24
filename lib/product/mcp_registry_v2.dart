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
      if (value.isEmpty) {
        throw FormatException('mcp_descriptor_${key}_required');
      }
      return value;
    }

    Set<String> strings(String key) {
      final raw = payload[key];
      if (raw == null) {
        return const <String>{};
      }
      if (raw is! List) {
        throw FormatException('mcp_descriptor_${key}_invalid');
      }
      final values = raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
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
    if (tools.isEmpty) {
      throw const FormatException('mcp_descriptor_tools_required');
    }
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
    final retention =
        int.tryParse(payload['retentionDays']?.toString() ?? '') ?? 0;
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
        'executionMode': executionMode == McpExecutionModeV2.isolated
            ? 'isolated'
            : 'owner_host',
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

  McpRegistryRecordV2 copyWith(
          {McpLifecycleStateV2? state, DateTime? updatedAt}) =>
      McpRegistryRecordV2(
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

  factory McpRegistryRecordV2.fromJson(Map<String, dynamic> json) =>
      McpRegistryRecordV2(
        id: json['id']?.toString() ?? '',
        projectId: json['projectId']?.toString() ?? '',
        descriptor: McpServerDescriptorV2.fromPayload(
          Map<String, Object?>.from(
              json['descriptor'] as Map? ?? const <String, Object?>{}),
        ),
        manifestSha256: json['manifestSha256']?.toString() ?? '',
        signerKeyId: json['signerKeyId']?.toString() ?? '',
        state: McpLifecycleStateV2.values.firstWhere(
          (candidate) => candidate.name == json['state']?.toString(),
          orElse: () => McpLifecycleStateV2.disabled,
        ),
        installedAt: DateTime.parse(json['installedAt'].toString()).toUtc(),
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt'].toString()).toUtc(),
      );
}

class McpExecutionGrantV2 {
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

class McpRegistryV2 {
  McpRegistryV2({
    required DurableWorkflowStore workflow,
    required this.audit,
    required Map<String, McpDescriptorTrustKeyV2> trustedKeys,
    McpExecutionBackendV2 backend = const McpUnavailableExecutionBackendV2(),
  })  : _trustedKeys =
            Map<String, McpDescriptorTrustKeyV2>.unmodifiable(trustedKeys),
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

  Future<McpRegistryRecordV2> _validatedCandidate({
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
    final scopeChanged = !_setsEqual(
            candidate.descriptor.tools, current.descriptor.tools) ||
        !_setsEqual(
            candidate.descriptor.resources, current.descriptor.resources) ||
        !_setsEqual(candidate.descriptor.prompts, current.descriptor.prompts) ||
        !_setsEqual(candidate.descriptor.roots, current.descriptor.roots) ||
        !_setsEqual(
          candidate.descriptor.networkDestinations,
          current.descriptor.networkDestinations,
        ) ||
        !_setsEqual(
            candidate.descriptor.secretIds, current.descriptor.secretIds) ||
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

  Future<McpRegistryRecordV2?> get(String id) => _repository.get(id);
  Future<List<McpRegistryRecordV2>> all() => _repository.all();

  Future<McpRegistryRecordV2> enable(String id) async {
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

  Future<McpBackendReceiptV2> start({
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

  Future<bool> health(String id) async {
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

  Future<McpRegistryRecordV2> _required(String id) async {
    final record = await _repository.get(id);
    if (record == null) {
      throw ProductException(
          'mcp_server_unregistered', 'MCP server is not registered.');
    }
    return record;
  }
}
