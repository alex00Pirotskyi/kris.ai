---
phase: P14
title: "Content manufacturing and publishing"
execution_view_status: BLOCKED_BY_CONTENT_AND_PROVIDER_FOUNDATIONS
primary_workers: [F, G, H]
test_center_module: "Content Factory"
source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md
live_authority: ../../MASTER.md
---

# P14 — Content manufacturing and publishing

## Purpose

This is the bounded execution packet for P14. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

## Current execution view

- Status: `BLOCKED_BY_CONTENT_AND_PROVIDER_FOUNDATIONS`
- Primary workers: Worker F, Worker G, Worker H
- Test Center module: `Content Factory`
- Authority note: this file does not independently mark tasks complete.

## Task backlog

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

## Test Center deliverables

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

## Acceptance scenarios

- `P14-ACC-001` one brief creates three channel variants
- `P14-ACC-002` editable source reopens and reproduces render
- `P14-ACC-003` restricted asset cannot publish
- `P14-ACC-004` interrupted video render resumes
- `P14-ACC-005` spreadsheet formulas remain formulas and recalculate

## Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Image, audio, video, document, spreadsheet, and presentation projects are editable and reproducible.
- Publishing is account-, rights-, and transaction-policy aware.
- Content provenance and channel receipts are retained.

## Parallel execution rules

1. Claim one task before editing.
2. Do not implement a task whose dependencies are incomplete unless the task packet explicitly authorizes dependency-safe contracts, fixtures, or documentation.
3. Shared schemas and authorities require an ownership lock or integration packet.
4. Every completed change updates the owning worker file and exact-commit evidence.
5. Source-only foundations retain `SOURCE_FOUNDATION` or equivalent classification until behavioral evidence exists.

## Worker resume command

```text
Take the repo. You are Worker F. Continue the highest-priority dependency-satisfied P14 task.
```
