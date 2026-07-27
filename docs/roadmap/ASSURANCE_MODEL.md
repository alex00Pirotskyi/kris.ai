# Kristin Assurance Model v1

**Milestone:** P0-007 — Split source lint from behavioral assurance
**Status:** implemented, pending complete-checkout execution and independent review
**Schema:** `schemas/assurance_report.v1.json`

## Purpose

Kristin previously combined source-marker checks, executable tests, SDK checks, and release claims in reports that looked equally authoritative. A source check can prove that a class, call, schema, test name, or security hook exists. It cannot prove that the behavior ran, resisted attack, survived a crash, or worked on a native operating system.

P0-007 establishes a claim firewall:

```text
source inspection
  -> architecture/source-contract evidence only

executed deterministic harness
  -> behavioral evidence for exactly the exercised behavior

native OS/installer/update execution
  -> platform or release evidence
```

## Assurance categories

| Category | Meaning | Counts as pure behavioral proof? |
|---|---|---:|
| `architecture_lint` | Source-tree shape, imports, syntax, forbidden dependencies, generated-state policy | No |
| `source_contract` | Wiring, required markers, schemas, documentation, declared tests, compatibility hooks | No |
| `mixed` | A legacy gate combines an executable command with source-marker assertions | No |
| `behavioral` | A deterministic executable harness validates observable behavior without depending on source-marker success | Yes |
| `sdk_toolchain` | Formatter, dependency resolver, analyzer, or test runner executed | No, not by itself |
| `platform` | Native OS behavior, packaging, containment, install, update, or rollback executed | Yes for its stated platform scope |
| `release` | Signed and attributable release transaction executed and independently verified | Yes for its stated release scope |
| `unclassified` | A new check has no reviewed classification | No; strict reports fail |

## Proof kinds

```text
source_inspection
executed_behavior
toolchain_execution
platform_execution
release_execution
mixed
unclassified
```

The report field `behavioral_proof` may be `true` only for `executed_behavior`, `platform_execution`, or `release_execution` evidence. It is always `false` for `source_inspection`, `mixed`, and `unclassified` evidence.

## Non-negotiable rules

1. **Source checks never prove runtime behavior.**
2. **Mixed gates do not count as pure behavioral evidence.** They remain useful compatibility gates until their executable and source portions are split into separate records.
3. **SDK success is not platform success.** `flutter analyze` and `flutter test` do not establish native packaging, signing, installation, containment, update, or rollback.
4. **Unknown checks fail classification.** A new validator function must be added to the assurance taxonomy before a strict report can pass.
5. **Names and prose cannot upgrade evidence.** Classification is derived from the producing function and reviewed taxonomy, not from persuasive check names.
6. **Behavioral evidence is criterion-scoped.** Passing the SQLite durability harness proves the covered SQLite invariants; it does not prove browser automation, sandbox containment, or updater security.
7. **Platform and release claims require lane evidence.** Source and mixed checks cannot satisfy those categories.

## P0-007 implementation

### `tool/system_test.py`

The compatibility gate remains available, but its machine-readable output now declares:

```json
{
  "assuranceLevel": "source_contract",
  "proofKind": "source_inspection",
  "behavioralProof": false
}
```

### `tool/validate_release.py`

Every `Check` records:

```text
assurance_level
proof_kind
behavioral_proof
claim_scope
source_function
```

The validator creates separate summary groups for source, mixed, behavioral, SDK/toolchain, platform, release, and unclassified checks. Mixed checks are excluded from behavioral totals.

### `tool/architecture_contract_test.py`

This wrapper executes `system_test.py`, validates the source-only metadata, and writes:

```text
release/ARCHITECTURE_CONTRACT_RESULTS.json
release/ARCHITECTURE_CONTRACT_RESULTS.md
```

### `tool/assurance_dashboard.py`

The dashboard combines the categorized validation report and architecture report into:

```text
release/ASSURANCE_REPORT.json
release/ASSURANCE_REPORT.md
```

It fails in strict mode when:

- a check is unclassified;
- a source or mixed check claims behavioral proof;
- a blocking categorized check failed;
- report metadata is inconsistent.

## Migration guidance

Legacy mixed checks should be split incrementally:

```text
source marker assertions
  -> architecture/source-contract result

executable test command and parsed outcome
  -> behavioral result
```

P0-007 does not rewrite every legacy test. It prevents overclaim immediately and creates the stable model used by P8-001 for the full test hierarchy.

## Required commands

```bash
python3 tool/assurance_model_test.py
python3 tool/p0_007_assurance_test.py --project .
python3 tool/architecture_contract_test.py --project .
python3 tool/validate_release.py --skip-sdk
python3 tool/assurance_dashboard.py --project . --strict
```

## Definition of done

P0-007 is `DONE` only when:

- the complete checkout passes the commands above;
- `release/ASSURANCE_REPORT.json` has `noSourceMarkerOverclaim: true`;
- no check is `unclassified`;
- a fresh independent reviewer confirms that source and mixed checks are not presented as behavioral proof;
- the roadmap status and evidence manifest identify the exact tested commit.
