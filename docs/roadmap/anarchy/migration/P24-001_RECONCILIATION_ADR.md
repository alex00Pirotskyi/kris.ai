# P24-001 — Roadmap-as-data and ANARCHY adoption reconciliation ADR

- Status: **PROPOSED / ADOPTION_REVIEW**
- Decision owner: Worker J
- Required independent review: Worker B and Worker I
- Protected-main anchor: `0a4176bcbcb975684c3a590be652c9fffe1ce770` / `641e11e63fa84f3a16dc4d74b418778839ce5bc2`
- Stacked proposal anchor: `6b23beb64070932886e75a131580fbc6fda878b6` / `724b838cae31bb50befb4e7676c55a41f925091e`

## Context

The repository already has a deliberately split control plane: `docs/roadmap/MASTER.md` is the sole human-readable implementation constitution, while `docs/roadmap/roadmap.yaml` is the canonical machine-readable authority inside its declared P0/P1 bootstrap scope. `STATUS.md`, `HANDOFF.md`, and `GENERATED_STATE.md` are derived compatibility views. The additive ANARCHY packet in draft PR #63 contains 25 phase packets, 359 task IDs, and ten durable worker identities, but its own documents say that it is a proposal and cannot manufacture task completion.

P24-001 therefore extends the existing model. It does not replace the current authority with a parallel mutable ledger, and it does not promote proposal phase status into live product truth.

## Decision

### Human authority

`docs/roadmap/MASTER.md` remains the only human-readable normative roadmap authority. Human-readable phase, worker, dashboard, migration, and reference files are governed views, proposal inputs, operational memory, or historical evidence. None may independently assign task status.

### Machine authority

`docs/roadmap/roadmap.yaml` remains the one canonical machine authority. Adoption will extend that file from its current P0/P1 bootstrap scope to the accepted P0–P24 task set using the schema contract in `schemas/anarchy_execution.schema.json`. The extension must retain the JSON subset of YAML 1.2 unless an independently reviewed migration proves every current consumer supports a richer parser.

`DIRECTIVE_MATRIX.yaml`, `MIGRATION_LEDGER.yaml`, claims, evidence manifests, and generated reports are not competing task-status ledgers. They carry migration decisions, append-only observations, ownership, and evidence bindings. On conflict, canonical machine state wins unless the human authority explicitly requires reconciliation.

### File roles

| Source | Role before adoption | Role after adoption |
|---|---|---|
| `docs/roadmap/MASTER.md` | normative human authority | unchanged |
| `docs/roadmap/roadmap.yaml` | normative machine authority for declared P0/P1 scope | normative machine authority for accepted P0–P24 scope |
| `docs/roadmap/STATUS.md` | generated compatibility view | generated compatibility view |
| `docs/roadmap/HANDOFF.md` | generated compatibility view | generated compatibility view |
| `docs/roadmap/GENERATED_STATE.md` | generated-state registry | generated-state registry |
| `docs/roadmap/anarchy/phases/**` | bounded proposal/input packets | source-mapped navigation packets; status generated from machine authority |
| `docs/roadmap/anarchy/workers/**` | durable proposal worker memory | durable generated/operational worker memory with freshness binding |
| `docs/roadmap/anarchy/DASHBOARD.md` | proposal compatibility view | generated compatibility view |
| v3.2 reference pointer | immutable source reference | immutable historical/reference source |
| migration files | adoption evidence and decision records | immutable historical migration evidence after adoption |

### Source immutability and supersession

Accepted evidence, task IDs, hashes, historical phase wording, and reviewed commits are append-only. A replacement identifies the superseded object, reason, compatibility behavior, and rollback. Files are never silently rewritten to erase an earlier claim. The v3.2 pointer remains a hash-linked reference and is not converted into normative source.

### Task identity

