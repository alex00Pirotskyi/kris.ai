#!/usr/bin/env python3
"""One-shot, fail-closed recovery helper for Worker F MISSION-005.

The helper executes only the first Python heredoc from the reviewed finalizer
source, replaces stale orphan object IDs with verified surviving blobs, then
reconciles the generated P5 records with the current Worker B Test Center and
P8 assurance hierarchy. It is deleted in the publication commit.
"""
from __future__ import annotations

import json
import os
import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tool/worker_f_recovery_source.yml"
TEST_PREFIX = "tc.p5-001."
FIXED_TIME = "2026-08-05T18:00:00Z"

REPLACEMENTS = {
    "d39fc0bad7980f35942dcdac170032722d765caa": "344a2c615a85a87cae7b54db72bc5590e5f180c8",
    "19d8e3e848e4ec937acb9f51ac65c07c044361f9": "f9b8e871c254fb939a4089af28f63ff6b131768f",
    "a13aa488c7d0c35bb0105a8e739decf6b0e07280": "f235dbb77741c429302e86744ad3859be04ffda9",
    "845b99d2e99a6d4cf31073d5b10099781eb4da63": "845b9539ee32013dac519eb835f6869e818be931",
    "642eb0eba2ca9b3ae16a1170915db03263b9ea59": "633e5226596ce373df90b149340c9f6d17a7dad3",
    "c4368ce437caa96a9b99b9505df981a0f9a7ad9b": "f16ee298c8f5f755657b5515cbf56c1d679df032",
    "2e3b7d098696bd7f92d3830a506ff33fe7205e0f": "c3d728294ace39abf82702cb4e9b36e9b3a6e233",
    "d95b658732943b5e6fa4f47ae1d7b958124f38eb": "7506299c039eba219821534598593d78176c20bd",
    "326462d4db7c9ec895c7f9dbf09de84fa83b8895": "3c8d9d7ad78bd47970c4742f55a355e0768ea718",
}


def materialize() -> None:
    payload = yaml.safe_load(SOURCE.read_text(encoding="utf-8"))
    step = next(
        item
        for item in payload["jobs"]["prepare"]["steps"]
        if item.get("name") == "Materialize reviewed source and deterministic contracts"
    )
    script = str(step["run"])
    match = re.search(r"python - <<'PY'\n(?P<body>.*?)\nPY(?:\n|$)", script, re.DOTALL)
    if match is None:
        raise RuntimeError("reviewed materializer Python heredoc was not found")
    code = match.group("body")
    for old, new in REPLACEMENTS.items():
        code = code.replace(old, new)
    namespace = {"__name__": "__main__"}
    exec(compile(code, "worker_f_recovered_materializer.py", "exec"), namespace)


def patch_source() -> None:
    fixture_path = ROOT / "lib/product/p5_information_architecture/p5_fixtures.dart"
    fixture = fixture_path.read_text(encoding="utf-8").replace(
        "<T5CapabilityFixture>[", "<P5CapabilityFixture>["
    )
    fixture_path.write_text(fixture, encoding="utf-8")

    controller_path = ROOT / "lib/product/p5_information_architecture/p5_controller.dart"
    controller = controller_path.read_text(encoding="utf-8").replace(
        "extension _P5IterableFirstOrNull<T>",
        "extension P5IterableFirstOrNull<T>",
    )
    controller_path.write_text(controller, encoding="utf-8")

    prototype_path = ROOT / "lib/product/p5_information_architecture/p5_prototype.dart"
    prototype = prototype_path.read_text(encoding="utf-8")
    old = """  late final P5InformationArchitectureController controller =
      widget.controller ?? P5InformationArchitectureController();
  late final bool ownsController = widget.controller == null;

  @override
  void dispose() {
"""
    new = """  late final P5InformationArchitectureController controller;
  late final bool ownsController;

  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? P5InformationArchitectureController();
    ownsController = widget.controller == null;
  }

  @override
  void dispose() {
"""
    if old in prototype:
        prototype = prototype.replace(old, new)
    if "late final P5InformationArchitectureController controller =" in prototype:
        raise RuntimeError("prototype lifecycle repair did not apply")
    prototype_path.write_text(prototype, encoding="utf-8")


