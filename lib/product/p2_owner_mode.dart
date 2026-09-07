import 'dart:math';

enum P2OwnerApprovalPolicy {
  everyHighRiskEffect,
  destructiveOnly,
  boundedSession,
}

enum P2OwnerModeState { disabled, enabledInteractive, enabledUnattended }

class P2OwnerModeSettings {
  const P2OwnerModeSettings({
    required this.state,
    required this.approvalPolicy,
    required this.enabledAt,
    required this.dataBoundaryAcknowledged,
    this.sessionId,
    this.sessionExpiresAt,
  });
  final P2OwnerModeState state;
  final P2OwnerApprovalPolicy approvalPolicy;
  final DateTime? enabledAt;
  final String? sessionId;
  final DateTime? sessionExpiresAt;
  final bool dataBoundaryAcknowledged;
  bool get enabled => state != P2OwnerModeState.disabled;
  bool get unattended => state == P2OwnerModeState.enabledUnattended;
  String get accessProfileId => switch (state) {
        P2OwnerModeState.enabledUnattended => 'owner_unattended',
        P2OwnerModeState.enabledInteractive => 'owner',
        P2OwnerModeState.disabled => 'chat',
      };
  String get persistentIndicator =>
      enabled ? 'OWNER MODE — full current-account access' : 'Owner Mode off';
  String get safetyLabel => enabled
      ? 'Owner Mode is not a sandbox. Authorized effects can reach all resources available to this OS account.'
      : 'No Owner Mode host authority.';
  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': '1.1.0',
        'state': state.name,
        'approvalPolicy': approvalPolicy.name,
        'enabledAt': enabledAt?.toUtc().toIso8601String(),
        'sessionId': sessionId,
        'sessionExpiresAt': sessionExpiresAt?.toUtc().toIso8601String(),
        'dataBoundaryAcknowledged': dataBoundaryAcknowledged,
      };
  factory P2OwnerModeSettings.disabled() => const P2OwnerModeSettings(
        state: P2OwnerModeState.disabled,
        approvalPolicy: P2OwnerApprovalPolicy.boundedSession,
        enabledAt: null,
        dataBoundaryAcknowledged: false,
      );
  P2OwnerModeSettings reset() => P2OwnerModeSettings.disabled();
}

typedef P2OwnerModeEnableAuthorizer = Future<void> Function(
    P2OwnerModeSettings settings);

class P2OwnerModeController {
  P2OwnerModeController(
    this.persist,
    this.clear, {
    this.authorizeEnable,
    this.clearAuthorization,
  });
  final Future<void> Function(Map<String, Object?>) persist;
  final Future<void> Function() clear;
  final P2OwnerModeEnableAuthorizer? authorizeEnable;
  final Future<void> Function()? clearAuthorization;
  P2OwnerModeSettings current = P2OwnerModeSettings.disabled();
  static String _newSessionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return 'owner-session-${bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join()}';
  }

  Future<void> enable({
    required bool unattended,
    required P2OwnerApprovalPolicy approvalPolicy,
    required bool acknowledged,
    DateTime? expiresAt,
  }) async {
    if (!acknowledged) {
      throw StateError('owner_data_boundary_acknowledgement_required');
    }
    final now = DateTime.now().toUtc();
    final expiry = expiresAt?.toUtc() ??
        now.add(
          unattended ? const Duration(hours: 24) : const Duration(hours: 8),
        );
    if (!now.isBefore(expiry) ||
        expiry.difference(now) > const Duration(hours: 24)) {
      throw StateError('owner_session_expiry_invalid');
    }
    final next = P2OwnerModeSettings(
      state: unattended
          ? P2OwnerModeState.enabledUnattended
          : P2OwnerModeState.enabledInteractive,
      approvalPolicy: approvalPolicy,
      enabledAt: now,
      sessionId: _newSessionId(),
      sessionExpiresAt: expiry,
      dataBoundaryAcknowledged: true,
    );
    try {
      await authorizeEnable?.call(next);
      await persist(next.toJson());
      current = next;
    } catch (_) {
      await clearAuthorization?.call();
      rethrow;
    }
  }

  Future<void> disableAndReset() async {
    current = current.reset();
    try {
      await clearAuthorization?.call();
    } finally {
      await clear();
    }
  }
}
