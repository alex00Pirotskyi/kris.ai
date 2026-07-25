# Kristin Production Metrics

**Roadmap authority:** `DERIVED`

A metric has no release meaning unless it links to a reproducible evidence artifact.

| Metric | Definition | Target | Current evidence |
|---|---|---:|---|
| Three-OS current CI completion | OS lanes passing every current workflow step through native build | 3/3 | `P0-003` evidence pending |
| Insecure v1 trust acceptance | Forged v1 envelopes accepted by an authorization path | 0 | `P0-002` regression evidence |
| Roadmap graph validity | Duplicate IDs, missing deps, cycles, invalid states, authority conflicts | 0 defects | `tool/roadmap_control.py validate` |
| Roadmap fresh-session readiness | Ready tasks returned with packet and acceptance criteria | 100% | `tool/roadmap_control.py next` |
| Source-marker behavioral overclaim | Source/mixed checks marked as behavioral proof | 0 | `P0-007` assurance report |
| Open critical/high security findings | Unresolved findings at release gate | 0 | P8/P20 audit evidence |
| Unsupported successful completion | Agent claims success without criterion-scoped evidence | <0.5% | P6/P8 benchmark |
| Unauthorized effects | Effects outside the active grant/profile | 0 | P6/P8 adversarial corpus |
| Crash reconciliation | Seeded local effects recovered or explicitly `unknown` | 100% | workflow chaos evidence |
| Owner kill latency | Complete supported process tree terminated | <2 seconds p95 | P2/P11 platform evidence |
| Release install/update/rollback | Successful clean-machine operations per supported platform | 100% release suite | P9 evidence |

## Reporting rules

- Publish sample size and confidence for probabilistic metrics.
- Report every mandatory desktop OS independently; never average away a failing platform.
- Separate source, behavioral, SDK, platform, security, and release evidence.
- Do not fill unknown values with estimates that appear measured.
