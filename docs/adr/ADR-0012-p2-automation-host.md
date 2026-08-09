# ADR-0012: P2 automation-host technology selection

- Status: **MEASURED SELECTION — independent review pending**
- Date: 2026-08-09
- Corrective scope: P2-004 technology selection only
- Measured source commit: `1b5a69739af9a999065ae9397bb74ade6b853356`
- Measurement workflow: `P2-004 Technology Selection` run `31301030782`

## Decision

**Select TypeScript/Node with `node-pty` plus native lifecycle adapters as the P2 automation-host architecture.**

The exact measured source commit produced successful Windows 2025, macOS 15 and Ubuntu 24.04 selection jobs plus a successful tri-platform aggregate. On every target OS, the Node candidate completed three real PTY launch/input/output/resize rounds. The selection measurements also captured startup time, resident memory and installed automation-host footprint.

This decision is not yet P2-004 `ACCEPTED`; exact-current Product validation and an independent commit-bound technical/security review remain required.

## Measured basis

| Platform | Node median startup | Node max RSS | Automation-host footprint | Node PTY rounds | Packaging note |
| --- | ---: | ---: | ---: | --- | --- |
| Ubuntu 24.04 | 61.667 ms | 51,544,064 B | 65,101,323 B | 3/3 PASS | none |
| macOS 15 | 68.941 ms | 48,398,336 B | 64,977,520 B | 3/3 PASS | `node-pty` 1.1.0 prebuilt spawn-helper required execute-bit repair |
| Windows 2025 | 5,158.999 ms | 56,479,744 B | 66,235,568 B | 3/3 PASS | none |

The Windows startup cost is materially larger than Linux/macOS and remains a downstream optimization target. It did not prevent reliable real PTY launch/input/output/resize in all three measured rounds.

The macOS first measurement run exposed `node-pty` failing with `posix_spawnp failed`. The corrective selection run preserved that as packaging evidence and applied a deterministic execute-bit repair to the installed prebuilt `spawn-helper`; all three subsequent macOS PTY rounds passed. Production packaging must remove the need for this runtime repair before downstream certification.

## Alternatives

### Native platform PTY supervisor

Real native POSIX PTY probes passed three rounds on Linux and macOS. Windows confirmed ConPTY and Job Object API availability, but this spike has no independent complete native Windows PTY supervisor implementation. The candidate is therefore not a complete tri-platform architecture today and is rejected for P2-004 selection without fabricating a Windows pass.

### Dart control plane + native PTY helper

Dart process/control-plane I/O was measured successfully on all three platforms, but the candidate still requires a native PTY helper and did not itself demonstrate real PTY behavior. Selecting it would add a second implementation boundary without removing the native dependency, so it is rejected for the automation-host role.

## Roadmap boundary

P2-004 is a technology-selection spike. It does **not** require production certification of every competing architecture before a selection can be made.

- **P2-004** selects the automation-host technology.
- **P2-005** implements and certifies production interactive PTY behavior, including input, resize, ANSI, attach, detach, reconnect and transcript.
- **P2-006** implements and certifies process-tree lifecycle behavior, including stable identity, descendants, stop/kill, parent death and PID reuse.

Therefore this selection must not be represented as P2-005 or P2-006 acceptance, release support, production readiness or GA.

## Measurement mechanism

`.github/workflows/p2-004-technology-selection.yml` executes on ordinary GitHub hosted Windows, macOS and Linux runners and measures the exact candidate commit through `tool/p2_004_technology_selection.py`.

For Node, the spike uses the repository's real `node-pty` dependency closure and a direct PTY launch/input/output/resize probe. It deliberately does not require the Windows Job-Object lifecycle helper because full process-tree guarantees belong to P2-006 rather than technology selection.

For the native candidate, POSIX PTY behavior is exercised directly while Windows ConPTY/Job Object API feasibility is measured separately. A missing independent Windows supervisor prototype is recorded as a rejection reason rather than a fake pass.

For Dart, the spike measures control-plane process startup/I/O and records that an independent native PTY helper remains necessary. The Dart candidate cannot win merely by delegating PTY behavior to the same native implementation and calling itself independent.

The aggregate selects a technology only when one candidate has real PTY behavior on every target platform and all three records are bound to the same exact Git commit.

## Evidence identities

Measurement source: `1b5a69739af9a999065ae9397bb74ade6b853356`

Workflow run: `31301030782`

Artifacts:

- Linux: artifact `9034489320`, digest `sha256:708ab66c671dc947bddaa8bca8e8211a60bbdcb5b168e4bc7aaabcd69e7ec095`
- macOS: artifact `9034489521`, digest `sha256:b4f312154ab24acaed8b375dc7211f30355f045b81ff8241481bbe18bd0a5d14`
- Windows: artifact `9034502386`, digest `sha256:87a132ae0753712e9be245e3c53dbaf186648590a35c5fa23fdc0750a3f1b8fa`
- Aggregate: artifact `9034507272`, digest `sha256:43e077c036f0b4a8fb1e420a9db0dcdf3ffddd5989b18d053af98d9245c9fb92`

The aggregate status is `selected` and the selected candidate is `typescript-node-node-pty-with-native-lifecycle-adapters`.

## Security and authority invariants

Technology selection does not alter the P1/P2 authority model:

- the desktop control plane remains the policy, grant, durable-use, replay, storage, approval and evidence authority;
- the automation host may never issue or widen authority;
- requests remain bound to authenticated local IPC and Capability Grant v2;
- technology selection does not authorize browser behavior; browser automation belongs to P3;
- source-only, skipped, unavailable, malformed or partial evidence cannot be promoted to a measured selection.

## Acceptance gates remaining

P2-004 may move to `ACCEPTED` only after:

1. exact-current Product validation is green for the final clean candidate;
2. the exact measured decision and carry-forward from measurement source `1b5a697…` are independently reviewed;
3. the clean current-main candidate is landed according to repository policy;
4. acceptance is recorded without implying P2-005/P2-006/release/GA support.

Until those gates pass, this ADR remains a measured selection pending review.
