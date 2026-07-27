# Kristin Production Roadmap Status

**Roadmap authority:** `DERIVED`
**Human constitution:** `docs/roadmap/MASTER.md`
**Machine authority:** `docs/roadmap/roadmap.yaml`
**Roadmap version:** `3.1.6-p0-010-generated-state-hygiene`
**Bootstrap scope:** `P0` and `P1`

> This file is generated from `roadmap.yaml`. Edit task status in the manifest through a reviewed work packet, then regenerate this ledger. GitHub issues may mirror this state but are not authoritative.

## Task ledger

<!-- ROADMAP_STATUS_TABLE_START -->
| Task | Status | Dependencies | Packet | Evidence |
|---|---|---|---|---|
| P0-001 | DONE | none | `tasks/completed/P0-001.md` | `release/evidence/baseline/execution.json`<br>`release/evidence/P0-001/manifest.json`<br>`release/evidence/baseline/BASELINE.md`<br>`tool/capture_baseline.py`<br>`release/evidence/P0/P0_EXIT_GATE_V44.json` |
| P0-002 | DONE | `P0-001` | `tasks/completed/P0-002.md` | `release/evidence/P0-002/manifest.json`<br>`release/evidence/P0-002/IMPLEMENTATION.md`<br>`tool/v1_trust_disablement_test.py`<br>`release/evidence/P0/P0_EXIT_GATE_V44.json` |
| P0-003 | DONE | `P0-001`, `P0-002` | `tasks/completed/P0-003.md` | `release/evidence/P0-003/ci_matrix.json`<br>`release/evidence/P0-003/IMPLEMENTATION_PLAN.md`<br>`release/evidence/P0/P0_EXIT_GATE_V44.json` |
| P0-004 | DONE | `P0-003` | `tasks/completed/P0-004.md` | `release/evidence/P0-004/comparison.json`<br>`release/evidence/P0-004/STARTER.md`<br>`config/toolchains.lock.json`<br>`release/evidence/P0-004/IMPLEMENTATION.md`<br>`release/evidence/P0/P0_EXIT_GATE_V44.json`<br>`release/evidence/P0-004/first-run.json`<br>`release/evidence/P0-004/second-run.json` |
| P0-005 | DONE | `P0-001`, `P0-002` | `tasks/completed/P0-005.md` | `release/evidence/P0-005/IMPLEMENTATION.md`<br>`docs/SUPPORT_POLICY.md`<br>`release/evidence/P0/P0_EXIT_GATE_V44.json` |
| P0-006 | DONE | `P0-003` | `tasks/completed/P0-006.md` | `release/evidence/P0-006/IMPLEMENTATION_PLAN.md`<br>`config/repository_governance.json`<br>`release/evidence/P0/P0_EXIT_GATE_V44.json`<br>`release/evidence/P0-006/github_governance_receipt.json`<br>`release/evidence/P0-006/github_governance_verification.json` |
| P0-007 | DONE | `P0-001` | `tasks/completed/P0-007.md` | `release/evidence/P0-007/manifest.json`<br>`release/evidence/P0-007/IMPLEMENTATION.md`<br>`docs/roadmap/ASSURANCE_MODEL.md`<br>`release/evidence/P0/P0_EXIT_GATE_V44.json` |
| P0-008 | DONE | `P0-001` | `tasks/completed/P0-008.md` | `release/evidence/P0-008/manifest.json`<br>`release/evidence/P0-008/IMPLEMENTATION.md`<br>`release/evidence/P0/P0_EXIT_GATE_V44.json` |
| P0-009 | DONE | `P0-001` | `tasks/completed/P0-009.md` | `evals/results/p0_009_baseline.json`<br>`evals/results/P0_009_BASELINE.md`<br>`release/evidence/P0-009/manifest.json`<br>`release/evidence/P0-009/IMPLEMENTATION.md`<br>`release/evidence/P0/P0_EXIT_GATE_V44.json` |
| P0-010 | DONE | `P0-001` | `tasks/completed/P0-010.md` | `release/evidence/P0-010/manifest.json`<br>`release/evidence/P0-010/IMPLEMENTATION.md`<br>`release/evidence/P0-010/EXECUTION.md`<br>`release/evidence/P0-010/removal_manifest.json`<br>`release/evidence/P0-010/audit.json`<br>`release/evidence/P0/P0_EXIT_GATE_V44.json` |
| P1-001 | DONE | `P0-008` | `tasks/completed/P1-001.md` | `release/evidence/P1-001/manifest.json`<br>`release/evidence/P1-001/test-results.json`<br>`release/evidence/P1-001/OWNER_APPROVAL.md` |
| P1-002 | DONE | `P1-001` | `tasks/completed/P1-002.md` | `release/evidence/P1-002/manifest.json`<br>`release/evidence/P1-002/test-results.json`<br>`release/evidence/P1-002/OWNER_APPROVAL.md` |
| P1-003 | READY | `P1-001`, `P1-002` | `tasks/active/P1-003.md` | none |
| P1-004 | NOT_STARTED | `P1-002`, `P1-003` | `tasks/active/P1-004.md` | none |
| P1-005 | READY | `P0-002`, `P1-001` | `tasks/active/P1-005.md` | none |
| P1-006 | NOT_STARTED | `P1-005` | `tasks/active/P1-006.md` | none |
| P1-007 | NOT_STARTED | `P1-006` | `tasks/active/P1-007.md` | none |
| P1-008 | NOT_STARTED | `P1-005` | `tasks/active/P1-008.md` | none |
| P1-009 | NOT_STARTED | `P1-005` | `tasks/active/P1-009.md` | none |
| P1-010 | NOT_STARTED | `P1-006`, `P1-009` | `tasks/active/P1-010.md` | none |
| P1-011 | NOT_STARTED | `P1-001`, `P1-004` | `tasks/active/P1-011.md` | none |
| P1-012 | NOT_STARTED | `P1-001`, `P1-003` | `tasks/active/P1-012.md` | none |
<!-- ROADMAP_STATUS_TABLE_END -->

## Next ready tasks

<!-- ROADMAP_NEXT_READY_START -->
- `P1-003` — Define capability grant v2 (`tasks/active/P1-003.md`)
- `P1-005` — Specify Signed Manifest v2 (`tasks/active/P1-005.md`)
<!-- ROADMAP_NEXT_READY_END -->

## Review and blocked work

- None.

## Fresh-session command

```bash
python3 tool/roadmap_control.py validate --project . --strict
python3 tool/roadmap_control.py next --project . --json
```
