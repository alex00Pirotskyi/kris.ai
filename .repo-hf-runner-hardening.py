from __future__ import annotations

from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"anchor mismatch {path}: expected 1, got {count}: {old[:120]!r}")
    file.write_text(text.replace(old, new, 1), encoding="utf-8")


# HF-A: make research/package readiness reflect the actual configured capabilities.
replace_once(
    "lib/product/planning_runtime.dart",
    """    if (RegExp(\n      r'\\b(research|latest|current|documentation|docs|download knowledge|look up|web|online|url|https)\\b',\n    ).hasMatch(lower)) {\n      permissions.add(PermissionScope.networkResearch);\n    }\n""",
    """    if (RegExp(\n      r'\\b(research|latest|current|documentation|docs|download knowledge|look up|web|online|url|https)\\b',\n    ).hasMatch(lower)) {\n      permissions.addAll(<PermissionScope>{\n        PermissionScope.networkResearch,\n        PermissionScope.secretUse,\n      });\n    }\n""",
)

replace_once(
    "lib/product/run_preflight.dart",
    """import 'domain.dart';\n""",
    """import 'domain.dart';\nimport 'storage_security.dart';\n""",
)
replace_once(
    "lib/product/run_preflight.dart",
    """  browser,\n  researchNetwork,\n  packageNetwork,\n""",
    """  browser,\n  researchNetwork,\n  researchSearch,\n  packageNetwork,\n""",
)
replace_once(
    "lib/product/run_preflight.dart",
    """    if (command.contract.requiredPermissions\n            .contains(PermissionScope.networkResearch) ||\n        tools.contains('research_search') ||\n        tools.contains('research_fetch')) {\n      add(RunCapabilityRequirement(\n        key: 'research-network',\n        label: 'Web research network',\n        kind: RunCapabilityKind.researchNetwork,\n        required: true,\n        probeUri: Uri.parse('https://example.com'),\n      ));\n    }\n""",
    """    if (tools.contains('research_search')) {\n      add(const RunCapabilityRequirement(\n        key: 'research-search',\n        label: 'Web search provider',\n        kind: RunCapabilityKind.researchSearch,\n        required: true,\n      ));\n    }\n    if (tools.contains('research_fetch') ||\n        (command.contract.requiredPermissions\n                .contains(PermissionScope.networkResearch) &&\n            !tools.contains('research_search'))) {\n      add(RunCapabilityRequirement(\n        key: 'research-network',\n        label: 'Web research network',\n        kind: RunCapabilityKind.researchNetwork,\n        required: true,\n        probeUri: Uri.parse('https://example.com'),\n      ));\n    }\n""",
)
replace_once(
    "lib/product/run_preflight.dart",
    """typedef RunBrowserProbe = Future<RunCapabilityProbeResult> Function(\n  RunCapabilityRequirement requirement,\n);\n\nclass RunPreflightService {\n  RunPreflightService({\n    required this.resolver,\n    required this.modelProbe,\n    required this.browserProbe,\n  });\n\n  final RunCapabilityResolver resolver;\n  final RunModelProbe modelProbe;\n  final RunBrowserProbe browserProbe;\n""",
    """typedef RunBrowserProbe = Future<RunCapabilityProbeResult> Function(\n  RunCapabilityRequirement requirement,\n);\ntypedef RunResearchSearchProbe = Future<RunCapabilityProbeResult> Function(\n  RunRecord run,\n  RunCapabilityRequirement requirement,\n);\ntypedef RunSettingsProvider = ProductSettings Function();\n\nclass RunPreflightService {\n  RunPreflightService({\n    required this.resolver,\n    required this.modelProbe,\n    required this.browserProbe,\n    required this.researchSearchProbe,\n    required this.settingsProvider,\n  });\n\n  final RunCapabilityResolver resolver;\n  final RunModelProbe modelProbe;\n  final RunBrowserProbe browserProbe;\n  final RunResearchSearchProbe researchSearchProbe;\n  final RunSettingsProvider settingsProvider;\n""",
)
replace_once(
    "lib/product/run_preflight.dart",
    """        (requirement) => _probe(\n          requirement,\n          run.command.model,\n          project,\n        ),\n""",
    """        (requirement) => _probe(\n          requirement,\n          run,\n          project,\n        ),\n""",
)
replace_once(
    "lib/product/run_preflight.dart",
    """  Future<RunCapabilityProbeResult> _probe(\n    RunCapabilityRequirement requirement,\n    ModelIdentity model,\n    ProjectRecord project,\n  ) async {\n""",
    """  Future<RunCapabilityProbeResult> _probe(\n    RunCapabilityRequirement requirement,\n    RunRecord run,\n    ProjectRecord project,\n  ) async {\n""",
)
replace_once(
    "lib/product/run_preflight.dart",
    """        case RunCapabilityKind.model:\n          return await modelProbe(model, requirement);\n""",
    """        case RunCapabilityKind.model:\n          return await modelProbe(run.command.model, requirement);\n""",
)
replace_once(
    "lib/product/run_preflight.dart",
    """        case RunCapabilityKind.researchNetwork:\n        case RunCapabilityKind.packageNetwork:\n          final uri = requirement.probeUri;\n          if (uri == null) {\n            return _result(requirement, true,\n                'No external endpoint probe is required.', stopwatch);\n          }\n          final client = HttpClient()\n            ..connectionTimeout = const Duration(seconds: 5);\n          try {\n            final request =\n                await client.headUrl(uri).timeout(const Duration(seconds: 6));\n            request.followRedirects = false;\n            final response =\n                await request.close().timeout(const Duration(seconds: 8));\n            final ok = response.statusCode >= 200 && response.statusCode < 500;\n            return _result(\n              requirement,\n              ok,\n              ok\n                  ? '${uri.host} is reachable.'\n                  : '${uri.host} returned HTTP ${response.statusCode}.',\n              stopwatch,\n              details: <String, dynamic>{\n                'host': uri.host,\n                'status': response.statusCode\n              },\n            );\n          } finally {\n            client.close(force: true);\n          }\n""",
    """        case RunCapabilityKind.researchSearch:\n          if (settingsProvider().localOnly) {\n            return _result(\n              requirement,\n              false,\n              'Web search is required by this plan but Kristin is in local-only mode.',\n              stopwatch,\n            );\n          }\n          return await researchSearchProbe(run, requirement);\n        case RunCapabilityKind.researchNetwork:\n          if (settingsProvider().localOnly) {\n            return _result(\n              requirement,\n              false,\n              'Web research is required by this plan but Kristin is in local-only mode.',\n              stopwatch,\n            );\n          }\n          return _probeNetwork(requirement, stopwatch);\n        case RunCapabilityKind.packageNetwork:\n          final settings = settingsProvider();\n          if (settings.localOnly || !settings.allowPackageNetwork) {\n            return _result(\n              requirement,\n              false,\n              'Package network is unavailable because package downloads are disabled.',\n              stopwatch,\n            );\n          }\n          return _probeNetwork(requirement, stopwatch);\n""",
)
replace_once(
    "lib/product/run_preflight.dart",
    """  RunCapabilityProbeResult _result(\n""",
    """  Future<RunCapabilityProbeResult> _probeNetwork(\n    RunCapabilityRequirement requirement,\n    Stopwatch stopwatch,\n  ) async {\n    final uri = requirement.probeUri;\n    if (uri == null) {\n      return _result(\n        requirement,\n        true,\n        'No external endpoint probe is required.',\n        stopwatch,\n      );\n    }\n    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);\n    try {\n      final request =\n          await client.headUrl(uri).timeout(const Duration(seconds: 6));\n      request.followRedirects = false;\n      final response = await request.close().timeout(const Duration(seconds: 8));\n      final ok = response.statusCode >= 200 && response.statusCode < 500;\n      return _result(\n        requirement,\n        ok,\n        ok\n            ? '${uri.host} is reachable.'\n            : '${uri.host} returned HTTP ${response.statusCode}.',\n        stopwatch,\n        details: <String, dynamic>{\n          'host': uri.host,\n          'status': response.statusCode,\n        },\n      );\n    } finally {\n      client.close(force: true);\n    }\n  }\n\n  RunCapabilityProbeResult _result(\n""",
)

