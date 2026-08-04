import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'crypto_utils.dart';
import 'domain.dart';
import 'durable_workflow.dart';
import 'repository.dart';
import 'storage_security.dart';

class McpTrustRecord {
  const McpTrustRecord({
    required this.id,
    required this.projectId,
    required this.label,
    required this.executablePath,
    required this.executableHash,
    required this.arguments,
    required this.allowedTools,
    required this.protocolVersion,
    required this.createdAt,
    required this.expiresAt,
    this.revokedAt,
  });

  final String id;
  final String projectId;
  final String label;
  final String executablePath;
  final String executableHash;
  final List<String> arguments;
  final Set<String> allowedTools;
  final String protocolVersion;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;

  bool get isActive =>
      revokedAt == null && expiresAt.isAfter(DateTime.now().toUtc());

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'projectId': projectId,
        'label': label,
        'executablePath': executablePath,
        'executableHash': executableHash,
        'arguments': arguments,
        'allowedTools': allowedTools.toList()..sort(),
        'protocolVersion': protocolVersion,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'revokedAt': revokedAt?.toUtc().toIso8601String(),
      };

  factory McpTrustRecord.fromJson(Map<String, dynamic> json) => McpTrustRecord(
        id: json['id']?.toString() ?? newId('mcp'),
        projectId: json['projectId']?.toString() ?? '',
        label: json['label']?.toString() ?? 'MCP server',
        executablePath: json['executablePath']?.toString() ?? '',
        executableHash: json['executableHash']?.toString() ?? '',
        arguments: stringList(json['arguments']),
        allowedTools: stringList(json['allowedTools']).toSet(),
        protocolVersion: json['protocolVersion']?.toString() ?? '2024-11-05',
        createdAt: parseUtc(json['createdAt'], fallback: DateTime.now()),
        expiresAt: parseUtc(json['expiresAt'], fallback: DateTime.now()),
        revokedAt:
            json['revokedAt'] == null ? null : parseUtc(json['revokedAt']),
      );
}

class McpTrustService {
  McpTrustService({
    required DurableWorkflowStore workflow,
    required this.audit,
    required this.redactor,
  }) : repository = SqliteEntityRepository<McpTrustRecord>(
          store: workflow,
          collection: 'mcp_trust',
          fromJson: McpTrustRecord.fromJson,
          toJson: (value) => value.toJson(),
          idOf: (value) => value.id,
        );

  final EntityRepository<McpTrustRecord> repository;
  final AuditChain audit;
  final SecretRedactor redactor;
  final Map<String, _McpSession> _sessions = <String, _McpSession>{};

  Future<McpTrustRecord> trust({
    required String projectId,
    required String label,
    required String executablePath,
    required List<String> arguments,
    required Set<String> allowedTools,
    String protocolVersion = '2024-11-05',
    Duration validity = const Duration(days: 30),
  }) async {
    final executable = File(executablePath).absolute;
    if (!await executable.exists()) {
      throw ProductException(
          'mcp_executable_missing', 'MCP executable does not exist.');
    }
    final canonical = await executable.resolveSymbolicLinks();
    if (allowedTools.isEmpty) {
      throw ProductException('mcp_tools_empty',
          'At least one exact MCP tool name must be allowed.');
    }
    if (arguments.any((argument) => argument.contains('\u0000'))) {
      throw ProductException(
          'mcp_argument_invalid', 'MCP arguments contain an invalid NUL byte.');
    }
    final now = DateTime.now().toUtc();
    final record = McpTrustRecord(
      id: newId('mcp'),
      projectId: projectId,
      label: label.trim().isEmpty
          ? executable.uri.pathSegments.last
          : label.trim(),
      executablePath: canonical,
      executableHash: Sha256.hex(await File(canonical).readAsBytes()),
      arguments: List<String>.unmodifiable(arguments),
      allowedTools: Set<String>.unmodifiable(allowedTools),
      protocolVersion: protocolVersion.trim(),
      createdAt: now,
      expiresAt: now.add(validity),
    );
    await repository.put(record);
    await audit.append('mcp.trusted', record.id, <String, dynamic>{
      'id': record.id,
      'projectId': projectId,
      'label': record.label,
      'executableHash': record.executableHash,
      'allowedTools': record.allowedTools.toList(),
      'expiresAt': record.expiresAt.toIso8601String(),
    });
    return record;
  }

