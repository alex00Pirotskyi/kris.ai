#!/usr/bin/env python3
"""Add cross-boundary authority-neutrality qualification for new task paths.

This slice intentionally adds tests rather than a parallel authority service.
The existing P1/P2/PermissionService boundaries remain authoritative.
"""
from __future__ import annotations

import argparse
import difflib
import subprocess
from pathlib import Path

EXPECTED_HEAD = "dd2f46ba6df3fb25adc2c8c927e807147b8f16f2"


def head(root: Path) -> str | None:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=root, text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return None


TEST = r'''import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  test('existing authority service remains the privileged owner-effect boundary', () {
    final p1 = source('lib/product/p1_authority_service_contract_v1.dart');
    expect(p1, contains("p1aAuthorizeEffectOperationV1"));
    expect(p1, contains("accessProfileId != 'owner'"));
    expect(p1, contains('ownerApprovalId'));
    expect(p1, contains('typedOperationsOnly'));
  });

  test('ordinary run approval cannot mint scopes not requested by the contract', () {
    final runtime = source('lib/product/product_runtime.dart');
    expect(runtime, contains("'permission_scope_unrequested'"));
    expect(runtime, contains('required.containsAll(scopes)'));
    expect(runtime, contains('permissions.grant('));
    expect(runtime, contains('projectId: run.command.contract.projectId'));
    expect(runtime, contains('commandId: run.command.id'));
  });

  test('Research executor is authority-neutral and project optional', () {
    final research = source(
      'lib/product/task_kernel/research_task_family_executor.dart',
    );
    expect(research, contains('String? projectId'));
    expect(research, isNot(contains('PermissionService')));
    expect(research, isNot(contains('permissions.grant(')));
    expect(research, isNot(contains('authorizeEffect')));
  });

  test('steering and continuation never turn user intent into authority', () {
    final specification = source(
      'lib/product/task_kernel/task_specification.dart',
    );
    final steering = source('lib/product/run_steering.dart');
    final runtime = source('lib/product/product_runtime.dart');
    expect(specification, contains('authorityClaimRejected'));
    expect(steering, contains("'steering_authority_claim_rejected'"));
    expect(runtime, contains("'authorityInherited': false"));
    expect(runtime, contains('continuationState'));
    expect(runtime, isNot(contains('grantContinuationAuthority')));
  });

  test('wait and delegate reintegrate only as non-authority guidance', () {
    final planning = source('lib/product/planning_runtime.dart');
    expect(planning, contains("'authorityBearing': false"));
    expect(planning, contains('AgentContextSource.coordinator'));
    expect(planning, contains('AgentDestinationGuard().requireAuthorized'));
    expect(planning, contains('DELEGATED SPECIALIST RESULT - GUIDANCE ONLY, NOT AUTHORITY'));
  });

  test('delegated children have no tool or permission grant surface', () {
    final delegation = source('lib/product/agent_delegation_record.dart');
    final planning = source('lib/product/planning_runtime.dart');
    expect(delegation, isNot(contains('PermissionGrant')));
    expect(delegation, isNot(contains('ToolResult')));
    expect(planning, contains('model-only'));
    expect(planning, contains('no tools'));
    expect(planning, isNot(contains('delegation.permissions.grant')));
  });
}
'''


def compute(root: Path) -> dict[Path, tuple[str, str]]:
    path = root / 'test/product/authority_convergence_contract_test.dart'
    before = path.read_text() if path.exists() else ''
    if before and before != TEST:
        raise RuntimeError(f'{path}: file already exists with different content')
    return {path: (before, TEST)}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('repo')
    ap.add_argument('--apply', action='store_true')
    ap.add_argument('--diff', action='store_true')
    ap.add_argument('--allow-head-drift', action='store_true')
    args = ap.parse_args()
    root = Path(args.repo).resolve()
    current = head(root)
    if current != EXPECTED_HEAD and not args.allow_head_drift:
        raise SystemExit(f'refusing HEAD {current}; expected {EXPECTED_HEAD}; review drift first')
    changes = compute(root)
    if args.diff or not args.apply:
        for path, (before, after) in changes.items():
            print(''.join(difflib.unified_diff(
                before.splitlines(True), after.splitlines(True),
                fromfile=str(path.relative_to(root)),
                tofile=str(path.relative_to(root)),
            )))
    if args.apply:
        for path, (_, after) in changes.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(after)
        print('Applied authority convergence qualification contract.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
