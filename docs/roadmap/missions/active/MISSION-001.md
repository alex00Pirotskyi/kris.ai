# MISSION-001 — Foundation, Trust, Product Core, and Owner Mode

**Default executor:** Worker A
**Priority:** `CRITICAL_PATH`
**Roadmap phases:** `P0`, `P1`, `P2`
**Authority:** execution overlay only; `docs/roadmap/MASTER.md` remains human authority.

## Mission objective

Finish the reproducible foundation, trust and policy authority, product runtime, Owner Mode, terminal, filesystem, OS operations, recovery, and the exact P2 behavioral closure without restarting valid Worker A work.

## Transfer and resume protocol

1. Re-resolve protected main, mission branch, PR, head/tree, CI, reviews, and dependency state.
2. Load this contract, the mission state, active claim, latest checkpoint, entry graph, and task interlocks.
3. Reuse valid implementation and evidence already present; never restart completed work without a proven defect.
4. Select the highest-priority dependency-satisfied task or a clearly labeled dependency-safe source/fixture/documentation packet.
5. Implement, test, document, commit, push, inspect exact-head CI, repair, obtain required independent review, and update state/checkpoint.
6. Yield only with an exact continuation point or complete the mission and release its claim.

## Current repository anchor

- Worker: `A`
- Branch: `agent/a/p1-p2-new-roadmap-execution`
- Draft PR: `#64`
- Observed head: `89a15332019c73675a19cdacd7021fae2199d75e`
- Observed tree: `2ea1f8a718a69dba0120a4f98acb78053d6cebfb`
- Current work: P1/P1A/P2 canonical Test Center integration; behavioral closure remains externally blocked
- These are discovery anchors, not permission to skip live-state discovery.

## P0 — Stabilize, contain, and establish truth

**Packet:** `docs/roadmap/anarchy/phases/P00-stabilize-contain-and-establish-truth.md`
**Current execution view:** `DONE_LIVE_AUTHORITY`
**Test Center module:** `Repository Truth`

### Purpose

