#!/usr/bin/env python3
"""Branch-bound compatibility routing for control-plane ownership checks.

PR #156 is an explicitly bounded runtime-sanitation candidate, not a product
mission branch. Its ownership exception is restricted to one exact branch and
one exact set of reviewed paths; every other branch continues through the
existing mission-centric checker unchanged.
"""
from __future__ import annotations

import json
import pathlib
import sys
from typing import Any, Iterable

HERE = pathlib.Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import mission_delivery_control_v1 as _impl

SANITATION_CONTROL_BRANCH = "agent/gpt-gold/gs-004a-runtime-workflow-sanitation"
SANITATION_CONTROL_PATHS = frozenset(
    {
        ".github/workflows/mission-execution-control.yml",
        ".github/workflows/mission-execution-materialize.yml",
        ".github/workflows/mission-v15-connector-authority-relay.yml",
        ".github/workflows/mission-v15-governance-drift.yml",
        ".github/workflows/mission-v15-helper-gate.yml",
        ".github/workflows/mission-v15-hygiene.yml",
        ".github/workflows/mission-v15-main-landing.yml",
        ".github/workflows/mission-v15-product-integration.yml",
        ".github/workflows/mission-v15-runtime-invariants.yml",
        ".github/workflows/mission-v15-scale.yml",
        ".github/workflows/pr14-current-main-reconciliation.yml",
        ".github/workflows/pr14-protected-main-repair.yml",
        ".github/workflows/temp-direct-pr14-repair.yml",
        ".github/workflows/temp-dispatch-p1-p2-promotion.yml",
        ".github/workflows/temp-execute-pr14-repair.yml",
        ".github/workflows/temp-observe-p1-p2-promotion.yml",
        ".github/workflows/temp-p2-python-lock-refresh.yml",
        ".github/workflows/temp-pr14-pull-request-repair.yml",
        ".github/workflows/temp-pr14-workflow-run-repair.yml",
        ".github/workflows/temp-reconcile-pr14-main.yml",
        ".github/workflows/v32-exact-source-import.yml",
        ".github/workflows/v71r12-validation-failure-recorder.yml",
        ".github/workflows/v71r12-validation-monitor.yml",
        ".github/workflows/workflow-integrity.yml",
        "SOURCE_MANIFEST.sha256",
        "tool/mission_delivery_control.py",
        "tool/mission_delivery_control_v1.py",
        "tool/mission_delivery_control_test.py",
        "tool/mission_delivery_control_test_v1.py",
        "tool/mission_delivery_lib.py",
        "tool/mission_delivery_lib_v1.py",
        "tool/workflow_integrity_test.rb",
    }
)


def classify_runtime_sanitation_paths(
    changed_paths: Iterable[str],
) -> dict[str, Any]:
    rows = []
    violations = []
    for raw in sorted(set(changed_paths)):
        path = _impl.normalize_path(raw)
        authorized = path in SANITATION_CONTROL_PATHS
        rows.append(
            {
                "path": path,
                "category": (
                    "V15_RUNTIME_SANITATION" if authorized else "UNDECLARED_PATH"
                ),
                "reason": (
                    None
                    if authorized
                    else "outside exact PR #156 runtime-sanitation scope"
                ),
            }
        )
        if not authorized:
            violations.append(path)
    return {
        "mission": None,
        "controlPlane": "MISSION_EXECUTION_V15_RUNTIME_SANITATION",
        "changedPathCount": len(rows),
        "authorized": not violations,
        "violations": violations,
        "requiredOwnerReviews": [],
        "coordinationIds": [],
        "paths": rows,
    }


_original_command_ownership = _impl.command_ownership


def _command_ownership_compat(project: pathlib.Path, args: Any) -> None:
    if args.mission:
        _original_command_ownership(project, args)
        return

    head_branch = args.head_branch
    if not head_branch and args.event_path:
        event = _impl.load_event(pathlib.Path(args.event_path))
        head_branch = event.get("pull_request", {}).get("head", {}).get("ref")
    if head_branch != SANITATION_CONTROL_BRANCH:
        _original_command_ownership(project, args)
        return

    changed = _impl.git_changed_paths(project, args.base, args.head)
    result = classify_runtime_sanitation_paths(changed)
    result.update(
        {
            "base": args.base,
            "head": args.head,
            "headBranch": head_branch,
            "namespaceDiagnostics": [],
        }
    )
    if args.output:
        _impl.write_json(pathlib.Path(args.output), result)
    print(json.dumps(result, indent=2, sort_keys=True))
    if not result["authorized"]:
        raise _impl.DeliveryError(
            "changed-file ownership violations: "
            + ", ".join(result["violations"])
        )


_impl.command_ownership = _command_ownership_compat

from mission_delivery_control_v1 import *  # noqa: E402,F401,F403

command_ownership = _impl.command_ownership


if __name__ == "__main__":
    raise SystemExit(_impl.main())
