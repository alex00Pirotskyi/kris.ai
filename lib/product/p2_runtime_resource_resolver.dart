import 'dart:convert';
import 'dart:io';

import 'crypto_utils.dart';

final class P2RuntimeResourceSet {
  const P2RuntimeResourceSet({
    required this.root,
    required this.manifestPath,
    required this.manifestSha256,
    required this.sourceCommit,
    required this.sourceTree,
    required this.runtimeBuildSha256,
    required this.p1AuthorityServiceContractSha256,
    required this.nodeExecutable,
    required this.hostScript,
    required this.workingDirectory,
    required this.restrictedWorkerLauncher,
    required this.restrictedWorkerLauncherSha256,
    required this.workerPolicy,
    required this.workerPolicySha256,
    required this.nodeExecutableSha256,
    required this.hostScriptSha256,
    this.windowsJobHelper,
    this.posixWatchdog,
    this.interactiveDesktopAdapter,
    this.provisionedEnvironment = const <String, String>{},
  });

  final Directory root;
  final String manifestPath;
  final String manifestSha256;
  final String sourceCommit;
  final String sourceTree;
  final String runtimeBuildSha256;
  final String p1AuthorityServiceContractSha256;
  final String nodeExecutable;
  final String hostScript;
  final String workingDirectory;
  final String restrictedWorkerLauncher;
  final String restrictedWorkerLauncherSha256;
  final String workerPolicy;
  final String workerPolicySha256;
  final String nodeExecutableSha256;
  final String hostScriptSha256;
  final String? windowsJobHelper;
  final String? posixWatchdog;
  final String? interactiveDesktopAdapter;
  final Map<String, String> provisionedEnvironment;

  Map<String, Object?> get provenance => <String, Object?>{
    'resolver': 'P2ApplicationOwnedRuntimeResourceResolver',
    'applicationOwned': true,
    'sourceWorkingDirectoryIndependent': true,
    'manifestSha256': manifestSha256,
    'sourceCommit': sourceCommit,
    'sourceTree': sourceTree,
    'runtimeBuildSha256': runtimeBuildSha256,
    'p1AuthorityServiceContractSha256': p1AuthorityServiceContractSha256,
    'rootPathSha256': Sha256.text(root.absolute.path),
    'nodePathSha256': Sha256.text(nodeExecutable),
    'hostScriptPathSha256': Sha256.text(hostScript),
    'restrictedWorkerLauncherPathSha256': Sha256.text(restrictedWorkerLauncher),
    'workerPolicyPathSha256': Sha256.text(workerPolicy),
    'provisionedEnvironmentKeys': provisionedEnvironment.keys.toList()..sort(),
    'provisionedEnvironmentSha256': Sha256.text(
      jsonEncode(<String, String>{
        for (final key in (provisionedEnvironment.keys.toList()..sort()))
          key: provisionedEnvironment[key]!,
      }),
    ),
  };
}

final class P2ApplicationOwnedRuntimeResourceResolver {
  P2ApplicationOwnedRuntimeResourceResolver({
    required this.applicationDataRoot,
    String? executablePath,
  }) : executablePath = executablePath ?? Platform.resolvedExecutable;

  final Directory applicationDataRoot;
  final String executablePath;

