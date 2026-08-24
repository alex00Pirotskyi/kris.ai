import 'dart:io';

import 'crypto_utils.dart';
import 'domain.dart';
import 'storage_security.dart';
import 'tool_schema.dart';
import 'workspace_tools_base.dart.inc' as base;

export 'workspace_tools_base.dart.inc' hide ToolRegistry;

/// Product-facing tool registry adapter for command execution reliability.
///
/// The mature tool implementations remain in [base.ToolRegistry]. This adapter
/// keeps their permissions, schemas, durable idempotency, workspace boundary,
/// and process policy intact while adding two pieces of evidence that a finite
/// process cannot report on its own: conservative argv compatibility
/// normalization and bounded project-local filesystem deltas.
class ToolRegistry {
  ToolRegistry._(this._delegate);

  factory ToolRegistry.standard() => ToolRegistry._(base.ToolRegistry.standard());

  final base.ToolRegistry _delegate;

  ToolSchemaRegistry get schemas => _delegate.schemas;

  Set<String> get names => _delegate.names;

  ToolContract contractFor(String name) => _delegate.contractFor(name);

  bool isMutatingTool(String name) => _delegate.isMutatingTool(name);

  Set<String> allowedToolNames(Iterable<String> requested) =>
      _delegate.allowedToolNames(requested);

  Set<PermissionScope> permissionsForTools(Iterable<String> names) =>
      _delegate.permissionsForTools(names);

  List<Map<String, dynamic>> descriptors({
    Set<String>? allowlist,
    ToolDescriptorDialect dialect = ToolDescriptorDialect.canonical,
  }) =>
      _delegate.descriptors(allowlist: allowlist, dialect: dialect);

  Future<base.ToolResult> execute(
    String name,
    Map<String, dynamic> arguments,
    base.ToolContext context,
  ) async {
    if (name != 'run_command') {
      return _delegate.execute(name, arguments, context);
    }

    final normalized = await _normalizeFiniteCommand(arguments, context);
    final before = await _WorkspaceSnapshot.capture(context.boundary.root);
    final result = await _delegate.execute(name, normalized.arguments, context);
    final after = await _WorkspaceSnapshot.capture(context.boundary.root);
    final changes = _WorkspaceChanges.between(before, after);
    final data = <String, dynamic>{
      ...result.data,
      'workingDirectory': context.boundary.root.path,
      'arguments': normalized.arguments['args'] is List
          ? List<String>.unmodifiable(
              (normalized.arguments['args']! as List)
                  .map((value) => value.toString()),
            )
          : const <String>[],
      'workspaceChanges': changes.toJson(),
      'beforeHash': before.aggregateSha256,
      'afterHash': after.aggregateSha256,
      if (normalized.duplicateExecutableRemoved)
        'duplicateExecutableRemoved': true,
      if (normalized.blankProjectScaffoldNormalized)
        'blankProjectScaffoldNormalized': true,
    };
    final adjusted = base.ToolResult(
      ok: result.ok,
      summary: result.summary,
      data: Map<String, dynamic>.unmodifiable(data),
      mutated: changes.paths.isNotEmpty,
    );
    _delegate.contractFor(name).validateOutput(adjusted.toJson());
    await context.audit.append(
      'tool.run_command_workspace_delta',
      context.runId,
      <String, dynamic>{
        'workItemId': context.workItem.id,
        'ok': adjusted.ok,
        'mutated': adjusted.mutated,
        'workspaceChanges': changes.toJson(),
        'beforeHash': before.aggregateSha256,
        'afterHash': after.aggregateSha256,
      },
    );
    await context.workflow.createCheckpoint(
      runId: context.runId,
      workItemId: context.workItem.id,
      kind: 'run_command_workspace_delta',
      state: <String, dynamic>{
        'attempt': context.attempt,
        'inputHash': Sha256.text(canonicalJson(normalized.arguments)),
        'ok': adjusted.ok,
        'mutated': adjusted.mutated,
        'workspaceChanges': changes.toJson(),
        'beforeHash': before.aggregateSha256,
        'afterHash': after.aggregateSha256,
      },
    );
    return adjusted;
  }

