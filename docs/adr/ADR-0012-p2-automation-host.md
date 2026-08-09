# ADR-0012: P2 automation-host technology selection

- Status: **PROVISIONAL — selection evidence pending**
- Date: 2026-08-09
- Corrective scope: P2-004 technology selection only

## Decision

P2-004 is a technology-selection spike. It is complete when an exact reviewed
candidate has real Windows, macOS and Linux measurements sufficient to select
one automation-host architecture using startup cost, memory, packaging
footprint, repeated-run reliability and actual PTY viability.

P2-004 does **not** require production certification of every competing
architecture before a selection can be made.

The candidate set is:

1. TypeScript/Node with `node-pty` plus platform lifecycle adapters.
2. A native platform PTY supervisor.
3. A Dart control plane using a native PTY helper.

The selected candidate must demonstrate real PTY launch/input/output/resize on
Windows 2025, macOS 15 and Ubuntu 24.04. Measurements are repeated three times
per platform so reliability is observed rather than inferred from source.

Alternatives may be rejected by real measured infeasibility, missing target-OS
implementation, or an additional native bridge requirement. Rejected
candidates are not allowed to submit fabricated passing receipts.

## Roadmap boundary

This ADR restores the original roadmap split:

- **P2-004** selects the automation-host technology.
- **P2-005** implements and certifies production interactive PTY behavior,
  including input, resize, ANSI, attach, detach, reconnect and transcript.
- **P2-006** implements and certifies process-tree lifecycle behavior,
  including stable identity, descendants, stop/kill, parent death and PID reuse.

Therefore P2-004 selection evidence must not be represented as P2-005 or P2-006
acceptance, release support, production readiness or GA.

## Measurement mechanism

`.github/workflows/p2-004-technology-selection.yml` executes on ordinary GitHub
hosted Windows, macOS and Linux runners. It measures the exact candidate commit
through `tool/p2_004_technology_selection.py`.

For Node, the spike uses the repository's real `node-pty` dependency closure and
runs a direct PTY launch/input/output/resize probe. It does not require the
Windows Job-Object helper because that helper is a P2-006 lifecycle boundary,
not a prerequisite for deciding whether `node-pty` is viable.

For the native candidate, POSIX PTY behavior is exercised directly while
Windows ConPTY API availability is measured separately. A missing independent
Windows supervisor prototype is a legitimate selection risk, not a fake pass.

For Dart, the spike measures control-plane process startup/I/O and records that
an independent native PTY helper remains necessary. The Dart candidate cannot
win merely by delegating PTY behavior to the same native implementation and
calling itself independent.

The tri-platform aggregate selects a technology only when one candidate has
real PTY behavior on every target platform and all three records are bound to
the same exact Git commit.

## Security and authority invariants

Technology selection does not alter the P1/P2 authority model:

- the desktop control plane remains the policy, grant, durable-use, replay,
  storage, approval and evidence authority;
- the automation host may never issue or widen authority;
- requests remain bound to authenticated local IPC and Capability Grant v2;
- technology selection does not authorize browser behavior; browser automation
  belongs to P3;
- source-only, skipped, unavailable, malformed or partial evidence cannot be
  promoted to a measured selection.

## Previous over-constraint

The prior revision required all three candidates to prove much of the complete
P2-005/P2-006 behavioral contract before P2-004 could choose one. That made the
technology-selection task depend on production certification of multiple
implementations and duplicated downstream roadmap work.

This corrective revision preserves real cross-platform measurement while moving
production interactive-PTY and process-tree certification back to the tasks
that own those guarantees.

## Acceptance

P2-004 may move to `ACCEPTED` only after:

1. the exact clean candidate has successful Windows/macOS/Linux selection jobs;
2. the aggregate selects one candidate from exact same-commit measurements;
3. exact-current Product validation is green;
4. the measured decision is recorded in P2-004 evidence;
5. required independent technical/security review approves the exact decision.

Until then this ADR remains provisional.
