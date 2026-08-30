#!/usr/bin/env python3
"""Materialize scope-changing steering before an awaiting-approval run starts.

Builds on apply_scope_changing_steering_continuation.py. A run that has not
started has no WorkspaceTransaction to reach the Runner's between-item callback,
so scope-changing steering must retire that source directly and create the same
linked reconciled continuation. No source permission is inherited or granted.
"""
from __future__ import annotations

import argparse
import difflib
import subprocess
from pathlib import Path

EXPECTED_HEAD = "dd2f46ba6df3fb25adc2c8c927e807147b8f16f2"


def rep(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor, found {count}")
    return text.replace(old, new, 1)


def head(root: Path) -> str | None:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=root,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return None


TEST = r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scope steering before execution materializes a continuation immediately', () {
    final planning = File('lib/product/planning_runtime.dart').readAsStringSync();
    final runtime = File('lib/product/product_runtime.dart').readAsStringSync();

    expect(planning, contains('interruptAwaitingApprovalForSteeringReplan'));
    expect(planning, contains("run.state != RunState.awaitingApproval"));
    expect(planning, contains("'executionStarted': false"));
    expect(planning, contains("'authorityInherited': false"));

    expect(runtime, contains('source?.state == RunState.awaitingApproval'));
    expect(runtime, contains('interruptAwaitingApprovalForSteeringReplan'));
    expect(runtime, contains('_materializePendingSteeringContinuation(retired)'));
    expect(runtime, contains('RunSteeringInstruction.fromRecord(record)'));
  });
}
'''


def transform_planning(src: str) -> str:
    anchor = r'''  Future<RunRecord> createContinuationRun(
    PreparedCommand command, {
    required String sourceRunId,
  }) =>
      _createFreshRun(
        command,
        budget: AutonomyBudget.forPlan(command.plan),
        sourceRunId: sourceRunId,
      );

'''
    method = r'''  Future<RunRecord> interruptAwaitingApprovalForSteeringReplan(
    String runId,
  ) async {
    final run = await repositories.runs.get(runId);
    if (run == null) {
      throw ProductException('run_missing', 'Unknown run: $runId');
    }
    if (run.state != RunState.awaitingApproval) {
      throw ProductException(
        'steering_idle_replan_state_invalid',
        'Only an awaiting-approval run can be retired before execution for scope replanning.',
        details: <String, dynamic>{
          'runId': run.id,
          'state': run.state.name,
        },
      );
    }
    final pending = await steering.pendingReplan(run.id);
    if (pending.isEmpty) {
      throw ProductException(
        'steering_replan_missing',
        'No scope-changing steering is pending for this run.',
        details: <String, dynamic>{'runId': run.id},
      );
    }
    await steering.markReplanning(run.id, pending);
    final now = DateTime.now().toUtc();
    final interrupted = run.copyWith(
      state: RunState.interrupted,
      completedAt: now,
      failure:
          'steering_replan_requested: Scope changed before execution began.',
    );
    await _save(interrupted);
    // Awaiting approval means execution never received an authority grant.
    // Revoke defensively anyway, and never copy a grant to the continuation.
    try {
      await permissions.revokeForCommand(interrupted.command.id);
    } catch (_) {}
    final details = <String, dynamic>{
      'runId': interrupted.id,
      'instructionIds': pending.map((value) => value.id).toList(),
      'executionStarted': false,
      'workspaceTransactionCreated': false,
      'authorityInherited': false,
    };
    await _bestEffortAudit(
      'run.steering_replan_before_execution',
      interrupted.id,
      details,
    );
    await _bestEffortEvent(
      'run.steering_replan_before_execution',
      interrupted.id,
      details,
    );
    liveSignals.publish(
      LiveRunSignal.phase(
        runId: interrupted.id,
        phase: 'replanning',
        message: 'Scope changed before execution. Preparing a revised plan.',
      ),
    );
    return interrupted;
  }

'''
    return rep(src, anchor, anchor + method, "idle steering coordinator API")


def transform_runtime(src: str) -> str:
    old = r'''  Future<RunSteeringInstruction> steerRun(String runId, String text) async {
    final queued = await runs.queueSteering(runId, text);
    if (!queued.patch.requiresReplan) return queued;
    // The coordinator materializes the continuation when the source reaches
    // the verified boundary. Reload the durable record so callers receive the
    // continuation id when it was created synchronously during this call.
    final record = await repositories.runSteeringRecords.get(queued.id);
    return record == null ? queued : RunSteeringInstruction.fromRecord(record);
  }
'''
    new = r'''  Future<RunSteeringInstruction> steerRun(String runId, String text) async {
    final queued = await runs.queueSteering(runId, text);
    if (!queued.patch.requiresReplan) return queued;

    // A source that has not started has no WorkspaceTransaction and therefore
    // cannot reach the Runner's between-work-item replan callback. Retire it
    // immediately and materialize the same linked continuation. Once execution
    // has started, the Runner boundary remains authoritative instead.
    final source = await repositories.runs.get(runId);
    if (source?.state == RunState.awaitingApproval) {
      final retired = await runs.interruptAwaitingApprovalForSteeringReplan(runId);
      await _materializePendingSteeringContinuation(retired);
    }

    // Reload so callers receive durable continuation identity whenever it was
    // materialized synchronously by the idle path above (or by a live boundary).
    final record = await repositories.runSteeringRecords.get(queued.id);
    return record == null ? queued : RunSteeringInstruction.fromRecord(record);
  }
'''
    return rep(src, old, new, "idle steering runtime materialization")


def compute(root: Path) -> dict[Path, tuple[str, str]]:
    transforms = {
        root / "lib/product/planning_runtime.dart": transform_planning,
        root / "lib/product/product_runtime.dart": transform_runtime,
    }
    out: dict[Path, tuple[str, str]] = {}
    for path, fn in transforms.items():
        if not path.exists():
            raise RuntimeError(f"missing source file: {path}")
        before = path.read_text()
        out[path] = (before, fn(before))
    test = root / "test/product/steering_idle_continuation_contract_test.dart"
    before = test.read_text() if test.exists() else ""
    out[test] = (before, TEST)
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("repo")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--diff", action="store_true")
    ap.add_argument("--allow-head-drift", action="store_true")
    args = ap.parse_args()
    root = Path(args.repo).resolve()
    current = head(root)
    if current != EXPECTED_HEAD and not args.allow_head_drift:
        raise SystemExit(
            f"refusing HEAD {current}; expected {EXPECTED_HEAD}; review drift first"
        )
    changes = compute(root)
    if args.diff or not args.apply:
        for path, (before, after) in changes.items():
            if before == after:
                continue
            print("".join(difflib.unified_diff(
                before.splitlines(True), after.splitlines(True),
                fromfile=str(path.relative_to(root)),
                tofile=str(path.relative_to(root)),
            )))
    if args.apply:
        for path, (_, after) in changes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(after)
        print("Applied idle awaiting-approval steering continuation slice.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