  Future<void> revoke(String id) async {
    final record = await repository.get(id);
    if (record == null) {
      return;
    }
    await close(id);
    await repository.put(McpTrustRecord(
      id: record.id,
      projectId: record.projectId,
      label: record.label,
      executablePath: record.executablePath,
      executableHash: record.executableHash,
      arguments: record.arguments,
      allowedTools: record.allowedTools,
      protocolVersion: record.protocolVersion,
      createdAt: record.createdAt,
      expiresAt: record.expiresAt,
      revokedAt: DateTime.now().toUtc(),
    ));
    await audit.append('mcp.revoked', id, <String, dynamic>{'id': id});
  }

  Future<Map<String, dynamic>> call({
    required String trustId,
    required String projectId,
    required String tool,
    required Map<String, dynamic> arguments,
    required String workingDirectory,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final trust = await repository.get(trustId);
    if (trust == null || !trust.isActive) {
      throw ProductException(
          'mcp_trust_invalid', 'MCP trust is missing, expired, or revoked.');
    }
    if (trust.projectId != projectId) {
      throw ProductException(
          'mcp_project_mismatch', 'MCP trust belongs to another project.');
    }
    if (!trust.allowedTools.contains(tool)) {
      throw ProductException('mcp_tool_rejected',
          'MCP tool $tool is not in the trusted allowlist.');
    }
    final executable = File(trust.executablePath);
    if (!await executable.exists()) {
      throw ProductException(
          'mcp_executable_missing', 'Trusted MCP executable no longer exists.');
    }
    final currentHash = Sha256.hex(await executable.readAsBytes());
    if (!constantTimeEquals(currentHash, trust.executableHash)) {
      await close(trust.id);
      throw ProductException('mcp_executable_changed',
          'Trusted MCP executable hash changed; explicit re-approval is required.');
    }
    final session = await _session(trust, workingDirectory, timeout);
    final response = await session.request(
      'tools/call',
      <String, dynamic>{'name': tool, 'arguments': arguments},
      timeout: timeout,
    );
    await audit.append('mcp.tool_called', trust.id, <String, dynamic>{
      'projectId': projectId,
      'trustId': trust.id,
      'tool': tool,
      'arguments': redactor.redactJson(arguments),
      'responseHash': Sha256.text(canonicalJson(redactor.redactJson(response))),
    });
    return <String, dynamic>{
      'trustId': trust.id,
      'tool': tool,
      'trust': 'untrusted_mcp_output',
      'response': redactor.redactJson(response),
    };
  }

  Future<_McpSession> _session(
      McpTrustRecord trust, String workingDirectory, Duration timeout) async {
    final existing = _sessions[trust.id];
    if (existing != null && existing.running) {
      return existing;
    }
    final process = await Process.start(
      trust.executablePath,
      trust.arguments,
      workingDirectory: workingDirectory,
      environment: _safeEnvironment(),
      runInShell: false,
      mode: ProcessStartMode.normal,
    );
    final session = _McpSession(process, redactor);
    _sessions[trust.id] = session;
    process.exitCode.then((_) => _sessions.remove(trust.id));
    final initialized = await session.request(
      'initialize',
      <String, dynamic>{
        'protocolVersion': trust.protocolVersion,
        'capabilities': <String, dynamic>{},
        'clientInfo': <String, String>{
          'name': 'Kristin Local Agent',
          'version': kristinVersion
        },
      },
      timeout: timeout,
    );
    if (initialized['protocolVersion'] == null) {
      await session.close();
      _sessions.remove(trust.id);
      throw ProductException('mcp_initialize_invalid',
          'MCP server returned an invalid initialize result.');
    }
    await session
        .notify('notifications/initialized', const <String, dynamic>{});
    return session;
  }

  Future<void> close(String trustId) async {
    final session = _sessions.remove(trustId);
    await session?.close();
  }

  Future<void> closeAll() async {
    final sessions = _sessions.values.toList();
    _sessions.clear();
    for (final session in sessions) {
      await session.close();
    }
  }

  Map<String, String> _safeEnvironment() {
    const allowed = <String>{
      'PATH',
      'Path',
      'HOME',
      'USERPROFILE',
      'TMP',
      'TEMP',
      'TMPDIR',
      'SystemRoot',
      'WINDIR',
      'COMSPEC',
      'PATHEXT',
      'LANG',
      'LC_ALL',
      'XDG_CACHE_HOME',
      'XDG_CONFIG_HOME',
      'LOCALAPPDATA',
      'APPDATA',
    };
    return <String, String>{
      for (final entry in Platform.environment.entries)
        if (allowed.contains(entry.key)) entry.key: entry.value,
    };
  }
}

class _McpSession {
  _McpSession(this.process, this.redactor) {
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine,
            onError: _failAll,
            onDone: () => _failAll(ProductException(
                'mcp_closed', 'MCP server closed its output.')));
    _stderrSubscription =
        process.stderr.transform(utf8.decoder).listen((chunk) {
      final cleaned = redactor.redact(chunk);
      if (_stderr.length + cleaned.length <= 65536) {
        _stderr.write(cleaned);
      }
    });
  }

