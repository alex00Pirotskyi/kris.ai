# Performance Wave A — Observability and Cache Foundation

## Base

- Live protected `main`: `9336c5568cbc1db9e9c867441dcc46af14339aa4`
- Branch: `perf/cache-sqlite-foundation`
- Pull request: `#276`
- Train: performance, model utilization, and native acceleration
- Wave: A — observability and cache foundation

Wave A is implemented directly in the repository. It is not an external bundle
and does not require an `apply_wave_a.py` installer.

## Implemented architecture

Kristin now has a separate runtime-owned `cache.sqlite3` under the existing
application cache directory. It is not part of `ProductRepositories` and does
not participate in workflow authority.

`workflow.sqlite3` remains authoritative for durable workflow state,
permissions, effects, leases, checkpoints, evidence, and completion.
`cache.sqlite3` contains only rebuildable performance state.

The cache startup contract is:

1. Open the application-owned cache database.
2. Validate the SQLite header, `quick_check`, schema version, and schema
   revision.
3. Reuse a compatible database.
4. Quarantine and recreate a corrupt or incompatible database.
5. Fall back to an in-memory cache when persistent cache storage is
   unavailable.
6. Continue normal application startup without using cache state as authority.

The initial schema contains:

- `cache_metadata`
- `cache_generations`
- `performance_spans`

Diagnostics expose schema version, persistent versus memory mode, startup mode,
cache size, row counts, dropped writes, degradation state, and last rebuild
time.

SQLite settings are intentionally different from workflow authority:

- WAL for the persistent cache
- `synchronous=NORMAL`
- bounded SQLite page cache
- memory temporary storage
- bounded WAL size and autocheckpointing
- a five-second busy timeout

These settings apply only to rebuildable cache state.

## Performance spans

`PerformanceSpan` records structured counters and timings without accepting
arbitrary attributes. It supports:

- operation and outcome;
- project hash;
- cold/warm state;
- cache hit/miss state;
- item, byte, and candidate counts;
- model identity, role, and task class;
- input/output token counts;
- first-token and total model latency;
- model/tool call counts;
- persistence, verification, process, browser, analyzer, source-index, and
  knowledge-retrieval durations.

Machine-label validation rejects whitespace, newlines, prompt text, source
contents, and arbitrary user text. Measurement recording is best effort, so an
instrumentation failure cannot replace the measured operation's result or
original exception.

The current `SourceIndexService` emits spans for:

- `source.index.update`
- `source.search`

This establishes a measurable baseline before the JSON/linear index is replaced
in Wave B.

## Bounded maintenance

Performance rows are retained with a configurable maximum. Span records are
buffered in memory and flushed as one SQLite transaction after 64 records,
after a two-second quiet period, when diagnostics are requested, or during
shutdown. Trimming is periodic rather than performed after every insert.

Cache generation counters are transactional and namespaced by a machine label
plus an optional project hash. Advisory spans still buffered during abnormal
process termination may be lost; workflow authority is unaffected.

A cache read/write failure degrades generation lookups to zero and performance
recording to a degraded advisory state. It cannot grant authority or certify
completion.

## Benchmark corpus

The deterministic benchmark runner creates:

- small corpus: 64 files;
- medium corpus: 1,500 files;
- large corpus: 10,000 files.

For each corpus it measures:

- cold source-index update;
- repeated warm source query;
- one externally changed file followed by update;
- repeated warm symbol lookup.

The result JSON separates cold/warm and hit/miss state and records sample count,
minimum, p50, p95, maximum, and mean latency. The current changed-file baseline
also records how many files were scanned so Wave B can prove that incremental
indexing eliminates project-wide rereads.

Run the full baseline:

```bash
dart run tool/performance/run_wave_a_benchmarks.dart
```

Skip the 10,000-file corpus for a quick local smoke benchmark:

```bash
dart run tool/performance/run_wave_a_benchmarks.dart --skip-large
```

Write to an explicit result file:

```bash
dart run tool/performance/run_wave_a_benchmarks.dart \
  --output=performance-results/wave-a-baseline.json
```

## Focused validation

```bash
dart format \
  lib/product/performance_cache.dart \
  lib/product/performance_spans.dart \
  lib/product/extensions_index.dart \
  lib/product/product_runtime.dart \
  test/product/performance_cache_test.dart \
  test/product/performance_spans_test.dart \
  test/product/source_index_performance_test.dart \
  test/product/source_contract_test.dart \
  tool/performance/benchmark_corpus.dart \
  tool/performance/run_wave_a_benchmarks.dart

flutter test test/product/performance_spans_test.dart
flutter test test/product/performance_cache_test.dart
flutter test test/product/source_index_performance_test.dart
flutter test test/product/source_contract_test.dart

flutter analyze
```

Refresh `SOURCE_MANIFEST.sha256` once after all edits and formatting:

```bash
python3 tool/p1a_refresh_source_manifest.py .
```

No `flutter clean`, platform regeneration, or broad unrelated formatting is part
of this workflow.

## Performance results

Wave A does not embed fabricated latency numbers. Benchmark output must be
produced on the target workstation and retained with operating system, Dart
version, processor count, sample counts, and cold/warm classifications.
Before/after percentages belong in the Wave B report after the SQLite/FTS source
engine is implemented and measured against this baseline.

## Next continuation

Wave B should extend the same `cache.sqlite3` contract with normalized source
project, file, symbol, dependency, generation, and qualified FTS tables. It
must preserve direct filesystem authority for final bytes, update only
committed changed paths, and prove through the Wave A benchmark that repeated
queries and one-file updates no longer perform full JSON decoding and linear
project scans.