A task ID is immutable once published. Wording may be clarified without changing the ID or acceptance semantics. A semantic split creates new IDs and records `supersedes`; a merge deprecates old IDs but retains them as aliases. Renames require an explicit compatibility map and cannot reuse a retired ID for a different task.

### Separate state machines

The control plane keeps roadmap task status, worker runtime status, test execution result, certification status, and capability support status in separate typed fields. Exact enums are defined in the schema. No inference crosses domains automatically. In particular:

- a static/source test `PASS` does not make a capability `BEHAVIOR_SUPPORTED`;
- hosted CI `PASS` does not imply platform or release support;
- task `DONE` requires accepted evidence and dependency/gate closure;
- certification can become `STALE` or `REVOKED` without rewriting historical test results.

### Claims and shared-contract locks

A valid active claim binds one task to one worker, branch, exact base, owned paths, shared-contract locks, reviewer, and durable next action. Multiple active owners for one task, or overlapping exclusive shared-contract locks, are invalid. Worker J owns P24-001 migration contracts only. Worker C retains PR #62 and Worker A retains proven P2 responsibility.

### Yield and takeover

A yield records target worker, continuity head/tree, open PR, evidence bindings, uncommitted state (which must be empty or explicitly archived), remaining findings, and next action. A takeover is valid only from that continuity record or an explicit ownership transfer. Neither action rewrites prior ownership history.

### Exact-SHA evidence and independent review

Evidence and reviews bind to a full commit SHA and tree. A repair creates a new candidate and invalidates review for changed scope. Adoption requires Worker B (roadmap/evidence) and Worker I (security/CI/governance) findings to have no unresolved critical or high severity. GitHub-hosted success is recorded as test evidence, not as independent review.

### Autonomous approval and genuine blockers

Routine implementation, repair, formatting, fixture, and deterministic CI work proceeds autonomously. Human or capability blocking is limited to repository authority rejection, ownership collision, credential/signing/platform absence without a deterministic substitute, security exposure, out-of-scope runtime dependency, or evidence that cannot be proven.

### Worker memory and dashboard freshness

Generated views carry a visible generator header and input fingerprint. Worker memory must expose lane, active task, branch/PR, exact anchors, owned/forbidden paths, tests, review, blockers, and one exact next action. Offline validation checks the local contract; optional GitHub reconciliation is a separate fail-closed command and must never leak tokens.

### CI and rollback

The existing `product-gates` matrix runs the P24 validator on Ubuntu, Windows, and macOS. `--check` is network-free and non-mutating. `--write` changes only declared generated output atomically and idempotently. Rollback removes the P24 gate and proposal extension while retaining this ADR, baseline, directive ledger, claims, and evidence as historical records; it restores the prior `roadmap.yaml` bytes and generated views through their owning generator.

## Compatibility

`tool/roadmap_control.py` remains the P0/P1 bootstrap validator throughout adoption preparation. The new validator is additive and validates ANARCHY packet integrity plus compatibility with the current authority. The existing manifest schema/version is not changed in this PR. A later adoption commit may extend `roadmap.yaml` only after compatibility fixtures prove existing consumers ignore or understand the extension.

`CONTRIBUTING.md` currently mentions `tool/roadmap_state.py`; the live implementation is `tool/roadmap_control.py`. This ADR records the mismatch, but P24-001 does not rename the live tool or silently alter current consumers.

## Explicit non-goals

This change does not modify product runtime, P1/P2 authority behavior, browser/search implementation, PR #62, P3 readiness, SQLite or no-SQL storage, persistence indexes or migrations, public APIs, wire formats, native interfaces, release metadata, support policy, signing material, secrets, or GA classification.

## Adoption gate

This ADR becomes accepted only after exact-head matrix CI, deterministic and non-mutation evidence, generator-owned source-manifest verification, Worker B and Worker I exact-SHA review, and explicit repository adoption approval. Until then, status is `ADOPTION_REVIEW` and PR #63 remains proposal authority only.
