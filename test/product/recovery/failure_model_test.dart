// Behavioural proof for the structured failure model.
//
// The recurrence signature is what stops autonomic recovery from believing a
// repeated failure is a fresh one and retrying forever. It has to normalise
// away volatile noise while keeping genuinely different failures distinct --
// getting either direction wrong is a real safety defect, so both are tested.

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/recovery/failure_recovery.dart';

FailureEvent _failure({
  String message = 'connection reset by peer',
  FailureCategory category = FailureCategory.transient,
  String subsystem = 'provider',
  String operation = 'complete',
  String? errorCode,
  Recoverability recoverability = Recoverability.unspecified,
  Set<String> requiredAuthority = const <String>{},
  String? runId,
  String? taskId,
  String? parentFailureId,
  String? rootFailureId,
  DateTime? timestamp,
}) {
  return FailureEvent(
    severity: FailureSeverity.error,
    category: category,
    subsystem: subsystem,
    operation: operation,
    message: message,
    errorCode: errorCode,
    recoverability: recoverability,
    requiredAuthority: requiredAuthority,
    runId: runId,
    taskId: taskId,
    parentFailureId: parentFailureId,
    rootFailureId: rootFailureId,
    timestamp: timestamp,
  );
}

void main() {
  group('failure identity', () {
    test('each event gets a distinct stable id that survives serialization',
        () {
      final a = _failure();
      final b = _failure();
      expect(a.id, isNotEmpty);
      expect(a.id, isNot(b.id));
      expect(a.toJson()['id'], a.id);
    });

    test('lineage to a parent and root failure is preserved', () {
      final root = _failure(message: 'origin');
      final child = _failure(
        message: 'downstream',
        parentFailureId: root.id,
        rootFailureId: root.id,
      );
      expect(child.parentFailureId, root.id);
      expect(child.rootFailureId, root.id);
      expect(child.toJson()['parentFailureId'], root.id);
    });
  });

  group('recurrence signature normalisation', () {
    test('the same underlying failure at different times has one signature',
        () {
      final first = _failure(timestamp: DateTime.utc(2026, 1, 1, 10));
      final second = _failure(timestamp: DateTime.utc(2026, 6, 30, 23, 59));
      expect(first.recurrenceSignature, second.recurrenceSignature);
    });

    test('memory addresses are normalised away', () {
      final a = _failure(message: 'segfault at 0x7ffde4a1b220');
      final b = _failure(message: 'segfault at 0x0000560bcafe1234');
      expect(a.recurrenceSignature, b.recurrenceSignature);
      expect(a.recurrenceSignature, contains('<addr>'));
    });

    test('volatile multi-digit numbers are normalised away', () {
      final a = _failure(message: 'worker 48122 exited after 9310 ms');
      final b = _failure(message: 'worker 51907 exited after 128 ms');
      expect(a.recurrenceSignature, b.recurrenceSignature);
      expect(a.recurrenceSignature, contains('<n>'));
    });

    test('temporary paths are normalised away', () {
      final a = _failure(message: 'cannot open /tmp/kristin-abc/run.lock');
      final b = _failure(message: 'cannot open /tmp/kristin-xyz/run.lock');
      expect(a.recurrenceSignature, b.recurrenceSignature);
      expect(a.recurrenceSignature, contains('<path>'));
    });

    test('whitespace and case differences do not create a new signature', () {
      final a = _failure(message: 'Connection   Reset  By Peer');
      final b = _failure(message: 'connection reset by peer');
      expect(a.recurrenceSignature, b.recurrenceSignature);
    });

    test('materially different failures stay distinguishable', () {
      final network = _failure(message: 'connection reset by peer');
      final disk = _failure(message: 'no space left on device');
      expect(network.recurrenceSignature, isNot(disk.recurrenceSignature));

      final differentOperation = _failure(operation: 'stream');
      expect(
        network.recurrenceSignature,
        isNot(differentOperation.recurrenceSignature),
      );

      final differentSubsystem = _failure(subsystem: 'browser');
      expect(
        network.recurrenceSignature,
        isNot(differentSubsystem.recurrenceSignature),
      );

      final differentCategory = _failure(category: FailureCategory.permission);
      expect(
        network.recurrenceSignature,
        isNot(differentCategory.recurrenceSignature),
      );

      final coded = _failure(errorCode: 'ECONNRESET');
      expect(network.recurrenceSignature, isNot(coded.recurrenceSignature));
    });

    test('an explicit signature is honoured over the derived one', () {
      final pinned = FailureEvent(
        severity: FailureSeverity.error,
        category: FailureCategory.transient,
        subsystem: 'provider',
        operation: 'complete',
        message: 'anything at all',
        recurrenceSignature: 'pinned-signature',
      );
      expect(pinned.recurrenceSignature, 'pinned-signature');
    });
  });

  group('classification determinism', () {
    test('an explicit recoverability from the producer wins', () {
      const classifier = FailureClassifier();
      final event = _failure(
        category: FailureCategory.transient,
        recoverability: Recoverability.repairable,
      );
      final result = classifier.classify(event);
      expect(result.recoverability, Recoverability.repairable);
      expect(result.level, RecoveryLevel.l3CodeRepair);
    });

    test('classification is a pure function of the event', () {
      const classifier = FailureClassifier();
      final event = _failure(category: FailureCategory.provider);
      final first = classifier.classify(event);
      final second = classifier.classify(event);
      expect(first.recoverability, second.recoverability);
      expect(first.level, second.level);
      expect(first.reason, second.reason);
    });

    test('transient and provider failures classify as retryable L0', () {
      const classifier = FailureClassifier();
      for (final category in <FailureCategory>[
        FailureCategory.transient,
        FailureCategory.provider,
      ]) {
        final result = classifier.classify(_failure(category: category));
        expect(result.recoverability, Recoverability.retryable);
        expect(result.level, RecoveryLevel.l0Transient);
      }
    });
  });

  group('operational checkpoints stay bounded and safe', () {
    test('before/after state is carried as structured fingerprints', () {
      final event = FailureEvent(
        severity: FailureSeverity.error,
        category: FailureCategory.process,
        subsystem: 'runner',
        operation: 'start_process',
        message: 'process exited',
        stateBefore: const <String, Object?>{
          'processRunning': true,
          'modelExactId': 'local/qwen',
        },
        stateAfter: const <String, Object?>{
          'processRunning': false,
          'modelExactId': 'local/qwen',
        },
      );
      expect(event.stateBefore['processRunning'], isTrue);
      expect(event.stateAfter['processRunning'], isFalse);
      final json = event.toJson();
      expect(json['stateBefore'], isNotNull);
      expect(json['stateAfter'], isNotNull);
    });

    test('a failure carrying no secrets does not invent any', () {
      final event = _failure(message: 'provider call failed');
      final serialized = event.toJson().toString();
      expect(serialized.toLowerCase(), isNot(contains('authorization:')));
      expect(serialized.toLowerCase(), isNot(contains('bearer ')));
    });
  });
}
