#!/usr/bin/env python3
"""Protected-main source-landing truth gate for Mission Execution 1.5."""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any

from mission_delivery_lib import load_model, read_json, record_files, run_git
from mission_delivery_strict import ACCEPTED, validate_source_landing

PROMOTION_VALUES = {
    "SUPPORTED",
    "ESTABLISHED",
    "CERTIFIED",
    "PRODUCTION",
    "PRODUCTION_READY",
    "GA",
    "GA_READY",
    "READY",
    "PASS",
    "TRUE",
}
PROMOTION_FIELDS = {
    "capabilitySupport",
    "behavioralSupport",
    "platformSupport",
    "releaseSupport",
    "productionReadiness",
    "gaReadiness",
    "certification",
}


def _promotes_without_acceptance(record: dict[str, Any]) -> list[str]:
    if record.get("sourceLanding") != "LANDED_MAIN" or record.get("status") in ACCEPTED:
        return []
    violations: list[str] = []
    if record.get("supportPromotion") is True:
        violations.append("supportPromotion=true")
    for field in sorted(PROMOTION_FIELDS):
        value = record.get(field)
        if value is None:
            continue
        if str(value).strip().upper().replace(" ", "_") in PROMOTION_VALUES:
            violations.append(f"{field}={value}")
    return violations


def validate_main_landing(project: pathlib.Path, main_commit: str) -> dict[str, Any]:
    run_git(project, "cat-file", "-e", f"{main_commit}^{{commit}}")
    model = load_model(project)
    landed: list[dict[str, Any]] = []
    violations: list[str] = []
    for path in record_files(project, model):
        record = read_json(path)
        if record.get("sourceLanding") != "LANDED_MAIN":
            continue
        try:
            validate_source_landing(project, record, path)
            merged = record.get("mergedMainCommit")
            run_git(project, "merge-base", "--is-ancestor", merged, main_commit)
        except Exception as exc:
            violations.append(f"{path.relative_to(project)}:{exc}")
            continue
        promotions = _promotes_without_acceptance(record)
        if promotions:
            violations.append(
                f"{path.relative_to(project)}:source-only landing contains support promotion: {promotions}"
            )
        landed.append(
            {
                "task": record.get("task"),
                "status": record.get("status"),
                "sourceCommit": record.get("commit"),
                "mergedMainCommit": merged,
                "path": path.relative_to(project).as_posix(),
            }
        )
    if violations:
        raise ValueError("; ".join(violations))
    return {
        "schemaVersion": 1,
        "mainCommit": main_commit,
        "landedMainRecordCount": len(landed),
        "landedMainRecords": landed,
        "acceptedCountNotInferred": True,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--main-commit", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        result = validate_main_landing(pathlib.Path(args.project).resolve(), args.main_commit)
        text = json.dumps(result, indent=2, sort_keys=True) + "\n"
        if args.output:
            pathlib.Path(args.output).write_text(text, encoding="utf-8")
        print(text, end="")
        return 0
    except Exception as exc:
        print(f"MISSION_V15_LANDING_GATE_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
