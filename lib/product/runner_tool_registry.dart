import 'dart:io';

import 'crypto_utils.dart';
import 'domain.dart';
import 'storage_security.dart';
import 'tool_schema.dart';
import 'workspace_tools.dart';

final class RunnerToolRegistry implements ToolRegistry {
  RunnerToolRegistry._(this._delegate);

  factory RunnerToolRegistry.standard() =>
      RunnerToolRegistry._(ToolRegistry.standard());

  final ToolRegistry _delegate;

  @override
  ToolSchemaRegistry get schemas => _delegate.schemas;

  @override
  Set<String> get names => _delegate.names;

  @override
  ToolContract contractFor(String name) => _delegate.contractFor(name);

  @override
  bool isMutatingTool(String name) => _delegate.isMutatingTool(name);

  @override
  Set<String> allowedToolNames(Iterable<String> requested) =>
      _delegate.allowedToolNames(requested);

  @override
  Set<PermissionScope> permissionsForTools(Iterable<String> names) =>
      _delegate.permissionsForTools(names);

  @override
  List<Map<String, dynamic>> descriptors({
    Set<String>? allowlist,
    ToolDescriptorDialect dialect = ToolDescriptorDialect.canonical,
  }) =>
      _delegate.descriptors(allowlist: allowlist, dialect: dialect);

