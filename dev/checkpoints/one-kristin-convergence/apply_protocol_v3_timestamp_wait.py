#!/usr/bin/env python3
"""Enable bounded durable protocol-v3 timestamp waits.

Scope is intentionally narrow:
- `waitUntil` is executable and durable;
- opaque `waitHandle` remains fail-closed until a real signal source exists;
- `delegate` remains fail-closed.

The script never commits/pushes and is anchored to recovered PR #291 head.
"""
from __future__ import annotations

import argparse
import difflib
import subprocess
from pathlib import Path

EXPECTED_HEAD = "dd2f46ba6df3fb25adc2c8c927e807147b8f16f2"


def rep(text: str, old: str, new: str, label: str, count: int = 1) -> str:
    found = text.count(old)
    if found != count:
        raise RuntimeError(f"{label}: expected {count} anchor(s), found {found}")
    return text.replace(old, new, count)


def head(root: Path) -> str | None:
    try:
        return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return None


def deferred_store(src: str) -> str:
    anchor = """  Future<RunRecord> _requireActiveRun(\n    String runId, {\n    required String workItemId,\n  }) async {\n"""
    method = """  /// Resolves a durable absolute-time wait once its timestamp has arrived.\n  ///\n  /// Opaque wait handles are deliberately not resolved here: without a\n  /// registered signal source, treating a handle as complete would invent an\n  /// external fact. The coordinator may call this after restart as well as\n  /// from an in-process timer.\n  Future<AgentDeferredInteraction> resolveReadyTimestampWait({\n    required String runId,\n    DateTime? now,\n  }) async {\n    final pending = await pendingForRun(runId);\n    if (pending == null) {\n      throw AgentDeferredInteractionException(\n        'agent_deferred_interaction_missing',\n        'Run $runId has no unresolved deferred interaction.',\n        details: <String, dynamic>{'runId': runId},\n      );\n    }\n    await _requireActiveRun(runId, workItemId: pending.workItemId);\n    if (pending.decision.kind != AgentDecisionV3Kind.wait ||\n        pending.decision.waitUntil == null ||\n        pending.decision.waitHandle != null) {\n      throw AgentDeferredInteractionException(\n        'agent_deferred_wait_not_timestamp',\n        'Only an absolute timestamp wait can be resolved by the time scheduler.',\n        details: <String, dynamic>{\n          'runId': runId,\n          'interactionId': pending.id,\n          'decisionKind': pending.decision.kind.wireName,\n          if (pending.decision.waitHandle != null)\n            'waitHandle': pending.decision.waitHandle,\n        },\n      );\n    }\n    final current = (now ?? DateTime.now()).toUtc();\n    final waitUntil = pending.decision.waitUntil!.toUtc();\n    if (current.isBefore(waitUntil)) {\n      throw AgentDeferredInteractionException(\n        'agent_deferred_wait_not_ready',\n        'The durable wait has not reached its requested timestamp.',\n        details: <String, dynamic>{\n          'runId': runId,\n          'interactionId': pending.id,\n          'waitUntil': waitUntil.toIso8601String(),\n          'now': current.toIso8601String(),\n        },\n      );\n    }\n\n    final checkpoint = await _workflow.createCheckpoint(\n      runId: runId,\n      workItemId: pending.workItemId,\n      kind: checkpointKind,\n      state: _state(\n        interactionId: pending.id,\n        status: AgentDeferredInteractionStatus.resolved,\n        decision: pending.decision,\n        createdAt: pending.createdAt,\n        updatedAt: current,\n      ),\n    );\n    await _workflow.appendEvent(\n      id: newId('event'),\n      type: 'agent.deferred.wait_elapsed',\n      correlationId: runId,\n      runId: runId,\n      causationId: checkpoint.id,\n      timestamp: current,\n      data: <String, dynamic>{\n        'interactionId': pending.id,\n        'checkpointId': checkpoint.id,\n        'workItemId': pending.workItemId,\n        'waitUntil': waitUntil.toIso8601String(),\n        'grantsAuthority': false,\n      },\n    );\n    return _decode(checkpoint);\n  }\n\n"""
    return rep(src, anchor, method + anchor, "timestamp wait store method")


