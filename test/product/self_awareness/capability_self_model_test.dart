// Behavioural proof for the Kristin self-model.
//
// These tests exist to show the architecture cannot violate its safety
// properties. The central one is the separation the whole design rests on:
//
//   knowledge != availability != authority != executable tool
//
// A model learning that a capability exists must not gain permission to use
// it; a runtime coming up must not mint authority; and nothing the self-model
// reports may add a Runner tool to a task.

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/self_awareness/capability_self_model.dart';

/// A capability provider whose descriptors and availability are supplied by the
/// test, so each invariant is exercised against stated inputs rather than
/// whatever the live application happens to report.
class _FakeProvider implements KristinCapabilityProvider {
  _FakeProvider(
    this.providerId,
    this._descriptors, {
    Map<String, CapabilityAvailability>? availability,
  }) : _availability = availability ?? <String, CapabilityAvailability>{};

  @override
  final String providerId;
  final List<CapabilityDescriptor> _descriptors;
  final Map<String, CapabilityAvailability> _availability;

  @override
  Iterable<CapabilityDescriptor> describeCapabilities() => _descriptors;

  @override
  Future<CapabilityAvailability> resolveAvailability(
    CapabilityDescriptor descriptor,
    ApplicationSnapshot snapshot,
  ) async {
    return _availability[descriptor.id] ??
        CapabilityAvailability(
          capabilityId: descriptor.id,
          state: CapabilityAvailabilityState.available,
          observedAt: DateTime.now().toUtc(),
          evidence: <KnowledgeEvidence>[
            KnowledgeEvidence(
              kind: KnowledgeEvidenceKind.observed,
              source: 'test',
            ),
          ],
        );
  }
}

class _FakeApplication implements ApplicationSnapshotProvider {
  _FakeApplication(this.snapshot);
  ApplicationSnapshot snapshot;
  int captures = 0;

  @override
  Future<ApplicationSnapshot> capture({
    bool forceRefresh = false,
    SelfModelSessionOverlay overlay = const SelfModelSessionOverlay(),
  }) async {
    captures += 1;
    return snapshot;
  }
}

ApplicationSnapshot _app({
  String platform = 'linux',
  Map<String, Object?>? selectedProject,
  Map<String, Object?>? selectedModel,
  List<Map<String, Object?>> providers = const <Map<String, Object?>>[],
  List<Map<String, Object?>> knownProjects = const <Map<String, Object?>>[],
  List<Map<String, Object?>> processes = const <Map<String, Object?>>[],
  Map<String, Object?> browser = const <String, Object?>{},
  Map<String, Object?> ownerMode = const <String, Object?>{},
  Map<String, Object?> authority = const <String, Object?>{},
  Map<String, Object?> runState = const <String, Object?>{},
}) {
  return ApplicationSnapshot(
    capturedAt: DateTime.utc(2026, 1, 1),
    applicationIdentity: 'kris.ai',
    platform: platform,
    selectedProject: selectedProject,
    selectedModel: selectedModel,
    providers: providers,
    knownProjects: knownProjects,
    processes: processes,
    browser: browser,
    ownerMode: ownerMode,
    authority: authority,
    runState: runState,
  );
}

CapabilityDescriptor _descriptor(
  String id, {
  CapabilityAuthorityClass authorityClass = CapabilityAuthorityClass.governed,
  CapabilityRiskClass riskClass = CapabilityRiskClass.readOnly,
  bool directlyExecutable = false,
  String? runnerToolName,
  String providerId = 'p1',
  Set<String> permissionRequirements = const <String>{},
}) {
  return CapabilityDescriptor(
    id: id,
    name: id,
    description: 'test capability $id',
    category: 'test',
    authorityClass: authorityClass,
    riskClass: riskClass,
    directlyExecutable: directlyExecutable,
    runnerToolName: runnerToolName,
    providerId: providerId,
    permissionRequirements: permissionRequirements,
    freshnessBudget: const Duration(days: 3650),
    healthFreshnessBudget: const Duration(days: 3650),
  );
}

KristinSelfModelService _service(
  List<KristinCapabilityProvider> providers,
  ApplicationSnapshot app, {
  int maxDetailedCapabilities = 12,
}) {
  final registry = KristinCapabilityRegistry();
  for (final provider in providers) {
    registry.register(provider);
  }
  return KristinSelfModelService(
    registry: registry,
    application: _FakeApplication(app),
    maxDetailedCapabilities: maxDetailedCapabilities,
  );
}

