import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'crypto_utils.dart';
import 'domain.dart';
import 'durable_workflow.dart';
import 'extensions_index.dart';
import 'deployment_support.dart';
import 'models_research.dart';
import 'research_search_provider.dart';
import 'mcp.dart';
import 'product_error_normalizer.dart';
import 'process_launch.dart';
import 'retry_policy.dart';
import 'storage_security.dart';
import 'tool_schema.dart';

/// Canonicalizes a model-emitted path token without granting any additional
/// filesystem authority. Models frequently wrap paths in quotes or Markdown
/// inline-code fences. Those wrappers are presentation syntax, not filename
/// characters, when they surround the entire scalar value.
String canonicalModelPathToken(String input) {
  var value = input.trim();
  for (var pass = 0; pass < 4; pass++) {
    final before = value;
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1).trim();
    } else {
      final leadingTicks = _edgeBacktickRun(value, fromStart: true);
      final trailingTicks = _edgeBacktickRun(value, fromStart: false);
      if (leadingTicks == trailingTicks &&
          leadingTicks >= 1 &&
          leadingTicks <= 3 &&
          value.length >= leadingTicks * 2) {
        final inner = value.substring(
          leadingTicks,
          value.length - trailingTicks,
        );
        if (!inner.contains('\n') && !inner.contains('\r')) {
          value = inner.trim();
        }
      }
    }
    if (value == before) {
      break;
    }
  }
  return value;
}

int _edgeBacktickRun(String value, {required bool fromStart}) {
  var count = 0;
  if (fromStart) {
    while (count < value.length && value[count] == '`') {
      count++;
    }
    return count;
  }
  var index = value.length - 1;
  while (index >= 0 && value[index] == '`') {
    count++;
    index--;
  }
  return count;
}

class WorkspacePathRecovery {
  const WorkspacePathRecovery({required this.path, required this.strategy});

  final String path;
  final String strategy;
}

class WorkspaceBoundary {
  WorkspaceBoundary._(this.root, this._canonicalRoot);

  final Directory root;
  final String _canonicalRoot;

  static Future<WorkspaceBoundary> open(String rootPath) async {
    final root = Directory(rootPath).absolute;
    if (!await root.exists()) {
      throw ProductException(
        'project_missing',
        'Project root does not exist: ${root.path}',
      );
    }
    final canonical = await root.resolveSymbolicLinks();
    return WorkspaceBoundary._(
      Directory(canonical),
      _normalizeAbsolute(canonical),
    );
  }

  Future<bool> isKristinSourceCheckout() async {
    final pubspec = File('${root.path}${Platform.pathSeparator}pubspec.yaml');
    final runtime = File(
      '${root.path}${Platform.pathSeparator}lib'
      '${Platform.pathSeparator}product'
      '${Platform.pathSeparator}product_runtime.dart',
    );
    final coordinator = File(
      '${root.path}${Platform.pathSeparator}lib'
      '${Platform.pathSeparator}product'
      '${Platform.pathSeparator}planning_runtime.dart',
    );
    if (!await pubspec.exists() ||
        !await runtime.exists() ||
        !await coordinator.exists()) {
      return false;
    }
    final length = await pubspec.length();
    if (length <= 0 || length > 1024 * 1024) {
      return false;
    }
    final content = await pubspec.readAsString();
    return RegExp(
      r'^name:\s*kristin_local_agent\s*$',
      multiLine: true,
    ).hasMatch(content);
  }

  String normalizeToolPath(String input) {
    var raw = canonicalModelPathToken(input);
    if (raw.isEmpty || raw == '.') {
      return '.';
    }
    if (raw.contains('\u0000')) {
      throw ProductException(
        'path_nul_rejected',
        'NUL bytes are not allowed in paths.',
      );
    }

    if (raw.toLowerCase().startsWith('file:')) {
      final uri = Uri.tryParse(raw);
      if (uri == null ||
          uri.scheme.toLowerCase() != 'file' ||
          (uri.host.isNotEmpty && uri.host.toLowerCase() != 'localhost')) {
        throw ProductException(
          'path_scheme_rejected',
          'Only local file URIs that resolve inside the active project are allowed.',
        );
      }
      try {
        raw = uri.toFilePath(windows: Platform.isWindows);
      } on UnsupportedError {
        throw ProductException(
          'path_scheme_rejected',
          'The file URI is not valid on this platform.',
        );
      }
    } else {
      final uri = Uri.tryParse(raw);
      final windowsAbsolute = RegExp(r'^[A-Za-z]:[/\\]').hasMatch(raw);
      if (!windowsAbsolute && uri != null && uri.hasScheme) {
        throw ProductException(
          'path_scheme_rejected',
          'URI paths are not allowed.',
        );
      }
    }

    final clean = raw.replaceAll('\\', '/');
    final rawSegments = clean.split('/');
    if (rawSegments.any((segment) => segment == '..')) {
      throw ProductException(
        'path_traversal_rejected',
        'Parent-directory traversal is not allowed in tool paths.',
      );
    }
    final windowsAbsolute = RegExp(r'^[A-Za-z]:/').hasMatch(clean);
    final absolute = clean.startsWith('/') || windowsAbsolute;
    if (absolute) {
      if (windowsAbsolute && !Platform.isWindows) {
        throw ProductException(
          'path_absolute_rejected',
          'A Windows absolute path cannot be resolved on this platform.',
        );
      }
      final normalized = _normalizeAbsolute(raw);
      try {
        _assertWithin(normalized);
      } on ProductException {
        throw ProductException(
          'path_outside_project',
          'The absolute tool path is outside the active project. Use a path inside the selected project.',
          details: <String, dynamic>{
            'inputPathHash': Sha256.text(raw),
            'activeProjectRootHash': Sha256.text(_canonicalRoot),
          },
        );
      }
      return relative(normalized);
    }

    final segments = rawSegments
        .where((segment) => segment.isNotEmpty && segment != '.')
        .toList(growable: false);
    if (segments.isEmpty) {
      return '.';
    }
    return segments.join('/');
  }

  Future<WorkspacePathRecovery?> recoverExternalToolPath(
    String input, {
    required bool allowMissing,
    required bool allowRootFallback,
    required bool allowUnanchoredExistingSuffix,
  }) async {
    try {
      normalizeToolPath(input);
      return null;
    } on ProductException catch (error) {
      if (!const <String>{
        'path_outside_project',
        'path_absolute_rejected',
      }.contains(error.code)) {
        rethrow;
      }
    }

    final portable = _portableExternalPath(input);
    if (portable == null) {
      return allowRootFallback
          ? const WorkspacePathRecovery(
              path: '.',
              strategy: 'active_project_root',
            )
          : null;
    }
    final rawSegments = portable
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    final segments = rawSegments.isNotEmpty &&
            RegExp(r'^[A-Za-z]:$').hasMatch(rawSegments.first)
        ? rawSegments.sublist(1)
        : rawSegments;
    if (segments.isEmpty) {
      return allowRootFallback
          ? const WorkspacePathRecovery(
              path: '.',
              strategy: 'active_project_root',
            )
          : null;
    }

    Future<WorkspacePathRecovery?> validated(
      Iterable<String> candidateSegments,
      String strategy, {
      bool? candidateAllowMissing,
    }) async {
      var candidate = candidateSegments
          .where((segment) => segment.isNotEmpty && segment != '.')
          .join('/');
      candidate = candidate.isEmpty ? '.' : candidate;
      if (candidate != '.' && _looksSensitiveRecoveryPath(candidate)) {
        return null;
      }
      late String normalized;
      try {
        normalized = normalizeToolPath(candidate);
        await resolve(
          normalized,
          allowMissing: candidateAllowMissing ?? allowMissing,
        );
      } on ProductException {
        return null;
      }
      return WorkspacePathRecovery(path: normalized, strategy: strategy);
    }

    final rootSegments = _canonicalRoot
        .split('/')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final rootName = rootSegments.isEmpty ? '' : rootSegments.last;
    final rootIndex = segments.lastIndexWhere(
      (segment) => _case(segment) == _case(rootName),
    );
    if (rootName.isNotEmpty && rootIndex >= 0) {
      final anchored = await validated(
        segments.skip(rootIndex + 1),
        'project_name_anchor',
      );
      if (anchored != null) {
        return anchored;
      }
    }

    const aliases = <String>{
      'workspace',
      'workspaces',
      'project',
      'repo',
      'repository',
      'app',
    };
    final aliasIndex = segments.lastIndexWhere(
      (segment) => aliases.contains(segment.toLowerCase()),
    );
    if (aliasIndex >= 0) {
      final suffix = segments.skip(aliasIndex + 1).toList();
      while (suffix.isNotEmpty &&
          (aliases.contains(suffix.first.toLowerCase()) ||
              _case(suffix.first) == _case(rootName))) {
        suffix.removeAt(0);
      }
      final virtual = await validated(suffix, 'virtual_workspace_alias');
      if (virtual != null) {
        return virtual;
      }
    }

    if (allowUnanchoredExistingSuffix) {
      final maximumDepth = min(6, segments.length);
      for (var depth = maximumDepth; depth >= 1; depth--) {
        final suffix = segments.sublist(segments.length - depth);
        final recovered = await validated(
          suffix,
          'existing_project_suffix',
          candidateAllowMissing: false,
        );
        if (recovered != null) {
          return recovered;
        }
      }
    }

    if (allowRootFallback) {
      return const WorkspacePathRecovery(
        path: '.',
        strategy: 'active_project_root',
      );
    }
    return null;
  }

  Future<FileSystemEntity> resolve(
    String relativePath, {
    bool allowMissing = false,
  }) async {
    final clean = normalizeToolPath(relativePath);
    if (clean == '.') {
      return root;
    }
    final segments = clean.split('/');
    final candidate = File(
      '${root.path}${Platform.pathSeparator}${segments.join(Platform.pathSeparator)}',
    ).absolute;
    final type = await FileSystemEntity.type(
      candidate.path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.notFound) {
      final canonical = await _resolveExistingEntityPath(candidate.path);
      _assertWithin(canonical);
      return _entityFor(type, canonical);
    }
    if (!allowMissing) {
      throw ProductException(
        'path_missing',
        'Project path does not exist: $relativePath',
      );
    }

    var ancestor = candidate.parent;
    final tail = <String>[
      candidate.uri.pathSegments.where((item) => item.isNotEmpty).last,
    ];
    while (!await ancestor.exists()) {
      if (_samePath(ancestor.path, ancestor.parent.path)) {
        throw ProductException(
          'path_parent_missing',
          'No existing parent could be found for $relativePath.',
        );
      }
      tail.insert(
        0,
        ancestor.uri.pathSegments.where((item) => item.isNotEmpty).last,
      );
      ancestor = ancestor.parent;
    }
    final canonicalAncestor = await ancestor.resolveSymbolicLinks();
    _assertWithin(canonicalAncestor);
    final reconstructed =
        '$canonicalAncestor${Platform.pathSeparator}${tail.join(Platform.pathSeparator)}';
    _assertWithin(reconstructed);
    return File(reconstructed);
  }

  Future<File> file(String relativePath, {bool allowMissing = false}) async {
    final entity = await resolve(relativePath, allowMissing: allowMissing);
    if (entity is Directory) {
      throw ProductException('path_not_file', '$relativePath is a directory.');
    }
    return File(entity.path);
  }

  Future<Directory> directory(
    String relativePath, {
    bool allowMissing = false,
  }) async {
    final entity = await resolve(relativePath, allowMissing: allowMissing);
    if (await FileSystemEntity.type(entity.path, followLinks: false) ==
        FileSystemEntityType.file) {
      throw ProductException('path_not_directory', '$relativePath is a file.');
    }
    return Directory(entity.path);
  }

  String relative(String absolutePath) {
    final normalized = _normalizeAbsolute(absolutePath);
    _assertWithin(normalized);
    if (_samePath(normalized, _canonicalRoot)) {
      return '.';
    }
    final suffix = normalized.substring(_canonicalRoot.length);
    return suffix.replaceFirst(RegExp(r'^[/\\]+'), '').replaceAll('\\', '/');
  }

