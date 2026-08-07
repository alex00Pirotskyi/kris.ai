#!/usr/bin/env python3
"""Generate mission views from durable live claim/state memory after first bootstrap.

`config/mission_execution.v1.json.activeClaims` is an initial bootstrap seed. Once
all mission state records are materialized, claim files are the ownership locks
and state files are durable execution memory. This adapter reuses the canonical
mission graph/parser but prevents later materialization from rewriting those live
records from stale discovery seeds.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Mapping

import mission_control as mc

NO_ACTIVE_CLAIM_STATES = {
    "AVAILABLE",
    "YIELDED",
    "COMPLETE",
    "COMPLETED",
    "ACCEPTED",
    "MERGED_MAIN",
    "SUPERSEDED",
}
MUTABLE_MEMORY_PREFIXES = ("claims/", "state/", "checkpoints/")


class LiveMaterializerError(ValueError):
    pass


def _load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise LiveMaterializerError(f"cannot read durable mission memory: {path}") from exc
    if not isinstance(value, dict):
        raise LiveMaterializerError(f"durable mission memory must be an object: {path}")
    return value


def _validate_claim_state_identity(
    mission_id: str,
    claim: Mapping[str, Any],
    state: Mapping[str, Any],
) -> None:
    if claim.get("mission") != mission_id or state.get("mission") != mission_id:
        raise LiveMaterializerError(f"mission identity drift for {mission_id}")
    required_claim = {
        "worker",
        "branch",
        "pr",
        "head",
        "status",
        "current",
        "exclusivePaths",
    }
    missing = sorted(required_claim - set(claim))
    if missing:
        raise LiveMaterializerError(
            f"durable claim {mission_id} is missing required fields: {missing}"
        )
    identity_pairs = (
        ("worker", "assignedWorker"),
        ("branch", "branch"),
        ("pr", "pullRequest"),
        ("head", "observedHead"),
        ("tree", "observedTree"),
    )
    for claim_field, state_field in identity_pairs:
        state_value = state.get(state_field)
        if state_value is not None and state_value != claim.get(claim_field):
            raise LiveMaterializerError(
                f"durable claim/state identity mismatch for {mission_id}: "
                f"{claim_field} != {state_field}"
            )


def load_live_claims(
    project: Path,
    missions: list[Mapping[str, Any]],
    seed_claims: list[Mapping[str, Any]],
) -> tuple[list[dict[str, Any]], bool]:
    state_dir = project / mc.OUTPUT_PATH / "state"
    claim_dir = project / mc.OUTPUT_PATH / "claims"
    if not state_dir.is_dir():
        return [dict(item) for item in seed_claims], False

    missing_states = [
        mission["id"]
        for mission in missions
        if not (state_dir / f"{mission['id']}.json").is_file()
    ]
    if missing_states:
        raise LiveMaterializerError(
            "materialized mission memory is incomplete; missing states: "
            + ", ".join(missing_states)
        )

    claims: list[dict[str, Any]] = []
    for mission in missions:
        mission_id = str(mission["id"])
        state = _load(state_dir / f"{mission_id}.json")
        if state.get("mission") != mission_id:
            raise LiveMaterializerError(f"state mission identity drift for {mission_id}")
        claim_path = claim_dir / f"{mission_id}.claim.json"
        if not claim_path.is_file():
            status = str(state.get("status", ""))
            if status not in NO_ACTIVE_CLAIM_STATES:
                raise LiveMaterializerError(
                    f"active-looking mission state has no ownership claim: "
                    f"{mission_id} status={status!r}"
                )
            continue
        claim = _load(claim_path)
        _validate_claim_state_identity(mission_id, claim, state)
        claims.append(claim)
    return claims, True


def _validate_collisions(claims: list[Mapping[str, Any]]) -> None:
    seen: set[str] = set()
    for claim in claims:
        mission = str(claim.get("mission", ""))
        if mission in seen:
            raise LiveMaterializerError(f"multiple durable active claims for {mission}")
        seen.add(mission)
    for index, left in enumerate(claims):
        for right in claims[index + 1 :]:
            for left_path in left.get("exclusivePaths", []):
                for right_path in right.get("exclusivePaths", []):
                    if mc.has_path_collision(str(left_path), str(right_path)):
                        raise LiveMaterializerError(
                            "durable exclusive path collision: "
                            f"{left['mission']} {left_path} vs "
                            f"{right['mission']} {right_path}"
                        )


def desired_live_views(project: Path) -> tuple[dict[str, str], bool, int]:
    model = mc.build_model(project)
    live_claims, materialized = load_live_claims(
        project,
        model["missions"],
        model["claims"],
    )
    if materialized:
        _validate_collisions(live_claims)
        model["claims"] = live_claims
        model["claimByMission"] = {
            str(claim["mission"]): claim for claim in live_claims
        }
    desired = mc.generated_files(model)
    if materialized:
        desired = {
            path: content
            for path, content in desired.items()
            if not path.startswith(MUTABLE_MEMORY_PREFIXES)
        }
    return desired, materialized, len(live_claims)


def materialize(project: Path, *, check: bool) -> dict[str, Any]:
    desired, materialized, claim_count = desired_live_views(project)
    output = project / mc.OUTPUT_PATH
    mismatches: list[str] = []
    for relative, content in desired.items():
        path = output / relative
        if check:
            if not path.is_file() or path.read_text(encoding="utf-8") != content:
                mismatches.append(path.relative_to(project).as_posix())
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
    if check and mismatches:
        raise LiveMaterializerError(
            "generated live mission views differ: " + ", ".join(mismatches)
        )
    return {
        "schemaVersion": 1,
        "status": "PASS",
        "mode": "MATERIALIZED_LIVE_MEMORY" if materialized else "INITIAL_BOOTSTRAP_SEED",
        "activeClaimCount": claim_count,
        "generatedViewCount": len(desired),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=".")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    args = parser.parse_args()
    project = Path(args.project).resolve()
    try:
        result = materialize(project, check=args.check)
    except (LiveMaterializerError, ValueError) as exc:
        print(json.dumps({"status": "FAIL", "error": str(exc)}, sort_keys=True))
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
