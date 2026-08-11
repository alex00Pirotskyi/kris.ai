import 'dart:convert';
import 'dart:io';

import '../crypto_utils.dart';

/// Immutable, application-owned browser runtime resources for P3-001.
///
/// The bundle deliberately contains the Node executable and browser executable.
/// Resolution never falls back to PATH, a globally installed Node runtime, or a
/// network browser installer.
final class P3BrowserRuntimeResourceSet {
  const P3BrowserRuntimeResourceSet({
    required this.root,
    required this.manifestPath,
    required this.manifestSha256,
    required this.sourceCommit,
    required this.sourceTree,
    required this.runtimeBuildSha256,
    required this.nodeVersion,
    required this.automationHostPackageVersion,
    required this.browserEngine,
    required this.browserRevision,
    required this.nodeExecutable,
    required this.nodeExecutableSha256,
    required this.workerScript,
    required this.workerScriptSha256,
    required this.workingDirectory,
    required this.browserExecutable,
    required this.browserExecutableSha256,
    required this.browserRoot,
    required this.browserRootTreeSha256,
    required this.packageLock,
    required this.packageLockSha256,
  });

  final Directory root;
  final String manifestPath;
  final String manifestSha256;
  final String sourceCommit;
  final String sourceTree;
  final String runtimeBuildSha256;
  final String nodeVersion;
  final String automationHostPackageVersion;
  final String browserEngine;
  final String browserRevision;
  final String nodeExecutable;
  final String nodeExecutableSha256;
  final String workerScript;
  final String workerScriptSha256;
  final String workingDirectory;
  final String browserExecutable;
  final String browserExecutableSha256;
  final String browserRoot;
  final String browserRootTreeSha256;
  final String packageLock;
  final String packageLockSha256;

  Map<String, Object?> get provenance => <String, Object?>{
        'resolver': 'P3ApplicationOwnedBrowserRuntimeResolver',
        'bundleType': P3ApplicationOwnedBrowserRuntimeResolver.bundleType,
        'applicationOwned': true,
        'globalRuntimeRequired': false,
        'browserNetworkInstallRequired': false,
        'sourceCommit': sourceCommit,
        'sourceTree': sourceTree,
        'runtimeBuildSha256': runtimeBuildSha256,
        'manifestSha256': manifestSha256,
        'nodeVersion': nodeVersion,
        'automationHostPackageVersion': automationHostPackageVersion,
        'browserEngine': browserEngine,
        'browserRevision': browserRevision,
        'nodeExecutableSha256': nodeExecutableSha256,
        'workerScriptSha256': workerScriptSha256,
        'browserExecutableSha256': browserExecutableSha256,
        'browserRootTreeSha256': browserRootTreeSha256,
        'packageLockSha256': packageLockSha256,
        'rootPathSha256': Sha256.text(root.absolute.path),
      };
}

/// Resolves only a packaged P3 browser runtime owned by the application.
final class P3ApplicationOwnedBrowserRuntimeResolver {
  P3ApplicationOwnedBrowserRuntimeResolver({
    required this.applicationDataRoot,
    String? executablePath,
  }) : executablePath = executablePath ?? Platform.resolvedExecutable;

  static const String schemaVersion = '1.0.0';
  static const String bundleType = 'kristin-p3-browser-runtime-v1';

  final Directory applicationDataRoot;
  final String executablePath;

