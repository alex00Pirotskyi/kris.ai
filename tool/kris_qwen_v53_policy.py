#!/usr/bin/env python3
from __future__ import annotations

ALWAYS_ON_BLOCK = r'''
CONTINUOUS_ACTIVE_WORK_STATES = {
    "READY", "RESERVED", "IN_PROGRESS", "HELPER_READY", "INTEGRATING",
    "VALIDATING", "REVIEW",
}
CONTINUOUS_SOURCE_TYPES = {
    "PRODUCT_FEATURE", "PRODUCT_DEFECT_REPAIR", "PRODUCT_TEST", "CI_REPAIR",
    "BLOCKER_REMOVAL",
}
CONTINUOUS_PRIMARY_CODE_PREFIXES = (
    "lib/", "test/", "automation_host/", "services/", "native/",
)
CONTINUOUS_CODE_PREFIXES = CONTINUOUS_PRIMARY_CODE_PREFIXES + ("tool/",)
CONTINUOUS_TOOL_DENY_PREFIXES = (
    "tool/kris_qwen_",
    "tool/mission_",
    "tool/branch_hygiene",
    "tool/p1a_",
    "tool/workflow_integrity",
)
CONTINUOUS_SOURCE_MARKER = "CONTINUOUS-QWEN"
CONTINUOUS_INTEGRATION_MARKER = "ALWAYS_ON_CONTINUOUS_INTEGRATION"
CONTINUOUS_CI_MARKER = "CONTINUOUS_QWEN_VALIDATE_INTEGRATION="


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


def helper_ready_children(cfg: Config, work: dict[str, Any]) -> list[dict[str, Any]]:
    direct = [
        row for row in work_children(cfg, str(work["workOrderId"]))
        if row.get("status") == "HELPER_READY"
    ]
    if direct:
        return sorted(
            direct,
            key=lambda row: (-int(row.get("priority", 0)), str(row.get("workOrderId"))),
        )
    patterns = [str(x) for x in work.get("allowedPaths") or []]
    if not patterns:
        return []
    candidates = []
    for row in runtime_work_rows(cfg):
        if row.get("parentProductPr") != work.get("parentProductPr"):
            continue
        if row.get("status") != "HELPER_READY" or row.get("type") not in CONTINUOUS_SOURCE_TYPES:
            continue
        paths = [normalize_relpath(str(x)) for x in row.get("allowedPaths") or []]
        if not paths or not all(allowed_write(path, patterns) for path in paths):
            continue
        candidates.append(row)
    return sorted(
        candidates,
        key=lambda row: (-int(row.get("priority", 0)), str(row.get("workOrderId"))),
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


def _create_continuous_work_order(
    cfg: Config,
    spec: dict[str, Any],
    commit_message: str,
    *,
    retries: int = 4,
) -> bool:
    for attempt in range(1, retries + 1):
        refresh_snapshots(cfg)
        generation = runtime_generation(cfg)
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
            if "runtime generation moved" in result.combined(4000) and attempt < retries:
                continue
            return False
        try:
            commit_runtime_transition(cfg, commit_message)
        except CASLost:
            if attempt < retries:
                continue
            return False
        refresh_snapshots(cfg)
        resilient_preflight(cfg)
        return True
    return False


def _continuous_path_bucket(value: str) -> int | None:
    value = str(value).strip()
    if any(value.startswith(prefix) for prefix in CONTINUOUS_PRIMARY_CODE_PREFIXES):
        return 0
    if value.startswith("tool/"):
        if any(value.startswith(prefix) for prefix in CONTINUOUS_TOOL_DENY_PREFIXES):
            return None
        return 1
    return None


def continuous_seed_allowed_paths(cfg: Config, product: dict[str, Any]) -> list[str]:
    parent_pr = int(product["productPr"])
    primary: list[str] = []
    fallback: list[str] = []

    def collect(value: str) -> None:
        bucket = _continuous_path_bucket(value)
        if bucket is None:
            return
        target = primary if bucket == 0 else fallback
        if value not in target:
            target.append(value)

    for row in runtime_work_rows(cfg):
        if row.get("parentProductPr") != parent_pr or row.get("type") not in CONTINUOUS_SOURCE_TYPES:
            continue
        for raw in row.get("allowedPaths") or []:
            collect(str(raw))
    if primary:
        return primary[:24]
    if fallback:
        return fallback[:24]

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
        collect(raw.strip())
    return (primary or fallback)[:24]


def continuous_source_work(row: dict[str, Any]) -> bool:
    return (
        CONTINUOUS_SOURCE_MARKER in str(row.get("workOrderId") or "")
        and row.get("type") in {"PRODUCT_FEATURE", "PRODUCT_DEFECT_REPAIR", "PRODUCT_TEST"}
    )


def ensure_continuous_integration_lane(cfg: Config, worker_identity: str) -> str | None:
    rows = runtime_work_rows(cfg)
    helpers = sorted(
        (
            row for row in rows
            if row.get("status") == "HELPER_READY" and continuous_source_work(row)
        ),
        key=lambda row: (-int(row.get("priority", 0)), str(row.get("workOrderId"))),
    )
    for helper in helpers:
        parent_pr = int(helper["parentProductPr"])
        existing = [
            row for row in rows
            if row.get("parentProductPr") == parent_pr
            and row.get("type") == "INTEGRATION"
            and CONTINUOUS_INTEGRATION_MARKER in str(row.get("objective") or "")
            and row.get("status") not in {"LANDED", "SUPERSEDED", "CANCELLED"}
        ]
        if existing:
            wakeable = sorted(
                (
                    row for row in existing
                    if row.get("status") == "BLOCKED" and not row.get("activeSemaphoreId")
                ),
                key=lambda row: (-int(row.get("priority", 0)), str(row.get("workOrderId"))),
            )
            if wakeable:
                transition_work_order_cas(
                    cfg,
                    str(wakeable[0]["workOrderId"]),
                    "READY",
                    "ELASTIC-QWEN-V53:CONTINUOUS_HELPER_READY",
                    make_work_execution_id(),
                )
                return str(wakeable[0]["workOrderId"])
            continue
        product = product_pr_record(cfg, parent_pr)
        live_head = str(product.get("observedHead") or "")
        branch = str(product.get("branch") or "")
        if not branch:
            continue
        actual_head = git(cfg.anchor, "rev-parse", f"origin/{branch}").stdout.strip()
        if live_head != actual_head:
            continue
        live_tree = exact_tree(cfg.anchor, live_head)
        work_id = f"WO-{slug(str(helper['roadmapTask']), 18).upper()}-CONTINUOUS-INTEGRATE-{short_id(8).upper()}"
        spec = {
            "schemaVersion": 1,
            "workOrderId": work_id,
            "mission": helper["mission"],
            "roadmapTask": helper["roadmapTask"],
            "parentProductPr": parent_pr,
            "priority": 95,
            "type": "INTEGRATION",
            "objective": (
                f"{CONTINUOUS_INTEGRATION_MARKER} sourceWorkOrder={helper['workOrderId']}. "
                "Integrate exactly one scope-compatible HELPER_READY Product hardening candidate into the "
                "canonical Product branch. Preserve source outside the helper/integration path envelope. "
                "Exact tri-platform Product CI remains mandatory before this integration becomes LANDED."
            ),
            "requestedRole": "INTEGRATOR",
            "allowedPaths": list(helper.get("allowedPaths") or []),
            "baseCommit": live_head,
            "baseTree": live_tree,
            "dependencyRequirements": [],
            "requiredTests": [
                "integrate exactly one HELPER_READY candidate whose paths fit the integration allowedPaths",
                "canonical Product branch update is non-force and exact-head guarded",
                "post-integration workflow_dispatch product-gates must pass Ubuntu, Windows, and macOS before LANDED",
            ],
            "maxChildWorkOrders": 0,
            "status": "READY",
            "createdBy": worker_identity,
            "createdAt": utc_iso(),
        }
        if _create_continuous_work_order(
            cfg,
            spec,
            f"mission-runtime: seed continuous integration {work_id}",
        ):
            return work_id
    return None


def ensure_continuous_validation_lane(cfg: Config, worker_identity: str) -> str | None:
    rows = runtime_work_rows(cfg)
    integrations = sorted(
        (
            row for row in rows
            if row.get("type") == "INTEGRATION"
            and row.get("status") == "VALIDATING"
            and CONTINUOUS_INTEGRATION_MARKER in str(row.get("objective") or "")
            and not row.get("activeSemaphoreId")
        ),
        key=lambda row: (-int(row.get("priority", 0)), str(row.get("workOrderId"))),
    )
    for integration in integrations:
        integration_id = str(integration["workOrderId"])
        marker = CONTINUOUS_CI_MARKER + integration_id
        ci_rows = [
            row for row in rows
            if row.get("parentProductPr") == integration.get("parentProductPr")
            and row.get("type") == "CI_REPAIR"
            and marker in str(row.get("objective") or "")
        ]
        terminal = sorted(
            (
                row for row in ci_rows
                if row.get("status") in {"LANDED", "BLOCKED"}
            ),
            key=lambda row: str(row.get("updatedAt") or ""),
            reverse=True,
        )
        if terminal:
            next_status = "LANDED" if terminal[0].get("status") == "LANDED" else "BLOCKED"
            transition_work_order_cas(
                cfg,
                integration_id,
                next_status,
                f"ELASTIC-QWEN-V53:CONTINUOUS_EXACT_CI_{next_status}",
                make_work_execution_id(),
            )
            return integration_id
        if any(row.get("status") in CONTINUOUS_ACTIVE_WORK_STATES for row in ci_rows):
            continue
        product = product_pr_record(cfg, int(integration["parentProductPr"]))
        live_head = str(product.get("observedHead") or "")
        branch = str(product.get("branch") or "")
        if not branch:
            continue
        actual_head = git(cfg.anchor, "rev-parse", f"origin/{branch}").stdout.strip()
        if not live_head or live_head != actual_head:
            continue
        live_tree = exact_tree(cfg.anchor, live_head)
        ci_id = f"WO-{slug(str(integration['roadmapTask']), 18).upper()}-CONTINUOUS-CI-{short_id(8).upper()}"
        spec = {
            "schemaVersion": 1,
            "workOrderId": ci_id,
            "mission": integration["mission"],
            "roadmapTask": integration["roadmapTask"],
            "parentProductPr": int(integration["parentProductPr"]),
            "priority": 100,
            "type": "CI_REPAIR",
            "objective": (
                f"{marker}. Dispatch exact product-gates workflow_dispatch for the current canonical Product "
                "head and do not mutate Product source. Require exact Ubuntu, Windows, and macOS validation."
            ),
            "requestedRole": "TESTER",
            "allowedPaths": list(integration.get("allowedPaths") or []),
            "baseCommit": live_head,
            "baseTree": live_tree,
            "dependencyRequirements": [],
            "requiredTests": [
                "workflow_dispatch exact product-gates on the canonical Product branch",
                "validate-ubuntu, validate-windows, and validate-macos all complete SUCCESS",
                "do not mutate Product source or tests in this read-only CI lane",
            ],
            "maxChildWorkOrders": 0,
            "status": "READY",
            "createdBy": worker_identity,
            "createdAt": utc_iso(),
        }
        if _create_continuous_work_order(
            cfg,
            spec,
            f"mission-runtime: seed continuous exact Product CI {ci_id}",
        ):
            return ci_id
    return None


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
            "maxChildWorkOrders": 0,
            "status": "READY",
            "createdBy": worker_identity,
            "createdAt": utc_iso(),
        }
        if _create_continuous_work_order(
            cfg,
            spec,
            f"mission-runtime: seed always-on Product hardening {work_id}",
        ):
            return work_id
    return None


def recover_continuous_frontier(cfg: Config, worker_identity: str, log: JsonlLog) -> dict[str, Any]:
    woken_reviews = wake_pending_reviews(cfg)
    if woken_reviews:
        log.trace("review-wake", f"woke pending R1 review Work Orders: {woken_reviews}")
        refresh_snapshots(cfg)

    validation = ensure_continuous_validation_lane(cfg, worker_identity)
    if validation:
        log.trace("continuous-ci", f"advanced continuous post-integration validation: {validation}")
        refresh_snapshots(cfg)

    integration = ensure_continuous_integration_lane(cfg, worker_identity)
    if integration:
        log.trace("continuous-integration", f"advanced continuous helper integration: {integration}")
        refresh_snapshots(cfg)

    front = dispatcher(cfg, worker_identity)
    if select_safe_candidate(cfg, front, cfg.allowed_types) is not None:
        return {
            "wokenReviews": woken_reviews,
            "continuousValidation": validation,
            "continuousIntegration": integration,
            "seededWorkOrder": None,
        }

    seeded = seed_continuous_product_work(cfg, worker_identity)
    if seeded:
        log.trace("frontier-seed", f"created bounded always-on Product hardening Work Order: {seeded}")
        refresh_snapshots(cfg)
    return {
        "wokenReviews": woken_reviews,
        "continuousValidation": validation,
        "continuousIntegration": integration,
        "seededWorkOrder": seeded,
    }

'''

PROMOTE_REPLACEMENT = r'''def promote_reviewed_source_work(cfg: Config, lease: WorkLease, target_head: str) -> None:
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
