# P2-002 — Full filesystem service implementation

## Contract

Absolute paths, drives, shares, hidden files, metadata, search, copy, move, delete, and transactions in Owner Mode.

## Done condition

Cross-platform fixtures pass, including symlinks/reparse points and long paths.

## Governed artifacts

- `lib/product/p2_filesystem_service.dart`
- `lib/product/p2_desktop_effect_authorizers.dart`
- `test/product/p2_filesystem_service_test.dart`
- `lib/product/p2_runtime_composition.dart`
- `lib/product/p2_automation_host_process_client.dart`
- `lib/product/p2_effect_journal.dart`
- `test/product/p2_shipped_product_runtime_e2e_test.dart`

## Assurance status

V63 contains source/local gates and the production product-to-worker composition, but this task is not DONE. Completion requires task-specific exact-source Windows, macOS, and Linux product-path receipts from governed interactive desktop lanes, explicit owner approval, and an independent commit-bound security review. `source_only`, helper-only, `blocked`, `unsupported`, `skipped`, `absent`, malformed, and `not_tested` evidence can never become `passed`.
