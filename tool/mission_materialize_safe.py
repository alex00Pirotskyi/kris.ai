#!/usr/bin/env python3
"""Materialize mission views without overwriting durable runtime state.

`config/mission_execution.v1.json` is a bootstrap/topology source. Once durable
claim files exist, they are the runtime ownership source and MUST NOT be
regenerated from bootstrap anchors. This wrapper keeps the existing deterministic
mission generator while removing its authority to rewrite mutable claims, states,
or checkpoints.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Any

import mission_control as core

RUNTIME_PREFIXES = ("claims/", "state/", "checkpoints/")


def read_json(path: pathlib.Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def is_runtime_path(relative: str) -> bool:
    return relative.startswith(RUNTIME_PREFIXES)


def load_durable_claims(project: pathlib.Path, model: dict[str, Any]) -> list[dict[str, Any]]:
    claim_dir = project / core.OUTPUT_PATH / "claims"
    if not claim_dir.is_dir():
        return list(model["claims"])

    paths = sorted(claim_dir.glob("MISSION-*.claim.json"))
    # Presence of the durable claim directory is authoritative. An empty
    # directory means no active claims; static bootstrap anchors must not
    # resurrect yielded/completed ownership.
    claims: list[dict[str, Any]] = []
    mission_ids = {mission["id"] for mission in model["missions"]}
    seen: set[str] = set()
    for path in paths:
        claim = read_json(path)
        mission = claim.get("mission")
        if mission not in mission_ids:
            raise ValueError(f"durable claim references unknown mission: {path}: {mission}")
        if mission in seen:
            raise ValueError(f"duplicate durable claim for {mission}")
        if not claim.get("worker") or not claim.get("branch"):
            raise ValueError(f"durable claim missing worker/branch: {path}")
        seen.add(mission)
        claims.append(claim)

    for index, left in enumerate(claims):
        for right in claims[index + 1 :]:
            for left_path in left.get("exclusivePaths", []):
                for right_path in right.get("exclusivePaths", []):
                    if core.has_path_collision(left_path, right_path):
                        raise ValueError(
                            "durable exclusive path collision: "
                            f"{left['mission']} {left_path} vs {right['mission']} {right_path}"
                        )
    return claims


def runtime_model(project: pathlib.Path) -> dict[str, Any]:
    model = core.build_model(project)
    claims = load_durable_claims(project, model)
    model["claims"] = claims
    model["claimByMission"] = {claim["mission"]: claim for claim in claims}
    return model


def desired_static_views(project: pathlib.Path) -> dict[str, str]:
    desired = core.generated_files(runtime_model(project))
    return {path: content for path, content in desired.items() if not is_runtime_path(path)}


def materialize(project: pathlib.Path, check: bool) -> None:
    output = project / core.OUTPUT_PATH
    desired = desired_static_views(project)
    mismatches: list[str] = []
    for relative, content in desired.items():
        path = output / relative
        if check:
            if not path.is_file() or path.read_text(encoding="utf-8") != content:
                mismatches.append(path.relative_to(project).as_posix())
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
    if mismatches:
        raise ValueError("safe generated mission views differ: " + ", ".join(mismatches))
    print(
        "MISSION_SAFE_MATERIALIZER "
        f"check={str(check).lower()} static_views={len(desired)} "
        f"durable_claims={len(runtime_model(project)['claims'])}"
    )


def validate(project: pathlib.Path) -> None:
    model = runtime_model(project)
    # build_model already validates the 25 packets, 359 tasks, task DAG,
    # mission DAG and bootstrap configuration. The runtime overlay adds durable
    # claim uniqueness/collision validation above.
    print(
        "MISSION_SAFE_RUNTIME_VALID "
        f"phases={len(model['phases'])} tasks={len(model['tasks'])} "
        f"missions={len(model['missions'])} interlocks={len(model['interlocks'])} "
        f"durable_claims={len(model['claims'])}"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    sub = parser.add_subparsers(dest="command", required=True)
    materialize_parser = sub.add_parser("materialize")
    materialize_parser.add_argument("--check", action="store_true")
    sub.add_parser("validate")
    args = parser.parse_args()
    project = pathlib.Path(args.project).resolve()
    try:
        if args.command == "materialize":
            materialize(project, check=args.check)
        else:
            validate(project)
        return 0
    except Exception as exc:
        print(f"MISSION_SAFE_MATERIALIZER_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
