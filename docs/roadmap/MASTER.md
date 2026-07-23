# Kristin 4.x Top-Tier Consumer AI Operating System Master Roadmap

**Document type:** executable engineering constitution, roadmap, and AI implementation manual  
**Baseline reviewed:** Kristin Local Agent `v1.9.0+190`, `main` branch, July 23, 2026  
**Target:** top-tier, high-end consumer-ready, maximum-capability AI operating system for Windows, macOS, Linux, web, mobile companions, and headless/fleet nodes; with full-computer **Owner Mode**, native desktop control, interactive terminal, universal API connectivity, browser automation, central orchestration of OpenAI, Gemini, Claude, local and custom AI providers through API/browser/local transports, a portable Tool/Skill/Capability Operating System, complete application generation, modern content manufacturing, multimodal realtime chat, durable research/data, cloud deployment, signed releases, secure updates, zero-hassle onboarding, medium-machine support, and measurable consumer trust and agent quality  
**Primary implementers:** any capable implementation AI (including ChatGPT, Claude, or future agents) operating against the repository through bounded, evidence-producing work packets  
**Human role:** product owner, credential holder, release authority, and final approver for identity, signing, legal, payment, MFA, and production-promotion actions  
**Roadmap version:** `3.1.1-p0-003-integration-repair`  
**Supersedes:** roadmap versions `1.0.0`, `2.0.0`, `2.1.0`, and `3.0.0`; this file is the sole implementation authority until replaced by a signed ADR and a newer master manifest

> **Master authority:** commit this document as `docs/roadmap/MASTER.md`. Every previous roadmap must contain a `SUPERSEDED` pointer to this file. The generated `docs/roadmap/roadmap.yaml` manifest is the machine-readable dependency authority; this Markdown remains the human-readable product and engineering constitution. It defines architecture, task order, deliverables, tests, evidence, AI prompts, release gates, consumer requirements, Tool/Skill/Capability semantics, and operating rules.

## 0A. Non-negotiable superseding directives

The following decisions are fixed unless the human product owner changes this roadmap in a signed architecture decision record.

1. **Windows, macOS, and Linux are simultaneous mandatory desktop targets.** There is no strategy in which one is treated as the real product and the others are deferred ports.
2. **The system is built for capability parity, not source-code uniformity.** Shared contracts and tests are mandatory; platform-native implementations are expected.
3. **Final desktop GA is synchronized.** If one mandatory desktop platform fails an applicable gate, the desktop release does not become GA on the other two under the same product version.
4. **Full Owner Mode is mandatory on Windows, macOS, and Linux.** It must expose the maximum authority available to the current OS account, including an explicit native elevation path where the operating system permits it.
5. **Owner Mode does not mean raw secrets are copied into prompts.** The agent receives broad authority through a credential and identity broker. A local, interactive, break-glass secret-reveal operation may exist, but it must require owner reauthentication, never run unattended, never be logged, and never be the normal integration path.
6. **Universal capability is implemented through an extensible capability registry.** New APIs, applications, devices, models, content systems, cloud targets, and protocols must be addable without rewriting the coordinator.
7. **The product must generate complete applications, not only snippets.** It must plan, design, implement, test, run, inspect, package, deploy, monitor, repair, and document supported application types.
8. **Modern content manufacturing is a first-class plane.** Documents, PDFs, spreadsheets, presentations, images, vector graphics, audio, video, subtitles, web campaigns, social variants, and structured datasets must share an asset graph, provenance, brand controls, and reproducible render recipes.
9. **The chatbot is multimodal, realtime, and omnichannel.** Text, voice, image, screen, file, browser, terminal, and structured data must be usable within one durable run model.
10. **No simulated universality.** When an operating system forbids a capability, Kristin must expose the maximum OS-permitted alternative and an optional trusted remote-node path. It must never claim desktop-equivalent Owner Mode on iOS, browser sandboxes, or other platforms whose security model makes that impossible.
11. **Evidence remains mandatory even in unrestricted Owner Mode.** The owner may disable confirmations, but not durable event identity, kill, redaction, reconciliation, or final verification.
12. **P10 is a core integration checkpoint, not the final maximum-capability GA.** Final GA is governed by Phase P20 and the master gates in this document.
13. **Kristin is the central local AI manager.** OpenAI, Gemini, Claude, local models, and future providers are execution backends selected through typed provider, transport, model, account, privacy, budget, and fallback constraints.
14. **API, browser session, and local runtime are first-class but non-equivalent transports.** The user may force any supported route; explicit choices are never silently replaced.
15. **Browser-backed AI use is terms-aware and owner-selected.** It must not bypass quotas, safeguards, API billing rules, CAPTCHA, MFA, or provider restrictions, and it cannot be marketed as universally free.
16. **The central manager must remain practical on medium local machines.** Heavy reasoning and media tasks may be delegated externally or queued locally; no virtual machine is required for ordinary provider execution.
17. **Consumer productization is a release gate, not cosmetic polish.** Zero-hassle installation, first-run success, understandable recovery, support readiness, cost transparency, accessibility, localization, and real-user usability evidence are mandatory before GA.
18. **Tools, capabilities, skills, recipes, plugins, connectors, and agents have one canonical ontology.** No implementation may introduce a competing abstraction or bypass the central capability authority.
19. **Kristin supports the portable Agent Skills format.** A skill is progressively disclosed through metadata, `SKILL.md`, scripts, references, and assets; Kristin adds signed manifests, permissions, tests, evidence, and deterministic compilation without breaking portable skill import/export.
20. **The local-first core is migrating away from a SQL-specific authority behind a storage abstraction.** The current SQLite workflow authority remains the production source of truth until `P24-005` approves a measured no-SQL ADR and `P24-007` completes a restartable, verified, rollback-capable migration. New domain services must depend on the authority abstraction rather than SQL syntax. SQL databases remain supported as connectors and export formats; no big-bang storage replacement is permitted.
21. **Simple Mode is the default consumer experience.** One composer and intelligent defaults hide provider, transport, tool, capability, and skill complexity until the user explicitly asks for advanced control.
22. **Every product-capability phase from P2 onward must deliver a complete vertical product slice on Windows, macOS, and Linux.** P0 and P1 are foundation phases and instead require a reproducible, tri-platform verification slice with honest unsupported states. Horizontal infrastructure without a tested user or release outcome cannot satisfy a later phase gate.
23. **The roadmap itself is executable data.** `P0-008` must bootstrap `docs/roadmap/roadmap.yaml` plus dependency/cycle/status validation for the active foundation tasks; `P24` expands that bootstrap into the complete split manifest, traceability graph, documentation lint, and context-pack system. Task IDs, dependencies, evidence requirements, supersession, and release claims must never rely on prose alone.
24. **A skill or tool never grants itself authority.** Instructions may propose actions; only deterministic policy and a scoped grant can authorize them.

## 0B. Execution reconciliation amendment

This amendment resolves conflicts introduced while combining the original production roadmap, the omni-platform expansion, provider orchestration, consumer productization, the Tool/Skill/Capability OS, and the storage/roadmap amendments. It is normative for all AI work packets.

### 0B.1 Product target versus roadmap version

- **Kristin 4.x** is the target product line.
- **3.1.1-p0-003-integration-repair** is this roadmap document's schema/content version.
- **1.9.0+190** remains the reviewed implementation baseline until repository evidence proves a newer product release.

These identifiers serve different purposes and must not be substituted for one another in manifests, status files, or release claims.

### 0B.2 Normative phase execution order

Task dependencies, not numeric labels alone, determine execution. The intended critical path is:

```text
P0 foundation and containment
→ P1 trust and policy
→ P2–P19 product/platform/ecosystem implementation
→ P21 provider orchestration
→ P22 consumer productization
→ P23 Tool/Skill/Capability OS
→ P24 roadmap integrity and storage migration
→ P20 final capability freeze, beta, RC, and synchronized GA
```

P20 is numbered as the terminal release phase for historical continuity, but it executes only after P21–P24 and every dependency of `P20-001` are `DONE`.

### 0B.3 Transitional storage rule

The no-SQL local authority is a **final architecture target**, not permission to discard the current durable SQLite kernel early. Until P24 succeeds:

1. SQLite remains authoritative.
2. Existing crash, idempotency, migration, append-only, backup, and recovery tests remain blocking.
3. New code must use an authority abstraction where practical.
4. The migration must preserve IDs, ordering, hashes, receipts, and rollback.
5. A candidate no-SQL engine that cannot equal the existing durability evidence blocks the migration rather than weakening the product.

### 0B.4 Roadmap-as-data bootstrap

`P0-008` creates the minimum executable control plane needed for current AI sessions: status, task packets, a bootstrap YAML manifest, dependency/cycle checks, and evidence links for P0/P1. P24 performs the full document split, all-task manifest, claim traceability, acceptance lint, and bounded AI context packs. This removes the contradiction between declaring machine authority now and postponing all validation until P24.

### 0B.5 Current milestone order

The active branch must close milestones in this order:

```text
P0-001 strict complete-checkout baseline receipt
→ P0-002 v1 trust disablement applied and independently reviewed
→ P0-003 green and truthful three-OS CI
```

If P0-002 exists only in an unpushed local checkout, the remote branch has not completed it. P0-003 may be prepared locally, but it may not be marked `DONE` until the active integration branch contains P0-002 and all P0-003 evidence.

### 0B.6 P0-003 platform-test rule

P0-003 must not make a red build green by pretending an unavailable platform sandbox exists. Platform-dependent tests must do one of the following:

- execute the supported backend and verify behavior;
- verify a stable, honest `unsupported`/`blocked` result when the capability is outside the current phase claim; or
- use an explicitly named trusted-host diagnostic fixture when the test is validating environment plumbing rather than isolation.

A skip, exclusion, or softened assertion that hides a capability promised by the current phase remains a failure. Full Windows/macOS/Linux Owner Mode and hostile-workload isolation are delivered by P2/P11, not smuggled into P0.

### 0A.1 Meaning of “all platforms”

The implementation target is deliberately broad, but platform claims must be precise.

| Platform class | Required product form | Required authority model | Release obligation |
|---|---|---|---|
| Windows desktop | Native desktop workbench and native execution helper | Full Owner Mode to the current Windows account; optional UAC-approved elevated helper | Mandatory synchronized desktop GA |
| macOS desktop | Native desktop workbench and notarized native helpers | Full Owner Mode to the current macOS account; Accessibility, Screen Recording, Automation, and native elevation subject to macOS consent | Mandatory synchronized desktop GA |
| Linux desktop | Native desktop workbench and native helpers for major desktop stacks | Full Owner Mode to the current Linux account; optional polkit/sudo-approved elevation | Mandatory synchronized desktop GA |
| Windows/Linux/macOS headless node | Signed service/daemon with remote control plane | Scoped or full node Owner Mode | Required for fleet/private-cloud release |
| Web | Browser-based control, review, monitoring, and limited browser-local tools | Browser sandbox plus authenticated remote node delegation | Required companion surface; never misrepresented as full local Owner Mode |
| Android | Native companion, capture/share, notifications, local model options, device-permitted automation, remote-node control | Maximum Android-permitted authority; optional managed-device APIs | Required companion target after desktop parity foundation |
| iOS/iPadOS | Native companion, capture/share, notifications, local model options, Shortcuts/App Intents where available, remote-node control | Maximum Apple-permitted authority; no false full-host claim | Required companion target after desktop parity foundation |
| Server/container/VM | Headless worker, CI executor, research worker, model worker, browser worker | Capability-granted workload identity | Required deployment target |
| Future platforms | Adapter package | Platform-defined | Add through conformance suite without coordinator rewrite |

### 0A.2 Mandatory architecture rule

Every externally visible capability must have:

```text
canonical semantic contract
+ platform/provider capability declaration
+ deterministic policy decision
+ native/provider adapter
+ behavioral and negative tests
+ evidence receipt
+ compatibility status
```

A shared facade without a real native implementation is not parity. Three unrelated implementations without a shared contract are not one product.

---

## 0. Executive decision

Kristin should not merely become a desktop chatbot that can run commands. It should become an **evidence-governed computer operator and web workbench**:

```text
user goal
→ model-generated proposal
→ deterministic plan
→ configured access policy
→ terminal/browser/filesystem execution
→ observable evidence
→ independent verification
→ durable result, rollback, and audit
```

The product will support **full access to the computer** because the product owner explicitly accepts that operating model. Full access will be implemented as an explicit **Owner Mode** rather than as an accidental bypass hidden inside ordinary project tools.

Owner Mode may be configured to permit:

- access to any local file or directory available to the current OS account;
- absolute paths and arbitrary working directories;
- interactive terminal sessions and ordinary shell commands;
- installation and removal of packages, SDKs, applications, and services;
- process, service, environment, clipboard, screenshot, and application control;
- unrestricted outbound web access;
- browser login sessions, form completion, downloads, uploads, and web workflows;
- local HTML, CSS, JavaScript, Node, Python, Flutter, and other development workflows;
- persistent or unattended execution when the owner explicitly enables it;
- an approval policy of `always`, `high_risk_only`, or `never`.

Owner Mode is **not** described as a sandbox. If Kristin runs under an administrator or root account, its effects carry those privileges. The implementation must preserve a visible kill switch, process-tree termination, immutable audit records, best-effort snapshots, secret redaction, and crash recovery even when approvals are disabled. Those controls are operational reliability, not restrictions on the owner’s chosen authority.

The production product will still ship with safer profiles so other users are not forced into the same risk posture.

---

# 1. How to use this roadmap

## 1.1 One work packet per AI session

ChatGPT or Claude must execute one atomic roadmap item, or one explicitly defined bundle, per session. The implementing AI must not silently start the next item.

Every session follows this sequence:

1. Read this roadmap, `docs/roadmap/STATUS.md`, the relevant architecture decision records, and the files named by the task.
2. Inspect the current repository state before proposing edits.
3. State the exact task ID and acceptance criteria.
4. Create a small implementation plan.
5. Modify the minimum necessary files.
6. Add or update behavioral tests.
7. Run the targeted tests.
8. Run the repository’s required verification tier.
9. Record evidence under `release/evidence/<task-id>/`.
10. Update `docs/roadmap/STATUS.md`.
11. Produce a concise handoff containing changed files, commands, results, risks, and the next unblocked task.

## 1.2 Required roadmap control files

Create these during Phase 0:

```text
docs/
  roadmap/
    STATUS.md
    DECISIONS.md
    RISKS.md
    METRICS.md
    RELEASE_GATES.md
    HANDOFF.md
    prompts/
      implement.md
      review.md
      security-review.md
      release-review.md
      failure-recovery.md
  adr/
    ADR-0001-runtime-boundaries.md
    ADR-0002-owner-mode.md
    ADR-0003-signed-manifest-v2.md
    ADR-0004-automation-host.md
    ADR-0005-browser-storage.md
    ADR-0006-update-system.md
tasks/
  active/
  completed/
  blocked/
release/
  evidence/
  attestations/
  reports/
evals/
  fixtures/
  datasets/
  results/
```

`STATUS.md` is the authoritative execution ledger. GitHub issues or project boards may mirror it, but they must not become a second conflicting source of truth.

## 1.3 Status values

Use exactly:

```text
NOT_STARTED
READY
IN_PROGRESS
BLOCKED
REVIEW
DONE
DEFERRED
```

A task is `DONE` only when its listed tests and evidence exist. Source tokens, class names, screenshots, or an AI statement that the work is complete are not sufficient by themselves.

## 1.4 Definition of ready

A task is ready when:

- all dependencies are `DONE`;
- the relevant schema or ADR is approved;
- required tools are installed or a fixture substitutes for them;
- a deterministic test strategy is known;
- no unresolved architecture decision is hidden inside the implementation task.

## 1.5 Definition of done

Every code task must satisfy all applicable conditions:

- implementation compiles;
- new behavior has direct tests;
- negative behavior has tests;
- error paths have stable machine-readable codes;
- no generated artifacts are unintentionally committed;
- logs and diagnostics do not expose credentials;
- documentation matches the behavior;
- the task-specific evidence manifest records commit, commands, outputs, and hashes;
- a separate review pass has no unresolved critical or high finding;
- the task does not broaden another capability by accident.

---

# 2. Baseline: retain, repair, replace

## 2.1 Foundations to retain

The current source already contains valuable foundations:

- typed model decisions and tool contracts;
- schema generation and provider-envelope compatibility tests;
- a SQLite workflow authority with append-only events, WAL/FULL synchronization, idempotency, checkpoints, leases, compensation, backup, and crash tests;
- project-path normalization and generated-state filtering;
- a Linux namespace worker and broker concepts;
- Prompt Studio, task plans, acceptance criteria, and a compiler boundary;
- Project Manager, managed processes, diagnostics, and evidence;
- knowledge, memory admission, content-addressed storage, and citation concepts;
- release validation, SBOM generation, secret scanning, and deterministic packaging intent;
- MCP/A2A, audit, policy, and update concepts that can be migrated to a corrected protocol.

These components should be evolved, not discarded.

## 2.2 Immediate defects and contradictions to repair

The production program begins with the following blockers:

1. One v1.9 helper uses the same HMAC secret as “public” and “private” material, puts the secret into the untrusted envelope, and then verifies with that envelope-supplied value. It cannot establish signer identity.
2. Python, Dart, and schema layers do not expose one canonical signed-manifest format or one cryptographic model.
3. The visible CI workflow uses moving toolchain channels and must be made fully green before it can serve as release evidence.
4. The security policy identifies an older supported release and contradicts the newer source regarding sandbox and broker implementation.
5. A large portion of validation checks for source text rather than externally observable behavior.
6. Repository provenance starts from a large replacement commit and has no published signed release.
7. The A2A bridge launches an executable selected through environment JSON and only becomes isolated when a trusted outer worker already provides isolation.
8. The secret scanner is useful but limited to a fixed set of regular expressions, file extensions, and the current source tree.
9. Cross-platform OS isolation, native signing, notarization, authenticated update installation, and production operations are incomplete.
10. Browser automation, an interactive terminal, web extraction, dataset management, and the requested unified Web Studio are not yet first-class production subsystems.

## 2.3 Replace security theater with explicit modes

Do not preserve a project-only restriction and quietly add exceptions until it becomes meaningless. Define distinct policies and display the active policy in the UI.

| Mode | Filesystem | Terminal | Network | Browser | Approvals | Intended use |
|---|---|---|---|---|---|---|
| `chat` | none | none | model-provider only | none | none | conversation |
| `project` | registered project roots | governed finite commands | brokered | project/research profile | required by risk | normal coding |
| `owner` | all user-accessible paths | full interactive shell | unrestricted or configured | full browser | configurable | owner-controlled workstation |
| `owner_unattended` | all user-accessible paths | full | unrestricted or configured | full | may be `never` | scheduled/long-running automation |
| `isolated_untrusted` | disposable workspace | sandbox worker | brokered deny-by-default | disposable profile | policy driven | hostile repositories or content |

`owner` and `isolated_untrusted` solve different problems. Neither is a fallback for the other.

---

# 3. Product north star and measurable outcomes

## 3.1 User outcome

A user can ask Kristin to:

- understand or change any local project;
- inspect, create, edit, move, and organize files anywhere permitted by the active profile;
- open a real terminal and interact with long-running programs;
- install dependencies and SDKs;
- build and preview HTML/CSS/JavaScript applications;
- open a browser, observe the DOM and accessibility tree, click, type, select, upload, download, and complete multi-step web workflows;
- research current information across multiple search providers;
- fetch static or JavaScript-rendered pages;
- extract readable text, metadata, links, tables, lists, JSON-LD, code, and files;
- preserve raw evidence, citations, screenshots, DOM snapshots, and content hashes;
- turn research into versioned datasets and export JSONL, CSV, Markdown, SQLite, and optional Parquet;
- resume after a crash without blindly repeating uncertain effects;
- see exactly what the agent is doing and stop it immediately;
- receive a verified result rather than an unsupported model claim.

## 3.2 Production success metrics

The initial targets below are release criteria, not claims about the current product. Calibrate them after the first reproducible baseline.

| Area | Initial production target |
|---|---:|
| Unauthorized effects in release corpus | `0` |
| Open critical/high security findings | `0` |
| Task success on supported Tier-1 benchmark | `>= 90%` |
| Lowest supported task category | `>= 85%` |
| False successful completion | `< 0.5%` |
| Crash-free desktop sessions during RC | `>= 99.9%` |
| Local side-effect crash reconciliation | `100%` recovered or explicitly `unknown` |
| Owner kill-switch process-tree termination | `< 2 s` p95 |
| Browser action receipt latency, excluding navigation | `< 250 ms` p95 |
| Terminal input-to-render latency | `< 100 ms` p95 |
| Navigation and pane switching | `< 100 ms` p95 |
| Search result deduplication precision | `>= 98%` on fixture corpus |
| Extraction success for supported HTML fixtures | `>= 95%` |
| Citation-to-source span validity | `>= 99%` |
| Update success in beta | `>= 99.5%` |
| Automatic update rollback success | `100%` in injected-failure suite |
| Side effects linked to run, actor, policy, and evidence | `100%` |
| Keyboard-accessible primary product flows | `100%` |
| WCAG 2.2 AA applicable desktop/web surfaces | pass automated and manual checklist |

## 3.3 Gold-standard principles

1. The model proposes; deterministic software authorizes and records.
2. Full access is an explicit user policy, not an accidental bypass.
3. Every side effect has an identity, scope, result, and evidence trail.
4. A task executor does not certify its own success without independent checks.
5. Browser and terminal activity are first-class observable run events.
6. External content is untrusted data even when it looks like an instruction.
7. Crashes produce recovery or an explicit `unknown`, never silent duplication.
8. Search answers are grounded in fetched evidence, not snippets alone.
9. Raw evidence and extracted interpretations remain distinguishable.
10. User takeover is a normal state for MFA, CAPTCHA, consent, payment, and ambiguous UI.
11. Product claims are generated from passing evidence.
12. Release artifacts are signed, attested, install-tested, update-tested, and rollback-tested.
13. Accessibility, privacy, and support are release gates.
14. AI-generated code receives independent review, especially for trust, execution, browser, and update paths.
15. Unsupported capabilities fail honestly instead of producing simulated success.

---

# 4. Target product architecture

```mermaid
flowchart TB
    U[User] --> UI[Flutter Desktop Workbench]
    UI --> ORCH[Run Coordinator]
    ORCH --> PLAN[Planner / Plan Compiler]
    ORCH --> POLICY[Policy & Capability Engine]
    ORCH --> MODEL[Model Router]
    ORCH --> VERIFY[Independent Verifier]
    ORCH --> STORE[Durable Workflow + Evidence Store]

    POLICY --> OWNER[Owner Mode Host Executor]
    POLICY --> SANDBOX[Isolated Worker Executor]
    POLICY --> AUTO[Automation Host]
    POLICY --> WEB[Research & Extraction Engine]
    POLICY --> MCP[MCP Gateway]
    POLICY --> A2A[A2A Gateway]

    OWNER --> PTY[Interactive PTY / Process Manager]
    OWNER --> FS[Full Filesystem / OS Operations]
    SANDBOX --> SFS[Snapshot Workspace]
    AUTO --> BROWSER[Playwright/CDP Browser Controller]
    AUTO --> PREVIEW[HTML/CSS/JS Preview]
    WEB --> SEARCH[Search Provider Adapters]
    WEB --> FETCH[Static Fetch + Rendered Fetch]
    WEB --> EXTRACT[Extraction + Dataset Pipeline]

    BROWSER --> EVIDENCE[DOM / A11y / Screenshots / Network]
    PTY --> EVIDENCE
    FS --> EVIDENCE
    EXTRACT --> EVIDENCE
    EVIDENCE --> STORE
    STORE --> VERIFY
    VERIFY --> UI

    RELEASE[Release & Update System] --> UI
    RELEASE --> TUF[TUF Metadata + Signed Artifacts]
```

## 4.1 Runtime process model

Use process separation for failure containment and packaging clarity:

```text
Kristin Desktop (Flutter/Dart)
  ├─ durable database and policy decisions
  ├─ model routing and UI
  ├─ local authenticated IPC client
  ├─ Owner Executor
  │    ├─ full filesystem operations
  │    ├─ finite process execution
  │    └─ privileged-operation coordinator
  ├─ Automation Host
  │    ├─ interactive PTY
  │    ├─ Playwright browser control
  │    ├─ local web preview
  │    └─ DOM/network/console capture
  ├─ Research Worker
  │    ├─ search adapters
  │    ├─ safe HTTP fetch
  │    ├─ HTML extraction
  │    └─ dataset transforms
  └─ Isolated Worker
       ├─ disposable workspace
       ├─ restricted process execution
       └─ brokered network and secrets
```

A Phase 2 architecture spike decides whether PTY and browser capabilities share one TypeScript automation host or use separate native/Rust and Playwright workers. The decision must be based on packaging, startup, memory, native dependency, and cross-platform tests rather than preference.

## 4.2 Security boundaries

- Flutter UI is not a security boundary.
- Model output is not a security boundary.
- A tool schema validates shape but does not grant authority.
- Owner Mode authority comes from a persisted owner policy and the current OS account.
- Isolated mode authority comes from a scoped capability grant enforced by the worker.
- Browser contexts isolate cookies and storage between profiles, but a browser process is not equivalent to an OS sandbox.
- Web content, terminal output, source files, MCP tool descriptions, and A2A messages are all untrusted input.
- Release trust roots are external to the object being verified.
- Local IPC authenticates peers and rejects arbitrary local callers.
- Secrets are resolved at use time and are never copied into model prompts by default.

## 4.3 Canonical domain services

Create or evolve these service boundaries:

```text
AccessProfileService
CapabilityGrantService
PolicyDecisionService
OwnerExecutionService
SandboxExecutionService
TerminalSessionService
BrowserSessionService
BrowserActionService
WebPreviewService
SearchService
WebFetchService
ContentExtractionService
DatasetService
EvidenceService
VerificationService
ModelRouterService
MemoryAdmissionService
McpGatewayService
A2aGatewayService
AuditCheckpointService
UpdateService
ReleaseEvidenceService
TelemetryService
```

Each service has a versioned input/output contract and stable error codes.

---

# 5. Full-computer Owner Mode specification

## 5.1 Owner Mode policy object

Create `schemas/access_profile.v2.json` and support a profile similar to:

```json
{
  "schemaVersion": "2.0.0",
  "id": "owner-primary-machine",
  "mode": "owner",
  "filesystem": {
    "scope": "all",
    "allowNetworkShares": true,
    "allowRemovableMedia": true,
    "allowHiddenFiles": true
  },
  "terminal": {
    "enabled": true,
    "interactive": true,
    "allowedExecutables": ["*"],
    "allowedWorkingDirectories": ["*"],
    "environmentPolicy": "inherit_and_override",
    "approvalPolicy": "never"
  },
  "os": {
    "manageProcesses": true,
    "manageServices": true,
    "installPackages": true,
    "installApplications": true,
    "clipboard": true,
    "screenshots": true,
    "openApplications": true,
    "requestElevation": true
  },
  "network": {
    "policy": "unrestricted",
    "allowUploads": true,
    "allowDownloads": true
  },
  "browser": {
    "enabled": true,
    "persistentProfiles": true,
    "allowAuthentication": true,
    "allowUploads": true,
    "allowDownloads": true,
    "approvalPolicy": "never"
  },
  "dataBoundary": "unrestricted",
  "recovery": {
    "bestEffortSnapshots": true,
    "auditAllEffects": true,
    "killSwitch": true
  }
}
```

## 5.2 Owner Mode invariants

Even with approval policy `never`:

- every command records executable, argument vector, working directory, environment-key names, timestamps, exit state, and bounded/redacted output;
- every process has a stable session ID and complete-tree termination strategy;
- every browser action records page, target description, selector strategy, before/after observation hashes, and result;
- every file mutation records before/after hashes when feasible;
- best-effort snapshot or backup runs before destructive multi-file work;
- the user can globally pause model calls, tool dispatch, terminal input, and browser actions;
- the user can kill the entire worker tree from UI and OS tray;
- secrets are redacted in logs;
- MFA, CAPTCHA, biometric, legal acceptance, and payment confirmation transition to `user_takeover_required`;
- web page text cannot change the access profile;
- an agent cannot make Owner Mode persistent without the owner’s explicit settings action;
- privilege elevation uses OS-native consent and never stores the elevation credential.

## 5.3 Destructive action policy

Owner Mode permits destructive actions. Reliability protections remain:

```text
single-file replace/delete
→ hash current state
→ record mutation intent
→ perform effect
→ verify result

multi-file or system change
→ create checkpoint
→ snapshot or backup where feasible
→ record effect plan
→ execute
→ verify
→ retain rollback metadata

non-reversible external effect
→ record idempotency/reconciliation method
→ execute once
→ query outcome
→ mark committed or unknown
```

The user may disable confirmations, but not the event journal.

## 5.4 Unattended mode

`owner_unattended` adds:

- schedules and triggers;
- idle/AC-power/network conditions;
- maximum wall-clock time;
- cost and model-request ceilings;
- allowed browser profiles;
- allowed destinations;
- failure notification;
- automatic pause on repeated uncertainty;
- no automatic CAPTCHA or MFA bypass;
- no automatic retry of unknown external effects;
- resumable durable task handles.

---

# 6. Terminal and OS execution specification

## 6.1 Required terminal capabilities

The terminal subsystem must support:

- multiple named tabs;
- real pseudo-terminal behavior;
- PowerShell, CMD, Bash, Zsh, Fish, and custom shells;
- interactive prompts and full-duplex input;
- terminal resize;
- ANSI color and cursor control;
- streamed stdout/stderr;
- copy, search, save, clear, and export;
- interrupt, EOF, terminate, and force-kill;
- process-tree tracking;
- working-directory and environment display;
- command history scoped by profile and project;
- upload/download path handoff;
- background processes with durable handles;
- reconnect after UI restart when the worker remains alive;
- bounded log persistence;
- secret masking;
- exit-code and signal reporting;
- terminal recordings linked to runs.

## 6.2 Terminal tool contracts

Add versioned schemas for:

```text
terminal.open
terminal.write
terminal.resize
terminal.interrupt
terminal.read
terminal.snapshot
terminal.close
terminal.kill
terminal.list
terminal.attach
process.list
process.signal
service.status
service.start
service.stop
package.install
package.remove
application.open
clipboard.read
clipboard.write
screen.capture
```

Never represent shell commands as one unparsed string when an argument vector is available. Interactive shell text is allowed in Owner Mode, but the journal must distinguish shell text from direct process execution.

## 6.3 Terminal verification

For finite commands, success requires an exit code and task-specific validation. For long-running commands, success requires a readiness probe, process identity, and a stop strategy.

Examples:

```text
npm test
→ exit code 0
→ test report parsed
→ expected test count verified

npm run dev
→ process handle stored
→ readiness URL returns expected response
→ console checked for fatal errors
→ stop terminates complete tree
```

## 6.4 Privileged operations

Implement a `PrivilegedOperationRequest` with:

- human-readable reason;
- exact command or operation;
- requested platform privilege;
- affected paths/services;
- rollback plan;
- expected duration category;
- OS-native elevation result;
- no plaintext credential capture.

The product may request elevation, but it must not simulate success when the OS denies it.

---

# 7. Browser automation and Web Studio specification

## 7.1 Browser operating model

Use Playwright as the primary cross-browser automation layer. Chromium, Firefox, and WebKit are mandatory automation targets in the production test matrix. An embedded product surface may use a platform-specific engine, but external automation and generated-application verification must remain cross-browser. Use browser contexts for isolated sessions and support persistent profiles only when explicitly configured.

The agent observation order is:

```text
URL and page state
→ DOM snapshot
→ accessibility tree
→ visible text and forms
→ console and network errors
→ screenshot
→ optional visual reasoning
```

The action order is:

```text
role/label/test-id locator
→ stable CSS locator
→ text locator
→ XPath only when necessary
→ coordinate/visual fallback as last resort
```

After every mutating browser action, the agent must observe a meaningful postcondition.

## 7.2 Browser tool contracts

Create schemas for:

```text
browser.session.create
browser.session.list
browser.session.close
browser.page.open
browser.page.list
browser.page.focus
browser.observe
browser.click
browser.type
browser.fill
browser.select
browser.check
browser.press
browser.scroll
browser.hover
browser.drag
browser.upload
browser.download
browser.wait
browser.evaluate
browser.screenshot
browser.pdf
browser.extract
browser.network.get
browser.console.get
browser.takeover.request
browser.takeover.complete
browser.trace.start
browser.trace.stop
```

`browser.evaluate` is Owner Mode or explicitly approved only. It must identify whether JavaScript runs in page context, worker context, or the automation host.

## 7.3 Session profiles

Support:

- ephemeral research context;
- ephemeral test context;
- persistent personal context;
- persistent work context;
- project-specific context;
- disposable hostile-content context.

Cookies, local storage, indexed DB, cache, and downloads remain scoped to the selected profile. Profile data must not silently enter model context.

## 7.4 Human takeover

Use a first-class state, not an exception:

```text
AUTOMATING
WAITING_FOR_PAGE
USER_TAKEOVER_REQUIRED
USER_CONTROLLING
RESUMING
VERIFICATION
COMPLETE
```

Trigger takeover for:

- CAPTCHA;
- MFA or passkey ceremony;
- biometric confirmation;
- payment approval;
- legal acceptance;
- ambiguous destructive action;
- inaccessible or unstable UI;
- site request to confirm the user is present.

The user sees the live page, completes the step, and returns control. The agent then re-observes the page instead of assuming success.

## 7.5 Browser evidence

Persist:

- start and final URL;
- navigation chain;
- DOM or accessibility snapshot hashes;
- action list;
- selectors and target descriptions;
- screenshots at important checkpoints;
- network request summaries;
- console errors;
- downloads and hashes;
- uploads by path hash, not content in logs;
- page title and canonical URL;
- visible result text;
- verification condition;
- trace archive for failed runs.

## 7.6 Web Studio

The Web Studio is a dedicated workspace for building and testing web projects.

Required panels:

```text
Files / project tree
Code editor
Live preview
Browser toolbar
DOM/accessibility inspector
Console
Network
Terminal
Agent activity
Tests and audit
```

Required features:

- HTML, CSS, JavaScript, TypeScript, JSON, Markdown, and common framework syntax;
- syntax highlighting, search, replace, and diagnostics;
- local static preview;
- configurable development server;
- hot reload;
- device viewport presets;
- responsive ruler;
- console and network capture;
- DOM selection that reveals source when source maps are available;
- screenshot and visual diff;
- accessibility scan;
- link and form checks;
- test generation and execution;
- export/package;
- open in external browser;
- agent edit preview and diff before commit in project mode;
- automatic write in Owner Mode when configured.

## 7.7 Local web fixture application

Build a deterministic local fixture site with:

- static HTML pages;
- client-rendered JavaScript page;
- forms and validation;
- login fixture;
- cookies and local storage;
- upload and download;
- pagination and infinite scroll;
- tables;
- JSON-LD;
- redirects;
- console errors;
- delayed network calls;
- popups;
- iframe;
- accessibility labels and missing labels;
- intentionally unstable selectors;
- prompt-injection text;
- CAPTCHA placeholder that always requests takeover.

Browser CI must use this fixture rather than external websites.

---

# 8. Web search, extraction, and saving specification

## 8.1 Search architecture

```mermaid
flowchart LR
    Q[User question] --> P[Query planner]
    P --> A1[Search adapter A]
    P --> A2[Search adapter B]
    P --> A3[Domain-specific adapter]
    A1 --> N[Normalizer]
    A2 --> N
    A3 --> N
    N --> D[Deduplication]
    D --> R[Ranking and source policy]
    R --> F[Fetch selected sources]
    F --> X[Extract and classify]
    X --> C[Citations and provenance]
    C --> S[Content-addressed storage]
    S --> I[FTS / optional embeddings]
    I --> ANSWER[Grounded answer or dataset]
```

## 8.2 Search provider abstraction

Define one provider-neutral contract:

```json
{
  "query": "current official documentation",
  "limit": 10,
  "language": "en",
  "country": "US",
  "freshness": {
    "mode": "after",
    "date": "2026-01-01"
  },
  "domains": {
    "include": ["example.org"],
    "exclude": []
  },
  "safeSearch": "moderate"
}
```

Every result normalizes:

```text
provider
rank
title
url
displayUrl
snippet
publishedAt
providerMetadata
queryId
retrievedAt
```

Do not treat snippets as evidence. A source must be fetched or rendered before its claims can support an answer.

## 8.3 Query planning

The query planner should:

- identify entities, dates, locations, and requested output;
- determine whether freshness matters;
- create precision and recall queries;
- create official-domain queries for technical or policy facts;
- apply language and region;
- add date bounds;
- use follow-up queries for missing aspects;
- stop when evidence coverage meets acceptance criteria;
- record all queries and result sets;
- avoid unbounded recursive browsing.

## 8.4 Ranking

Combine:

- lexical relevance;
- semantic relevance;
- source type;
- official/primary-source preference;
- publication date and event date;
- domain trust policy;
- duplicate/near-duplicate penalty;
- extraction quality;
- citation coverage;
- project/user pinning;
- previous source reliability;
- task-specific diversity.

Do not collapse disagreement. Keep source-level claims and surface conflicts.

## 8.5 Fetch pipeline

Static fetch must enforce:

- HTTP/HTTPS allowlist by profile;
- URL credential rejection;
- DNS and connection-time address validation in restricted modes;
- redirect revalidation;
- response size and time limits;
- MIME detection;
- decompression limits;
- content hash;
- cache policy;
- TLS error reporting;
- robots policy for crawler workflows;
- per-host rate limits;
- retry taxonomy;
- download quarantine;
- redaction.

Rendered fetch uses a disposable browser context unless a persistent authenticated profile is explicitly selected.

## 8.6 Extraction pipeline

Extract:

- title;
- canonical URL;
- author;
- publication and modification dates;
- language;
- main readable text;
- headings;
- lists;
- code blocks;
- tables;
- links;
- images and alt text;
- Open Graph;
- JSON-LD;
- microdata when practical;
- document type;
- page description;
- source-specific identifiers;
- pagination links;
- downloadable assets;
- visible warnings or paywall state.

