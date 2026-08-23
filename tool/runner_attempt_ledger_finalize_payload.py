#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def patch_durable_workflow() -> None:
    path = ROOT / "lib" / "product" / "durable_workflow.dart"
    text = path.read_text(encoding="utf-8")
    marker = "\n  Future<IdempotencyClaim> claimOperation({"
    if text.count(marker) != 1:
        raise SystemExit("durable workflow insertion marker changed")
    methods = r'''

  Future<void> recordAgentActionAttempt({
    required String runId,
    required String workItemId,
    required int workItemAttempt,
    required int turn,
    required int requestNumber,
    required String stateSha256,
    required String decisionSha256,
    required String outcome,
    Map<String, dynamic>? action,
    String? actionSha256,
    String? tool,
    String? errorCode,
    String? beforeSha256,
    String? afterSha256,
    Map<String, dynamic> details = const <String, dynamic>{},
  }) =>
      _serialize<void>(() {
        _transaction<void>(() {
          final now = _now();
          final actionJson = action == null ? null : canonicalJson(action);
          final detailJson = canonicalJson(details);
          _database.execute(
            '''INSERT INTO agent_action_attempts(
                 id, run_id, work_item_id, work_item_attempt, turn,
                 request_number, state_sha256, decision_sha256, action_json,
                 action_sha256, tool, outcome, error_code, before_sha256,
                 after_sha256, details_json, details_sha256, created_at
               ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
            <Object?>[
              newId('action_attempt'),
              runId,
              workItemId,
              workItemAttempt,
              turn,
              requestNumber,
              stateSha256,
              decisionSha256,
              actionJson,
              actionSha256,
              tool,
              outcome,
              errorCode,
              beforeSha256,
              afterSha256,
              detailJson,
              Sha256.text(detailJson),
              now,
            ],
          );
        });
      });

  Future<List<Map<String, dynamic>>> closedAgentActionBranches({
    required String runId,
    required String workItemId,
    required String stateSha256,
    int limit = 5,
  }) =>
      _serialize<List<Map<String, dynamic>>>(() {
        final boundedLimit = limit.clamp(1, 20).toInt();
        final rows = _database.select(
          '''SELECT action_json, action_sha256, decision_sha256, tool, outcome,
                    error_code, details_json, created_at
             FROM agent_action_attempts
             WHERE run_id = ? AND work_item_id = ? AND state_sha256 = ?
               AND outcome IN (
                 'protocol_error', 'tool_error', 'no_progress', 'rejected',
                 'deterministic_error'
               )
             ORDER BY created_at DESC, id DESC
             LIMIT ?''',
          <Object?>[runId, workItemId, stateSha256, boundedLimit],
        );
        return rows
            .map(
              (row) => <String, dynamic>{
                'action': _decodeNullableMap(row['action_json']),
                'actionSha256': row['action_sha256']?.toString(),
                'decisionSha256': row['decision_sha256']?.toString() ?? '',
                'tool': row['tool']?.toString(),
                'outcome': row['outcome']?.toString() ?? '',
                'errorCode': row['error_code']?.toString(),
                'details': _decodeMap(row['details_json']),
                'createdAt': row['created_at']?.toString() ?? '',
              },
            )
            .toList(growable: false);
      });