  void _assertWithin(String path) {
    final normalized = _normalizeAbsolute(path);
    final rootWithSeparator = '$_canonicalRoot/';
    if (!_samePath(normalized, _canonicalRoot) &&
        !_case(normalized).startsWith(_case(rootWithSeparator))) {
      throw ProductException(
        'workspace_escape_rejected',
        'The requested path escapes the active project.',
      );
    }
  }

  static FileSystemEntity _entityFor(FileSystemEntityType type, String path) {
    if (type == FileSystemEntityType.directory) {
      return Directory(path);
    }
    if (type == FileSystemEntityType.link) {
      return Link(path);
    }
    return File(path);
  }

  static String? _portableExternalPath(String input) {
    var raw = canonicalModelPathToken(input);
    if (raw.toLowerCase().startsWith('file:')) {
      final uri = Uri.tryParse(raw);
      if (uri == null ||
          uri.scheme.toLowerCase() != 'file' ||
          (uri.host.isNotEmpty && uri.host.toLowerCase() != 'localhost')) {
        return null;
      }
      try {
        raw = uri.toFilePath(windows: Platform.isWindows);
      } on UnsupportedError {
        return null;
      }
    }
    final portable = raw.replaceAll('\\', '/');
    final windowsAbsolute = RegExp(r'^[A-Za-z]:/').hasMatch(portable);
    if (!portable.startsWith('/') && !windowsAbsolute) {
      return null;
    }
    if (portable.split('/').any((segment) => segment == '..')) {
      return null;
    }
    return portable;
  }

  static bool _looksSensitiveRecoveryPath(String path) {
    final lower = path.toLowerCase().replaceAll('\\', '/');
    final segments = lower.split('/');
    if (segments.any(
      (segment) => segment.startsWith('.') && segment != '.' && segment != '..',
    )) {
      return true;
    }
    return RegExp(
      r'(^|[/_.-])(secret|secrets|credential|credentials|password|passwd|token|tokens|private|id_rsa|api[_-]?key|\.env)([/_.-]|$)',
    ).hasMatch(lower);
  }

  static String _normalizeAbsolute(String path) {
    var absolute = File(path).absolute.path;
    // Resolve existing files, directories, and reparse-point links before
    // comparing them with the canonical project root. Windows runners can
    // expose the same temporary directory through long-name, short-name, or
    // reparse aliases; lexical comparison alone can reject a valid path.
    try {
      final type = FileSystemEntity.typeSync(absolute, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        absolute = Directory(absolute).resolveSymbolicLinksSync();
      } else if (type == FileSystemEntityType.file) {
        absolute = File(absolute).resolveSymbolicLinksSync();
      } else if (type == FileSystemEntityType.link) {
        absolute = Link(absolute).resolveSymbolicLinksSync();
      }
    } on FileSystemException {
      // Missing mutation targets remain lexical and are still checked against
      // the already-canonical project root by _assertWithin.
    }

    var normalized = absolute.replaceAll('\\', '/');
    // Windows canonicalization can return an extended-length path such as
    // \\?\C:\project or \\?\UNC\server\share. Model and filesystem
    // tool paths normally use the equivalent plain form. Normalize both
    // representations before enforcing the project boundary so a legitimate
    // in-project path is not rejected solely because one side crossed a
    // reparse point while resolving symbolic links.
    if (normalized.startsWith('//?/')) {
      normalized = normalized.substring(4);
      if (normalized.toUpperCase().startsWith('UNC/')) {
        normalized = '//${normalized.substring(4)}';
      }
    }
    if (normalized == '/' || RegExp(r'^[A-Za-z]:/$').hasMatch(normalized)) {
      return normalized;
    }
    return normalized.replaceAll(RegExp(r'/+$'), '');
  }

  static String _case(String path) =>
      Platform.isWindows ? path.toLowerCase() : path;
  static bool _samePath(String a, String b) =>
      _case(_normalizeAbsolute(a)) == _case(_normalizeAbsolute(b));
}

class MutationRecord {
  const MutationRecord({
    required this.id,
    required this.operation,
    required this.relativePath,
    required this.existed,
    required this.beforeHash,
    required this.afterHash,
    required this.backupPath,
    required this.timestamp,
    this.status = 'applied',
    this.idempotencyKey = '',
    this.workItemId = '',
  });

  final String id;
  final String operation;
  final String relativePath;
  final bool existed;
  final String beforeHash;
  final String afterHash;
  final String backupPath;
  final DateTime timestamp;
  final String status;
  final String idempotencyKey;
  final String workItemId;

  MutationRecord copyWith({String? status}) => MutationRecord(
        id: id,
        operation: operation,
        relativePath: relativePath,
        existed: existed,
        beforeHash: beforeHash,
        afterHash: afterHash,
        backupPath: backupPath,
        timestamp: timestamp,
        status: status ?? this.status,
        idempotencyKey: idempotencyKey,
        workItemId: workItemId,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'operation': operation,
        'relativePath': relativePath,
        'existed': existed,
        'beforeHash': beforeHash,
        'afterHash': afterHash,
        'backupPath': backupPath,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'status': status,
        if (idempotencyKey.isNotEmpty) 'idempotencyKey': idempotencyKey,
        if (workItemId.isNotEmpty) 'workItemId': workItemId,
      };

  factory MutationRecord.fromJson(Map<String, dynamic> json) => MutationRecord(
        id: json['id']?.toString() ?? newId('mutation'),
        operation: json['operation']?.toString() ?? '',
        relativePath: json['relativePath']?.toString() ?? '',
        existed: json['existed'] == true,
        beforeHash: json['beforeHash']?.toString() ?? '',
        afterHash: json['afterHash']?.toString() ?? '',
        backupPath: json['backupPath']?.toString() ?? '',
        timestamp: parseUtc(json['timestamp'], fallback: DateTime.now()),
        status: json['status']?.toString() ?? 'applied',
        idempotencyKey: json['idempotencyKey']?.toString() ?? '',
        workItemId: json['workItemId']?.toString() ?? '',
      );
}

class WorkspaceTransaction {
  WorkspaceTransaction._({
    required this.runId,
    required this.boundary,
    required this.directory,
    required this.audit,
    required this.workflow,
  });

  final String runId;
  final WorkspaceBoundary boundary;
  final Directory directory;
  final AuditChain audit;
  final DurableWorkflowStore? workflow;
  final List<MutationRecord> _records = <MutationRecord>[];
  final Map<String, MutationRecord> _latest = <String, MutationRecord>{};
  bool _committed = false;
  String _activeOperationKey = '';
  String _activeWorkItemId = '';

  File get _journal =>
      File('${directory.path}${Platform.pathSeparator}journal.jsonl');
  File get _committedMarker =>
      File('${directory.path}${Platform.pathSeparator}COMMITTED');
  File get _rolledBackMarker =>
      File('${directory.path}${Platform.pathSeparator}ROLLED_BACK');

  static Future<WorkspaceTransaction> begin({
    required String runId,
    required WorkspaceBoundary boundary,
    required Directory checkpointRoot,
    required AuditChain audit,
    DurableWorkflowStore? workflow,
  }) async {
    final directory = Directory(
      '${checkpointRoot.path}${Platform.pathSeparator}$runId',
    );
    await directory.create(recursive: true);
    final transaction = WorkspaceTransaction._(
      runId: runId,
      boundary: boundary,
      directory: directory,
      audit: audit,
      workflow: workflow,
    );
    if (await transaction._journal.exists()) {
      for (final line in await transaction._journal.readAsLines()) {
        if (line.trim().isEmpty) {
          continue;
        }
        try {
          final decoded = jsonDecode(line);
          if (decoded is Map) {
            final record = MutationRecord.fromJson(mapValue(decoded));
            transaction._latest[record.id] = record;
          }
        } catch (_) {
          throw ProductException(
            'transaction_journal_corrupt',
            'The mutation journal for run $runId contains invalid data.',
          );
        }
      }
    }
    transaction._committed = await transaction._committedMarker.exists();
    if (!transaction._committed &&
        !await transaction._rolledBackMarker.exists()) {
      for (final record in transaction._latest.values.toList()) {
        if (record.status == 'prepared') {
          await transaction._recoverPrepared(record);
        }
      }
    }
    transaction._rebuildAppliedRecords();
    return transaction;
  }

  int get mutationCount => _records.length;
  bool get isCommitted => _committed;

  Future<T> runOperation<T>({
    required String idempotencyKey,
    required String workItemId,
    required Future<T> Function() action,
  }) async {
    if (_activeOperationKey.isNotEmpty) {
      throw ProductException(
        'transaction_operation_nested',
        'Workspace operations cannot be nested.',
      );
    }
    _activeOperationKey = idempotencyKey;
    _activeWorkItemId = workItemId;
    try {
      return await action();
    } finally {
      _activeOperationKey = '';
      _activeWorkItemId = '';
    }
  }

  Future<MutationRecord> writeText({
    required String relativePath,
    required String content,
    String? expectedHash,
    bool? expectedExists,
  }) =>
      writeBytes(
        relativePath: relativePath,
        bytes: utf8.encode(content),
        expectedHash: expectedHash,
        expectedExists: expectedExists,
      );