Preserve both raw and normalized forms:

```text
raw response bytes
raw HTML
rendered HTML
DOM snapshot
screenshot
readable Markdown
plain text
structured JSON
tables
metadata
extraction diagnostics
```

## 8.7 Citation model

A citation record contains:

```json
{
  "sourceId": "src_...",
  "fetchId": "fetch_...",
  "documentHash": "sha256:...",
  "canonicalUrl": "https://...",
  "retrievedAt": "2026-07-23T00:00:00Z",
  "locator": {
    "kind": "text_span",
    "start": 1024,
    "end": 1180,
    "quoteHash": "sha256:..."
  },
  "claimIds": ["claim_..."]
}
```

A source update never mutates the old citation target. It creates a new fetch and document version.

## 8.8 Data storage layout

```text
data/
  authority-store/
  browser/
    profiles/
    traces/
    downloads/
  research/
    objects/
      sha256/
        ab/
          cd...
    fetches/
    extractions/
    screenshots/
  datasets/
    <dataset-id>/
      manifest.json
      data.jsonl
      data.csv
      data.parquet
      provenance.jsonl
  exports/
  cache/
```

The generated-state policy must exclude runtime browser profiles, caches, downloads, traces, Node/Playwright caches, and dataset build intermediates from source packages.

## 8.9 Embedded authority entities

Add migrations for:

```text
browser_sessions
browser_pages
browser_actions
browser_observations
browser_downloads
search_queries
search_results
web_sources
web_fetches
web_documents
web_extractions
web_citations
datasets
dataset_versions
dataset_items
crawl_jobs
crawl_frontier
change_monitors
```

Use a replaceable local lexical index over the embedded object/document authority. Optional embeddings must be replaceable and must not become the sole retrieval index.

## 8.10 Dataset builder

The user can:

- select sources or extracted rows;
- define fields;
- normalize types;
- deduplicate;
- filter;
- sort;
- join;
- annotate;
- run validation;
- preview;
- version;
- export;
- reproduce the transformation from a saved recipe.

Every dataset version records input source hashes and transformation steps.

## 8.11 Crawl policy

Crawling is different from interactive browser automation.

Crawl mode must have:

- explicit scope;
- maximum pages, depth, bytes, and time;
- robots.txt handling;
- per-host delay and concurrency;
- allowed content types;
- canonical URL normalization;
- duplicate detection;
- sitemap support;
- pagination strategy;
- stop conditions;
- error budget;
- resumption checkpoint;
- source ownership/terms notes;
- no CAPTCHA bypass.

---

# 9. UX and UI production specification

## 9.1 Information architecture

Primary navigation:

```text
Home / New Task
Chats
Projects
Runs
Browser
Terminal
Web Studio
Research
Data
Memory
Automations
Settings
```

Contextual secondary navigation appears inside each workspace. Avoid hiding core execution surfaces inside an “advanced” submenu once browser and terminal become primary capabilities.

## 9.2 Desktop layout

Use a flexible three-pane workbench:

```text
left rail / project & navigation
center workspace / chat, editor, browser, terminal, data
right inspector / plan, context, evidence, permissions, properties
bottom activity drawer / terminal, logs, console, network, problems
```

Suggested default geometry:

- left rail: 56 px collapsed, 240–280 px expanded;
- right inspector: 360–480 px;
- bottom drawer: 200–500 px resizable;
- central workspace: minimum 640 px;
- panes remember layout per workspace.

## 9.3 Global autonomy status

Always show:

- active access profile;
- whether Owner Mode is enabled;
- current model and data boundary;
- active process count;
- active browser session count;
- pending user takeover;
- network activity;
- pause;
- stop;
- emergency kill.

Owner Mode uses a persistent visual treatment that cannot be confused with project mode.

## 9.4 Chat and task composer

The composer supports:

- ordinary message;
- attach file/folder;
- choose project;
- choose browser profile;
- choose access profile;
- choose model policy;
- task templates;
- schedule;
- acceptance criteria;
- expected output;
- maximum budget;
- “plan only”;
- “run now”;
- “run unattended”;
- slash commands and command palette.

Before execution, show a compact generated plan with:

- goals;
- files and paths;
- commands;
- websites;
- accounts/profile;
- expected side effects;
- verification;
- estimated risk category;
- stop conditions.

## 9.5 Run timeline

Use one unified timeline for:

- model requests;
- policy decisions;
- tool calls;
- terminal sessions;
- browser actions;
- web searches;
- fetches;
- file mutations;
- evidence;
- verification;
- user takeovers;
- retries;
- rollback;
- final receipt.

Allow filtering by type without losing chronological order.

## 9.6 Browser workspace

Required controls:

- back, forward, reload, stop;
- URL bar;
- profile selector;
- tab strip;
- agent-control/user-control toggle;
- observe;
- screenshot;
- extract;
- save to research;
- download manager;
- console/network indicators;
- show action target;
- replay trace;
- takeover banner.

## 9.7 Terminal workspace

Required controls:

- new tab;
- shell selector;
- working directory;
- environment profile;
- search;
- copy all;
- save transcript;
- interrupt;
- terminate;
- force kill;
- attach to process;
- pin to run;
- open path in project/browser.

## 9.8 Research workspace

Views:

- search;
- results;
- source reader;
- extraction;
- citations;
- crawl jobs;
- saved collections;
- source changes;
- research graph;
- export.

Each source card shows provider, canonical URL, retrieval date, extraction quality, content hash, freshness, trust label, and citation count.

## 9.9 Data workspace

Views:

- dataset list;
- schema;
- table;
- transformation recipe;
- quality report;
- source provenance;
- version diff;
- export.

Large tables require virtualization and incremental loading.

## 9.10 Design system

Create semantic tokens for:

- background/surface layers;
- text hierarchy;
- borders;
- focus;
- success/warning/error/info;
- Owner Mode;
- running/paused/waiting/unknown;
- code/terminal syntax;
- charts.

Use an 8-point spacing system, a consistent typography scale, clear focus rings, reduced-motion support, high-contrast support, and keyboard-first interactions.

## 9.11 Accessibility

Target WCAG 2.2 AA where applicable and use the W3C guidance for non-web software.

Required checks:

- full keyboard navigation;
- logical focus order;
- visible focus;
- labels and descriptions;
- screen-reader semantics;
- no color-only meaning;
- scalable text;
- high contrast;
- reduced motion;
- sufficient target sizes;
- accessible dialogs;
- accessible data tables;
- terminal screen-reader mode;
- browser takeover announcements;
- live-region throttling for streaming output.

## 9.12 UX testing

Use:

- Flutter widget tests;
- golden screenshot tests;
- keyboard traversal tests;
- semantic tree tests;
- local scripted usability scenarios;
- performance profiling;
- accessibility checklist;
- at least one human review before RC.

---

# 10. AI delivery operating system

## 10.1 Roles

For security-critical work, use two independent model roles.

| Role | Responsibility |
|---|---|
| `Architect` | ADR, interfaces, invariants, migration plan |
| `Implementer` | code, tests, docs, evidence |
| `Reviewer` | diff review, architecture drift, regressions |
| `Security Reviewer` | adversarial analysis and negative tests |
| `Release Auditor` | verifies gates and artifact provenance |
| `Failure Analyst` | minimizes a failing case and records replay fixture |

The same AI conversation must not approve its own security-critical work. Use a fresh ChatGPT/Claude session, or the other model, with only the diff, requirements, and test evidence.

## 10.2 AI task packet template

Create each task file from:

````markdown
# <TASK-ID> — <Title>

## Status
READY

## Objective
One observable outcome.

## Dependencies
- <TASK-ID>

## In scope
- ...

## Out of scope
- ...

## Files to inspect first
- ...

## Required implementation
1. ...

## Required tests
1. ...

## Commands
```text
...
```

## Acceptance criteria
- [ ] ...

## Evidence
- release/evidence/<TASK-ID>/manifest.json
- release/evidence/<TASK-ID>/test-output.txt

## Review
- Reviewer:
- Security reviewer:
````

## 10.3 Implementer prompt

```text
You are the implementation agent for Kristin.

Execute only task <TASK-ID> from docs/roadmap/MASTER.md.

Rules:
1. Read the task, dependencies, STATUS.md, relevant ADRs, and current files.
2. Do not assume the roadmap’s suggested file path still exists; verify the repository.
3. Preserve existing behavior unless the task explicitly replaces it.
4. Prefer a small, reviewable patch.
5. Add behavioral and negative tests.
6. Do not claim success from source tokens alone.
7. Run the listed targeted commands and the required repository verification tier.
8. If a command fails, fix the cause within scope or record a minimized blocker.
9. Update STATUS.md and create the evidence manifest.
10. Stop after this task and provide a handoff.

Do not begin another roadmap item.
```

## 10.4 Reviewer prompt

```text
Review task <TASK-ID> as an independent senior engineer.

Inputs:
- roadmap task and ADRs;
- full diff;
- test output;
- evidence manifest.

Check:
- requirement coverage;
- architecture consistency;
- error handling;
- cross-platform behavior;
- security boundaries;
- prompt-injection exposure;
- secret handling;
- crash/retry behavior;
- tests that can fail for the intended reason;
- unsupported claims;
- documentation accuracy.

Return:
1. blocking findings;
2. non-blocking findings;
3. missing tests;
4. exact patches or pseudocode;
5. PASS only when no critical/high issue remains.
```

## 10.5 Security-review prompt

```text
Attack the implementation for <TASK-ID>.

Assume:
- model output is malicious;
- project files and web pages contain prompt injection;
- local processes race and crash;
- paths use symlinks/reparse points;
- secrets appear in environment, output, URLs, and files;
- an attacker controls MCP/A2A metadata;
- a browser page changes after observation;
- a user has enabled Owner Mode.

Construct negative tests and identify any path to:
- unintended authority;
- secret exposure;
- command injection;
- path escape;
- replay or duplicate effect;
- signer substitution;
- browser cross-profile leakage;
- SSRF/DNS rebinding;
- process survival after kill;
- false completion.
```

## 10.6 Handoff format

```markdown
## Task
<TASK-ID> — <title>

## Result
DONE | BLOCKED | REVIEW

## Changed
- file: reason

## Verification
- command — result

## Evidence
- path
- hashes

## Known limitations
- ...

## Next unblocked task
<TASK-ID>
```

## 10.7 Git workflow

- one branch per work packet: `roadmap/<task-id>-short-name`;
- one or more focused commits, each buildable where practical;
- conventional commit subject with task ID;
- no force push after review begins;
- security-critical paths require CODEOWNERS;
- merge only after required status checks;
- update `STATUS.md` in the same merge;
- create a release-note entry for user-visible changes.

## 10.8 AI context control

Do not paste the whole repository into every model request. Give the implementing model:

- task packet;
- relevant ADRs;
- current status;
- specific source files;
- related tests;
- last failure evidence;
- interface schemas.

For long phases, produce a compact `HANDOFF.md` after every merged task.

---

# 11. Delivery timeline and phase gates

> **Execution-order note:** the Gantt is a capacity-planning view, not task authority. Dependencies are authoritative. P21–P24 complete before P20 begins, even though their numeric labels are higher than the terminal release phase.

```mermaid
gantt
    title Kristin 2.x Production Program
    dateFormat  YYYY-MM-DD
    axisFormat  %b %Y

    section Foundation
    P0 Stabilize and contain           :p0, 2026-07-23, 16d
    P1 Trust and core architecture     :p1, after p0, 42d

    section Execution
    P2 Owner Mode and terminal         :p2, 2026-08-24, 56d
    P3 Browser and Web Studio          :p3, 2026-09-14, 70d
    P4 Search extraction and data      :p4, 2026-10-05, 70d

    section Product
    P5 UX and UI redesign              :p5, 2026-09-07, 105d
    P6 Agent quality and model layer   :p6, 2026-10-19, 105d
    P7 MCP A2A and plugins             :p7, 2026-12-07, 70d

    section Assurance
    P8 Reliability security and evals  :p8, 2026-09-21, 168d
    P9 Release engineering             :p9, 2027-01-04, 70d
    P10 Beta RC and GA                 :p10, 2027-03-15, 56d
```

This is an execution sequence, not a promise. Optimize for gate completion rather than dates. Windows, macOS, and Linux are mandatory synchronized desktop targets; a public desktop GA is blocked until all three pass every applicable gate. Mobile, web, headless, and fleet surfaces have separate capability-equivalence gates, but may not be used to justify dropping a mandatory desktop platform.

---

# 12. Master implementation backlog

The backlog below is the canonical order. A task may begin early only when every dependency is complete and it does not create a competing architecture.



## P0 — Stabilize, contain, and establish truth

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P0-001` | Capture reproducible baseline | `none` | Inventory tree, schemas, tool registry, tests, CI, current failures, and hashes; write `release/evidence/baseline/`. | A clean checkout can reproduce the baseline report and every unavailable gate is explicitly marked. |
| `P0-002` | Disable insecure v1 trust decisions | `P0-001` | Remove or hard-disable authorization and update decisions that use `tool/interoperability_v19.py` envelope-supplied HMAC material. | Forgery test is rejected; no runtime path accepts v1 envelope trust. |
| `P0-003` | Green the current three-OS CI | `P0-001,P0-002` | Commit canonical Dart formatting; run every downstream analyzer, behavioral, validator, and native-build gate; repair the current Windows Project Manager readiness, SDK-environment, and artifact-evidence test failures without claiming unavailable isolation; retain complete failure evidence on all OS lanes. Do not redesign or pin CI in this task. | Ubuntu, Windows, and macOS reach every applicable workflow step and pass; platform-dependent unsupported states are asserted honestly; no blocking gate is skipped, excluded, or relabeled unavailable; the active branch contains reviewed P0-002. |
| `P0-004` | Pin toolchains and GitHub Actions | `P0-003` | Pin Flutter/Dart, Python, Actions by commit SHA, and cache keys; record versions in a toolchain manifest. | Two CI reruns use identical declared inputs. |
| `P0-005` | Rewrite security and support policy | `P0-001,P0-002` | Update supported version, platform matrix, Owner Mode intent, sandbox truth, interop freeze, and disclosure procedure. | README, SECURITY, UI, and release classification agree. |
| `P0-006` | Protect repository governance | `P0-003` | Add CODEOWNERS, branch protection requirements, PR template, security review labels, and merge policy. | Protected main cannot merge without required checks/review. |
| `P0-007` | Split source lint from behavioral assurance | `P0-001` | Reclassify `system_test.py` and validator token checks; create separate report categories. | Dashboard never reports source-marker checks as behavioral proof. |
| `P0-008` | Create roadmap control files and bootstrap manifest | `P0-001` | Add STATUS, ADR, risk, metric, prompt, evidence, handoff, `docs/roadmap/roadmap.yaml`, and a minimal dependency/cycle/status validator for active P0/P1 tasks. P24 later expands this into the complete all-task authority and traceability system. | A new AI session can select the next ready task without oral context, and CI rejects duplicate IDs, missing dependencies, cycles, invalid statuses, or conflicting roadmap authority in the bootstrap scope. |
| `P0-009` | Establish initial benchmark corpus | `P0-001` | Record current results for coding, analysis, path safety, crash recovery, browser-absent, and research tasks. | Baseline is versioned and reproducible. |
| `P0-010` | Remove committed generated state | `P0-001` | Apply source-tree policy, remove caches such as `__pycache__`, and update ignore rules. | Clean checkout stays clean after standard tests except declared reports. |

### P0 exit gate
- Current trust flaw is disabled.
- Current three-platform CI is green from formatting through native build.
- Toolchains and Actions are pinned.
- Security documentation is accurate.
- Roadmap status/evidence files exist.
- Baseline benchmark is reproducible.


## P1 — Trust, policy, and core architecture

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P1-001` | Approve runtime-boundary ADRs | `P0-008` | Define desktop, owner executor, automation host, research worker, sandbox worker, IPC, and storage boundaries. | ADRs resolve ownership and do not leave implementation-critical ambiguity. |
| `P1-002` | Define access profile v2 | `P1-001` | Create schema and domain model for chat, project, owner, owner_unattended, and isolated_untrusted modes. | Round-trip and invalid-policy tests pass in Dart and worker languages. |
| `P1-003` | Define capability grant v2 | `P1-001,P1-002` | Bind grants to run, task, actor, tool, paths, process, network, browser profile, secrets, budgets, expiry, and use count. | Worker rejects modified, expired, replayed, and wrong-run grants. |
| `P1-004` | Build deterministic policy engine | `P1-002,P1-003` | Implement mode resolution, organization/project/user overlays, and explicit widening rules. | Policy property tests prove deny-by-default and Owner Mode’s intended authority. |
| `P1-005` | Specify Signed Manifest v2 | `P0-002,P1-001` | Adopt Ed25519, RFC 8785 canonical JSON, external keyring, key IDs, intended use, expiry, trust domain, and revocation. | Language-neutral spec and negative vectors approved. |
| `P1-006` | Implement cross-language signing | `P1-005` | Implement Dart/Python signing and verification against shared golden vectors. | Both languages produce and verify identical vectors and reject mutations. |
| `P1-007` | Migrate or reject v1 envelopes | `P1-006` | Add explicit compatibility policy; v1 never authorizes production trust. | Downgrade and mixed-format tests pass. |
| `P1-008` | Design TUF update trust | `P1-005` | Define offline root, targets, snapshot, timestamp, delegations, thresholds, rotation, and recovery. | ADR and key ceremony runbook approved. |
| `P1-009` | Implement key storage and revocation | `P1-005` | Use OS keychain or external protected store; separate signing, API, browser, and secret-broker keys. | No private key is stored in repository or unencrypted settings. |
| `P1-010` | Create append-only signed audit checkpoints | `P1-006,P1-009` | Anchor audit heads with trusted keys and export verification receipts. | Tampering, truncation, reordering, and signer substitution are detected. |
| `P1-011` | Create threat model v2 | `P1-001,P1-004` | Map trust boundaries and OWASP agentic risks across model, tools, web, memory, MCP/A2A, terminal, and updater. | Every high-risk boundary has an owner and planned test. |
| `P1-012` | Create local authenticated IPC | `P1-001,P1-003` | Use named pipes/Unix sockets or loopback with mutual authentication, peer identity, request IDs, limits, and versioning. | Unprivileged unrelated local process cannot invoke a worker. |

### P1 exit gate
- One policy model covers safe, project, Owner, unattended, and isolated modes.
- One Signed Manifest v2 passes cross-language positive and adversarial vectors.
- Trust roots are external to envelopes.
- Local IPC rejects unauthorized callers.
- Threat model and TUF design are approved.


## P2 — Owner Mode, terminal, filesystem, and OS operations

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P2-001` | Owner Mode onboarding and settings | `P1-002,P1-004` | Build explicit enablement, persistent indicator, approval policy, data boundary, and disable/reset controls. | User can choose full access and UI never mislabels it as sandboxed. |
| `P2-002` | Full filesystem service | `P1-003,P1-012` | Support absolute paths, drives, shares, hidden files, metadata, search, copy, move, delete, and transactions in Owner Mode. | Cross-platform fixtures pass, including symlinks/reparse points and long paths. |
| `P2-003` | Owner finite command execution | `P1-003,P1-012` | Execute arbitrary direct processes with cwd/env, output limits, cancellation, and effect records. | Commands run outside projects only in Owner Mode and are fully journaled. |
| `P2-004` | Automation host technology spike | `P1-001,P1-012` | Compare TypeScript/node-pty+Playwright, native/Rust PTY+Playwright, and other viable packaging options. | ADR selects a solution using measured startup, memory, packaging, and reliability. |
| `P2-005` | Interactive PTY service | `P2-004` | Implement shell sessions, input, resize, ANSI, attach, detach, reconnect, and transcript. | Interactive fixtures pass on Windows, macOS, and Linux. |
| `P2-006` | Process-tree lifecycle manager | `P2-003,P2-005` | Track stable process identity, descendants, readiness, stop, kill, parent death, and PID reuse. | No child remains after kill/timeout in adversarial tests. |
| `P2-007` | Package and SDK operations | `P2-003` | Add package install/remove/update and SDK discovery with structured receipts. | Fixture installers and dry-run policies pass; real smoke tests run on target images. |
| `P2-008` | Service and application control | `P2-003` | Add service status/start/stop and app open/close adapters with platform-specific implementations. | Supported operations return honest status and rollback notes. |
| `P2-009` | Clipboard and screen capabilities | `P1-003,P1-012` | Add clipboard read/write, screen capture, active-window metadata, and redaction policy. | Capabilities obey profile and do not leak content into logs. |
| `P2-010` | Best-effort host snapshots and undo | `P2-002,P2-003` | Add file backups, Git checkpoints, restore points where available, and operation receipts. | Injected failures restore supported file changes and mark non-restorable effects. |
| `P2-011` | Emergency pause and kill watchdog | `P2-005,P2-006` | Add UI, tray, keyboard shortcut, and worker watchdog kill paths. | Kill works with frozen UI, runaway output, and descendant processes. |
| `P2-012` | Terminal UX | `P2-005,P2-006` | Build tabs, shell/cwd selector, search, save, copy, interrupt, terminate, attach, and run linkage. | Keyboard and screen-reader terminal scenarios pass. |
| `P2-013` | Owner Mode adversarial suite | `P2-002,P2-003,P2-006,P2-011` | Test destructive commands, path races, output floods, fork bombs, crashes, and restart. | Effects are intended, bounded by OS account, observable, cancellable, and recoverable where claimed. |
| `P2-014` | Owner Mode operator guide | `P2-001,P2-013` | Document privileges, risk, backups, unattended mode, secrets, kill, and recovery. | Guide matches UI and tested behavior. |

### P2 exit gate
- Owner Mode can access the full host available to the OS account.
- Interactive terminals work on Windows, macOS, and Linux, with platform-specific shell and lifecycle evidence.
- Process trees can be killed reliably.
- Full-host effects are observable, journaled, and recoverable where claimed.
- Owner Mode is clearly distinguished from isolation.


## P3 — Browser automation and Web Studio

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P3-001` | Bundle browser automation runtime | `P2-004,P1-012` | Pin automation host dependencies and browser binaries; create reproducible packaging. | Clean machine launches the bundled worker without a global runtime. |
| `P3-002` | Browser session service | `P3-001,P1-003` | Create ephemeral and persistent contexts, pages, profile selection, quotas, and cleanup. | Isolation and lifecycle tests pass. |
| `P3-003` | Canonical page observation | `P3-002` | Capture URL, title, DOM, accessibility tree, forms, visible text, screenshot, console, and network summary. | Observation hashes are stable on deterministic fixtures. |
| `P3-004` | Locator and action engine | `P3-003` | Implement click, type, fill, select, check, press, scroll, hover, drag, and wait with locator priority. | Fixture actions pass without coordinate fallback. |
| `P3-005` | Visual fallback | `P3-003,P3-004` | Add screenshot-based target selection only after structured locators fail, with confidence and verification. | Low-confidence actions pause instead of guessing. |
| `P3-006` | Downloads and uploads | `P3-002,P3-004` | Add controlled downloads, hashes, quarantine, file chooser handling, and upload receipts. | Download/upload fixtures pass and paths remain profile-scoped. |
| `P3-007` | Console, network, and trace capture | `P3-002` | Capture errors, requests, responses, timing, WebSocket summary, HAR/trace where supported. | Failed browser run exports a bounded replay bundle. |
| `P3-008` | Authentication profile storage | `P1-009,P3-002` | Protect cookies/storage, support personal/work profiles, export/delete, and no-model-context default. | Cross-profile leakage tests pass. |
| `P3-009` | User takeover state machine | `P3-002,P3-004` | Implement visible control transfer for MFA, CAPTCHA, payment, consent, and ambiguity. | Agent resumes only after re-observation. |
| `P3-010` | Browser action verification | `P3-003,P3-004` | Require postconditions and independent final verification for web tasks. | False-completion fixtures are rejected. |
| `P3-011` | Browser workspace UI | `P3-002,P3-007,P3-009` | Add tabs, URL, profile, agent/user control, action target, screenshot, extract, and trace. | Primary browser workflow is keyboard accessible. |
| `P3-012` | Web Studio editor | `P3-001` | Add file tree, code editor, diagnostics, format, search, diff, and source control hooks. | HTML/CSS/JS project can be edited and saved. |
| `P3-013` | Live preview and development server | `P3-012,P2-006` | Support static preview, configured dev server, readiness probe, hot reload, and stop. | Static and framework fixtures preview reliably. |
| `P3-014` | DOM, console, network inspector | `P3-003,P3-007,P3-011` | Expose structured page internals and link DOM selection to source when possible. | Inspector handles large pages without freezing UI. |
| `P3-015` | Responsive, accessibility, and visual test tools | `P3-013,P3-014` | Add viewports, screenshots, diff, accessibility checks, link/form checks. | Fixture defects are detected with actionable evidence. |
| `P3-016` | Deterministic browser fixture site | `P3-001` | Build local pages for auth, JS render, forms, downloads, uploads, popup, iframe, infinite scroll, injection, and takeover. | Browser CI has no external-network dependency. |
| `P3-017` | Browser security suite | `P3-002,P3-006,P3-008,P3-009,P3-016` | Test profile leakage, malicious downloads, prompt injection, tab confusion, redirects, and stale targets. | No unresolved critical/high browser finding. |
| `P3-018` | Browser task recipes | `P3-010,P3-011` | Ship recipes for research, form completion, authenticated download, web testing, and data extraction. | Recipes run against fixtures and produce receipts. |

### P3 exit gate
- Browser sessions, actions, profiles, downloads/uploads, takeover, traces, and verification work against deterministic fixtures.
- Web Studio can edit and preview HTML/CSS/JavaScript.
- Cross-profile leakage and blind-action tests pass.


## P4 — Web search, extraction, citations, and data saving

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
| `P4-012` | Web/research authority-schema migrations | `P4-001,P4-011` | Add search, fetch, source, extraction, citation, crawl, and dataset entities plus versioned authority migrations through the storage abstraction. The current SQLite adapter remains allowed until P24 completes the no-SQL cutover. | Migration, rollback, backup, corruption, and integrity tests pass on the current authority adapter and the entities can be migrated/rebuilt without embedding SQL assumptions in domain services. |
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

### P4 exit gate
- Search results are normalized and fetched before use.
- Static and rendered extraction meets benchmark thresholds.
- Citations bind to immutable source versions.
- Research and datasets persist, version, search, and export reproducibly.
- Crawl limits and robots handling pass fixtures.


## P5 — UX/UI redesign and accessibility

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P5-001` | Information architecture and UX flows | `P0-008` | Specify navigation, workspaces, jobs-to-be-done, and state transitions. | Clickable or coded flow prototype covers primary scenarios. |
| `P5-002` | Design token system | `P5-001` | Define semantic color, type, spacing, elevation, focus, motion, status, and Owner Mode tokens. | Light, dark, high-contrast, and reduced-motion themes pass. |
| `P5-003` | Reusable component library | `P5-002` | Build buttons, fields, dialogs, split panes, tabs, cards, tables, timelines, badges, empty/error states. | Components have widget, golden, and semantics tests. |
| `P5-004` | Three-pane application shell | `P5-001,P5-003` | Implement resizable left rail, center workspace, right inspector, and bottom activity drawer. | Layouts persist and handle minimum window size. |
| `P5-005` | Global autonomy status and kill | `P2-011,P5-004` | Display profile, model, active sessions, takeover, network, pause, stop, and emergency kill. | Status remains visible across workspaces. |
| `P5-006` | Chat and task composer redesign | `P5-003,P5-004` | Add attachments, project/profile/model/access, plan-only, run, schedule, criteria, and budget. | Composer supports keyboard-only task launch. |
| `P5-007` | Plan review and permission UX | `P1-004,P5-006` | Show goals, files, commands, sites, side effects, verification, risk, and profile. | Owner approval policy `never` is represented accurately. |
| `P5-008` | Unified run timeline | `P5-004` | Render model, policy, file, terminal, browser, web, evidence, verification, retries, and rollback. | Timeline handles 10k events with filtering. |
| `P5-009` | Artifact, diff, and evidence viewers | `P5-003` | Add text/binary metadata, image, Markdown, JSON, table, diff, citation, and receipt views. | All supported evidence types reopen from a saved run. |
| `P5-010` | Command palette and keyboard system | `P5-004` | Add searchable commands, shortcuts, conflict handling, and discoverability. | Primary workflows are keyboard complete. |
| `P5-011` | Onboarding and capability doctor | `P2-001,P3-001,P4-001` | Guide model, Owner Mode, browser, terminal, search providers, storage, and diagnostics. | Fresh machine reaches a tested working state. |
| `P5-012` | Accessibility compliance program | `P5-003` | Add semantics, focus, contrast, scaling, reduced motion, target sizes, and manual checklist. | Applicable WCAG 2.2 AA checks pass. |
| `P5-013` | UI performance budgets | `P5-004` | Instrument startup, frame time, list virtualization, stream throttling, and memory. | Performance dashboard meets initial targets. |
| `P5-014` | UX regression suite | `P5-006,P5-008,P5-009,P5-012` | Add widget, golden, navigation, semantics, keyboard, and failure-state tests. | Critical flow change cannot merge without tests. |
| `P5-015` | Human usability review | `P5-011,P5-014` | Run scripted sessions with representative users; record findings and fixes. | No unresolved critical usability blocker before RC. |

### P5 exit gate
- Primary workspaces are coherent, keyboard accessible, and measurable.
- Owner Mode and kill state are always visible.
- Run, browser, terminal, research, data, and evidence flows pass UI tests.
- Accessibility and performance gates pass.


## P6 — Agent intelligence, model routing, and safe autonomy

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P6-001` | Model registry v2 | `P1-001` | Record provider/model identity, limits, tool profile, data boundary, cost, benchmark, and approved task classes. | Unknown models start evaluation-only. |
| `P6-002` | Role-based model routing | `P6-001` | Separate planner, executor, verifier, browser observer, extractor, and reviewer roles. | Routing decisions are durable and policy constrained. |
| `P6-003` | Planner/executor/verifier separation | `P6-002,P1-004` | Prevent executor from granting scope or self-certifying acceptance criteria. | Adversarial model cannot convert prose into authority. |
| `P6-004` | Unified action protocol v3 | `P1-003` | Add terminal, browser, research, data, user takeover, wait, delegate, complete, and fail decisions. | Cross-provider golden and fuzz tests pass. |
| `P6-005` | Context provenance labels | `P6-003` | Label user, system, project, web, memory, terminal, MCP, A2A, and tool output. | Injection text cannot impersonate system authority. |
| `P6-006` | Prompt-injection containment | `P6-005` | Add untrusted-content wrappers, tool-policy separation, destination checks, and exfiltration controls. | Direct/indirect injection corpus has zero unauthorized effects. |
| `P6-007` | Browser planning policy | `P3-010,P6-004` | Require observe-action-verify, bounded retries, takeover, and stale-target handling. | Dynamic-page fixtures converge without blind clicking. |
| `P6-008` | Terminal planning policy | `P2-006,P6-004` | Distinguish finite/interactive/background commands, readiness, destructive scope, and recovery. | Agent stops loops and verifies command outcomes. |
| `P6-009` | Research answer policy | `P4-010,P6-005` | Require fetched evidence, citation coverage, freshness, disagreement, and source type. | Snippet-only or uncited claims fail verification. |
| `P6-010` | Memory admission v2 | `P6-005` | Quarantine failed/adversarial runs, preserve provenance, add expiry and user pinning. | Poisoned memory does not enter normal context. |
| `P6-011` | Long-running task handles | `P1-012,P6-004` | Support durable wait, resume, polling, mid-flight input, pause, and cancellation. | Desktop restart can resume supported tasks. |
| `P6-012` | Strategy escalation and convergence | `P6-003` | Use semantic progress, repeated-outcome detection, split, replan, stronger model, user takeover, or fail. | Long tasks do not loop indefinitely. |
| `P6-013` | Independent acceptance engine | `P6-003` | Map every criterion to current objective evidence and validator. | Generic evidence cannot satisfy unrelated criteria. |
| `P6-014` | Model compatibility test matrix | `P6-001,P6-004` | Run every supported model through protocol, coding, browser, research, and safety suites. | Support matrix is generated from results. |
| `P6-015` | Agent benchmark dashboard | `P6-013,P6-014` | Report task success, false completion, unauthorized attempts/effects, cost, latency, and recovery. | Release comparison is reproducible and signed. |

### P6 exit gate
- Planner, executor, policy, and verifier responsibilities are separate.
- Browser, terminal, research, and user takeover are typed decisions.
- Prompt injection cannot grant authority or exfiltrate through tools.
- Every supported model has a measured compatibility profile.


## P7 — MCP, A2A, skills, and extension ecosystem

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P7-001` | MCP version adapter architecture | `P1-001` | Support current stable MCP and isolate upcoming/spec-draft changes behind adapters; pin negotiated versions. | Protocol upgrade cannot silently remove capabilities. |
| `P7-002` | MCP server descriptor and registry | `P1-005,P7-001` | Record publisher, digest, version, transport, tools, resources, prompts, roots, network, secrets, and retention. | Unregistered or changed server fails trust policy. |
| `P7-003` | MCP lifecycle manager | `P7-002,P1-004` | Install, enable, start, health-check, stop, update, revoke, and remove servers. | Lifecycle and process cleanup tests pass. |
| `P7-004` | MCP execution isolation | `P7-003` | Run untrusted servers in isolated workers; Owner Mode may opt into host execution with clear status. | Mode selection is explicit and auditable. |
| `P7-005` | A2A 1.0 protocol adapter | `P1-005` | Implement Agent Cards, discovery, task/messages/artifacts, version header, auth schemes, streaming, and async tasks. | Conformance fixtures pass for supported subset. |
| `P7-006` | A2A trust and delegation grants | `P7-005,P1-003` | Bind remote agent identity, task, inputs, outputs, network, secrets, deadline, and downstream delegation. | Remote agent cannot widen authority. |
| `P7-007` | Replace environment-selected A2A executable | `P7-006` | Change bridge to resolve a registered agent/worker descriptor instead of raw executable JSON. | Environment control alone cannot execute an arbitrary program. |
| `P7-008` | A2A evidence and reconciliation | `P7-006` | Validate artifacts, progress, cancellation, idempotency, and unknown outcomes. | Forged completion and duplicate effect fixtures fail. |
| `P7-009` | Skill and plugin manifest v2 | `P1-006` | Define signed publisher identity, code digest, permissions, compatibility, entry point, tests, and revocation. | Unsigned or modified production extension is rejected. |
| `P7-010` | Extension marketplace/local registry | `P7-009` | Build install, inspect, enable, update, disable, revoke, and trust UI. | User sees exact requested capabilities. |
| `P7-011` | Interop adversarial suite | `P7-003,P7-008,P7-010` | Test prompt injection, lookalike tools, signer substitution, confused deputy, replay, and cascading failure. | No unresolved critical/high finding. |
| `P7-012` | Interop operator documentation | `P7-011` | Document MCP/A2A versions, trust, isolation, Owner Mode, data retention, and revocation. | Docs match conformance and UI. |

### P7 exit gate
- MCP and A2A versions are pinned and negotiated.
- External servers/agents/extensions have trusted identities and scoped grants.
- Raw environment data cannot select an arbitrary A2A executable.
- Adversarial interoperability suite has no open critical/high issue.


## P8 — Reliability, security, observability, and evaluation

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P8-001` | Formal test hierarchy | `P0-007` | Separate architecture lint, unit, component, integration, platform, adversarial, benchmark, and release tests. | Reports identify assurance level. |
| `P8-002` | Workflow chaos expansion | `P2-010,P4-012` | Inject disk full, corruption, WAL loss, clock jumps, duplicate completion, cancellation races, and interrupted migrations. | Every case recovers or becomes explicit unknown. |
| `P8-003` | External-effect state machine | `P1-003` | Implement planned, authorized, started, observed, committed, compensated, unknown, and reconciliation-required. | Unknown external effects are never blindly retried. |
| `P8-004` | Terminal fault-injection suite | `P2-006` | Test hung prompts, binary output, output floods, fork bombs, process escapes, and abrupt worker death. | Kill and recovery targets pass. |
| `P8-005` | Browser fault-injection suite | `P3-017` | Test navigation races, stale DOM, popups, downloads, crashes, storage leaks, and worker death. | No false completion or profile leakage. |
| `P8-006` | Research adversarial suite | `P4-021,P6-006` | Test poisoned pages, malicious metadata, SSRF, rebinding, giant pages, extraction traps, and citation drift. | No unauthorized effect or unsupported citation. |
| `P8-007` | Secret scanning v2 | `P0-010` | Add Git-history scan, entropy, provider detectors, archives, binary metadata, pre-commit, CI, and safe fingerprints. | Seeded secrets are detected without printing values. |
| `P8-008` | Dependency and license policy | `P0-004` | Add vulnerability, lockfile, provenance, license, and abandoned-package gates. | Unapproved dependency cannot reach release. |
| `P8-009` | OpenTelemetry instrumentation | `P1-001` | Add correlated traces, metrics, and logs for model, policy, tools, terminal, browser, web, and update. | One run is traceable end to end without project content by default. |
| `P8-010` | Privacy and telemetry controls | `P8-009` | Make telemetry opt-in, redact content, expose preview/export/delete, and document retention. | Privacy tests and data inventory pass. |
| `P8-011` | Performance and soak suite | `P5-013,P8-009` | Measure startup, memory, event throughput, large repos, long terminal/browser sessions, search, datasets, and 24h runs. | Budgets and leak thresholds pass. |
| `P8-012` | Agentic security mapping | `P1-011` | Map tests and controls to OWASP Agentic Top 10 and AI Agent Security guidance. | Every applicable risk has evidence or explicit accepted gap. |
| `P8-013` | NIST AI RMF evidence map | `P6-015,P8-012` | Map Govern, Map, Measure, Manage outcomes to product artifacts and owners. | Release package includes current risk register and measurement report. |
| `P8-014` | Independent penetration test | `P2-013,P3-017,P7-011` | Commission review of full-host execution, browser, IPC, signing, updater, MCP/A2A, and prompt injection. | No unresolved critical/high finding. |
| `P8-015` | Failure replay corpus | `P8-002,P8-004,P8-005,P8-006` | Minimize every production failure into a permanent deterministic fixture. | Regression replay runs in release CI. |

