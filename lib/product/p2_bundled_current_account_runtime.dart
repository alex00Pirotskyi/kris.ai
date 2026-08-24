import 'dart:convert';
import 'dart:io';

final class P2BundledCurrentAccountRuntime {
  const P2BundledCurrentAccountRuntime._();

  static Future<bool> prepareIfPresent({
    required Directory applicationDataRoot,
    String? executablePath,
  }) async {
    final executable = File(
      executablePath ?? Platform.resolvedExecutable,
    ).absolute;
    final bundledRoot = Directory(
      '${executable.parent.path}${Platform.pathSeparator}runtime'
      '${Platform.pathSeparator}p2${Platform.pathSeparator}current',
    );
    final bundledManifest = File(
      '${bundledRoot.path}${Platform.pathSeparator}runtime-manifest.v3.json',
    );
    if (!await bundledManifest.exists()) return false;
    if (await FileSystemEntity.isLink(bundledManifest.path)) {
      throw StateError('p2_bundled_runtime_manifest_symlink');
    }

    final bundled = _object(
      jsonDecode(await bundledManifest.readAsString()),
      'p2_bundled_runtime_manifest_invalid',
    );
    if (bundled['schemaVersion'] != '3.0.0' ||
        bundled['bundleType'] != 'kristin-p2-application-runtime-v3' ||
        bundled['ownerRiskQa'] != true) {
      return false;
    }

    final targetRoot = Directory(
      '${applicationDataRoot.absolute.path}${Platform.pathSeparator}runtime'
      '${Platform.pathSeparator}p2${Platform.pathSeparator}current',
    );
    final targetManifest = File(
      '${targetRoot.path}${Platform.pathSeparator}runtime-manifest.v3.json',
    );
    final bundledIdentity = _object(
      bundled['identity'],
      'p2_bundled_runtime_identity_invalid',
    );
    final bundledCommit = _hex(
      bundledIdentity['sourceCommit'],
      40,
      'p2_bundled_runtime_source_commit_invalid',
    );
    final bundledTree = _hex(
      bundledIdentity['sourceTree'],
      40,
      'p2_bundled_runtime_source_tree_invalid',
    );

    var replace = !await targetManifest.exists();
    if (!replace) {
      try {
        if (await FileSystemEntity.isLink(targetManifest.path)) {
          replace = true;
        } else {
          final existing = _object(
            jsonDecode(await targetManifest.readAsString()),
            'p2_existing_runtime_manifest_invalid',
          );
          final identity = _object(
            existing['identity'],
            'p2_existing_runtime_identity_invalid',
          );
          replace =
              identity['sourceCommit'] != bundledCommit ||
              identity['sourceTree'] != bundledTree;
        }
      } catch (_) {
        replace = true;
      }
    }
    if (replace) {
      if (await targetRoot.exists()) {
        await targetRoot.delete(recursive: true);
      }
      await _copyTree(bundledRoot, targetRoot);
    }

    final provisioning = File(
      '${targetRoot.path}${Platform.pathSeparator}provisioning'
      '${Platform.pathSeparator}environment.v1.json',
    );
    final provisioningValue = _object(
      jsonDecode(await provisioning.readAsString()),
      'p2_current_account_provisioning_invalid',
    );
    final environment = _object(
      provisioningValue['environment'],
      'p2_current_account_environment_invalid',
    );
    final packageSha = _hex(
      environment['KRISTIN_P2_SOURCE_PACKAGE_SHA256'],
      64,
      'p2_current_account_package_sha_invalid',
    );

    final node = File(
      '${targetRoot.path}${Platform.pathSeparator}node${Platform.pathSeparator}'
      '${Platform.isWindows ? 'node.exe' : 'node'}',
    );
    final configurator = File(
      '${targetRoot.path}${Platform.pathSeparator}tools${Platform.pathSeparator}'
      'configure-owner-risk-runtime.mjs',
    );
    final contract = File(
      '${targetRoot.path}${Platform.pathSeparator}contracts${Platform.pathSeparator}'
      'p1_authority_service_contract_v1.dart',
    );
    for (final file in <File>[node, configurator, contract]) {
      if (!await file.exists() || await FileSystemEntity.isLink(file.path)) {
        throw StateError('p2_current_account_runtime_component_missing');
      }
    }

    final result = await Process.run(
      node.path,
      <String>[
        configurator.path,
        '--root',
        targetRoot.path,
        '--platform',
        Platform.isWindows ? 'windows' : (Platform.isMacOS ? 'macos' : 'linux'),
        '--source-commit',
        bundledCommit,
        '--source-tree',
        bundledTree,
        '--p2-package-sha256',
        packageSha,
        '--p1-contract',
        contract.path,
        '--mode',
        'product-current-account',
      ],
      workingDirectory: targetRoot.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) {
      throw StateError('p2_current_account_runtime_configuration_failed');
    }

    final configured = _object(
      jsonDecode(await targetManifest.readAsString()),
      'p2_current_account_manifest_invalid',
    );
    if (configured['productCurrentAccount'] != true ||
        configured['ownerRiskQa'] != true) {
      throw StateError('p2_current_account_manifest_not_enabled');
    }
    return true;
  }

  static Future<void> _copyTree(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final relative = entity.path.substring(source.path.length + 1);
      final target = '${destination.path}${Platform.pathSeparator}$relative';
      if (await FileSystemEntity.isLink(entity.path)) {
        throw StateError('p2_bundled_runtime_symlink_forbidden');
      }
      if (entity is Directory) {
        await Directory(target).create(recursive: true);
        continue;
      }
      if (entity is! File) continue;
      final file = File(target);
      await file.parent.create(recursive: true);
      await entity.copy(file.path);
      if (!Platform.isWindows) {
        final mode = (await entity.stat()).mode;
        await Process.run('chmod', <String>[
          (mode & 0x1ff).toRadixString(8).padLeft(3, '0'),
          file.path,
        ]);
      }
    }
  }

  static Map<String, Object?> _object(Object? value, String error) {
    if (value is! Map) throw StateError(error);
    return Map<String, Object?>.from(value);
  }

  static String _hex(Object? value, int length, String error) {
    final text = value?.toString().toLowerCase() ?? '';
    if (!RegExp('^[0-9a-f]{$length}\$').hasMatch(text)) {
      throw StateError(error);
    }
    return text;
  }
}
