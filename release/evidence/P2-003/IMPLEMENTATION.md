# P2-003 — Owner finite command execution implementation

## Contract

Arbitrary direct processes with cwd/env, bounded output, cancellation, and effect records.

## Done condition

Commands run outside projects only in Owner Mode and are fully journaled.

## Governed artifacts

- `lib/product/p2_finite_command_service.dart`
- `lib/product/p2_automation_command_service.dart`
- `lib/product/p2_effect_boundary.dart`
- `automation_host/src/host-operations.mjs`
- `test/product/p2_effect_boundary_test.dart`
- `lib/product/p2_runtime_composition.dart`
- `lib/product/p2_automation_host_process_client.dart`
- `lib/product/p2_effect_journal.dart`
- `test/product/p2_shipped_product_runtime_e2e_test.dart`

## Assurance status

V63 contains source/local gates and the production product-to-worker composition, but this task is not DONE. Completion requires task-specific exact-source Windows, macOS, and Linux product-path receipts from governed interactive desktop lanes, explicit owner approval, and an independent commit-bound security review. `source_only`, helper-only, `blocked`, `unsupported`, `skipped`, `absent`, malformed, and `not_tested` evidence can never become `passed`.
