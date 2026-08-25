import 'dart:async';
import 'dart:io';

import 'application_runtime_provisioner.dart';
import 'browser/browser_runtime.dart';
import 'browser/browser_runtime_bundle.dart';
import 'domain.dart';
import 'p2_product_runtime_bootstrap.dart';
import 'product_runtime.dart';
import 'research/research_browser_adapter.dart';

final Expando<_ProductRuntimeProvisioningState> _runtimeProvisioningStates =
    Expando<_ProductRuntimeProvisioningState>('kristin-runtime-provisioning');

extension ProductRuntimeProvisioning on ProductRuntime {
  _ProductRuntimeProvisioningState get _runtimeProvisioningState {
    final existing = _runtimeProvisioningStates[this];
    if (existing != null) return existing;
    final created = _ProductRuntimeProvisioningState(
      runtime: this,
      provisioner: ApplicationRuntimeProvisioner(
        applicationDataRoot: directories.root,
      ),
      ownerMode: p2OwnerMode,
      browserInitiallyReady: p3BrowserRuntime.available,
    );
    _runtimeProvisioningStates[this] = created;
    _attachProvisionedResearchBrowser(this);
    return created;
  }

  Stream<ApplicationRuntimeProvisioningProgress>
      get runtimeProvisioningProgress =>
          _runtimeProvisioningState.provisioner.progress;

  P2ProductRuntimeOwnerModeHandle get provisionedOwnerMode =>
      _runtimeProvisioningState.ownerMode;

  bool get browserRuntimePrepared =>
      _runtimeProvisioningState.browserInitiallyReady ||
      _runtimeProvisioningState.browserResources != null;

  Future<P2ProductRuntimeOwnerModeHandle> ensureOwnerModeReady({
    bool repair = false,
  }) {
    final state = _runtimeProvisioningState;
    if (state.ownerMode.available && !repair) {
      return Future<P2ProductRuntimeOwnerModeHandle>.value(state.ownerMode);
    }
    final inFlight = state.ownerInFlight;
    if (inFlight != null) return inFlight;
    late final Future<P2ProductRuntimeOwnerModeHandle> operation;
    operation = _ensureOwnerModeReady(state, repair: repair).whenComplete(() {
      if (identical(state.ownerInFlight, operation)) state.ownerInFlight = null;
    });
    state.ownerInFlight = operation;
    return operation;
  }

  Future<P3BrowserRuntimeResourceSet> ensureBrowserRuntimeReady({
    bool repair = false,
  }) {
    final state = _runtimeProvisioningState;
    final existing = state.browserResources;
    if (existing != null && !repair) {
      return Future<P3BrowserRuntimeResourceSet>.value(existing);
    }
    final inFlight = state.browserInFlight;
    if (inFlight != null) return inFlight;
    late final Future<P3BrowserRuntimeResourceSet> operation;
    operation =
        _ensureBrowserRuntimeReady(state, repair: repair).whenComplete(() {
      if (identical(state.browserInFlight, operation)) {
        state.browserInFlight = null;
      }
    });
    state.browserInFlight = operation;
    return operation;
  }

  Future<P3BrowserSessionProcess> startProvisionedBrowserSessions({
    required Directory stateDirectory,
    P3BrowserSessionQuotas quotas = const P3BrowserSessionQuotas(),
    Duration startupTimeout = const Duration(seconds: 30),
    Duration requestTimeout = const Duration(seconds: 60),
  }) async {
    await ensureBrowserRuntimeReady();
    return P3BrowserRuntimeService(
      applicationDataRoot: directories.root,
    ).startSessions(
      stateDirectory: stateDirectory,
      quotas: quotas,
      startupTimeout: startupTimeout,
      requestTimeout: requestTimeout,
    );
  }

  Future<void> closeRuntimeProvisioning() async {
    final state = _runtimeProvisioningStates[this];
    if (state == null) return;
    final owner = state.ownerInFlight;
    if (owner != null) {
      try {
        await owner;
      } catch (_) {}
    }
    final browser = state.browserInFlight;
    if (browser != null) {
      try {
        await browser;
      } catch (_) {}
    }
    final provisionedOwner = state.ownerMode;
    if (!identical(provisionedOwner, p2OwnerMode)) {
      try {
        await provisionedOwner.close();
      } catch (_) {}
    }
    await state.provisioner.close();
    _runtimeProvisioningStates[this] = null;
  }

