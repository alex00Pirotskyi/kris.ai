import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kristin_local_agent/product/crypto_utils.dart';
import 'package:kristin_local_agent/product/domain.dart';
import 'package:kristin_local_agent/product/durable_workflow.dart';
import 'package:kristin_local_agent/product/execution_intelligence.dart';
import 'package:kristin_local_agent/product/runner_attempt_ledger.dart';

void main() {
  const policy = RunnerAttemptLedgerPolicy();

  group('runner attempt ledger policy', () {
    test('short-circuits an explicit finite command without a model', () {
      const item = WorkItem(
        id: 'work-flutter-create',
        title: 'Initialize Flutter Project',
        description:
            "Run the command 'flutter create mp3_to_url_converter'.",
        dependencies: <String>{},
        allowedTools: <String>{'run_command', 'inspect_file'},
        acceptanceCriteria: <String>['The Flutter project exists.'],
      );

      final action = policy.deterministicAction(item);
      expect(action, isNotNull);
      expect(action!.kind, 'tool');
      expect(action.tool, 'run_command');
      expect(action.arguments['executable'], 'flutter');
      expect(
        action.arguments['args'],
        <String>['create', 'mp3_to_url_converter'],
      );
    });

    test('does not deterministic-execute shell syntax', () {
      const item = WorkItem(
        id: 'work-shell',
        title: 'Unsafe command shape',
        description: "Run the command 'flutter create app && rm -rf .'.",
        dependencies: <String>{},
        allowedTools: <String>{'run_command'},
        acceptanceCriteria: <String>['The app exists.'],
      );
      expect(policy.deterministicAction(item), isNull);
    });

    test('requires run_command to already be allowed', () {
      const item = WorkItem(
        id: 'work-no-command',
        title: 'No command permission',
        description: "Run the command 'flutter create app'.",
        dependencies: <String>{},
        allowedTools: <String>{'inspect_file'},
        acceptanceCriteria: <String>['The app exists.'],
      );
      expect(policy.deterministicAction(item), isNull);
    });

    test('world state ignores evidence-only churn', () {
      const first = SemanticProgressSnapshot(
        artifacts: <String, String>{'pubspec.yaml': 'a'},
        evidenceIds: <String>{'evidence-1'},
        satisfiedCriteria: <String>{'criterion-1'},
        externalState: <String>{'process:1:running'},
        planHash: 'plan',
        actionHash: 'action-1',
        resultHash: 'result-1',
      );
      const second = SemanticProgressSnapshot(
        artifacts: <String, String>{'pubspec.yaml': 'a'},
        evidenceIds: <String>{'evidence-1', 'evidence-2'},
        satisfiedCriteria: <String>{'criterion-1'},
        externalState: <String>{'process:1:running'},
        planHash: 'plan',
        actionHash: 'action-2',
        resultHash: 'result-2',
      );
      const changed = SemanticProgressSnapshot(
        artifacts: <String, String>{'pubspec.yaml': 'b'},
        evidenceIds: <String>{'evidence-1', 'evidence-2'},
        satisfiedCriteria: <String>{'criterion-1'},
        externalState: <String>{'process:1:running'},
        planHash: 'plan',
      );

      expect(
        policy.worldStateSha256(first, mutationEpoch: 2),
        policy.worldStateSha256(second, mutationEpoch: 2),
      );
      expect(
        policy.worldStateSha256(first, mutationEpoch: 2),
        isNot(policy.worldStateSha256(changed, mutationEpoch: 2)),
      );
    });

    test('evidence alone is not material progress', () {
      const delta = SemanticProgressDelta(
        newArtifacts: <String>[],
        changedArtifactHashes: <String>[],
        newEvidence: <String>['evidence-2'],
        resolvedErrors: <String>[],
        newErrors: <String>[],
        criteriaSatisfied: <String>[],
        criteriaRegressed: <String>[],
        newExternalState: <String>[],
        planRevised: false,
        repeatedAction: false,
        repeatedResult: false,
        beforeHash: 'before',
        afterHash: 'after',
      );
      expect(policy.hasMaterialProgress(delta), isFalse);
    });
  });

  test('durable ledger closes a failed action only for the same state', () async {
    final root = await Directory.systemTemp.createTemp('kristin-ledger-');
    DurableWorkflowStore? store;
    try {
      store = await DurableWorkflowStore.open(
        databaseFile: File(
          '${root.path}${Platform.pathSeparator}workflow.sqlite3',
        ),
        migrationBackupDirectory: Directory(
          '${root.path}${Platform.pathSeparator}backups',
        ),
      );
      expect(store.schemaVersion, 7);
      const state =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const otherState =
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
      const decision =
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
      final action = <String, dynamic>{
        'action': 'tool',
        'tool': 'run_command',
        'arguments': <String, dynamic>{
          'executable': 'flutter',
          'args': <String>['create', 'app'],
        },
      };
      final actionSha = Sha256.text(canonicalJson(action));

      await store.recordAgentActionAttempt(
        runId: 'run-1',
        workItemId: 'work-1',
        workItemAttempt: 1,
        turn: 1,
        requestNumber: 1,
        stateSha256: state,
        decisionSha256: decision,
        action: action,
        actionSha256: actionSha,
        tool: 'run_command',
        outcome: 'proposed',
        beforeSha256: state,
      );
      await store.recordAgentActionAttempt(
        runId: 'run-1',
        workItemId: 'work-1',
        workItemAttempt: 1,
        turn: 1,
        requestNumber: 1,
        stateSha256: state,
        decisionSha256: decision,
        action: action,
        actionSha256: actionSha,
        tool: 'run_command',
        outcome: 'tool_error',
        errorCode: 'process_failed',
        beforeSha256: state,
        afterSha256: state,
      );

      final closed = await store.closedAgentActionBranches(
        runId: 'run-1',
        workItemId: 'work-1',
        stateSha256: state,
      );
      expect(closed, hasLength(1));
      expect(closed.single['outcome'], 'tool_error');
      expect(closed.single['actionSha256'], actionSha);
      expect(closed.single['action'], action);

      expect(
        await store.closedAgentActionBranches(
          runId: 'run-1',
          workItemId: 'work-1',
          stateSha256: otherState,
        ),
        isEmpty,
      );
    } finally {
      await store?.close();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  });
}
