# P8-001 formal Test Center hierarchy

## Scope

P8-001 establishes one machine-enforced assurance hierarchy for the canonical Test Center. It does not claim that every level is already implemented or passing. It makes the assurance level of each registered test explicit and prevents source-only evidence from being promoted into behavioral, platform, or release support.

## Canonical levels

| Rank | Level | Proof boundary | Maximum support impact |
|---:|---|---|---|
| 10 | `architecture_lint` | Static architecture, schema, policy, manifest, and source-contract inspection | `NONE` |
| 20 | `unit` | Deterministic behavior within one isolated module | `SOURCE_FOUNDATION` |
| 30 | `component` | Real behavior across one bounded component contract | `BEHAVIOR_SUPPORTED` |
| 40 | `integration` | Multi-component behavior with durable state and cleanup | `BEHAVIOR_SUPPORTED` |
| 50 | `platform` | Real execution on a named mandatory platform | `PLATFORM_SUPPORTED` |
| 60 | `adversarial` | Hostile input, fault injection, races, abuse, and recovery | `PLATFORM_SUPPORTED` |
| 70 | `benchmark` | Versioned measured workload with environment identity | `BEHAVIOR_SUPPORTED` |
| 80 | `release` | Exact release-candidate certification with independent review | `RELEASE_SUPPORTED` |

The hierarchy is not a linear promotion shortcut. Release assurance requires applicable platform, adversarial, and benchmark evidence. A higher-level pass does not rewrite or coerce lower-level results, and an unexecuted result remains `BLOCKED`, `SKIPPED`, or `NOT_IMPLEMENTED`.

## Source contracts

- `schemas/test_center_assurance_hierarchy.v1.json` defines the closed hierarchy document.
- `config/test_center_assurance_hierarchy.v1.json` defines the eight levels, report requirements, and exact stable-test bindings.
- `tool/test_center_assurance_hierarchy.py check --project .` validates the hierarchy without writing.
- `tool/test_center_assurance_hierarchy_test.py` executes deterministic semantic regressions.
- `config/test_center_registry.v1.json` registers the P8-001 checks under `Reliability, Security & Diagnostics`.

Every canonical Test Center stable ID must have exactly one hierarchy binding. Unknown assurance levels fail closed. Source-only checks have a support-claim ceiling of `NONE`.

## CI and evidence

The dedicated `p8-001-ubuntu`, `p8-001-windows`, and `p8-001-macos` jobs run both the existing Test Center contract suite and the P8-001 hierarchy suite. Exact-head success is necessary before source integration can be considered. It is not sufficient for product behavior, platform support, release support, or phase completion.

Durable implementation evidence is rooted at `release/evidence/TEST_CENTER/P8-001/`. Generated run reports remain separate from reviewed source evidence.

## Certification boundary

P8-001 is complete only when the final exact commit/tree passes the canonical checks on all required lanes and an independent reviewer binds a decision to that exact identity. Worker B does not self-author an independent review. No P2 behavior, P3 authorization, native parity, production readiness, or release readiness is inferred from this hierarchy.
