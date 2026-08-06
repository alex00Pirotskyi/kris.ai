# MISSION-007 — Interoperability, Skills, Tools, and Capability Operating System

**Default executor:** Worker G
**Priority:** `HIGH`
**Roadmap phases:** `P7`, `P23`
**Authority:** execution overlay only; `docs/roadmap/MASTER.md` remains human authority.

## Mission objective

Implement the canonical ontology and portable, signed, permissioned Tool/Skill/Capability OS with MCP, A2A, recipes, plugins, discovery, compilation, testing, evidence, and compatibility.

## Transfer and resume protocol

1. Re-resolve protected main, mission branch, PR, head/tree, CI, reviews, and dependency state.
2. Load this contract, the mission state, active claim, latest checkpoint, entry graph, and task interlocks.
3. Reuse valid implementation and evidence already present; never restart completed work without a proven defect.
4. Select the highest-priority dependency-satisfied task or a clearly labeled dependency-safe source/fixture/documentation packet.
5. Implement, test, document, commit, push, inspect exact-head CI, repair, obtain required independent review, and update state/checkpoint.
6. Yield only with an exact continuation point or complete the mission and release its claim.

## Current repository anchor

- No active claim. The mission is available only when its entry dependencies and ownership checks pass.

## P7 — MCP, A2A, skills, and extension ecosystem

**Packet:** `docs/roadmap/anarchy/phases/P07-mcp-a2a-skills-and-extension-ecosystem.md`
**Current execution view:** `READY_PARALLEL_P7_001`
**Test Center module:** `Interoperability & Extensions`

### Purpose

