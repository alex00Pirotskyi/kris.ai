#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import pathlib
import sys

SOURCE = pathlib.Path(__file__).with_name("kris_qwen_worker.py")
POLICY_ENTRY = pathlib.Path(__file__).with_name("kris_qwen_v53_policy.py")
TARGET_VERSION = "5.3.0"


def load_policy_module():
    spec = importlib.util.spec_from_file_location("kris_qwen_v53_policy_runtime", POLICY_ENTRY)
    if spec is None or spec.loader is None:
        raise SystemExit("KRIS_QWEN_V53_ERROR: cannot load 5.3 policy module")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def replace_exact(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"KRIS_QWEN_V53_ERROR: {label} expected exactly one source anchor, got {count}")
    return text.replace(old, new, 1)


def transform(text: str) -> str:
    policy = load_policy_module()

    if all(
        marker in text
        for marker in (
            'SCRIPT_VERSION = "5.3.0"',
            'def wake_pending_reviews(',
            'def seed_continuous_product_work(',
            'RED_ALERT_FRONTIER',
            '+refs/pull/*/head:refs/remotes/origin/pull/*/head',
        )
    ):
        compile(text, str(SOURCE), "exec")
        return text

    text = replace_exact(
        text,
        'SCRIPT_VERSION = "5.2.2"',
        'SCRIPT_VERSION = "5.3.0"',
        "worker version",
    )

    old_fetch = (
        'def fetch_all(cfg: Config) -> None:\n'
        '    git(cfg.anchor, "fetch", "origin", "+refs/heads/*:refs/remotes/origin/*", "--prune", timeout=1800)\n'
    )
    new_fetch = (
        'def fetch_all(cfg: Config) -> None:\n'
        '    git(\n'
        '        cfg.anchor,\n'
        '        "fetch",\n'
        '        "origin",\n'
        '        "+refs/heads/*:refs/remotes/origin/*",\n'
        '        "+refs/pull/*/head:refs/remotes/origin/pull/*/head",\n'
        '        "--prune",\n'
        '        timeout=1800,\n'
        '    )\n'
    )
    text = replace_exact(text, old_fetch, new_fetch, "immutable PR fetch")

    old_promote = '''def promote_reviewed_source_work(cfg: Config, lease: WorkLease, target_head: str) -> None:\n    candidates = [\n        w for w in runtime_work_rows(cfg)\n        if w.get("mission") == lease.work.get("mission")\n        and w.get("parentProductPr") == lease.work.get("parentProductPr")\n        and w.get("status") == "REVIEW"\n        and w.get("type") in {"PRODUCT_FEATURE", "PRODUCT_DEFECT_REPAIR", "PRODUCT_TEST", "CI_REPAIR", "BLOCKER_REMOVAL"}\n        and sorted(w.get("allowedPaths") or []) == sorted(lease.work.get("allowedPaths") or [])\n    ]\n    if len(candidates) != 1:\n        return\n    transition_work_order_cas(\n        cfg, str(candidates[0]["workOrderId"]), "HELPER_READY",\n        f"ELASTIC-QWEN-V5:R1_PASS:{target_head}", make_work_execution_id(),\n    )\n    refresh_snapshots(cfg)\n    wake_integration_for_helper(cfg, candidates[0])\n'''
    text = replace_exact(
        text,
        old_promote,
        policy.PROMOTE_REPLACEMENT.rstrip("\n"),
        "review promotion",
    )

    text = replace_exact(
        text,
        '\ndef system_prompt() -> str:\n',
        '\n' + policy.ALWAYS_ON_BLOCK + 'def system_prompt() -> str:\n',
        "always-on policy insertion",
    )

    old_housekeeping = '''        stranded_woken = wake_stranded_integrations(cfg)\n        if stranded_woken:\n            log.trace("integration-wake", f"woke stranded integration Work Orders: {stranded_woken}")\n            refresh_snapshots(cfg)\n        lease = reserve_work(cfg, worker_identity, work_execution_id)\n'''
    new_housekeeping = '''        stranded_woken = wake_stranded_integrations(cfg)\n        if stranded_woken:\n            log.trace("integration-wake", f"woke stranded integration Work Orders: {stranded_woken}")\n            refresh_snapshots(cfg)\n        frontier_recovery = recover_continuous_frontier(cfg, worker_identity, log)\n        if any(frontier_recovery.values()):\n            refresh_snapshots(cfg)\n        lease = reserve_work(cfg, worker_identity, work_execution_id)\n'''
    text = replace_exact(text, old_housekeeping, new_housekeeping, "run_one frontier recovery")

    text = text.replace('write_worker_status(cfg, "IDLE"', 'write_worker_status(cfg, "CONTINUING"')

    text = replace_exact(
        text,
        '    parser.add_argument("--loop-sleep", type=int, default=int(os.environ.get("KRIS_QWEN_LOOP_SLEEP", "60")))\n',
        '    parser.add_argument("--loop-sleep", type=int, default=int(os.environ.get("KRIS_QWEN_LOOP_SLEEP", "2")), help="red-alert/transient polling interval only; successful jobs chain immediately")\n',
        "loop sleep default",
    )
    text = replace_exact(
        text,
        '    parser.add_argument("--max-consecutive-errors", type=int, default=int(os.environ.get("KRIS_QWEN_MAX_CONSECUTIVE_ERRORS", "5")), help="persistent loop exits only after this many consecutive Qwen/job hard errors; shared runtime validation drift does not consume this budget")\n',
        '    parser.add_argument("--max-consecutive-errors", type=int, default=int(os.environ.get("KRIS_QWEN_MAX_CONSECUTIVE_ERRORS", "5")), help="threshold before repeated hard Work Order errors become RED_ALERT_HARD_ERROR; the persistent stack keeps running")\n',
        "hard error threshold help",
    )

    old_loop_start = '''                    try:\n                        result = run_one(cfg)\n'''
    new_loop_start = '''                    try:\n                        if args.command == "stack" and (\n                            managed_proc is None or managed_proc.poll() is not None\n                        ):\n                            previous_returncode = (\n                                managed_proc.poll() if managed_proc is not None else None\n                            )\n                            write_worker_status(\n                                cfg, "RED_ALERT_MODEL_SERVER",\n                                reason="managed llama-server is not running; restarting",\n                                previousReturncode=previous_returncode, jobsCompleted=jobs,\n                            )\n                            if managed_proc is not None:\n                                stop_managed_server(managed_proc)\n                            managed_proc, server_log, plan = start_managed_server(cfg)\n                            print(json.dumps({\n                                "managedServer": "RESTARTED",\n                                "serverLog": str(server_log),\n                                "resourcePlan": plan.as_dict(),\n                            }, indent=2, sort_keys=True))\n                        result = run_one(cfg)\n'''
    text = replace_exact(text, old_loop_start, new_loop_start, "managed model-server supervision")

    old_no_work = '''                    except NoEligibleWork as exc:\n                        consecutive_errors = 0\n                        transient_signature = ""\n                        transient_count = 0\n                        write_worker_status(cfg, "CONTINUING", reason=str(exc), jobsCompleted=jobs)\n                        print(f"[idle] {exc}; retrying in {cfg.loop_sleep}s")\n'''
    new_no_work = '''                    except NoEligibleWork as exc:\n                        consecutive_errors = 0\n                        transient_signature = ""\n                        transient_count = 0\n                        red_alert_retry = min(5, max(1, int(cfg.loop_sleep)))\n                        write_worker_status(\n                            cfg, "RED_ALERT_FRONTIER", reason=str(exc), redAlert=True,\n                            retrySeconds=red_alert_retry, jobsCompleted=jobs,\n                        )\n                        print(f"[red-alert] no executable Product frontier: {exc}; aggressive retry in {red_alert_retry}s")\n                        if interruptible_sleep(cfg, red_alert_retry):\n                            continue\n                        continue\n'''
    text = replace_exact(text, old_no_work, new_no_work, "NoEligibleWork red alert")

    persistent_backoff = 'backoff = max(300, int(cfg.loop_sleep) * 5)'
    if text.count(persistent_backoff) != 2:
        raise SystemExit(
            "KRIS_QWEN_V53_ERROR: expected exactly two five-minute persistent backoff anchors"
        )
    text = text.replace(
        persistent_backoff,
        'backoff = min(30, max(5, int(cfg.loop_sleep) * 5))',
    )

    old_hard_error = '''                    except WorkerError as exc:\n                        consecutive_errors += 1\n                        write_worker_status(cfg, "RECOVERING", error=str(exc), consecutiveErrors=consecutive_errors, jobsCompleted=jobs)\n                        print(\n                            f"[job-error] {exc}; consecutive={consecutive_errors}/{cfg.max_consecutive_errors}",\n                            file=sys.stderr,\n                        )\n                        if consecutive_errors >= max(1, cfg.max_consecutive_errors):\n                            raise WorkerError(\n                                f"persistent worker reached {consecutive_errors} consecutive hard Work Order errors; "\n                                f"last error: {exc}"\n                            )\n                        backoff = min(max(15, cfg.loop_sleep) * consecutive_errors, 300)\n                        print(f"[recover] re-resolving frontier in {backoff}s instead of terminating stack")\n                        if interruptible_sleep(cfg, backoff):\n                            continue\n                        continue\n'''
    new_hard_error = '''                    except WorkerError as exc:\n                        consecutive_errors += 1\n                        model_endpoint_unhealthy = (\n                            args.command == "stack"\n                            and (\n                                "cannot reach local model endpoint" in str(exc)\n                                or "managed llama-server did not become healthy" in str(exc)\n                            )\n                        )\n                        if model_endpoint_unhealthy:\n                            write_worker_status(\n                                cfg, "RED_ALERT_MODEL_SERVER", error=str(exc),\n                                consecutiveErrors=consecutive_errors, jobsCompleted=jobs,\n                            )\n                            if managed_proc is not None:\n                                with contextlib.suppress(Exception):\n                                    stop_managed_server(managed_proc)\n                            managed_proc = None\n                        persistent_hard_error = consecutive_errors >= max(1, cfg.max_consecutive_errors)\n                        backoff = min(30, max(5, int(cfg.loop_sleep) * min(consecutive_errors, 15)))\n                        status_state = (\n                            "RED_ALERT_MODEL_SERVER" if model_endpoint_unhealthy\n                            else ("RED_ALERT_HARD_ERROR" if persistent_hard_error else "RECOVERING")\n                        )\n                        write_worker_status(\n                            cfg, status_state, error=str(exc),\n                            consecutiveErrors=consecutive_errors,\n                            persistentHardError=persistent_hard_error,\n                            retrySeconds=backoff, jobsCompleted=jobs,\n                        )\n                        tag = (\n                            "red-alert-model-server" if model_endpoint_unhealthy\n                            else ("red-alert-hard-error" if persistent_hard_error else "job-error")\n                        )\n                        print(\n                            f"[{tag}] {exc}; consecutive={consecutive_errors}/"\n                            f"{cfg.max_consecutive_errors}; re-resolving in {backoff}s; stack stays alive",\n                            file=sys.stderr,\n                        )\n                        if interruptible_sleep(cfg, backoff):\n                            continue\n                        continue\n'''
    text = replace_exact(text, old_hard_error, new_hard_error, "persistent hard error recovery")

    old_tail = '''                    if interruptible_sleep(cfg, cfg.loop_sleep):\n                        continue\n'''
    if text.count(old_tail) < 1:
        raise SystemExit("KRIS_QWEN_V53_ERROR: persistent loop sleep anchor missing")
    pos = text.rfind(old_tail)
    text = (
        text[:pos]
        + '                    # Successful work chains immediately; no normal idle sleep.\n'
        + '                    continue\n'
        + text[pos + len(old_tail):]
    )

    required = (
        'SCRIPT_VERSION = "5.3.0"',
        '+refs/pull/*/head:refs/remotes/origin/pull/*/head',
        'def wake_pending_reviews(',
        'def ensure_continuous_integration_lane(',
        'def ensure_continuous_validation_lane(',
        'def seed_continuous_product_work(',
        'CONTINUOUS_PRIMARY_CODE_PREFIXES',
        'CONTINUOUS_TOOL_DENY_PREFIXES',
        'RED_ALERT_FRONTIER',
        'RED_ALERT_HARD_ERROR',
        'RED_ALERT_MODEL_SERVER',
        'managedServer": "RESTARTED',
        'backoff = min(30, max(5, int(cfg.loop_sleep) * 5))',
        'stack stays alive',
        'Successful work chains immediately',
    )
    missing = [marker for marker in required if marker not in text]
    if missing:
        raise SystemExit(f"KRIS_QWEN_V53_ERROR: transformed worker missing markers: {missing}")
    compile(text, str(SOURCE), "exec")
    return text


def main() -> None:
    transformed = transform(SOURCE.read_text(encoding="utf-8"))
    namespace = {
        "__name__": "__main__",
        "__file__": str(pathlib.Path(__file__).resolve()),
        "__package__": None,
        "__cached__": None,
    }
    exec(compile(transformed, str(SOURCE), "exec"), namespace, namespace)


if __name__ == "__main__":
    main()
