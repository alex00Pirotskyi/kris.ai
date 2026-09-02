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
  })  : id = id ?? newId('causal'),
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

/// Bounded causal graph for operational reasoning.
///
/// Edges are evidence-bearing hypotheses, not proof. That distinction matters:
/// recovery may use the graph to rank likely causes, but authority and repair
/// policy remain separate gates.
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
        _edges.add(CausalEdge(
          from: parent,
          to: node.id,
          kind: edgeKind,
          confidence: confidence,
          reason: reason,
        ));
      }
    }
    _trim();
    return node;
  }

  CausalNode recordAction(
    String label, {
    Map<String, Object?> attributes = const <String, Object?>{},
    List<String> evidenceReferences = const <String>[],
  }) =>
      record(CausalNode(
        kind: CausalNodeKind.action,
        label: label,
        attributes: attributes,
        evidenceReferences: evidenceReferences,
      ));

  CausalNode recordStateChange(
    String label, {
    Iterable<String> causedBy = const <String>[],
    Map<String, Object?> attributes = const <String, Object?>{},
    ObservationConfidence confidence = ObservationConfidence.high,
  }) =>
      record(
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
  }) =>
      record(
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
  }) =>
      record(
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
  }) =>
      record(
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
        if (!frontier.contains(edge.to) || visited.contains(edge.from)) continue;
        visited.add(edge.from);
        next.add(edge.from);
        final node = _nodes.where((candidate) => candidate.id == edge.from).firstOrNull;
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
      _edges.removeWhere((edge) => edge.from == removed.id || edge.to == removed.id);
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
      violations.add(SelfInvariantViolation(
        invariantId: invariant.id,
        severity: invariant.severity,
        message: message,
        observedAt: now,
      ));
    }
    return List<SelfInvariantViolation>.unmodifiable(violations);
  }
}