  final Process process;
  final SecretRedactor redactor;
  final Map<int, Completer<Map<String, dynamic>>> _pending =
      <int, Completer<Map<String, dynamic>>>{};
  final StringBuffer _stderr = StringBuffer();
  late final StreamSubscription<String> _stdoutSubscription;
  late final StreamSubscription<String> _stderrSubscription;
  var _nextId = 1;
  bool _closed = false;

  bool get running => !_closed;

  Future<Map<String, dynamic>> request(
      String method, Map<String, dynamic> params,
      {required Duration timeout}) async {
    if (_closed) {
      throw ProductException('mcp_closed', 'MCP session is closed.');
    }
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final message = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params
    };
    final encoded = jsonEncode(message);
    if (utf8.encode(encoded).length > 1024 * 1024) {
      throw ProductException(
          'mcp_request_too_large', 'MCP request exceeds 1 MiB.');
    }
    process.stdin.writeln(encoded);
    await process.stdin.flush();
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(id);
      throw ProductException('mcp_timeout', 'MCP request timed out.');
    }
  }

  Future<void> notify(String method, Map<String, dynamic> params) async {
    if (_closed) {
      return;
    }
    process.stdin.writeln(jsonEncode(<String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      'params': params
    }));
    await process.stdin.flush();
  }

  void _onLine(String line) {
    if (utf8.encode(line).length > 1024 * 1024) {
      _failAll(ProductException(
          'mcp_response_too_large', 'MCP response exceeds 1 MiB.'));
      return;
    }
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        return;
      }
      final message = mapValue(decoded);
      final id = int.tryParse(message['id']?.toString() ?? '');
      if (id == null) {
        return;
      }
      final completer = _pending.remove(id);
      if (completer == null) {
        return;
      }
      if (message['error'] != null) {
        completer.completeError(ProductException(
            'mcp_remote_error', 'MCP server returned an error.',
            details: mapValue(redactor.redactJson(message['error']))));
      } else {
        completer.complete(mapValue(redactor.redactJson(message['result'])));
      }
    } catch (error) {
      _failAll(ProductException(
          'mcp_response_invalid', 'MCP server returned invalid JSON.',
          details: <String, dynamic>{'error': '$error'}));
    }
  }

  void _failAll(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pending.clear();
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _failAll(ProductException('mcp_closed', 'MCP session closed.'));
    try {
      await process.stdin.close();
    } catch (_) {}
    process.kill(ProcessSignal.sigterm);
    try {
      await process.exitCode.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
    }
    await _stdoutSubscription.cancel();
    await _stderrSubscription.cancel();
  }
}
