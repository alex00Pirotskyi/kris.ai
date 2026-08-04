# P2-010 — Best-effort host snapshots and undo implementation

## Contract

File backups, Git checkpoints, restore points where available, and operation receipts.

## Done condition

Injected failures restore supported file changes and mark non-restorable effects.

## Governed artifacts

- `lib/product/p2_snapshot_undo.dart`
- `lib/product/p2_desktop_effect_authorizers.dart`
- `lib/product/p2_effect_journal.dart`
- `test/product/p2_snapshot_undo_test.dart`
- `lib/product/p2_runtime_composition.dart`
- `lib/product/p2_automation_host_process_client.dart`
- `lib/product/p2_effect_journal.dart`
- `test/product/p2_shipped_product_runtime_e2e_test.dart`

## Assurance status

V63 contains source/local gates and the production product-to-worker composition, but this task is not DONE. Completion requires task-specific exact-source Windows, macOS, and Linux product-path receipts from governed interactive desktop lanes, explicit owner approval, and an independent commit-bound security review. `source_only`, helper-only, `blocked`, `unsupported`, `skipped`, `absent`, malformed, and `not_tested` evidence can never become `passed`.
