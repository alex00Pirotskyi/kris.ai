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

## Current assurance status

Technology selection is measured and recorded, but P2-004 remains review-pending. Source presence or hosted setup alone is not acceptance evidence. Acceptance still requires exact-current Product validation, independent commit-bound review and clean landing/reconciliation.

P1-012 is already completed and owner-approved on protected main; it is not a live P3 blocker. P3 remains gated only on P2-004 acceptance until this selection closes.

Nothing in this evidence claims P2-005, P2-006, release support, production readiness or GA.