# The self-source guard must run before any writable preflight probe.
replace_once(
    "lib/product/planning_runtime.dart",
    """    final readiness = await preflight.check(run: initial, project: project);\n""",
    """    final boundary = await WorkspaceBoundary.open(project.rootPath);\n    final mutatingRun = initial.command.contract.requiredPermissions.any(\n      const <PermissionScope>{\n        PermissionScope.projectWrite,\n        PermissionScope.projectDelete,\n      }.contains,\n    );\n    if (mutatingRun && await boundary.isKristinSourceCheckout()) {\n      final details = <String, dynamic>{\n        'runId': initial.id,\n        'projectId': project.id,\n        'projectPathHash': Sha256.text(boundary.root.path),\n        'reason': 'selected_project_is_kristin_source',\n      };\n      await _bestEffortAudit(\n        'run.self_project_target_rejected',\n        initial.id,\n        details,\n      );\n      await _bestEffortEvent(\n        'run.self_project_target_rejected',\n        initial.id,\n        details,\n      );\n      return _failBeforeTransaction(\n        initial,\n        \"self_project_target_rejected: The selected project is Kristin's own source checkout. Create or select a separate project folder for the application, then prepare a fresh run.\",\n      );\n    }\n    final readiness = await preflight.check(run: initial, project: project);\n""",
)
replace_once(
    "lib/product/planning_runtime.dart",
    """    final boundary = await WorkspaceBoundary.open(project.rootPath);\n    final mutatingRun = run.command.contract.requiredPermissions.any(\n      const <PermissionScope>{\n        PermissionScope.projectWrite,\n        PermissionScope.projectDelete,\n      }.contains,\n    );\n    if (mutatingRun && await boundary.isKristinSourceCheckout()) {\n      final details = <String, dynamic>{\n        'runId': run.id,\n        'projectId': project.id,\n        'projectPathHash': Sha256.text(boundary.root.path),\n        'reason': 'selected_project_is_kristin_source',\n      };\n      await _bestEffortAudit(\n        'run.self_project_target_rejected',\n        run.id,\n        details,\n      );\n      await _bestEffortEvent(\n        'run.self_project_target_rejected',\n        run.id,\n        details,\n      );\n      return _failBeforeTransaction(\n        run,\n        \"self_project_target_rejected: The selected project is Kristin's own source checkout. Create or select a separate project folder for the application, then prepare a fresh run.\",\n      );\n    }\n""",
    "",
)

