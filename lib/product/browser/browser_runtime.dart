import 'dart:io';

import 'browser_runtime_bundle.dart';
import 'browser_runtime_process.dart';

final class P3BrowserRuntimeProbeResult {
  const P3BrowserRuntimeProbeResult({
    required this.ready,
    required this.bundleProvenance,
  });

  final P3BrowserRuntimeReady ready;
  final Map<String, Object?> bundleProvenance;

  Map<String, Object?> get provenance => <String, Object?>{
        ...bundleProvenance,
        'probeWorkerPid': ready.pid,
        'probeBrowserPid': ready.browserPid,
        'browserEngine': ready.browserEngine,
        'browserVersion': ready.browserVersion,
        'browserRevision': ready.browserRevision,
        'protocol': ready.protocol,
        'p3_002SessionServiceImplemented': false,
      };
}

/// Application-side P3-001 entry point.
///
/// It proves that the pinned bundled Node worker can launch the pinned browser
/// executable and terminate cleanly. Persistent browser sessions are a P3-002
/// responsibility and are intentionally not exposed here.
final class P3BrowserRuntimeService {
  P3BrowserRuntimeService({
    required Directory applicationDataRoot,
    String? executablePath,
  }) : _resolver = P3ApplicationOwnedBrowserRuntimeResolver(
          applicationDataRoot: applicationDataRoot,
          executablePath: executablePath,
        );

  P3BrowserRuntimeService.withResolver(this._resolver);

  final P3ApplicationOwnedBrowserRuntimeResolver _resolver;

  Future<P3BrowserRuntimeResourceSet> resolveBundle() => _resolver.resolve();

  Future<P3BrowserRuntimeProbeResult> probe({
    required Directory stateDirectory,
    Duration startupTimeout = const Duration(seconds: 30),
  }) async {
    final resources = await resolveBundle();
    final process = await P3BrowserRuntimeProcess.start(
      resources: resources,
      stateDirectory: stateDirectory,
      startupTimeout: startupTimeout,
    );
    try {
      return P3BrowserRuntimeProbeResult(
        ready: process.ready,
        bundleProvenance: resources.provenance,
      );
    } finally {
      await process.close();
    }
  }
}
