# P2 master implementation specification

## Objective

P2 turns the P1 trust and policy contracts into full-host Owner Mode execution on Windows, macOS, and Linux. It introduces filesystem, finite command, interactive terminal, process-tree, package/SDK, service/application, clipboard/screen, snapshot/undo, watchdog, terminal UI, adversarial assurance, and operator documentation.

P2 is a single integration train containing fourteen internally gated tasks. It may use multiple commits on the WIP branch for reviewability, but the final integration is one protected-main PR/merge after final P1 rebasing.

## Internal topological checkpoints

### Checkpoint A — foundations

- P2-001 Owner Mode onboarding/settings
- P2-002 full filesystem service
- P2-003 finite command execution
- P2-004 automation-host technology spike
- P2-009 clipboard/screen may begin in parallel after P1 contracts are present

Checkpoint A gate:

- every host effect requires an exact P1 policy/grant decision
- Owner Mode is visibly enabled and never mislabeled as sandboxed
- absolute-path behavior and direct process execution are exercised by behavioral fixtures
- technology ADR contains measured comparison data

### Checkpoint B — execution core

- P2-005 interactive PTY
- P2-006 process-tree lifecycle manager

Checkpoint B gate:

- Windows ConPTY or selected equivalent works through the common contract
- macOS/Linux PTY works through the same lifecycle contract
- attach/detach/reconnect and transcript boundaries pass
- kill/timeout/parent-death tests leave no managed descendant

### Checkpoint C — host operations

- P2-007 package and SDK operations
- P2-008 service and application control
- P2-009 clipboard and screen capabilities
- P2-010 snapshots and undo

Checkpoint C gate:

- platform support matrices are explicit
- unsupported operations fail closed
- receipts are structured and redacted
- rollback honesty is encoded and tested

### Checkpoint D — safety and UX

- P2-011 emergency pause and kill watchdog
- P2-012 terminal UX

Checkpoint D gate:

- a frozen UI does not disable the external kill path
- terminal UI remains linked to run/task/grant identity
- keyboard and screen-reader scenarios pass

### Checkpoint E — adversarial closure

- P2-013 Owner Mode adversarial suite
- P2-014 operator guide

Checkpoint E gate:

- destructive, race, flood, fork/process-bomb, crash, restart, and recovery scenarios are tested
- no unresolved critical/high P2 finding remains
- documentation matches observed behavior and capability limits

## Architecture boundaries

### Desktop control plane

Owns policy resolution, grant issuance, durable state, evidence acceptance, user-facing Owner Mode state, and recovery decisions.

### Automation host

Out-of-process supervised executor. It can start registered workers, manage PTY/process lifecycles, stream bounded redacted output, and enforce deadlines. It cannot grant authority, read the core database directly, select arbitrary executables from untrusted environment input, or mark acceptance.

### Owner executor

Exercises broad current-account authority only under exact capability grants. It is not a sandbox.

### Platform adapters

Implement Windows/macOS/Linux behavior while preserving shared typed semantics. Missing functionality returns typed unsupported status rather than silent emulation with weaker guarantees.

## Filesystem requirements

- canonical absolute-path representation without narrowing Owner Mode to project roots
- explicit path-operation intent: inspect, read, create, write, append, copy, move, delete, metadata, enumerate, search
- Windows drive/UNC/extended-length path support where available
- macOS/Linux root and mounted-volume support
- hidden/system metadata reporting without fabricated portability
- symlink/reparse/junction handling and final-target validation
- path-race mitigation with handle-relative or equivalent safe operations where feasible
- transaction receipts and rollback plan before mutation
- bounded recursive traversal and search
- no secret/content leakage into normal logs

## Finite command requirements

- explicit executable, arguments, cwd, environment-delta, stdin policy, deadline, output budget, and grant binding
- no shell interpolation unless the selected operation explicitly requests a shell
- environment is data, never authority
- stdout and stderr remain separate bounded channels
- cancellation and process-tree termination
- stable effect record with executable identity, normalized cwd, argument hashes/redaction, exit status, timing, output hashes, and mutation/unknown markers
- owner-only access outside project roots

## PTY and process requirements

- shell selection by platform and explicit user choice
- input, resize, ANSI, Unicode, attach/detach/reconnect, transcript export
- stable process identity robust against PID reuse
- descendant tracking and full-tree termination
- parent-death cleanup
- bounded output/backpressure
- terminal history and transcript redaction
- readiness probes and typed lifecycle states
- unknown completion reconciliation before retry

## Host-operation requirements

Package/SDK:

- package-manager adapters with plan/dry-run/apply distinction
- SDK discovery with version/source/path provenance
- no hidden package-manager choice
- structured receipt and reboot/restart requirements

Service/application:

- explicit platform support matrix
- status/start/stop/open/close only when supported
- no fabricated rollback
- native elevation only through approved owner interaction

Clipboard/screen:

- capability-scoped read/write/capture
- persistent visible indication where appropriate
- redaction zones and no-model-context defaults for sensitive content
- no raw image/text data in ordinary audit records

Snapshots/undo:

- pre-mutation file backup where practical
- Git checkpoint for eligible repositories
- OS restore point only when supported and explicitly approved
- per-effect reversibility classification
- injected-failure recovery tests

## Security and assurance requirements

- deny by default outside exact grant
- exact run/task/actor/tool/profile binding
- budget and use-count consumption before effect
- revocation and expiry checked at effect time
- no secret in command line, environment logs, PTY transcript, screenshot metadata, or audit evidence
- no model-generated elevation consent
- symlink/reparse race tests
- process/fork bomb fixtures must be bounded and run only in controlled CI/sandbox environments
- emergency kill path independent of normal UI responsiveness
- signed audit checkpoint integration for high-authority effects
- independent security-review packet for P2 adversarial closure

## Aggregate exit gate

P2 closes only when:

1. Owner Mode can access the full host available to the OS account.
2. Interactive terminals work on Windows, macOS, and Linux with platform-specific evidence.
3. Process trees can be killed reliably.
4. Full-host effects are observable, journaled, and recoverable where claimed.
5. Owner Mode is clearly distinguished from isolation.
