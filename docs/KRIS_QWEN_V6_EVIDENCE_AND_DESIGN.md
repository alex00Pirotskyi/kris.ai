# KRIS Qwen Worker v6 — Evidence, Failure Model, and Gold-Standard Design

## Status

This document defines the source and operational contract for **KRIS Qwen Worker v6.0.0** and **KRIS Qwen Control v2.0.0**.

It is an engineering design and migration contract. It does not certify a platform, release, production deployment, or GA status.

## 1. Why v6 exists

Qwen v5.2 proved that a local model can execute bounded repository work, but live fleet evidence exposed two stop-ship failure classes:

1. **Shared-authority loss during integration.** The integration sanitizer restored every effective path outside one Work Order to protected-main bytes. This correctly removed stale foreign branch material, but it also deleted independently governed shared surfaces such as ProductRuntime composition, source inventory entries, Test Center registry records, hierarchy bindings, and proof-lineage records.
2. **GitHub authentication failures were classified as Work Order failures.** A systemd worker could complete local source work and then lose access to the root GitHub CLI credential store. The same task was regenerated repeatedly instead of entering a stable infrastructure-blocked state.

The server controller also needed stronger process identity, secret handling, operation recovery, and service separation.

## 2. Evidence register

### E-001 — P3 shared composition loss

A current-main reconciliation removed valid P3 ProductRuntime composition and source-inventory entries because those paths were outside the integration Work Order even though they were governed by separate shared authorities.

### E-002 — P4 Test Center lineage loss

A P4 reconciliation removed registry, assurance-hierarchy, and proof-lineage additions for the same reason. These were append-safe shared-authority surfaces, not stale foreign branch material.

### E-003 — GitHub credential-store outage

The worker completed local source validation, then five consecutive `gh pr view` operations failed because the systemd environment did not resolve the authenticated root credential store. v5.2 counted those as hard task failures and repeated work.

### E-004 — Controller process identity was PID-only

The controller combined a PID, command-line substring, and process record. It did not bind Linux process start time and executable/cmdline digest, so a stale record could theoretically adopt an unrelated reused PID.

### E-005 — Dashboard token disclosure

The v5.2 controller rendered the control token directly into dashboard HTML. Loopback binding reduced exposure, but any local browser extension, page-source capture, or local process able to read the response could obtain the long-lived control credential.

### E-006 — Combined service lifecycle

The controller started the worker/model stack as a child process while systemd used `KillMode=process` to keep that child alive when the controller restarted. This created split ownership and made restart/adoption behavior harder to prove.

### E-007 — Model sandbox exposed excessive read-only host state

The v5.2 bubblewrap command used a read-only bind of `/`. Although the configured home was replaced with tmpfs, other credential-bearing host locations could remain visible. v6 overlays `/root`, `/home`, and `/run/user` with private tmpfs mounts and audits worktree symlinks after every model command.

### E-008 — Model actions accepted open-ended fields

The action protocol validated action names but did not consistently reject unknown fields or enforce a single global payload budget. v6 introduces closed per-action schemas and explicit content, patch, argument-count, and argument-size limits.

## 3. v6 non-negotiable invariants

### 3.1 Product-first default

The default capability profile accepts only:

- `PRODUCT_FEATURE`
- `PRODUCT_DEFECT_REPAIR`
- `PRODUCT_TEST`
- `CI_REPAIR`
- `BLOCKER_REMOVAL`
- `REVIEW`

`INTEGRATION`, `AUTHORITY_UPDATE`, `EVIDENCE_FINALIZATION`, and `RELEASE_FINALIZATION` require explicit operator opt-in. They are never implicit defaults.

### 3.2 Shared authority is never sanitized silently

Before any canonical Product branch push, v6 classifies every path outside the integration Work Order:

- ordinary stale foreign paths may be restored to protected-main bytes;
- known shared-authority paths stop the push;
- the worker writes a durable `BLOCKED_SHARED_AUTHORITY` report;
- the report names the exact authority ID, mode, owner mission, path, requesting mission, eligibility, Product head, and protected-main head;
- manual-only authority modes remain manual-only;
- no model-generated scope escalation is accepted.

### 3.3 GitHub auth is infrastructure state

Before reserving a source-changing Work Order, v6 requires:

- `gh auth status --hostname github.com`;
- authenticated read access to the configured repository;
- working Git credential plumbing.

Authentication loss becomes `BLOCKED_GITHUB_AUTH`, not a Work Order defect. The worker applies stable backoff, preserves diagnostics and any patch bundle, and does not count the condition as a hard task failure.

### 3.4 Remote side effects are idempotent

Every helper push, PR creation, workflow dispatch, canonical integration push, PR close, and branch deletion is assigned an idempotency key derived from the immutable target. A durable operation journal records `PREPARED` and `COMPLETED` states. Restart reconciliation inspects GitHub before repeating an operation.

### 3.5 Closed model protocol

Every model action:

- has a closed allowed-key set;
- requires a bounded `why` field;
- is constrained by a global canonical JSON size limit;
- applies action-specific content/patch/argv limits;
- remains read-only in review mode;
- is audited before and after execution.

### 3.6 Strong process identity

A Linux process record binds:

- PID;
- `/proc/<pid>/stat` start ticks;
- resolved executable path;
- SHA-256 of the exact NUL-delimited command line.

The controller refuses stale or mismatched records, preventing PID-reuse adoption.

### 3.7 Control token is never embedded in HTML

