# KRIS Qwen server control

This is the operational controller for the repo-owned Qwen worker.

## Current implementation status

As of 2026-08-19, `tool/kris_qwen_worker.py` on the Qwen control candidate reports **5.2.1**. This patch keeps Mission runtime metadata backward-compatible: when schema-v1 `runtime/meta.json` does not contain `controlPlaneBranch`, the worker uses its configured/default control branch and still verifies that exact remote branch exists before proceeding. If the runtime metadata does name a control branch, that runtime-selected branch remains authoritative. Separate v6 experiments exist in Git history, but this delivery does not claim that design: the current worker source has not implemented those v6 invariants completely. The controller therefore reads the worker's real JSON `version` response instead of hard-coding a fictional v6 version.

The control layer is Python-standard-library only. Uvicorn/Gunicorn/Flask/FastAPI are not required.

## Fastest way: run from the server and open it on your phone

From the server checkout:

```bash
chmod +x tool/run_kris_qwen_phone_control.sh
./tool/run_kris_qwen_phone_control.sh
```

The script follows the branch currently checked out on the server unless `KRIS_QWEN_REPO_BRANCH` is set. It prints:

- one or more `http://SERVER-IP:8090` URLs;
- the control-token file path;
- the control token for this installation.

Open the printed URL on your phone, paste the token into **Control token**, then press:

**Fetch latest + run Qwen**

That operation:

1. safely drains a currently running Qwen worker;
2. refuses to touch a dirty server checkout;
3. runs `git fetch origin <configured-branch>`;
4. accepts only a fast-forward update;
5. fast-forwards the checkout;
6. executes the refreshed worker's `version` command and parses its JSON `scriptVersion`;
7. verifies `gh auth status`;
8. starts the refreshed `tool/kris_qwen_worker.py stack`.

The controller process itself does not need to restart when the worker file changes. The new worker process is loaded from the refreshed bytes on disk.

Other buttons:

- **Run current Qwen** — starts the worker already present in the checkout without fetching.
- **Safe stop** — uses `kris_qwen_worker.py control stop`; it does not hard-kill the worker.

## Security boundary

Phone mode intentionally binds to `0.0.0.0`, but it is an explicit opt-in. Every API operation requires a long random bearer token and same-origin browser requests. The token is never embedded in dashboard HTML; the browser keeps it only in `sessionStorage`.

**Plain HTTP does not encrypt the token. Use phone mode only on a trusted LAN or private VPN such as Tailscale. Do not expose port 8090 directly to the public Internet.**

For an Internet-hosted server without a VPN, keep the controller loopback-only and use a tunnel instead.

## Direct controller commands

Loopback-only:

```bash
python3 tool/kris_qwen_control.py
```

Phone/trusted-LAN mode:

```bash
python3 tool/kris_qwen_control.py --phone
```

Explicit host:

```bash
python3 tool/kris_qwen_control.py --host 192.168.1.20 --allow-remote-http
```

Status:

```bash
python3 tool/kris_qwen_control.py --status
python3 tool/kris_qwen_worker.py version
```

Environment overrides:

```text
KRIS_QWEN_REPO_DIR
KRIS_QWEN_REPO_BRANCH
KRIS_QWEN_ROOT
KRIS_QWEN_PYTHON
KRIS_QWEN_CONTROL_HOST
KRIS_QWEN_CONTROL_PORT
KRIS_QWEN_CONTROL_ALLOW_REMOTE_HTTP
KRIS_QWEN_STOP_TIMEOUT
KRIS_QWEN_WORKER_ARGS
```

## Fetch safety rules

**Fetch latest + run** never uses `git reset --hard`, rebase, force checkout, or force push. It fails closed if:

- the server checkout is dirty;
- the checkout is not on the configured branch;
- the remote update is not a fast-forward;
- the worker `version` entry point is missing/broken;
- GitHub CLI authentication is unavailable to the server process;
- the current worker does not reach a safe stop before the configured timeout.

If safe stop times out, the controller leaves the worker alive and reports the failure.

## Optional systemd controller

A persistent loopback controller can be installed with:

```bash
chmod +x tool/install_kris_qwen_control_systemd.sh
sudo ./tool/install_kris_qwen_control_systemd.sh
```

The installer defaults to loopback-only. To make the installed service reachable over a trusted private network, edit `/etc/kris-qwen-control.env`:

```text
KRIS_QWEN_CONTROL_HOST=0.0.0.0
KRIS_QWEN_CONTROL_ALLOW_REMOTE_HTTP=1
```

then:

```bash
sudo systemctl restart kris-qwen-control
```

The foreground `run_kris_qwen_phone_control.sh` path is simpler when you only want to open the panel temporarily.

## Worker status note

The current 5.2 worker includes the repeated `control-plane-invalid:*` backoff behavior: after repeated identical Mission Execution authority failures it surfaces a stable blocked/recovering state instead of continuously burning fresh executions.

That behavior is separate from historical/in-progress v6 design work. This PR does not ship or claim those v6 invariants.