# HF-B: stream bounded redacted terminal output instead of waiting for process completion.
replace_once(
    "lib/product/workspace_tools.dart",
    """import 'mcp.dart';\n""",
    """import 'mcp.dart';\nimport 'product_error_normalizer.dart';\n""",
)
replace_once(
    "lib/product/workspace_tools.dart",
    """    required String runId,\n    required String workItemId,\n  }) async {\n""",
    """    required String runId,\n    required String workItemId,\n    void Function(String stream, String delta)? onOutput,\n  }) async {\n""",
)
replace_once(
    "lib/product/workspace_tools.dart",
    """      startedAt: DateTime.now().toUtc(),\n      log: log,\n    );\n""",
    """      startedAt: DateTime.now().toUtc(),\n      log: log,\n      onOutput: onOutput,\n    );\n""",
)
replace_once(
    "lib/product/workspace_tools.dart",
    """    record.tail.write(text);\n""",
    """    try {\n      record.onOutput?.call(stream, text);\n    } catch (_) {\n      // Live presentation must never change process execution semantics.\n    }\n    record.tail.write(text);\n""",
)
replace_once(
    "lib/product/workspace_tools.dart",
    """    required this.startedAt,\n    required this.log,\n  });\n""",
    """    required this.startedAt,\n    required this.log,\n    this.onOutput,\n  });\n""",
)
replace_once(
    "lib/product/workspace_tools.dart",
    """  final File log;\n  final StringBuffer tail = StringBuffer();\n""",
    """  final File log;\n  final void Function(String stream, String delta)? onOutput;\n  final StringBuffer tail = StringBuffer();\n""",
)
replace_once(
    "lib/product/workspace_tools.dart",
    """    required this.sourceIndex,\n    required this.mcp,\n  });\n""",
    """    required this.sourceIndex,\n    required this.mcp,\n    this.onToolOutput,\n  });\n""",
)
replace_once(
    "lib/product/workspace_tools.dart",
    """  final SourceIndexService sourceIndex;\n  final McpTrustService mcp;\n}\n""",
    """  final SourceIndexService sourceIndex;\n  final McpTrustService mcp;\n  final void Function(String tool, String stream, String delta)? onToolOutput;\n}\n""",
)
replace_once(
    "lib/product/workspace_tools.dart",
    """    final process = await Process.start(\n      executable,\n      arguments,\n      workingDirectory: workingDirectory,\n      environment: environment,\n      runInShell: false,\n      mode: ProcessStartMode.normal,\n    );\n""",
    """    Process process;\n    try {\n      process = await Process.start(\n        executable,\n        arguments,\n        workingDirectory: workingDirectory,\n        environment: environment,\n        runInShell: false,\n        mode: ProcessStartMode.normal,\n      );\n    } on ProcessException catch (error) {\n      throw ProductErrorNormalizer.normalize(error, executable: executable);\n    }\n""",
)
replace_once(
    "lib/product/workspace_tools.dart",
    """    int maxOutputBytes = 4 * 1024 * 1024,\n  }) async {\n    cancellation.throwIfCancelled();\n    final started = DateTime.now().toUtc();\n    final process = await Process.start(\n      executable,\n      arguments,\n      workingDirectory: workingDirectory,\n      environment: environment,\n      runInShell: false,\n      mode: ProcessStartMode.normal,\n    );\n""",
    """    int maxOutputBytes = 4 * 1024 * 1024,\n    void Function(String stream, String delta)? onOutput,\n  }) async {\n    cancellation.throwIfCancelled();\n    final started = DateTime.now().toUtc();\n    Process process;\n    try {\n      process = await Process.start(\n        executable,\n        arguments,\n        workingDirectory: workingDirectory,\n        environment: environment,\n        runInShell: false,\n        mode: ProcessStartMode.normal,\n      );\n    } on ProcessException catch (error) {\n      throw ProductErrorNormalizer.normalize(error, executable: executable);\n    }\n""",
)
replace_once(
    "lib/product/workspace_tools.dart",
    """    Future<void> collect(Stream<List<int>> stream, BytesBuilder builder) async {\n      await for (final chunk in stream) {\n        if (builder.length + chunk.length <= maxOutputBytes) {\n""",
    """    Future<void> collect(\n      Stream<List<int>> stream,\n      BytesBuilder builder,\n      String streamName,\n    ) async {\n      await for (final chunk in stream) {\n        if (onOutput != null && chunk.isNotEmpty) {\n          var live = redactor.redact(utf8.decode(chunk, allowMalformed: true));\n          if (live.length > 65536) {\n            live = live.substring(0, 65536);\n          }\n          if (live.isNotEmpty) {\n            try {\n              onOutput(streamName, live);\n            } catch (_) {\n              // Live presentation must never change command execution semantics.\n            }\n          }\n        }\n        if (builder.length + chunk.length <= maxOutputBytes) {\n""",
)
replace_once(
    "lib/product/workspace_tools.dart",
    """    final output = collect(process.stdout, stdoutBytes);\n    final errors = collect(process.stderr, stderrBytes);\n""",
    """    final output = collect(process.stdout, stdoutBytes, 'stdout');\n    final errors = collect(process.stderr, stderrBytes, 'stderr');\n""",
)
replace_once(
    "lib/product/workspace_tools.dart",
    """      cancellation: context.cancellation,\n      redactor: context.redactor,\n    );\n    return ToolResult(\n      ok: result['exitCode'] == 0,\n""",
    """      cancellation: context.cancellation,\n      redactor: context.redactor,\n      onOutput: (stream, delta) =>\n          context.onToolOutput?.call('run_command', stream, delta),\n    );\n    return ToolResult(\n      ok: result['exitCode'] == 0,\n""",
)
replace_once(
    "lib/product/workspace_tools.dart",
    """      runId: context.runId,\n      workItemId: context.workItem.id,\n    );\n    return ToolResult(\n      ok: true,\n      summary:\n          'Started managed process ${result['id']} with PID ${result['pid']}.',\n""",
    """      runId: context.runId,\n      workItemId: context.workItem.id,\n      onOutput: (stream, delta) =>\n          context.onToolOutput?.call('start_process', stream, delta),\n    );\n    return ToolResult(\n      ok: true,\n      summary:\n          'Started managed process ${result['id']} with PID ${result['pid']}.',\n""",
)
replace_once(
    "lib/product/workspace_tools.dart",
    """      cancellation: context.cancellation,\n      redactor: context.redactor,\n    );\n    final notRepository = _isNotGitRepository(result);\n""",
    """      cancellation: context.cancellation,\n      redactor: context.redactor,\n      onOutput: (stream, delta) =>\n          context.onToolOutput?.call('git_status', stream, delta),\n    );\n    final notRepository = _isNotGitRepository(result);\n""",
)
replace_once(
    "lib/product/workspace_tools.dart",
    """      cancellation: context.cancellation,\n      redactor: context.redactor,\n      maxOutputBytes: 2 * 1024 * 1024,\n    );\n    final notRepository = _isNotGitRepository(result);\n""",
    """      cancellation: context.cancellation,\n      redactor: context.redactor,\n      maxOutputBytes: 2 * 1024 * 1024,\n      onOutput: (stream, delta) =>\n          context.onToolOutput?.call('git_diff', stream, delta),\n    );\n    final notRepository = _isNotGitRepository(result);\n""",
)
replace_once(
    "lib/product/workspace_tools.dart",
    """          redactor: context.redactor,\n          maxOutputBytes: 4 * 1024 * 1024,\n        );\n""",
    """          redactor: context.redactor,\n          maxOutputBytes: 4 * 1024 * 1024,\n          onOutput: (stream, delta) => context.onToolOutput?.call(\n            'verify_project',\n            stream,\n            '[${command.label}] $delta',\n          ),\n        );\n""",
)

