# MISSION-002 — Verification OS, Security, Reliability, and Continuous Certification

**Default executor:** Worker B
**Priority:** `CRITICAL_PATH`
**Roadmap phases:** `P8`
**Authority:** execution overlay only; `docs/roadmap/MASTER.md` remains human authority.

## Mission objective

Operate the canonical Test Center, Development Verification, security, reliability, observability, evaluation, certification, evidence, and independent review backbone used by every mission.

## Transfer and resume protocol

1. Re-resolve protected main, mission branch, PR, head/tree, CI, reviews, and dependency state.
2. Load this contract, the mission state, active claim, latest checkpoint, entry graph, and task interlocks.
3. Reuse valid implementation and evidence already present; never restart completed work without a proven defect.
4. Select the highest-priority dependency-satisfied task or a clearly labeled dependency-safe source/fixture/documentation packet.
5. Implement, test, document, commit, push, inspect exact-head CI, repair, obtain required independent review, and update state/checkpoint.
6. Yield only with an exact continuation point or complete the mission and release its claim.

## Current repository anchor

- Worker: `B`
- Branch: `agent/b/test-center-contracts-and-review`
- Draft PR: `#65`
- Observed head: `90c574665363140aeb6cf764ab8387714cab88cf`
- Observed tree: `438fe3f710c0fed32106ee6acdc138f4e4c6accc`
- Current work: Canonical Test Center contracts, exact reviews, certification and integration governance
- These are discovery anchors, not permission to skip live-state discovery.

## P8 — Reliability, security, observability, and evaluation

**Packet:** `docs/roadmap/anarchy/phases/P08-reliability-security-observability-and-evaluation.md`
**Current execution view:** `READY_PARALLEL_SECURITY_WORK`
**Test Center module:** `Reliability, Security & Diagnostics`

### Purpose

This is the bounded execution packet for P8. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P8-001` | Formal test hierarchy | `P0-007` | Separate architecture lint, unit, component, integration, platform, adversarial, benchmark, and release tests. | Reports identify assurance level. |
| `P8-002` | Workflow chaos expansion | `P2-010`, `P4-012` | Inject disk full, corruption, WAL loss, clock jumps, duplicate completion, cancellation races, and interrupted migrations. | Every case recovers or becomes explicit unknown. |
| `P8-003` | External-effect state machine | `P1-003` | Implement planned, authorized, started, observed, committed, compensated, unknown, and reconciliation-required. | Unknown external effects are never blindly retried. |
| `P8-004` | Terminal fault-injection suite | `P2-006` | Test hung prompts, binary output, output floods, fork bombs, process escapes, and abrupt worker death. | Kill and recovery targets pass. |
| `P8-005` | Browser fault-injection suite | `P3-017` | Test navigation races, stale DOM, popups, downloads, crashes, storage leaks, and worker death. | No false completion or profile leakage. |
| `P8-006` | Research adversarial suite | `P4-021`, `P6-006` | Test poisoned pages, malicious metadata, SSRF, rebinding, giant pages, extraction traps, and citation drift. | No unauthorized effect or unsupported citation. |
| `P8-007` | Secret scanning v2 | `P0-010` | Add Git-history scan, entropy, provider detectors, archives, binary metadata, pre-commit, CI, and safe fingerprints. | Seeded secrets are detected without printing values. |
| `P8-008` | Dependency and license policy | `P0-004` | Add vulnerability, lockfile, provenance, license, and abandoned-package gates. | Unapproved dependency cannot reach release. |
| `P8-009` | OpenTelemetry instrumentation | `P1-001` | Add correlated traces, metrics, and logs for model, policy, tools, terminal, browser, web, and update. | One run is traceable end to end without project content by default. |
| `P8-010` | Privacy and telemetry controls | `P8-009` | Make telemetry opt-in, redact content, expose preview/export/delete, and document retention. | Privacy tests and data inventory pass. |
| `P8-011` | Performance and soak suite | `P5-013`, `P8-009` | Measure startup, memory, event throughput, large repos, long terminal/browser sessions, search, datasets, and 24h runs. | Budgets and leak thresholds pass. |
| `P8-012` | Agentic security mapping | `P1-011` | Map tests and controls to OWASP Agentic Top 10 and AI Agent Security guidance. | Every applicable risk has evidence or explicit accepted gap. |
| `P8-013` | NIST AI RMF evidence map | `P6-015`, `P8-012` | Map Govern, Map, Measure, Manage outcomes to product artifacts and owners. | Release package includes current risk register and measurement report. |
| `P8-014` | Independent penetration test | `P2-013`, `P3-017`, `P7-011` | Commission review of full-host execution, browser, IPC, signing, updater, MCP/A2A, and prompt injection. | No unresolved critical/high finding. |
| `P8-015` | Failure replay corpus | `P8-002`, `P8-004`, `P8-005`, `P8-006` | Minimize every production failure into a permanent deterministic fixture. | Regression replay runs in release CI. |

### Test Center deliverables

- `P8-TC-001` formal hierarchy enforcement
- `P8-TC-002` workflow chaos suite
- `P8-TC-003` external-effect state-machine tests
- `P8-TC-004` terminal fault injection
- `P8-TC-005` browser fault injection
- `P8-TC-006` research adversarial suite
- `P8-TC-007` secret-scan seeded fixtures
- `P8-TC-008` dependency/license policy tests
- `P8-TC-009` end-to-end trace correlation
- `P8-TC-010` privacy/telemetry controls
- `P8-TC-011` performance and 24h soak
- `P8-TC-012` agentic-security evidence map
- `P8-TC-013` NIST evidence map
- `P8-TC-014` penetration-test finding regressions
- `P8-TC-015` permanent failure replay corpus

### Acceptance scenarios

- `P8-ACC-001` crash after external commit becomes reconciled or unknown
- `P8-ACC-002` disk full during object write preserves prior authority
- `P8-ACC-003` seeded secret detected without printing value
- `P8-ACC-004` one run is traceable end to end without content telemetry
- `P8-ACC-005` production failure fixture remains permanently executable

### Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Assurance levels are reported separately.
- Chaos, browser, terminal, research, prompt-injection, and replay suites pass.
- OpenTelemetry and privacy controls are production ready.
- Independent penetration test has no unresolved critical/high issue.

## Cross-mission task interlocks

- `P8-001` waits for `P0-007` from `MISSION-001`.
- `P8-002` waits for `P2-010` from `MISSION-001`.
- `P8-002` waits for `P4-012` from `MISSION-004`.
- `P8-003` waits for `P1-003` from `MISSION-001`.
- `P8-004` waits for `P2-006` from `MISSION-001`.
- `P8-005` waits for `P3-017` from `MISSION-003`.
- `P8-006` waits for `P4-021` from `MISSION-004`.
- `P8-006` waits for `P6-006` from `MISSION-006`.
- `P8-007` waits for `P0-010` from `MISSION-001`.
- `P8-008` waits for `P0-004` from `MISSION-001`.
- `P8-009` waits for `P1-001` from `MISSION-001`.
- `P8-011` waits for `P5-013` from `MISSION-005`.
- `P8-012` waits for `P1-011` from `MISSION-001`.
- `P8-013` waits for `P6-015` from `MISSION-006`.
- `P8-014` waits for `P2-013` from `MISSION-001`.
- `P8-014` waits for `P3-017` from `MISSION-003`.
- `P8-014` waits for `P7-011` from `MISSION-007`.

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
Take the repo. You are Worker B. Take MISSION-002 and continue autonomously.
```
