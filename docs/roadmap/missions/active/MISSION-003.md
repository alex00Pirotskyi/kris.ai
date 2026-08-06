# MISSION-003 — Browser Automation and Web Studio

**Default executor:** Worker D
**Priority:** `HIGH`
**Roadmap phases:** `P3`
**Authority:** execution overlay only; `docs/roadmap/MASTER.md` remains human authority.

## Mission objective

Deliver a real bundled browser runtime, deterministic browser sessions, actions, profiles, downloads, uploads, recovery, security boundaries, and the complete Web Studio vertical slice.

## Transfer and resume protocol

1. Re-resolve protected main, mission branch, PR, head/tree, CI, reviews, and dependency state.
2. Load this contract, the mission state, active claim, latest checkpoint, entry graph, and task interlocks.
3. Reuse valid implementation and evidence already present; never restart completed work without a proven defect.
4. Select the highest-priority dependency-satisfied task or a clearly labeled dependency-safe source/fixture/documentation packet.
5. Implement, test, document, commit, push, inspect exact-head CI, repair, obtain required independent review, and update state/checkpoint.
6. Yield only with an exact continuation point or complete the mission and release its claim.

## Current repository anchor

- Worker: `D`
- Branch: `agent/d/p3-readiness-fixtures`
- Draft PR: `#68`
- Observed head: `7eecc840f68ca0dff13ab58c138845593254e390`
- Observed tree: `2080824a34956e3b202126a0a9bd61b4d645d338`
- Current work: P3 browser-runtime readiness source foundation; P3-001 blocked by P2-004 evidence
- These are discovery anchors, not permission to skip live-state discovery.

## P3 — Browser automation and Web Studio

**Packet:** `docs/roadmap/anarchy/phases/P03-browser-automation-and-web-studio.md`
**Current execution view:** `BLOCKED_BY_P2_DEPENDENCIES`
**Test Center module:** `Browser & Web Studio`

### Purpose

