# MISSION-005 — Experience Platform and Consumer Productization

**Default executor:** Worker F
**Priority:** `HIGH`
**Roadmap phases:** `P5`, `P22`
**Authority:** execution overlay only; `docs/roadmap/MASTER.md` remains human authority.

## Mission objective

Create the information architecture, Simple Mode, advanced workspaces, Verification Center presentation, accessibility, onboarding, localization, support, cost transparency, and consumer experience assurance.

## Transfer and resume protocol

1. Re-resolve protected main, mission branch, PR, head/tree, CI, reviews, and dependency state.
2. Load this contract, the mission state, active claim, latest checkpoint, entry graph, and task interlocks.
3. Reuse valid implementation and evidence already present; never restart completed work without a proven defect.
4. Select the highest-priority dependency-satisfied task or a clearly labeled dependency-safe source/fixture/documentation packet.
5. Implement, test, document, commit, push, inspect exact-head CI, repair, obtain required independent review, and update state/checkpoint.
6. Yield only with an exact continuation point or complete the mission and release its claim.

## Current repository anchor

- Worker: `F`
- Branch: `agent/f/P5-001-information-architecture`
- Draft PR: `#72`
- Observed head: `fd89a66925b90c75448ef33583349b90ca88531b`
- Observed tree: `UNRESOLVED`
- Current work: P5-001 bounded information architecture and UX prototype; exact tri-platform handoff remains unsettled
- These are discovery anchors, not permission to skip live-state discovery.

## P5 — UX/UI redesign and accessibility

**Packet:** `docs/roadmap/anarchy/phases/P05-ux-ui-redesign-and-accessibility.md`
**Current execution view:** `READY_PARALLEL_P5_001`
**Test Center module:** `User Experience & Accessibility`

### Purpose

