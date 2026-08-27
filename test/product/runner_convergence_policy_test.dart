import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/execution_intelligence.dart';
import 'package:kristin_local_agent/product/retry_policy.dart';

class _RecordedConvergenceProvider {
  const _RecordedConvergenceProvider(this.snapshots);

  final List<SemanticProgressSnapshot> snapshots;

  List<SemanticProgressDelta> play() {
    final engine = SemanticProgressEngine();
    final deltas = <SemanticProgressDelta>[];
    for (var index = 1; index < snapshots.length; index++) {
      deltas.add(engine.compare(snapshots[index - 1], snapshots[index]));
    }
    return deltas;
  }
}

SemanticProgressSnapshot _errors(
  Iterable<String> errors, {
  String? actionHash,
  String? resultHash,
  Set<String> evidence = const <String>{},
  Map<String, String> artifacts = const <String, String>{},
  Set<String> criteria = const <String>{},
  Set<String> external = const <String>{},
}) =>
    SemanticProgressSnapshot(
      errorCodes: errors.toSet(),
      actionHash: actionHash,
      resultHash: resultHash,
      evidenceIds: evidence,
      artifacts: artifacts,
      satisfiedCriteria: criteria,
      externalState: external,
    );

void main() {
  group('Runner progress-aware convergence', () {
    test('productive multi-repair sequence is not convergence-terminated', () {
      const provider = _RecordedConvergenceProvider(<SemanticProgressSnapshot>[
        SemanticProgressSnapshot(
          errorCodes: <String>{'E1', 'E2', 'E3', 'E4', 'E5'},
        ),
        SemanticProgressSnapshot(
          errorCodes: <String>{'E1', 'E2', 'E3', 'E4'},
        ),
        SemanticProgressSnapshot(errorCodes: <String>{'E1', 'E2', 'E3'}),
        SemanticProgressSnapshot(errorCodes: <String>{'E1', 'E2'}),
        SemanticProgressSnapshot(errorCodes: <String>{'E1'}),
        SemanticProgressSnapshot(errorCodes: <String>{}),
      ]);
      const controller = ConvergenceController();
      var stalled = 0;
      for (final delta in provider.play()) {
        expect(delta.progressClass, ConvergenceProgressClass.positiveProgress);
        stalled = delta.semanticProgress ? 0 : stalled + 1;
        final decision = controller.decide(
          stalledTurns: stalled,
          semanticProgress: delta.semanticProgress,
          progressClass: delta.progressClass,
          strongerModelAvailable: false,
          strongerModelApproved: false,
        );
        expect(decision.terminal, isFalse);
        expect(decision.action, ConvergenceAction.continueExecution);
      }
    });

    test('failure fingerprint swap is not objective progress by itself', () {
      final engine = SemanticProgressEngine();
      const before = SemanticProgressSnapshot(
        errorCodes: <String>{'compile_parse_error'},
        evidenceIds: <String>{'parse'},
      );
      const after = SemanticProgressSnapshot(
        errorCodes: <String>{'link_error'},
        evidenceIds: <String>{'parse', 'link'},
      );
      final delta = engine.compare(before, after);
      expect(delta.resolvedErrors, <String>['compile_parse_error']);
      expect(delta.newErrors, <String>['link_error']);
      expect(delta.progressClass, ConvergenceProgressClass.neutral);
      expect(delta.semanticProgress, isFalse);
    });

    test('coarse retained failure ignores changed diagnostic evidence', () {
      final engine = SemanticProgressEngine();
      const before = SemanticProgressSnapshot(
        errorCodes: <String>{'tool_failed'},
        evidenceIds: <String>{'verify:compile'},
        actionHash: 'verify_project',
        resultHash: 'compile_failure',
      );
      const after = SemanticProgressSnapshot(
        errorCodes: <String>{'tool_failed'},
        evidenceIds: <String>{'verify:compile', 'verify:test'},
        actionHash: 'verify_project',
        resultHash: 'test_failure',
      );
      final delta = engine.compare(before, after);
      expect(delta.retainedErrors, <String>['tool_failed']);
      expect(delta.repeatedResult, isFalse);
      expect(delta.progressClass, ConvergenceProgressClass.neutral);
      expect(engine.lastSameFailureCount, 1);
    });

    test('same failure stops after three unchanged recovery attempts', () {
      final provider = _RecordedConvergenceProvider(<SemanticProgressSnapshot>[
        _errors(<String>['VERIFY_X'], actionHash: 'verify', resultHash: 'x'),
        _errors(<String>['VERIFY_X'], actionHash: 'verify', resultHash: 'x'),
        _errors(<String>['VERIFY_X'], actionHash: 'verify', resultHash: 'x'),
        _errors(<String>['VERIFY_X'], actionHash: 'verify', resultHash: 'x'),
      ]);
      const controller = ConvergenceController();
      var stalled = 0;
      ConvergenceDecision? finalDecision;
      for (final delta in provider.play()) {
        stalled = delta.semanticProgress ? 0 : stalled + 1;
        finalDecision = controller.decide(
          stalledTurns: stalled,
          semanticProgress: delta.semanticProgress,
          progressClass: delta.progressClass,
          sameFailureCount: stalled,
          strongerModelAvailable: false,
          strongerModelApproved: false,
        );
      }
      expect(finalDecision, isNotNull);
      expect(finalDecision!.terminal, isTrue);
      expect(finalDecision.stopReason, 'repeated_failure_no_progress');
      expect(finalDecision.reason, isNot(contains('repair budget exhausted')));
    });

    test('live controller consumes tracked repeated failure automatically', () {
      final engine = SemanticProgressEngine();
      final controller = ConvergenceController(progressTracker: engine);
      final snapshots = <SemanticProgressSnapshot>[
        _errors(<String>['VERIFY_X'], actionHash: 'verify', resultHash: 'x'),
        _errors(<String>['VERIFY_X'], actionHash: 'verify', resultHash: 'x'),
        _errors(<String>['VERIFY_X'], actionHash: 'verify', resultHash: 'x'),
        _errors(<String>['VERIFY_X'], actionHash: 'verify', resultHash: 'x'),
      ];
      var stalled = 0;
      ConvergenceDecision? decision;
      for (var index = 1; index < snapshots.length; index++) {
        final delta = engine.compare(snapshots[index - 1], snapshots[index]);
        stalled = delta.semanticProgress ? 0 : stalled + 1;
        decision = controller.decide(
          stalledTurns: stalled,
          semanticProgress: delta.semanticProgress,
          strongerModelAvailable: false,
          strongerModelApproved: false,
        );
      }
      expect(engine.lastSameFailureCount, 3);
      expect(decision?.stopReason, 'repeated_failure_no_progress');
      expect(decision?.terminal, isTrue);
    });

    test('read-only observation does not clear repeated failure tracking', () {
      final engine = SemanticProgressEngine();
      engine.compare(
        _errors(<String>['VERIFY_X'], actionHash: 'verify', resultHash: 'x1'),
        _errors(<String>['VERIFY_X'], actionHash: 'verify', resultHash: 'x2'),
      );
      expect(engine.lastSameFailureCount, 1);
      engine.compare(
        _errors(<String>['VERIFY_X'], actionHash: 'verify', resultHash: 'x2'),
        _errors(
          <String>['VERIFY_X'],
          evidence: const <String>{'inspection'},
          actionHash: 'read_file',
          resultHash: 'read-result',
        ),
      );
      expect(engine.lastSameFailureCount, 2);
    });

    test('same action against same state is bounded', () {
      const controller = ConvergenceController();
      final decision = controller.decide(
        stalledTurns: 3,
        semanticProgress: false,
        progressClass: ConvergenceProgressClass.neutral,
        sameActionSameStateCount: 3,
        strongerModelAvailable: false,
        strongerModelApproved: false,
      );
      expect(decision.terminal, isTrue);
      expect(decision.stopReason, 'repeated_action_same_state');
      expect(decision.reason, contains('same action'));
    });

    test('same action is repeated despite changed diagnostic result text', () {
      final engine = SemanticProgressEngine();
      const before = SemanticProgressSnapshot(
        artifacts: <String, String>{'lib/a.dart': 'same'},
        errorCodes: <String>{'VERIFY_X'},
        actionHash: 'same-action',
        resultHash: 'wording-a',
      );
      const after = SemanticProgressSnapshot(
        artifacts: <String, String>{'lib/a.dart': 'same'},
        errorCodes: <String>{'VERIFY_X'},
        actionHash: 'same-action',
        resultHash: 'wording-b',
      );
      final delta = engine.compare(before, after);
      expect(delta.repeatedAction, isTrue);
      expect(delta.repeatedResult, isFalse);
      expect(engine.lastSameActionSameStateCount, 1);
    });

    test('bounded state window recognizes oscillation', () {
      final engine = SemanticProgressEngine();
      expect(engine.hasOscillation(<String>['A', 'B', 'A', 'B']), isTrue);
      expect(engine.hasOscillation(<String>['A', 'A', 'A', 'A']), isFalse);
      expect(
        engine.hasOscillation(<String>['A', 'B', 'C', 'D', 'E']),
        isFalse,
      );
      const controller = ConvergenceController();
      final decision = controller.decide(
        stalledTurns: 2,
        semanticProgress: false,
        progressClass: ConvergenceProgressClass.oscillation,
        oscillating: true,
        strongerModelAvailable: false,
        strongerModelApproved: false,
      );
      expect(decision.terminal, isTrue);
      expect(decision.stopReason, 'oscillation');
    });

    test('live controller detects A B A B material-state oscillation', () {
      final engine = SemanticProgressEngine();
      final controller = ConvergenceController(progressTracker: engine);
      const snapshots = <SemanticProgressSnapshot>[
        SemanticProgressSnapshot(
          artifacts: <String, String>{'lib/a.dart': 'A'},
        ),
        SemanticProgressSnapshot(
          artifacts: <String, String>{'lib/a.dart': 'B'},
        ),
        SemanticProgressSnapshot(
          artifacts: <String, String>{'lib/a.dart': 'A'},
        ),
        SemanticProgressSnapshot(
          artifacts: <String, String>{'lib/a.dart': 'B'},
        ),
      ];
      var stalled = 0;
      ConvergenceDecision? decision;
      for (var index = 1; index < snapshots.length; index++) {
        final delta = engine.compare(snapshots[index - 1], snapshots[index]);
        stalled = delta.semanticProgress ? 0 : stalled + 1;
        decision = controller.decide(
          stalledTurns: stalled,
          semanticProgress: delta.semanticProgress,
          strongerModelAvailable: false,
          strongerModelApproved: false,
        );
      }
      expect(engine.lastOscillating, isTrue);
      expect(decision?.terminal, isTrue);
      expect(decision?.stopReason, 'oscillation');
    });

    test('criterion swap is regression rather than fake progress', () {
      final engine = SemanticProgressEngine();
      const before = SemanticProgressSnapshot(
        satisfiedCriteria: <String>{'A'},
        evidenceIds: <String>{'before'},
      );
      const after = SemanticProgressSnapshot(
        satisfiedCriteria: <String>{'B'},
        evidenceIds: <String>{'before', 'after'},
      );
      final delta = engine.compare(before, after);
      expect(delta.criteriaSatisfied, <String>['B']);
      expect(delta.criteriaRegressed, <String>['A']);
      expect(delta.progressClass, ConvergenceProgressClass.regression);
      expect(delta.semanticProgress, isFalse);
    });

    test('mutation churn with unchanged failure is not progress', () {
      final engine = SemanticProgressEngine();
      const before = SemanticProgressSnapshot(
        artifacts: <String, String>{'lib/a.dart': 'h1'},
        evidenceIds: <String>{'e1'},
        errorCodes: <String>{'TEST_X'},
      );
      const after = SemanticProgressSnapshot(
        artifacts: <String, String>{'lib/a.dart': 'h2'},
        evidenceIds: <String>{'e1', 'e2'},
        errorCodes: <String>{'TEST_X'},
      );
      final delta = engine.compare(before, after);
      expect(delta.changedArtifactHashes, <String>['lib/a.dart']);
      expect(delta.retainedErrors, <String>['TEST_X']);
      expect(delta.progressClass, ConvergenceProgressClass.neutral);
      expect(delta.semanticProgress, isFalse);
    });

    test('read-only unique evidence is not objective progress', () {
      final engine = SemanticProgressEngine();
      const before = SemanticProgressSnapshot(
        evidenceIds: <String>{'file-a'},
        actionHash: 'read-a',
        resultHash: 'hash-a',
      );
      const after = SemanticProgressSnapshot(
        evidenceIds: <String>{'file-a', 'file-b'},
        actionHash: 'read-b',
        resultHash: 'hash-b',
      );
      final delta = engine.compare(before, after);
      expect(delta.progressClass, ConvergenceProgressClass.neutral);
      expect(delta.semanticProgress, isFalse);
    });

    test('protocol correction is separate from semantic no-progress', () {
      const taxonomy = WorkflowRetryTaxonomy();
      final protocol = taxonomy.classify('agent_action_parse_failed');
      final implementation = taxonomy.classify('verification_failed');
      expect(protocol.failureClass, WorkflowFailureClass.schemaProtocol);
      expect(protocol.disposition, RetryDisposition.retrySameAttempt);
      expect(implementation.failureClass, WorkflowFailureClass.verification);
      expect(implementation.disposition, RetryDisposition.retryNewAttempt);

      const controller = ConvergenceController();
      final semanticDecision = controller.decide(
        stalledTurns: 0,
        semanticProgress: true,
        progressClass: ConvergenceProgressClass.positiveProgress,
        strongerModelAvailable: false,
        strongerModelApproved: false,
      );
      expect(semanticDecision.action, ConvergenceAction.continueExecution);
      expect(semanticDecision.stalledTurns, 0);
    });

    test('Phi-style protocol repair can converge through implementation', () {
      const taxonomy = WorkflowRetryTaxonomy();
      final protocol = taxonomy.classify('agent_action_parse_failed');
      expect(protocol.disposition, RetryDisposition.retrySameAttempt);

      final engine = SemanticProgressEngine();
      final controller = ConvergenceController(progressTracker: engine);
      const snapshots = <SemanticProgressSnapshot>[
        SemanticProgressSnapshot(
          artifacts: <String, String>{'lib/a.dart': 'broken'},
          errorCodes: <String>{'compile_error', 'test_error', 'verify_error'},
          evidenceIds: <String>{'verify:compile'},
          resultHash: 'compile_failure',
        ),
        SemanticProgressSnapshot(
          artifacts: <String, String>{'lib/a.dart': 'repair-1'},
          errorCodes: <String>{'test_error', 'verify_error'},
          evidenceIds: <String>{'verify:compile', 'verify:test'},
          resultHash: 'test_failure',
        ),
        SemanticProgressSnapshot(
          artifacts: <String, String>{'lib/a.dart': 'repair-2'},
          errorCodes: <String>{'verify_error'},
          evidenceIds: <String>{
            'verify:compile',
            'verify:test',
            'verify:later',
          },
          resultHash: 'later-stage-failure',
        ),
        SemanticProgressSnapshot(
          artifacts: <String, String>{'lib/a.dart': 'repair-2'},
          errorCodes: <String>{},
          evidenceIds: <String>{
            'verify:compile',
            'verify:test',
            'verify:later',
            'verify:pass',
          },
          satisfiedCriteria: <String>{'criterion:verified'},
          resultHash: 'verification-pass',
        ),
      ];
      var stalled = 0;
      for (var index = 1; index < snapshots.length; index++) {
        final delta = engine.compare(snapshots[index - 1], snapshots[index]);
        expect(delta.semanticProgress, isTrue);
        stalled = delta.semanticProgress ? 0 : stalled + 1;
        final decision = controller.decide(
          stalledTurns: stalled,
          semanticProgress: delta.semanticProgress,
          strongerModelAvailable: false,
          strongerModelApproved: false,
        );
        expect(decision.terminal, isFalse);
        expect(decision.action, ConvergenceAction.continueExecution);
        expect(stalled, 0);
      }
    });

    test('missing executable is an environment block, not repair churn', () {
      const taxonomy = WorkflowRetryTaxonomy();
      for (final code in <String>[
        'executable_missing',
        'tool_executable_not_found',
        'tool_spawn_permission_denied',
      ]) {
        final classification = taxonomy.classify(code);
        expect(
          classification.failureClass,
          WorkflowFailureClass.resourceUnavailable,
        );
        expect(classification.disposition, RetryDisposition.awaitResource);
        expect(classification.retryability, 'environment');
      }
    });

    test(
      'ordinary convergence wording is specific and not repair-budget text',
      () {
        const controller = ConvergenceController();
        final decision = controller.decide(
          stalledTurns: 3,
          semanticProgress: false,
          progressClass: ConvergenceProgressClass.neutral,
          strongerModelAvailable: false,
          strongerModelApproved: false,
        );
        expect(decision.terminal, isTrue);
        expect(decision.stopReason, 'no_progress');
        expect(decision.reason, contains('no objective progress'));
        expect(decision.reason.toLowerCase(), isNot(contains('repair budget')));
      },
    );
  });
}
