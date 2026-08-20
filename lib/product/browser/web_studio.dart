import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../crypto_utils.dart';
import '../storage_security.dart' show ProductException;
import '../workspace_tools.dart';

enum P3WebStudioLanguage {
  html,
  css,
  javascript,
  json,
  text,
}

final class P3WebStudioLimits {
  const P3WebStudioLimits({
    this.maxFileBytes = 4 * 1024 * 1024,
    this.maxTreeEntries = 5000,
    this.maxTreeDepth = 12,
    this.maxSearchFiles = 2000,
    this.maxSearchMatches = 2000,
    this.maxSearchFileBytes = 2 * 1024 * 1024,
    this.maxQueryCharacters = 256,
  });

  final int maxFileBytes;
  final int maxTreeEntries;
  final int maxTreeDepth;
  final int maxSearchFiles;
  final int maxSearchMatches;
  final int maxSearchFileBytes;
  final int maxQueryCharacters;

  void validate() {
    if (maxFileBytes < 1024 ||
        maxFileBytes > 32 * 1024 * 1024 ||
        maxTreeEntries < 1 ||
        maxTreeEntries > 50000 ||
        maxTreeDepth < 1 ||
        maxTreeDepth > 64 ||
        maxSearchFiles < 1 ||
        maxSearchFiles > 20000 ||
        maxSearchMatches < 1 ||
        maxSearchMatches > 20000 ||
        maxSearchFileBytes < 1024 ||
        maxSearchFileBytes > 16 * 1024 * 1024 ||
        maxQueryCharacters < 1 ||
        maxQueryCharacters > 4096) {
      throw StateError('web_studio_limits_invalid');
    }
  }
}

