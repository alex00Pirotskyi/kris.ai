import 'dart:convert';
import 'dart:io';

const Set<String> _allowedDartFiles = <String>{
  'lib/main.dart',
  'lib/product/api_server.dart',
  'lib/product/chat_studio.dart',
  'lib/product/crypto_utils.dart',
  'lib/product/deployment_support.dart',
  'lib/product/domain.dart',
  'lib/product/extensions_index.dart',
  'lib/product/generated/v190_contracts.g.dart',
  'lib/product/interoperability_v19.dart',
  'lib/product/mcp.dart',
  'lib/product/models_research.dart',
  'lib/product/planning_runtime.dart',
  'lib/product/project_diagnostics.dart',
  'lib/product/product_runtime.dart',
  'lib/product/prompt_planning.dart',
  'lib/product/storage_security.dart',
  'lib/product/ui.dart',
  'lib/product/ui_advanced.dart',
  'lib/product/ui_components.dart',
  'lib/product/workspace_tools.dart',
  'test/product/source_contract_test.dart',
  'test/product/interoperability_v19_test.dart',
  'test/product/knowledge_memory_test.dart',
  'test/product/execution_reliability_test.dart',
  'test/product/diagnostic_replay_test.dart',
  'test/product/v1_product_preview_test.dart',
  'test/product/budget_diagnostics_test.dart',
  'test/widget_test.dart',
  'tool/prune_stale_legacy.dart',
};

const Set<String> _excludedTopLevelDirectories = <String>{
  '.dart_tool',
  '.git',
  'archive',
  'build',
  'coverage',
  'dist',
  'node_modules',
};

const Set<String> _legacySourceDirectories = <String>{
  'benchmark',
  'bin',
  'example',
  'integration_test',
};

void main() {
  final root = Directory.current.absolute;
  _requireProductMarker(root, 'lib/main.dart');
  _requireProductMarker(root, 'lib/product/product_runtime.dart');

  final candidates = _migrationCandidates(root);
  final timestamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[^0-9]'), '')
      .substring(0, 14);
  final archiveRoot = Directory(
    _join(root.path, 'archive/legacy_pre_v070_$timestamp'),
  );
  final preserved = <String>[];

  for (final entity in candidates) {
    final relative = _relativePath(root, entity);
    final destination = _availableDestination(
      _join(archiveRoot.path, relative),
    );
    Directory(destination).parent.createSync(recursive: true);
    _moveEntity(entity, destination);
    preserved.add(relative);
    stdout.writeln('Preserved stale path: $relative');
  }

  final report = <String, Object?>{
    'version': '1.3.0+130',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'projectRootExcluded': true,
    'quarantinedCount': preserved.length,
    'quarantinedPaths': preserved,
    'archiveDirectory':
        preserved.isEmpty ? null : _relativePath(root, archiveRoot),
    'discardedPaths': 0,
  };
  final reportFile = File(
    _join(root.path, 'release/legacy_quarantine_report.json'),
  );
  reportFile.parent.createSync(recursive: true);
  reportFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
    flush: true,
  );

  if (preserved.isEmpty) {
    stdout.writeln('Active source tree is already clean.');
  } else {
    stdout.writeln(
      'Preserved ${preserved.length} stale paths under '
      '${_relativePath(root, archiveRoot)}.',
    );
  }
}

void _requireProductMarker(Directory root, String relativePath) {
  if (File(_join(root.path, relativePath)).existsSync()) {
    return;
  }
  stderr.writeln(
    'ERROR: $relativePath is missing. Refusing to modify this directory.',
  );
  exit(2);
}

Set<String> _governedDartFiles(Directory root) {
  final allowed = <String>{..._allowedDartFiles};
  final inventoryFile = File(
    _join(root.path, 'config/p2_source_inventory.v1.json'),
  );
  if (!inventoryFile.existsSync()) {
    throw StateError(
      'config/p2_source_inventory.v1.json is missing; '
      'refusing stale-source migration.',
    );
  }
  final decoded = jsonDecode(inventoryFile.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw const FormatException(
      'P2 governed source inventory must be a JSON object.',
    );
  }
  for (final key in <String>[
    'productionDart',
    'testDart',
    'supportDart',
  ]) {
    final entries = decoded[key];
    if (entries is! List<Object?> || entries.isEmpty) {
      throw FormatException(
        'P2 governed source inventory is missing $key.',
      );
    }
    for (final entry in entries) {
      final relative = _normalizeGovernedPath(entry, key);
      if (!File(_join(root.path, relative)).existsSync()) {
        throw StateError('Governed Dart source is missing: $relative');
      }
      allowed.add(relative);
    }
  }

  final manifest = File(
    _join(root.path, 'SOURCE_MANIFEST.sha256'),
  );
  if (!manifest.existsSync()) {
    throw StateError(
      'SOURCE_MANIFEST.sha256 is missing; '
      'refusing stale-source migration.',
    );
  }
  final linePattern = RegExp(r'^[0-9a-f]{64}  (.+)$');
  for (final line in manifest.readAsLinesSync()) {
    if (line.trim().isEmpty) {
      continue;
    }
    final match = linePattern.firstMatch(line);
    if (match == null) {
      throw FormatException(
        'Malformed SOURCE_MANIFEST.sha256 line: $line',
      );
    }
    final relative = _normalizeGovernedPath(
      match.group(1),
      'SOURCE_MANIFEST.sha256',
    );
    if (!relative.endsWith('.dart')) {
      continue;
    }
    if (!File(_join(root.path, relative)).existsSync()) {
      throw StateError('Governed Dart source is missing: $relative');
    }
    allowed.add(relative);
  }
  return Set<String>.unmodifiable(allowed);
}

