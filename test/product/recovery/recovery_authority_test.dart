// Behavioural proof for the authority boundary that recovery continuations
// must respect.
//
//   INVARIANT: child_authority <= remaining_parent_authority
//              across scope, expiry, use budget and revocation.
//
// The tests below first pin down the permission model's real semantics -- how
// grants are keyed, how budget is consumed, and what "the effective authority
// of a command" actually means -- because the amplification defect these
// guard against was only visible once those semantics were stated plainly.
//
// The key fact the invariant rests on: permission enforcement is keyed by
// (projectId, commandId, scope). Nothing keys off runId. A recovery
// continuation produced by RunService.retryRun reuses the parent's
// PreparedCommand and therefore its commandId, so it is already covered by the
// parent's grants and must not be issued fresh ones.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/domain.dart';
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
  Future<void> removeWhere(bool Function(PermissionGrant item) predicate) async {
    _items.removeWhere((_, value) => predicate(value));
  }

  @override
  Future<void> replaceAll(Iterable<PermissionGrant> values) async {
    _items
      ..clear()
      ..addEntries(values.map((v) => MapEntry<String, PermissionGrant>(v.id, v)));
  }
}

/// The total budget a command can actually spend: the sum across every grant
/// that still authorises it. This mirrors PermissionService.require, which
/// selects whichever surviving grant allows the scope.
int _effectiveUses(
  List<PermissionGrant> grants, {
  required String projectId,
  required String commandId,
  required PermissionScope scope,
}) {
  var total = 0;
  for (final grant in grants) {
    if (grant.projectId == projectId &&
        grant.commandId == commandId &&
        grant.allows(scope)) {
      total += grant.remainingUses;
    }
  }
  return total;
}

DateTime? _latestExpiry(
  List<PermissionGrant> grants, {
  required String commandId,
}) {
  DateTime? latest;
  for (final grant in grants) {
    if (grant.commandId != commandId || grant.isExpired) continue;
    if (latest == null || grant.expiresAt.isAfter(latest)) {
      latest = grant.expiresAt;
    }
  }
  return latest;
}

