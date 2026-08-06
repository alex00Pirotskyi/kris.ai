# MISSION-009 — Core Integration, Alpha, Beta, Release Candidate, and Synchronized GA

**Default executor:** Worker A
**Priority:** `TERMINAL_PATH`
**Roadmap phases:** `P10`, `P20`
**Authority:** execution overlay only; `docs/roadmap/MASTER.md` remains human authority.

## Mission objective

Run the P10 integration checkpoint and later the P20 maximum-capability freeze, alpha, beta, RC, synchronized GA, recovery, support, and release evidence without confusing the early checkpoint with final GA.

## Transfer and resume protocol

1. Re-resolve protected main, mission branch, PR, head/tree, CI, reviews, and dependency state.
2. Load this contract, the mission state, active claim, latest checkpoint, entry graph, and task interlocks.
3. Reuse valid implementation and evidence already present; never restart completed work without a proven defect.
4. Select the highest-priority dependency-satisfied task or a clearly labeled dependency-safe source/fixture/documentation packet.
5. Implement, test, document, commit, push, inspect exact-head CI, repair, obtain required independent review, and update state/checkpoint.
6. Yield only with an exact continuation point or complete the mission and release its claim.

## Current repository anchor

- No active claim. The mission is available only when its entry dependencies and ownership checks pass.

## P10 — Core alpha, beta, release candidate, and integration checkpoint

**Packet:** `docs/roadmap/anarchy/phases/P10-core-alpha-beta-release-candidate-and-integration-checkpoint.md`
**Current execution view:** `BLOCKED_RELEASE_CHECKPOINT`
**Test Center module:** `Core Release Readiness`

### Purpose

