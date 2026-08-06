#!/usr/bin/env python3
"""Read-only validation for the bounded Worker F P5-001 prototype."""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
from pathlib import Path, PurePosixPath
from typing import Any, Iterable, Mapping, Sequence

MODULE_ID = "tm.p5-information-architecture"
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
PLACEHOLDERS = (
    "PENDING_SHA",
    "STAGE_1_COMMIT_PENDING",
    "TBD_SHA",
    "UNKNOWN_TREE",
)
FORBIDDEN_SOURCE_TOKENS = (
    "import 'dart:io'",
    "import 'dart:ffi'",
    "import 'dart:html'",
    "package:http/",
    "ProductRuntime",
    "P2OwnerWorkspace",
    "Process.",
    "MethodChannel",
    "Socket(",
    "File(",
    "Directory(",
)


class WorkerFError(ValueError):
    pass


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def canonical_json(value: Any) -> str:
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def normalize_path(value: str) -> str:
    normalized = value.replace("\\", "/").lstrip("./")
    path = PurePosixPath(normalized)
    if not normalized or path.is_absolute() or ".." in path.parts:
        raise WorkerFError(f"changed path must be repository-relative: {value!r}")
    return path.as_posix()


def select_affected_tests(
    changed_paths: Iterable[str],
    mappings: Iterable[Mapping[str, Any]],
) -> list[str]:
    normalized_paths = sorted({normalize_path(path) for path in changed_paths})
    selected: set[str] = set()
    for mapping in sorted(
        mappings,
        key=lambda item: (int(item.get("priority", 1000)), str(item["mappingId"])),
    ):
        includes = sorted(set(mapping.get("pathPatterns", [])))
        excludes = sorted(set(mapping.get("excludedPaths", [])))
        for changed in normalized_paths:
            if any(fnmatch.fnmatchcase(changed, pattern) for pattern in excludes):
                continue
            if any(fnmatch.fnmatchcase(changed, pattern) for pattern in includes):
                selected.update(str(test_id) for test_id in mapping.get("testIds", []))
                break
    return sorted(selected)


def worker_f_files(project: Path) -> list[Path]:
    explicit = [
        project / ".github/workflows/worker-f-p5-001-information-architecture.yml",
        project / "config/test_center_registry.v1.json",
        project / "config/test_center_assurance_hierarchy.v1.json",
        project / "docs/ux/P5-001_INFORMATION_ARCHITECTURE.md",
        project / "lib/p5_ia_preview.dart",
        project / "test/product/p5_information_architecture/worker_f_p5_ia.py",
        project / "test/product/p5_information_architecture/worker_f_p5_ia_test.py",
    ]
    files = [path for path in explicit if path.is_file()]
    for base in (
        project / "lib/product/p5_information_architecture",
        project / "test/product/p5_information_architecture",
        project / "release/evidence/P5-001",
    ):
        if base.is_dir():
            files.extend(
                path
                for path in base.rglob("*")
                if path.is_file() and path.name != "manifest.json"
            )
    return sorted(set(files), key=lambda path: path.relative_to(project).as_posix())


def manifest_payload(project: Path) -> dict[str, Any]:
    artifacts = []
    for path in worker_f_files(project):
        raw = path.read_bytes()
        artifacts.append(
            {
                "path": path.relative_to(project).as_posix(),
                "sha256": hashlib.sha256(raw).hexdigest(),
                "sizeBytes": len(raw),
            }
        )
    return {
        "schemaVersion": "1.0.0",
        "taskId": "P5-001",
        "classification": "SOURCE_FOUNDATION",
        "sourceCandidateBinding": "EXTERNAL_AFTER_PUBLICATION",
        "selfExclusion": "release/evidence/P5-001/manifest.json",
        "claimBoundary": "Coded information-architecture and UX-flow prototype only.",
        "artifacts": artifacts,
    }


def write_manifest(project: Path, *, check: bool) -> None:
    path = project / "release/evidence/P5-001/manifest.json"
    expected = canonical_json(manifest_payload(project))
    if check:
        if not path.is_file() or path.read_text(encoding="utf-8") != expected:
            raise WorkerFError("P5-001 manifest is stale")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(expected, encoding="utf-8")


