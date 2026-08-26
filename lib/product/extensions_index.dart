import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';

import 'crypto_utils.dart';
import 'domain.dart';
import 'performance_spans.dart';

class SourceIndexEntry {
  const SourceIndexEntry({
    required this.path,
    required this.sha256,
    required this.bytes,
    required this.modifiedAt,
    required this.language,
    required this.symbols,
    required this.dependencies,
    required this.text,
  });

  final String path;
  final String sha256;
  final int bytes;
  final DateTime modifiedAt;
  final String language;
  final List<String> symbols;
  final List<String> dependencies;
  final String text;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'path': path,
        'sha256': sha256,
        'bytes': bytes,
        'modifiedAt': modifiedAt.toUtc().toIso8601String(),
        'language': language,
        'symbols': symbols,
        'dependencies': dependencies,
        'text': text,
      };

  factory SourceIndexEntry.fromJson(Map<String, dynamic> json) =>
      SourceIndexEntry(
        path: json['path']?.toString() ?? '',
        sha256: json['sha256']?.toString() ?? '',
        bytes: int.tryParse(json['bytes']?.toString() ?? '') ?? 0,
        modifiedAt: parseUtc(json['modifiedAt'], fallback: DateTime.now()),
        language: json['language']?.toString() ?? 'text',
        symbols: stringList(json['symbols']),
        dependencies: stringList(json['dependencies']),
        text: json['text']?.toString() ?? '',
      );
}

class SourceIndexReport {
  const SourceIndexReport({
    required this.scanned,
    required this.changed,
    required this.removed,
    required this.skipped,
    required this.total,
    required this.generatedAt,
    this.generation = 0,
  });

  final int scanned;
  final int changed;
  final int removed;
  final int skipped;
  final int total;
  final DateTime generatedAt;
  final int generation;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'scanned': scanned,
        'changed': changed,
        'removed': removed,
        'skipped': skipped,
        'total': total,
        'generatedAt': generatedAt.toUtc().toIso8601String(),
        'generation': generation,
      };
}

class SourceIndexDiagnostics {
  const SourceIndexDiagnostics({
    required this.projectHash,
    required this.databasePath,
    required this.backend,
    required this.persistent,
    required this.initialized,
    required this.watcherActive,
    required this.generation,
    required this.files,
    required this.lastUpdateAt,
  });

  final String projectHash;
  final String databasePath;
  final String backend;
  final bool persistent;
  final bool initialized;
  final bool watcherActive;
  final int generation;
  final int files;
  final DateTime? lastUpdateAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'projectHash': projectHash,
        'databasePath': databasePath,
        'backend': backend,
        'persistent': persistent,
        'initialized': initialized,
        'watcherActive': watcherActive,
        'generation': generation,
        'files': files,
        'lastUpdateAt': lastUpdateAt?.toUtc().toIso8601String(),
      };
}

class SourceIndexService {
  SourceIndexService(
    this.indexDirectory, {
    PerformanceSpanSink performance = const NoopPerformanceSpanSink(),
  }) : _performance = performance;

  static const int _maxFiles = 25000;
  static const int _maxFileBytes = 2 * 1024 * 1024;
  static const int _maxStoredText = 200000;
  static const int _watchBatchSize = 512;
  static const Duration _watchDebounce = Duration(milliseconds: 120);

  final Directory indexDirectory;
  final PerformanceSpanSink _performance;
  final Map<String, _SourceProjectRuntime> _projects =
      <String, _SourceProjectRuntime>{};
  Future<_SourceSqliteStore>? _storeFuture;
  Future<void> _mutationTail = Future<void>.value();
  bool _closed = false;