This is the bounded execution packet for P0. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P0-001` | Capture reproducible baseline | None | Inventory tree, schemas, tool registry, tests, CI, current failures, and hashes; write release/evidence/baseline/. | A clean checkout can reproduce the baseline report and every unavailable gate is explicitly marked. |
| `P0-002` | Disable insecure v1 trust decisions | `P0-001` | Remove or hard-disable authorization and update decisions that use tool/interoperability_v19.py envelope-supplied HMAC material. | Forgery test is rejected; no runtime path accepts v1 envelope trust. |
| `P0-003` | Green the current three-OS CI | `P0-001` | Fix formatting and any downstream analyzer, test, validator, and native-build failures. | Ubuntu, Windows, and macOS reach every workflow step and pass. |
| `P0-004` | Pin toolchains and GitHub Actions | `P0-003` | Pin Flutter/Dart, Python, Actions by commit SHA, and cache keys; record versions in a toolchain manifest. | Two CI reruns use identical declared inputs. |
| `P0-005` | Rewrite security and support policy | `P0-001`, `P0-002` | Update supported version, platform matrix, Owner Mode intent, sandbox truth, interop freeze, and disclosure procedure. | README, SECURITY, UI, and release classification agree. |
| `P0-006` | Protect repository governance | `P0-003` | Add CODEOWNERS, branch protection requirements, PR template, security review labels, and merge policy. | Protected main cannot merge without required checks/review. |
| `P0-007` | Split source lint from behavioral assurance | `P0-001` | Reclassify system_test.py and validator token checks; create separate report categories. | Dashboard never reports source-marker checks as behavioral proof. |
| `P0-008` | Create roadmap control files | `P0-001` | Add STATUS, ADR, risk, metric, prompt, evidence, and handoff structure. | A new AI session can find the next ready task without oral context. |
| `P0-009` | Establish initial benchmark corpus | `P0-001` | Record current results for coding, analysis, path safety, crash recovery, browser-absent, and research tasks. | Baseline is versioned and reproducible. |
| `P0-010` | Remove committed generated state | `P0-001` | Apply source-tree policy, remove caches such as __pycache__, and update ignore rules. | Clean checkout stays clean after standard tests except declared reports. |

### Test Center deliverables

- `P0-TC-001` Test hierarchy and result taxonomy
- `P0-TC-002` Test registry schema and validator
- `P0-TC-003` Baseline runner and machine-readable report
- `P0-TC-004` Evidence manifest and content-addressed output storage
- `P0-TC-005` Source-marker versus behavioral-proof separation
- `P0-TC-006` Generated-state cleanliness checks
- `P0-TC-007` Three-OS CI result aggregation
- `P0-TC-008` Regression-corpus directory and naming rules
- `P0-TC-009` Roadmap-task-to-test coverage report
- `P0-TC-010` Minimal Verification Center status screen or CLI report
- `P0-TC-011` Project Test Profile schema and resolver
- `P0-TC-012` Non-mutating development fast-check runner
- `P0-TC-013` Change-impact report and affected-test selector
- `P0-TC-014` Configurable pre-commit/pre-push verification policy
- `P0-TC-015` Development Verification CLI and initial Flutter profile

### Acceptance scenarios

- `P0-ACC-001` clean checkout reproduces baseline report
- `P0-ACC-002` test report distinguishes static checks from behavior
- `P0-ACC-003` repeated CI inputs produce equivalent declared environment
- `P0-ACC-004` generated files do not dirty the source tree
- `P0-ACC-005` insecure v1 trust fixture is rejected
- `P0-ACC-006` changing a Flutter source file selects and runs affected fast checks
- `P0-ACC-007` required pre-commit verification blocks a known failing test
- `P0-ACC-008` automatic verification does not modify source or dependency locks

### Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Current trust flaw is disabled.
- Current three-platform CI is green from formatting through native build.
- Toolchains and Actions are pinned.
- Security documentation is accurate.
- Roadmap status/evidence files exist.
- Baseline benchmark is reproducible.

## P1 — Trust, policy, and core architecture

**Packet:** `docs/roadmap/anarchy/phases/P01-trust-policy-and-core-architecture.md`
**Current execution view:** `DONE_LIVE_AUTHORITY`
**Test Center module:** `Trust, Policy & IPC`

### Purpose

This is the bounded execution packet for P1. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P1-001` | Approve runtime-boundary ADRs | `P0-008` | Define desktop, owner executor, automation host, research worker, sandbox worker, IPC, and storage boundaries. | ADRs resolve ownership and do not leave implementation-critical ambiguity. |
| `P1-002` | Define access profile v2 | `P1-001` | Create schema and domain model for chat, project, owner, owner_unattended, and isolated_untrusted modes. | Round-trip and invalid-policy tests pass in Dart and worker languages. |
| `P1-003` | Define capability grant v2 | `P1-001`, `P1-002` | Bind grants to run, task, actor, tool, paths, process, network, browser profile, secrets, budgets, expiry, and use count. | Worker rejects modified, expired, replayed, and wrong-run grants. |
| `P1-004` | Build deterministic policy engine | `P1-002`, `P1-003` | Implement mode resolution, organization/project/user overlays, and explicit widening rules. | Policy property tests prove deny-by-default and Owner Mode’s intended authority. |
| `P1-005` | Specify Signed Manifest v2 | `P0-002`, `P1-001` | Adopt Ed25519, RFC 8785 canonical JSON, external keyring, key IDs, intended use, expiry, trust domain, and revocation. | Language-neutral spec and negative vectors approved. |
| `P1-006` | Implement cross-language signing | `P1-005` | Implement Dart/Python signing and verification against shared golden vectors. | Both languages produce and verify identical vectors and reject mutations. |
| `P1-007` | Migrate or reject v1 envelopes | `P1-006` | Add explicit compatibility policy; v1 never authorizes production trust. | Downgrade and mixed-format tests pass. |
| `P1-008` | Design TUF update trust | `P1-005` | Define offline root, targets, snapshot, timestamp, delegations, thresholds, rotation, and recovery. | ADR and key ceremony runbook approved. |
| `P1-009` | Implement key storage and revocation | `P1-005` | Use OS keychain or external protected store; separate signing, API, browser, and secret-broker keys. | No private key is stored in repository or unencrypted settings. |
| `P1-010` | Create append-only signed audit checkpoints | `P1-006`, `P1-009` | Anchor audit heads with trusted keys and export verification receipts. | Tampering, truncation, reordering, and signer substitution are detected. |
| `P1-011` | Create threat model v2 | `P1-001`, `P1-004` | Map trust boundaries and OWASP agentic risks across model, tools, web, memory, MCP/A2A, terminal, and updater. | Every high-risk boundary has an owner and planned test. |
| `P1-012` | Create local authenticated IPC | `P1-001`, `P1-003` | Use named pipes/Unix sockets or loopback with mutual authentication, peer identity, request IDs, limits, and versioning. | Unprivileged unrelated local process cannot invoke a worker. |

