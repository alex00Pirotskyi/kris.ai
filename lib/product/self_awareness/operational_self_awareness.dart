import 'dart:async';

import '../crypto_utils.dart';
import 'capability_self_model.dart';

enum CausalNodeKind { action, stateChange, observation, failure, recovery }

enum CausalEdgeKind { caused, preceded, observedAfter, recoveredBy, correlated }

final class CausalNode {
  CausalNode({
    String? id,
    DateTime? observedAt,
    required this.kind,
    required this.label,
    this.attributes = const <String, Object?>{},
    this.evidenceReferences = const <String>[],
  }) : id = id ?? newId('causal'),
       observedAt = observedAt ?? DateTime.now().toUtc();

  final String id;
  final DateTime observedAt;
  final CausalNodeKind kind;
  final String label;
  final Map<String, Object?> attributes;
  final List<String> evidenceReferences;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'observedAt': observedAt.toIso8601String(),
    'kind': kind.name,
    'label': label,
    'attributes': attributes,
    'evidenceReferences': evidenceReferences,
  };
}

final class CausalEdge {
  const CausalEdge({
    required this.from,
    required this.to,
    required this.kind,
    this.confidence = ObservationConfidence.medium,
    this.reason = '',
  });

  final String from;
  final String to;
  final CausalEdgeKind kind;
  final ObservationConfidence confidence;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'from': from,
    'to': to,
    'kind': kind.name,
    'confidence': confidence.name,
    if (reason.isNotEmpty) 'reason': reason,
  };
}

/// Bounded evidence graph. Causal edges are hypotheses with confidence, not
/// authority or proof, and therefore cannot authorize a repair on their own.
final class CausalStateGraph {
  CausalStateGraph({this.maxNodes = 256, this.maxEdges = 512});

  final int maxNodes;
  final int maxEdges;
  final List<CausalNode> _nodes = <CausalNode>[];
  final List<CausalEdge> _edges = <CausalEdge>[];

  List<CausalNode> get nodes => List<CausalNode>.unmodifiable(_nodes);
  List<CausalEdge> get edges => List<CausalEdge>.unmodifiable(_edges);

  CausalNode record(
    CausalNode node, {
    Iterable<String> causedBy = const <String>[],
    CausalEdgeKind edgeKind = CausalEdgeKind.caused,
    ObservationConfidence confidence = ObservationConfidence.medium,
    String reason = '',
  }) {
    _nodes.add(node);
    for (final parent in causedBy) {
      if (_nodes.any((candidate) => candidate.id == parent)) {
        _edges.add(
          CausalEdge(
            from: parent,
            to: node.id,
            kind: edgeKind,
            confidence: confidence,
            reason: reason,
          ),
        );
      }
    }
    _trim();
    return node;
  }

  CausalNode recordAction(
    String label, {
    Map<String, Object?> attributes = const <String, Object?>{},
    List<String> evidenceReferences = const <String>[],
  }) => record(
    CausalNode(
      kind: CausalNodeKind.action,
      label: label,
      attributes: attributes,
      evidenceReferences: evidenceReferences,
    ),
  );

  CausalNode recordStateChange(
    String label, {
    Iterable<String> causedBy = const <String>[],
    Map<String, Object?> attributes = const <String, Object?>{},
    ObservationConfidence confidence = ObservationConfidence.high,
  }) => record(
    CausalNode(
      kind: CausalNodeKind.stateChange,
      label: label,
      attributes: attributes,
    ),
    causedBy: causedBy,
    confidence: confidence,
  );

  CausalNode recordObservation(
    String label, {
    Iterable<String> observedAfter = const <String>[],
    Map<String, Object?> attributes = const <String, Object?>{},
    ObservationConfidence confidence = ObservationConfidence.high,
  }) => record(
    CausalNode(
      kind: CausalNodeKind.observation,
      label: label,
      attributes: attributes,
    ),
    causedBy: observedAfter,
    edgeKind: CausalEdgeKind.observedAfter,
    confidence: confidence,
  );

  CausalNode recordFailure(
    String label, {
    Iterable<String> causedBy = const <String>[],
    Map<String, Object?> attributes = const <String, Object?>{},
    List<String> evidenceReferences = const <String>[],
    ObservationConfidence confidence = ObservationConfidence.medium,
  }) => record(
    CausalNode(
      kind: CausalNodeKind.failure,
      label: label,
      attributes: attributes,
      evidenceReferences: evidenceReferences,
    ),
    causedBy: causedBy,
    confidence: confidence,
  );

