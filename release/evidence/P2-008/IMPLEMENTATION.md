# P2-008 — Service and application control implementation

## Contract

Service status/start/stop and application open/close adapters with platform-specific implementations.

## Done condition

Supported operations return honest status and rollback notes.

## Governed artifacts

- `lib/product/p2_automation_host_operations.dart`
- `automation_host/src/host-operations.mjs`
- `docs/architecture/P2_PLATFORM_SUPPORT_MATRIX.md`
- `test/product/p2_automation_host_operations_test.dart`
- `lib/product/p2_runtime_composition.dart`
- `lib/product/p2_automation_host_process_client.dart`
- `lib/product/p2_effect_journal.dart`
- `test/product/p2_shipped_product_runtime_e2e_test.dart`

## Assurance status

V63 contains source/local gates and the production product-to-worker composition, but this task is not DONE. Completion requires task-specific exact-source Windows, macOS, and Linux product-path receipts from governed interactive desktop lanes, explicit owner approval, and an independent commit-bound security review. `source_only`, helper-only, `blocked`, `unsupported`, `skipped`, `absent`, malformed, and `not_tested` evidence can never become `passed`.
