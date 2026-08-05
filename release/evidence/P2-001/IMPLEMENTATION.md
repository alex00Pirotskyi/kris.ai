# P2-001 — Owner Mode onboarding and settings implementation

## Contract

Explicit enablement, persistent indicator, approval policy, data boundary, disable/reset controls.

## Done condition

User can choose full access and UI never mislabels it as sandboxed.

## Governed artifacts

- `lib/product/p2_owner_mode.dart`
- `config/p2_owner_mode.v1.json`
- `lib/product/p2_owner_workspace.dart`
- `test/product/p2_owner_mode_test.dart`
- `test/product/p2_owner_workspace_test.dart`

## Assurance status

V63 contains source/local gates and the production product-to-worker composition, but this task is not DONE. Completion requires task-specific exact-source Windows, macOS, and Linux product-path receipts from governed interactive desktop lanes, explicit owner approval, and an independent commit-bound security review. `source_only`, helper-only, `blocked`, `unsupported`, `skipped`, `absent`, malformed, and `not_tested` evidence can never become `passed`.