### P8 exit gate
- Assurance levels are reported separately.
- Chaos, browser, terminal, research, prompt-injection, and replay suites pass.
- OpenTelemetry and privacy controls are production ready.
- Independent penetration test has no unresolved critical/high issue.


## P9 — Release engineering, installers, signing, and updates

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P9-001` | Redesign CI pipeline | `P0-003,P8-001` | Split PR, nightly, platform, adversarial, benchmark, and release workflows with artifact retention. | Failures do not hide downstream evidence and required gates are enforced. |
| `P9-002` | Extend generated-state policy | `P3-001,P4-011` | Exclude Playwright, Node, browser profiles, traces, downloads, dataset intermediates, and native build state. | Validator, scanner, and packager use one tested policy. |
| `P9-003` | Reproducible dependency and browser lock | `P3-001,P8-008` | Lock Flutter/Dart, Python, automation host, browser binaries, native tools, and checksums. | Clean builders resolve identical inputs. |
| `P9-004` | SBOM and provenance | `P9-001,P9-003` | Generate source/build SBOMs, GitHub artifact attestations, checksums, and SLSA-aligned provenance. | Consumer can verify artifact to source/workflow. |
| `P9-005` | Windows installer and signing | `P9-003` | Build installer, code sign, timestamp, verify, install, upgrade, rollback, and uninstall on clean images. | All Windows release tests pass. |
| `P9-006` | macOS signing and notarization | `P9-003` | Sign nested binaries/helpers, hardened runtime, notarize, staple, verify, install, upgrade, rollback, uninstall. | All macOS release tests pass. |
| `P9-007` | Linux packages | `P9-003` | Produce supported signed package/bundle, dependency declarations, install/upgrade/rollback/uninstall tests. | Supported distributions pass. |
| `P9-008` | TUF repository and channels | `P1-008,P9-004` | Create offline root, delegated nightly/alpha/beta/stable/emergency targets, snapshot, timestamp, and publication. | Metadata expiry, rollback, freeze, mix-and-match, and compromise tests pass. |
| `P9-009` | Updater and rollback engine | `P9-008` | Download, verify, stage, stop workers, backup state, install, health-check, rollback, and report. | Injected failure at every stage returns to working version. |
| `P9-010` | Database upgrade compatibility | `P8-002,P9-009` | Test N-2 upgrade, N-1 rollback where supported, forward-only declarations, and backups. | No unsupported migration path is offered. |
| `P9-011` | Reproducible unsigned payload comparison | `P9-003,P9-004` | Build twice on clean builders and compare unsigned payloads; isolate intended signature/timestamp differences. | Payloads match or documented nondeterminism blocks release. |
| `P9-012` | Release command and evidence bundle | `P9-001,P9-004` | Create one release orchestrator that refuses missing gates and exports reports, SBOM, provenance, hashes, and notes. | A release cannot be labeled compiled/stable without all evidence. |
| `P9-013` | Support, privacy, license, and EULA documents | `P5-011,P8-010` | Finalize support matrix, privacy, retention, third-party notices, license, terms, and Owner Mode disclosure. | Human legal review recorded. |
| `P9-014` | Release website and verification guide | `P9-004,P9-012` | Publish checksums, signatures, provenance verification, install, update, rollback, and known limits. | Fresh user can verify an artifact independently. |
| `P9-015` | Key compromise drill | `P9-008,P9-012` | Simulate targets/timestamp/root compromise, rotate/revoke, issue emergency metadata, and block old artifacts. | Runbook succeeds from offline root. |
| `P9-016` | Bad update drill | `P9-009` | Publish faulty beta fixture, detect, halt rollout, rollback, and preserve state. | Staged rollout stops automatically. |

### P9 exit gate
- Signed installers/packages pass clean-machine install, upgrade, rollback, and uninstall.
- TUF metadata and updater tests pass.
- SBOM, SLSA-aligned provenance, attestations, hashes, and verification guide exist.
- Release command refuses incomplete evidence.


## P10 — Core alpha, beta, release candidate, and integration checkpoint

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P10-001` | Tri-platform internal alpha | `P2-013,P3-017,P4-021,P5-014,P6-015` | Ship equal Windows, macOS, and Linux internal builds with Owner Mode, terminal, browser, research, and data; capture failures. | Every mandatory desktop OS is represented, no P0 issue remains, and the replay corpus grows per platform. |
| `P10-002` | Tri-platform private beta | `P9-005,P9-006,P9-007,P9-009,P10-001` | Equal Windows, macOS, and Linux opt-in cohorts, staged updates, support intake, privacy telemetry, and weekly quality review. | SLOs and update targets hold independently on all three desktop OSs. |
| `P10-003` | External security audit closeout | `P8-014,P10-002` | Fix audit findings, add regressions, and publish scope/summary. | Zero unresolved critical/high. |
| `P10-004` | Release candidate freeze | `P10-003` | Feature freeze, exact versions, docs, translations, support, and release evidence. | RC artifact is immutable except blocker fixes. |
| `P10-005` | Thirty-day synchronized core RC soak | `P10-004` | Run continuous Windows, macOS, and Linux long-session, update, rollback, benchmark, and support monitoring. | Crash, quality, security, and parity thresholds pass independently on every mandatory desktop OS. |
| `P10-006` | Incident-response exercises | `P9-015,P9-016,P10-004` | Exercise leaked key, malicious extension, browser profile leak, sandbox escape, data corruption, and bad model. | Owners execute runbooks successfully. |
| `P10-007` | Core integration go/no-go review | `P10-005,P10-006` | Review every gate, accepted risk, cross-platform parity, evidence, support, and rollback. | Signed decision includes Windows, macOS, and Linux; no mandatory desktop OS is removed from the core integration scope. |
| `P10-008` | Staged core preview rollout | `P10-007` | Release internal→1%→5%→25%→50%→100% with automatic halt criteria. | No halt threshold is breached. |
| `P10-009` | Post-preview operations | `P10-008` | Monthly dependency/model review, quarterly drills, benchmark trend, vulnerability response, and deprecation policy. | Operational calendar has owners and evidence. |
| `P10-010` | Federated ecosystem checkpoint | `P7-011,P10-009` | Promote MCP/A2A/plugins only after dedicated soak and revocation testing. | Interop is independently gated from core GA. |

### P10 exit gate
- Private beta and RC soak meet SLOs.
- Security and incident exercises pass.
- The core preview includes Windows, macOS, and Linux; each claimed mode is enabled only where its gate passed, and unresolved parity gaps remain release blockers for P20.
- Staged rollout and automatic halt/rollback are operational.


---

# 13. Detailed implementation blueprints

The master backlog defines order and completion. This section tells an AI implementer how to execute the largest subsystems without creating a big-bang rewrite.

## 13.1 Incremental repository migration

Do not reorganize the entire repository in one patch. Use facade boundaries and move one service at a time.

Target structure:

```text
lib/
  app/
    app.dart
    routing.dart
    theme/
  core/
    contracts/
    errors/
    ipc/
    policy/
    telemetry/
  features/
    chat/
    projects/
    runs/
    terminal/
    browser/
    web_studio/
    research/
    data/
    memory/
    automations/
    settings/
  infrastructure/
    database/
    models/
    release/
    workers/
services/
  automation_host/
    src/
      ipc/
      terminal/
      browser/
      preview/
    test/
    fixtures/
  research_worker/
    src/
      search/
      fetch/
      extract/
      datasets/
    test/
schemas/
  access_profile.v2.json
  capability_grant.v2.json
  agent_decision.v3.json
  browser_action.v1.json
  browser_observation.v1.json
  terminal_session.v1.json
  web_search_request.v1.json
  web_source_record.v1.json
  web_extraction.v1.json
  citation_record.v1.json
  dataset_manifest.v1.json
  signed_manifest.v2.json
  update_policy.v2.json
test/
  unit/
  component/
  integration/
  platform/
e2e/
  browser_fixture/
  terminal_fixture/
  owner_mode/
evals/
  protocol/
  coding/
  browser/
  research/
  safety/
```

Migration rules:

1. Add a new interface and adapter around the current implementation.
2. Add characterization tests.
3. Move one implementation behind the interface.
4. Preserve existing APIs through a compatibility facade.
5. Update callers in small batches.
6. Delete the old path only after usage search and tests prove it is unused.
7. Update source-contract lint to assert architecture rules, not implementation text.

## 13.2 Error taxonomy

Create stable error classes:

```text
policy_denied
profile_required
capability_invalid
capability_expired
capability_replayed
ipc_unauthorized
path_unavailable
process_start_failed
process_timeout
process_tree_termination_incomplete
terminal_disconnected
browser_launch_failed
browser_target_stale
browser_action_ambiguous
browser_takeover_required
browser_download_blocked
search_provider_unavailable
fetch_ssrf_blocked
fetch_too_large
fetch_timeout
extract_failed
citation_locator_invalid
dataset_validation_failed
external_effect_unknown
signature_invalid
signer_unknown
manifest_expired
update_rollback_required
```

Every error includes:

```text
code
safe user message
technical detail
retryability
responsible subsystem
run/task/action IDs
redacted context
recommended next state
```

## 13.3 Capability enforcement sequence

Every effect follows:

```mermaid
sequenceDiagram
    participant M as Model
    participant C as Coordinator
    participant P as Policy Engine
    participant W as Worker
    participant E as Evidence Store
    participant V as Verifier

    M->>C: Typed proposed action
    C->>C: Schema validation
    C->>P: Resolve profile and grant
    P-->>C: Signed/scoped grant or denial
    C->>W: Action + grant + idempotency key
    W->>W: Revalidate grant and local state
    W->>E: Record prepared effect
    W->>W: Execute
    W->>E: Record result and evidence
    C->>V: Acceptance criteria + evidence
    V-->>C: verified / rejected / unknown
```

Owner Mode still uses a grant. Its grant may be broad, but that breadth is explicit and attributable.

## 13.4 Browser stale-target prevention

Between observation and action, the page may change. Every target should include:

```text
page ID
frame ID
observation hash
locator strategy
accessible name/text
element signature
expected precondition
maximum observation age
```

Before action:

1. Resolve target again.
2. Compare identity and key attributes.
3. Reject or re-observe when ambiguous.
4. Perform action.
5. Wait for the expected state.
6. Capture post-observation.
7. Verify.

## 13.5 Search source policy

For technical and current factual research:

1. prefer official specifications and primary documentation;
2. use repository source for implementation facts;
3. use authoritative institutions for standards and policy;
4. use independent sources for evaluation and competing interpretations;
5. compare publication date with event/effective date;
6. preserve disagreement;
7. mark inference as inference;
8. re-fetch when freshness policy expires.

## 13.6 Data-quality report

Each dataset version produces:

```text
row count
field count
null count per field
type conformance
duplicate count
source count
source-date range
extraction-quality distribution
validation failures
transformation recipe hash
input object hashes
output hash
```

## 13.7 Update transaction

```text
check metadata
→ verify trusted root chain
→ select channel target
→ verify version/rollback/freeze policy
→ download to staging
→ verify hashes and signatures
→ verify SBOM/provenance policy
→ stop active workers safely
→ checkpoint database and settings
→ install side by side
→ launch health check
→ migrate state
→ run post-install verification
→ switch active version
→ retain rollback version
→ report result

failure at any step
→ restore prior version and state
→ verify health
→ mark update failed
→ preserve evidence
```

---

# 14. Current-file improvement map

The following tasks should be tied directly to the current source rather than implemented as unrelated replacements.

## 14.1 `tool/source_tree_policy.py`

Extend and test generated paths for:

```text
.playwright/
playwright-report/
test-results/
browser-data/
browser-profiles/
browser-downloads/
browser-traces/
node_modules/
.npm/
.pnpm-store/
.yarn/
services/automation_host/dist/
services/automation_host/.cache/
datasets/.build/
release/evidence/generated/
```

Keep one policy shared by validation, secret scanning, packaging, and reproducibility checks. Add Windows path, case, separator, symlink, nested generated directory, and false-positive tests.

## 14.2 `tool/a2a_bridge.py`

Do not treat the bridge itself as a sandbox.

Migration:

1. Replace `KRISTIN_A2A_TARGET_JSON.executable` with a registered agent ID and descriptor digest.
2. Resolve the descriptor in the trusted host.
3. Create a delegation capability grant.
4. Select host or isolated execution based on policy.
5. Pass only normalized request data and a short-lived grant.
6. Verify the agent output schema.
7. Capture stdout/stderr as untrusted evidence.
8. Record cancellation and uncertain outcomes.
9. Delete the direct arbitrary-executable environment path.

## 14.3 `tool/secret_scan.py`

Retain fingerprint-only reporting, then add:

- Git-history scanning;
- entropy detection;
- provider-specific detectors;
- archive inspection;
- configuration for false-positive suppressions with owner and expiry;
- binary metadata scan;
- browser profile/download exclusions;
- pre-commit and CI integrations;
- seeded fixture suite;
- no secret validation request that would transmit a credential without explicit policy.

## 14.4 `tool/verify.sh`

Turn the script into a non-mutating orchestrator:

```text
generated contract checks
Python unit/component tests
Dart format check
Flutter dependency resolution
fatal analysis
Flutter tests
automation-host lint/type/test
browser fixture tests
research worker tests
workflow crash tests
architecture lint
security tests
secret/dependency/license scan
release validator
```

Formatting fixes must be a separate explicit command. Verification must not silently modify source.

## 14.5 `tool/system_test.py`

Split it into:

```text
architecture_contract_test.py
offline_behavior_test.py
platform_capability_test.py
security_behavior_test.py
```

Source markers may assert that a generated registry is wired or a forbidden dependency is absent. They must not claim that a sandbox, verifier, browser, terminal, or updater is secure.

## 14.6 `tool/workflow_kernel_test.py`

Retain the existing 14 durability cases and add:

- browser action committed before response loss;
- download written before result commit;
- terminal command exits after coordinator crash;
- process remains active after UI restart;
- unknown remote effect;
- crawl frontier resume;
- dataset transform interrupted;
- disk full during raw object write;
- database corruption;
- migration interrupted at each step;
- cancellation/commit race;
- duplicate worker completion;
- clock jump;
- backup validation failure.

## 14.7 `tool/validate_release.py`

Refactor into a manifest-driven release gate:

```text
gate ID
assurance level
command
platform
blocking
result
duration
artifact paths
artifact hashes
evidence URI
```

Remove duplicate file names and stale release identities. Separate “source contract passed” from “behavioral/platform/security passed.”

## 14.8 `tool/build_desktop.sh`

Evolve from “verify then flutter build” to:

```text
bootstrap exact toolchain
restore locked dependencies
build automation/research workers
run all platform gates
build Flutter app
bundle sidecars and browser runtime
generate SBOM/provenance
package platform artifact
sign/notarize
verify signature
install smoke test
update/rollback test
emit release evidence
```

Never label an unsigned local build as a stable production installer.

---

# 15. Verification command ladder

The exact commands may evolve, but preserve these tiers.

## 15.1 Fast developer gate

```bash
python3 tool/protocol_contract_test.py
python3 tool/generate_workflow_migrations.py --check
python3 tool/workflow_kernel_test.py --project .
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub --fatal-warnings --fatal-infos
flutter test --no-pub --concurrency=1
```

## 15.2 Automation host gate

```bash
npm ci --prefix services/automation_host
npm run lint --prefix services/automation_host
npm run typecheck --prefix services/automation_host
npm test --prefix services/automation_host
npm run test:e2e --prefix services/automation_host
```

Pin the package manager, runtime, lockfile, browser version, and download checksums.

## 15.3 Research worker gate

```bash
python3 -m pytest services/research_worker/test -q
python3 tool/research_contract_test.py
python3 tool/research_benchmark.py --fixtures evals/fixtures/research
```

## 15.4 Full system gate

```bash
./tool/verify.sh
python3 tool/validate_release.py
python3 tool/security_adversarial_test.py
python3 tool/eval_runner.py --suite release
```

## 15.5 Release gate

Run on clean, disposable native machines:

```text
dependency restore
all tests
native build
sidecar packaging
SBOM
provenance
sign/notarize
signature verification
install
first launch
upgrade
rollback
uninstall
artifact verification
```

---

# 16. Required evaluation suites

## 16.1 Coding and local-computer tasks

- inspect unfamiliar repository;
- explain architecture;
- fix compile error;
- implement feature;
- write tests;
- refactor without regression;
- install dependency;
- start and stop application;
- edit files outside project in Owner Mode;
- search entire computer for a file;
- manage package or service;
- recover after crash.

## 16.2 Terminal tasks

- interactive REPL;
- passwordless prompt fixture;
- long-running server;
- Ctrl+C;
- resize;
- binary output;
- huge output;
- child processes;
- hung process;
- environment variables;
- attach/detach;
- restart UI and reconnect;
- kill complete tree.

## 16.3 Browser tasks

- search and open result;
- navigate multi-page site;
- complete form;
- authenticate fixture;
- user takeover;
- upload/download;
- popup/tab;
- iframe;
- dynamic DOM;
- infinite scroll;
- console failure;
- network failure;
- stale target;
- prompt injection;
- extract table;
- verify submitted result.

## 16.4 Research tasks

- current fact requiring date;
- official technical documentation;
- conflicting sources;
- multi-language search;
- rendered page;
- article extraction;
- table extraction;
- crawl with robots;
- citation validation;
- dataset export;
- source changed after first fetch;
- paywall/blocked page;
- unsupported source.

## 16.5 Safety and authority

- web page asks for secrets;
- README asks agent to ignore user;
- terminal output imitates system message;
- MCP tool description asks for broader permissions;
- A2A agent returns forged success;
- memory contains fake instruction;
- model requests out-of-profile path;
- Owner Mode intentionally allows full path;
- isolated mode blocks same path;
- unknown external effect is not retried;
- signer replacement;
- expired grant;
- wrong browser profile;
- secret in URL/output/download.

## 16.6 Release and update

- trusted stable update;
- wrong channel;
- expired timestamp;
- rollback attack;
- freeze attack;
- mix-and-match metadata;
- corrupted download;
- revoked key;
- interrupted download;
- interrupted install;
- failed database migration;
- failed first launch;
- rollback;
- compromised online key;
- offline root rotation.

---

# 17. Release gates and sign-off

## Gate A — repository health

- protected main;
- pinned toolchains;
- green Linux/Windows/macOS CI;
- no generated drift;
- no unresolved secret/dependency blocker;
- evidence reports retained.

## Gate B — trust and policy

- v1 insecure verifier disabled;
- Signed Manifest v2 only;
- cross-language vectors;
- external trust roots;
- key rotation/revocation drill;
- policy property tests;
- authenticated IPC.

## Gate C — Owner Mode and terminal

- full filesystem and arbitrary command behavior works as specified;
- PTY works on Windows, macOS, and Linux;
- process trees terminate;
- kill works independently of UI;
- effects are journaled;
- docs accurately state privileges.

## Gate D — browser and Web Studio

- deterministic browser suite passes;
- profile isolation;
- human takeover;
- download/upload policy;
- stale-target handling;
- trace/replay;
- HTML/CSS/JS build and preview;
- no open critical/high finding.

## Gate E — research and data

- provider abstraction;
- fetch and rendered fetch;
- extraction benchmark;
- immutable citations;
- FTS;
- dataset reproduction;
- robots/rate limits;
- exports reopen;
- no open critical/high finding.

## Gate F — agent quality

- supported model matrix;
- task thresholds;
- zero unauthorized effects;
- false-completion target;
- prompt-injection suite;
- independent acceptance;
- recovery targets.

## Gate G — UX/accessibility

- primary flows;
- Owner status and kill;
- keyboard coverage;
- semantics;
- WCAG checklist;
- performance;
- onboarding;
- no critical usability issue.

## Gate H — release supply chain

- signed artifacts;
- notarization where applicable;
- SBOM and provenance;
- SLSA-aligned evidence;
- TUF;
- install/update/rollback/uninstall;
- reproducible unsigned payload;
- verification guide.

## Gate I — operations

- beta SLOs;
- 30-day RC soak;
- incident drills;
- support;
- privacy;
- legal;
- staged rollout;
- kill/update rollback authority.

---

# 18. Human-required actions

AI can prepare code, forms, commands, runbooks, and verification. The following require the human owner or an authorized organization representative:

- purchasing or verifying a Windows code-signing certificate;
- Apple Developer enrollment, certificate issuance, and notarization credentials;
- Linux repository signing-key custody;
- offline TUF root key ceremony;
- GitHub organization settings and protected-environment approvals;
- provider API account creation and billing;
- MFA, CAPTCHA, passkey, biometric, and payment steps;
- legal review of license, EULA, privacy policy, terms, and data processing;
- commissioning an independent penetration test;
- deciding accepted residual risk;
- promoting a release to stable/GA.

The AI should create exact checklists and stop at the point requiring identity or secret-bearing human action.

---

# 19. First 14 AI sessions

Use this exact starting sequence.

## Session 1 — P0-001

Capture repository inventory and baseline reports. Do not modify product behavior.

## Session 2 — P0-002

Disable the insecure v1 signed-manifest trust path and add the attacker-forgery regression.

## Session 3 — P0-003

Commit canonical formatting, repair every downstream gate, and make the existing Ubuntu/Windows/macOS workflow truthful and green. Treat unsupported platform capabilities explicitly; do not invent a sandbox, redesign CI, or pin toolchains in this task.

## Session 4 — P0-004

Pin toolchains and Actions. Record exact versions.

## Session 5 — P0-005

Rewrite `SECURITY.md`, platform matrix, and release classification.

## Session 6 — P0-007

Separate source contracts from behavioral assurance.

## Session 7 — P0-008

Create roadmap status, ADR, risk, metric, prompt, evidence, and handoff files.

## Session 8 — P0-006

Add repository governance files and document required GitHub settings.

## Session 9 — P0-009

Create the first versioned benchmark baseline.

## Session 10 — P0-010

Clean generated state and expand the shared source-tree tests.

## Session 11 — P1-001

Write runtime-boundary ADRs.

## Session 12 — P1-002

Define Access Profile v2, including unrestricted Owner Mode.

## Session 13 — P1-003

Define Capability Grant v2.

## Session 14 — P1-004

Implement the policy engine and property tests.

Do not begin terminal or browser implementation before these contracts are stable.

---

# 20. Product release scope recommendation

## Kristin Core Alpha

- Windows, macOS, and Linux internal builds from the first alpha; no mandatory desktop platform may be omitted;
- project and Owner Mode;
- finite commands plus early PTY;
- Chromium automation against fixtures;
- static/rendered research;
- local datasets;
- no public updater;
- MCP/A2A disabled by default;
- internal testers only.

## Kristin Core Beta

- full PTY on Windows, macOS, and Linux;
- browser workspace and Web Studio;
- search, extraction, citations, datasets;
- signed Windows and Linux installers/packages plus signed-and-notarized macOS artifacts;
- beta TUF channel;
- opt-in telemetry;
- private cohort;
- Owner Mode clearly disclosed;
- external MCP/A2A still experimental.

## Kristin Core RC

- Windows, macOS, and Linux workers packaged and passing parity gates;
- browser and terminal adversarial suites;
- external security review closed;
- signed/notarized artifacts;
- stable update and rollback;
- complete docs/support;
- 30-day soak.

## Kristin Core Integration Release

Do not publish a final desktop GA unless Windows, macOS, and Linux all passed every applicable gate. A blocked platform blocks the synchronized desktop release rather than being silently removed from scope.

A core integration preview may label an isolated backend experimental while its containment suite is still open. The final P20 maximum-capability GA, however, requires independently tested `project`, `owner`, `owner_unattended`, and `isolated_untrusted` execution semantics on Windows, macOS, and Linux; no desktop platform may silently downgrade hostile-workload isolation.

## Federated Agent GA

MCP, A2A, skills, plugins, remote execution, and fleet administration graduate separately after identity, revocation, isolation, prompt-injection, delegation, and cross-agent evidence gates pass.

---

# 21. Standards and implementation references

These references are implementation baselines, not automatic certifications.

1. Kristin current source overview: <https://raw.githubusercontent.com/alex00Pirotskyi/kris.ai/main/README.md>
2. Kristin current CI workflow: <https://raw.githubusercontent.com/alex00Pirotskyi/kris.ai/main/.github/workflows/ci.yml>
3. Kristin current security policy: <https://raw.githubusercontent.com/alex00Pirotskyi/kris.ai/main/SECURITY.md>
4. Vulnerable v1.9 helper to remove: <https://raw.githubusercontent.com/alex00Pirotskyi/kris.ai/main/tool/interoperability_v19.py>
5. Safer external-key-lookup HMAC helper to migrate away from for distributable trust: <https://raw.githubusercontent.com/alex00Pirotskyi/kris.ai/main/tool/release_ops_v19.py>
6. NIST AI Risk Management Framework: <https://www.nist.gov/itl/ai-risk-management-framework>
7. NIST Generative AI Profile: <https://www.nist.gov/publications/artificial-intelligence-risk-management-framework-generative-artificial-intelligence>
8. OWASP Top 10 for Agentic Applications 2026: <https://genai.owasp.org/resource/owasp-top-10-for-agentic-applications-for-2026/>
9. OWASP AI Agent Security Cheat Sheet: <https://cheatsheetseries.owasp.org/cheatsheets/AI_Agent_Security_Cheat_Sheet.html>
10. SLSA v1.2: <https://slsa.dev/spec/v1.2/>
11. The Update Framework: <https://theupdateframework.io/>
12. RFC 8785 JSON Canonicalization Scheme: <https://www.rfc-editor.org/rfc/rfc8785.html>
13. RFC 8032 Ed25519: <https://www.rfc-editor.org/rfc/rfc8032.html>
14. Playwright browser contexts: <https://playwright.dev/docs/browser-contexts>
15. Playwright network APIs: <https://playwright.dev/docs/network>
16. Chrome DevTools: <https://developer.chrome.com/docs/devtools>
17. Model Context Protocol specification: <https://modelcontextprotocol.io/specification/>
18. MCP roadmap/current draft tracking: <https://modelcontextprotocol.io/development/roadmap>
19. Agent2Agent protocol 1.0 specification: <https://a2a-protocol.org/latest/specification/>
20. SQLite FTS5: <https://www.sqlite.org/fts5.html>
21. OpenTelemetry specification: <https://opentelemetry.io/docs/specs/otel/>
22. WCAG 2.2: <https://www.w3.org/TR/WCAG22/>
23. WCAG guidance for non-web software: <https://www.w3.org/TR/wcag2ict-22/>
24. RFC 9309 Robots Exclusion Protocol: <https://www.rfc-editor.org/rfc/rfc9309.html>
25. GitHub artifact attestations: <https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations>

> Date-sensitive protocol note: on July 23, 2026, the MCP `2026-07-28` revision is still described as a release candidate expected on July 28, 2026. Kristin should isolate MCP versions behind an adapter, pin the currently supported stable version, and re-evaluate the final specification after publication rather than coding production behavior to a draft without a compatibility layer.

---



# 22. Omni-platform delivery contract

## 22.1 Synchronized desktop rule

Windows, macOS, and Linux are mandatory from architecture, CI, development, alpha, beta, RC, signing, installation, update, rollback, and support. The team may implement platform lanes in parallel, but a cross-platform work packet is `DONE` only after all mandatory lanes pass.

Every task that changes a platform-facing contract must declare:

```text
platformImpact:
  windows: required | unchanged | not_applicable_with_reason
  macos: required | unchanged | not_applicable_with_reason
  linux: required | unchanged | not_applicable_with_reason
  web: required | unchanged | deferred_with_task
  android: required | unchanged | deferred_with_task
  ios: required | unchanged | deferred_with_task
```

For Windows, macOS, or Linux, `deferred_with_task` is not permitted for a capability included in the current phase exit gate.

## 22.2 Supported architecture matrix

The release manifest must be generated from tested artifacts, not manually written marketing text.

| Family | Architectures | Desktop environments / shells | Minimum mandatory verification |
|---|---|---|---|
| Windows | x64 and ARM64 where the Flutter/native dependency chain supports it | PowerShell, CMD, Windows Terminal-compatible ConPTY clients | clean install, first launch, Owner Mode, PTY, UI Automation, browser, updater, rollback |
| macOS | Apple Silicon; Intel while supported by the selected Flutter/Xcode product policy | Zsh, Bash, Fish/custom shell; Finder and native apps | signed/notarized install, TCC consent flows, Owner Mode, PTY, AX automation, browser, updater, rollback |
| Linux | x64 and ARM64 for declared packages | GNOME and KDE; Wayland and X11 where supported; Bash/Zsh/Fish | package install, portal/AT-SPI behavior, Owner Mode, PTY, browser, updater, rollback |

A platform architecture may be declared temporarily unavailable only when the underlying OS vendor or pinned toolchain makes it impossible. The evidence bundle must include the upstream limitation, impact, owner decision, and restoration task.

## 22.3 Parallel platform-lane protocol

For a cross-platform feature, use this merge order:

1. Approve the shared schema, stable errors, and conformance fixtures.
2. Create empty platform adapters that return `capability_not_implemented` honestly.
3. Implement Windows, macOS, and Linux lanes in parallel branches or bounded sub-packets.
4. Run shared conformance tests against every adapter.
5. Run native hostile and lifecycle tests on clean platform images.
6. Merge only when the integration branch is green on all three.
7. Generate the capability matrix and evidence receipt from the passing runs.

No platform adapter may silently fall back to shell text when the contract promises a structured native result.

## 22.4 Platform version policy

Create `config/platform_support.yaml` containing exact tested versions, architectures, desktop environments, shells, browser builds, package formats, signing identities, and end-of-support dates. Review it monthly and before every release candidate.

The policy must distinguish:

- `build_supported` — source compiles;
- `behavior_supported` — capability tests pass;
- `release_supported` — signed package passed install/update/rollback/uninstall;
- `owner_mode_supported` — full-host path passed adversarial and kill tests;
- `isolation_supported` — hostile-workload containment has independent evidence.

## 22.5 Capability-equivalence rule

Parity means equal user outcome and evidence, not identical low-level mechanisms. Examples:

```text
terminate process tree
Windows → Job Object with kill-on-close and descendant accounting
macOS   → process groups plus descendant reconciliation and watchdog
Linux   → process groups plus cgroup/systemd scope where available

observe desktop UI
Windows → UI Automation tree
macOS   → AXUIElement accessibility hierarchy
Linux   → AT-SPI2 hierarchy, with desktop-portal or compositor-specific fallback
```

When structured semantics are unavailable, the capability status must explicitly change to `visual_fallback`, include confidence, and require postcondition verification.

---

# 23. Maximum-capability architecture v3

## 23.1 System planes

```mermaid
flowchart TB
    USER[Owner / User / Organization] --> CLIENTS[Desktop + Web + Mobile Clients]
    CLIENTS --> CONTROL[Control Plane / Durable Run Coordinator]

    CONTROL --> POLICY[Policy, Identity, Capability and Budget Engine]
    CONTROL --> MODELS[Model and Multimodal Runtime Plane]
    CONTROL --> EVIDENCE[Evidence, Audit, Verification and Memory Plane]
    CONTROL --> REGISTRY[Capability, Connector, Skill and Platform Registry]

    POLICY --> WIN[Windows Native Executor]
    POLICY --> MAC[macOS Native Executor]
    POLICY --> LINUX[Linux Native Executor]
    POLICY --> SANDBOX[Isolated Workload Executors]
    POLICY --> BROWSER[Browser and Web Automation Plane]
    POLICY --> CONNECT[Universal Connector and API Plane]
    POLICY --> APPFACTORY[Application Factory and Vibe Coding Plane]
    POLICY --> CONTENT[Content Manufacturing Plane]
    POLICY --> DEPLOY[Deployment, Cloud and Fleet Plane]
    POLICY --> CHANNELS[Realtime and Omnichannel Plane]

    WIN --> EVIDENCE
    MAC --> EVIDENCE
    LINUX --> EVIDENCE
    SANDBOX --> EVIDENCE
    BROWSER --> EVIDENCE
    CONNECT --> EVIDENCE
    APPFACTORY --> EVIDENCE
    CONTENT --> EVIDENCE
    DEPLOY --> EVIDENCE
    CHANNELS --> EVIDENCE

    REGISTRY --> WIN
    REGISTRY --> MAC
    REGISTRY --> LINUX
    REGISTRY --> CONNECT
    REGISTRY --> APPFACTORY
    REGISTRY --> CONTENT

    RELEASE[Supply Chain, Signing, TUF, Installers and Updates] --> CLIENTS
    RELEASE --> WIN
    RELEASE --> MAC
    RELEASE --> LINUX
```

## 23.2 Canonical service boundaries

Add or evolve these services. Each service has versioned contracts, stable error codes, OpenTelemetry spans, budgets, evidence hooks, and independent conformance tests.

```text
RunCoordinatorService
PlanCompilerService
AccessProfileService
CapabilityGrantService
PolicyDecisionService
IdentityBrokerService
CredentialVaultService
CredentialLeaseService
TransactionPolicyService
CapabilityRegistryService
PlatformSupportService
WindowsNativeService
MacNativeService
LinuxNativeService
TerminalSessionService
ProcessLifecycleService
FilesystemService
DesktopObservationService
DesktopActionService
DeviceService
BrowserSessionService
WebResearchService
ConnectorRegistryService
ApiIntrospectionService
ApiExecutionService
WebhookService
DatabaseConnectorService
ApplicationFactoryService
RepositoryIntelligenceService
BuildTestService
PreviewService
DeploymentService
ContentProjectService
AssetGraphService
ImagePipelineService
AudioPipelineService
VideoPipelineService
DocumentPipelineService
PresentationPipelineService
SpreadsheetPipelineService
PublishingService
BrandPolicyService
ProvenanceService
ModelRegistryService
ModelRouterService
LocalInferenceService
RealtimeConversationService
ChannelGatewayService
KnowledgeIngestionService
MemoryService
FleetControlService
NodeIdentityService
EvidenceService
IndependentVerificationService
AuditCheckpointService
UpdateService
ReleaseEvidenceService
TelemetryService
```

## 23.3 Capability registry

Create `schemas/capability_descriptor.v3.json`. Every tool, native function, connector operation, content renderer, model, remote agent, and application recipe registers a descriptor.

```json
{
  "schemaVersion": "3.0.0",
  "capabilityId": "desktop.element.invoke",
  "providerId": "builtin.windows.uia",
  "providerVersion": "1.0.0",
  "kind": "effect",
  "riskClass": "host_mutation",
  "inputSchema": "schema://desktop_action.v2",
  "outputSchema": "schema://desktop_action_receipt.v2",
  "platforms": {
    "windows": {"status": "behavior_supported", "backend": "uia"},
    "macos": {"status": "behavior_supported", "backend": "axuielement"},
    "linux": {"status": "behavior_supported", "backend": "at-spi2"}
  },
  "authority": {
    "requiredProfile": ["owner", "owner_unattended"],
    "grantDimensions": ["application", "window", "element", "action"],
    "supportsDryRun": false,
    "supportsIdempotency": "conditional"
  },
  "evidence": {
    "required": ["preObservationHash", "targetSignature", "postObservationHash"],
    "sensitiveFields": ["typedText"]
  },
  "verification": {
    "required": true,
    "strategies": ["element_state", "window_state", "screen_diff"]
  }
}
```

The registry must support:

- discovery by semantic goal, platform, risk, profile, provider, cost, latency, and data boundary;
- provider priority and fallback rules;
- version negotiation;
- capability health;
- deprecation and revocation;
- signed publisher identity;
- compatibility fixtures;
- generated user-facing support matrix;
- generated model tool catalogs that expose only granted capabilities.

## 23.4 Platform support manifest

Create `schemas/platform_support_manifest.v1.json` and generate one manifest per release.

Required fields:

```text
release ID and commit
OS family/version/build
CPU architecture
package type and hash
native helper versions
shells
browser engines and versions
desktop environment/compositor
credential backend
PTY backend
process-tree backend
desktop automation backend
screen/audio/camera backend
signing/notarization status
install/update/rollback results
capability IDs and assurance level
known limitations and evidence URIs
```

## 23.5 Action envelope v4

Every model-proposed action is normalized into:

```json
{
  "schemaVersion": "4.0.0",
  "runId": "run_...",
  "taskId": "task_...",
  "actionId": "act_...",
  "actor": {"type": "model", "id": "provider/model"},
  "capabilityId": "api.operation.execute",
  "providerSelection": {"mode": "policy", "preferred": []},
  "arguments": {},
  "expectedEffects": [],
  "preconditions": [],
  "postconditions": [],
  "idempotency": {"key": "...", "reconciliation": "query_provider"},
  "budgets": {"timeMs": 60000, "costMicros": 0, "bytes": 10485760},
  "dataLabels": ["owner_private"],
  "grantRef": "grant_...",
  "evidencePolicy": "standard",
  "onUncertainty": "pause_or_reconcile"
}
```

A worker must reject an envelope if the capability is absent, the provider is incompatible, the grant is invalid, the action exceeds budget, or mandatory preconditions cannot be observed.

## 23.6 Storage architecture

Use a layered design:

```text
embedded transactional object/document authority (no SQL core)
  → durable single-machine workflow, settings, grants, receipts, metadata and rebuildable index manifests

content-addressed object store
  → source snapshots, DOM, images, audio, video, documents, traces, model artifacts

optional PostgreSQL authority
  → organization/fleet coordination, shared jobs, connector metadata, audit indexes

optional vector/graph indexes
  → replaceable derived indexes, never sole source of truth

encrypted credential store
  → OS-native vault plus optional enterprise vault/HSM integrations
```

Raw assets and immutable evidence are content-addressed. Mutable project state references versions. Every derived index is rebuildable.

## 23.7 Cross-plane invariants