  Future<_NormalizedFiniteCommand> _normalizeFiniteCommand(
    Map<String, dynamic> source,
    base.ToolContext context,
  ) async {
    final arguments = <String, dynamic>{...source};
    final executable = arguments['executable']?.toString().trim() ?? '';
    final rawArgs = arguments['args'];
    final values = rawArgs is List
        ? rawArgs.map((value) => value.toString()).toList(growable: true)
        : <String>[];
    var duplicateRemoved = false;
    var scaffoldNormalized = false;

    if (values.isNotEmpty &&
        _sameExecutableToken(executable, values.first)) {
      values.removeAt(0);
      duplicateRemoved = true;
      await context.audit.append(
        'tool.run_command_argv_normalized',
        context.runId,
        <String, dynamic>{
          'workItemId': context.workItem.id,
          'reason': 'duplicated_leading_executable',
          'executable': _executableToken(executable),
        },
      );
    }

    if (_sameExecutableToken(executable, 'flutter') &&
        values.length >= 2 &&
        values.first == 'create' &&
        await _isSemanticallyBlank(context.boundary.root)) {
      final target = values[1].trim();
      if (target != '.') {
        if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(target)) {
          throw ProductException(
            'blank_project_nested_scaffold_rejected',
            'A blank selected project must be scaffolded in the active project root. Use flutter create . with a valid --project-name instead of creating a nested path.',
            details: <String, dynamic>{
              'targetHash': Sha256.text(target),
              'activeProjectRootHash':
                  Sha256.text(context.boundary.root.path),
            },
          );
        }
        values[1] = '.';
        final hasProjectName = values.any(
          (value) => value == '--project-name' ||
              value.startsWith('--project-name='),
        );
        if (!hasProjectName) {
          values.addAll(<String>['--project-name', target]);
        }
        scaffoldNormalized = true;
        await context.audit.append(
          'tool.blank_project_scaffold_normalized',
          context.runId,
          <String, dynamic>{
            'workItemId': context.workItem.id,
            'tool': 'run_command',
            'executable': 'flutter',
            'normalizedTarget': '.',
            'projectName': target,
          },
        );
      }
    }

    arguments['args'] = values;
    return _NormalizedFiniteCommand(
      arguments: Map<String, dynamic>.unmodifiable(arguments),
      duplicateExecutableRemoved: duplicateRemoved,
      blankProjectScaffoldNormalized: scaffoldNormalized,
    );
  }

  bool _sameExecutableToken(String left, String right) {
    final a = _executableToken(left);
    final b = _executableToken(right);
    return a.isNotEmpty && a == b;
  }

  String _executableToken(String value) {
    var token = value.trim().replaceAll('\\', '/');
    if (token.contains('/')) {
      token = token.substring(token.lastIndexOf('/') + 1);
    }
    token = token.toLowerCase();
    for (final suffix in const <String>['.exe', '.cmd', '.bat']) {
      if (token.endsWith(suffix)) {
        token = token.substring(0, token.length - suffix.length);
        break;
      }
    }
    return token;
  }

  Future<bool> _isSemanticallyBlank(Directory root) async {
    await for (final entity in root.list(followLinks: false)) {
      final name = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      if (!_WorkspaceSnapshot.ignoredSegments.contains(name)) {
        return false;
      }
    }
    return true;
  }
}

class _NormalizedFiniteCommand {
  const _NormalizedFiniteCommand({
    required this.arguments,
    required this.duplicateExecutableRemoved,
    required this.blankProjectScaffoldNormalized,
  });

  final Map<String, dynamic> arguments;
  final bool duplicateExecutableRemoved;
  final bool blankProjectScaffoldNormalized;
}

class _WorkspaceSnapshot {
  const _WorkspaceSnapshot({
    required this.entries,
    required this.complete,
    required this.hashedBytes,
  });

  static const int maxEntries = 4096;
  static const int maxHashedBytes = 64 * 1024 * 1024;
  static const int maxSingleFileBytes = 8 * 1024 * 1024;
  static const Set<String> ignoredSegments = <String>{
    '.git',
    '.dart_tool',
    '.kristin',
    'build',
    'node_modules',
    '.venv',
    '__pycache__',
  };

  final Map<String, String> entries;
  final bool complete;
  final int hashedBytes;

  String get aggregateSha256 => Sha256.text(canonicalJson(entries));

