import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'browser/browser_runtime_bundle.dart';
import 'crypto_utils.dart';
import 'p2_runtime_resource_resolver.dart';

enum ApplicationRuntimeKind { p2, p3 }

enum ApplicationRuntimeProvisioningPhase {
  idle,
  checking,
  preparing,
  acquiring,
  validating,
  promoting,
  ready,
  failed,
}

final class ApplicationRuntimeProvisioningProgress {
  const ApplicationRuntimeProvisioningProgress({
    required this.kind,
    required this.phase,
    required this.message,
    this.fraction,
    this.diagnosticCode,
  });

  final ApplicationRuntimeKind kind;
  final ApplicationRuntimeProvisioningPhase phase;
  final String message;
  final double? fraction;
  final String? diagnosticCode;
}

final class ApplicationRuntimeProvisioner {
  ApplicationRuntimeProvisioner({
    required Directory applicationDataRoot,
    String? executablePath,
    HttpClient Function()? httpClientFactory,
  })  : applicationDataRoot = applicationDataRoot.absolute,
        executablePath = executablePath ?? Platform.resolvedExecutable,
        _httpClientFactory = httpClientFactory ?? HttpClient.new {
    _p2Slot = AtomicApplicationRuntimeSlot<P2RuntimeResourceSet>(
      applicationDataRoot: this.applicationDataRoot,
      runtimeKind: 'p2',
      validate: _validateP2ApplicationRoot,
    );
    _p3Slot = AtomicApplicationRuntimeSlot<P3BrowserRuntimeResourceSet>(
      applicationDataRoot: this.applicationDataRoot,
      runtimeKind: 'p3',
      validate: _validateP3ApplicationRoot,
    );
  }

  final Directory applicationDataRoot;
  final String executablePath;
  final HttpClient Function() _httpClientFactory;
  final StreamController<ApplicationRuntimeProvisioningProgress> _progress =
      StreamController<ApplicationRuntimeProvisioningProgress>.broadcast();
  late final AtomicApplicationRuntimeSlot<P2RuntimeResourceSet> _p2Slot;
  late final AtomicApplicationRuntimeSlot<P3BrowserRuntimeResourceSet> _p3Slot;

  Stream<ApplicationRuntimeProvisioningProgress> get progress =>
      _progress.stream;

  Future<P2RuntimeResourceSet> ensureP2({
    required bool currentAccountRequired,
    bool repair = false,
  }) async {
    _emit(
      ApplicationRuntimeKind.p2,
      ApplicationRuntimeProvisioningPhase.checking,
      'Checking Owner Mode runtime...',
    );
    try {
      final bundled = await _bundledP2(currentAccountRequired);
      if (bundled != null) {
        final identity = 'bundled:${bundled.runtimeBuildSha256}';
        final result = await _p2Slot.ensure(
          targetIdentity: identity,
          repair: repair,
          matches: (value) =>
              _p2AuthorityModeMatches(value, currentAccountRequired) &&
              value.runtimeBuildSha256 == bundled.runtimeBuildSha256 &&
              value.sourceCommit == bundled.sourceCommit &&
              value.sourceTree == bundled.sourceTree,
          materialize: (destination) async {
            _emit(
              ApplicationRuntimeKind.p2,
              ApplicationRuntimeProvisioningPhase.preparing,
              'Preparing Owner Mode from the Kristin package...',
              fraction: 0.35,
            );
            await _copyRuntimeTree(
              bundled.root,
              destination,
              allowInternalSymlinks: false,
            );
          },
          onPhase: (phase) => _slotPhase(ApplicationRuntimeKind.p2, phase),
        );
        _emitReady(ApplicationRuntimeKind.p2, 'Owner Mode ready.');
        return result;
      }

      final source = await _discoverSourceIdentity();
      if (source != null && currentAccountRequired) {
        final contract = File(
          '${source.root.path}${Platform.pathSeparator}lib'
          '${Platform.pathSeparator}product${Platform.pathSeparator}'
          'p1_authority_service_contract_v1.dart',
        );
        final contractSha256 = Sha256.hex(await contract.readAsBytes());
        final identity =
            'source:${source.commit}:${source.tree}:$contractSha256:current-account';
        final result = await _p2Slot.ensure(
          targetIdentity: identity,
          repair: repair,
          matches: (value) =>
              _p2AuthorityModeMatches(value, true) &&
              value.sourceCommit == source.commit &&
              value.sourceTree == source.tree &&
              value.p1AuthorityServiceContractSha256 == contractSha256,
          materialize: (destination) => _materializeFromSource(
            kind: ApplicationRuntimeKind.p2,
            source: source,
            destination: destination,
          ),
          onPhase: (phase) => _slotPhase(ApplicationRuntimeKind.p2, phase),
        );
        _emitReady(ApplicationRuntimeKind.p2, 'Owner Mode ready.');
        return result;
      }

      final cached = await _tryP2Current();
      if (cached != null &&
          _p2AuthorityModeMatches(cached, currentAccountRequired)) {
        _emitReady(ApplicationRuntimeKind.p2, 'Owner Mode ready.');
        return cached;
      }
      if (!currentAccountRequired) {
        throw StateError('p2_secure_runtime_materialization_unavailable');
      }
      throw StateError('p2_application_runtime_source_unavailable');
    } catch (error) {
      _emitFailure(ApplicationRuntimeKind.p2, error);
      rethrow;
    }
  }

