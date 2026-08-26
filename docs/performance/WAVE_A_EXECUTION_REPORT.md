# Performance Wave A — Execution Report

## Base

- Repository: `alex00Pirotskyi/kris.ai`
- Confirmed live protected `main`: `9336c5568cbc1db9e9c867441dcc46af14339aa4`
- Branch: `perf/cache-sqlite-foundation`
- Pull request: `#276`
- Delivery: direct repository implementation from live protected `main`
- Code-equivalent cleanup head before this report correction:
  `fd4e9a4556b27f565d1ca9b210386f9afe069769`

The final pull-request head and hosted check results are authoritative after
report-only or manifest-only commits. The implementation was derived from live
protected `main`, not from historical branch names or stale implementation
notes.

## Baseline performance

The deterministic baseline harness covers 64-, 1,500-, and 10,000-file source
projects. It records:

- cold cache open;
- warm cache reopen;
- cold source-index construction;
- repeated warm source queries;
- one-file mutation followed by index update;
- repeated symbol lookup;
- scan, change, candidate, result, and indexed-byte counts;
- sample count, minimum, p50, p95, maximum, and mean latency.

No workstation latency numbers or speedup percentages are embedded in this
wave. Those claims require before/after samples collected on the same hardware
and environment.

## Implemented

### Performance instrumentation

- Added first-party `PerformanceSpan` and `PerformanceSpanRecord` abstractions.
- Added structured operation, duration, project hash, cache state, thermal
  state, count, token, model, tool, persistence, verification, process,
  browser, analyzer, source-index, and knowledge timing fields.
- Rejected arbitrary text in machine-label fields.
- Preserved the measured result and original exception when telemetry
  construction or recording fails.
- Instrumented source-index update and search without changing filesystem
  authority.

### Rebuildable cache database

- Added runtime-owned `cache/cache.sqlite3` through the application cache
  directory.
- Kept `state/workflow.sqlite3` authoritative and fail-closed.
- Added independent cache schema versioning and schema-revision checks.
- Added SQLite-header validation and `quick_check`.
- Added quarantine-and-recreate behavior for corrupt or incompatible cache
  files.
- Added an in-memory fallback when persistent cache storage is unavailable.
- Added transactional namespaced generation counters.
- Added bounded performance-span retention.
- Added diagnostics for startup mode, persistence mode, size, schema, last
  rebuild, row counts, dropped writes, and degraded state.

### Write-amplification control

- Buffered performance spans rather than committing each record separately.
- Flushed a batch after 64 records, after a two-second quiet period, when
  diagnostics are requested, or during orderly shutdown.
- Used one SQLite transaction per batch.
- Kept buffered spans advisory: abnormal termination may lose them without
  affecting workflow authority or completion.

### Benchmark corpus

- Added deterministic small, medium, and large project generators.
- Added source-index baseline measurements with explicit cold/warm and
  hit/miss classification.
- Mutated file length as well as content so coarse filesystem timestamp
  resolution cannot hide the change.
- Added a machine-readable benchmark manifest distinguishing implemented
  scenarios from model, knowledge, persistent-toolchain, P3, and Owner Mode
  fixtures reserved for later waves.

## Security boundaries

- Cache state cannot grant permission, Owner Mode authority, effect authority,
  completion, evidence, verification, idempotency, or leases.
- Cache failures degrade to misses, generation zero, rebuild, or memory mode.
- Performance rows do not contain prompts, source text, terminal output,
  credentials, secret values, or arbitrary user text fields.
- Performance statistics remain advisory.
- No Owner Mode or P3 security boundary was weakened.
- Direct filesystem bytes remain authoritative over source-index contents.

## Validation

Focused validation recorded for the Wave A implementation:

- `performance_spans_test.dart`: 7 tests passed
- `performance_cache_test.dart`: 7 tests passed
- `source_index_performance_test.dart`: 2 tests passed
- `source_contract_test.dart`: 46 tests passed
- `flutter analyze`: no issues
- repository format-scope checks: clean
- `git diff --check`: clean

Hosted qualification is rerun on every final PR head. After temporary diagnostic
workflows were removed, the canonical source-manifest regeneration and
non-mutation checks passed on Ubuntu, macOS, and Windows at cleanup head
`fd4e9a4556b27f565d1ca9b210386f9afe069769`.

The pull request's final check suite, rather than this static report, is the
authority for the exact final-head validation state.

## Git activity

Wave A is delivered directly on `perf/cache-sqlite-foundation` through PR
`#276`. Temporary report-diagnostic workflows used to isolate a hosted failure
were removed after they identified source-manifest scope as the issue. They are
not part of the product diff or the governed source manifest.

No merge into protected `main` is claimed in this report.

## Regressions and limitations

- The primary source engine remains the existing JSON/linear implementation in
  Wave A. Its measured baseline is the input to Wave B.
- Model, knowledge, analyzer, P2, and P3 runtime measurements require configured
  fixtures and are represented in the benchmark manifest rather than
  fabricated.
- Source-index operation exceptions are not yet persisted as failed spans;
  successful and empty-result paths are measured. The generic span helper does
  classify failed measured actions.
- Buffered advisory spans below the batch threshold can be lost on hard process
  termination.
- No before/after speedup percentage is claimed until Wave B is measured against
  this baseline on the same hardware.

## Continuation

The highest-return continuation is Wave B: normalized SQLite source projects,
files, symbols, dependencies, generations, qualified FTS support, committed
file-local updates, canonical indexed search, and watcher-driven freshness.

Wave B should branch from protected `main` only after PR `#276` is merged and
its exact merge SHA is confirmed.
