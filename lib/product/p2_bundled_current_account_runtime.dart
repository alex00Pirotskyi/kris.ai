import 'dart:convert';
import 'dart:io';

import 'application_runtime_provisioner.dart';
import 'p2_runtime_resource_resolver.dart';

final class P2BundledCurrentAccountRuntime {
  const P2BundledCurrentAccountRuntime._();

  static Future<bool> prepareIfPresent({
    required Directory applicationDataRoot,
    String? executablePath,
  }) async {
    final executable = File(
      executablePath ?? Platform.resolvedExecutable,
    ).absolute;
    final bundledCandidates = <Directory>[
      if (Platform.isMacOS)
        Directory(
          '${executable.parent.parent.path}${Platform.pathSeparator}Resources'
          '${Platform.pathSeparator}runtime${Platform.pathSeparator}p2'
          '${Platform.pathSeparator}current',
        ),
      Directory(
        '${executable.parent.path}${Platform.pathSeparator}runtime'
        '${Platform.pathSeparator}p2${Platform.pathSeparator}current',
      ),
    ];
    Directory? selectedBundledRoot;
    for (final candidate in bundledCandidates) {
      final manifest = File(
        '${candidate.path}${Platform.pathSeparator}runtime-manifest.v3.json',
      );
      if (!await manifest.exists()) continue;
      if (await FileSystemEntity.isLink(manifest.path)) {
        throw StateError('p2_bundled_runtime_manifest_symlink');
      }
      selectedBundledRoot = candidate;
      break;
    }
    if (selectedBundledRoot == null) return false;

    final bundledRoot = selectedBundledRoot;
    final bundledManifest = File(
      '${bundledRoot.path}${Platform.pathSeparator}runtime-manifest.v3.json',
    );
    final bundled = _object(
      jsonDecode(await bundledManifest.readAsString()),
      'p2_bundled_runtime_manifest_invalid',
    );
    if (bundled['schemaVersion'] != '3.0.0' ||
        bundled['bundleType'] != 'kristin-p2-application-runtime-v3' ||
        bundled['productCurrentAccount'] != true ||
        bundled['ownerRiskQa'] != false) {
      return false;
    }
    final identity = _object(
      bundled['identity'],
      'p2_bundled_runtime_identity_invalid',
    );
    final sourceCommit = _hex(
      identity['sourceCommit'],
      40,
      'p2_bundled_runtime_source_commit_invalid',
    );
    final sourceTree = _hex(
      identity['sourceTree'],
      40,
      'p2_bundled_runtime_source_tree_invalid',
    );
    final runtimeBuildSha256 = _hex(
      identity['runtimeBuildSha256'],
      64,
      'p2_bundled_runtime_build_invalid',
    );

    final slot = AtomicApplicationRuntimeSlot<P2RuntimeResourceSet>(
      applicationDataRoot: applicationDataRoot.absolute,
      runtimeKind: 'p2',
      validate: (applicationRoot) => P2ApplicationOwnedRuntimeResourceResolver(
        applicationDataRoot: applicationRoot.absolute,
        executablePath:
            '${applicationRoot.absolute.path}${Platform.pathSeparator}'
            '.p2-bundled-runtime-probe',
      ).resolve(),
    );
    await slot.ensure(
      targetIdentity:
          'bundled:$sourceCommit:$sourceTree:$runtimeBuildSha256:current-account',
      repair: false,
      matches: (resources) =>
          resources.sourceCommit == sourceCommit &&
          resources.sourceTree == sourceTree &&
          resources.runtimeBuildSha256 == runtimeBuildSha256 &&
          resources.provisionedEnvironment[
                  'KRISTIN_CURRENT_ACCOUNT_OWNER_PRODUCT'] ==
              '1' &&
          !resources.provisionedEnvironment
              .containsKey('KRISTIN_OWNER_RISK_QA'),
      materialize: (destination) => _copyTree(bundledRoot, destination),
    );
    return true;
  }

  static Future<void> _copyTree(
    Directory source,
    Directory destination,
  ) async {
    if (await destination.exists()) {
      await destination.delete(recursive: true);
    }
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