  static Future<_WorkspaceSnapshot> capture(Directory root) async {
    final entries = <String, String>{};
    var complete = true;
    var hashedBytes = 0;
    var observed = 0;
    final entities = <FileSystemEntity>[];
    await for (final entity in root.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entities.length >= maxEntries * 2) {
        complete = false;
        break;
      }
      entities.add(entity);
    }
    entities.sort((a, b) => a.path.compareTo(b.path));

    for (final entity in entities) {
      final relative = _relative(root, entity.path);
      if (relative.isEmpty || _ignored(relative)) {
        continue;
      }
      if (observed >= maxEntries) {
        complete = false;
        break;
      }
      observed++;
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        entries[relative] = 'directory';
        continue;
      }
      if (type != FileSystemEntityType.file) {
        continue;
      }
      final file = File(entity.path);
      final stat = await file.stat();
      if (stat.size <= maxSingleFileBytes &&
          hashedBytes + stat.size <= maxHashedBytes) {
        final bytes = await file.readAsBytes();
        hashedBytes += bytes.length;
        entries[relative] = 'sha256:${Sha256.hex(bytes)}';
      } else {
        complete = false;
        entries[relative] = 'stat:${stat.size}:'
            '${stat.modified.toUtc().microsecondsSinceEpoch}';
      }
    }
    return _WorkspaceSnapshot(
      entries: Map<String, String>.unmodifiable(entries),
      complete: complete,
      hashedBytes: hashedBytes,
    );
  }

  static String _relative(Directory root, String absolute) {
    final rootPath = root.absolute.path.replaceAll('\\', '/');
    final path = File(absolute).absolute.path.replaceAll('\\', '/');
    if (path == rootPath) {
      return '';
    }
    return path.startsWith('$rootPath/')
        ? path.substring(rootPath.length + 1)
        : path;
  }

  static bool _ignored(String path) {
    final segments = path.split('/');
    return segments.any(ignoredSegments.contains);
  }
}

class _WorkspaceChanges {
  const _WorkspaceChanges({
    required this.paths,
    required this.added,
    required this.modified,
    required this.deleted,
    required this.beforeFingerprints,
    required this.afterFingerprints,
    required this.complete,
    required this.truncatedPaths,
  });

  static const int maxReportedPaths = 200;

  final List<String> paths;
  final List<String> added;
  final List<String> modified;
  final List<String> deleted;
  final Map<String, String> beforeFingerprints;
  final Map<String, String> afterFingerprints;
  final bool complete;
  final bool truncatedPaths;

  factory _WorkspaceChanges.between(
    _WorkspaceSnapshot before,
    _WorkspaceSnapshot after,
  ) {
    final all = <String>{...before.entries.keys, ...after.entries.keys}.toList()
      ..sort();
    final added = <String>[];
    final modified = <String>[];
    final deleted = <String>[];
    for (final path in all) {
      final left = before.entries[path];
      final right = after.entries[path];
      if (left == null && right != null) {
        added.add(path);
      } else if (left != null && right == null) {
        deleted.add(path);
      } else if (left != right) {
        modified.add(path);
      }
    }
    final changed = <String>[...added, ...modified, ...deleted]..sort();
    final reported = changed.take(maxReportedPaths).toList(growable: false);
    final reportedSet = reported.toSet();
    return _WorkspaceChanges(
      paths: List<String>.unmodifiable(reported),
      added: List<String>.unmodifiable(
        added.where(reportedSet.contains),
      ),
      modified: List<String>.unmodifiable(
        modified.where(reportedSet.contains),
      ),
      deleted: List<String>.unmodifiable(
        deleted.where(reportedSet.contains),
      ),
      beforeFingerprints: Map<String, String>.unmodifiable(<String, String>{
        for (final path in reported)
          if (before.entries[path] != null) path: before.entries[path]!,
      }),
      afterFingerprints: Map<String, String>.unmodifiable(<String, String>{
        for (final path in reported)
          if (after.entries[path] != null) path: after.entries[path]!,
      }),
      complete: before.complete && after.complete,
      truncatedPaths: changed.length > maxReportedPaths,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'paths': paths,
        'added': added,
        'modified': modified,
        'deleted': deleted,
        'beforeFingerprints': beforeFingerprints,
        'afterFingerprints': afterFingerprints,
        'complete': complete,
        'truncatedPaths': truncatedPaths,
      };
}
