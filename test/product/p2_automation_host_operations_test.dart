import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/p2_automation_host.dart';
import 'package:kristin_local_agent/product/p2_automation_host_operations.dart';
import 'package:kristin_local_agent/product/p2_effect_boundary.dart';

import 'p2_test_support.dart';

void main() {
  test(
    'product host adapter routes package effect through exact envelope',
    () async {
      final authority = TestEnvelopeAuthority();
      final journal = TestJournal();
      final client = TestAutomationHostClient((envelope) {
        final operation = envelope.operation;
        return <String, Object?>{
          'status': 'ok',
          'support': <String, Object?>{
            'status': 'supported',
            'reason': 'controlled_fixture',
            'requiresElevation': false,
          },
          'receipt': testReceipt(envelope.binding, operation),
          'output': operation == 'package.plan'
              ? <String, Object?>{
                  'status': 'planned',
                  'manager': 'fixture',
                  'packageOperation': 'install',
                  'packages': <String>['fixture-sdk'],
                  'dryRun': true,
                }
              : <String, Object?>{'applied': true},
        };
      });
      final adapter = P2AutomationHostOperations(
        host: P2SupervisedAutomationHost(client),
        authority: authority,
        journal: journal,
        bindingProvider: _Bindings(),
      );
      final plan = await adapter.plan(
          'fixture',
          'install',
          <String>[
            'fixture-sdk',
          ],
          testBinding('package.plan', taskId: 'P2-007'));
      final applied = await adapter.apply(
        plan,
        testBinding('package.apply', taskId: 'P2-007'),
      );
      expect(plan['dryRun'], isTrue);
      expect(applied.status.name, 'succeeded');
      expect(client.calls.map((item) => item.operation), <String>[
        'package.plan',
        'package.apply',
      ]);
      expect(journal.receipts, hasLength(2));
      expect(
        client.calls.every(
          (item) =>
              p2CanonicalJson(item.toJson()['payload']) ==
              p2CanonicalJson(item.payload),
        ),
        isTrue,
      );
    },
  );

  test(
    'screen bytes flow through product adapter without entering receipt',
    () async {
      final authority = TestEnvelopeAuthority();
      final journal = TestJournal();
      final bytes = utf8.encode('png-fixture');
      final client = TestAutomationHostClient(
        (envelope) => <String, Object?>{
          'status': 'ok',
          'support': <String, Object?>{
            'status': 'supported',
            'reason': 'interactive_desktop',
            'requiresElevation': false,
          },
          'receipt': testReceipt(
            envelope.binding,
            envelope.operation,
            reversibility: 'irreversible',
            details: const <String, Object?>{'contentLogged': false},
          ),
          'output': <String, Object?>{'bytesBase64': base64Encode(bytes)},
        },
      );
      final adapter = P2AutomationHostOperations(
        host: P2SupervisedAutomationHost(client),
        authority: authority,
        journal: journal,
        bindingProvider: _Bindings(),
      );
      final observed = await adapter.captureScreen(
        testBinding('screen.capture', taskId: 'P2-009'),
      );
      expect(observed, bytes);
      expect(journal.receipts.single.details['contentLogged'], isFalse);
      expect(
        jsonEncode(journal.receipts.single.toJson()),
        isNot(contains('png-fixture')),
      );
    },
  );
}

final class _Bindings implements P2HostBindingProvider {
  @override
  P2EffectBinding bindingFor(String operation) => testBinding(operation);
}
