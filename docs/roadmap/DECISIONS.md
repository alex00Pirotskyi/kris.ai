# Kristin Architecture Decision Ledger

**Roadmap authority:** `DERIVED`

This ledger indexes decisions. The ADR files are authoritative for their individual decisions.

| ADR | Title | Status | Owner task | Implementation authority |
|---|---|---|---|---|
| `ADR-0000` | Bootstrap roadmap control plane | ACCEPTED | `P0-008` | Yes, for P0/P1 control-plane behavior only |
| `ADR-0001` | Runtime process and trust boundaries | ACCEPTED | `P1-001` | Yes |
| `ADR-0002` | Owner Mode authority model | ACCEPTED | `P1-001`, `P1-002` | Yes for authority boundary; profile schema remains P1-002 |
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