  CausalNode recordRecovery(
    String label, {
    Iterable<String> recovers = const <String>[],
    Map<String, Object?> attributes = const <String, Object?>{},
  }) => record(
    CausalNode(
      kind: CausalNodeKind.recovery,
      label: label,
      attributes: attributes,
    ),
    causedBy: recovers,
    edgeKind: CausalEdgeKind.recoveredBy,
    confidence: ObservationConfidence.high,
  );

  List<CausalNode> likelyCauses(String nodeId, {int maxDepth = 3}) {
    final result = <CausalNode>[];
    final visited = <String>{nodeId};
    var frontier = <String>{nodeId};
    for (var depth = 0; depth < maxDepth && frontier.isNotEmpty; depth++) {
      final next = <String>{};
      for (final edge in _edges.reversed) {
        if (!frontier.contains(edge.to) || visited.contains(edge.from))
          continue;
        visited.add(edge.from);
        next.add(edge.from);
        final node = _nodes
            .where((candidate) => candidate.id == edge.from)
            .firstOrNull;
        if (node != null) result.add(node);
      }
      frontier = next;
    }
    return List<CausalNode>.unmodifiable(result);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'nodes': _nodes.map((node) => node.toJson()).toList(),
    'edges': _edges.map((edge) => edge.toJson()).toList(),
  };

  void _trim() {
    while (_nodes.length > maxNodes) {
      final removed = _nodes.removeAt(0);
      _edges.removeWhere(
        (edge) => edge.from == removed.id || edge.to == removed.id,
      );
    }
    if (_edges.length > maxEdges) {
      _edges.removeRange(0, _edges.length - maxEdges);
    }
  }
}

enum SelfInvariantSeverity { advisory, warning, critical }

final class SelfInvariant {
  const SelfInvariant({
    required this.id,
    required this.description,
    required this.evaluate,
    this.severity = SelfInvariantSeverity.critical,
  });

  final String id;
  final String description;
  final SelfInvariantSeverity severity;
  final String? Function(KristinSelfSnapshot snapshot) evaluate;
}

final class SelfInvariantViolation {
  const SelfInvariantViolation({
    required this.invariantId,
    required this.severity,
    required this.message,
    required this.observedAt,
  });

  final String invariantId;
  final SelfInvariantSeverity severity;
  final String message;
  final DateTime observedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'invariantId': invariantId,
    'severity': severity.name,
    'message': message,
    'observedAt': observedAt.toIso8601String(),
  };
}

final class SelfIntegrityMonitor {
  const SelfIntegrityMonitor(this.invariants);

  final List<SelfInvariant> invariants;

  List<SelfInvariantViolation> checkSnapshot(KristinSelfSnapshot snapshot) {
    final now = DateTime.now().toUtc();
    final violations = <SelfInvariantViolation>[];
    for (final invariant in invariants) {
      final message = invariant.evaluate(snapshot);
      if (message == null || message.trim().isEmpty) continue;
      violations.add(
        SelfInvariantViolation(
          invariantId: invariant.id,
          severity: invariant.severity,
          message: message,
          observedAt: now,
        ),
      );
    }
    return List<SelfInvariantViolation>.unmodifiable(violations);
  }
}

