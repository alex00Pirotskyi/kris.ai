# MISSION-011 — Identity, Credentials, Universal Connectors, and Multi-provider Orchestration

**Default executor:** Worker H
**Priority:** `HIGH`
**Roadmap phases:** `P12`, `P21`
**Authority:** execution overlay only; `docs/roadmap/MASTER.md` remains human authority.

## Mission objective

Implement identity and credential brokerage, universal connectors, OpenAI/Gemini/Claude/local/custom provider orchestration, typed transports, account and privacy constraints, budgets, fallback, and owner-selected routes.

## Transfer and resume protocol

1. Re-resolve protected main, mission branch, PR, head/tree, CI, reviews, and dependency state.
2. Load this contract, the mission state, active claim, latest checkpoint, entry graph, and task interlocks.
3. Reuse valid implementation and evidence already present; never restart completed work without a proven defect.
4. Select the highest-priority dependency-satisfied task or a clearly labeled dependency-safe source/fixture/documentation packet.
5. Implement, test, document, commit, push, inspect exact-head CI, repair, obtain required independent review, and update state/checkpoint.
6. Yield only with an exact continuation point or complete the mission and release its claim.

## Current repository anchor

- No active claim. The mission is available only when its entry dependencies and ownership checks pass.

## P12 — Identity, credentials, and universal connectors

**Packet:** `docs/roadmap/anarchy/phases/P12-identity-credentials-and-universal-connectors.md`
**Current execution view:** `BLOCKED_BY_P11_IDENTITY_FOUNDATIONS`
**Test Center module:** `Accounts, Credentials & Connectors`

### Purpose

