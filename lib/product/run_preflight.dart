import 'dart:async';
import 'dart:io';

import 'domain.dart';
import 'process_launch.dart';
import 'storage_security.dart';

enum RunPreflightVerdict { ready, readyWithWarnings, blocked }

enum RunCapabilityKind {
  model,
  workspaceRead,
  workspaceWrite,
  executable,
  browser,
  researchNetwork,
  researchSearch,
  packageNetwork,
}

class RunCapabilityRequirement {
  const RunCapabilityRequirement({
    required this.key,
    required this.label,
    required this.kind,
    required this.required,
    this.executable,
    this.probeUri,
  });

  final String key;
  final String label;
  final RunCapabilityKind kind;
  final bool required;
  final String? executable;
  final Uri? probeUri;
}

class RunCapabilityProbeResult {
  const RunCapabilityProbeResult({
    required this.key,
    required this.label,
    required this.ok,
    required this.required,
    required this.message,
    required this.durationMilliseconds,
    this.details = const <String, dynamic>{},
  });

  final String key;
  final String label;
  final bool ok;
  final bool required;
  final String message;
  final int durationMilliseconds;
  final Map<String, dynamic> details;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'key': key,
    'label': label,
    'ok': ok,
    'required': required,
    'message': message,
    'durationMilliseconds': durationMilliseconds,
    if (details.isNotEmpty) 'details': details,
  };
}

class RunPreflightReceipt {
  const RunPreflightReceipt({
    required this.id,
    required this.runId,
    required this.verdict,
    required this.startedAt,
    required this.completedAt,
    required this.probes,
  });

  final String id;
  final String runId;
  final RunPreflightVerdict verdict;
  final DateTime startedAt;
  final DateTime completedAt;
  final List<RunCapabilityProbeResult> probes;

  bool get blocked => verdict == RunPreflightVerdict.blocked;

  List<RunCapabilityProbeResult> get blockingFailures => probes
      .where((probe) => probe.required && !probe.ok)
      .toList(growable: false);

  String get summary {
    if (blockingFailures.isNotEmpty) {
      return blockingFailures.map((probe) => probe.message).join(' ');
    }
    final warnings = probes.where((probe) => !probe.ok).length;
    return warnings == 0
        ? 'All required capabilities are ready.'
        : 'Required capabilities are ready with $warnings warning${warnings == 1 ? '' : 's'}.';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'runId': runId,
    'verdict': verdict.name,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt.toIso8601String(),
    'summary': summary,
    'probes': probes.map((probe) => probe.toJson()).toList(),
  };
}

class RunCapabilityResolver {
  const RunCapabilityResolver();

