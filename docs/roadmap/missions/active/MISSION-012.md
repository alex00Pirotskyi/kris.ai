# MISSION-012 — Application Factory and Advanced Vibe Coding

**Default executor:** Worker G
**Priority:** `MEDIUM`
**Roadmap phases:** `P13`
**Authority:** execution overlay only; `docs/roadmap/MASTER.md` remains human authority.

## Mission objective

Create a complete application factory that plans, designs, implements, tests, runs, inspects, packages, deploys, monitors, repairs, and documents supported applications rather than producing snippets.

## Transfer and resume protocol

1. Re-resolve protected main, mission branch, PR, head/tree, CI, reviews, and dependency state.
2. Load this contract, the mission state, active claim, latest checkpoint, entry graph, and task interlocks.
3. Reuse valid implementation and evidence already present; never restart completed work without a proven defect.
4. Select the highest-priority dependency-satisfied task or a clearly labeled dependency-safe source/fixture/documentation packet.
5. Implement, test, document, commit, push, inspect exact-head CI, repair, obtain required independent review, and update state/checkpoint.
6. Yield only with an exact continuation point or complete the mission and release its claim.

## Current repository anchor

- No active claim. The mission is available only when its entry dependencies and ownership checks pass.

## P13 — Application Factory and advanced vibe coding

**Packet:** `docs/roadmap/anarchy/phases/P13-application-factory-and-advanced-vibe-coding.md`
**Current execution view:** `BLOCKED_BY_REPOSITORY_AND_PLATFORM_FOUNDATIONS`
**Test Center module:** `Application Factory`

### Purpose

This is the bounded execution packet for P13. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P13-001` | Application project/spec schemas | `P6-004`, `P5-006` | Requirements, architecture, acceptance and lineage model | Requirement-to-code/test links survive round trips. |
| `P13-002` | Recipe registry v2 | `P12-006` | Signed application recipe manifests | Changed recipes are detected and versioned upgrades work. |
| `P13-003` | Repository intelligence v2 | `P3-012`, `P6-003` | Symbols, dependencies, tests, generated files, impact map | Multi-language fixture repos produce correct maps. |
| `P13-004` | Code editing transaction engine | `P13-003`, `P2-010` | Multi-file patch, checkpoint, conflict, restore | Injected failure restores or marks exact partial state. |
| `P13-005` | Web full-stack golden recipes | `P13-002`, `P13-004`, `P3-013` | Static, modern frontend, API+database recipes | Clean creation/change/test/preview/deploy fixtures pass. |
| `P13-006` | Service/API golden recipes | `P13-002`, `P13-004`, `P12-011` | TypeScript, Python, Go, Rust, Java/.NET declared recipes | Build/test/package/health/upgrade fixtures pass. |
| `P13-007` | Flutter cross-platform app recipe | `P13-002`, `P11-010` | Windows/macOS/Linux/web/mobile project recipe | Shared app builds and smoke tests on declared targets. |
| `P13-008` | Native/mobile recipes | `P13-002` | SwiftUI, Kotlin/Compose, optional React Native recipes | Platform CI builds, tests, and emulator/device smoke pass. |
| `P13-009` | Desktop/CLI/extension recipes | `P13-002`, `P11-010` | Tauri/Electron/CLI/browser extension recipes | Package and behavior fixtures pass. |
| `P13-010` | Design-to-code loop | `P3-015`, `P13-004` | Tokens, components, screenshot/semantic diff, repair | Responsive and accessibility fixtures converge. |
| `P13-011` | Automated debug and repair | `P13-003`, `P8-009` | Correlated error/trace/test/source repair loop | Hidden bug corpus improves without repeated-loop failure. |
| `P13-012` | Application deployment handoff | `P13-005`, `P13-006` | Preview, docs, runbook, rollback bundle | Generated apps reach verified preview from clean checkout. |
| `P13-013` | Vibe Coding workspace v2 | `P5-004`, `P13-003`, `P13-010` | Integrated editor/runtime/test/evidence UX | End-to-end keyboard workflow passes. |
| `P13-014` | Application Factory benchmark | `P13-005`, `P13-013` | Hidden/public multi-stack corpus | Success, regression, cost, latency, and false-completion targets pass. |

### Test Center deliverables

- `P13-TC-001` project/spec round-trip
- `P13-TC-002` signed recipe versioning
- `P13-TC-003` repository intelligence corpus
- `P13-TC-004` transactional multi-file editing
- `P13-TC-005` web full-stack recipe certification
- `P13-TC-006` API/service recipe certification
- `P13-TC-007` Flutter cross-platform recipe
- `P13-TC-008` native/mobile recipe lanes
- `P13-TC-009` desktop/CLI/extension recipes
- `P13-TC-010` design-to-code convergence
- `P13-TC-011` automated debug/repair corpus
- `P13-TC-012` deployment handoff
- `P13-TC-013` workbench E2E
- `P13-TC-014` Application Factory benchmark

### Acceptance scenarios

- `P13-ACC-001` create app from brief on clean machine
- `P13-ACC-002` make one feature change and verify runtime
- `P13-ACC-003` inject compiler/runtime defect and repair
- `P13-ACC-004` package/deploy preview and reopen evidence
- `P13-ACC-005` upgrade recipe from previous version

### Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- At least six materially different application recipes pass full lifecycle tests.
- Windows/macOS/Linux Flutter recipe has synchronized evidence.
- Generated apps are tested, previewed, packaged/deployed, and documented.

## Cross-mission task interlocks

- `P13-001` waits for `P5-006` from `MISSION-005`.
- `P13-001` waits for `P6-004` from `MISSION-006`.
- `P13-002` waits for `P12-006` from `MISSION-011`.
- `P13-003` waits for `P3-012` from `MISSION-003`.
- `P13-003` waits for `P6-003` from `MISSION-006`.
- `P13-004` waits for `P2-010` from `MISSION-001`.
- `P13-005` waits for `P3-013` from `MISSION-003`.
- `P13-006` waits for `P12-011` from `MISSION-011`.
- `P13-007` waits for `P11-010` from `MISSION-010`.
- `P13-009` waits for `P11-010` from `MISSION-010`.
- `P13-010` waits for `P3-015` from `MISSION-003`.
- `P13-011` waits for `P8-009` from `MISSION-002`.
- `P13-013` waits for `P5-004` from `MISSION-005`.

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
Take the repo. You are Worker G. Take MISSION-012 and continue autonomously.
```