This is the bounded execution packet for P3. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P3-001` | Bundle browser automation runtime | `P2-004`, `P1-012` | Pin automation host dependencies and browser binaries; create reproducible packaging. | Clean machine launches the bundled worker without a global runtime. |
| `P3-002` | Browser session service | `P3-001`, `P1-003` | Create ephemeral and persistent contexts, pages, profile selection, quotas, and cleanup. | Isolation and lifecycle tests pass. |
| `P3-003` | Canonical page observation | `P3-002` | Capture URL, title, DOM, accessibility tree, forms, visible text, screenshot, console, and network summary. | Observation hashes are stable on deterministic fixtures. |
| `P3-004` | Locator and action engine | `P3-003` | Implement click, type, fill, select, check, press, scroll, hover, drag, and wait with locator priority. | Fixture actions pass without coordinate fallback. |
| `P3-005` | Visual fallback | `P3-003`, `P3-004` | Add screenshot-based target selection only after structured locators fail, with confidence and verification. | Low-confidence actions pause instead of guessing. |
| `P3-006` | Downloads and uploads | `P3-002`, `P3-004` | Add controlled downloads, hashes, quarantine, file chooser handling, and upload receipts. | Download/upload fixtures pass and paths remain profile-scoped. |
| `P3-007` | Console, network, and trace capture | `P3-002` | Capture errors, requests, responses, timing, WebSocket summary, HAR/trace where supported. | Failed browser run exports a bounded replay bundle. |
| `P3-008` | Authentication profile storage | `P1-009`, `P3-002` | Protect cookies/storage, support personal/work profiles, export/delete, and no-model-context default. | Cross-profile leakage tests pass. |
| `P3-009` | User takeover state machine | `P3-002`, `P3-004` | Implement visible control transfer for MFA, CAPTCHA, payment, consent, and ambiguity. | Agent resumes only after re-observation. |
| `P3-010` | Browser action verification | `P3-003`, `P3-004` | Require postconditions and independent final verification for web tasks. | False-completion fixtures are rejected. |
| `P3-011` | Browser workspace UI | `P3-002`, `P3-007`, `P3-009` | Add tabs, URL, profile, agent/user control, action target, screenshot, extract, and trace. | Primary browser workflow is keyboard accessible. |
| `P3-012` | Web Studio editor | `P3-001` | Add file tree, code editor, diagnostics, format, search, diff, and source control hooks. | HTML/CSS/JS project can be edited and saved. |
| `P3-013` | Live preview and development server | `P3-012`, `P2-006` | Support static preview, configured dev server, readiness probe, hot reload, and stop. | Static and framework fixtures preview reliably. |
| `P3-014` | DOM, console, network inspector | `P3-003`, `P3-007`, `P3-011` | Expose structured page internals and link DOM selection to source when possible. | Inspector handles large pages without freezing UI. |
| `P3-015` | Responsive, accessibility, and visual test tools | `P3-013`, `P3-014` | Add viewports, screenshots, diff, accessibility checks, link/form checks. | Fixture defects are detected with actionable evidence. |
| `P3-016` | Deterministic browser fixture site | `P3-001` | Build local pages for auth, JS render, forms, downloads, uploads, popup, iframe, infinite scroll, injection, and takeover. | Browser CI has no external-network dependency. |
| `P3-017` | Browser security suite | `P3-002`, `P3-006`, `P3-008`, `P3-009`, `P3-016` | Test profile leakage, malicious downloads, prompt injection, tab confusion, redirects, and stale targets. | No unresolved critical/high browser finding. |
| `P3-018` | Browser task recipes | `P3-010`, `P3-011` | Ship recipes for research, form completion, authenticated download, web testing, and data extraction. | Recipes run against fixtures and produce receipts. |

### Test Center deliverables

- `P3-TC-001` bundled-runtime clean-machine launch test
- `P3-TC-002` browser-session lifecycle and profile isolation
- `P3-TC-003` canonical observation stability
- `P3-TC-004` locator/action engine fixtures
- `P3-TC-005` visual-fallback confidence tests
- `P3-TC-006` upload/download quarantine and hash tests
- `P3-TC-007` console/network/trace export tests
- `P3-TC-008` protected authentication-profile tests
- `P3-TC-009` takeover state-machine tests
- `P3-TC-010` browser postcondition verification
- `P3-TC-011` browser workspace widget/E2E tests
- `P3-TC-012` editor and source-control hook tests
- `P3-TC-013` live preview/readiness/hot-reload tests
- `P3-TC-014` inspector large-page performance tests
- `P3-TC-015` responsive/a11y/visual tests
- `P3-TC-016` deterministic fixture-site suite
- `P3-TC-017` browser adversarial certification
- `P3-TC-018` recipe acceptance pack

### Acceptance scenarios

- `P3-ACC-001` open local fixture page from composer
- `P3-ACC-002` fill and submit form, verify server-side result
- `P3-ACC-003` upload fixture, verify received hash
- `P3-ACC-004` download fixture, verify MIME and hash
- `P3-ACC-005` login fixture with user takeover
- `P3-ACC-006` detect CAPTCHA placeholder and request takeover
- `P3-ACC-007` reject stale target after DOM mutation
- `P3-ACC-008` capture trace for failed workflow
- `P3-ACC-009` edit HTML/CSS/JS and verify preview
- `P3-ACC-010` find accessibility defect and link it to evidence

### Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Browser sessions, actions, profiles, downloads/uploads, takeover, traces, and verification work against deterministic fixtures.
- Web Studio can edit and preview HTML/CSS/JavaScript.
- Cross-profile leakage and blind-action tests pass.

## Cross-mission task interlocks

- `P3-001` waits for `P1-012` from `MISSION-001`.
- `P3-001` waits for `P2-004` from `MISSION-001`.
- `P3-002` waits for `P1-003` from `MISSION-001`.
- `P3-008` waits for `P1-009` from `MISSION-001`.
- `P3-013` waits for `P2-006` from `MISSION-001`.

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
Take the repo. You are Worker D. Take MISSION-003 and continue autonomously.
```