void main() {
  late Directory temp;
  late PermissionService permissions;
  late _MemoryGrants repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('kristin-authority-test');
    repository = _MemoryGrants();
    final audit = AuditChain(
      File('${temp.path}/audit.log'),
      SecretRedactor(),
    );
    await audit.open();
    permissions = PermissionService(repository, audit);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  group('permission model semantics', () {
    test('a grant is keyed by project and command, never by run', () async {
      final grant = await permissions.grant(
        projectId: 'proj-1',
        commandId: 'cmd-1',
        scopes: <PermissionScope>{PermissionScope.projectRead},
        validity: const Duration(hours: 1),
        uses: 3,
      );
      expect(grant.projectId, 'proj-1');
      expect(grant.commandId, 'cmd-1');
      expect(grant.toJson().containsKey('runId'), isFalse);
    });

    test('require consumes exactly one use per governed call', () async {
      await permissions.grant(
        projectId: 'proj-1',
        commandId: 'cmd-1',
        scopes: <PermissionScope>{PermissionScope.projectRead},
        validity: const Duration(hours: 1),
        uses: 3,
      );

      await permissions.require(
        projectId: 'proj-1',
        commandId: 'cmd-1',
        scope: PermissionScope.projectRead,
      );

      final after = await repository.all();
      expect(after.single.remainingUses, 2);
    });

    test('an exhausted grant authorises nothing', () async {
      await permissions.grant(
        projectId: 'proj-1',
        commandId: 'cmd-1',
        scopes: <PermissionScope>{PermissionScope.projectRead},
        validity: const Duration(hours: 1),
        uses: 1,
      );
      await permissions.require(
        projectId: 'proj-1',
        commandId: 'cmd-1',
        scope: PermissionScope.projectRead,
      );

      await expectLater(
        permissions.require(
          projectId: 'proj-1',
          commandId: 'cmd-1',
          scope: PermissionScope.projectRead,
        ),
        throwsA(isA<ProductException>()),
      );
    });

    test('an expired grant authorises nothing', () async {
      final expired = PermissionGrant(
        id: 'grant-expired',
        projectId: 'proj-1',
        commandId: 'cmd-1',
        scopes: <PermissionScope>{PermissionScope.projectRead},
        createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
        expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
        remainingUses: 100,
      );
      await repository.put(expired);

      expect(expired.isExpired, isTrue);
      expect(expired.allows(PermissionScope.projectRead), isFalse);
      await expectLater(
        permissions.require(
          projectId: 'proj-1',
          commandId: 'cmd-1',
          scope: PermissionScope.projectRead,
        ),
        throwsA(isA<ProductException>()),
      );
    });

    test(
      'two grants on one command pool their budget -- this is why minting a '
      'second grant amplifies authority',
      () async {
        await permissions.grant(
          projectId: 'proj-1',
          commandId: 'cmd-1',
          scopes: <PermissionScope>{PermissionScope.projectRead},
          validity: const Duration(hours: 1),
          uses: 3,
        );
        final beforeSecond = _effectiveUses(
          await repository.all(),
          projectId: 'proj-1',
          commandId: 'cmd-1',
          scope: PermissionScope.projectRead,
        );
        expect(beforeSecond, 3);

        // A second grant for the same command -- exactly what the recovery
        // continuation path used to do -- raises the effective budget.
        await permissions.grant(
          projectId: 'proj-1',
          commandId: 'cmd-1',
          scopes: <PermissionScope>{PermissionScope.projectRead},
          validity: const Duration(hours: 2),
          uses: 100,
        );
        final afterSecond = _effectiveUses(
          await repository.all(),
          projectId: 'proj-1',
          commandId: 'cmd-1',
          scope: PermissionScope.projectRead,
        );
        expect(afterSecond, 103,
            reason: 'minting adds budget rather than carrying it forward');
      },
    );
  });

  group('the continuation invariant: child <= remaining parent', () {
    test(
      'sharing the parent grant keeps a continuation inside the original '
      'budget, however many continuations there are',
      () async {
        // A parent approval with a small, finite budget.
        await permissions.grant(
          projectId: 'proj-1',
          commandId: 'cmd-1',
          scopes: <PermissionScope>{PermissionScope.projectRead},
          validity: const Duration(hours: 1),
          uses: 3,
        );

        // Three chained continuations. Each reuses the parent's
        // PreparedCommand, so each spends the same pool and mints nothing.
        for (var i = 0; i < 3; i++) {
          await permissions.require(
            projectId: 'proj-1',
            commandId: 'cmd-1',
            scope: PermissionScope.projectRead,
          );
        }

        expect(
          _effectiveUses(
            await repository.all(),
            projectId: 'proj-1',
            commandId: 'cmd-1',
            scope: PermissionScope.projectRead,
          ),
          0,
          reason: 'a chain consumes the parent budget, it does not renew it',
        );
        await expectLater(
          permissions.require(
            projectId: 'proj-1',
            commandId: 'cmd-1',
            scope: PermissionScope.projectRead,
          ),
          throwsA(isA<ProductException>()),
          reason: 'the fourth continuation must fail closed and ask a human',
        );
      },
    );

    test('a continuation cannot extend the parent expiry', () async {
      final soon = DateTime.now().toUtc().add(const Duration(minutes: 8));
      await repository.put(
        PermissionGrant(
          id: 'grant-parent',
          projectId: 'proj-1',
          commandId: 'cmd-1',
          scopes: <PermissionScope>{PermissionScope.projectRead},
          createdAt: DateTime.now().toUtc(),
          expiresAt: soon,
          remainingUses: 5,
        ),
      );

      // Sharing the parent grant means the continuation inherits its deadline.
      final latest = _latestExpiry(await repository.all(), commandId: 'cmd-1');
      expect(latest, soon);
      expect(
        latest!.difference(DateTime.now().toUtc()).inMinutes,
        lessThanOrEqualTo(8),
        reason: 'eight minutes of authority must not become two hours',
      );
    });

    test(
      'bounded delegation to a new command may not exceed the parent, and '
      'debiting stops two siblings each receiving the full remainder',
      () async {
        // Parent approval: 4 uses.
        await repository.put(
          PermissionGrant(
            id: 'grant-parent',
            projectId: 'proj-1',
            commandId: 'cmd-parent',
            scopes: <PermissionScope>{PermissionScope.projectRead},
            createdAt: DateTime.now().toUtc(),
            expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
            remainingUses: 4,
          ),
        );

        Future<void> delegate(String childCommandId, int requested) async {
          final grants = await repository.all();
          final parent = grants.firstWhere((g) => g.id == 'grant-parent');
          final available = parent.remainingUses;
          final uses = requested < available ? requested : available;
          // Debit the parent by exactly what the child receives.
          await repository.put(
            PermissionGrant(
              id: parent.id,
              projectId: parent.projectId,
              commandId: parent.commandId,
              scopes: parent.scopes,
              createdAt: parent.createdAt,
              expiresAt: parent.expiresAt,
              remainingUses: parent.remainingUses - uses,
            ),
          );
          await permissions.grant(
            projectId: 'proj-1',
            commandId: childCommandId,
            scopes: <PermissionScope>{PermissionScope.projectRead},
            validity: parent.expiresAt.difference(DateTime.now().toUtc()),
            uses: uses,
          );
        }

        // Two sibling recovery children, each asking for far more than exists.
        await delegate('cmd-child-a', 100);
        await delegate('cmd-child-b', 100);

        final grants = await repository.all();
        final parentLeft = grants
            .firstWhere((g) => g.id == 'grant-parent')
            .remainingUses;
        final childA = _effectiveUses(grants,
            projectId: 'proj-1',
            commandId: 'cmd-child-a',
            scope: PermissionScope.projectRead);
        final childB = _effectiveUses(grants,
            projectId: 'proj-1',
            commandId: 'cmd-child-b',
            scope: PermissionScope.projectRead);

        expect(childA, 4, reason: 'the first child is capped at the remainder');
        expect(childB, 0, reason: 'nothing was left for the second child');
        expect(parentLeft, 0);
        expect(parentLeft + childA + childB, 4,
            reason: 'authority is conserved, never created');
      },
    );

    test('an exhausted parent cannot be resurrected by a continuation',
        () async {
      await repository.put(
        PermissionGrant(
          id: 'grant-parent',
          projectId: 'proj-1',
          commandId: 'cmd-1',
          scopes: <PermissionScope>{PermissionScope.projectRead},
          createdAt: DateTime.now().toUtc(),
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          remainingUses: 0,
        ),
      );

      final grants = await repository.all();
      expect(
        _effectiveUses(grants,
            projectId: 'proj-1',
            commandId: 'cmd-1',
            scope: PermissionScope.projectRead),
        0,
      );
      await expectLater(
        permissions.require(
          projectId: 'proj-1',
          commandId: 'cmd-1',
          scope: PermissionScope.projectRead,
        ),
        throwsA(isA<ProductException>()),
      );
    });

    test('a revoked command has no authority left to inherit', () async {
      await permissions.grant(
        projectId: 'proj-1',
        commandId: 'cmd-1',
        scopes: <PermissionScope>{PermissionScope.projectRead},
        validity: const Duration(hours: 1),
        uses: 10,
      );
      await permissions.revokeForCommand('cmd-1');

      expect(await repository.all(), isEmpty);
      await expectLater(
        permissions.require(
          projectId: 'proj-1',
          commandId: 'cmd-1',
          scope: PermissionScope.projectRead,
        ),
        throwsA(isA<ProductException>()),
      );
    });

    test('narrowed scope cannot be widened by inheritance', () async {
      await permissions.grant(
        projectId: 'proj-1',
        commandId: 'cmd-1',
        scopes: <PermissionScope>{PermissionScope.projectRead},
        validity: const Duration(hours: 1),
        uses: 10,
      );

      await expectLater(
        permissions.require(
          projectId: 'proj-1',
          commandId: 'cmd-1',
          scope: PermissionScope.projectWrite,
        ),
        throwsA(isA<ProductException>()),
        reason: 'a read approval never becomes a write approval',
      );
    });
  });
}
