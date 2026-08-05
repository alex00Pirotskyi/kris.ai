# P4-001 Search Provider Interface Foundation

## Task and authority

- Task: `P4-001 — Search Provider Interface`
- Human roadmap authority: `docs/roadmap/MASTER.md`
- Machine dependency ledger: `docs/roadmap/roadmap.yaml`
- Branch: `agent/p4-001-search-provider-foundation`
- Original base: `5794dffa6fd8f1c16d6c004c9f75aca0e7b8b961`
- Original Worker C head: `6b877b2a344ad8f9c2f52e9888d902165ac50c5f`
- Synchronized protected-main base: `de8dc3bcde31356b490c32b7d60bb373d9fa68ed`
- Synchronization commit: `71d63f256b86b8da0e5ecf740a4c8d066155af0b`
- Observed implementation head before documentation/evidence: `122ea8902bb4c33547928434a6d4d5aa88e08c73`
- Observed implementation tree: `a2257451d6d6eb72df75717e9921ec6a7f3841c7`

The branch was synchronized with a genuine two-parent merge commit. The protected-main P2 integration-control files were preserved byte-for-byte. No conflict occurred because the P2 controller and P4-001 foundation occupy disjoint paths.

## Scope

Implemented only the provider-neutral search interface foundation required by P4-001:

- immutable request, result, page, rate-limit, partial-failure, provider-error, and capability models;
- strict request/page/error schemas;
- deterministic serialization and semantic query identity;
- stable provider and result identities;
- explicit capability negotiation;
- provider/query/version-bound pagination cursors;
- explicit rate-limit and typed partial-failure semantics;
- two deterministic network-free fixture providers sharing one canonical envelope;
- dependency-free schema validation for the reviewed schema subset;
- fail-closed URL, domain, timestamp, size, numeric, field, capability, metadata, and secret validation;
- permanent `unfetched_snippet_only` classification for snippets.

## Explicit exclusions

Not implemented:

- query planning or aggregation;
- live HTTP search;
- static or rendered fetch;
- browser automation, sessions, DOM observation, downloads, uploads, tracing, or takeover;
- extraction, citations, crawling, datasets, or research workspace;
- Owner Mode, terminal, filesystem authority, or native execution;
- P2 or P3 implementation;
- P4-002 or another roadmap task.

## Architecture

The dependency direction is:

```text
SearchProvider interface
→ immutable canonical contracts
→ strict validation and schemas
→ deterministic fixture adapters
→ source-only contract gate
```

Providers normalize native candidates into canonical `SearchResult` and `SearchPage` values. Provider metadata is untrusted supplementary data. It cannot redefine canonical identity, rank, URL, snippet, retrieval, evidence, pagination, rate-limit, or failure authority fields.

## Acceptance coverage

| Roadmap requirement | Source | Schema/fixture | Positive verification | Negative verification | Status |
|---|---|---|---|---|---|
| Provider-neutral interface | `provider.py`, `models.py` | all three schemas | two adapters return one envelope | provider mismatch rejected | implemented |
| Typed query and filters | `SearchRequest` | request schema and contract cases | minimal/full requests | unknown fields, invalid filters, limits, dates, domains | implemented |
| Pagination | `fixture_provider.py` | page schema | first/next page | malformed, wrong-provider, wrong-query, wrong-version cursor | implemented |
| Rate and error semantics | `SearchRateLimit`, `SearchProviderError` | page/error schemas | deterministic rate state | invalid retry/rate values | implemented |
| Partial failure | `SearchPartialFailure` | partial fixture case | surviving results retained | unsupported failure code rejected | implemented |
| Two adapters | `fixture_provider_a`, `fixture_provider_b` | contract cases | canonical parity | unsupported exclusion on beta | implemented |
| Stable identity | semantic query hash and result hash | deterministic fixtures | request/cursor/page-size invariance | duplicate results/ranks rejected | implemented |

## Security and validation decisions

- Request contracts expose no credential, grant, Owner Mode, browser, terminal, filesystem, or native-execution channel.
- Secret-key normalization handles snake case, camel case, Pascal case, kebab case, and mixed punctuation.
- Result URLs require HTTP(S), a host, no embedded credentials, and no fragment.
- Canonical JSON rejects NaN and infinities.
- Domain filters reject IP literals, invalid names, overlap, and excessive entries.
- Provider metadata rejects secret-bearing keys and canonical authority-field names recursively.
- Pagination tokens bind contract version, provider identity, semantic query identity, and offset.
- A semantic query identity excludes request ID, cursor, and page size, but includes query and semantic filters.

## Dependency decision

Production and tests remain Python standard-library-only. No Python, Flutter, Node, native, or GitHub Actions toolchain dependency was added or changed.

## Test Center and development verification impact

- Module: `P4 Research & Data / Search Provider Interface`
- Assurance classes: unit, schema, contract, component, negative, regression
- Environment: deterministic network-free fixtures
- Support claim: `search_provider_interface_source_foundation`
- Explicitly unsupported claims: live search, web search, research completion, citations, rendered fetch

No parallel Test Center registry was invented because no committed P4 Test Center registration surface currently exists.

## Testing performed before exact-head CI

The new regression module was executed locally against the modified contract implementation:

```text
6 tests run
6 passed
0 failures
0 errors
0 skipped
network usage: none
output SHA-256: 90fe3eb0b64a9fd2e89b92d1eaa7b2d1e7684afe333abb0ae6f29e60f7af6657
```

The branch source gate discovers every `test_*.py` file and now includes the regression module in its required inventory. Exact-head full contract and repository results are recorded in `release/evidence/P4-001/` after CI observation.

## Synchronization and parallel compatibility

Worker A's protected P2 integration-control commit was merged without modification. Worker B review artifacts and PR #14 were not changed. The P4 implementation remains isolated under `services/research_worker`, P4-specific schemas/fixtures, and the P4 source gate.

## Generated roadmap files

`docs/roadmap/STATUS.md` and `docs/roadmap/HANDOFF.md` are declared derived from `roadmap.yaml`. The current machine ledger has bootstrap scope P0/P1 and contains no authorized P4 row. Worker C therefore did not manually add an ungoverned P4 status or handoff entry. This progress record is the P4-001 side-branch handoff until the roadmap-control owner adopts P4 in the machine ledger.

## Classification and limitations

Classification: `source_only_machine_observed`.

P4-001 is not release-ready and is not yet completion-eligible. Exact-head CI and independent AI review remain required. Deterministic fixture providers are not external search providers and do not prove live web behavior.

## Integration guidance

After P2/P3 and the roadmap machine ledger are ready, integrate the provider interface without changing its claim boundary. Later search implementations must adapt through `SearchProvider`, honor capability negotiation and cursor binding, and keep provider snippets classified as unfetched until a later authorized fetch/citation phase establishes evidence.

## Next dependency

The next roadmap task is identified by the live roadmap after P4-001 review and dependency authorization. P4-002 was not started.
