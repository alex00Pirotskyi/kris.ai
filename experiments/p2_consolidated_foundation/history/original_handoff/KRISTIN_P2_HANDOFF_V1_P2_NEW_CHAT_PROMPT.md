# New-chat execution prompt — build the complete Kristin P2 integration train

You are taking over development of Kristin, a local-first native desktop AI agent for Windows, macOS, and Linux.

Repository:

- GitHub: `https://github.com/alex00Pirotskyi/kris.ai`
- Operator checkout: `C:\dev\flutter\kris_studio_ai_2`
- Git Bash path: `/c/dev/flutter/kris_studio_ai_2`
- P2 parallel worktree: `/c/dev/flutter/kris_studio_ai_2_p2`
- P2 WIP branch: `integration/p2-full-train-wip`

You have been given:

1. `KRISTIN_P2_PARALLEL_BUILD_HANDOFF_V1.zip`
2. a tracked-source snapshot created from the latest P1 closure/P2 base branch
3. current logs and repository state in the handoff bundle

## Mission

Build **all of P2 — Owner Mode, filesystem, terminal, process, and host operations — as one guarded integration train**.

The canonical P2 task graph remains P2-001 through P2-014. Reducing merge cycles does not permit removing task evidence, skipping dependencies, weakening security, or claiming untested behavior.

Develop on the P2 side branch while P1 is being finalized. Do not merge P2. Keep the P2 branch rebaseable onto the final P1 protected-main commit.

## Mandatory P2 scope

Implement, test, document, and evidence:

- P2-001 Owner Mode onboarding and settings
- P2-002 Full filesystem service
- P2-003 Owner finite command execution
- P2-004 Automation-host technology spike and accepted ADR
- P2-005 Interactive PTY service
- P2-006 Process-tree lifecycle manager
- P2-007 Package and SDK operations
- P2-008 Service and application control
- P2-009 Clipboard and screen capabilities
- P2-010 Best-effort host snapshots and undo
- P2-011 Emergency pause and kill watchdog
- P2-012 Terminal UX
- P2-013 Owner Mode adversarial suite
- P2-014 Owner Mode operator guide

Use `P2_TASK_MATRIX.json` and `P2_MASTER_IMPLEMENTATION_SPEC.md` as the authoritative P2 handoff contract.

## P1 contracts P2 must consume

P2 must build on, not bypass:

- Access Profile v2: `chat`, `project`, `owner`, `owner_unattended`, `isolated_untrusted`
- Capability Grant v2 exact run/task/actor/tool/scope/budget/expiry/use-count binding
- deterministic deny-by-default policy resolution
- external trust roots and Signed Manifest v2
- protected key handles and revocation
- signed audit checkpoints
- authenticated local IPC
- the desktop control plane as policy/storage/evidence authority
- the automation host as a supervised executor, never a grant issuer

Every effect must be preceded by a valid policy decision and capability grant. Model text, web content, repositories, tool output, environment variables, and workers are not authorization roots.

## Parallel-branch requirements

To minimize rebase conflicts:

1. Put feature implementation and behavioral tests in P2-specific files first.
2. Keep shared integration surfaces in a final isolated commit:
   - `.github/workflows/ci.yml`
   - `SOURCE_MANIFEST.sha256`
   - `docs/roadmap/STATUS.md`
   - `docs/roadmap/HANDOFF.md`
   - `docs/roadmap/DECISIONS.md`
   - `docs/roadmap/roadmap.yaml`
   - `tool/validate_release.py`
   - `tool/verify.sh`
   - `test/product/source_contract_test.dart`
3. Never edit P1 task evidence or mark P1 differently.
4. Preserve `tasks/active/.gitkeep` even when no task packet is active.
5. Do not generate the final source manifest until after rebasing onto final P1 main.
6. Do not open or merge a P2 PR while P1 is unresolved.

## Required architecture qualities

- Windows, macOS, and Linux remain synchronized mandatory platforms.
- Platform adapters may differ, but capability, cancellation, evidence, and lifecycle semantics must match.
- Unsupported backend operations fail closed and return typed honest status.
- Owner Mode can access the entire host available to the current OS account, including paths outside registered projects.
- Owner Mode is not containment. `isolated_untrusted` remains separate and must not silently downgrade.
- Elevation requires visible OS-native owner interaction or preconfigured external authority; unattended model output cannot synthesize consent.
- Commands, PTY sessions, processes, descendants, screen/clipboard access, packages, services, and filesystem effects must be journaled and bounded.
- Raw secrets must never appear in prompts, ordinary logs, transcripts, screenshots, or evidence.
- Cancellation and kill are idempotent. Ambiguous completion becomes `unknown` and is reconciled before retry.
- Undo is explicitly best-effort. Every operation records whether it is reversible, partially reversible, or irreversible.

