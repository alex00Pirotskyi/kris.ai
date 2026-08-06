#!/usr/bin/env python3
"""Read-only regression checks for the bounded Worker F P5-001 prototype."""
from __future__ import annotations

import json
from pathlib import Path

TEST_PREFIX = "tc.p5-001."
REQUIRED_TEST_IDS = {
    "tc.p5-001.navigation.primary-workspaces",
    "tc.p5-001.flow.simple-task",
    "tc.p5-001.flow.existing-run",
    "tc.p5-001.flow.owner-mode",
    "tc.p5-001.flow.verification-center",
    "tc.p5-001.state.transitions",
    "tc.p5-001.mode.progressive-disclosure",
    "tc.p5-001.capability.honest-unavailable",
    "tc.p5-001.keyboard.primary-flow",
    "tc.p5-001.semantics.primary-flow",
}


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    required = [
        root / "lib/p5_ia_preview.dart",
        root / "lib/product/p5_information_architecture/p5_models.dart",
        root / "lib/product/p5_information_architecture/p5_controller.dart",
        root / "lib/product/p5_information_architecture/p5_fixtures.dart",
        root / "lib/product/p5_information_architecture/p5_prototype.dart",
        root / "test/product/p5_information_architecture/p5_state_controller_test.dart",
        root / "test/product/p5_information_architecture/p5_source_boundary_test.dart",
        root / "test/product/p5_information_architecture/p5_verification_center_test.dart",
        root / "test/product/p5_information_architecture/p5_accessibility_test.dart",
        root / "release/evidence/P5-001/current-ux-inventory.json",
        root / "release/evidence/P5-001/claim-boundary.json",
    ]
    missing = [path.relative_to(root).as_posix() for path in required if not path.is_file()]
    if missing:
        raise AssertionError(f"missing P5-001 paths: {missing}")

    registry = json.loads((root / "config/test_center_registry.v1.json").read_text(encoding="utf-8"))
    cases = {
        item["testId"]
        for item in registry.get("testCases", [])
        if str(item.get("testId", "")).startswith(TEST_PREFIX)
    }
    profiles = {
        item["stableCheckId"]
        for item in registry.get("projectTestProfiles", [])
        if str(item.get("stableCheckId", "")).startswith(TEST_PREFIX)
    }
    if cases != REQUIRED_TEST_IDS or profiles != REQUIRED_TEST_IDS:
        raise AssertionError(f"P5 case/profile mismatch cases={sorted(cases)} profiles={sorted(profiles)}")

    hierarchy = json.loads((root / "config/test_center_assurance_hierarchy.v1.json").read_text(encoding="utf-8"))
    bindings = {
        item["testId"]: item["levelId"]
        for item in hierarchy.get("testBindings", [])
        if str(item.get("testId", "")).startswith(TEST_PREFIX)
    }
    if set(bindings) != REQUIRED_TEST_IDS or set(bindings.values()) != {"unit"}:
        raise AssertionError(f"P5 hierarchy bindings are incomplete or inflated: {bindings}")

    production = (root / "lib/main.dart").read_text(encoding="utf-8")
    if "P5InformationArchitectureApp" in production or "p5_ia_preview.dart" in production:
        raise AssertionError("P5 preview leaked into the production entry point")

    forbidden = (
        "import 'dart:io'",
        "import 'dart:ffi'",
        "package:http/",
        "ProductRuntime",
        "P2OwnerWorkspace",
        "Process.",
        "MethodChannel",
    )
    for path in sorted((root / "lib/product/p5_information_architecture").glob("*.dart")):
        text = path.read_text(encoding="utf-8")
        for token in forbidden:
            if token in text:
                raise AssertionError(f"forbidden side-effect token {token!r} in {path.relative_to(root)}")

    print(json.dumps({
        "status": "PASS",
        "moduleId": "tm.p5-information-architecture",
        "testIdCount": len(REQUIRED_TEST_IDS),
        "capabilitySupport": "SOURCE_FOUNDATION",
        "certification": "NOT_EVALUATED",
        "productionEntryPointChanged": False,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