This is the bounded execution packet for P12. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P12-001` | Identity domain v3 | `P1-005`, `P11-002` | Human, node, account, publisher, model, connector, signer identities | Identity substitution and revocation fixtures pass. |
| `P12-002` | OS-native credential vault adapters | `P1-009`, `P11-003`, `P11-004`, `P11-005` | Windows DPAPI/Credential, macOS Keychain, Linux Secret Service adapters | Secret CRUD, locked vault, migration, and redaction tests pass. |
| `P12-003` | Credential lease service | `P12-001`, `P12-002`, `P1-003` | Short-lived operation-bound handles | Wrong run/destination/scope/use/expiry is rejected. |
| `P12-004` | Owner break-glass reveal | `P12-002`, `P2-001` | Local interactive reauth flow | Value never reaches model/log/telemetry and unattended calls fail. |
| `P12-005` | OAuth account connection framework | `P12-003` | PKCE, device, service account, refresh, revoke, multi-account | Provider fixtures cover mix-up, redirect, state, rotation, expiry. |
| `P12-006` | Connector IR and manifest v2 | `P1-006`, `P12-001` | Signed schema and registry | Modified or untrusted connector fails registration. |
| `P12-007` | OpenAPI 3.x importer | `P12-006`, `P12-005` | 3.0/3.1/3.2 parsing, generated operations and fixtures | Reference, auth, callback, upload, and malformed specs pass. |
| `P12-008` | GraphQL connector | `P12-006`, `P12-005` | Schema import, approved operations, limits | Query/mutation, custom scalar, complexity and auth fixtures pass. |
| `P12-009` | gRPC/Protobuf connector | `P12-006`, `P12-005` | Descriptor/reflection import, unary/streaming | Deadlines, metadata, status, and binary artifacts pass. |
| `P12-010` | Generic protocol adapters | `P12-006` | JSON-RPC, SOAP/WSDL, WebSocket, SSE, webhook, SFTP/SSH baseline | Shared reliability and security fixtures pass. |
| `P12-011` | Database connector foundation | `P12-003`, `P12-006` | SQL introspection, typed query, transaction and migration contracts | PostgreSQL/MySQL/SQLite/SQL Server fixtures pass. |
| `P12-012` | Connector SDK and conformance kit | `P12-007`, `P12-008`, `P12-009`, `P12-010` | Scaffolder, mock server, record/replay, sign/package | A third-party sample connector passes without core changes. |
| `P12-013` | Transaction policy service | `P12-003`, `P1-004` | Publish/send/purchase/deploy/delete policy | Limits, step-up, idempotency and reconciliation tests pass. |
| `P12-014` | Connector workspace UI | `P12-005`, `P12-012` | Accounts, scopes, operations, health, logs, revoke | User can inspect exact account and permission for every call. |

### Test Center deliverables

- `P12-TC-001` identity substitution/revocation
- `P12-TC-002` OS-native vault adapter matrix
- `P12-TC-003` credential-lease boundary tests
- `P12-TC-004` break-glass reveal isolation
- `P12-TC-005` OAuth attack and lifecycle suite
- `P12-TC-006` signed connector registry
- `P12-TC-007` OpenAPI importer corpus
- `P12-TC-008` GraphQL limits/auth suite
- `P12-TC-009` gRPC unary/streaming suite
- `P12-TC-010` generic protocol adapters
- `P12-TC-011` database connector transactions/migrations
- `P12-TC-012` third-party SDK conformance
- `P12-TC-013` consequential transaction policy
- `P12-TC-014` connector workspace acceptance

### Acceptance scenarios

- `P12-ACC-001` use credential without exposing value to model/log
- `P12-ACC-002` wrong account/destination lease is rejected
- `P12-ACC-003` OAuth mix-up/replay/redirect attacks fail
- `P12-ACC-004` timeout-after-commit reconciles provider state
- `P12-ACC-005` user can inspect exact account, scopes and last use

### Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Credentials are used through leases on all three desktop OSs.
- OpenAPI, GraphQL, gRPC, generic HTTP/webhook, and SQL connectors work.
- One external connector can be built and signed without coordinator modification.

## P21 — Multi-provider AI orchestration

**Packet:** `docs/roadmap/anarchy/phases/P21-multi-provider-ai-orchestration.md`
**Current execution view:** `BLOCKED_BY_PROVIDER_BROWSER_MODEL_FOUNDATIONS`
**Test Center module:** `Provider Orchestration`

### Purpose

This is the bounded execution packet for P21. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P21-001` | Approve provider-orchestration ADR | `P3-010`, `P12-001`, `P18-003` | Central manager, adapter, transport, routing, artifact, and authority boundaries | ADR has no unresolved security or ownership ambiguity. |
| `P21-002` | Define provider and endpoint schemas | `P21-001` | ai_provider_descriptor.v1, endpoint capability, account and terms-policy schemas | Dart and worker languages pass round-trip/invalid fixtures. |
| `P21-003` | Define canonical execution/result schemas | `P21-001`, `P21-002` | Request, streamed event, result, artifact, disclosure, cost, and route-receipt contracts | Cross-language golden vectors and fuzz tests pass. |
| `P21-004` | Build provider capability registry | `P21-002`, `P21-003` | Runtime registry, versioning, deprecation, operation matrix, account entitlement overlays | Unsupported operation cannot be selected. |
| `P21-005` | Build provider account and session manager | `P12-004`, `P21-002` | API accounts, browser profiles, local endpoints, health, connect/disconnect/revoke | Cross-account substitution tests pass. |
| `P21-006` | Implement intent and constraint compiler | `P21-003`, `P6-004` | Parse provider/transport/model/fallback/privacy/budget constraints from language and UI | Corpus including apple/watermelon examples resolves deterministically. |
| `P21-007` | Implement deterministic provider router | `P21-004`, `P21-005`, `P21-006` | Hard filters, ranking, route receipt, health/budget/data checks | Explicit routes are never silently overridden. |
| `P21-008` | Implement fallback and reconciliation engine | `P21-007`, `P8-003` | Failure taxonomy, same-provider/cross-provider/local fallback, unknown-state handling | Safety/policy/terms refusals cannot be circumvented. |
| `P21-009` | Implement external usage and cost ledger | `P21-003`, `P21-007` | API costs, subscription-unknown usage, local estimates, quotas and ceilings | Hard budgets block pre-dispatch and reconcile final usage. |
| `P21-010` | Implement provider disclosure manifest | `P21-003`, `P12-004` | Exact outbound data slices, labels, retention/account policy and redaction evidence | Local-only and secret-exclusion fixtures pass. |
| `P21-011` | Implement OpenAI API adapter | `P21-003`, `P21-005` | Current Responses/text/tool plus declared image/video/audio/files adapters | Official test-account conformance and async artifact fixtures pass. |
| `P21-012` | Implement Gemini API adapter | `P21-003`, `P21-005` | Current primary text/multimodal/image/video/files/live adapters and attribution handling | Official test-account conformance passes for declared operations. |
| `P21-013` | Implement Anthropic API adapter | `P21-003`, `P21-005` | Messages/tool/vision/computer-use adapters; honest media capability declaration | Official test-account conformance passes and false image/video claims fail. |
| `P21-014` | Implement local-runtime provider adapter | `P18-003`, `P21-003` | Same canonical protocol over installed local runtimes and hardware-aware loading | CPU reference and at least two runtime adapters pass. |
| `P21-015` | Implement custom/OpenAI-compatible adapter SDK | `P19-005`, `P21-003` | Base URL, auth handles, model discovery, capability probes and conformance kit | A self-hosted fixture integrates without coordinator changes. |
| `P21-016` | Build provider-browser adapter framework | `P3-010`, `P3-017`, `P21-003`, `P21-005` | Origin/profile/account verification, prompt submission, output capture, takeover, UI-version manifest | Mock browser provider suite passes with no coordinate-only dependency. |
| `P21-017` | Implement OpenAI browser adapter | `P21-016` | Terms-aware ChatGPT profile adapter for declared text/image/file operations | Live bounded test and changed-UI failure tests pass. |
| `P21-018` | Implement Gemini browser adapter | `P21-016` | Terms-aware Gemini profile adapter for declared operations | Live bounded test and changed-UI failure tests pass. |
| `P21-019` | Implement Claude browser adapter | `P21-016` | Terms-aware Claude profile adapter for declared text/code/file operations | Live bounded test and changed-UI failure tests pass. |
| `P21-020` | Implement external artifact normalizer | `P14-002`, `P21-003` | Text/image/video/audio/file ingestion, hashes, provenance, thumbnails/proxies, parent relationships | API/browser/local outputs produce equivalent asset records. |
| `P21-021` | Implement durable sequential and async generation DAGs | `P21-008`, `P21-020`, `P6-011` | Dependencies, polling, restart, cancellation, duplicate prevention, apple→watermelon fixture | Crash/restart never creates an unintended duplicate generation. |
| `P21-022` | Implement ensembles and cross-provider synthesis | `P21-007`, `P21-020` | Parallel compare, reviewer, synthesis, best-of-N and bounded debate | Cost/data bounds and provenance fixtures pass. |
| `P21-023` | Build provider UX, preferences, onboarding and capability doctor | `P5-011`, `P21-005`, `P21-022` | Simple provider chip plus advanced route/account/privacy/cost/fallback controls | Fresh user connects a provider and runs local/API/browser examples without manual runtime setup. |
| `P21-024` | Provider orchestration release gate | `P21-001`, `P21-023` | Tri-OS conformance, medium-machine benchmark, terms review, privacy/cost/security report | Gate S passes with no critical/high finding and no silent routing violation. |