1. Model output never grants itself authority.
2. A capability descriptor is not a grant.
3. A credential value is not normal model context.
4. Every side effect has a run, actor, profile, grant, target, result, and evidence link.
5. Every platform adapter returns the same semantic result envelope.
6. A fallback cannot claim the assurance level of the preferred backend.
7. No executor is the sole verifier of its own completion.
8. Unsupported is a valid machine-readable result; fabricated success is not.
9. Every network upload records destination, account, byte count, data labels, and provider receipt.
10. Every generated artifact records inputs, model/provider, tool versions, recipe, hash, and rights/provenance metadata.

---

# 24. Native execution backends for Windows, macOS, and Linux

## 24.1 Shared native-host contract

Create one native host interface with platform adapters for:

```text
host.info
host.permissions.inspect
host.elevation.request
filesystem.*
terminal.*
process.*
service.*
package.*
application.*
desktop.observe
desktop.action
window.*
input.*
clipboard.*
screen.*
audio.*
camera.*
device.*
network.interface.*
credential.backend.*
notification.*
power.*
schedule.*
```

The shared contract must never erase platform-specific evidence. Common fields live in the canonical receipt; native details live under a namespaced `providerDetails` object.

## 24.2 Windows backend

Implement with native Windows facilities where applicable:

- ConPTY for interactive terminal semantics;
- Job Objects for process-tree accounting, limits, and kill-on-close;
- Win32 and WinRT APIs for process, window, file, notification, device, clipboard, screen, audio, and application operations;
- Windows UI Automation as the primary structured desktop tree;
- COM/WMI/CIM and Service Control Manager adapters for system information and services;
- Task Scheduler adapter for durable schedules;
- Registry adapter with explicit hive/view and before/after evidence;
- Windows Credential Management API and DPAPI-backed encryption for local secrets;
- Windows package adapters for MSI/MSIX, winget, and declared third-party package managers;
- UAC-aware privileged helper using signed binaries, narrow IPC, explicit operation records, and no stored administrator password;
- Authenticode signing and timestamp verification for every executable, DLL, helper, installer, and update payload.

Windows-specific tests must cover:

```text
x64 and declared ARM64 support
long paths and UNC paths
junctions, symlinks and reparse points
case-insensitive path collisions
ConPTY resize and Unicode
nested process jobs and breakaway attempts
UIA tree changes and stale elements
UAC approval/denial/cancel
registry 32/64-bit views
service recovery
locked files
installer reboot requirements
Windows Defender/SmartScreen-compatible signing evidence
```

## 24.3 macOS backend

Implement with native macOS facilities where applicable:

- POSIX PTY, process groups, descendant reconciliation, and watchdog lifecycle;
- AXUIElement accessibility API as the primary structured desktop tree;
- NSWorkspace and NSRunningApplication for application lifecycle and workspace observation;
- Apple Events, Shortcuts, or App Intents only through explicit capability declarations and OS consent;
- ScreenCaptureKit or the currently supported native capture API for screen/window capture;
- CoreAudio/AVFoundation adapters for permitted audio/camera operations;
- Keychain Services using the data-protection keychain where appropriate;
- launchd adapters for services and scheduled jobs;
- native authorization/elevation flow with no credential capture;
- TCC permission discovery and a first-class onboarding/repair experience for Accessibility, Screen Recording, Automation, microphone, camera, files, and other protected resources;
- hardened runtime, signed nested helpers, Developer ID distribution, notarization, stapling, and verification.

macOS-specific tests must cover:

```text
Apple Silicon and declared Intel support
APFS case-sensitive and case-insensitive volumes
symlinks, aliases and file coordination
PTY Unicode, resize and shell profiles
AX trust absent/granted/revoked mid-run
TCC prompts and denial recovery
Spaces, multiple displays and full-screen apps
sandboxed and non-sandboxed helper boundaries
launchd lifecycle
Keychain locked/unlocked behavior
quarantine attributes and Gatekeeper
notarized install, upgrade, rollback and uninstall
```

## 24.4 Linux backend

Implement with Linux desktop and service standards where applicable:

- POSIX PTY and process groups;
- cgroups v2 or transient systemd scopes when available for lifecycle, limits, and accounting;
- AT-SPI2 as the primary structured desktop tree;
- D-Bus integrations for desktop and system services;
- XDG Desktop Portal for file chooser, screen cast, remote desktop, notifications, global shortcuts, clipboard, camera, and other supported portal operations;
- X11 and Wayland-aware screen/input strategies, with portal or compositor-specific consent where required;
- Secret Service API for local credential storage, with explicit degraded mode when no compatible service exists;
- systemd, OpenRC, and other declared init/service adapters through a common contract;
- package adapters for deb/apt, rpm/dnf, pacman, Flatpak, Snap, AppImage metadata, and declared distribution mechanisms;
- polkit/sudo-aware elevation with no password logging or prompt scraping;
- signed packages and repository metadata for supported distributions.

Linux-specific tests must cover:

```text
GNOME and KDE
Wayland and X11
x64 and declared ARM64
ext4, btrfs and network filesystem fixtures
case-sensitive paths and symlinks
PTY shells and locale variations
AT-SPI availability and stale objects
portal backend discovery
cgroup/systemd scope kill
package-manager locks
Secret Service absent/locked/unlocked
polkit approval/denial
signed package install, update, rollback and uninstall
```

## 24.5 Cross-platform `isolated_untrusted` backends

Full Owner Mode and hostile-workload isolation are separate mandatory capabilities. Owner Mode deliberately uses the owner account's authority. `isolated_untrusted` must instead minimize ambient authority and provide independently tested containment.

### 24.5.1 Assurance tiers

Every isolated run declares one of these levels. The product must never silently downgrade the requested level.

| Level | Meaning | Valid use |
|---|---|---|
| `process_restriction` | Process tree, resource limits, reduced token/capabilities and brokered I/O, but shared host kernel and no complete hostile-code claim | Cooperative tools and low-risk build steps |
| `os_container` | OS-native application/container isolation with explicit filesystem, network, credential, IPC and device boundaries | Medium-risk workloads after platform conformance |
| `vm_isolation` | Disposable virtual machine or microVM with immutable base, copy-on-write state and brokered host exchange | Hostile repositories, unknown binaries and high-risk plugins |
| `remote_disposable_node` | Attested disposable worker on another trusted machine or cloud account | Hardware/edition limits, incompatible guest architecture, or stronger blast-radius separation |

A task marked hostile requires `vm_isolation` or a separately approved containment profile whose external assessment demonstrates equivalent protection. `process_restriction` alone is never described as a hostile-code sandbox.

### 24.5.2 Windows isolated backend

Provide a tiered adapter:

- restricted tokens, integrity levels, Job Objects and explicit handle inheritance for process restriction;
- AppContainer where the workload and packaging model are compatible;
- Windows Sandbox or a managed Hyper-V disposable VM for hostile workloads when supported by the installed edition and hardware;
- an attested remote disposable node when local virtualization is unavailable;
- mapped host folders disabled by default, read-only when possible, and always represented by a scoped capability grant;
- clipboard, audio, camera, printer, GPU, host networking and other redirections disabled by default and individually declared;
- network disabled by default or routed through a policy broker with connection receipts;
- disposable disk, base-image digest, guest-agent digest and teardown receipt.

Tests must cover edition/feature absence, nested virtualization, AppContainer escape attempts, Job breakaway, mapped-folder mutation, clipboard/device leakage, host credential access, guest reboot, abandoned VM cleanup and kill from a frozen desktop client.

### 24.5.3 macOS isolated backend

Use Apple's Virtualization framework as the primary hostile-workload boundary:

- signed native virtualization helper with the minimum required entitlements;
- pinned Linux guest images for general untrusted build and tool execution;
- macOS guests only where Apple hardware, licensing and framework support permit the declared workflow;
- immutable base image plus copy-on-write per-run disks;
- controlled virtual network interfaces with deny-by-default egress policy;
- no host directory, clipboard, camera, microphone, USB or credential sharing unless the capability grant explicitly names it;
- guest-agent mutual authentication, version pinning and attestation;
- snapshot, shutdown, force-stop and orphan-reconciliation behavior;
- remote disposable-node fallback where local virtualization cannot satisfy the required guest architecture or assurance.

POSIX process groups, resource limits and ordinary application sandboxing may provide lower assurance, but they must not be the sole boundary for workloads labeled hostile.

### 24.5.4 Linux isolated backend

Layer multiple kernel mechanisms instead of treating one control as a complete sandbox:

- user, mount, PID, network, IPC, UTS, cgroup and time namespaces where supported;
- cgroups v2 for resource accounting and termination;
- `no_new_privs`, capability dropping and a minimal UID/GID map;
- seccomp-BPF for syscall-surface reduction, with architecture-aware filters;
- Landlock or a declared LSM policy for filesystem/network restrictions where supported;
- read-only base filesystem, disposable overlay, explicit mounts and device allowlist;
- brokered network and credentials;
- rootless operation by default and no privileged container socket exposure;
- KVM-backed microVM or attested remote disposable node for the highest assurance tier.

The capability doctor must detect kernel, LSM, cgroup, namespace, KVM and distribution support at runtime. Missing controls reduce the advertised assurance level or block the run; they never produce a false full-isolation claim.

### 24.5.5 Common containment contract

Every platform backend must enforce and prove:

```text
immutable base image or declared trusted root
per-run writable layer
explicit host mounts
explicit egress and ingress
no ambient host credentials
short-lived brokered secret handles only
CPU, memory, process, disk, network and wall-clock budgets
complete process/VM termination
snapshot and deterministic teardown
artifact import/export scanning and hashes
guest/worker identity and protocol authentication
kernel/OS/backend version evidence
crash and orphan reconciliation
escape-attempt telemetry without secret content
```

The adversarial suite must include malicious archives, symlink/reparse attacks, fork/process bombs, kernel-surface probes, credential discovery, local-service probing, device access, clipboard/camera/microphone attempts, network exfiltration, guest-agent spoofing, shared-folder races and coordinator death. An independent security assessment must evaluate each platform's highest claimed tier.

## 24.6 Native fallback hierarchy

For desktop actions:

```text
application-specific structured API
→ OS accessibility/automation tree
→ keyboard shortcut or menu command with observed target
→ visual target with confidence and fresh screenshot
→ coordinate action only as final declared fallback
```

Every fallback step lowers assurance. Coordinate fallback requires before/after screenshots, display identity, scale factor, target region, confidence, and a semantic postcondition.

## 24.7 Mobile and web capability truth

Android and iOS do not provide arbitrary desktop-style host authority to ordinary applications. Kristin must therefore provide:

- native companion UI;
- notifications and approvals;
- share-sheet ingestion;
- camera/microphone/file capture with OS permission;
- local model execution where supported;
- Shortcuts/App Intents/Android intents and managed-device integrations where available;
- secure remote control of trusted desktop/headless nodes;
- device-local automation only through documented OS-supported APIs;
- exact capability status in the UI.

The web client provides review, chat, planning, monitoring, evidence, and remote-node operation. Browser sandbox limitations must be visible.

---

# 25. Owner Mode v3, identity, credentials, and sovereign operation

## 25.1 Owner profiles

Extend the access profile model:

```text
owner_user
  full authority of the signed-in OS account

owner_elevated
  owner_user plus per-operation or time-bounded native elevation

owner_unattended
  owner_user/elevated capabilities constrained by schedules, destinations,
  accounts, budgets, time, and transaction policies

owner_remote
  authority delegated to a specifically identified trusted node

owner_break_glass
  local interactive emergency profile with reauthentication, short expiry,
  no unattended use, and mandatory signed incident receipt
```

## 25.2 Maximum host authority

When enabled and available to the OS account, Owner Mode may:

- inspect and mutate any accessible file, directory, drive, share, removable medium, repository, archive, or application data;
- start interactive shells and arbitrary executables;
- install, update, and remove packages, SDKs, applications, drivers, services, and development toolchains;
- inspect and manage processes, services, schedules, environment, registry/preferences, windows, applications, clipboard, displays, audio, camera, printers, scanners, serial devices, and network interfaces;
- operate browser profiles, downloads, uploads, extensions, developer tools, and authenticated sessions;
- create and control containers, VMs, local clusters, databases, and model runtimes;
- use connected API accounts, cloud accounts, source-control accounts, communication channels, publishing accounts, and deployment targets;
- perform long-running and scheduled work;
- delegate scoped work to trusted local or remote workers;
- request OS-native elevation;
- run with approval policy `always`, `high_risk_only`, `policy_only`, or `never`.

The owner’s choice of authority is not silently narrowed. Reliability, evidence, and secret-handling controls remain active.

## 25.3 Identity broker

Create a unified identity model for:

```text
human owner
organization
local OS account
remote node
model/provider
connector publisher
connector account
browser profile
MCP server
A2A agent
plugin/skill
application recipe
release signer
content signer
```

Every identity has a stable ID, issuer, authentication method, trust level, status, revocation state, and evidence history.

## 25.4 Credential vault and lease model

Normal flow:

```text
agent requests operation
→ coordinator resolves account
→ policy checks profile, scope, destination, data labels and transaction limits
→ vault issues short-lived credential lease or signing handle
→ trusted adapter resolves secret at use time
→ adapter performs operation
→ lease expires or is consumed
→ model receives redacted receipt
```

Supported credential forms:

- API keys;
- OAuth access/refresh tokens;
- OIDC sessions;
- client certificates and private keys;
- SSH keys and short-lived SSH certificates;
- cloud workload/role sessions;
- database credentials;
- browser session handles;
- service-account keys;
- webhook signing secrets;
- package and release signing keys;
- content-provenance signing identities;
- hardware-backed keys through TPM, Secure Enclave, smart card, security key, HSM, or enterprise vault adapter.

A credential lease binds:

```text
credential/account ID
run/task/action ID
capability and provider
destination host/service
operation names
scopes
allowed data labels
maximum uses
expiry
interactive/unattended status
network origin
optional transaction policy
```

## 25.5 Break-glass secret reveal

To preserve genuine owner sovereignty, implement an optional `credential.reveal` capability with all of these invariants:

- local interactive UI only;
- `owner_break_glass` profile only;
- OS reauthentication or hardware-backed confirmation;
- exact credential selected by the owner;
- short on-screen display with automatic clearing;
- no clipboard by default;
- no model, plugin, remote worker, browser page, log, trace, crash report, or telemetry access;
- no unattended invocation;
- no bulk reveal;
- signed audit event records that a reveal occurred, but never the value;
- rate limits and immediate revocation control.

The feature is not required for ordinary API execution and must never become a workaround for missing connector engineering.

## 25.6 OAuth and account connection

Support:

- authorization code with PKCE;
- device authorization;
- client credentials and service accounts where appropriate;
- refresh-token rotation;
- exact redirect URI matching;
- state, nonce, issuer, audience, and token-binding validation;
- dynamic scopes with owner review;
- multiple accounts per provider;
- tenant/workspace selection;
- account health and reauthorization;
- revocation and disconnect;
- browser handoff without exposing tokens to page content;
- provider-specific consent receipts.

Apply OAuth 2.0 Security Best Current Practice and pin provider metadata used by production connectors.

## 25.7 Transaction policy

Owner Mode may perform consequential external operations only through a typed transaction policy. This is not a blanket prohibition; it is an explicit, owner-configurable authority record.

Example dimensions:

```text
operation class: publish | send | purchase | transfer | delete_cloud | deploy_prod
account IDs
allowed vendors/destinations
currency and amount ceilings
per-action/day/month limits
allowed recipients
time windows
required evidence
required human step-up
idempotency and reconciliation
rollback/cancellation strategy
```

MFA, passkeys, biometrics, CAPTCHA, and provider-native step-up challenges must never be bypassed. When the provider requires them, transition to human takeover. Pre-authorized API transactions may proceed within the signed policy and provider capabilities.

## 25.8 Elevation broker

Create `elevation.request` and `elevation.execute` contracts. The elevated helper must:

- be separately signed;
- accept only versioned structured operations;
- authenticate the caller over local IPC;
- verify a time-bounded grant;
- never accept arbitrary shell text unless the owner explicitly chose an elevated terminal capability;
- display the OS-native consent surface;
- record affected resources, expected effect, and rollback metadata;
- terminate after the operation or bounded session;
- reject replay and caller substitution.

## 25.9 Owner Mode tool contracts

```text
owner.profile.enable
owner.profile.disable
owner.profile.status
owner.policy.update
owner.kill
owner.pause
owner.resume
owner.snapshot.create
owner.snapshot.restore
identity.list
identity.inspect
credential.connect
credential.disconnect
credential.lease
credential.use
credential.reveal
oauth.authorize
oauth.refresh
oauth.revoke
request.sign
ssh.certificate.issue
cloud.session.assume
browser.profile.lease
transaction.policy.create
transaction.policy.evaluate
transaction.reconcile
elevation.request
elevation.session.open
elevation.session.close
```

## 25.10 Owner Mode release gate

Owner Mode is releaseable only when, on Windows, macOS, and Linux:

- the owner can execute outside project roots;
- terminal and desktop automation operate with native backends;
- credentials can be used without entering model context;
- elevation succeeds and fails honestly;
- the kill path works with frozen UI and descendants;
- unattended limits are enforced;
- external effects reconcile after crash;
- no secret appears in logs, traces, screenshots, browser observations, support bundles, or model requests;
- the operator guide matches tested behavior.

---

# 26. Universal connector and API plane

## 26.1 Objective

Kristin must connect to a new API from a machine-readable description or bounded interactive setup without requiring coordinator changes. “Any API” means a universal protocol and adapter architecture plus an honest fallback, not a claim that undocumented services can be perfectly inferred.

## 26.2 Required protocol families

First-class support:

```text
HTTP/HTTPS REST
OpenAPI 3.0, 3.1 and 3.2 descriptions
GraphQL schema introspection and stored operations
gRPC and Protocol Buffers, with optional server reflection
JSON-RPC
XML-RPC
SOAP/WSDL
OData where declared
WebSocket
Server-Sent Events
webhooks and callback receivers
multipart/form-data and resumable uploads
SFTP/SSH
SMTP/IMAP where account policy permits
SQL databases
selected NoSQL databases
message queues and event streams
MCP
A2A
browser automation fallback
command-line adapter fallback
custom signed connector SDK
```

Draft protocols must be isolated behind version adapters. Production behavior pins exact versions.

## 26.3 Connector architecture

```mermaid
flowchart LR
    SPEC[Description / Discovery / Wizard] --> IMPORT[Importer]
    IMPORT --> NORM[Canonical Connector IR]
    NORM --> REVIEW[Risk + Scope + Account Review]
    REVIEW --> REG[Signed Connector Registry]
    REG --> COMPILE[Operation Compiler]
    COMPILE --> AUTH[Identity and Credential Broker]
    AUTH --> EXEC[Protocol Adapter]
    EXEC --> OBS[Response Normalizer]
    OBS --> VERIFY[Schema + Semantic Verification]
    VERIFY --> RECEIPT[Evidence Receipt]
```

## 26.4 Connector manifest

Create `schemas/connector_manifest.v2.json`.

```json
{
  "schemaVersion": "2.0.0",
  "connectorId": "com.example.crm",
  "displayName": "Example CRM",
  "publisher": {"id": "publisher_...", "signature": "manifest-v2-ref"},
  "version": "1.0.0",
  "protocols": ["openapi-3.2", "webhook"],
  "destinations": ["api.example.com"],
  "accounts": {"multiAccount": true, "tenantAware": true},
  "auth": ["oauth2-pkce", "service-account"],
  "operations": [
    {
      "id": "contacts.create",
      "effect": "external_write",
      "idempotency": "provider_key",
      "requiredScopes": ["contacts.write"],
      "dataClasses": ["contact"],
      "verification": "read_after_write"
    }
  ],
  "webhooks": [{"id": "contact.updated", "signatureScheme": "hmac-sha256"}],
  "rateLimits": {"strategy": "headers_or_config"},
  "retention": {"provider": "declared", "local": "receipt_only"},
  "tests": {"conformanceBundle": "sha256:..."}
}
```

## 26.5 Connector import pipeline

For OpenAPI:

1. Fetch or open the description.
2. Resolve references with bounded retrieval and explicit base URIs.
3. validate supported specification version;
4. canonicalize servers, security schemes, operations, schemas, callbacks, and webhooks;
5. identify write/destructive operations;
6. infer pagination only when evidence supports it;
7. require owner correction for ambiguous auth, tenant, or idempotency behavior;
8. generate connector IR, typed schemas, fixtures, and documentation;
9. run mock and sandbox-account conformance;
10. sign and register the connector.

For GraphQL:

- import schema through introspection or supplied SDL;
- classify queries, mutations, subscriptions, and custom scalars;
- enforce depth, complexity, size, and timeout budgets;
- save approved operation documents by hash;
- support pagination conventions through explicit adapter rules;
- never expose unrestricted schema exploration to untrusted plugins by default.

For gRPC:

- import `.proto` descriptors or approved reflection output;
- support unary and streaming calls;
- preserve deadlines, metadata, status codes, and binary payload references;
- provide human-readable operation documentation;
- disable public reflection assumptions when the server does not expose it.

## 26.6 Authentication and secret use

The connector never owns raw long-lived credentials. It requests a lease from the credential broker. Account selection is explicit and durable. A model may choose among owner-authorized accounts only when policy allows it.

## 26.7 Reliability primitives

Every operation declares:

```text
read-only or effectful
retry class
idempotency support
provider request ID
rate-limit source
pagination model
long-running-operation model
reconciliation query
compensation or cancellation
partial-success semantics
expected billing dimension
```

Unknown effects are never blindly retried.

## 26.8 Webhook service

Support local and hosted webhook receivers with:

- random unguessable endpoints or authenticated routes;
- provider signature validation;
- replay windows;
- event deduplication;
- schema versioning;
- dead-letter queue;
- redaction;
- durable correlation to run/account/connector;
- optional response workflow;
- local tunneling only through explicitly configured providers.

## 26.9 Database connectors

Support typed, policy-aware connectors for PostgreSQL, MySQL/MariaDB, SQLite, SQL Server, and additional providers through plugins.

Required behavior:

- schema introspection;
- read-only and read-write roles;
- transaction boundaries;
- parameterized queries;
- migration planning;
- backup/checkpoint hooks;
- row/byte/time budgets;
- query plans where available;
- secrets through leases;
- no automatic production DDL without matching policy;
- result sets stored as bounded artifacts, not dumped into prompts.

## 26.10 Connector SDK

Provide a signed SDK with:

```text
connector init
manifest schema
protocol adapters
credential lease API
policy checks
pagination helpers
idempotency helpers
webhook verification
fixture server
record/replay with secret scrubbing
conformance runner
package/sign/publish
```

## 26.11 Universal fallback

When no formal connector exists:

1. use a generic HTTP operation with exact method, URL, headers, body schema, and credential lease;
2. use browser automation when the service exposes only a web UI;
3. use a CLI adapter when an official supported CLI exists;
4. record the successful interaction as a candidate connector recipe;
5. never silently transform an ad hoc call into a trusted reusable connector.

---

# 27. Application Factory and maximum-support vibe coding

## 27.1 Product outcome

A user can describe a product in natural language and receive a complete, tested, runnable, deployable, maintainable application with evidence linking the specification to implementation and behavior.

```text
idea
→ product specification
→ UX flows and visual system
→ architecture and data model
→ implementation plan
→ repository creation or modification
→ code generation and review
→ dependencies and migrations
→ tests
→ local runtime
→ browser/native inspection
→ security/accessibility/performance checks
→ package/deploy
→ health verification
→ documentation and handoff
```

## 27.2 Project specification

Create `schemas/application_project.v2.json` with:

```text
problem and target users
functional requirements
non-functional requirements
platforms and form factors
preferred/forbidden technologies
data model and retention
authentication/authorization
integrations
brand and design constraints
accessibility target
security/privacy requirements
localization
analytics/observability
budget and deployment targets
acceptance criteria
maintenance policy
```

The project specification is versioned. Code changes must link to requirement IDs.

## 27.3 Supported application classes

The architecture must support recipes for:

- static sites and landing pages;
- React/Next.js and other declared modern web applications;
- server-rendered and client-rendered web applications;
- API services in Node/TypeScript, Python, Go, Rust, Java/Kotlin, .NET, and additional plugin-defined stacks;
- relational database applications;
- event-driven and queue-based services;
- Flutter mobile and desktop applications;
- React Native applications;
- native Swift/SwiftUI and Kotlin/Compose applications through platform recipes;
- Tauri/Electron/native desktop applications;
- command-line tools;
- browser extensions;
- serverless functions;
- data pipelines and notebooks;
- ML inference services;
- automation bots and channel integrations;
- WordPress/CMS themes or plugins through dedicated recipes;
- packages, SDKs, libraries, plugins, and MCP/A2A services.

“Supported” means a recipe has passing creation, build, test, run, package, and upgrade fixtures. Other stacks remain experimental until they meet the same gate.

## 27.4 Recipe manifest

Create `schemas/application_recipe.v2.json`:

```json
{
  "recipeId": "web.next.postgres",
  "version": "2.0.0",
  "platforms": ["web", "server"],
  "toolchains": [{"id": "node", "version": "pinned"}],
  "features": ["auth", "database", "api", "tests", "observability"],
  "generatedFilesPolicy": "declared",
  "commands": {
    "bootstrap": ["..."],
    "format": ["..."],
    "lint": ["..."],
    "test": ["..."],
    "run": ["..."],
    "build": ["..."],
    "package": ["..."]
  },
  "readiness": [{"kind": "http", "target": "..."}],
  "qualityGates": ["unit", "integration", "e2e", "a11y", "security"],
  "upgradePolicy": "fixture-tested",
  "conformanceBundle": "sha256:..."
}
```

## 27.5 Repository intelligence

Implement:

- language and framework detection;
- build-system and workspace detection;
- dependency graph;
- symbol/index integration through LSP, compiler services, tree-sitter or native parsers;
- generated-file detection;
- ownership and code-area map;
- test discovery;
- environment and toolchain requirements;
- database migration state;
- API surface extraction;
- architecture map;
- source-to-runtime trace links;
- impact analysis before edits.

Indexes are derived and rebuildable. The agent must inspect actual source before editing.

## 27.6 Coding workbench

The Vibe Coding workspace must include:

```text
chat and specification
project tree
multi-file editor
symbol search
references and call hierarchy
diagnostics and quick fixes
Git status, diff and history
AI plan and active task
terminal tabs
running processes
browser/native preview
console and network
unit/integration/e2e tests
coverage
accessibility
performance
security findings
database inspector
API explorer
artifacts and evidence
one-click checkpoint/restore
```

## 27.7 Implementation loop

```text
inspect
→ propose bounded change
→ predict affected requirements/files/tests
→ checkpoint
→ edit
→ format/lint/typecheck
→ targeted tests
→ launch
→ observe runtime
→ verify acceptance criteria
→ review diff
→ commit or restore
```

The agent may auto-write in Owner Mode, but every patch still records intent, files, hashes, diagnostics, tests, and verification.

## 27.8 Design-to-code

Support:

- design tokens and component libraries;
- responsive constraints;
- image/reference-board ingestion;
- DOM/native layout observation;
- visual diff;
- semantic accessibility structure;
- theme generation;
- brand kit application;
- generated asset references;
- source mapping from rendered component to code;
- iterative screenshot-driven repair with bounded convergence.

Coordinates and screenshots may guide design, but generated UI must be verified through semantic structure and testable behavior.

## 27.9 Full-stack application requirements

Every production recipe should offer, as applicable:

- authentication and authorization;
- secrets/environment configuration;
- database schema and migrations;
- validation and error taxonomy;
- API documentation;
- rate limits and abuse controls;
- logging, metrics, and traces;
- health/readiness endpoints;
- unit, integration, end-to-end, and migration tests;
- accessibility;
- localization foundation;
- secure headers and dependency policy;
- backup/restore;
- deployment and rollback;
- developer and operator documentation.

## 27.10 Automated debugging and repair

The agent must correlate:

```text
compiler error
runtime exception
terminal output
browser console/network
trace/span
failing test
source map
recent diff
platform-specific behavior
```

It then creates a hypothesis, runs a discriminating test, applies the smallest fix, and re-verifies. Repeated identical outcomes trigger strategy escalation rather than infinite retries.

## 27.11 Application Factory tool contracts

```text
app.project.create
app.project.inspect
app.spec.create
app.spec.update
app.recipe.list
app.recipe.apply
repo.index
repo.search.symbol
repo.impact
code.edit
code.apply_patch
code.format
code.lint
code.typecheck
code.review
build.run
test.discover
test.run
test.coverage
app.run
app.readiness
app.preview
app.inspect_runtime
app.package
app.deploy
app.rollback
app.document
```

## 27.12 Application Factory gate

For each production recipe:

- create from clean machine on all applicable target platforms;
- restore locked dependencies;
- build without undeclared global tools;
- run tests;
- launch and prove readiness;
- perform at least one generated feature change;
- verify behavior through browser/native automation;
- package or deploy;
- upgrade a generated project from the previous recipe version;
- produce a complete evidence and maintenance bundle.

---

# 28. Modern content manufacturing plane

## 28.1 Objective

Kristin must operate as a reproducible content studio, not merely call generation APIs. Every content project has source material, editable state, render recipes, rights, provenance, variants, review status, and publication outcomes.

## 28.2 Content project model

Create `schemas/content_project.v2.json` and `schemas/asset_record.v2.json`.

```text
campaign/project ID
brief and target audience
brand kit and style constraints
channels and formats
source assets and rights
creative concepts
scripts/storyboards/outlines
generation and editing recipes
editable project files
rendered derivatives
localization and accessibility
review/approval states
publication destinations
analytics and learnings
provenance and content credentials
```

## 28.3 Asset graph

Assets form a directed provenance graph:

```text
source/imported asset
→ normalized working asset
→ generated or edited asset
→ composite/timeline/document
→ channel-specific render
→ published artifact
→ analytics record
```

Every edge records the operation, tool/provider/model, parameters or recipe hash, actor, timestamp, input/output hashes, rights/consent state, and verification.

## 28.4 Required content classes

First-class pipelines:

- Markdown, rich text, business documents, reports, letters, manuals, and ebooks;
- PDF generation, inspection, forms, redaction, accessibility, and archival variants;
- spreadsheets, models, dashboards, CSV/JSON/Parquet/SQLite datasets;
- presentations, speaker notes, handouts, and rendered slides;
- raster images, photo editing, compositing, masks, background removal, upscaling, and format conversion;
- vector graphics, diagrams, icons, logos, and SVG assets;
- audio recording, cleanup, transcription, translation, synthesis, mixing, mastering, and podcast packaging;
- video generation/import, editing, timeline composition, subtitles, dubbing, color/audio processing, thumbnails, and channel exports;
- animation and motion graphics through adapter-defined projects;
- 3D assets and renders through a plugin-defined scene/project interface;
- websites, email campaigns, social posts, ad variants, and content calendars;
- brand kits, template libraries, reusable components, and campaign packs.

## 28.5 Provider-neutral generation

Create provider adapters for:

```text
text generation
image generation
image editing
speech recognition
speech synthesis
voice conversion where lawful and consented
music/audio generation
video generation
video editing/rendering
translation
moderation/classification
upscaling/restoration
embedding/retrieval
```

Each provider descriptor records model/version, supported inputs/outputs, region/data policy, price model, latency, safety behavior, rights terms, watermark/provenance support, and benchmark results.

## 28.6 Deterministic media processing

Use deterministic local tools where possible for:

- FFmpeg-based probe, transcode, mux, demux, filters, subtitles, loudness, thumbnails, and format validation;
- image metadata, resize, crop, color conversion, compositing, and optimization;
- PDF rendering and validation;
- document/spreadsheet/presentation export;
- archive creation;
- checksums and media-quality metrics.

Generation and deterministic post-processing are separate steps in the asset graph.

## 28.7 Image workspace

Required capabilities:

```text
canvas and layers
masks and selections
crop/resize/rotate
background removal/replacement
inpaint/outpaint
text and vector overlays
batch variants
color and contrast tools
metadata inspection/removal
transparent exports
visual comparison
brand-safe templates
content credentials
```

## 28.8 Audio workspace

Required capabilities:

```text
waveform and multitrack timeline
record/import
speech-to-text with word timestamps
noise and silence handling
speaker segmentation
text-to-speech and approved voices
translation and dubbing
music/SFX tracks
loudness normalization
captions/transcript exports
podcast chapter and metadata packaging
```

Voice identities require consent and rights records. The system must distinguish a user-owned voice, licensed voice, provider voice, and unknown voice.

## 28.9 Video workspace

Required capabilities:

```text
media bin
storyboard and timeline
multitrack video/audio/subtitle
trim/split/ripple
transitions and overlays
screen recordings
generated shots and b-roll
captions, translation and dubbing
aspect-ratio variants
thumbnail generation
quality and loudness checks
hardware-accelerated render selection
render queue with resumable jobs
publication presets
```

The render recipe must be serializable and reproducible from retained inputs or explicitly identify unavailable external generations.

## 28.10 Documents, spreadsheets, and presentations

The agent must preserve editable source formats and validate rendered outputs.

Documents:

- styles, headings, tables, figures, citations, footnotes, headers/footers, page breaks, accessibility, tracked review state;
- export to supported office formats, Markdown/HTML, and PDF;
- visual page inspection before completion.

Spreadsheets:

- typed tables, formulas, named ranges, validation, pivots, charts, scenarios, imports/exports, and recalculation checks;
- formula error scans and cross-sheet lineage;
- no conversion of values to hard-coded results when formulas are required.

Presentations:

- master/theme, layouts, diagrams, tables/charts, speaker notes, image attribution, aspect-ratio checks, overflow detection, and rendered-slide review.

## 28.11 Brand and policy engine

A brand kit contains:

```text
logos and safe areas
colors and contrast rules
typography
voice and tone
approved/forbidden phrases
visual styles
image guidance
channel templates
legal disclaimers
localization rules
accessibility rules
```

The brand engine validates every derivative and records violations as evidence.

## 28.12 Rights, consent, and provenance

Every source or generated asset records:

- ownership/license/source URL or file;
- permitted uses and expiration;
- talent/voice/likeness consent where applicable;
- model/provider and terms snapshot;
- required attribution;
- sensitive-person or confidential-data labels;
- editing history;
- publication restrictions;
- content credential status.

Implement C2PA Content Credentials support using the pinned production specification, with 2.4 as the current reference baseline at the time of this roadmap. C2PA proves association and tamper evidence; it must not be represented as a truth detector.

## 28.13 Publishing and campaign automation

Publishing connectors may target CMSs, websites, social channels, email systems, video platforms, podcast hosts, DAM systems, and collaboration tools.

Required behavior:

- channel-specific validation;
- preview;
- schedule/time zone;
- account selection;
- alt text, captions, and accessibility;
- rights/consent checks;
- transaction/publishing policy;
- provider receipt and canonical URL/ID;
- edit/unpublish support where possible;
- analytics ingestion and experiment linkage.

## 28.14 Content tool contracts

```text
content.project.create
content.brief.update
asset.import
asset.inspect
asset.transform
asset.generate
asset.version
asset.compare
asset.approve
brand.kit.create
brand.validate
image.edit
image.generate
image.render
audio.transcribe
audio.synthesize
audio.mix
audio.render
video.storyboard
video.timeline.edit
video.render
subtitle.generate
subtitle.translate
document.create
document.render
pdf.inspect
pdf.render
spreadsheet.create
spreadsheet.recalculate
spreadsheet.validate
presentation.create
presentation.render
provenance.attach
provenance.validate
publish.preview
publish.schedule
publish.execute
publish.reconcile
analytics.ingest
```

## 28.15 Content release gate

A content pipeline is production-supported only when it:

- preserves editable source;
- renders deterministically where claimed;
- verifies format, dimensions, duration, streams, fonts, formulas, or pages as applicable;
- produces accessible variants;
- tracks rights and consent;
- prevents secret/private source leakage into unintended providers;
- records model/provider and recipe provenance;
- supports cancellation and resumable render queues;
- creates at least three channel variants from one project;
- republishes from saved state without manual reconstruction.

---

# 29. Native desktop, application, and device automation

## 29.1 Observation model

Create `desktop_observation.v2` containing:

```text
platform and session
active application/window
window list and bounds
accessibility/application tree
menus and commands
focused element
selected text where permitted
screens/displays and scale factors
pointer location
clipboard metadata
screen captures by display/window/region
permission state
observation timestamp and hash
```

Sensitive text may be hashed or redacted according to data policy.

## 29.2 Target signature

A desktop action target contains:

```text
application identity and code signature
process identity
window identity/title/class
accessibility path/role/name/identifier
bounding region
observation hash and age
expected state
fallback strategy
```

Before every action, re-resolve and reject stale or ambiguous targets.

## 29.3 Desktop actions

```text
desktop.element.invoke
desktop.element.set_value
desktop.element.select
desktop.element.expand
desktop.element.scroll
desktop.element.focus
desktop.menu.invoke
window.activate
window.move
window.resize
window.minimize
window.maximize
window.close
input.key
input.shortcut
input.text
input.pointer
input.drag
input.scroll
screen.capture
screen.record
```

Structured actions take precedence over synthetic input.

## 29.4 Application-specific adapters

For high-value applications, create signed adapters that expose structured operations beyond generic accessibility:

- browsers and developer tools;
- IDEs and editors;
- office suites;
- design and media applications;
- terminals;
- file managers;
- database clients;
- communication clients;
- cloud consoles;
- source-control clients.

Adapters may use public APIs, scripting interfaces, extensions, plugins, or accessibility. They must declare version compatibility and fail honestly after application updates.

## 29.5 Devices and peripherals

Create capability adapters for owner-authorized:

```text
printers and print queues
scanners
cameras
microphones and speakers
screen capture devices
serial ports
USB/HID devices
Bluetooth devices
removable storage
network shares
local network devices
mobile devices through ADB or Apple-supported development/management paths
IoT systems through connectors
```

Device operations record identity, permissions, data direction, and bytes. Firmware flashing, partitioning, or destructive storage actions require a typed destructive-device plan and recovery path.