void main() {
  group('registry integrity', () {
    test('duplicate provider ids are rejected', () {
      final registry = KristinCapabilityRegistry();
      registry.register(_FakeProvider('dup', <CapabilityDescriptor>[]));
      expect(
        () => registry.register(_FakeProvider('dup', <CapabilityDescriptor>[])),
        throwsA(isA<StateError>()),
      );
    });

    test('duplicate capability ids across providers are rejected', () async {
      final service = _service(<KristinCapabilityProvider>[
        _FakeProvider('p1', <CapabilityDescriptor>[_descriptor('same.id')]),
        _FakeProvider('p2', <CapabilityDescriptor>[_descriptor('same.id')]),
      ], _app());
      await expectLater(service.snapshot(), throwsA(isA<StateError>()));
    });

    test('enumeration is ordered by id, not by insertion order', () async {
      final forward = _service(<KristinCapabilityProvider>[
        _FakeProvider('p1', <CapabilityDescriptor>[
          _descriptor('c.charlie'),
          _descriptor('a.alpha'),
        ]),
        _FakeProvider('p2', <CapabilityDescriptor>[_descriptor('b.bravo')]),
      ], _app());
      final reverse = _service(<KristinCapabilityProvider>[
        _FakeProvider('p2', <CapabilityDescriptor>[_descriptor('b.bravo')]),
        _FakeProvider('p1', <CapabilityDescriptor>[
          _descriptor('a.alpha'),
          _descriptor('c.charlie'),
        ]),
      ], _app());

      final a = await forward.snapshot();
      final b = await reverse.snapshot();
      final idsA = a.capabilities
          .map((item) => item.descriptor.id)
          .toList(growable: false);
      final idsB = b.capabilities
          .map((item) => item.descriptor.id)
          .toList(growable: false);
      expect(idsA, <String>['a.alpha', 'b.bravo', 'c.charlie']);
      expect(idsB, idsA);
    });
  });

  group('bounded, deterministic serialization', () {
    test('equivalent runtime state serializes identically', () async {
      final first = _service(<KristinCapabilityProvider>[
        _FakeProvider('p1', <CapabilityDescriptor>[
          _descriptor('a'),
          _descriptor('b'),
        ]),
      ], _app());
      final second = _service(<KristinCapabilityProvider>[
        _FakeProvider('p1', <CapabilityDescriptor>[
          _descriptor('b'),
          _descriptor('a'),
        ]),
      ], _app());

      final one = (await first.snapshot()).application.semanticJson();
      final two = (await second.snapshot()).application.semanticJson();
      expect(one.toString(), two.toString());
    });

    test('planning context bounds the detailed capability list', () async {
      final many = <CapabilityDescriptor>[
        for (var i = 0; i < 40; i++)
          _descriptor('cap.${i.toString().padLeft(3, '0')}'),
      ];
      final service = _service(<KristinCapabilityProvider>[
        _FakeProvider('p1', many),
      ], _app(), maxDetailedCapabilities: 5);

      final context = await service.planningContext();
      expect(context.relevantCapabilities.length, 5);
      expect(context.freshnessWarnings.length, lessThanOrEqualTo(12));
    });

    test('oversized application state cannot explode the summary', () async {
      final projects = <Map<String, Object?>>[
        for (var i = 0; i < 500; i++)
          <String, Object?>{'id': 'p$i', 'name': 'project $i'},
      ];
      final processes = <Map<String, Object?>>[
        for (var i = 0; i < 500; i++)
          <String, Object?>{'pid': i, 'name': 'proc $i'},
      ];
      final service = _service(<KristinCapabilityProvider>[
        _FakeProvider('p1', <CapabilityDescriptor>[_descriptor('a')]),
      ], _app(knownProjects: projects, processes: processes));

      final snapshot = await service.snapshot();
      final summary = service.renderSummary(snapshot);
      // The summary is a prompt-facing string. It must stay a summary even
      // when the application is holding a great deal of state, and it must not
      // inline the state itself. If someone later enumerates projects or
      // processes into it, both of these fail.
      expect(summary.length, lessThan(4000));
      expect(summary, isNot(contains('project 499')));
      expect(summary, isNot(contains('proc 499')));

      // The bound must hold for the machine-readable projection too, which is
      // what a model would actually be handed.
      final context = await service.planningContext();
      expect(context.relevantCapabilities.length, lessThanOrEqualTo(12));
      expect(context.toJson().toString(), isNot(contains('project 499')));
    });
  });

  group('truthfulness about current state', () {
    test('no selected project and no selected model are reported as such',
        () async {
      final service = _service(<KristinCapabilityProvider>[
        _FakeProvider('p1', <CapabilityDescriptor>[_descriptor('a')]),
      ], _app());
      final snapshot = await service.snapshot();
      expect(snapshot.application.selectedProject, isNull);
      expect(snapshot.application.selectedModel, isNull);
    });

    test('platform is reported from injected runtime state, not assumed',
        () async {
      for (final platform in <String>['linux', 'windows', 'macos']) {
        final service = _service(<KristinCapabilityProvider>[
          _FakeProvider('p1', <CapabilityDescriptor>[_descriptor('a')]),
        ], _app(platform: platform));
        final snapshot = await service.snapshot();
        expect(snapshot.application.platform, platform);
      }
    });

    test('browser and owner runtime absence and presence both round-trip',
        () async {
      final absent = _service(<KristinCapabilityProvider>[
        _FakeProvider('p1', <CapabilityDescriptor>[_descriptor('a')]),
      ], _app());
      final absentSnapshot = await absent.snapshot();
      expect(absentSnapshot.application.browser['available'], isNull);
      expect(absentSnapshot.application.ownerMode['available'], isNull);

      final present = _service(
          <KristinCapabilityProvider>[
            _FakeProvider('p1', <CapabilityDescriptor>[_descriptor('a')]),
          ],
          _app(
            browser: <String, Object?>{'available': true},
            ownerMode: <String, Object?>{'available': true},
          ));
      final presentSnapshot = await present.snapshot();
      expect(presentSnapshot.application.browser['available'], isTrue);
      expect(presentSnapshot.application.ownerMode['available'], isTrue);
    });

    test('a blocked capability carries the actual blocking reason', () async {
      final blocked = CapabilityAvailability(
        capabilityId: 'browser.open',
        state: CapabilityAvailabilityState.browserUnavailable,
        reasons: const <String>['the browser runtime is not installed'],
        observedAt: DateTime.now().toUtc(),
      );
      final service = _service(<KristinCapabilityProvider>[
        _FakeProvider(
          'p1',
          <CapabilityDescriptor>[_descriptor('browser.open')],
          availability: <String, CapabilityAvailability>{
            'browser.open': blocked,
          },
        ),
      ], _app());

      final snapshot = await service.snapshot();
      final capability = snapshot.capability('browser.open');
      expect(capability, isNotNull);
      expect(capability!.operationallyUsable, isFalse);
      expect(
        capability.availability.reasons.first,
        'the browser runtime is not installed',
      );
      // The capability is still *known*. Being blocked is not being invisible.
      expect(snapshot.capabilities.map((c) => c.descriptor.id),
          contains('browser.open'));
    });
  });

  group('knowledge != availability != authority != executable tool', () {
    test('a known capability may be unavailable', () async {
      final service = _service(<KristinCapabilityProvider>[
        _FakeProvider(
          'p1',
          <CapabilityDescriptor>[_descriptor('known.but.down')],
          availability: <String, CapabilityAvailability>{
            'known.but.down': CapabilityAvailability(
              capabilityId: 'known.but.down',
              state: CapabilityAvailabilityState.runtimeMissing,
              observedAt: DateTime.now().toUtc(),
            ),
          },
        ),
      ], _app());

      final snapshot = await service.snapshot();
      expect(snapshot.capability('known.but.down'), isNotNull);
      expect(
        snapshot.available.map((c) => c.descriptor.id),
        isNot(contains('known.but.down')),
      );
    });

    test(
      'an otherwise-available capability stays unusable while authority is '
      'unobserved, and becomes usable only once authority is granted',
      () {
        final descriptor = _descriptor(
          'owner.reset',
          authorityClass: CapabilityAuthorityClass.owner,
          riskClass: CapabilityRiskClass.sensitive,
        );
        final now = DateTime.now().toUtc();
        final evidence = <KnowledgeEvidence>[
          // 'owner.reset' is a sensitive capability, so operational usability
          // additionally requires directly-observed evidence at high
          // confidence. State that explicitly here: this test varies only the
          // authority dimension, and the default (medium) confidence would
          // otherwise fail the positive case for an unrelated reason.
          KnowledgeEvidence(
            kind: KnowledgeEvidenceKind.observed,
            source: 'test',
            confidence: ObservationConfidence.high,
          ),
        ];
        final health = CapabilityHealth(
          capabilityId: 'owner.reset',
          state: CapabilityHealthState.healthy,
          observedAt: now,
          evidence: evidence,
        );

        // Availability says "available" -- the runtime is up. Authority has
        // not been observed. That must not be enough.
        final unobserved = KnownCapability(
          descriptor: descriptor,
          availability: CapabilityAvailability(
            capabilityId: 'owner.reset',
            state: CapabilityAvailabilityState.available,
            requiredAuthority: const <String>{'owner.session'},
            authorityObservation: AuthorityObservationState.notEvaluated,
            observedAt: now,
            evidence: evidence,
          ),
          health: health,
        );
        expect(unobserved.operationallyUsableAt(now), isFalse);

        // Explicitly absent authority is likewise not enough.
        final absent = KnownCapability(
          descriptor: descriptor,
          availability: CapabilityAvailability(
            capabilityId: 'owner.reset',
            state: CapabilityAvailabilityState.available,
            requiredAuthority: const <String>{'owner.session'},
            authorityObservation: AuthorityObservationState.absent,
            observedAt: now,
            evidence: evidence,
          ),
          health: health,
        );
        expect(absent.operationallyUsableAt(now), isFalse);

        // Only an observed grant flips it.
        final granted = KnownCapability(
          descriptor: descriptor,
          availability: CapabilityAvailability(
            capabilityId: 'owner.reset',
            state: CapabilityAvailabilityState.available,
            requiredAuthority: const <String>{'owner.session'},
            currentAuthority: const <String>{'owner.session'},
            authorityObservation: AuthorityObservationState.granted,
            observedAt: now,
            evidence: evidence,
          ),
          health: health,
        );
        expect(granted.operationallyUsableAt(now), isTrue);
      },
    );

    test(
      'availability turning true does not mint authority: the planning context '
      'still reports the capability as authority-not-evaluated',
      () async {
        final descriptor = _descriptor(
          'owner.reset',
          authorityClass: CapabilityAuthorityClass.owner,
          riskClass: CapabilityRiskClass.sensitive,
        );
        final service = _service(<KristinCapabilityProvider>[
          _FakeProvider(
            'p1',
            <CapabilityDescriptor>[descriptor],
            availability: <String, CapabilityAvailability>{
              'owner.reset': CapabilityAvailability(
                capabilityId: 'owner.reset',
                state: CapabilityAvailabilityState.available,
                requiredAuthority: const <String>{'owner.session'},
                authorityObservation: AuthorityObservationState.notEvaluated,
                observedAt: DateTime.now().toUtc(),
              ),
            },
          ),
        ], _app());

        final context = await service.planningContext();
        expect(context.authorityNotEvaluated, contains('owner.reset'));
        expect(context.availableCapabilityIds, isNot(contains('owner.reset')));
        expect(context.currentAuthority, isEmpty);
      },
    );

    test(
      'the planning context carries no runner tool list, so self-awareness '
      'cannot smuggle an executable tool into a task',
      () async {
        // A capability that names a Runner tool and claims to be directly
        // executable is still only *described*. The planning context has no
        // field through which a tool could reach the Runner allow-list.
        final service = _service(<KristinCapabilityProvider>[
          _FakeProvider('p1', <CapabilityDescriptor>[
            _descriptor(
              'danger.exec',
              directlyExecutable: true,
              runnerToolName: 'run_command',
              riskClass: CapabilityRiskClass.destructive,
            ),
          ]),
        ], _app());

        final context = await service.planningContext();
        final json = context.toJson();
        expect(json.containsKey('allowedTools'), isFalse);
        expect(json.containsKey('tools'), isFalse);
        expect(json.containsKey('runnerTools'), isFalse);
        // Everything the context exposes about capabilities is descriptive.
        expect(
          json.keys.toSet(),
          <String>{
            'summary',
            'availableCapabilityIds',
            'blockedCapabilityReasons',
            'currentAuthority',
            'authorityNotEvaluated',
            'relevantCapabilities',
            'freshnessWarnings',
          },
        );
      },
    );

    test('current authority is read from observed state, never synthesised',
        () async {
      final service = _service(
          <KristinCapabilityProvider>[
            _FakeProvider('p1', <CapabilityDescriptor>[_descriptor('a')]),
          ],
          _app(authority: <String, Object?>{
            'granted': <String>['project.read'],
          }));
      final context = await service.planningContext();
      expect(context.currentAuthority, <String>{'project.read'});

      final empty = _service(<KristinCapabilityProvider>[
        _FakeProvider('p1', <CapabilityDescriptor>[_descriptor('a')]),
      ], _app());
      final emptyContext = await empty.planningContext();
      expect(emptyContext.currentAuthority, isEmpty);
    });
  });

  group('read-only introspection', () {
    test('taking a snapshot does not mutate application state', () async {
      final app = _FakeApplication(_app());
      final registry = KristinCapabilityRegistry()
        ..register(
          _FakeProvider('p1', <CapabilityDescriptor>[_descriptor('a')]),
        );
      final service = KristinSelfModelService(
        registry: registry,
        application: app,
      );

      final before = app.snapshot.semanticJson().toString();
      await service.snapshot();
      await service.planningContext();
      final after = app.snapshot.semanticJson().toString();
      expect(after, before);
    });
  });
}
