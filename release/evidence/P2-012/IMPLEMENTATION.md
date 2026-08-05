# P2-012 — Terminal UX implementation

## Contract

Tabs, shell/cwd selector, search, save, copy, interrupt, terminate, attach, and run linkage.

## Done condition

Keyboard and screen-reader terminal scenarios pass.

## Governed artifacts

- `lib/product/p2_terminal_model.dart`
- `lib/product/p2_owner_workspace.dart`
- `test/product/p2_owner_workspace_test.dart`
- `test/product/p2_process_terminal_contract_test.dart`

## Assurance status

V63 contains source/local gates and the production product-to-worker composition, but this task is not DONE. Completion requires task-specific exact-source Windows, macOS, and Linux product-path receipts from governed interactive desktop lanes, explicit owner approval, and an independent commit-bound security review. `source_only`, helper-only, `blocked`, `unsupported`, `skipped`, `absent`, malformed, and `not_tested` evidence can never become `passed`.
