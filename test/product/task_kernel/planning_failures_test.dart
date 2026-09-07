import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/storage_security.dart';
import 'package:kristin_local_agent/product/task_kernel/planning_failures.dart';

/// The predecessor change answered EVERY exception with "here is the
/// conservative plan". These tests pin the corrected behavior: exactly
/// one class of failure may degrade into a plan, and the default for an
/// unrecognized error is a real failure, not a plan.
void main() {
  PlanningFailure classify(String code, [String message = 'boom']) =>
      classifyPlanningFailure(ProductException(code, message));

  group('fallback is allowed for known recoverable planning failures only', () {
    test('SCENARIO I: an invalid task plan may degrade', () {
      final failure = classify('task_plan_invalid');
      expect(failure.kind, PlanningFailureKind.recoverablePlanning);
      expect(failure.allowsConservativeFallback, isTrue);
    });

    test('every documented recoverable planning code degrades', () {
      for (final code in kRecoverablePlanningCodes) {
        final failure = classify(code);
        expect(
          failure.kind,
          PlanningFailureKind.recoverablePlanning,
          reason: '$code should be a recoverable planning failure',
        );
        expect(failure.allowsConservativeFallback, isTrue, reason: code);
      }
    });
  });

  group('everything else is a real outcome, never a plan', () {
    test('SCENARIO K: cancellation is cancellation', () {
      for (final code in kCancellationCodes) {
        final failure = classify(code);
        expect(failure.kind, PlanningFailureKind.cancelled, reason: code);
        expect(failure.allowsConservativeFallback, isFalse, reason: code);
      }
    });

    test('an unavailable provider blocks rather than degrades', () {
      for (final code in kProviderUnavailableCodes) {
        final failure = classify(code);
        expect(
          failure.kind,
          PlanningFailureKind.providerUnavailable,
          reason: code,
        );
        expect(failure.allowsConservativeFallback, isFalse, reason: code);
      }
    });

    test('a denied permission stays a governance outcome', () {
      for (final code in kPermissionDeniedCodes) {
        final failure = classify(code);
        expect(
          failure.kind,
          PlanningFailureKind.permissionDenied,
          reason: code,
        );
        expect(failure.allowsConservativeFallback, isFalse, reason: code);
      }
    });

    test('SCENARIO J: a storage failure is a real failure with evidence', () {
      for (final code in kPersistenceFailureCodes) {
        final failure = classify(code);
        expect(
          failure.kind,
          PlanningFailureKind.persistenceFailure,
          reason: code,
        );
        expect(failure.allowsConservativeFallback, isFalse, reason: code);
      }
      final failure = classifyPlanningFailure(
        ProductException(
          'storage_corrupt',
          'The task plan store is corrupted.',
          details: <String, dynamic>{'path': 'state.db'},
        ),
      );
      expect(failure.toEvidence()['fallbackAllowed'], isFalse);
      expect(failure.toEvidence()['details'], contains('path'));
    });

    test('a programming defect is a defect, not a plan', () {
      final failure = classifyPlanningFailure(
        StateError('Bad state: no element'),
        stackTrace: StackTrace.current,
      );
      expect(failure.kind, PlanningFailureKind.unexpected);
      expect(failure.code, 'planning_defect');
      expect(failure.allowsConservativeFallback, isFalse);
      // Evidence is carried, not swallowed.
      expect(failure.details['error'], contains('no element'));
      expect(failure.details['stackTrace'], isNotEmpty);
    });

    test('an UNRECOGNIZED product error defaults to a real failure', () {
      // This is the single most important assertion in this file: the
      // default must be "unexpected", not "recoverable planning". Getting
      // it backwards is what turned arbitrary bugs into a cheerful
      // safety-net plan.
      final failure = classify('some_code_nobody_has_seen_before');
      expect(failure.kind, PlanningFailureKind.unexpected);
      expect(failure.allowsConservativeFallback, isFalse);
    });

    test('an arbitrary thrown object defaults to a real failure', () {
      final failure = classifyPlanningFailure('a bare string');
      expect(failure.kind, PlanningFailureKind.unexpected);
      expect(failure.code, 'planning_failed');
      expect(failure.allowsConservativeFallback, isFalse);
    });

    test('the cancellation sentinel classifies without a code string', () {
      final failure = classifyPlanningFailure(kPlanningCancelled);
      expect(failure.kind, PlanningFailureKind.cancelled);
      expect(failure.allowsConservativeFallback, isFalse);
    });
  });

  test('classification is idempotent', () {
    final first = classify('task_plan_invalid');
    expect(classifyPlanningFailure(first), same(first));
  });

  group('the taxonomy is grounded in codes the product actually throws', () {
    test(
        'the real provider/model failure codes classify as provider '
        'unavailable', () {
      // These are thrown by ModelRegistry.providerFor and the providers
      // themselves. Before they were listed, a missing provider
      // classified as "unexpected" -- which would have blocked ordinary
      // Chat rather than degrading to the deterministic reading.
      for (final code in <String>[
        'model_provider_unavailable',
        'model_provider_mismatch',
        'model_not_installed',
        'model_load_failed',
        'model_load_timeout',
        'model_first_token_timeout',
        'model_timeout',
        'model_generation_failed',
        'model_digest_changed',
      ]) {
        expect(
          classify(code).kind,
          PlanningFailureKind.providerUnavailable,
          reason: '$code is thrown by the real model layer',
        );
      }
    });

    test('the real model protocol codes are recoverable planning failures', () {
      for (final code in <String>[
        'model_response_invalid',
        'model_response_empty',
        'model_response_too_large',
        'model_json_invalid',
        'model_protocol_exhausted',
      ]) {
        expect(
          classify(code).kind,
          PlanningFailureKind.recoverablePlanning,
          reason: '$code means the model answered badly, not that it '
              'failed to run',
        );
      }
    });

    test('the real permission and boundary codes are governance outcomes', () {
      for (final code in <String>[
        'permission_required',
        'permission_scope_missing',
        'permission_read_required',
        'tool_spawn_permission_denied',
        'path_outside_project',
        'path_traversal_rejected',
        'self_project_target_rejected',
      ]) {
        expect(
          classify(code).kind,
          PlanningFailureKind.permissionDenied,
          reason: '$code is a governed refusal',
        );
      }
    });

    test('the real storage-corruption codes are persistence failures', () {
      for (final code in <String>[
        'storage_corrupt',
        'transaction_journal_corrupt',
        'checkpoint_missing',
        'command_missing',
        'run_missing',
      ]) {
        expect(
          classify(code).kind,
          PlanningFailureKind.persistenceFailure,
          reason: '$code means stored state is missing or damaged',
        );
      }
    });
  });

  test('the recoverable and non-recoverable code sets are disjoint', () {
    final nonRecoverable = <String>{
      ...kCancellationCodes,
      ...kProviderUnavailableCodes,
      ...kPermissionDeniedCodes,
      ...kPersistenceFailureCodes,
    };
    expect(
      kRecoverablePlanningCodes.intersection(nonRecoverable),
      isEmpty,
      reason: 'a code that means two things would make fallback ambiguous',
    );
  });
}