The dashboard does not receive the token from the server response. Operators provide it to the browser session explicitly; it remains in session storage and is sent only in `X-Kris-Control-Token`.

POST requests additionally require:

- a loopback Host;
- an absent origin for CLI clients or a loopback Origin/Referer for browsers;
- a bounded content length;
- serialized controller operation ownership.

### 3.8 Sandbox confidentiality

The model command sandbox:

- keeps network isolation;
- mounts the worktree read-write;
- overlays `/root`, `/home`, and `/run/user` with tmpfs;
- uses an empty private HOME;
- strips secret-shaped environment keys;
- rejects symlinks resolving outside the worktree after every command;
- never exposes GitHub credentials to model-generated processes.

## 4. Worker state model

v6 adds explicit local states:

- `BLOCKED_GITHUB_AUTH`
- `BLOCKED_SHARED_AUTHORITY`
- `BLOCKED_MODEL_RUNTIME`
- `BLOCKED_CONTROL_PLANE`
- `BLOCKED_BRANCH_CAPACITY`
- `READY`
- `WORKING`
- `DRAINING`
- `STOPPED`

Infrastructure-blocked states do not mutate task truth. They include a stable failure signature and retry deadline.

## 5. Integration transaction

A canonical integration is a durable transaction with these phases:

1. `PREPARED` — exact main, Product head, helper head/tree, Work Order, semaphore, and authority snapshot recorded.
2. `LOCAL_COMPOSED` — local merge/sanitize result validated; no remote side effect yet.
3. `AUTHORITY_CHECKED` — outside-scope paths classified; shared-authority report is empty.
4. `PUSH_PREPARED` — idempotency record committed locally.
5. `CANONICAL_PUSHED` — exact Product branch observed at the intended commit/tree.
6. `RUNTIME_RECONCILED` — runtime Product record and Work Order updated through CAS.
7. `POSTCHECKED` — exact-head CI dispatched and observed.

A restart resumes from the last durable phase; it does not blindly rerun the model or repeat a remote side effect.

## 6. Controller v2 contract

The v2 controller is still localhost-only, but its responsibility is reduced to orchestration and observability.

It must:

- maintain an atomic operation journal;
- refuse concurrent start/stop/refresh operations;
- use strong process identities;
- verify repository cleanliness and fast-forward-only refreshes;
- preflight GitHub auth, model file, sandbox tooling, ports, and exact worker version;
- wait for a bounded worker readiness heartbeat rather than assuming a successful `Popen` means ready;
- never embed its token in HTML;
- recover interrupted controller operations after restart;
- expose redacted structured status only.

## 7. Server-side target architecture

The ultimate Linux deployment separates lifecycle ownership:

- `kris-qwen-model.service` — `llama-server`, model file read-only, bounded CPU/RAM/NUMA, no GitHub credentials.
- `kris-qwen-worker.service` — repository worker loop, dedicated service account, restricted GitHub App credential, no model file write access.
- `kris-qwen-control.socket` + `kris-qwen-control.service` — localhost control API, on-demand activation, no child-process ownership.

The controller calls `systemctl` on the two services. systemd owns cgroups, restart policy, logs, stop ordering, and process cleanup. No unit uses `KillMode=process` to intentionally orphan children.

Hardening baseline:

- dedicated `kris-qwen` user;
- `NoNewPrivileges=true`;
- `PrivateTmp=true`;
- `ProtectSystem=strict`;
- `ProtectHome=true` where compatible;
- explicit `ReadOnlyPaths`/`ReadWritePaths`;
- `RestrictSUIDSGID=true`;
- `LockPersonality=true`;
- bounded `TasksMax`, `MemoryMax`, `CPUQuota`, and restart bursts;
- root-owned 0600 environment/credential files;
- log rotation and disk quotas;
- no public listener.

## 8. Migration contract

1. Stop v5.2 gracefully.
2. Preserve the worker root, logs, patches, active lease journal, and runtime state.
3. Install v6 files from a current-main commit.
4. Run `kris_qwen_worker.py doctor` and the v6 guard/controller tests.
5. Start v6 in the default product capability profile.
6. Verify exact worker/controller versions and GitHub auth state.
7. Keep integration disabled until the shared-authority negative controls pass on the server checkout.
8. Migrate to split systemd services only after the repository v6 source candidate passes exact-head CI.
9. Roll back by stopping v6 and restoring the prior service files; never reset or delete the worker root.

## 9. Required regression matrix

- P3 ProductRuntime and source-inventory changes produce `BLOCKED_SHARED_AUTHORITY` and remain byte-identical locally.
- P4 registry/hierarchy/proof-lineage changes enumerate all three authorities.
- an ordinary foreign README change is still sanitized.
- missing root GitHub credentials produce `BLOCKED_GITHUB_AUTH` before model execution.
- an expired token after local work preserves a patch bundle and avoids hard-error accounting.
- duplicate helper push/PR/dispatch operations reuse the durable receipt.
- PID reuse and command-line mismatch are rejected.
- dashboard HTML contains no control token.
- non-loopback Host/Origin requests are rejected.
- model sandbox hides `/root`, `/home`, and `/run/user`.
- external symlinks created by model commands are rejected.
- unknown model action fields and oversized payloads are rejected.
- controller restart recovers or terminates an interrupted operation deterministically.

## 10. Truth boundary

v6 improves the worker and local controller source. It does not by itself certify:

- a production Linux server;
- independent R2 review;
- platform support;
- a signed desktop package;
- release support;
- production readiness;
- release or GA.