  @override
  Future<ToolResult> execute(
    String name,
    Map<String, dynamic> arguments,
    ToolContext context,
  ) async {
    if (name != 'run_command') {
      return _delegate.execute(name, arguments, context);
    }

    final rawInputHash = Sha256.text(canonicalJson(arguments));
    final replayKind = _replayCheckpointKind(
      context: context,
      rawInputHash: rawInputHash,
    );
    final prior = await context.workflow.latestCheckpoint(
      context.runId,
      kind: replayKind,
    );
    final normalized = prior == null
        ? await _normalizeFiniteCommand(arguments, context)
        : _normalizedFromCheckpoint(prior.state, context, rawInputHash);
    final normalizedInputHash = Sha256.text(
      canonicalJson(normalized.arguments),
    );

    final before = await _WorkspaceSnapshot.capture(context.boundary.root);
    final result = await _delegate.execute(name, normalized.arguments, context);
    final after = await _WorkspaceSnapshot.capture(context.boundary.root);
    final changes = _WorkspaceChanges.between(before, after);

    if (prior != null) {
      if (changes.paths.isNotEmpty) {
        throw ProductException(
          'run_command_replay_mutated_workspace',
          'An idempotent run_command replay changed the project workspace.',
          details: <String, dynamic>{
            'workItemId': context.workItem.id,
            'attempt': context.attempt,
            'rawInputHash': rawInputHash,
            'normalizedInputHash': normalizedInputHash,
            'workspaceChanges': changes.toJson(),
          },
        );
      }
      final restored = _restorePriorResult(
        base: result,
        state: prior.state,
        context: context,
        rawInputHash: rawInputHash,
        normalizedInputHash: normalizedInputHash,
      );
      _delegate.contractFor(name).validateOutput(restored.toJson());
      await context.audit.append(
        'tool.run_command_workspace_delta_replayed',
        context.runId,
        <String, dynamic>{
          'workItemId': context.workItem.id,
          'attempt': context.attempt,
          'rawInputHash': rawInputHash,
          'normalizedInputHash': normalizedInputHash,
          'mutated': restored.mutated,
          'checkpointSha256': prior.stateSha256,
        },
      );
      return restored;
    }

    final extras = <String, dynamic>{
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
    final adjusted = ToolResult(
      ok: result.ok,
      summary: result.summary,
      data: Map<String, dynamic>.unmodifiable(<String, dynamic>{
        ...result.data,
        ...extras,
      }),
      mutated: changes.paths.isNotEmpty,
    );
    _delegate.contractFor(name).validateOutput(adjusted.toJson());

    final state = <String, dynamic>{
      'schemaVersion': 1,
      'workItemId': context.workItem.id,
      'attempt': context.attempt,
      'rawInputHash': rawInputHash,
      'normalizedInputHash': normalizedInputHash,
      'normalizedArguments': normalized.arguments,
      'duplicateExecutableRemoved': normalized.duplicateExecutableRemoved,
      'blankProjectScaffoldNormalized':
          normalized.blankProjectScaffoldNormalized,
      'ok': adjusted.ok,
      'mutated': adjusted.mutated,
      'extras': extras,
    };
    await context.audit.append(
      'tool.run_command_workspace_delta',
      context.runId,
      <String, dynamic>{
        'workItemId': context.workItem.id,
        'attempt': context.attempt,
        'ok': adjusted.ok,
        'mutated': adjusted.mutated,
        'workspaceChanges': changes.toJson(),
        'beforeHash': before.aggregateSha256,
        'afterHash': after.aggregateSha256,
        'rawInputHash': rawInputHash,
        'normalizedInputHash': normalizedInputHash,
      },
    );
    await context.workflow.createCheckpoint(
      runId: context.runId,
      workItemId: context.workItem.id,
      kind: 'run_command_workspace_delta',
      state: state,
    );
    await context.workflow.createCheckpoint(
      runId: context.runId,
      workItemId: context.workItem.id,
      kind: replayKind,
      state: state,
    );
    return adjusted;
  }

  _NormalizedFiniteCommand _normalizedFromCheckpoint(
    Map<String, dynamic> state,
    ToolContext context,
    String rawInputHash,
  ) {
    if (state['schemaVersion'] != 1 ||
        state['workItemId']?.toString() != context.workItem.id ||
        state['attempt'] != context.attempt ||
        state['rawInputHash']?.toString() != rawInputHash ||
        state['normalizedArguments'] is! Map) {
      throw ProductException(
        'run_command_workspace_delta_checkpoint_invalid',
        'Stored run_command replay evidence does not match the active operation.',
      );
    }
    return _NormalizedFiniteCommand(
      arguments: Map<String, dynamic>.unmodifiable(
        mapValue(state['normalizedArguments']),
      ),
      duplicateExecutableRemoved: state['duplicateExecutableRemoved'] == true,
      blankProjectScaffoldNormalized:
          state['blankProjectScaffoldNormalized'] == true,
    );
  }

  ToolResult _restorePriorResult({
    required ToolResult base,
    required Map<String, dynamic> state,
    required ToolContext context,
    required String rawInputHash,
    required String normalizedInputHash,
  }) {
    if (state['schemaVersion'] != 1 ||
        state['workItemId']?.toString() != context.workItem.id ||
        state['attempt'] != context.attempt ||
        state['rawInputHash']?.toString() != rawInputHash ||
        state['normalizedInputHash']?.toString() != normalizedInputHash ||
        state['extras'] is! Map) {
      throw ProductException(
        'run_command_workspace_delta_checkpoint_invalid',
        'Stored run_command replay evidence does not match the active operation.',
      );
    }
    return ToolResult(
      ok: base.ok,
      summary: base.summary,
      data: Map<String, dynamic>.unmodifiable(<String, dynamic>{
        ...base.data,
        ...mapValue(state['extras']),
      }),
      mutated: state['mutated'] == true,
    );
  }

  String _replayCheckpointKind({
    required ToolContext context,
    required String rawInputHash,
  }) {
    final key = Sha256.text(
      canonicalJson(<String, dynamic>{
        'workItemId': context.workItem.id,
        'attempt': context.attempt,
        'rawInputHash': rawInputHash,
      }),
    );
    return 'run_command_workspace_delta:$key';
  }

  Future<_NormalizedFiniteCommand> _normalizeFiniteCommand(
    Map<String, dynamic> source,
    ToolContext context,
  ) async {
    final arguments = <String, dynamic>{...source};
    final executable = arguments['executable']?.toString().trim() ?? '';
    final rawArgs = arguments['args'];
    final values = rawArgs is List
        ? rawArgs.map((value) => value.toString()).toList(growable: true)
        : <String>[];
    var duplicateRemoved = false;
    var scaffoldNormalized = false;

    if (values.isNotEmpty && _sameExecutableToken(executable, values.first)) {
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
              'activeProjectRootHash': Sha256.text(context.boundary.root.path),
            },
          );
        }
        values[1] = '.';
        final hasProjectName = values.any(
          (value) =>
              value == '--project-name' || value.startsWith('--project-name='),
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
      final name =
          entity.uri.pathSegments.where((segment) => segment.isNotEmpty).last;
      if (!_WorkspaceSnapshot.ignoredSegments.contains(name)) {
        return false;
      }
    }
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NormalizedFiniteCommand {
  const _NormalizedFiniteCommand({
    required this.arguments,
    required this.duplicateExecutableRemoved,
    required this.blankProjectScaffoldNormalized,
  });

  final Map<String, dynamic> arguments;
  final bool duplicateExecutableRemoved;
  final bool blankProjectScaffoldNormalized;
}

final class _WorkspaceSnapshot {
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
        entries[relative] =
            'stat:${stat.size}:${stat.modified.toUtc().microsecondsSinceEpoch}';
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

final class _WorkspaceChanges {
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
      added: List<String>.unmodifiable(added.where(reportedSet.contains)),
      modified: List<String>.unmodifiable(modified.where(reportedSet.contains)),
      deleted: List<String>.unmodifiable(deleted.where(reportedSet.contains)),
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