### Test Center deliverables

- `P1-TC-001` access-profile round-trip and invalid-policy suite
- `P1-TC-002` capability-grant mutation, replay, expiry and wrong-run suite
- `P1-TC-003` deterministic policy property suite
- `P1-TC-004` Signed Manifest v2 cross-language vectors
- `P1-TC-005` downgrade and mixed-format rejection suite
- `P1-TC-006` key storage and revocation fixtures
- `P1-TC-007` audit tamper/truncation/reordering suite
- `P1-TC-008` local authenticated IPC adversarial suite
- `P1-TC-009` threat-model control coverage dashboard
- `P1-TC-010` Test Center trust certification panel

### Acceptance scenarios

- `P1-ACC-001` project profile denies unrelated absolute path
- `P1-ACC-002` owner profile authorizes intended broad path only after explicit enablement
- `P1-ACC-003` modified grant is rejected by worker
- `P1-ACC-004` unrelated local process cannot call privileged IPC
- `P1-ACC-005` audit export detects one changed event

### Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- One policy model covers safe, project, Owner, unattended, and isolated modes.
- One Signed Manifest v2 passes cross-language positive and adversarial vectors.
- Trust roots are external to envelopes.
- Local IPC rejects unauthorized callers.
- Threat model and TUF design are approved.

## P2 — Owner Mode, terminal, filesystem, and OS operations

**Packet:** `docs/roadmap/anarchy/phases/P02-owner-mode-terminal-filesystem-and-os-operations.md`
**Current execution view:** `ACTIVE_CRITICAL_PATH`
**Test Center module:** `Owner Mode & Host Operations`

### Purpose