def planning(src: str) -> str:
    src = rep(
        src,
        """  final Map<String, Future<RunRecord>> _active = <String, Future<RunRecord>>{};\n  final Map<String, String> _runLeaseOwners = <String, String>{};\n  final String _instanceId = newId('workflow_kernel');\n  static const Duration _runLeaseDuration = Duration(minutes: 2);\n  static const Duration _runLeaseHeartbeat = Duration(seconds: 20);\n""",
        """  final Map<String, Future<RunRecord>> _active = <String, Future<RunRecord>>{};\n  final Map<String, Timer> _deferredWaitTimers = <String, Timer>{};\n  final Map<String, String> _runLeaseOwners = <String, String>{};\n  final String _instanceId = newId('workflow_kernel');\n  static const Duration _runLeaseDuration = Duration(minutes: 2);\n  static const Duration _runLeaseHeartbeat = Duration(seconds: 20);\n  static const Duration _maxDeferredTimestampWait = Duration(hours: 24);\n""",
        "wait timer fields",
    )

    old_pending = """  Future<void> _throwIfDeferredInteractionPending(String runId) async {\n    final pending = await AgentDeferredInteractionStore(repositories.workflow)\n        .pendingForRun(\n      runId,\n    );\n    if (pending == null) {\n      return;\n    }\n    throw ProductException(\n      'agent_deferred_interaction_pending',\n      'Run $runId is waiting for deferred input before it can resume.',\n      details: <String, dynamic>{\n        'runId': runId,\n        'interactionId': pending.id,\n        'workItemId': pending.workItemId,\n        'decisionKind': pending.decision.toJson()['action']?.toString() ?? '',\n        'grantsAuthority': false,\n      },\n    );\n  }\n"""
    new_pending = """  Future<void> _throwIfDeferredInteractionPending(String runId) async {\n    final store = AgentDeferredInteractionStore(repositories.workflow);\n    var pending = await store.pendingForRun(runId);\n    if (pending == null) return;\n\n    // A timestamp wait can be re-evaluated after a process restart or a\n    // manual Resume. If its objective clock condition is already true,\n    // resolve the durable checkpoint before the run re-enters execution.\n    if (pending.decision.kind == AgentDecisionV3Kind.wait &&\n        pending.decision.waitUntil != null &&\n        pending.decision.waitHandle == null &&\n        !DateTime.now().toUtc().isBefore(pending.decision.waitUntil!.toUtc())) {\n      await store.resolveReadyTimestampWait(runId: runId);\n      pending = await store.pendingForRun(runId);\n      if (pending == null) return;\n    }\n\n    throw ProductException(\n      'agent_deferred_interaction_pending',\n      'Run $runId is waiting for deferred continuation before it can resume.',\n      details: <String, dynamic>{\n        'runId': runId,\n        'interactionId': pending.id,\n        'workItemId': pending.workItemId,\n        'decisionKind': pending.decision.toJson()['action']?.toString() ?? '',\n        if (pending.decision.waitUntil != null)\n          'waitUntil': pending.decision.waitUntil!.toUtc().toIso8601String(),\n        if (pending.decision.waitHandle != null)\n          'waitHandle': pending.decision.waitHandle,\n        'grantsAuthority': false,\n      },\n    );\n  }\n\n  /// Reinstates timers for durable timestamp waits after application startup.\n  Future<void> restoreDeferredWaitSchedules() async {\n    final storedRuns = await repositories.runs.all();\n    for (final run in storedRuns) {\n      if (const <RunState>{\n        RunState.cancelled,\n        RunState.succeeded,\n        RunState.failed,\n      }.contains(run.state)) {\n        continue;\n      }\n      final pending = await AgentDeferredInteractionStore(repositories.workflow)\n          .pendingForRun(run.id);\n      if (pending != null &&\n          pending.decision.kind == AgentDecisionV3Kind.wait &&\n          pending.decision.waitUntil != null &&\n          pending.decision.waitHandle == null) {\n        _scheduleDeferredTimestampWait(pending);\n      }\n    }\n  }\n\n  void cancelDeferredWaitSchedules() {\n    for (final timer in _deferredWaitTimers.values) {\n      timer.cancel();\n    }\n    _deferredWaitTimers.clear();\n  }\n\n  void _scheduleDeferredTimestampWait(AgentDeferredInteraction interaction) {\n    final waitUntil = interaction.decision.waitUntil?.toUtc();\n    if (!interaction.pending ||\n        interaction.decision.kind != AgentDecisionV3Kind.wait ||\n        waitUntil == null ||\n        interaction.decision.waitHandle != null) {\n      return;\n    }\n    _deferredWaitTimers.remove(interaction.runId)?.cancel();\n    final now = DateTime.now().toUtc();\n    final delay = waitUntil.isAfter(now) ? waitUntil.difference(now) : Duration.zero;\n    _deferredWaitTimers[interaction.runId] = Timer(delay, () {\n      unawaited(_resumeDeferredTimestampWait(\n        interaction.runId,\n        interaction.id,\n      ));\n    });\n  }\n\n  Future<void> _resumeDeferredTimestampWait(\n    String runId,\n    String interactionId,\n  ) async {\n    _deferredWaitTimers.remove(runId);\n    try {\n      final active = _active[runId];\n      if (active != null) {\n        try {\n          await active;\n        } catch (_) {\n          // The durable checkpoint below is authoritative. A suspended stack\n          // may complete with its control-flow exception while unwinding.\n        }\n      }\n      final store = AgentDeferredInteractionStore(repositories.workflow);\n      final pending = await store.pendingForRun(runId);\n      if (pending == null || pending.id != interactionId) return;\n      await store.resolveReadyTimestampWait(runId: runId);\n      final run = await repositories.runs.get(runId);\n      if (run == null || run.state != RunState.paused) return;\n      unawaited(execute(runId));\n    } on AgentDeferredInteractionException catch (error) {\n      if (error.code == 'agent_deferred_wait_not_ready') {\n        final pending = await AgentDeferredInteractionStore(repositories.workflow)\n            .pendingForRun(runId);\n        if (pending != null) _scheduleDeferredTimestampWait(pending);\n        return;\n      }\n      await _bestEffortAudit(\n        'run.deferred_wait_resume_failed',\n        runId,\n        <String, dynamic>{\n          'runId': runId,\n          'interactionId': interactionId,\n          'errorCode': error.code,\n        },\n      );\n    } catch (error) {\n      await _bestEffortAudit(\n        'run.deferred_wait_resume_failed',\n        runId,\n        <String, dynamic>{\n          'runId': runId,\n          'interactionId': interactionId,\n          'error': redactor.redact('$error'),\n        },\n      );\n    }\n  }\n"""
    src = rep(src, old_pending, new_pending, "pending deferred gate")

    old_reject = """        if (executionStep is AgentProtocolV3DeferredStep) {\n          if (!executionStep.isUserTakeover) {\n            throw ProductException(\n              'agent_decision_v3_deferred_action',\n              'Protocol v3 deferred control flow is not executable at this Runner boundary yet.',\n              details: executionStep.toEvidence(),\n            );\n          }\n          control.deferredSuspension = true;\n"""
    new_reject = """        if (executionStep is AgentProtocolV3DeferredStep) {\n          final deferredDecision = executionStep.decision;\n          final executableTimestampWait = executionStep.isWait &&\n              deferredDecision.waitUntil != null &&\n              deferredDecision.waitHandle == null;\n          if (!executionStep.isUserTakeover && !executableTimestampWait) {\n            throw ProductException(\n              'agent_decision_v3_deferred_action',\n              executionStep.isDelegation\n                  ? 'Protocol v3 delegation requires a dedicated bounded subtask coordinator and remains disabled.'\n                  : 'Protocol v3 opaque wait handles require a registered signal source and remain disabled.',\n              details: executionStep.toEvidence(),\n            );\n          }\n          if (executableTimestampWait) {\n            final delay = deferredDecision.waitUntil!\n                .toUtc()\n                .difference(DateTime.now().toUtc());\n            if (delay > _maxDeferredTimestampWait) {\n              throw ProductException(\n                'agent_decision_v3_wait_too_long',\n                'Protocol v3 timestamp waits are bounded to 24 hours.',\n                details: executionStep.toEvidence(),\n              );\n            }\n          }\n          control.deferredSuspension = true;\n"""
    src = rep(src, old_reject, new_reject, "runner wait acceptance")

    # Schedule only after the durable paused record/event has been written and
    # immediately before returning from the suspension catch.
    src = rep(
        src,
        """            liveSignals.publish(\n              LiveRunSignal.phase(\n                runId: paused.id,\n                phase: 'awaiting_user_input',\n                workItemId: progress.item.id,\n                message: 'Waiting for user input before continuing.',\n              ),\n            );\n            return paused;\n""",
        """            final waitsForUser = suspension.interaction.decision.kind ==\n                AgentDecisionV3Kind.userTakeover;\n            liveSignals.publish(\n              LiveRunSignal.phase(\n                runId: paused.id,\n                phase: waitsForUser ? 'awaiting_user_input' : 'waiting',\n                workItemId: progress.item.id,\n                message: waitsForUser\n                    ? 'Waiting for user input before continuing.'\n                    : 'Waiting until the requested UTC timestamp before continuing.',\n              ),\n            );\n            if (!waitsForUser) {\n              _scheduleDeferredTimestampWait(suspension.interaction);\n            }\n            return paused;\n""",
        "wait suspension phase",
    )

    src = rep(
        src,
        """            await _bestEffortAudit(\n              'run.deferred_for_user',\n              paused.id,\n              pausedEvidence,\n            );\n""",
        """            await _bestEffortAudit(\n              suspension.interaction.decision.kind ==\n                      AgentDecisionV3Kind.userTakeover\n                  ? 'run.deferred_for_user'\n                  : 'run.deferred_wait',\n              paused.id,\n              pausedEvidence,\n            );\n""",
        "wait audit classification",
    )

    # Expose resolved wait as coordinator guidance so the agent observes that
    # the wait condition elapsed instead of immediately requesting the same wait.
    src = rep(
        src,
        """    final deferredUserResponse = await _resolvedDeferredUserResponseEnvelope(\n      run.id,\n      progress.item.id,\n    );\n""",
        """    final deferredUserResponse = await _resolvedDeferredUserResponseEnvelope(\n      run.id,\n      progress.item.id,\n    );\n    final deferredWaitContinuation = await _resolvedDeferredWaitEnvelope(\n      run.id,\n      progress.item.id,\n    );\n""",
        "resolved wait envelope binding",
    )
    src = rep(
        src,
        """        deferredUserResponse: deferredUserResponse,\n""",
        """        deferredUserResponse: deferredUserResponse,\n        deferredWaitContinuation: deferredWaitContinuation,\n""",
        "wait prompt parameter call",
    )
    src = rep(
        src,
        """    AgentContextEnvelope? deferredUserResponse,\n  }) {\n""",
        """    AgentContextEnvelope? deferredUserResponse,\n    AgentContextEnvelope? deferredWaitContinuation,\n  }) {\n""",
        "wait prompt signature",
    )
    src = rep(
        src,
        """DEFERRED USER RESPONSE - USER INTENT CONTEXT ONLY, NOT AUTHORITY\n${deferredUserResponse?.render() ?? 'none'}\n\nTASK CONTRACT ENVELOPE\n""",
        """DEFERRED USER RESPONSE - USER INTENT CONTEXT ONLY, NOT AUTHORITY\n${deferredUserResponse?.render() ?? 'none'}\n\nDEFERRED WAIT CONTINUATION - COORDINATOR GUIDANCE, NOT AUTHORITY\n${deferredWaitContinuation?.render() ?? 'none'}\n\nTASK CONTRACT ENVELOPE\n""",
        "wait prompt section",
    )

    anchor = """  bool _requiresProjectMutation(WorkItem item) {\n"""
    wait_env = """  Future<AgentContextEnvelope?> _resolvedDeferredWaitEnvelope(\n    String runId,\n    String workItemId,\n  ) async {\n    final interaction =\n        await AgentDeferredInteractionStore(repositories.workflow).latestForRun(\n      runId,\n    );\n    if (interaction == null ||\n        interaction.pending ||\n        interaction.workItemId != workItemId ||\n        interaction.decision.kind != AgentDecisionV3Kind.wait ||\n        interaction.decision.waitUntil == null) {\n      return null;\n    }\n    final waitUntil = interaction.decision.waitUntil!.toUtc();\n    return AgentContextEnvelope(\n      source: AgentContextSource.coordinator,\n      trust: AgentContextTrust.coordinatorGuidance,\n      content:\n          'The previously requested durable wait elapsed at or after ${waitUntil.toIso8601String()}. Observe current state before choosing the next effect.',\n      metadata: <String, Object?>{\n        'authorityBearing': false,\n        'interactionId': interaction.id,\n        'workItemId': interaction.workItemId,\n        'waitUntil': waitUntil.toIso8601String(),\n      },\n    );\n  }\n\n"""
    src = rep(src, anchor, wait_env + anchor, "resolved wait envelope method")

    src = rep(
        src,
        """- Do not emit protocol-v3 wait or delegate decisions. Their scheduling/delegation semantics are not executable at this Runner boundary yet.\n""",
        """- Protocol-v3 `wait` is allowed only with an absolute UTC `waitUntil` timestamp no more than 24 hours in the future. Do not emit an opaque `waitHandle`; no signal source is registered for it yet.\n- Do not emit protocol-v3 `delegate`; bounded delegation semantics are not executable at this Runner boundary yet.\n""",
        "runner prompt deferred rules",
    )
    return src


