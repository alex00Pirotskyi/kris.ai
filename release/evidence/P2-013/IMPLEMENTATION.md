# P2-013 — Owner Mode adversarial suite implementation

## Contract

Destructive-command, path-race, output-flood, fork-bomb, crash, and restart tests.

## Done condition

Effects are intended, bounded by the OS account, observable, cancellable, and recoverable where claimed.

## Governed artifacts

- `lib/product/p2_p1_authority_adapter.dart`
- `lib/product/p2_product_runtime_bootstrap.dart`
- `lib/product/p2_product_runtime_integration.dart`
- `lib/product/p2_managed_authorization_registry.dart`
- `test/product/p2_shipped_product_runtime_e2e_test.dart`
- `tool/p2_behavioral_gate.py`
- `tool/p2_task_fixture.py`
- `tool/p2_task_platform_assertions.py`
- `tool/p2_evidence_contract.py`
- `tool/p2_evidence_contract_test.py`
- `tool/p2_strict_finalizer_contract_test.py`
- `evals/fixtures/p2`
- `docs/security/P2_SECURITY_REVIEW_PACKET.md`

## Assurance status

V63 contains source/local gates and the production product-to-worker composition, but this task is not DONE. Completion requires task-specific exact-source Windows, macOS, and Linux product-path receipts from governed interactive desktop lanes, explicit owner approval, and an independent commit-bound security review. `source_only`, helper-only, `blocked`, `unsupported`, `skipped`, `absent`, malformed, and `not_tested` evidence can never become `passed`.
