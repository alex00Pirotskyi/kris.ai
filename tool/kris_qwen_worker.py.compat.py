#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re

SOURCE = pathlib.Path(__file__).with_name("kris_qwen_worker.py")
TARGET_VERSION = "5.3.0"

_ALWAYS_ON_BLOCK = r'''
CONTINUOUS_ACTIVE_WORK_STATES = {
    "READY", "RESERVED", "IN_PROGRESS", "HELPER_READY", "INTEGRATING",
    "VALIDATING", "REVIEW",
}
CONTINUOUS_SOURCE_TYPES = {
    "PRODUCT_FEATURE", "PRODUCT_DEFECT_REPAIR", "PRODUCT_TEST", "CI_REPAIR",
    "BLOCKER_REMOVAL",
}
CONTINUOUS_CODE_PREFIXES = (
    "lib/", "test/", "automation_host/", "services/", "native/", "tool/",
)


def review_requires_external_identity(work: dict[str, Any]) -> bool:
    if str(work.get("externalReviewerGitHub") or "").strip():
        return True
    text = (str(work.get("objective") or "") + "\n" + "\n".join(
        str(x) for x in work.get("requiredTests", [])
    )).lower()
    return any(
        marker in text
        for marker in (
            "must be submitted by github identity",
            "distinct external reviewer identity",
            "externalreviewergithub",
            "requires github identity alex11",
        )
    )


def wake_pending_reviews(cfg: Config) -> list[str]:
    rows = sorted(
        (
            row for row in runtime_work_rows(cfg)
            if row.get("status") == "REVIEW"
            and row.get("type") == "REVIEW"
            and not row.get("activeSemaphoreId")
        ),
        key=lambda row: (-int(row.get("priority", 0)), str(row.get("workOrderId"))),
    )
    for row in rows:
        work_id = str(row.get("workOrderId") or "")
        if not work_id or local_cooldown_active(cfg, work_id):
            continue
        if review_requires_external_identity(row):
            continue
        try:
            if not review_is_independent_enough(cfg, row):
                continue
            _, _, target_head = review_target(cfg, row)
            transition_work_order_cas(
                cfg,
                work_id,
                "READY",
                f"ELASTIC-QWEN-V53:AUTO_WAKE_REVIEW:{target_head}",
                make_work_execution_id(),
            )
            return [work_id]
        except (CASLost, TransientFleetState):
            refresh_snapshots(cfg)
            return []
        except Exception:
            continue
    return []


def continuous_seed_allowed_paths(cfg: Config, product: dict[str, Any]) -> list[str]:
    parent_pr = int(product["productPr"])
    paths: list[str] = []
    for row in runtime_work_rows(cfg):
        if row.get("parentProductPr") != parent_pr or row.get("type") not in CONTINUOUS_SOURCE_TYPES:
            continue
        for raw in row.get("allowedPaths") or []:
            value = str(raw)
            if value.startswith(CONTINUOUS_CODE_PREFIXES) and value not in paths:
                paths.append(value)
    if paths:
        return paths[:24]
    branch = str(product["branch"])
    diff = git(
        cfg.anchor,
        "diff",
        "--name-only",
        f"origin/{cfg.main_branch}...origin/{branch}",
        "--",
        check=False,
        timeout=120,
    )
    if diff.returncode != 0:
        return []
    for raw in diff.stdout.splitlines():
        value = raw.strip()
        if value.startswith(CONTINUOUS_CODE_PREFIXES) and value not in paths:
            paths.append(value)
    return paths[:24]


def seed_continuous_product_work(cfg: Config, worker_identity: str) -> str | None:
    products = []
    for path in sorted((cfg.runtime / "runtime/integration/product-prs").glob("*.json")):
        product = read_json(path)
        if product.get("status") == "ACTIVE":
            products.append(product)
    products.sort(key=lambda row: (str(row.get("mission")), str(row.get("task"))))
    all_work = runtime_work_rows(cfg)
    for product in products:
        parent_pr = product.get("productPr")
        if not isinstance(parent_pr, int) or parent_pr <= 0:
            continue
        if any(
            row.get("parentProductPr") == parent_pr
            and row.get("status") in CONTINUOUS_ACTIVE_WORK_STATES
            for row in all_work
        ):
            continue
        branch = str(product.get("branch") or "")
        if not branch:
            continue
        try:
            info = gh_pr_info(cfg, parent_pr)
            live_head = git(cfg.anchor, "rev-parse", f"origin/{branch}").stdout.strip()
        except Exception:
            continue
        if (
            info.get("state") != "OPEN"
            or str(info.get("headRefName") or "") != branch
            or str(info.get("headRefOid") or "") != live_head
        ):
            continue
        allowed_paths = continuous_seed_allowed_paths(cfg, product)
        if not allowed_paths:
            continue
        live_tree = exact_tree(cfg.anchor, live_head)
        for attempt in range(1, 5):
            refresh_snapshots(cfg)
            generation = runtime_generation(cfg)
            work_id = (
                f"WO-{slug(str(product['task']), 18).upper()}-CONTINUOUS-QWEN-"
                f"{short_id(8).upper()}"
            )
            spec = {
                "schemaVersion": 1,
                "workOrderId": work_id,
                "mission": product["mission"],
                "roadmapTask": product["task"],
                "parentProductPr": parent_pr,
                "priority": 85,
                "type": "PRODUCT_DEFECT_REPAIR",
                "objective": (
                    "Always-on Product hardening. Inspect exact current Product source/tests inside "
                    "allowedPaths, identify one concrete correctness, performance, reliability, "
                    "UX-facing behavior, or missing-regression defect that can be proven locally, "
                    "and implement the smallest durable code/test fix. Do not create documentation-"
                    "only, formatting-only, governance-only, or no-op changes."
                ),
                "requestedRole": "DEFECT_HUNTER",
                "allowedPaths": allowed_paths,
                "baseCommit": live_head,
                "baseTree": live_tree,
                "dependencyRequirements": [],
                "requiredTests": [
                    "run at least one focused local product/source regression or analyzer command and require exit 0",
                    "final changed paths remain inside exact Work Order allowedPaths",
                    "no documentation-only or no-op candidate is allowed",
                ],
                "maxChildWorkOrders": 1,
                "status": "READY",
                "createdBy": worker_identity,
                "createdAt": utc_iso(),
            }
            with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False, suffix=".json") as fh:
                json.dump(spec, fh, indent=2, sort_keys=True)
                fh.write("\n")
                spec_path = fh.name
            try:
                result = control_python(
                    cfg,
                    "mission_orchestrator.py",
                    "--project", str(cfg.runtime),
                    "work-create",
                    "--spec", spec_path,
                    "--work-id", make_work_execution_id(),
                    "--expected-generation", str(generation),
                    check=False,
                )
            finally:
                pathlib.Path(spec_path).unlink(missing_ok=True)
            if result.returncode != 0:
                if git(cfg.runtime, "status", "--porcelain", check=False).stdout.strip():
                    git(cfg.runtime, "reset", "--hard", f"origin/{cfg.runtime_branch}", check=False)
                    git(cfg.runtime, "clean", "-fd", check=False)
                if "runtime generation moved" in result.combined(4000) and attempt < 4:
                    continue
                break
            try:
                commit_runtime_transition(
                    cfg,
                    f"mission-runtime: seed always-on Product hardening {work_id}",
                )
            except CASLost:
                if attempt < 4:
                    continue
                return None
            refresh_snapshots(cfg)
            resilient_preflight(cfg)
            return work_id
    return None


def recover_continuous_frontier(cfg: Config, worker_identity: str, log: JsonlLog) -> dict[str, Any]:
    woken_reviews = wake_pending_reviews(cfg)
    if woken_reviews:
        log.trace("review-wake", f"woke pending R1 review Work Orders: {woken_reviews}")
        refresh_snapshots(cfg)
    front = dispatcher(cfg, worker_identity)
    if select_safe_candidate(cfg, front, cfg.allowed_types) is not None:
        return {"wokenReviews": woken_reviews, "seededWorkOrder": None}
    seeded = seed_continuous_product_work(cfg, worker_identity)
    if seeded:
        log.trace("frontier-seed", f"created bounded always-on Product hardening Work Order: {seeded}")
        refresh_snapshots(cfg)
    return {"wokenReviews": woken_reviews, "seededWorkOrder": seeded}

'''

