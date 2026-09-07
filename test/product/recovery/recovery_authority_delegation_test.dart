// Adversarial proof that bounded L3 recovery delegation cannot compose
// heterogeneous parent grants into a stronger child envelope.
//
//   INVARIANT: no delegated child may exercise any scope more times, for
//              longer, or in a broader combination than the source authority
//              actually permitted.
//
// Authority here is three-dimensional -- scope x uses x expiry -- and the
// dimensions are NOT independent. The permission engine's real semantics,
// pinned by the first group below, are what make that true:
// PermissionService.require selects whichever surviving grant *itself* allows
// the requested scope and debits that one grant. So a command's real authority
// for a scope is bounded by the grants that individually carry that scope --
// their own remaining uses, their own expiry -- and never by the pool.
//
// Taking union(scopes), sum(uses) and max(expiry) independently therefore does
// not describe authority any parent ever held. A parent holding
// {projectRead, 1 use, +5m} and {projectWrite, 100 uses, +1h} can read exactly
// once inside five minutes; a pooled child grant carrying {read, write} for
// 101 uses over an hour could read a hundred times for an hour.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/recovery/product_runtime_recovery.dart';
import 'package:kristin_local_agent/product/repository.dart';
import 'package:kristin_local_agent/product/storage_security.dart';

class _MemoryGrants implements EntityRepository<PermissionGrant> {
  final Map<String, PermissionGrant> _items = <String, PermissionGrant>{};

  @override
  Future<List<PermissionGrant>> all() async => _items.values.toList();

  @override
  Future<PermissionGrant?> get(String id) async => _items[id];

  @override
  Future<void> put(PermissionGrant item) async => _items[item.id] = item;

  @override
  Future<void> putAll(Iterable<PermissionGrant> values) async {
    for (final value in values) {
      _items[value.id] = value;
    }
  }

  @override
  Future<void> remove(String id) async => _items.remove(id);

  @override
  Future<void> removeWhere(
      bool Function(PermissionGrant item) predicate) async {
    _items.removeWhere((_, value) => predicate(value));
  }

  @override
  Future<void> replaceAll(Iterable<PermissionGrant> values) async {
    _items
      ..clear()
      ..addEntries(
          values.map((v) => MapEntry<String, PermissionGrant>(v.id, v)));
  }
}

PermissionGrant _grant({
  required String id,
  required Set<PermissionScope> scopes,
  required int uses,
  required Duration expiresIn,
  String projectId = 'proj-1',
  String commandId = 'cmd-parent',
}) =>
    PermissionGrant(
      id: id,
      projectId: projectId,
      commandId: commandId,
      scopes: scopes,
      createdAt: DateTime.now().toUtc(),
      expiresAt: DateTime.now().toUtc().add(expiresIn),
      remainingUses: uses,
    );

/// How many times the parent could actually exercise [scope]: the budget of the
/// grants that individually carry it. This mirrors PermissionService.require,
/// which never spends a grant on a scope that grant does not hold.
int _parentUsesOf(Iterable<PermissionGrant> grants, PermissionScope scope) =>
    grants
        .where((grant) => grant.allows(scope))
        .fold<int>(0, (total, grant) => total + grant.remainingUses);

/// The last instant the parent could exercise [scope].
DateTime? _parentExpiryOf(
  Iterable<PermissionGrant> grants,
  PermissionScope scope,
) {
  DateTime? latest;
  for (final grant in grants.where((grant) => grant.allows(scope))) {
    if (latest == null || grant.expiresAt.isAfter(latest)) {
      latest = grant.expiresAt;
    }
  }
  return latest;
}

/// The invariant every correct implementation must satisfy, whatever strategy
/// it uses. A conservative single-source implementation satisfies it by
/// refusing; a more expressive one could satisfy it by preserving each source
/// grant's own constraints. Pooling cannot satisfy it.
void _expectNoAmplification(
  RecoveryDelegationBound bound,
  List<PermissionGrant> parents,
  Set<PermissionScope> required,
) {
  if (!bound.isGranted) return; // Refusing is always safe.
  for (final scope in required) {
    final parentUses = _parentUsesOf(parents, scope);
    final parentExpiry = _parentExpiryOf(parents, scope);
    expect(
      parentExpiry,
      isNotNull,
      reason: 'delegated $scope the parent could not exercise at all',
    );
    expect(
      bound.uses,
      lessThanOrEqualTo(parentUses),
      reason: 'child may use $scope at most $parentUses times, '
          'got ${bound.uses}',
    );
    expect(
      bound.expiresAt!.isAfter(parentExpiry!),
      isFalse,
      reason: 'child may exercise $scope no later than $parentExpiry, '
          'got ${bound.expiresAt}',
    );
  }
}

