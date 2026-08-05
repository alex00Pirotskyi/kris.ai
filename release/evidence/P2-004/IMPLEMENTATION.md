# P2-004 — Automation host technology spike implementation

## Contract

Measured comparison of TypeScript/node-pty+Playwright, native/Rust PTY+Playwright, and other viable packaging options.

## Done condition

An ADR selects a solution using measured startup, memory, packaging, and reliability.

## Governed artifacts

- `docs/adr/ADR-0012-p2-automation-host.md`
- `tool/p2_technology_spike.py`
- `tool/p2_toolchains.py`
- `tool/p2_extend_toolchain_lock.py`
- `tool/p2_toolchain_extension_test.py`
- `tool/p2_evidence_contract.py`
- `tool/p2_evidence_contract_test.py`
- `tool/p2_contract_fixture_support.py`
- `tool/p2_strict_finalizer_contract_test.py`
- `.github/workflows/p2-owner-mode.yml`
- `automation_host/package.json`
- `automation_host/package-lock.json`
- `config/toolchains.lock.json`
- `config/p2_toolchain_extension.v1.template.json`
- `config/p2_runner_provisioning.v3.template.json`
- `config/p2_controlled_runner_policy.v5.template.json`
- `schemas/p2_runner_attestation_v5.schema.json`
- `schemas/p2_post_run_cleanup_v2.schema.json`
- `docs/operations/P2_TECHNOLOGY_CANDIDATE_RECEIPT_TEMPLATE.json`

## Assurance status

V63 contains source/local gates and the production product-to-worker composition, but this task is not DONE. Completion requires task-specific exact-source Windows, macOS, and Linux product-path receipts from governed interactive desktop lanes, explicit owner approval, and an independent commit-bound security review. `source_only`, helper-only, `blocked`, `unsupported`, `skipped`, `absent`, malformed, and `not_tested` evidence can never become `passed`.
