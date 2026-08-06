# MISSION-015 — Roadmap Integrity, Mission Execution, Traceability, and No-SQL Authority Migration

**Default executor:** Worker J
**Priority:** `EXECUTION_CONTROL`
**Roadmap phases:** `P24`
**Authority:** execution overlay only; `docs/roadmap/MASTER.md` remains human authority.

## Mission objective

Make the full roadmap executable data, maintain durable transferable missions, validate dependencies and claims, generate bounded context packs, preserve traceability and supersession, and complete the measured restartable no-SQL authority migration without a big bang.

## Transfer and resume protocol

1. Re-resolve protected main, mission branch, PR, head/tree, CI, reviews, and dependency state.
2. Load this contract, the mission state, active claim, latest checkpoint, entry graph, and task interlocks.
3. Reuse valid implementation and evidence already present; never restart completed work without a proven defect.
4. Select the highest-priority dependency-satisfied task or a clearly labeled dependency-safe source/fixture/documentation packet.
5. Implement, test, document, commit, push, inspect exact-head CI, repair, obtain required independent review, and update state/checkpoint.
6. Yield only with an exact continuation point or complete the mission and release its claim.

## Current repository anchor

- Worker: `J`
- Branch: `agent/j/P24-001-roadmap-as-data-adr`
- Draft PR: `#66`
- Observed head: `2a14b875ff529cfd90348673e8e45b2442663619`
- Observed tree: `595346993b4512411f48075a47289333c51b3850`
- Current work: P24-001 ANARCHY adoption-review source repair; product gates pass while the P24 adoption review remains red
- These are discovery anchors, not permission to skip live-state discovery.

## P24 — Roadmap integrity, traceability, and no-SQL authority

**Packet:** `docs/roadmap/anarchy/phases/P24-roadmap-integrity-traceability-and-no-sql-authority.md`
**Current execution view:** `READY_PARALLEL_P24_001`
**Test Center module:** `Roadmap & Storage Integrity`

### Purpose

This is the bounded execution packet for P24. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P24-001` | Approve roadmap-as-data ADR | `P0-008` | Authority, file split, manifest, generation and supersession rules | No competing roadmap authority remains. |
| `P24-002` | Split master roadmap into bounded phase/task files | `P24-001` | Generated navigation and compatibility MASTER | Content hashes and cross-links prove no task loss. |
| `P24-003` | Implement roadmap manifest schema and validator | `P24-001` | IDs, dependencies, cycles, gates, status, evidence and supersession validation | Invalid fixture classes fail CI. |
| `P24-004` | Implement requirement/claim traceability | `P24-003`, `P23-006` | Promise→requirement→capability→test→evidence graph | Unsupported marketing claim cannot be generated. |
| `P24-005` | Approve no-SQL local authority ADR | `P1-001`, `P24-001` | Engine evaluation, journal/object/index architecture and migration | Human owner approves no-SQL target and rollback. |
| `P24-006` | Build embedded authority abstraction | `P24-005` | Transaction, query, watch, migration, backup and corruption interfaces | Reference implementation passes durability suite. |
| `P24-007` | Implement SQLite-to-object migration | `P24-006`, `P8-002` | Restartable migration, verification and rollback | Historical fixtures preserve IDs, events and content hashes. |
| `P24-008` | Replace core SQL-specific indexes | `P24-006`, `P4-013` | Rebuildable lexical and optional semantic/graph indexes | Full function survives index deletion and rebuild. |
| `P24-009` | Create vertical slice suite | `P24-003`, `P22-004`, `P23-019` | V1–V9 scenarios and evidence manifests | Every slice runs on all mandatory desktop OSs. |
| `P24-010` | Generate AI context packs | `P24-002`, `P24-003` | Bounded task bundles and freshness checks | Local model executes sampled tasks without whole-roadmap context. |
| `P24-011` | Implement documentation and acceptance lint | `P24-003` | Missing criteria, ambiguous verbs, stale links, uncited standards and duplicate authority checks | Seeded documentation defects fail CI. |
| `P24-012` | Roadmap integrity and storage release gate | `P24-001`, `P24-011` | Manifest, traceability, no-SQL migration, vertical slices and context-pack report | Gate V passes before final capability freeze. |

### Test Center deliverables

- `P24-TC-001` roadmap-authority/supersession checks
- `P24-TC-002` split-roadmap content preservation
- `P24-TC-003` manifest ID/dependency/cycle/gate validation
- `P24-TC-004` promise-to-evidence traceability
- `P24-TC-005` no-SQL ADR conformance
- `P24-TC-006` embedded authority durability
- `P24-TC-007` SQLite migration/restart/rollback
- `P24-TC-008` index deletion/rebuild
- `P24-TC-009` V1–V9 vertical slice suite
- `P24-TC-010` bounded AI context-pack freshness
- `P24-TC-011` documentation/acceptance lint
- `P24-TC-012` roadmap/storage certification

### Acceptance scenarios

- `P24-ACC-001` duplicate task ID fails CI
- `P24-ACC-002` dependency cycle fails CI
- `P24-ACC-003` unsupported public promise cannot be generated
- `P24-ACC-004` core runs after deleting/rebuilding derived indexes
- `P24-ACC-005` historical migration preserves IDs/events/hashes
- `P24-ACC-006` each vertical slice passes on Windows/macOS/Linux
- `P24-ACC-007` sampled local model executes task from bounded context pack

### Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- One human-readable master and one machine-readable manifest control execution.
- Older roadmaps are clearly superseded.
- Task dependencies and evidence are CI-validated.
- Every public promise is traceable to passing evidence.
- The core runs without a SQL database.
- Historical data migrates with verification and rollback.
- Vertical slices prove complete user outcomes across all desktop platforms.
- Local implementation models receive bounded context packs.

## Cross-mission task interlocks

- `P24-001` waits for `P0-008` from `MISSION-001`.
- `P24-004` waits for `P23-006` from `MISSION-007`.
- `P24-005` waits for `P1-001` from `MISSION-001`.
- `P24-007` waits for `P8-002` from `MISSION-002`.
- `P24-008` waits for `P4-013` from `MISSION-004`.
- `P24-009` waits for `P22-004` from `MISSION-005`.
- `P24-009` waits for `P23-019` from `MISSION-007`.

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
Take the repo. You are Worker J. Take MISSION-015 and continue autonomously.
```
