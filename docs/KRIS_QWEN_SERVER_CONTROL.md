# KRIS Qwen server control

This is the repository-owned phone controller for the local Qwen Mission Execution worker.

## Operator flow

From the server checkout:

```bash
git pull --ff-only
./run_my_server.py
```

The launcher verifies GitHub CLI authentication, owns the configured HTTP port, enables trusted-LAN phone mode, and starts the always-on controller/worker entries.

## Executed versions

The phone execution path is compatibility-layered while the large retained source files remain stable:

- stable controller-facing worker: `tool/kris_qwen_worker_v53.py` — forwards to the deterministic 5.4.1 entry;
- executed worker: `tool/kris_qwen_worker_v541.py` — **5.4.1**;
- legacy worker path: `tool/kris_qwen_worker.py.compat.py` — forwards to the same stable 5.4.1 path so older controller configuration reaches current worker bytes after Fetch latest;
- retained base worker: `tool/kris_qwen_worker.py` — compatibility/transformation base, not the reported executed version;
- executed controller: `tool/kris_qwen_control.py.compat.py` — **2.2.2**;
- retained base controller: `tool/kris_qwen_control.py` — compatibility base, not the reported executed version.

The worker version shown by the phone flow is derived from the executed worker entry, not the retained base-file label.

## Always-on Product protocol

Normal `IDLE` is a **red-alert condition**, not a steady state. Qwen is expected to be continuously doing one of these things:

- implementing Product source;
- writing or strengthening Product tests;
- repairing a demonstrated defect;
- integrating an exact-green helper into a canonical Product branch;
- running exact Product CI;
- performing a context-independent R1 technical review it is allowed to perform;
- actively recovering a runtime/control-plane blocker;
- deriving the next bounded Product hardening Work Order through existing Mission Runtime authority.

Successful Work Orders chain immediately. The normal 60-second inter-job sleep is removed by the 5.4.1 execution adapter.

### Review wake

Mission Runtime historically allowed a Work Order to be `type=REVIEW` while its runtime state was `REVIEW`; however `next-work` dispatches only state `READY`, and semaphore reservation accepts only `READY` or `IN_PROGRESS`. Worker 5.4.1 therefore wakes an eligible pending context-independent R1 from `REVIEW` to `READY` before dispatch.

It does not wake review work that explicitly requires a distinct external GitHub identity, and it retains the existing refusal to R1-review `agent/local-qwen/**` helpers authored by local Qwen itself.

### Helper integration

A reviewed or exact-green `HELPER_READY` source candidate is not treated as finished. Worker 5.4.1 can bind a scope-compatible sibling helper to the same canonical Product PR when older runtime history did not record a formal parent/child relationship.

For continuous Product hardening, an exact-green helper gets a bounded integration lane. Integration remains non-force, exact-head guarded, and path-scoped. A helper is marked `LANDED` only after its bytes are actually reconciled into the canonical Product branch.

### Post-integration exact Product CI

Continuous integration does not self-certify just because helper CI was green. When the canonical Product branch reaches `VALIDATING`, worker 5.4.1 creates a read-only `CI_REPAIR` Work Order through Mission Runtime for exact `workflow_dispatch` Product Gates. Ubuntu, Windows, and macOS must all complete successfully.

The integration Work Order is reconciled from that exact CI result:

- exact Product CI green → integration `LANDED`;
- exact Product CI red → integration `BLOCKED`.

Only after that terminal result can the continuous Product loop seed more work on that Product PR.

### Governed frontier seeding

If no dispatchable GREEN Work Order exists, worker 5.4.1 may create **one** bounded `PRODUCT_DEFECT_REPAIR` Work Order through the existing `mission_orchestrator.py work-create` CAS path, and only when all of these conditions hold:

- the Product PR is already canonical in `agent/mission-runtime`;
- the Product record is `ACTIVE`;
- the GitHub PR is still open;
- the runtime Product branch matches the GitHub PR head branch;
- the exact live branch SHA equals the GitHub PR head SHA;
- no active Work Order already occupies that Product lane;
- allowed paths come only from governed Product/source paths or the current Product diff and remain inside code/test-oriented prefixes;
- Mission Runtime path validation, WIP limits, semaphore collision checks, and exact Git base/tree verification all pass.

The seeded objective explicitly forbids documentation-only, formatting-only, governance-only, and no-op work. It requires a concrete correctness, performance, reliability, UX-facing behavior, or missing-regression target plus focused local validation.

If no safe authority exists, the worker reports `RED_ALERT_FRONTIER` and aggressively re-resolves instead of reporting normal idle.

## Automatic update and restart

Controller 2.2.2 enables automatic supervision by default:

```text
KRIS_QWEN_AUTO_UPDATE=1
KRIS_QWEN_AUTO_UPDATE_SECONDS=30
```

Every interval it resolves the remote head of the configured Qwen branch. If the remote head differs from the local checkout, controller 2.2.2 reuses the existing safe Fetch latest + run path:

1. graceful worker drain;
2. dirty-checkout refusal;
3. fetch of the configured branch;
4. fast-forward-only update;
5. refreshed worker `version` probe;
6. stack restart using the newly fetched worker entry.

There is no reset-hard, rebase, force checkout, force push, or arbitrary branch mutation in this path.

If the tracked branch is already current but the worker process exited unexpectedly, controller 2.2.2 starts it again automatically while automation is **ACTIVE**. **Pause automation + safe stop** atomically persists operator intent in `<state_dir>/auto-run-state.json`, pauses automatic updates and restarts across controller/systemd restarts, and safely stops a running worker. Run current Qwen or Fetch latest + run Qwen explicitly returns automation to **ACTIVE**. Invalid or malformed durable state fails closed to **PAUSED**.

The phone dashboard exposes **ACTIVE**, **PAUSED**, or **ERROR** plus the persisted intent reason. The pause control remains available when automation is active even if the worker is already stopped, preventing the controller from silently restarting it before the operator can pause it.

The controller process itself must be loaded once with 2.2.2. Future worker/controller branch changes are then detected automatically; repeated manual Fetch latest presses are not part of the normal protocol.

## Security boundary

Phone mode intentionally binds to `0.0.0.0`, but every API operation requires a long random bearer token and same-origin browser requests. The token is not embedded in dashboard HTML.

Plain HTTP does not encrypt the token. Use phone mode only on a trusted LAN or private VPN such as Tailscale. Do not expose port 8090 directly to the public Internet.

## Fetch safety rules

Automatic/manual fetch-run never uses `git reset --hard`, rebase, force checkout, or force push. It fails closed if:

- the server checkout is dirty;
- the checkout is not on the configured branch;
- the remote update is not a fast-forward;
- the executed worker version entry is missing/broken;
- GitHub CLI authentication is unavailable;
- the current worker cannot reach a safe stop before the configured timeout.

## Resource behavior

The managed llama.cpp server remains resource-tuned from the actual host at startup. It reads CPU affinity, physical cores, logical CPUs, NUMA, and live memory; reuses `llama-bench` tuning only while the machine/model fingerprint remains valid; and derives generation/batch/build/HTTP threads, context size, prompt-cache budget, system reserve, parallel slots, and NUMA behavior.

This is startup/restart adaptation rather than second-by-second retuning while the model server is resident.

## Safety boundary for always-on execution

Always-on does not mean uncontrolled. Qwen still may not:

- write directly to protected `main`;
- force-push;
- change branch protection;
- manufacture R2 identity independence;
- self-certify R1 for its own local-Qwen helper;
- promote acceptance/support/release/GA without the separate required authority;
- bypass Work Order allowed paths or semaphore authority;
- mutate Product source from an exact-CI-only lane.

`IDLE` is removed as a normal business outcome, but fail-closed authority remains mandatory.
