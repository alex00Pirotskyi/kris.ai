# P24-001 — Roadmap-as-data and ANARCHY adoption reconciliation ADR

- Status: **PROPOSED / ADOPTION_REVIEW**
- Decision owner: Worker J
- Required independent review: Worker B and Worker I
- Protected-main anchor: `0a4176bcbcb975684c3a590be652c9fffe1ce770` / `641e11e63fa84f3a16dc4d74b418778839ce5bc2`
- Stacked proposal anchor: `6b23beb64070932886e75a131580fbc6fda878b6` / `724b838cae31bb50befb4e7676c55a41f925091e`

## Context

The repository already has a deliberately split control plane: `docs/roadmap/MASTER.md` is the sole human-readable implementation constitution, while `docs/roadmap/roadmap.yaml` is the canonical machine-readable authority only inside its declared P0/P1 bootstrap scope. `STATUS.md`, `HANDOFF.md`, and `GENERATED_STATE.md` are compatibility/generated views. Draft PR #63 supplies an additive ANARCHY proposal with 25 phase packets, 359 task IDs, and ten worker cards, but it is not normative authority and cannot manufacture completion.

P24-001 prepares a reversible adoption foundation. It does not replace the current authority, extend `roadmap.yaml`, promote PR #63, or enact the v3.2 planning reference.

## Decision

### Human authority

`docs/roadmap/MASTER.md` remains the only human-readable normative roadmap authority. Phase packets, worker cards, dashboards, migration records, and references remain proposal, navigation, operational-memory, compatibility, or evidence artifacts. They cannot independently assign roadmap task state.

### Machine authority

`docs/roadmap/roadmap.yaml` remains the one canonical machine authority within its existing P0/P1 scope. This adoption-review run does **not** extend that scope to P0–P24 and does not rewrite `MASTER.md`, `roadmap.yaml`, `STATUS.md`, `HANDOFF.md`, or `GENERATED_STATE.md`.

A future, separately authorized adoption action may extend the existing machine authority after exact-head CI, compatibility proof, and independent review. It must not create a second mutable roadmap ledger.

### P24-001 scoped schema

`schemas/anarchy_execution.schema.json` is specifically scoped to P24-001 adoption-review execution records: roadmap references, worker runtime records, claims and shared-contract locks, phase/worker packet integrity, migration directives/observations, and generated navigation. It is not the future full roadmap manifest schema and does not replace Worker B's Test Center, Project Test Profile, Testing Studio, result registry, or certification architecture.

The P24 validator treats TestExecutionResult and CertificationStatus as externally owned Worker B references. Until Worker B publishes canonical versioned contracts, their external bindings remain `BLOCKED_BY_SHARED_CONTRACT`; Worker J validates separation and inflation rules without claiming ownership.

### File roles

| Source | Adoption-review role |
|---|---|
| `docs/roadmap/MASTER.md` | normative human authority |
| `docs/roadmap/roadmap.yaml` | normative machine authority for declared P0/P1 scope |
| `docs/roadmap/STATUS.md`, `HANDOFF.md`, `GENERATED_STATE.md` | existing compatibility/generated views; unchanged |
| `docs/roadmap/anarchy/phases/**` | bounded proposal/navigation inputs |
| `docs/roadmap/anarchy/workers/**` | bounded operational/proposal memory |
| `docs/roadmap/anarchy/DASHBOARD.md` | proposal compatibility view |
| `docs/roadmap/anarchy/generated/P24-001_CONTROL_PLANE_INDEX.json` | deterministic generated P24 navigation index; not authority |
| v3.2 reference pointer | immutable hash-linked planning reference |
| `DIRECTIVE_MATRIX.yaml` | proposed reconciliation decisions, not task status |
| `MIGRATION_LEDGER.yaml` | append-only migration observations, not task status |
| claims/reviews/evidence | ownership/evidence bindings, not roadmap authority |

### Source immutability and supersession

Accepted evidence, task IDs, hashes, historical wording, and reviewed commits are append-only. A replacement identifies the superseded object, rationale, compatibility behavior, and rollback. Stale claims are corrected by a new observation rather than erased.

### Task identity