final class P3WebStudioFileNode {
  const P3WebStudioFileNode({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.language,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final int sizeBytes;
  final DateTime? modifiedAt;
  final P3WebStudioLanguage? language;
}

final class P3WebStudioDocument {
  const P3WebStudioDocument({
    required this.path,
    required this.content,
    required this.sha256,
    required this.language,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.exists,
  });

  final String path;
  final String content;
  final String sha256;
  final P3WebStudioLanguage language;
  final int sizeBytes;
  final DateTime? modifiedAt;
  final bool exists;

  bool isChanged(String nextContent) => Sha256.text(nextContent) != sha256;
}

final class P3WebStudioSaveResult {
  const P3WebStudioSaveResult({
    required this.path,
    required this.beforeHash,
    required this.afterHash,
    required this.operation,
  });

  final String path;
  final String beforeHash;
  final String afterHash;
  final String operation;
}

final class P3WebStudioSearchMatch {
  const P3WebStudioSearchMatch({
    required this.path,
    required this.line,
    required this.column,
    required this.preview,
  });

  final String path;
  final int line;
  final int column;
  final String preview;
}

final class P3WebStudioSearchResult {
  const P3WebStudioSearchResult({
    required this.matches,
    required this.filesScanned,
    required this.filesSkipped,
    required this.truncated,
  });

  final List<P3WebStudioSearchMatch> matches;
  final int filesScanned;
  final int filesSkipped;
  final bool truncated;
}

final class P3WebStudioDiffHunk {
  const P3WebStudioDiffHunk({
    required this.oldStartLine,
    required this.newStartLine,
    required this.removed,
    required this.added,
  });

  final int oldStartLine;
  final int newStartLine;
  final List<String> removed;
  final List<String> added;
}

final class P3WebStudioDiff {
  const P3WebStudioDiff({
    required this.beforeHash,
    required this.afterHash,
    required this.changed,
    required this.hunks,
  });

  final String beforeHash;
  final String afterHash;
  final bool changed;
  final List<P3WebStudioDiffHunk> hunks;
}

enum P3WebStudioDiagnosticSeverity { info, warning, error }

final class P3WebStudioDiagnostic {
  const P3WebStudioDiagnostic({
    required this.path,
    required this.message,
    required this.severity,
    this.line,
    this.column,
    this.code,
  });

  final String path;
  final String message;
  final P3WebStudioDiagnosticSeverity severity;
  final int? line;
  final int? column;
  final String? code;
}

final class P3WebStudioSourceState {
  const P3WebStudioSourceState({
    required this.path,
    required this.status,
    this.diff = '',
  });

  final String path;
  final String status;
  final String diff;
}

abstract interface class P3WebStudioMutationWriter {
  Future<P3WebStudioSaveResult> write({
    required String path,
    required String content,
    required String expectedHash,
    required bool expectedExists,
  });
}

final class P3WorkspaceTransactionMutationWriter
    implements P3WebStudioMutationWriter {
  P3WorkspaceTransactionMutationWriter(this.transaction);

  final WorkspaceTransaction transaction;
  int _operation = 0;

  @override
  Future<P3WebStudioSaveResult> write({
    required String path,
    required String content,
    required String expectedHash,
    required bool expectedExists,
  }) async {
    _operation += 1;
    final record = await transaction.runOperation<MutationRecord>(
      idempotencyKey: 'web-studio-save-$_operation-${Sha256.text(path)}',
      workItemId: 'P3-012',
      action: () => transaction.writeText(
        relativePath: path,
        content: content,
        expectedHash: expectedHash,
        expectedExists: expectedExists,
      ),
    );
    return P3WebStudioSaveResult(
      path: record.relativePath,
      beforeHash: record.beforeHash,
      afterHash: record.afterHash,
      operation: record.operation,
    );
  }
}

abstract interface class P3WebStudioFormatter {
  Future<String> format({
    required String path,
    required P3WebStudioLanguage language,
    required String content,
  });
}

abstract interface class P3WebStudioDiagnosticsProvider {
  Future<List<P3WebStudioDiagnostic>> inspect(P3WebStudioDocument document);
}

abstract interface class P3WebStudioSourceControl {
  Future<P3WebStudioSourceState> inspect(String path);
}

final class P3WebStudioEditor {
  P3WebStudioEditor({
    required this.boundary,
    required this.mutations,
    this.formatter,
    this.diagnostics,
    this.sourceControl,
    this.limits = const P3WebStudioLimits(),
  }) {
    limits.validate();
  }

  final WorkspaceBoundary boundary;
  final P3WebStudioMutationWriter mutations;
  final P3WebStudioFormatter? formatter;
  final P3WebStudioDiagnosticsProvider? diagnostics;
  final P3WebStudioSourceControl? sourceControl;
  final P3WebStudioLimits limits;

  static const Set<String> _ignoredDirectoryNames = <String>{
    '.git',
    '.dart_tool',
    '.idea',
    '.vscode',
    'node_modules',
    'build',
    'dist',
    'coverage',
  };

  static const Set<String> _searchableExtensions = <String>{
    '.html',
    '.htm',
    '.css',
    '.js',
    '.mjs',
    '.cjs',
    '.json',
    '.txt',
    '.md',
    '.yaml',
    '.yml',
  };

  static P3WebStudioLanguage languageForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      return P3WebStudioLanguage.html;
    }
    if (lower.endsWith('.css')) return P3WebStudioLanguage.css;
    if (lower.endsWith('.js') ||
        lower.endsWith('.mjs') ||
        lower.endsWith('.cjs')) {
      return P3WebStudioLanguage.javascript;
    }
    if (lower.endsWith('.json')) return P3WebStudioLanguage.json;
    return P3WebStudioLanguage.text;
  }

  Future<List<P3WebStudioFileNode>> fileTree({String root = '.'}) async {
    final directory =
        await boundary.directory(boundary.normalizeToolPath(root));
    final result = <P3WebStudioFileNode>[];
    await _walkTree(directory, 0, result);
    result.sort((left, right) {
      if (left.isDirectory != right.isDirectory) {
        return left.isDirectory ? -1 : 1;
      }
      return left.path.toLowerCase().compareTo(right.path.toLowerCase());
    });
    return List<P3WebStudioFileNode>.unmodifiable(result);
  }

  Future<void> _walkTree(
    Directory directory,
    int depth,
    List<P3WebStudioFileNode> output,
  ) async {
    if (depth > limits.maxTreeDepth || output.length >= limits.maxTreeEntries) {
      return;
    }
    final entities = await directory.list(followLinks: false).toList();
    entities
        .sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    for (final entity in entities) {
      if (output.length >= limits.maxTreeEntries) return;
      if (entity is Link) continue;
      final path = boundary.relative(entity.path);
      final name = _basename(entity);
      if (entity is Directory && _ignoredDirectoryNames.contains(name)) {
        continue;
      }
      if (entity is Directory) {
        output.add(
          P3WebStudioFileNode(
            path: path,
            name: name,
            isDirectory: true,
            sizeBytes: 0,
            modifiedAt: null,
            language: null,
          ),
        );
        if (depth < limits.maxTreeDepth) {
          await _walkTree(entity, depth + 1, output);
        }
        continue;
      }
      if (entity is! File) continue;
      final stat = await entity.stat();
      output.add(
        P3WebStudioFileNode(
          path: path,
          name: name,
          isDirectory: false,
          sizeBytes: stat.size,
          modifiedAt: stat.modified.toUtc(),
          language: languageForPath(path),
        ),
      );
    }
  }

