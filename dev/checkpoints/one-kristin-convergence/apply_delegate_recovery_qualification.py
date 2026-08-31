#!/usr/bin/env python3
"""Tighten bounded delegation recovery and repeated-decision convergence."""
from __future__ import annotations

import argparse, difflib, subprocess
from pathlib import Path

EXPECTED_HEAD = "dd2f46ba6df3fb25adc2c8c927e807147b8f16f2"

def rep(t,o,n,l):
    c=t.count(o)
    if c!=1: raise RuntimeError(f"{l}: expected exactly one anchor, found {c}")
    return t.replace(o,n,1)

def head(root):
    try: return subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True,stderr=subprocess.DEVNULL).strip()
    except Exception: return None

TEST=r'''import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bounded delegation converges across repeats and restart', () {
    final record = File('lib/product/agent_delegation_record.dart').readAsStringSync();
    final runner = File('lib/product/planning_runtime.dart').readAsStringSync();
    expect(record, contains('interrupted'));
    expect(record, contains('attempts'));
    expect(runner, contains("'agent_delegation_previous_failure'"));
    expect(runner, contains("'agent_delegation_retry_exhausted'"));
    expect(runner, contains('reconcileInterruptedDelegations'));
    expect(runner, contains('existing?.state == AgentDelegationState.succeeded'));
    expect(runner, contains("'agent.delegation_replayed'"));
  });
}
'''

def transform_record(src):
    src=rep(src,"enum AgentDelegationState { running, succeeded, failed }\n","enum AgentDelegationState { running, succeeded, failed, interrupted }\n","delegate interrupted state")
    src=rep(src,"    this.result = '',\n    this.resultSha256 = '',\n","    this.attempts = 0,\n    this.result = '',\n    this.resultSha256 = '',\n","delegate attempts ctor")
    src=rep(src,"  final AgentDelegationState state;\n  final String result;\n","  final AgentDelegationState state;\n  final int attempts;\n  final String result;\n","delegate attempts field")
    src=rep(src,"    AgentDelegationState? state,\n    String? result,\n","    AgentDelegationState? state,\n    int? attempts,\n    String? result,\n","delegate attempts copy param")
    src=rep(src,"    DateTime? completedAt,\n  }) =>\n","    DateTime? completedAt,\n    bool clearCompletedAt = false,\n  }) =>\n","delegate clear completedAt param")
    src=rep(src,"        state: state ?? this.state,\n        result: result ?? this.result,\n","        state: state ?? this.state,\n        attempts: attempts ?? this.attempts,\n        result: result ?? this.result,\n","delegate attempts copy")
    src=rep(src,"        completedAt: completedAt ?? this.completedAt,\n","        completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),\n","delegate clear completedAt copy")
    src=rep(src,"        'state': state.name,\n        if (result.isNotEmpty) 'result': result,\n","        'state': state.name,\n        'attempts': attempts,\n        if (result.isNotEmpty) 'result': result,\n","delegate attempts json")
    src=rep(src,"        state: AgentDelegationState.values\n","        attempts: int.tryParse(json['attempts']?.toString() ?? '') ?? 0,\n        state: AgentDelegationState.values\n","delegate attempts parse")
    return src