This is the bounded execution packet for P7. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P7-001` | MCP version adapter architecture | `P1-001` | Support current stable MCP and isolate upcoming/spec-draft changes behind adapters; pin negotiated versions. | Protocol upgrade cannot silently remove capabilities. |
| `P7-002` | MCP server descriptor and registry | `P1-005`, `P7-001` | Record publisher, digest, version, transport, tools, resources, prompts, roots, network, secrets, and retention. | Unregistered or changed server fails trust policy. |
| `P7-003` | MCP lifecycle manager | `P7-002`, `P1-004` | Install, enable, start, health-check, stop, update, revoke, and remove servers. | Lifecycle and process cleanup tests pass. |
| `P7-004` | MCP execution isolation | `P7-003` | Run untrusted servers in isolated workers; Owner Mode may opt into host execution with clear status. | Mode selection is explicit and auditable. |
| `P7-005` | A2A 1.0 protocol adapter | `P1-005` | Implement Agent Cards, discovery, task/messages/artifacts, version header, auth schemes, streaming, and async tasks. | Conformance fixtures pass for supported subset. |
| `P7-006` | A2A trust and delegation grants | `P7-005`, `P1-003` | Bind remote agent identity, task, inputs, outputs, network, secrets, deadline, and downstream delegation. | Remote agent cannot widen authority. |
| `P7-007` | Replace environment-selected A2A executable | `P7-006` | Change bridge to resolve a registered agent/worker descriptor instead of raw executable JSON. | Environment control alone cannot execute an arbitrary program. |
| `P7-008` | A2A evidence and reconciliation | `P7-006` | Validate artifacts, progress, cancellation, idempotency, and unknown outcomes. | Forged completion and duplicate effect fixtures fail. |
| `P7-009` | Skill and plugin manifest v2 | `P1-006` | Define signed publisher identity, code digest, permissions, compatibility, entry point, tests, and revocation. | Unsigned or modified production extension is rejected. |
| `P7-010` | Extension marketplace/local registry | `P7-009` | Build install, inspect, enable, update, disable, revoke, and trust UI. | User sees exact requested capabilities. |
| `P7-011` | Interop adversarial suite | `P7-003`, `P7-008`, `P7-010` | Test prompt injection, lookalike tools, signer substitution, confused deputy, replay, and cascading failure. | No unresolved critical/high finding. |
| `P7-012` | Interop operator documentation | `P7-011` | Document MCP/A2A versions, trust, isolation, Owner Mode, data retention, and revocation. | Docs match conformance and UI. |

### Test Center deliverables

- `P7-TC-001` MCP version negotiation
- `P7-TC-002` descriptor identity/digest tests
- `P7-TC-003` lifecycle and process cleanup
- `P7-TC-004` isolated versus host execution truth
- `P7-TC-005` A2A conformance
- `P7-TC-006` delegation-grant containment
- `P7-TC-007` environment-selected executable removal regression
- `P7-TC-008` forged completion/idempotency/reconciliation
- `P7-TC-009` signed extension manifest
- `P7-TC-010` install/update/revoke UX
- `P7-TC-011` interop adversarial suite
- `P7-TC-012` operator documentation scenario

### Acceptance scenarios

- `P7-ACC-001` unregistered MCP server is rejected
- `P7-ACC-002` changed server digest requires review
- `P7-ACC-003` remote agent cannot widen grant
- `P7-ACC-004` revoked extension stops loading
- `P7-ACC-005` malicious tool description cannot impersonate policy

### Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- MCP and A2A versions are pinned and negotiated.
- External servers/agents/extensions have trusted identities and scoped grants.
- Raw environment data cannot select an arbitrary A2A executable.
- Adversarial interoperability suite has no open critical/high issue.

## P23 — Tool, Skill and Capability Operating System

**Packet:** `docs/roadmap/anarchy/phases/P23-tool-skill-and-capability-operating-system.md`
**Current execution view:** `BLOCKED_BY_CAPABILITY_PROVIDER_AND_SKILL_FOUNDATIONS`
**Test Center module:** `Tools, Skills & Capabilities`

### Purpose

This is the bounded execution packet for P23. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P23-001` | Approve execution ontology ADR | `P1-001`, `P7-009`, `P19-005` | Tool/capability/skill/recipe/plugin/connector/agent/workflow definitions | Every subsystem maps without overlap. |
| `P23-002` | Adopt Agent Skills compatibility profile | `P23-001` | Portable SKILL.md import/export, progressive disclosure and compatibility tests | Reference packages round-trip without Kristin lock-in. |
| `P23-003` | Define signed Skill Manifest v3 and lock | `P1-006`, `P23-002` | Digest tree, publisher, permissions, capabilities, dependencies, evals and revocation | Mutation, downgrade and signer-substitution tests fail. |
| `P23-004` | Define Capability Descriptor v4 | `P23-001`, `P11-002`, `P12-006`, `P21-004` | Extended semantics, effects, resources, transactions, health and quality | All built-in capability classes validate. |
| `P23-005` | Define Tool Contract Standard v1 | `P23-004`, `P8-003` | Shared action/effect/idempotency/cancel/reconcile/evidence contract | Dart and workers pass golden and fuzz vectors. |
| `P23-006` | Build capability graph and deterministic resolver | `P23-004`, `P23-005`, `P21-007` | Goal→skill→capability→tool/provider graph and route receipts | Explicit constraints and policy property tests pass. |
| `P23-007` | Implement token-efficient discovery | `P23-006`, `P18-009` | Progressive metadata retrieval and bounded model tool catalogs | Recall/precision and local-model context budgets pass. |
| `P23-008` | Implement skill parser and validator | `P23-002`, `P23-003` | YAML/Markdown/resources/scripts validator and safe path rules | Malformed, recursive and path-escape packages fail. |
| `P23-009` | Implement skill compiler IR | `P23-006`, `P23-008` | Deterministic DAG, grants, locks, checkpoints, takeover, verification and rollback | Same locked skill compiles reproducibly. |
| `P23-010` | Implement durable skill runtime | `P23-009`, `P6-011`, `P8-003` | Start/pause/resume/cancel/restart/migrate/reconcile | Crash and unknown-effect fixtures pass. |
| `P23-011` | Implement safe skill composition | `P23-009`, `P23-010` | Subskill schemas, budget, state, recursion and transaction rules | Cycle, confused-deputy and budget tests pass. |
| `P23-012` | Implement tool/skill health service | `P23-004`, `P19-010`, `P21-016` | Canaries, health states, last-known-good, disable and repair | Broken capability stops routing before user impact threshold. |
| `P23-013` | Implement multi-tool transaction and resource locks | `P23-005`, `P8-003` | Prepare/commit/compensate/reconcile and lock manager | Duplicate booking/send/deploy/edit fixtures produce no duplicate effects. |
| `P23-014` | Build Skill Studio basic | `P5-004`, `P23-008`, `P23-009` | Conversational creation, import, edit, simulate, install and export | User creates a private tested skill without editing raw files. |
| `P23-015` | Build Skill Studio advanced | `P23-014` | Visual DAG, permission, provider, test, version and manifest editors | Developer can diagnose compile/runtime failures. |
| `P23-016` | Implement verified-run-to-skill proposal | `P23-014`, `P23-010` | Parameterization, subskill discovery, fixture generation and human approval | Untrusted content cannot auto-install or publish. |
| `P23-017` | Implement permission and update-diff UX | `P23-003`, `P5-007` | Install/update capability, destination, credential and egress preview | New authority cannot activate silently. |
| `P23-018` | Build skill evaluation harness | `P23-010`, `P8-015` | Positive, negative, crash, provider, platform, cost, security and accessibility suites | Skill quality reports are reproducible. |
| `P23-019` | Build Gold Skill Pack — communication/travel | `P23-018`, `P12-014`, `P3-018` | Gmail/calendar and hotel/travel skills with fixtures | Real and fixture beta meets thresholds. |
| `P23-020` | Build Gold Skill Pack — coding/research | `P23-018`, `P13-014`, `P4-021` | App, repository, research and dataset skills | Supported recipes meet task and false-completion gates. |
| `P23-021` | Build Gold Skill Pack — content/computer/productivity | `P23-018`, `P14-014`, `P15-010` | Content, desktop and personal productivity skills | Tri-OS and artifact correctness gates pass. |
| `P23-022` | Build registry and marketplace governance | `P19-008`, `P23-003`, `P23-018` | Official/private/public registries, review, quality, revoke and rollback | Modified or revoked skills stop loading. |
| `P23-023` | Run tool/skill security assessment | `P23-011`, `P23-022` | Supply-chain, injection, confused-deputy and authority review | Zero unresolved critical/high findings. |
| `P23-024` | Tool/Skill/Capability OS release gate | `P23-001`, `P23-023` | Discovery, compilation, runtime, marketplace, Gold Skill and consumer permission evidence | Gate U passes on all mandatory desktop OSs and medium hardware. |