  Future<MutationRecord> writeBytes({
    required String relativePath,
    required List<int> bytes,
    String? expectedHash,
    bool? expectedExists,
  }) async {
    _ensureOpen();
    final file = await boundary.file(relativePath, allowMissing: true);
    final existed = await file.exists();
    if (expectedExists != null && existed != expectedExists) {
      throw ProductException(
        'stale_existence',
        expectedExists
            ? 'The file no longer exists at the approved path.'
            : 'The file already exists and must be inspected before replacement.',
        details: <String, dynamic>{
          'path': relativePath,
          'expectedExists': expectedExists,
          'actualExists': existed,
        },
      );
    }
    final beforeBytes = existed ? await file.readAsBytes() : <int>[];
    final beforeHash = existed ? Sha256.hex(beforeBytes) : '';
    if (expectedHash != null &&
        expectedHash.isNotEmpty &&
        !constantTimeEquals(beforeHash, expectedHash)) {
      throw ProductException(
        'stale_content',
        'The file changed after it was read.',
        details: <String, dynamic>{
          'path': relativePath,
          'expectedHash': expectedHash,
          'actualHash': beforeHash,
        },
      );
    }
    final afterHash = Sha256.hex(bytes);
    if (existed && constantTimeEquals(beforeHash, afterHash)) {
      final record = MutationRecord(
        id: newId('mutation'),
        operation: 'noop',
        relativePath: relativePath.replaceAll('\\', '/'),
        existed: true,
        beforeHash: beforeHash,
        afterHash: afterHash,
        backupPath: '',
        timestamp: DateTime.now().toUtc(),
        status: 'committed',
        idempotencyKey: _activeOperationKey,
        workItemId: _activeWorkItemId,
      );
      await audit.append('workspace.mutation_noop', runId, record.toJson());
      return record;
    }
    final backupPath = await _backup(relativePath, beforeBytes, existed);
    final record = MutationRecord(
      id: newId('mutation'),
      operation: existed ? 'replace' : 'create',
      relativePath: relativePath.replaceAll('\\', '/'),
      existed: existed,
      beforeHash: beforeHash,
      afterHash: afterHash,
      backupPath: backupPath,
      timestamp: DateTime.now().toUtc(),
      status: 'prepared',
      idempotencyKey: _activeOperationKey,
      workItemId: _activeWorkItemId,
    );
    await _setStatus(record, 'prepared');
    final temporary = File('${file.path}.kristin-${newId('tmp')}');
    try {
      await file.parent.create(recursive: true);
      await temporary.writeAsBytes(bytes, flush: true);
      if (Platform.isWindows && await file.exists()) {
        await file.delete();
      }
      await temporary.rename(file.path);
      final applied = await _setStatus(record, 'applied');
      await audit.append('workspace.mutated', runId, applied.toJson());
      return applied;
    } catch (_) {
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {
          // Best effort; state reconciliation relies on hashes, not temp files.
        }
      }
      await _markAbandonedIfUnchanged(record);
      rethrow;
    }
  }

  Future<MutationRecord> delete({
    required String relativePath,
    String? expectedHash,
  }) async {
    _ensureOpen();
    final file = await boundary.file(relativePath);
    if (!await file.exists()) {
      throw ProductException('path_missing', '$relativePath does not exist.');
    }
    final beforeBytes = await file.readAsBytes();
    final beforeHash = Sha256.hex(beforeBytes);
    if (expectedHash != null &&
        expectedHash.isNotEmpty &&
        !constantTimeEquals(beforeHash, expectedHash)) {
      throw ProductException(
        'stale_content',
        'The file changed after it was read.',
      );
    }
    final backupPath = await _backup(relativePath, beforeBytes, true);
    final record = MutationRecord(
      id: newId('mutation'),
      operation: 'delete',
      relativePath: relativePath.replaceAll('\\', '/'),
      existed: true,
      beforeHash: beforeHash,
      afterHash: '',
      backupPath: backupPath,
      timestamp: DateTime.now().toUtc(),
      status: 'prepared',
      idempotencyKey: _activeOperationKey,
      workItemId: _activeWorkItemId,
    );
    await _setStatus(record, 'prepared');
    try {
      await file.delete();
      final applied = await _setStatus(record, 'applied');
      await audit.append('workspace.mutated', runId, applied.toJson());
      return applied;
    } catch (_) {
      await _markAbandonedIfUnchanged(record);
      rethrow;
    }
  }

  Future<void> commit() async {
    _ensureOpen();
    for (final record in _records.toList(growable: false)) {
      if (record.status == 'applied') {
        await _setStatus(record, 'committed');
      }
    }
    await _committedMarker.writeAsString(
      DateTime.now().toUtc().toIso8601String(),
      flush: true,
    );
    _committed = true;
    await workflow?.createCheckpoint(
      runId: runId,
      kind: 'workspace_committed',
      state: <String, dynamic>{
        'runId': runId,
        'mutations': _records.map((record) => record.toJson()).toList(),
      },
    );
    await audit.append(
      'workspace.transaction_committed',
      runId,
      <String, dynamic>{'mutations': _records.length},
    );
  }

  Future<void> rollback() async {
    if (_committed) {
      throw ProductException(
        'transaction_committed',
        'A committed transaction cannot be rolled back automatically.',
      );
    }
    for (final record in _records.reversed.toList(growable: false)) {
      if (record.status != 'applied' && record.status != 'committed') {
        continue;
      }
      try {
        final file = await boundary.file(
          record.relativePath,
          allowMissing: true,
        );
        if (record.existed) {
          final backup = File(record.backupPath);
          if (!await backup.exists()) {
            throw ProductException(
              'checkpoint_missing',
              'Checkpoint data is missing for ${record.relativePath}.',
            );
          }
          await file.parent.create(recursive: true);
          final temporary = File('${file.path}.rollback-${newId('tmp')}');
          await backup.copy(temporary.path);
          if (Platform.isWindows && await file.exists()) {
            await file.delete();
          }
          await temporary.rename(file.path);
        } else if (await file.exists()) {
          await file.delete();
        }
        await _setStatus(record, 'rolled_back');
      } catch (error) {
        await _setStatus(record, 'rollback_failed');
        rethrow;
      }
    }
    await _rolledBackMarker.writeAsString(
      DateTime.now().toUtc().toIso8601String(),
      flush: true,
    );
    await workflow?.createCheckpoint(
      runId: runId,
      kind: 'workspace_rolled_back',
      state: <String, dynamic>{
        'runId': runId,
        'mutations': _latest.values.map((record) => record.toJson()).toList(),
      },
    );
    await audit.append(
      'workspace.transaction_rolled_back',
      runId,
      <String, dynamic>{'mutations': _records.length},
    );
  }

  Future<void> _recoverPrepared(MutationRecord record) async {
    final file = await boundary.file(record.relativePath, allowMissing: true);
    final exists = await file.exists();
    final currentHash = exists ? Sha256.hex(await file.readAsBytes()) : '';
    final effectApplied = record.operation == 'delete'
        ? !exists
        : exists && constantTimeEquals(currentHash, record.afterHash);
    final stateUnchanged = record.operation == 'create'
        ? !exists
        : exists && constantTimeEquals(currentHash, record.beforeHash);
    if (effectApplied) {
      await _setStatus(record, 'applied');
      await audit.append(
        'workspace.mutation_recovered',
        runId,
        <String, dynamic>{...record.toJson(), 'recoveredStatus': 'applied'},
      );
      return;
    }
    if (stateUnchanged) {
      await _setStatus(record, 'abandoned');
      return;
    }
    throw ProductException(
      'transaction_recovery_required',
      'A prepared mutation has an ambiguous filesystem state and cannot be replayed or rolled back automatically.',
      details: <String, dynamic>{
        'runId': runId,
        'mutationId': record.id,
        'path': record.relativePath,
        'operation': record.operation,
        'beforeHash': record.beforeHash,
        'afterHash': record.afterHash,
        'currentHash': currentHash,
        'exists': exists,
      },
    );
  }

  Future<void> _markAbandonedIfUnchanged(MutationRecord record) async {
    final file = await boundary.file(record.relativePath, allowMissing: true);
    final exists = await file.exists();
    final currentHash = exists ? Sha256.hex(await file.readAsBytes()) : '';
    final unchanged = record.operation == 'create'
        ? !exists
        : exists && constantTimeEquals(currentHash, record.beforeHash);
    if (unchanged) {
      await _setStatus(record, 'abandoned');
    }
  }

  Future<String> _backup(
    String relativePath,
    List<int> bytes,
    bool existed,
  ) async {
    if (!existed) {
      return '';
    }
    final name = '${_latest.length.toString().padLeft(6, '0')}-'
        '${Sha256.text(relativePath).substring(0, 16)}.bak';
    final backup = File('${directory.path}${Platform.pathSeparator}$name');
    await backup.writeAsBytes(bytes, flush: true);
    return backup.path;
  }

  Future<MutationRecord> _setStatus(
    MutationRecord source,
    String status,
  ) async {
    final record = source.copyWith(status: status);
    _latest[record.id] = record;
    await _journal.writeAsString(
      '${jsonEncode(record.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
    await workflow?.recordCompensation(
      runId: runId,
      mutationId: record.id,
      operation: record.operation,
      relativePath: record.relativePath,
      status: status,
      record: record.toJson(),
      workItemId: record.workItemId.isEmpty ? null : record.workItemId,
      idempotencyKey:
          record.idempotencyKey.isEmpty ? null : record.idempotencyKey,
      beforeSha256: record.beforeHash.isEmpty ? null : record.beforeHash,
      afterSha256: record.afterHash.isEmpty ? null : record.afterHash,
      backupPath: record.backupPath.isEmpty ? null : record.backupPath,
      rollbackResult: const <String, dynamic>{},
    );
    _rebuildAppliedRecords();
    if (status == 'prepared' || status == 'applied') {
      await workflow?.createCheckpoint(
        runId: runId,
        workItemId: record.workItemId.isEmpty ? null : record.workItemId,
        kind: 'mutation_$status',
        state: record.toJson(),
      );
    }
    return record;
  }

  void _rebuildAppliedRecords() {
    _records
      ..clear()
      ..addAll(
        _latest.values.where(
          (record) =>
              record.status == 'applied' || record.status == 'committed',
        ),
      );
    _records.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  void _ensureOpen() {
    if (_committed) {
      throw ProductException(
        'transaction_closed',
        'The transaction is already committed.',
      );
    }
  }
}

class CancellationSignal {
  bool _cancelled = false;
  final Completer<void> _completer = Completer<void>();

  bool get isCancelled => _cancelled;
  Future<void> get cancelled => _completer.future;

  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    _completer.complete();
  }

  void throwIfCancelled() {
    if (_cancelled) {
      throw ProductException('cancelled', 'Execution was cancelled.');
    }
  }
}

class ManagedProcessService {
  ManagedProcessService({required this.logDirectory, required this.redactor});

  final Directory logDirectory;
  final SecretRedactor redactor;
  final Map<String, _ManagedProcess> _processes = <String, _ManagedProcess>{};

  Future<Map<String, dynamic>> start({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    required Map<String, String> environment,
    required String runId,
    required String workItemId,
    void Function(String stream, String delta)? onOutput,
    ManagedProcessLifecycle lifecycle = ManagedProcessLifecycle.ephemeral,
  }) async {
    await logDirectory.create(recursive: true);
    final id = newId('process');
    final log = File('${logDirectory.path}${Platform.pathSeparator}$id.log');
    Process process;
    try {
      final launch = await resolveProcessLaunchTarget(executable);
      process = await Process.start(
        launch.executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: launch.runInShell,
        mode: ProcessStartMode.normal,
      );
    } on ProcessException catch (error) {
      throw ProductErrorNormalizer.normalize(error, executable: executable);
    }
    final record = _ManagedProcess(
      id: id,
      process: process,
      executable: executable,
      arguments: List<String>.unmodifiable(arguments),
      workingDirectory: workingDirectory,
      runId: runId,
      workItemId: workItemId,
      startedAt: DateTime.now().toUtc(),
      log: log,
      onOutput: onOutput,
      lifecycle: lifecycle,
    );
    _processes[id] = record;
    final stdoutPump = _pump(record, 'stdout', process.stdout);
    final stderrPump = _pump(record, 'stderr', process.stderr);
    unawaited(() async {
      try {
        final code = await process.exitCode;
        record.exitCode = code;
        record.completedAt = DateTime.now().toUtc();
        await Future.wait(<Future<void>>[stdoutPump, stderrPump]);
        await _writeLog(
            record,
            <String, dynamic>{
              'timestamp': record.completedAt!.toIso8601String(),
              'stream': 'lifecycle',
              'message': 'process exited with code $code',
            },
            flush: true);
      } catch (error, stackTrace) {
        record.completedAt ??= DateTime.now().toUtc();
        record.lifecycleError = redactor.redact('$error');
        record.lifecycleErrorHash = Sha256.text('$stackTrace');
      }
    }());
    return _status(record);
  }

  Future<Map<String, dynamic>> status(String id) async {
    final record = _processes[id];
    if (record == null) {
      throw ProductException(
        'managed_process_missing',
        'Unknown managed process.',
      );
    }
    return _status(record);
  }

  Future<Map<String, dynamic>> stop(
    String id, {
    Duration grace = const Duration(seconds: 5),
  }) async {
    final record = _processes[id];
    if (record == null) {
      throw ProductException(
        'managed_process_missing',
        'Unknown managed process.',
      );
    }
    if (record.exitCode == null) {
      record.process.kill(ProcessSignal.sigterm);
      try {
        await record.process.exitCode.timeout(grace);
      } on TimeoutException {
        record.process.kill(ProcessSignal.sigkill);
        await record.process.exitCode;
      }
    }
    return _status(record);
  }

  Future<void> stopAll() async {
    for (final record in _processes.values.toList()) {
      if (record.exitCode == null) {
        try {
          await stop(record.id);
        } catch (_) {
          record.process.kill(ProcessSignal.sigkill);
        }
      }
    }
  }

  /// Stops every tracked process whose [ManagedProcessLifecycle] is
  /// [ManagedProcessLifecycle.ephemeral] — every ordinary agent tool call
  /// or Analyze/Test/Build invocation. Processes started with
  /// [ManagedProcessLifecycle.persistUntilStopped] (a Project Manager Run)
  /// are left running: they belong to the durable project runtime session
  /// registry, not to this application's own lifecycle, and are reconciled
  /// on the next startup instead of being killed here.
  Future<void> stopEphemeral() async {
    for (final record in _processes.values.toList()) {
      if (record.exitCode == null &&
          record.lifecycle == ManagedProcessLifecycle.ephemeral) {
        try {
          await stop(record.id);
        } catch (_) {
          record.process.kill(ProcessSignal.sigkill);
        }
      }
    }
  }

