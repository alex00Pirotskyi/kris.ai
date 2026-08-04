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
    this.sessionExpiresAt,
  });

  final P2OwnerModeState state;
  final P2OwnerApprovalPolicy approvalPolicy;
  final DateTime? enabledAt;
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
      ? 'Not a sandbox. Effects can reach all resources available to this OS account.'
      : 'No Owner Mode host authority.';

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': '1.0.0',
        'state': state.name,
        'approvalPolicy': approvalPolicy.name,
        'enabledAt': enabledAt?.toUtc().toIso8601String(),
        'sessionExpiresAt': sessionExpiresAt?.toUtc().toIso8601String(),
        'dataBoundaryAcknowledged': dataBoundaryAcknowledged,
      };

  factory P2OwnerModeSettings.disabled() => const P2OwnerModeSettings(
        state: P2OwnerModeState.disabled,
        approvalPolicy: P2OwnerApprovalPolicy.everyHighRiskEffect,
        enabledAt: null,
        dataBoundaryAcknowledged: false,
      );

  P2OwnerModeSettings reset() => P2OwnerModeSettings.disabled();
}

class P2OwnerModeController {
  P2OwnerModeController(this.persist, this.clear);

  final Future<void> Function(Map<String, Object?>) persist;
  final Future<void> Function() clear;

  P2OwnerModeSettings current = P2OwnerModeSettings.disabled();

  Future<void> enable({
    required bool unattended,
    required P2OwnerApprovalPolicy approvalPolicy,
    required bool acknowledged,
    DateTime? expiresAt,
  }) async {
    if (!acknowledged) {
      throw StateError('owner_data_boundary_acknowledgement_required');
    }
    current = P2OwnerModeSettings(
      state: unattended
          ? P2OwnerModeState.enabledUnattended
          : P2OwnerModeState.enabledInteractive,
      approvalPolicy: approvalPolicy,
      enabledAt: DateTime.now().toUtc(),
      sessionExpiresAt: expiresAt?.toUtc(),
      dataBoundaryAcknowledged: true,
    );
    await persist(current.toJson());
  }

  Future<void> disableAndReset() async {
    current = current.reset();
    await clear();
  }
}
