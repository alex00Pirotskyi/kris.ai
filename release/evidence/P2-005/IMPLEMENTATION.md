# P2-005 — Interactive PTY service implementation

## Contract

Shell sessions, input, resize, ANSI, attach, detach, reconnect, and transcript.

## Done condition

Interactive fixtures pass on Windows, macOS, and Linux.

## Governed artifacts

- `lib/product/p2_pty_service.dart`
- `lib/product/p2_runtime_composition.dart`
- `lib/product/p2_automation_host_process_client.dart`
- `automation_host/src/host.mjs`
- `automation_host/src/authenticated-ipc.mjs`
- `automation_host/src/windows-pty-broker.mjs`
- `test/product/p2_runtime_composition_test.dart`
- `test/product/p2_shipped_product_runtime_e2e_test.dart`

## Assurance status

V63 contains source/local gates and the production product-to-worker composition, but this task is not DONE. Completion requires task-specific exact-source Windows, macOS, and Linux product-path receipts from governed interactive desktop lanes, explicit owner approval, and an independent commit-bound security review. `source_only`, helper-only, `blocked`, `unsupported`, `skipped`, `absent`, malformed, and `not_tested` evidence can never become `passed`.
