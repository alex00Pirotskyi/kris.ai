import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'browser/browser_runtime.dart';
import 'capability_doctor.dart';
import 'crypto_utils.dart';
import 'deployment_support.dart';
import 'domain.dart';
import 'execution_intelligence.dart';
import 'extensions_index.dart';
import 'file_adapters.dart';
import 'models_research.dart';
import 'knowledge_memory_v2.dart';
import 'mcp.dart';
import 'mcp_registry_v2.dart';
import 'planning_runtime.dart';
import 'prompt_planning.dart';
import 'prompt_studio_v2.dart';
import 'project_diagnostics.dart';
import 'project_manager_v2.dart';
import 'conversation_orchestrator.dart';
import 'project_provisioning.dart';
import 'run_live_signals.dart';
import 'run_preflight.dart';
import 'run_steering.dart';
import 'storage_security.dart';
import 'workspace_tools.dart';
import 'p2_product_runtime_bootstrap.dart';
import 'p2_bundled_current_account_runtime.dart';
import 'p8_observability.dart';
import 'p1_authority_service_contract_v1.dart';
import 'p1_authority_service_product_runtime_v1.dart';

final class P3ProductRuntimeBrowserHandle {
  P3ProductRuntimeBrowserHandle._({
    required P3BrowserRuntimeService? service,
    required Directory? stateDirectory,
    required String statusCode,
    required Map<String, Object?> provenance,
  })  : _service = service,
        _stateDirectory = stateDirectory,
        _statusCode = statusCode,
        _provenance = Map<String, Object?>.unmodifiable(provenance);

  factory P3ProductRuntimeBrowserHandle.blocked(String statusCode) =>
      P3ProductRuntimeBrowserHandle._(
        service: null,
        stateDirectory: null,
        statusCode: statusCode,
        provenance: const <String, Object?>{
          'applicationOwned': true,
          'globalRuntimeRequired': false,
          'browserNetworkInstallRequired': false,
          'p3_002SessionServiceImplemented': false,
        },
      );

  static Future<P3ProductRuntimeBrowserHandle> open({
    required Directory applicationDataRoot,
    required Directory stateDirectory,
    String? executablePath,
  }) async {
    final service = P3BrowserRuntimeService(
      applicationDataRoot: applicationDataRoot,
      executablePath: executablePath,
    );
    try {
      final resources = await service.resolveBundle();
      return P3ProductRuntimeBrowserHandle._(
        service: service,
        stateDirectory: stateDirectory.absolute,
        statusCode: 'p3_browser_runtime_available',
        provenance: resources.provenance,
      );
    } on StateError catch (error) {
      final message = error.message.toString();
      return P3ProductRuntimeBrowserHandle.blocked(
        message.startsWith('p3_browser_runtime_bundle_missing')
            ? 'p3_browser_runtime_bundle_missing'
            : 'p3_browser_runtime_bundle_invalid',
      );
    } on FileSystemException {
      return P3ProductRuntimeBrowserHandle.blocked(
        'p3_browser_runtime_bundle_unreadable',
      );
    }
  }

  final P3BrowserRuntimeService? _service;
  final Directory? _stateDirectory;
  final String _statusCode;
  final Map<String, Object?> _provenance;
  Future<P3BrowserRuntimeProbeResult>? _activeProbe;
  bool _closed = false;

  bool get available => !_closed && _service != null;

  String get statusCode => _closed ? 'p3_product_runtime_closed' : _statusCode;

  Map<String, Object?> get provenance =>
      Map<String, Object?>.unmodifiable(<String, Object?>{
        ..._provenance,
        'available': available,
        'statusCode': statusCode,
        'p3_002SessionServiceImplemented': false,
      });

  Future<P3BrowserRuntimeProbeResult> probe({
    Duration startupTimeout = const Duration(seconds: 30),
  }) async {
    if (_closed) {
      throw const P3BrowserRuntimeException('p3_product_runtime_closed');
    }
    final service = _service;
    final stateDirectory = _stateDirectory;
    if (service == null || stateDirectory == null) {
      throw P3BrowserRuntimeException(
        'p3_product_runtime_unavailable',
        _statusCode,
      );
    }
    if (_activeProbe != null) {
      throw const P3BrowserRuntimeException(
        'p3_product_runtime_probe_in_progress',
      );
    }
    final future = service.probe(
      stateDirectory: stateDirectory,
      startupTimeout: startupTimeout,
    );
    _activeProbe = future;
    try {
      return await future;
    } finally {
      if (identical(_activeProbe, future)) _activeProbe = null;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final active = _activeProbe;
    if (active != null) {
      try {
        await active;
      } catch (_) {
        // The probe owns fail-closed teardown. Application shutdown must wait
        // for it, but a failed diagnostic probe must not strand other runtime
        // shutdown responsibilities.
      }
    }
    _activeProbe = null;
  }
}

class ProductRuntime {
  ProductRuntime._({
    required this.directories,
    required this.repositories,
    required this.redactor,
    required this.events,
    required this.audit,
    required this.permissions,
    required this.secrets,
    required this.tokens,
    required this.knowledge,
    required this.objectStore,
    required this.skillPublication,
    required this.fileAdapters,
    required this.research,
    required this.models,
    required this.deployment,
    required this.managedProcesses,
    required this.sourceIndex,
    required this.mcp,
    required this.mcpV2,
    required this.telemetry,
    required this.telemetryBridge,
    required this.support,
    required this.commandService,
    required this.promptPlanning,
    required this.promptStudioV2,
    required this.diagnostics,
    required this.executionIntelligence,
    required this.projectManagerV2,
    required this.liveRunSignals,
    required this.runPreflight,
    required this.conversationOrchestrator,
    required this.projectProvisioning,
    required this.runSteering,
    required this.runs,
    required ProductSettings settings,
  }) : _settings = settings;

  final AppDirectories directories;
  final ProductRepositories repositories;
  final SecretRedactor redactor;
  final EventJournal events;
  final AuditChain audit;
  final PermissionService permissions;
  final SecretVault secrets;
  final ApiTokenService tokens;
  final KnowledgeService knowledge;
  final ContentAddressedObjectStore objectStore;
  final SkillPublicationService skillPublication;
  final FileAdapterRegistry fileAdapters;
  final ResearchService research;
  final ModelRegistry models;
  final DeploymentService deployment;
  final ManagedProcessService managedProcesses;
  final SourceIndexService sourceIndex;
  final McpTrustService mcp;
  final McpRegistryV2 mcpV2;
  final P8TelemetryBuffer telemetry;
  final P8ProductTelemetryBridge telemetryBridge;
  final SupportBundleService support;
  final PreparedCommandService commandService;
  final PromptPlanningService promptPlanning;
  final PromptStudioV2Service promptStudioV2;
  final ProjectDiagnosticsService diagnostics;
  final ExecutionIntelligenceService executionIntelligence;
  final ProjectManagerV2Service projectManagerV2;
  final LiveRunSignalBus liveRunSignals;
  final RunPreflightService runPreflight;
  final ConversationOrchestrator conversationOrchestrator;
  final ProjectProvisioningService projectProvisioning;
  final RunSteeringService runSteering;
  final RunCoordinator runs;
  P3ProductRuntimeBrowserHandle? _p3BrowserRuntime;
  P3ProductRuntimeBrowserHandle get p3BrowserRuntime =>
      _p3BrowserRuntime ??
      P3ProductRuntimeBrowserHandle.blocked(
        'product_runtime_p3_not_initialized',
      );
  P2ProductRuntimeOwnerModeHandle? _p2OwnerModeRuntime;
  P2ProductRuntimeOwnerModeHandle get p2OwnerMode =>
      _p2OwnerModeRuntime ??
      P2ProductRuntimeOwnerModeHandle.blocked(
        'product_runtime_p2_not_initialized',
      );
  P1AuthorityServiceProductRuntimeV1? _p1AuthorityServiceRuntime;
  P1AuthorityServiceHandleV1? get p1AuthorityService =>
      _p1AuthorityServiceRuntime?.handle;
  final Map<String, String> _projectProcessIds = <String, String>{};
  ProductSettings _settings;