  Future<void> _pump(
    _ManagedProcess record,
    String stream,
    Stream<List<int>> source,
  ) async {
    await for (final chunk in source) {
      await _append(record, stream, chunk);
    }
  }

  Future<void> _append(
    _ManagedProcess record,
    String stream,
    List<int> chunk,
  ) async {
    var text = redactor.redact(utf8.decode(chunk, allowMalformed: true));
    if (text.length > 65536) {
      text = text.substring(0, 65536);
    }
    try {
      record.onOutput?.call(stream, text);
    } catch (_) {
      // Live presentation must never change process execution semantics.
    }
    record.tail.write(text);
    if (record.tail.length > 131072) {
      final compacted = record.tail.toString();
      record.tail
        ..clear()
        ..write(compacted.substring(compacted.length - 65536));
    }
    await _writeLog(record, <String, dynamic>{
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'stream': stream,
      'message': text,
    });
  }

  Future<void> _writeLog(
    _ManagedProcess record,
    Map<String, dynamic> payload, {
    bool flush = false,
  }) {
    final write = record.pendingWrite.then<void>((_) async {
      await record.log.writeAsString(
        '${jsonEncode(payload)}\n',
        mode: FileMode.append,
        flush: flush,
      );
    });
    record.pendingWrite = write;
    return write;
  }

  Map<String, dynamic> _status(_ManagedProcess record) => <String, dynamic>{
        'id': record.id,
        'pid': record.process.pid,
        'executable': record.executable,
        'arguments': record.arguments,
        'runId': record.runId,
        'workItemId': record.workItemId,
        'startedAt': record.startedAt.toIso8601String(),
        'completedAt': record.completedAt?.toIso8601String(),
        'running': record.exitCode == null,
        'exitCode': record.exitCode,
        'outputTail': record.tail.toString(),
        'logFileName': record.log.uri.pathSegments.last,
        'lifecycleError': record.lifecycleError,
        'lifecycleErrorHash': record.lifecycleErrorHash,
      };
}

class _ManagedProcess {
  _ManagedProcess({
    required this.id,
    required this.process,
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.runId,
    required this.workItemId,
    required this.startedAt,
    required this.log,
    this.onOutput,
    this.lifecycle = ManagedProcessLifecycle.ephemeral,
  });

  final String id;
  final Process process;
  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final String runId;
  final String workItemId;
  final DateTime startedAt;
  final File log;
  final void Function(String stream, String delta)? onOutput;
  final ManagedProcessLifecycle lifecycle;
  final StringBuffer tail = StringBuffer();
  Future<void> pendingWrite = Future<void>.value();
  int? exitCode;
  DateTime? completedAt;
  String? lifecycleError;
  String? lifecycleErrorHash;
}

class ToolContext {
  const ToolContext({
    required this.project,
    required this.command,
    required this.runId,
    required this.workItem,
    required this.attempt,
    required this.operationOwnerId,
    required this.workflow,
    required this.boundary,
    required this.transaction,
    required this.permissions,
    required this.secrets,
    required this.research,
    required this.knowledge,
    required this.audit,
    required this.settings,
    required this.cancellation,
    required this.redactor,
    required this.deployment,
    required this.managedProcesses,
    required this.sourceIndex,
    required this.mcp,
    this.onToolOutput,
  });

  final ProjectRecord project;
  final PreparedCommand command;
  final String runId;
  final WorkItem workItem;
  final int attempt;
  final String operationOwnerId;
  final DurableWorkflowStore workflow;
  final WorkspaceBoundary boundary;
  final WorkspaceTransaction transaction;
  final PermissionService permissions;
  final SecretVault secrets;
  final ResearchService research;
  final KnowledgeService knowledge;
  final AuditChain audit;
  final ProductSettings settings;
  final CancellationSignal cancellation;
  final SecretRedactor redactor;
  final DeploymentService deployment;
  final ManagedProcessService managedProcesses;
  final SourceIndexService sourceIndex;
  final McpTrustService mcp;
  final void Function(String tool, String stream, String delta)? onToolOutput;
}

class ToolResult {
  const ToolResult({
    required this.ok,
    required this.summary,
    this.data = const <String, dynamic>{},
    this.mutated = false,
  });

  final bool ok;
  final String summary;
  final Map<String, dynamic> data;
  final bool mutated;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'ok': ok,
        'summary': summary,
        'data': data,
        'mutated': mutated,
      };

  factory ToolResult.fromJson(Map<String, dynamic> json) => ToolResult(
        ok: json['ok'] == true,
        summary: json['summary']?.toString() ?? '',
        data: mapValue(json['data']),
        mutated: json['mutated'] == true,
      );
}

typedef ToolHandler = Future<ToolResult> Function(
  ToolContext context,
  Map<String, dynamic> arguments,
);

class GovernedTool {
  const GovernedTool({required this.contract, required this.handler});

  final ToolContract contract;
  final ToolHandler handler;

  String get name => contract.name;
  String get description => contract.description;
  PermissionScope get permission => contract.permission;

  Map<String, dynamic> descriptor({
    ToolDescriptorDialect dialect = ToolDescriptorDialect.canonical,
  }) =>
      contract.descriptor(dialect: dialect);
}

class ToolRegistry {
  ToolRegistry._(this._tools, this.schemas) {
    schemas.verifyCoverage(_tools.keys);
  }

  static const Map<String, Set<String>> _pathArgumentKeys =
      <String, Set<String>>{
    'list_directory': <String>{'path'},
    'read_file': <String>{'path'},
    'inspect_file': <String>{'path'},
    'search_text': <String>{'path'},
    'write_file': <String>{'path'},
    'write_binary_file': <String>{'path'},
    'replace_text': <String>{'path'},
    'apply_patch': <String>{'path'},
    'delete_file': <String>{'path'},
  };

  final Map<String, GovernedTool> _tools;
  final ToolSchemaRegistry schemas;

  factory ToolRegistry.standard() {
    const schemas = ToolSchemaRegistry();
    final tools = <GovernedTool>[
      GovernedTool(
        contract: schemas.require('list_directory'),
        handler: _listDirectory,
      ),
      GovernedTool(contract: schemas.require('read_file'), handler: _readFile),
      GovernedTool(
        contract: schemas.require('inspect_file'),
        handler: _inspectFile,
      ),
      GovernedTool(
        contract: schemas.require('search_text'),
        handler: _searchText,
      ),
      GovernedTool(
        contract: schemas.require('index_project'),
        handler: _indexProject,
      ),
      GovernedTool(
        contract: schemas.require('index_search'),
        handler: _indexSearch,
      ),
      GovernedTool(
        contract: schemas.require('write_file'),
        handler: _writeFile,
      ),
      GovernedTool(
        contract: schemas.require('write_binary_file'),
        handler: _writeBinaryFile,
      ),
      GovernedTool(
        contract: schemas.require('replace_text'),
        handler: _replaceText,
      ),
      GovernedTool(
        contract: schemas.require('apply_patch'),
        handler: _applyPatch,
      ),
      GovernedTool(
        contract: schemas.require('delete_file'),
        handler: _deleteFile,
      ),
      GovernedTool(
        contract: schemas.require('run_command'),
        handler: _runCommand,
      ),
      GovernedTool(
        contract: schemas.require('start_process'),
        handler: _startProcess,
      ),
      GovernedTool(
        contract: schemas.require('process_status'),
        handler: _processStatus,
      ),
      GovernedTool(
        contract: schemas.require('stop_process'),
        handler: _stopProcess,
      ),
      GovernedTool(
        contract: schemas.require('git_status'),
        handler: _gitStatus,
      ),
      GovernedTool(contract: schemas.require('git_diff'), handler: _gitDiff),
      GovernedTool(
        contract: schemas.require('knowledge_search'),
        handler: _knowledgeSearch,
      ),
      GovernedTool(
        contract: schemas.require('research_fetch'),
        handler: _researchFetch,
      ),
      GovernedTool(
        contract: schemas.require('research_search'),
        handler: _researchSearch,
      ),
      GovernedTool(
        contract: schemas.require('verify_project'),
        handler: _verifyProject,
      ),
      GovernedTool(
        contract: schemas.require('package_deployment'),
        handler: _packageDeployment,
      ),
      GovernedTool(contract: schemas.require('mcp_call'), handler: _mcpCall),
    ];
    return ToolRegistry._(<String, GovernedTool>{
      for (final tool in tools) tool.name: tool,
    }, schemas);
  }

  Set<String> get names => Set<String>.unmodifiable(_tools.keys);

  ToolContract contractFor(String name) => schemas.require(name);

  bool isMutatingTool(String name) =>
      _tools[name]?.contract.isMutating ?? false;

  Set<String> allowedToolNames(Iterable<String> requested) =>
      requested.where(_tools.containsKey).toSet();

  Set<PermissionScope> permissionsForTools(Iterable<String> names) => names
      .map((name) => _tools[name]?.permission)
      .whereType<PermissionScope>()
      .toSet();

  List<Map<String, dynamic>> descriptors({
    Set<String>? allowlist,
    ToolDescriptorDialect dialect = ToolDescriptorDialect.canonical,
  }) =>
      _tools.values
          .where((tool) => allowlist == null || allowlist.contains(tool.name))
          .map((tool) => tool.descriptor(dialect: dialect))
          .toList(growable: false);