  Future<P3BrowserRuntimeResourceSet> ensureP3({bool repair = false}) async {
    _emit(
      ApplicationRuntimeKind.p3,
      ApplicationRuntimeProvisioningPhase.checking,
      'Checking Web Studio runtime...',
    );
    try {
      final bundled = await _bundledP3();
      if (bundled != null) {
        final identity = 'bundled:${bundled.runtimeBuildSha256}';
        final result = await _p3Slot.ensure(
          targetIdentity: identity,
          repair: repair,
          matches: (value) =>
              value.runtimeBuildSha256 == bundled.runtimeBuildSha256 &&
              value.sourceCommit == bundled.sourceCommit &&
              value.sourceTree == bundled.sourceTree,
          materialize: (destination) async {
            _emit(
              ApplicationRuntimeKind.p3,
              ApplicationRuntimeProvisioningPhase.preparing,
              'Preparing browser runtime from the Kristin package...',
              fraction: 0.35,
            );
            await _copyRuntimeTree(
              bundled.root,
              destination,
              allowInternalSymlinks: true,
            );
          },
          onPhase: (phase) => _slotPhase(ApplicationRuntimeKind.p3, phase),
        );
        await _prepareWindowsBrowserAcl(Directory(result.browserRoot));
        _emitReady(ApplicationRuntimeKind.p3, 'Web Studio ready.');
        return result;
      }

      final source = await _discoverSourceIdentity();
      if (source != null) {
        final lock = await _readAcquisitionLock(source.root);
        final identity =
            'source:${source.commit}:${source.tree}:${lock.p3PackageLockSha256}:'
            '${lock.p3BrowserRevision}';
        final result = await _p3Slot.ensure(
          targetIdentity: identity,
          repair: repair,
          matches: (value) =>
              value.sourceCommit == source.commit &&
              value.sourceTree == source.tree &&
              value.packageLockSha256 == lock.p3PackageLockSha256 &&
              value.browserRevision == lock.p3BrowserRevision,
          materialize: (destination) => _materializeFromSource(
            kind: ApplicationRuntimeKind.p3,
            source: source,
            destination: destination,
          ),
          onPhase: (phase) => _slotPhase(ApplicationRuntimeKind.p3, phase),
        );
        await _prepareWindowsBrowserAcl(Directory(result.browserRoot));
        _emitReady(ApplicationRuntimeKind.p3, 'Web Studio ready.');
        return result;
      }

      final cached = await _tryP3Current();
      if (cached != null) {
        await _prepareWindowsBrowserAcl(Directory(cached.browserRoot));
        _emitReady(ApplicationRuntimeKind.p3, 'Web Studio ready.');
        return cached;
      }
      throw StateError('p3_browser_runtime_source_unavailable');
    } catch (error) {
      _emitFailure(ApplicationRuntimeKind.p3, error);
      rethrow;
    }
  }

  Future<void> close() => _progress.close();

  Future<P2RuntimeResourceSet> _validateP2ApplicationRoot(
    Directory root,
  ) {
    return P2ApplicationOwnedRuntimeResourceResolver(
      applicationDataRoot: root.absolute,
      executablePath:
          '${root.absolute.path}${Platform.pathSeparator}.runtime-probe',
    ).resolve();
  }