  Future<P3BrowserRuntimeResourceSet> resolve() async {
    if (!applicationDataRoot.isAbsolute) {
      throw StateError('p3_application_data_root_must_be_absolute');
    }
    final executableRoot = File(executablePath).absolute.parent;
    final candidates = <Directory>[
      Directory(
        '${applicationDataRoot.absolute.path}${Platform.pathSeparator}'
        'runtime${Platform.pathSeparator}p3${Platform.pathSeparator}current',
      ),
      Directory(
        '${executableRoot.path}${Platform.pathSeparator}'
        'runtime${Platform.pathSeparator}p3${Platform.pathSeparator}current',
      ),
    ];
    Object? lastError;
    for (final candidate in candidates) {
      if (!await candidate.exists()) continue;
      try {
        return await resolveRoot(candidate.absolute);
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) {
      throw StateError('p3_browser_runtime_bundle_invalid:$lastError');
    }
    throw StateError('p3_browser_runtime_bundle_missing');
  }

  Future<P3BrowserRuntimeResourceSet> resolveRoot(Directory root) async {
    if (!root.isAbsolute || !await root.exists()) {
      throw StateError('p3_browser_runtime_root_missing');
    }
    if (await FileSystemEntity.isLink(root.path)) {
      throw StateError('p3_browser_runtime_root_symlink');
    }
    final manifest = File(
      '${root.path}${Platform.pathSeparator}browser-runtime-manifest.v1.json',
    );
    if (!await manifest.exists() ||
        await FileSystemEntity.isLink(manifest.path)) {
      throw StateError('p3_browser_runtime_manifest_missing_or_symlink');
    }
    final Object? raw = jsonDecode(await manifest.readAsString());
    if (raw is! Map) {
      throw StateError('p3_browser_runtime_manifest_not_object');
    }
    final decoded = Map<String, Object?>.from(raw);
    if (decoded['schemaVersion'] != schemaVersion ||
        decoded['bundleType'] != bundleType ||
        decoded['applicationOwned'] != true ||
        decoded['workingDirectoryIndependent'] != true ||
        decoded['currentWorkingDirectoryUsed'] != false ||
        decoded['globalRuntimeRequired'] != false ||
        decoded['browserNetworkInstallRequired'] != false ||
        decoded['identity'] is! Map ||
        decoded['resources'] is! Map) {
      throw StateError('p3_browser_runtime_manifest_identity_invalid');
    }

    final identity = Map<String, Object?>.from(decoded['identity']! as Map);
    final resources = Map<String, Object?>.from(decoded['resources']! as Map);
    final sourceCommit = _hex(identity, 'sourceCommit', 40);
    final sourceTree = _hex(identity, 'sourceTree', 40);
    final runtimeBuildSha256 = _hex(identity, 'runtimeBuildSha256', 64);
    final packageLockSha256 = _hex(identity, 'packageLockSha256', 64);
    final nodeVersion = _requiredText(identity, 'nodeVersion');
    final automationHostPackageVersion = _requiredText(
      identity,
      'automationHostPackageVersion',
    );
    final browserEngine = _requiredText(identity, 'browserEngine');
    final browserRevision = _requiredText(identity, 'browserRevision');
    if (browserEngine != 'chromium') {
      throw StateError('p3_browser_engine_not_pinned_chromium');
    }

    final node = await _fileResource(root, resources, 'nodeExecutable');
    final worker = await _fileResource(root, resources, 'browserWorker');
    final working = await _directoryResource(
      root,
      resources,
      'automationHostRoot',
    );
    final browser = await _fileResource(root, resources, 'browserExecutable');
    final browserRoot = await _directoryResource(
      root,
      resources,
      'browserRoot',
    );
    final packageLock = await _fileResource(root, resources, 'packageLock');
    if (packageLock.sha256 != packageLockSha256) {
      throw StateError('p3_package_lock_identity_mismatch');
    }
    if (!node.executable || !browser.executable) {
      throw StateError('p3_runtime_executable_marker_missing');
    }

    return P3BrowserRuntimeResourceSet(
      root: root,
      manifestPath: manifest.absolute.path,
      manifestSha256: Sha256.hex(await manifest.readAsBytes()),
      sourceCommit: sourceCommit,
      sourceTree: sourceTree,
      runtimeBuildSha256: runtimeBuildSha256,
      nodeVersion: nodeVersion,
      automationHostPackageVersion: automationHostPackageVersion,
      browserEngine: browserEngine,
      browserRevision: browserRevision,
      nodeExecutable: node.path,
      nodeExecutableSha256: node.sha256,
      workerScript: worker.path,
      workerScriptSha256: worker.sha256,
      workingDirectory: working.path,
      browserExecutable: browser.path,
      browserExecutableSha256: browser.sha256,
      browserRoot: browserRoot.path,
      browserRootTreeSha256: browserRoot.treeSha256,
      packageLock: packageLock.path,
      packageLockSha256: packageLock.sha256,
    );
  }

  Future<_P3FileResource> _fileResource(
    Directory root,
    Map<String, Object?> resources,
    String key,
  ) async {
    final row = _resourceRow(resources, key);
    if (row['kind'] != 'file' || row['sha256'] is! String) {
      throw StateError('p3_runtime_resource_kind:$key');
    }
    final relative = _relativePath(row, key);
    final file = File(
      '${root.path}${Platform.pathSeparator}'
      '${relative.replaceAll('/', Platform.pathSeparator)}',
    ).absolute;
    _requireContained(root, file.path, key);
    if (!await file.exists() || await FileSystemEntity.isLink(file.path)) {
      throw StateError('p3_runtime_resource_missing_or_symlink:$key');
    }
    final expected = row['sha256']!.toString().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
      throw StateError('p3_runtime_resource_digest_invalid:$key');
    }
    final actual = Sha256.hex(await file.readAsBytes());
    if (actual != expected) {
      throw StateError('p3_runtime_resource_digest_mismatch:$key');
    }
    return _P3FileResource(
      path: file.path,
      sha256: actual,
      executable: row['executable'] == true,
    );
  }

