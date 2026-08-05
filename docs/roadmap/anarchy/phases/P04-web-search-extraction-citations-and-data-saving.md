---
phase: P4
title: "Web search, extraction, citations, and data saving"
execution_view_status: ACTIVE_DEPENDENCY_SAFE_P4_001
primary_workers: [C, D, B]
test_center_module: "Research & Data"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P4 — Web search, extraction, citations, and data saving

## Purpose

This is the bounded execution packet for P4. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `ACTIVE_DEPENDENCY_SAFE_P4_001`
- Primary workers: Worker C, Worker D, Worker B
- Test Center module: `Research & Data`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P4-001` | Search provider interface | `P1-001` | Define adapters, normalized results, errors, rate limits, region/language, date/domain filters. | Two fixture providers pass the same contract. |
| `P4-002` | Query planner | `P4-001` | Create precision, recall, official-source, freshness, and follow-up queries with bounded stopping. | Planner corpus covers current, technical, local, and ambiguous questions. |
| `P4-003` | Search deduplication and ranking | `P4-001,P4-002` | Normalize URLs, canonicalize results, detect near duplicates, rank relevance/freshness/source diversity. | Benchmark meets dedupe target. |
| `P4-004` | Safe static fetcher | `P1-004` | Add redirects, limits, MIME, TLS, URL credentials, address policy, caching, retries, and hashes. | SSRF, decompression, redirect, and timeout tests pass. |
| `P4-005` | Connection-time address pinning | `P4-004` | Close DNS-rebinding gap in restricted modes and revalidate redirects. | Rebinding fixture cannot reach blocked address. |
| `P4-006` | Rendered fetcher | `P3-002,P4-004` | Render JavaScript pages in disposable context and return final DOM/evidence. | Static and rendered outputs are distinguishable. |
| `P4-007` | Readable content extraction | `P4-004,P4-006` | Extract main text, title, author, dates, headings, lists, links, code, and diagnostics. | Supported fixture corpus reaches extraction target. |
| `P4-008` | Structured-data extraction | `P4-007` | Extract tables, JSON-LD, Open Graph, microdata, forms, and downloadable assets. | Schema and malformed-data fixtures pass. |
| `P4-009` | Pagination, sitemap, and crawl frontier | `P4-004,P4-007` | Implement bounded crawling, robots rules, rate limits, depth/pages/bytes/time, resume, and dedupe. | Crawler respects fixture robots and resumes deterministically. |
| `P4-010` | Citation span model | `P4-007` | Link claims to immutable fetched document versions and text/table locators. | Source edits do not invalidate historical citation records. |
| `P4-011` | Research content-addressed storage | `P4-004,P4-010` | Store raw, rendered, extracted, screenshot, and metadata objects by hash. | Duplicate fetch content reuses objects without losing fetch provenance. |
| `P4-012` | Web/research embedded-authority migrations | `P4-001,P4-011` | Add search, fetch, source, extraction, citation, crawl, and dataset objects plus indexes and versioned migrations. | Migration, rollback, backup, corruption, and integrity tests pass without a SQL core. |
| `P4-013` | Replaceable local lexical search | `P4-012` | Index extracted content and metadata with project/profile scoping, incremental update, and full rebuild support. | Search benchmark and index-rebuild tests pass; disabling one index implementation preserves the authority store. |
| `P4-014` | Optional semantic index | `P4-013` | Add replaceable embedding provider, versioned vectors, and lexical fallback. | Disabling embeddings preserves full product function. |
| `P4-015` | Dataset manifest and versioning | `P4-012` | Define dataset, schema, lineage, transformation recipe, source hashes, and version diff. | Dataset version is reproducible from stored inputs. |
| `P4-016` | Dataset transforms | `P4-015` | Add select, rename, cast, filter, sort, dedupe, join, normalize, annotate, and validation. | Transform property tests pass. |
| `P4-017` | Dataset exports | `P4-015,P4-016` | Export JSONL, CSV, Markdown, SQLite, and optional Parquet with provenance. | Exports reopen and validate against manifest. |
| `P4-018` | Research workspace UI | `P4-003,P4-010,P4-012` | Build search, result, source, extraction, citation, crawl, collection, and export views. | User can inspect every claim’s source. |
| `P4-019` | Data workspace UI | `P4-015,P4-017` | Build virtualized table, schema, recipes, quality, provenance, versions, and exports. | Large fixture dataset remains responsive. |
| `P4-020` | Freshness and change monitoring | `P4-011,P4-012` | Schedule re-fetch, compare hashes/extractions, notify changes, and preserve versions. | Change fixtures generate precise diffs. |
| `P4-021` | Research quality benchmark | `P4-003,P4-007,P4-010` | Create hidden/public corpus for search coverage, extraction, citations, disagreement, and freshness. | Release dashboard reports category scores. |
| `P4-022` | Research operator guide | `P4-018,P4-019` | Document interactive search, crawling, authenticated pages, citations, datasets, exports, and limitations. | Guide is exercised by scripted onboarding test. |

## Test Center deliverables

- `P4-TC-001` search-provider shared contract suite
- `P4-TC-002` query-planner corpus
- `P4-TC-003` dedupe/ranking benchmark
- `P4-TC-004` static fetch security suite
- `P4-TC-005` DNS-rebinding and redirect suite
- `P4-TC-006` rendered-fetch distinction tests
- `P4-TC-007` readable extraction benchmark
- `P4-TC-008` structured-data extraction fixtures
- `P4-TC-009` crawl/robots/frontier-resume suite
- `P4-TC-010` immutable citation-locator suite
- `P4-TC-011` content-addressed storage dedupe suite
- `P4-TC-012` authority migration/backup/corruption tests
- `P4-TC-013` lexical index rebuild suite
- `P4-TC-014` semantic-index optionality suite
- `P4-TC-015` dataset manifest/version reproducibility
- `P4-TC-016` transform property tests
- `P4-TC-017` export reopen-and-validate tests
- `P4-TC-018` research workspace UI tests
- `P4-TC-019` data workspace virtualization tests
- `P4-TC-020` freshness/change-monitoring fixtures
- `P4-TC-021` research quality certification
- `P4-TC-022` onboarding/operator acceptance

## Acceptance scenarios

- `P4-ACC-001` search two fixture providers and deduplicate results
- `P4-ACC-002` fetch sources before allowing claims
- `P4-ACC-003` answer with citations that reopen exact immutable spans
- `P4-ACC-004` extract article and table from static and rendered pages
- `P4-ACC-005` create dataset, transform, version, export CSV/JSONL/Markdown
- `P4-ACC-006` rebuild indexes from authority data
- `P4-ACC-007` resume bounded crawl after interruption
- `P4-ACC-008` detect changed source and preserve both versions
- `P4-ACC-009` reject SSRF, rebinding, giant response and decompression bomb

## Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Search results are normalized and fetched before use.
- Static and rendered extraction meets benchmark thresholds.
- Citations bind to immutable source versions.
- Research and datasets persist, version, search, and export reproducibly.
- Crawl limits and robots handling pass fixtures.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker C. Continue the highest-priority dependency-satisfied P4 task.
```
