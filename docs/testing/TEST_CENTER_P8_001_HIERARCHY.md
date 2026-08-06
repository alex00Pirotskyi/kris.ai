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

The hierarchy is not a linear promotion shortcut. Release assurance requires applicable platform, adversarial, and benchmark evidence. A higher-level pass does not rewrite lower-level results, and an unexecuted result remains `BLOCKED`, `SKIPPED`, or `NOT_IMPLEMENTED`.

## Machine connection to execution results

`schemas/test_center_assurance_execution_report.v1.json` is a closed, versioned wrapper around canonical `TestExecutionResult`. Each report must bind the result to exactly one active hierarchy mapping, the canonical module and roadmap tasks, the same commit/tree, and a support request at or below the level ceiling.

The read-only command below validates a real normalized result rather than checking only field names in hierarchy configuration:

```text
python tool/test_center_assurance_hierarchy.py check-report \
  --project . \
  --report release/evidence/TEST_CENTER/P8-001/fixtures/assurance-execution-report.pass.json
```

Missing, unknown, mismatched, cross-candidate, source-promoting, unexecuted-promoting, or above-ceiling actual reports fail closed. The canonical `TestExecutionResult` schema remains unchanged and closed; the wrapper supplies the P8 assurance-level identity without weakening it.

## Downstream integration contract

`pendingMigrationSource` freezes Worker A PR #64 at commit `89a15332019c73675a19cdacd7021fae2199d75e` / tree `2ea1f8a718a69dba0120a4f98acb78053d6cebfb`, and `pendingMigrationBindings` records its exact eleven reviewed stable IDs. They are not active bindings until those IDs enter the canonical registry. Integration fails if a pending ID appears without being promoted to exactly one active binding.

`tc.p1a.exit-gate` is explicitly `architecture_lint` and `sourceOnly: true` because its current command uses `--source-only`. A future real platform certification must use a separate stable identity and real platform evidence. No source result is promoted to platform support.

## Source contracts

- `schemas/test_center_assurance_hierarchy.v1.json` defines the closed hierarchy document.
- `schemas/test_center_assurance_execution_report.v1.json` defines the closed execution-report wrapper.
- `config/test_center_assurance_hierarchy.v1.json` defines levels, active bindings, pending migrations, and report policy.
- `tool/test_center_assurance_semantics.py` enforces hierarchy and actual-result semantics.
- `tool/test_center_assurance_hierarchy.py check --project .` validates the hierarchy without writing.
- `tool/test_center_assurance_hierarchy.py check-report ...` validates an actual canonical execution record.
- `tool/test_center_assurance_hierarchy_test.py` executes deterministic semantic regressions.

Every canonical Test Center stable ID must have exactly one active hierarchy binding. Unknown assurance levels fail closed. Source-only checks have a support-claim ceiling of `NONE`.

## CI and evidence

The dedicated Ubuntu, Windows, and macOS jobs run the existing Test Center suite, hierarchy validation, actual execution-report validation, 32 deterministic regressions, and non-mutation checks. They regenerate `SOURCE_MANIFEST.sha256` through `tool/p1a_refresh_source_manifest.py` and fail if the committed manifest differs. Ubuntu uploads the canonical generated manifest to support a deterministic repair loop.

Exact-head success is necessary before source integration can be considered. It is not sufficient for product behavior, platform support, release support, or phase completion. Durable evidence is rooted at `release/evidence/TEST_CENTER/P8-001/`.

## Certification boundary

P8-001 is complete only when the final exact commit/tree passes all required lanes and an independent reviewer binds a decision to that exact identity. Worker B does not self-author an independent review. No P2 behavior, P3 authorization, native parity, production readiness, or release readiness is inferred from this hierarchy.
