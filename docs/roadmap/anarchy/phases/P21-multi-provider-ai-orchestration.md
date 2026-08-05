---
phase: P21
title: "Multi-provider AI orchestration"
execution_view_status: BLOCKED_BY_PROVIDER_BROWSER_MODEL_FOUNDATIONS
primary_workers: [G, H, D]
test_center_module: "Provider Orchestration"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P21 — Multi-provider AI orchestration

## Purpose

This is the bounded execution packet for P21. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `BLOCKED_BY_PROVIDER_BROWSER_MODEL_FOUNDATIONS`
- Primary workers: Worker G, Worker H, Worker D
- Test Center module: `Provider Orchestration`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P21-001` | Approve provider-orchestration ADR | `P3-010,P12-001,P18-003` | Central manager, adapter, transport, routing, artifact, and authority boundaries | ADR has no unresolved security or ownership ambiguity. |
| `P21-002` | Define provider and endpoint schemas | `P21-001` | `ai_provider_descriptor.v1`, endpoint capability, account and terms-policy schemas | Dart and worker languages pass round-trip/invalid fixtures. |
| `P21-003` | Define canonical execution/result schemas | `P21-001,P21-002` | Request, streamed event, result, artifact, disclosure, cost, and route-receipt contracts | Cross-language golden vectors and fuzz tests pass. |
| `P21-004` | Build provider capability registry | `P21-002,P21-003` | Runtime registry, versioning, deprecation, operation matrix, account entitlement overlays | Unsupported operation cannot be selected. |
| `P21-005` | Build provider account and session manager | `P12-004,P21-002` | API accounts, browser profiles, local endpoints, health, connect/disconnect/revoke | Cross-account substitution tests pass. |
| `P21-006` | Implement intent and constraint compiler | `P21-003,P6-004` | Parse provider/transport/model/fallback/privacy/budget constraints from language and UI | Corpus including apple/watermelon examples resolves deterministically. |
| `P21-007` | Implement deterministic provider router | `P21-004,P21-005,P21-006` | Hard filters, ranking, route receipt, health/budget/data checks | Explicit routes are never silently overridden. |
| `P21-008` | Implement fallback and reconciliation engine | `P21-007,P8-003` | Failure taxonomy, same-provider/cross-provider/local fallback, unknown-state handling | Safety/policy/terms refusals cannot be circumvented. |
| `P21-009` | Implement external usage and cost ledger | `P21-003,P21-007` | API costs, subscription-unknown usage, local estimates, quotas and ceilings | Hard budgets block pre-dispatch and reconcile final usage. |
| `P21-010` | Implement provider disclosure manifest | `P21-003,P12-004` | Exact outbound data slices, labels, retention/account policy and redaction evidence | Local-only and secret-exclusion fixtures pass. |
| `P21-011` | Implement OpenAI API adapter | `P21-003,P21-005` | Current Responses/text/tool plus declared image/video/audio/files adapters | Official test-account conformance and async artifact fixtures pass. |
| `P21-012` | Implement Gemini API adapter | `P21-003,P21-005` | Current primary text/multimodal/image/video/files/live adapters and attribution handling | Official test-account conformance passes for declared operations. |
| `P21-013` | Implement Anthropic API adapter | `P21-003,P21-005` | Messages/tool/vision/computer-use adapters; honest media capability declaration | Official test-account conformance passes and false image/video claims fail. |
| `P21-014` | Implement local-runtime provider adapter | `P18-003,P21-003` | Same canonical protocol over installed local runtimes and hardware-aware loading | CPU reference and at least two runtime adapters pass. |
| `P21-015` | Implement custom/OpenAI-compatible adapter SDK | `P19-005,P21-003` | Base URL, auth handles, model discovery, capability probes and conformance kit | A self-hosted fixture integrates without coordinator changes. |
| `P21-016` | Build provider-browser adapter framework | `P3-010,P3-017,P21-003,P21-005` | Origin/profile/account verification, prompt submission, output capture, takeover, UI-version manifest | Mock browser provider suite passes with no coordinate-only dependency. |
| `P21-017` | Implement OpenAI browser adapter | `P21-016` | Terms-aware ChatGPT profile adapter for declared text/image/file operations | Live bounded test and changed-UI failure tests pass. |
| `P21-018` | Implement Gemini browser adapter | `P21-016` | Terms-aware Gemini profile adapter for declared operations | Live bounded test and changed-UI failure tests pass. |
| `P21-019` | Implement Claude browser adapter | `P21-016` | Terms-aware Claude profile adapter for declared text/code/file operations | Live bounded test and changed-UI failure tests pass. |
| `P21-020` | Implement external artifact normalizer | `P14-002,P21-003` | Text/image/video/audio/file ingestion, hashes, provenance, thumbnails/proxies, parent relationships | API/browser/local outputs produce equivalent asset records. |
| `P21-021` | Implement durable sequential and async generation DAGs | `P21-008,P21-020,P6-011` | Dependencies, polling, restart, cancellation, duplicate prevention, apple→watermelon fixture | Crash/restart never creates an unintended duplicate generation. |
| `P21-022` | Implement ensembles and cross-provider synthesis | `P21-007,P21-020` | Parallel compare, reviewer, synthesis, best-of-N and bounded debate | Cost/data bounds and provenance fixtures pass. |
| `P21-023` | Build provider UX, preferences, onboarding and capability doctor | `P5-011,P21-005` through `P21-022` | Simple provider chip plus advanced route/account/privacy/cost/fallback controls | Fresh user connects a provider and runs local/API/browser examples without manual runtime setup. |
| `P21-024` | Provider orchestration release gate | `P21-001` through `P21-023` | Tri-OS conformance, medium-machine benchmark, terms review, privacy/cost/security report | Gate S passes with no critical/high finding and no silent routing violation. |

## Test Center deliverables

- `P21-TC-001` orchestration-boundary ADR checks
- `P21-TC-002` provider/endpoint schema tests
- `P21-TC-003` execution/result golden/fuzz vectors
- `P21-TC-004` capability registry support matrix
- `P21-TC-005` account/session substitution tests
- `P21-TC-006` natural-language route corpus
- `P21-TC-007` deterministic router properties
- `P21-TC-008` fallback/refusal/reconciliation
- `P21-TC-009` cost/quota ledger
- `P21-TC-010` disclosure-manifest privacy
- `P21-TC-011` OpenAI API conformance
- `P21-TC-012` Gemini API conformance
- `P21-TC-013` Anthropic API conformance
- `P21-TC-014` local provider conformance
- `P21-TC-015` custom-compatible SDK fixture
- `P21-TC-016` browser-provider framework
- `P21-TC-017` OpenAI browser adapter
- `P21-TC-018` Gemini browser adapter
- `P21-TC-019` Claude browser adapter
- `P21-TC-020` external artifact normalization
- `P21-TC-021` sequential/async crash safety
- `P21-TC-022` ensemble budget/provenance
- `P21-TC-023` provider UX/onboarding
- `P21-TC-024` provider release certification

## Acceptance scenarios

- `P21-ACC-001` "through OpenAI" never silently routes to another provider
- `P21-ACC-002` "through OpenAI API" never silently becomes browser
- `P21-ACC-003` "local only" produces zero external requests
- `P21-ACC-004` apple then watermelon preserves order without unintended shared input
- `P21-ACC-005` restart does not duplicate async media generation
- `P21-ACC-006` browser login/MFA requests takeover
- `P21-ACC-007` provider refusal is preserved and not bypassed
- `P21-ACC-008` actual outbound content matches disclosure manifest

## Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- OpenAI, Gemini, Anthropic/Claude, and local endpoints are first-class provider families.
- API, browser, and local transports use one canonical contract.
- Explicit user provider/transport selection is deterministic and visible.
- Browser-backed operation is terms-aware, user-owned, takeover-capable, and does not bypass restrictions.
- API credentials and browser sessions remain outside prompts.
- Images, videos, text, code, and files enter one artifact/evidence model.
- Sequential, fallback, async, and ensemble workflows survive restart without duplicate effects.
- Local-only policy has zero external dispatches.
- Medium-machine tri-OS benchmarks pass the declared budgets.
- No VM is required for ordinary provider operation.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker G. Continue the highest-priority dependency-satisfied P21 task.
```