void main() {
  late Directory temp;
  late PermissionService permissions;
  late _MemoryGrants repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('kristin-delegation-test');
    repository = _MemoryGrants();
    final audit = AuditChain(File('${temp.path}/audit.log'), SecretRedactor());
    await audit.open();
    permissions = PermissionService(repository, audit);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  group('the real permission algebra', () {
    test(
      'a scope is satisfied only by a grant that itself carries it, and only '
      'that grant is debited',
      () async {
        await repository.put(_grant(
          id: 'g-read',
          scopes: <PermissionScope>{PermissionScope.projectRead},
          uses: 1,
          expiresIn: const Duration(minutes: 5),
        ));
        await repository.put(_grant(
          id: 'g-write',
          scopes: <PermissionScope>{PermissionScope.projectWrite},
          uses: 100,
          expiresIn: const Duration(hours: 1),
        ));

        await permissions.require(
          projectId: 'proj-1',
          commandId: 'cmd-parent',
          scope: PermissionScope.projectRead,
        );

        expect((await repository.get('g-read'))!.remainingUses, 0,
            reason: 'the read grant paid for the read');
        expect((await repository.get('g-write'))!.remainingUses, 100,
            reason: 'the write grant must not fund a read');

        await expectLater(
          permissions.require(
            projectId: 'proj-1',
            commandId: 'cmd-parent',
            scope: PermissionScope.projectRead,
          ),
          throwsA(isA<ProductException>()),
          reason: 'the write grant\'s 100 uses are not read authority',
        );
      },
    );

    test('per-scope expiry is preserved: a dead grant funds nothing', () async {
      await repository.put(_grant(
        id: 'g-read',
        scopes: <PermissionScope>{PermissionScope.projectRead},
        uses: 5,
        expiresIn: const Duration(seconds: -1),
      ));
      await repository.put(_grant(
        id: 'g-write',
        scopes: <PermissionScope>{PermissionScope.projectWrite},
        uses: 5,
        expiresIn: const Duration(hours: 1),
      ));

      await expectLater(
        permissions.require(
          projectId: 'proj-1',
          commandId: 'cmd-parent',
          scope: PermissionScope.projectRead,
        ),
        throwsA(isA<ProductException>()),
        reason: 'a live write grant does not revive an expired read grant',
      );
    });

    test('grants are keyed by project: authority does not cross projects',
        () async {
      await repository.put(_grant(
        id: 'g-a',
        projectId: 'proj-a',
        scopes: <PermissionScope>{PermissionScope.projectWrite},
        uses: 10,
        expiresIn: const Duration(hours: 1),
      ));

      await expectLater(
        permissions.require(
          projectId: 'proj-b',
          commandId: 'cmd-parent',
          scope: PermissionScope.projectWrite,
        ),
        throwsA(isA<ProductException>()),
      );
    });
  });

  group('heterogeneous grants cannot be composed into stronger authority', () {
    test(
      'different scopes, different budgets, different expiries: a short '
      'single-use read must not inherit a long high-budget write',
      () {
        final parents = <PermissionGrant>[
          _grant(
            id: 'g-read',
            scopes: <PermissionScope>{PermissionScope.projectRead},
            uses: 1,
            expiresIn: const Duration(minutes: 5),
          ),
          _grant(
            id: 'g-write',
            scopes: <PermissionScope>{PermissionScope.projectWrite},
            uses: 100,
            expiresIn: const Duration(hours: 1),
          ),
        ];
        final required = <PermissionScope>{
          PermissionScope.projectRead,
          PermissionScope.projectWrite,
        };

        final bound = boundRecoveryDelegation(
          grants: parents,
          required: required,
          requestedUses: 100,
          now: DateTime.now().toUtc(),
          projectId: 'proj-1',
          commandId: 'cmd-parent',
        );

        // The parent could read exactly once, within five minutes.
        expect(_parentUsesOf(parents, PermissionScope.projectRead), 1);
        _expectNoAmplification(bound, parents, required);
      },
    );

    test('required scopes spanning two parent grants are refused fail-closed',
        () {
      final parents = <PermissionGrant>[
        _grant(
          id: 'g-read',
          scopes: <PermissionScope>{PermissionScope.projectRead},
          uses: 10,
          expiresIn: const Duration(hours: 1),
        ),
        _grant(
          id: 'g-write',
          scopes: <PermissionScope>{PermissionScope.projectWrite},
          uses: 10,
          expiresIn: const Duration(hours: 1),
        ),
      ];
      final required = <PermissionScope>{
        PermissionScope.projectRead,
        PermissionScope.projectWrite,
      };

      final bound = boundRecoveryDelegation(
        grants: parents,
        required: required,
        requestedUses: 5,
        now: DateTime.now().toUtc(),
        projectId: 'proj-1',
        commandId: 'cmd-parent',
      );

      expect(bound.isGranted, isFalse,
          reason: 'no single approval covers both scopes');
      expect(bound.rejection, 'recovery_authority_not_single_sourced');
      _expectNoAmplification(bound, parents, required);
    });

    test('overlapping scopes with different expiries take the narrower life',
        () {
      final parents = <PermissionGrant>[
        _grant(
          id: 'g-short',
          scopes: <PermissionScope>{
            PermissionScope.projectRead,
            PermissionScope.projectWrite,
          },
          uses: 4,
          expiresIn: const Duration(minutes: 5),
        ),
        _grant(
          id: 'g-long-read',
          scopes: <PermissionScope>{PermissionScope.projectRead},
          uses: 50,
          expiresIn: const Duration(hours: 2),
        ),
      ];
      final required = <PermissionScope>{
        PermissionScope.projectRead,
        PermissionScope.projectWrite,
      };

      final bound = boundRecoveryDelegation(
        grants: parents,
        required: required,
        requestedUses: 100,
        now: DateTime.now().toUtc(),
        projectId: 'proj-1',
        commandId: 'cmd-parent',
      );

      // projectWrite lives only 5 minutes, so the child cannot outlive that.
      expect(_parentUsesOf(parents, PermissionScope.projectWrite), 4);
      _expectNoAmplification(bound, parents, required);
    });

    test('overlapping scopes with different budgets take the narrower budget',
        () {
      final parents = <PermissionGrant>[
        _grant(
          id: 'g-small-both',
          scopes: <PermissionScope>{
            PermissionScope.projectRead,
            PermissionScope.projectWrite,
          },
          uses: 2,
          expiresIn: const Duration(hours: 1),
        ),
        _grant(
          id: 'g-big-read',
          scopes: <PermissionScope>{PermissionScope.projectRead},
          uses: 500,
          expiresIn: const Duration(hours: 1),
        ),
      ];
      final required = <PermissionScope>{
        PermissionScope.projectRead,
        PermissionScope.projectWrite,
      };

      final bound = boundRecoveryDelegation(
        grants: parents,
        required: required,
        requestedUses: 100,
        now: DateTime.now().toUtc(),
        projectId: 'proj-1',
        commandId: 'cmd-parent',
      );

      expect(_parentUsesOf(parents, PermissionScope.projectWrite), 2,
          reason: 'write authority is 2 uses however large the read grant is');
      _expectNoAmplification(bound, parents, required);
    });

    test('an expired or exhausted grant contributes nothing', () {
      final parents = <PermissionGrant>[
        _grant(
          id: 'g-expired',
          scopes: <PermissionScope>{
            PermissionScope.projectRead,
            PermissionScope.projectWrite,
          },
          uses: 500,
          expiresIn: const Duration(seconds: -1),
        ),
        _grant(
          id: 'g-exhausted',
          scopes: <PermissionScope>{
            PermissionScope.projectRead,
            PermissionScope.projectWrite,
          },
          uses: 0,
          expiresIn: const Duration(hours: 2),
        ),
        _grant(
          id: 'g-live',
          scopes: <PermissionScope>{
            PermissionScope.projectRead,
            PermissionScope.projectWrite,
          },
          uses: 3,
          expiresIn: const Duration(minutes: 10),
        ),
      ];
      final required = <PermissionScope>{
        PermissionScope.projectRead,
        PermissionScope.projectWrite,
      };

      final bound = boundRecoveryDelegation(
        grants: parents,
        required: required,
        requestedUses: 100,
        now: DateTime.now().toUtc(),
        projectId: 'proj-1',
        commandId: 'cmd-parent',
      );

      expect(bound.isGranted, isTrue);
      expect(bound.uses, 3,
          reason: 'only the live grant\'s budget is real authority');
      _expectNoAmplification(bound, parents, required);
    });

    test('a scope the parent never held is refused as expansion', () {
      final parents = <PermissionGrant>[
        _grant(
          id: 'g-read',
          scopes: <PermissionScope>{PermissionScope.projectRead},
          uses: 10,
          expiresIn: const Duration(hours: 1),
        ),
      ];
      final required = <PermissionScope>{
        PermissionScope.projectRead,
        PermissionScope.networkResearch,
      };

      final bound = boundRecoveryDelegation(
        grants: parents,
        required: required,
        requestedUses: 5,
        now: DateTime.now().toUtc(),
        projectId: 'proj-1',
        commandId: 'cmd-parent',
      );

      expect(bound.isGranted, isFalse);
      expect(bound.rejection, 'recovery_authority_expansion_rejected');
    });

    test('a partial required set is bounded by the grant that carries it', () {
      final parents = <PermissionGrant>[
        _grant(
          id: 'g-both',
          scopes: <PermissionScope>{
            PermissionScope.projectRead,
            PermissionScope.projectWrite,
          },
          uses: 6,
          expiresIn: const Duration(minutes: 30),
        ),
      ];
      final required = <PermissionScope>{PermissionScope.projectRead};

      final bound = boundRecoveryDelegation(
        grants: parents,
        required: required,
        requestedUses: 100,
        now: DateTime.now().toUtc(),
        projectId: 'proj-1',
        commandId: 'cmd-parent',
      );

      expect(bound.isGranted, isTrue);
      expect(bound.uses, 6);
      _expectNoAmplification(bound, parents, required);
    });
  });

  group('producer-supplied failure data cannot reach foreign authority', () {
    test('a grant in another project cannot fund a delegation', () {
      // The L3 repair command takes its project from the FailureEvent, which
      // is producer-supplied. A failure naming another project must not reach
      // the authority that project holds.
      final foreign = <PermissionGrant>[
        _grant(
          id: 'g-other-project',
          projectId: 'proj-attacker',
          scopes: <PermissionScope>{PermissionScope.projectWrite},
          uses: 500,
          expiresIn: const Duration(hours: 2),
        ),
      ];

      final bound = boundRecoveryDelegation(
        grants: foreign,
        required: <PermissionScope>{PermissionScope.projectWrite},
        requestedUses: 100,
        now: DateTime.now().toUtc(),
        projectId: 'proj-1',
        commandId: 'cmd-parent',
      );

      expect(bound.isGranted, isFalse);
      expect(bound.rejection, 'recovery_authority_expansion_rejected');
    });

    test('a grant for another command of the same project cannot fund it', () {
      final foreign = <PermissionGrant>[
        _grant(
          id: 'g-other-command',
          commandId: 'cmd-unrelated',
          scopes: <PermissionScope>{PermissionScope.projectWrite},
          uses: 500,
          expiresIn: const Duration(hours: 2),
        ),
      ];

      final bound = boundRecoveryDelegation(
        grants: foreign,
        required: <PermissionScope>{PermissionScope.projectWrite},
        requestedUses: 100,
        now: DateTime.now().toUtc(),
        projectId: 'proj-1',
        commandId: 'cmd-parent',
      );

      expect(bound.isGranted, isFalse,
          reason: 'authority is keyed by (project, command), not by project');
    });

    test('a foreign grant cannot be laundered by mixing it with a real one',
        () {
      final mixed = <PermissionGrant>[
        _grant(
          id: 'g-mine',
          scopes: <PermissionScope>{PermissionScope.projectWrite},
          uses: 2,
          expiresIn: const Duration(minutes: 10),
        ),
        _grant(
          id: 'g-theirs',
          projectId: 'proj-attacker',
          scopes: <PermissionScope>{PermissionScope.projectWrite},
          uses: 500,
          expiresIn: const Duration(hours: 5),
        ),
      ];

      final bound = boundRecoveryDelegation(
        grants: mixed,
        required: <PermissionScope>{PermissionScope.projectWrite},
        requestedUses: 100,
        now: DateTime.now().toUtc(),
        projectId: 'proj-1',
        commandId: 'cmd-parent',
      );

      expect(bound.isGranted, isTrue);
      expect(bound.uses, 2,
          reason: 'only this project\'s own grant is real authority');
      expect(bound.sourceGrants.single.id, 'g-mine');
    });
  });

  group('delegation conserves authority rather than creating it', () {
    test('two siblings cannot each receive the full remainder', () {
      var parents = <PermissionGrant>[
        _grant(
          id: 'g-parent',
          scopes: <PermissionScope>{PermissionScope.projectWrite},
          uses: 4,
          expiresIn: const Duration(hours: 1),
        ),
      ];
      final required = <PermissionScope>{PermissionScope.projectWrite};

      final first = boundRecoveryDelegation(
        grants: parents,
        required: required,
        requestedUses: 3,
        now: DateTime.now().toUtc(),
        projectId: 'proj-1',
        commandId: 'cmd-parent',
      );
      expect(first.isGranted, isTrue);
      expect(first.uses, 3);

      // Debit exactly what the first sibling received, as the runtime does.
      parents = <PermissionGrant>[
        PermissionGrant(
          id: 'g-parent',
          projectId: 'proj-1',
          commandId: 'cmd-parent',
          scopes: parents.first.scopes,
          createdAt: parents.first.createdAt,
          expiresAt: parents.first.expiresAt,
          remainingUses: parents.first.remainingUses - first.uses,
        ),
      ];

      final second = boundRecoveryDelegation(
        grants: parents,
        required: required,
        requestedUses: 100,
        now: DateTime.now().toUtc(),
        projectId: 'proj-1',
        commandId: 'cmd-parent',
      );
      expect(second.uses, 1,
          reason: 'the second sibling sees only what the first left');
      expect(first.uses + second.uses, lessThanOrEqualTo(4),
          reason: 'siblings share one finite approval');
    });

    test('a chain terminates instead of renewing authority', () {
      var remaining = 3;
      var rounds = 0;
      while (rounds < 10) {
        final parents = <PermissionGrant>[
          _grant(
            id: 'g-chain',
            scopes: <PermissionScope>{PermissionScope.projectWrite},
            uses: remaining,
            expiresIn: const Duration(hours: 1),
          ),
        ];
        final bound = boundRecoveryDelegation(
          grants: parents,
          required: <PermissionScope>{PermissionScope.projectWrite},
          requestedUses: 1,
          now: DateTime.now().toUtc(),
          projectId: 'proj-1',
          commandId: 'cmd-parent',
        );
        if (!bound.isGranted) break;
        remaining -= bound.uses;
        rounds += 1;
      }
      expect(rounds, 3, reason: 'a 3-use approval funds exactly 3 links');
      expect(remaining, 0);
    });

    test(
      'a delegated child cannot outlive the grant it drew from, proven '
      'through the real permission engine',
      () async {
        final parent = _grant(
          id: 'g-parent',
          scopes: <PermissionScope>{PermissionScope.projectWrite},
          uses: 2,
          expiresIn: const Duration(minutes: 4),
        );
        final bound = boundRecoveryDelegation(
          grants: <PermissionGrant>[parent],
          required: <PermissionScope>{PermissionScope.projectWrite},
          requestedUses: 100,
          now: DateTime.now().toUtc(),
          projectId: 'proj-1',
          commandId: 'cmd-parent',
        );
        expect(bound.isGranted, isTrue);

        // Mint the child exactly as the runtime would, then spend it.
        await permissions.grant(
          projectId: 'proj-1',
          commandId: 'cmd-child',
          scopes: <PermissionScope>{PermissionScope.projectWrite},
          validity: bound.expiresAt!.difference(DateTime.now().toUtc()),
          uses: bound.uses,
        );

        for (var i = 0; i < bound.uses; i++) {
          await permissions.require(
            projectId: 'proj-1',
            commandId: 'cmd-child',
            scope: PermissionScope.projectWrite,
          );
        }
        await expectLater(
          permissions.require(
            projectId: 'proj-1',
            commandId: 'cmd-child',
            scope: PermissionScope.projectWrite,
          ),
          throwsA(isA<ProductException>()),
          reason: 'the child is exhausted at the delegated budget',
        );
      },
    );
  });
}