  Future<P3BrowserRuntimeResourceSet> _validateP3ApplicationRoot(
    Directory root,
  ) {
    final current = Directory(
      '${root.absolute.path}${Platform.pathSeparator}runtime'
      '${Platform.pathSeparator}p3${Platform.pathSeparator}current',
    );
    return P3ApplicationOwnedBrowserRuntimeResolver(
      applicationDataRoot: root.absolute,
      executablePath:
          '${root.absolute.path}${Platform.pathSeparator}.runtime-probe',
    ).resolveRoot(current);
  }

  Future<P2RuntimeResourceSet?> _tryP2Current() async {
    try {
      return await _validateP2ApplicationRoot(applicationDataRoot);
    } catch (_) {
      return null;
    }
  }

  Future<P3BrowserRuntimeResourceSet?> _tryP3Current() async {
    try {
      return await _validateP3ApplicationRoot(applicationDataRoot);
    } catch (_) {
      return null;
    }
  }

  Future<P2RuntimeResourceSet?> _bundledP2(
    bool currentAccountRequired,
  ) async {
    final probeRoot = Directory(
      '${applicationDataRoot.path}${Platform.pathSeparator}runtime'
      '${Platform.pathSeparator}.bundled-p2-probe',
    );
    try {
      final resolved = await P2ApplicationOwnedRuntimeResourceResolver(
        applicationDataRoot: probeRoot,
        executablePath: executablePath,
      ).resolve();
      return _p2AuthorityModeMatches(resolved, currentAccountRequired)
          ? resolved
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<P3BrowserRuntimeResourceSet?> _bundledP3() async {
    final candidates = P3ApplicationOwnedBrowserRuntimeResolver.candidateRoots(
      applicationDataRoot: applicationDataRoot,
      executablePath: executablePath,
    );
    final resolver = P3ApplicationOwnedBrowserRuntimeResolver(
      applicationDataRoot: applicationDataRoot,
      executablePath: executablePath,
    );
    for (final candidate in candidates.skip(1)) {
      if (!await candidate.exists()) continue;
      try {
        return await resolver.resolveRoot(candidate);
      } catch (_) {}
    }
    return null;
  }

  bool _p2AuthorityModeMatches(
    P2RuntimeResourceSet resources,
    bool currentAccountRequired,
  ) {
    final currentAccount = resources
            .provisionedEnvironment['KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT'] ==
        '1';
    final ownerRiskQa =
        resources.provisionedEnvironment['KRISTIN_OWNER_RISK_QA'] == '1';
    if (ownerRiskQa) return false;
    return currentAccountRequired ? currentAccount : !currentAccount;
  }

  Future<_SourceIdentity?> _discoverSourceIdentity() async {
    final root = await _discoverSourceRoot();
    if (root == null) return null;
    try {
      final commit = await _git(root, <String>['rev-parse', 'HEAD']);
      final tree = await _git(root, <String>['rev-parse', 'HEAD^{tree}']);
      if (!_hex(commit, 40) || !_hex(tree, 40)) return null;
      return _SourceIdentity(root: root, commit: commit, tree: tree);
    } catch (_) {
      return null;
    }
  }

  Future<Directory?> _discoverSourceRoot() async {
    final candidates = <Directory>[];
    final configured = Platform.environment['KRISTIN_SOURCE_ROOT']?.trim();
    if (configured != null && configured.isNotEmpty) {
      candidates.add(Directory(configured).absolute);
    }
    candidates.add(Directory.current.absolute);
    candidates.add(File(executablePath).absolute.parent);

    final seen = <String>{};
    for (final start in candidates) {
      var current = start;
      for (var depth = 0; depth < 12; depth++) {
        if (seen.add(current.path) && await _isSourceRoot(current)) {
          return current;
        }
        final parent = current.parent;
        if (parent.path == current.path) break;
        current = parent;
      }
    }
    return null;
  }

  Future<bool> _isSourceRoot(Directory root) async {
    final required = <String>[
      'pubspec.yaml',
      'automation_host${Platform.pathSeparator}package-lock.json',
      'config${Platform.pathSeparator}application_runtime_acquisition.v1.json',
      'tool${Platform.pathSeparator}application_runtime_materializer.mjs',
      'tool${Platform.pathSeparator}configure-owner-risk-runtime.mjs',
    ];
    for (final relative in required) {
      if (!await File('${root.path}${Platform.pathSeparator}$relative')
          .exists()) {
        return false;
      }
    }
    return true;
  }

  Future<void> _materializeFromSource({
    required ApplicationRuntimeKind kind,
    required _SourceIdentity source,
    required Directory destination,
  }) async {
    _emit(
      kind,
      ApplicationRuntimeProvisioningPhase.acquiring,
      kind == ApplicationRuntimeKind.p2
          ? 'Preparing local Owner Mode runtime...'
          : 'Preparing browser runtime...',
      fraction: 0.2,
    );
    final acquisition = await _readAcquisitionLock(source.root);
    final toolchain =
        await _ensureNodeToolchain(source.root, acquisition, kind);
    final materializer = File(
      '${source.root.path}${Platform.pathSeparator}tool'
      '${Platform.pathSeparator}application_runtime_materializer.mjs',
    );
    final lockFile = File(
      '${source.root.path}${Platform.pathSeparator}config'
      '${Platform.pathSeparator}application_runtime_acquisition.v1.json',
    );
    await destination.parent.create(recursive: true);
    final result = await _runBounded(
      toolchain.node.path,
      <String>[
        materializer.path,
        '--kind',
        kind.name,
        '--source-root',
        source.root.path,
        '--destination',
        destination.path,
        '--node',
        toolchain.node.path,
        '--npm-cli',
        toolchain.npmCli.path,
        '--source-commit',
        source.commit,
        '--source-tree',
        source.tree,
        '--lock',
        lockFile.path,
      ],
      workingDirectory: source.root.path,
      timeout: kind == ApplicationRuntimeKind.p3
          ? const Duration(minutes: 18)
          : const Duration(minutes: 10),
    );
    if (result.exitCode != 0) {
      throw StateError(
        '${kind.name}_runtime_materialization_failed:${_boundedDiagnostic(result)}',
      );
    }
  }

  Future<_RuntimeAcquisitionLock> _readAcquisitionLock(
    Directory sourceRoot,
  ) async {
    final file = File(
      '${sourceRoot.path}${Platform.pathSeparator}config'
      '${Platform.pathSeparator}application_runtime_acquisition.v1.json',
    );
    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map ||
        raw['schemaVersion'] != '1.0.0' ||
        raw['acquisitionType'] !=
            'kristin-application-runtime-acquisition-v1' ||
        raw['platforms'] is! Map) {
      throw StateError('application_runtime_acquisition_lock_invalid');
    }
    final platformKey = await _platformKey();
    final platformRaw = (raw['platforms'] as Map)[platformKey];
    if (platformRaw is! Map || platformRaw['node'] is! Map) {
      throw StateError('application_runtime_platform_unsupported:$platformKey');
    }
    final node = Map<String, Object?>.from(platformRaw['node'] as Map);
    final url = Uri.tryParse(node['url']?.toString() ?? '');
    final archiveSha = node['archiveSha256']?.toString().toLowerCase() ?? '';
    final executableSha =
        node['executableSha256']?.toString().toLowerCase() ?? '';
    final executableName = node['executableName']?.toString() ?? '';
    final npmCliSuffix = node['npmCliSuffix']?.toString() ?? '';
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'nodejs.org' ||
        !_hex(archiveSha, 64) ||
        !_hex(executableSha, 64) ||
        executableName.isEmpty ||
        npmCliSuffix.isEmpty) {
      throw StateError('application_runtime_node_acquisition_invalid');
    }
    final packageLock =
        raw['p3PackageLockSha256']?.toString().toLowerCase() ?? '';
    final browserRevision = raw['p3BrowserRevision']?.toString() ?? '';
    final nodeVersion = raw['nodeVersion']?.toString() ?? '';
    if (!_hex(packageLock, 64) ||
        browserRevision.isEmpty ||
        nodeVersion.isEmpty) {
      throw StateError('application_runtime_acquisition_identity_invalid');
    }
    return _RuntimeAcquisitionLock(
      nodeVersion: nodeVersion,
      platformKey: platformKey,
      nodeUrl: url,
      nodeArchiveSha256: archiveSha,
      nodeExecutableSha256: executableSha,
      nodeExecutableName: executableName,
      npmCliSuffix: npmCliSuffix.replaceAll('/', Platform.pathSeparator),
      p3PackageLockSha256: packageLock,
      p3BrowserRevision: browserRevision,
    );
  }