def runtime(src: str) -> str:
    src = rep(
        src,
        """    await audit.append('application.started', 'application', <String, dynamic>{\n""",
        """    await coordinator.restoreDeferredWaitSchedules();\n    await audit.append('application.started', 'application', <String, dynamic>{\n""",
        "startup wait recovery",
    )
    src = rep(
        src,
        """    await managedProcesses.stopEphemeral();\n""",
        """    runs.cancelDeferredWaitSchedules();\n    await managedProcesses.stopEphemeral();\n""",
        "shutdown wait timers",
    )
    return src


TEST = r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String deferred;
  late String runner;
  late String runtime;

  setUpAll(() {
    deferred = File('lib/product/agent_deferred_interaction.dart').readAsStringSync();
    runner = File('lib/product/planning_runtime.dart').readAsStringSync();
    runtime = File('lib/product/product_runtime.dart').readAsStringSync();
  });

  test('timestamp wait has a durable, authority-free resolution path', () {
    expect(deferred, contains('resolveReadyTimestampWait({'));
    expect(deferred, contains("'agent.deferred.wait_elapsed'"));
    expect(deferred, contains("'agent_deferred_wait_not_ready'"));
    expect(deferred, contains("'agent_deferred_wait_not_timestamp'"));
    expect(deferred, contains("'grantsAuthority': false"));
  });

  test('runner accepts bounded timestamp waits but not opaque handles', () {
    expect(runner, contains('final executableTimestampWait = executionStep.isWait'));
    expect(runner, contains('_maxDeferredTimestampWait = Duration(hours: 24)'));
    expect(runner, contains("'agent_decision_v3_wait_too_long'"));
    expect(runner, contains('Protocol v3 opaque wait handles require a registered signal source'));
  });

  test('wait releases execution stack and resumes through a timer', () {
    expect(runner, contains('_scheduleDeferredTimestampWait(suspension.interaction);'));
    expect(runner, contains('await active;'));
    expect(runner, contains('await store.resolveReadyTimestampWait(runId: runId);'));
    expect(runner, contains('unawaited(execute(runId));'));
  });

  test('resolved wait is reintroduced only as coordinator guidance', () {
    expect(runner, contains('_resolvedDeferredWaitEnvelope('));
    expect(runner, contains('source: AgentContextSource.coordinator'));
    expect(runner, contains('trust: AgentContextTrust.coordinatorGuidance'));
    expect(runner, contains("'authorityBearing': false"));
    expect(runner, contains('DEFERRED WAIT CONTINUATION - COORDINATOR GUIDANCE, NOT AUTHORITY'));
  });

  test('runtime restores and tears down timestamp wait schedules', () {
    expect(runtime, contains('await coordinator.restoreDeferredWaitSchedules();'));
    expect(runtime, contains('runs.cancelDeferredWaitSchedules();'));
  });
}
'''


def compute(root: Path):
    mapping = {
        root / 'lib/product/agent_deferred_interaction.dart': deferred_store,
        root / 'lib/product/planning_runtime.dart': planning,
        root / 'lib/product/product_runtime.dart': runtime,
    }
    out = {}
    for path, fn in mapping.items():
        if not path.exists():
            raise RuntimeError(f"missing {path}")
        before = path.read_text()
        out[path] = (before, fn(before))
    test_path = root / 'test/product/runner_deferred_timestamp_wait_contract_test.dart'
    out[test_path] = (test_path.read_text() if test_path.exists() else '', TEST)
    return out


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument('repo')
    p.add_argument('--apply', action='store_true')
    p.add_argument('--diff', action='store_true')
    p.add_argument('--allow-head-drift', action='store_true')
    a = p.parse_args()
    root = Path(a.repo).resolve()
    current = head(root)
    if current and current != EXPECTED_HEAD and not a.allow_head_drift:
        raise SystemExit(f"refusing HEAD {current}; expected {EXPECTED_HEAD}")
    changes = compute(root)
    if a.diff or not a.apply:
        for path, (before, after) in changes.items():
            rel = path.relative_to(root)
            print(''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True), fromfile=f'a/{rel}', tofile=f'b/{rel}')), end='')
    if a.apply:
        for path, (_, after) in changes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(after)
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