_PROMOTE_REPLACEMENT = r'''def promote_reviewed_source_work(cfg: Config, lease: WorkLease, target_head: str) -> None:
    candidates = [
        w for w in runtime_work_rows(cfg)
        if w.get("mission") == lease.work.get("mission")
        and w.get("parentProductPr") == lease.work.get("parentProductPr")
        and w.get("status") in {"REVIEW", "HELPER_READY"}
        and w.get("type") in {"PRODUCT_FEATURE", "PRODUCT_DEFECT_REPAIR", "PRODUCT_TEST", "CI_REPAIR", "BLOCKER_REMOVAL"}
        and sorted(w.get("allowedPaths") or []) == sorted(lease.work.get("allowedPaths") or [])
    ]
    if len(candidates) != 1:
        return
    source_work = candidates[0]
    if source_work.get("status") == "REVIEW":
        transition_work_order_cas(
            cfg,
            str(source_work["workOrderId"]),
            "HELPER_READY",
            f"ELASTIC-QWEN-V53:R1_PASS:{target_head}",
            make_work_execution_id(),
        )
        refresh_snapshots(cfg)
        source_work = next(
            row for row in runtime_work_rows(cfg)
            if row.get("workOrderId") == source_work.get("workOrderId")
        )
    integrations = sorted(
        (
            row for row in runtime_work_rows(cfg)
            if row.get("parentProductPr") == source_work.get("parentProductPr")
            and row.get("type") == "INTEGRATION"
            and row.get("status") in {"VALIDATING", "BLOCKED"}
            and not row.get("activeSemaphoreId")
        ),
        key=lambda row: (-int(row.get("priority", 0)), str(row.get("workOrderId"))),
    )
    if integrations:
        transition_work_order_cas(
            cfg,
            str(integrations[0]["workOrderId"]),
            "READY",
            f"ELASTIC-QWEN-V53:REVIEWED_HELPER_INTEGRATION_WAKE:{target_head}",
            make_work_execution_id(),
        )
        refresh_snapshots(cfg)

'''