This is the bounded execution packet for P2. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P2-001` | Owner Mode onboarding and settings | `P1-002`, `P1-004` | Build explicit enablement, persistent indicator, approval policy, data boundary, and disable/reset controls. | User can choose full access and UI never mislabels it as sandboxed. |
| `P2-002` | Full filesystem service | `P1-003`, `P1-012` | Support absolute paths, drives, shares, hidden files, metadata, search, copy, move, delete, and transactions in Owner Mode. | Cross-platform fixtures pass, including symlinks/reparse points and long paths. |
| `P2-003` | Owner finite command execution | `P1-003`, `P1-012` | Execute arbitrary direct processes with cwd/env, output limits, cancellation, and effect records. | Commands run outside projects only in Owner Mode and are fully journaled. |
| `P2-004` | Automation host technology spike | `P1-001`, `P1-012` | Compare TypeScript/node-pty+Playwright, native/Rust PTY+Playwright, and other viable packaging options. | ADR selects a solution using measured startup, memory, packaging, and reliability. |
| `P2-005` | Interactive PTY service | `P2-004` | Implement shell sessions, input, resize, ANSI, attach, detach, reconnect, and transcript. | Interactive fixtures pass on Windows, macOS, and Linux. |
| `P2-006` | Process-tree lifecycle manager | `P2-003`, `P2-005` | Track stable process identity, descendants, readiness, stop, kill, parent death, and PID reuse. | No child remains after kill/timeout in adversarial tests. |
| `P2-007` | Package and SDK operations | `P2-003` | Add package install/remove/update and SDK discovery with structured receipts. | Fixture installers and dry-run policies pass; real smoke tests run on target images. |
| `P2-008` | Service and application control | `P2-003` | Add service status/start/stop and app open/close adapters with platform-specific implementations. | Supported operations return honest status and rollback notes. |
| `P2-009` | Clipboard and screen capabilities | `P1-003`, `P1-012` | Add clipboard read/write, screen capture, active-window metadata, and redaction policy. | Capabilities obey profile and do not leak content into logs. |
| `P2-010` | Best-effort host snapshots and undo | `P2-002`, `P2-003` | Add file backups, Git checkpoints, restore points where available, and operation receipts. | Injected failures restore supported file changes and mark non-restorable effects. |
| `P2-011` | Emergency pause and kill watchdog | `P2-005`, `P2-006` | Add UI, tray, keyboard shortcut, and worker watchdog kill paths. | Kill works with frozen UI, runaway output, and descendant processes. |
| `P2-012` | Terminal UX | `P2-005`, `P2-006` | Build tabs, shell/cwd selector, search, save, copy, interrupt, terminate, attach, and run linkage. | Keyboard and screen-reader terminal scenarios pass. |
| `P2-013` | Owner Mode adversarial suite | `P2-002`, `P2-003`, `P2-006`, `P2-011` | Test destructive commands, path races, output floods, fork bombs, crashes, and restart. | Effects are intended, bounded by OS account, observable, cancellable, and recoverable where claimed. |
| `P2-014` | Owner Mode operator guide | `P2-001`, `P2-013` | Document privileges, risk, backups, unattended mode, secrets, kill, and recovery. | Guide matches UI and tested behavior. |

### Test Center deliverables

- `P2-TC-001` owner-onboarding UI tests
- `P2-TC-002` full-filesystem conformance suite
- `P2-TC-003` finite command execution suite
- `P2-TC-004` automation-host technology benchmark report
- `P2-TC-005` interactive PTY suite
- `P2-TC-006` process-tree lifecycle and escape suite
- `P2-TC-007` package/SDK operation fixtures
- `P2-TC-008` service/application-control fixtures
- `P2-TC-009` clipboard/screen privacy tests
- `P2-TC-010` snapshot/undo and partial-failure suite
- `P2-TC-011` emergency kill independent-path suite
- `P2-TC-012` terminal accessibility and UX tests
- `P2-TC-013` Owner Mode adversarial certification
- `P2-TC-014` consumer acceptance pack

### Acceptance scenarios

- `P2-ACC-001` — Create Desktop hello file
- `P2-ACC-002` create folder, rename file, move file, verify result
- `P2-ACC-003` delete then restore supported snapshot
- `P2-ACC-004` open Notepad/TextEdit/editor with created file
- `P2-ACC-005` open interactive shell, run command, interrupt, close
- `P2-ACC-006` start long-running server, verify readiness, stop complete tree
- `P2-ACC-007` freeze UI simulation and trigger independent emergency kill
- `P2-ACC-008` denied elevation is reported honestly
- `P2-ACC-009` unattended limits stop a long-running task
- `P2-ACC-010` clipboard and screenshot respect profile and redaction

### Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Owner Mode can access the full host available to the OS account.
- Interactive terminals work on Windows, macOS, and Linux, with platform-specific shell and lifecycle evidence.
- Process trees can be killed reliably.
- Full-host effects are observable, journaled, and recoverable where claimed.
- Owner Mode is clearly distinguished from isolation.

## Cross-mission task interlocks

- No cross-mission task dependency is declared in the normalized roadmap packets.

## Git, collision, and merge contract

- One active claim per mission. A replacement worker must receive a recorded yield or transfer.
- Do not edit another active mission's exclusive paths or shared authority without an explicit coordination packet.
- Workers may commit, push, update their draft PR, and iterate CI inside their bounded claim.
- No blanket right to bypass branch protection, required checks, security review, dependency gates, or roadmap authority.
- A materially changed exact candidate invalidates commit-bound reviews and evidence.
- Every significant push updates mission state and creates or supersedes a checkpoint.

## Mission definition of done

The mission is complete only when every assigned roadmap task is truthfully complete; applicable unit, contract, component, integration, negative, regression, platform, recovery, performance, acceptance, certification, and release gates pass; evidence and documentation are durable; required independent reviews bind the final exact commit/tree; and the integrated product capability works on every mandatory platform claimed by the roadmap.

## Resume command

```text
Take the repo. You are Worker A. Take MISSION-001 and continue autonomously.
```