  Future<P3WebStudioDocument> open(String path) async {
    final normalized = boundary.normalizeToolPath(path);
    final file = await boundary.file(normalized);
    final stat = await file.stat();
    if (stat.size > limits.maxFileBytes) {
      throw ProductException(
        'web_studio_file_too_large',
        'The file exceeds the Web Studio editor limit.',
        details: <String, dynamic>{
          'path': normalized,
          'sizeBytes': stat.size,
          'maxBytes': limits.maxFileBytes,
        },
      );
    }
    final bytes = await file.readAsBytes();
    return P3WebStudioDocument(
      path: normalized,
      content: _decodeText(bytes, normalized),
      sha256: Sha256.hex(bytes),
      language: languageForPath(normalized),
      sizeBytes: bytes.length,
      modifiedAt: stat.modified.toUtc(),
      exists: true,
    );
  }

  P3WebStudioDocument newDocument(String path, {String content = ''}) {
    final normalized = boundary.normalizeToolPath(path);
    final bytes = utf8.encode(content);
    if (bytes.length > limits.maxFileBytes) {
      throw StateError('web_studio_file_too_large');
    }
    return P3WebStudioDocument(
      path: normalized,
      content: content,
      sha256: '',
      language: languageForPath(normalized),
      sizeBytes: bytes.length,
      modifiedAt: null,
      exists: false,
    );
  }

  Future<P3WebStudioDocument> save(
    P3WebStudioDocument source,
    String content,
  ) async {
    final bytes = utf8.encode(content);
    if (bytes.length > limits.maxFileBytes) {
      throw ProductException(
        'web_studio_file_too_large',
        'The edited file exceeds the Web Studio editor limit.',
      );
    }
    await mutations.write(
      path: source.path,
      content: content,
      expectedHash: source.sha256,
      expectedExists: source.exists,
    );
    final file = await boundary.file(source.path);
    final stat = await file.stat();
    final savedBytes = await file.readAsBytes();
    return P3WebStudioDocument(
      path: source.path,
      content: _decodeText(savedBytes, source.path),
      sha256: Sha256.hex(savedBytes),
      language: source.language,
      sizeBytes: savedBytes.length,
      modifiedAt: stat.modified.toUtc(),
      exists: true,
    );
  }

  Future<String> format(P3WebStudioDocument source, String content) async {
    final hook = formatter;
    if (hook == null) throw StateError('web_studio_formatter_unavailable');
    final formatted = await hook.format(
      path: source.path,
      language: source.language,
      content: content,
    );
    if (utf8.encode(formatted).length > limits.maxFileBytes) {
      throw StateError('web_studio_formatted_file_too_large');
    }
    return formatted;
  }

  Future<List<P3WebStudioDiagnostic>> inspect(
    P3WebStudioDocument source,
  ) async {
    final hook = diagnostics;
    if (hook == null) return const <P3WebStudioDiagnostic>[];
    return List<P3WebStudioDiagnostic>.unmodifiable(await hook.inspect(source));
  }

  Future<P3WebStudioSourceState> sourceState(String path) async {
    final hook = sourceControl;
    if (hook == null) throw StateError('web_studio_source_control_unavailable');
    return hook.inspect(boundary.normalizeToolPath(path));
  }