  Future<_NodeToolchain> _ensureNodeToolchain(
    Directory sourceRoot,
    _RuntimeAcquisitionLock lock,
    ApplicationRuntimeKind kind,
  ) async {
    final root = Directory(
      '${applicationDataRoot.path}${Platform.pathSeparator}runtime'
      '${Platform.pathSeparator}toolchains${Platform.pathSeparator}node'
      '${Platform.pathSeparator}${lock.nodeVersion}'
      '${Platform.pathSeparator}${lock.platformKey}',
    );
    final extracted = Directory(
      '${root.path}${Platform.pathSeparator}extracted',
    );
    final cached = await _locateNodeToolchain(extracted, lock);
    if (cached != null) return cached;

    await root.create(recursive: true);
    final archiveName = lock.nodeUrl.pathSegments.last;
    final archive = File('${root.path}${Platform.pathSeparator}$archiveName');
    if (!await archive.exists() ||
        Sha256.hex(await archive.readAsBytes()) != lock.nodeArchiveSha256) {
      if (await archive.exists()) await archive.delete();
      _emit(
        kind,
        ApplicationRuntimeProvisioningPhase.acquiring,
        'Downloading pinned Kristin runtime components...',
        fraction: 0.28,
      );
      await _downloadPinned(lock.nodeUrl, archive, lock.nodeArchiveSha256);
    }

    if (await extracted.exists()) await extracted.delete(recursive: true);
    await extracted.create(recursive: true);
    if (Platform.isWindows) {
      final result = await _runBounded(
        'powershell.exe',
        <String>[
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '& { param([string]\$p,[string]\$d) '
              'Expand-Archive -LiteralPath \$p -DestinationPath \$d -Force }',
          archive.path,
          extracted.path,
        ],
        timeout: const Duration(minutes: 3),
      );
      if (result.exitCode != 0) {
        throw StateError(
          'application_runtime_node_extract_failed:${_boundedDiagnostic(result)}',
        );
      }
    } else {
      final result = await _runBounded(
        'tar',
        <String>['-xzf', archive.path, '-C', extracted.path],
        timeout: const Duration(minutes: 3),
      );
      if (result.exitCode != 0) {
        throw StateError(
          'application_runtime_node_extract_failed:${_boundedDiagnostic(result)}',
        );
      }
    }
    final resolved = await _locateNodeToolchain(extracted, lock);
    if (resolved == null) {
      throw StateError('application_runtime_node_executable_invalid');
    }
    return resolved;
  }