List<SelfInvariant> defaultKristinSelfInvariants() => <SelfInvariant>[
  SelfInvariant(
    id: 'coordinator_never_runner_tool',
    description:
        'Coordinator capabilities must never be represented as exact Runner tools.',
    evaluate: (snapshot) {
      final invalid = snapshot.capabilities
          .where(
            (item) =>
                item.descriptor.coordinator &&
                item.descriptor.runnerToolName != null,
          )
          .map((item) => item.descriptor.id)
          .toList();
      return invalid.isEmpty
          ? null
          : 'Coordinator capability/Runner-tool boundary violated by: ${invalid.join(', ')}.';
    },
  ),
  SelfInvariant(
    id: 'owner_capability_never_self_grants',
    description:
        'Owner capabilities cannot be usable unless authority was evaluated and granted.',
    evaluate: (snapshot) {
      final invalid = snapshot.capabilities
          .where((item) {
            if (item.descriptor.authorityClass !=
                CapabilityAuthorityClass.owner) {
              return false;
            }
            return item.operationallyUsable &&
                item.availability.authorityObservation !=
                    AuthorityObservationState.granted;
          })
          .map((item) => item.descriptor.id)
          .toList();
      return invalid.isEmpty
          ? null
          : 'Owner authority would be implied without a real grant for: ${invalid.join(', ')}.';
    },
  ),
  SelfInvariant(
    id: 'browser_truth_matches_runtime',
    description:
        'Browser-dependent capabilities cannot be usable when Browser is absent.',
    evaluate: (snapshot) {
      if (snapshot.application.browser['available'] == true) return null;
      final invalid = snapshot.capabilities
          .where(
            (item) =>
                item.descriptor.browserRequired && item.operationallyUsable,
          )
          .map((item) => item.descriptor.id)
          .toList();
      return invalid.isEmpty
          ? null
          : 'Browser-required capabilities report usable while Browser is unavailable: ${invalid.join(', ')}.';
    },
  ),
  SelfInvariant(
    id: 'selected_project_is_known',
    description:
        'A selected project must resolve to the current project repository snapshot.',
    severity: SelfInvariantSeverity.warning,
    evaluate: (snapshot) {
      final selected = snapshot.application.selectedProject?['id']?.toString();
      if (selected == null || selected.isEmpty) return null;
      final known = snapshot.application.knownProjects.any(
        (project) => project['id']?.toString() == selected,
      );
      return known
          ? null
          : 'Selected project $selected is not present in the current project snapshot.';
    },
  ),
  SelfInvariant(
    id: 'selected_model_is_live',
    description:
        'A selected model used for planning must be present in fresh provider discovery.',
    severity: SelfInvariantSeverity.warning,
    evaluate: (snapshot) {
      final selected = snapshot.application.selectedModel;
      if (selected == null) return null;
      return selected['discovered'] == true
          ? null
          : 'Selected model ${selected['exactId']} is not present in fresh provider discovery.';
    },
  ),
  SelfInvariant(
    id: 'failing_health_not_plannable',
    description:
        'Capabilities with failing health cannot be exposed as operationally usable.',
    evaluate: (snapshot) {
      final invalid = snapshot.capabilities
          .where(
            (item) =>
                item.health?.state == CapabilityHealthState.failing &&
                item.operationallyUsable,
          )
          .map((item) => item.descriptor.id)
          .toList();
      return invalid.isEmpty
          ? null
          : 'Failing capabilities are still plannable: ${invalid.join(', ')}.';
    },
  ),
];

enum ProbeStatus { healthy, degraded, failing, skipped }

final class SelfConsistencyProbeResult {
  SelfConsistencyProbeResult({
    required this.probeId,
    required this.status,
    required this.message,
    this.capabilityIds = const <String>{},
    this.evidenceReferences = const <String>[],
    this.attributes = const <String, Object?>{},
    DateTime? observedAt,
    this.validFor = const Duration(seconds: 30),
    this.latency,
  }) : observedAt = observedAt ?? DateTime.now().toUtc();

  final String probeId;
  final Set<String> capabilityIds;
  final ProbeStatus status;
  final String message;
  final DateTime observedAt;
  final Duration validFor;
  final Duration? latency;
  final List<String> evidenceReferences;
  final Map<String, Object?> attributes;