  Future<P2RuntimeResourceSet> resolve() async {
    if (!applicationDataRoot.isAbsolute) {
      throw StateError('application_data_root_must_be_absolute');
    }
    final executableRoot = File(executablePath).absolute.parent;
    final candidates = <Directory>[
      Directory(
        '${applicationDataRoot.absolute.path}${Platform.pathSeparator}'
        'runtime${Platform.pathSeparator}p2${Platform.pathSeparator}current',
      ),
      Directory(
        '${executableRoot.path}${Platform.pathSeparator}'
        'runtime${Platform.pathSeparator}p2${Platform.pathSeparator}current',
      ),
    ];
    Object? lastError;
    for (final candidate in candidates) {
      if (!await candidate.exists()) continue;
      try {
        return await _resolveRoot(candidate.absolute);
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) {
      throw StateError('p2_application_runtime_bundle_invalid:$lastError');
    }
    throw StateError('p2_application_runtime_bundle_missing');
  }

  Future<P2RuntimeResourceSet> _resolveRoot(Directory root) async {
    final manifest = File(
      '${root.path}${Platform.pathSeparator}runtime-manifest.v3.json',
    );
    if (!await manifest.exists() ||
        await FileSystemEntity.isLink(manifest.path)) {
      throw StateError('runtime_manifest_missing_or_symlink');
    }
    final decoded = jsonDecode(await manifest.readAsString());
    const buildOwnerRiskQa = bool.fromEnvironment(
      'KRISTIN_OWNER_RISK_QA',
      defaultValue: false,
    );
    final manifestOwnerRiskQa =
        decoded is Map && decoded['ownerRiskQa'] == true;
    final ownerRiskQa = buildOwnerRiskQa || manifestOwnerRiskQa;
    if (decoded is! Map ||
        decoded['schemaVersion'] != '3.0.0' ||
        decoded['bundleType'] != 'kristin-p2-application-runtime-v3' ||
        decoded['resources'] is! Map ||
        decoded['identity'] is! Map ||
        decoded['workingDirectoryIndependent'] != true ||
        decoded['currentWorkingDirectoryUsed'] != false ||
        decoded['authorityServiceExecutableStaged'] != false ||
        decoded['authorityBrokerStaged'] != false ||
        decoded['rawAuthoritySecretsIncluded'] != false ||
        decoded['p2DelegationOnly'] != true ||
        (!ownerRiskQa && decoded['authorityServiceExternal'] != true) ||
        (ownerRiskQa && decoded['authorityServiceExternal'] != false) ||
        (!ownerRiskQa && decoded['restrictedWorkerLauncherExternal'] != true) ||
        (ownerRiskQa && decoded['restrictedWorkerLauncherExternal'] != false) ||
        (!ownerRiskQa &&
            decoded['restrictedWorkerLauncherOsEnforced'] != true) ||
        (ownerRiskQa &&
            decoded['restrictedWorkerLauncherOsEnforced'] != false) ||
        (ownerRiskQa && decoded['ownerRiskQa'] != true)) {
      throw StateError('runtime_manifest_identity_invalid');
    }
    final identity = Map<String, Object?>.from(decoded['identity']! as Map);
    final sourceCommit = _hex(identity, 'sourceCommit', 40);
    final sourceTree = _hex(identity, 'sourceTree', 40);
    final runtimeBuildSha256 = _hex(identity, 'runtimeBuildSha256', 64);
    final p1AuthorityServiceContractSha256 = _hex(
      identity,
      'p1AuthorityServiceContractSha256',
      64,
    );
    final resources = Map<dynamic, dynamic>.from(decoded['resources']! as Map);

    final node = await _fileResource(root, resources, 'nodeExecutable', true);
    final host = await _fileResource(root, resources, 'automationHost', true);
    final working = await _directoryResource(
      root,
      resources,
      'automationHostRoot',
      true,
    );

    final restrictedWorkerLauncher = await _fileResource(
      root,
      resources,
      'restrictedWorkerLauncher',
      true,
      allowExternal: true,
    );
    final workerPolicy = await _fileResource(
      root,
      resources,
      'restrictedWorkerPolicy',
      true,
    );

    final provisioningPath = await _fileResource(
      root,
      resources,
      'runtimeProvisioning',
      true,
    );
    final provisionedEnvironment = await _readProvisionedEnvironment(
      File(provisioningPath!),
    );
    return P2RuntimeResourceSet(
      root: root,
      manifestPath: manifest.absolute.path,
      manifestSha256: Sha256.hex(await manifest.readAsBytes()),
      sourceCommit: sourceCommit,
      sourceTree: sourceTree,
      runtimeBuildSha256: runtimeBuildSha256,
      p1AuthorityServiceContractSha256: p1AuthorityServiceContractSha256,
      nodeExecutable: node!,
      hostScript: host!,
      workingDirectory: working!,
      restrictedWorkerLauncher: restrictedWorkerLauncher!,
      restrictedWorkerLauncherSha256: _resourceSha256(
        resources,
        'restrictedWorkerLauncher',
      ),
      workerPolicy: workerPolicy!,
      workerPolicySha256: _resourceSha256(resources, 'restrictedWorkerPolicy'),
      nodeExecutableSha256: _resourceSha256(resources, 'nodeExecutable'),
      hostScriptSha256: _resourceSha256(resources, 'automationHost'),
      windowsJobHelper: await _fileResource(
        root,
        resources,
        'windowsJobHelper',
        false,
      ),
      posixWatchdog: await _fileResource(
        root,
        resources,
        'posixWatchdog',
        false,
      ),
      interactiveDesktopAdapter: await _fileResource(
        root,
        resources,
        'interactiveDesktopAdapter',
        false,
      ),
      provisionedEnvironment: provisionedEnvironment,
    );
  }

  static Future<Map<String, String>> _readProvisionedEnvironment(
    File file,
  ) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map ||
        decoded['schemaVersion'] != '1.0.0' ||
        decoded['provisioningType'] !=
            'kristin-p2-application-runtime-environment-v1' ||
        decoded['environment'] is! Map ||
        decoded['containsSecrets'] != false) {
      throw StateError('runtime_provisioning_identity_invalid');
    }
    const allowed = <String>{
      'KRISTIN_P2_NATIVE_SERVICE_ID',
      'KRISTIN_P2_NATIVE_SERVICE_PROVIDER',
      'KRISTIN_P2_NATIVE_SERVICE_ATTESTATION',
      'KRISTIN_P2_NATIVE_SERVICE_ATTESTATION_SHA256',
      'KRISTIN_P2_RUNNER_ATTESTATION_RECEIPT',
      'KRISTIN_P2_RUNNER_ATTESTATION_SHA256',
      'KRISTIN_P2_RUNNER_POLICY',
      'KRISTIN_P2_RUNNER_POLICY_SHA256',
      'KRISTIN_P2_COMMIT_SHA',
      'KRISTIN_P2_SOURCE_PACKAGE_SHA256',
      'KRISTIN_P2_E2E_ROOT',
      'KRISTIN_P2_RUNNER_ID',
      'KRISTIN_P2_RUNNER_GROUP',
      'KRISTIN_P2_RUNNER_CONFIGURATION_SHA256',
      'KRISTIN_P2_AUTHORITY_PROVISIONING_SHA256',
      'KRISTIN_P1A_MERGED_MANIFEST',
      'KRISTIN_P1A_MERGED_MANIFEST_SHA256',
      'KRISTIN_P1A_PLATFORM_RECEIPT',
      'KRISTIN_P1A_PLATFORM_RECEIPT_SHA256',
      'KRISTIN_P1A_EVIDENCE_TRUST',
      'KRISTIN_P1A_EVIDENCE_TRUST_SHA256',
      'KRISTIN_P1A_SERVICE_BEHAVIOR_RECEIPT_SHA256',
      'KRISTIN_P1A_WORKER_DENIAL_RECEIPT_SHA256',
      'KRISTIN_P1A_WORKER_LAUNCHER_SHA256',
      'KRISTIN_P1A_WORKER_EXECUTABLE_SHA256',
      'KRISTIN_P1A_WORKER_IDENTITY_SHA256',
      'KRISTIN_P1A_DENIAL_TRANSCRIPT_SHA256',
      'KRISTIN_P2_NPM_EXECUTABLE',
      'KRISTIN_P2_CONTROLLED_PACKAGE_MANAGER',
      'KRISTIN_P2_CONTROLLED_PACKAGE_NAME',
      'KRISTIN_P2_CONTROLLED_PACKAGE_SOURCE',
      'KRISTIN_P2_CONTROLLED_PACKAGE_PREFIX',
      'KRISTIN_P2_TOOLCHAIN_EXTENSION_FINGERPRINT',
      'KRISTIN_P2_NATIVE_RUNTIME_MANIFEST',
      'KRISTIN_P2_NATIVE_RUNTIME_MANIFEST_SHA256',
      'GITHUB_REPOSITORY',
      'GITHUB_WORKFLOW',
      'GITHUB_WORKFLOW_REF',
      'GITHUB_RUN_ID',
      'GITHUB_RUN_ATTEMPT',
      'GITHUB_JOB',
      'RUNNER_NAME',
      'KRISTIN_OWNER_RISK_QA',
      'KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT',
    };
    final raw = Map<dynamic, dynamic>.from(decoded['environment']! as Map);
    final result = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final value = entry.value?.toString() ?? '';
      if (!allowed.contains(key) ||
          value.isEmpty ||
          key.contains('=') ||
          value.contains('\u0000') ||
          RegExp(
            r'(secret|token|password|credential|api.?key|private.?key|seed)',
            caseSensitive: false,
          ).hasMatch(key)) {
        throw StateError('runtime_provisioning_entry_invalid:$key');
      }
      result[key] = value;
    }
    if (result.isEmpty) {
      throw StateError('runtime_provisioning_environment_empty');
    }
    return Map<String, String>.unmodifiable(result);
  }

  static String _hex(Map<String, Object?> value, String key, int length) {
    final item = value[key]?.toString().toLowerCase() ?? '';
    if (!RegExp('^[0-9a-f]{$length}\$').hasMatch(item)) {
      throw StateError('runtime_identity_$key');
    }
    return item;
  }

  Future<String?> _fileResource(
    Directory root,
    Map<dynamic, dynamic> resources,
    String key,
    bool required, {
    bool allowExternal = false,
  }) async {
    final row = _resourceRow(resources, key, required);
    if (row == null) return null;
    final external = row['kind'] == 'external-file';
    if (row['kind'] != 'file' && !(allowExternal && external)) {
      throw StateError('runtime_resource_kind:$key');
    }
    final path = external
        ? File(_externalPath(row, key)).absolute
        : File(_candidatePath(root, row, key)).absolute;
    if (external) {
      if (row['osEnforcedIdentityTransition'] != true) {
        throw StateError('runtime_external_identity_transition_missing:$key');
      }
    } else {
      await _validateContained(root, path.path, key);
    }
    if (!await path.exists() || await FileSystemEntity.isLink(path.path)) {
      throw StateError('runtime_resource_missing_or_symlink:$key');
    }
    final actual = Sha256.hex(await path.readAsBytes());
    if (actual != row['sha256']) {
      throw StateError('runtime_resource_digest_mismatch:$key');
    }
    return path.path;
  }

  Future<String?> _directoryResource(
    Directory root,
    Map<dynamic, dynamic> resources,
    String key,
    bool required,
  ) async {
    final row = _resourceRow(resources, key, required);
    if (row == null) return null;
    if (row['kind'] != 'directory') {
      throw StateError('runtime_resource_kind:$key');
    }
    final path = Directory(_candidatePath(root, row, key)).absolute;
    await _validateContained(root, path.path, key);
    if (!await path.exists() || await FileSystemEntity.isLink(path.path)) {
      throw StateError('runtime_resource_missing_or_symlink:$key');
    }
    final expected = row['treeSha256']?.toString().toLowerCase() ?? '';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
      throw StateError('runtime_directory_digest_invalid:$key');
    }
    final actual = await _directoryDigest(path);
    if (actual != expected) {
      throw StateError('runtime_directory_digest_mismatch:$key');
    }
    return path.path;
  }

  static String _resourceSha256(Map<dynamic, dynamic> resources, String key) {
    final raw = resources[key];
    if (raw is! Map) throw StateError('runtime_resource_$key');
    final digest = raw['sha256']?.toString().toLowerCase() ?? '';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
      throw StateError('runtime_resource_digest_invalid:$key');
    }
    return digest;
  }

  static Map<String, Object?>? _resourceRow(
    Map<dynamic, dynamic> resources,
    String key,
    bool required,
  ) {
    final raw = resources[key];
    if (raw == null && !required) return null;
    if (raw is! Map) throw StateError('runtime_resource_$key');
    return Map<String, Object?>.from(raw);
  }

  static String _externalPath(Map<String, Object?> row, String key) {
    final value = row['path']?.toString() ?? '';
    final absolute =
        value.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value) ||
        value.startsWith(r'\\');
    if (!absolute ||
        value.contains('\u0000') ||
        value.split(RegExp(r'[\\/]')).contains('..')) {
      throw StateError('runtime_external_resource_path_invalid:$key');
    }
    return value;
  }

  static String _candidatePath(
    Directory root,
    Map<String, Object?> row,
    String key,
  ) {
    final relative = row['path']?.toString() ?? '';
    if (relative.isEmpty ||
        relative.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(relative) ||
        relative.split(RegExp(r'[\\/]')).contains('..')) {
      throw StateError('runtime_resource_path_invalid:$key');
    }
    return '${root.path}${Platform.pathSeparator}'
        '${relative.replaceAll('/', Platform.pathSeparator)}';
  }

  static Future<void> _validateContained(
    Directory root,
    String path,
    String key,
  ) async {
    final resolvedRoot = await root.resolveSymbolicLinks();
    final entity = FileSystemEntity.typeSync(path, followLinks: false);
    if (entity == FileSystemEntityType.notFound) {
      throw StateError('runtime_resource_missing:$key');
    }
    final resolvedPath = entity == FileSystemEntityType.directory
        ? await Directory(path).resolveSymbolicLinks()
        : await File(path).resolveSymbolicLinks();
    final prefix = resolvedRoot.endsWith(Platform.pathSeparator)
        ? resolvedRoot
        : '$resolvedRoot${Platform.pathSeparator}';
    if (resolvedPath != resolvedRoot && !resolvedPath.startsWith(prefix)) {
      throw StateError('runtime_resource_escape:$key');
    }
  }

  static Future<String> _directoryDigest(Directory directory) async {
    final rows = <String>[];
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (await FileSystemEntity.isLink(entity.path)) {
        throw StateError('runtime_directory_symlink_rejected');
      }
      if (entity is! File) continue;
      final relative = entity.path
          .substring(directory.path.length)
          .replaceAll('\\', '/')
          .replaceFirst(RegExp(r'^/+'), '');
      rows.add('$relative\u0000${Sha256.hex(await entity.readAsBytes())}');
    }
    rows.sort();
    return Sha256.text(rows.join('\n'));
  }
}
