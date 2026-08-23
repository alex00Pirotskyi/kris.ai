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
        description: "Run the command 'flutter create mp3_to_url_converter'.",
        dependencies: <String>{},
        allowedTools: <String>{'run_command', 'inspect_file'},
        acceptanceCriteria: <String>['The Flutter project exists.'],
      );

      final action = policy.deterministicAction(item);
      expect(action, isNotNull);
      expect(action!.kind, 'tool');
      expect(action.tool, 'run_command');
      expect(action.arguments['executable'], 'flutter');
      expect(action.arguments['args'], <String>[
        'create',
        'mp3_to_url_converter',
      ]);
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

    test('does not infer a command from mixed prose', () {
      const item = WorkItem(
        id: 'work-mixed',
        title: 'Mixed instruction',
        description:
            "Inspect the project, then run the command 'flutter create app'.",
        dependencies: <String>{},
        allowedTools: <String>{'run_command', 'inspect_file'},
        acceptanceCriteria: <String>['The app exists.'],
      );
      expect(policy.deterministicAction(item), isNull);
    });

    test('normalizes equivalent JSON decisions before hashing', () {
      const first = '{"action":"tool","tool":"git_status","arguments":{}}';
      const second = '''```json
{
  "arguments": {},
  "tool": "git_status",
  "action": "tool"
}
```''';
      expect(policy.decisionSha256(first), policy.decisionSha256(second));
    });

    test('does not close retryable or unclassified failures', () {
      const transient = <String, dynamic>{
        'outcome': 'tool_error',
        'errorCode': 'provider_connection_failed',
        'actionSha256':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'decisionSha256':
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        'action': <String, dynamic>{'action': 'tool', 'tool': 'research_fetch'},
      };
      const resource = <String, dynamic>{
        'outcome': 'deterministic_error',
        'errorCode': 'resource_unavailable',
        'actionSha256':
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
        'decisionSha256':
            'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
        'action': <String, dynamic>{'action': 'tool', 'tool': 'run_command'},
      };
      const stateConflict = <String, dynamic>{
        'outcome': 'tool_error',
        'errorCode': 'stale_content',
        'actionSha256':
            '1111111111111111111111111111111111111111111111111111111111111111',
        'decisionSha256':
            '2222222222222222222222222222222222222222222222222222222222222222',
        'action': <String, dynamic>{'action': 'tool', 'tool': 'write_file'},
      };
      const failedResult = <String, dynamic>{
        'outcome': 'tool_error',
        'errorCode': 'tool_result_not_ok',
        'actionSha256':
            '3333333333333333333333333333333333333333333333333333333333333333',
        'decisionSha256':
            '4444444444444444444444444444444444444444444444444444444444444444',
        'action': <String, dynamic>{'action': 'tool', 'tool': 'run_command'},
      };
      final branches = <Map<String, dynamic>>[
        transient,
        resource,
        stateConflict,
        failedResult,
      ];

      expect(policy.closedActionHashes(branches), isEmpty);
      expect(policy.closedDecisionHashes(branches), isEmpty);
      expect(policy.closedBranchPrompt(branches), isEmpty);
    });

    test('closes deterministic corrections and verification failures', () {
      const correction = <String, dynamic>{
        'outcome': 'tool_error',
        'errorCode': 'path_missing',
        'actionSha256':
            'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
        'decisionSha256':
            'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
        'action': <String, dynamic>{'action': 'tool', 'tool': 'inspect_file'},
      };
      const verification = <String, dynamic>{
        'outcome': 'tool_error',
        'errorCode': 'verification_failed',
        'actionSha256':
            '5555555555555555555555555555555555555555555555555555555555555555',
        'decisionSha256':
            '6666666666666666666666666666666666666666666666666666666666666666',
        'action': <String, dynamic>{'action': 'tool', 'tool': 'verify_project'},
      };
      final branches = <Map<String, dynamic>>[correction, verification];

      expect(policy.closedActionHashes(branches), hasLength(2));
      expect(policy.closedDecisionHashes(branches), hasLength(2));
      expect(policy.closedBranchPrompt(branches), contains('path_missing'));
      expect(
        policy.closedBranchPrompt(branches),
        contains('verification_failed'),
      );
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

  test(
    'durable ledger closes only failed or no-progress same-state branches',
    () async {
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
          outcome: 'tool_error',
          errorCode: 'process_failed',
          beforeSha256: state,
          afterSha256: state,
        );
        await store.recordAgentActionAttempt(
          runId: 'run-1',
          workItemId: 'work-1',
          workItemAttempt: 1,
          turn: 2,
          requestNumber: 2,
          stateSha256: state,
          decisionSha256:
              'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
          action: <String, dynamic>{
            'action': 'tool',
            'tool': 'inspect_file',
            'arguments': <String, dynamic>{'path': 'pubspec.yaml'},
          },
          actionSha256:
              'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
          tool: 'inspect_file',
          outcome: 'ok',
          beforeSha256: state,
          afterSha256: otherState,
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
    },
  );
}
