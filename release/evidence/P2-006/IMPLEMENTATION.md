# P2-006 — Process-tree lifecycle manager implementation

## Contract

Stable process identity, descendants, readiness, stop, kill, parent death, and PID-reuse handling.

## Done condition

No child remains after kill or timeout in adversarial tests.

## Governed artifacts

- `lib/product/p2_process_tree.dart`
- `lib/product/p2_runtime_composition.dart`
- `automation_host/src/process-tree.mjs`
- `automation_host/src/windows-process-broker.mjs`
- `automation_host/native/windows/job_supervisor.cpp`
- `automation_host/native/posix/watchdog.c`
- `test/product/p2_shipped_product_runtime_e2e_test.dart`

## Assurance status

V63 contains source/local gates and the production product-to-worker composition, but this task is not DONE. Completion requires task-specific exact-source Windows, macOS, and Linux product-path receipts from governed interactive desktop lanes, explicit owner approval, and an independent commit-bound security review. `source_only`, helper-only, `blocked`, `unsupported`, `skipped`, `absent`, malformed, and `not_tested` evidence can never become `passed`.