  Future<_P3DirectoryResource> _directoryResource(
    Directory root,
    Map<String, Object?> resources,
    String key,
  ) async {
    final row = _resourceRow(resources, key);
    if (row['kind'] != 'directory' || row['treeSha256'] is! String) {
      throw StateError('p3_runtime_resource_kind:$key');
    }
    final relative = _relativePath(row, key);
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}'
      '${relative.replaceAll('/', Platform.pathSeparator)}',
    ).absolute;
    _requireContained(root, directory.path, key);
    if (!await directory.exists() ||
        await FileSystemEntity.isLink(directory.path)) {
      throw StateError('p3_runtime_directory_missing_or_symlink:$key');
    }
    final expected = row['treeSha256']!.toString().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
      throw StateError('p3_runtime_tree_digest_invalid:$key');
    }
    final actual = await treeSha256(directory);
    if (actual != expected) {
      throw StateError('p3_runtime_tree_digest_mismatch:$key');
    }
    return _P3DirectoryResource(path: directory.path, treeSha256: actual);
  }

  static Future<String> treeSha256(Directory directory) async {
    final root = directory.absolute.path;
    final rows = <String>[];
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Link || await FileSystemEntity.isLink(entity.path)) {
        throw StateError('p3_runtime_tree_symlink');
      }
      if (entity is! File) continue;
      final absolute = entity.absolute.path;
      final relative = absolute
          .substring(root.length + 1)
          .replaceAll(Platform.pathSeparator, '/');
      rows.add('$relative\u0000${Sha256.hex(await entity.readAsBytes())}');
    }
    rows.sort();
    return Sha256.text(rows.join('\n'));
  }

  static Map<String, Object?> _resourceRow(
    Map<String, Object?> resources,
    String key,
  ) {
    final raw = resources[key];
    if (raw is! Map) {
      throw StateError('p3_runtime_resource_missing:$key');
    }
    return Map<String, Object?>.from(raw);
  }

  static String _relativePath(Map<String, Object?> row, String key) {
    final value = row['path']?.toString() ?? '';
    if (value.isEmpty ||
        value.startsWith('/') ||
        value.startsWith(r'\\') ||
        RegExp(r'^[A-Za-z]:').hasMatch(value) ||
        value.contains('\\') ||
        value
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw StateError('p3_runtime_resource_path_invalid:$key');
    }
    return value;
  }

  static void _requireContained(Directory root, String candidate, String key) {
    final rootPath = root.absolute.path;
    final candidatePath = File(candidate).absolute.path;
    if (candidatePath == rootPath ||
        !candidatePath.startsWith('$rootPath${Platform.pathSeparator}')) {
      throw StateError('p3_runtime_resource_outside_bundle:$key');
    }
  }

  static String _hex(Map<String, Object?> value, String key, int length) {
    final item = value[key]?.toString().toLowerCase() ?? '';
    if (!RegExp('^[0-9a-f]{$length}\$').hasMatch(item)) {
      throw StateError('p3_runtime_identity_$key');
    }
    return item;
  }

  static String _requiredText(Map<String, Object?> value, String key) {
    final item = value[key]?.toString().trim() ?? '';
    if (item.isEmpty || item.length > 160 || item.contains('\u0000')) {
      throw StateError('p3_runtime_identity_$key');
    }
    return item;
  }
}

final class _P3FileResource {
  const _P3FileResource({
    required this.path,
    required this.sha256,
    required this.executable,
  });

  final String path;
  final String sha256;
  final bool executable;
}

final class _P3DirectoryResource {
  const _P3DirectoryResource({required this.path, required this.treeSha256});

  final String path;
  final String treeSha256;
}