def transform_planning(src):
    # startup recovery method before reconcileInterruptedRuns
    anchor="  Future<void> reconcileInterruptedRuns() async {\n"
    method=r'''  Future<void> reconcileInterruptedDelegations() async {
    final running = (await repositories.agentDelegations.all())
        .where((value) => value.state == AgentDelegationState.running)
        .toList(growable: false);
    for (final value in running) {
      final now = DateTime.now().toUtc();
      await repositories.agentDelegations.put(
        value.copyWith(
          state: AgentDelegationState.interrupted,
          failure:
              'agent_delegation_interrupted: Application restarted during model-only specialist generation.',
          updatedAt: now,
          completedAt: now,
        ),
      );
      await _bestEffortAudit(
        'agent.delegation_interrupted',
        value.parentRunId,
        <String, dynamic>{
          'runId': value.parentRunId,
          'workItemId': value.workItemId,
          'delegationId': value.id,
          'destination': value.destination,
          'attempts': value.attempts,
          'authorityBearing': false,
          'toolAccess': false,
        },
      );
    }
  }

'''
    src=rep(src,anchor,method+anchor,"delegate restart reconciliation method")
    # convergence after succeeded replay block and before distinct budget.
    anchor2="""    final distinct = all
        .where((value) =>
"""
    guard=r'''    if (existing?.state == AgentDelegationState.failed) {
      throw ProductException(
        'agent_delegation_previous_failure',
        'The same bounded specialist delegation already failed; repeating it would only burn the parent model budget.',
        details: <String, dynamic>{
          'runId': run.id,
          'workItemId': progress.item.id,
          'delegationId': delegationId,
          'destination': destination,
          'attempts': existing!.attempts,
          'failureSha256': Sha256.text(existing.failure),
        },
      );
    }
    if (existing?.state == AgentDelegationState.interrupted &&
        existing!.attempts >= 2) {
      throw ProductException(
        'agent_delegation_retry_exhausted',
        'The model-only delegated child was interrupted twice and will not be regenerated again automatically.',
        details: <String, dynamic>{
          'runId': run.id,
          'workItemId': progress.item.id,
          'delegationId': delegationId,
          'attempts': existing.attempts,
        },
      );
    }

'''
    src=rep(src,anchor2,guard+anchor2,"delegate repeat guards")
    # persist incremented attempts on running record and use activeRecord for later copies
    old=r'''    await repositories.agentDelegations.put(
      record.copyWith(
        state: AgentDelegationState.running,
        failure: '',
        updatedAt: now,
      ),
    );
'''
    new=r'''    final activeRecord = record.copyWith(
      state: AgentDelegationState.running,
      attempts: record.attempts + 1,
      failure: '',
      updatedAt: now,
      clearCompletedAt: true,
    );
    await repositories.agentDelegations.put(activeRecord);
'''
    src=rep(src,old,new,"delegate increment attempts")
    src=rep(src,"          'delegationDepth': 1,\n      },\n    );\n\n    var updatedRun = run.copyWith(modelRequests: run.modelRequests + 1);\n","          'delegationDepth': 1,\n          'delegationAttempt': activeRecord.attempts,\n      },\n    );\n\n    var updatedRun = run.copyWith(modelRequests: run.modelRequests + 1);\n","delegate audit attempt")
    # copies after generation/failure should originate from activeRecord to preserve attempts.
    src=src.replace("        record.copyWith(\n          state: AgentDelegationState.succeeded,", "        activeRecord.copyWith(\n          state: AgentDelegationState.succeeded,",1)
    src=src.replace("        record.copyWith(\n          state: AgentDelegationState.failed,", "        activeRecord.copyWith(\n          state: AgentDelegationState.failed,",1)
    return src

def transform_runtime(src):
    return rep(src,
        "    await coordinator.reconcileInterruptedRuns();\n    await runtime.reconcileSteeringContinuations();\n    await runtime.reconcileTaskFamilyExecutions();\n",
        "    await coordinator.reconcileInterruptedRuns();\n    await coordinator.reconcileInterruptedDelegations();\n    await runtime.reconcileSteeringContinuations();\n    await runtime.reconcileTaskFamilyExecutions();\n",
        "startup delegate reconciliation")

def compute(root):
    transforms={
      root/'lib/product/agent_delegation_record.dart':transform_record,
      root/'lib/product/planning_runtime.dart':transform_planning,
      root/'lib/product/product_runtime.dart':transform_runtime,
    }
    out={}
    for p,fn in transforms.items():
      if not p.exists(): raise RuntimeError(f'missing source file: {p}')
      b=p.read_text(); out[p]=(b,fn(b))
    p=root/'test/product/runner_delegate_recovery_contract_test.dart'; b=p.read_text() if p.exists() else ''
    if b and b!=TEST: raise RuntimeError(f'{p}: file already exists with different content')
    out[p]=(b,TEST)
    return out

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('repo'); ap.add_argument('--apply',action='store_true'); ap.add_argument('--diff',action='store_true'); ap.add_argument('--allow-head-drift',action='store_true'); a=ap.parse_args(); root=Path(a.repo).resolve(); h=head(root)
    if h and h!=EXPECTED_HEAD and not a.allow_head_drift: raise SystemExit(f'refusing HEAD {h}; expected {EXPECTED_HEAD}')
    changes=compute(root)
    if a.diff or not a.apply:
      for p,(b,n) in changes.items():
        r=p.relative_to(root); print(''.join(difflib.unified_diff(b.splitlines(True),n.splitlines(True),fromfile=f'a/{r}',tofile=f'b/{r}')),end='')
    if a.apply:
      for p,(_,n) in changes.items(): p.parent.mkdir(parents=True,exist_ok=True); p.write_text(n)
    return 0
if __name__=='__main__': raise SystemExit(main())
