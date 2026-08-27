import 'domain.dart';
import 'git_state_probe.dart';
import 'product_runtime.dart';
import 'storage_security.dart';

/// Freshness of one Analyze/Test/Build result relative to the project's
/// current git state. [blocked] is reserved for a future dependency-chain
/// signal (e.g. "build blocked because analyze failed") and is not produced
/// by Wave A's assembly logic.
enum ProjectQualityState { pass, fail, notRun, blocked, stale }

ProjectQualityState _qualityStateFor(
  ProjectQualityResult? result,
  String? currentHeadSha,
) {
  if (result == null) {
    return ProjectQualityState.notRun;
  }
  final hasComparableShas = currentHeadSha != null &&
      currentHeadSha.isNotEmpty &&
      result.sourceGitSha.isNotEmpty;
  if (hasComparableShas && currentHeadSha != result.sourceGitSha) {
    return ProjectQualityState.stale;
  }
  return result.passed ? ProjectQualityState.pass : ProjectQualityState.fail;
}

/// The single, canonical projection of "everything Project Manager knows
/// about a project right now" — assembled by [ProjectControlService] and
/// intended to be the one source of truth consumed by the desktop UI, the
/// loopback API, and (later) the command palette, rather than each of them
/// independently stitching together project/process/run queries.
class ProjectControlStatus {
  const ProjectControlStatus({
    required this.project,
    required this.git,
    required this.launchProfiles,
    required this.activeRuntime,
    required this.analyzeState,
    required this.testState,
    required this.buildState,
    required this.recentRuns,
    required this.knowledgeCount,
  });

  final ProjectRecord project;
  final GitStateSnapshot? git;
  final List<ProjectLaunchProfile> launchProfiles;
  final ProjectRuntimeSession? activeRuntime;
  final ProjectQualityState analyzeState;
  final ProjectQualityState testState;
  final ProjectQualityState buildState;
  final List<RunRecord> recentRuns;
  final int knowledgeCount;

  bool get running => activeRuntime?.running ?? false;

  /// `listProjectLaunchProfiles` already orders `preferred DESC, updated_at
  /// DESC`, so the first entry is always the preferred profile (or, absent
  /// one, the most recently detected/learned profile).
  ProjectLaunchProfile? get preferredLaunchProfile =>
      launchProfiles.firstOrNull;
}

/// One row of the Project Manager "Running" section: a project with an
/// active durable runtime session, regardless of which project is
/// currently selected in the UI.
class ProjectControlRunningEntry {
  const ProjectControlRunningEntry({
    required this.project,
    required this.session,
  });

  final ProjectRecord project;
  final ProjectRuntimeSession session;
}

/// Assembles [ProjectControlStatus] for a project, and lists every
/// currently-running project, from durable state plus a small
/// TTL-cached git probe — never by re-running `git status` on every card
/// render (see `git_state_probe.dart`'s doc comment for the caching
/// contract this enforces).
class ProjectControlService {
  ProjectControlService({required this.runtime});

  final ProductRuntime runtime;

  static const Duration _gitCacheTtl = Duration(seconds: 45);
  final Map<String, GitStateSnapshot> _gitCache = <String, GitStateSnapshot>{};

  /// Returns the cached git state for [projectId] if it is still within
  /// the TTL, otherwise probes fresh. Pass [forceRefresh] only from an
  /// explicit user "Refresh" action or the first time a project's detail
  /// view opens this session — never from a card-grid redraw.
  Future<GitStateSnapshot> cachedGitState(
    String projectId,
    String rootPath, {
    bool forceRefresh = false,
  }) async {
    final cached = _gitCache[projectId];
    if (cached != null && !forceRefresh) {
      final age = DateTime.now().toUtc().difference(cached.capturedAt);
      if (age < _gitCacheTtl) {
        return cached;
      }
    }
    final probed = await probeGitState(rootPath);
    _gitCache[projectId] = probed;
    return probed;
  }

  Future<ProjectControlStatus> status(
    String projectId, {
    bool refreshGit = false,
  }) async {
    final project = await runtime.repositories.projects.get(projectId);
    if (project == null) {
      throw ProductException('project_missing', 'Select a valid project.');
    }
    final git = await cachedGitState(
      projectId,
      project.rootPath,
      forceRefresh: refreshGit,
    );
    final launchProfiles =
        await runtime.repositories.workflow.listProjectLaunchProfiles(
      projectId,
    );
    final activeSessions =
        await runtime.repositories.workflow.listManagedProjectProcesses(
      projectId: projectId,
      states: const <ProjectRuntimeState>{
        ProjectRuntimeState.starting,
        ProjectRuntimeState.running,
        ProjectRuntimeState.stopping,
      },
    );
    final recentRuns = await runtime.listRuns(projectId: projectId, limit: 5);
    final knowledgeCount = (await runtime.repositories.knowledge.all())
        .where((entry) => entry.projectId == projectId)
        .length;

    return ProjectControlStatus(
      project: project,
      git: git,
      launchProfiles: launchProfiles,
      activeRuntime: activeSessions.firstOrNull,
      analyzeState: _qualityStateFor(project.lastAnalyzeResult, git.headSha),
      testState: _qualityStateFor(project.lastTestResult, git.headSha),
      buildState: _qualityStateFor(project.lastBuildResult, git.headSha),
      recentRuns: recentRuns,
      knowledgeCount: knowledgeCount,
    );
  }

  /// Every project with an active runtime session — the Project Manager
  /// "Running" section's data source. One durable-table scan plus one
  /// project lookup per distinct running project; never a per-project
  /// process probe.
  Future<List<ProjectControlRunningEntry>> runningProjects() async {
    final sessions =
        await runtime.repositories.workflow.listManagedProjectProcesses(
      states: const <ProjectRuntimeState>{
        ProjectRuntimeState.starting,
        ProjectRuntimeState.running,
        ProjectRuntimeState.stopping,
      },
    );
    final entries = <ProjectControlRunningEntry>[];
    for (final session in sessions) {
      final project = await runtime.repositories.projects.get(
        session.projectId,
      );
      if (project != null) {
        entries.add(
          ProjectControlRunningEntry(project: project, session: session),
        );
      }
    }
    return entries;
  }
}
