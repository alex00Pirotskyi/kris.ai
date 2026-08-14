# P2-004 — Automation host technology selection

## Contract

Select the P2 automation-host architecture using real measured startup, memory,
packaging footprint, reliability and PTY viability on Windows, macOS and Linux.

## Corrected done condition

P2-004 is DONE when an exact reviewed tri-platform measurement selects an automation-host technology. It does not certify the complete interactive PTY or process-tree feature set for every rejected architecture.

Production proof remains downstream:

- P2-005 — interactive PTY, attach/detach/reconnect/transcript/ANSI/resize.
- P2-006 — stable process identity, descendants, stop/kill and no surviving descendants.

## Measured selection

Exact measurement source: `1b5a69739af9a999065ae9397bb74ade6b853356`

Workflow: `P2-004 Technology Selection` run `31301030782`

All selection jobs and the aggregate completed successfully:

- `selection-ubuntu`: PASS
- `selection-macos`: PASS
- `selection-windows`: PASS
- `selection-aggregate`: PASS

The aggregate selected:

`typescript-node-node-pty-with-native-lifecycle-adapters`

### Node/node-pty measurements

| Platform | Median startup | Max RSS | Installed automation-host footprint | Real PTY reliability |
| --- | ---: | ---: | ---: | --- |
| Linux | 61.667 ms | 51,544,064 B | 65,101,323 B | 3/3 PASS |
| macOS | 68.941 ms | 48,398,336 B | 64,977,520 B | 3/3 PASS |
| Windows | 5,158.999 ms | 56,479,744 B | 66,235,568 B | 3/3 PASS |

Every passing Node round exercised actual PTY launch/input/output and resize. The Windows startup latency is materially higher and remains a downstream optimization concern rather than a hidden result.

On macOS, the first exact measurement exposed the pinned `node-pty` 1.1.0 prebuilt `spawn-helper` as non-executable. The corrective run records the deterministic execute-bit repair and then obtains three real PTY passes. The packaging issue therefore remains explicit work for the selected architecture; it is not silently erased from the decision.

### Native alternative

Linux and macOS native POSIX PTY feasibility passed 3/3 rounds. Windows exposed the required ConPTY/Job Object APIs, but this spike has no independent complete native Windows supervisor implementation. The architecture is therefore not selection-ready across all three platforms.

### Dart alternative

Dart control-plane process I/O was measured on all three platforms, but the candidate still requires a native PTY helper and never independently demonstrated PTY behavior. It is not selected.

## Governed selection artifacts

- `docs/adr/ADR-0012-p2-automation-host.md`
- `tool/p2_004_technology_selection.py`
- `tool/p2_004_technology_selection_test.py`
- `.github/workflows/p2-004-technology-selection.yml`
- `release/evidence/P2-004/manifest.json`

Artifacts from run `31301030782`:

- Linux `9034489320` — `sha256:708ab66c671dc947bddaa8bca8e8211a60bbdcb5b168e4bc7aaabcd69e7ec095`
- macOS `9034489521` — `sha256:b4f312154ab24acaed8b375dc7211f30355f045b81ff8241481bbe18bd0a5d14`
- Windows `9034502386` — `sha256:87a132ae0753712e9be245e3c53dbaf186648590a35c5fa23fdc0750a3f1b8fa`
- Aggregate `9034507272` — `sha256:43e077c036f0b4a8fb1e420a9db0dcdf3ffddd5989b18d053af98d9245c9fb92`

## Independent review

The clean six-file helper PR #128 was reviewed at exact head
`e8e85a4ffa744f9118f4dc6e04b563e7ee521aae` and tree
`94e237375c8924f5b4c063243af7075f10fbd50e` by the context-independent
review execution `WRK-20260809T103104Z-44AE364B`.

The review verified:

- the effective protected-main diff was exactly the six P2-004 files;
- workflow run `31301030782` and all four artifact identities/digests;
- real PTY launch/input/output/resize for 3/3 rounds on every target OS;
- honest rejection evidence for the native and Dart alternatives;
- explicit macOS execute-bit packaging debt and Windows startup debt;
- the boundary that P2-004 does not certify P2-005, P2-006, P3 behavior,
  release support, production readiness or GA;
- exact-head P2-004 and tri-platform Product validation.

Technical disposition: **R1 PASS**.

GitHub records the review as `COMMENTED` because the connected GitHub identity
was also the PR author. The Mission Execution review was a different,
context-independent execution and is the R1 required by the P2-004 acceptance
contract. It is not represented as separate-identity R2.

## Clean landing and exact-current validation

- clean helper PR #128 merged as `2c8499f4b0b56276c29e5bfde821478836074041`;
- canonical integration Work Order `WO-P2-004-INTEGRATE-SELECTION-6E91A2F4` is LANDED;
- exact-current P2-004 Technology Selection run `31769134490`: SUCCESS;
- exact-current P2 Owner Mode source-contract run `31769134494`: SUCCESS on Windows, macOS and Linux;
- exact-current product-gates run `31769134506`: SUCCESS on Windows, macOS and Linux, including native release builds;
- validated candidate `bb2085479d6e2f0e167e8db97fa6f54120534a5d` has tree `af0f9308c29a4a4391dbc88386fa59dafb20e73a`;
- protected-main commit `1e4cc0102e371307a577ceefef7dc0ca1855412f` carries that exact tree;
- the later P3 integration re-bound `config/p2_toolchain_extension.v1.json` to the exact automation-host package lock and exact-current P2-004/P2 Owner Mode validation remained green.

## Current assurance status

**P2-004 is ACCEPTED.**

The corrected task done condition and all four acceptance gates are satisfied:
real tri-platform measurement, exact commit-bound R1, clean protected-main
landing, and exact-current Product validation.

This acceptance remains intentionally narrow. It does not claim:

- separate-identity R2;
- P2-005 interactive PTY certification;
- P2-006 process-tree certification;
- packaging/signing/updater certification;
- removal of the macOS `spawn-helper` packaging repair;
- Windows startup optimization;
- platform or release support;
- production readiness, release or GA;
- human owner approval for identity, signing, legal, payment, MFA or
  production-promotion actions.
