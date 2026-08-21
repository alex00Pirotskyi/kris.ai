#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import pathlib
import sys

SOURCE = pathlib.Path(__file__).with_name("kris_qwen_worker.py")
V53_ENTRY = pathlib.Path(__file__).with_name("kris_qwen_worker_v53_base.py")
RECONCILE_ENTRY = pathlib.Path(__file__).with_name("kris_qwen_v53_reconcile.py")
TARGET_VERSION = "5.3.1"


def load_module(path: pathlib.Path, name: str, label: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"KRIS_QWEN_V531_ERROR: cannot load {label}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def replace_exact(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"KRIS_QWEN_V531_ERROR: {label} expected exactly one source anchor, got {count}"
        )
    return text.replace(old, new, 1)


def transform(text: str) -> str:
    v53 = load_module(V53_ENTRY, "kris_qwen_v53_base_transform", "retained 5.3 base transformer")
    reconcile = load_module(
        RECONCILE_ENTRY,
        "kris_qwen_v53_reconcile_runtime",
        "5.3.1 Product reconciliation policy",
    )
    text = v53.transform(text)

    text = replace_exact(
        text,
        'SCRIPT_VERSION = "5.3.0"',
        'SCRIPT_VERSION = "5.3.1"',
        "worker version",
    )

    text = replace_exact(
        text,
        '\ndef system_prompt() -> str:\n',
        '\n' + reconcile.RECONCILE_BLOCK + 'def system_prompt() -> str:\n',
        "reconciliation/schema insertion",
    )

    old_pre_housekeeping = '''        model_health(cfg)\n        refresh_snapshots(cfg)\n        reap_expired_runtime(cfg)\n'''
    new_pre_housekeeping = '''        model_health(cfg)\n        refresh_snapshots(cfg)\n        # Reconcile safe generated Product descendants before any mutable\n        # housekeeping or continuous-frontier seeding.\n        resilient_preflight(cfg)\n        reap_expired_runtime(cfg)\n'''
    text = replace_exact(
        text,
        old_pre_housekeeping,
        new_pre_housekeeping,
        "pre-housekeeping reconciliation order",
    )

    text = replace_exact(
        text,
        '        frontier_recovery = recover_continuous_frontier(cfg, worker_identity, log)\n',
        '        resilient_preflight(cfg)\n        frontier_recovery = recover_continuous_frontier(cfg, worker_identity, log)\n',
        "pre-continuous-frontier reconciliation order",
    )

    text = replace_exact(
        text,
        '        reply = chat_reply(cfg, messages, max_tokens=min(cfg.max_tokens, 1024))\n',
        '        reply = chat_reply(\n            cfg, messages, max_tokens=min(cfg.max_tokens, 1024),\n            response_schema=REVIEW_ACTION_SCHEMA,\n        )\n',
        "review exploration JSON schema",
    )
    text = replace_exact(
        text,
        '        reply = chat_reply(cfg, messages, max_tokens=min(cfg.max_tokens, 768))\n',
        '        reply = chat_reply(\n            cfg, messages, max_tokens=min(cfg.max_tokens, 768),\n            response_schema=REVIEW_FINAL_SCHEMA,\n        )\n',
        "review final JSON schema",
    )

    old_transient = '''                    except TransientFleetState as exc:\n                        consecutive_errors = 0\n                        signature = str(getattr(exc, "signature", "") or str(exc))\n'''
    new_transient = '''                    except TransientFleetState as exc:\n                        if isinstance(exc, ProductDivergenceWatch):\n                            consecutive_errors = 0\n                            transient_signature = ""\n                            transient_count = 0\n                            wait_result = wait_for_product_divergence_change(\n                                cfg, exc, jobs_completed=jobs\n                            )\n                            if wait_result == "STOP_REQUESTED":\n                                continue\n                            # The relevant remote authority changed. Resume exactly\n                            # one full resolution cycle instead of repeatedly running\n                            # doctor/hygiene/audit while the refs are unchanged.\n                            continue\n                        consecutive_errors = 0\n                        signature = str(getattr(exc, "signature", "") or str(exc))\n'''
    text = replace_exact(
        text,
        old_transient,
        new_transient,
        "cheap Product divergence polling",
    )

    required = (
        'SCRIPT_VERSION = "5.3.1"',
        'class ProductDivergenceWatch',
        'def reconcile_safe_generated_product_descendant',
        'PRODUCT_RUNTIME_RECONCILED',
        'github-actions-linear-generated-descendant-v1',
        'RED_ALERT_PRODUCT_DIVERGENCE',
        'polling refs only',
        'REVIEW_ACTION_SCHEMA',
        'REVIEW_FINAL_SCHEMA',
        '"type": "json_schema"',
        'response_schema=REVIEW_ACTION_SCHEMA',
        'response_schema=REVIEW_FINAL_SCHEMA',
        'resilient_preflight(cfg)\n        frontier_recovery',
        '+refs/pull/*/head:refs/remotes/origin/pull/*/head',
        'RED_ALERT_HARD_ERROR',
        'RED_ALERT_MODEL_SERVER',
        'stack stays alive',
    )
    missing = [marker for marker in required if marker not in text]
    if missing:
        raise SystemExit(f"KRIS_QWEN_V531_ERROR: transformed worker missing markers: {missing}")
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
