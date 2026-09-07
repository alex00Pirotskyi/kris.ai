// Behavioural proof for the evidence gate on sensitive capabilities.
//
// Operational usability is not one question but four independent ones:
//
//   knowledge  -- Kristin knows the capability exists
//   availability -- the runtime for it is actually up
//   evidence   -- how directly and how confidently that was observed
//   authority  -- someone actually granted permission to use it
//
// For a sensitive or destructive capability the evidence gate additionally
// demands a single witness that is *itself* both directly observed and at
// least *high* confidence. Inference, cache and hearsay are knowledge, not
// proof, and a capability Kristin merely believes is present must not be
// reported as usable.
//
// The witness must be atomic. Asking "is any item direct?" and "is any item
// high-confidence?" separately lets an inferred-but-certain item supply the
// confidence while an observed-but-low item supplies the directness --
// composing a claim no single observation supports. That is the same defect
// shape as pooling separate permission grants into one stronger authority
// envelope, and it fails closed here for the same reason.
//
// This rule materially affects capability truthfulness -- the first real
// execution of this subsystem showed a fixture tripping it -- but it had no
// direct coverage. These tests pin it, and pin that satisfying it grants
// nothing else: evidence is not availability, and evidence is certainly not
// authority.

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/self_awareness/capability_self_model.dart';

CapabilityDescriptor _sensitive(
  String id, {
  CapabilityRiskClass riskClass = CapabilityRiskClass.sensitive,
}) =>
    CapabilityDescriptor(
      id: id,
      name: id,
      description: 'test capability $id',
      category: 'test',
      authorityClass: CapabilityAuthorityClass.owner,
      riskClass: riskClass,
      directlyExecutable: false,
      providerId: 'p1',
      permissionRequirements: const <String>{},
      freshnessBudget: const Duration(days: 3650),
      healthFreshnessBudget: const Duration(days: 3650),
    );

KnowledgeEvidence _evidence({
  required KnowledgeEvidenceKind kind,
  required ObservationConfidence confidence,
  required DateTime observedAt,
}) =>
    KnowledgeEvidence(
      kind: kind,
      source: 'test',
      confidence: confidence,
      observedAt: observedAt,
    );

/// Builds a capability that is available and healthy, so the only variables
/// under test are the evidence and the authority observation.
KnownCapability _capability({
  required DateTime now,
  required List<KnowledgeEvidence> evidence,
  AuthorityObservationState authority = AuthorityObservationState.granted,
  CapabilityAvailabilityState state = CapabilityAvailabilityState.available,
  CapabilityRiskClass riskClass = CapabilityRiskClass.sensitive,
  Set<String> requiredAuthority = const <String>{'owner.session'},
  Set<String> currentAuthority = const <String>{'owner.session'},
}) =>
    KnownCapability(
      descriptor: _sensitive('owner.reset', riskClass: riskClass),
      availability: CapabilityAvailability(
        capabilityId: 'owner.reset',
        state: state,
        requiredAuthority: requiredAuthority,
        currentAuthority: currentAuthority,
        authorityObservation: authority,
        observedAt: now,
        evidence: evidence,
      ),
      health: CapabilityHealth(
        capabilityId: 'owner.reset',
        state: CapabilityHealthState.healthy,
        observedAt: now,
        evidence: evidence,
      ),
    );

