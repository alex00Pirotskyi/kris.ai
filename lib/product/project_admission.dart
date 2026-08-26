import 'dart:io';

import 'domain.dart';
import 'repository.dart';

/// Admits a folder into the durable Project Manager registry, or refreshes
/// an already-admitted project's activity, without ever duplicating a
/// registration for the same canonical root.
///
/// A folder becomes a durable Kristin project only when there is meaningful
/// project intent or evidence — Kristin building/modifying/analyzing/
/// testing/verifying it, or the user explicitly adding/creating/importing
/// it. Reading a directory in passing is not, by itself, admission; callers
/// are expected to invoke [admitOrTouch] only from an already-successful
/// event (see `ProductRuntime.analyzeProject`/`testProject`/`buildProject`/
/// `startProject`/`addProject`/`createProject`).
class ProjectAdmissionService {
  const ProjectAdmissionService({required this.projects});

  final EntityRepository<ProjectRecord> projects;

  /// Reuses the exact canonicalization used by `ProductRuntime.addProject`
  /// (`resolveSymbolicLinks()` + Windows case-insensitive comparison) so a
  /// project already registered by hand is recognized here, and vice versa.
  Future<ProjectRecord> admitOrTouch({
    required String rootPath,
    required String name,
    required ProjectAdmissionReason reason,
  }) async {
    final root = Directory(rootPath.trim()).absolute;
    final canonical =
        await root.exists() ? (await root.resolveSymbolicLinks()) : root.path;
    final normalized = Platform.isWindows ? canonical.toLowerCase() : canonical;
    final all = await projects.all();
    final existing = all.where((project) {
      final path = Platform.isWindows
          ? project.rootPath.toLowerCase()
          : project.rootPath;
      return path == normalized;
    }).firstOrNull;

    final now = DateTime.now().toUtc();
    if (existing != null) {
      // admissionReason/admittedAt record why the project was first
      // admitted and stay fixed; every subsequent qualifying event only
      // refreshes lastMeaningfulActivityAt.
      final touched = existing.copyWith(
        updatedAt: now,
        admissionReason: existing.admissionReason ?? reason,
        admittedAt: existing.admittedAt ?? now,
        lastMeaningfulActivityAt: now,
      );
      await projects.put(touched);
      return touched;
    }

    final trimmedName = name.trim();
    final project = ProjectRecord(
      id: newId('project'),
      name: trimmedName.isEmpty
          ? root.uri.pathSegments.where((segment) => segment.isNotEmpty).last
          : trimmedName,
      rootPath: canonical,
      createdAt: now,
      updatedAt: now,
      admissionReason: reason,
      admittedAt: now,
      lastMeaningfulActivityAt: now,
    );
    await projects.put(project);
    return project;
  }

  /// Refreshes an already-resolved [project]'s admission bookkeeping
  /// without re-scanning the registry by path — for callers (analyze/test/
  /// build/run success hooks) that already hold the exact record because
  /// their action required an existing, registered project.
  Future<ProjectRecord> touchExisting(
    ProjectRecord project,
    ProjectAdmissionReason reason,
  ) async {
    final now = DateTime.now().toUtc();
    final touched = project.copyWith(
      updatedAt: now,
      admissionReason: project.admissionReason ?? reason,
      admittedAt: project.admittedAt ?? now,
      lastMeaningfulActivityAt: now,
    );
    await projects.put(touched);
    return touched;
  }
}
