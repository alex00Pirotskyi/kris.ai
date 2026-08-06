#!/usr/bin/env python3
"""Read-only Worker E Test Center owner-handoff validator."""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
from pathlib import Path
from typing import Any

REGISTRY = Path("config/test_center_registry.v1.json")
SPEC = Path("release/evidence/P11-001/test-center-registration-spec.json")
HANDOFF = Path("release/evidence/P11-001/test-center-owner-handoff.json")
PREFIX = "tc.p11.readiness."
MODULE_ID = "tm.p11-readiness"

class RegistrationError(ValueError):
    pass

def canonical_bytes(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()

def _load(project: Path, relative: Path) -> dict[str, Any]:
    value = json.loads((project / relative).read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RegistrationError(f"{relative} must contain an object")
    return value

def _records(spec: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
    stable_ids = spec["stableTestIds"]
    cases: list[dict[str, Any]] = []
    profiles: list[dict[str, Any]] = []
    for test_id in stable_ids:
        suffix = test_id.rsplit(".", 1)[-1]
        cases.append({
            "testId": test_id,
            "moduleId": MODULE_ID,
            "displayName": f"P11 readiness {suffix}",
            "purpose": f"Validate the {suffix} source contract without support promotion.",
            "roadmapTaskIds": ["P11-001"],
            "assuranceClass": "source_contract",
            "mandatory": True,
        })
        profiles.append({
            "stableCheckId": test_id,
            "argv": ["python", "tool/worker_e_native_parity_readiness.py", "--check", "--project", ".", "--test-id", test_id],
            "workingDirectory": ".",
            "platforms": ["linux", "macos", "windows"],
            "timeoutSeconds": 120,
            "environmentAllowlist": ["CI", "GITHUB_ACTIONS", "RUNNER_ARCH", "RUNNER_OS"],
            "inputPaths": ["release/evidence/P11-001", "tool/worker_e_native_parity_readiness.py"],
            "expectedOutputs": [],
            "mutationPolicy": "NON_MUTATING",
            "assuranceClass": "source_contract",
            "evidenceDestination": f"release/evidence/generated/worker-e/{test_id}.json",
            "affectedPaths": ["release/evidence/P11-001", "tool/worker_e_native_parity_readiness.py"],
        })
    mappings: list[dict[str, Any]] = []
    for item in spec["mappingGroups"]:
        row = copy.deepcopy(item)
        if row["testIds"] == "ALL":
            row["testIds"] = stable_ids
        mappings.append(row)
    return cases, profiles, mappings

def build_registry(current: dict[str, Any], spec: dict[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(current)
    cases, profiles, mappings = _records(spec)
    result["testModules"] = [row for row in result.get("testModules", []) if row.get("moduleId") != MODULE_ID]
    result["testCases"] = [row for row in result.get("testCases", []) if not str(row.get("testId", "")).startswith(PREFIX)]
    result["projectTestProfiles"] = [row for row in result.get("projectTestProfiles", []) if not str(row.get("stableCheckId", "")).startswith(PREFIX)]
    result["affectedTestMappings"] = [row for row in result.get("affectedTestMappings", []) if not str(row.get("mappingId", "")).startswith("affected.p11-readiness")]
    result["testModules"].append(spec["module"])
    result["testCases"].extend(cases)
    result["projectTestProfiles"].extend(profiles)
    result["affectedTestMappings"].extend(mappings)
    return result

def validate_handoff(project: Path) -> dict[str, Any]:
    current = _load(project, REGISTRY)
    spec = _load(project, SPEC)
    handoff = _load(project, HANDOFF)
    if handoff.get("status") != "OWNER_HANDOFF_PENDING":
        raise RegistrationError("Test Center handoff is not pending owner publication")
    if handoff.get("workerERegistryMutationAllowed") is not False:
        raise RegistrationError("Worker E registry mutation must remain forbidden")
    stable_ids = spec.get("stableTestIds")
    if not isinstance(stable_ids, list) or len(stable_ids) != 10 or len(stable_ids) != len(set(stable_ids)):
        raise RegistrationError("Test Center stable ID specification is incomplete")
    expected = build_registry(current, spec)
    live = {
        "modules": [row for row in current.get("testModules", []) if row.get("moduleId") == MODULE_ID],
        "cases": [row for row in current.get("testCases", []) if str(row.get("testId", "")).startswith(PREFIX)],
        "profiles": [row for row in current.get("projectTestProfiles", []) if str(row.get("stableCheckId", "")).startswith(PREFIX)],
        "mappings": [row for row in current.get("affectedTestMappings", []) if str(row.get("mappingId", "")).startswith("affected.p11-readiness")],
    }
    count = sum(len(rows) for rows in live.values())
    if count == 0:
        state = "OWNER_HANDOFF_PENDING"
    elif current == expected:
        state = "OWNER_PUBLICATION_PRESENT"
    else:
        raise RegistrationError("partial or stale Worker E Test Center publication")
    preview = canonical_bytes(expected)
    return {
        "schemaVersion": 1,
        "resultState": "PASS",
        "state": state,
        "registryMutated": False,
        "moduleId": MODULE_ID,
        "stableTestIds": stable_ids,
        "previewSha256": hashlib.sha256(preview).hexdigest(),
        "previewBytes": len(preview),
    }

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=".")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        print(json.dumps(validate_handoff(Path(args.project).resolve()), sort_keys=True))
        return 0
    except (OSError, json.JSONDecodeError, KeyError, RegistrationError) as exc:
        print(json.dumps({"resultState": "FAIL", "error": str(exc)}, sort_keys=True))
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