  ProductSettings get settings => _settings;
  Map<String, Object> previewTelemetry() => telemetry.preview();
  Future<void> exportTelemetry(File file) => telemetry.export(file);
  void deleteTelemetry() => telemetry.deleteAll();
  Stream<EventEnvelope> get eventStream => events.stream;
  Stream<LiveRunSignal> get liveRunStream => liveRunSignals.stream;

  static Future<ProductRuntime> initialize({String? dataRoot}) async {
    final directories = await AppDirectories.create(overrideRoot: dataRoot);
    final repositories = await ProductRepositories.open(directories);
    final redactor = SecretRedactor();
    final events = EventJournal(
      repositories.eventFile,
      workflow: repositories.workflow,
    );
    await events.open();
    final audit = AuditChain(repositories.auditFile, redactor);
    await audit.open();
    final settings = await repositories.loadSettings();
    final permissions = PermissionService(repositories.grants, audit);
    final secrets = SecretVault(repositories.secretReferences, redactor, audit);
    final tokens = ApiTokenService(repositories.tokens, audit);
    final objectStore = ContentAddressedObjectStore(
      Directory('${directories.support.path}${Platform.pathSeparator}objects'),
    );
    await objectStore.initialize();
    final knowledge = KnowledgeService(
      repositories.knowledge,
      archiveRepository: repositories.researchArchive,
      episodeRepository: repositories.memoryEpisodes,
      archiveDirectory: Directory(
        '${directories.root.path}${Platform.pathSeparator}research-archive',
      ),
      indexDirectory: Directory(
        '${directories.cache.path}${Platform.pathSeparator}knowledge-index',
      ),
      exportDirectory: Directory(
        '${directories.root.path}${Platform.pathSeparator}knowledge-exports',
      ),
      objectStore: objectStore,
      freshnessPolicy: const ResearchFreshnessPolicy(),
      admissionPolicy: const MemoryAdmissionPolicy(),
    );
    await knowledge.initialize();
    final skillPublication = SkillPublicationService(
      candidateRepository: repositories.skillCandidates,
      publishedRepository: repositories.publishedSkills,
      objectStore: objectStore,
    );
    const fileAdapters = FileAdapterRegistry();
    final research = ResearchService(
      policy: ResearchPolicy(
        maxBytes: settings.maxResearchBytes,
        maxRedirects: settings.maxResearchRedirects,
        timeout: Duration(seconds: settings.researchTimeoutSeconds),
      ),
      redactor: redactor,
    );
    final models = ModelRegistry(
      settings: settings,
      vault: secrets,
      redactor: redactor,
    );
    final deployment = DeploymentService(
      outputDirectory: Directory(
        '${directories.root.path}${Platform.pathSeparator}deployments',
      ),
      redactor: redactor,
    );
    final managedProcesses = ManagedProcessService(
      logDirectory: Directory(
        '${directories.logs.path}${Platform.pathSeparator}managed-processes',
      ),
      redactor: redactor,
    );
    final sourceIndex = SourceIndexService(
      Directory(
        '${directories.cache.path}${Platform.pathSeparator}source-index',
      ),
    );
    final mcp = McpTrustService(
      workflow: repositories.workflow,
      audit: audit,
      redactor: redactor,
    );
    final mcpV2 = McpRegistryV2(
      workflow: repositories.workflow,
      audit: audit,
      trustedKeys: const <String, McpDescriptorTrustKeyV2>{},
    );
    final telemetry = P8TelemetryBuffer(
      policy: P8TelemetryPolicy(
        optedIn: settings.telemetryOptIn,
        retentionDays: settings.telemetryRetentionDays,
        maxBufferedEvents: settings.telemetryMaxBufferedEvents,
      ),
    );
    final telemetryBridge = P8ProductTelemetryBridge(
      buffer: telemetry,
      events: events.stream,
    );
    final support = SupportBundleService(
      directories: directories,
      repositories: repositories,
      audit: audit,
      redactor: redactor,
    );
    final commandService = PreparedCommandService(
      repositories,
      const ContractPlanner(),
      audit,
      events,
    );
    final tools = ToolRegistry.standard();
    final liveRunSignals = LiveRunSignalBus();
    const conversationOrchestrator = ConversationOrchestrator();
    final projectProvisioning = ProjectProvisioningService(
      directories: directories,
    );
    late ProductRuntime runtime;
    final runPreflight = RunPreflightService(
      resolver: const RunCapabilityResolver(),
      settingsProvider: () => runtime._settings,
      modelProbe: (model, requirement) async {
        final stopwatch = Stopwatch()..start();
        try {
          final provider = models.providerFor(model);
          if (model.providerId == 'ollama') {
            final discovered = await provider.discover().timeout(
                  const Duration(seconds: 12),
                );
            final exact = discovered.where((candidate) {
              if (candidate.name != model.name) return false;
              if (model.digest.isEmpty || candidate.digest.isEmpty) return true;
              return candidate.digest == model.digest;
            }).firstOrNull;
            stopwatch.stop();
            return RunCapabilityProbeResult(
              key: requirement.key,
              label: requirement.label,
              ok: exact != null,
              required: requirement.required,
              message: exact != null
                  ? '${model.name} is installed and the Ollama service is reachable.'
                  : '${model.name} is not available with the selected identity.',
              durationMilliseconds: stopwatch.elapsedMilliseconds,
              details: <String, dynamic>{
                'model': model.toJson(),
                'probe': 'discovery',
              },
            );
          }
          final result = await provider.generate(
            ModelGenerationRequest(
              identity: model,
              systemPrompt:
                  'You are a readiness probe. Return exactly {\\"status\\":\\"ready\\"}.',
              userPrompt: 'Return readiness JSON now.',
              commandId: newId('preflight_model'),
              temperature: 0,
              maxOutputTokens: 32,
              firstTokenTimeout: const Duration(seconds: 45),
              totalTimeout: const Duration(seconds: 90),
            ),
          );
          stopwatch.stop();
          return RunCapabilityProbeResult(
            key: requirement.key,
            label: requirement.label,
            ok: result.text.trim().isNotEmpty,
            required: requirement.required,
            message: result.text.trim().isNotEmpty
                ? '${model.name} is loaded and responding.'
                : '${model.name} returned an empty readiness response.',
            durationMilliseconds: stopwatch.elapsedMilliseconds,
            details: <String, dynamic>{
              'model': model.toJson(),
              'firstTokenLatencyMs': result.firstTokenLatency.inMilliseconds,
            },
          );
        } catch (error) {
          stopwatch.stop();
          return RunCapabilityProbeResult(
            key: requirement.key,
            label: requirement.label,
            ok: false,
            required: requirement.required,
            message: '${model.name} is not ready: $error',
            durationMilliseconds: stopwatch.elapsedMilliseconds,
          );
        }
      },
      browserProbe: (requirement) async {
        final stopwatch = Stopwatch()..start();
        try {
          await runtime.p3BrowserRuntime.probe(
            startupTimeout: const Duration(seconds: 20),
          );
          stopwatch.stop();
          return RunCapabilityProbeResult(
            key: requirement.key,
            label: requirement.label,
            ok: true,
            required: requirement.required,
            message: 'Browser runtime starts and shuts down cleanly.',
            durationMilliseconds: stopwatch.elapsedMilliseconds,
          );
        } catch (error) {
          stopwatch.stop();
          return RunCapabilityProbeResult(
            key: requirement.key,
            label: requirement.label,
            ok: false,
            required: requirement.required,
            message: 'Browser runtime is not ready: $error',
            durationMilliseconds: stopwatch.elapsedMilliseconds,
          );
        }
      },
      researchSearchProbe: (run, requirement) async {
        final stopwatch = Stopwatch()..start();
        try {
          final references = await repositories.secretReferences.all();
          int score(SecretReference reference) {
            final text =
                '${reference.environmentKey} ${reference.label} ${reference.description}'
                    .toLowerCase();
            if (reference.environmentKey.toUpperCase() ==
                'BRAVE_SEARCH_API_KEY') {
              return 0;
            }
            if (text.contains('brave') && text.contains('search')) return 1;
            if (text.contains('brave')) return 2;
            return 100;
          }

          final candidates = references
              .where((item) => score(item) < 100)
              .toList()
            ..sort((left, right) => score(left).compareTo(score(right)));
          if (candidates.isEmpty) {
            stopwatch.stop();
            return RunCapabilityProbeResult(
              key: requirement.key,
              label: requirement.label,
              ok: false,
              required: requirement.required,
              message:
                  'Web search is required, but no Brave Search secret reference is configured.',
              durationMilliseconds: stopwatch.elapsedMilliseconds,
            );
          }
          final reference = candidates.first;
          final key = await secrets.resolve(
            reference.id,
            commandId: run.command.id,
          );
          final results = await research.braveSearch(
            query: 'Kristin readiness probe',
            apiKey: key,
            count: 1,
          );
          stopwatch.stop();
          return RunCapabilityProbeResult(
            key: requirement.key,
            label: requirement.label,
            ok: true,
            required: requirement.required,
            message: 'Brave Search is configured and responding.',
            durationMilliseconds: stopwatch.elapsedMilliseconds,
            details: <String, dynamic>{
              'referenceId': reference.id,
              'resultCount': results.length,
            },
          );
        } catch (error) {
          stopwatch.stop();
          return RunCapabilityProbeResult(
            key: requirement.key,
            label: requirement.label,
            ok: false,
            required: requirement.required,
            message:
                'Web search provider is not ready: ${redactor.redact('$error')}',
            durationMilliseconds: stopwatch.elapsedMilliseconds,
          );
        }
      },
    );
    final runSteering = RunSteeringService(liveSignals: liveRunSignals);
    final promptPlanning = PromptPlanningService(
      models: models,
      repositories: repositories,
      audit: audit,
      events: events,
      redactor: redactor,
      tools: tools,
      settingsProvider: () => runtime._settings,
    );
    final promptStudioV2 = PromptStudioV2Service(
      tools: tools,
      audit: audit,
      events: events,
      settingsProvider: () => runtime._settings,
    );
    final diagnostics = ProjectDiagnosticsService(redactor: redactor);
    final executionIntelligence = ExecutionIntelligenceService(
      workflow: repositories.workflow,
    );
    final projectManagerV2 = ProjectManagerV2Service(
      dataRoot: directories.root.path,
      redactor: redactor,
    );
    final coordinator = RunCoordinator(
      directories: directories,
      repositories: repositories,
      modelRegistry: models,
      permissions: permissions,
      secrets: secrets,
      research: research,
      knowledge: knowledge,
      tools: tools,
      audit: audit,
      events: events,
      settingsProvider: () => runtime._settings,
      redactor: redactor,
      deployment: deployment,
      managedProcesses: managedProcesses,
      sourceIndex: sourceIndex,
      skillRegistry: const SkillRegistry(),
      mcp: mcp,
      executionIntelligence: executionIntelligence,
      preflight: runPreflight,
      liveSignals: liveRunSignals,
      steering: runSteering,
    );
    runtime = ProductRuntime._(
      directories: directories,
      repositories: repositories,
      redactor: redactor,
      events: events,
      audit: audit,
      permissions: permissions,
      secrets: secrets,
      tokens: tokens,
      knowledge: knowledge,
      objectStore: objectStore,
      skillPublication: skillPublication,
      fileAdapters: fileAdapters,
      research: research,
      models: models,
      deployment: deployment,
      managedProcesses: managedProcesses,
      sourceIndex: sourceIndex,
      mcp: mcp,
      mcpV2: mcpV2,
      telemetry: telemetry,
      telemetryBridge: telemetryBridge,
      support: support,
      commandService: commandService,
      promptPlanning: promptPlanning,
      promptStudioV2: promptStudioV2,
      diagnostics: diagnostics,
      executionIntelligence: executionIntelligence,
      projectManagerV2: projectManagerV2,
      liveRunSignals: liveRunSignals,
      runPreflight: runPreflight,
      conversationOrchestrator: conversationOrchestrator,
      projectProvisioning: projectProvisioning,
      runSteering: runSteering,
      runs: coordinator,
      settings: settings,
    );
    telemetryBridge.start();
    runtime._p1AuthorityServiceRuntime =
        await P1AuthorityServiceConnectorRegistryV1.openInstalledOrTest();
    if (runtime.p1AuthorityService == null) {
      await P2BundledCurrentAccountRuntime.prepareIfPresent(
        applicationDataRoot: directories.root,
      );
    }
    runtime._p2OwnerModeRuntime = await P2ProductRuntimeBootstrap.start(
      dataRoot: directories.root,
      p1AuthorityService: runtime.p1AuthorityService,
    );
    runtime._p3BrowserRuntime = await P3ProductRuntimeBrowserHandle.open(
      applicationDataRoot: directories.root,
      stateDirectory: Directory(
        '${directories.cache.path}${Platform.pathSeparator}p3-browser-runtime',
      ),
    );
    await coordinator.reconcileInterruptedRuns();
    await coordinator.reconcileMemoryEpisodes();
    await audit.append('application.started', 'application', <String, dynamic>{
      'version': kristinVersion,
      'platform': Platform.operatingSystem,
      'dataRootHash': Sha256.text(directories.root.path),
    });
    return runtime;
  }

