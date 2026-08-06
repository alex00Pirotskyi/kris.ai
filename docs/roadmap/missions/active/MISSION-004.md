# MISSION-004 — Research, Data, Citations, and Knowledge

**Default executor:** Worker C
**Priority:** `HIGH`
**Roadmap phases:** `P4`
**Authority:** execution overlay only; `docs/roadmap/MASTER.md` remains human authority.

## Mission objective

Build search, safe fetch, extraction, citations, crawling, content-addressed research storage, datasets, indexes, workspaces, change monitoring, and evidence-backed reusable knowledge.

## Transfer and resume protocol

1. Re-resolve protected main, mission branch, PR, head/tree, CI, reviews, and dependency state.
2. Load this contract, the mission state, active claim, latest checkpoint, entry graph, and task interlocks.
3. Reuse valid implementation and evidence already present; never restart completed work without a proven defect.
4. Select the highest-priority dependency-satisfied task or a clearly labeled dependency-safe source/fixture/documentation packet.
5. Implement, test, document, commit, push, inspect exact-head CI, repair, obtain required independent review, and update state/checkpoint.
6. Yield only with an exact continuation point or complete the mission and release its claim.

## Current repository anchor

- Worker: `D`
- Branch: `agent/p4-001-search-provider-foundation`
- Draft PR: `#62`
- Observed head: `1c089c7094a122bb3cfbbc78221f218b3dd7ac0f`
- Observed tree: `276481693c3da7d56fa3e315018c851e659ddec5`
- Current work: P4-001 exact source/integration candidate is reconciled with current Worker B/P8 ancestry and all exact-head CI passes; Worker B and Worker J decisions are pending, Worker I is BLOCKED_EXTERNAL, and P4-002 plus merge remain unauthorized.
- These are discovery anchors, not permission to skip live-state discovery.

## P4 — Web search, extraction, citations, and data saving

**Packet:** `docs/roadmap/anarchy/phases/P04-web-search-extraction-citations-and-data-saving.md`
**Current execution view:** `ACTIVE_DEPENDENCY_SAFE_P4_001`
**Test Center module:** `Research & Data`

### Purpose