  Future<P2ProductRuntimeOwnerModeHandle> _ensureOwnerModeReady(
    _ProductRuntimeProvisioningState state, {
    required bool repair,
  }) async {
    final resources = await state.provisioner.ensureP2(
      currentAccountRequired: p1AuthorityService == null,
      repair: repair,
    );
    final handle = await P2ProductRuntimeBootstrap.start(
      dataRoot: directories.root,
      p1AuthorityService: p1AuthorityService,
      runtimeResources: resources,
    );
    if (!handle.available) {
      await handle.close();
      throw StateError(handle.diagnosticCode);
    }
    final previous = state.ownerMode;
    state.ownerMode = handle;
    if (previous.available && !identical(previous.runtime, handle.runtime)) {
      await previous.close();
    }
    return handle;
  }

  Future<P3BrowserRuntimeResourceSet> _ensureBrowserRuntimeReady(
    _ProductRuntimeProvisioningState state, {
    required bool repair,
  }) async {
    final resources = await state.provisioner.ensureP3(repair: repair);
    state.browserResources = resources;
    state.browserInitiallyReady = true;
    return resources;
  }
}

void _attachProvisionedResearchBrowser(ProductRuntime runtime) {
  final browserAware = runtime.research;
  if (browserAware is P4BrowserAwareResearchService) {
    browserAware.attachRenderedPageLoader(
      (url) => _renderWithProvisionedBrowser(runtime, url),
    );
  }
}

Future<P3BrowserPageObservation> _renderWithProvisionedBrowser(
  ProductRuntime runtime,
  Uri url,
) async {
  await runtime.ensureBrowserRuntimeReady();
  final stateDirectory = Directory(
    '${runtime.directories.cache.path}${Platform.pathSeparator}'
    'rendered-research-${newId('browser')}',
  );
  await stateDirectory.create(recursive: true);
  P3BrowserSessionProcess? process;
  String? sessionId;
  String? pageId;
  try {
    process = await P3BrowserRuntimeService(
      applicationDataRoot: runtime.directories.root,
    ).startSessions(
      stateDirectory: stateDirectory,
      quotas: const P3BrowserSessionQuotas(
        maxSessions: 1,
        maxPagesPerSession: 1,
        maxPersistentProfiles: 1,
      ),
      startupTimeout: const Duration(seconds: 30),
      requestTimeout: const Duration(seconds: 45),
    );
    final session = await process.openSession(
      kind: P3BrowserSessionKind.ephemeral,
      blockServiceWorkers: true,
    );
    sessionId = session.sessionId;
    final page = await process.openPage(sessionId);
    pageId = page.pageId;
    return process.navigatePublicPage(
      sessionId,
      pageId,
      P3BrowserPublicNavigationRequest(url: url.toString()),
    );
  } finally {
    final active = process;
    if (active != null) {
      if (sessionId != null && pageId != null) {
        try {
          await active.closePage(sessionId, pageId);
        } catch (_) {}
      }
      if (sessionId != null) {
        try {
          await active.closeSession(sessionId);
        } catch (_) {}
      }
      try {
        await active.close();
      } catch (_) {}
    }
    try {
      if (await stateDirectory.exists()) {
        await stateDirectory.delete(recursive: true);
      }
    } catch (_) {}
  }
}

final class _ProductRuntimeProvisioningState {
  _ProductRuntimeProvisioningState({
    required this.runtime,
    required this.provisioner,
    required this.ownerMode,
    required this.browserInitiallyReady,
  });

  final ProductRuntime runtime;
  final ApplicationRuntimeProvisioner provisioner;
  P2ProductRuntimeOwnerModeHandle ownerMode;
  bool browserInitiallyReady;
  P3BrowserRuntimeResourceSet? browserResources;
  Future<P2ProductRuntimeOwnerModeHandle>? ownerInFlight;
  Future<P3BrowserRuntimeResourceSet>? browserInFlight;
}