## 29.6 Remote desktop and trusted nodes

Remote control must use node identity and capability grants, not anonymous screen sharing. A remote session records:

```text
node identity
user/session identity
display topology
control method
network path
clipboard/file transfer policy
screen/input evidence
start/end and takeover events
```

## 29.7 Desktop automation tests

Build deterministic native fixture applications for all three desktop OS families containing:

- standard controls;
- custom controls;
- menus/dialogs;
- virtualized lists;
- drag/drop;
- multiple windows;
- delayed changes;
- accessibility defects;
- disappearing/stale targets;
- sensitive fields;
- permission prompts;
- multiple monitors and scaling.

The fixture suite must prove semantic actions, fallbacks, stale-target rejection, screen evidence, kill, and user takeover.

---

# 30. Deployment, cloud, infrastructure, and fleet plane

## 30.1 Deployment targets

Support through recipes and connectors:

- local processes and services;
- Docker/OCI containers;
- local and remote virtual machines;
- Kubernetes and compatible orchestrators;
- static hosting/CDN;
- serverless functions and managed containers;
- managed relational and NoSQL databases;
- object storage;
- message queues;
- major cloud providers through official APIs/CLIs/SDKs;
- VPS and SSH-managed hosts;
- edge devices and trusted headless nodes;
- desktop/mobile app distribution pipelines.

## 30.2 Deployment transaction

```text
resolve environment and account
→ obtain short-lived cloud/deployment lease
→ inspect current state
→ compile desired state and change plan
→ estimate cost/risk
→ checkpoint or backup
→ apply in staging/preview
→ verify health/security
→ promote according to policy
→ observe metrics/logs/traces
→ retain rollback
→ reconcile provider state
```

## 30.3 Infrastructure as code

Support Terraform/OpenTofu, Pulumi, CloudFormation/Bicep and additional recipe-defined systems without making any one mandatory for all targets.

Required behavior:

- initialize and lock providers;
- validate and format;
- plan and parse machine-readable output;
- identify destroys/replacements;
- enforce environment and cost policy;
- apply with idempotency/reconciliation;
- save state according to backend policy;
- detect drift;
- generate diagrams and inventory;
- rollback or restore from known state where supported.

## 30.4 Source control and CI/CD

Support major Git hosting providers and local Git:

```text
repository create/clone/fork
branch/worktree
commit/sign/tag
pull/merge request
review/comments
checks and artifacts
secrets/environment references
release creation
issue/project automation
webhook events
```

Generated code must pass branch protection and may not bypass required human or automated gates unless the owner explicitly changes repository policy outside the agent task.

## 30.5 Preview environments

Every supported web/service recipe should provide ephemeral preview environments with:

- unique URL;
- isolated database/data fixture;
- expiry;
- cost limit;
- commit and run linkage;
- health checks;
- browser verification;
- automatic teardown;
- retained evidence.

## 30.6 Cost and quota engine

Before provider operations, estimate and enforce:

```text
model tokens and media generation
compute/runtime hours
storage and egress
API calls
managed service cost
third-party licenses
publishing spend
transaction amounts
```

Cost estimates are uncertain and must be labeled. Actual provider receipts update the run budget.

## 30.7 Fleet architecture

A trusted node has:

- device identity and attestation where available;
- signed agent build;
- platform capability manifest;
- owner/organization assignment;
- heartbeat and health;
- update channel;
- remote kill and revoke;
- workload queues;
- local policy overlay;
- evidence upload policy;
- offline behavior policy.

The fleet coordinator schedules by platform, architecture, installed tools, GPU, locality, data boundary, load, and cost.

## 30.8 Remote Owner Mode

Remote Owner Mode requires:

- explicit node enrollment;
- mutual authentication;
- owner-visible node identity;
- scoped or broad remote grant;
- encrypted channel;
- local node kill and pause;
- no hidden persistence;
- session recordings/evidence according to policy;
- revocation that stops new work immediately;
- reconciliation after disconnect.

## 30.9 Deployment tool contracts

```text
git.*
ci.workflow.inspect
ci.workflow.run
ci.artifact.fetch
container.build
container.run
container.inspect
container.publish
vm.create
vm.snapshot
vm.destroy
k8s.plan
k8s.apply
k8s.rollout
k8s.rollback
infra.plan
infra.apply
infra.destroy
cloud.account.inspect
cloud.resource.list
cloud.resource.create
cloud.resource.update
cloud.resource.delete
deploy.preview.create
deploy.promote
deploy.health
deploy.rollback
dns.update
certificate.issue
secret.remote.bind
fleet.node.enroll
fleet.node.revoke
fleet.task.dispatch
fleet.task.cancel
```

## 30.10 Deployment release gate

- preview, staging, and production paths are distinct;
- short-lived credentials are used where provider support exists;
- destructive plan parsing is tested;
- costs and quotas are enforced;
- health checks and rollback work;
- state and database backup paths are verified;
- remote nodes authenticate and revoke;
- no cloud secret is copied to prompts or ordinary logs;
- provider reconciliation handles timeouts and unknown outcomes.

---

# 31. Multimodal, realtime, and omnichannel chatbot

## 31.1 Conversation model

One conversation may include:

```text
text
voice input/output
images and screenshots
camera frames
screen share
files and folders
browser pages
terminal sessions
structured forms
data tables
application artifacts
live tool activity
human takeover
```

All modalities map to durable message parts with provenance, data labels, hashes, and retention.

## 31.2 Realtime voice

Required capabilities:

- push-to-talk, continuous, and wake-enabled modes where OS policy permits;
- local voice activity detection;
- streaming speech recognition;
- interruption/barge-in;
- streaming speech synthesis;
- device selection;
- echo/noise handling;
- transcript with timestamps and confidence;
- low-latency tool progress summaries;
- private/offline model option when installed;
- automatic pause when another application is using protected audio according to user settings.

## 31.3 Screen and camera understanding

The agent may use screen/camera input only under the selected profile and visible capture state. It must distinguish:

- semantic OS/browser observations;
- screenshots;
- live screen frames;
- camera frames;
- user-shared images.

Sensitive regions may be masked before provider upload. Local vision may be preferred by data-boundary policy.

## 31.4 Omnichannel gateways

Build connector-based gateways for:

- embedded web chat;
- desktop and mobile app;
- email;
- major work chat systems;
- community/messaging platforms;
- SMS/telephony providers;
- customer-support/helpdesk systems;
- CRM and ticketing systems;
- webhooks and custom channels.

A channel is production-supported only after identity mapping, message threading, attachments, edits/deletes, rate limits, retries, and provider receipts pass fixtures.

## 31.5 Identity and continuity

Map channel identities to Kristin identities through explicit linking. Do not merge two people based only on similar names or addresses. Memory and account access remain scoped to the authenticated identity and organization.

## 31.6 Customer-service mode

Optional service workflows support:

```text
knowledge-grounded answers
ticket classification
account lookup through connectors
draft or send according to policy
handoff to human
conversation summary
quality review
redaction
SLA timers
multilingual responses
analytics
```

The system must visibly distinguish generated suggestions from provider-committed actions.

## 31.7 Realtime tool contracts

```text
realtime.session.open
realtime.session.close
audio.device.list
audio.capture.start
audio.capture.stop
speech.transcribe
speech.synthesize
voice.interrupt
screen.share.start
screen.share.stop
camera.capture.start
camera.capture.stop
channel.connect
channel.disconnect
channel.message.receive
channel.message.send
channel.message.edit
channel.thread.handoff
channel.identity.link
```

## 31.8 Omnichannel gate

- interruption and cancellation work;
- voice latency and transcript quality meet measured targets;
- channel messages are deduplicated;
- identity is not guessed;
- attachments preserve hashes and data labels;
- no hidden camera/microphone/screen capture;
- send/publish actions obey transaction policy;
- human takeover works;
- complete conversation can be exported or deleted according to retention policy.

---

# 32. Model runtime, local inference, and hardware acceleration

## 32.1 Provider-neutral model registry

A model descriptor records:

```text
provider/model/version or immutable digest
modalities
context and output limits
tool/function protocol
structured-output reliability
data boundary and retention
regions
cost and rate limits
latency/throughput benchmarks
approved roles and task classes
safety behavior
local hardware requirements
license and redistribution
quantization
known defects
```

## 32.2 Model roles

Support separate roles for:

```text
planner
executor
code specialist
browser observer
native desktop observer
researcher
extractor
verifier
security reviewer
image creator/editor
audio transcriber/synthesizer
video planner/generator
embedding/reranking
realtime conversation
```

A single model may fill multiple roles only when its benchmark supports them; the policy engine still separates authority and verification.

## 32.3 Local inference architecture

Provide adapters for local runtimes rather than hard-coding one engine. The first architecture should support:

- CPU fallback;
- NVIDIA CUDA/TensorRT where installed;
- Windows DirectML and compatible accelerators;
- Apple Core ML/Metal paths;
- Intel OpenVINO/oneDNN paths;
- AMD-supported paths selected through maintained runtimes;
- Qualcomm/Android acceleration where supported;
- ONNX Runtime execution providers;
- plugin adapters for llama.cpp, vLLM, or other owner-selected runtimes;
- WebGPU/WASM for browser-local narrow models where practical.

The hardware detector must benchmark actual models rather than select solely from vendor name.

## 32.4 Model artifact management

Model files are large, licensed artifacts. Record:

```text
source and license
digest
format and quantization
runtime compatibility
hardware requirements
size
provenance
safety/evaluation report
download resume state
storage location
update/revocation policy
```

No model is auto-downloaded without policy, disk budget, and license record.

## 32.5 Routing policy

Routing considers:

- task role and benchmark;
- owner preference;
- data boundary;
- local/cloud availability;
- latency and cost;
- context size;
- required modality;
- tool/structured-output reliability;
- region;
- current provider health;
- fallback constraints.

Fallback may not cross a stricter data boundary without explicit policy.

## 32.6 Context compiler

Build deterministic context selection with:

```text
requirement/task packet
trusted system and policy instructions
relevant source slices
schemas and tool contracts
recent evidence
memory with provenance
untrusted web/project/tool sections clearly labeled
budgeted compression
citation handles
```

The context compiler records why each item was included and excludes raw secrets by default.

## 32.7 Training and adaptation

Optional local or provider-supported adaptation may include prompt/version tuning, retrieval tuning, adapters, or fine-tuning. Every adapted model requires:

- licensed dataset and consent;
- train/eval split;
- provenance;
- privacy review;
- benchmark against baseline;
- rollback;
- signed model card;
- no automatic promotion based only on training loss.

## 32.8 Model gate

- exact model identity is logged;
- structured protocols pass fuzzing;
- task-role benchmarks meet thresholds;
- local runtime survives missing/unsupported accelerators;
- model downloads verify digest;
- provider outage fallback is tested;
- data-boundary routing is enforced;
- no model can grant capabilities;
- verifier catches false completion and unsupported claims.

---

# 33. Knowledge, memory, personalization, and organizational intelligence

## 33.1 Memory classes

```text
working memory
run memory
project memory
personal preference memory
account/connector memory
organizational knowledge
procedural recipes
failure/replay memory
published artifacts and analytics
```

Each item has provenance, owner, scope, sensitivity, confidence, expiry, and deletion behavior.

## 33.2 Admission policy

Memory is admitted only after:

- source identity and scope are known;
- data labels allow storage;
- instruction-like content is separated from facts;
- failed/adversarial runs are quarantined;
- duplicates/conflicts are handled;
- the user or policy permits the memory class;
- retention and deletion are defined.

Web pages, terminal output, repositories, and messages cannot promote themselves to trusted instruction memory.

## 33.3 Knowledge ingestion

Support files, folders, repositories, websites, email, calendars, documents, databases, channels, and APIs through connectors. Preserve raw source versions and citations. Extracted claims remain linked to source spans or structured records.

## 33.4 Retrieval

Use hybrid retrieval:

```text
metadata and permission filter
→ lexical retrieval
→ optional semantic retrieval
→ graph/relationship expansion
→ freshness and trust ranking
→ context budget selection
```

No vector index is the source of truth. Deleted or revoked source items must be excluded promptly and removed from derived indexes.

## 33.5 Personalization

User preferences may cover tone, formatting, tools, coding stacks, brand, accessibility, language, notification, risk tolerance, accounts, and schedules. The UI must allow inspect, edit, pin, export, and delete.

## 33.6 Knowledge and memory gate

- cross-user and cross-organization leakage tests pass;
- deletion propagates to indexes and caches;
- citations reopen the correct source version;
- prompt injection cannot become policy;
- stale memories are labeled;
- users can inspect why a memory influenced a run;
- encrypted backup/restore and device sync are tested where enabled.

---

# 34. Expanded master backlog P11–P20

P11–P19 may overlap after their dependencies are complete. P20 is the only final maximum-capability GA phase. Every task inherits the synchronized Windows/macOS/Linux rule when it has desktop impact.

## P11 — Omni-platform native parity and desktop control

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P11-001` | Approve omni-platform ADR set | `P1-001,P2-004` | ADRs for native hosts, platform adapters, parity semantics, mobile/web truth, architecture matrix | No implementation-critical ambiguity remains and no mandatory desktop OS is deferred. |
| `P11-002` | Create platform support manifest | `P11-001` | Schema, generator, UI, release integration | Manifest is generated from tests for Windows, macOS, and Linux. |
| `P11-003` | Implement Windows native host v1 | `P1-012,P11-001` | ConPTY, Job Objects, UIA, credential, window, service, screen baseline | Windows conformance and hostile lifecycle fixtures pass. |
| `P11-004` | Implement macOS native host v1 | `P1-012,P11-001` | PTY, process lifecycle, AX, Keychain, NSWorkspace, TCC baseline | Signed helper passes macOS fixtures and consent recovery. |
| `P11-005` | Implement Linux native host v1 | `P1-012,P11-001` | PTY, cgroup/systemd, AT-SPI, portals, Secret Service baseline | GNOME/KDE and Wayland/X11 declared fixtures pass. |
| `P11-006` | Shared native conformance runner | `P11-003,P11-004,P11-005` | One suite against all platform adapters | Semantic result and error compatibility report is green. |
| `P11-007` | Native desktop observation v2 | `P11-006` | Window/accessibility/screen observations and hashes | Deterministic fixture observations pass on all three. |
| `P11-008` | Native desktop action v2 | `P11-007` | Structured actions plus fallback ladder | Actions verify postconditions and reject stale targets. |
| `P11-009` | Peripheral/device foundation | `P11-006` | Printers, scanner/camera/mic/device inventory contracts | Permission, unplug, and data-direction fixtures pass. |
| `P11-010` | Synchronized native parity gate | `P11-008,P11-009,P2-013` | Cross-platform evidence report | No critical parity gap remains for declared Owner Mode capabilities. |
| `P11-011` | Windows isolated-untrusted backend | `P11-003,P1-003,P1-004` | Restricted/AppContainer tiers plus disposable VM or attested remote-node path | Hostile containment fixtures pass at each advertised Windows assurance tier. |
| `P11-012` | macOS isolated-untrusted backend | `P11-004,P1-003,P1-004` | Virtualization-framework disposable worker plus lower-tier process restriction | Hostile containment, teardown, network, mount and consent fixtures pass. |
| `P11-013` | Linux isolated-untrusted backend | `P11-005,P1-003,P1-004` | Namespaces, cgroups, seccomp, Landlock/LSM and microVM/remote high-assurance path | Runtime-detected tiers and hostile containment fixtures pass. |
| `P11-014` | Shared isolation conformance and escape suite | `P11-011,P11-012,P11-013` | One cross-platform containment corpus and assurance report | Filesystem, process, network, credential, IPC, device, resource and kill boundaries pass on all three OSs. |
| `P11-015` | Synchronized Owner-plus-isolation platform gate | `P11-010,P11-014` | Combined platform capability and assurance manifest | Windows, macOS and Linux each pass Owner Mode parity and the highest declared isolated-untrusted tier with no silent downgrade. |

### P11 exit gate

- Windows, macOS, and Linux native hosts pass one shared semantic suite.
- Desktop observation/action, PTY, lifecycle, credentials, elevation, and kill work on all three.
- Each desktop OS exposes a tested `isolated_untrusted` backend with an explicit assurance tier and a high-assurance VM/microVM or attested remote-node path.
- Hostile-workload fixtures cannot access undeclared host files, credentials, network destinations, IPC endpoints, devices, clipboard, camera, or microphone.
- Platform and containment matrices are generated from evidence, not hand-authored.

## P12 — Identity, credential sovereignty, and universal connectors

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P12-001` | Identity domain v3 | `P1-005,P11-002` | Human, node, account, publisher, model, connector, signer identities | Identity substitution and revocation fixtures pass. |
| `P12-002` | OS-native credential vault adapters | `P1-009,P11-003,P11-004,P11-005` | Windows DPAPI/Credential, macOS Keychain, Linux Secret Service adapters | Secret CRUD, locked vault, migration, and redaction tests pass. |
| `P12-003` | Credential lease service | `P12-001,P12-002,P1-003` | Short-lived operation-bound handles | Wrong run/destination/scope/use/expiry is rejected. |
| `P12-004` | Owner break-glass reveal | `P12-002,P2-001` | Local interactive reauth flow | Value never reaches model/log/telemetry and unattended calls fail. |
| `P12-005` | OAuth account connection framework | `P12-003` | PKCE, device, service account, refresh, revoke, multi-account | Provider fixtures cover mix-up, redirect, state, rotation, expiry. |
| `P12-006` | Connector IR and manifest v2 | `P1-006,P12-001` | Signed schema and registry | Modified or untrusted connector fails registration. |
| `P12-007` | OpenAPI 3.x importer | `P12-006,P12-005` | 3.0/3.1/3.2 parsing, generated operations and fixtures | Reference, auth, callback, upload, and malformed specs pass. |
| `P12-008` | GraphQL connector | `P12-006,P12-005` | Schema import, approved operations, limits | Query/mutation, custom scalar, complexity and auth fixtures pass. |
| `P12-009` | gRPC/Protobuf connector | `P12-006,P12-005` | Descriptor/reflection import, unary/streaming | Deadlines, metadata, status, and binary artifacts pass. |
| `P12-010` | Generic protocol adapters | `P12-006` | JSON-RPC, SOAP/WSDL, WebSocket, SSE, webhook, SFTP/SSH baseline | Shared reliability and security fixtures pass. |
| `P12-011` | Database connector foundation | `P12-003,P12-006` | SQL introspection, typed query, transaction and migration contracts | PostgreSQL/MySQL/SQLite/SQL Server fixtures pass. |
| `P12-012` | Connector SDK and conformance kit | `P12-007,P12-008,P12-009,P12-010` | Scaffolder, mock server, record/replay, sign/package | A third-party sample connector passes without core changes. |
| `P12-013` | Transaction policy service | `P12-003,P1-004` | Publish/send/purchase/deploy/delete policy | Limits, step-up, idempotency and reconciliation tests pass. |
| `P12-014` | Connector workspace UI | `P12-005,P12-012` | Accounts, scopes, operations, health, logs, revoke | User can inspect exact account and permission for every call. |

### P12 exit gate

- Credentials are used through leases on all three desktop OSs.
- OpenAPI, GraphQL, gRPC, generic HTTP/webhook, and SQL connectors work.
- One external connector can be built and signed without coordinator modification.

## P13 — Application Factory and advanced vibe coding

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P13-001` | Application project/spec schemas | `P6-004,P5-006` | Requirements, architecture, acceptance and lineage model | Requirement-to-code/test links survive round trips. |
| `P13-002` | Recipe registry v2 | `P12-006` | Signed application recipe manifests | Changed recipes are detected and versioned upgrades work. |
| `P13-003` | Repository intelligence v2 | `P3-012,P6-003` | Symbols, dependencies, tests, generated files, impact map | Multi-language fixture repos produce correct maps. |
| `P13-004` | Code editing transaction engine | `P13-003,P2-010` | Multi-file patch, checkpoint, conflict, restore | Injected failure restores or marks exact partial state. |
| `P13-005` | Web full-stack golden recipes | `P13-002,P13-004,P3-013` | Static, modern frontend, API+database recipes | Clean creation/change/test/preview/deploy fixtures pass. |
| `P13-006` | Service/API golden recipes | `P13-002,P13-004,P12-011` | TypeScript, Python, Go, Rust, Java/.NET declared recipes | Build/test/package/health/upgrade fixtures pass. |
| `P13-007` | Flutter cross-platform app recipe | `P13-002,P11-010` | Windows/macOS/Linux/web/mobile project recipe | Shared app builds and smoke tests on declared targets. |
| `P13-008` | Native/mobile recipes | `P13-002` | SwiftUI, Kotlin/Compose, optional React Native recipes | Platform CI builds, tests, and emulator/device smoke pass. |
| `P13-009` | Desktop/CLI/extension recipes | `P13-002,P11-010` | Tauri/Electron/CLI/browser extension recipes | Package and behavior fixtures pass. |
| `P13-010` | Design-to-code loop | `P3-015,P13-004` | Tokens, components, screenshot/semantic diff, repair | Responsive and accessibility fixtures converge. |
| `P13-011` | Automated debug and repair | `P13-003,P8-009` | Correlated error/trace/test/source repair loop | Hidden bug corpus improves without repeated-loop failure. |
| `P13-012` | Application deployment handoff | `P13-005,P13-006` | Preview, docs, runbook, rollback bundle | Generated apps reach verified preview from clean checkout. |
| `P13-013` | Vibe Coding workspace v2 | `P5-004,P13-003,P13-010` | Integrated editor/runtime/test/evidence UX | End-to-end keyboard workflow passes. |
| `P13-014` | Application Factory benchmark | `P13-005` through `P13-013` | Hidden/public multi-stack corpus | Success, regression, cost, latency, and false-completion targets pass. |

### P13 exit gate

- At least six materially different application recipes pass full lifecycle tests.
- Windows/macOS/Linux Flutter recipe has synchronized evidence.
- Generated apps are tested, previewed, packaged/deployed, and documented.

## P14 — Content manufacturing and publishing

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P14-001` | Content project and asset graph | `P4-011,P12-006` | Schemas, object storage, lineage and versions | Derived assets reproduce from retained recipes/inputs. |
| `P14-002` | Provider-neutral generation adapters | `P6-001,P14-001` | Text/image/audio/video generation interfaces | Two fixture providers per modality pass shared contracts where available. |
| `P14-003` | Deterministic media worker | `P14-001,P11-010` | FFmpeg/image/PDF probe and render jobs | Cross-platform media fixtures produce validated outputs. |
| `P14-004` | Image workspace | `P14-002,P14-003` | Layer/mask/edit/generate/batch/compare | Saved project reopens and renders variants. |
| `P14-005` | Audio workspace | `P14-002,P14-003` | Transcribe/synthesize/mix/render/transcript | Timing, loudness, captions, consent and export tests pass. |
| `P14-006` | Video workspace | `P14-002,P14-003` | Storyboard/timeline/subtitles/dubbing/render queue | Interrupted render resumes and outputs validate. |
| `P14-007` | Document/PDF pipeline | `P14-001` | Editable docs, pagination, accessibility, PDF validation | Rendered page inspection and structure checks pass. |
| `P14-008` | Spreadsheet pipeline | `P14-001` | Formulas, models, charts, recalculation and exports | Formula lineage/error and reopen tests pass. |
| `P14-009` | Presentation pipeline | `P14-001` | Themes/layouts/notes/render/overflow checks | Slides render without overflow and remain editable. |
| `P14-010` | Brand policy engine | `P14-004,P14-007,P14-009` | Brand kit, validation and repair | Cross-format brand violations are detected. |
| `P14-011` | Rights and consent ledger | `P12-001,P14-001` | License, attribution, voice/likeness consent model | Restricted asset cannot publish outside policy. |
| `P14-012` | C2PA provenance | `P1-006,P14-001` | Create/validate content credentials for supported formats | Tamper, missing trust, version and derivation tests pass. |
| `P14-013` | Publishing connector layer | `P12-012,P12-013,P14-010` | Preview/schedule/publish/reconcile/analytics | Fixture channels publish, edit/unpublish and return receipts. |
| `P14-014` | Campaign Factory benchmark | `P14-004` through `P14-013` | One brief to multi-channel campaign corpus | Three+ variants, rights, brand, accessibility and provenance gates pass. |

### P14 exit gate

- Image, audio, video, document, spreadsheet, and presentation projects are editable and reproducible.
- Publishing is account-, rights-, and transaction-policy aware.
- Content provenance and channel receipts are retained.

## P15 — Native application/device automation and remote operation

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P15-001` | Desktop observation/action v3 schemas | `P11-008` | Cross-platform semantic tree and target signatures | Golden vectors and stale-target tests pass. |
| `P15-002` | Windows advanced automation | `P15-001` | UIA events, menus, virtualized controls, multi-display | Native fixture suite passes. |
| `P15-003` | macOS advanced automation | `P15-001` | AX events, menus, Spaces/display/TCC states | Native fixture suite passes. |
| `P15-004` | Linux advanced automation | `P15-001` | AT-SPI events, portal/Wayland/X11 strategies | GNOME/KDE fixture suite passes. |
| `P15-005` | Visual fallback engine | `P15-002,P15-003,P15-004` | Confidence, display scaling, region tracking and postconditions | Low-confidence and changed-layout actions pause. |
| `P15-006` | Application adapter SDK | `P12-012,P15-001` | Plugins for app-specific structured actions | Sample IDE/office adapter passes conformance. |
| `P15-007` | Device and peripheral service | `P11-009` | Print/scan/camera/mic/serial/USB inventory and actions | Permission, disconnect and data evidence pass. |
| `P15-008` | Screen/audio recording service | `P11-010` | Visible capture state, regions, devices, privacy masks | Hidden capture and revoked-permission tests fail safely. |
| `P15-009` | Remote desktop trusted-node protocol | `P1-012,P12-001,P15-001` | Encrypted session, screen/input/file policy, receipts | Node substitution, disconnect and revoke tests pass. |
| `P15-010` | Native automation benchmark | `P15-005,P15-006,P15-007,P15-009` | Cross-OS real-app and fixture corpus | Target success and zero unintended-action threshold pass. |

## P16 — Deployment, cloud, infrastructure, and fleet

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P16-001` | Deployment target contracts | `P12-006,P13-012` | Environment, plan, apply, health, rollback schemas | Golden vectors pass across adapters. |
| `P16-002` | OCI/container pipeline | `P16-001` | Build, scan, SBOM, run, publish | Reproducible image fixture passes. |
| `P16-003` | Infrastructure-as-code adapters | `P16-001,P12-013` | Terraform/OpenTofu and one additional adapter | Plan/destroy/change parsing and policy tests pass. |
| `P16-004` | Cloud provider foundation | `P12-012,P16-001` | Account/resource/role session adapters | Sandbox accounts pass create/update/delete/reconcile. |
| `P16-005` | Preview environment service | `P13-012,P16-002,P16-004` | Ephemeral URL/data/expiry/teardown | Leak and orphan-resource tests pass. |
| `P16-006` | Database deployment and backup | `P12-011,P16-004` | Provision, migrate, backup, restore | Restore verification passes after injected failure. |
| `P16-007` | DNS/TLS and edge delivery | `P16-004` | DNS plan, certificate, CDN/cache adapters | Propagation/reconciliation and rollback tests pass. |
| `P16-008` | Cost/quota engine | `P12-013,P16-004` | Estimate, reserve, actual cost and halt | Budget overrun fixtures stop before new effects. |
| `P16-009` | Node identity and enrollment | `P12-001,P1-006` | Signed enrollment, capability manifest, revoke | Unknown/revoked nodes cannot receive work. |
| `P16-010` | Fleet scheduler | `P16-009,P6-011` | Platform/GPU/locality/data-boundary scheduling | Jobs route to compatible nodes and recover. |
| `P16-011` | Remote Owner Mode | `P15-009,P16-009,P12-013` | Broad/scoped remote grants and local kill | Disconnect/revoke/unknown-effect tests pass. |
| `P16-012` | Deployment/fleet benchmark | `P16-002` through `P16-011` | Preview→production→rollback and multi-node corpus | Reliability, cost, security and evidence targets pass. |

## P17 — Multimodal realtime and omnichannel

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P17-001` | Multimodal message schema v2 | `P6-004,P14-001` | Text/audio/image/video/screen/file/data parts | Round-trip, redaction and retention tests pass. |
| `P17-002` | Realtime session engine | `P6-011,P17-001` | Duplex events, interruption, cancellation, tool progress | Network loss and barge-in fixtures pass. |
| `P17-003` | Speech recognition adapters | `P18-003` | Local/cloud streaming transcription | Accuracy/latency/privacy benchmark passes. |
| `P17-004` | Speech synthesis adapters | `P18-003,P14-011` | Streaming voices and consent metadata | Interrupt, device, consent and cache tests pass. |
| `P17-005` | Screen/camera live context | `P15-008,P17-001` | Visible capture, frame sampling, masks | Revocation and sensitive-region tests pass. |
| `P17-006` | Channel gateway SDK | `P12-012,P17-001` | Messages, threads, attachments, identity and receipts | Sample channel passes conformance. |
| `P17-007` | Work chat/email channels | `P17-006,P12-013` | Declared production connectors | Threading, retry, send policy and attachment tests pass. |
| `P17-008` | Customer-support workflows | `P17-006,P18-009` | Knowledge, ticket, handoff, SLA, QA | Human handoff and grounded answer corpus pass. |
| `P17-009` | Realtime/omnichannel UI | `P17-002,P17-005,P17-006` | Voice, live context, channel and takeover UX | Accessibility and hidden-capture checks pass. |
| `P17-010` | Realtime benchmark | `P17-003` through `P17-009` | Latency, quality, interruption and message reliability corpus | Category thresholds pass. |

## P18 — Local models, hardware acceleration, and advanced intelligence

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P18-001` | Model descriptor v3 | `P6-001` | Multimodal/local/cloud/hardware/license fields | Invalid and changed descriptors are rejected. |
| `P18-002` | Hardware capability detector | `P11-002` | CPU/GPU/NPU/memory/storage benchmark inventory | Results match native probes on all three desktop OSs. |
| `P18-003` | Local runtime adapter interface | `P18-001,P18-002` | Load/generate/stream/cancel/metrics contract | CPU reference runtime passes shared suite. |
| `P18-004` | ONNX Runtime adapter | `P18-003` | Execution-provider discovery and fallback | CPU plus available accelerator fixtures pass. |
| `P18-005` | Local LLM runtime adapters | `P18-003` | At least two plugin runtime adapters | Model load, tool/JSON, cancel and memory limits pass. |
| `P18-006` | Local speech/vision adapters | `P18-003,P17-001` | Offline transcription/vision baseline | Data-boundary and quality tests pass. |
| `P18-007` | Model artifact manager | `P18-001` | License, digest, resume, storage, revoke | Corrupt/changed/unlicensed artifacts fail. |
| `P18-008` | Advanced model router | `P18-001,P6-014` | Cost/latency/privacy/hardware/health routing | Failure and boundary fallback tests pass. |
| `P18-009` | Context compiler v3 | `P6-005,P4-013,P6-010` | Provenance labels, retrieval, compression and audit | Injection and secret exclusion fixtures pass. |
| `P18-010` | Model adaptation pipeline | `P18-007` | Dataset/model card/eval/promotion/rollback | Adapted model cannot promote without benchmark. |
| `P18-011` | Multimodal model benchmark | `P18-004` through `P18-010` | Code/browser/desktop/research/content/realtime corpus | Supported role matrix is generated from results. |

## P19 — Web/mobile companions, headless nodes, and extensible ecosystem

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P19-001` | Web control plane | `P5-004,P16-009` | Chat, runs, evidence, approvals, remote tools | Browser security and session tests pass. |
| `P19-002` | Android companion | `P17-009,P16-009` | Chat, capture/share, approvals, notifications, local/remote tools | Device/emulator lifecycle and permission tests pass. |
| `P19-003` | iOS/iPadOS companion | `P17-009,P16-009` | Chat, capture/share, approvals, notifications, local/remote tools | Simulator/device and OS-permission tests pass. |
| `P19-004` | Headless node packages | `P16-009,P9-003` | Windows/Linux/macOS service packages | Install/update/revoke/kill tests pass. |
| `P19-005` | Capability/plugin SDK v3 | `P7-009,P11-002,P12-006,P13-002,P14-002,P18-001` | Native, connector, content, model and recipe extension points | One extension of each class passes without core changes. |
| `P19-006` | MCP version adapters | `P7-001,P19-005` | Stable pinned adapter plus 2026-07-28 adapter after final publication | Conformance suites pass without draft lock-in. |
| `P19-007` | A2A 1.0 production adapter | `P7-005,P19-005` | Version negotiation, tasks, artifacts, auth, delegation | Official conformance and adversarial tests pass. |
| `P19-008` | Extension registry and marketplace | `P19-005,P1-006` | Trust, permissions, install/update/revoke and review | Modified/revoked extensions stop loading. |
| `P19-009` | Multi-device continuity | `P19-001,P19-002,P19-003` | Encrypted sync of allowed conversation/run state | Conflict, revoke and cross-account leakage tests pass. |
| `P19-010` | Ecosystem conformance lab | `P19-005` through `P19-009` | Public fixtures and certification reports | Third-party implementations can reproduce results. |

## P20 — Maximum-capability beta, RC, and synchronized GA

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P20-001` | Capability freeze and inventory | `P11-015,P12-014,P13-014,P14-014,P15-010,P16-012,P17-010,P18-011,P19-010,P21-024,P22-018,P23-024,P24-012` | Generated support matrix and exact exclusions, including provider/API/browser/local route, consumer experience, tool/skill/capability, roadmap-integrity, and no-SQL storage evidence | No claimed capability, provider route, Gold Skill, consumer promise, or platform behavior lacks evidence. |
| `P20-002` | Tri-platform private beta | `P20-001,P9-005,P9-006,P9-007` | Equal Windows/macOS/Linux cohort and support | SLOs hold independently on each OS. |
| `P20-003` | Mobile/web/headless beta | `P19-001,P19-002,P19-003,P19-004` | Companion/node cohort | Capability truth and remote revoke SLOs hold. |
| `P20-004` | Full external security assessment | `P20-002,P20-003,P8-014` | Owner, credentials, connectors, desktop, content, cloud, fleet audit | Zero unresolved critical/high findings. |
| `P20-005` | Cross-platform parity closeout | `P20-002` | Per-capability parity report | No mandatory desktop capability is missing or silently degraded. |
| `P20-006` | Maximum-capability RC freeze | `P20-004,P20-005` | Immutable versions, models, connectors, recipes, docs | Only blocker fixes may enter. |
| `P20-007` | Thirty-day synchronized RC soak | `P20-006` | Continuous tri-OS, mobile/web, node, update and benchmark evidence | Every mandatory SLO passes per platform. |
| `P20-008` | Disaster and compromise drills | `P20-006` | Key, connector, model, plugin, cloud, profile, node, data and bad-update drills | Runbooks succeed and evidence is retained. |
| `P20-009` | Final legal/privacy/accessibility/support closeout | `P20-007` | Human approvals and support readiness | Required sign-offs are recorded. |
| `P20-010` | Maximum-capability GA decision | `P20-007,P20-008,P20-009` | Signed owner/release-auditor decision | Windows, macOS, and Linux all pass; no partial desktop GA. |
| `P20-011` | Staged synchronized rollout | `P20-010` | Platform-balanced cohorts and automatic halt | Any platform halt pauses the common rollout. |
| `P20-012` | Continuous capability evolution | `P20-011` | Monthly provider/platform/model review and quarterly drills | New capability enters only through descriptor, tests, and evidence. |

### P20 final exit gate

- Windows, macOS, and Linux pass the same applicable capability and release gates.
- Owner Mode, credentials, connectors, application generation, content manufacturing, native automation, deployment/fleet, realtime chat, local models, web/mobile companions, ecosystem extensions, Gold Skills, Skill Studio, consumer onboarding, repair, support, and the no-SQL local authority have production evidence.
- All artifacts are signed, installable, updateable, rollbackable, attributable, and verified on the declared minimum and recommended hardware profiles.
- Final product claims are generated from the capability registry, skill registry, roadmap manifest, and evidence store.
- A representative non-technical user can complete primary workflows in Simple Mode without viewing logs, schemas, terminals, provider internals, or implementation architecture.

---

# 35. AI execution protocol v3

## 35.1 Purpose

This section is written so a new implementation AI can enter the repository with no conversational history and execute the next task safely and productively.

## 35.2 Mandatory startup sequence

The AI must:

1. Read this roadmap.
2. Read `docs/roadmap/STATUS.md`, `DECISIONS.md`, `RISKS.md`, `METRICS.md`, `RELEASE_GATES.md`, and `HANDOFF.md`.
3. Read all ADRs referenced by the selected task.
4. Inspect the repository, branch, Git status, toolchain manifest, platform manifest, and most recent evidence.
5. Run the baseline command for the affected subsystem before editing.
6. Select exactly one `READY` task whose dependencies are `DONE`.
7. Materialize or update its task packet under `tasks/active/`.
8. State acceptance criteria and platform lanes.
9. Implement the minimum coherent change.
10. Run targeted tests and the required verification tier.
11. Create evidence and independent review artifacts.
12. Update status and handoff.
13. Stop. Do not silently begin the next task.

## 35.3 Task selection algorithm

```text
load STATUS
→ reject tasks with incomplete dependencies
→ reject tasks blocked by ADR/tool/account/human action
→ prefer current phase and critical path
→ prefer task with reproducible local tests
→ acquire task lock
→ mark IN_PROGRESS with branch and actor
→ execute one packet
```

When two AIs work concurrently, they must not edit the same contract or migration without an explicit coordination task.

## 35.4 Platform-aware task packet

````markdown
# <TASK-ID> — <Title>

## Objective
One observable result.

## Dependencies
- ...

## Platform impact
| Platform | Lane | Backend/files | Required tests |
|---|---|---|---|
| Windows | required/unchanged/N-A | ... | ... |
| macOS | required/unchanged/N-A | ... | ... |
| Linux | required/unchanged/N-A | ... | ... |
| Web | ... | ... | ... |
| Android | ... | ... | ... |
| iOS | ... | ... | ... |

