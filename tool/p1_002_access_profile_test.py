#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


def add(results, name, passed, detail):
    results.append({"name": name, "passed": bool(passed), "detail": detail})


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--json-output")
    args = parser.parse_args()
    root = Path(args.project).resolve()
    results = []
    required = [
        "schemas/access_profile_v2.schema.json",
        "config/access_profiles.v2.json",
        "docs/architecture/ACCESS_PROFILE_V2.md",
        "docs/adr/ADR-0002-owner-mode.md",
        "lib/product/access_profile_v2.dart",
        "test/product/access_profile_v2_test.dart",
        "tool/access_profile_v2.py",
        "tool/access_profile_v2_test.py",
        "evals/fixtures/p1_002_access_profiles/invalid_cases.json",
        "tasks/completed/P1-002.md",
        "release/evidence/P1-002/manifest.json",
    ]
    missing = [path for path in required if not (root / path).is_file()]
    add(results, "Required P1-002 files", not missing, "all present" if not missing else str(missing))
    sys.path.insert(0, str(root / "tool"))
    try:
        import access_profile_v2 as AP
        catalog = AP.load_catalog(root / "config/access_profiles.v2.json")
    except Exception as error:
        catalog = {}
        add(results, "Python catalog validation", False, str(error))
    else:
        add(results, "Python catalog validation", True, "profiles=" + ",".join(sorted(catalog)))
    expected = {"chat", "project", "owner", "owner_unattended", "isolated_untrusted"}
    add(results, "Five canonical profiles", set(catalog) == expected, str(sorted(catalog)))
    if catalog:
        stable = all(
            AP.AccessProfileV2.from_json(profile.to_json()).canonical_json() == profile.canonical_json()
            for profile in catalog.values()
        )
        add(results, "Python round-trip", stable, "all canonical profiles stable")
        owner = catalog["owner"].to_json()
        unattended = catalog["owner_unattended"].to_json()
        isolated = catalog["isolated_untrusted"].to_json()
        add(results, "Owner is unrestricted non-sandbox ceiling", owner["sandboxed"] is False and owner["filesystem"]["scope"] == "current_account" and owner["network"]["scope"] == "unrestricted", str(owner["authorityClass"]))
        add(results, "Owner unattended secret boundary", unattended["sandboxed"] is False and unattended["credentials"]["rawReveal"] == "never" and unattended["process"]["elevation"] == "none", str(unattended["credentials"]))
        add(results, "Isolated profile has no host credentials", isolated["sandboxed"] is True and isolated["credentials"]["mode"] == "none" and isolated["network"]["privateAddresses"] is False, str(isolated["authorityClass"]))
    fixture = json.loads((root / "evals/fixtures/p1_002_access_profiles/invalid_cases.json").read_text(encoding="utf-8")) if (root / "evals/fixtures/p1_002_access_profiles/invalid_cases.json").is_file() else {"cases": []}
    rejected = []
    for case in fixture.get("cases", []):
        try:
            value = AP.apply_fixture_patch(catalog[case["baseProfile"]].to_json(), case["patch"])
            AP.AccessProfileV2.from_json(value)
        except Exception as error:
            if case["errorContains"] in str(error):
                rejected.append(case["name"])
    add(results, "Shared invalid vectors rejected by Python", len(rejected) == len(fixture.get("cases", [])) and bool(rejected), str(rejected))
    dart_test = (root / "test/product/access_profile_v2_test.dart").read_text(encoding="utf-8") if (root / "test/product/access_profile_v2_test.dart").is_file() else ""
    dart_model = (root / "lib/product/access_profile_v2.dart").read_text(encoding="utf-8") if (root / "lib/product/access_profile_v2.dart").is_file() else ""
    dart_ok = all(anchor in dart_test + dart_model for anchor in ("AccessProfileV2.fromJson", "invalid_cases.json", "AccessProfileValidationException", "owner_unattended", "isolated_untrusted"))
    add(results, "Dart round-trip and invalid-policy suite", dart_ok, "shared vectors and typed model wired")
    validator_source = (root / "tool/validate_release.py").read_text(encoding="utf-8")
    source_contract = (root / "test/product/source_contract_test.dart").read_text(encoding="utf-8")
    release_inventory_paths = ("lib/product/access_profile_v2.dart", "test/product/access_profile_v2_test.dart")
    library_inventory_paths = ("lib/product/access_profile_v2.dart",)
    release_inventory_ok = all(path in validator_source for path in release_inventory_paths)
    library_inventory_ok = all(path in source_contract for path in library_inventory_paths)
    test_not_in_library_inventory = "'test/product/access_profile_v2_test.dart'," not in source_contract and '"test/product/access_profile_v2_test.dart",' not in source_contract
    inventory_ok = release_inventory_ok and library_inventory_ok and test_not_in_library_inventory
    forbidden_paths_absent = not (root / "lib/src").exists() and not (root / "test/access_profile_v2_test.dart").exists()
    add(results, "Governed Dart source inventory", inventory_ok and forbidden_paths_absent, f"releaseInventory={release_inventory_ok} libraryInventory={library_inventory_ok} testExcludedFromLibraryInventory={test_not_in_library_inventory} forbiddenPathsAbsent={forbidden_paths_absent}")
    roadmap = json.loads((root / "docs/roadmap/roadmap.yaml").read_text(encoding="utf-8"))
    tasks = {item["id"]: item for item in roadmap["tasks"]}
    ready = sorted(task_id for task_id, item in tasks.items() if item.get("status") == "READY")
    state_ok = tasks.get("P1-001", {}).get("status") == "DONE" and tasks.get("P1-002", {}).get("status") == "DONE" and "P1-003" in ready and "P1-005" in ready
    add(results, "Roadmap state", state_ok, f"P1-002={tasks.get('P1-002', {}).get('status')} ready={ready}")
    ci = (root / ".github/workflows/ci.yml").read_text(encoding="utf-8")
    add(results, "CI integration", "P1-002 access profile v2" in ci, "workflow step present")
    verify = (root / "tool/verify.sh").read_text(encoding="utf-8")
    add(results, "Verification integration", "p1_002_access_profile_test.py" in verify and "access_profile_v2_test.py" in verify, "local gates present")
    validator = (root / "tool/validate_release.py").read_text(encoding="utf-8")
    add(results, "Release validation integration", "tool/p1_002_access_profile_test.py" in validator and "schemas/access_profile_v2.schema.json" in validator and "lib/product/access_profile_v2.dart" in validator and "test/product/access_profile_v2_test.dart" in validator, "required files and exact Dart inventory present")
    passed = all(item["passed"] for item in results)
    report = {
        "schemaVersion": "1.0.0",
        "taskId": "P1-002",
        "caseCount": len(results),
        "passedCount": sum(1 for item in results if item["passed"]),
        "failedCount": sum(1 for item in results if not item["passed"]),
        "passed": passed,
        "results": results,
    }
    text = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.json_output:
        output = root / args.json_output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8", newline="\n")
    print(text, end="")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
