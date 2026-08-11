# KRIS Qwen server control

This is the simple operational mode for the local Qwen Mission Execution worker.

## What runs

There are two layers:

1. `kris-qwen-control.service` — a tiny persistent localhost HTTP controller.
2. `tool/kris_qwen_worker.py stack` — the repo-owned Qwen stack that the controller starts and drains.

The controller stays available while the worker is stopped. It uses only the Python standard library and systemd; Gunicorn, Flask and FastAPI are not required.

`serve` is intentionally **not** used by the dashboard. `serve` starts only `llama-server`. `stack` starts the tuned `llama-server` and the worker loop as one lifecycle.

## Buttons

- **Start worker** — verifies the repo-owned worker entrypoint and starts `stack`.
- **Safe stop** — writes the worker's existing `operator/stop-request.json` graceful-stop request. It never sends a hard kill.
- **Refresh + restart** — requests a safe stop, waits for the worker to drain, refuses a dirty checkout, fetches the configured Git branch, accepts only a fast-forward, verifies the refreshed worker entrypoint, and starts it again.

The status panel shows the worker PID/state, Git branch/head, script version, current controller operation, and recent worker output.

## One-time install

From the server checkout of `alex00Pirotskyi/kris.ai`:

```bash
chmod +x tool/install_kris_qwen_control_systemd.sh
sudo ./tool/install_kris_qwen_control_systemd.sh
```

The installer writes:

- `/etc/systemd/system/kris-qwen-control.service`
- `/etc/kris-qwen-control.env`

Edit `/etc/kris-qwen-control.env` for model/worker overrides, then restart only the controller:

```bash
sudo systemctl restart kris-qwen-control
```

A controller restart does not intentionally hard-stop the Qwen worker; the service uses `KillMode=process` so the repo-owned worker remains governed by its own graceful-stop protocol.

## Open the dashboard

The controller deliberately binds only to `127.0.0.1`. From your laptop/desktop, use an SSH tunnel:

```bash
ssh -L 8090:127.0.0.1:8090 root@YOUR_SERVER
```

Then open:

```text
http://127.0.0.1:8090
```

Do not bind this control endpoint directly to the public Internet. POST operations require a per-install token, but localhost + SSH tunneling is the intended boundary.

## Migrating from the old manual command

If a manually launched command such as this is still running:

```bash
python ./kris_qwen_worker_v5_1_9.py serve
```

stop that old process once before pressing **Start worker**. A standalone `serve` process owns the model port but does not participate in the worker process lock/graceful-stop lifecycle.

After migration, use the dashboard rather than manually starting `serve`.

## Refresh safety rules

**Refresh + restart never performs `git reset --hard`, force checkout, rebase, or force push.** It fails closed when:

- the server checkout is dirty;
- the checkout is not on the configured branch;
- the remote update is not a fast-forward;
- the refreshed worker fails its `version` entrypoint probe;
- the current worker does not reach a safe stop before `KRIS_QWEN_STOP_TIMEOUT`.

If safe stop times out, the controller reports the error and leaves the worker alive instead of killing it.

## Current control-plane validation failure

The repeated message:

```text
shared Mission Execution runtime validation is unhealthy;
Work Order path exceeds mission/shared authority policy: lib/product/product_runtime.dart
```

is a repository/runtime authority validation failure, not a llama.cpp health failure. Worker v5.2 changes the repeated-invalid-state behavior: after three identical `control-plane-invalid:*` failures it exposes `BLOCKED_CONTROL_PLANE` and backs off for at least five minutes instead of creating a new execution every 30 seconds forever.

That makes the fault visible in the dashboard without hiding it. The actual invalid Work Order/control-plane record still has to be repaired by the Mission Execution authority that owns that runtime state.

## Useful commands

```bash
systemctl status kris-qwen-control --no-pager
journalctl -u kris-qwen-control -f
python3 tool/kris_qwen_control.py --status
python3 tool/kris_qwen_worker.py version
```