  Future<ToolResult> execute(
    String name,
    Map<String, dynamic> arguments,
    ToolContext context,
  ) async {
    context.cancellation.throwIfCancelled();
    final tool = _tools[name];
    if (tool == null) {
      throw ProductException('tool_unknown', 'Unknown tool: $name');
    }
    if (!context.workItem.allowedTools.contains(name)) {
      throw ProductException(
        'tool_not_allowed',
        'Tool $name is not allowed for this work item.',
      );
    }

    final normalization = tool.contract.canonicalizeInput(arguments);
    tool.contract.validateInput(normalization.arguments);
    final normalizedArguments = Map<String, dynamic>.from(
      normalization.arguments,
    );
    if (normalization.changed) {
      await context.audit.append(
        'tool.arguments_compatibility_normalized',
        context.runId,
        <String, dynamic>{
          'workItemId': context.workItem.id,
          'tool': name,
          'schemaVersion': tool.contract.version,
          'compatibilityVersion': tool.contract.compatibilityVersion,
          'changes': normalization.changes
              .map((change) => change.toJson())
              .toList(growable: false),
        },
      );
    }

    await context.permissions.require(
      projectId: context.project.id,
      commandId: context.command.id,
      scope: tool.permission,
    );
    context.cancellation.throwIfCancelled();
    for (final key in _pathArgumentKeys[name] ?? const <String>{}) {
      final raw = normalizedArguments[key]?.toString();
      if (raw == null || raw.trim().isEmpty) {
        continue;
      }
      final normalized = context.boundary.normalizeToolPath(raw);
      normalizedArguments[key] = normalized;
      if (normalized != raw.trim().replaceAll('\\', '/')) {
        await context.audit
            .append('tool.path_normalized', context.runId, <String, dynamic>{
          'workItemId': context.workItem.id,
          'tool': name,
          'argument': key,
          'originalPathHash': Sha256.text(raw),
          'normalizedPath': normalized,
        });
      }
    }
    tool.contract.validateInput(normalizedArguments);
    final inputHash = Sha256.text(canonicalJson(normalizedArguments));
    final snapshotSensitive = tool.contract.idempotency ==
            ToolIdempotency.projectSnapshot ||
        (tool.contract.risk == ToolRisk.process && name == 'verify_project');
    final idempotencyInputHash = snapshotSensitive
        ? Sha256.text('$inputHash:${context.transaction.mutationCount}')
        : inputHash;
    final durableOperation = tool.contract.risk != ToolRisk.read;
    final idempotencyKey = durableOperation
        ? DurableWorkflowStore.deriveIdempotencyKey(
            runId: context.runId,
            workItemId: context.workItem.id,
            attempt: context.attempt,
            logicalOperation: 'tool:$name:${tool.contract.version}',
            normalizedArgumentsSha256: idempotencyInputHash,
          )
        : '';

    await context.audit.append('tool.started', context.runId, <String, dynamic>{
      'workItemId': context.workItem.id,
      'tool': name,
      'schemaVersion': tool.contract.version,
      'registryVersion': schemas.version,
      'contractDigest': schemas.contractDigest,
      'normalizedInputHash': inputHash,
      if (idempotencyKey.isNotEmpty) 'idempotencyKey': idempotencyKey,
      'arguments': context.redactor.redactJson(normalizedArguments),
    });

    if (idempotencyKey.isNotEmpty) {
      IdempotencyClaim claim;
      try {
        claim = await context.workflow.claimOperation(
          key: idempotencyKey,
          runId: context.runId,
          workItemId: context.workItem.id,
          attempt: context.attempt,
          operation: 'tool:$name',
          normalizedArgumentsSha256: idempotencyInputHash,
          ownerId: context.operationOwnerId,
          lease: const Duration(minutes: 2),
          allowLeaseTakeover: !const <String>{
            'run_command',
            'start_process',
            'package_deployment',
            'mcp_call',
          }.contains(name),
        );
      } on WorkflowStorageException catch (error) {
        throw ProductException(
          error.code,
          error.message,
          details: error.details,
        );
      }
      switch (claim.kind) {
        case IdempotencyClaimKind.replay:
          final replay = ToolResult.fromJson(
            claim.result ?? const <String, dynamic>{},
          );
          tool.contract.validateOutput(replay.toJson());
          await context.audit.append(
            'tool.idempotency_replayed',
            context.runId,
            <String, dynamic>{
              'workItemId': context.workItem.id,
              'tool': name,
              'idempotencyKey': idempotencyKey,
              'executionGeneration': claim.executionGeneration,
              'outputHash': Sha256.text(canonicalJson(replay.toJson())),
            },
          );
          return replay;
        case IdempotencyClaimKind.effectRecorded:
          final recovered = _recoverRecordedMutationResult(
            name,
            claim.effect ?? const <String, dynamic>{},
            normalizedArguments,
          );
          tool.contract.validateOutput(recovered.toJson());
          await context.workflow.completeOperation(
            key: idempotencyKey,
            ownerId: context.operationOwnerId,
            result: recovered.toJson(),
          );
          await context.audit.append(
            'tool.idempotency_effect_recovered',
            context.runId,
            <String, dynamic>{
              'workItemId': context.workItem.id,
              'tool': name,
              'idempotencyKey': idempotencyKey,
              'mutationId': recovered.data['id'],
            },
          );
          return recovered;
        case IdempotencyClaimKind.busy:
          throw ProductException(
            'operation_in_flight',
            'The same durable operation is already executing under an active lease.',
            details: <String, dynamic>{
              'tool': name,
              'idempotencyKey': idempotencyKey,
            },
          );
        case IdempotencyClaimKind.terminalFailure:
          throw ProductException(
            claim.errorCode ?? 'operation_previously_failed',
            'The same durable operation already failed with a non-retryable result.',
            details: <String, dynamic>{
              'tool': name,
              'idempotencyKey': idempotencyKey,
              'errorClass': claim.errorClass,
              'retryability': claim.retryability,
            },
          );
        case IdempotencyClaimKind.manualRecovery:
          throw ProductException(
            'operation_recovery_required',
            'A non-compensatable operation was interrupted after it began. Kristin will not repeat it automatically; inspect external state before retrying.',
            details: <String, dynamic>{
              'tool': name,
              'idempotencyKey': idempotencyKey,
            },
          );
        case IdempotencyClaimKind.acquired:
          break;
      }
      await context.workflow.createCheckpoint(
        runId: context.runId,
        workItemId: context.workItem.id,
        kind: 'operation_claimed',
        state: <String, dynamic>{
          'tool': name,
          'attempt': context.attempt,
          'idempotencyKey': idempotencyKey,
          'normalizedInputHash': inputHash,
          'executionGeneration': claim.executionGeneration,
          'recoveredLease': claim.recoveredLease,
        },
      );
    }

    try {
      final result = idempotencyKey.isEmpty
          ? await tool.handler(context, normalizedArguments)
          : await context.transaction.runOperation<ToolResult>(
              idempotencyKey: idempotencyKey,
              workItemId: context.workItem.id,
              action: () => tool.handler(context, normalizedArguments),
            );
      try {
        tool.contract.validateOutput(result.toJson());
      } on ToolSchemaException catch (schemaError) {
        await context.audit.append(
          'tool.output_schema_failed',
          context.runId,
          <String, dynamic>{
            'workItemId': context.workItem.id,
            'tool': name,
            'schemaVersion': tool.contract.version,
            'normalizedInputHash': inputHash,
            'mutated': result.mutated,
            'outputHash': Sha256.text(canonicalJson(result.toJson())),
            'errorCode': schemaError.code,
            'errorDetails': context.redactor.redactJson(schemaError.details),
          },
        );
        rethrow;
      }
      if (idempotencyKey.isNotEmpty) {
        try {
          await context.workflow.completeOperation(
            key: idempotencyKey,
            ownerId: context.operationOwnerId,
            result: result.toJson(),
          );
        } on WorkflowStorageException catch (error) {
          throw ProductException(
            error.code,
            error.message,
            details: error.details,
          );
        }
        await context.workflow.createCheckpoint(
          runId: context.runId,
          workItemId: context.workItem.id,
          kind: 'operation_completed',
          state: <String, dynamic>{
            'tool': name,
            'attempt': context.attempt,
            'idempotencyKey': idempotencyKey,
            'outputHash': Sha256.text(canonicalJson(result.toJson())),
            'mutated': result.mutated,
          },
        );
      }
      await context.audit
          .append('tool.completed', context.runId, <String, dynamic>{
        'workItemId': context.workItem.id,
        'tool': name,
        'schemaVersion': tool.contract.version,
        'normalizedInputHash': inputHash,
        if (idempotencyKey.isNotEmpty) 'idempotencyKey': idempotencyKey,
        'outputHash': Sha256.text(canonicalJson(result.toJson())),
        'ok': result.ok,
        'mutated': result.mutated,
        'summary': result.summary,
      });
      return result;
    } catch (error) {
      final code = error is ProductException
          ? error.code
          : error is ToolSchemaException
              ? error.code
              : 'tool_runtime_error';
      final classification = const WorkflowRetryTaxonomy().classify(code);
      if (idempotencyKey.isNotEmpty) {
        try {
          await context.workflow.failOperation(
            key: idempotencyKey,
            ownerId: context.operationOwnerId,
            errorClass: classification.failureClass.name,
            errorCode: code,
            retryability: classification.retryability,
          );
        } catch (_) {
          // The original tool failure remains authoritative.
        }
      }
      await context.audit
          .append('tool.failed', context.runId, <String, dynamic>{
        'workItemId': context.workItem.id,
        'tool': name,
        'schemaVersion': tool.contract.version,
        'normalizedInputHash': inputHash,
        if (idempotencyKey.isNotEmpty) 'idempotencyKey': idempotencyKey,
        'failureClass': classification.failureClass.name,
        'retryDisposition': classification.disposition.name,
        'retryability': classification.retryability,
        'error': context.redactor.redact('$error'),
      });
      rethrow;
    }
  }

  static ToolResult _recoverRecordedMutationResult(
    String tool,
    Map<String, dynamic> effect,
    Map<String, dynamic> arguments,
  ) {
    if (!const <String>{
      'write_file',
      'write_binary_file',
      'replace_text',
      'apply_patch',
      'delete_file',
    }.contains(tool)) {
      throw ProductException(
        'operation_recovery_required',
        'A durable effect exists, but this tool has no deterministic result reconstruction policy.',
        details: <String, dynamic>{'tool': tool},
      );
    }
    final data = Map<String, dynamic>.from(effect);
    final operation = data['operation']?.toString() ?? '';
    final path =
        data['relativePath']?.toString() ?? arguments['path']?.toString() ?? '';
    if (tool == 'write_binary_file') {
      var encoded = arguments['base64']?.toString().trim() ?? '';
      final comma = encoded.indexOf(',');
      if (encoded.startsWith('data:') && comma >= 0) {
        encoded = encoded.substring(comma + 1);
      }
      final bytes = base64Decode(encoded.replaceAll(RegExp(r'\s+'), ''));
      final format = _fileFormat(path, bytes.take(64).toList());
      data
        ..['bytes'] = bytes.length
        ..['format'] = format.$1
        ..['mimeType'] = format.$2;
    }
    final summary = switch (tool) {
      'delete_file' => 'Recovered the durable deletion of $path.',
      'replace_text' => 'Recovered the durable text replacement in $path.',
      'apply_patch' => 'Recovered the durable patch applied to $path.',
      'write_binary_file' => 'Recovered the durable binary write to $path.',
      _ => 'Recovered the durable write to $path.',
    };
    return ToolResult(
      ok: true,
      summary: summary,
      data: data,
      mutated: operation != 'noop',
    );
  }

  static Future<ToolResult> _listDirectory(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final path = arguments['path']?.toString() ?? '.';
    final recursive = arguments['recursive'] == true;
    final maxEntries =
        (int.tryParse(arguments['maxEntries']?.toString() ?? '') ?? 500)
            .clamp(1, 2000)
            .toInt();
    final directory = await context.boundary.directory(path);
    final entries = <Map<String, dynamic>>[];
    await for (final entity in directory.list(
      recursive: recursive,
      followLinks: false,
    )) {
      if (entries.length >= maxEntries) {
        break;
      }
      final relative = context.boundary.relative(entity.path);
      if (_ignored(relative)) {
        continue;
      }
      final stat = await entity.stat();
      entries.add(<String, dynamic>{
        'path': relative,
        'type': entity is Directory
            ? 'directory'
            : entity is Link
                ? 'link'
                : 'file',
        'bytes': stat.size,
        'modifiedAt': stat.modified.toUtc().toIso8601String(),
      });
    }
    entries.sort(
      (a, b) => a['path'].toString().compareTo(b['path'].toString()),
    );
    return ToolResult(
      ok: true,
      summary: 'Listed ${entries.length} entries.',
      data: <String, dynamic>{'entries': entries},
    );
  }