This is the bounded execution packet for P5. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P5-001` | Information architecture and UX flows | `P0-008` | Specify navigation, workspaces, jobs-to-be-done, and state transitions. | Clickable or coded flow prototype covers primary scenarios. |
| `P5-002` | Design token system | `P5-001` | Define semantic color, type, spacing, elevation, focus, motion, status, and Owner Mode tokens. | Light, dark, high-contrast, and reduced-motion themes pass. |
| `P5-003` | Reusable component library | `P5-002` | Build buttons, fields, dialogs, split panes, tabs, cards, tables, timelines, badges, empty/error states. | Components have widget, golden, and semantics tests. |
| `P5-004` | Three-pane application shell | `P5-001`, `P5-003` | Implement resizable left rail, center workspace, right inspector, and bottom activity drawer. | Layouts persist and handle minimum window size. |
| `P5-005` | Global autonomy status and kill | `P2-011`, `P5-004` | Display profile, model, active sessions, takeover, network, pause, stop, and emergency kill. | Status remains visible across workspaces. |
| `P5-006` | Chat and task composer redesign | `P5-003`, `P5-004` | Add attachments, project/profile/model/access, plan-only, run, schedule, criteria, and budget. | Composer supports keyboard-only task launch. |
| `P5-007` | Plan review and permission UX | `P1-004`, `P5-006` | Show goals, files, commands, sites, side effects, verification, risk, and profile. | Owner approval policy never is represented accurately. |
| `P5-008` | Unified run timeline | `P5-004` | Render model, policy, file, terminal, browser, web, evidence, verification, retries, and rollback. | Timeline handles 10k events with filtering. |
| `P5-009` | Artifact, diff, and evidence viewers | `P5-003` | Add text/binary metadata, image, Markdown, JSON, table, diff, citation, and receipt views. | All supported evidence types reopen from a saved run. |
| `P5-010` | Command palette and keyboard system | `P5-004` | Add searchable commands, shortcuts, conflict handling, and discoverability. | Primary workflows are keyboard complete. |
| `P5-011` | Onboarding and capability doctor | `P2-001`, `P3-001`, `P4-001` | Guide model, Owner Mode, browser, terminal, search providers, storage, and diagnostics. | Fresh machine reaches a tested working state. |
| `P5-012` | Accessibility compliance program | `P5-003` | Add semantics, focus, contrast, scaling, reduced motion, target sizes, and manual checklist. | Applicable WCAG 2.2 AA checks pass. |
| `P5-013` | UI performance budgets | `P5-004` | Instrument startup, frame time, list virtualization, stream throttling, and memory. | Performance dashboard meets initial targets. |
| `P5-014` | UX regression suite | `P5-006`, `P5-008`, `P5-009`, `P5-012` | Add widget, golden, navigation, semantics, keyboard, and failure-state tests. | Critical flow change cannot merge without tests. |
| `P5-015` | Human usability review | `P5-011`, `P5-014` | Run scripted sessions with representative users; record findings and fixes. | No unresolved critical usability blocker before RC. |

### Test Center deliverables

- `P5-TC-001` navigation/state-transition scenarios
- `P5-TC-002` design-token golden and contrast tests
- `P5-TC-003` component widget/semantics tests
- `P5-TC-004` three-pane persistence and minimum-size tests
- `P5-TC-005` global autonomy/kill visibility tests
- `P5-TC-006` composer keyboard-only acceptance
- `P5-TC-007` plan/permission comprehension tests
- `P5-TC-008` 10k-event timeline performance tests
- `P5-TC-009` artifact/evidence reopen tests
- `P5-TC-010` command-palette and shortcut conflicts
- `P5-TC-011` onboarding/capability-doctor E2E
- `P5-TC-012` accessibility automated/manual program
- `P5-TC-013` startup/frame/memory budgets
- `P5-TC-014` UI regression suite
- `P5-TC-015` human usability evidence

### Acceptance scenarios

- `P5-ACC-001` complete primary task with keyboard only
- `P5-ACC-002` enable and disable Owner Mode with correct persistent status
- `P5-ACC-003` pause/stop from every workspace
- `P5-ACC-004` reopen run evidence after restart
- `P5-ACC-005` screen reader announces takeover and completion
- `P5-ACC-006` high-contrast and scaled-text layouts remain usable
- `P5-ACC-007` non-technical user understands one recovery message

### Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Primary workspaces are coherent, keyboard accessible, and measurable.
- Owner Mode and kill state are always visible.
- Run, browser, terminal, research, data, and evidence flows pass UI tests.
- Accessibility and performance gates pass.

## P22 — Consumer productization and experience assurance

**Packet:** `docs/roadmap/anarchy/phases/P22-consumer-productization-and-experience-assurance.md`
**Current execution view:** `BLOCKED_BY_CORE_UX_AND_PROVIDER_FOUNDATIONS`
**Test Center module:** `Consumer Readiness`

### Purpose

This is the bounded execution packet for P22. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P22-001` | Approve consumer product contract ADR | `P5-001`, `P21-001` | Promises, exclusions, Simple/Advanced/Developer modes, support and evidence rules | No marketing or UX ambiguity remains. |
| `P22-002` | Define consumer metrics and telemetry | `P22-001`, `P8-010` | Privacy-preserving funnel, success, recovery, hardware and comprehension metrics | Metrics can be measured without collecting task content by default. |
| `P22-003` | Implement resumable first-run state machine | `P5-011`, `P22-001` | Cross-platform onboarding, resume, reset and failure recovery | Clean fixtures complete without terminal or developer runtime. |
| `P22-004` | Implement Simple Mode | `P5-006`, `P21-007`, `P23-006` | One-composer experience with intelligent defaults and concise route disclosure | Representative tasks complete without exposing internal architecture. |
| `P22-005` | Implement Advanced and Developer modes | `P22-004`, `P5-010` | Progressive controls, searchable settings, safe mode switching | Explicit provider/tool/profile choices remain hard constraints. |
| `P22-006` | Build hardware certification harness | `P18-002`, `P8-011` | Minimum/recommended/creator tri-OS images and resource tests | Published hardware claims match passing evidence. |
| `P22-007` | Build consumer failure translation layer | `P22-001`, `P8-003` | Stable consumer states mapped from subsystem errors | User studies meet comprehension target. |
| `P22-008` | Implement Repair Mode | `P22-003`, `P22-007`, `P9-009` | Detect, explain, repair, verify and rollback known installation/runtime failures | Injected failures recover at target rate. |
| `P22-009` | Implement cost and quota center | `P21-009`, `P22-004` | Estimates, hard budgets, reconciled use, browser-subscription qualification | No route is represented as free without evidence. |
| `P22-010` | Implement data and account control center | `P12-004`, `P21-005`, `P8-010` | Export, delete, revoke, clear profiles, disclosure history and reset | Deletion/export fixtures pass and secrets are not reproduced. |
| `P22-011` | Implement Owner Mode comprehension UX | `P2-001`, `P5-005`, `P22-001` | First-enable education, persistent status, action summaries, kill and disable | Non-technical study meets comprehension threshold. |
| `P22-012` | Complete localization foundation | `P5-012`, `P22-004` | Locale architecture, string extraction, date/currency, RTL readiness and language matrix | Declared language smoke and layout tests pass. |
| `P22-013` | Complete accessibility consumer gate | `P5-012`, `P22-004`, `P22-003` | Keyboard, screen reader, scaling, contrast, motion, captions and takeover flows | Critical flows pass automated and human audit. |
| `P22-014` | Implement support and diagnostic bundle | `P8-009`, `P22-007`, `P22-008` | Previewable redacted bundle, support code, known issues and status integration | Seeded secrets and private content are excluded by default. |
| `P22-015` | Run non-technical tri-OS beta | `P22-003`, `P22-014` | Balanced cohort, task recordings with consent, findings and fixes | Primary task, recovery and trust metrics meet targets. |
| `P22-016` | Implement uninstall and local-data removal verification | `P9-005`, `P9-006`, `P9-007`, `P22-010` | Process, helper, cache, profile, model and credential cleanup matrix | Clean-machine before/after tests pass. |
| `P22-017` | Consumer claim generator | `P22-002`, `P24-004` | User-facing capability, hardware, privacy and limitation text from evidence | Handwritten unsupported claims fail CI. |
| `P22-018` | Consumer productization release gate | `P22-001`, `P22-017` | Tri-OS report, hardware certification, usability, support, privacy and accessibility evidence | Gate T passes with no critical experience, safety or support blocker. |