### Test Center deliverables

- `P23-TC-001` ontology consistency
- `P23-TC-002` portable Agent Skills round-trip
- `P23-TC-003` signed skill manifest/lock
- `P23-TC-004` capability descriptor validation
- `P23-TC-005` tool contract golden/fuzz
- `P23-TC-006` capability graph/resolver
- `P23-TC-007` token-efficient discovery benchmark
- `P23-TC-008` skill parser/path safety
- `P23-TC-009` deterministic compiler
- `P23-TC-010` durable runtime crash/restart
- `P23-TC-011` composition cycles/confused deputy
- `P23-TC-012` health and last-known-good
- `P23-TC-013` multi-tool transaction/locks
- `P23-TC-014` Skill Studio basic E2E
- `P23-TC-015` Skill Studio advanced
- `P23-TC-016` verified-run proposal safety
- `P23-TC-017` permission/update-diff UX
- `P23-TC-018` skill evaluation harness
- `P23-TC-019` communication/travel Gold Skills
- `P23-TC-020` coding/research Gold Skills
- `P23-TC-021` content/computer/productivity Gold Skills
- `P23-TC-022` registry/marketplace governance
- `P23-TC-023` security assessment regressions
- `P23-TC-024` Tool/Skill OS certification

### Acceptance scenarios

- `P23-ACC-001` portable skill imports/exports without lock-in
- `P23-ACC-002` skill cannot grant itself authority
- `P23-ACC-003` new permission in update remains disabled until approved
- `P23-ACC-004` crash during multi-tool booking/send/deploy does not duplicate effect
- `P23-ACC-005` user creates a private tested skill without editing files
- `P23-ACC-006` revoked skill stops routing

### Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- One ontology and registry covers all tools, capabilities, skills, recipes, connectors, plugins and agents.
- Portable Agent Skills packages import and export with progressive disclosure.
- Signed sidecars add authority and evidence without breaking portability.
- Local models discover a bounded, relevant tool set within context budgets.
- Skills compile deterministically into durable, resumable task graphs.
- Multi-tool transactions do not duplicate unknown external effects.
- Users can create, test, install, inspect, update, revoke and share skills.
- Gold Skills cover core consumer outcomes.
- Broken, malicious, changed or revoked skills stop routing.
- No skill can grant itself authority.

## Cross-mission task interlocks

- `P23-001` waits for `P1-001` from `MISSION-001`.
- `P23-001` waits for `P19-005` from `MISSION-014`.
- `P23-003` waits for `P1-006` from `MISSION-001`.
- `P23-004` waits for `P11-002` from `MISSION-010`.
- `P23-004` waits for `P12-006` from `MISSION-011`.
- `P23-004` waits for `P21-004` from `MISSION-011`.
- `P23-005` waits for `P8-003` from `MISSION-002`.
- `P23-006` waits for `P21-007` from `MISSION-011`.
- `P23-007` waits for `P18-009` from `MISSION-006`.
- `P23-010` waits for `P6-011` from `MISSION-006`.
- `P23-010` waits for `P8-003` from `MISSION-002`.
- `P23-012` waits for `P19-010` from `MISSION-014`.
- `P23-012` waits for `P21-016` from `MISSION-011`.
- `P23-013` waits for `P8-003` from `MISSION-002`.
- `P23-014` waits for `P5-004` from `MISSION-005`.
- `P23-017` waits for `P5-007` from `MISSION-005`.
- `P23-018` waits for `P8-015` from `MISSION-002`.
- `P23-019` waits for `P12-014` from `MISSION-011`.
- `P23-019` waits for `P3-018` from `MISSION-003`.
- `P23-020` waits for `P13-014` from `MISSION-012`.
- `P23-020` waits for `P4-021` from `MISSION-004`.
- `P23-021` waits for `P14-014` from `MISSION-013`.
- `P23-021` waits for `P15-010` from `MISSION-010`.
- `P23-022` waits for `P19-008` from `MISSION-014`.
- `P7-001` waits for `P1-001` from `MISSION-001`.
- `P7-002` waits for `P1-005` from `MISSION-001`.
- `P7-003` waits for `P1-004` from `MISSION-001`.
- `P7-005` waits for `P1-005` from `MISSION-001`.
- `P7-006` waits for `P1-003` from `MISSION-001`.
- `P7-009` waits for `P1-006` from `MISSION-001`.

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
Take the repo. You are Worker G. Take MISSION-007 and continue autonomously.
```