List<SelfInvariant> defaultKristinSelfInvariants() => <SelfInvariant>[
      SelfInvariant(
        id: 'coordinator_never_direct_runner_tool',
        description: 'Coordinator capabilities must never be marked directly executable.',
        evaluate: (snapshot) {
          final invalid = snapshot.capabilities
              .where((item) => item.descriptor.coordinator && item.descriptor.directlyExecutable)
              .map((item) => item.descriptor.id)
              .toList();
          return invalid.isEmpty
              ? null
              : 'Coordinator capability/direct-execution boundary violated by: ${invalid.join(', ')}.';
        },
      ),
      SelfInvariant(
        id: 'owner_capability_never_self_grants',
        description: 'Owner capabilities cannot be operationally usable without observed Owner authority.',
        evaluate: (snapshot) {
          final invalid = snapshot.capabilities.where((item) {
            if (item.descriptor.authorityClass != CapabilityAuthorityClass.owner) return false;
            return item.operationallyUsable && !item.availability.currentAuthority.contains('owner');
          }).map((item) => item.descriptor.id).toList();
          return invalid.isEmpty
              ? null
              : 'Owner authority would be implied without a real grant for: ${invalid.join(', ')}.';
        },
      ),
      SelfInvariant(
        id: 'browser_truth_matches_runtime',
        description: 'Browser-dependent capabilities cannot be usable when the Browser runtime is absent.',
        evaluate: (snapshot) {
          if (snapshot.application.browser['available'] == true) return null;
          final invalid = snapshot.capabilities
              .where((item) => item.descriptor.browserRequired && item.operationallyUsable)
              .map((item) => item.descriptor.id)
              .toList();
          return invalid.isEmpty
              ? null
              : 'Browser-required capabilities report usable while Browser is unavailable: ${invalid.join(', ')}.';
        },
      ),
      SelfInvariant(
        id: 'selected_project_is_known',
        description: 'A selected project must resolve to the current project repository snapshot.',
        severity: SelfInvariantSeverity.warning,
        evaluate: (snapshot) {
          final selected = snapshot.application.selectedProject?['id']?.toString();
          if (selected == null || selected.isEmpty) return null;
          final known = snapshot.application.knownProjects
              .any((project) => project['id']?.toString() == selected);
          return known ? null : 'Selected project $selected is not present in the current project snapshot.';
        },
      ),
      SelfInvariant(
        id: 'failing_health_not_plannable',
        description: 'Capabilities with failing health cannot be exposed as operationally usable.',
        evaluate: (snapshot) {
          final invalid = snapshot.capabilities
              .where((item) => item.health?.state == CapabilityHealthState.failing && item.operationallyUsable)
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
    this.capabilityId,
    this.evidenceReferences = const <String>[],
    this.attributes = const <String, Object?>{},
    DateTime? observedAt,
    this.latency,
  }) : observedAt = observedAt ?? DateTime.now().toUtc();

  final String probeId;
  final String? capabilityId;
  final ProbeStatus status;
  final String message;
  final DateTime observedAt;
  final Duration? latency;
  final List<String> evidenceReferences;
  final Map<String, Object?> attributes;

  CapabilityHealth? toCapabilityHealth() {
    final id = capabilityId;
    if (id == null) return null;
    final state = switch (status) {
      ProbeStatus.healthy => CapabilityHealthState.healthy,
      ProbeStatus.degraded => CapabilityHealthState.degraded,
      ProbeStatus.failing => CapabilityHealthState.failing,
      ProbeStatus.skipped => CapabilityHealthState.unknown,
    };
    return CapabilityHealth(
      capabilityId: id,
      state: state,
      reasons: <String>[message],
      observedAt: observedAt,
      lastVerifiedAt: status == ProbeStatus.skipped ? null : observedAt,
      evidence: <KnowledgeEvidence>[
        KnowledgeEvidence(
          kind: KnowledgeEvidenceKind.observed,
          source: 'self_consistency_probe:$probeId',
          confidence: status == ProbeStatus.skipped
              ? ObservationConfidence.unknown
              : ObservationConfidence.high,
          observedAt: observedAt,
          detail: message,
        ),
      ],
      latency: latency,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'probeId': probeId,
        if (capabilityId != null) 'capabilityId': capabilityId,
        'status': status.name,
        'message': message,
        'observedAt': observedAt.toIso8601String(),
        if (latency != null) 'latencyMs': latency!.inMilliseconds,
        'evidenceReferences': evidenceReferences,
        'attributes': attributes,
      };
}

abstract interface class SelfConsistencyProbe {
  String get id;
  Duration get interval;
  Future<SelfConsistencyProbeResult> run(KristinSelfSnapshot snapshot);
}

final class CallbackSelfConsistencyProbe implements SelfConsistencyProbe {
  const CallbackSelfConsistencyProbe({
    required this.id,
    required this.interval,
    required this.callback,
  });

  @override
  final String id;
  @override
  final Duration interval;
  final Future<SelfConsistencyProbeResult> Function(KristinSelfSnapshot snapshot) callback;

  @override
  Future<SelfConsistencyProbeResult> run(KristinSelfSnapshot snapshot) => callback(snapshot);
}

/// Runs bounded read-only probes and feeds their observations back into the
/// self-model. The monitor has no authority-granting or recovery actuator API.
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

  Future<List<SelfConsistencyProbeResult>> runDue({bool force = false}) async {
    if (_running) return const <SelfConsistencyProbeResult>[];
    _running = true;
    try {
      final snapshot = await selfModel.snapshot(
        source: 'self_consistency_monitor',
        reason: 'probe_context',
      );
      final now = DateTime.now().toUtc();
      final results = <SelfConsistencyProbeResult>[];
      for (final probe in probes) {
        final last = _lastRun[probe.id];
        if (!force && last != null && now.difference(last) < probe.interval) {
          continue;
        }
        final result = await probe.run(snapshot);
        _lastRun[probe.id] = result.observedAt;
        results.add(result);
        final health = result.toCapabilityHealth();
        if (health != null) selfModel.recordHealthObservation(health);
        if (onResult != null) await onResult!(result);
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