# RunCoordinator bridges process chunks into the ephemeral live bus only.
replace_once(
    "lib/product/planning_runtime.dart",
    """        sourceIndex: sourceIndex,\n        mcp: mcp,\n      );\n      final liveTool = action.tool!;\n""",
    """        sourceIndex: sourceIndex,\n        mcp: mcp,\n        onToolOutput: (tool, stream, delta) {\n          liveSignals.publish(\n            LiveRunSignal.tool(\n              runId: current.id,\n              workItemId: progress.item.id,\n              tool: tool,\n              kind: LiveRunSignalKind.toolOutput,\n              data: <String, dynamic>{\n                'stream': stream,\n                'delta': delta,\n              },\n            ),\n          );\n        },\n      );\n      final liveTool = action.tool!;\n""",
)
replace_once(
    "lib/product/planning_runtime.dart",
    """      sourceIndex: sourceIndex,\n      mcp: mcp,\n    );\n    final result = await tools.execute(\n      'verify_project',\n""",
    """      sourceIndex: sourceIndex,\n      mcp: mcp,\n      onToolOutput: (tool, stream, delta) {\n        liveSignals.publish(\n          LiveRunSignal.tool(\n            runId: run.id,\n            workItemId: item.id,\n            tool: tool,\n            kind: LiveRunSignalKind.toolOutput,\n            data: <String, dynamic>{\n              'stream': stream,\n              'delta': delta,\n            },\n          ),\n        );\n      },\n    );\n    final result = await tools.execute(\n      'verify_project',\n""",
)