## Technology-spike rule

Do not choose the automation-host technology by preference alone. Measure at least:

- TypeScript/Node with node-pty and Playwright-compatible packaging
- a native/Rust PTY supervisor with browser sidecar or equivalent
- any viable Dart/native alternative discovered in the current codebase

Measure cold start, steady RSS, package size, process-tree termination, Windows ConPTY behavior, macOS/Linux PTY fidelity, attach/reconnect, code-signing impact, updater impact, and three-platform packaging reliability. Record an ADR with measured evidence and rejected alternatives.

Browse current official documentation and primary sources when selecting current libraries or platform APIs. Do not rely on outdated package assumptions.

## Required behavioral and adversarial tests

At minimum cover:

- absolute paths, drive roots, UNC/network shares where available, hidden files, Unicode, long paths
- symlink, junction, and reparse-point traversal/races
- copy/move/delete transaction interruption and recovery
- cwd/env handling without treating environment values as authority
- stdout/stderr floods, binary output, ANSI, Unicode, resize, detach/reconnect
- process parent death, PID reuse, descendant escape, timeout, cancellation, forced kill
- package dry runs and controlled fixture installs
- service/application support matrix and honest unsupported results
- clipboard/screen redaction and no-log-leak tests
- snapshots, backups, Git checkpoints, and honest non-restorable effects
- frozen UI emergency kill and external watchdog
- destructive commands, fork/process bombs in bounded fixtures, crashes, restart, and reconciliation
- keyboard and screen-reader terminal workflows

Tests must distinguish source-contract checks from actual behavioral proof.

## Required task evidence

For every P2 task create:

- task packet under `tasks/completed/P2-xxx.md` only after its gate passes
- `release/evidence/P2-xxx/IMPLEMENTATION.md`
- `release/evidence/P2-xxx/OWNER_APPROVAL.md`
- `release/evidence/P2-xxx/manifest.json`
- `release/evidence/P2-xxx/test-results.json`

Also create aggregate P2 evidence and a P2 exit-gate test. Security-critical claims require an independent review packet; do not represent the same AI conversation as an independent security reviewer.

## Expected final deliverables

After the implementation is complete and rebased onto final P1 main, generate:

- `KRISTIN_P2_FULL_INTEGRATION_V<next>.zip`
- `integrate_kristin_p2_full_train_v<next>.sh`
- `KRISTIN_P2_FULL_INTEGRATION_V<next>_README_FIRST.md`
- `KRISTIN_P2_FULL_INTEGRATION_V<next>_VALIDATION.md`
- ZIP and launcher SHA-256 files

The final launcher must:

1. require final P1 closure on protected main
2. verify exact successful merged-main Windows/macOS/Linux CI for the P1 base SHA
3. preserve the operator checkout byte-for-byte
4. use a disposable worktree
5. apply or reuse the complete P2 train
6. run internal P2 task gates in dependency order
7. run the P2 exit gate and complete regression ladder
8. enforce governed Dart/test source inventories without mixing library-only and global inventories
9. preserve `tasks/active/.gitkeep`
10. refresh source authority only after final staging
11. verify exact staged scope and `git diff --check`
12. commit once for the aggregate P2 train, push non-force, and run exact tri-OS branch CI
13. create one PR, require appropriate review, and merge only when authorized
14. require exact tri-OS merged-main CI
15. report the next integration train without claiming it is already complete

## Definition of done

P2 is complete only when:

- P2-001 through P2-014 are `DONE`
- every task has executable evidence
- the P2 exit gate passes
- Owner Mode reaches the full authority of the current OS account without being described as a sandbox
- terminal and process lifecycle behavior pass on Windows, macOS, and Linux
- descendant processes are reliably terminated
- full-host effects are observable, journaled, cancellable, and recoverable where claimed
- the operator guide agrees with tested UI behavior
- branch and protected-main CI are green for the exact commits on all three desktop platforms

Do not ask the user to choose routine implementation details that can be derived from the repository and roadmap. Inspect the supplied source, make the safest production-grade choices, document assumptions, and deliver the most complete working package possible.
