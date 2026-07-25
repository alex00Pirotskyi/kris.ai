# Kristin Benchmark Governance

## Purpose

P0-009 establishes the first versioned benchmark corpus and reproducible baseline. It does **not** establish production quality thresholds and it does not imply that unsupported or unexecuted capabilities pass.

## Initial categories

- Coding
- Analysis
- Path safety
- Crash recovery
- Browser capability honesty
- Research and citations

Every category contains at least two cases. The corpus mixes executable current-product gates with future model task fixtures. Each case declares its assurance level and proof kind.

## Status semantics

| Status | Meaning |
|---|---|
| `passed` | The declared evaluator executed and met its current expectation. |
| `failed` | The evaluator executed and exposed a measurable gap. |
| `unavailable` | A required SDK, file, or local execution prerequisite was unavailable in this baseline mode. |
| `unsupported` | The product does not currently expose the required capability. |
| `not_run` | A valid task fixture exists but no model/candidate result was supplied. |
| `error` | The benchmark infrastructure itself failed. |

Only `passed` is a pass. A failed benchmark case does not fail P0-009; P0-009 is complete when the corpus, evaluator, result semantics, and baseline are reproducible.

## Assurance boundaries

- `source_contract` / `source_inspection` can measure architecture or wiring only.
- `behavioral` / `executed_behavior` records a command or evaluator that actually ran.
- `capability_inventory` records whether a capability exists; absence is `unsupported`, not pass.
- `benchmark_task` / `model_evaluation` requires a candidate result and otherwise remains `not_run` or `unsupported`.

The baseline report always asserts:

```text
sourceInspectionIsBehavioralProof = false
unsupportedCountsAsPassed = false
unavailableCountsAsPassed = false
notRunCountsAsPassed = false
baselineRecordedMeansProductReady = false
```

## Reproduction

```bash
python3 tool/benchmark_runner.py validate --project .
python3 tool/benchmark_runner.py run --project . --mode portable
python3 tool/benchmark_runner.py check --project .
```

The portable mode is network-free, credential-free, model-free, and excludes SDK-dependent execution so the same checkout produces the same committed result on supported hosts.

A machine-specific exploratory run may include SDK gates:

```bash
python3 tool/benchmark_runner.py run \
  --project . \
  --mode machine \
  --include-sdk \
  --output release/evidence/P0-009/execution.json \
  --markdown release/evidence/P0-009/EXECUTION.md
```

Machine results supplement the portable baseline; they do not replace it.

## Model task evaluation

Materialize a task fixture:

```bash
python3 tool/benchmark_runner.py materialize \
  --project . \
  --case coding.python_bugfix_task \
  --output /tmp/coding.python_bugfix_task
```

After an agent modifies or produces candidate files, place them under a candidate root using the case's declared relative path and run. Workspace tasks are evaluated in a fresh temporary copy of the authoritative fixture; only the suite-declared mutable files are copied from the candidate, so the candidate cannot replace its acceptance tests:

```bash
python3 tool/benchmark_runner.py run \
  --project . \
  --mode machine \
  --candidate-root /tmp/candidates \
  --output /tmp/model-benchmark.json \
  --markdown /tmp/model-benchmark.md
```

Future model/provider benchmarks must record exact provider, model, prompt/policy version, account/data boundary, cost, latency, and candidate hashes outside the portable baseline. Candidate execution is a benchmark harness, not a hostile-code sandbox; untrusted candidates must later run through the isolated evaluation backend introduced by the platform/security phases.

A capability inventory passes only when the suite names actual behavioral evidence files and all of them are present. Source files, tool names, or UI labels are implementation signals only and cannot make a browser or other capability pass.

## Change control

A suite change requires:

1. suite-version increment;
2. fixture and evaluator review;
3. a new portable baseline;
4. explicit migration notes for score comparability;
5. no deletion of a failing case merely to improve results;
6. independent review before the new baseline becomes authoritative.

P8-001 later expands this bootstrap into the formal benchmark and assurance hierarchy.
