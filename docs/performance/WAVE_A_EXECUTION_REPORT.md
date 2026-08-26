# Performance Wave A — Execution Report

## Base

- Repository: `alex00Pirotskyi/kris.ai`
- Confirmed live protected `main`: `9336c5568cbc1db9e9c867441dcc46af14339aa4`
- Delivery form: source-shape-guarded local implementation bundle
- Branch: not created in the repository
- PR: not created
- Exact repository head SHA: unchanged; no remote write capability was available

The implementation was derived from the confirmed live-main files rather than
historical branch names or stale implementation notes.

## Baseline performance

The deterministic baseline harness is implemented for 64-, 1,500-, and
10,000-file source projects. It records cold index construction, repeated warm
queries, one-file mutation updates, symbol lookup, scan counts, indexed bytes,
cache state, sample count, minimum, p50, p95, maximum, and mean latency.

No workstation latency numbers are embedded in this report. The execution
environment used to build the bundle did not contain a Dart or Flutter SDK, so
publishing synthetic or inferred timings would be misleading.

## Implemented

### Performance instrumentation

- Added a first-party `PerformanceSpan` abstraction.
- Added structured operation, duration, project hash, cache state, thermal
  state, count, token, model, tool, persistence, verification, process,
  browser, analyzer, source-index, and knowledge timing fields.
- Rejected arbitrary text in machine-label fields.
- Preserved the measured result and original exception when telemetry
  construction or recording fails.
- Wired source index update and search spans into the current runtime.

### Rebuildable cache database

- Added runtime-owned `cache/cache.sqlite3` through the existing application
  cache directory.
- Kept `state/workflow.sqlite3` exclusively authoritative.
- Added independent cache schema versioning and schema-revision checks.
- Added SQLite header validation and `quick_check`.
- Added quarantine-and-recreate behavior for corrupt or incompatible cache
  files.
- Added an in-memory fallback when persistent cache storage is unavailable.
- Added transactional, namespaced generation counters.
- Added bounded performance-span retention.
- Added diagnostics for startup mode, persistence mode, size, schema, last
  rebuild, row counts, dropped writes, and degraded state.

### Write-amplification control

- Span writes are buffered rather than committed individually.
- A batch is flushed after 64 records, after a two-second quiet period, when
  diagnostics are requested, or during orderly shutdown.
- Batch writes use one SQLite transaction.
- Advisory spans still buffered at an abnormal process termination may be
  lost; no workflow authority or completion state is affected.

### Benchmark corpus

- Added deterministic small, medium, and large project generators.
- Added source-index baseline measurements with explicit cold/warm and
  hit/miss classification.
- Changed the mutated file's byte length so coarse filesystem timestamp
  resolution cannot hide the change.
- Added a machine-readable benchmark manifest that distinguishes automated
  scenarios from model, knowledge, persistent-toolchain, P3, and Owner Mode
  fixtures scheduled for later waves.

## Security boundaries

- Cache state cannot grant permission, Owner Mode authority, effect authority,
  completion, evidence, verification, idempotency, or leases.
- Cache failures degrade to misses, generation zero, rebuild, or memory mode.
- Performance rows do not contain prompts, source text, terminal output,
  credentials, or arbitrary user text fields.
- Performance statistics are advisory only.
- No Owner Mode or P3 security boundary was modified.

## Validation performed in this environment

Passed:

- Confirmed the live protected-main SHA and inspected current runtime, storage,
  source-index, observability, dependency, and source-contract files.
- Applied every guarded edit against a reconstructed live-source-shape fixture;
  every expected replacement matched exactly once.
- Re-ran the installer idempotently; all files and edits were recognized as
  already present.
- Injected a stale source shape and verified the dry preflight failed before
  writing any Wave A file.
- Parsed `apply_wave_a.py` with Python bytecode compilation.
- Parsed every JSON artifact.
- Performed a string/comment-aware delimiter scan across every added Dart file.
- Executed the cache schema, span insert, generation upsert, and retention SQL
  through SQLite.
- Verified the span insert has 30 placeholders and 30 values.
- Verified the cache-generation upsert advances monotonically.
- Verified retention SQL leaves the configured newest-row limit.
- Verified no `flutter clean` command exists in the implementation path.

Not executed here:

- `dart format`
- `flutter test`
- `flutter analyze`
- workstation baseline benchmarks

The bundle's apply script runs targeted formatting when Dart is present. With
`--validate`, it runs the four focused tests and one final analyzer pass. The
source manifest is refreshed once at the end.

## Git activity

One direct repository transport attempt was made and stopped after DNS access
failed. No repeated Git CLI inspection, cleanup, branch churn, commits, pushes,
or PR operations were performed. The optional final manifest refresh in the
apply script uses the repository's existing manifest tool once; that existing
tool performs one tracked/untracked file enumeration.

## Regressions and limitations

- The primary source engine is intentionally still the current JSON/linear
  implementation in Wave A. Its measured baseline is the input to Wave B.
- Model, knowledge, analyzer, P2, and P3 runtime measurements require configured
  fixtures and are represented in the benchmark manifest rather than
  fabricated.
- Source-index operation exceptions are not yet persisted as failed spans;
  successful and empty-result paths are measured. The generic span helper does
  preserve and classify failures for later integrations.
- Buffered advisory spans below the batch threshold can be lost on hard process
  termination.
- No before/after speedup percentage is claimed until the same benchmark corpus
  is run before and after Wave B on the same hardware.

## Continuation

The highest-return continuation is Wave B: normalized SQLite source projects,
files, symbols, dependencies, generations, qualified FTS support, committed
file-local updates, and watcher-driven freshness. The continuation base remains
`9336c5568cbc1db9e9c867441dcc46af14339aa4` until this Wave A bundle is applied
and qualified in a real checkout.
