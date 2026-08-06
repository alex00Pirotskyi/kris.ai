# MISSION-013 — Content Manufacturing and Publishing

**Default executor:** Worker F
**Priority:** `MEDIUM`
**Roadmap phases:** `P14`
**Authority:** execution overlay only; `docs/roadmap/MASTER.md` remains human authority.

## Mission objective

Build the asset graph and reproducible manufacturing pipelines for documents, PDFs, spreadsheets, presentations, images, vector graphics, audio, video, subtitles, campaigns, social variants, datasets, brand controls, and publishing.

## Transfer and resume protocol

1. Re-resolve protected main, mission branch, PR, head/tree, CI, reviews, and dependency state.
2. Load this contract, the mission state, active claim, latest checkpoint, entry graph, and task interlocks.
3. Reuse valid implementation and evidence already present; never restart completed work without a proven defect.
4. Select the highest-priority dependency-satisfied task or a clearly labeled dependency-safe source/fixture/documentation packet.
5. Implement, test, document, commit, push, inspect exact-head CI, repair, obtain required independent review, and update state/checkpoint.
6. Yield only with an exact continuation point or complete the mission and release its claim.

## Current repository anchor

- No active claim. The mission is available only when its entry dependencies and ownership checks pass.

## P14 — Content manufacturing and publishing

**Packet:** `docs/roadmap/anarchy/phases/P14-content-manufacturing-and-publishing.md`
**Current execution view:** `BLOCKED_BY_CONTENT_AND_PROVIDER_FOUNDATIONS`
**Test Center module:** `Content Factory`

### Purpose

This is the bounded execution packet for P14. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P14-001` | Content project and asset graph | `P4-011`, `P12-006` | Schemas, object storage, lineage and versions | Derived assets reproduce from retained recipes/inputs. |
| `P14-002` | Provider-neutral generation adapters | `P6-001`, `P14-001` | Text/image/audio/video generation interfaces | Two fixture providers per modality pass shared contracts where available. |
| `P14-003` | Deterministic media worker | `P14-001`, `P11-010` | FFmpeg/image/PDF probe and render jobs | Cross-platform media fixtures produce validated outputs. |
| `P14-004` | Image workspace | `P14-002`, `P14-003` | Layer/mask/edit/generate/batch/compare | Saved project reopens and renders variants. |
| `P14-005` | Audio workspace | `P14-002`, `P14-003` | Transcribe/synthesize/mix/render/transcript | Timing, loudness, captions, consent and export tests pass. |
| `P14-006` | Video workspace | `P14-002`, `P14-003` | Storyboard/timeline/subtitles/dubbing/render queue | Interrupted render resumes and outputs validate. |
| `P14-007` | Document/PDF pipeline | `P14-001` | Editable docs, pagination, accessibility, PDF validation | Rendered page inspection and structure checks pass. |
| `P14-008` | Spreadsheet pipeline | `P14-001` | Formulas, models, charts, recalculation and exports | Formula lineage/error and reopen tests pass. |
| `P14-009` | Presentation pipeline | `P14-001` | Themes/layouts/notes/render/overflow checks | Slides render without overflow and remain editable. |
| `P14-010` | Brand policy engine | `P14-004`, `P14-007`, `P14-009` | Brand kit, validation and repair | Cross-format brand violations are detected. |
| `P14-011` | Rights and consent ledger | `P12-001`, `P14-001` | License, attribution, voice/likeness consent model | Restricted asset cannot publish outside policy. |
| `P14-012` | C2PA provenance | `P1-006`, `P14-001` | Create/validate content credentials for supported formats | Tamper, missing trust, version and derivation tests pass. |
| `P14-013` | Publishing connector layer | `P12-012`, `P12-013`, `P14-010` | Preview/schedule/publish/reconcile/analytics | Fixture channels publish, edit/unpublish and return receipts. |
| `P14-014` | Campaign Factory benchmark | `P14-004`, `P14-013` | One brief to multi-channel campaign corpus | Three+ variants, rights, brand, accessibility and provenance gates pass. |

### Test Center deliverables

- `P14-TC-001` asset graph reproducibility
- `P14-TC-002` provider-neutral generation contracts
- `P14-TC-003` deterministic media worker
- `P14-TC-004` image project reopen/render
- `P14-TC-005` audio timing/loudness/consent
- `P14-TC-006` video resumable render
- `P14-TC-007` document/PDF structure and visual inspection
- `P14-TC-008` spreadsheet formula/lineage/recalculation
- `P14-TC-009` presentation overflow/editability
- `P14-TC-010` brand validation
- `P14-TC-011` rights/consent enforcement
- `P14-TC-012` C2PA provenance/tamper
- `P14-TC-013` publishing receipts/reconciliation
- `P14-TC-014` campaign benchmark

### Acceptance scenarios

- `P14-ACC-001` one brief creates three channel variants
- `P14-ACC-002` editable source reopens and reproduces render
- `P14-ACC-003` restricted asset cannot publish
- `P14-ACC-004` interrupted video render resumes
- `P14-ACC-005` spreadsheet formulas remain formulas and recalculate

### Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Image, audio, video, document, spreadsheet, and presentation projects are editable and reproducible.
- Publishing is account-, rights-, and transaction-policy aware.
- Content provenance and channel receipts are retained.

## Cross-mission task interlocks

- `P14-001` waits for `P12-006` from `MISSION-011`.
- `P14-001` waits for `P4-011` from `MISSION-004`.
- `P14-002` waits for `P6-001` from `MISSION-006`.
- `P14-003` waits for `P11-010` from `MISSION-010`.
- `P14-011` waits for `P12-001` from `MISSION-011`.
- `P14-012` waits for `P1-006` from `MISSION-001`.
- `P14-013` waits for `P12-012` from `MISSION-011`.
- `P14-013` waits for `P12-013` from `MISSION-011`.

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
Take the repo. You are Worker F. Take MISSION-013 and continue autonomously.
```
