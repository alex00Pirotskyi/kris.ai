# Kristin Research and Data Operator Guide

## What the research system does

Kristin separates discovery from evidence. Search-provider snippets are discovery hints only. Claims should be based on fetched, versioned source evidence with extraction hashes and citation spans. The Research Workspace exposes search, results, immutable source versions, extraction identity, citations, crawl jobs, collections, changes and export. The Data Workspace exposes dataset rows, schema, transformation recipes, quality, provenance, version diff and export.

## Search and query planning

A research question is expanded into bounded precision, recall, official-source, freshness and follow-up queries. The planner does not search forever: result budgets and provider limits terminate exploration. Results are canonicalized, tracking parameters are removed, near duplicates are collapsed, and ranking combines relevance, freshness, provider diversity and provider rank.

Search results are not evidence until the referenced document is fetched.

## Safe static fetching

Static research fetches require HTTPS. URL credentials are not accepted. DNS is resolved before connection and only public addresses are eligible. The network connection is opened to the validated address while TLS SNI and the HTTP Host header remain bound to the original hostname; redirects are resolved, revalidated and re-pinned. Fetches have redirect, time, MIME and byte limits.

Do not use research fetching to probe localhost, private networks, link-local addresses, cloud metadata endpoints or other restricted destinations.

## Rendered pages and authenticated pages

JavaScript-rendered evidence uses the P3 browser runtime through a disposable rendered-page adapter. The returned evidence is explicitly marked rendered and is bound to the canonical page observation and screenshot hashes. The rendered page is closed after evidence capture.

Authenticated research should use an explicitly selected browser profile and the P3 takeover flow for MFA, CAPTCHA, payment, consent or ambiguity. Do not attempt CAPTCHA bypass.

## Extraction and structured data

Readable extraction captures title, author/date metadata when present, main readable text, headings, lists, links and code. Structured extraction captures bounded JSON-LD, tables, Open Graph fields, form counts and downloadable assets. Malformed structured records are ignored rather than granting them authority.

## Crawling

Crawls are bounded by pages, depth, total bytes, elapsed time and per-host delay. The crawler obeys robots rules, remains within the seed host unless a future policy explicitly broadens scope, deduplicates canonical URLs and saves a resumable frontier checkpoint. A stopped crawl is not silently reported as complete; its stop reason and remaining frontier are part of the result.

## Immutable source versions and citations

Fetched content is stored by SHA-256. Re-fetching identical bytes reuses the content object while preserving a separate fetch-version record and timestamp. Raw, rendered, screenshot and extraction objects have separate identities.

Citations bind a claim to an exact fetch version, extraction hash, character span and quote hash. If a website later changes, historical citation records still point to the evidence version that supported the original claim.

## Local research search

The replaceable lexical index is project/profile scoped and can be fully rebuilt from authority records. An optional semantic index may improve ranking, but disabling embeddings must leave lexical search fully functional. The semantic index is never the source of authority; it only proposes document identities that still resolve through the durable store.

## Datasets

Datasets are versioned from source hashes, schema and explicit transformation recipes. Supported operations include field selection, rename, cast, filter, sort, dedupe, text normalization, annotation, required-field validation and a deterministic keyed join. A version manifest includes parent version, source hashes, recipe and a rows hash so the same stored inputs and time-bound manifest reproduce the same version identity.

The Data Workspace uses lazy row construction for large datasets instead of materializing every cell widget at once.

## Dataset export

Supported required exports are JSONL, CSV, Markdown and SQLite. Each export is generated from an immutable dataset version. SQLite exports include a manifest table with the dataset version ID and manifest hash. Parquet remains optional and is not claimed unless an approved implementation is present.

## Freshness and change monitoring

A monitor compares immutable extraction hashes per canonical URL. The first observation establishes the baseline, identical hashes produce no change, and changed hashes produce a precise before/after record. Previous fetch versions remain available for audit and citation verification.

## Authority storage, backup and recovery

Research entities are accessed through `P4ResearchAuthorityStore`, not SQL embedded in domain services. The current file-backed authority adapter and future SQLite/no-SQL adapters can implement the same entity contract. The migration layer is versioned and supports rollback of applied migration steps. Backup first verifies authority integrity, copies application-owned records, and emits a deterministic manifest hash.

If integrity verification detects malformed records, stop research mutations, preserve the corrupt store for diagnosis, restore a verified backup or rebuild replaceable indexes from immutable authority/source objects. Do not delete corrupt evidence silently.

## Limitations

- Search providers can omit, reorder or bias results; provider snippets are not evidence.
- Extraction may miss content hidden behind unsupported interaction or complex rendering.
- Robots rules and site policies can restrict crawling.
- Authenticated pages can expose sensitive content; profile and evidence boundaries must be selected deliberately.
- A citation proves what the stored source version contained; it does not prove that the source's claim is true.
- Semantic search is optional and must not become a hard dependency.

## Completion checklist

A research task is ready to report complete only when the relevant result was fetched or rendered, the final evidence version is immutable, material claims have citation bindings, crawl stop conditions are honest, datasets carry reproducible provenance, and requested exports reopen and validate against their manifest.