  Future<_SourceSqliteStore> _store() {
    if (_closed) {
      throw StateError('source_index_closed');
    }
    return _storeFuture ??= _SourceSqliteStore.open(indexDirectory);
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _mutationTail = _mutationTail.then<void>((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<SourceIndexReport> update(ProjectRecord project) {
    return _serialize<SourceIndexReport>(() async {
      final store = await _store();
      final projectHash = Sha256.text(project.id);
      var before = store.projectInfo(projectHash);
      final span = PerformanceSpan.start(
        'source.index.update',
        sink: _performance,
        projectHash: projectHash,
        cacheResult: before?.initialized == true
            ? PerformanceCacheResult.hit
            : PerformanceCacheResult.miss,
        thermalState: before?.initialized == true
            ? PerformanceThermalState.warm
            : PerformanceThermalState.cold,
        taskClass: 'reconcile',
      );
      try {
        final root = await _canonicalProjectRoot(project);
        final rootHash = Sha256.text(_normalizedAbsolute(root.path));
        if (before != null &&
            before.rootHash.isNotEmpty &&
            before.rootHash != rootHash) {
          store.resetProjectRoot(projectHash, rootHash);
          before = store.projectInfo(projectHash);
          await _replaceRuntime(projectHash, null);
        }
        final result = await _reconcileProject(
          store,
          project,
          projectHash,
          root,
          rootHash,
        );
        await _ensureWatcher(project, projectHash, root, rootHash);
        span.finish(
          itemCount: result.report.total,
          bytesConsidered: result.bytesConsidered,
          candidateCount: result.report.scanned,
        );
        return result.report;
      } catch (error, stackTrace) {
        try {
          span.finish(outcome: PerformanceOutcome.failure);
        } catch (_) {}
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
  }

  Future<SourceIndexReport> reindexCommittedPaths(
    ProjectRecord project,
    Iterable<String> paths,
  ) {
    final requested = paths
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (requested.isEmpty) {
      return Future<SourceIndexReport>.value(
        SourceIndexReport(
          scanned: 0,
          changed: 0,
          removed: 0,
          skipped: 0,
          total: 0,
          generatedAt: DateTime.now().toUtc(),
        ),
      );
    }
    return _serialize<SourceIndexReport>(() async {
      final store = await _store();
      final projectHash = Sha256.text(project.id);
      final root = await _canonicalProjectRoot(project);
      final rootHash = Sha256.text(_normalizedAbsolute(root.path));
      var before = store.projectInfo(projectHash);
      final span = PerformanceSpan.start(
        'source.index.update',
        sink: _performance,
        projectHash: projectHash,
        cacheResult: before?.initialized == true
            ? PerformanceCacheResult.hit
            : PerformanceCacheResult.miss,
        thermalState: before?.initialized == true
            ? PerformanceThermalState.warm
            : PerformanceThermalState.cold,
        taskClass: 'incremental',
      );
      try {
        if (before == null || !before.initialized || before.rootHash != rootHash) {
          if (before != null && before.rootHash != rootHash) {
            store.resetProjectRoot(projectHash, rootHash);
            await _replaceRuntime(projectHash, null);
          }
          final reconciled = await _reconcileProject(
            store,
            project,
            projectHash,
            root,
            rootHash,
          );
          await _ensureWatcher(project, projectHash, root, rootHash);
          span.finish(
            itemCount: reconciled.report.total,
            bytesConsidered: reconciled.bytesConsidered,
            candidateCount: reconciled.report.scanned,
          );
          return reconciled.report;
        }
        final result = await _reindexPaths(
          store,
          projectHash,
          root,
          rootHash,
          requested,
        );
        await _ensureWatcher(project, projectHash, root, rootHash);
        span.finish(
          itemCount: result.report.total,
          bytesConsidered: result.bytesConsidered,
          candidateCount: result.report.scanned,
        );
        return result.report;
      } catch (error, stackTrace) {
        try {
          span.finish(outcome: PerformanceOutcome.failure);
        } catch (_) {}
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
  }

  Future<List<Map<String, dynamic>>> search(
    String projectId,
    String query, {
    int limit = 20,
  }) async {
    final store = await _store();
    final projectHash = Sha256.text(projectId);
    final info = store.projectInfo(projectHash);
    final warm = info?.initialized == true;
    final span = PerformanceSpan.start(
      'source.search',
      sink: _performance,
      projectHash: projectHash,
      cacheResult:
          warm ? PerformanceCacheResult.hit : PerformanceCacheResult.miss,
      thermalState: warm
          ? PerformanceThermalState.warm
          : PerformanceThermalState.cold,
      taskClass: 'indexed',
    );
    try {
      final terms = _queryTerms(query);
      if (!warm || terms.isEmpty) {
        span.finish(itemCount: 0, bytesConsidered: 0, candidateCount: 0);
        return <Map<String, dynamic>>[];
      }
      final candidates = store.search(
        projectHash,
        terms,
        limit.clamp(1, 100).toInt(),
      );
      final results = candidates
          .map(
            (candidate) => <String, dynamic>{
              'path': candidate.entry.path,
              'sha256': candidate.entry.sha256,
              'language': candidate.entry.language,
              'symbols': candidate.entry.symbols,
              'dependencies': candidate.entry.dependencies,
              'score': candidate.score,
              'snippet': _snippet(candidate.entry.text, terms),
            },
          )
          .toList(growable: false);
      span.finish(
        itemCount: results.length,
        bytesConsidered: 0,
        candidateCount: candidates.length,
      );
      return results;
    } catch (error, stackTrace) {
      try {
        span.finish(outcome: PerformanceOutcome.failure);
      } catch (_) {}
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<SourceIndexDiagnostics> diagnostics(String projectId) async {
    final store = await _store();
    final projectHash = Sha256.text(projectId);
    final info = store.projectInfo(projectHash);
    final runtime = _projects[projectHash];
    return SourceIndexDiagnostics(
      projectHash: projectHash,
      databasePath: store.databasePath,
      backend: store.backend,
      persistent: store.persistent,
      initialized: info?.initialized ?? false,
      watcherActive: runtime?.watcherActive ?? false,
      generation: info?.generation ?? 0,
      files: store.fileCount(projectHash),
      lastUpdateAt: info?.updatedAt,
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final runtime in _projects.values.toList(growable: false)) {
      runtime.debounce?.cancel();
      runtime.debounce = null;
      try {
        await runtime.watcher?.cancel();
      } catch (_) {}
      runtime.watcher = null;
      runtime.watcherActive = false;
      runtime.pending.clear();
    }
    _projects.clear();
    try {
      await _mutationTail;
    } catch (_) {}
    final future = _storeFuture;
    _storeFuture = null;
    if (future != null) {
      try {
        final store = await future;
        store.close();
      } catch (_) {}
    }
  }

  Future<Directory> _canonicalProjectRoot(ProjectRecord project) async {
    final root = Directory(project.rootPath).absolute;
    if (!await root.exists()) {
      throw ProductException(
        'project_missing',
        'Project root no longer exists.',
      );
    }
    final canonical = await root.resolveSymbolicLinks();
    return Directory(canonical).absolute;
  }

  Future<_SourceUpdateResult> _reconcileProject(
    _SourceSqliteStore store,
    ProjectRecord project,
    String projectHash,
    Directory root,
    String rootHash,
  ) async {
    final prior = store.fileMetadata(projectHash);
    final seen = <String>{};
    final changedEntries = <SourceIndexEntry>[];
    final touches = <_SourceStatUpdate>[];
    var scanned = 0;
    var changed = 0;
    var skipped = 0;
    var bytesConsidered = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (++scanned > _maxFiles) {
        throw ProductException(
          'index_file_limit',
          'Project contains more than 25,000 indexable files.',
        );
      }
      final relative = _relativeToRoot(root.path, entity.absolute.path);
      if (relative == null || relative.isEmpty || _ignored(relative)) {
        skipped++;
        continue;
      }
      final stat = await entity.stat();
      if (stat.size > _maxFileBytes) {
        skipped++;
        continue;
      }
      final previous = prior[relative];
      if (previous != null &&
          previous.bytes == stat.size &&
          previous.modifiedAtMs == stat.modified.toUtc().millisecondsSinceEpoch) {
        seen.add(relative);
        continue;
      }
      final read = await _readSourceFile(relative, entity, stat);
      bytesConsidered += read.bytesRead;
      final entry = read.entry;
      if (entry == null) {
        skipped++;
        continue;
      }
      seen.add(relative);
      if (previous != null && previous.sha256 == entry.sha256) {
        touches.add(
          _SourceStatUpdate(
            path: relative,
            bytes: entry.bytes,
            modifiedAtMs: entry.modifiedAt.millisecondsSinceEpoch,
          ),
        );
      } else {
        changedEntries.add(entry);
        changed++;
      }
    }
    final removedPaths = prior.keys.where((path) => !seen.contains(path)).toSet();
    final info = store.applyBatch(
      projectHash: projectHash,
      rootHash: rootHash,
      entries: changedEntries,
      removedPaths: removedPaths,
      touches: touches,
      forceInitialize: true,
    );
    return _SourceUpdateResult(
      report: SourceIndexReport(
        scanned: scanned,
        changed: changed,
        removed: removedPaths.length,
        skipped: skipped,
        total: store.fileCount(projectHash),
        generatedAt: info.updatedAt ?? DateTime.now().toUtc(),
        generation: info.generation,
      ),
      bytesConsidered: bytesConsidered,
    );
  }

  Future<_SourceUpdateResult> _reindexPaths(
    _SourceSqliteStore store,
    String projectHash,
    Directory root,
    String rootHash,
    Iterable<String> requestedPaths,
  ) async {
    final normalizedPaths = <String>{};
    var skipped = 0;
    for (final requested in requestedPaths) {
      final relative = _relativeToRoot(root.path, requested);
      if (relative == null || relative.isEmpty) {
        skipped++;
        continue;
      }
      normalizedPaths.add(relative);
    }
    final changedEntries = <SourceIndexEntry>[];
    final touches = <_SourceStatUpdate>[];
    final removedPaths = <String>{};
    var changed = 0;
    var bytesConsidered = 0;
    for (final relative in normalizedPaths) {
      if (_ignored(relative)) {
        removedPaths.addAll(store.pathsAtOrBelow(projectHash, relative));
        skipped++;
        continue;
      }
      final absolute = File(
        '${root.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}',
      );
      final type = await FileSystemEntity.type(
        absolute.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.notFound) {
        removedPaths.addAll(store.pathsAtOrBelow(projectHash, relative));
        continue;
      }
      if (type != FileSystemEntityType.file) {
        if (type == FileSystemEntityType.link) {
          removedPaths.addAll(store.pathsAtOrBelow(projectHash, relative));
        }
        skipped++;
        continue;
      }
      final stat = await absolute.stat();
      if (stat.size > _maxFileBytes) {
        removedPaths.addAll(store.pathsAtOrBelow(projectHash, relative));
        skipped++;
        continue;
      }
      final read = await _readSourceFile(relative, absolute, stat);
      bytesConsidered += read.bytesRead;
      final entry = read.entry;
      if (entry == null) {
        removedPaths.addAll(store.pathsAtOrBelow(projectHash, relative));
        skipped++;
        continue;
      }
      final previous = store.fileMetadataForPath(projectHash, relative);
      if (previous != null && previous.sha256 == entry.sha256) {
        touches.add(
          _SourceStatUpdate(
            path: relative,
            bytes: entry.bytes,
            modifiedAtMs: entry.modifiedAt.millisecondsSinceEpoch,
          ),
        );
      } else {
        changedEntries.add(entry);
        changed++;
      }
    }
    for (final entry in changedEntries) {
      removedPaths.remove(entry.path);
    }
    final info = store.applyBatch(
      projectHash: projectHash,
      rootHash: rootHash,
      entries: changedEntries,
      removedPaths: removedPaths,
      touches: touches,
      forceInitialize: false,
    );
    return _SourceUpdateResult(
      report: SourceIndexReport(
        scanned: normalizedPaths.length,
        changed: changed,
        removed: removedPaths.length,
        skipped: skipped,
        total: store.fileCount(projectHash),
        generatedAt: info.updatedAt ?? DateTime.now().toUtc(),
        generation: info.generation,
      ),
      bytesConsidered: bytesConsidered,
    );
  }

  Future<_ReadSourceFile> _readSourceFile(
    String relative,
    File file,
    FileStat stat,
  ) async {
    final bytes = await file.readAsBytes();
    if (bytes.take(min(bytes.length, 8192)).contains(0)) {
      return _ReadSourceFile(entry: null, bytesRead: bytes.length);
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    final storedText =
        text.length > _maxStoredText ? text.substring(0, _maxStoredText) : text;
    final language = _language(relative);
    return _ReadSourceFile(
      entry: SourceIndexEntry(
        path: relative,
        sha256: Sha256.hex(bytes),
        bytes: bytes.length,
        modifiedAt: stat.modified.toUtc(),
        language: language,
        symbols: _symbols(language, storedText),
        dependencies: _dependencies(language, storedText),
        text: storedText,
      ),
      bytesRead: bytes.length,
    );
  }

  Future<void> _ensureWatcher(
    ProjectRecord project,
    String projectHash,
    Directory root,
    String rootHash,
  ) async {
    final existing = _projects[projectHash];
    if (existing != null &&
        existing.rootHash == rootHash &&
        existing.watcher != null) {
      existing.project = project;
      return;
    }
    if (existing != null) {
      await _replaceRuntime(projectHash, null);
    }
    final runtime = _SourceProjectRuntime(
      project: project,
      root: root,
      rootHash: rootHash,
    );
    _projects[projectHash] = runtime;
    try {
      runtime.watcher = root.watch(recursive: true).listen(
        (event) {
          _queueWatcherPath(projectHash, runtime, event.path);
          if (event is FileSystemMoveEvent && event.destination != null) {
            _queueWatcherPath(projectHash, runtime, event.destination!);
          }
        },
        onError: (_) {
          runtime.watcherActive = false;
        },
        cancelOnError: false,
      );
      runtime.watcherActive = true;
    } on FileSystemException {
      runtime.watcherActive = false;
    } on UnsupportedError {
      runtime.watcherActive = false;
    }
  }

  void _queueWatcherPath(
    String projectHash,
    _SourceProjectRuntime runtime,
    String path,
  ) {
    if (_closed || !identical(_projects[projectHash], runtime)) return;
    final relative = _relativeToRoot(runtime.root.path, path);
    if (relative == null || relative.isEmpty) return;
    runtime.pending.add(relative);
    runtime.debounce?.cancel();
    runtime.debounce = Timer(_watchDebounce, () {
      runtime.debounce = null;
      unawaited(
        _serialize<void>(() async {
          await _flushWatcher(projectHash, runtime);
        }),
      );
    });
  }

  Future<void> _flushWatcher(
    String projectHash,
    _SourceProjectRuntime runtime,
  ) async {
    if (_closed || !identical(_projects[projectHash], runtime)) return;
    if (runtime.pending.isEmpty) return;
    final batch = runtime.pending.take(_watchBatchSize).toSet();
    runtime.pending.removeAll(batch);
    try {
      final store = await _store();
      await _reindexPaths(
        store,
        projectHash,
        runtime.root,
        runtime.rootHash,
        batch,
      );
    } catch (_) {
      runtime.watcherActive = false;
    }
    if (runtime.pending.isNotEmpty && !_closed) {
      runtime.debounce?.cancel();
      runtime.debounce = Timer(_watchDebounce, () {
        runtime.debounce = null;
        unawaited(
          _serialize<void>(() async {
            await _flushWatcher(projectHash, runtime);
          }),
        );
      });
    }
  }

  Future<void> _replaceRuntime(
    String projectHash,
    _SourceProjectRuntime? replacement,
  ) async {
    final existing = _projects.remove(projectHash);
    if (existing != null) {
      existing.debounce?.cancel();
      existing.debounce = null;
      existing.pending.clear();
      try {
        await existing.watcher?.cancel();
      } catch (_) {}
      existing.watcher = null;
      existing.watcherActive = false;
    }
    if (replacement != null) {
      _projects[projectHash] = replacement;
    }
  }

  String? _relativeToRoot(String rootPath, String path) {
    var raw = path.trim();
    if (raw.isEmpty) return null;
    raw = raw.replaceAll('\\', '/');
    final root = _normalizedAbsolute(rootPath);
    final windowsAbsolute = RegExp(r'^[A-Za-z]:/').hasMatch(raw);
    final absolute = raw.startsWith('/') || windowsAbsolute;
    String relative;
    if (absolute) {
      final candidate = _normalizedAbsolute(raw);
      final compareRoot = Platform.isWindows ? root.toLowerCase() : root;
      final compareCandidate =
          Platform.isWindows ? candidate.toLowerCase() : candidate;
      if (compareCandidate == compareRoot) return '';
      if (!compareCandidate.startsWith('$compareRoot/')) return null;
      relative = candidate.substring(root.length + 1);
    } else {
      relative = raw;
    }
    final segments = relative
        .split('/')
        .where((segment) => segment.isNotEmpty && segment != '.')
        .toList(growable: false);
    if (segments.isEmpty || segments.any((segment) => segment == '..')) {
      return null;
    }
    return segments.join('/');
  }

  String _normalizedAbsolute(String path) {
    var value = File(path).absolute.path.replaceAll('\\', '/');
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  Set<String> _queryTerms(String query) => RegExp(r'[A-Za-z0-9_\-]{2,}')
      .allMatches(query.toLowerCase())
      .map((match) => match.group(0)!)
      .take(24)
      .toSet();

  String _snippet(String text, Set<String> terms) {
    final lower = text.toLowerCase();
    var firstOffset = -1;
    for (final term in terms) {
      final offset = lower.indexOf(term);
      if (offset >= 0 && (firstOffset < 0 || offset < firstOffset)) {
        firstOffset = offset;
      }
    }
    final start = max(0, firstOffset < 0 ? 0 : firstOffset - 250);
    final end = min(text.length, start + 1200);
    return text.substring(start, end);
  }

  bool _ignored(String path) => path.replaceAll('\\', '/').split('/').any(
        const <String>{
          '.git',
          '.dart_tool',
          'build',
          'node_modules',
          '.venv',
          'venv',
          '__pycache__',
          '.pytest_cache',
          '.idea',
          '.vscode',
          '.kristin',
          'coverage',
          'dist',
          'target',
        }.contains,
      );

  String _language(String path) {
    final extension =
        path.contains('.') ? path.split('.').last.toLowerCase() : '';
    return const <String, String>{
          'dart': 'dart',
          'py': 'python',
          'js': 'javascript',
          'mjs': 'javascript',
          'cjs': 'javascript',
          'ts': 'typescript',
          'tsx': 'typescript',
          'jsx': 'javascript',
          'java': 'java',
          'kt': 'kotlin',
          'swift': 'swift',
          'go': 'go',
          'rs': 'rust',
          'c': 'c',
          'h': 'c',
          'cpp': 'cpp',
          'cc': 'cpp',
          'hpp': 'cpp',
          'cs': 'csharp',
          'rb': 'ruby',
          'php': 'php',
          'html': 'html',
          'css': 'css',
          'scss': 'scss',
          'sql': 'sql',
          'yaml': 'yaml',
          'yml': 'yaml',
          'json': 'json',
          'toml': 'toml',
          'md': 'markdown',
          'sh': 'shell',
          'ps1': 'powershell',
        }[extension] ??
        'text';
  }

  List<String> _symbols(String language, String text) {
    final patterns = <RegExp>[
      RegExp(
        r'\b(?:class|enum|mixin|extension|interface|struct|trait)\s+([A-Za-z_][A-Za-z0-9_]*)',
      ),
      RegExp(r'\b(?:def|function|func|fn)\s+([A-Za-z_][A-Za-z0-9_]*)'),
      RegExp(
        r'\b(?:Future<[^>]+>|Future|void|int|double|String|bool|Widget|dynamic)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(',
      ),
      RegExp(r'\b(?:const|let|var|final)\s+([A-Za-z_][A-Za-z0-9_]*)\s*='),
    ];
    final symbols = <String>{};
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(text)) {
        final value = match.group(1);
        if (value != null) symbols.add(value);
        if (symbols.length >= 250) break;
      }
      if (symbols.length >= 250) break;
    }
    return symbols.toList()..sort();
  }

  List<String> _dependencies(String language, String text) {
    final patterns = <RegExp>[
      RegExp(r'''\bimport\s+["']([^"']+)["']'''),
      RegExp(r'''\bfrom\s+([A-Za-z0-9_.]+)\s+import\b'''),
      RegExp(r'''\brequire\s*\(\s*["']([^"']+)["']\s*\)'''),
      RegExp(r'''#include\s*[<"]([^>"]+)[>"]'''),
      RegExp(r'''\buse\s+([A-Za-z0-9_:]+)'''),
    ];
    final dependencies = <String>{};
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(text)) {
        final value = match.group(1);
        if (value != null) dependencies.add(value);
        if (dependencies.length >= 250) break;
      }
      if (dependencies.length >= 250) break;
    }
    return dependencies.toList()..sort();
  }
}

final class _SourceProjectRuntime {
  _SourceProjectRuntime({
    required this.project,
    required this.root,
    required this.rootHash,
  });

  ProjectRecord project;
  final Directory root;
  final String rootHash;
  final Set<String> pending = <String>{};
  StreamSubscription<FileSystemEvent>? watcher;
  Timer? debounce;
  bool watcherActive = false;
}

final class _SourceUpdateResult {
  const _SourceUpdateResult({
    required this.report,
    required this.bytesConsidered,
  });

  final SourceIndexReport report;
  final int bytesConsidered;
}

final class _ReadSourceFile {
  const _ReadSourceFile({required this.entry, required this.bytesRead});

  final SourceIndexEntry? entry;
  final int bytesRead;
}

final class _SourceFileMetadata {
  const _SourceFileMetadata({
    required this.path,
    required this.sha256,
    required this.bytes,
    required this.modifiedAtMs,
  });

  final String path;
  final String sha256;
  final int bytes;
  final int modifiedAtMs;
}

final class _SourceStatUpdate {
  const _SourceStatUpdate({
    required this.path,
    required this.bytes,
    required this.modifiedAtMs,
  });

  final String path;
  final int bytes;
  final int modifiedAtMs;
}

final class _SourceProjectInfo {
  const _SourceProjectInfo({
    required this.rootHash,
    required this.generation,
    required this.initialized,
    required this.updatedAt,
  });

  final String rootHash;
  final int generation;
  final bool initialized;
  final DateTime? updatedAt;
}

final class _SourceSearchCandidate {
  const _SourceSearchCandidate({required this.entry, required this.score});

  final SourceIndexEntry entry;
  final double score;
}

final class _SourceSqliteStore {
  _SourceSqliteStore._({
    required Database database,
    required this.databasePath,
    required this.persistent,
    required this.backend,
  }) : _database = database;

  static const String _schemaRevision = 'wave_b.source.v1';
  static final RegExp _termPattern = RegExp(r'[A-Za-z0-9_\-]{2,}');

  final Database _database;
  final String databasePath;
  final bool persistent;
  final String backend;
  bool _closed = false;

  static Future<_SourceSqliteStore> open(Directory indexDirectory) async {
    await indexDirectory.create(recursive: true);
    final sharedFile = File(
      '${indexDirectory.parent.path}${Platform.pathSeparator}cache.sqlite3',
    );
    final useShared = await sharedFile.exists();
    final databaseFile = useShared
        ? sharedFile
        : File(
            '${indexDirectory.path}${Platform.pathSeparator}source-index.sqlite3',
          );
    try {
      final database = sqlite3.open(databaseFile.path);
      try {
        _configure(database, standalone: !useShared);
        final backend = _ensureSchema(database);
        return _SourceSqliteStore._(
          database: database,
          databasePath: databaseFile.path,
          persistent: true,
          backend: backend,
        );
      } catch (_) {
        database.dispose();
        rethrow;
      }
    } catch (_) {
      if (!useShared) {
        for (final suffix in const <String>['', '-wal', '-shm']) {
          final candidate = File('${databaseFile.path}$suffix');
          try {
            if (await candidate.exists()) await candidate.delete();
          } catch (_) {}
        }
        try {
          final database = sqlite3.open(databaseFile.path);
          _configure(database, standalone: true);
          final backend = _ensureSchema(database);
          return _SourceSqliteStore._(
            database: database,
            databasePath: databaseFile.path,
            persistent: true,
            backend: backend,
          );
        } catch (_) {}
      }
      final memory = sqlite3.openInMemory();
      _configure(memory, standalone: false);
      final backend = _ensureSchema(memory);
      return _SourceSqliteStore._(
        database: memory,
        databasePath: ':memory:',
        persistent: false,
        backend: backend,
      );
    }
  }

  static void _configure(Database database, {required bool standalone}) {
    database.execute('PRAGMA foreign_keys = ON');
    database.execute('PRAGMA busy_timeout = 5000');
    database.execute('PRAGMA temp_store = MEMORY');
    database.execute('PRAGMA cache_size = -8192');
    if (standalone) {
      database.execute('PRAGMA journal_mode = WAL');
      database.execute('PRAGMA synchronous = NORMAL');
      database.execute('PRAGMA journal_size_limit = 16777216');
      database.execute('PRAGMA wal_autocheckpoint = 1000');
    }
  }

  static String _ensureSchema(Database database) {
    database.execute('''
CREATE TABLE IF NOT EXISTS source_index_metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at_ms INTEGER NOT NULL
) WITHOUT ROWID
''');
    final revisionRows = database.select(
      "SELECT value FROM source_index_metadata WHERE key = 'schema_revision'",
    );
    final backendRows = database.select(
      "SELECT value FROM source_index_metadata WHERE key = 'search_backend'",
    );
    final revision =
        revisionRows.isEmpty ? '' : revisionRows.first['value']?.toString() ?? '';
    final existingBackend =
        backendRows.isEmpty ? '' : backendRows.first['value']?.toString() ?? '';
    if (revision == _schemaRevision &&
        const <String>{'fts5', 'terms'}.contains(existingBackend) &&
        _schemaLooksComplete(database, existingBackend)) {
      return existingBackend;
    }
    return _transaction<String>(database, () {
      database.execute('DROP TABLE IF EXISTS source_fts');
      database.execute('DROP TABLE IF EXISTS source_terms');
      database.execute('DROP TABLE IF EXISTS source_symbols');
      database.execute('DROP TABLE IF EXISTS source_dependencies');
      database.execute('DROP TABLE IF EXISTS source_files');
      database.execute('DROP TABLE IF EXISTS source_projects');
      database.execute('DELETE FROM source_index_metadata');
      database.execute('''
CREATE TABLE source_projects (
  project_hash TEXT PRIMARY KEY,
  root_hash TEXT NOT NULL,
  generation INTEGER NOT NULL CHECK(generation >= 0),
  initialized INTEGER NOT NULL CHECK(initialized IN (0, 1)),
  updated_at_ms INTEGER NOT NULL
) WITHOUT ROWID
''');
      database.execute('''
CREATE TABLE source_files (
  project_hash TEXT NOT NULL,
  path TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  byte_length INTEGER NOT NULL CHECK(byte_length >= 0),
  mtime_ms INTEGER NOT NULL,
  language TEXT NOT NULL,
  text TEXT NOT NULL,
  generation INTEGER NOT NULL CHECK(generation >= 0),
  PRIMARY KEY(project_hash, path),
  FOREIGN KEY(project_hash) REFERENCES source_projects(project_hash)
    ON DELETE CASCADE
) WITHOUT ROWID
''');
      database.execute('''
CREATE INDEX source_files_project_language_idx
ON source_files(project_hash, language, path)
''');
      database.execute('''
CREATE TABLE source_symbols (
  project_hash TEXT NOT NULL,
  path TEXT NOT NULL,
  symbol TEXT NOT NULL,
  kind TEXT NOT NULL,
  PRIMARY KEY(project_hash, path, symbol),
  FOREIGN KEY(project_hash, path)
    REFERENCES source_files(project_hash, path) ON DELETE CASCADE
) WITHOUT ROWID
''');
      database.execute('''
CREATE INDEX source_symbols_lookup_idx
ON source_symbols(project_hash, symbol, path)
''');
      database.execute('''
CREATE TABLE source_dependencies (
  project_hash TEXT NOT NULL,
  path TEXT NOT NULL,
  dependency TEXT NOT NULL,
  PRIMARY KEY(project_hash, path, dependency),
  FOREIGN KEY(project_hash, path)
    REFERENCES source_files(project_hash, path) ON DELETE CASCADE
) WITHOUT ROWID
''');
      database.execute('''
CREATE INDEX source_dependencies_lookup_idx
ON source_dependencies(project_hash, dependency, path)
''');
      var qualifiedBackend = 'terms';
      try {
        database.execute('''
CREATE VIRTUAL TABLE source_fts USING fts5(
  project_hash UNINDEXED,
  path,
  language UNINDEXED,
  symbols,
  dependencies,
  text,
  tokenize = 'unicode61'
)
''');
        database.select("SELECT rowid FROM source_fts WHERE source_fts MATCH 'qualification' LIMIT 1");
        qualifiedBackend = 'fts5';
      } on SqliteException {
        database.execute('DROP TABLE IF EXISTS source_fts');
        database.execute('''
CREATE TABLE source_terms (
  project_hash TEXT NOT NULL,
  path TEXT NOT NULL,
  term TEXT NOT NULL,
  weight REAL NOT NULL,
  PRIMARY KEY(project_hash, path, term),
  FOREIGN KEY(project_hash, path)
    REFERENCES source_files(project_hash, path) ON DELETE CASCADE
) WITHOUT ROWID
''');
        database.execute('''
CREATE INDEX source_terms_lookup_idx
ON source_terms(project_hash, term, weight DESC, path)
''');
      }
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      for (final pair in <(String, String)>[
        ('schema_revision', _schemaRevision),
        ('search_backend', qualifiedBackend),
        ('last_rebuild_at_ms', now.toString()),
      ]) {
        database.execute(
          'INSERT INTO source_index_metadata(key, value, updated_at_ms) VALUES (?, ?, ?)',
          <Object?>[pair.$1, pair.$2, now],
        );
      }
      return qualifiedBackend;
    });
  }

  static bool _schemaLooksComplete(Database database, String backend) {
    final tables = database
        .select("SELECT name FROM sqlite_master WHERE type IN ('table', 'view')")
        .map((row) => row['name']?.toString() ?? '')
        .toSet();
    if (!tables.containsAll(const <String>{
      'source_index_metadata',
      'source_projects',
      'source_files',
      'source_symbols',
      'source_dependencies',
    })) {
      return false;
    }
    return backend == 'fts5'
        ? tables.contains('source_fts')
        : tables.contains('source_terms');
  }

  static T _transaction<T>(Database database, T Function() action) {
    database.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      database.execute('COMMIT');
      return result;
    } catch (_) {
      try {
        database.execute('ROLLBACK');
      } catch (_) {}
      rethrow;
    }
  }

  _SourceProjectInfo? projectInfo(String projectHash) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT root_hash, generation, initialized, updated_at_ms '
      'FROM source_projects WHERE project_hash = ?',
      <Object?>[projectHash],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final updatedMs = _asInt(row['updated_at_ms']);
    return _SourceProjectInfo(
      rootHash: row['root_hash']?.toString() ?? '',
      generation: _asInt(row['generation']),
      initialized: _asInt(row['initialized']) == 1,
      updatedAt: updatedMs <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(updatedMs, isUtc: true),
    );
  }

  Map<String, _SourceFileMetadata> fileMetadata(String projectHash) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT path, sha256, byte_length, mtime_ms FROM source_files '
      'WHERE project_hash = ?',
      <Object?>[projectHash],
    );
    return <String, _SourceFileMetadata>{
      for (final row in rows)
        row['path'].toString(): _SourceFileMetadata(
          path: row['path'].toString(),
          sha256: row['sha256']?.toString() ?? '',
          bytes: _asInt(row['byte_length']),
          modifiedAtMs: _asInt(row['mtime_ms']),
        ),
    };
  }

  _SourceFileMetadata? fileMetadataForPath(
    String projectHash,
    String path,
  ) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT path, sha256, byte_length, mtime_ms FROM source_files '
      'WHERE project_hash = ? AND path = ?',
      <Object?>[projectHash, path],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return _SourceFileMetadata(
      path: row['path'].toString(),
      sha256: row['sha256']?.toString() ?? '',
      bytes: _asInt(row['byte_length']),
      modifiedAtMs: _asInt(row['mtime_ms']),
    );
  }

  int fileCount(String projectHash) {
    _ensureOpen();
    final rows = _database.select(
      'SELECT COUNT(*) AS value FROM source_files WHERE project_hash = ?',
      <Object?>[projectHash],
    );
    return rows.isEmpty ? 0 : _asInt(rows.first['value']);
  }

  Set<String> pathsAtOrBelow(String projectHash, String path) {
    _ensureOpen();
    final escaped = path
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final rows = _database.select(
      "SELECT path FROM source_files WHERE project_hash = ? "
      "AND (path = ? OR path LIKE ? ESCAPE '\\')",
      <Object?>[projectHash, path, '$escaped/%'],
    );
    return rows.map((row) => row['path'].toString()).toSet();
  }

  void resetProjectRoot(String projectHash, String rootHash) {
    _ensureOpen();
    _transaction<void>(_database, () {
      final current = projectInfo(projectHash);
      final generation = current?.generation ?? 0;
      _deleteProjectSearchRows(projectHash);
      _database.execute(
        'DELETE FROM source_files WHERE project_hash = ?',
        <Object?>[projectHash],
      );
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      _database.execute(
        '''INSERT INTO source_projects(
  project_hash, root_hash, generation, initialized, updated_at_ms
) VALUES (?, ?, ?, 0, ?)
ON CONFLICT(project_hash) DO UPDATE SET
  root_hash = excluded.root_hash,
  generation = excluded.generation,
  initialized = 0,
  updated_at_ms = excluded.updated_at_ms''',
        <Object?>[projectHash, rootHash, generation, now],
      );
    });
  }

  _SourceProjectInfo applyBatch({
    required String projectHash,
    required String rootHash,
    required Iterable<SourceIndexEntry> entries,
    required Iterable<String> removedPaths,
    required Iterable<_SourceStatUpdate> touches,
    required bool forceInitialize,
  }) {
    _ensureOpen();
    final entryList = entries.toList(growable: false);
    final removed = removedPaths.toSet();
    final touchList = touches.toList(growable: false);
    return _transaction<_SourceProjectInfo>(_database, () {
      final before = projectInfo(projectHash);
      final shouldAdvance =
          forceInitialize && before?.initialized != true ||
              entryList.isNotEmpty ||
              removed.isNotEmpty;
      final generation = (before?.generation ?? 0) + (shouldAdvance ? 1 : 0);
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      _database.execute(
        '''INSERT INTO source_projects(
  project_hash, root_hash, generation, initialized, updated_at_ms
) VALUES (?, ?, ?, 1, ?)
ON CONFLICT(project_hash) DO UPDATE SET
  root_hash = excluded.root_hash,
  generation = excluded.generation,
  initialized = 1,
  updated_at_ms = excluded.updated_at_ms''',
        <Object?>[projectHash, rootHash, generation, now],
      );
      for (final path in removed) {
        _deletePath(projectHash, path);
      }
      for (final touch in touchList) {
        _database.execute(
          'UPDATE source_files SET byte_length = ?, mtime_ms = ? '
          'WHERE project_hash = ? AND path = ?',
          <Object?>[
            touch.bytes,
            touch.modifiedAtMs,
            projectHash,
            touch.path,
          ],
        );
      }
      for (final entry in entryList) {
        _upsertEntry(projectHash, entry, generation);
      }
      _syncSharedGeneration(projectHash, generation, now);
      return _SourceProjectInfo(
        rootHash: rootHash,
        generation: generation,
        initialized: true,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
      );
    });
  }

  void _upsertEntry(
    String projectHash,
    SourceIndexEntry entry,
    int generation,
  ) {
    _deletePath(projectHash, entry.path);
    _database.execute(
      '''INSERT INTO source_files(
  project_hash, path, sha256, byte_length, mtime_ms, language, text, generation
) VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
      <Object?>[
        projectHash,
        entry.path,
        entry.sha256,
        entry.bytes,
        entry.modifiedAt.millisecondsSinceEpoch,
        entry.language,
        entry.text,
        generation,
      ],
    );
    for (final symbol in entry.symbols) {
      _database.execute(
        'INSERT INTO source_symbols(project_hash, path, symbol, kind) '
        'VALUES (?, ?, ?, ?)',
        <Object?>[projectHash, entry.path, symbol, 'symbol'],
      );
    }
    for (final dependency in entry.dependencies) {
      _database.execute(
        'INSERT INTO source_dependencies(project_hash, path, dependency) '
        'VALUES (?, ?, ?)',
        <Object?>[projectHash, entry.path, dependency],
      );
    }
    if (backend == 'fts5') {
      _database.execute(
        '''INSERT INTO source_fts(
  project_hash, path, language, symbols, dependencies, text
) VALUES (?, ?, ?, ?, ?, ?)''',
        <Object?>[
          projectHash,
          entry.path,
          entry.language,
          entry.symbols.join(' '),
          entry.dependencies.join(' '),
          entry.text,
        ],
      );
    } else {
      final weights = _termWeights(entry);
      for (final weighted in weights.entries) {
        _database.execute(
          'INSERT INTO source_terms(project_hash, path, term, weight) '
          'VALUES (?, ?, ?, ?)',
          <Object?>[projectHash, entry.path, weighted.key, weighted.value],
        );
      }
    }
  }

  void _deletePath(String projectHash, String path) {
    if (backend == 'fts5') {
      _database.execute(
        'DELETE FROM source_fts WHERE project_hash = ? AND path = ?',
        <Object?>[projectHash, path],
      );
    }
    _database.execute(
      'DELETE FROM source_files WHERE project_hash = ? AND path = ?',
      <Object?>[projectHash, path],
    );
  }

  void _deleteProjectSearchRows(String projectHash) {
    if (backend == 'fts5') {
      _database.execute(
        'DELETE FROM source_fts WHERE project_hash = ?',
        <Object?>[projectHash],
      );
    }
  }

  void _syncSharedGeneration(String projectHash, int generation, int now) {
    final table = _database.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'cache_generations'",
    );
    if (table.isEmpty) return;
    _database.execute(
      '''INSERT INTO cache_generations(
  namespace, project_hash, generation, updated_at_ms
) VALUES ('source', ?, ?, ?)
ON CONFLICT(namespace, project_hash) DO UPDATE SET
  generation = excluded.generation,
  updated_at_ms = excluded.updated_at_ms''',
      <Object?>[projectHash, generation, now],
    );
  }

  List<_SourceSearchCandidate> search(
    String projectHash,
    Set<String> terms,
    int limit,
  ) {
    _ensureOpen();
    if (terms.isEmpty) return const <_SourceSearchCandidate>[];
    final ranked = backend == 'fts5'
        ? _searchFts(projectHash, terms, limit)
        : _searchTerms(projectHash, terms, limit);
    final results = <_SourceSearchCandidate>[];
    for (final row in ranked) {
      final path = row.path;
      final fileRows = _database.select(
        'SELECT sha256, byte_length, mtime_ms, language, text '
        'FROM source_files WHERE project_hash = ? AND path = ?',
        <Object?>[projectHash, path],
      );
      if (fileRows.isEmpty) continue;
      final file = fileRows.first;
      final symbols = _database
          .select(
            'SELECT symbol FROM source_symbols '
            'WHERE project_hash = ? AND path = ? ORDER BY symbol',
            <Object?>[projectHash, path],
          )
          .map((item) => item['symbol'].toString())
          .toList(growable: false);
      final dependencies = _database
          .select(
            'SELECT dependency FROM source_dependencies '
            'WHERE project_hash = ? AND path = ? ORDER BY dependency',
            <Object?>[projectHash, path],
          )
          .map((item) => item['dependency'].toString())
          .toList(growable: false);
      results.add(
        _SourceSearchCandidate(
          entry: SourceIndexEntry(
            path: path,
            sha256: file['sha256']?.toString() ?? '',
            bytes: _asInt(file['byte_length']),
            modifiedAt: DateTime.fromMillisecondsSinceEpoch(
              _asInt(file['mtime_ms']),
              isUtc: true,
            ),
            language: file['language']?.toString() ?? 'text',
            symbols: symbols,
            dependencies: dependencies,
            text: file['text']?.toString() ?? '',
          ),
          score: row.score,
        ),
      );
    }
    return results;
  }

  List<({String path, double score})> _searchFts(
    String projectHash,
    Set<String> terms,
    int limit,
  ) {
    final match = terms
        .map((term) => '"${term.replaceAll('"', '""')}"*')
        .join(' OR ');
    final rows = _database.select(
      '''SELECT path,
  bm25(source_fts, 0.0, 8.0, 0.0, 6.0, 4.0, 1.0) AS rank
FROM source_fts
WHERE source_fts MATCH ? AND project_hash = ?
ORDER BY rank ASC, path ASC
LIMIT ?''',
      <Object?>[match, projectHash, limit],
    );
    return rows.map((row) {
      final rank = _asDouble(row['rank']).abs();
      return (
        path: row['path'].toString(),
        score: 1000.0 / (1.0 + rank),
      );
    }).toList(growable: false);
  }

  List<({String path, double score})> _searchTerms(
    String projectHash,
    Set<String> terms,
    int limit,
  ) {
    final placeholders = List<String>.filled(terms.length, '?').join(', ');
    final values = <Object?>[projectHash, ...terms, limit];
    final rows = _database.select(
      '''SELECT path, SUM(weight) AS score
FROM source_terms
WHERE project_hash = ? AND term IN ($placeholders)
GROUP BY path
ORDER BY score DESC, path ASC
LIMIT ?''',
      values,
    );
    return rows
        .map(
          (row) => (
            path: row['path'].toString(),
            score: _asDouble(row['score']),
          ),
        )
        .toList(growable: false);
  }

  static Map<String, double> _termWeights(SourceIndexEntry entry) {
    final weights = <String, double>{};
    void add(String value, double weight) {
      for (final match in _termPattern.allMatches(value.toLowerCase())) {
        final term = match.group(0)!;
        weights[term] = (weights[term] ?? 0) + weight;
      }
    }

    add(entry.path, 8);
    for (final symbol in entry.symbols) {
      add(symbol, 6);
    }
    for (final dependency in entry.dependencies) {
      add(dependency, 4);
    }
    final counts = <String, int>{};
    for (final match in _termPattern.allMatches(entry.text.toLowerCase())) {
      final term = match.group(0)!;
      counts[term] = min(10, (counts[term] ?? 0) + 1);
    }
    for (final item in counts.entries) {
      weights[item.key] =
          (weights[item.key] ?? 0) + 1.0 + item.value.toDouble() * 0.4;
    }
    if (weights.length <= 4096) return weights;
    final ordered = weights.entries.toList()
      ..sort((left, right) {
        final byWeight = right.value.compareTo(left.value);
        return byWeight != 0 ? byWeight : left.key.compareTo(right.key);
      });
    return <String, double>{
      for (final item in ordered.take(4096)) item.key: item.value,
    };
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _asDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  void _ensureOpen() {
    if (_closed) throw StateError('source_index_store_closed');
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _database.dispose();
    } catch (_) {}
  }
}

class SkillPackage {
  const SkillPackage({
    required this.id,
    required this.title,
    required this.triggers,
    required this.instructions,
    required this.recommendedTools,
  });

  final String id;
  final String title;
  final Set<String> triggers;
  final String instructions;
  final Set<String> recommendedTools;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'recommendedTools': recommendedTools.toList()..sort(),
        'instructions': instructions,
      };
}

class SkillRegistry {
  const SkillRegistry();

  List<SkillPackage> get all => List<SkillPackage>.unmodifiable(_builtins);

  List<SkillPackage> match(String request, {int limit = 4}) {
    final lower = request.toLowerCase();
    final scored = <({SkillPackage skill, int score})>[];
    for (final skill in _builtins) {
      final score = skill.triggers.where(lower.contains).length;
      if (score > 0) {
        scored.add((skill: skill, score: score));
      }
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.skill.id.compareTo(b.skill.id);
    });
    return scored.take(limit).map((item) => item.skill).toList();
  }

  String contextFor(String request) {
    final skills = match(request);
    if (skills.isEmpty) {
      return 'No specialized built-in skill package matched this request.';
    }
    return skills
        .map(
          (skill) => '''
SKILL ${skill.id} — ${skill.title}
These are product-authored advisory instructions. They never expand tools, permissions, paths, or budgets.
${skill.instructions}
Recommended tools: ${skill.recommendedTools.join(', ')}
''',
        )
        .join('\n');
  }
}

const List<SkillPackage> _builtins = <SkillPackage>[
  SkillPackage(
    id: 'static-web',
    title: 'Production static website',
    triggers: <String>{'website', 'landing page', 'html', 'css', 'static site'},
    instructions:
        'Use semantic HTML, responsive layouts, accessible labels and focus states, content-security considerations, optimized assets, metadata, and a deterministic local verification path. Avoid external runtime dependencies unless the contract requires them.',
    recommendedTools: <String>{
      'read_file',
      'inspect_file',
      'write_file',
      'apply_patch',
      'verify_project',
    },
  ),
  SkillPackage(
    id: 'node-service',
    title: 'Node.js application or service',
    triggers: <String>{
      'node',
      'typescript',
      'javascript',
      'express',
      'fastify',
      'react',
      'next.js',
    },
    instructions:
        'Pin dependencies through a lockfile, validate all external input, separate configuration from code, use environment secret references, include health and shutdown behavior, and add automated tests before packaging.',
    recommendedTools: <String>{
      'read_file',
      'inspect_file',
      'write_file',
      'run_command',
      'verify_project',
    },
  ),
  SkillPackage(
    id: 'python-service',
    title: 'Python application or service',
    triggers: <String>{'python', 'fastapi', 'flask', 'django', 'pytest'},
    instructions:
        'Use a virtual-environment-compatible dependency manifest, typed boundaries, structured logging, explicit configuration, environment secret references, graceful shutdown, and pytest coverage of core behavior.',
    recommendedTools: <String>{
      'read_file',
      'inspect_file',
      'write_file',
      'run_command',
      'verify_project',
    },
  ),
  SkillPackage(
    id: 'telegram-bot',
    title: 'Telegram bot',
    triggers: <String>{
      'telegram',
      'tg bot',
      'chat bot',
      'botfather',
      'aiogram',
      'telegraf',
    },
    instructions:
        'Keep the BotFather token exclusively in a named runtime secret. Validate updates, restrict administrator actions by numeric user ID, rate-limit handlers, avoid logging message secrets, mock Telegram in tests, support graceful polling shutdown, and provide webhook deployment only with HTTPS and secret-path validation.',
    recommendedTools: <String>{
      'research_fetch',
      'read_file',
      'inspect_file',
      'write_file',
      'run_command',
      'package_deployment',
    },
  ),
  SkillPackage(
    id: 'flutter-application',
    title: 'Flutter application',
    triggers: <String>{
      'flutter',
      'dart',
      'android app',
      'ios app',
      'desktop app',
    },
    instructions:
        'Keep state and side effects separated, use responsive Material semantics, avoid blocking the UI isolate, provide deterministic initialization and disposal, test domain behavior and key widgets, and require flutter analyze plus flutter test before release.',
    recommendedTools: <String>{
      'read_file',
      'inspect_file',
      'write_file',
      'apply_patch',
      'verify_project',
    },
  ),
  SkillPackage(
    id: 'docker-deployment',
    title: 'Container deployment',
    triggers: <String>{
      'docker',
      'container',
      'deploy',
      'deployment',
      'production',
      'compose',
    },
    instructions:
        'Use a non-root runtime user, a minimal pinned base image, multi-stage builds, read-only configuration, health checks, graceful shutdown, no embedded secrets, explicit exposed ports, and a rollback-ready artifact manifest.',
    recommendedTools: <String>{
      'read_file',
      'inspect_file',
      'write_file',
      'verify_project',
      'package_deployment',
    },
  ),
  SkillPackage(
    id: 'security-review',
    title: 'Application security review',
    triggers: <String>{
      'security',
      'auth',
      'authentication',
      'authorization',
      'secret',
      'vulnerability',
    },
    instructions:
        'Map trust boundaries, reject default-allow authorization, validate canonical paths and URLs, apply least privilege, bound resources, avoid sensitive logs, verify cryptographic uses, and rank findings by exploitability and impact with concrete evidence.',
    recommendedTools: <String>{
      'search_text',
      'read_file',
      'run_command',
      'git_diff',
    },
  ),
];
