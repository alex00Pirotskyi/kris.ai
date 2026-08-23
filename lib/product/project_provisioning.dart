import 'dart:io';

import 'storage_security.dart';

class ProvisionedProjectLocation {
  const ProvisionedProjectLocation({
    required this.name,
    required this.parentPath,
    required this.rootPath,
  });

  final String name;
  final String parentPath;
  final String rootPath;
}

class ProjectProvisioningService {
  const ProjectProvisioningService({required this.directories});

  final AppDirectories directories;

  Future<ProvisionedProjectLocation> prepare({
    required String suggestedName,
  }) async {
    final name = _safeDisplayName(suggestedName);
    final parent = await _defaultProjectsRoot();
    await parent.create(recursive: true);
    final slug = _slug(name);
    var candidate = Directory('${parent.path}${Platform.pathSeparator}$slug');
    var suffix = 2;
    while (await candidate.exists()) {
      candidate = Directory(
        '${parent.path}${Platform.pathSeparator}$slug-$suffix',
      );
      suffix += 1;
    }
    await candidate.create(recursive: true);
    return ProvisionedProjectLocation(
      name: name,
      parentPath: parent.path,
      rootPath: candidate.path,
    );
  }

  Future<Directory> _defaultProjectsRoot() async {
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']
        : Platform.environment['HOME'];
    if (home != null && home.trim().isNotEmpty) {
      final documents = Directory('$home${Platform.pathSeparator}Documents');
      if (await documents.exists()) {
        return Directory(
          '${documents.path}${Platform.pathSeparator}Kristin Projects',
        );
      }
      return Directory('$home${Platform.pathSeparator}KristinProjects');
    }
    return Directory(
      '${directories.root.path}${Platform.pathSeparator}projects',
    );
  }

  String _safeDisplayName(String input) {
    final normalized = input
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return 'Kristin Project';
    return normalized.length <= 64
        ? normalized
        : normalized.substring(0, 64).trim();
  }

  String _slug(String value) {
    final slug = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'kristin-project' : slug;
  }
}