This is the bounded execution packet for P10. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P10-001` | Tri-platform internal alpha | `P2-013`, `P3-017`, `P4-021`, `P5-014`, `P6-015` | Ship equal Windows, macOS, and Linux internal builds with Owner Mode, terminal, browser, research, and data; capture failures. | Every mandatory desktop OS is represented, no P0 issue remains, and the replay corpus grows per platform. |
| `P10-002` | Tri-platform private beta | `P9-005`, `P9-006`, `P9-007`, `P9-009`, `P10-001` | Equal Windows, macOS, and Linux opt-in cohorts, staged updates, support intake, privacy telemetry, and weekly quality review. | SLOs and update targets hold independently on all three desktop OSs. |
| `P10-003` | External security audit closeout | `P8-014`, `P10-002` | Fix audit findings, add regressions, and publish scope/summary. | Zero unresolved critical/high. |
| `P10-004` | Release candidate freeze | `P10-003` | Feature freeze, exact versions, docs, translations, support, and release evidence. | RC artifact is immutable except blocker fixes. |
| `P10-005` | Thirty-day synchronized core RC soak | `P10-004` | Run continuous Windows, macOS, and Linux long-session, update, rollback, benchmark, and support monitoring. | Crash, quality, security, and parity thresholds pass independently on every mandatory desktop OS. |
| `P10-006` | Incident-response exercises | `P9-015`, `P9-016`, `P10-004` | Exercise leaked key, malicious extension, browser profile leak, sandbox escape, data corruption, and bad model. | Owners execute runbooks successfully. |
| `P10-007` | Core integration go/no-go review | `P10-005`, `P10-006` | Review every gate, accepted risk, cross-platform parity, evidence, support, and rollback. | Signed decision includes Windows, macOS, and Linux; no mandatory desktop OS is removed from the core integration scope. |
| `P10-008` | Staged core preview rollout | `P10-007` | Release internal→1%→5%→25%→50%→100% with automatic halt criteria. | No halt threshold is breached. |
| `P10-009` | Post-preview operations | `P10-008` | Monthly dependency/model review, quarterly drills, benchmark trend, vulnerability response, and deprecation policy. | Operational calendar has owners and evidence. |
| `P10-010` | Federated ecosystem checkpoint | `P7-011`, `P10-009` | Promote MCP/A2A/plugins only after dedicated soak and revocation testing. | Interop is independently gated from core GA. |

### Test Center deliverables

- `P10-TC-001` internal-alpha acceptance bundle
- `P10-TC-002` private-beta SLO dashboard
- `P10-TC-003` security-audit closeout regressions
- `P10-TC-004` immutable RC manifest
- `P10-TC-005` thirty-day soak aggregation
- `P10-TC-006` incident-response exercise runner
- `P10-TC-007` signed go/no-go report
- `P10-TC-008` staged-rollout halt criteria tests
- `P10-TC-009` operational calendar verification
- `P10-TC-010` federated ecosystem checkpoint

### Acceptance scenarios

- Add one criterion-scoped acceptance scenario for every user-visible outcome.

### Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Private beta and RC soak meet SLOs.
- Security and incident exercises pass.
- The core preview includes Windows, macOS, and Linux; each claimed mode is enabled only where its gate passed, and unresolved parity gaps remain release blockers for P20.
- Staged rollout and automatic halt/rollback are operational.

## P20 — Maximum-capability beta, RC, and synchronized GA

**Packet:** `docs/roadmap/anarchy/phases/P20-maximum-capability-beta-rc-and-synchronized-ga.md`
**Current execution view:** `FINAL_AGGREGATION_BLOCKED`
**Test Center module:** `Maximum-Capability Certification`

### Purpose

This is the bounded execution packet for P20. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P20-001` | Capability freeze and inventory | `P11-015`, `P12-014`, `P13-014`, `P14-014`, `P15-010`, `P16-012`, `P17-010`, `P18-011`, `P19-010`, `P21-024`, `P22-018`, `P23-024`, `P24-012` | Generated support matrix and exact exclusions, including provider/API/browser/local route, consumer experience, tool/skill/capability, roadmap-integrity, and no-SQL storage evidence | No claimed capability, provider route, Gold Skill, consumer promise, or platform behavior lacks evidence. |
| `P20-002` | Tri-platform private beta | `P20-001`, `P9-005`, `P9-006`, `P9-007` | Equal Windows/macOS/Linux cohort and support | SLOs hold independently on each OS. |
| `P20-003` | Mobile/web/headless beta | `P19-001`, `P19-002`, `P19-003`, `P19-004` | Companion/node cohort | Capability truth and remote revoke SLOs hold. |
| `P20-004` | Full external security assessment | `P20-002`, `P20-003`, `P8-014` | Owner, credentials, connectors, desktop, content, cloud, fleet audit | Zero unresolved critical/high findings. |
| `P20-005` | Cross-platform parity closeout | `P20-002` | Per-capability parity report | No mandatory desktop capability is missing or silently degraded. |
| `P20-006` | Maximum-capability RC freeze | `P20-004`, `P20-005` | Immutable versions, models, connectors, recipes, docs | Only blocker fixes may enter. |
| `P20-007` | Thirty-day synchronized RC soak | `P20-006` | Continuous tri-OS, mobile/web, node, update and benchmark evidence | Every mandatory SLO passes per platform. |
| `P20-008` | Disaster and compromise drills | `P20-006` | Key, connector, model, plugin, cloud, profile, node, data and bad-update drills | Runbooks succeed and evidence is retained. |
| `P20-009` | Final legal/privacy/accessibility/support closeout | `P20-007` | Human approvals and support readiness | Required sign-offs are recorded. |
| `P20-010` | Maximum-capability GA decision | `P20-007`, `P20-008`, `P20-009` | Signed owner/release-auditor decision | Windows, macOS, and Linux all pass; no partial desktop GA. |
| `P20-011` | Staged synchronized rollout | `P20-010` | Platform-balanced cohorts and automatic halt | Any platform halt pauses the common rollout. |
| `P20-012` | Continuous capability evolution | `P20-011` | Monthly provider/platform/model review and quarterly drills | New capability enters only through descriptor, tests, and evidence. |

