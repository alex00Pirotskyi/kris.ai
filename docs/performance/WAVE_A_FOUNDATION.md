# Performance Wave A — Observability and Cache Foundation

## Base

- Live protected `main`: `9336c5568cbc1db9e9c867441dcc46af14339aa4`
- Train: performance, model utilization, and native acceleration
- Wave: A — observability and cache foundation

## Applying this bundle

Extract the bundle outside the Kristin checkout, then apply it to a current
checkout based on the live-main source shape:

```bash
python3 apply_wave_a.py /path/to/kris.ai --validate
```

On Windows:

```powershell
py apply_wave_a.py C:\path\to\kris.ai --validate
```

The script copies only the Wave A files, applies exact source-shape-guarded
edits, formats only changed Dart files, optionally runs the four focused tests
plus one final analyzer pass, and refreshes `SOURCE_MANIFEST.sha256` once at the
end. It creates no branch, commit, or PR and never runs `flutter clean`.

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
cache size, row counts, dropped writes, degradation state, and the last rebuild
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

- operation and outcome
- project hash
- cold/warm state
- cache hit/miss state
- item, byte, and candidate counts
- model identity, role, and task class
- input/output token counts
- first-token and total model latency
- model/tool call counts
- persistence, verification, process, browser, analyzer, source-index, and
  knowledge-retrieval durations

Machine-label validation rejects whitespace, newlines, prompt text, source
contents, and arbitrary user text. The measurement helper treats record
construction and sink failures as best-effort telemetry, so instrumentation
cannot replace the measured operation's result or original exception.

The current `SourceIndexService` emits spans for:

- `source.index.update`
- `source.search`

This creates a measurable baseline before the JSON/linear index is replaced in
Wave B.

## Bounded maintenance

Performance rows are retained with a configurable maximum. Span records are
buffered in memory and flushed as one SQLite transaction after 64 records,
after a two-second quiet period, when diagnostics are requested, or during
shutdown. Trimming is periodic rather than performed after every insert. Cache
generation counters are transactional and namespaced by a machine label plus
an optional project hash. Advisory spans still buffered during an abnormal
process termination may be lost; workflow authority is unaffected.

A cache read/write failure degrades generation lookups to zero and retrieval to
cache-miss behavior. It cannot grant authority or certify completion.

## Benchmark corpus

The deterministic benchmark runner creates:

- small corpus: 64 files
- medium corpus: 1,500 files
- large corpus: 10,000 files

For each corpus it measures:

- cold source-index update
- repeated warm source query
- one externally changed file followed by update
- repeated warm symbol lookup

The result JSON separates cold/warm and hit/miss state and records sample count,
minimum, p50, p95, maximum, and mean latency. The current one-file-change
baseline also records how many files were scanned, so Wave B can prove that
incremental indexing eliminates project-wide rereads.

Run the full baseline:

```bash
dart run tool/performance/run_wave_a_benchmarks.dart
```

Skip the 10,000-file corpus when only a quick local smoke benchmark is needed:

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

Refresh `SOURCE_MANIFEST.sha256` once, after formatting and all edits:

```bash
python3 tool/p2_refresh_source_manifest.py .
```

No `flutter clean` is part of this workflow.

## Performance results

This wave does not embed fabricated latency numbers. The benchmark output must
be produced on the target workstation and retained with its operating system,
Dart version, processor count, sample counts, and cold/warm classifications.
Before/after percentages belong in the Wave B report after the SQLite/FTS
source engine is implemented and measured against this baseline.

## Next continuation

Wave B should extend the same `cache.sqlite3` schema contract with normalized
source project, file, symbol, dependency, generation, and qualified FTS tables.
It should preserve direct filesystem authority for final bytes, update only
committed changed paths, and prove through this benchmark that repeated queries
and one-file updates no longer perform full JSON decoding and linear project
scans.