def _sub1(text: str, pattern: str, replacement: str, label: str, flags: int = 0) -> str:
    out, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"KRIS_QWEN_COMPAT_ERROR: {label} expected one match, got {count}")
    return out


def _already_v53(text: str) -> bool:
    required = (
        'SCRIPT_VERSION = "5.3.0"',
        '+refs/pull/*/head:refs/remotes/origin/pull/*/head',
        'def wake_pending_reviews(',
        'def seed_continuous_product_work(',
        'RED_ALERT_FRONTIER',
    )
    return all(marker in text for marker in required)


def transform(text: str) -> str:
    if _already_v53(text):
        compile(text, str(SOURCE), "exec")
        return text

    if text.count('SCRIPT_VERSION = "5.2.2"') != 1:
        raise SystemExit("KRIS_QWEN_COMPAT_ERROR: unsupported normal worker version for 5.3 transform")

    text = text.replace('SCRIPT_VERSION = "5.2.2"', 'SCRIPT_VERSION = "5.3.0"', 1)

    text = _sub1(
        text,
        r'def fetch_all\(cfg: Config\) -> None:\n(?:    .*\n)+?(?=\ndef )',
        '''def fetch_all(cfg: Config) -> None:\n    git(\n        cfg.anchor,\n        "fetch",\n        "origin",\n        "+refs/heads/*:refs/remotes/origin/*",\n        "+refs/pull/*/head:refs/remotes/origin/pull/*/head",\n        "--prune",\n        timeout=1800,\n    )\n\n''',
        "fetch-all",
    )

    text = _sub1(
        text,
        r'def promote_reviewed_source_work\(cfg: Config, lease: WorkLease, target_head: str\) -> None:\n.*?(?=\ndef integrate_helper_candidate\()',
        _PROMOTE_REPLACEMENT + "\n",
        "reviewed-helper integration wake",
        re.S,
    )

    text = _sub1(
        text,
        r'\ndef validate_authority_append_safety\(cfg: Config, lease: WorkLease\) -> None:\n',
        "\n" + _ALWAYS_ON_BLOCK + "def validate_authority_append_safety(cfg: Config, lease: WorkLease) -> None:\n",
        "always-on insertion",
    )

    text = _sub1(
        text,
        r'(        stranded_woken = wake_stranded_integrations\(cfg\)\n'
        r'        if stranded_woken:\n'
        r'            log\.trace\("integration-wake", f"woke stranded integration Work Orders: \{stranded_woken\}"\)\n'
        r'            refresh_snapshots\(cfg\)\n)'
        r'(        lease = reserve_work\(cfg, worker_identity, work_execution_id\)\n)',
        r'\1        frontier_recovery = recover_continuous_frontier(cfg, worker_identity, log)\n'
        r'        if frontier_recovery.get("wokenReviews") or frontier_recovery.get("seededWorkOrder"):\n'
        r'            refresh_snapshots(cfg)\n\2',
        "run-one frontier recovery",
    )

    text = text.replace('write_worker_status(cfg, "IDLE"', 'write_worker_status(cfg, "CONTINUING"')

    text = _sub1(
        text,
        r'parser\.add_argument\("--loop-sleep", type=int, default=int\(os\.environ\.get\("KRIS_QWEN_LOOP_SLEEP", "60"\)\)\)',
        'parser.add_argument("--loop-sleep", type=int, default=int(os.environ.get("KRIS_QWEN_LOOP_SLEEP", "2")), help="red-alert/transient polling interval only; successful jobs chain immediately")',
        "loop sleep default",
    )

    text = _sub1(
        text,
        r'(                    except NoEligibleWork as exc:\n)(.*?)(?=                    except )',
        r'''\1                        consecutive_errors = 0
                        transient_signature = ""
                        transient_count = 0
                        red_alert_retry = min(5, max(1, int(cfg.loop_sleep)))
                        write_worker_status(
                            cfg, "RED_ALERT_FRONTIER", reason=str(exc), redAlert=True,
                            retrySeconds=red_alert_retry, jobsCompleted=jobs,
                        )
                        print(f"[red-alert] no executable Product frontier: {exc}; aggressive retry in {red_alert_retry}s")
                        if interruptible_sleep(cfg, red_alert_retry):
                            continue
                        continue
''',
        "no-eligible red alert",
        re.S,
    )

    sleep_block = '                    if interruptible_sleep(cfg, cfg.loop_sleep):\n                        continue\n'
    pos = text.rfind(sleep_block)
    if pos < 0:
        raise SystemExit("KRIS_QWEN_COMPAT_ERROR: outer inter-job sleep not found")
    text = (
        text[:pos]
        + '                    # Successful work chains immediately; no normal idle sleep.\n'
        + '                    continue\n'
        + text[pos + len(sleep_block):]
    )

    if not _already_v53(text):
        raise SystemExit("KRIS_QWEN_COMPAT_ERROR: 5.3 transform incomplete")
    compile(text, str(SOURCE), "exec")
    return text


def main() -> None:
    text = SOURCE.read_text(encoding="utf-8")
    transformed = transform(text)
    namespace = {
        "__name__": "__main__",
        "__file__": str(SOURCE),
        "__package__": None,
        "__cached__": None,
    }
    exec(compile(transformed, str(SOURCE), "exec"), namespace, namespace)


if __name__ == "__main__":
    main()