### Test Center deliverables

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

### Acceptance scenarios

- `P21-ACC-001` "through OpenAI" never silently routes to another provider
- `P21-ACC-002` "through OpenAI API" never silently becomes browser
- `P21-ACC-003` "local only" produces zero external requests
- `P21-ACC-004` apple then watermelon preserves order without unintended shared input
- `P21-ACC-005` restart does not duplicate async media generation
- `P21-ACC-006` browser login/MFA requests takeover
- `P21-ACC-007` provider refusal is preserved and not bypassed
- `P21-ACC-008` actual outbound content matches disclosure manifest

### Exit gate

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

## Cross-mission task interlocks

- `P12-001` waits for `P1-005` from `MISSION-001`.
- `P12-001` waits for `P11-002` from `MISSION-010`.
- `P12-002` waits for `P1-009` from `MISSION-001`.
- `P12-002` waits for `P11-003` from `MISSION-010`.
- `P12-002` waits for `P11-004` from `MISSION-010`.
- `P12-002` waits for `P11-005` from `MISSION-010`.
- `P12-003` waits for `P1-003` from `MISSION-001`.
- `P12-004` waits for `P2-001` from `MISSION-001`.
- `P12-006` waits for `P1-006` from `MISSION-001`.
- `P12-013` waits for `P1-004` from `MISSION-001`.
- `P21-001` waits for `P18-003` from `MISSION-006`.
- `P21-001` waits for `P3-010` from `MISSION-003`.
- `P21-006` waits for `P6-004` from `MISSION-006`.
- `P21-008` waits for `P8-003` from `MISSION-002`.
- `P21-014` waits for `P18-003` from `MISSION-006`.
- `P21-015` waits for `P19-005` from `MISSION-014`.
- `P21-016` waits for `P3-010` from `MISSION-003`.
- `P21-016` waits for `P3-017` from `MISSION-003`.
- `P21-020` waits for `P14-002` from `MISSION-013`.
- `P21-021` waits for `P6-011` from `MISSION-006`.
- `P21-023` waits for `P5-011` from `MISSION-005`.

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
Take the repo. You are Worker H. Take MISSION-011 and continue autonomously.
```