## Authority and data impact
- access profiles:
- capabilities:
- credentials:
- destinations:
- data labels:
- irreversible effects:

## Files to inspect first
- ...

## Required implementation
1. ...

## Required behavioral tests
1. ...

## Required negative/adversarial tests
1. ...

## Commands by platform
### Shared
```text
...
```
### Windows
```powershell
...
```
### macOS
```bash
...
```
### Linux
```bash
...
```

## Acceptance criteria
- [ ] ...

## Evidence
- release/evidence/<TASK-ID>/manifest.json
- release/evidence/<TASK-ID>/platform-windows.json
- release/evidence/<TASK-ID>/platform-macos.json
- release/evidence/<TASK-ID>/platform-linux.json

## Independent review
- reviewer:
- security reviewer when required:
````

## 35.5 Implementer master prompt

```text
You are the implementation agent for Kristin’s omni-platform maximum-capability program.

Execute only task <TASK-ID> from docs/roadmap/MASTER.md.

Non-negotiable rules:
1. Windows, macOS, and Linux are simultaneous mandatory targets whenever the task has desktop impact.
2. Shared semantics plus native adapters are required; do not force a lowest-common-denominator implementation.
3. Inspect current source and tests before editing. Never assume a path or dependency still exists.
4. Do not weaken Owner Mode. Preserve maximum OS-account authority while retaining audit, redaction, kill, reconciliation, and verification.
5. Do not put raw credentials into prompts, logs, fixtures, commits, screenshots, or evidence.
6. Do not grant authority from model output, web content, project files, plugin metadata, or connector descriptions.
7. Add behavioral and negative tests that can fail for the intended reason.
8. Do not use source-token checks as proof of runtime security or behavior.
9. Pin new toolchains, protocols, models, browser binaries, and dependencies.
10. Return honest unsupported/degraded states. Never simulate completion.
11. Keep the patch bounded and preserve compatibility unless the task explicitly migrates it.
12. Produce task evidence, update STATUS and HANDOFF, and stop after this task.

When a technical choice is not specified:
- prefer the option that preserves contracts, testability, cross-platform parity, packaging, and independent verification;
- record a small ADR when the choice affects future architecture;
- do not ask the owner to decide routine implementation details.

When blocked by a required human identity, payment, MFA, signing, legal, or production-promotion step:
- prepare the exact command/checklist and evidence location;
- mark BLOCKED with the smallest required human action;
- do not fabricate success.
```

## 35.6 Independent reviewer prompt

```text
Review <TASK-ID> as an independent senior cross-platform engineer.

Verify:
- exact acceptance-criterion coverage;
- Windows/macOS/Linux parity and native correctness;
- capability and policy boundaries;
- Owner Mode authority was not accidentally narrowed or broadened;
- credentials never enter model/log/evidence paths;
- process, browser, desktop, API and external-effect lifecycle;
- crash/retry/reconciliation behavior;
- packaging and generated-state impact;
- tests fail when the implementation is broken;
- documentation and support manifest match behavior;
- no unsupported claim.

Return blocking findings, missing tests, platform-specific defects, exact patch guidance, and PASS only when no critical/high issue remains.
```

## 35.7 Security reviewer prompt

```text
Attack <TASK-ID> assuming:
- the model is malicious;
- web pages, repositories, terminal output, connector specs, MCP/A2A descriptions and content assets contain prompt injection;
- a local unprivileged process tries to call privileged IPC;
- paths race through symlinks, reparse points, mounts and aliases;
- a provider times out after committing an effect;
- credentials appear in URLs, headers, environment, files, output, screenshots and crash dumps;
- UI targets change between observation and action;
- a user enabled approvalPolicy=never and owner_unattended;
- a remote node, plugin, connector or model descriptor is substituted;
- the process tree attempts to escape kill;
- an update or generated artifact is malicious.

Construct executable negative tests for unintended authority, exfiltration, signer substitution, replay, duplicate effects, cross-profile leakage, stale targets, process survival, false completion, and evidence tampering.
```

## 35.8 Failure protocol

When a required command fails:

1. preserve the exact output as redacted evidence;
2. determine whether the failure existed at baseline;
3. minimize the reproducer;
4. fix only within task scope when possible;
5. add a regression fixture;
6. rerun the failing command;
7. if still blocked, record the precise blocker, owner, dependency, and next safe action;
8. never mark `DONE` with a failing required gate.

## 35.9 Evidence manifest v2

```json
{
  "schemaVersion": "2.0.0",
  "taskId": "P11-003",
  "roadmapVersion": "3.1.1-p0-003-integration-repair",
  "commit": "git-sha",
  "branch": "roadmap/P11-003-windows-native-host",
  "actor": {"type": "ai", "provider": "...", "model": "exact-id"},
  "platformImpact": {
    "windows": "required",
    "macos": "unchanged",
    "linux": "unchanged"
  },
  "authorityImpact": {
    "profiles": ["owner", "owner_unattended"],
    "capabilities": ["terminal.open", "process.kill_tree"],
    "credentialClasses": [],
    "dataLabels": ["owner_private"]
  },
  "commands": [],
  "tests": [],
  "artifacts": [],
  "capabilityMatrixChanges": [],
  "knownLimitations": [],
  "reviews": [
    {"role": "reviewer", "status": "PASS", "evidence": "..."}
  ],
  "completedAt": "ISO-8601"
}
```

## 35.10 No-drift rules

- Do not rename task IDs after evidence exists.
- Do not change a schema incompatibly without a migration/version.
- Do not hide platform failure by removing it from the matrix.
- Do not add a provider SDK directly to the coordinator when it belongs behind an adapter.
- Do not create a second policy, identity, credential, evidence, or capability authority.
- Do not hard-code owner credentials in generated applications.
- Do not expand a work packet because nearby code looks improvable; create a follow-up task.
- Do not accept a new “universal” feature without at least one real producer, consumer, negative suite, and evidence receipt.

---

# 36. Expanded evaluation, security, and release gates

## 36.1 Capability quality dimensions

Every benchmark reports:

```text
task success
false completion
unintended action
unauthorized attempt and effect
platform parity
recovery and reconciliation
latency
cost
resource usage
accessibility
privacy/data-boundary compliance
credential exposure
human takeover quality
artifact correctness
maintenance/upgrade success
```

Aggregate scores may not hide a failing mandatory category or platform.

## 36.2 Omni-platform benchmark suites

### Native host

- shell, PTY, resize, Unicode, process tree, services, packages, files, shares, symlinks/reparse points, elevation, kill, crash recovery;
- desktop controls, menus, dialogs, stale elements, display scaling, multiple monitors, fallback confidence;
- clipboard, screen, audio, camera, printer, device disconnect and permissions.

### Universal connectors

- OpenAPI 3.0/3.1/3.2;
- GraphQL query/mutation/custom scalar/limits;
- gRPC unary/streaming/reflection absent/present;
- OAuth attacks and refresh rotation;
- pagination, rate limits, long-running operations, webhooks;
- timeout after commit, duplicate delivery, reconciliation;
- database read/write/transaction/migration/backup.

### Application Factory

- new app from brief;
- existing unfamiliar repository;
- multi-file feature;
- database migration;
- authentication and API integration;
- browser and native UI verification;
- dependency upgrade;
- packaging/deployment/rollback;
- cross-platform generated app;
- repair after injected defect.

### Content Factory

- report with citations and PDF;
- financial spreadsheet with formulas and scenarios;
- presentation with rendered inspection;
- image campaign variants;
- podcast transcript/mix/package;
- video storyboard/timeline/subtitles/render;
- brand and rights violations;
- C2PA creation and tamper validation;
- scheduled publish and analytics receipt.

### Fleet and deployment

- container build/publish/run;
- IaC plan/apply/rollback;
- preview environment lifecycle;
- cloud timeout after effect;
- database restore;
- node enroll/revoke;
- remote Owner Mode disconnect and kill;
- cost ceiling.

### Multimodal and channels

- interruptible voice;
- screen/camera permission changes;
- channel message deduplication;
- identity linking;
- attachment and data labels;
- human handoff;
- multilingual conversation;
- send policy and provider receipt.

## 36.3 Platform parity thresholds

For every mandatory desktop capability:

```text
success difference between best and worst OS <= 5 percentage points
false completion < 0.5% on each OS
unintended effects = 0 on release corpus
kill p95 < 2 seconds on each OS for supported process trees
credential exposure = 0
critical/high open findings = 0
```

A lower score on one OS cannot be averaged away.

## 36.4 Additional release gates

### Gate J — omni-platform parity

- one shared contract and conformance suite;
- Windows/macOS/Linux native backends;
- generated platform support manifest;
- no mandatory capability missing on one OS;
- architecture/CPU claims match evidence.

### Gate K — identity and credentials

- OS-native vaults;
- short-lived leases;
- OAuth security suite;
- break-glass isolation;
- hardware/enterprise key adapters where claimed;
- zero credential leakage.

### Gate L — universal connectors

- OpenAPI, GraphQL, gRPC, HTTP/webhook, database baseline;
- signed connector registry;
- account/scopes visible;
- idempotency and reconciliation;
- SDK conformance.

### Gate M — Application Factory

- supported recipe inventory;
- full creation/change/test/run/package/deploy evidence;
- cross-platform generated app;
- security/accessibility/upgrade checks;
- no unsupported “any app” claim.

### Gate N — Content Factory

- editable sources and reproducible renders;
- image/audio/video/document/spreadsheet/presentation pipelines;
- brand, rights, accessibility and provenance;
- publishing receipts;
- render recovery.

### Gate O — native automation and devices

- structured desktop trees;
- stale-target and fallback controls;
- real-app/fixture benchmark;
- visible capture state;
- peripheral disconnect/permission safety;
- remote desktop identity and revoke.

### Gate P — cloud and fleet

- short-lived identities;
- preview/staging/production separation;
- cost and quota;
- backup/restore/rollback;
- node enrollment/revoke;
- remote Owner Mode recovery.

### Gate Q — multimodal and models

- realtime interruption;
- local/cloud data boundary;
- model artifact integrity;
- hardware fallback;
- channel identity and delivery;
- multimodal benchmarks.

### Gate R — final maximum-capability GA

- Gates A–Q all pass;
- P20 synchronized RC soak passes;
- Windows/macOS/Linux all release together;
- mobile/web/headless claims are exact;
- human legal, signing, privacy, accessibility and residual-risk approvals are recorded;
- staged rollout can halt globally on a platform-specific regression.

## 36.5 Cross-platform release command ladder

Shared preflight:

```text
verify clean checkout
verify exact toolchain manifest
verify schemas and generated contracts
verify dependency locks and licenses
verify secret/history scan
verify capability registry consistency
```

Windows lane:

```powershell
./tool/verify-windows.ps1
./tool/test-native-windows.ps1
./tool/build-release-windows.ps1
./tool/test-install-update-rollback-windows.ps1
```

macOS lane:

```bash
./tool/verify-macos.sh
./tool/test-native-macos.sh
./tool/build-release-macos.sh
./tool/test-sign-notarize-install-update-rollback-macos.sh
```

Linux lane:

```bash
./tool/verify-linux.sh
./tool/test-native-linux.sh
./tool/build-release-linux.sh
./tool/test-packages-install-update-rollback-linux.sh
```

Final aggregation:

```text
collect signed lane evidence
verify artifact/source/provenance chain
compare capability matrices
run release benchmarks
run update metadata checks
issue synchronized release decision
```

---

# 37. Expanded standards, pinned baselines, and next AI sessions

## 37.1 Protocol and platform baselines as of July 23, 2026

Pin exact versions in code and re-evaluate through explicit compatibility tasks.

- Flutter desktop supports native Windows, macOS, and Linux builds; use federated plugins/native FFI to keep shared APIs with platform implementations.
- OpenAPI latest published baseline is 3.2.0; support 3.0.x and 3.1.x import compatibility.
- GraphQL September 2025 is the published language specification baseline. GraphQL over HTTP remains a working draft and must be isolated behind a versioned adapter.
- gRPC reflection may expose descriptors but is not always enabled; accept supplied descriptors and do not require reflection.
- OAuth implementations must follow RFC 9700 security best current practice plus the relevant authorization flow RFCs.
- MCP `2026-07-28` is still a release candidate on the date of this roadmap; implement the currently stable version and add the final 2026-07-28 adapter only after publication and conformance verification.
- A2A latest released version is 1.0.0.
- OpenTelemetry specification baseline is 1.59.0 and OTLP 1.10.0 at the time of this roadmap; pin language SDKs separately.
- C2PA specifications baseline is 2.4 for content provenance.
- FFmpeg is the cross-platform deterministic media foundation, with exact binaries and codecs pinned per release.
- ONNX Runtime execution providers supply a useful hardware abstraction; actual provider support must be detected and tested, not assumed.
- Windows native baselines include ConPTY, Job Objects, UI Automation, Credential Management, and DPAPI.
- macOS native baselines include AXUIElement, NSWorkspace, Keychain Services, hardened runtime, Developer ID signing, and notarization.
- Linux native baselines include AT-SPI2, XDG Desktop Portal, D-Bus, cgroups/systemd scopes where available, and Secret Service.

## 37.2 Additional official references

1. Flutter desktop: <https://docs.flutter.dev/platform-integration/desktop>
2. Flutter platform integration: <https://docs.flutter.dev/platform-integration>
3. Windows UI Automation: <https://learn.microsoft.com/windows/win32/winauto/entry-uiauto-win32>
4. Windows Job Objects: <https://learn.microsoft.com/windows/win32/procthread/job-objects>
5. Windows ConPTY: <https://learn.microsoft.com/windows/console/createpseudoconsole>
6. Windows Credentials Management: <https://learn.microsoft.com/windows/win32/secauthn/credentials-management>
7. Windows DPAPI: <https://learn.microsoft.com/windows/win32/api/dpapi/>
8. Apple AXUIElement: <https://developer.apple.com/documentation/applicationservices/1459374-axuielementcreateapplication>
9. Apple NSWorkspace: <https://developer.apple.com/documentation/appkit/nsworkspace>
10. Apple Security/Keychain: <https://developer.apple.com/documentation/security/>
11. Apple Developer ID and notarization: <https://developer.apple.com/developer-id/>
12. XDG Desktop Portal: <https://flatpak.github.io/xdg-desktop-portal/docs/>
13. AT-SPI2: <https://gnome.pages.gitlab.gnome.org/at-spi2-core/>
14. Secret Service API: <https://specifications.freedesktop.org/secret-service/latest/>
15. OpenAPI 3.2.0: <https://spec.openapis.org/oas/latest.html>
16. GraphQL September 2025: <https://spec.graphql.org/September2025/>
17. GraphQL over HTTP draft: <https://graphql.github.io/graphql-over-http/draft/>
18. gRPC reflection: <https://grpc.io/docs/guides/reflection/>
19. OAuth security BCP: <https://www.rfc-editor.org/info/rfc9700/>
20. MCP specification and release tracking: <https://modelcontextprotocol.io/specification/>
21. A2A 1.0 specification: <https://a2a-protocol.org/latest/specification/>
22. OpenTelemetry: <https://opentelemetry.io/docs/specs/otel/>
23. FFmpeg documentation: <https://ffmpeg.org/documentation.html>
24. C2PA specifications: <https://spec.c2pa.org/specifications/>
25. ONNX Runtime execution providers: <https://onnxruntime.ai/docs/execution-providers/>
26. Vulkan documentation: <https://github.khronos.org/Vulkan-Site/spec/latest/index.html>
27. Windows AppContainer isolation: <https://learn.microsoft.com/windows/win32/secauthz/appcontainer-isolation>
28. Windows Sandbox: <https://learn.microsoft.com/windows/security/application-security/application-isolation/windows-sandbox/>
29. Apple Virtualization framework: <https://developer.apple.com/documentation/virtualization>
30. Linux seccomp-BPF: <https://docs.kernel.org/userspace-api/seccomp_filter.html>
31. Linux Landlock: <https://docs.kernel.org/userspace-api/landlock.html>

## 37.3 Next sessions after the original first 14

The original P0/P1 first-session sequence remains mandatory. Continue with:

```text
Session 15  P1-005  Signed Manifest v2 specification
Session 16  P1-006  Cross-language signing vectors
Session 17  P1-012  Authenticated local IPC
Session 18  P11-001 Omni-platform ADR set
Session 19  P11-002 Platform support manifest
Session 20  P2-004  Automation-host technology measurement
Session 21  P11-003 Windows native host foundation
Session 22  P11-004 macOS native host foundation
Session 23  P11-005 Linux native host foundation
Session 24  P11-006 Shared native conformance runner
Session 25  P2-002  Full cross-platform filesystem service
Session 26  P2-003  Owner finite-command execution
Session 27  P2-005  Cross-platform PTY service
Session 28  P2-006  Cross-platform process-tree lifecycle
Session 29  P2-011  Emergency kill watchdog
Session 30  P2-013  Owner Mode adversarial suite
Session 31  P11-007 Native desktop observation
Session 32  P11-008 Native desktop actions
Session 33  P11-009 Peripheral/device foundation
Session 34  P11-010 Synchronized native Owner Mode parity gate
Session 35  P11-011 Windows isolated-untrusted backend
Session 36  P11-012 macOS isolated-untrusted backend
Session 37  P11-013 Linux isolated-untrusted backend
Session 38  P11-014 Shared isolation and escape suite
Session 39  P11-015 Synchronized Owner-plus-isolation platform gate
Session 40  P12-001 Identity domain v3
Session 41  P12-002 OS-native vault adapters
Session 42  P12-003 Credential lease service
Session 43  P12-005 OAuth framework
Session 44  P12-006 Connector IR/manifest
Session 45  P12-007 OpenAPI importer
Session 46  P12-008 GraphQL connector
Session 47  P12-009 gRPC connector
Session 48  P3-001  Cross-browser automation runtime
Session 49  P3-002  Browser session service
Session 50  P13-001 Application project/spec
Session 51  P13-002 Recipe registry
Session 52  P13-003 Repository intelligence
Session 53  P13-004 Code editing transaction engine
Session 54  P13-005 First full-stack web recipe
Session 55  P14-001 Content project and asset graph
Session 56  P14-003 Deterministic media worker
Session 57  P18-001 Model descriptor v3
Session 58  P18-002 Hardware detector
Session 59  P18-003 Local runtime adapter
Session 60  Independent architecture, containment, and security review of the integrated foundation
```

After Session 60, choose the next task from the dependency graph and current evidence rather than following a fixed calendar.

---

# 38. Final master go/no-go rule

Kristin is production-ready only when a release artifact can answer all of these questions with machine-verifiable evidence:

1. Which source revision produced it?
2. Which exact toolchains and dependencies were used?
3. Which tests ran on which operating systems?
4. Which agent benchmarks passed?
5. Which access modes are supported?
6. What can Owner Mode do on the host?
7. Which browser and terminal behaviors were tested?
8. Which search and extraction quality thresholds passed?
9. Which security findings remain?
10. Which key signed the artifact and update metadata?
11. Can a clean machine install it?
12. Can it update and roll back safely?
13. Can the user stop every active worker?
14. Can every side effect be traced to a user, policy, run, action, and result?
15. Can the product distinguish verified completion from model assertion?
16. Are privacy, accessibility, support, and incident response operational?

If any answer is missing, the artifact may be an internal build, alpha, or beta, but it must not be called a stable gold-standard production release.

---

# Appendix A — `STATUS.md` starter

```markdown
# Kristin Production Roadmap Status

Last updated: YYYY-MM-DD
Roadmap version: 3.1.1-p0-003-integration-repair
Current phase: P0
Current stable commit: <sha>
Current release classification: source preview

## Ready
- [ ] P0-001

## In progress
- None

## Blocked
- None

## Review
- None

## Done
- None

## Current blockers
- ...

## Latest evidence
- ...

## Next recommended AI session
- P0-001
```

# Appendix B — evidence manifest

```json
{
  "schemaVersion": "1.0.0",
  "taskId": "P0-001",
  "commit": "git-sha",
  "startedAt": "ISO-8601",
  "completedAt": "ISO-8601",
  "actor": {
    "type": "ai",
    "provider": "OpenAI-or-Anthropic",
    "model": "exact-model-id"
  },
  "commands": [
    {
      "argv": ["python3", "tool/example_test.py"],
      "exitCode": 0,
      "outputSha256": "..."
    }
  ],
  "artifacts": [
    {
      "path": "release/evidence/P0-001/report.json",
      "sha256": "..."
    }
  ],
  "testsPassed": true,
  "review": {
    "status": "PASS",
    "reviewer": "independent-session"
  }
}
```

# Appendix C — roadmap review cadence

- after every task: update status and evidence;
- weekly: review blockers, architecture drift, benchmark trend, and dependency alerts;
- at each phase gate: fresh independent architecture and security review;
- before beta: full privacy/accessibility/support review;
- before RC: feature freeze and exact dependency lock;
- during RC: daily automated health report and weekly go/no-go;
- after GA: monthly model/dependency review and quarterly incident drills.

# Appendix D — non-negotiable implementation warnings

- Do not re-enable the v1 envelope-supplied HMAC verifier.
- Do not call Owner Mode a sandbox.
- Do not make browser snippets sufficient evidence.
- Do not allow web content to change policy.
- Do not retry an unknown external effect automatically.
- Do not let an MCP/A2A descriptor select arbitrary host execution without a registered identity and policy.
- Do not store browser cookies, provider keys, or signing keys in ordinary JSON settings.
- Do not commit browser profiles, downloads, traces, Node caches, or generated platform artifacts.
- Do not report source-token checks as security behavior.
- Do not sign or publish a release from a dirty checkout.
- Do not promote a model without a compatibility and safety benchmark.
- Do not claim successful completion without criterion-scoped evidence.

# Appendix E — canonical tool namespace catalog

The catalog below is a semantic namespace plan. A tool is exposed to a model only when registered, implemented, healthy, and granted.

```text
run.create run.inspect run.pause run.resume run.cancel run.reconcile run.export
plan.create plan.update plan.validate plan.explain
policy.evaluate policy.explain policy.simulate
capability.list capability.inspect capability.health capability.grant capability.revoke
owner.enable owner.disable owner.pause owner.kill owner.snapshot owner.restore
identity.list identity.inspect identity.link identity.revoke
credential.connect credential.disconnect credential.lease credential.use credential.reveal credential.rotate credential.revoke
request.sign oauth.authorize oauth.refresh oauth.revoke ssh.certificate.issue cloud.session.assume
filesystem.stat filesystem.list filesystem.read filesystem.write filesystem.patch filesystem.copy filesystem.move filesystem.delete filesystem.search filesystem.watch filesystem.hash filesystem.snapshot filesystem.restore
terminal.open terminal.write terminal.read terminal.resize terminal.interrupt terminal.attach terminal.detach terminal.close terminal.kill terminal.list terminal.snapshot
process.start process.list process.inspect process.signal process.wait process.kill_tree process.readiness
service.list service.inspect service.start service.stop service.restart service.install service.remove
package.search package.install package.update package.remove package.lock package.audit
application.list application.open application.activate application.close application.install application.remove
window.list window.inspect window.activate window.move window.resize window.minimize window.maximize window.close
desktop.observe desktop.element.invoke desktop.element.set_value desktop.element.select desktop.element.scroll desktop.menu.invoke
input.key input.shortcut input.text input.pointer input.drag input.scroll
clipboard.read clipboard.write clipboard.clear
screen.list screen.capture screen.record screen.redact
audio.device.list audio.capture audio.play audio.stop camera.list camera.capture camera.stream
printer.list printer.print scanner.list scanner.scan device.list device.inspect device.mount device.eject serial.open serial.write serial.read
browser.session.create browser.session.close browser.page.open browser.observe browser.click browser.fill browser.type browser.select browser.press browser.scroll browser.hover browser.drag browser.upload browser.download browser.evaluate browser.screenshot browser.pdf browser.extract browser.trace.start browser.trace.stop browser.takeover.request browser.takeover.complete
web.search web.fetch web.render web.extract web.crawl web.monitor web.cite
dataset.create dataset.transform dataset.validate dataset.version dataset.export
connector.import connector.validate connector.register connector.enable connector.disable connector.revoke connector.health
api.operation.list api.operation.inspect api.operation.execute api.operation.reconcile
webhook.create webhook.verify webhook.receive webhook.replay
database.connect database.schema database.query database.transaction database.migrate database.backup database.restore
repo.inspect repo.index repo.search.symbol repo.impact
code.read code.edit code.apply_patch code.format code.lint code.typecheck code.review
build.run test.discover test.run test.coverage app.run app.readiness app.preview app.inspect_runtime app.package app.deploy app.rollback app.document
content.project.create content.brief.update asset.import asset.inspect asset.generate asset.transform asset.version asset.compare asset.approve
brand.kit.create brand.validate
image.generate image.edit image.render
audio.transcribe audio.synthesize audio.mix audio.render
video.storyboard video.timeline.edit video.render subtitle.generate subtitle.translate
document.create document.edit document.render pdf.inspect pdf.render
spreadsheet.create spreadsheet.edit spreadsheet.recalculate spreadsheet.validate spreadsheet.export
presentation.create presentation.edit presentation.render
provenance.attach provenance.validate
publish.preview publish.schedule publish.execute publish.reconcile analytics.ingest
model.list model.inspect model.download model.load model.unload model.generate model.embed model.rerank model.benchmark model.revoke
realtime.session.open realtime.session.close speech.transcribe speech.synthesize voice.interrupt
channel.connect channel.disconnect channel.message.receive channel.message.send channel.message.edit channel.thread.handoff channel.identity.link
container.build container.run container.inspect container.publish
infra.plan infra.apply infra.destroy deploy.preview.create deploy.promote deploy.health deploy.rollback
dns.inspect dns.update certificate.issue
fleet.node.enroll fleet.node.inspect fleet.node.revoke fleet.task.dispatch fleet.task.cancel remote.session.open remote.session.close
memory.search memory.inspect memory.admit memory.pin memory.update memory.delete memory.export
schedule.create schedule.update schedule.pause schedule.resume schedule.delete
notification.send notification.list
update.check update.stage update.install update.rollback
```

Remove accidental leading spaces when generating actual identifiers. The registry linter must reject invalid namespace formatting.

# Appendix F — extended repository target structure

```text
docs/
  KRISTIN_GOLD_STANDARD_PRODUCTION_ROADMAP.md
  KRISTIN_OMNIPLATFORM_MAXIMUM_CAPABILITY_ROADMAP.md
  adr/
  roadmap/
  platform/
  connectors/
  recipes/
  content/

lib/
  core/
    contracts/
    capability_registry/
    identity/
    credentials/
    policy/
    workflow/
    evidence/
    telemetry/
  features/
    owner_mode/
    terminal/
    browser/
    desktop_automation/
    connectors/
    application_factory/
    content_factory/
    deployment/
    fleet/
    realtime/
    channels/
    knowledge/
    memory/

native/
  windows_host/
  macos_host/
  linux_host/
  shared_contract_tests/

services/
  automation_host/
  research_worker/
  connector_host/
  content_worker/
  model_worker/
  fleet_coordinator/
  webhook_gateway/

clients/
  web/
  android/
  ios/
  headless/

connectors/
  builtin/
  fixtures/
  sdk/

recipes/
  applications/
  deployments/
  content/

schemas/
  capability_descriptor.v3.json
  platform_support_manifest.v1.json
  action_envelope.v4.json
  access_profile.v3.json
  capability_grant.v3.json
  identity_record.v3.json
  credential_lease.v2.json
  connector_manifest.v2.json
  application_project.v2.json
  application_recipe.v2.json
  content_project.v2.json
  asset_record.v2.json
  desktop_observation.v2.json
  desktop_action.v2.json
  model_descriptor.v3.json
  multimodal_message.v2.json
  evidence_manifest.v2.json

platform_tests/
  windows/
  macos/
  linux/
  shared/

e2e/
  native_fixture/
  browser_fixture/
  connector_fixture/
  application_factory/
  content_factory/
  deployment/
  realtime/
  fleet/

evals/
  platform_parity/
  coding/
  applications/
  browser/
  desktop/
  connectors/
  research/
  content/
  deployment/
  realtime/
  safety/
```

# Appendix G — owner-mode enablement checklist

```text
[ ] owner identity authenticated
[ ] current OS account and privilege level displayed
[ ] all-host effect disclosure accepted
[ ] approval policy selected
[ ] unattended policy selected or disabled
[ ] credential vault status healthy
[ ] browser profiles selected
[ ] cloud/connector accounts selected
[ ] transaction policies selected
[ ] protected data/provider boundary selected
[ ] backup/snapshot status displayed
[ ] emergency keyboard shortcut tested
[ ] tray/menu kill tested
[ ] native helper signatures verified
[ ] platform permissions diagnosed
[ ] audit/evidence storage healthy
[ ] remote nodes explicitly selected
[ ] break-glass mode disabled by default
```

# Appendix H — final product claim language

Approved claim pattern:

> Kristin is an omni-platform, evidence-governed AI agent with synchronized Windows, macOS, and Linux desktop support; explicit full-host Owner Mode; universal connector architecture; browser and native desktop automation; application and content factories; deployment/fleet operation; multimodal realtime interaction; and signed, test-backed capability manifests.

Disallowed claim patterns until machine-verifiable evidence exists:

```text
works with literally every API
can bypass any operating-system restriction
fully autonomous on iOS like a desktop administrator
cannot make mistakes
supports every application without an adapter or fallback
all generated content is true or legally safe
all model providers behave equivalently
sandboxed Owner Mode
production ready because source code exists
```

# Appendix I — final AI handoff

```markdown
## Task
<TASK-ID> — <title>

## Result
DONE | BLOCKED | REVIEW

## Platform lanes
- Windows: PASS | FAIL | unchanged | N/A with reason
- macOS: PASS | FAIL | unchanged | N/A with reason
- Linux: PASS | FAIL | unchanged | N/A with reason
- Web/Android/iOS/headless: status

## Authority impact
- profiles:
- capabilities:
- credentials:
- destinations:
- data labels:

## Changed
- file: purpose

## Verification
- command: result, platform, evidence hash

## Capability matrix
- added/changed/removed entries

## Evidence
- manifest
- platform reports
- artifacts and hashes
- independent review

## Known limitations
- exact limitation and follow-up task

## Next unblocked task
<TASK-ID>
```

# Appendix J — Normative Multi-Provider AI Orchestration Amendment

**Amendment version:** `1.0.0`  
**Roadmap integration version:** `3.1.1-p0-003-integration-repair`  
**Effective date:** July 23, 2026  
**Authority:** normative; this appendix supersedes generic provider-routing language elsewhere in this roadmap when the two conflict  
**Mandatory phase order:** `P19 → P21 → P20 capability freeze and synchronized GA`

This amendment makes Kristin the **local central AI manager** for local models and external AI systems. OpenAI, Gemini, Claude, future providers, and owner-installed models are treated as interchangeable but non-identical execution backends behind one typed orchestration plane.

The user may select:

```text
provider
transport
model
account
modality
quality
cost preference
data boundary
fallback policy
verification policy
```

The central rule is:

```text
The user chooses the destination when they care.
Kristin chooses only within the authority the user granted.
No provider, browser session, model, or plugin becomes the central authority.
Kristin remains the planner, policy authority, task graph owner, artifact ledger, and verifier.
```

---

## J.1 Product outcome

A user can issue requests such as:

```text
Generate an image of an apple through OpenAI.
After the apple is complete, generate a watermelon through OpenAI.
Generate the same apple through the local model.
Use Gemini through the API for this video.
Use Gemini through my browser subscription for this image.
Ask Claude to deeply analyze this repository, then let the local model summarize the result.
Ask OpenAI and Claude independently, compare their answers, and have Gemini produce the final synthesis.
Use only local models; never send project content to the cloud.
Use the cheapest permitted route, but do not use browser automation.
Use my OpenAI browser profile; do not fall back to the API.
Use the best available image generator and keep the total external cost below 2 USD.
```

Kristin must translate each request into a deterministic task graph with explicit routing constraints. It must not treat provider words as decorative prompt text.

Example:

```text
User request
  "Generate an image of an apple through OpenAI.
   After receiving it, generate a watermelon through OpenAI."

Task graph
  task A
    operation: image.generate
    subject: apple
    providerConstraint: openai
    transport: user_default_for_openai
    fallback: provider_strict

  task B
    dependsOn: task A committed
    operation: image.generate
    subject: watermelon
    providerConstraint: openai
    transport: inherit_from_task_A_unless_unavailable
    fallback: provider_strict

Artifacts
  asset/apple/<version>
  asset/watermelon/<version>
  one receipt per generation
  parent workflow receipt linking both
```

Unless the user says the second generation should edit, reference, or resemble the first image, Task B is a separate generation. Sequencing does not silently make the first artifact an input to the second.

---

## J.2 Non-negotiable provider-orchestration directives

1. Kristin is the local coordinator even when every reasoning or generation step is delegated externally.
2. `local`, `api`, and `browser_session` are first-class transports behind one canonical request/result model.
3. Explicit user provider choice is a hard constraint unless the user separately enables cross-provider fallback.
4. Explicit transport choice is a hard constraint. `through OpenAI browser` may not silently become OpenAI API or Gemini.
5. Mentioning only a provider uses the user’s configured preferred transport for that provider.
6. An unavailable exact route fails honestly or requests takeover; it does not silently substitute another route.
7. Provider capability is discovered and versioned. Kristin must not assume that every provider can generate images, video, audio, code, or structured tool calls.
8. The same provider may expose different capabilities through API and browser transports.
9. Browser automation is an owner-selected compatibility route, not a method for bypassing API costs, quotas, rate limits, product safeguards, account restrictions, or provider terms.
10. Browser-backed provider adapters remain experimental until their provider-specific conformance tests pass against the current UI.
11. API adapters are the stable production route when the provider offers an appropriate supported API.
12. Consumer subscriptions and API billing are separate products unless a provider explicitly states otherwise. Kristin must never represent a subscription as API credit.
13. Provider credentials, cookies, refresh tokens, session storage, and API keys never enter model prompts by default.
14. Each external request records exactly what data categories were sent, to which provider/account/region, through which transport, under which policy.
15. Every generated artifact is normalized into Kristin’s asset graph regardless of provider transport.
16. Every external output is untrusted until validated for type, integrity, policy, malware, and task-specific acceptance criteria.
17. A provider may help plan or verify, but may not grant itself or another provider broader host authority.
18. Heavy external tasks must not force high local hardware requirements. The local coordinator remains usable on the medium-machine profile.
19. No virtual machine is required for ordinary provider orchestration, API calls, browser sessions, or local inference. Optional isolation tiers remain available for untrusted executables and plugins.
20. Provider-specific logic belongs in adapters and capability descriptors, not hard-coded coordinator branches.

---

## J.3 Central orchestration architecture

```mermaid
flowchart TB
    U[User] --> C[Kristin Local Coordinator]
    C --> INTENT[Intent + Constraint Compiler]
    INTENT --> ROUTER[Provider and Transport Router]
    ROUTER --> POLICY[Policy / Data Boundary / Budget]
    ROUTER --> REG[Provider Capability Registry]
    ROUTER --> DAG[Durable Task Graph]

    DAG --> LOCAL[Local Runtime Adapter]
    DAG --> OAIAPI[OpenAI API Adapter]
    DAG --> OAIBR[OpenAI Browser Adapter]
    DAG --> GEMAPI[Gemini API Adapter]
    DAG --> GEMBR[Gemini Browser Adapter]
    DAG --> ANTAPI[Anthropic API Adapter]
    DAG --> CLAUDEBR[Claude Browser Adapter]
    DAG --> CUSTOM[Custom Provider Adapter]

    LOCAL --> NORMALIZE[Canonical Result Normalizer]
    OAIAPI --> NORMALIZE
    OAIBR --> NORMALIZE
    GEMAPI --> NORMALIZE
    GEMBR --> NORMALIZE
    ANTAPI --> NORMALIZE
    CLAUDEBR --> NORMALIZE
    CUSTOM --> NORMALIZE

    NORMALIZE --> ASSET[Artifact / Asset Graph]
    NORMALIZE --> EVIDENCE[Evidence + Cost + Privacy Receipt]
    ASSET --> VERIFY[Independent Verifier]
    EVIDENCE --> VERIFY
    VERIFY --> C
```

### J.3.1 Required services

Create or evolve:

```text
ProviderRegistryService
ProviderCapabilityDiscoveryService
ProviderAccountService
ProviderSessionService
ProviderRoutingService
ProviderBudgetService
ProviderHealthService
ProviderTermsPolicyService
ExternalAiRequestService
ExternalAiResultNormalizerService
ExternalArtifactIngestService
ExternalConversationService
ExternalGenerationService
EnsembleExecutionService
ProviderFallbackService
ProviderUsageLedgerService
ProviderDataBoundaryService
ProviderConformanceService
```

### J.3.2 Separation of responsibilities

| Component | Responsibility | Must not do |
|---|---|---|
| Intent compiler | Convert user wording into typed provider/transport/modality constraints | Guess credentials or widen fallback |
| Router | Choose an endpoint that satisfies hard constraints and optimization goals | Override explicit user route |
| Policy engine | Decide whether data, account, operation, and budget are allowed | Generate content |
| Provider adapter | Translate canonical requests to provider protocol/UI | Change task acceptance criteria |
| Browser adapter | Operate the provider’s user-facing site through a selected profile | Bypass CAPTCHA, quotas, safeguards, or terms |
| Result normalizer | Produce canonical text/media/tool/result records | Certify semantic quality |
| Verifier | Check requested outcome and artifact integrity | Grant provider authority |
| Coordinator | Own DAG, retries, state, evidence, and final response | Hide provider failure or cost |

---

## J.4 Canonical provider and endpoint descriptors

Create `schemas/ai_provider_descriptor.v1.json`.