  Future<CapabilityDoctorReport> inspectCapabilities({
    String? projectId,
    List<ModelIdentity>? discoveredModels,
    ProjectDiagnosticReport? projectReport,
    CapabilityDoctorDepth depth = CapabilityDoctorDepth.quick,
  }) async {
    final checks = <CapabilityDoctorCheck>[];

    final storageWatch = Stopwatch()..start();
    final probeFile = File(
      '${directories.support.path}${Platform.pathSeparator}.capability-doctor-${newId('probe')}.tmp',
    );
    try {
      await probeFile.writeAsString('kristin-ready\n', flush: true);
      final stored = await probeFile.readAsString();
      storageWatch.stop();
      checks.add(
        CapabilityDoctorCheck(
          id: 'storage',
          title: 'Local storage',
          status: stored == 'kristin-ready\n'
              ? CapabilityDoctorStatus.ready
              : CapabilityDoctorStatus.blocked,
          message: stored == 'kristin-ready\n'
              ? 'Application-owned state and support storage are writable.'
              : 'The storage probe could not read back the bytes it wrote.',
          required: true,
          action: stored == 'kristin-ready\n'
              ? CapabilityDoctorAction.none
              : CapabilityDoctorAction.openSettings,
          durationMilliseconds: storageWatch.elapsedMilliseconds,
          details: <String, Object?>{'root': directories.root.path},
        ),
      );
    } catch (error) {
      storageWatch.stop();
      checks.add(
        CapabilityDoctorCheck(
          id: 'storage',
          title: 'Local storage',
          status: CapabilityDoctorStatus.blocked,
          message:
              'Kristin cannot safely write application state: ${redactor.redact('$error')}',
          required: true,
          action: CapabilityDoctorAction.openSettings,
          durationMilliseconds: storageWatch.elapsedMilliseconds,
        ),
      );
    } finally {
      try {
        if (await probeFile.exists()) await probeFile.delete();
      } catch (_) {
        // The probe result is about application storage availability; a stale
        // temporary file is non-authoritative cleanup evidence.
      }
    }

    final modelWatch = Stopwatch()..start();
    try {
      final knownModels = discoveredModels ?? await discoverModels();
      modelWatch.stop();
      checks.add(
        CapabilityDoctorCheck(
          id: 'model',
          title: 'AI model',
          status: knownModels.isEmpty
              ? CapabilityDoctorStatus.blocked
              : CapabilityDoctorStatus.ready,
          message: knownModels.isEmpty
              ? 'No usable AI model is currently discovered.'
              : '${knownModels.first.name} is available${knownModels.length == 1 ? '' : ' with ${knownModels.length - 1} additional model(s)'}.',
          required: true,
          action: knownModels.isEmpty
              ? CapabilityDoctorAction.connectModel
              : CapabilityDoctorAction.none,
          durationMilliseconds: modelWatch.elapsedMilliseconds,
          details: <String, Object?>{
            'modelCount': knownModels.length,
            'models': knownModels.map((item) => item.exactId).toList(),
          },
        ),
      );
    } catch (error) {
      modelWatch.stop();
      checks.add(
        CapabilityDoctorCheck(
          id: 'model',
          title: 'AI model',
          status: CapabilityDoctorStatus.blocked,
          message: 'Model discovery failed: ${redactor.redact('$error')}',
          required: true,
          action: CapabilityDoctorAction.connectModel,
          durationMilliseconds: modelWatch.elapsedMilliseconds,
        ),
      );
    }

    final owner = p2OwnerMode;
    checks.add(
      CapabilityDoctorCheck(
        id: 'owner-mode',
        title: 'Owner Mode',
        status: owner.available
            ? CapabilityDoctorStatus.ready
            : CapabilityDoctorStatus.warning,
        message: owner.available
            ? 'Owner Mode runtime is available when full-computer access is explicitly selected.'
            : owner.recoveryMessage,
        required: false,
        action: owner.available
            ? CapabilityDoctorAction.none
            : CapabilityDoctorAction.openSettings,
        details: <String, Object?>{
          'available': owner.available,
          'completionEligible': owner.completionEligible,
          if (!owner.available) 'diagnosticCode': owner.diagnosticCode,
        },
      ),
    );

    checks.add(
      CapabilityDoctorCheck(
        id: 'terminal',
        title: 'Interactive terminal',
        status: owner.available
            ? CapabilityDoctorStatus.ready
            : CapabilityDoctorStatus.warning,
        message: owner.available
            ? 'The governed Owner runtime can provide interactive terminal sessions.'
            : 'Terminal automation needs a healthy Owner Mode runtime. Ordinary project commands remain separately governed.',
        required: false,
        action: owner.available
            ? CapabilityDoctorAction.none
            : CapabilityDoctorAction.openSettings,
      ),
    );

    final browserWatch = Stopwatch()..start();
    if (!p3BrowserRuntime.available) {
      browserWatch.stop();
      checks.add(
        CapabilityDoctorCheck(
          id: 'browser',
          title: 'Browser automation',
          status: CapabilityDoctorStatus.warning,
          message:
              'Browser runtime is unavailable: ${p3BrowserRuntime.statusCode}.',
          required: false,
          action: CapabilityDoctorAction.retryDoctor,
          durationMilliseconds: browserWatch.elapsedMilliseconds,
          details: <String, Object?>{'statusCode': p3BrowserRuntime.statusCode},
        ),
      );
    } else if (depth == CapabilityDoctorDepth.quick) {
      browserWatch.stop();
      checks.add(
        CapabilityDoctorCheck(
          id: 'browser',
          title: 'Browser automation',
          status: CapabilityDoctorStatus.ready,
          message:
              'The application-owned browser bundle is available. Full Doctor launches a bounded startup probe.',
          required: false,
          durationMilliseconds: browserWatch.elapsedMilliseconds,
          details: <String, Object?>{'statusCode': p3BrowserRuntime.statusCode},
        ),
      );
    } else {
      try {
        await p3BrowserRuntime.probe(
          startupTimeout: const Duration(seconds: 20),
        );
        browserWatch.stop();
        checks.add(
          CapabilityDoctorCheck(
            id: 'browser',
            title: 'Browser automation',
            status: CapabilityDoctorStatus.ready,
            message: 'Browser runtime starts and shuts down cleanly.',
            required: false,
            durationMilliseconds: browserWatch.elapsedMilliseconds,
            details: <String, Object?>{
              'statusCode': p3BrowserRuntime.statusCode,
            },
          ),
        );
      } catch (error) {
        browserWatch.stop();
        checks.add(
          CapabilityDoctorCheck(
            id: 'browser',
            title: 'Browser automation',
            status: CapabilityDoctorStatus.warning,
            message:
                'Browser startup probe failed: ${redactor.redact('$error')}',
            required: false,
            action: CapabilityDoctorAction.retryDoctor,
            durationMilliseconds: browserWatch.elapsedMilliseconds,
            details: <String, Object?>{
              'statusCode': p3BrowserRuntime.statusCode,
            },
          ),
        );
      }
    }

    final searchWatch = Stopwatch()..start();
    if (settings.localOnly) {
      searchWatch.stop();
      checks.add(
        CapabilityDoctorCheck(
          id: 'search',
          title: 'Web search',
          status: CapabilityDoctorStatus.warning,
          message:
              'Web research is disabled by local-only settings. Runs that require current web information will fail closed before execution.',
          required: false,
          action: CapabilityDoctorAction.openSettings,
          durationMilliseconds: searchWatch.elapsedMilliseconds,
        ),
      );
    } else {
      try {
        final references = await repositories.secretReferences.all();
        bool isSearchReference(SecretReference reference) {
          final text =
              '${reference.environmentKey} ${reference.label} ${reference.description}'
                  .toLowerCase();
          return reference.environmentKey.toUpperCase() ==
                  'BRAVE_SEARCH_API_KEY' ||
              (text.contains('brave') && text.contains('search'));
        }

        final configured = references.where(isSearchReference).toList();
        searchWatch.stop();
        checks.add(
          CapabilityDoctorCheck(
            id: 'search',
            title: 'Web search',
            status: configured.isEmpty
                ? CapabilityDoctorStatus.warning
                : CapabilityDoctorStatus.ready,
            message: configured.isEmpty
                ? 'Web research is enabled, but no Brave Search secret reference is configured.'
                : 'A Brave Search credential reference is configured. Task-specific preflight performs the authenticated provider probe before a run that needs web research.',
            required: false,
            action: configured.isEmpty
                ? CapabilityDoctorAction.openSettings
                : CapabilityDoctorAction.none,
            durationMilliseconds: searchWatch.elapsedMilliseconds,
            details: <String, Object?>{
              'configuredReferenceCount': configured.length,
            },
          ),
        );
      } catch (error) {
        searchWatch.stop();
        checks.add(
          CapabilityDoctorCheck(
            id: 'search',
            title: 'Web search',
            status: CapabilityDoctorStatus.warning,
            message:
                'Search-provider configuration could not be inspected: ${redactor.redact('$error')}',
            required: false,
            action: CapabilityDoctorAction.openSettings,
            durationMilliseconds: searchWatch.elapsedMilliseconds,
          ),
        );
      }
    }

    final projectWatch = Stopwatch()..start();
    if (projectId == null || projectId.trim().isEmpty) {
      projectWatch.stop();
      checks.add(
        CapabilityDoctorCheck(
          id: 'project',
          title: 'Project workspace',
          status: CapabilityDoctorStatus.warning,
          message:
              'No project is selected. Build requests can still create and bind a workspace automatically.',
          required: false,
          action: CapabilityDoctorAction.openProjects,
          durationMilliseconds: projectWatch.elapsedMilliseconds,
        ),
      );
    } else {
      try {
        final knownModels = discoveredModels ?? await discoverModels();
        final report = depth == CapabilityDoctorDepth.quick &&
                projectReport?.projectId == projectId
            ? projectReport!
            : await inspectProject(
                projectId,
                modelReady: knownModels.isNotEmpty,
              );
        projectWatch.stop();
        final healthy = !report.hasBlockingFailure;
        checks.add(
          CapabilityDoctorCheck(
            id: 'project',
            title: 'Project workspace',
            status: healthy
                ? CapabilityDoctorStatus.ready
                : CapabilityDoctorStatus.warning,
            message: healthy
                ? '${report.projectType} workspace is available; ${report.passed} diagnostic check(s) pass.'
                : 'The selected workspace has ${report.failed} blocking diagnostic failure(s).',
            required: false,
            action: healthy
                ? CapabilityDoctorAction.none
                : CapabilityDoctorAction.openProjects,
            durationMilliseconds: projectWatch.elapsedMilliseconds,
            details: <String, Object?>{
              'projectId': projectId,
              'projectType': report.projectType,
              'passed': report.passed,
              'warnings': report.warnings,
              'failed': report.failed,
            },
          ),
        );
      } catch (error) {
        projectWatch.stop();
        checks.add(
          CapabilityDoctorCheck(
            id: 'project',
            title: 'Project workspace',
            status: CapabilityDoctorStatus.warning,
            message:
                'Project diagnostics could not be completed: ${redactor.redact('$error')}',
            required: false,
            action: CapabilityDoctorAction.openProjects,
            durationMilliseconds: projectWatch.elapsedMilliseconds,
          ),
        );
      }
    }

    return CapabilityDoctorReport(depth: depth, checks: checks);
  }