'''
    text = text.replace(marker, methods + marker, 1)
    path.write_text(text, encoding="utf-8", newline="\n")


def patch_planning_runtime() -> None:
    path = ROOT / "lib" / "product" / "planning_runtime.dart"
    text = path.read_text(encoding="utf-8")

    text = replace_once(
        text,
        "import 'retry_policy.dart';\n",
        "import 'retry_policy.dart';\nimport 'runner_attempt_ledger.dart';\n",
        "runner ledger import",
    )

    old = '''    final conversational = run.command.contract.mode == CommandMode.ask &&
        isConversationalRequest(run.command.contract.request) &&
        progress.item.allowedTools.isEmpty;
    final includeUnsuccessfulEpisodes = isFailureInvestigationRequest(
'''
    new = '''    final conversational = run.command.contract.mode == CommandMode.ask &&
        isConversationalRequest(run.command.contract.request) &&
        progress.item.allowedTools.isEmpty;
    const attemptLedgerPolicy = RunnerAttemptLedgerPolicy();
    final deterministicFirstAction = conversational
        ? null
        : attemptLedgerPolicy.deterministicAction(progress.item);
    final includeUnsuccessfulEpisodes = isFailureInvestigationRequest(
'''
    text = replace_once(text, old, new, "deterministic action setup")

    old = '''    var knowledgeContext = conversational
        ? 'Automatic project retrieval is intentionally disabled for this conversational message.'
        : 'No matching project knowledge or prior successful run memory was retrieved.';
    if (!conversational) {
'''
    new = '''    var knowledgeContext = deterministicFirstAction != null
        ? 'Automatic project retrieval was skipped because this work item contains one explicit governed command.'
        : conversational
            ? 'Automatic project retrieval is intentionally disabled for this conversational message.'
            : 'No matching project knowledge or prior successful run memory was retrieved.';
    if (!conversational && deterministicFirstAction == null) {
'''
    text = replace_once(text, old, new, "determinism before retrieval")

    old = '''    final turnLimit = min(
      _agentTurnLimit(current, conversational: conversational),
      executionPhaseBudget.maxModelRequests,
    );
'''
    new = '''    final modelTurnLimit = min(
      _agentTurnLimit(current, conversational: conversational),
      executionPhaseBudget.maxModelRequests,
    );
    final turnLimit = deterministicFirstAction == null
        ? modelTurnLimit
        : max(1, modelTurnLimit + 1);
'''
    text = replace_once(text, old, new, "deterministic turn budget")

    old = '''    for (var turn = 0; turn < turnLimit; turn++) {
      await _awaitControl(control, current.budget, started);
      _enforceBudget(current, started);
      final descriptors = tools.descriptors(
'''
    new = '''    for (var turn = 0; turn < turnLimit; turn++) {
      await _awaitControl(control, current.budget, started);
      _enforceBudget(current, started);
      final stateSha256 = attemptLedgerPolicy.worldStateSha256(
        semanticSnapshot,
        mutationEpoch: current.mutations,
      );
      final closedBranches =
          await repositories.workflow.closedAgentActionBranches(
        runId: current.id,
        workItemId: progress.item.id,
        stateSha256: stateSha256,
        limit: 5,
      );
      final closedActionHashes =
          attemptLedgerPolicy.closedActionHashes(closedBranches);
      final closedDecisionHashes =
          attemptLedgerPolicy.closedDecisionHashes(closedBranches);
      final descriptors = tools.descriptors(
'''
    text = replace_once(text, old, new, "state-aware branch query")

    old = '''      var user = _userPrompt(
        current,
        progress.item,
        knowledgeContext,
        history,
        turn: turn + 1,
        turnLimit: turnLimit,
        itemMutations: itemMutations,
        inspectionEvidence: inspectionEvidence,
      );
      final pendingSteering = steering.takePending(current.id);
'''
    new = '''      var user = _userPrompt(
        current,
        progress.item,
        knowledgeContext,
        history,
        turn: turn + 1,
        turnLimit: turnLimit,
        itemMutations: itemMutations,
        inspectionEvidence: inspectionEvidence,
      );
      final closedBranchPrompt =
          attemptLedgerPolicy.closedBranchPrompt(closedBranches);
      if (closedBranchPrompt.isNotEmpty) {
        user = '$user\\n\\nCLOSED BRANCHES FROM THIS EXACT MATERIAL STATE\\n'
            '$closedBranchPrompt\\n'
            'Do not repeat any closed action. Choose a materially different valid action.';
      }
      final pendingSteering = steering.takePending(current.id);
'''
    text = replace_once(text, old, new, "closed branch prompt")

    start_marker = "      final requestNumber = current.modelRequests + 1;\n"
    end_marker = "\n      late AgentAction action;\n"
    start = text.find(start_marker)
    end = text.find(end_marker, start)
    if start < 0 or end < 0:
        raise SystemExit("model generation block markers changed")
    if text.find(start_marker, start + 1) != -1:
        raise SystemExit("model generation start marker is no longer unique")

    generation = r'''      final deterministicCandidate =
          turn == 0 ? deterministicFirstAction : null;
      final deterministicCandidateHash = deterministicCandidate == null
          ? null
          : attemptLedgerPolicy.actionSha256(deterministicCandidate);
      final deterministicSelected = deterministicCandidate != null &&
          deterministicCandidateHash != null &&
          !closedActionHashes.contains(deterministicCandidateHash);
      late final int requestNumber;
      late final ModelGenerationResult generation;
      if (deterministicSelected) {
        final candidate = deterministicCandidate;
        requestNumber = 0;
        final deterministicAt = DateTime.now().toUtc();
        final deterministicJson = attemptLedgerPolicy.actionJson(candidate);
        generation = ModelGenerationResult(
          text: jsonEncode(deterministicJson),
          identity: current.command.model,
          startedAt: deterministicAt,
          firstTokenAt: deterministicAt,
          completedAt: deterministicAt,
          inputTokens: 0,
          outputTokens: 0,
          providerDetails: const <String, dynamic>{
            'deterministicAction': true,
          },
        );
        await _bestEffortEvent(
          'work_item.deterministic_action_selected',
          current.id,
          <String, dynamic>{
            'runId': current.id,
            'workItemId': progress.item.id,
            'attempt': progress.attempts,
            'turn': turn + 1,
            'tool': candidate.tool,
            'actionHash': deterministicCandidateHash,
            'modelRequestConsumed': false,
          },
        );
      } else {
        if (current.modelRequests >= current.budget.maxModelRequests) {
          throw ProductException(
            'budget_model_requests',
            'The model-request budget was exhausted before a new branch could be generated.',
            details: _budgetSnapshot(current),
          );
        }
        requestNumber = current.modelRequests + 1;
        current = current.copyWith(modelRequests: requestNumber);
        await _save(current);
        final stopwatch = Stopwatch()..start();
        await _bestEffortEvent(
          'model.request_started',
          current.id,
          <String, dynamic>{
            'runId': current.id,
            'workItemId': progress.item.id,
            'attempt': progress.attempts,
            'turn': turn + 1,
            'requestNumber': requestNumber,
            'requestLimit': current.budget.maxModelRequests,
            'model': current.command.model.toJson(),
          },
        );
        try {
          generation = await provider.generate(
            ModelGenerationRequest(
              identity: current.command.model,
              systemPrompt: system,
              userPrompt: user,
              commandId: current.command.id,
              temperature: 0.0,
              maxOutputTokens: conversational
                  ? min(768, executionPhaseBudget.maxOutputTokens)
                  : executionPhaseBudget.maxOutputTokens,
              cancellation: control.cancellation.cancelled,
              isCancelled: () => control.cancellation.isCancelled,
              onTextDelta: (delta) {
                liveSignals.publish(
                  LiveRunSignal.modelText(
                    runId: current.id,
                    workItemId: progress.item.id,
                    model: current.command.model,
                    delta: delta,
                  ),
                );
              },
              onProgress: (modelProgress) {
                liveSignals.publish(
                  LiveRunSignal.modelProgress(
                    runId: current.id,
                    workItemId: progress.item.id,
                    model: current.command.model,
                    stage: modelProgress.stage,
                    message: modelProgress.message,
                    elapsedMilliseconds:
                        modelProgress.elapsed.inMilliseconds,
                  ),
                );
                unawaited(
                  _bestEffortEvent(
                    'model.${modelProgress.stage}',
                    current.id,
                    <String, dynamic>{
                      'runId': current.id,
                      'workItemId': progress.item.id,
                      'attempt': progress.attempts,
                      'workItemAttempt': progress.attempts,
                      'turn': turn + 1,
                      'requestNumber': requestNumber,
                      'model': current.command.model.toJson(),
                      'stage': modelProgress.stage,
                      'message': modelProgress.message,
                      'modelLoadAttempt': modelProgress.attempt,
                      'modelLoadMaxAttempts': modelProgress.maxAttempts,
                      'elapsedMilliseconds':
                          modelProgress.elapsed.inMilliseconds,
                    },
                  ),
                );
              },
            ),
          );
        } catch (error) {
          stopwatch.stop();
          await _recordModelCircuitFailure(current.command.model, error);
          await _bestEffortEvent(
            'model.request_failed',
            current.id,
            <String, dynamic>{
              'runId': current.id,
              'workItemId': progress.item.id,
              'attempt': progress.attempts,
              'turn': turn + 1,
              'requestNumber': requestNumber,
              'durationMilliseconds': stopwatch.elapsedMilliseconds,
              'errorCode': _errorCode(error),
              'error': redactor.redact('$error'),
              'budget': _budgetSnapshot(current),
            },
          );
          rethrow;
        }
        stopwatch.stop();
        await _recordModelCircuitSuccess(current.command.model);
        await _bestEffortEvent(
          'model.request_completed',
          current.id,
          <String, dynamic>{
            'runId': current.id,
            'workItemId': progress.item.id,
            'attempt': progress.attempts,
            'turn': turn + 1,
            'requestNumber': requestNumber,
            'durationMilliseconds': stopwatch.elapsedMilliseconds,
            'responseCharacters': generation.text.length,
            'responseHash': Sha256.text(generation.text),
            'budget': _budgetSnapshot(current),
          },
        );
      }
      await _evidence(
        current,
        progress.item.id,
        deterministicSelected ? EvidenceKind.audit : EvidenceKind.model,
        deterministicSelected
            ? 'Deterministic coordinator decision for work item ${progress.item.title}.'
            : 'Model decision for work item ${progress.item.title}.',
        <String, dynamic>{
          ...generation.toEvidence(),
          'responseCharacters': generation.text.length,
          'responsePreview': _modelPreview(generation.text, limit: 2000),
          'deterministicAction': deterministicSelected,
        },
      );
      final decisionSha256 = Sha256.text(generation.text);
'''
    text = text[:start] + generation + text[end:]

    old = '''        final canRequestRepair =
            protocolRepairAttempts < 2 && current.repairs < phaseRepairCeiling;
'''
    new = '''        await repositories.workflow.recordAgentActionAttempt(
          runId: current.id,
          workItemId: progress.item.id,
          workItemAttempt: progress.attempts,
          turn: turn + 1,
          requestNumber: requestNumber,
          stateSha256: stateSha256,
          decisionSha256: decisionSha256,
          outcome: deterministicSelected
              ? 'deterministic_error'
              : 'protocol_error',
          errorCode: protocolError.code,
          beforeSha256: stateSha256,
          afterSha256: stateSha256,
          details: <String, dynamic>{
            'model': current.command.model.toJson(),
            'responseCharacters': generation.text.length,
          },
        );
        final repeatedClosedDecision =
            closedDecisionHashes.contains(decisionSha256);
        if (repeatedClosedDecision) {
          await _bestEffortEvent(
            'model.protocol_branch_repeated',
            current.id,
            <String, dynamic>{
              'runId': current.id,
              'workItemId': progress.item.id,
              'attempt': progress.attempts,
              'turn': turn + 1,
              'decisionHash': decisionSha256,
              'errorCode': protocolError.code,
            },
          );
        }
        final canRequestRepair = !deterministicSelected &&
            !repeatedClosedDecision &&
            protocolRepairAttempts < 2 &&
            current.repairs < phaseRepairCeiling;
'''
    text = replace_once(text, old, new, "protocol branch ledger")

    old = '''        return _WorkOutcome(current, summary);
      }
      if (action.kind == 'fail') {
        throw ProductException(
          'model_declared_failure',
          action.summary.trim().isEmpty ? action.reason : action.summary,
        );
      }
'''
    new = '''        await repositories.workflow.recordAgentActionAttempt(
          runId: current.id,
          workItemId: progress.item.id,
          workItemAttempt: progress.attempts,
          turn: turn + 1,
          requestNumber: requestNumber,
          stateSha256: stateSha256,
          decisionSha256: decisionSha256,
          action: mapValue(
            redactor.redactJson(attemptLedgerPolicy.actionJson(action)),
          ),
          actionSha256: attemptLedgerPolicy.actionSha256(action),
          outcome: 'complete',
          beforeSha256: stateSha256,
          afterSha256: stateSha256,
          details: <String, dynamic>{
            'summaryHash': Sha256.text(summary),
          },
        );
        return _WorkOutcome(current, summary);
      }
      if (action.kind == 'fail') {
        await repositories.workflow.recordAgentActionAttempt(
          runId: current.id,
          workItemId: progress.item.id,
          workItemAttempt: progress.attempts,
          turn: turn + 1,
          requestNumber: requestNumber,
          stateSha256: stateSha256,
          decisionSha256: decisionSha256,
          action: mapValue(
            redactor.redactJson(attemptLedgerPolicy.actionJson(action)),
          ),
          actionSha256: attemptLedgerPolicy.actionSha256(action),
          outcome: 'declared_failure',
          errorCode: 'model_declared_failure',
          beforeSha256: stateSha256,
          afterSha256: stateSha256,
        );
        throw ProductException(
          'model_declared_failure',
          action.summary.trim().isEmpty ? action.reason : action.summary,
        );
      }
'''
    text = replace_once(text, old, new, "terminal decision ledger")

    marker = '''      if (phaseToolCalls >= executionPhaseBudget.maxToolCalls) {
        throw ProductException(
          'phase_budget_tool_calls',
          'The execution-phase tool-call budget was exhausted for this work-item attempt.',
'''
    if text.count(marker) != 1:
        raise SystemExit(
            f"tool proposal insertion marker: expected 1, found {text.count(marker)}"
        )
    proposal = r'''      final actionJsonForLedger = attemptLedgerPolicy.actionJson(action);
      final actionSha256ForLedger = attemptLedgerPolicy.actionSha256(action);
      final redactedActionForLedger =
          mapValue(redactor.redactJson(actionJsonForLedger));
      if (closedActionHashes.contains(actionSha256ForLedger)) {
        await repositories.workflow.recordAgentActionAttempt(
          runId: current.id,
          workItemId: progress.item.id,
          workItemAttempt: progress.attempts,
          turn: turn + 1,
          requestNumber: requestNumber,
          stateSha256: stateSha256,
          decisionSha256: decisionSha256,
          action: redactedActionForLedger,
          actionSha256: actionSha256ForLedger,
          tool: action.tool,
          outcome: 'rejected',
          errorCode: 'agent_action_branch_closed',
          beforeSha256: stateSha256,
          afterSha256: stateSha256,
        );
        history.add(<String, dynamic>{
          'turn': turn + 1,
          'coordinatorCorrection': true,
          'errorCode': 'agent_action_branch_closed',
          'tool': action.tool,
          'arguments': redactor.redactJson(action.arguments),
          'correction':
              'This exact action already failed or produced no material progress from the current state. Choose a different allowed action.',
        });
        await _bestEffortEvent(
          'agent.closed_branch_rejected',
          current.id,
          <String, dynamic>{
            'runId': current.id,
            'workItemId': progress.item.id,
            'attempt': progress.attempts,
            'turn': turn + 1,
            'actionHash': actionSha256ForLedger,
            'stateHash': stateSha256,
          },
        );
        continue;
      }
'''
    text = text.replace(marker, proposal + marker, 1)

    old = '''        if (!_isRecoverableToolInputError(toolError) ||
            toolRepairAttempts >= 3 ||
            current.repairs >= phaseRepairCeiling) {
'''
    new = '''        await repositories.workflow.recordAgentActionAttempt(
          runId: current.id,
          workItemId: progress.item.id,
          workItemAttempt: progress.attempts,
          turn: turn + 1,
          requestNumber: requestNumber,
          stateSha256: stateSha256,
          decisionSha256: decisionSha256,
          action: redactedActionForLedger,
          actionSha256: actionSha256ForLedger,
          tool: liveTool,
          outcome: deterministicSelected
              ? 'deterministic_error'
              : 'tool_error',
          errorCode: toolError.code,
          beforeSha256: stateSha256,
          afterSha256: stateSha256,
          details: <String, dynamic>{
            'errorDetails': redactor.redactJson(toolError.details),
          },
        );
        if (!_isRecoverableToolInputError(toolError) ||
            toolRepairAttempts >= 3 ||
            current.repairs >= phaseRepairCeiling) {
'''
    text = replace_once(text, old, new, "tool failure ledger")

    old = '''      final semanticDelta = executionIntelligence.progress.compare(
        semanticSnapshot,
        nextSemanticSnapshot,
      );
      stalledTurns = semanticDelta.semanticProgress ? 0 : stalledTurns + 1;
'''
    new = '''      final semanticDelta = executionIntelligence.progress.compare(
        semanticSnapshot,
        nextSemanticSnapshot,
      );
      final materialProgress =
          attemptLedgerPolicy.hasMaterialProgress(semanticDelta);
      final afterStateSha256 = attemptLedgerPolicy.worldStateSha256(
        nextSemanticSnapshot,
        mutationEpoch: current.mutations,
      );
      final actionOutcome = !result.ok
          ? (deterministicSelected ? 'deterministic_error' : 'tool_error')
          : materialProgress
              ? (deterministicSelected ? 'deterministic_ok' : 'ok')
              : 'no_progress';
      await repositories.workflow.recordAgentActionAttempt(
        runId: current.id,
        workItemId: progress.item.id,
        workItemAttempt: progress.attempts,
        turn: turn + 1,
        requestNumber: requestNumber,
        stateSha256: stateSha256,
        decisionSha256: decisionSha256,
        action: redactedActionForLedger,
        actionSha256: actionSha256ForLedger,
        tool: action.tool,
        outcome: actionOutcome,
        errorCode: result.ok
            ? null
            : result.data['errorCode']?.toString() ?? 'tool_result_not_ok',
        beforeSha256: stateSha256,
        afterSha256: afterStateSha256,
        details: <String, dynamic>{
          'materialProgress': materialProgress,
          'semanticDelta': semanticDelta.toJson(),
        },
      );
      stalledTurns = semanticDelta.semanticProgress ? 0 : stalledTurns + 1;
'''
    text = replace_once(text, old, new, "semantic outcome ledger")

    path.write_text(text, encoding="utf-8", newline="\n")


def patch_tests_and_policy() -> None:
    test_path = ROOT / "test" / "product" / "durable_workflow_kernel_test.dart"
    text = test_path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        "expect(store!.schemaVersion, 6);",
        "expect(store!.schemaVersion, 7);",
        "durable kernel schema version",
    )
    test_path.write_text(text, encoding="utf-8", newline="\n")

    kernel_path = ROOT / "tool" / "workflow_kernel_test.py"
    text = kernel_path.read_text(encoding="utf-8")
    text = replace_once(
        text,
        '            "task_attempts",\n            "run_leases",',
        '            "task_attempts",\n            "agent_action_attempts",\n            "run_leases",',
        "workflow kernel expected ledger table",
    )
    kernel_path.write_text(text, encoding="utf-8", newline="\n")


def main() -> int:
    patch_durable_workflow()
    patch_planning_runtime()
    patch_tests_and_policy()
    print("runner attempt ledger hotfix patched")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