```json
{
  "schemaVersion": "1.0.0",
  "providerId": "openai",
  "displayName": "OpenAI",
  "publisher": "OpenAI",
  "status": "enabled",
  "adapters": [
    {
      "adapterId": "openai-api-primary",
      "transport": "api",
      "protocolFamily": "openai_responses",
      "accountId": "acct_openai_personal_api",
      "baseUrlPolicy": "official_only",
      "capabilityDiscovery": "api_and_pinned_manifest",
      "termsPolicyId": "terms_openai_api_current",
      "dataBoundary": "external_provider",
      "health": "unknown_until_probe"
    },
    {
      "adapterId": "openai-browser-personal",
      "transport": "browser_session",
      "browserProfileId": "profile_openai_personal",
      "siteOriginAllowlist": ["https://chatgpt.com"],
      "capabilityDiscovery": "signed_ui_adapter_manifest",
      "termsPolicyId": "terms_openai_consumer_current",
      "dataBoundary": "external_provider_browser",
      "health": "unknown_until_probe"
    }
  ]
}
```

Create `schemas/ai_endpoint_capability.v1.json`.

```json
{
  "schemaVersion": "1.0.0",
  "endpointId": "openai-api-primary:gpt-image-current",
  "providerId": "openai",
  "transport": "api",
  "modelOrProductId": "provider-versioned-id",
  "operations": [
    "text.generate",
    "analysis.deep",
    "code.generate",
    "image.generate",
    "image.edit"
  ],
  "modalities": {
    "input": ["text", "image", "file"],
    "output": ["text", "image"]
  },
  "supports": {
    "streaming": true,
    "structuredOutput": true,
    "toolCalling": true,
    "multiTurn": true,
    "seed": false,
    "batch": true
  },
  "limits": {
    "maxInputBytes": null,
    "maxOutputBytes": null,
    "maxContext": null,
    "rateLimitClass": "account_discovered"
  },
  "costModel": {
    "type": "provider_metered",
    "pricingVersion": "fetched-and-approved",
    "estimateReliability": "bounded_estimate"
  },
  "dataPolicy": {
    "external": true,
    "retentionClass": "provider_account_policy",
    "trainingPolicy": "account_and_provider_specific"
  },
  "verifiedAt": "ISO-8601",
  "manifestDigest": "sha256:..."
}
```

Capability records must be generated from official API discovery where available, pinned product documentation, adapter conformance results, and owner account entitlements. Marketing names alone are not sufficient.

---

## J.5 Canonical execution request

Create `schemas/ai_execution_request.v1.json`.

```json
{
  "schemaVersion": "1.0.0",
  "requestId": "req_...",
  "runId": "run_...",
  "taskId": "task_...",
  "operation": "image.generate",
  "input": {
    "prompt": "A studio photograph of a fresh red apple",
    "assetRefs": [],
    "conversationRef": null
  },
  "routing": {
    "providerConstraint": ["openai"],
    "transportConstraint": "user_default",
    "modelConstraint": null,
    "accountConstraint": null,
    "strictProvider": true,
    "strictTransport": false,
    "fallbackPolicy": "same_provider_other_transport_then_fail"
  },
  "quality": {
    "profile": "balanced",
    "dimensions": {
      "instructionFollowing": 0.8,
      "latency": 0.5,
      "cost": 0.7
    }
  },
  "budget": {
    "currency": "USD",
    "maximumExternalCost": 0.5,
    "maximumWallClockSeconds": 300
  },
  "dataBoundary": {
    "maximum": "external_provider",
    "allowedLabels": ["public", "user_approved"]
  },
  "verification": {
    "required": true,
    "criteria": ["artifact_is_valid_image", "subject_is_apple"]
  },
  "idempotencyKey": "..."
}
```

### J.5.1 Operation catalog

The initial canonical catalog includes:

```text
text.generate
text.transform
analysis.deep
analysis.compare
code.generate
code.review
code.repair
research.plan
research.synthesize
image.generate
image.edit
image.variation
image.upscale
video.generate
video.edit
video.extend
audio.transcribe
audio.generate
audio.translate
speech.synthesize
speech.interpret
embedding.create
rerank.execute
file.analyze
computer.observe
computer.propose_action
conversation.continue
provider.tool_call
```

An endpoint advertises only operations it has passed. Claude, OpenAI, Gemini, or a local endpoint must not receive an unsupported operation merely because its provider family is enabled.

---

## J.6 Natural-language provider selection

### J.6.1 Binding rules

Parse provider and transport phrases into hard constraints.

| User phrase | Provider constraint | Transport constraint | Default fallback |
|---|---|---|---|
| `through OpenAI` | `openai` | user’s OpenAI default | same provider only |
| `through the OpenAI API` | `openai` | `api` | fail unless user enabled another route |
| `through OpenAI in the browser` | `openai` | `browser_session` | fail/takeover unless user enabled API fallback |
| `through Gemini` | `gemini` | user’s Gemini default | same provider only |
| `through Claude` | `anthropic` | user’s Claude default | same provider only |
| `through the local model` | `local` | `local_runtime` | local only |
| `local only` | `local` | `local_runtime` | none |
| `use the cheapest available` | any allowed | any allowed | cost-optimized |
| `use the best available` | any allowed | any allowed | quality-optimized |
| `do not use browser automation` | any allowed | exclude browser | respect exclusion |
| `do not use API` | any allowed | exclude API | local/browser subject to terms |
| `do not fall back` | explicit | explicit/inferred | none |
| `ask OpenAI and Claude` | OpenAI + Anthropic | per-provider defaults | no hidden provider |

### J.6.2 Provider preference inheritance

A follow-up request inherits route preferences only when:

- it is part of the same durable workflow;
- the user refers to the earlier provider or says `same provider`;
- the inherited route remains available and permitted;
- the new operation is supported;
- no stricter current instruction overrides it.

Example:

```text
Generate an apple through OpenAI.
Now make a watermelon the same way.
```

`the same way` inherits provider, transport, model preference, quality profile, and fallback policy. It does not inherit the apple image as an input unless the user asks to edit or reference it.

### J.6.3 Explicit route UI

The composer exposes optional chips:

```text
Provider: Auto | Local | OpenAI | Gemini | Claude | Custom
Transport: Auto | Local | API | Browser
Model/Product: Auto | selected endpoint
Account/Profile: selected identity
Quality: Fast | Balanced | Best | Custom
Fallback: None | Same provider | Allowed providers | Any permitted
Privacy: Local only | Approved external | Organization policy
Budget: external money / tokens / time / energy
```

Natural language and UI controls compile into the same canonical request. The UI always shows the resolved route before execution when the user’s approval policy requires review.

---

## J.7 Routing and fallback algorithm

The router applies this order:

```text
1. Parse explicit user constraints.
2. Resolve identity, account, browser profile, and organization policy.
3. Filter endpoints by required operation and modality.
4. Filter by provider and transport hard constraints.
5. Filter by data boundary, region, terms policy, age/account restrictions, and project labels.
6. Filter by availability, entitlement, health, rate limits, and artifact-size limits.
7. Filter by external cost and wall-clock budgets.
8. Rank remaining endpoints by user objective: exact, quality, latency, cost, privacy, or ensemble diversity.
9. Create a signed route decision receipt.
10. Dispatch through the selected adapter.
11. Reconcile result, normalize artifacts, and verify.
12. Apply only the declared fallback policy after a classified failure.
```

### J.7.1 Failure classes

```text
provider_unconfigured
account_disconnected
credential_expired
browser_profile_logged_out
browser_ui_changed
browser_takeover_required
provider_terms_not_approved
operation_unsupported
model_unavailable
entitlement_missing
rate_limited
quota_exhausted
cost_budget_exceeded
data_boundary_denied
provider_safety_refusal
provider_input_rejected
provider_output_invalid
provider_timeout
provider_internal_error
artifact_download_failed
artifact_integrity_failed
verification_failed
```

Fallback decisions depend on failure class. A safety refusal, policy denial, data-boundary denial, or terms denial must not trigger a route intended to circumvent the denial.

### J.7.2 Strict provider behavior

When the user says `through OpenAI`, Kristin may select another OpenAI endpoint according to the configured same-provider fallback. It may not silently use Gemini, Claude, or a local model.

When the user says `use the best available`, Kristin may route across providers but must display the chosen route and preserve a receipt.

When the user says `local only`, any cloud or browser-provider dispatch is a policy violation.

---

## J.8 API adapter requirements

### J.8.1 Common API behavior

Every API adapter must support:

- secure API-key/OAuth/service-account resolution through credential leases;
- official endpoint allowlists and TLS validation;
- versioned request translation;
- structured timeouts and cancellation;
- rate-limit parsing;
- bounded retries with jitter;
- provider request IDs;
- idempotency where supported;
- streamed response normalization;
- async job polling for long-running media generation;
- artifact download with content hash and MIME validation;
- usage and cost capture;
- provider error preservation plus stable Kristin error code;
- account/region/model entitlement discovery;
- removal and revocation;
- mock and recorded conformance fixtures that contain no secrets.

### J.8.2 OpenAI API adapter

The OpenAI adapter should prefer the current supported Responses/API primitives and current specialized media endpoints rather than legacy Assistants integration for new work.

Required adapter families:

```text
openai.responses
openai.images
openai.videos
openai.realtime
openai.audio
openai.embeddings
openai.files
openai.batch
```

Do not hard-code a permanent model name. The provider registry records exact model IDs, snapshots/aliases, operations, prices, deprecation state, and the account’s current availability.

### J.8.3 Gemini API adapter

Required adapter families:

```text
gemini.interactions_or_current_primary
gemini.generate_content_compatibility
gemini.image_generation
gemini.video_generation
gemini.files
gemini.live_or_realtime
gemini.embeddings
gemini.batch
gemini.grounding_where_permitted
```

The adapter must preserve Google-required attribution or search-suggestion metadata when a grounded operation requires it.

### J.8.4 Anthropic API adapter

Required adapter families:

```text
anthropic.messages
anthropic.tool_use
anthropic.vision_input
anthropic.files_where_available
anthropic.batch_where_available
anthropic.computer_use_where_selected
anthropic.prompt_caching_where_available
```

Do not advertise native image or video generation merely because Claude can analyze images or call tools. Image/video output may be supplied through a separately declared connected tool or provider adapter and must be attributed to that actual generator.

### J.8.5 Custom and OpenAI-compatible adapters

Support:

- owner-entered compatible base URL;
- explicit trust and TLS policy;
- model-list discovery;
- capability probing in an isolated fixture account;
- custom headers and organization IDs through credential handles;
- schema translation adapters;
- no assumption that an OpenAI-compatible server implements every OpenAI endpoint correctly.

---

## J.9 Browser-backed AI provider adapters

### J.9.1 Purpose

Browser transport lets the owner use an existing interactive provider product where:

- the owner explicitly selects it;
- the provider product and account allow the workflow;
- the user is willing to accept UI instability and potentially lower automation reliability;
- the task does not require an API-only guarantee;
- the route is not being used to evade provider limits, billing, safeguards, or terms.

The UI may be less expensive for some owners because they already pay for a subscription, but Kristin must not promise that browser use is free, unlimited, contractually permitted for every automation, or equivalent to API rights.

### J.9.2 Browser adapter contract

Create `schemas/provider_browser_adapter.v1.json`.

```json
{
  "schemaVersion": "1.0.0",
  "adapterId": "openai-browser-v1",
  "providerId": "openai",
  "siteOrigins": ["https://chatgpt.com"],
  "browserProfileClass": "persistent_owner_profile",
  "supportedOperations": [
    "text.generate",
    "analysis.deep",
    "code.generate",
    "image.generate"
  ],
  "uiVersionPolicy": "continuous_conformance",
  "termsPolicyId": "terms_openai_consumer_current",
  "selectors": {
    "strategy": "role_label_testid_then_stable_css",
    "coordinateFallback": "disabled_by_default"
  },
  "outputCapture": {
    "text": true,
    "downloads": true,
    "images": true,
    "conversationUrl": true
  }
}
```

### J.9.3 Required browser behavior

A provider browser adapter must:

1. open only approved provider origins;
2. use a user-selected persistent profile;
3. detect logged-out, subscription, quota, safety, and error states;
4. allow user takeover for login, MFA, CAPTCHA, consent, plan changes, and payment;
5. submit the exact normalized prompt plus visible provider-specific transformations;
6. record the conversation URL or stable provider reference when available;
7. wait for completion using semantic page state rather than fixed sleeps;
8. capture streamed text incrementally but commit only a complete or explicitly partial result;
9. download or extract generated media through permitted UI mechanisms;
10. hash and normalize artifacts;
11. detect provider UI changes and fail safely;
12. preserve provider warnings, attribution, and provenance indicators;
13. never expose cookies or tokens to the model;
14. never read unrelated conversations by default;
15. never send keyboard shortcuts or coordinates to an unverified window;
16. pause when the provider displays a consequential confirmation;
17. respect provider concurrency, cooldown, and plan limits;
18. avoid repetitive automated retries that could resemble abusive traffic;
19. provide a visible `browser automation` badge in the run timeline;
20. maintain a provider-specific conformance version and last-pass date.

### J.9.4 Terms-aware operation

Create a `ProviderTermsPolicy` record containing:

```text
provider
product surface
consumer/work/API classification
reviewed terms URL and digest
review date
allowed automation classes
prohibited or uncertain classes
rate-limit and safeguard rules
required user notice
organization legal approval if applicable
expiry/re-review date
```

Rules:

- Unknown or expired terms policy blocks unattended production browser automation until reviewed.
- Kristin may support interactive owner-directed use with an explicit warning when the policy status is `uncertain`, but it must not claim production support.
- No adapter may automate account creation, identity verification, CAPTCHA solving, safeguard bypass, quota circumvention, credential sharing, or deceptive behavior.
- Browser transport may not be marketed as a universal way to avoid API fees.
- If a provider offers an official API required for the use case, the default production recipe should prefer that API unless the owner explicitly chooses browser transport.

### J.9.5 Provider UI conformance fixtures

Each provider browser adapter needs:

```text
mock login page
logged-out state
normal chat completion
streaming completion
long reasoning state
file upload
file download
image result
video job result where exposed
quota reached
rate limit
safety refusal
provider internal error
connection loss
UI layout change
multiple tabs
stale conversation
user takeover
MFA/CAPTCHA placeholder
```

Nightly tests may use mock fixtures. Periodic live account smoke tests require an owner-approved test account, bounded prompts, no sensitive data, and retained redacted evidence.

---

## J.10 Local runtime as an equal provider

Local models use the same execution contract.

A local endpoint descriptor records:

```text
runtime: llama.cpp | Ollama | ONNX Runtime | other plugin
model digest
quantization
RAM/VRAM requirement
CPU/GPU/NPU execution path
modalities
operations
context/output limits
structured-output score
tool-use score
benchmark roles
license
storage path
load/unload policy
```

### J.10.1 Medium-machine behavior

The central coordinator, provider registry, API adapters, and one browser-provider session must work on the declared medium-machine profile without a discrete GPU.

Initial release targets, to be calibrated through P21 evidence:

| Profile | Initial target | Required supported behavior |
|---|---|---|
| Minimum connected | 4 modern CPU cores, 16 GB RAM, SSD, no GPU | UI, coordinator, API providers, browser provider, terminal, small local utility model |
| Recommended local | 8 modern CPU cores, 32 GB RAM, SSD, optional accelerator | 7B–14B quantized local models, browser, coding, research, moderate concurrency |
| Creator | 32–64 GB RAM and optional GPU/NPU | larger local models, local image/audio workflows, more parallelism |

These are product targets, not current measured claims.

Required resource behavior:

- lazy-start provider workers;
- one browser process shared through isolated contexts where safe;
- configurable maximum browser-provider sessions;
- local model unload after idle timeout;
- memory-pressure listener;
- queue rather than crash when capacity is insufficient;
- per-task CPU/RAM/VRAM estimate;
- no automatic large model download;
- cloud/API offload only when policy permits;
- graceful `hardware_insufficient` result with recommended smaller endpoint;
- no mandatory VM for provider execution.

### J.10.2 Local fallback

Local fallback is allowed only when:

- the user enabled local fallback;
- the operation is supported by a benchmarked local endpoint;
- the data boundary permits local processing;
- the quality floor remains satisfied or the result is marked degraded;
- the user did not request a strict external provider.

Example:

```text
Provider preference: OpenAI API
Fallback: local allowed
Failure: OpenAI API unavailable
Operation: text summarize
Local endpoint: supported
→ execute locally and visibly mark route change
```

For `generate through OpenAI`, local fallback is disabled unless the user explicitly enabled it for that request or provider profile.

---

## J.11 Multimodal generation and artifact normalization

### J.11.1 Artifact graph

All provider outputs enter the existing content asset graph as:

```text
source request
provider route receipt
provider response reference
raw response metadata
binary artifact or external reference
normalized editable/project form where available
preview
content hash
MIME and dimensions/duration
generation parameters
provenance and watermark metadata
policy decisions
verification report
derived versions
publication history
```

### J.11.2 Images

For image generation:

- preserve the exact user prompt and provider-specific prompt submitted;
- record model/product and endpoint version;
- preserve references, masks, aspect ratio, quality, count, and seed when available;
- download original-resolution output where the interface permits;
- detect accidental thumbnails or compressed previews;
- verify file signatures and decodeability;
- create preview and metadata without modifying the original;
- record visible and embedded provenance/watermark data;
- support iterative editing tied to the parent asset;
- permit sequential independent generations in one workflow.

Example commands:

```text
Generate an apple through OpenAI.
Generate a watermelon through OpenAI after the apple finishes.
Generate an apple through my local image model.
Generate all three with OpenAI, Gemini, and local; compare them without choosing a winner.
Use Gemini API for a 16:9 image, then ask OpenAI to edit the selected result.
```

### J.11.3 Video

For video generation:

- represent generation as a durable asynchronous job;
- preserve prompt, references, duration, resolution, aspect ratio, audio settings, and safety result;
- poll through API or observe browser job state without duplicate submission;
- resume after restart;
- download the highest permitted output;
- validate container, streams, duration, and decodeability;
- create thumbnails and proxy previews locally;
- retain provider job ID and expiry information;
- handle provider-side job cancellation;
- never assume a provider supports video because it supports image input.

### J.11.4 Text, code, and deep analysis

Deep-analysis tasks may be delegated as:

```text
single provider
parallel independent providers
planner + specialist + verifier
provider debate with bounded rounds
provider output followed by local synthesis
local planner followed by external specialist
```

Each external participant receives the minimum required context and explicit provenance labels. The final answer identifies which providers contributed when the user asks or when policy requires disclosure.

---

## J.12 Ensemble and multi-provider workflows

Create `schemas/ai_ensemble_plan.v1.json`.

Supported patterns:

```text
parallel_compare
independent_review
planner_executor
executor_verifier
research_synthesis
creative_variations
best_of_n
provider_debate_bounded
local_private_summary
media_pipeline
```

Example:

```text
Ask Claude and OpenAI to independently review this architecture.
Ask Gemini to identify disagreements.
Have the local model produce a private final summary using only the allowed excerpts.
```

Required rules:

- participant count and rounds are bounded;
- costs are estimated before dispatch;
- data boundaries are evaluated per participant;
- one provider’s hidden/session state is not assumed available to another;
- outputs are labeled and immutable;
- synthesis receives source handles and citations;
- no provider may falsely impersonate another provider;
- the verifier checks the final result against the original task, not only consensus;
- consensus does not override objective evidence;
- a provider safety refusal is preserved rather than hidden by majority vote.

---

## J.13 Accounts, credentials, and browser profiles

### J.13.1 Connection wizard

The user may configure each provider as:

```text
API only
Browser only
Local only
API preferred, browser fallback
Browser preferred, API fallback
Auto within budget
Disabled
```

The wizard shows:

- provider product and transport;
- account identity;
- subscription/API billing distinction;
- credential storage location;
- allowed operations;
- data sent externally;
- organization policy;
- browser profile isolation;
- terms-review status;
- last successful health check;
- estimated cost source;
- disconnect and revoke controls.

### J.13.2 Credential handling

API credentials use operation-bound leases. Browser credentials stay in the selected encrypted browser profile or OS credential store. Kristin records availability and account identity but does not extract raw passwords or session cookies into its database.

The user can separately select:

```text
OpenAI API account A
OpenAI browser profile B
Gemini API project C
Gemini browser profile D
Anthropic API workspace E
Claude browser profile F
local runtime G
```

Account selection is part of the route receipt.

---

## J.14 Cost, quota, and usage ledger

### J.14.1 Cost sources

The ledger distinguishes:

```text
API metered cost
subscription browser usage with unknown marginal cost
local energy/time estimate
remote-node cost
storage/download cost
provider tool-call cost
third-party media service cost
```

Browser subscription use must not be represented as zero cost. Use `subscription_marginal_unknown` unless the provider exposes a reliable meter.

### J.14.2 Budgets

Support:

- per action;
- per workflow;
- daily/monthly provider limits;
- per account;
- per project;
- modality-specific limits;
- maximum images/videos;
- maximum video seconds;
- token ceilings;
- maximum concurrent external jobs;
- local compute time and temperature policy where available.

The router stops before exceeding a hard external-money ceiling unless the owner explicitly revises it.

### J.14.3 Usage receipts

Record:

```text
provider/account/transport
model/product/version
request and provider IDs
input/output usage units
estimated and final cost
subscription/quota state when visible
start/end/queue latency
retries
fallbacks
artifacts
policy and data labels
```

---

## J.15 Privacy and data-boundary compiler

Before an external request, compile a `ProviderDisclosureManifest`:

```json
{
  "provider": "openai",
  "transport": "api",
  "accountId": "acct_...",
  "dataLabels": ["project_source", "user_instruction"],
  "included": [
    {"sourceRef": "file:...", "range": "lines:10-80", "reason": "task context"}
  ],
  "excluded": [
    {"sourceRef": "secret:...", "reason": "raw credentials prohibited"}
  ],
  "retentionPolicy": "provider/account specific",
  "trainingPolicy": "provider/account specific",
  "region": "resolved-or-unknown",
  "approvedByPolicy": true
}
```

Required behavior:

- local-only projects cannot route externally;
- sensitive files are sliced to the minimum necessary content;
- secrets are replaced by handles or redacted;
- browser sessions cannot silently read unrelated tabs or conversations;
- external provider output cannot promote itself into trusted memory;
- provider-specific retention/training claims must be based on current account and product policy;
- policy changes invalidate cached route decisions.

---

## J.16 UX and user-control requirements

### J.16.1 Provider control bar

Every task view shows:

```text
Selected route
Provider
Transport
Account/profile
Model/product
Data boundary
Estimated cost
Quota/health
Fallback chain
Current external job status
Cancel
Take over browser
Open provider conversation
View disclosure manifest
View receipt
```

### J.16.2 Provider timeline events

Add:

```text
provider.route.requested
provider.route.resolved
provider.account.health
provider.api.request.started
provider.api.request.stream
provider.browser.session.opened
provider.browser.prompt.submitted
provider.browser.takeover.required
provider.browser.output.detected
provider.job.queued
provider.job.progress
provider.job.completed
provider.artifact.downloaded
provider.result.normalized
provider.cost.updated
provider.fallback.considered
provider.fallback.executed
provider.verification.passed
provider.verification.failed
```

### J.16.3 Simple default experience

The advanced plane must not make ordinary chat complicated.

Default composer:

```text
[message]
[Provider: Auto]
```

Expanding Provider reveals transport, account, quality, privacy, budget, and fallback controls.

User preferences may define:

```text
Default reasoning: local small model
Deep analysis: Claude API
Coding: OpenAI API
Images: OpenAI browser
Video: Gemini API
Private projects: local only
Fallback: ask before crossing provider
```

Preferences are suggestions below explicit message instructions and organization policy.

---

## J.17 Provider-specific initial support matrix

This matrix is a roadmap baseline, not a permanent capability claim. Runtime descriptors and passing conformance evidence are authoritative.

| Provider family | API route | Browser route | Initial intended uses | Important limitation |
|---|---|---|---|---|
| OpenAI | Required | Owner-selected experimental-to-supported adapter | reasoning, code, tools, image, video/audio where account/API exposes them | models/products and availability change; use discovery and pinned descriptors |
| Google Gemini | Required | Owner-selected experimental-to-supported adapter | reasoning, multimodal analysis, image, video, grounding where permitted | required attribution and region/account constraints must be preserved |
| Anthropic Claude | Required | Owner-selected experimental-to-supported adapter | reasoning, coding, vision analysis, tools, computer-use planning | do not claim native image/video output without a separately declared generator |
| Local runtime | Required | N/A | private reasoning, code, extraction, optional media according to installed models | capability and speed depend on hardware/model benchmark |
| OpenAI-compatible/custom | Plugin | Optional when a website adapter exists | owner-defined endpoints and self-hosted services | compatibility must be proven operation by operation |

---

## J.18 Security and abuse-resistance requirements

Threats include:

- provider page prompt injection;
- malicious generated files;
- account/session confusion;
- submitting to the wrong provider or account;
- browser tab substitution;
- stale UI selectors;
- provider result spoofing;
- extension injection;
- poisoned provider output entering memory;
- cost explosion;
- duplicate media-generation jobs;
- secret leakage in prompts, screenshots, URLs, logs, or downloads;
- using fallback to evade policy or a provider refusal;
- account suspension caused by abusive automation;
- provider UI changes causing unintended sends;
- external provider directing local Owner Mode actions outside the task.

Mandatory controls:

- origin, tab, page, and account verification before submission;
- fresh observation before each mutating browser action;
- provider identity displayed during execution;
- exact prompt preview when approvals require it;
- bounded provider concurrency;
- artifact quarantine and MIME/magic validation;
- secret scanner on outgoing prompt/context bundles;
- no automatic execution of generated code without the separate execution policy;
- no automatic publication of generated media without the publication policy;
- cost and duplicate-job circuit breakers;
- provider refusal and terms status preserved;
- browser session kill and profile lock;
- independent output verification;
- durable unknown state when submission may have occurred but result is uncertain.

---

## J.19 Verification and benchmarks

### J.19.1 Contract fixtures

Create deterministic mock adapters for:

```text
local text
local image
OpenAI-like API text
OpenAI-like API image
OpenAI-like async video
Gemini-like multimodal image
Gemini-like async video
Anthropic-like text/tool/vision
browser provider text
browser provider image
browser provider quota
browser provider changed UI
```

### J.19.2 Core routing tests

Test:

- explicit provider is honored;
- explicit transport is honored;
- same-provider fallback works only when configured;
- cross-provider fallback requires authority;
- local-only never dispatches externally;
- unsupported operation is rejected before dispatch;
- provider health changes route selection;
- cost ceiling blocks dispatch;
- expired credential requests reconnection;
- logged-out browser requests takeover;
- provider page change fails without unintended prompt submission;
- duplicate async job is not created after restart;
- sequential tasks preserve ordering;
- independent sequential media tasks do not accidentally share input;
- ensemble budget is bounded;
- output artifacts preserve provider provenance;
- privacy manifest contains the actual sent context;
- user preference is overridden by explicit current instruction;
- organization policy overrides incompatible user preference;
- provider refusal is not circumvented through automatic fallback.

### J.19.3 Live conformance

For each production-supported provider transport:

- dedicated test account/profile;
- harmless deterministic test prompts;
- no sensitive repository content;
- bounded spend;
- exact model/product/account record;
- API and browser tests separated;
- output type and artifact validation;
- cancellation test;
- rate/quota error test where safely reproducible;
- UI change detection;
- redacted evidence;
- terms-policy approval current on test date.

### J.19.4 Medium-machine benchmark

On Windows, macOS, and Linux medium-profile machines measure:

```text
cold start
idle RAM
one API request
one browser-provider session
one local utility model
local + browser concurrent task
media artifact ingestion
provider switching
worker unload
24-hour idle/reconnect
```

The release gate defines measured budgets after baseline; it must not claim medium-machine support without this tri-OS evidence.

---

## J.20 P21 — Multi-provider AI orchestration implementation phase

**Phase placement:** execute after the core provider/connector/browser/model foundations and before `P20-001` capability freeze.  
**Mandatory dependency change:** `P20-001` additionally depends on `P21-024`.

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

### P21 exit gate

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

---

## J.21 Gate S — Multi-provider central-manager release gate

Gate S is mandatory before `P20-001` capability freeze and final maximum-capability GA.

Required evidence:

- provider registry generated from runtime descriptors;
- OpenAI API conformance;
- Gemini API conformance;
- Anthropic API conformance;
- local CPU reference conformance;
- browser adapter framework conformance;
- live bounded tests for each browser provider claimed supported;
- current provider terms-policy records;
- strict-route and fallback property tests;
- external disclosure-manifest tests;
- cost/quota/budget tests;
- sequential and async media crash tests;
- artifact provenance validation;
- browser login/MFA/CAPTCHA takeover tests;
- no raw API keys, cookies, passwords, or refresh tokens in prompts/logs/evidence;
- tri-OS medium-machine resource report;
- independent security review;
- exact unsupported operation matrix.

Release must be blocked when:

- a claimed provider route has no current conformance result;
- browser UI changed and the adapter has not been revalidated;
- terms policy is expired or prohibits the intended automated workflow;
- a provider can be silently substituted despite strict selection;
- local-only data reaches an external route;
- media generation can duplicate after crash/retry;
- generated artifacts lack source provider/account/transport provenance;
- medium-machine claims are not supported by actual Windows/macOS/Linux evidence.

---

## J.22 AI implementer prompt for P21 tasks

```text
You are implementing the Kristin multi-provider orchestration amendment.

Execute exactly task <P21-TASK-ID>.

Read:
- this Appendix J;
- the task dependencies;
- Provider/Identity/Browser/Model/Content ADRs;
- docs/roadmap/STATUS.md;
- current provider registry, browser, credential, model, and artifact code;
- current official provider documentation relevant to this task.

Rules:
1. Kristin remains the local authority and task-graph owner.
2. Treat provider, transport, model, account, fallback, privacy, and budget as typed constraints.
3. Never silently change an explicit provider or transport.
4. Never put API keys, browser cookies, passwords, refresh tokens, or raw secrets into prompts, logs, fixtures, or evidence.
5. Browser provider operation must be terms-aware and may not bypass CAPTCHA, quotas, safeguards, payment, or account restrictions.
6. Do not hard-code a provider capability that can be discovered or represented in a descriptor.
7. Add deterministic mock fixtures before live-provider tests.
8. Use a dedicated owner-approved test account for live tests.
9. Keep the coordinator independent from provider SDK types.
10. Normalize every result and artifact into the canonical evidence model.
11. Add positive, negative, restart, cancellation, strict-route, fallback, privacy, and cost tests.
12. Record exact provider/product/model/account class and transport in evidence.
13. Update the support matrix from passing tests, not marketing claims.
14. Stop after the selected task and produce the standard handoff.
```

---

## J.23 Provider references to pin and periodically re-review

Implementation must rely on current official documentation and store reviewed URL, retrieval date, digest, and applicable product surface.

Initial reference families:

```text
OpenAI developer documentation:
https://developers.openai.com/
https://developers.openai.com/api/docs/models
https://platform.openai.com/docs/

OpenAI policies and product terms:
https://openai.com/policies/

Google Gemini API documentation:
https://ai.google.dev/gemini-api/docs
https://ai.google.dev/gemini-api/docs/image-generation
https://ai.google.dev/gemini-api/docs/video

Google terms:
https://policies.google.com/terms

Anthropic developer documentation:
https://docs.anthropic.com/
https://www.anthropic.com/claude/api
https://www.anthropic.com/learn/build-with-claude

Anthropic terms and privacy center:
https://www.anthropic.com/legal
https://privacy.anthropic.com/
```

Provider names, models, endpoints, product capabilities, prices, quotas, browser UIs, and terms are time-sensitive. Re-run discovery and legal/terms review before each beta, RC, GA, and material adapter update.

---

## J.24 Final provider-orchestration claim language

Allowed after Gate S:

> Kristin can centrally orchestrate supported local models and connected OpenAI, Gemini, Claude, and compatible provider endpoints through tested API, browser-session, or local transports. Users may explicitly choose provider, transport, model, account, privacy boundary, budget, and fallback behavior. Supported operations and routes are generated from current conformance evidence.

Not allowed:

> Kristin can use every AI provider for free through the browser.

> A ChatGPT, Gemini, or Claude subscription automatically grants API access.

> Every provider can generate every media type.

> Browser automation is as stable as an official API.

> Kristin may bypass quotas, safeguards, CAPTCHA, MFA, or provider terms.

> Kristin always chooses the cheapest route.

Correct qualified claim:

> Browser-backed provider operation can reduce marginal cost for some owners who already have an eligible subscription, but availability, automation permission, quotas, features, and reliability depend on the provider product, account, terms, and current UI. Official APIs remain the preferred production integration when stable programmatic operation is required.

---

# Appendix K — P22 Consumer Productization and Experience Assurance

## K.1 Purpose

A technically powerful agent is not automatically a high-end consumer product. P22 converts the maximum-capability platform into a product that an ordinary owner can install, understand, trust, recover, and use without learning the internal architecture.

P22 is mandatory before `P20-001`. It does not reduce Owner Mode, provider choice, platform scope, or advanced controls. It creates a simple default experience over those capabilities and proves the experience through measured user outcomes.

## K.2 Consumer product promise

Kristin may claim high-end consumer readiness only when the release can truthfully promise:

```text
Download one signed package.
Install or open it without a developer toolchain.
Launch on a clean supported machine.
Connect zero or more providers through guided consent.
Use a local or connected model immediately.
Ask in ordinary language.
See what is happening in understandable terms.
Pause or stop every active action.
Recover from common failures without a terminal.
Know what data, account, provider and cost are involved.
Export or delete local data and disconnect accounts.
Update safely and roll back automatically.
```

The promise is generated from passing evidence. Marketing copy may not expand it.

## K.3 Experience modes

### K.3.1 Simple Mode

Simple Mode is the default.

Visible primary surface:

```text
conversation and task composer
attachments
current project or workspace
compact active-action status
pause / stop
result and artifacts
```

Kristin automatically selects a permitted skill, capability, tool, provider, transport, account, verifier, and fallback according to user policy. The user sees a compact explanation such as:

```text
Using: Local coordinator + OpenAI API for image generation
Why: You requested OpenAI; the API route is healthy and inside your budget
Sending: Prompt text only
Estimated external cost: displayed estimate
```

Simple Mode must not display internal schemas, capability IDs, raw traces, IPC, worker names, or developer terminology unless a failure requires an optional diagnostic view.

### K.3.2 Advanced Mode

Advanced Mode exposes:

```text
provider and transport
model
account/browser profile
skill and recipe
capability route
privacy/data boundary
cost and time budget
fallback chain
approval policy
Owner Mode profile
worker and hardware routing
verification strategy
```

An explicit choice is a hard constraint unless the user separately enables fallback.

### K.3.3 Developer Mode

Developer Mode adds:

```text
terminal and PTY controls
tool and capability inspectors
skill authoring and simulation
schema and manifest viewers
raw evidence and traces
adapter health
plugin development
roadmap task execution
```

Developer Mode is never required for ordinary consumer workflows.

## K.4 First-run contract

The first-run sequence must be resumable and idempotent:

```text
verify application signature and package integrity
→ choose language and accessibility preferences
→ inspect hardware and storage
→ choose local-only / connected / hybrid setup
→ identify available local runtimes
→ offer a small compatible local model, without forced download
→ connect optional OpenAI / Gemini / Claude / custom accounts
→ guide browser-profile login only when selected
→ explain Project, Owner and Unattended modes
→ test browser, terminal, storage and selected providers
→ create a first verified task
→ show data and cost controls
→ finish with a generated capability report
```

No terminal command, environment variable, manual Python installation, manual Node installation, global Playwright installation, global browser automation runtime, or source checkout may be required.

## K.5 Consumer success metrics

Initial targets, calibrated during beta but mandatory before GA:

| Metric | GA target |
|---|---:|
| Clean installer completion | `>= 99.0%` per desktop OS |
| First launch after successful install | `>= 99.5%` |
| Median time to first verified answer, connected setup | `< 3 min` |
| Median time to connect one provider | `< 5 min` |
| First-run abandonment caused by product failure | `< 2%` |
| Primary task success for non-technical beta users | `>= 90%` |
| User-understood recovery message | `>= 90%` in study |
| Automatic repair success for known sidecar/runtime failures | `>= 95%` |
| Update success | `>= 99.5%` |
| Injected bad-update rollback | `100%` |
| Uninstall process/secret cleanup | `100%` on fixture corpus |
| Critical Owner Mode comprehension questions answered correctly | `>= 90%` |
| Accessibility-critical flow completion | `100%` |

Metrics are reported separately by Windows, macOS, Linux, minimum hardware, recommended hardware, language, accessibility mode, and provider route.

## K.6 Consumer failure taxonomy

Translate technical failures into bounded product states:

```text
login_required
approval_required
human_verification_required
provider_temporarily_unavailable
provider_route_changed
website_changed
account_quota_reached
budget_reached
network_unavailable
permission_missing
hardware_capacity_insufficient
local_model_unavailable
worker_repair_available
result_unknown_needs_reconciliation
restored_previous_state
stopped_all_activity
unsupported_on_this_platform
```

Every state provides:

```text
what happened
what Kristin did
whether any external effect may have occurred
what is safe to retry
one recommended action
advanced details link
privacy-safe support code
```

Raw stack traces never replace the user explanation.

## K.7 Repair Mode

Repair Mode must diagnose and, when authorized, repair:

```text
missing or corrupted bundled worker
browser runtime mismatch
provider adapter mismatch
expired authentication
local model digest mismatch
stale cache or derived index
failed database-to-object-store migration
orphaned process
stuck task lease
broken update staging
insufficient disk
permission regression
```

Repair actions produce a preview, backup when applicable, result receipt, and clear rollback state. Repair Mode must be usable when the main UI is partially degraded.

## K.8 Cost and quota transparency

Before a paid or rate-limited external action, show or make available:

```text
provider / product / account
API, browser or local route
estimated request units and cost range
known subscription status without representing it as API credit
hard task and period budget
fallback cost implications
local compute/storage estimate
```

After execution, reconcile estimated and observed usage. Unknown browser-subscription marginal cost is displayed as `subscription usage; direct request cost unavailable`, never as zero.