  static Future<ToolResult> _readFile(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final path = _requiredString(arguments, 'path');
    final maxBytes =
        (int.tryParse(arguments['maxBytes']?.toString() ?? '') ?? 1048576)
            .clamp(1, 4194304)
            .toInt();
    final file = await context.boundary.file(path);
    final stat = await file.stat();
    if (stat.size > maxBytes) {
      throw ProductException('file_too_large', 'File exceeds the read limit.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.take(min(bytes.length, 8192)).contains(0)) {
      throw ProductException(
        'binary_file_rejected',
        'Binary files cannot be returned to the model.',
      );
    }
    final content = utf8.decode(bytes, allowMalformed: true);
    return ToolResult(
      ok: true,
      summary: 'Read $path.',
      data: <String, dynamic>{
        'path': path,
        'content': content,
        'sha256': Sha256.hex(bytes),
        'bytes': bytes.length,
      },
    );
  }

  static Future<ToolResult> _inspectFile(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final path = _requiredString(arguments, 'path');
    final maxBytes = (int.tryParse(arguments['maxBytes']?.toString() ?? '') ??
            8 * 1024 * 1024)
        .clamp(1, 16 * 1024 * 1024)
        .toInt();
    final previewBytes =
        (int.tryParse(arguments['previewBytes']?.toString() ?? '') ?? 32768)
            .clamp(256, 262144)
            .toInt();
    final file = await context.boundary.file(path);
    final stat = await file.stat();
    if (stat.size > maxBytes) {
      throw ProductException(
        'file_too_large',
        'File exceeds the bounded inspection limit.',
        details: <String, dynamic>{'bytes': stat.size, 'maxBytes': maxBytes},
      );
    }
    final bytes = await file.readAsBytes();
    final sample = bytes.take(min(bytes.length, previewBytes)).toList();
    final binary = _looksBinary(sample);
    final format = _fileFormat(path, sample);
    final data = <String, dynamic>{
      'path': path,
      'bytes': bytes.length,
      'sha256': Sha256.hex(bytes),
      'format': format.$1,
      'mimeType': format.$2,
      'binary': binary,
      'modifiedAt': stat.modified.toUtc().toIso8601String(),
    };
    if (binary) {
      data['base64Preview'] = base64Encode(sample);
      data['previewBytes'] = sample.length;
    } else {
      data['textPreview'] = utf8.decode(sample, allowMalformed: true);
      data['previewBytes'] = sample.length;
    }
    return ToolResult(
      ok: true,
      summary: 'Inspected $path as ${format.$1}.',
      data: data,
    );
  }

  static Future<ToolResult> _searchText(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final query = _requiredString(arguments, 'query');
    if (query.length > 1000) {
      throw ProductException('query_too_long', 'Search query is too long.');
    }
    final path = arguments['path']?.toString() ?? '.';
    final maxResults =
        (int.tryParse(arguments['maxResults']?.toString() ?? '') ?? 100)
            .clamp(1, 500)
            .toInt();
    final root = await context.boundary.directory(path);
    final results = <Map<String, dynamic>>[];
    var scanned = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      context.cancellation.throwIfCancelled();
      if (entity is! File) {
        continue;
      }
      final relative = context.boundary.relative(entity.path);
      if (_ignored(relative)) {
        continue;
      }
      final stat = await entity.stat();
      if (stat.size > 1024 * 1024) {
        continue;
      }
      if (++scanned > 5000) {
        break;
      }
      final bytes = await entity.readAsBytes();
      if (bytes.take(min(bytes.length, 4096)).contains(0)) {
        continue;
      }
      final lines = utf8.decode(bytes, allowMalformed: true).split('\n');
      for (var index = 0;
          index < lines.length && results.length < maxResults;
          index++) {
        if (lines[index].contains(query)) {
          results.add(<String, dynamic>{
            'path': relative,
            'line': index + 1,
            'text': lines[index].length > 500
                ? lines[index].substring(0, 500)
                : lines[index],
          });
        }
      }
      if (results.length >= maxResults) {
        break;
      }
    }
    return ToolResult(
      ok: true,
      summary: 'Found ${results.length} matches.',
      data: <String, dynamic>{'results': results, 'filesScanned': scanned},
    );
  }

  static Future<ToolResult> _indexProject(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final report = await context.sourceIndex.update(context.project);
    return ToolResult(
      ok: true,
      summary:
          'Indexed ${report.total} project files (${report.changed} changed, ${report.removed} removed).',
      data: report.toJson(),
    );
  }

  static Future<ToolResult> _indexSearch(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final query = _requiredString(arguments, 'query');
    final limit = (int.tryParse(arguments['limit']?.toString() ?? '') ?? 20)
        .clamp(1, 100)
        .toInt();
    final results = await context.sourceIndex.search(
      context.project.id,
      query,
      limit: limit,
    );
    return ToolResult(
      ok: true,
      summary: 'Found ${results.length} indexed matches.',
      data: <String, dynamic>{'results': results},
    );
  }

  static Future<ToolResult> _writeFile(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final path = _requiredString(arguments, 'path');
    if (!arguments.containsKey('content')) {
      throw ProductException(
        'argument_required',
        'Argument "content" is required.',
        details: const <String, dynamic>{'argument': 'content'},
      );
    }
    final content = arguments['content']?.toString() ?? '';
    if (utf8.encode(content).length > 4 * 1024 * 1024) {
      throw ProductException(
        'write_too_large',
        'A single write cannot exceed 4 MiB.',
      );
    }
    final expectedExists = _optionalBool(arguments, 'expectedExists');
    final record = await context.transaction.writeText(
      relativePath: path,
      content: content,
      expectedHash: arguments['expectedSha256']?.toString(),
      expectedExists: expectedExists,
    );
    final mutated = record.operation != 'noop';
    return ToolResult(
      ok: true,
      summary: mutated
          ? '${record.operation} $path.'
          : 'No changes were needed for $path; the requested content already matches the file.',
      data: record.toJson(),
      mutated: mutated,
    );
  }

  static Future<ToolResult> _writeBinaryFile(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final path = _requiredString(arguments, 'path');
    var encoded = _requiredString(arguments, 'base64').trim();
    final comma = encoded.indexOf(',');
    if (encoded.startsWith('data:') && comma >= 0) {
      encoded = encoded.substring(comma + 1);
    }
    List<int> bytes;
    try {
      bytes = base64Decode(encoded.replaceAll(RegExp(r'\s+'), ''));
    } on FormatException {
      throw ProductException(
        'base64_invalid',
        'The binary file content is not valid base64.',
      );
    }
    if (bytes.length > 8 * 1024 * 1024) {
      throw ProductException(
        'write_too_large',
        'A single binary write cannot exceed 8 MiB.',
      );
    }
    final expectedExists = _optionalBool(arguments, 'expectedExists');
    final record = await context.transaction.writeBytes(
      relativePath: path,
      bytes: bytes,
      expectedHash: arguments['expectedSha256']?.toString(),
      expectedExists: expectedExists,
    );
    final format = _fileFormat(path, bytes.take(64).toList());
    final mutated = record.operation != 'noop';
    return ToolResult(
      ok: true,
      summary: mutated
          ? '${record.operation} binary file $path.'
          : 'No changes were needed for binary file $path; the requested bytes already match the file.',
      data: <String, dynamic>{
        ...record.toJson(),
        'bytes': bytes.length,
        'format': format.$1,
        'mimeType': format.$2,
      },
      mutated: mutated,
    );
  }

  static Future<ToolResult> _replaceText(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final path = _requiredString(arguments, 'path');
    final old = _requiredString(arguments, 'old');
    final replacement = arguments['replacement']?.toString() ?? '';
    final file = await context.boundary.file(path);
    final bytes = await file.readAsBytes();
    final hash = Sha256.hex(bytes);
    final expected = arguments['expectedSha256']?.toString();
    if (expected != null &&
        expected.isNotEmpty &&
        !constantTimeEquals(hash, expected)) {
      throw ProductException(
        'stale_content',
        'The file changed after it was read.',
      );
    }
    final content = utf8.decode(bytes, allowMalformed: true);
    final first = content.indexOf(old);
    if (first < 0) {
      throw ProductException(
        'replacement_not_found',
        'The exact text to replace was not found.',
      );
    }
    if (content.indexOf(old, first + old.length) >= 0) {
      throw ProductException(
        'replacement_ambiguous',
        'The exact text occurs more than once; use apply_patch with a larger hunk.',
      );
    }
    final updated = content.replaceRange(
      first,
      first + old.length,
      replacement,
    );
    final record = await context.transaction.writeText(
      relativePath: path,
      content: updated,
      expectedHash: hash,
    );
    final mutated = record.operation != 'noop';
    return ToolResult(
      ok: true,
      summary: mutated
          ? 'Replaced exact text in $path.'
          : 'No changes were needed for $path; the replacement produced identical content.',
      data: record.toJson(),
      mutated: mutated,
    );
  }

  static Future<ToolResult> _applyPatch(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final path = _requiredString(arguments, 'path');
    final file = await context.boundary.file(path);
    final bytes = await file.readAsBytes();
    final hash = Sha256.hex(bytes);
    final expected = arguments['expectedSha256']?.toString();
    if (expected != null &&
        expected.isNotEmpty &&
        !constantTimeEquals(hash, expected)) {
      throw ProductException(
        'stale_content',
        'The file changed after it was read.',
      );
    }
    var content = utf8.decode(bytes, allowMalformed: true);
    final hunks = arguments['hunks'];
    if (hunks is! List || hunks.isEmpty) {
      throw ProductException(
        'patch_empty',
        'At least one replacement hunk is required.',
      );
    }
    for (var index = 0; index < hunks.length; index++) {
      final hunk = mapValue(hunks[index]);
      final old = _requiredString(hunk, 'old');
      final replacement = hunk['replacement']?.toString() ?? '';
      final first = content.indexOf(old);
      if (first < 0) {
        throw ProductException(
          'patch_hunk_not_found',
          'Patch hunk ${index + 1} was not found.',
        );
      }
      if (content.indexOf(old, first + old.length) >= 0) {
        throw ProductException(
          'patch_hunk_ambiguous',
          'Patch hunk ${index + 1} is ambiguous.',
        );
      }
      content = content.replaceRange(first, first + old.length, replacement);
    }
    final record = await context.transaction.writeText(
      relativePath: path,
      content: content,
      expectedHash: hash,
    );
    final mutated = record.operation != 'noop';
    return ToolResult(
      ok: true,
      summary: mutated
          ? 'Applied ${hunks.length} patch hunks to $path.'
          : 'No changes were needed for $path; the patch produced identical content.',
      data: record.toJson(),
      mutated: mutated,
    );
  }

  static Future<ToolResult> _deleteFile(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final path = _requiredString(arguments, 'path');
    final record = await context.transaction.delete(
      relativePath: path,
      expectedHash: arguments['expectedSha256']?.toString(),
    );
    return ToolResult(
      ok: true,
      summary: 'Deleted $path.',
      data: record.toJson(),
      mutated: true,
    );
  }

