enum ExternalEffectState {
  planned,
  authorized,
  started,
  observed,
  committed,
  compensated,
  unknown,
  reconciliationRequired,
}

extension ExternalEffectStateWire on ExternalEffectState {
  String get wireName => switch (this) {
        ExternalEffectState.planned => 'planned',
        ExternalEffectState.authorized => 'authorized',
        ExternalEffectState.started => 'started',
        ExternalEffectState.observed => 'observed',
        ExternalEffectState.committed => 'committed',
        ExternalEffectState.compensated => 'compensated',
        ExternalEffectState.unknown => 'unknown',
        ExternalEffectState.reconciliationRequired =>
          'reconciliation_required',
      };
}

class ExternalEffectTransition {
  const ExternalEffectTransition({
    required this.from,
    required this.to,
    required this.evidenceId,
    required this.recordedAt,
  });

  final ExternalEffectState from;
  final ExternalEffectState to;
  final String evidenceId;
  final DateTime recordedAt;

  Map<String, Object> toJson() => <String, Object>{
        'from': from.wireName,
        'to': to.wireName,
        'evidenceId': evidenceId,
        'recordedAt': recordedAt.toUtc().toIso8601String(),
      };
}

class ExternalEffectReceipt {
  ExternalEffectReceipt({
    required this.effectId,
    required this.idempotencyKey,
    this.initialState = ExternalEffectState.planned,
  }) : _state = initialState;

  final String effectId;
  final String idempotencyKey;
  final ExternalEffectState initialState;
  final List<ExternalEffectTransition> _transitions =
      <ExternalEffectTransition>[];
  ExternalEffectState _state;

  ExternalEffectState get state => _state;
  List<ExternalEffectTransition> get transitions =>
      List<ExternalEffectTransition>.unmodifiable(_transitions);

  bool get retryAllowed => switch (_state) {
        ExternalEffectState.planned || ExternalEffectState.authorized => true,
        _ => false,
      };

  bool get requiresReconciliation =>
      _state == ExternalEffectState.unknown ||
      _state == ExternalEffectState.reconciliationRequired;

  void transition(
    ExternalEffectState next, {
    required String evidenceId,
    required DateTime recordedAt,
  }) {
    if (evidenceId.trim().isEmpty) {
      throw StateError('external_effect_evidence_required');
    }
    if (!_allowed(_state, next)) {
      throw StateError(
        'external_effect_transition_invalid:${_state.wireName}->${next.wireName}',
      );
    }
    _transitions.add(
      ExternalEffectTransition(
        from: _state,
        to: next,
        evidenceId: evidenceId,
        recordedAt: recordedAt.toUtc(),
      ),
    );
    _state = next;
  }

  Map<String, Object> toJson() => <String, Object>{
        'schemaVersion': '1.0.0',
        'effectId': effectId,
        'idempotencyKey': idempotencyKey,
        'state': _state.wireName,
        'retryAllowed': retryAllowed,
        'requiresReconciliation': requiresReconciliation,
        'transitions': _transitions
            .map((transition) => transition.toJson())
            .toList(growable: false),
      };

  static bool _allowed(
    ExternalEffectState current,
    ExternalEffectState next,
  ) {
    return switch (current) {
      ExternalEffectState.planned =>
        next == ExternalEffectState.authorized,
      ExternalEffectState.authorized =>
        next == ExternalEffectState.started,
      ExternalEffectState.started =>
        next == ExternalEffectState.observed ||
            next == ExternalEffectState.unknown,
      ExternalEffectState.observed =>
        next == ExternalEffectState.committed ||
            next == ExternalEffectState.unknown,
      ExternalEffectState.committed =>
        next == ExternalEffectState.compensated,
      ExternalEffectState.unknown =>
        next == ExternalEffectState.reconciliationRequired,
      ExternalEffectState.reconciliationRequired =>
        next == ExternalEffectState.observed ||
            next == ExternalEffectState.committed ||
            next == ExternalEffectState.compensated,
      ExternalEffectState.compensated => false,
    };
  }
}