This is the bounded execution packet for P4. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P4-001` | Search provider interface | `P1-001` | Define adapters, normalized results, errors, rate limits, region/language, date/domain filters. | Two fixture providers pass the same contract. |
| `P4-002` | Query planner | `P4-001` | Create precision, recall, official-source, freshness, and follow-up queries with bounded stopping. | Planner corpus covers current, technical, local, and ambiguous questions. |
| `P4-003` | Search deduplication and ranking | `P4-001`, `P4-002` | Normalize URLs, canonicalize results, detect near duplicates, rank relevance/freshness/source diversity. | Benchmark meets dedupe target. |
| `P4-004` | Safe static fetcher | `P1-004` | Add redirects, limits, MIME, TLS, URL credentials, address policy, caching, retries, and hashes. | SSRF, decompression, redirect, and timeout tests pass. |
| `P4-005` | Connection-time address pinning | `P4-004` | Close DNS-rebinding gap in restricted modes and revalidate redirects. | Rebinding fixture cannot reach blocked address. |
| `P4-006` | Rendered fetcher | `P3-002`, `P4-004` | Render JavaScript pages in disposable context and return final DOM/evidence. | Static and rendered outputs are distinguishable. |
| `P4-007` | Readable content extraction | `P4-004`, `P4-006` | Extract main text, title, author, dates, headings, lists, links, code, and diagnostics. | Supported fixture corpus reaches extraction target. |
| `P4-008` | Structured-data extraction | `P4-007` | Extract tables, JSON-LD, Open Graph, microdata, forms, and downloadable assets. | Schema and malformed-data fixtures pass. |
| `P4-009` | Pagination, sitemap, and crawl frontier | `P4-004`, `P4-007` | Implement bounded crawling, robots rules, rate limits, depth/pages/bytes/time, resume, and dedupe. | Crawler respects fixture robots and resumes deterministically. |
| `P4-010` | Citation span model | `P4-007` | Link claims to immutable fetched document versions and text/table locators. | Source edits do not invalidate historical citation records. |
| `P4-011` | Research content-addressed storage | `P4-004`, `P4-010` | Store raw, rendered, extracted, screenshot, and metadata objects by hash. | Duplicate fetch content reuses objects without losing fetch provenance. |
| `P4-012` | Web/research embedded-authority migrations | `P4-001`, `P4-011` | Add search, fetch, source, extraction, citation, crawl, and dataset objects plus indexes and versioned migrations. | Migration, rollback, backup, corruption, and integrity tests pass without a SQL core. |
| `P4-013` | Replaceable local lexical search | `P4-012` | Index extracted content and metadata with project/profile scoping, incremental update, and full rebuild support. | Search benchmark and index-rebuild tests pass; disabling one index implementation preserves the authority store. |
| `P4-014` | Optional semantic index | `P4-013` | Add replaceable embedding provider, versioned vectors, and lexical fallback. | Disabling embeddings preserves full product function. |
| `P4-015` | Dataset manifest and versioning | `P4-012` | Define dataset, schema, lineage, transformation recipe, source hashes, and version diff. | Dataset version is reproducible from stored inputs. |
| `P4-016` | Dataset transforms | `P4-015` | Add select, rename, cast, filter, sort, dedupe, join, normalize, annotate, and validation. | Transform property tests pass. |
| `P4-017` | Dataset exports | `P4-015`, `P4-016` | Export JSONL, CSV, Markdown, SQLite, and optional Parquet with provenance. | Exports reopen and validate against manifest. |
| `P4-018` | Research workspace UI | `P4-003`, `P4-010`, `P4-012` | Build search, result, source, extraction, citation, crawl, collection, and export views. | User can inspect every claim’s source. |
| `P4-019` | Data workspace UI | `P4-015`, `P4-017` | Build virtualized table, schema, recipes, quality, provenance, versions, and exports. | Large fixture dataset remains responsive. |
| `P4-020` | Freshness and change monitoring | `P4-011`, `P4-012` | Schedule re-fetch, compare hashes/extractions, notify changes, and preserve versions. | Change fixtures generate precise diffs. |
| `P4-021` | Research quality benchmark | `P4-003`, `P4-007`, `P4-010` | Create hidden/public corpus for search coverage, extraction, citations, disagreement, and freshness. | Release dashboard reports category scores. |
| `P4-022` | Research operator guide | `P4-018`, `P4-019` | Document interactive search, crawling, authenticated pages, citations, datasets, exports, and limitations. | Guide is exercised by scripted onboarding test. |

### Test Center deliverables

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

### Acceptance scenarios

- `P4-ACC-001` search two fixture providers and deduplicate results
- `P4-ACC-002` fetch sources before allowing claims
- `P4-ACC-003` answer with citations that reopen exact immutable spans
- `P4-ACC-004` extract article and table from static and rendered pages
- `P4-ACC-005` create dataset, transform, version, export CSV/JSONL/Markdown
- `P4-ACC-006` rebuild indexes from authority data
- `P4-ACC-007` resume bounded crawl after interruption
- `P4-ACC-008` detect changed source and preserve both versions
- `P4-ACC-009` reject SSRF, rebinding, giant response and decompression bomb

### Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Search results are normalized and fetched before use.
- Static and rendered extraction meets benchmark thresholds.
- Citations bind to immutable source versions.
- Research and datasets persist, version, search, and export reproducibly.
- Crawl limits and robots handling pass fixtures.

## Cross-mission task interlocks

- `P4-001` waits for `P1-001` from `MISSION-001`.
- `P4-004` waits for `P1-004` from `MISSION-001`.
- `P4-006` waits for `P3-002` from `MISSION-003`.

## Git, collision, and merge contract

- One active claim per mission. A replacement worker must receive a recorded yield or transfer.
- Do not edit another active mission's exclusive paths or shared authority without an explicit coordination packet.
- Workers may commit, push, update their draft PR, and iterate CI inside their bounded claim.
- No blanket right to bypass branch protection, required checks, security review, dependency gates, or roadmap authority.
- A materially changed exact candidate invalidates commit-bound reviews and evidence.
- Every significant push updates mission state and creates or supersedes a checkpoint.

## Mission definition of done

The mission is complete only when every assigned roadmap task is truthfully complete; applicable unit, contract, component, integration, negative, regression, platform, recovery, performance, acceptance, certification, and release gates pass; evidence and documentation are durable; required independent reviews bind the final exact commit/tree; and the integrated product capability works on every mandatory platform claimed by the roadmap.

## Resume command

```text
Take the repo. You are Worker C. Take MISSION-004 and continue autonomously.
```
