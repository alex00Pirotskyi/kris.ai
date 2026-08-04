# P1/P2 tri-platform QA matrix

Every row must be executed on Windows, macOS, and Linux unless the row explicitly names one platform. Record pass/fail, logs, screenshots where safe, exact artifact SHA-256, OS version, and tester.

## Install, launch, upgrade, uninstall

- Extract on a clean QA machine.
- Verify the ZIP SHA-256 sidecar.
- Launch using the included platform launcher.
- Confirm the permanent banner: `OWNER-RISK QA — SECURITY EVIDENCE WAIVED`.
- Confirm app relaunch preserves only intended state.
- Confirm uninstall/removal leaves no unintended service, worker, process, or temporary runtime.

## P1 and P1A integration

- P1 trust/manifest parsing and downgrade rejection.
- Key registry and revocation behavior.
- Signed audit verification and tamper rejection.
- IPC request/response contract.
- P1A native authority binary source self-test.
- P1A native connector source self-test.
- P1A worker-launcher source self-test.
- Owner-risk mode clearly reports `completionEligible: false` and never claims isolated authority evidence.

## P2-001 — Owner Mode onboarding/settings

- Enable/disable Owner Mode.
- Acknowledgement is mandatory.
- Unattended mode and destructive-only approval policy persist correctly.
- Security-waiver banner remains visible.

## P2-002 — Filesystem service

- Read, write, replace, append, enumerate, metadata, search, delete/quarantine.
- Unicode and long paths.
- Large-file and quota limits.
- Traversal and malformed-path rejection.
- Permission-denied reporting.

## P2-003 — Finite command execution

- stdout/stderr capture, exit codes, Unicode output.
- cwd and bounded environment.
- deadline, cancellation, process failure, missing executable.
- Administrator/root effects on a disposable fixture only.

## P2-004 — Automation-host boundary

- Worker starts through the bundled owner-risk launcher.
- Public/bootstrap material contains no raw authority secrets.
- Request, payload, grant, policy, and worker identity bindings remain enforced.
- Replay and duplicate request IDs are rejected.

## P2-005 — PTY sessions

- Open, input, resize, attach/detach, reconnect, close.
- Shell exit and crash behavior.
- Unicode and high-volume output.
- Windows ConPTY, macOS PTY, Linux PTY.

## P2-006 — Process-tree lifecycle

- Stable process identity.
- Child and descendant discovery.
- Normal stop, forced stop, crash cleanup.
- No orphan processes after app exit.

## P2-007 — Package/SDK operations

- Controlled local package dry-run/install/remove.
- SDK/tool discovery and provenance display.
- Unsupported manager and permission errors.
- Never install arbitrary production packages during QA.

## P2-008 — Service/application control

- Query a safe built-in service.
- Open/close a disposable application process.
- Wrong identity, already stopped, permission denied.

## P2-009 — Clipboard/screen/active window

- Clipboard text round trip without logging clipboard content.
- Screen capture to a disposable fixture.
- Active-window identity.
- OS permission denial and later permission grant.

## P2-010 — Snapshots/undo

- Snapshot before write/delete/replace.
- Undo restores exact bytes and metadata where promised.
- Missing/corrupt snapshot and conflict behavior.

## P2-011 — Emergency pause/kill

- Pause new effects.
- Kill running command and full descendant tree.
- Frozen/runaway/flooding worker.
- UI remains responsive and records bounded diagnostics.

## P2-012 — Terminal UX

- Open, tabs/sessions, scrollback, selection/copy, resize.
- Keyboard accessibility and focus.
- Bounded rendering under high output.

## P2-013 — Adversarial suite

- Race, replay, duplicate use, flood, fork bomb fixture with strict limits.
- Worker crash, host crash, app crash, restart.
- Malformed IPC, oversized payload, invalid authorization binding.
- No credential-shaped data in logs.

## P2-014 — Operator guide and shipment evidence

- Instructions match actual behavior on all three OSes.
- Known limitations are listed.
- Exact artifact/commit/tree/toolchain identifiers are recorded.
- All failures are resolved or accepted explicitly before shipment sign-off.