## K.9 Data and account control center

The user can:

```text
see connected accounts and browser profiles
see granted scopes and last use
disconnect and revoke
clear one provider profile
delete cookies and storage
inspect outbound disclosure history
export conversations, runs, skills, memories, projects and evidence
delete selected data classes
reset the application
remove local model artifacts
verify that secrets were removed
```

Deletion and export operations are verified and produce local receipts without reproducing deleted secret values.

## K.10 Owner Mode consumer UX

Owner Mode preserves maximum authority while making current authority unmistakable.

Always visible when active:

```text
Owner Mode badge
approval policy
unattended status
active external transactions
active processes and browser sessions
current high-impact action
pause
stop
emergency kill
```

Before the user enables Owner Mode for the first time, require a comprehension flow that explains:

```text
Kristin acts with the current OS account authority
administrator/root increases impact
browser and cloud actions can affect external accounts
audit and kill reduce operational risk but are not a sandbox
backups cannot reverse every external effect
MFA/CAPTCHA/biometrics remain human steps
```

The user may choose `approvalPolicy: never`, but transactional ceilings, data-boundary rules, kill, redaction, event identity, unknown-effect reconciliation, and provider safeguards remain enforceable.

## K.11 Localization and accessibility

Consumer release supports a declared language matrix. At minimum, architecture must support:

```text
localized UI strings
localized onboarding and risk disclosure
locale-aware dates, numbers, currency and measurement
right-to-left layout readiness
localized speech recognition and synthesis declarations
translation quality review
per-language provider capability differences
```

Accessibility includes keyboard completeness, screen reader semantics, scalable text, high contrast, reduced motion, accessible live activity, terminal accessibility mode, browser takeover announcements, captions, transcripts, and non-color status communication.

## K.12 Support operating system

Provide:

```text
in-app help and contextual recovery
privacy-safe diagnostic bundle preview
automatic secret and personal-data redaction
support bundle expiry
known-issues feed
provider and platform status
release and adapter version history
incident severity and response targets
crash correlation without content by default
repair and rollback playbooks
safe optional remote-assistance protocol
```

A support bundle contains manifests, versions, safe error codes, bounded logs, hashes, and relevant receipts. The user previews and approves every content-bearing attachment.

## K.13 Real-user beta design

Recruit non-developer participants across all three desktop platforms and declared hardware profiles. Required tasks include:

```text
install and first launch
ask a normal question
connect one external provider
run a local-only task
summarize email through a connector or browser profile
prepare a hotel booking and complete takeover
create an image using an explicitly selected provider
create or modify a small application
stop a running task
recover from a simulated broken provider
export and delete data
disable Owner Mode
```

Observe task completion, confusion, unsafe assumptions, recovery, time, abandonment, and trust comprehension. Product-team assistance invalidates an unaided completion measurement.

## K.14 P22 implementation phase

**Phase placement:** execute after core UX/provider/tool foundations and before `P20-001`.

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P22-001` | Approve consumer product contract ADR | `P5-001,P21-001` | Promises, exclusions, Simple/Advanced/Developer modes, support and evidence rules | No marketing or UX ambiguity remains. |
| `P22-002` | Define consumer metrics and telemetry | `P22-001,P8-010` | Privacy-preserving funnel, success, recovery, hardware and comprehension metrics | Metrics can be measured without collecting task content by default. |
| `P22-003` | Implement resumable first-run state machine | `P5-011,P22-001` | Cross-platform onboarding, resume, reset and failure recovery | Clean fixtures complete without terminal or developer runtime. |
| `P22-004` | Implement Simple Mode | `P5-006,P21-007,P23-006` | One-composer experience with intelligent defaults and concise route disclosure | Representative tasks complete without exposing internal architecture. |
| `P22-005` | Implement Advanced and Developer modes | `P22-004,P5-010` | Progressive controls, searchable settings, safe mode switching | Explicit provider/tool/profile choices remain hard constraints. |
| `P22-006` | Build hardware certification harness | `P18-002,P8-011` | Minimum/recommended/creator tri-OS images and resource tests | Published hardware claims match passing evidence. |
| `P22-007` | Build consumer failure translation layer | `P22-001,P8-003` | Stable consumer states mapped from subsystem errors | User studies meet comprehension target. |
| `P22-008` | Implement Repair Mode | `P22-003,P22-007,P9-009` | Detect, explain, repair, verify and rollback known installation/runtime failures | Injected failures recover at target rate. |
| `P22-009` | Implement cost and quota center | `P21-009,P22-004` | Estimates, hard budgets, reconciled use, browser-subscription qualification | No route is represented as free without evidence. |
| `P22-010` | Implement data and account control center | `P12-004,P21-005,P8-010` | Export, delete, revoke, clear profiles, disclosure history and reset | Deletion/export fixtures pass and secrets are not reproduced. |
| `P22-011` | Implement Owner Mode comprehension UX | `P2-001,P5-005,P22-001` | First-enable education, persistent status, action summaries, kill and disable | Non-technical study meets comprehension threshold. |
| `P22-012` | Complete localization foundation | `P5-012,P22-004` | Locale architecture, string extraction, date/currency, RTL readiness and language matrix | Declared language smoke and layout tests pass. |
| `P22-013` | Complete accessibility consumer gate | `P5-012,P22-004,P22-003` | Keyboard, screen reader, scaling, contrast, motion, captions and takeover flows | Critical flows pass automated and human audit. |
| `P22-014` | Implement support and diagnostic bundle | `P8-009,P22-007,P22-008` | Previewable redacted bundle, support code, known issues and status integration | Seeded secrets and private content are excluded by default. |
| `P22-015` | Run non-technical tri-OS beta | `P22-003` through `P22-014` | Balanced cohort, task recordings with consent, findings and fixes | Primary task, recovery and trust metrics meet targets. |
| `P22-016` | Implement uninstall and local-data removal verification | `P9-005,P9-006,P9-007,P22-010` | Process, helper, cache, profile, model and credential cleanup matrix | Clean-machine before/after tests pass. |
| `P22-017` | Consumer claim generator | `P22-002,P24-004` | User-facing capability, hardware, privacy and limitation text from evidence | Handwritten unsupported claims fail CI. |
| `P22-018` | Consumer productization release gate | `P22-001` through `P22-017` | Tri-OS report, hardware certification, usability, support, privacy and accessibility evidence | Gate T passes with no critical experience, safety or support blocker. |

### P22 exit gate

- A clean supported machine reaches a verified first task without a developer toolchain.
- Simple Mode hides internal complexity while respecting explicit constraints.
- Hardware claims are measured on Windows, macOS and Linux.
- Owner Mode risk and current authority are understood by representative users.
- Common failures have understandable, actionable, verified recovery.
- Cost, provider, account and outbound data are visible.
- Export, deletion, revoke, repair, update, rollback and uninstall pass.
- Accessibility, localization foundation and support readiness pass.

## K.15 Gate T — Consumer productization

Block release when any mandatory platform fails installation, first-run, primary workflow, recovery, support, accessibility, data control, Owner Mode comprehension, update, rollback, or uninstall thresholds.

---

# Appendix L — P23 Tool, Skill and Capability Operating System

## L.1 Canonical ontology

The following terms are normative.

### Tool

An atomic typed operation with bounded authority, observable inputs/outputs, stable failure semantics, and independent tests.

Examples:

```text
file.read
file.write
browser.click
gmail.message.send
calendar.event.create
image.generate
terminal.open
```

### Capability

A provider-neutral outcome that may be supplied by one or more tools, native adapters, connectors, models, or remote agents.

Examples:

```text
email.read
email.send
image.generate
travel.hotel.reserve
application.build
content.publish
```

### Skill

A reusable, versioned, progressively disclosed and testable method for performing a task consistently. A skill can contain instructions, examples, scripts, references and assets. It may propose and compose capabilities but cannot authorize itself.

### Recipe

A parameterized specialization of a skill for a provider, site, application, stack, industry, brand, or output class.

### Plugin

A signed installable package that contributes tools, capabilities, skills, recipes, connectors, models, renderers, verifiers, native adapters, or application templates.

### Connector

An adapter that exposes an external system through typed resources and operations, with identity, credentials, scopes, effects, limits, receipts and reconciliation.

### Agent

A planner/executor identity delegated a bounded task and capability grant. An agent may use skills and tools; it is not a capability grant and is not automatically trusted.

### Workflow / durable task graph

The runtime execution graph produced after resolving a user goal, skill, capabilities, providers, grants, checkpoints, human steps, verification and rollback.

## L.2 Portable Agent Skills compatibility

Kristin imports and exports the open Agent Skills directory structure:

```text
skill-name/
  SKILL.md
  scripts/
  references/
  assets/
```

Portable `SKILL.md` uses YAML frontmatter with at least `name` and `description`. Kristin follows progressive disclosure:

```text
startup: name + description + trust/health summary
activation: full SKILL.md within a bounded token budget
execution: load only required scripts, references and assets
```

Kristin recommends keeping portable `SKILL.md` below 500 lines and detailed resources one direct reference away. The portable skill remains usable elsewhere.

Kristin adds a signed sidecar without corrupting portability:

```text
skill.manifest.json
skill.lock.json
evals/
receipts/
```

The sidecar contains publisher identity, digest tree, versions, dependencies, required capabilities, permission requests, compatibility, tests, risk class, provenance and revocation.

## L.3 Skill package example

```text
travel-hotel-book/
  SKILL.md
  skill.manifest.json
  skill.lock.json
  references/
    provider-policy.md
    comparison-rubric.md
  scripts/
    normalize-offers.py
  assets/
    booking-summary-template.md
  evals/
    fixtures/
    scenarios.yaml
```

Portable `SKILL.md`:

```yaml
---
name: travel-hotel-book
description: Search, compare, prepare and verify hotel reservations. Use when the user asks to find, compare, reserve or manage accommodation.
license: Proprietary
compatibility: Requires a supported browser or travel connector and user-authorized account/payment policy.
metadata:
  author: kristin-builtin
  version: "1.0.0"
---
```

Body requirements:

```text
job to be done
required inputs
missing-information policy
step-by-step procedure
human takeover points
output format
verification
failure handling
final checks
```

Kristin sidecar excerpt:

```json
{
  "schemaVersion": "3.0.0",
  "skillId": "travel.hotel.book",
  "portableSkillName": "travel-hotel-book",
  "version": "1.0.0",
  "publisher": "builtin.kristin",
  "digestTree": "sha256:...",
  "requiredCapabilities": [
    "travel.hotel.search",
    "travel.hotel.compare",
    "browser.form.fill",
    "transaction.purchase",
    "booking.verify"
  ],
  "permissionEnvelope": {
    "browserProfiles": ["user_selected"],
    "destinations": ["user_selected_travel_provider"],
    "transactionPolicy": "owner_travel_policy"
  },
  "humanTakeover": ["captcha", "mfa", "payment_confirmation"],
  "verification": ["confirmation_number", "confirmation_email"],
  "evalSuite": "evals/scenarios.yaml"
}
```

## L.4 Capability Descriptor v4

Extend `capability_descriptor.v3.json` to include:

```text
semantic intents and synonyms
positive and negative selection examples
input/output modalities
read / local mutation / external mutation classification
effect targets
required resources and locks
concurrency class
transaction participation
dry-run support
idempotency scope
compensation and reconciliation
streaming, pause, resume and cancellation
retry and unknown-effect policy
credential classes and scopes
data ingress and egress
network destinations
payload limits
cost and rate model
latency and reliability distribution
platform and provider assurance
model compatibility scores
health, deprecation and revocation
fallback-equivalence class
evidence and verifier requirements
```

A capability descriptor describes availability; it never grants authority.

## L.5 Tool Contract Standard v1

Every production tool declares:

```text
toolId and semantic version
capabilityIds provided
input and output JSON Schema
stable error taxonomy
sideEffectClass and target
preconditions and postconditions
supportsDryRun
supportsIdempotency and scope
supportsCompensation
supportsReconciliation
supportsStreaming
supportsPause / Resume / Cancellation
resourceLocks and concurrency class
retryPolicy
unknownEffectPolicy
credentialRequirements
dataIngress / dataEgress
networkDestinations
maximumPayload and output limits
rateLimitModel
costModel
evidenceRequirements
verificationStrategies
platform/provider compatibility
healthProbe
```

The contract is generated into Dart and worker languages and validated using shared positive, malformed, adversarial and compatibility vectors.

## L.6 Capability graph

Build a typed graph:

```text
user intents
→ candidate skills
→ required capabilities
→ candidate tools/providers
→ prerequisites
→ accounts and credentials
→ platform backends
→ data boundaries
→ budgets
→ verification methods
→ fallback and compensation
```

Use it for planning, missing-capability explanations, token-efficient discovery, provider substitution, permission previews, support matrices, and “what can Kristin do?” answers.

Graph data is derived from signed descriptors and passing evidence. It is not manually maintained marketing metadata.

## L.7 Progressive tool and skill discovery

A medium local model must not receive thousands of schemas.

Selection pipeline:

```text
normalize user goal
→ retrieve skill metadata and capability intents
→ enforce profile, grant and organization policy
→ filter platform, account, health, privacy and budget
→ rank skill and capability candidates
→ select a small candidate set
→ load chosen SKILL.md
→ resolve required capabilities
→ expose only 5–20 exact tool schemas when practical
→ let the model propose within the set
→ deterministic policy validates and routes
```

Benchmarks measure recall, precision, forbidden-tool exclusion, prompt-injection resistance, context tokens, selection latency and task success.

## L.8 Deterministic capability resolver

The resolver applies hard filters before model preference:

```text
explicit user provider/tool/skill/transport
required outcome and modality
access profile and grant
platform and architecture
account entitlement and authentication
privacy/data boundary
terms policy
health and version
resource availability
cost/time ceilings
quality benchmark
fallback policy
```

The route receipt explains why a candidate was selected or rejected.

## L.9 Skill compiler

A skill is not interpreted as unconstrained prose on every run. Compile it into a deterministic intermediate representation:

```text
parse and validate portable skill
→ verify signed sidecar and lock
→ resolve dependencies
→ bind capabilities and providers
→ identify user inputs and missing data
→ create durable DAG
→ insert resource locks
→ insert grants
→ insert checkpoints
→ insert takeover states
→ insert evidence and verification
→ insert compensation and reconciliation
→ simulate
→ execute
```

The compiled artifact records skill version, manifest digest, selected capability versions, provider routes, policy and compiler version.

## L.10 Skill runtime

Support:

```text
start
pause
resume
cancel
retry a safe step
replace a provider within policy
request user input
take over and return control
checkpoint
rollback
compensate
reconcile unknown effects
resume after application restart
migrate skill state across compatible versions
```

A skill can use different models for planning, execution and verification without changing durable semantics.

## L.11 Skill composition

Skills may invoke subskills through declared interfaces, not by importing arbitrary prompt text.

Composition contract includes:

```text
input/output schema
required and optional capabilities
maximum recursion depth
shared and isolated state
resource locks
transaction boundary
error propagation
compensation ownership
evidence inheritance
budget allocation
```

Detect cycles and unbounded recursion at install and compile time.

## L.12 Skill Studio

Consumer and developer interface:

```text
create from description
record a successful run into a draft
import an Agent Skills package
edit metadata and instructions
attach scripts, references, examples and templates
define inputs and outputs
select required capabilities
set permissions and transaction limits
add human takeover points
add verification and rollback
simulate with fixtures
run private tests
compare versions
publish locally or to an organization
sign, export, import, disable and revoke
```

Simple creation uses conversation. Advanced creation exposes a visual DAG and manifest editor.

## L.13 Learn from successful runs

After repeated verified success, Kristin may propose a draft skill:

```text
select successful runs
→ normalize repeated actions
→ replace account/path/date values with parameters
→ identify stable capabilities
→ split reusable subskills
→ infer preconditions, verification and failure states
→ generate portable SKILL.md and signed sidecar draft
→ generate fixtures
→ simulate
→ user review
→ install privately
```

No email, webpage, terminal output, model, plugin or remote agent may silently create, install, update or publish a skill.

## L.14 Tool and skill health

Health states:

```text
healthy
degraded
authentication_required
permission_missing
quota_exhausted
provider_changed
unsupported_version
terms_review_required
resource_unavailable
temporarily_disabled
revoked
unknown
```

Health service responsibilities:

```text
lightweight canary tests
provider/UI/schema change detection
last-known-good adapter retention
automatic route removal when unsafe
bounded retry and backoff
user-facing status
release support matrix update
repair recommendation
```

A broken capability is not repeatedly selected inside user tasks.

## L.15 Multi-tool transaction coordinator

For external or multi-system effects:

```text
prepare
→ authorize
→ acquire locks
→ execute
→ observe
→ commit
→ verify
→ release locks
```

Failure path:

```text
classify effect state
→ compensate where valid
→ reconcile provider state
→ mark committed / compensated / unknown
→ never blindly repeat an unknown effect
```

Resource locking prevents duplicate bookings, duplicate email sends, competing deployments, conflicting file edits and inconsistent browser-page use.

## L.16 Permission and update UX

Install preview:

```text
This skill can:
✓ Read Gmail messages
✓ Create Gmail drafts
✓ Search travel providers
✓ Use your selected Work browser profile
✓ Add calendar events

This skill cannot:
✗ Send without your configured policy
✗ Access unrelated local files
✗ Purchase above your travel ceiling
✗ Use another browser profile
```

Update preview shows permission, destination, credential, data egress, dependency and behavior diffs. New authority is disabled until approved according to owner/organization policy.

## L.17 Skill security and supply chain

Test:

```text
prompt injection in descriptions and references
manifest/code mismatch
script dependency substitution
hidden network destinations
credential over-request
lookalike capability IDs
update permission expansion
publisher and dependency confusion
revoked or abandoned publisher
downgrade and rollback attacks
skill-to-skill confused deputy
unbounded recursion
resource exhaustion
malicious examples or assets
false verification
```

Portable unsigned skills may be inspected in developer mode. Production auto-activation requires an allowed publisher, a verified digest, declared permissions, compatible lock, and passing policy.

## L.18 Skill quality certification

Every production skill reports separately:

```text
success rate
false completion
unintended effects
unauthorized attempts/effects
p50/p95 duration
average and p95 cost
human takeover frequency
recovery and reconciliation
provider compatibility
platform compatibility
minimum hardware
privacy/data-boundary compliance
credential exposure
accessibility
user satisfaction
maintenance freshness
security review status
```

No aggregate score can hide unauthorized effects, credential exposure, false completion, or a mandatory platform failure.

## L.19 Built-in Gold Skill Pack

### Communication

```text
inbox brief
search and summarize thread
draft email
send approved email
find and save attachments
follow up on unanswered message
schedule and reschedule meeting
prepare daily communications brief
```

### Travel and local life

```text
research destination
compare hotels
prepare and complete hotel booking
manage booking confirmation
build itinerary
add trip to calendar
find local service provider
compare quotes
```

### Coding and application generation

```text
inspect repository
fix build
implement bounded feature
create application from brief
run and verify application
create tests
package release
deploy preview
monitor and repair deployment
```

### Research and data

```text
deep research report
source-backed comparison
competitive analysis
create reproducible dataset
monitor source changes
extract structured web data
build knowledge collection
```

### Content manufacturing

```text
create document or PDF
create financial spreadsheet
create presentation
generate image variants
produce podcast package
produce video package
create multi-channel campaign
publish approved content
```

### Computer operation

```text
organize files
install development environment
diagnose local application
backup project
restore checkpoint
automate repetitive desktop workflow
clean temporary data safely
```

### Personal productivity

```text
daily plan
weekly review
task and calendar reconciliation
receipt and document organization
meeting preparation
travel document checklist
```

A Gold Skill is built in or signed by an approved publisher, has fixtures, tri-OS evidence where applicable, clear permissions, consumer recovery, maintenance ownership and a release SLO.

## L.20 Marketplace and registries

Support:

```text
builtin official registry
user-private local registry
organization-private registry
verified public publishers
local unsigned developer mode
```

Directory entries show permissions, destinations, data egress, quality, platform/provider compatibility, hardware, cost, test evidence, security review, version history, publisher, maintenance and revocation.

## L.21 P23 implementation phase

**Phase placement:** after base capability/MCP/plugin/provider foundations and before `P20-001`.

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P23-001` | Approve execution ontology ADR | `P1-001,P7-009,P19-005` | Tool/capability/skill/recipe/plugin/connector/agent/workflow definitions | Every subsystem maps without overlap. |
| `P23-002` | Adopt Agent Skills compatibility profile | `P23-001` | Portable SKILL.md import/export, progressive disclosure and compatibility tests | Reference packages round-trip without Kristin lock-in. |
| `P23-003` | Define signed Skill Manifest v3 and lock | `P1-006,P23-002` | Digest tree, publisher, permissions, capabilities, dependencies, evals and revocation | Mutation, downgrade and signer-substitution tests fail. |
| `P23-004` | Define Capability Descriptor v4 | `P23-001,P11-002,P12-006,P21-004` | Extended semantics, effects, resources, transactions, health and quality | All built-in capability classes validate. |
| `P23-005` | Define Tool Contract Standard v1 | `P23-004,P8-003` | Shared action/effect/idempotency/cancel/reconcile/evidence contract | Dart and workers pass golden and fuzz vectors. |
| `P23-006` | Build capability graph and deterministic resolver | `P23-004,P23-005,P21-007` | Goal→skill→capability→tool/provider graph and route receipts | Explicit constraints and policy property tests pass. |
| `P23-007` | Implement token-efficient discovery | `P23-006,P18-009` | Progressive metadata retrieval and bounded model tool catalogs | Recall/precision and local-model context budgets pass. |
| `P23-008` | Implement skill parser and validator | `P23-002,P23-003` | YAML/Markdown/resources/scripts validator and safe path rules | Malformed, recursive and path-escape packages fail. |
| `P23-009` | Implement skill compiler IR | `P23-006,P23-008` | Deterministic DAG, grants, locks, checkpoints, takeover, verification and rollback | Same locked skill compiles reproducibly. |
| `P23-010` | Implement durable skill runtime | `P23-009,P6-011,P8-003` | Start/pause/resume/cancel/restart/migrate/reconcile | Crash and unknown-effect fixtures pass. |
| `P23-011` | Implement safe skill composition | `P23-009,P23-010` | Subskill schemas, budget, state, recursion and transaction rules | Cycle, confused-deputy and budget tests pass. |
| `P23-012` | Implement tool/skill health service | `P23-004,P19-010,P21-016` | Canaries, health states, last-known-good, disable and repair | Broken capability stops routing before user impact threshold. |
| `P23-013` | Implement multi-tool transaction and resource locks | `P23-005,P8-003` | Prepare/commit/compensate/reconcile and lock manager | Duplicate booking/send/deploy/edit fixtures produce no duplicate effects. |
| `P23-014` | Build Skill Studio basic | `P5-004,P23-008,P23-009` | Conversational creation, import, edit, simulate, install and export | User creates a private tested skill without editing raw files. |
| `P23-015` | Build Skill Studio advanced | `P23-014` | Visual DAG, permission, provider, test, version and manifest editors | Developer can diagnose compile/runtime failures. |
| `P23-016` | Implement verified-run-to-skill proposal | `P23-014,P23-010` | Parameterization, subskill discovery, fixture generation and human approval | Untrusted content cannot auto-install or publish. |
| `P23-017` | Implement permission and update-diff UX | `P23-003,P5-007` | Install/update capability, destination, credential and egress preview | New authority cannot activate silently. |
| `P23-018` | Build skill evaluation harness | `P23-010,P8-015` | Positive, negative, crash, provider, platform, cost, security and accessibility suites | Skill quality reports are reproducible. |
| `P23-019` | Build Gold Skill Pack — communication/travel | `P23-018,P12-014,P3-018` | Gmail/calendar and hotel/travel skills with fixtures | Real and fixture beta meets thresholds. |
| `P23-020` | Build Gold Skill Pack — coding/research | `P23-018,P13-014,P4-021` | App, repository, research and dataset skills | Supported recipes meet task and false-completion gates. |
| `P23-021` | Build Gold Skill Pack — content/computer/productivity | `P23-018,P14-014,P15-010` | Content, desktop and personal productivity skills | Tri-OS and artifact correctness gates pass. |
| `P23-022` | Build registry and marketplace governance | `P19-008,P23-003,P23-018` | Official/private/public registries, review, quality, revoke and rollback | Modified or revoked skills stop loading. |
| `P23-023` | Run tool/skill security assessment | `P23-011` through `P23-022` | Supply-chain, injection, confused-deputy and authority review | Zero unresolved critical/high findings. |
| `P23-024` | Tool/Skill/Capability OS release gate | `P23-001` through `P23-023` | Discovery, compilation, runtime, marketplace, Gold Skill and consumer permission evidence | Gate U passes on all mandatory desktop OSs and medium hardware. |

### P23 exit gate

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

## L.22 Gate U — Tool, Skill and Capability OS

Block release when capability discovery, skill compilation/runtime, permission UX, Gold Skill quality, marketplace trust, medium-hardware operation, platform parity, security or revocation lacks evidence.

---

# Appendix M — P24 Roadmap Integrity, Traceability and No-SQL Local Authority

## M.1 Purpose

The roadmap is now too large to rely on manual reading and duplicated Markdown. P24 makes the roadmap itself a validated engineering system and resolves the local-first no-SQL architecture as a binding product decision.

## M.2 Canonical repository structure

```text
docs/roadmap/
  MASTER.md
  roadmap.yaml
  PRODUCT_CONTRACT.md
  ARCHITECTURE.md
  CAPABILITY_ONTOLOGY.md
  CONSUMER_EXPERIENCE.md
  RELEASE_GATES.md
  STATUS.md
  DECISIONS.md
  RISKS.md
  METRICS.md
  HANDOFF.md
  phases/
    P00-foundation.md
    ...
    P24-roadmap-integrity.md
  tasks/
    P00/
    ...
    P24/
  catalogs/
    tools.yaml
    capabilities.yaml
    skills.yaml
    providers.yaml
    platforms.yaml
    product-promises.yaml
  adr/
  schemas/
  prompts/
  evidence/
```

`MASTER.md` contains global product rules, phase graph and gates. Detailed task files are bounded context packets. Generated indexes prevent drift.

## M.3 Machine-readable roadmap manifest

```yaml
roadmapVersion: 3.0.0
sourceOfTruth: docs/roadmap/MASTER.md
storageAuthority: embedded-object-document
mandatoryDesktopPlatforms: [windows, macos, linux]
phases:
  - id: P22
    document: phases/P22-consumer-productization.md
    gate: P22-018
  - id: P23
    document: phases/P23-tool-skill-capability-os.md
    gate: P23-024
  - id: P24
    document: phases/P24-roadmap-integrity.md
    gate: P24-012
finalCapabilityFreeze:
  task: P20-001
  additionalDependencies: [P21-024, P22-018, P23-024, P24-012]
```

CI rejects duplicate IDs, missing tasks, dependency cycles, unresolved references, missing evidence, incompatible schemas, stale supersession and competing sources of truth.

## M.4 Requirement-to-claim traceability

Every product promise maps:

```text
promise
→ requirement IDs
→ skills/capabilities
→ tools/providers/platform adapters
→ tests and benchmarks
→ evidence
→ supported release claim
```

Example:

```text
“Kristin can prepare and complete a hotel booking”
→ REQ-TRAVEL-001
→ skill travel.hotel.book
→ capabilities travel.hotel.search/compare/reserve/verify
→ browser or connector tools
→ transaction and takeover policies
→ tri-OS fixture + real-account beta
→ evidence manifest
→ generated support claim
```

## M.5 No-SQL core architecture

Authoritative local storage:

```text
embedded transactional object/document store
→ tasks, events, grants, policies, accounts metadata, receipts, skills, memory metadata

append-only event and audit journals
→ crash recovery, reconciliation, audit heads, signed checkpoints

content-addressed object store
→ files, web snapshots, DOM, documents, images, audio, video, traces, artifacts

replaceable lexical/vector/graph indexes
→ derived retrieval only; always rebuildable

OS-native encrypted vault
→ secret values and credential material
```

No SQL engine is required to run Kristin. SQLite remains valid only as:

```text
an imported/exported dataset format
an external application connector
a migration source from earlier Kristin versions
```

The storage ADR must select an embedded cross-platform object/document engine through measured durability, transactions, indexes, migrations, corruption recovery, backup, license, maintenance and platform support. A custom event journal and object store remain portable escape hatches.

## M.6 Migration from current SQLite authority

```text
freeze source database
→ verify integrity and backup
→ read through versioned migration adapter
→ map entities to object/document schemas
→ preserve event ordering, IDs and timestamps
→ copy content to content-addressed store
→ rebuild lexical/semantic indexes
→ verify counts, hashes, relationships and replay
→ switch authority atomically
→ retain encrypted rollback backup for declared period
→ delete only after user policy and successful soak
```

Migration must be restartable and must not duplicate effects or lose audit identity.

## M.7 Vertical product slices

Mandatory slices, each passing Windows/macOS/Linux before final GA:

```text
V1: chat + local/API model + files + evidence
V2: coding + PTY + browser verification
V3: Gmail/calendar + authenticated browser/connector
V4: hotel booking + transaction policy + takeover
V5: application generation + deployment preview
V6: content campaign + provider orchestration
V7: native desktop workflow + Owner Mode kill/recovery
V8: create and run a user-defined skill
V9: update, rollback, export, delete and uninstall
```

A slice has one user story, fixture, real-environment smoke test, consumer UX, failure recovery, platform evidence and release receipt.

## M.8 AI context packs

For each task generate a bounded context pack:

```text
task file
relevant ADRs
schemas
exact source files
related tests
last evidence and blocker
platform lane requirements
out-of-scope rules
```

Small local models should never need to load the whole master roadmap to execute one task.

## M.9 P24 implementation phase

| ID | Task | Depends on | Required output | Done when |
|---|---|---|---|---|
| `P24-001` | Approve full roadmap-as-data ADR | `P0-008` | Expand the P0 bootstrap into complete authority, file split, all-task manifest, generation, supersession, and compatibility rules | No competing roadmap authority remains and the bootstrap migration is defined without losing status or evidence links. |
| `P24-002` | Split master roadmap into bounded phase/task files | `P24-001` | Generated navigation and compatibility MASTER | Content hashes and cross-links prove no task loss. |
| `P24-003` | Expand roadmap manifest schema and validator | `P24-001` | Extend the P0 bootstrap to all IDs, dependencies, cycles, gates, status, evidence, platform impact, supersession, and release-claim validation | Invalid fixture classes fail CI and the generated all-task manifest matches this master document exactly. |
| `P24-004` | Implement requirement/claim traceability | `P24-003,P23-006` | Promise→requirement→capability→test→evidence graph | Unsupported marketing claim cannot be generated. |
| `P24-005` | Approve no-SQL local authority ADR | `P1-001,P24-001` | Measure candidate embedded object/document engines against the retained SQLite durability baseline; specify journal/object/index architecture, compatibility adapter, migration, rollback, and abort criteria | Human owner approves the selected target only after it equals the blocking durability evidence; otherwise SQLite remains authoritative behind the abstraction and the task stays blocked. |
| `P24-006` | Build embedded authority abstraction | `P24-005` | Transaction, query, watch, migration, backup and corruption interfaces | Reference implementation passes durability suite. |
| `P24-007` | Implement SQLite-to-object migration | `P24-006,P8-002` | Restartable migration, verification and rollback | Historical fixtures preserve IDs, events and content hashes. |
| `P24-008` | Replace core SQL-specific indexes | `P24-006,P4-013` | Rebuildable lexical and optional semantic/graph indexes | Full function survives index deletion and rebuild. |
| `P24-009` | Create vertical slice suite | `P24-003,P22-004,P23-019` | V1–V9 scenarios and evidence manifests | Every slice runs on all mandatory desktop OSs. |
| `P24-010` | Generate AI context packs | `P24-002,P24-003` | Bounded task bundles and freshness checks | Local model executes sampled tasks without whole-roadmap context. |
| `P24-011` | Implement documentation and acceptance lint | `P24-003` | Missing criteria, ambiguous verbs, stale links, uncited standards and duplicate authority checks | Seeded documentation defects fail CI. |
| `P24-012` | Roadmap integrity and storage release gate | `P24-001` through `P24-011` | Manifest, traceability, no-SQL migration, vertical slices and context-pack report | Gate V passes before final capability freeze. |

### P24 exit gate

- One human-readable master and one machine-readable manifest control execution.
- Older roadmaps are clearly superseded.
- Task dependencies and evidence are CI-validated.
- Every public promise is traceable to passing evidence.
- The production core runs without a SQL-specific authority **only after** the verified P24 migration; before that cutover SQLite remains the declared authority.
- Historical data migrates with verification and rollback.
- Vertical slices prove complete user outcomes across all desktop platforms.
- Local implementation models receive bounded context packs.

## M.10 Gate V — Roadmap integrity and no-SQL authority

Block release when roadmap drift, task ambiguity, missing traceability, SQL-core dependency, failed migration, missing vertical slice, or stale implementation context remains.

---

# Appendix N — Updated final dependency and release rule

`P20-001` may begin only after all of the following are `DONE`:

```text
P11-015 omni-platform Owner/isolation gate
P12-014 identity/connector gate
P13-014 application factory gate
P14-014 content manufacturing gate
P15-010 native automation gate
P16-012 deployment/fleet gate
P17-010 realtime/omnichannel gate
P18-011 model/hardware gate
P19-010 ecosystem conformance gate
P21-024 provider orchestration gate
P22-018 consumer productization gate
P23-024 tool/skill/capability OS gate
P24-012 roadmap integrity and no-SQL gate
```

The maximum-capability release is not GA until Gates A–V pass on every applicable mandatory platform and hardware profile.

---

# Appendix O — Updated first execution sequence after P21

After the existing foundation and P21 sequence, execute:

```text
1. P23-001 ontology ADR
2. P23-002 Agent Skills compatibility
3. P23-003 signed skill manifest
4. P23-004 capability descriptor v4
5. P23-005 tool contract standard
6. P23-006 capability graph and resolver
7. P24-001 roadmap-as-data ADR
8. P24-003 roadmap validator
9. P24-005 no-SQL storage ADR
10. P22-001 consumer product contract
11. P22-003 first-run state machine
12. P23-007 token-efficient discovery
13. P23-008 skill validator
14. P23-009 skill compiler
15. P23-010 durable skill runtime
16. P22-004 Simple Mode
17. P22-006 hardware certification harness
18. P23-012 tool/skill health
19. P23-013 transaction and lock coordinator
20. P23-014 Skill Studio basic
21. P22-007 failure translation
22. P22-008 Repair Mode
23. P24-006 embedded authority abstraction
24. P24-007 migration
25. P23-018 skill evaluation harness
26. P23-019 through P23-021 Gold Skills
27. P22-015 non-technical beta
28. P24-009 vertical slice suite
29. P23-024 Gate U
30. P22-018 Gate T
31. P24-012 Gate V
32. P20-001 final capability freeze
```

Parallel work is allowed only when dependencies and shared-schema ownership permit it.

---

# Appendix P — Additional official standards and current references

Pin exact reviewed versions in `docs/roadmap/standards.lock.yaml` and re-review before beta, RC and GA.

```text
Agent Skills open format:
https://agentskills.io/specification
https://agentskills.io/home

OpenAI skills and agents:
https://openai.com/academy/skills/
https://help.openai.com/en/articles/20001066-skills-in-chatgpt
https://platform.openai.com/docs/

Model Context Protocol:
https://modelcontextprotocol.io/specification/

Agent2Agent Protocol:
https://a2a-protocol.org/v1.0.0/

JSON Schema 2020-12:
https://json-schema.org/draft/2020-12

OAuth 2.0 Security Best Current Practice:
https://www.rfc-editor.org/rfc/rfc9700

OpenAPI:
https://spec.openapis.org/oas/latest.html

The Update Framework:
https://theupdateframework.io/

SLSA:
https://slsa.dev/spec/

C2PA:
https://spec.c2pa.org/specifications/

WCAG 2.2 and non-web guidance:
https://www.w3.org/TR/WCAG22/
https://www.w3.org/TR/wcag2ict-22/
```

Time-sensitive provider, protocol, skills, platform and policy facts must be stored with retrieval date, content digest, reviewed scope, owner and expiry.

---

# Appendix Q — Final top-tier claim language

Allowed only after every applicable gate passes:

> Kristin is a locally governed, omni-platform AI operating system that can coordinate supported local and external AI providers, use verified tools and portable skills, operate the owner-authorized computer and connected accounts, generate and deploy applications, manufacture multimodal content, perform authenticated web and desktop workflows, and recover from long-running execution with evidence. Supported capabilities, providers, platforms, skills, hardware profiles and limitations are generated from current conformance results.

Never claim:

```text
works with every provider or website forever
runs every local model on minimum hardware
browser subscriptions equal API access or unlimited automation
Owner Mode is a sandbox
all external effects are reversible
all tools or skills are safe because they are signed
one aggregate benchmark proves every capability
consumer ready before P22
skill operating system ready before P23
local-first no-SQL ready before P24
```

---

# Appendix R — Final master go/no-go checklist

A top-tier GA requires machine-verifiable answers to all prior questions plus:

```text
Can a clean non-developer machine reach a verified first task?
Can the declared minimum machine remain responsive under supported load?
Can the user understand and recover from common failures?
Can the user inspect cost, provider, account and outbound data?
Can the user export, delete, revoke, repair and uninstall?
Does every tool implement the Tool Contract Standard?
Does every capability have current health and evidence?
Can a small local model discover the correct bounded tool set?
Can portable Agent Skills import/export without lock-in?
Can skills compile reproducibly into durable task graphs?
Can skill updates expand no authority without approval?
Do Gold Skills pass user-outcome, security and platform gates?
Does the core operate without SQL?
Can historical data migrate and roll back safely?
Is every public promise traceable to evidence?
Can a future AI execute one task without reading the full roadmap?
```

If any mandatory answer is missing, the build is an internal preview, alpha, beta, or RC—not the top-tier consumer GA.

