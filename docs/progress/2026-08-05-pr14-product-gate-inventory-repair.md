# PR #14 product-gate inventory and chat-shell repair

## Scope

This change repairs the exact `product-gates` failure observed on PR #14
head `cec0a2d431edc9b972934fcc5898a30a7a1942f8`. It does not start a
new roadmap milestone and does not change the owner-risk QA classification.

## Root cause

The P2 landing introduced governed Dart sources and a chat-first
`P2KristinShell`, while the cumulative release validator still carried a
copied static Dart allowlist and required the older direct
`home: ChatStudio(...)` composition. The stale-source migration also
retained a pre-P1/P2 product allowlist that could quarantine reviewed
sources if invoked.

## Implementation

- `config/p2_source_inventory.v1.json` now records the P2 native Dart
  probe alongside production and test Dart sources.
- `tool/validate_release.py` consumes that inventory for P2 source
  authority and recognizes the governed shell only when ChatStudio is
  the first page.
- `tool/prune_stale_legacy.dart` combines the explicit P2 inventory with
  `SOURCE_MANIFEST.sha256`, validates every path, and fails closed before
  moving files when either authority is absent or malformed.
- Source-contract tests cover chat-first shell ordering, inventory
  alignment, malformed-authority fail-closed markers, and non-destructive
  migration behavior.

## Compatibility and architecture

ChatStudio remains the default consumer workflow. Owner Mode is added as
an explicit second navigation surface; no duplicate application shell,
authority service, process manager, or capability registry is introduced.

## Verification

The protected repair workflow runs the exact P2 inventory test, complete
P1 exit gate, source-only release validator, Git whitespace checks, and
exact changed-path assertions before pushing. Fresh PR product gates then
execute Flutter formatting, analysis, all Dart tests, architecture and
security validation on Windows, macOS, and Linux.

## Claim boundary

This repair restores CI consistency only. It does not provide independent
security approval, production-release eligibility, public-GA eligibility,
or P3 completion evidence.
