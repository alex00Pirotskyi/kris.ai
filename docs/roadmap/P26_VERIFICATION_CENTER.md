# P26 — Verification Center

**Status:** `READY`  
**Roadmap authority:** `HUMAN_CONSTITUTION_EXTENSION`  
**Machine extension:** `docs/roadmap/p26/manifest.v1.json`  
**Decision:** `docs/roadmap/decisions/ADR-P26-001-verification-center-architecture.md`  
**Acceptance contract:** `docs/roadmap/p26/verification_center_acceptance_contract.v1.json`  
**Test Station:** `docs/roadmap/p26/verification_center_test_station.v1.json`

## Mission

Verification Center is a first-class product workspace for proving whether a project,
change, build, website, native application, updater operation, or repair attempt meets
explicit acceptance criteria. It must serve arbitrary projects rather than encode
Kristin-only assumptions, while dogfooding Kristin as a release-blocking reference
journey.

The product combines the canonical Test Center evidence model, Project Manager project
identity, P3 browser/testing paths, P2 managed operations and updater stages, project
profiles, verification reports, coverage import, and bounded repair into one truthful
end-user flow.

## User promise

A user can open a project, describe what “correct” means, choose an evidence depth,
watch every meaningful stage, stop safely, inspect exact failures and blockers, and—when
authorized—allow at most two repair attempts. Verification never promotes a blocked,
unknown, stale, cross-commit, or unexecuted result to PASS.

## Canonical result states

Only these result states are permitted:

- `PASS`
- `FAIL`
- `BLOCKED_ENVIRONMENT`
- `BLOCKED_PERMISSION`
- `NOT_RUN`
- `UNKNOWN`

`BLOCKED_ENVIRONMENT`, `BLOCKED_PERMISSION`, `NOT_RUN`, and `UNKNOWN` are terminally
non-passing for the run being reported. A higher-level summary may not coerce them into
PASS.

## Verification modes

- `ANALYZE_ONLY` — inspect project and acceptance criteria without executing tests or changing source.
- `QUICK_CHECK` — run a bounded, deterministic affected-test selection.
- `DEEP_CHECK` — run the governed full profile selected for the project and environment.
- `TEST_AND_REPAIR` — execute, diagnose, request or observe authorization, and perform no more than two repair attempts.

Destructive actions, remote changes, installer application, restart, rollback, and any
write outside the active project require explicit confirmation. Analyze-only is
strictly non-mutating.

## Acceptance criteria

Verification Center treats all three forms as first-class inputs:

1. `STRUCTURED` criteria with stable IDs, expected evidence, severity, and evaluation rules.
2. `HUMAN` criteria written in natural language and preserved verbatim with provenance.
3. `AGENT_PROMPT` criteria that instruct an authorized agent what to verify, what evidence
   to return, and where to stop; these are never silently rewritten into hidden reasoning.

Each criterion receives an explicit result state, evidence links, exact source identity,
environment identity, timing, and an explanation suitable for the user.

## Product flow

```text
Open project
→ Discover or select verification profile
→ Define acceptance criteria
→ Choose analyze / quick / deep / test-and-repair
→ Review actions and confirmations
→ Create durable run
→ Stream stages, commands, logs, evidence and criterion results
→ Inspect coverage, failures and blockers
→ Optionally authorize bounded repair
→ Re-run affected verification
→ Export exact report
```

## Target architecture

```text
VerificationCenterWorkspace
        │
VerificationCenterController
        │
VerificationRunService
        ├── durable run + attempt ledger
        ├── exact source/environment identity
        ├── cancellation + managed-process lifecycle
        ├── ordered activity/log/evidence stream
        ├── acceptance criterion evaluator
        └── result-state aggregation (never optimistic)
        │
VerificationPlanCompiler
        ├── project profile + affected-test mapping
        ├── structured/human/agent-prompt criteria
        ├── browser / HTTP / native / updater adapters
        ├── coverage adapters
        └── confirmation and permission policy
        │
Canonical Test Center + Project Manager + P2/P3 governed operations
```

## Project-local configuration

Projects may opt into a versioned, idempotent `.prowork/verification/` directory.
Discovery never requires it. Generated configuration must preserve human-authored fields,
support deterministic upgrades, and never execute arbitrary project content merely by
opening the project.

## Web verification

Web verification uses two explicit paths:

- P3 governed browser execution for real browser journeys.
- A network-bounded headless HTTP fixture path for deterministic contract tests.

Browser absence, denied permission, unreachable fixtures, and unsupported platform
conditions are represented as blockers—not skipped or converted to PASS.

## Updater verification

Updater journeys reuse P2 operations and keep these stages distinct:

```text
CHECK → DOWNLOAD → INSTALL → RESTART → VERIFY → ROLLBACK
```

A PASS at one stage does not certify later stages. Restart and rollback require explicit
authorization and exact post-operation evidence.

## Coverage

Supported import families are Cobertura XML, LCOV, and a native/source-map equivalent.
Unknown, malformed, stale, or source-unmappable coverage remains explicit `UNKNOWN`;
absence of coverage never means 100%.

## Repair boundary

Test-and-repair is limited to two repair attempts per durable run. Every attempt is
recorded with source-before, patch or change summary, source-after, selected verification,
result state, and evidence. The system stops earlier on PASS, denied confirmation,
permission or environment blocker, budget exhaustion, scope violation, or repeated
non-progress. There is no unbounded or silent retry.

## Governed task order

| Task | Deliverable |
|---|---|
| `P26-001` | Governance, contracts, Test Station and CI lane |
| `P26-002` | Project discovery, profile and durable identity |
| `P26-003` | Plan compiler and affected-test selection |
| `P26-004` | Acceptance criteria engine |
| `P26-005` | End-user workspace and live run UX |
| `P26-006` | Managed execution and exact result aggregation |
| `P26-007` | Bounded test-and-repair |
| `P26-008` | Browser and HTTP-fixture web verification |
| `P26-009` | Coverage ingestion and mapping |
| `P26-010` | Updater verification and rollback |
| `P26-011` | Native-owner and permission campaigns |
| `P26-012` | Release-blocking Kristin dogfood and closeout |

Only `P26-001` is initially `READY`. Every later packet is dependency-blocked.

## Test Station

Governance workers run:

```bash
python3 tool/p26_verification_center_roadmap_test.py --project .
python3 tool/p26_verification_center_test_station.py --project . --list
python3 tool/p26_verification_center_test_station.py --project . --profile contract --check
```

Deterministic, behavioral, web, native, updater and dogfood profiles remain
`BLOCKED_NOT_IMPLEMENTED` or `BLOCKED_ENVIRONMENT` until their real source and
environment exist. A blocked profile never exits as PASS.

## Truth boundary

Landing P26 governance proves only that the roadmap, contracts, task graph, Test Station
and CI lane are coherent. Source tests do not certify installed behavior. Browser
fixtures do not certify every live site. Native-owner evidence is platform-specific.
Updater CHECK does not certify INSTALL, RESTART, VERIFY, or ROLLBACK. The Kristin
dogfood journey is mandatory for release eligibility but cannot alone prove general
project support or GA readiness.
