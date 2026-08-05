import 'p2_effect_boundary.dart';
import 'p2_effect_journal.dart';

enum P2SupportStatus {
  supported,
  unsupported,
  approvalRequired,
  unavailable,
  blocked,
  unknown,
}

class P2OperationSupport {
  const P2OperationSupport(
    this.status,
    this.reason, {
    this.requiresElevation = false,
  });

  final P2SupportStatus status;
  final String reason;
  final bool requiresElevation;
}

class P2HostOperationResult {
  const P2HostOperationResult({
    required this.status,
    required this.receipt,
    required this.support,
    this.output = const <String, Object?>{},
  });

  final P2EffectStatus status;
  final P2EffectReceipt receipt;
  final P2OperationSupport support;
  final Map<String, Object?> output;
}

abstract interface class P2HostOperationAuthorizer {
  Future<void> authorize(
    P2EffectBinding binding,
    String operation,
    Map<String, Object?> scope,
  );
}

abstract interface class P2PackageSdkAdapter {
  Future<P2OperationSupport> support(String operation);
  Future<Map<String, Object?>> plan(
    String manager,
    String operation,
    List<String> packages,
    P2EffectBinding binding,
  );
  Future<P2HostOperationResult> apply(
    Map<String, Object?> plan,
    P2EffectBinding binding,
  );
  Future<List<Map<String, Object?>>> discoverSdks(P2EffectBinding binding);
}

abstract interface class P2ServiceApplicationAdapter {
  Future<Map<String, P2OperationSupport>> supportMatrix();
  Future<P2HostOperationResult> serviceStatus(
    String id,
    P2EffectBinding binding,
  );
  Future<P2HostOperationResult> serviceStart(
    String id,
    P2EffectBinding binding,
  );
  Future<P2HostOperationResult> serviceStop(String id, P2EffectBinding binding);
  Future<P2HostOperationResult> applicationOpen(
    String target,
    P2EffectBinding binding,
  );
  Future<P2HostOperationResult> applicationClose(
    String identity,
    P2EffectBinding binding,
  );
}

abstract interface class P2ClipboardScreenAdapter {
  Future<P2OperationSupport> clipboardSupport();
  Future<P2OperationSupport> screenSupport();
  Future<String> readClipboard(P2EffectBinding binding);
  Future<void> writeClipboard(String text, P2EffectBinding binding);
  Future<List<int>> captureScreen(
    P2EffectBinding binding, {
    List<Map<String, int>> redactionZones = const <Map<String, int>>[],
  });
  Future<Map<String, Object?>> activeWindowMetadata(P2EffectBinding binding);
}

/// Production implementations must cross the authenticated automation-host
/// boundary. The concrete implementation is [P2AutomationHostOperations] in
/// `p2_automation_host_operations.dart`; this file intentionally contains only
/// shared typed contracts and cannot perform direct helper-only host effects.