  Iterable<CapabilityHealth> toCapabilityHealth() sync* {
    final state = switch (status) {
      ProbeStatus.healthy => CapabilityHealthState.healthy,
      ProbeStatus.degraded => CapabilityHealthState.degraded,
      ProbeStatus.failing => CapabilityHealthState.failing,
      ProbeStatus.skipped => CapabilityHealthState.unknown,
    };
    for (final capabilityId in capabilityIds) {
      yield CapabilityHealth(
        capabilityId: capabilityId,
        state: state,
        reasons: <String>[message],
        observedAt: observedAt,
        lastVerifiedAt: status == ProbeStatus.skipped ? null : observedAt,
        expiresAt: observedAt.add(validFor),
        evidence: <KnowledgeEvidence>[
          KnowledgeEvidence(
            kind: KnowledgeEvidenceKind.observed,
            source: 'self_consistency_probe:$probeId',
            confidence: status == ProbeStatus.skipped
                ? ObservationConfidence.unknown
                : ObservationConfidence.high,
            observedAt: observedAt,
            expiresAt: observedAt.add(validFor),
            detail: message,
          ),
        ],
        latency: latency,
      );
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'probeId': probeId,
    'capabilityIds': capabilityIds.toList()..sort(),
    'status': status.name,
    'message': message,
    'observedAt': observedAt.toIso8601String(),
    'validForMs': validFor.inMilliseconds,
    if (latency != null) 'latencyMs': latency!.inMilliseconds,
    'evidenceReferences': evidenceReferences,
    'attributes': attributes,
  };
}

abstract interface class SelfConsistencyProbe {
  String get id;
  Duration get interval;
  bool applies(SelfModelSessionOverlay overlay);
  Future<SelfConsistencyProbeResult> run(
    KristinSelfSnapshot snapshot,
    SelfModelSessionOverlay overlay,
  );
}

final class CallbackSelfConsistencyProbe implements SelfConsistencyProbe {
  const CallbackSelfConsistencyProbe({
    required this.id,
    required this.interval,
    required this.callback,
    this.appliesTo,
  });

  @override
  final String id;
  @override
  final Duration interval;
  final bool Function(SelfModelSessionOverlay overlay)? appliesTo;
  final Future<SelfConsistencyProbeResult> Function(
    KristinSelfSnapshot snapshot,
    SelfModelSessionOverlay overlay,
  )
  callback;

  @override
  bool applies(SelfModelSessionOverlay overlay) =>
      appliesTo?.call(overlay) ?? true;

  @override
  Future<SelfConsistencyProbeResult> run(
    KristinSelfSnapshot snapshot,
    SelfModelSessionOverlay overlay,
  ) => callback(snapshot, overlay);
}

/// Bounded observation-only monitor. It determines which probes are due before
/// snapshotting, so a five-second scheduler does not poll all providers every
/// five seconds. Probe outcomes are then published into one post-probe model
/// refresh so failures cannot disappear without ever becoming model-visible.
final class SelfConsistencyMonitor {
  SelfConsistencyMonitor({
    required this.selfModel,
    required this.probes,
    this.onResult,
  });

  final KristinSelfModelService selfModel;
  final List<SelfConsistencyProbe> probes;
  final Future<void> Function(SelfConsistencyProbeResult result)? onResult;
  final Map<String, DateTime> _lastRun = <String, DateTime>{};
  bool _running = false;
  Timer? _timer;

  Future<List<SelfConsistencyProbeResult>> runDue({
    bool force = false,
    SelfModelSessionOverlay overlay = const SelfModelSessionOverlay(),
  }) async {
    if (_running) return const <SelfConsistencyProbeResult>[];
    final now = DateTime.now().toUtc();
    final due = probes
        .where((probe) {
          if (!probe.applies(overlay)) return false;
          final key = '${overlay.cacheKey}|${probe.id}';
          final last = _lastRun[key];
          return force ||
              last == null ||
              now.difference(last) >= probe.interval;
        })
        .toList(growable: false);
    if (due.isEmpty) return const <SelfConsistencyProbeResult>[];

    _running = true;
    try {
      final snapshot = await selfModel.snapshot(
        source: 'self_consistency_monitor',
        reason: 'probe_context',
        overlay: overlay,
      );
      final results = <SelfConsistencyProbeResult>[];
      for (final probe in due) {
        final result = await probe.run(snapshot, overlay);
        _lastRun['${overlay.cacheKey}|${probe.id}'] = result.observedAt;
        results.add(result);
        for (final health in result.toCapabilityHealth()) {
          selfModel.recordHealthObservation(health, overlay: overlay);
        }
        if (onResult != null) await onResult!(result);
      }
      if (results.isNotEmpty) {
        await selfModel.notifyStateChanged(
          source: 'self_consistency_monitor',
          reason: 'probe_results_updated',
          overlay: overlay,
        );
      }
      return List<SelfConsistencyProbeResult>.unmodifiable(results);
    } finally {
      _running = false;
    }
  }

  void start({Duration tick = const Duration(seconds: 5)}) {
    if (_timer != null) return;
    _timer = Timer.periodic(tick, (_) {
      unawaited(runDue());
    });
  }

  Future<void> close() async {
    _timer?.cancel();
    _timer = null;
  }
}