def validate_registry(project: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    registry = load_json(project / "config/test_center_registry.v1.json")
    modules = [
        item
        for item in registry.get("testModules", [])
        if item.get("moduleId") == MODULE_ID
    ]
    if len(modules) != 1:
        raise WorkerFError(f"expected exactly one {MODULE_ID} module, found {len(modules)}")

    cases = {
        str(item.get("testId")): item
        for item in registry.get("testCases", [])
        if str(item.get("testId", "")).startswith(TEST_PREFIX)
    }
    profiles = {
        str(item.get("stableCheckId")): item
        for item in registry.get("projectTestProfiles", [])
        if str(item.get("stableCheckId", "")).startswith(TEST_PREFIX)
    }
    mappings = [
        item
        for item in registry.get("affectedTestMappings", [])
        if str(item.get("mappingId", "")).startswith("affected.p5-001.")
    ]
    if set(cases) != REQUIRED_TEST_IDS:
        raise WorkerFError(f"P5 test cases drifted: {sorted(cases)}")
    if set(profiles) != REQUIRED_TEST_IDS:
        raise WorkerFError(f"P5 profiles drifted: {sorted(profiles)}")
    if len({str(item["mappingId"]) for item in mappings}) != len(mappings):
        raise WorkerFError("P5 affected mapping IDs are not unique")
    if len(mappings) < 10:
        raise WorkerFError(f"expected at least ten P5 affected mappings, found {len(mappings)}")

    for test_id, case in cases.items():
        if case.get("moduleId") != MODULE_ID:
            raise WorkerFError(f"{test_id} is bound to the wrong module")
        if case.get("roadmapTaskIds") != ["P5-001"]:
            raise WorkerFError(f"{test_id} is not bound exactly to P5-001")
        if case.get("mandatory") is not True:
            raise WorkerFError(f"{test_id} must remain mandatory")
    for test_id, profile in profiles.items():
        if profile.get("mutationPolicy") != "NON_MUTATING":
            raise WorkerFError(f"{test_id} profile is mutating")
        if profile.get("workingDirectory") != ".":
            raise WorkerFError(f"{test_id} profile working directory drifted")
        if sorted(profile.get("platforms", [])) != ["linux", "macos", "windows"]:
            raise WorkerFError(f"{test_id} platform matrix drifted")
        if not isinstance(profile.get("argv"), list) or not profile["argv"]:
            raise WorkerFError(f"{test_id} profile argv is not structured")

    selected_a = select_affected_tests(
        [
            "lib/product/p5_information_architecture/p5_models.dart",
            "test/product/p5_information_architecture/p5_accessibility_test.dart",
        ],
        mappings,
    )
    selected_b = select_affected_tests(
        [
            "test/product/p5_information_architecture/p5_accessibility_test.dart",
            "lib/product/p5_information_architecture/p5_models.dart",
        ],
        reversed(mappings),
    )
    if selected_a != selected_b:
        raise WorkerFError("affected-test selection is input-order dependent")
    if not selected_a:
        raise WorkerFError("representative P5 changes select no tests")
    return registry, mappings


def validate_hierarchy(project: Path) -> None:
    hierarchy = load_json(project / "config/test_center_assurance_hierarchy.v1.json")
    bindings = {
        str(item.get("testId")): str(item.get("levelId"))
        for item in hierarchy.get("testBindings", [])
        if str(item.get("testId", "")).startswith(TEST_PREFIX)
    }
    if set(bindings) != REQUIRED_TEST_IDS:
        raise WorkerFError(f"P5 assurance bindings drifted: {bindings}")
    if set(bindings.values()) != {"unit"}:
        raise WorkerFError(f"P5 assurance level is inflated: {bindings}")


def validate_source_boundary(project: Path) -> None:
    required = [
        "lib/p5_ia_preview.dart",
        "lib/product/p5_information_architecture/p5_models.dart",
        "lib/product/p5_information_architecture/p5_controller.dart",
        "lib/product/p5_information_architecture/p5_fixtures.dart",
        "lib/product/p5_information_architecture/p5_prototype.dart",
        "test/product/p5_information_architecture/p5_state_controller_test.dart",
        "test/product/p5_information_architecture/p5_source_boundary_test.dart",
        "test/product/p5_information_architecture/p5_verification_center_test.dart",
        "test/product/p5_information_architecture/p5_accessibility_test.dart",
        "release/evidence/P5-001/current-ux-inventory.json",
        "release/evidence/P5-001/test-center-registration.json",
        "release/evidence/P5-001/claim-boundary.json",
    ]
    missing = [relative for relative in required if not (project / relative).is_file()]
    if missing:
        raise WorkerFError(f"required P5 paths are missing: {missing}")

    production = (project / "lib/main.dart").read_text(encoding="utf-8")
    if "p5_ia_preview.dart" in production or "P5InformationArchitectureApp" in production:
        raise WorkerFError("P5 preview leaked into the production entry point")

    source_root = project / "lib/product/p5_information_architecture"
    for path in sorted(source_root.glob("*.dart")):
        text = path.read_text(encoding="utf-8")
        for token in FORBIDDEN_SOURCE_TOKENS:
            if token in text:
                raise WorkerFError(
                    f"forbidden side-effect token {token!r} in {path.relative_to(project)}"
                )

    checker = (
        project / "test/product/p5_information_architecture/worker_f_p5_ia.py"
    ).resolve()
    for path in worker_f_files(project):
        if path.resolve() == checker:
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for token in PLACEHOLDERS:
            if token in text:
                raise WorkerFError(f"placeholder {token} remains in {path.relative_to(project)}")


def validate_claim_boundary(project: Path) -> None:
    claim = load_json(project / "release/evidence/P5-001/claim-boundary.json")
    forbidden_true = (
        "productionShell",
        "ownerModeBehavior",
        "webStudio",
        "accessibilityCertified",
        "consumerReady",
        "releaseReady",
    )
    for key in forbidden_true:
        if claim.get(key) is True:
            raise WorkerFError(f"claim boundary illegally promotes {key}")


def validate_project(project: Path) -> dict[str, Any]:
    project = project.resolve()
    registry, mappings = validate_registry(project)
    validate_hierarchy(project)
    validate_source_boundary(project)
    validate_claim_boundary(project)
    write_manifest(project, check=True)
    return {
        "schemaVersion": "1.0.0",
        "status": "PASS",
        "checkMode": "NON_MUTATING",
        "taskId": "P5-001",
        "moduleId": MODULE_ID,
        "testIdCount": len(REQUIRED_TEST_IDS),
        "affectedMappingCount": len(mappings),
        "capabilitySupport": "SOURCE_FOUNDATION",
        "certification": "NOT_EVALUATED",
        "platformSupport": "UNSUPPORTED",
        "releaseSupport": "UNSUPPORTED",
        "productionEntryPointChanged": False,
        "registryId": registry.get("registryId"),
    }


def parse_args(argv: Sequence[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    check = sub.add_parser("check")
    check.add_argument("--project", type=Path, default=Path("."))
    manifest = sub.add_parser("manifest")
    manifest.add_argument("--project", type=Path, default=Path("."))
    manifest.add_argument("--check", action="store_true")
    select = sub.add_parser("select")
    select.add_argument("--project", type=Path, default=Path("."))
    select.add_argument("paths", nargs="+")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    project = args.project.resolve()
    try:
        if args.command == "manifest":
            write_manifest(project, check=args.check)
            print(canonical_json({"status": "PASS", "check": args.check}).rstrip())
        elif args.command == "select":
            registry = load_json(project / "config/test_center_registry.v1.json")
            mappings = [
                item
                for item in registry.get("affectedTestMappings", [])
                if str(item.get("mappingId", "")).startswith("affected.p5-001.")
            ]
            print(json.dumps(select_affected_tests(args.paths, mappings)))
        else:
            print(canonical_json(validate_project(project)).rstrip())
        return 0
    except (WorkerFError, AssertionError, KeyError, TypeError, ValueError) as exc:
        print(canonical_json({"status": "FAIL", "error": str(exc)}).rstrip())
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
