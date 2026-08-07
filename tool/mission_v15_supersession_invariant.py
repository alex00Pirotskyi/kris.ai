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


def validate_supersession(project: pathlib.Path) -> dict[str, Any]:
    work_orders = load_work_orders(project)
    edges: list[dict[str, str]] = []

    for work_id, item in work_orders.items():
        replacement_id = item.get("supersededBy")
        source_id = item.get("supersedes")

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
            if replacement.get("supersedes") != work_id:
                raise ValueError(
                    f"Work Order {work_id} replacement {replacement_id} does not reciprocally supersede it"
                )
            edges.append({"from": work_id, "to": replacement_id})

        if source_id:
            if not isinstance(source_id, str):
                raise ValueError(f"Work Order {work_id} supersedes must be a string")
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