A published task ID is immutable. Clarification may not alter acceptance semantics. Splits create new IDs and `supersedes` metadata; merges retain deprecated aliases. A retired ID is never reused for different work.

### Separate state domains

RoadmapTaskStatus, WorkerRuntimeStatus, TestExecutionResult, CertificationStatus, and CapabilitySupportStatus remain separate typed fields. No parser, generator, review, or report coerces one into another. In particular:

- `source_only` does not mean supported;
- test `PASS` does not mean roadmap `DONE`;
- hosted CI `PASS` does not mean behavioral or platform certification;
- a review comment does not mean approval;
- a migration proposal does not mean normative authority;
- P2 source success remains distinct from controlled behavioral evidence and release support.

### Claims and shared-contract locks

A valid active claim binds task, worker, branch, exact base, owned paths, shared-contract locks, reviewers, continuity, and one durable next action. Multiple active owners for one task or overlapping exclusive locks are invalid. Worker J owns only P24-001 migration/control-plane paths. Worker C retains PR #62; Worker B retains horizontal Test Center contracts; Worker I retains security/release review scope.

### Yield and takeover

A yield records exact head/tree, safe-takeover condition, evidence continuity, and next action. A takeover is valid only from a yielded record or explicit ownership transfer and preserves prior ownership history.

### Exact-head independent review

A valid Worker B or Worker I review artifact records reviewer role, full candidate commit/tree, reviewed files, commands, findings/severity/disposition, decision, timestamp, and artifact hash. Formal GitHub approval is optional when the same GitHub account makes identity independence unavailable, but Worker J cannot author its own Worker B/I review. Any changed implementation, schema, fixture, workflow, generated report, or source manifest invalidates earlier review.

### Deterministic tooling

`tool/anarchy_control_plane.py --check --project .` is network-free and strictly non-mutating across declared scope. `--write` is separate, atomic, deterministic, idempotent, fail-closed, and bounded to the generated P24 navigation index. Normal validation never invokes write mode.

`SOURCE_MANIFEST.sha256` remains owned by `tool/p1a_refresh_source_manifest.py`. The P24 validator verifies expected bytes read-only but does not replace or silently invoke the owner. The canonical write command is:

```text
python tool/p1a_refresh_source_manifest.py .
```

### CI and rollback

`.github/workflows/p24-adoption-review.yml` is a bounded exact-head Ubuntu/Windows/macOS gate. It checks out the candidate SHA, runs tests and `--check`, builds expected generated output and source manifest only in an isolated clone, proves source-manifest second-write idempotence, verifies checkout cleanliness, and uploads bounded evidence. It cannot commit, push, refresh authority, or weaken P1/P1A/P2/P4 gates.

Rollback closes the stacked PR or reverts its focused commits, removes the bounded P24 workflow and generated proposal index, and retains ADR/baseline/directive/claim/review/evidence history. Existing roadmap bytes, product/runtime behavior, PR #62, P2 evidence, and task IDs remain untouched.

## Compatibility

`tool/roadmap_control.py validate --project . --strict` remains the P0/P1 bootstrap validator. The P24 validator is additive and validates proposal packet integrity and status separation. `CONTRIBUTING.md` still names nonexistent `tool/roadmap_state.py`; the live implementation is `tool/roadmap_control.py`. This mismatch is recorded but is not silently repaired in P24-001.

## Explicit non-goals

No product runtime, P1/P2 authority behavior, P2 behavioral certification, P3/P4 implementation, PR #62 history, SQLite/no-SQL storage, persistence index/migration, public API, wire format, native interface, release metadata, support policy, signing material, secret, production, or GA claim changes in this run.

## Adoption gate

The result remains `ADOPTION_REVIEW` until committed artifacts, exact-head tri-OS CI, full non-mutation, atomic/idempotent write proof, canonical source-manifest verification, Worker B exact-head `PASS`, Worker I exact-head `PASS`, stacked draft PR, and pushed-state clean-room resume all pass. `ADOPTION_READY`, when eventually justified, still does not mean adopted, normative, merged, product-complete, P2 behaviorally complete, release-ready, production-ready, or GA. Authority promotion is a separate explicit action and is not performed by Worker J here.