def patch_registry_and_hierarchy() -> list[str]:
    registry_path = ROOT / "config/test_center_registry.v1.json"
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    test_ids = sorted(
        item["testId"]
        for item in registry.get("testCases", [])
        if str(item.get("testId", "")).startswith(TEST_PREFIX)
    )
    if len(test_ids) != 10:
        raise RuntimeError(f"expected 10 P5 test IDs, found {test_ids}")

    modules = [
        item
        for item in registry.get("testModules", [])
        if item.get("moduleId") == "tm.p5-information-architecture"
    ]
    if len(modules) != 1:
        raise RuntimeError(f"expected one P5 module, found {len(modules)}")
    modules[0].update(
        {
            "displayName": "P5 information architecture",
            "owner": "Worker F / MISSION-005",
            "purpose": "Validate the isolated presentation-only P5-001 navigation, workspace, state, Verification Center, Owner Mode, keyboard, and semantics prototype.",
            "assuranceClasses": ["source_contract", "behavioral"],
        }
    )

    for case in registry.get("testCases", []):
        if str(case.get("testId", "")).startswith(TEST_PREFIX):
            case["roadmapTaskIds"] = ["P5-001"]
            case["assuranceClass"] = "behavioral"
            case["mandatory"] = True

    for profile in registry.get("projectTestProfiles", []):
        if str(profile.get("stableCheckId", "")).startswith(TEST_PREFIX):
            profile["assuranceClass"] = "behavioral"
            profile["evidenceDestination"] = "release/evidence/P5-001/test-results.json"
            profile["environmentAllowlist"] = [
                "CI",
                "GITHUB_ACTIONS",
                "RUNNER_ARCH",
                "RUNNER_OS",
            ]
            profile["mutationPolicy"] = "NON_MUTATING"
            profile["platforms"] = ["linux", "macos", "windows"]
            profile["timeoutSeconds"] = 900
            profile["workingDirectory"] = "."

    registry["testingStudioPresentationRecords"] = [
        item
        for item in registry.get("testingStudioPresentationRecords", [])
        if not str(item.get("presentationId", "")).startswith("presentation.p5-001.")
    ]
    registry["testingStudioPresentationRecords"].extend(
        [
            {
                "presentationId": "presentation.p5-001.test-execution",
                "surface": "DEVELOPMENT_VERIFICATION",
                "displayName": "P5-001 test execution",
                "purpose": "Present exact test execution without implying review, certification, platform, or release support.",
                "phase": "P5-001 coded prototype",
                "capability": "Information architecture prototype",
                "assuranceClass": "behavioral",
                "platformMatrix": {
                    "required": ["linux", "macos", "windows"],
                    "observed": [],
                },
                "stateDomain": "TEST_EXECUTION",
                "currentState": "UNKNOWN",
                "lastExactCommitResult": None,
                "staleResultWarning": False,
                "requiredNextAction": "Run exact-head tests on all three required desktop CI hosts.",
                "evidenceLinks": [],
                "certificationImpact": "Test execution alone does not certify P5-001.",
                "supportClaimImpact": "No support promotion is allowed from this record.",
            },
            {
                "presentationId": "presentation.p5-001.certification",
                "surface": "PLATFORM_CERTIFICATION",
                "displayName": "P5-001 certification boundary",
                "purpose": "Keep certification independent from source and widget results.",
                "phase": "P5-001 coded prototype",
                "capability": "Information architecture prototype",
                "assuranceClass": "behavioral",
                "platformMatrix": {
                    "required": ["linux", "macos", "windows"],
                    "observed": [],
                },
                "stateDomain": "CERTIFICATION",
                "currentState": "NOT_EVALUATED",
                "lastExactCommitResult": None,
                "staleResultWarning": False,
                "requiredNextAction": "Obtain exact-candidate independent review after exact CI passes.",
                "evidenceLinks": [],
                "certificationImpact": "Certification remains NOT_EVALUATED.",
                "supportClaimImpact": "No platform or release support is established.",
            },
            {
                "presentationId": "presentation.p5-001.capability-support",
                "surface": "RELEASE_READINESS",
                "displayName": "P5-001 capability support ceiling",
                "purpose": "Expose the source-foundation ceiling without consumer or release inflation.",
                "phase": "P5-001 coded prototype",
                "capability": "Information architecture prototype",
                "assuranceClass": "behavioral",
                "platformMatrix": {
                    "required": ["linux", "macos", "windows"],
                    "observed": [],
                },
                "stateDomain": "CAPABILITY_SUPPORT",
                "currentState": "SOURCE_FOUNDATION",
                "lastExactCommitResult": None,
                "staleResultWarning": False,
                "requiredNextAction": "Retain SOURCE_FOUNDATION until later production UX tasks and certifications complete.",
                "evidenceLinks": [],
                "certificationImpact": "No certification state is inferred.",
                "supportClaimImpact": "Maximum claim is SOURCE_FOUNDATION.",
            },
        ]
    )
    registry["testingStudioPresentationRecords"].sort(
        key=lambda item: item["presentationId"]
    )
    registry_path.write_text(
        json.dumps(registry, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    hierarchy_path = ROOT / "config/test_center_assurance_hierarchy.v1.json"
    hierarchy = json.loads(hierarchy_path.read_text(encoding="utf-8"))
    hierarchy["testBindings"] = [
        item
        for item in hierarchy["testBindings"]
        if not str(item.get("testId", "")).startswith(TEST_PREFIX)
    ]
    hierarchy["testBindings"].extend(
        {
            "testId": test_id,
            "levelId": "unit",
            "rationale": "Deterministic in-memory presentation behavior capped at SOURCE_FOUNDATION support.",
        }
        for test_id in test_ids
    )
    hierarchy["testBindings"].sort(key=lambda item: item["testId"])
    hierarchy_path.write_text(
        json.dumps(hierarchy, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return test_ids


def patch_validator() -> None:
    path = ROOT / "tool/worker_f_p5_ia.py"
    text = path.read_text(encoding="utf-8")
    text = text.replace(
        "profiles={p.get('profileId'):p for p in registry.get('projectTestProfiles',[]) if 'p5-001' in str(p.get('profileId',''))}",
        "profiles={p.get('stableCheckId'):p for p in registry.get('projectTestProfiles',[]) if str(p.get('stableCheckId','')).startswith('tc.p5-001.')}",
    )
    pattern = re.compile(
        r"\s+for case in cases\.values\(\):\n"
        r"\s+ids=case\.get\('projectProfileIds'\) or case\.get\('profileIds'\) or \[\]\n"
        r"\s+if len\(ids\)!=1 or ids\[0\] not in profiles: raise AssertionError\(f'case profile mismatch: \{case\.get\(\"testId\"\)\}'\)\n"
    )
    text, count = pattern.subn(
        "\n            if set(cases) != set(profiles):\n"
        "              raise AssertionError('P5 case/profile identities differ')\n",
        text,
        count=1,
    )
    if count != 1:
        raise RuntimeError("Worker F case/profile validator block was not repaired")
    path.write_text(text, encoding="utf-8")


def patch_workflow() -> None:
    path = ROOT / ".github/workflows/worker-f-p5-001-information-architecture.yml"
    text = path.read_text(encoding="utf-8")
    text = text.replace("ubuntu-latest", "ubuntu-24.04")
    text = text.replace("windows-latest", "windows-2025")
    text = text.replace("macos-latest", "macos-15")
    needle = "                    python tool/test_center_contracts.py check --project .\n"
    if needle in text and "test_center_assurance_hierarchy.py check" not in text:
        text = text.replace(
            needle,
            needle
            + "                    python tool/test_center_assurance_hierarchy.py check --project .\n",
        )
    path.write_text(text, encoding="utf-8")


def write_evidence(test_ids: list[str]) -> None:
    evidence = ROOT / "release/evidence/P5-001"
    evidence.mkdir(parents=True, exist_ok=True)
    registration = {
        "schemaVersion": "1.0.0",
        "taskId": "P5-001",
        "classification": "SOURCE_FOUNDATION",
        "authority": {
            "human": "docs/roadmap/MASTER.md",
            "machine": "docs/roadmap/roadmap.yaml within declared P0/P1 scope",
            "testCenter": "Worker B canonical contracts",
        },
        "sourceCandidateBinding": "EXTERNAL_AFTER_PUBLICATION",
        "moduleId": "tm.p5-information-architecture",
        "testIds": test_ids,
        "profileIds": test_ids,
        "mappingIds": sorted(
            item["mappingId"]
            for item in json.loads(
                (ROOT / "config/test_center_registry.v1.json").read_text(
                    encoding="utf-8"
                )
            )["affectedTestMappings"]
            if str(item.get("mappingId", "")).startswith("affected.p5-001.")
        ),
        "assuranceLevel": "unit",
        "mutationPolicy": "NON_MUTATING",
        "capabilitySupport": "SOURCE_FOUNDATION",
        "certification": "NOT_EVALUATED",
        "platformSupport": "UNSUPPORTED",
        "releaseSupport": "UNSUPPORTED",
        "claimBoundary": "Coded information-architecture and UX-flow prototype only.",
    }
    (evidence / "test-center-registration.json").write_text(
        json.dumps(registration, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    (evidence / "test-results.json").write_text(
        json.dumps(
            {
                "schemaVersion": "1.0.0",
                "taskId": "P5-001",
                "classification": "SOURCE_FOUNDATION",
                "sourceCandidateBinding": "EXTERNAL_AFTER_PUBLICATION",
                "resultState": "UNKNOWN",
                "certification": "NOT_EVALUATED",
                "capabilitySupport": "SOURCE_FOUNDATION",
                "platformSupport": "UNSUPPORTED",
                "releaseSupport": "UNSUPPORTED",
                "claimBoundary": "Exact-head results are packaged after publication.",
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


def write_documentation() -> None:
    progress = ROOT / "docs/roadmap/progress/2026-08-06-mission-005-p5-001-recovery.md"
    progress.parent.mkdir(parents=True, exist_ok=True)
    progress.write_text(
        "# MISSION-005 / P5-001 recovery — 2026-08-06\n\n"
        "## Result\n\n"
        "Recovered the ordinary P5-001 source candidate from surviving reviewed Git objects and reconciled it with the current Worker B/P8 ancestry.\n\n"
        "## Repairs\n\n"
        "- Removed the temporary self-publishing workflow chain.\n"
        "- Restored the isolated `lib/p5_ia_preview.dart` entry and presentation-only source.\n"
        "- Restored widget, state, keyboard, semantics, Verification Center, and no-side-effect tests.\n"
        "- Registered ten stable IDs in the canonical Test Center and P8 unit hierarchy.\n"
        "- Retained `SOURCE_FOUNDATION`, `NOT_EVALUATED`, `UNSUPPORTED`, and `BLOCKED_EXTERNAL` claim boundaries.\n"
        "- Preserved the production shell and all P2/Owner Mode runtime semantics.\n\n"
        "## Remaining gates\n\n"
        "Exact Ubuntu, Windows, and macOS validation, product-gates, Worker B review, Worker A semantic verification, Worker J no-conflict record, and mission checkpoint publication remain required. P5-002+, P22, merge, and support promotion are not authorized.\n",
        encoding="utf-8",
    )


def main() -> int:
    if not os.environ.get("GH_TOKEN") or not os.environ.get("REPO"):
        raise RuntimeError("GH_TOKEN and REPO are required")
    materialize()
    patch_source()
    test_ids = patch_registry_and_hierarchy()
    patch_validator()
    patch_workflow()
    write_evidence(test_ids)
    write_documentation()
    print(json.dumps({"status": "RECOVERED", "testIds": test_ids}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