  List<RunCapabilityRequirement> resolve(PreparedCommand command) {
    final request = command.contract.request.toLowerCase();
    final tools = command.plan.items
        .expand((item) => item.allowedTools)
        .toSet();
    final requirements = <String, RunCapabilityRequirement>{};

    void add(RunCapabilityRequirement requirement) {
      requirements[requirement.key] = requirement;
    }

    add(
      const RunCapabilityRequirement(
        key: 'model',
        label: 'Selected AI model',
        kind: RunCapabilityKind.model,
        required: true,
      ),
    );

    final conversational =
        command.contract.mode == CommandMode.ask &&
        isConversationalRequest(command.contract.request);
    if (!conversational) {
      add(
        const RunCapabilityRequirement(
          key: 'workspace-read',
          label: 'Project workspace',
          kind: RunCapabilityKind.workspaceRead,
          required: true,
        ),
      );
    }
    if (command.contract.mode == CommandMode.build ||
        command.contract.mode == CommandMode.fix) {
      add(
        const RunCapabilityRequirement(
          key: 'workspace-write',
          label: 'Writable project workspace',
          kind: RunCapabilityKind.workspaceWrite,
          required: true,
        ),
      );
    }

    void executable(String value, {bool required = true}) {
      add(
        RunCapabilityRequirement(
          key: 'exec-$value',
          label: '$value executable',
          kind: RunCapabilityKind.executable,
          required: required,
          executable: value,
        ),
      );
    }

    if (RegExp(r'\bflutter\b').hasMatch(request)) {
      executable('flutter');
      executable('dart');
      add(
        RunCapabilityRequirement(
          key: 'package-pub',
          label: 'pub.dev package network',
          kind: RunCapabilityKind.packageNetwork,
          required: false,
          probeUri: Uri.parse('https://pub.dev'),
        ),
      );
    }
    if (RegExp(r'\b(python|pip)\b').hasMatch(request)) {
      executable(Platform.isWindows ? 'python' : 'python3');
      add(
        RunCapabilityRequirement(
          key: 'package-pypi',
          label: 'PyPI package network',
          kind: RunCapabilityKind.packageNetwork,
          required: request.contains('install') || request.contains('package'),
          probeUri: Uri.parse('https://pypi.org'),
        ),
      );
    }
    if (RegExp(
      r'\b(node|npm|react|typescript|javascript)\b',
    ).hasMatch(request)) {
      executable('node');
      executable(
        'npm',
        required: request.contains('npm') || request.contains('package'),
      );
      add(
        RunCapabilityRequirement(
          key: 'package-npm',
          label: 'npm package network',
          kind: RunCapabilityKind.packageNetwork,
          required: request.contains('install') || request.contains('package'),
          probeUri: Uri.parse('https://registry.npmjs.org'),
        ),
      );
    }
    if (tools.contains('git_status') || tools.contains('git_diff')) {
      executable('git', required: false);
    }
    if (tools.any(_isBrowserTool)) {
      add(
        const RunCapabilityRequirement(
          key: 'browser',
          label: 'Browser runtime',
          kind: RunCapabilityKind.browser,
          required: true,
        ),
      );
    }
    if (tools.contains('research_search')) {
      add(
        const RunCapabilityRequirement(
          key: 'research-search',
          label: 'Web search provider',
          kind: RunCapabilityKind.researchSearch,
          required: true,
        ),
      );
    }
    if (tools.contains('research_fetch') ||
        (command.contract.requiredPermissions.contains(
              PermissionScope.networkResearch,
            ) &&
            !tools.contains('research_search'))) {
      add(
        RunCapabilityRequirement(
          key: 'research-network',
          label: 'Web research network',
          kind: RunCapabilityKind.researchNetwork,
          required: true,
          probeUri: Uri.parse('https://example.com'),
        ),
      );
    }
    if (command.contract.requiredPermissions.contains(
      PermissionScope.networkPackages,
    )) {
      add(
        RunCapabilityRequirement(
          key: 'package-network',
          label: 'Package network',
          kind: RunCapabilityKind.packageNetwork,
          required: true,
          probeUri: Uri.parse('https://example.com'),
        ),
      );
    }

    final values = requirements.values.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return List.unmodifiable(values);
  }

  bool _isBrowserTool(String tool) {
    final normalized = tool.trim().toLowerCase();
    return normalized == 'browser' ||
        normalized.startsWith('browser_') ||
        normalized.startsWith('browser.');
  }
}

typedef RunModelProbe =
    Future<RunCapabilityProbeResult> Function(
      ModelIdentity model,
      RunCapabilityRequirement requirement,
    );
typedef RunBrowserProbe =
    Future<RunCapabilityProbeResult> Function(
      RunCapabilityRequirement requirement,
    );
typedef RunResearchSearchProbe =
    Future<RunCapabilityProbeResult> Function(
      RunRecord run,
      RunCapabilityRequirement requirement,
    );
typedef RunSettingsProvider = ProductSettings Function();

class RunPreflightService {
  RunPreflightService({
    required this.resolver,
    required this.modelProbe,
    required this.browserProbe,
    required this.researchSearchProbe,
    required this.settingsProvider,
  });

  final RunCapabilityResolver resolver;
  final RunModelProbe modelProbe;
  final RunBrowserProbe browserProbe;
  final RunResearchSearchProbe researchSearchProbe;
  final RunSettingsProvider settingsProvider;

  Future<RunPreflightReceipt> check({
    required RunRecord run,
    required ProjectRecord project,
  }) async {
    final started = DateTime.now().toUtc();
    final requirements = resolver.resolve(run.command);
    final probes = await Future.wait(
      requirements.map((requirement) => _probe(requirement, run, project)),
    );
    final requiredFailure = probes.any((probe) => probe.required && !probe.ok);
    final warning = probes.any((probe) => !probe.ok);
    final verdict = requiredFailure
        ? RunPreflightVerdict.blocked
        : warning
        ? RunPreflightVerdict.readyWithWarnings
        : RunPreflightVerdict.ready;
    return RunPreflightReceipt(
      id: newId('preflight'),
      runId: run.id,
      verdict: verdict,
      startedAt: started,
      completedAt: DateTime.now().toUtc(),
      probes: List.unmodifiable(probes),
    );
  }

