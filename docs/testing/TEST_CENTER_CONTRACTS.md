# Canonical Test Center and Development Verification contracts

Status: **Worker B canonical shared-contract candidate**  
Scope: data contracts, validation, deterministic selection, and independent review evidence.  
Out of scope: roadmap authority, worker-ledger authority, P1/P1A/P2 runtime repair, complete Testing Studio UI, and release approval.

## Authority boundary

The Test Center consumes roadmap task identifiers and worker-produced evidence, but it does not become roadmap or worker authority. The following state domains remain separate:

| Domain | Canonical examples | Forbidden inference |
|---|---|---|
| Roadmap task | `READY`, `IN_PROGRESS`, `REVIEW`, `DONE` | A test `PASS` cannot mark a task `DONE`. |
| Worker runtime | `CLAIMED`, `ACTIVE`, `YIELDED`, `BLOCKED` | A worker state cannot become a test result. |
| Test execution | `PASS`, `FAIL`, `ERROR`, `SKIPPED`, `BLOCKED`, `UNKNOWN`, `FLAKY`, `NOT_IMPLEMENTED` | A test `PASS` cannot create certification or support. |
| Certification | `NOT_EVALUATED`, `PARTIAL`, `PASS`, `FAIL`, `STALE`, `REVOKED` | Certification requires exact-candidate evidence and independent review. |
| Capability support | `SOURCE_FOUNDATION`, `BEHAVIOR_SUPPORTED`, `PLATFORM_SUPPORTED`, `RELEASE_SUPPORTED`, and conservative negative states | Source presence or a test result cannot silently inflate support. |

## Existing-component inventory

| Existing component | Classification | Reuse decision |
|---|---|---|
| `tool/assurance_model.py` | `REUSE_EXISTING_VERIFIED` | Preserve its source-versus-behavior separation and assurance vocabulary. |
| `schemas/assurance_report.v1.json` | `REUSE_EXISTING_RETEST_REQUIRED` | Accept only through an explicit legacy result adapter; do not make it the normalized result authority. |
| `schemas/project_profile.v2.json` | `EXTEND_EXISTING` | Reuse structured executable/arguments and sandbox intent. Project Test Profiles add stable IDs, affected paths, evidence destinations, platform matrix, and mandatory non-mutation. |
| `schemas/verification_report.v1.json` | `EXTEND_EXISTING` | Reuse hashed evidence concepts. Exact commit/tree binding, cleanup, platform coverage, independent review, and certification remain new strict requirements. |
| P1/P1A/P2 task receipts and hosted QA bundles | `REUSE_EXISTING_RETEST_REQUIRED` | Preserve original immutable evidence and normalize it without claiming behavioral or release certification. |
| Canonical Test Center schema, stable identity, affected mapping, certification, Development Verification, Testing Studio metadata | `IMPLEMENT_MISSING` | Implemented by `schemas/test_center.v1.json`, `config/test_center_registry.v1.json`, and `tool/test_center_contracts.py`. |

## Canonical models

`schemas/test_center.v1.json` defines:

- `TestModule`
- `TestCase`
- `StableTestId`
- `ProjectTestProfile`
- `AffectedTestMapping`
- `TestExecutionResult`
- `EvidenceReference`
- `CertificationRecord`
- `CapabilitySupportRecord`
- `DevelopmentVerificationRequest`
- `DevelopmentVerificationResult`
- `TestingStudioPresentationRecord`

Stable test IDs use the immutable lowercase dotted form `tc.<module>.<case>`. Renaming display text does not rename an ID. Duplicate case or profile IDs are rejected, and every test case has exactly one Project Test Profile.

## Project Test Profile safety

A verification profile declares a stable check ID, argv array, repository-relative working directory, platforms, timeout, environment allowlist, input paths, expected outputs, mutation policy, assurance class, evidence destination, and affected paths.

Verification profiles are always `NON_MUTATING`. Shell interpreters, shell control tokens, absolute paths, parent traversal, newline/NUL argv tokens, duplicate environment entries, and evidence destinations outside `release/evidence/` are rejected. Repair, generation, formatting, commit, push, and merge remain separate governed operations.

## Result and evidence integrity

The normalized result preserves exact test/module/task identity, commit, tree, branch, working-tree identity, platform, runner, toolchain, environment, timing, state, exit code, assurance class, immutable evidence references, cleanup, failure classification, and certification impact.

Legacy states are normalized only through an explicit adapter. Unknown values fail closed. Original evidence references retain their SHA-256 and exact commit/tree binding.

## Certification safety

Certification is evaluated separately from test execution. `PASS` is rejected when any of the following is true:

- required evidence or test results are missing;
- evidence, result, or independent review belongs to another commit/tree;
- a required platform is absent;
- a mandatory result is not `PASS`;
- cleanup is unresolved;
- independent review is missing or not `PASS`;
- a critical/high finding is unresolved;
- the certification is stale;
- evidence bindings are empty.

A certification record does not mutate roadmap or capability-support state.

## Testing Studio metadata

The presentation contract supports `Test Me`, `Quick Check`, `Development Verification`, `Affected Tests`, `Platform Certification`, `Evidence`, and `Release Readiness`. It exposes display name, purpose, phase, capability, assurance class, platform matrix, explicit state domain, current state, last exact-commit result, stale warning, required next action, evidence links, certification impact, and support-claim impact.

This is a data/presentation contract, not the complete Testing Studio UI.

## Deterministic commands

Read-only contract check:

```text
python tool/test_center_contracts.py check --project .
```

Semantic regression suite:

```text
python -m unittest -v tool/test_center_contracts_test.py
```

Deterministic affected-test selection:

```text
python tool/test_center_contracts.py select-affected --project . <changed-path>...
```

Generated validation evidence is an explicit separate operation:

```text
python tool/test_center_contracts.py write-report --project .
```

`check` never writes the report. The explicitly generated, committed validation record is stored at `release/evidence/worker-b/test-center-contract-validation.json`; `release/evidence/generated/**` remains disposable generated state and must not contain tracked certification evidence.
