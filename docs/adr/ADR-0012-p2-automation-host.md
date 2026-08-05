# ADR-0012: P2 automation-host and PTY architecture

- Status: **PROVISIONAL — no technology selected by source alone**
- Date: 2026-07-28
- Revision: V63 corrective candidate

## Decision gate

P2 will select an automation-host technology only after the exact reviewed source commit has three independent candidate implementations measured on Windows 2025, macOS 15, and Ubuntu 24.04. Source code, availability checks, delayed reads, wrappers, and self-declared capability booleans are not acceptance evidence.

The candidates are:

1. TypeScript/Node with `node-pty` plus native lifecycle adapters.
2. A native PTY/process supervisor with an independently packaged browser-sidecar boundary.
3. An independent Dart control-plane implementation using native PTY/lifecycle helpers.

For every candidate and platform, `tool/p2_technology_spike.py` requires three machine-observed rounds bound to the exact commit, implementation, executable, build, package, and evidence hashes. Each round must prove real consumer detach, continued output while detached, reconnect by durable cursor, exact backlog replay with no duplication or loss, creation of descendants, identity verification, full-tree termination, and zero surviving descendants. Packaging reliability, code-signing impact, updater impact, interactive input, resize, ANSI, and Unicode fidelity are mandatory.

The Dart candidate is rejected if it merely republishes a native probe. Candidate implementation hashes must be distinct. Missing, malformed, wrapper-only, or partial evidence leaves P2-004 `blocked`. The accepted ADR is generated only after exact tri-platform task evidence and independent review agree on the measured decision.

## Invariants independent of technology selection

- The desktop control plane is the sole policy, grant, durable-use, replay, storage, approval, and evidence authority.
- The supervised automation host never issues or widens authority.
- Every request uses P1 authenticated local IPC and an exact Capability Grant v2 binding.
- Grant use is durably consumed before an effect and survives worker restart.
- Windows descendants are controlled through identity-verified Job Objects; POSIX descendants use identity-bound process groups/watchdogs.
- `node-pty`, native, and Dart prototypes are measurement candidates only until the governed decision closes.
- Playwright/browser automation is not a P2 dependency; it belongs to P3.

## Primary sources verified for the V63 source contract

Reviewed on 2026-07-29. They constrain implementation and measurement design; they are not behavioral proof.

- Node.js v24.18.0 signed release archive: https://nodejs.org/en/download/archive/v24.18.0
- Node.js `child_process`: https://nodejs.org/api/child_process.html
- Microsoft Pseudoconsoles / ConPTY: https://learn.microsoft.com/en-us/windows/console/pseudoconsoles
- Microsoft Job Objects: https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects
- Microsoft `node-pty`: https://github.com/microsoft/node-pty
- Dart `Process.start`: https://api.dart.dev/dart-io/Process/start.html
- Linux pseudoterminals: https://man7.org/linux/man-pages/man7/pty.7.html
- Apple `forkpty`: https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/forkpty.3.html

The exact-run spike must additionally record the current platform code-signing, packaging, and updater inputs used by each measured candidate.

This source ADR makes no release-selection claim.