String _normalizeGovernedPath(Object? value, String source) {
  if (value is! String) {
    throw FormatException('$source contains a non-string path.');
  }
  final relative = value.replaceAll('\\', '/');
  if (relative.isEmpty ||
      relative.startsWith('/') ||
      relative.startsWith('../') ||
      relative.contains('/../') ||
      relative.contains('\u0000')) {
    throw FormatException('$source contains an unsafe path: $relative');
  }
  return relative;
}

List<FileSystemEntity> _migrationCandidates(Directory root) {
  final allowedDartFiles = _governedDartFiles(root);
  final allowedProductFiles = allowedDartFiles
      .where(
        (path) =>
            path.startsWith('lib/product/') &&
            !path.substring('lib/product/'.length).contains('/'),
      )
      .map((path) => path.substring('lib/product/'.length))
      .toSet();
  final candidates = <String, FileSystemEntity>{};

  final lib = Directory(_join(root.path, 'lib'));
  if (lib.existsSync()) {
    for (final entity in lib.listSync(followLinks: false)) {
      final name = _entityName(entity);
      if (name == 'main.dart' || name == 'product' && entity is Directory) {
        continue;
      }
      candidates[_relativePath(root, entity)] = entity;
    }
  }

  final product = Directory(_join(root.path, 'lib/product'));
  if (product.existsSync()) {
    for (final entity in product.listSync(followLinks: false)) {
      final name = _entityName(entity);
      if (entity is File && allowedProductFiles.contains(name)) {
        continue;
      }
      candidates[_relativePath(root, entity)] = entity;
    }
  }

  final test = Directory(_join(root.path, 'test'));
  if (test.existsSync()) {
    for (final entity in test.listSync(followLinks: false)) {
      final name = _entityName(entity);
      if (name == 'widget_test.dart' ||
          name == 'product' && entity is Directory) {
        continue;
      }
      candidates[_relativePath(root, entity)] = entity;
    }
  }

  final productTests = Directory(_join(root.path, 'test/product'));
  if (productTests.existsSync()) {
    for (final entity in productTests.listSync(followLinks: false)) {
      final relative = _relativePath(root, entity);
      if (entity is File && allowedDartFiles.contains(relative)) {
        continue;
      }
      candidates[relative] = entity;
    }
  }

  for (final name in _legacySourceDirectories) {
    final entity = Directory(_join(root.path, name));
    if (entity.existsSync()) {
      candidates[name] = entity;
    }
  }

  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.toLowerCase().endsWith('.dart')) {
      continue;
    }
    final relative = _relativePath(root, entity);
    final first = relative.split('/').first;
    if (_excludedTopLevelDirectories.contains(first) ||
        allowedDartFiles.contains(relative) ||
        _coveredByCandidate(relative, candidates.keys)) {
      continue;
    }
    candidates[relative] = entity;
  }

  final entries = candidates.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return entries.map((entry) => entry.value).toList(growable: false);
}

bool _coveredByCandidate(String relative, Iterable<String> candidates) {
  for (final candidate in candidates) {
    if (relative == candidate || relative.startsWith('$candidate/')) {
      return true;
    }
  }
  return false;
}

String _availableDestination(String requested) {
  if (FileSystemEntity.typeSync(requested, followLinks: false) ==
      FileSystemEntityType.notFound) {
    return requested;
  }
  var suffix = 1;
  while (FileSystemEntity.typeSync('$requested.$suffix', followLinks: false) !=
      FileSystemEntityType.notFound) {
    suffix += 1;
  }
  return '$requested.$suffix';
}

void _moveEntity(FileSystemEntity source, String destination) {
  source.renameSync(destination);
}

String _entityName(FileSystemEntity entity) {
  final normalized = entity.path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}

String _relativePath(Directory root, FileSystemEntity entity) {
  final rootPath = root.path.endsWith(Platform.pathSeparator)
      ? root.path
      : '${root.path}${Platform.pathSeparator}';
  final absolute = entity.absolute.path;
  if (!absolute.startsWith(rootPath)) {
    throw StateError('Path escaped project root: $absolute');
  }
  return absolute
      .substring(rootPath.length)
      .replaceAll(Platform.pathSeparator, '/');
}

String _join(String base, String relative) {
  return '$base${Platform.pathSeparator}'
      '${relative.replaceAll('/', Platform.pathSeparator)}';
}