void main() {
  late DateTime now;

  setUp(() {
    now = DateTime.now().toUtc();
  });

  group('a sensitive capability demands direct, high-confidence evidence', () {
    test('directly observed high-confidence evidence satisfies the gate', () {
      final capability = _capability(
        now: now,
        evidence: <KnowledgeEvidence>[
          _evidence(
            kind: KnowledgeEvidenceKind.observed,
            confidence: ObservationConfidence.high,
            observedAt: now,
          ),
        ],
      );
      expect(capability.operationallyUsableAt(now), isTrue);
    });

    test('configured evidence counts as directly observed', () {
      final capability = _capability(
        now: now,
        evidence: <KnowledgeEvidence>[
          _evidence(
            kind: KnowledgeEvidenceKind.configured,
            confidence: ObservationConfidence.certain,
            observedAt: now,
          ),
        ],
      );
      expect(capability.operationallyUsableAt(now), isTrue);
    });

    test('medium-confidence evidence does not make it usable', () {
      final capability = _capability(
        now: now,
        evidence: <KnowledgeEvidence>[
          _evidence(
            kind: KnowledgeEvidenceKind.observed,
            confidence: ObservationConfidence.medium,
            observedAt: now,
          ),
        ],
      );
      expect(
        capability.operationallyUsableAt(now),
        isFalse,
        reason: 'medium is the KnowledgeEvidence default, so a caller that '
            'never states its confidence must not clear a sensitive gate',
      );
    });

    test('low and unknown confidence do not make it usable', () {
      for (final confidence in <ObservationConfidence>[
        ObservationConfidence.low,
        ObservationConfidence.unknown,
      ]) {
        final capability = _capability(
          now: now,
          evidence: <KnowledgeEvidence>[
            _evidence(
              kind: KnowledgeEvidenceKind.observed,
              confidence: confidence,
              observedAt: now,
            ),
          ],
        );
        expect(
          capability.operationallyUsableAt(now),
          isFalse,
          reason: '$confidence must not clear a sensitive gate',
        );
      }
    });

    test(
      'indirect evidence does not satisfy a direct-evidence requirement, '
      'however confident it is',
      () {
        for (final kind in <KnowledgeEvidenceKind>[
          KnowledgeEvidenceKind.inferred,
          KnowledgeEvidenceKind.cached,
          KnowledgeEvidenceKind.unknown,
        ]) {
          final capability = _capability(
            now: now,
            evidence: <KnowledgeEvidence>[
              _evidence(
                kind: kind,
                confidence: ObservationConfidence.certain,
                observedAt: now,
              ),
            ],
          );
          expect(
            capability.operationallyUsableAt(now),
            isFalse,
            reason: 'certainty about an inference is not direct observation '
                '($kind)',
          );
        }
      },
    );

    test('no evidence at all does not make it usable', () {
      final capability = _capability(now: now, evidence: <KnowledgeEvidence>[]);
      expect(capability.operationallyUsableAt(now), isFalse);
    });

    test('directly observed certain-confidence evidence satisfies the gate',
        () {
      final capability = _capability(
        now: now,
        evidence: <KnowledgeEvidence>[
          _evidence(
            kind: KnowledgeEvidenceKind.observed,
            confidence: ObservationConfidence.certain,
            observedAt: now,
          ),
        ],
      );
      expect(capability.operationallyUsableAt(now), isTrue);
    });

    test('configured evidence at high confidence satisfies the gate', () {
      final capability = _capability(
        now: now,
        evidence: <KnowledgeEvidence>[
          _evidence(
            kind: KnowledgeEvidenceKind.configured,
            confidence: ObservationConfidence.high,
            observedAt: now,
          ),
        ],
      );
      expect(capability.operationallyUsableAt(now), isTrue);
    });
  });

  group('directness and confidence must come from the same witness', () {
    test(
      'a certain inference plus a low direct observation is refused',
      () {
        // The set contains a directly observed item, and the set's strongest
        // confidence is `certain` -- but no single observation is both. The
        // gate must read one witness, not the union of two.
        final capability = _capability(
          now: now,
          evidence: <KnowledgeEvidence>[
            _evidence(
              kind: KnowledgeEvidenceKind.inferred,
              confidence: ObservationConfidence.certain,
              observedAt: now,
            ),
            _evidence(
              kind: KnowledgeEvidenceKind.observed,
              confidence: ObservationConfidence.low,
              observedAt: now,
            ),
          ],
        );
        expect(
          capability.operationallyUsableAt(now),
          isFalse,
          reason: 'nothing directly observed was ever high-confidence',
        );
      },
    );

    test('a certain cache plus a medium configuration is refused', () {
      final capability = _capability(
        now: now,
        evidence: <KnowledgeEvidence>[
          _evidence(
            kind: KnowledgeEvidenceKind.cached,
            confidence: ObservationConfidence.certain,
            observedAt: now,
          ),
          _evidence(
            kind: KnowledgeEvidenceKind.configured,
            confidence: ObservationConfidence.medium,
            observedAt: now,
          ),
        ],
      );
      expect(capability.operationallyUsableAt(now), isFalse);
    });

    test(
      'a qualifying witness still passes when weaker evidence sits beside it',
      () {
        // The observed/high item satisfies the gate on its own, so unrelated
        // indirect evidence in the same set neither helps nor harms.
        final capability = _capability(
          now: now,
          evidence: <KnowledgeEvidence>[
            _evidence(
              kind: KnowledgeEvidenceKind.observed,
              confidence: ObservationConfidence.high,
              observedAt: now,
            ),
            _evidence(
              kind: KnowledgeEvidenceKind.inferred,
              confidence: ObservationConfidence.certain,
              observedAt: now,
            ),
          ],
        );
        expect(capability.operationallyUsableAt(now), isTrue);
      },
    );

    test('every direct item being sub-high is refused, however many there are',
        () {
      final capability = _capability(
        now: now,
        evidence: <KnowledgeEvidence>[
          _evidence(
            kind: KnowledgeEvidenceKind.observed,
            confidence: ObservationConfidence.medium,
            observedAt: now,
          ),
          _evidence(
            kind: KnowledgeEvidenceKind.configured,
            confidence: ObservationConfidence.low,
            observedAt: now,
          ),
          _evidence(
            kind: KnowledgeEvidenceKind.inferred,
            confidence: ObservationConfidence.certain,
            observedAt: now,
          ),
        ],
      );
      expect(capability.operationallyUsableAt(now), isFalse);
    });

    test('a destructive capability follows the same paired-witness rule', () {
      final mixed = _capability(
        now: now,
        riskClass: CapabilityRiskClass.destructive,
        evidence: <KnowledgeEvidence>[
          _evidence(
            kind: KnowledgeEvidenceKind.inferred,
            confidence: ObservationConfidence.certain,
            observedAt: now,
          ),
          _evidence(
            kind: KnowledgeEvidenceKind.observed,
            confidence: ObservationConfidence.low,
            observedAt: now,
          ),
        ],
      );
      expect(mixed.operationallyUsableAt(now), isFalse);

      final paired = _capability(
        now: now,
        riskClass: CapabilityRiskClass.destructive,
        evidence: <KnowledgeEvidence>[
          _evidence(
            kind: KnowledgeEvidenceKind.observed,
            confidence: ObservationConfidence.high,
            observedAt: now,
          ),
        ],
      );
      expect(paired.operationallyUsableAt(now), isTrue);
    });
  });

  group('the rest of the sensitive gate', () {
    test('a destructive capability is held to the same evidence bar', () {
      final weak = _capability(
        now: now,
        riskClass: CapabilityRiskClass.destructive,
        evidence: <KnowledgeEvidence>[
          _evidence(
            kind: KnowledgeEvidenceKind.observed,
            confidence: ObservationConfidence.medium,
            observedAt: now,
          ),
        ],
      );
      expect(weak.operationallyUsableAt(now), isFalse);
    });

    test('a read-only capability is not held to the sensitive bar', () {
      final capability = _capability(
        now: now,
        riskClass: CapabilityRiskClass.readOnly,
        evidence: <KnowledgeEvidence>[
          _evidence(
            kind: KnowledgeEvidenceKind.inferred,
            confidence: ObservationConfidence.medium,
            observedAt: now,
          ),
        ],
      );
      expect(
        capability.operationallyUsableAt(now),
        isTrue,
        reason: 'the high-confidence direct-evidence bar is specific to '
            'sensitive and destructive work, not a universal tax',
      );
    });
  });

  group('evidence, availability and authority remain separate gates', () {
    final strong = <KnowledgeEvidence>[];

    setUp(() {
      strong
        ..clear()
        ..add(
          _evidence(
            kind: KnowledgeEvidenceKind.observed,
            confidence: ObservationConfidence.high,
            observedAt: DateTime.now().toUtc(),
          ),
        );
    });

    test('satisfying the evidence gate does not satisfy authority', () {
      for (final observation in <AuthorityObservationState>[
        AuthorityObservationState.notEvaluated,
        AuthorityObservationState.absent,
      ]) {
        final capability = _capability(
          now: now,
          evidence: strong,
          authority: observation,
          currentAuthority: const <String>{},
        );
        expect(
          capability.operationallyUsableAt(now),
          isFalse,
          reason: 'proof that the runtime is up is not permission to use it '
              '($observation)',
        );
      }
    });

    test('satisfying evidence and authority does not satisfy availability', () {
      final capability = _capability(
        now: now,
        evidence: strong,
        state: CapabilityAvailabilityState.runtimeMissing,
      );
      expect(
        capability.operationallyUsableAt(now),
        isFalse,
        reason: 'a granted, well-evidenced capability whose runtime is absent '
            'is still not usable',
      );
    });

    test(
      'all three together are required, and removing any one closes the gate',
      () {
        final open = _capability(now: now, evidence: strong);
        expect(open.operationallyUsableAt(now), isTrue);

        expect(
          _capability(
            now: now,
            evidence: strong,
            authority: AuthorityObservationState.absent,
            currentAuthority: const <String>{},
          ).operationallyUsableAt(now),
          isFalse,
        );
        expect(
          _capability(
            now: now,
            evidence: strong,
            state: CapabilityAvailabilityState.unavailable,
          ).operationallyUsableAt(now),
          isFalse,
        );
        expect(
          _capability(
            now: now,
            evidence: <KnowledgeEvidence>[
              _evidence(
                kind: KnowledgeEvidenceKind.observed,
                confidence: ObservationConfidence.medium,
                observedAt: now,
              ),
            ],
          ).operationallyUsableAt(now),
          isFalse,
        );
      },
    );

    test(
      'authority is read from the observation, never synthesised from evidence',
      () {
        // currentAuthority is populated but the observation says it was never
        // evaluated: the model must believe the observation, not the payload.
        final capability = _capability(
          now: now,
          evidence: strong,
          authority: AuthorityObservationState.notEvaluated,
          currentAuthority: const <String>{'owner.session'},
        );
        expect(capability.operationallyUsableAt(now), isFalse);
      },
    );
  });
}
