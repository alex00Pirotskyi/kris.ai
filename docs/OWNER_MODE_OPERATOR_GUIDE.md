# Owner Mode operator guide

## What Owner Mode means

Owner Mode gives Kristin the full authority available to the current operating-system account. **Owner Mode is not a sandbox.** It can inspect and change files outside registered projects, start commands and terminal sessions, manage supported packages and applications, read or write the clipboard, and capture the screen when a matching policy decision and Capability Grant v2 authorize the exact effect.

`isolated_untrusted` is a separate hostile-workload profile. It is never an automatic fallback for Owner Mode and Owner Mode is never relabelled as isolation.

## Enabling and disabling

The Settings > Authority page requires an explicit data-boundary acknowledgement, an approval policy, and a choice between interactive `owner` and stricter `owner_unattended`. A persistent **OWNER MODE — full current-account access** indicator remains visible while enabled. Disable and Reset revokes the local Owner Mode session state; existing grants still fail at the final effect boundary when revoked, expired, exhausted, or bound to another run/task/actor/tool/profile.

## Approvals and elevation

High-risk or destructive actions follow the selected approval policy and the deterministic P1 policy engine. Elevation is not synthesized from model text. It requires visible OS-native owner interaction or a separately configured external authority. Environment variables, repositories, web pages, terminal output, workers, and model messages are data—not authorization.

## Secrets and privacy

Do not place raw secrets in command arguments or normal environment deltas. Use protected secret leases. Ordinary logs, evidence, PTY transcripts, clipboard receipts, and screenshot metadata contain hashes, sizes, identities, and redacted metadata rather than raw sensitive content. Screen capture defaults to no-model-context until the operator explicitly permits the captured content.

## Terminal and process controls

Each terminal tab shows shell, cwd, run, task, grant, and attach state. Keyboard workflows include new/close tab, search, copy, save transcript, interrupt, terminate, detach, and attach. Terminate is idempotent and targets the managed process tree, not only the parent PID. If completion is ambiguous, the session becomes `unknown` and must be reconciled before retry.

## Emergency stop

Emergency Pause and Kill is available from the main UI, tray, keyboard shortcut, and an external watchdog. The watchdog owns an independent kill path so a frozen UI or runaway output cannot disable termination. On Windows, the lifecycle helper owns a Job Object configured to kill all associated descendants when closed. On macOS/Linux, managed sessions have a dedicated process group and an external heartbeat watchdog.

## Backups and undo

Undo is best effort. Every effect is labelled `reversible`, `partiallyReversible`, or `irreversible` before execution. Eligible file writes create backups; eligible repositories can receive Git checkpoints. Package, service, external network, hardware, and arbitrary command effects may be non-restorable. Never treat a successful command as proof that all side effects can be undone.

## Recovery

After a crash or restart, the desktop control plane restores durable request replay and grant-use consumption state before the automation host accepts work. Kristin also reconciles journal entries in `started`, `killing`, or `unknown`; verifies process identity rather than trusting a reused PID; checks backup/quarantine state; and asks for operator action where completion cannot be proven. Never blindly retry an `unknown` mutation.