  Future<RunCapabilityProbeResult> _probe(
    RunCapabilityRequirement requirement,
    RunRecord run,
    ProjectRecord project,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      switch (requirement.kind) {
        case RunCapabilityKind.model:
          return await modelProbe(run.command.model, requirement);
        case RunCapabilityKind.browser:
          return await browserProbe(requirement);
        case RunCapabilityKind.workspaceRead:
          final root = Directory(project.rootPath).absolute;
          if (!await root.exists()) {
            return _result(
              requirement,
              false,
              'The project workspace does not exist.',
              stopwatch,
            );
          }
          await root.list(followLinks: false).take(1).toList();
          return _result(
            requirement,
            true,
            'Project workspace is readable.',
            stopwatch,
          );
        case RunCapabilityKind.workspaceWrite:
          final root = Directory(project.rootPath).absolute;
          if (!await root.exists()) {
            return _result(
              requirement,
              false,
              'The project workspace does not exist.',
              stopwatch,
            );
          }
          final probe = File(
            '${root.path}${Platform.pathSeparator}.kristin-preflight-${newId('probe')}.tmp',
          );
          await probe.writeAsString('kristin-preflight\n', flush: true);
          await probe.delete();
          return _result(
            requirement,
            true,
            'Project workspace is writable.',
            stopwatch,
          );
        case RunCapabilityKind.executable:
          final executable = requirement.executable ?? '';
          final resolved = await resolveExecutableOnPath(executable);
          if (resolved == null) {
            return _result(
              requirement,
              false,
              '$executable is required by this plan but was not found on PATH.',
              stopwatch,
            );
          }
          final result = await Process.run(
            resolved,
            _versionArguments(executable),
            workingDirectory: project.rootPath,
            runInShell: requiresWindowsCommandShell(resolved),
          ).timeout(const Duration(seconds: 12));
          final ok = result.exitCode == 0;
          return _result(
            requirement,
            ok,
            ok
                ? '$executable is available.'
                : '$executable was found but its readiness probe exited ${result.exitCode}.',
            stopwatch,
            details: <String, dynamic>{'resolved': resolved},
          );
        case RunCapabilityKind.researchSearch:
          if (settingsProvider().localOnly) {
            return _result(
              requirement,
              false,
              'Web search is required by this plan but Kristin is in local-only mode.',
              stopwatch,
            );
          }
          return await researchSearchProbe(run, requirement);
        case RunCapabilityKind.researchNetwork:
          if (settingsProvider().localOnly) {
            return _result(
              requirement,
              false,
              'Web research is required by this plan but Kristin is in local-only mode.',
              stopwatch,
            );
          }
          return _probeNetwork(requirement, stopwatch);
        case RunCapabilityKind.packageNetwork:
          final settings = settingsProvider();
          if (settings.localOnly || !settings.allowPackageNetwork) {
            return _result(
              requirement,
              false,
              'Package network is unavailable because package downloads are disabled.',
              stopwatch,
            );
          }
          return _probeNetwork(requirement, stopwatch);
      }
    } on TimeoutException {
      return _result(
        requirement,
        false,
        '${requirement.label} readiness probe timed out.',
        stopwatch,
      );
    } on ProcessException catch (error) {
      return _result(
        requirement,
        false,
        '${requirement.executable ?? requirement.label} could not be started: ${error.message}',
        stopwatch,
      );
    } on Object catch (error) {
      return _result(
        requirement,
        false,
        '${requirement.label} is not ready: $error',
        stopwatch,
      );
    }
  }

  Future<RunCapabilityProbeResult> _probeNetwork(
    RunCapabilityRequirement requirement,
    Stopwatch stopwatch,
  ) async {
    final uri = requirement.probeUri;
    if (uri == null) {
      return _result(
        requirement,
        true,
        'No external endpoint probe is required.',
        stopwatch,
      );
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .headUrl(uri)
          .timeout(const Duration(seconds: 6));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      final ok = response.statusCode >= 200 && response.statusCode < 500;
      return _result(
        requirement,
        ok,
        ok
            ? '${uri.host} is reachable.'
            : '${uri.host} returned HTTP ${response.statusCode}.',
        stopwatch,
        details: <String, dynamic>{
          'host': uri.host,
          'status': response.statusCode,
        },
      );
    } finally {
      client.close(force: true);
    }
  }

  RunCapabilityProbeResult _result(
    RunCapabilityRequirement requirement,
    bool ok,
    String message,
    Stopwatch stopwatch, {
    Map<String, dynamic> details = const <String, dynamic>{},
  }) {
    stopwatch.stop();
    return RunCapabilityProbeResult(
      key: requirement.key,
      label: requirement.label,
      ok: ok,
      required: requirement.required,
      message: message,
      durationMilliseconds: stopwatch.elapsedMilliseconds,
      details: details,
    );
  }

  List<String> _versionArguments(String executable) {
    final lower = executable.toLowerCase();
    if (lower == 'flutter' ||
        lower == 'dart' ||
        lower == 'git' ||
        lower == 'node' ||
        lower == 'npm' ||
        lower == 'python' ||
        lower == 'python3') {
      return const <String>['--version'];
    }
    return const <String>['--version'];
  }
}
