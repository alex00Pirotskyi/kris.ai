#!/usr/bin/env python3
from __future__ import annotations

CI_RECOVERY_BLOCK = r'''
CONTINUOUS_HELPER_CI_REPAIR_MARKER = "CONTINUOUS_HELPER_CI_REPAIR="
CONTINUOUS_CANONICAL_CI_REPAIR_MARKER = "CONTINUOUS_CANONICAL_CI_REPAIR="
CONTINUOUS_SOURCE_WIP_LIMIT = 3

_base_recover_continuous_frontier = recover_continuous_frontier
_base_ensure_continuous_validation_lane = ensure_continuous_validation_lane


def continuous_source_work(row: dict[str, Any]) -> bool:
    return (
        CONTINUOUS_SOURCE_MARKER in str(row.get("workOrderId") or "")
        and row.get("type") in {
            "PRODUCT_FEATURE", "PRODUCT_DEFECT_REPAIR", "PRODUCT_TEST", "CI_REPAIR",
        }
    )


def _continuous_red_checks(info: dict[str, Any]) -> str:
    rows: list[str] = []
    for check in info.get("statusCheckRollup") or []:
        if not isinstance(check, dict):
            continue
        status = str(check.get("status") or "").upper()
        conclusion = str(check.get("conclusion") or "").upper()
        if conclusion not in TERMINAL_CHECK_FAILURES:
            continue
        name = str(check.get("name") or check.get("context") or check.get("workflowName") or "check")
        rows.append(f"{name}:{status or 'UNKNOWN'}:{conclusion}")
    return ", ".join(rows[:20]) or "hosted exact-head checks reported RED"


def _continuous_repair_spec(
    cfg: Config,
    source: dict[str, Any],
    worker_identity: str,
    *,
    marker: str,
    objective: str,
    priority: int = 110,
) -> tuple[str, dict[str, Any]] | None:
    parent_pr = source.get("parentProductPr")
    if not isinstance(parent_pr, int) or isinstance(parent_pr, bool) or parent_pr <= 0:
        return None
    product = product_pr_record(cfg, parent_pr)
    branch = str(product.get("branch") or "")
    live_head = str(product.get("observedHead") or "")
    if not branch or not live_head:
        return None
    actual_head = git(cfg.anchor, "rev-parse", f"origin/{branch}").stdout.strip()
    if actual_head != live_head:
        return None
    live_tree = exact_tree(cfg.anchor, live_head)
    allowed = [str(path) for path in source.get("allowedPaths") or []]
    if not allowed:
        return None
    work_id = (
        f"WO-{slug(str(source['roadmapTask']), 18).upper()}-CONTINUOUS-QWEN-CI-REPAIR-"
        f"{short_id(8).upper()}"
    )
    spec = {
        "schemaVersion": 1,
        "workOrderId": work_id,
        "mission": source["mission"],
        "roadmapTask": source["roadmapTask"],
        "parentProductPr": parent_pr,
        "priority": priority,
        "type": "CI_REPAIR",
        "objective": f"{marker}. {objective}",
        "requestedRole": "CI_REPAIR",
        "allowedPaths": allowed,
        "baseCommit": live_head,
        "baseTree": live_tree,
        "dependencyRequirements": [],
        "requiredTests": [
            "inspect the exact failed helper/canonical CI evidence named in the objective before editing",
            "run at least one focused local test/check/analyzer command and require exit 0",
            "final changed paths remain inside exact Work Order allowedPaths",
            "do not produce documentation-only, formatting-only, governance-only, or no-op repair",
        ],
        "maxChildWorkOrders": 0,
        "status": "READY",
        "createdBy": worker_identity,
        "createdAt": utc_iso(),
    }
    return work_id, spec


def _existing_marker_work(rows: list[dict[str, Any]], marker: str) -> dict[str, Any] | None:
    candidates = [
        row for row in rows
        if marker in str(row.get("objective") or "")
        and row.get("status") not in {"SUPERSEDED", "CANCELLED"}
    ]
    if not candidates:
        return None
    candidates.sort(key=lambda row: str(row.get("updatedAt") or row.get("createdAt") or ""), reverse=True)
    return candidates[0]


def recover_continuous_red_helper_ci(
    cfg: Config,
    worker_identity: str,
    log: JsonlLog,
) -> str | None:
    rows = runtime_work_rows(cfg)
    validating = sorted(
        (
            row for row in rows
            if row.get("status") == "VALIDATING" and continuous_source_work(row)
        ),
        key=lambda row: (-int(row.get("priority", 0)), str(row.get("workOrderId"))),
    )
    for source in validating:
        info = helper_pr_for_work(cfg, source)
        if not info or info.get("state") != "OPEN" or pr_check_state(info) != "RED":
            continue
        helper_head = str(info.get("headRefOid") or "")
        helper_branch = str(info.get("headRefName") or "")
        helper_pr = info.get("number")
        if not re.fullmatch(r"[0-9a-f]{40}", helper_head) or not isinstance(helper_pr, int):
            continue
        marker = (
            f"{CONTINUOUS_HELPER_CI_REPAIR_MARKER}{source['workOrderId']}:{helper_head}"
        )
        existing = _existing_marker_work(rows, marker)
        repair_id = str(existing.get("workOrderId")) if existing else ""
        if not repair_id:
            failures = _continuous_red_checks(info)
            built = _continuous_repair_spec(
                cfg,
                source,
                worker_identity,
                marker=marker,
                objective=(
                    f"Helper PR #{helper_pr} exact head {helper_head} failed hosted exact-head CI: "
                    f"{failures}. The failed helper is immutable evidence only and must not be integrated. "
                    "Compare the canonical Product base to that exact helper head, recover the intended bounded "
                    "source/test change, reproduce the relevant failure or invariant locally, and re-implement the "
                    "smallest corrected repair on the current canonical Product head."
                ),
            )
            if built is None:
                continue
            repair_id, spec = built
            if not _create_continuous_work_order(
                cfg,
                spec,
                f"mission-runtime: repair red continuous helper CI {repair_id}",
            ):
                continue
            rows = runtime_work_rows(cfg)

        current = next(
            (row for row in runtime_work_rows(cfg) if row.get("workOrderId") == source.get("workOrderId")),
            None,
        )
        if isinstance(current, dict) and current.get("status") == "VALIDATING":
            transition_work_order_cas(
                cfg,
                str(source["workOrderId"]),
                "BLOCKED",
                f"ELASTIC-QWEN-V53:CONTINUOUS_HELPER_CI_RED:{helper_head}",
                make_work_execution_id(),
            )
            refresh_snapshots(cfg)

        close = run(
            [
                "gh", "pr", "close", str(helper_pr), "--repo", cfg.repo_full_name,
                "--comment",
                f"Superseded after exact-head CI failure by continuous repair Work Order `{repair_id}`. "
                f"Immutable failed helper head remains `{helper_head}`.",
            ],
            check=False,
            timeout=120,
        )
        deleted = False
        if close.returncode == 0:
            deleted = safe_delete_consumed_helper_branch(
                cfg, helper_branch, helper_head, log
            )
        log.write(
            "continuous_helper_ci_red_repair",
            sourceWorkOrder=source.get("workOrderId"),
            helperPr=helper_pr,
            helperHead=helper_head,
            repairWorkOrder=repair_id,
            helperBranchDeleted=deleted,
        )
        log.trace(
            "continuous-ci-repair",
            f"red helper PR #{helper_pr} head={helper_head} -> repair Work Order {repair_id}",
        )
        return repair_id
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
        ci_marker = CONTINUOUS_CI_MARKER + integration_id
        ci_rows = [
            row for row in rows
            if row.get("parentProductPr") == integration.get("parentProductPr")
            and row.get("type") == "CI_REPAIR"
            and ci_marker in str(row.get("objective") or "")
        ]
        blocked = sorted(
            (row for row in ci_rows if row.get("status") == "BLOCKED"),
            key=lambda row: str(row.get("updatedAt") or ""),
            reverse=True,
        )
        if not blocked:
            continue
        failed_ci = blocked[0]
        repair_marker = (
            f"{CONTINUOUS_CANONICAL_CI_REPAIR_MARKER}{failed_ci['workOrderId']}"
        )
        existing = _existing_marker_work(rows, repair_marker)
        repair_id = str(existing.get("workOrderId")) if existing else ""
        if not repair_id:
            built = _continuous_repair_spec(
                cfg,
                integration,
                worker_identity,
                marker=repair_marker,
                objective=(
                    f"Exact canonical Product CI Work Order {failed_ci['workOrderId']} returned BLOCKED "
                    f"for canonical head {failed_ci.get('baseCommit')}. Diagnose the current canonical "
                    "Product source/tests inside allowedPaths, reproduce the failing platform/test invariant "
                    "with the strongest available local check, and implement the smallest Product/test repair. "
                    "Do not reinterpret the blocked CI receipt as acceptance or integrate unrelated changes."
                ),
                priority=115,
            )
            if built is None:
                return None
            repair_id, spec = built
            if not _create_continuous_work_order(
                cfg,
                spec,
                f"mission-runtime: repair red continuous Product CI {repair_id}",
            ):
                return None

        current = next(
            (row for row in runtime_work_rows(cfg) if row.get("workOrderId") == integration_id),
            None,
        )
        if isinstance(current, dict) and current.get("status") == "VALIDATING":
            transition_work_order_cas(
                cfg,
                integration_id,
                "BLOCKED",
                f"ELASTIC-QWEN-V53:CONTINUOUS_EXACT_CI_BLOCKED:{failed_ci['workOrderId']}",
                make_work_execution_id(),
            )
            refresh_snapshots(cfg)
        return repair_id

    return _base_ensure_continuous_validation_lane(cfg, worker_identity)


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
        product_rows = [row for row in all_work if row.get("parentProductPr") == parent_pr]
        active_build = sum(
            1 for row in product_rows
            if row.get("type") in BUILD_TYPES and row.get("status") in ACTIVE_WORK
        )
        helper_ready = sum(1 for row in product_rows if row.get("status") == "HELPER_READY")
        continuous_pending = sum(
            1 for row in product_rows
            if continuous_source_work(row) and row.get("status") in CONTINUOUS_ACTIVE_WORK_STATES
        )
        if (
            active_build >= ACTIVE_BUILD_LIMIT
            or helper_ready >= HELPER_READY_LIMIT
            or continuous_pending >= CONTINUOUS_SOURCE_WIP_LIMIT
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
    ci_repair = recover_continuous_red_helper_ci(cfg, worker_identity, log)
    if ci_repair:
        refresh_snapshots(cfg)
    result = _base_recover_continuous_frontier(cfg, worker_identity, log)
    result["continuousCiRepair"] = ci_repair
    return result

'''