# HF-C/HF-F: typed clarification answers, batched live rendering, live terminal chunks, responsive graph nodes.
replace_once(
    "lib/product/chat_studio.dart",
    """  StreamSubscription<LiveRunSignal>? liveRunSubscription;\n  Timer? refreshTimer;\n""",
    """  StreamSubscription<LiveRunSignal>? liveRunSubscription;\n  Timer? refreshTimer;\n  Timer? liveSignalFlushTimer;\n  final List<LiveRunSignal> pendingLiveSignals = <LiveRunSignal>[];\n""",
)
replace_once(
    "lib/product/chat_studio.dart",
    """    refreshTimer?.cancel();\n    final promptCancellation = promptGenerationCancellation;\n""",
    """    refreshTimer?.cancel();\n    liveSignalFlushTimer?.cancel();\n    pendingLiveSignals.clear();\n    final promptCancellation = promptGenerationCancellation;\n""",
)
old_live = """  void _onLiveRunSignal(LiveRunSignal signal) {\n    if (!mounted) return;\n    final activeRunId = selectedRunId ?? currentRun?.id;\n    if (signal.runId != activeRunId) return;\n    setState(() {\n      selectedRunLiveSignals.add(signal);\n      if (selectedRunLiveSignals.length > 2000) {\n        selectedRunLiveSignals.removeRange(\n          0,\n          selectedRunLiveSignals.length - 2000,\n        );\n      }\n      switch (signal.kind) {\n        case LiveRunSignalKind.modelTextDelta:\n          final delta = signal.data['delta']?.toString() ?? '';\n          final combined = '$liveAssistantText$delta';\n          liveAssistantText = combined.length <= 12000\n              ? combined\n              : combined.substring(combined.length - 12000);\n          liveAssistantStage = 'streaming';\n        case LiveRunSignalKind.modelProgress:\n          liveAssistantStage = signal.data['stage']?.toString() ?? 'model';\n          liveAssistantMessage = signal.data['message']?.toString() ?? '';\n        case LiveRunSignalKind.toolStarted:\n          liveToolLabel = signal.data['tool']?.toString() ?? 'tool';\n          liveToolOutput = '';\n        case LiveRunSignalKind.toolCompleted:\n          liveToolLabel = signal.data['tool']?.toString() ?? liveToolLabel;\n          liveToolOutput = signal.data['output']?.toString() ?? '';\n        case LiveRunSignalKind.toolFailed:\n          liveToolLabel = signal.data['tool']?.toString() ?? liveToolLabel;\n          liveToolOutput = signal.data['detail']?.toString() ?? '';\n        case LiveRunSignalKind.preflight:\n        case LiveRunSignalKind.phase:\n          liveAssistantMessage = signal.data['message']?.toString() ?? '';\n        case LiveRunSignalKind.steeringQueued:\n          status = 'Direction queued for the next safe step';\n        case LiveRunSignalKind.steeringApplied:\n          status = 'Direction applied';\n        case LiveRunSignalKind.toolOutput:\n        case LiveRunSignalKind.heartbeat:\n          break;\n      }\n    });\n  }\n\n"""
new_live = """  void _onLiveRunSignal(LiveRunSignal signal) {\n    if (!mounted) return;\n    final activeRunId = selectedRunId ?? currentRun?.id;\n    if (signal.runId != activeRunId) return;\n    pendingLiveSignals.add(signal);\n    liveSignalFlushTimer ??= Timer(\n      const Duration(milliseconds: 65),\n      _flushLiveRunSignals,\n    );\n  }\n\n  void _flushLiveRunSignals() {\n    liveSignalFlushTimer = null;\n    if (!mounted) {\n      pendingLiveSignals.clear();\n      return;\n    }\n    final activeRunId = selectedRunId ?? currentRun?.id;\n    final batch = pendingLiveSignals\n        .where((signal) => signal.runId == activeRunId)\n        .toList(growable: false);\n    pendingLiveSignals.clear();\n    if (batch.isEmpty) return;\n    setState(() {\n      for (final signal in batch) {\n        selectedRunLiveSignals.add(signal);\n        switch (signal.kind) {\n          case LiveRunSignalKind.modelTextDelta:\n            final delta = signal.data['delta']?.toString() ?? '';\n            final combined = '$liveAssistantText$delta';\n            liveAssistantText = combined.length <= 12000\n                ? combined\n                : combined.substring(combined.length - 12000);\n            liveAssistantStage = 'streaming';\n          case LiveRunSignalKind.modelProgress:\n            liveAssistantStage = signal.data['stage']?.toString() ?? 'model';\n            liveAssistantMessage = signal.data['message']?.toString() ?? '';\n          case LiveRunSignalKind.toolStarted:\n            liveToolLabel = signal.data['tool']?.toString() ?? 'tool';\n            liveToolOutput = '';\n          case LiveRunSignalKind.toolOutput:\n            liveToolLabel = signal.data['tool']?.toString() ?? liveToolLabel;\n            final delta = signal.data['delta']?.toString() ?? '';\n            final combined = '$liveToolOutput$delta';\n            liveToolOutput = combined.length <= 16000\n                ? combined\n                : combined.substring(combined.length - 16000);\n          case LiveRunSignalKind.toolCompleted:\n            liveToolLabel = signal.data['tool']?.toString() ?? liveToolLabel;\n            final output = signal.data['output']?.toString() ?? '';\n            if (output.isNotEmpty) liveToolOutput = output;\n          case LiveRunSignalKind.toolFailed:\n            liveToolLabel = signal.data['tool']?.toString() ?? liveToolLabel;\n            liveToolOutput = signal.data['detail']?.toString() ?? '';\n          case LiveRunSignalKind.preflight:\n          case LiveRunSignalKind.phase:\n            liveAssistantMessage = signal.data['message']?.toString() ?? '';\n          case LiveRunSignalKind.steeringQueued:\n            status = 'Direction queued for the next safe step';\n          case LiveRunSignalKind.steeringApplied:\n            status = 'Direction applied';\n          case LiveRunSignalKind.heartbeat:\n            break;\n        }\n      }\n      if (selectedRunLiveSignals.length > 2000) {\n        selectedRunLiveSignals.removeRange(\n          0,\n          selectedRunLiveSignals.length - 2000,\n        );\n      }\n    });\n  }\n\n"""
replace_once("lib/product/chat_studio.dart", old_live, new_live)
replace_once(
    "lib/product/chat_studio.dart",
    """    if (request.startsWith('/')) {\n      final handled = await _handleSlashCommand(request);\n      if (handled) {\n        return;\n      }\n    }\n    final active = currentRun;\n""",
    """    if (request.startsWith('/')) {\n      final handled = await _handleSlashCommand(request);\n      if (handled) {\n        return;\n      }\n    }\n    final clarification = promptClarificationSession;\n    if (embeddedClarificationActive && clarification != null) {\n      final missing = clarification.missingAnswerIds(promptClarificationAnswers);\n      final question = clarification.questions\n          .where((item) => missing.contains(item.id))\n          .firstOrNull;\n      if (question != null) {\n        _answerEmbeddedClarification(question, request);\n        composerController.clear();\n        final remaining =\n            clarification.missingAnswerIds(promptClarificationAnswers);\n        if (remaining.isEmpty) {\n          await _continueEmbeddedClarification();\n        } else if (mounted) {\n          setState(() {\n            status = 'Got it — ${remaining.length} focused choice${remaining.length == 1 ? '' : 's'} left';\n          });\n        }\n        return;\n      }\n    }\n    final active = currentRun;\n""",
)
replace_once(
    "lib/product/chat_studio.dart",
    """    const nodeWidth = 204.0;\n    const nodeHeight = 148.0;\n    const horizontalGap = 86.0;\n    const left = 70.0;\n    const top = 68.0;\n""",
    """    final textScale = MediaQuery.textScalerOf(context).scale(1.0);\n    final accessibilityGrowth = (textScale - 1).clamp(0.0, 1.0);\n    final nodeWidth = 204.0 + accessibilityGrowth * 56.0;\n    final nodeHeight = 148.0 + accessibilityGrowth * 82.0;\n    const horizontalGap = 86.0;\n    const left = 70.0;\n    const top = 68.0;\n""",
)
replace_once(
    "lib/product/chat_studio.dart",
    """        top + row * 184,\n""",
    """        top + row * (nodeHeight + 36),\n""",
)
replace_once(
    "lib/product/chat_studio.dart",
    """    const canvasHeight = 470.0;\n""",
    """    final canvasHeight = top * 2 + nodeHeight * 2 + 48;\n""",
)
replace_once(
    "lib/product/chat_studio.dart",
    """    if (signal.kind == LiveRunSignalKind.toolCompleted) {\n      return 'completed ${signal.data['tool'] ?? 'tool'}';\n    }\n""",
    """    if (signal.kind == LiveRunSignalKind.toolOutput) {\n      return '${signal.data['tool'] ?? 'tool'} · ${signal.data['stream'] ?? 'output'}';\n    }\n    if (signal.kind == LiveRunSignalKind.toolCompleted) {\n      return 'completed ${signal.data['tool'] ?? 'tool'}';\n    }\n""",
)