  Future<_NodeToolchain?> _locateNodeToolchain(
    Directory extracted,
    _RuntimeAcquisitionLock lock,
  ) async {
    if (!await extracted.exists()) return null;
    File? node;
    File? npmCli;
    await for (final entity in extracted.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || await FileSystemEntity.isLink(entity.path)) {
        continue;
      }
      final normalized = entity.path.replaceAll('\\', '/');
      if (node == null &&
          entity.uri.pathSegments.last == lock.nodeExecutableName) {
        node = entity;
      }
      if (npmCli == null &&
          normalized.endsWith(lock.npmCliSuffix.replaceAll('\\', '/'))) {
        npmCli = entity;
      }
    }
    if (node == null || npmCli == null) return null;
    if (Sha256.hex(await node.readAsBytes()) != lock.nodeExecutableSha256) {
      return null;
    }
    if (!Platform.isWindows) {
      await _runBounded('chmod', <String>['755', node.path]);
    }
    return _NodeToolchain(node: node, npmCli: npmCli);
  }

  Future<void> _downloadPinned(
    Uri source,
    File destination,
    String expectedSha256,
  ) async {
    final partial = File('${destination.path}.part');
    if (await partial.exists()) await partial.delete();
    final client = _httpClientFactory();
    client.connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(source).timeout(
            const Duration(seconds: 30),
          );
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'KristinLocalAgent-RuntimeProvisioner/1',
      );
      final response =
          await request.close().timeout(const Duration(seconds: 45));
      if (response.statusCode != HttpStatus.ok) {
        throw StateError(
          'application_runtime_download_http_${response.statusCode}',
        );
      }
      if (response.contentLength > 160 * 1024 * 1024) {
        throw StateError('application_runtime_download_too_large');
      }
      final sink = partial.openWrite();
      await response.pipe(sink).timeout(const Duration(minutes: 6));
      final actual = Sha256.hex(await partial.readAsBytes());
      if (actual != expectedSha256) {
        throw StateError('application_runtime_download_digest_mismatch');
      }
      await partial.rename(destination.path);
    } finally {
      client.close(force: true);
      if (await partial.exists()) {
        try {
          await partial.delete();
        } catch (_) {}
      }
    }
  }

  Future<String> _platformKey() async {
    if (Platform.isWindows) {
      final raw = (Platform.environment['PROCESSOR_ARCHITEW6432'] ??
              Platform.environment['PROCESSOR_ARCHITECTURE'] ??
              '')
          .toLowerCase();
      if (raw.contains('arm64')) return 'windows-arm64';
      if (raw.contains('amd64') || raw.contains('x86_64')) return 'windows-x64';
      return 'windows-x64';
    }
    final result = await _runBounded(
      'uname',
      const <String>['-m'],
      timeout: const Duration(seconds: 5),
    );
    if (result.exitCode != 0) {
      throw StateError('application_runtime_architecture_unknown');
    }
    final arch = result.stdout.trim().toLowerCase();
    final normalized = arch == 'arm64' || arch == 'aarch64' ? 'arm64' : 'x64';
    return Platform.isMacOS ? 'macos-$normalized' : 'linux-$normalized';
  }

  Future<String> _git(Directory root, List<String> arguments) async {
    final result = await _runBounded(
      'git',
      <String>['-C', root.path, ...arguments],
      timeout: const Duration(seconds: 8),
    );
    if (result.exitCode != 0) {
      throw StateError('application_runtime_git_identity_unavailable');
    }
    return result.stdout.trim().toLowerCase();
  }

  Future<_BoundedProcessResult> _runBounded(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration timeout = const Duration(minutes: 2),
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: true,
      runInShell: false,
    );
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill();
      throw StateError('application_runtime_subprocess_timeout');
    }
    return _BoundedProcessResult(
      exitCode: exitCode,
      stdout: await stdoutFuture,
      stderr: await stderrFuture,
    );
  }

  Future<void> _prepareWindowsBrowserAcl(Directory browserRoot) async {
    if (!Platform.isWindows || !await browserRoot.exists()) return;
    final result = await _runBounded(
      'icacls.exe',
      <String>[
        browserRoot.path,
        '/grant',
        '*S-1-15-2-1:(OI)(CI)(RX)',
        '*S-1-15-2-2:(OI)(CI)(RX)',
        '/T',
        '/Q',
      ],
      timeout: const Duration(minutes: 2),
    );
    if (result.exitCode != 0) {
      throw StateError(
        'p3_windows_sandbox_acl_preparation_failed:${_boundedDiagnostic(result)}',
      );
    }
  }

  Future<void> _copyRuntimeTree(
    Directory source,
    Directory destination, {
    required bool allowInternalSymlinks,
  }) async {
    if (await destination.exists()) await destination.delete(recursive: true);
    await destination.create(recursive: true);
    if (!Platform.isWindows) {
      final result = await _runBounded(
        'cp',
        <String>[
          '-a',
          '${source.path}${Platform.pathSeparator}.',
          destination.path
        ],
        timeout: const Duration(minutes: 5),
      );
      if (result.exitCode != 0) {
        throw StateError(
          'application_runtime_bundle_copy_failed:${_boundedDiagnostic(result)}',
        );
      }
      return;
    }
    final sourceRoot = source.absolute.path;
    final resolvedRoot = await source.resolveSymbolicLinks();
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final relative = entity.path.substring(sourceRoot.length + 1);
      final target = '${destination.path}${Platform.pathSeparator}$relative';
      if (await FileSystemEntity.isLink(entity.path)) {
        if (!allowInternalSymlinks) {
          throw StateError('application_runtime_bundle_symlink_forbidden');
        }
        final link = Link(entity.path);
        final raw = await link.target();
        if (File(raw).isAbsolute) {
          throw StateError('application_runtime_bundle_absolute_symlink');
        }
        final resolved = await link.resolveSymbolicLinks();
        if (resolved != resolvedRoot &&
            !resolved.startsWith('$resolvedRoot${Platform.pathSeparator}')) {
          throw StateError('application_runtime_bundle_escaping_symlink');
        }
        await Link(target).create(raw, recursive: true);
      } else if (entity is Directory) {
        await Directory(target).create(recursive: true);
      } else if (entity is File) {
        await File(target).parent.create(recursive: true);
        await entity.copy(target);
      }
    }
  }

  void _slotPhase(ApplicationRuntimeKind kind, AtomicRuntimeSlotPhase phase) {
    switch (phase) {
      case AtomicRuntimeSlotPhase.validating:
        _emit(
          kind,
          ApplicationRuntimeProvisioningPhase.validating,
          'Validating exact runtime...',
          fraction: 0.78,
        );
      case AtomicRuntimeSlotPhase.promoting:
        _emit(
          kind,
          ApplicationRuntimeProvisioningPhase.promoting,
          'Activating runtime...',
          fraction: 0.92,
        );
      case AtomicRuntimeSlotPhase.preparing:
        _emit(
          kind,
          ApplicationRuntimeProvisioningPhase.preparing,
          kind == ApplicationRuntimeKind.p2
              ? 'Preparing Owner Mode...'
              : 'Preparing Web Studio...',
          fraction: 0.12,
        );
    }
  }

  void _emitReady(ApplicationRuntimeKind kind, String message) {
    _emit(
      kind,
      ApplicationRuntimeProvisioningPhase.ready,
      message,
      fraction: 1,
    );
  }

  void _emitFailure(ApplicationRuntimeKind kind, Object error) {
    _emit(
      kind,
      ApplicationRuntimeProvisioningPhase.failed,
      kind == ApplicationRuntimeKind.p2
          ? "Owner Mode couldn't be prepared."
          : "Web Studio couldn't be prepared.",
      diagnosticCode: _diagnosticCode(error),
    );
  }

  void _emit(
    ApplicationRuntimeKind kind,
    ApplicationRuntimeProvisioningPhase phase,
    String message, {
    double? fraction,
    String? diagnosticCode,
  }) {
    if (_progress.isClosed) return;
    _progress.add(
      ApplicationRuntimeProvisioningProgress(
        kind: kind,
        phase: phase,
        message: message,
        fraction: fraction,
        diagnosticCode: diagnosticCode,
      ),
    );
  }

  static String _diagnosticCode(Object error) {
    final value = error is StateError ? error.message.toString() : '$error';
    final safe = value
        .replaceAll(RegExp(r'[^A-Za-z0-9_.:-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return safe.length <= 180 ? safe : safe.substring(0, 180);
  }

  static String _boundedDiagnostic(_BoundedProcessResult result) {
    final value =
        '${result.stderr}\n${result.stdout}'.replaceAll('\u0000', '').trim();
    if (value.isEmpty) return 'exit_${result.exitCode}';
    return value.length <= 2048 ? value : value.substring(value.length - 2048);
  }

  static bool _hex(String value, int length) =>
      RegExp('^[0-9a-f]{$length}\$').hasMatch(value);
}

enum AtomicRuntimeSlotPhase { preparing, validating, promoting }

final class AtomicApplicationRuntimeSlot<T> {
  AtomicApplicationRuntimeSlot({
    required Directory applicationDataRoot,
    required this.runtimeKind,
    required this.validate,
  }) : applicationDataRoot = applicationDataRoot.absolute;

  final Directory applicationDataRoot;
  final String runtimeKind;
  final Future<T> Function(Directory applicationRoot) validate;
  final Map<String, Future<T>> _inFlight = <String, Future<T>>{};

  Directory get _slotRoot => Directory(
        '${applicationDataRoot.path}${Platform.pathSeparator}runtime'
        '${Platform.pathSeparator}$runtimeKind',
      );

  Directory get _current => Directory(
        '${_slotRoot.path}${Platform.pathSeparator}current',
      );

  Future<T> ensure({
    required String targetIdentity,
    required bool repair,
    required bool Function(T value) matches,
    required Future<void> Function(Directory stagedCurrent) materialize,
    void Function(AtomicRuntimeSlotPhase phase)? onPhase,
  }) {
    final existing = _inFlight[targetIdentity];
    if (existing != null) return existing;
    late final Future<T> future;
    future = _ensure(
      targetIdentity: targetIdentity,
      repair: repair,
      matches: matches,
      materialize: materialize,
      onPhase: onPhase,
    ).whenComplete(() {
      if (identical(_inFlight[targetIdentity], future)) {
        _inFlight.remove(targetIdentity);
      }
    });
    _inFlight[targetIdentity] = future;
    return future;
  }

  Future<T> _ensure({
    required String targetIdentity,
    required bool repair,
    required bool Function(T value) matches,
    required Future<void> Function(Directory stagedCurrent) materialize,
    required void Function(AtomicRuntimeSlotPhase phase)? onPhase,
  }) async {
    await _recoverInterruptedPromotion();
    if (!repair && await _current.exists()) {
      try {
        final current = await validate(applicationDataRoot);
        if (matches(current)) return current;
      } catch (_) {}
    }

    onPhase?.call(AtomicRuntimeSlotPhase.preparing);
    final operationId = _operationId();
    final stagingApplicationRoot = Directory(
      '${_slotRoot.path}${Platform.pathSeparator}staging-$operationId',
    );
    final stagedCurrent = Directory(
      '${stagingApplicationRoot.path}${Platform.pathSeparator}runtime'
      '${Platform.pathSeparator}$runtimeKind${Platform.pathSeparator}current',
    );
    final previous = Directory(
      '${_slotRoot.path}${Platform.pathSeparator}previous-$operationId',
    );
    try {
      await stagedCurrent.parent.create(recursive: true);
      await materialize(stagedCurrent);
      onPhase?.call(AtomicRuntimeSlotPhase.validating);
      final staged = await validate(stagingApplicationRoot);
      if (!matches(staged)) {
        throw StateError('${runtimeKind}_runtime_staged_identity_mismatch');
      }

      onPhase?.call(AtomicRuntimeSlotPhase.promoting);
      if (await _current.exists()) {
        await _current.rename(previous.path);
      }
      try {
        await stagedCurrent.rename(_current.path);
        final promoted = await validate(applicationDataRoot);
        if (!matches(promoted)) {
          throw StateError('${runtimeKind}_runtime_promoted_identity_mismatch');
        }
        if (await previous.exists()) await previous.delete(recursive: true);
        return promoted;
      } catch (_) {
        if (await _current.exists()) {
          await _current.delete(recursive: true);
        }
        if (await previous.exists()) {
          await previous.rename(_current.path);
        }
        rethrow;
      }
    } finally {
      if (await stagingApplicationRoot.exists()) {
        try {
          await stagingApplicationRoot.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<void> _recoverInterruptedPromotion() async {
    await _slotRoot.create(recursive: true);
    final staging = <Directory>[];
    final previous = <Directory>[];
    await for (final entity in _slotRoot.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name =
          entity.uri.pathSegments.where((value) => value.isNotEmpty).last;
      if (name.startsWith('staging-')) staging.add(entity);
      if (name.startsWith('previous-')) previous.add(entity);
    }
    if (!await _current.exists() && previous.isNotEmpty) {
      previous.sort((a, b) => a.path.compareTo(b.path));
      final restore = previous.removeLast();
      await restore.rename(_current.path);
    }
    for (final directory in staging) {
      try {
        await directory.delete(recursive: true);
      } catch (_) {}
    }
    if (await _current.exists()) {
      for (final directory in previous) {
        try {
          await directory.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  static String _operationId() {
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    final random = Random.secure().nextInt(0x7fffffff);
    return '$micros-${random.toRadixString(16)}';
  }
}

final class _SourceIdentity {
  const _SourceIdentity({
    required this.root,
    required this.commit,
    required this.tree,
  });

  final Directory root;
  final String commit;
  final String tree;
}

final class _RuntimeAcquisitionLock {
  const _RuntimeAcquisitionLock({
    required this.nodeVersion,
    required this.platformKey,
    required this.nodeUrl,
    required this.nodeArchiveSha256,
    required this.nodeExecutableSha256,
    required this.nodeExecutableName,
    required this.npmCliSuffix,
    required this.p3PackageLockSha256,
    required this.p3BrowserRevision,
  });

  final String nodeVersion;
  final String platformKey;
  final Uri nodeUrl;
  final String nodeArchiveSha256;
  final String nodeExecutableSha256;
  final String nodeExecutableName;
  final String npmCliSuffix;
  final String p3PackageLockSha256;
  final String p3BrowserRevision;
}

final class _NodeToolchain {
  const _NodeToolchain({required this.node, required this.npmCli});

  final File node;
  final File npmCli;
}

final class _BoundedProcessResult {
  const _BoundedProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}
