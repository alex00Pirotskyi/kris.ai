# Kristin Architecture Decision Ledger

**Roadmap authority:** `DERIVED`

This ledger indexes decisions. The ADR files are authoritative for their individual decisions.

| ADR | Title | Status | Owner task | Implementation authority |
|---|---|---|---|---|
| `ADR-0000` | Bootstrap roadmap control plane | ACCEPTED | `P0-008` | Yes, for P0/P1 control-plane behavior only |
| `ADR-0001` | Runtime process and trust boundaries | ACCEPTED | `P1-001` | Yes |
| `ADR-0002` | Owner Mode and Access Profile v2 authority model | ACCEPTED | `P1-001`, `P1-002` | Yes |
| `ADR-0003` | Signed Manifest v2 | PROPOSED | `P1-005` | No |
| `ADR-0004` | Automation-host boundary; technology deferred | ACCEPTED | `P1-001`, `P2-004` | Yes for boundary; technology remains P2-004 |
| `ADR-0005` | Browser profile and research storage | PROPOSED | `P3-008`, `P4-011` | No |
| `ADR-0006` | Secure update system | PROPOSED | `P1-008`, `P9-008` | No |

A proposed ADR may guide investigation but may not authorize a production implementation. An ADR becomes accepted only through its owning roadmap task and evidence.
## P1-001 accepted runtime-boundary set — 2026-07-27

- `docs/adr/ADR-0001-runtime-boundaries.md` — process, authority, IPC and storage ownership.
- `docs/adr/ADR-0002-owner-mode.md` — explicit full-authority Owner Mode semantics; Access Profile v2 remains P1-002.
- `docs/adr/ADR-0004-automation-host.md` — technology-neutral worker supervision boundary; concrete host selection remains P2-004.
- Machine contract: `config/runtime_boundaries.v1.json`.

## P1-002 Access Profile v2 — 2026-07-27

- Canonical schema: `schemas/access_profile_v2.schema.json`.
- Canonical catalog: `config/access_profiles.v2.json`.
- Dart model: `lib/product/access_profile_v2.dart`.
- Worker model: `tool/access_profile_v2.py`.
- Shared invalid vectors: `evals/fixtures/p1_002_access_profiles/invalid_cases.json`.
- Profiles are ceilings, not grants; overlays may only narrow until P1-004.

## P1-003 Capability Grant v2 — 2026-07-27

- Canonical schema: `schemas/capability_grant_v2.schema.json`.
- Runtime policy: `config/capability_grant.v2.json`.
- Dart envelope model: `lib/product/capability_grant_v2.dart`.
- Worker verifier: `tool/capability_grant_v2.py`.
- Shared adversarial vectors: `evals/fixtures/p1_003_capability_grants/vectors.json`.
- Issuer key material remains outside the envelope.

## P1-004 deterministic policy engine — 2026-07-28

- Policy configuration: `config/policy_engine.v2.json`.
- Request schema: `schemas/deterministic_policy_v2.schema.json`.
- Python reference engine: `tool/deterministic_policy_engine.py`.
- Dart engine: `lib/product/deterministic_policy_engine.dart`.
- Property corpus: `evals/fixtures/p1_004_policy_engine/property_cases.json`.
- Deny, scope intersection and budget minimums are monotonic; only trusted explicit widening may restore scope within the Access Profile ceiling.

## P1 full trust-stack closure — 2026-07-28

P1-004 through P1-012 are delivered in one dependency-ordered integration train. Each task retains a completed packet, individual evidence manifest, executable gate and acceptance criteria. Signed Manifest v2 uses Ed25519 and external trust roots; v1 remains rejected; TUF trust, protected key references, signed audit checkpoints, threat ownership and authenticated IPC are approved.

The program now uses twelve governed integration trains. This changes merge cadence only and does not collapse task-level truth or assurance.

## P1 authority-service amendment V65

P1A-001 is a separately governed security amendment. It introduces an OS-isolated, typed P1 authority service owned outside the full-current-account automation worker boundary. Historical P1 evidence and the bootstrap P0/P1 roadmap remain immutable. P1A state is carried only by its dedicated task packet and signed evidence graph. Source landing on protected main is explicitly non-completing; only a later evidence-only closure can satisfy the P2 dependency.

## P2 automation host — V65

P2 is a delegation-only Owner Mode consumer of the separately completed P1A authority service. Source landing on protected main remains incomplete and cannot unlock P3. P2 task state is carried by dedicated task/evidence packets and the signed aggregate exit graph; the historical P0/P1 bootstrap roadmap and generated views remain untouched.
