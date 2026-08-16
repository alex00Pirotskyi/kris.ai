#!/usr/bin/env python3
"""Fail-closed Work Order supersession-chain validation for Mission Execution 1.5."""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any

WORK_ORDERS = pathlib.Path("runtime/work-orders")


def read_json(path: pathlib.Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def load_work_orders(project: pathlib.Path) -> dict[str, dict[str, Any]]:
    root = project / WORK_ORDERS
    result: dict[str, dict[str, Any]] = {}
    if not root.is_dir():
        return result
    for path in sorted(root.glob("**/*.json")):
        item = read_json(path)
        work_id = item.get("workOrderId")
        if not isinstance(work_id, str) or not work_id or work_id in result:
            raise ValueError(f"invalid/duplicate Work Order identity: {path}")
        item["_path"] = path.relative_to(project).as_posix()
        result[work_id] = item
    return result


def scope_key(item: dict[str, Any]) -> tuple[Any, Any, Any]:
    return (
        item.get("mission"),
        item.get("roadmapTask"),
        item.get("parentProductPr"),
    )


def supersedes_ids(item: dict[str, Any], work_id: str) -> list[str]:
    """Return normalized predecessor IDs, accepting legacy one-to-one records."""
    value = item.get("supersedes")
    if value is None:
        return []
    if isinstance(value, str):
        if not value:
            raise ValueError(f"Work Order {work_id} supersedes must not be empty")
        return [value]
    if isinstance(value, list):
        if not value:
            raise ValueError(f"Work Order {work_id} supersedes list must not be empty")
        result: list[str] = []
        for index, source_id in enumerate(value):
            if not isinstance(source_id, str) or not source_id:
                raise ValueError(
                    f"Work Order {work_id} supersedes[{index}] must be a non-empty string"
                )
            result.append(source_id)
        if len(set(result)) != len(result):
            raise ValueError(f"Work Order {work_id} supersedes contains duplicates")
        return result
    raise ValueError(
        f"Work Order {work_id} supersedes must be a string or an array of strings"
    )


def missing_superseded_by_ids(
    work_orders: dict[str, dict[str, Any]],
) -> list[str]:
    """Return every legacy SUPERSEDED record missing its reciprocal successor."""
    return sorted(
        work_id
        for work_id, item in work_orders.items()
        if item.get("status") == "SUPERSEDED" and not item.get("supersededBy")
    )


def validate_supersession(project: pathlib.Path) -> dict[str, Any]:
    work_orders = load_work_orders(project)
    edges: list[dict[str, str]] = []

    missing_replacements = missing_superseded_by_ids(work_orders)
    if missing_replacements:
        raise ValueError(
            "SUPERSEDED Work Orders missing supersededBy: "
            + ",".join(missing_replacements)
        )

    for work_id, item in work_orders.items():
        replacement_id = item.get("supersededBy")
        source_ids = supersedes_ids(item, work_id)

        if item.get("status") == "SUPERSEDED" and not replacement_id:
            raise ValueError(
                f"SUPERSEDED Work Order {work_id} must name supersededBy"
            )
        if replacement_id and item.get("status") != "SUPERSEDED":
            raise ValueError(
                f"Work Order {work_id} has supersededBy but status is {item.get('status')}"
            )

        if replacement_id:
            if not isinstance(replacement_id, str):
                raise ValueError(f"Work Order {work_id} supersededBy must be a string")
            replacement = work_orders.get(replacement_id)
            if replacement is None:
                raise ValueError(
                    f"Work Order {work_id} supersededBy references missing {replacement_id}"
                )
            if scope_key(replacement) != scope_key(item):
                raise ValueError(
                    f"Work Order {work_id} replacement {replacement_id} crosses mission/task/Product PR scope"
                )
            replacement_sources = supersedes_ids(replacement, replacement_id)
            if work_id not in replacement_sources:
                raise ValueError(
                    f"Work Order {work_id} replacement {replacement_id} does not reciprocally supersede it"
                )
            edges.append({"from": work_id, "to": replacement_id})

        for source_id in source_ids:
            source = work_orders.get(source_id)
            if source is None:
                raise ValueError(
                    f"Work Order {work_id} supersedes references missing {source_id}"
                )
            if scope_key(source) != scope_key(item):
                raise ValueError(
                    f"Work Order {work_id} source {source_id} crosses mission/task/Product PR scope"
                )
            if source.get("status") != "SUPERSEDED":
                raise ValueError(
                    f"Work Order {work_id} supersedes non-SUPERSEDED {source_id}"
                )
            if source.get("supersededBy") != work_id:
                raise ValueError(
                    f"Work Order {work_id} source {source_id} does not point back via supersededBy"
                )

    for start in work_orders:
        seen: set[str] = set()
        cursor = start
        while True:
            if cursor in seen:
                raise ValueError(f"Work Order supersession cycle detected from {start}")
            seen.add(cursor)
            next_id = work_orders[cursor].get("supersededBy")
            if not next_id:
                break
            cursor = next_id

    return {
        "schemaVersion": 1,
        "workOrderCount": len(work_orders),
        "supersessionEdgeCount": len(edges),
        "edges": edges,
        "pass": True,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        result = validate_supersession(pathlib.Path(args.project).resolve())
        text = json.dumps(result, indent=2, sort_keys=True) + "\n"
        if args.output:
            pathlib.Path(args.output).write_text(text, encoding="utf-8")
        print(text, end="")
        return 0
    except Exception as exc:
        print(f"MISSION_V15_SUPERSESSION_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