  Future<void> close() async {
    await _p3BrowserRuntime?.close();
    await _p2OwnerModeRuntime?.close();
    await _p1AuthorityServiceRuntime?.close();
    await managedProcesses.stopAll();
    await mcp.closeAll();
    secrets.clearSession();
    await audit.append('application.stopped', 'application', <String, dynamic>{
      'version': kristinVersion,
    });
    await liveRunSignals.close();
    await telemetryBridge.close();
    await events.close();
    await repositories.workflow.close();
  }

  Future<ProjectRecord> provisionProjectForRequest({
    required String request,
    String? suggestedName,
  }) async {
    final intent = conversationOrchestrator.classify(
      request,
      CommandMode.build,
    );
    final location = await projectProvisioning.prepare(
      suggestedName: suggestedName?.trim().isNotEmpty == true
          ? suggestedName!
          : intent.suggestedProjectName,
    );
    return addProject(name: location.name, rootPath: location.rootPath);
  }

  Future<RunSteeringInstruction> steerRun(String runId, String text) =>
      runs.queueSteering(runId, text);

  Future<List<EventEnvelope>> eventsForRun(
    String runId, {
    int limit = 10000,
  }) async {
    final result = <EventEnvelope>[];
    var cursor = 0;
    while (result.length < limit) {
      final batch = await events.after(cursor, limit: 1000);
      if (batch.isEmpty) break;
      cursor = batch.last.sequence;
      for (final event in batch) {
        if (event.correlationId == runId ||
            event.data['runId']?.toString() == runId) {
          result.add(event);
          if (result.length >= limit) break;
        }
      }
      if (batch.length < 1000) break;
    }
    return List<EventEnvelope>.unmodifiable(result);
  }