  static Future<ToolResult> _runCommand(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final executable = _requiredString(arguments, 'executable');
    final args = _validateProcess(
      context,
      executable,
      stringList(arguments['args']),
    );
    final network = _usesNetwork(executable, args);
    if (network) {
      if (context.settings.localOnly || !context.settings.allowPackageNetwork) {
        throw ProductException(
          'network_disabled',
          'Package and command network access is disabled.',
        );
      }
      await context.permissions.require(
        projectId: context.project.id,
        commandId: context.command.id,
        scope: PermissionScope.networkPackages,
      );
    }
    final environment = _safeEnvironment();
    final secretRefs = mapValue(arguments['environmentSecretRefs']);
    for (final entry in secretRefs.entries) {
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(entry.key)) {
        throw ProductException(
          'environment_key_invalid',
          'Invalid environment variable name ${entry.key}.',
        );
      }
      await context.permissions.require(
        projectId: context.project.id,
        commandId: context.command.id,
        scope: PermissionScope.secretUse,
      );
      environment[entry.key] = await context.secrets.resolve(
        entry.value.toString(),
        commandId: context.command.id,
      );
    }
    final timeout = Duration(
      seconds:
          (int.tryParse(arguments['timeoutSeconds']?.toString() ?? '') ?? 300)
              .clamp(1, 3600)
              .toInt(),
    );
    final result = await _runFinite(
      executable: executable,
      arguments: args,
      workingDirectory: context.boundary.root.path,
      environment: environment,
      timeout: timeout,
      cancellation: context.cancellation,
      redactor: context.redactor,
      onOutput: (stream, delta) =>
          context.onToolOutput?.call('run_command', stream, delta),
    );
    return ToolResult(
      ok: result['exitCode'] == 0,
      summary: 'Command exited with code ${result['exitCode']}.',
      data: result,
    );
  }

  static Future<ToolResult> _startProcess(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final executable = _requiredString(arguments, 'executable');
    final args = _validateProcess(
      context,
      executable,
      stringList(arguments['args']),
    );
    final network = _usesNetwork(executable, args);
    if (network) {
      if (context.settings.localOnly || !context.settings.allowPackageNetwork) {
        throw ProductException(
          'network_disabled',
          'Package and command network access is disabled.',
        );
      }
      await context.permissions.require(
        projectId: context.project.id,
        commandId: context.command.id,
        scope: PermissionScope.networkPackages,
      );
    }
    final environment = _safeEnvironment();
    final secretRefs = mapValue(arguments['environmentSecretRefs']);
    for (final entry in secretRefs.entries) {
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(entry.key)) {
        throw ProductException(
          'environment_key_invalid',
          'Invalid environment variable name ${entry.key}.',
        );
      }
      await context.permissions.require(
        projectId: context.project.id,
        commandId: context.command.id,
        scope: PermissionScope.secretUse,
      );
      environment[entry.key] = await context.secrets.resolve(
        entry.value.toString(),
        commandId: context.command.id,
      );
    }
    final result = await context.managedProcesses.start(
      executable: executable,
      arguments: args,
      workingDirectory: context.boundary.root.path,
      environment: environment,
      runId: context.runId,
      workItemId: context.workItem.id,
      onOutput: (stream, delta) =>
          context.onToolOutput?.call('start_process', stream, delta),
    );
    return ToolResult(
      ok: true,
      summary:
          'Started managed process ${result['id']} with PID ${result['pid']}.',
      data: result,
    );
  }

  static Future<ToolResult> _processStatus(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final id = _requiredString(arguments, 'processId');
    final result = await context.managedProcesses.status(id);
    return ToolResult(
      ok: true,
      summary: result['running'] == true
          ? 'Managed process is running.'
          : 'Managed process has exited.',
      data: result,
    );
  }

  static Future<ToolResult> _stopProcess(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final id = _requiredString(arguments, 'processId');
    final grace = Duration(
      seconds: (int.tryParse(arguments['graceSeconds']?.toString() ?? '') ?? 5)
          .clamp(1, 30)
          .toInt(),
    );
    final result = await context.managedProcesses.stop(id, grace: grace);
    return ToolResult(
      ok: true,
      summary: 'Managed process stopped.',
      data: result,
    );
  }

  static Future<ToolResult> _gitStatus(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final result = await _runFinite(
      executable: 'git',
      arguments: const <String>[
        'status',
        '--porcelain=v1',
        '--untracked-files=all',
      ],
      workingDirectory: context.boundary.root.path,
      environment: _safeEnvironment(),
      timeout: const Duration(seconds: 30),
      cancellation: context.cancellation,
      redactor: context.redactor,
      onOutput: (stream, delta) =>
          context.onToolOutput?.call('git_status', stream, delta),
    );
    final notRepository = _isNotGitRepository(result);
    return ToolResult(
      ok: result['exitCode'] == 0 || notRepository,
      summary: notRepository
          ? 'The selected project is not a Git repository.'
          : 'Collected Git status.',
      data: <String, dynamic>{...result, 'isRepository': !notRepository},
    );
  }

  static Future<ToolResult> _gitDiff(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final result = await _runFinite(
      executable: 'git',
      arguments: const <String>['diff', '--no-ext-diff', '--unified=3'],
      workingDirectory: context.boundary.root.path,
      environment: _safeEnvironment(),
      timeout: const Duration(seconds: 30),
      cancellation: context.cancellation,
      redactor: context.redactor,
      maxOutputBytes: 2 * 1024 * 1024,
      onOutput: (stream, delta) =>
          context.onToolOutput?.call('git_diff', stream, delta),
    );
    final notRepository = _isNotGitRepository(result);
    return ToolResult(
      ok: result['exitCode'] == 0 || notRepository,
      summary: notRepository
          ? 'The selected project is not a Git repository; no Git diff is available.'
          : 'Collected Git diff.',
      data: <String, dynamic>{...result, 'isRepository': !notRepository},
    );
  }

  static Future<ToolResult> _knowledgeSearch(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final query = _requiredString(arguments, 'query');
    final limit = (int.tryParse(arguments['limit']?.toString() ?? '') ?? 8)
        .clamp(1, 20)
        .toInt();
    final includeEpisodes = arguments['includeEpisodes'] != false;
    final includeUnsuccessfulEpisodes =
        arguments['includeUnsuccessfulEpisodes'] == true;
    final retrieval = await context.knowledge.retrieve(
      context.project.id,
      query,
      limit: limit,
      includeEpisodes: includeEpisodes,
      includeUnsuccessfulEpisodes: includeUnsuccessfulEpisodes,
    );
    return ToolResult(
      ok: true,
      summary:
          'Retrieved ${retrieval.hits.length} cited knowledge and memory excerpts.',
      data: retrieval.toJson(),
    );
  }

  static Future<ToolResult> _researchFetch(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    if (context.settings.localOnly) {
      throw ProductException(
        'network_disabled',
        'Research is disabled in local-only mode.',
      );
    }
    final raw = _requiredString(arguments, 'url');
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      throw ProductException('url_invalid', 'The research URL is invalid.');
    }
    final source = await context.research.fetch(uri);
    final entry = await context.knowledge.addResearch(
      context.project.id,
      source,
      tags: stringList(arguments['tags']).toSet(),
    );
    return ToolResult(
      ok: true,
      summary: 'Fetched and indexed ${source.url.host}.',
      data: <String, dynamic>{
        'knowledgeId': entry.id,
        'archiveId': entry.archiveId,
        'title': entry.title,
        'url': entry.sourceUrl,
        'contentHash': entry.contentHash,
        'trust': entry.trust,
        'characters': entry.content.length,
      },
    );
  }

  static Future<ToolResult> _researchSearch(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    if (context.settings.localOnly) {
      throw ProductException(
        'network_disabled',
        'Research is disabled in local-only mode.',
      );
    }
    final query = _requiredString(arguments, 'query');
    final count = (int.tryParse(arguments['count']?.toString() ?? '') ?? 10)
        .clamp(1, 20)
        .toInt();
    final referenceId = arguments['secretReferenceId']?.toString().trim() ?? '';
    SearchProvider? preferred;
    final providerFailures = <String>[];
    if (referenceId.isNotEmpty) {
      try {
        await context.permissions.require(
          projectId: context.project.id,
          commandId: context.command.id,
          scope: PermissionScope.secretUse,
        );
        final key = await context.secrets.resolve(
          referenceId,
          commandId: context.command.id,
        );
        preferred = BraveSearchProvider(
          apiKey: key,
          callback: ({
            required String query,
            required String apiKey,
            required int count,
          }) =>
              context.research.braveSearch(
            query: query,
            apiKey: apiKey,
            count: count,
          ),
        );
      } on ProductException catch (error) {
        if (error.code == 'cancelled') rethrow;
        providerFailures.add('$braveSearchProviderId:${error.code}');
      }
    }
    final router = SearchProviderRouter(
      preferred: preferred,
      builtIn: BuiltInDuckDuckGoSearchProvider(
        timeout: context.research.policy.timeout,
        maxBytes: context.research.policy.maxBytes,
      ),
    );
    final response = await router.search(
      SearchProviderRequest(
        query: query,
        count: count,
        cancellation: context.cancellation.cancelled,
        isCancelled: () => context.cancellation.isCancelled,
      ),
    );
    final results = response.results
        .map((result) => result.toMap())
        .toList(growable: false);
    final failures = <String>[
      ...providerFailures,
      ...response.providerFailures,
    ];
    final archive = await context.knowledge.addResearchSearch(
      projectId: context.project.id,
      query: query,
      results: results,
      provider: response.providerId,
    );
    return ToolResult(
      ok: true,
      summary: 'Found and archived ${results.length} web search results.',
      data: <String, dynamic>{
        'results': results,
        'knowledgeId': archive.id,
        'archiveId': archive.archiveId,
        'contentHash': archive.contentHash,
        'providerId': response.providerId,
        'fallbackUsed': response.fallbackUsed || providerFailures.isNotEmpty,
        if (failures.isNotEmpty) 'providerFailures': failures,
      },
    );
  }

  static Future<ToolResult> _verifyProject(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final commands = <({String executable, List<String> args, String label})>[];
    Future<bool> exists(String path) async =>
        (await context.boundary.resolve(path, allowMissing: true)).exists();
    if (await exists('pubspec.yaml')) {
      commands.add((
        executable: 'flutter',
        args: <String>['analyze'],
        label: 'flutter analyze',
      ));
      commands.add((
        executable: 'flutter',
        args: <String>['test'],
        label: 'flutter test',
      ));
    } else if (await exists('package.json')) {
      final lock = await exists('package-lock.json');
      if (lock &&
          context.settings.allowPackageNetwork &&
          !context.settings.localOnly) {
        commands.add((
          executable: 'npm',
          args: <String>['ci', '--ignore-scripts'],
          label: 'npm ci --ignore-scripts',
        ));
      }
      commands.add((
        executable: 'npm',
        args: <String>['test', '--', '--runInBand'],
        label: 'npm test',
      ));
      commands.add((
        executable: 'npm',
        args: <String>['run', 'build', '--if-present'],
        label: 'npm run build',
      ));
    } else if (await exists('pyproject.toml') ||
        await exists('requirements.txt')) {
      commands.add((
        executable: 'python',
        args: <String>['-m', 'pytest', '-q'],
        label: 'pytest',
      ));
    } else if (await exists('CMakeLists.txt')) {
      commands.add((
        executable: 'cmake',
        args: <String>['-S', '.', '-B', 'build'],
        label: 'cmake configure',
      ));
      commands.add((
        executable: 'cmake',
        args: <String>['--build', 'build'],
        label: 'cmake build',
      ));
    } else if (await exists('index.html')) {
      return const ToolResult(
        ok: true,
        summary: 'Static site structure detected.',
        data: <String, dynamic>{'checks': <Object>[]},
      );
    } else {
      throw ProductException(
        'project_type_unknown',
        'No supported project verification profile was detected.',
      );
    }

    final checks = <Map<String, dynamic>>[];
    var allPassed = true;
    for (final command in commands) {
      context.cancellation.throwIfCancelled();
      try {
        final result = await _runFinite(
          executable: command.executable,
          arguments: command.args,
          workingDirectory: context.boundary.root.path,
          environment: _safeEnvironment(),
          timeout: const Duration(minutes: 15),
          cancellation: context.cancellation,
          redactor: context.redactor,
          maxOutputBytes: 4 * 1024 * 1024,
          onOutput: (stream, delta) => context.onToolOutput?.call(
            'verify_project',
            stream,
            '[${command.label}] $delta',
          ),
        );
        final passed = result['exitCode'] == 0;
        allPassed = allPassed && passed;
        checks.add(<String, dynamic>{
          'label': command.label,
          'passed': passed,
          ...result,
        });
        if (!passed) {
          break;
        }
      } on ProcessException catch (error) {
        allPassed = false;
        checks.add(<String, dynamic>{
          'label': command.label,
          'passed': false,
          'error': '${error.message}: ${error.executable}',
        });
        break;
      }
    }
    return ToolResult(
      ok: allPassed,
      summary: allPassed
          ? 'Project verification passed.'
          : 'Project verification failed.',
      data: <String, dynamic>{'checks': checks},
    );
  }

  static Future<ToolResult> _packageDeployment(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final package = await context.deployment.package(
      project: context.project,
      runId: context.runId,
      profile: arguments['profile']?.toString() ?? 'auto',
    );
    return ToolResult(
      ok: true,
      summary: 'Created a governed ${package.profile} deployment package.',
      data: package.toJson(),
    );
  }

  static Future<ToolResult> _mcpCall(
    ToolContext context,
    Map<String, dynamic> arguments,
  ) async {
    final trustId = _requiredString(arguments, 'trustId');
    final tool = _requiredString(arguments, 'tool');
    final result = await context.mcp.call(
      trustId: trustId,
      projectId: context.project.id,
      tool: tool,
      arguments: mapValue(arguments['arguments']),
      workingDirectory: context.boundary.root.path,
    );
    return ToolResult(
      ok: true,
      summary: 'Called trusted MCP tool $tool. Output is labeled untrusted.',
      data: result,
    );
  }

  static bool _looksBinary(List<int> bytes) {
    if (bytes.isEmpty) {
      return false;
    }
    if (bytes.contains(0)) {
      return true;
    }
    var suspicious = 0;
    for (final byte in bytes) {
      final printable = byte == 9 ||
          byte == 10 ||
          byte == 13 ||
          (byte >= 32 && byte <= 126) ||
          byte >= 0x80;
      if (!printable) {
        suspicious++;
      }
    }
    return suspicious / bytes.length > 0.08;
  }

  static (String, String) _fileFormat(String path, List<int> bytes) {
    final lower = path.toLowerCase();
    if (_startsWith(bytes, const <int>[0x25, 0x50, 0x44, 0x46])) {
      return ('PDF', 'application/pdf');
    }
    if (_startsWith(bytes, const <int>[0x50, 0x4b, 0x03, 0x04])) {
      if (lower.endsWith('.docx')) {
        return (
          'Word document',
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        );
      }
      if (lower.endsWith('.xlsx')) {
        return (
          'Excel workbook',
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        );
      }
      if (lower.endsWith('.pptx')) {
        return (
          'PowerPoint presentation',
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        );
      }
      return ('ZIP archive', 'application/zip');
    }
    if (_startsWith(bytes, const <int>[0x89, 0x50, 0x4e, 0x47])) {
      return ('PNG image', 'image/png');
    }
    if (_startsWith(bytes, const <int>[0xff, 0xd8, 0xff])) {
      return ('JPEG image', 'image/jpeg');
    }
    if (_startsWith(bytes, const <int>[0x47, 0x49, 0x46, 0x38])) {
      return ('GIF image', 'image/gif');
    }
    if (_startsWith(bytes, const <int>[0x52, 0x49, 0x46, 0x46])) {
      return lower.endsWith('.webp')
          ? ('WebP image', 'image/webp')
          : ('RIFF media', 'application/octet-stream');
    }
    final extension = lower.contains('.') ? lower.split('.').last : '';
    return switch (extension) {
      'md' => ('Markdown', 'text/markdown'),
      'txt' || 'log' => ('Text', 'text/plain'),
      'json' => ('JSON', 'application/json'),
      'xml' => ('XML', 'application/xml'),
      'yaml' || 'yml' => ('YAML', 'application/yaml'),
      'csv' => ('CSV', 'text/csv'),
      'html' || 'htm' => ('HTML', 'text/html'),
      'dart' => ('Dart source', 'text/x-dart'),
      'py' => ('Python source', 'text/x-python'),
      'js' || 'mjs' || 'cjs' => ('JavaScript source', 'text/javascript'),
      'ts' || 'tsx' => ('TypeScript source', 'text/typescript'),
      'mp3' => ('MP3 audio', 'audio/mpeg'),
      'mp4' => ('MP4 video', 'video/mp4'),
      'wav' => ('WAV audio', 'audio/wav'),
      _ => _looksBinary(bytes)
          ? ('Binary file', 'application/octet-stream')
          : ('Text file', 'text/plain'),
    };
  }

  static bool _startsWith(List<int> bytes, List<int> signature) {
    if (bytes.length < signature.length) {
      return false;
    }
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) {
        return false;
      }
    }
    return true;
  }

  static bool? _optionalBool(Map<String, dynamic> arguments, String name) {
    if (!arguments.containsKey(name) || arguments[name] == null) {
      return null;
    }
    final value = arguments[name];
    if (value is bool) {
      return value;
    }
    throw ProductException(
      'argument_type_invalid',
      'Argument "$name" must be a JSON boolean.',
      details: <String, dynamic>{'argument': name, 'expectedType': 'boolean'},
    );
  }

  static String _requiredString(Map<String, dynamic> arguments, String name) {
    final value = arguments[name]?.toString().trim() ?? '';
    if (value.isEmpty) {
      throw ProductException(
        'argument_required',
        'Argument "$name" is required.',
        details: <String, dynamic>{'argument': name},
      );
    }
    return value;
  }

  static bool _ignored(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.split('/').any(
          const <String>{
            '.git',
            '.dart_tool',
            'build',
            'node_modules',
            '.venv',
            '__pycache__',
            '.kristin',
          }.contains,
        );
  }

  static List<String> _validateProcess(
    ToolContext context,
    String executable,
    List<String> args,
  ) {
    final name = executable.replaceAll('\\', '/').split('/').last.toLowerCase();
    const denied = <String>{
      'rm',
      'rmdir',
      'del',
      'erase',
      'format',
      'mkfs',
      'diskpart',
      'shutdown',
      'reboot',
      'sudo',
      'su',
      'doas',
      'reg',
      'regedit',
      'sc',
      'net',
      'chmod',
      'chown',
      'dd',
    };
    if (denied.contains(name)) {
      throw ProductException(
        'executable_rejected',
        'Executable $name is not allowed.',
      );
    }
    if (name == 'sh' ||
        name == 'bash' ||
        name == 'zsh' ||
        name == 'cmd' ||
        name == 'powershell' ||
        name == 'pwsh') {
      throw ProductException(
        'shell_rejected',
        'Shell interpreters are not available to the agent. Use an executable and argument array.',
      );
    }
    if (args.any((arg) => arg.contains('\u0000'))) {
      throw ProductException(
        'argument_nul_rejected',
        'NUL bytes are not allowed in process arguments.',
      );
    }
    if ((name == 'git' || name == 'git.exe') &&
        args.any(
          (arg) =>
              arg == '-C' ||
              arg.startsWith('--git-dir') ||
              arg.startsWith('--work-tree'),
        )) {
      throw ProductException(
        'process_scope_argument_rejected',
        'Git working-directory and repository-root overrides are not allowed. Use git_status or git_diff so Kristin always operates on the selected project.',
      );
    }
    return args.map((argument) {
      final equals = argument.indexOf('=');
      final prefix = equals > 0 ? argument.substring(0, equals + 1) : '';
      final value = equals > 0 ? argument.substring(equals + 1) : argument;
      if (!_looksAbsoluteProcessPath(value)) {
        return argument;
      }
      try {
        final normalized = context.boundary.normalizeToolPath(value);
        return '$prefix$normalized';
      } on ProductException catch (error) {
        throw ProductException(
          'process_path_outside_project',
          'A process argument contains an absolute path outside the selected project. Use a project-relative path or a dedicated project-scoped tool.',
          details: <String, dynamic>{
            'argumentHash': Sha256.text(value),
            'causeCode': error.code,
          },
        );
      }
    }).toList(growable: false);
  }

  static bool _looksAbsoluteProcessPath(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('http://') ||
        trimmed.startsWith('https://')) {
      return false;
    }
    final windowsSlashOption = Platform.isWindows &&
        RegExp(
          r'^/(?:[QqSsDdYyNn]|\?|nologo|restore|m|v:[^/\\]*|p:[^/\\]*|property:[^/\\]*|target:[^/\\]*|verbosity:[^/\\]*)$',
          caseSensitive: false,
        ).hasMatch(trimmed);
    final unixAbsolute = trimmed.startsWith('/') && !windowsSlashOption;
    return unixAbsolute ||
        trimmed.toLowerCase().startsWith('file:') ||
        RegExp(r'^[A-Za-z]:[/\\]').hasMatch(trimmed) ||
        trimmed.startsWith('\\\\');
  }

  static bool _isNotGitRepository(Map<String, dynamic> result) {
    if (result['exitCode'] == 0) {
      return false;
    }
    final stderr = result['stderr']?.toString().toLowerCase() ?? '';
    return stderr.contains('not a git repository');
  }

  static bool _usesNetwork(String executable, List<String> args) {
    final name = executable.replaceAll('\\', '/').split('/').last.toLowerCase();
    if (const <String>{
      'curl',
      'wget',
      'git',
      'npm',
      'npx',
      'pnpm',
      'yarn',
      'pip',
      'pip3',
      'cargo',
      'go',
      'ollama',
    }.contains(name)) {
      final joined = args.join(' ').toLowerCase();
      if (name == 'git') {
        return RegExp(
          r'\b(clone|fetch|pull|push|remote|ls-remote|submodule)\b',
        ).hasMatch(joined);
      }
      if (name == 'npm') {
        return !RegExp(r'^\s*(test|run|exec)\b').hasMatch(joined);
      }
      return true;
    }
    return false;
  }

  static Map<String, String> _safeEnvironment() {
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

  static Future<Map<String, dynamic>> _runFinite({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    required Map<String, String> environment,
    required Duration timeout,
    required CancellationSignal cancellation,
    required SecretRedactor redactor,
    int maxOutputBytes = 4 * 1024 * 1024,
    void Function(String stream, String delta)? onOutput,
  }) async {
    cancellation.throwIfCancelled();
    final started = DateTime.now().toUtc();
    Process process;
    try {
      final launch = await resolveProcessLaunchTarget(executable);
      process = await Process.start(
        launch.executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: launch.runInShell,
        mode: ProcessStartMode.normal,
      );
    } on ProcessException catch (error) {
      throw ProductErrorNormalizer.normalize(error, executable: executable);
    }
    final stdoutBytes = BytesBuilder(copy: false);
    final stderrBytes = BytesBuilder(copy: false);
    var truncated = false;

    Future<void> collect(
      Stream<List<int>> stream,
      BytesBuilder builder,
      String streamName,
    ) async {
      await for (final chunk in stream) {
        if (onOutput != null && chunk.isNotEmpty) {
          var live = redactor.redact(utf8.decode(chunk, allowMalformed: true));
          if (live.length > 65536) {
            live = live.substring(0, 65536);
          }
          if (live.isNotEmpty) {
            try {
              onOutput(streamName, live);
            } catch (_) {
              // Live presentation must never change command execution semantics.
            }
          }
        }
        if (builder.length + chunk.length <= maxOutputBytes) {
          builder.add(chunk);
        } else {
          final remaining = max(0, maxOutputBytes - builder.length);
          if (remaining > 0) {
            builder.add(chunk.sublist(0, min(chunk.length, remaining)));
          }
          truncated = true;
        }
      }
    }

    final output = collect(process.stdout, stdoutBytes, 'stdout');
    final errors = collect(process.stderr, stderrBytes, 'stderr');
    // The subscription is cancelled in the finally block below.
    // ignore: cancel_subscriptions
    final cancelSubscription = cancellation.cancelled.asStream().listen((_) {
      process.kill(ProcessSignal.sigterm);
      Future<void>.delayed(
        const Duration(seconds: 2),
        () => process.kill(ProcessSignal.sigkill),
      );
    });
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill(ProcessSignal.sigterm);
          Future<void>.delayed(
            const Duration(seconds: 2),
            () => process.kill(ProcessSignal.sigkill),
          );
          return -124;
        },
      );
      await Future.wait(<Future<void>>[output, errors]);
    } finally {
      await cancelSubscription.cancel();
    }
    final stdoutText = redactor.redact(
      utf8.decode(stdoutBytes.takeBytes(), allowMalformed: true),
    );
    final stderrText = redactor.redact(
      utf8.decode(stderrBytes.takeBytes(), allowMalformed: true),
    );
    return <String, dynamic>{
      'executable': executable,
      'arguments': arguments,
      'exitCode': exitCode,
      'stdout': stdoutText,
      'stderr': stderrText,
      'truncated': truncated,
      'startedAt': started.toIso8601String(),
      'completedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }
}

Future<String> _resolveExistingEntityPath(String path) async {
  final followed = FileSystemEntity.typeSync(path, followLinks: true);
  if (followed == FileSystemEntityType.directory) {
    return Directory(path).resolveSymbolicLinks();
  }
  if (followed == FileSystemEntityType.file) {
    return File(path).resolveSymbolicLinks();
  }
  final direct = FileSystemEntity.typeSync(path, followLinks: false);
  if (direct == FileSystemEntityType.link) {
    return Link(path).resolveSymbolicLinks();
  }
  throw FileSystemException('Path does not exist', path);
}