### Test Center deliverables

- `P20-TC-001` capability/evidence freeze
- `P20-TC-002` private-beta tri-OS dashboard
- `P20-TC-003` companion/headless beta dashboard
- `P20-TC-004` external-security finding closure
- `P20-TC-005` cross-platform parity report
- `P20-TC-006` immutable RC certification manifest
- `P20-TC-007` thirty-day synchronized soak
- `P20-TC-008` disaster/compromise drills
- `P20-TC-009` legal/privacy/accessibility/support closeout
- `P20-TC-010` signed GA decision
- `P20-TC-011` staged global halt verification
- `P20-TC-012` continuous revalidation schedule

### Acceptance scenarios

- Add one criterion-scoped acceptance scenario for every user-visible outcome.

### Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Windows, macOS, and Linux pass the same applicable capability and release gates.
- Owner Mode, credentials, connectors, application generation, content manufacturing, native automation, deployment/fleet, realtime chat, local models, web/mobile companions, ecosystem extensions, Gold Skills, Skill Studio, consumer onboarding, repair, support, and the no-SQL local authority have production evidence.
- All artifacts are signed, installable, updateable, rollbackable, attributable, and verified on the declared minimum and recommended hardware profiles.
- Final product claims are generated from the capability registry, skill registry, roadmap manifest, and evidence store.
- A representative non-technical user can complete primary workflows in Simple Mode without viewing logs, schemas, terminals, provider internals, or implementation architecture.

## Cross-mission task interlocks

- `P10-001` waits for `P2-013` from `MISSION-001`.
- `P10-001` waits for `P3-017` from `MISSION-003`.
- `P10-001` waits for `P4-021` from `MISSION-004`.
- `P10-001` waits for `P5-014` from `MISSION-005`.
- `P10-001` waits for `P6-015` from `MISSION-006`.
- `P10-002` waits for `P9-005` from `MISSION-008`.
- `P10-002` waits for `P9-006` from `MISSION-008`.
- `P10-002` waits for `P9-007` from `MISSION-008`.
- `P10-002` waits for `P9-009` from `MISSION-008`.
- `P10-003` waits for `P8-014` from `MISSION-002`.
- `P10-006` waits for `P9-015` from `MISSION-008`.
- `P10-006` waits for `P9-016` from `MISSION-008`.
- `P10-010` waits for `P7-011` from `MISSION-007`.
- `P20-001` waits for `P11-015` from `MISSION-010`.
- `P20-001` waits for `P12-014` from `MISSION-011`.
- `P20-001` waits for `P13-014` from `MISSION-012`.
- `P20-001` waits for `P14-014` from `MISSION-013`.
- `P20-001` waits for `P15-010` from `MISSION-010`.
- `P20-001` waits for `P16-012` from `MISSION-014`.
- `P20-001` waits for `P17-010` from `MISSION-014`.
- `P20-001` waits for `P18-011` from `MISSION-006`.
- `P20-001` waits for `P19-010` from `MISSION-014`.
- `P20-001` waits for `P21-024` from `MISSION-011`.
- `P20-001` waits for `P22-018` from `MISSION-005`.
- `P20-001` waits for `P23-024` from `MISSION-007`.
- `P20-001` waits for `P24-012` from `MISSION-015`.
- `P20-002` waits for `P9-005` from `MISSION-008`.
- `P20-002` waits for `P9-006` from `MISSION-008`.
- `P20-002` waits for `P9-007` from `MISSION-008`.
- `P20-003` waits for `P19-001` from `MISSION-014`.
- `P20-003` waits for `P19-002` from `MISSION-014`.
- `P20-003` waits for `P19-003` from `MISSION-014`.
- `P20-003` waits for `P19-004` from `MISSION-014`.
- `P20-004` waits for `P8-014` from `MISSION-002`.

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
Take the repo. You are Worker A. Take MISSION-009 and continue autonomously.
```