# ProductRuntime binds the preflight to a real Brave Search credential + request.
replace_once(
    "lib/product/product_runtime.dart",
    """    final runPreflight = RunPreflightService(\n      resolver: const RunCapabilityResolver(),\n""",
    """    final runPreflight = RunPreflightService(\n      resolver: const RunCapabilityResolver(),\n      settingsProvider: () => runtime._settings,\n""",
)
replace_once(
    "lib/product/product_runtime.dart",
    """      browserProbe: (requirement) async {\n        final stopwatch = Stopwatch()..start();\n        try {\n          await runtime.p3BrowserRuntime.probe(\n            startupTimeout: const Duration(seconds: 20),\n          );\n          stopwatch.stop();\n          return RunCapabilityProbeResult(\n            key: requirement.key,\n            label: requirement.label,\n            ok: true,\n            required: requirement.required,\n            message: 'Browser runtime starts and shuts down cleanly.',\n            durationMilliseconds: stopwatch.elapsedMilliseconds,\n          );\n        } catch (error) {\n          stopwatch.stop();\n          return RunCapabilityProbeResult(\n            key: requirement.key,\n            label: requirement.label,\n            ok: false,\n            required: requirement.required,\n            message: 'Browser runtime is not ready: $error',\n            durationMilliseconds: stopwatch.elapsedMilliseconds,\n          );\n        }\n      },\n    );\n""",
    """      browserProbe: (requirement) async {\n        final stopwatch = Stopwatch()..start();\n        try {\n          await runtime.p3BrowserRuntime.probe(\n            startupTimeout: const Duration(seconds: 20),\n          );\n          stopwatch.stop();\n          return RunCapabilityProbeResult(\n            key: requirement.key,\n            label: requirement.label,\n            ok: true,\n            required: requirement.required,\n            message: 'Browser runtime starts and shuts down cleanly.',\n            durationMilliseconds: stopwatch.elapsedMilliseconds,\n          );\n        } catch (error) {\n          stopwatch.stop();\n          return RunCapabilityProbeResult(\n            key: requirement.key,\n            label: requirement.label,\n            ok: false,\n            required: requirement.required,\n            message: 'Browser runtime is not ready: $error',\n            durationMilliseconds: stopwatch.elapsedMilliseconds,\n          );\n        }\n      },\n      researchSearchProbe: (run, requirement) async {\n        final stopwatch = Stopwatch()..start();\n        try {\n          final references = await repositories.secretReferences.all();\n          int score(SecretReference reference) {\n            final text =\n                '${reference.environmentKey} ${reference.label} ${reference.description}'\n                    .toLowerCase();\n            if (reference.environmentKey.toUpperCase() ==\n                'BRAVE_SEARCH_API_KEY') {\n              return 0;\n            }\n            if (text.contains('brave') && text.contains('search')) return 1;\n            if (text.contains('brave')) return 2;\n            return 100;\n          }\n\n          final candidates = references.where((item) => score(item) < 100).toList()\n            ..sort((left, right) => score(left).compareTo(score(right)));\n          if (candidates.isEmpty) {\n            stopwatch.stop();\n            return RunCapabilityProbeResult(\n              key: requirement.key,\n              label: requirement.label,\n              ok: false,\n              required: requirement.required,\n              message:\n                  'Web search is required, but no Brave Search secret reference is configured.',\n              durationMilliseconds: stopwatch.elapsedMilliseconds,\n            );\n          }\n          final reference = candidates.first;\n          final key = await secrets.resolve(\n            reference.id,\n            commandId: run.command.id,\n          );\n          final results = await research.braveSearch(\n            query: 'Kristin readiness probe',\n            apiKey: key,\n            count: 1,\n          );\n          stopwatch.stop();\n          return RunCapabilityProbeResult(\n            key: requirement.key,\n            label: requirement.label,\n            ok: true,\n            required: requirement.required,\n            message: 'Brave Search is configured and responding.',\n            durationMilliseconds: stopwatch.elapsedMilliseconds,\n            details: <String, dynamic>{\n              'referenceId': reference.id,\n              'resultCount': results.length,\n            },\n          );\n        } catch (error) {\n          stopwatch.stop();\n          return RunCapabilityProbeResult(\n            key: requirement.key,\n            label: requirement.label,\n            ok: false,\n            required: requirement.required,\n            message:\n                'Web search provider is not ready: ${redactor.redact('$error')}',\n            durationMilliseconds: stopwatch.elapsedMilliseconds,\n          );\n        }\n      },\n    );\n""",
)