### Test Center deliverables

- `P22-TC-001` product-promise contract
- `P22-TC-002` privacy-preserving metrics
- `P22-TC-003` resumable first-run E2E
- `P22-TC-004` Simple Mode user-outcome tests
- `P22-TC-005` Advanced/Developer constraint preservation
- `P22-TC-006` hardware certification harness
- `P22-TC-007` failure-message comprehension
- `P22-TC-008` Repair Mode injected failures
- `P22-TC-009` cost/quota transparency
- `P22-TC-010` export/delete/revoke/reset
- `P22-TC-011` Owner Mode comprehension
- `P22-TC-012` localization/RTL foundation
- `P22-TC-013` accessibility consumer gate
- `P22-TC-014` support-bundle privacy
- `P22-TC-015` non-technical tri-OS beta
- `P22-TC-016` uninstall/data-removal verification
- `P22-TC-017` claim-generation lint
- `P22-TC-018` consumer release certification

### Acceptance scenarios

- `P22-ACC-001` clean non-developer machine reaches first verified task
- `P22-ACC-002` one provider connects without terminal/manual runtime
- `P22-ACC-003` known broken sidecar is repaired and verified
- `P22-ACC-004` user exports and deletes selected data
- `P22-ACC-005` Owner Mode comprehension questions meet threshold
- `P22-ACC-006` uninstall leaves no undeclared process, secret, profile or cache

### Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- A clean supported machine reaches a verified first task without a developer toolchain.
- Simple Mode hides internal complexity while respecting explicit constraints.
- Hardware claims are measured on Windows, macOS and Linux.
- Owner Mode risk and current authority are understood by representative users.
- Common failures have understandable, actionable, verified recovery.
- Cost, provider, account and outbound data are visible.
- Export, deletion, revoke, repair, update, rollback and uninstall pass.
- Accessibility, localization foundation and support readiness pass.

## Cross-mission task interlocks

- `P22-001` waits for `P21-001` from `MISSION-011`.
- `P22-002` waits for `P8-010` from `MISSION-002`.
- `P22-004` waits for `P21-007` from `MISSION-011`.
- `P22-004` waits for `P23-006` from `MISSION-007`.
- `P22-006` waits for `P18-002` from `MISSION-006`.
- `P22-006` waits for `P8-011` from `MISSION-002`.
- `P22-007` waits for `P8-003` from `MISSION-002`.
- `P22-008` waits for `P9-009` from `MISSION-008`.
- `P22-009` waits for `P21-009` from `MISSION-011`.
- `P22-010` waits for `P12-004` from `MISSION-011`.
- `P22-010` waits for `P21-005` from `MISSION-011`.
- `P22-010` waits for `P8-010` from `MISSION-002`.
- `P22-011` waits for `P2-001` from `MISSION-001`.
- `P22-014` waits for `P8-009` from `MISSION-002`.
- `P22-016` waits for `P9-005` from `MISSION-008`.
- `P22-016` waits for `P9-006` from `MISSION-008`.
- `P22-016` waits for `P9-007` from `MISSION-008`.
- `P22-017` waits for `P24-004` from `MISSION-015`.
- `P5-001` waits for `P0-008` from `MISSION-001`.
- `P5-005` waits for `P2-011` from `MISSION-001`.
- `P5-007` waits for `P1-004` from `MISSION-001`.
- `P5-011` waits for `P2-001` from `MISSION-001`.
- `P5-011` waits for `P3-001` from `MISSION-003`.
- `P5-011` waits for `P4-001` from `MISSION-004`.

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
Take the repo. You are Worker F. Take MISSION-005 and continue autonomously.
```
