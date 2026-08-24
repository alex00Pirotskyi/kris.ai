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
        ExternalEffectState.reconciliationRequired => 'reconciliation_required',
      };

  static ExternalEffectState parse(String value) => switch (value) {
        'planned' => ExternalEffectState.planned,
        'authorized' => ExternalEffectState.authorized,
        'started' => ExternalEffectState.started,
        'observed' => ExternalEffectState.observed,
        'committed' => ExternalEffectState.committed,
        'compensated' => ExternalEffectState.compensated,
        'unknown' => ExternalEffectState.unknown,
        'reconciliation_required' => ExternalEffectState.reconciliationRequired,
        _ => throw const FormatException('external_effect_state_invalid'),
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

  factory ExternalEffectTransition.fromJson(Map<String, Object?> json) {
    final evidenceId = json['evidenceId']?.toString().trim() ?? '';
    final recordedAt =
        DateTime.tryParse(json['recordedAt']?.toString() ?? '')?.toUtc();
    if (evidenceId.isEmpty || recordedAt == null) {
      throw const FormatException('external_effect_transition_invalid');
    }
    return ExternalEffectTransition(
      from: ExternalEffectStateWire.parse(json['from']?.toString() ?? ''),
      to: ExternalEffectStateWire.parse(json['to']?.toString() ?? ''),
      evidenceId: evidenceId,
      recordedAt: recordedAt,
    );
  }
}

class ExternalEffectReceipt {
  ExternalEffectReceipt({
    required this.effectId,
    required this.idempotencyKey,
    this.initialState = ExternalEffectState.planned,
  }) : _state = initialState {
    if (effectId.trim().isEmpty || idempotencyKey.trim().isEmpty) {
      throw StateError('external_effect_identity_required');
    }
  }

  factory ExternalEffectReceipt.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != '1.0.0') {
      throw const FormatException('external_effect_schema_invalid');
    }
    final effectId = json['effectId']?.toString().trim() ?? '';
    final idempotencyKey = json['idempotencyKey']?.toString().trim() ?? '';
    final rawTransitions = json['transitions'];
    if (effectId.isEmpty || idempotencyKey.isEmpty || rawTransitions is! List) {
      throw const FormatException('external_effect_receipt_invalid');
    }
    final receipt = ExternalEffectReceipt(
      effectId: effectId,
      idempotencyKey: idempotencyKey,
    );
    for (final raw in rawTransitions) {
      if (raw is! Map) {
        throw const FormatException('external_effect_transition_invalid');
      }
      final transition = ExternalEffectTransition.fromJson(
        <String, Object?>{
          for (final entry in raw.entries) entry.key.toString(): entry.value,
        },
      );
      if (transition.from != receipt.state) {
        throw const FormatException('external_effect_transition_chain_invalid');
      }
      receipt.transition(
        transition.to,
        evidenceId: transition.evidenceId,
        recordedAt: transition.recordedAt,
      );
    }
    if (receipt.state.wireName != json['state']?.toString()) {
      throw const FormatException('external_effect_state_mismatch');
    }
    return receipt;
  }

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
      ExternalEffectState.planned => next == ExternalEffectState.authorized,
      ExternalEffectState.authorized => next == ExternalEffectState.started,
      ExternalEffectState.started => next == ExternalEffectState.observed ||
          next == ExternalEffectState.unknown,
      ExternalEffectState.observed => next == ExternalEffectState.committed ||
          next == ExternalEffectState.unknown,
      ExternalEffectState.committed => next == ExternalEffectState.compensated,
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