# Focused contracts for the new hardening behavior.
replace_once(
    "test/product/hf_runner_chat_convergence_test.dart",
    """import 'package:kristin_local_agent/product/run_steering.dart';\n""",
    """import 'package:kristin_local_agent/product/run_steering.dart';\nimport 'package:kristin_local_agent/product/storage_security.dart';\n""",
)
replace_once(
    "test/product/hf_runner_chat_convergence_test.dart",
    """      browserProbe: (requirement) async => RunCapabilityProbeResult(\n        key: requirement.key,\n        label: requirement.label,\n        ok: true,\n        required: requirement.required,\n        message: 'ready',\n        durationMilliseconds: 1,\n      ),\n    );\n""",
    """      browserProbe: (requirement) async => RunCapabilityProbeResult(\n        key: requirement.key,\n        label: requirement.label,\n        ok: true,\n        required: requirement.required,\n        message: 'ready',\n        durationMilliseconds: 1,\n      ),\n      researchSearchProbe: (run, requirement) async => RunCapabilityProbeResult(\n        key: requirement.key,\n        label: requirement.label,\n        ok: true,\n        required: requirement.required,\n        message: 'ready',\n        durationMilliseconds: 1,\n      ),\n      settingsProvider: () => const ProductSettings(\n        localOnly: false,\n        allowPackageNetwork: true,\n      ),\n    );\n""",
)
replace_once(
    "test/product/hf_runner_chat_convergence_test.dart",
    """  test('timeline projection keeps durable and live activity together', () {\n""",
    """  test('research plans require a real search-provider capability', () {\n    const resolver = RunCapabilityResolver();\n    final command = _command(\n      request: 'Research the current Flutter web documentation',\n      mode: CommandMode.ask,\n      allowedTools: const <String>{'research_search', 'research_fetch'},\n      requiredPermissions: const <PermissionScope>{\n        PermissionScope.networkResearch,\n        PermissionScope.secretUse,\n      },\n    );\n    final keys = resolver.resolve(command).map((item) => item.key).toSet();\n    expect(keys, contains('research-search'));\n    expect(keys, contains('research-network'));\n  });\n\n  test('local-only mode blocks required web search before execution', () async {\n    final root = await Directory.systemTemp.createTemp('kristin-search-preflight-');\n    addTearDown(() => root.delete(recursive: true));\n    final project = ProjectRecord(\n      id: 'project',\n      name: 'test',\n      rootPath: root.path,\n      createdAt: DateTime.now().toUtc(),\n      updatedAt: DateTime.now().toUtc(),\n    );\n    final command = _command(\n      request: 'Research current Flutter docs',\n      mode: CommandMode.ask,\n      allowedTools: const <String>{'research_search'},\n      requiredPermissions: const <PermissionScope>{\n        PermissionScope.networkResearch,\n        PermissionScope.secretUse,\n      },\n    );\n    final run = RunRecord(\n      id: 'run',\n      command: command,\n      state: RunState.prepared,\n      items: command.plan.items\n          .map((item) => WorkItemProgress(\n                item: item,\n                state: WorkItemState.queued,\n                attempts: 0,\n              ))\n          .toList(),\n      budget: const AutonomyBudget(),\n      createdAt: DateTime.now().toUtc(),\n      updatedAt: DateTime.now().toUtc(),\n    );\n    var searchProbeCalled = false;\n    final service = RunPreflightService(\n      resolver: const RunCapabilityResolver(),\n      modelProbe: (model, requirement) async => RunCapabilityProbeResult(\n        key: requirement.key,\n        label: requirement.label,\n        ok: true,\n        required: requirement.required,\n        message: 'ready',\n        durationMilliseconds: 1,\n      ),\n      browserProbe: (requirement) async => RunCapabilityProbeResult(\n        key: requirement.key,\n        label: requirement.label,\n        ok: true,\n        required: requirement.required,\n        message: 'ready',\n        durationMilliseconds: 1,\n      ),\n      researchSearchProbe: (run, requirement) async {\n        searchProbeCalled = true;\n        return RunCapabilityProbeResult(\n          key: requirement.key,\n          label: requirement.label,\n          ok: true,\n          required: requirement.required,\n          message: 'ready',\n          durationMilliseconds: 1,\n        );\n      },\n      settingsProvider: () => const ProductSettings(localOnly: true),\n    );\n    final receipt = await service.check(run: run, project: project);\n    expect(receipt.verdict, RunPreflightVerdict.blocked);\n    expect(searchProbeCalled, isFalse);\n  });\n\n  test('timeline projection keeps durable and live activity together', () {\n""",
)
replace_once(
    "test/product/hf_runner_chat_convergence_test.dart",
    """PreparedCommand _command({required String request, required CommandMode mode}) {\n""",
    """PreparedCommand _command({\n  required String request,\n  required CommandMode mode,\n  Set<String>? allowedTools,\n  Set<PermissionScope>? requiredPermissions,\n}) {\n""",
)
replace_once(
    "test/product/hf_runner_chat_convergence_test.dart",
    """    requiredPermissions: mode == CommandMode.build\n        ? const <PermissionScope>{\n            PermissionScope.projectRead,\n            PermissionScope.projectWrite,\n          }\n        : const <PermissionScope>{},\n""",
    """    requiredPermissions: requiredPermissions ??\n        (mode == CommandMode.build\n            ? const <PermissionScope>{\n                PermissionScope.projectRead,\n                PermissionScope.projectWrite,\n              }\n            : const <PermissionScope>{}),\n""",
)
replace_once(
    "test/product/hf_runner_chat_convergence_test.dart",
    """    allowedTools: mode == CommandMode.ask\n        ? const <String>{}\n        : const <String>{'read_file', 'write_file', 'git_status'},\n""",
    """    allowedTools: allowedTools ??\n        (mode == CommandMode.ask\n            ? const <String>{}\n            : const <String>{'read_file', 'write_file', 'git_status'}),\n""",
)

# Update the design note so the durable behavior is explicit.
replace_once(
    "docs/HF_RUNNER_CHAT_CONVERGENCE.md",
    """- High-frequency model/tool presentation uses `LiveRunSignalBus`; durable transitions, receipts, and applied steering stay in `EventJournal`.\n""",
    """- High-frequency model/tool presentation uses `LiveRunSignalBus`; model tokens and redacted stdout/stderr chunks are UI-batched instead of journaled per token/chunk, while durable transitions, receipts, and applied steering stay in `EventJournal`.\n- Research preflight checks local-only policy, a configured Brave Search secret reference, and a real bounded provider request before a research run starts; package probes respect the package-network policy before touching registries.\n""",
)