  Future<List<ProjectRecord>> listProjects() async {
    final projects = await repositories.projects.all();
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  Future<ProjectRecord?> getProject(String id) => repositories.projects.get(id);

  Future<ProjectRecord> addProject({
    required String name,
    required String rootPath,
  }) async {
    final root = Directory(rootPath.trim()).absolute;
    if (!await root.exists()) {
      throw ProductException(
        'project_missing',
        'The selected project directory does not exist.',
      );
    }
    final canonical = await root.resolveSymbolicLinks();
    final normalized = Platform.isWindows ? canonical.toLowerCase() : canonical;
    final existing = (await repositories.projects.all()).where((project) {
      final path = Platform.isWindows
          ? project.rootPath.toLowerCase()
          : project.rootPath;
      return path == normalized;
    }).firstOrNull;
    if (existing != null) {
      return existing;
    }
    final now = DateTime.now().toUtc();
    final project = ProjectRecord(
      id: newId('project'),
      name: name.trim().isEmpty
          ? root.uri.pathSegments.where((item) => item.isNotEmpty).last
          : name.trim(),
      rootPath: canonical,
      createdAt: now,
      updatedAt: now,
    );
    await repositories.projects.put(project);
    await audit.append('project.added', project.id, <String, dynamic>{
      'projectId': project.id,
      'name': project.name,
      'rootPathHash': Sha256.text(project.rootPath),
    });
    await events.publish('project.added', project.id, <String, dynamic>{
      'project': project.toJson(),
    });
    return project;
  }

  Future<ProjectRecord> createProject({
    required String name,
    required String parentPath,
  }) async {
    final safeName = name.trim();
    if (safeName.isEmpty ||
        safeName == '.' ||
        safeName == '..' ||
        safeName.contains('/') ||
        safeName.contains('\\') ||
        RegExp(r'[:*?"<>|]').hasMatch(safeName)) {
      throw ProductException(
        'project_name_invalid',
        'Choose a simple project name without path separators or reserved characters.',
      );
    }
    final parent = Directory(parentPath.trim()).absolute;
    if (!await parent.exists()) {
      throw ProductException(
        'project_parent_missing',
        'The selected parent folder does not exist.',
      );
    }
    final root = Directory('${parent.path}${Platform.pathSeparator}$safeName');
    if (await root.exists()) {
      final entities = await root.list(followLinks: false).take(1).toList();
      if (entities.isNotEmpty) {
        throw ProductException(
          'project_folder_not_empty',
          'A non-empty folder with that name already exists.',
        );
      }
    } else {
      await root.create(recursive: false);
    }
    final readme = File('${root.path}${Platform.pathSeparator}README.md');
    if (!await readme.exists()) {
      await readme.writeAsString(
        '# $safeName\n\nCreated with Kristin Local Agent.\n',
        flush: true,
      );
    }
    return addProject(name: safeName, rootPath: root.path);
  }

  Future<String?> pickProjectFolder({
    String prompt = 'Choose a project folder',
  }) =>
      diagnostics.pickFolder(prompt: prompt);

  Future<void> removeProject(String id) async {
    final project = await repositories.projects.get(id);
    if (project == null) {
      return;
    }
    final active = (await repositories.runs.all()).where(
      (run) =>
          run.command.contract.projectId == id &&
          const <RunState>{
            RunState.running,
            RunState.paused,
            RunState.cancelling,
          }.contains(run.state),
    );
    final managed = await projectProcessStatus(id);
    if (active.isNotEmpty || managed?.running == true) {
      throw ProductException(
        'project_has_active_run',
        'Stop the active agent run or managed project process before removing this project.',
      );
    }
    await repositories.projects.remove(id);
    _projectProcessIds.remove(id);
    await audit.append('project.removed', id, <String, dynamic>{
      'projectId': id,
      'name': project.name,
    });
    await events.publish('project.removed', id, <String, dynamic>{
      'projectId': id,
    });
  }

  Future<void> updateSettings(ProductSettings value) async {
    if (value.apiPort < 1024 || value.apiPort > 65535) {
      throw ProductException(
        'api_port_invalid',
        'API port must be between 1024 and 65535.',
      );
    }
    if (value.ollamaLoadTimeoutSeconds < 60 ||
        value.ollamaLoadTimeoutSeconds > 3600) {
      throw ProductException(
        'ollama_load_timeout_invalid',
        'Ollama cold-load timeout must be between 60 and 3600 seconds.',
      );
    }
    if (value.ollamaLoadRetries < 0 || value.ollamaLoadRetries > 2) {
      throw ProductException(
        'ollama_load_retries_invalid',
        'Ollama cold-load retries must be between 0 and 2.',
      );
    }
    if (value.ollamaKeepAliveMinutes < 1 ||
        value.ollamaKeepAliveMinutes > 120) {
      throw ProductException(
        'ollama_keep_alive_invalid',
        'Ollama keep-alive must be between 1 and 120 minutes.',
      );
    }
    for (final origin in value.allowedOrigins) {
      final uri = Uri.tryParse(origin);
      if (uri == null ||
          !const <String>{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.pathSegments.isNotEmpty) {
        throw ProductException(
          'origin_invalid',
          'Allowed browser origins must be origin-only HTTP(S) URLs.',
        );
      }
      if (origin.contains('*')) {
        throw ProductException(
          'origin_wildcard_rejected',
          'Wildcard CORS origins are not allowed.',
        );
      }
    }
    _settings = value;
    models.settings = value;
    research.policy = ResearchPolicy(
      maxBytes: value.maxResearchBytes,
      maxRedirects: value.maxResearchRedirects,
      timeout: Duration(seconds: value.researchTimeoutSeconds),
    );
    telemetry.updatePolicy(
      P8TelemetryPolicy(
        optedIn: value.telemetryOptIn,
        retentionDays: value.telemetryRetentionDays,
        maxBufferedEvents: value.telemetryMaxBufferedEvents,
      ),
    );
    await repositories.saveSettings(value);
    await audit.append('settings.updated', 'settings', <String, dynamic>{
      'apiEnabled': value.apiEnabled,
      'apiPort': value.apiPort,
      'allowedOrigins': value.allowedOrigins.toList(),
      'localOnly': value.localOnly,
      'allowPackageNetwork': value.allowPackageNetwork,
      'ollamaLoadTimeoutSeconds': value.ollamaLoadTimeoutSeconds,
      'ollamaLoadRetries': value.ollamaLoadRetries,
      'ollamaKeepAliveMinutes': value.ollamaKeepAliveMinutes,
      'telemetryOptIn': value.telemetryOptIn,
      'telemetryRetentionDays': value.telemetryRetentionDays,
      'telemetryMaxBufferedEvents': value.telemetryMaxBufferedEvents,
      'hasOpenAiSecretReference': value.openAiApiKeyReferenceId.isNotEmpty,
    });
    await events.publish('settings.updated', 'settings', <String, dynamic>{
      'settings': value.toJson(),
    });
  }

  Future<List<ModelIdentity>> discoverModels() => models.discover();

  List<SkillPackage> listBuiltInSkills() => const SkillRegistry().all;

  Future<List<SkillCandidateRecord>> listSkillCandidates() =>
      skillPublication.listCandidates();

  Future<List<PublishedSkillRecord>> listPublishedSkills() =>
      skillPublication.listPublished();

  Future<FileInspectionResult> inspectFileAdapter(String path) =>
      fileAdapters.inspect(File(path));

  Future<Map<String, dynamic>> validateFileAdapter(String path) =>
      fileAdapters.validate(File(path));

  Future<PreparedCommand> prepare({
    required String projectId,
    required CommandMode mode,
    required String request,
    required ModelIdentity model,
  }) async {
    final project = await repositories.projects.get(projectId);
    if (project == null) {
      throw ProductException(
        'project_missing',
        'Select a valid active project.',
      );
    }
    return commandService.prepare(
      project: project,
      mode: mode,
      request: request,
      model: model,
    );
  }

  Future<RunRecord> createRun(
    String commandId, {
    AutonomyBudget? budget,
  }) async {
    final command = await repositories.commands.get(commandId);
    if (command == null) {
      throw ProductException('command_missing', 'Unknown prepared command.');
    }
    return runs.createRun(
      command,
      budget: budget ?? AutonomyBudget.forPlan(command.plan),
    );
  }

  Future<RunRecord> retryRun(String runId) => runs.retryRun(runId);

  Future<PermissionGrant> approve({
    required String runId,
    required Set<PermissionScope> scopes,
    Duration validity = const Duration(hours: 2),
  }) async {
    final run = await repositories.runs.get(runId);
    if (run == null) {
      throw ProductException('run_missing', 'Unknown run.');
    }
    final required = run.command.contract.requiredPermissions;
    if (!scopes.containsAll(required)) {
      throw ProductException(
        'permission_scope_missing',
        'Approval is missing a scope required by the command contract.',
      );
    }
    if (!required.containsAll(scopes)) {
      throw ProductException(
        'permission_scope_unrequested',
        'Approval contains a scope not requested by the command contract.',
      );
    }
    if (required.contains(PermissionScope.projectRead) &&
        !scopes.contains(PermissionScope.projectRead)) {
      throw ProductException(
        'permission_read_required',
        'Project read permission is required for this governed execution.',
      );
    }
    final grant = await permissions.grant(
      projectId: run.command.contract.projectId,
      commandId: run.command.id,
      scopes: scopes,
      validity: validity,
      uses: max(100, run.budget.maxToolCalls * 3),
    );
    await events.publish('run.approved', run.id, <String, dynamic>{
      'runId': run.id,
      'scopes': scopes.map((scope) => scope.name).toList(),
    });
    return grant;
  }

  Future<RunRecord> execute(String runId) => runs.execute(runId);
  Future<void> pause(String runId) => runs.pause(runId);
  Future<void> resume(String runId) => runs.resume(runId);
  Future<void> cancel(String runId) => runs.cancel(runId);

  Future<List<RunRecord>> listRuns({String? projectId, int limit = 100}) async {
    var runs = await repositories.runs.all();
    if (projectId != null) {
      runs = runs
          .where((run) => run.command.contract.projectId == projectId)
          .toList();
    }
    runs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return runs.take(limit).toList();
  }

  Future<RunRecord?> getRun(String id) => repositories.runs.get(id);

  Future<List<EvidenceRecord>> evidenceForRun(String runId) async {
    final evidence = (await repositories.evidence.all())
        .where((item) => item.runId == runId)
        .toList();
    evidence.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return evidence;
  }

  Future<List<KnowledgeEntry>> listKnowledge(String projectId) =>
      knowledge.list(projectId);

  Future<KnowledgeEntry> addKnowledge({
    required String projectId,
    required String title,
    required String content,
    Set<String> tags = const <String>{},
  }) =>
      knowledge.addNote(
        projectId: projectId,
        title: title,
        content: content,
        tags: tags,
      );

  Future<void> deleteKnowledge(String id) => knowledge.deleteEntry(id);

  Future<KnowledgeEntry> setKnowledgePinned(String id, bool pinned) async {
    final entry = await knowledge.setEntryPinned(id, pinned);
    await audit.append('knowledge.pin_changed', entry.id, <String, dynamic>{
      'knowledgeId': entry.id,
      'projectId': entry.projectId,
      'pinned': entry.pinned,
    });
    await events.publish(
      'knowledge.pin_changed',
      entry.projectId,
      <String, dynamic>{
        'knowledgeId': entry.id,
        'projectId': entry.projectId,
        'pinned': entry.pinned,
      },
    );
    return entry;
  }

  Future<MemoryEpisode> setMemoryPinned(String id, bool pinned) async {
    final episode = await knowledge.setEpisodePinned(id, pinned);
    await audit.append('memory.pin_changed', episode.id, <String, dynamic>{
      'episodeId': episode.id,
      'projectId': episode.projectId,
      'pinned': episode.pinned,
    });
    await events
        .publish('memory.pin_changed', episode.projectId, <String, dynamic>{
      'episodeId': episode.id,
      'projectId': episode.projectId,
      'pinned': episode.pinned,
    });
    return episode;
  }

  Future<List<ResearchArchiveRecord>> listResearchArchive(String projectId) =>
      knowledge.listArchives(projectId);

  Future<List<MemoryEpisode>> listMemoryEpisodes(String projectId) =>
      knowledge.listEpisodes(projectId);

  Future<KnowledgeRetrieval> searchKnowledge(
    String projectId,
    String query, {
    int limit = 12,
    bool includeEpisodes = true,
    bool includeUnsuccessfulEpisodes = false,
  }) =>
      knowledge.retrieve(
        projectId,
        query,
        limit: limit,
        includeEpisodes: includeEpisodes,
        includeUnsuccessfulEpisodes: includeUnsuccessfulEpisodes,
      );

  Future<KnowledgeStats> knowledgeStats(String projectId) =>
      knowledge.stats(projectId);

  Future<int> rebuildKnowledgeIndex(String projectId) async {
    final count = await knowledge.rebuildIndex(projectId);
    await audit.append('knowledge.index_rebuilt', projectId, <String, dynamic>{
      'projectId': projectId,
      'chunks': count,
    });
    await events.publish(
      'knowledge.index_rebuilt',
      projectId,
      <String, dynamic>{'projectId': projectId, 'chunks': count},
    );
    return count;
  }

  Future<File> exportKnowledge(String projectId) async {
    final file = await knowledge.exportPackage(projectId);
    await audit.append('knowledge.exported', projectId, <String, dynamic>{
      'projectId': projectId,
      'fileName': file.uri.pathSegments.last,
      'bytes': await file.length(),
      'sha256': Sha256.hex(await file.readAsBytes()),
    });
    await events.publish('knowledge.exported', projectId, <String, dynamic>{
      'projectId': projectId,
      'fileName': file.uri.pathSegments.last,
    });
    return file;
  }

  Future<List<PromptTemplateRecord>> listPrompts() async {
    final prompts = await repositories.prompts.all();
    prompts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return prompts;
  }

  Future<PromptTemplateRecord> savePrompt({
    String? id,
    required String title,
    required String description,
    required String systemPrompt,
    required String userPrompt,
    required List<String> variables,
    required Set<String> tags,
    required CommandMode mode,
  }) async {
    if (title.trim().isEmpty || userPrompt.trim().isEmpty) {
      throw ProductException(
        'prompt_invalid',
        'A prompt needs a title and user prompt.',
      );
    }
    final existing = id == null ? null : await repositories.prompts.get(id);
    final now = DateTime.now().toUtc();
    final prompt = PromptTemplateRecord(
      id: existing?.id ?? newId('prompt'),
      title: title.trim(),
      description: description.trim(),
      systemPrompt: systemPrompt.trim(),
      userPrompt: userPrompt.trim(),
      variables: variables
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort(),
      tags: tags
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toSet(),
      mode: mode,
      version: (existing?.version ?? 0) + 1,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await repositories.prompts.put(prompt);
    await audit.append('prompt.saved', prompt.id, <String, dynamic>{
      'promptId': prompt.id,
      'title': prompt.title,
      'version': prompt.version,
      'mode': prompt.mode.name,
      'variables': prompt.variables,
    });
    await events.publish('prompt.saved', prompt.id, <String, dynamic>{
      'prompt': prompt.toJson(),
    });
    return prompt;
  }

  Future<PromptClarificationSession> generatePromptClarification({
    required String goal,
    required ModelIdentity model,
    Future<void>? cancellation,
    bool Function()? isCancelled,
    void Function(ModelGenerationProgress progress)? onProgress,
    void Function(String delta)? onTextDelta,
  }) =>
      promptPlanning.generateClarification(
        goal: goal,
        model: model,
        cancellation: cancellation,
        isCancelled: isCancelled,
        onProgress: onProgress,
        onTextDelta: onTextDelta,
      );

  Future<PromptStudioDraft> generatePromptDraft({
    required String goal,
    required ModelIdentity model,
    PromptGenerationAction action = PromptGenerationAction.generate,
    PromptStudioDraft? current,
    String feedback = '',
    PromptClarificationSession? clarification,
    Map<String, String> clarificationAnswers = const <String, String>{},
    Future<void>? cancellation,
    bool Function()? isCancelled,
    void Function(ModelGenerationProgress progress)? onProgress,
    void Function(String delta)? onTextDelta,
  }) =>
      promptPlanning.generatePrompt(
        goal: goal,
        model: model,
        action: action,
        current: current,
        feedback: feedback,
        clarification: clarification,
        clarificationAnswers: clarificationAnswers,
        cancellation: cancellation,
        isCancelled: isCancelled,
        onProgress: onProgress,
        onTextDelta: onTextDelta,
      );

  Future<({PromptTemplateRecord prompt, PromptVersionRecord version})>
      saveGeneratedPrompt({
    String? id,
    required String goal,
    required PromptStudioDraft draft,
    required ModelIdentity model,
    PromptGenerationAction action = PromptGenerationAction.generate,
    String createdBy = 'model',
  }) async {
    final prompt = await savePrompt(
      id: id,
      title: draft.title,
      description: draft.purpose,
      systemPrompt: draft.systemPrompt,
      userPrompt: draft.userPrompt,
      variables: draft.variables,
      tags: <String>{'ai-generated', draft.mode.name},
      mode: draft.mode,
    );
    final version = await promptPlanning.savePromptVersion(
      promptId: prompt.id,
      sourceGoal: goal,
      action: action,
      draft: draft,
      model: model,
      createdBy: createdBy,
    );
    return (prompt: prompt, version: version);
  }

  Future<List<PromptVersionRecord>> listPromptVersions(String promptId) =>
      promptPlanning.listPromptVersions(promptId);

  Future<TaskPlanRecord> generateTaskPlan({
    required PromptVersionRecord promptVersion,
    required String projectId,
    required ModelIdentity model,
    PlanningDepth depth = PlanningDepth.auto,
    int maxLeafTasks = 25,
    Future<void>? cancellation,
    bool Function()? isCancelled,
    void Function(ModelGenerationProgress progress)? onProgress,
    void Function(String delta)? onTextDelta,
  }) =>
      promptPlanning.generateTaskPlan(
        promptVersion: promptVersion,
        projectId: projectId,
        model: model,
        depth: depth,
        maxLeafTasks: maxLeafTasks,
        cancellation: cancellation,
        isCancelled: isCancelled,
        onProgress: onProgress,
        onTextDelta: onTextDelta,
      );

  Future<List<TaskPlanRecord>> listTaskPlans({
    String? promptId,
    String? projectId,
  }) =>
      promptPlanning.listTaskPlans(promptId: promptId, projectId: projectId);

  Future<TaskPlanRecord> updateTaskPlan(
    TaskPlanRecord plan, {
    required List<PlanTaskRecord> tasks,
    String? title,
    String? rationale,
  }) =>
      promptPlanning.updateTaskPlan(
        plan,
        tasks: tasks,
        title: title,
        rationale: rationale,
      );

  Future<PreparedCommand> prepareTaskPlan({
    required TaskPlanRecord plan,
    required PromptVersionRecord promptVersion,
    required String projectId,
    required ModelIdentity model,
    Set<String>? selectedTaskIds,
  }) async {
    final project = await repositories.projects.get(projectId);
    if (project == null) {
      throw ProductException('project_missing', 'Select a valid project.');
    }
    return promptPlanning.compilePlan(
      plan: plan,
      promptVersion: promptVersion,
      project: project,
      model: model,
      selectedTaskIds: selectedTaskIds,
    );
  }

  Future<void> deletePrompt(String id) async {
    await repositories.prompts.remove(id);
    for (final version in (await repositories.promptVersions.all()).where(
      (item) => item.promptId == id,
    )) {
      await repositories.promptVersions.remove(version.id);
    }
    for (final plan in (await repositories.taskPlans.all()).where(
      (item) => item.promptId == id,
    )) {
      await repositories.taskPlans.remove(plan.id);
    }
    await audit.append('prompt.deleted', id, <String, dynamic>{'promptId': id});
    await events.publish('prompt.deleted', id, <String, dynamic>{
      'promptId': id,
    });
  }

  Future<ProjectDiagnosticReport> inspectProject(
    String projectId, {
    bool modelReady = false,
  }) async {
    final project = await repositories.projects.get(projectId);
    if (project == null) {
      throw ProductException('project_missing', 'Select a valid project.');
    }
    final report = await diagnostics.inspect(project, modelReady: modelReady);
    await events.publish('diagnostics.completed', project.id, <String, dynamic>{
      'projectId': project.id,
      'report': report.toJson(),
      'executedTests': false,
    });
    return report;
  }

  Future<ProjectDiagnosticReport> testProject(String projectId) async {
    final project = await repositories.projects.get(projectId);
    if (project == null) {
      throw ProductException('project_missing', 'Select a valid project.');
    }
    await events.publish('diagnostics.started', project.id, <String, dynamic>{
      'projectId': project.id,
      'kind': 'quick-tests',
    });
    final report = await diagnostics.runQuickTests(project);
    await events.publish('diagnostics.completed', project.id, <String, dynamic>{
      'projectId': project.id,
      'report': report.toJson(),
      'executedTests': true,
    });
    await audit.append('diagnostics.completed', project.id, <String, dynamic>{
      'projectId': project.id,
      'projectType': report.projectType,
      'passed': report.passed,
      'warnings': report.warnings,
      'failed': report.failed,
    });
    return report;
  }

  Future<ProjectDiagnosticReport> analyzeProject(String projectId) async {
    final project = await _requireProject(projectId);
    await events.publish(
      'project.analysis_started',
      project.id,
      <String, dynamic>{'projectId': project.id},
    );
    final report = await diagnostics.runAnalysis(project);
    final details = <String, dynamic>{
      'projectId': project.id,
      'projectType': report.projectType,
      'passed': report.passed,
      'warnings': report.warnings,
      'failed': report.failed,
      'analyzeCommand': report.analyzeCommand,
    };
    await audit.append('project.analysis_completed', project.id, details);
    await events.publish(
      'project.analysis_completed',
      project.id,
      <String, dynamic>{...details, 'report': report.toJson()},
    );
    return report;
  }

  Future<ProjectDiagnosticReport> buildProject(String projectId) async {
    final project = await _requireProject(projectId);
    await events.publish('project.build_started', project.id, <String, dynamic>{
      'projectId': project.id,
    });
    final report = await diagnostics.runBuild(project);
    final details = <String, dynamic>{
      'projectId': project.id,
      'projectType': report.projectType,
      'passed': report.passed,
      'warnings': report.warnings,
      'failed': report.failed,
      'buildCommand': report.buildCommand,
    };
    await audit.append('project.build_completed', project.id, details);
    await events.publish(
      'project.build_completed',
      project.id,
      <String, dynamic>{...details, 'report': report.toJson()},
    );
    return report;
  }

  Future<ProjectProcessStatus> startProject(String projectId) async {
    final project = await _requireProject(projectId);
    final existing = await projectProcessStatus(projectId);
    if (existing != null && existing.running) {
      return existing;
    }
    final profile = await diagnostics.executionProfile(project);
    final command = profile.runCommand;
    if (command == null) {
      throw ProductException(
        'project_run_unavailable',
        'No managed run command was detected. Add a run entry to kristin.project.json.',
      );
    }
    final executable = await diagnostics.resolveCommandExecutable(
      project,
      command,
    );
    if (executable == null) {
      throw ProductException(
        'project_run_tool_missing',
        '${command.executable} was not found.',
      );
    }
    final status = await managedProcesses.start(
      executable: executable,
      arguments: command.arguments,
      workingDirectory: project.rootPath,
      environment: diagnostics.commandEnvironment(command),
      runId: newId('project_session'),
      workItemId: 'project-manager-run',
    );
    final processId = status['id']?.toString() ?? '';
    if (processId.isEmpty) {
      throw ProductException(
        'project_process_invalid',
        'The managed project process did not return an identifier.',
      );
    }
    _projectProcessIds[project.id] = processId;
    final result = _projectProcessStatusFromMap(
      project: project,
      label: command.label,
      command: command.display,
      status: status,
    );
    final details = <String, dynamic>{
      'projectId': project.id,
      'processId': processId,
      'pid': result.pid,
      'command': command.display,
      'projectRootHash': Sha256.text(project.rootPath),
    };
    await audit.append('project.process_started', project.id, details);
    await events.publish('project.process_started', project.id, details);
    return result;
  }

  Future<ProjectProcessStatus?> projectProcessStatus(String projectId) async {
    final processId = _projectProcessIds[projectId];
    if (processId == null) {
      return null;
    }
    final project = await repositories.projects.get(projectId);
    if (project == null) {
      _projectProcessIds.remove(projectId);
      return null;
    }
    try {
      final profile = await diagnostics.executionProfile(project);
      final command = profile.runCommand;
      final status = await managedProcesses.status(processId);
      return _projectProcessStatusFromMap(
        project: project,
        label: command?.label ?? 'Project process',
        command: command?.display ?? '',
        status: status,
      );
    } on ProductException catch (error) {
      if (error.code == 'managed_process_missing') {
        _projectProcessIds.remove(projectId);
        return null;
      }
      rethrow;
    }
  }

  Future<ProjectProcessStatus?> stopProject(String projectId) async {
    final processId = _projectProcessIds[projectId];
    if (processId == null) {
      return null;
    }
    final project = await _requireProject(projectId);
    final profile = await diagnostics.executionProfile(project);
    final command = profile.runCommand;
    final status = await managedProcesses.stop(processId);
    final result = _projectProcessStatusFromMap(
      project: project,
      label: command?.label ?? 'Project process',
      command: command?.display ?? '',
      status: status,
    );
    final details = <String, dynamic>{
      'projectId': project.id,
      'processId': processId,
      'pid': result.pid,
      'exitCode': result.exitCode,
    };
    await audit.append('project.process_stopped', project.id, details);
    await events.publish('project.process_stopped', project.id, details);
    return result;
  }

  Future<ProjectRecord> _requireProject(String projectId) async {
    final project = await repositories.projects.get(projectId);
    if (project == null) {
      throw ProductException('project_missing', 'Select a valid project.');
    }
    return project;
  }

  ProjectProcessStatus _projectProcessStatusFromMap({
    required ProjectRecord project,
    required String label,
    required String command,
    required Map<String, dynamic> status,
  }) {
    DateTime parseDate(Object? value, {DateTime? fallback}) {
      return DateTime.tryParse(value?.toString() ?? '')?.toUtc() ??
          fallback ??
          DateTime.now().toUtc();
    }

    return ProjectProcessStatus(
      projectId: project.id,
      processId: status['id']?.toString() ?? '',
      label: label,
      command: command,
      pid: int.tryParse(status['pid']?.toString() ?? '') ?? 0,
      running: status['running'] == true,
      exitCode: status['exitCode'] == null
          ? null
          : int.tryParse(status['exitCode'].toString()),
      startedAt: parseDate(status['startedAt']),
      completedAt: status['completedAt'] == null
          ? null
          : parseDate(status['completedAt']),
      outputTail: redactor.redact(status['outputTail']?.toString() ?? ''),
      logFileName: status['logFileName']?.toString() ?? '',
    );
  }

  Future<SecretReference> registerSecretReference({
    required String label,
    required String environmentKey,
    String description = '',
  }) =>
      secrets.registerReference(
        label: label,
        environmentKey: environmentKey,
        description: description,
      );

  Future<List<SecretReference>> listSecretReferences() =>
      repositories.secretReferences.all();

  Future<McpTrustRecord> trustMcp({
    required String projectId,
    required String label,
    required String executablePath,
    required List<String> arguments,
    required Set<String> allowedTools,
    String protocolVersion = '2024-11-05',
    Duration validity = const Duration(days: 30),
  }) =>
      mcp.trust(
        projectId: projectId,
        label: label,
        executablePath: executablePath,
        arguments: arguments,
        allowedTools: allowedTools,
        protocolVersion: protocolVersion,
        validity: validity,
      );

  Future<List<McpTrustRecord>> listMcpTrust() => mcp.repository.all();
  Future<void> revokeMcpTrust(String id) => mcp.revoke(id);

  Future<IssuedToken> issueApiToken({
    required String label,
    required Set<String> scopes,
    String? projectId,
    Duration validity = const Duration(days: 30),
  }) =>
      tokens.issue(
        label: label,
        scopes: scopes,
        projectId: projectId,
        validity: validity,
      );

  Future<List<ApiTokenRecord>> listApiTokens() => repositories.tokens.all();
  Future<void> revokeApiToken(String id) => tokens.revoke(id);

  Future<Map<String, dynamic>> verifyAudit() => audit.verify();
  Future<File> createSupportBundle({
    String? projectId,
    String? runId,
    bool includeAllLogs = false,
  }) async {
    final file = await support.create(
      projectId: projectId,
      runId: runId,
      includeAllLogs: includeAllLogs,
    );
    final details = <String, dynamic>{
      'projectId': projectId,
      'runId': runId,
      'includeAllLogs': includeAllLogs,
      'fileName': file.uri.pathSegments.last,
      'pathHash': Sha256.text(file.path),
      'bytes': await file.length(),
      'sha256': Sha256.hex(await file.readAsBytes()),
    };
    await audit.append(
      'diagnostics.exported',
      runId ?? projectId ?? 'support',
      details,
    );
    await events.publish(
      'diagnostics.exported',
      runId ?? projectId ?? 'support',
      details,
    );
    return file;
  }
}