  P3WebStudioDiff diff(P3WebStudioDocument source, String content) {
    final beforeHash = source.sha256;
    final afterHash = Sha256.text(content);
    if (beforeHash == afterHash) {
      return P3WebStudioDiff(
        beforeHash: beforeHash,
        afterHash: afterHash,
        changed: false,
        hunks: const <P3WebStudioDiffHunk>[],
      );
    }

    final before = _lines(source.content);
    final after = _lines(content);
    var prefix = 0;
    while (prefix < before.length &&
        prefix < after.length &&
        before[prefix] == after[prefix]) {
      prefix += 1;
    }
    var suffix = 0;
    while (suffix < before.length - prefix &&
        suffix < after.length - prefix &&
        before[before.length - suffix - 1] ==
            after[after.length - suffix - 1]) {
      suffix += 1;
    }

    return P3WebStudioDiff(
      beforeHash: beforeHash,
      afterHash: afterHash,
      changed: true,
      hunks: <P3WebStudioDiffHunk>[
        P3WebStudioDiffHunk(
          oldStartLine: prefix + 1,
          newStartLine: prefix + 1,
          removed: List<String>.unmodifiable(
            before.sublist(prefix, before.length - suffix),
          ),
          added: List<String>.unmodifiable(
            after.sublist(prefix, after.length - suffix),
          ),
        ),
      ],
    );
  }

  Future<P3WebStudioSearchResult> search(
    String query, {
    String root = '.',
    bool caseSensitive = false,
  }) async {
    if (query.isEmpty || query.length > limits.maxQueryCharacters) {
      throw StateError('web_studio_search_query_invalid');
    }
    final directory =
        await boundary.directory(boundary.normalizeToolPath(root));
    final matches = <P3WebStudioSearchMatch>[];
    var filesScanned = 0;
    var filesSkipped = 0;
    var truncated = false;
    final expected = caseSensitive ? query : query.toLowerCase();

    Future<void> scan(Directory current, int depth) async {
      if (truncated || depth > limits.maxTreeDepth) return;
      final entities = await current.list(followLinks: false).toList();
      entities
          .sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
      for (final entity in entities) {
        if (truncated) return;
        if (entity is Link) continue;
        final path = boundary.relative(entity.path);
        if (entity is Directory) {
          if (_ignoredDirectoryNames.contains(_basename(entity))) {
            filesSkipped += 1;
            continue;
          }
          await scan(entity, depth + 1);
          continue;
        }
        if (entity is! File) continue;
        if (!_isSearchable(path)) {
          filesSkipped += 1;
          continue;
        }
        if (filesScanned >= limits.maxSearchFiles) {
          truncated = true;
          return;
        }
        final stat = await entity.stat();
        if (stat.size > limits.maxSearchFileBytes) {
          filesSkipped += 1;
          continue;
        }
        filesScanned += 1;
        late final String content;
        try {
          content = _decodeText(await entity.readAsBytes(), path);
        } on ProductException {
          filesSkipped += 1;
          continue;
        }
        final lines = _lines(content);
        for (var lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
          final line = lines[lineIndex];
          final haystack = caseSensitive ? line : line.toLowerCase();
          var start = 0;
          while (start <= haystack.length) {
            final index = haystack.indexOf(expected, start);
            if (index < 0) break;
            matches.add(
              P3WebStudioSearchMatch(
                path: path,
                line: lineIndex + 1,
                column: index + 1,
                preview: _preview(line, index, query.length),
              ),
            );
            if (matches.length >= limits.maxSearchMatches) {
              truncated = true;
              return;
            }
            start = index + max(1, expected.length);
          }
        }
      }
    }

    await scan(directory, 0);
    return P3WebStudioSearchResult(
      matches: List<P3WebStudioSearchMatch>.unmodifiable(matches),
      filesScanned: filesScanned,
      filesSkipped: filesSkipped,
      truncated: truncated,
    );
  }

  bool _isSearchable(String path) {
    final lower = path.toLowerCase();
    return _searchableExtensions.any(lower.endsWith);
  }

  String _basename(FileSystemEntity entity) =>
      entity.uri.pathSegments.where((segment) => segment.isNotEmpty).last;

  String _decodeText(List<int> bytes, String path) {
    if (bytes.contains(0)) {
      throw ProductException(
        'web_studio_binary_file_rejected',
        'Web Studio cannot open binary files.',
        details: <String, dynamic>{'path': path},
      );
    }
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw ProductException(
        'web_studio_non_utf8_file_rejected',
        'Web Studio currently supports UTF-8 text files only.',
        details: <String, dynamic>{'path': path},
      );
    }
  }

  List<String> _lines(String value) => value.split(RegExp(r'\r?\n'));

  String _preview(String line, int index, int length) {
    const radius = 80;
    final start = max(0, index - radius);
    final end = min(line.length, index + length + radius);
    return line.substring(start, end);
  }
}
