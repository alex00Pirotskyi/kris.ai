#!/usr/bin/env python3
"""Read-only Worker E native parity readiness validator with exact Git bindings."""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.dont_write_bytecode = True
_TOOL_DIR = str(Path(__file__).resolve().parent)
if _TOOL_DIR not in sys.path:
    sys.path.insert(0, _TOOL_DIR)

import worker_e_native_parity_readiness_legacy as legacy
import worker_e_dependency_binding as bindings
import worker_e_test_center_registration as registration
from worker_e_native_parity_model import *

check_inventory = legacy.check_inventory
check_platform_matrix = legacy.check_platform_matrix
check_no_silent_fallback = legacy.check_no_silent_fallback
check_fixtures = legacy.check_fixtures
check_isolation = legacy.check_isolation
check_devices = legacy.check_devices

EXTRA_SOURCE_PATHS = (
    Path("tool/worker_e_dependency_binding.py"),
    Path("tool/worker_e_native_parity_readiness_legacy.py"),
    Path("tool/worker_e_test_center_registration_legacy.py"),
    Path("release/evidence/P11-001/test-center-registration-spec.json"),
    Path("release/evidence/P11-001/test-center-owner-handoff.json"),
    Path("release/evidence/P11-001/worker-j-activation-review.json"),
)
SNAPSHOT_PATHS = tuple(dict.fromkeys((*WORKER_E_DURABLE_PATHS, *EXTRA_SOURCE_PATHS)))

def _snapshot(project: Path) -> dict[str, str]:
    return {
        path.as_posix(): (
            hashlib.sha256((project / path).read_bytes()).hexdigest()
            if (project / path).is_file() else "<MISSING>"
        )
        for path in SNAPSHOT_PATHS
    }

def check_source_manifest(project: Path) -> None:
    path = project / "SOURCE_MANIFEST.sha256"
    if not path.is_file():
        raise ReadinessError("SOURCE_MANIFEST.sha256 is missing")
    entries: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        if not match:
            raise ReadinessError(f"invalid source manifest line: {line!r}")
        entries[match.group(2)] = match.group(1)
    for relative in SNAPSHOT_PATHS:
        target = project / relative
        if not target.is_file():
            raise ReadinessError(f"Worker E durable path is missing: {relative}")
        expected = hashlib.sha256(target.read_bytes()).hexdigest()
        if entries.get(relative.as_posix()) != expected:
            raise ReadinessError(f"source manifest mismatch for {relative}")

def check_dependency_status(project: Path) -> None:
    document = json.loads((project / "release/evidence/P11-001/dependency-status.json").read_text())
    try:
        bindings.validate_dependency_document(project, document)
    except bindings.DependencyBindingError as exc:
        raise ReadinessError(str(exc)) from exc
    decisions = {row["taskId"]: row["decision"] for row in document.get("dependencies", [])}
    expected = {
        "P1-001": "READY",
        "P2-004": "MISSING_EVIDENCE",
        "P1-012": "MISSING_IMPLEMENTATION",
    }
    if decisions != expected:
        raise ReadinessError(f"dependency decisions changed: {decisions}")
    p2 = next(row for row in document["dependencies"] if row["taskId"] == "P2-004")
    required = {
        "STARTUP_LATENCY_NOT_MEASURED", "STEADY_STATE_MEMORY_NOT_MEASURED",
        "PACKAGING_NOT_PROVEN", "RESTART_RECOVERY_NOT_EXERCISED",
        "IPC_FRICTION_NOT_MEASURED", "MACOS_NOT_EXECUTED",
        "WINDOWS_NOT_EXECUTED", "DECISION_PROVISIONAL",
    }
    if not required <= set(p2.get("blockers", [])):
        raise ReadinessError("P2-004 blockers incomplete")
    activation = document.get("activationDecision", {})
    for field in (
        "p11_001AdrPreparationAuthorized", "p11_002PlusAuthorized",
        "p15Authorized", "productImplementationAuthorized",
    ):
        if activation.get(field) is not False:
            raise ReadinessError(f"forbidden authorization: {field}")

def check_test_center(project: Path) -> None:
    try:
        result = registration.validate_handoff(project)
    except registration.RegistrationError as exc:
        raise ReadinessError(str(exc)) from exc
    if result["registryMutated"] is not False:
        raise ReadinessError("Worker E registry mutation is forbidden")
    spec = json.loads((project / registration.SPEC).read_text())
    ids = set(spec["stableTestIds"])
    if ids != STABLE_IDS:
        raise ReadinessError("Test Center owner specification stable IDs drifted")
    if len(spec.get("mappingGroups", [])) < 4:
        raise ReadinessError("Test Center owner specification mappings incomplete")

def check_artifact_manifest(project: Path) -> None:
    data = json.loads((project / "release/evidence/P11-001/manifest.json").read_text())
    paths = [row.get("path") for row in data.get("artifacts", [])]
    if len(paths) != len(set(paths)):
        raise ReadinessError("duplicate manifest artifact paths")
    for row in data.get("artifacts", []):
        relative = Path(str(row["path"]))
        target = project / relative
        if not target.is_file():
            raise ReadinessError(f"manifest artifact missing: {relative}")
        digest = hashlib.sha256(target.read_bytes()).hexdigest()
        if row.get("sha256") != digest:
            raise ReadinessError(f"manifest artifact digest mismatch: {relative}")
    owned = data.get("ownedPaths", [])
    if "config/test_center_registry.v1.json" in owned:
        raise ReadinessError("Worker E may not claim the Test Center registry")
    if len(owned) != len(set(owned)):
        raise ReadinessError("duplicate Worker E owned paths")

def check_claim_boundary(project: Path) -> None:
    data = json.loads((project / "release/evidence/P11-001/manifest.json").read_text())
    claims = data.get("claims", {})
    forbidden = (
        "p11_001Done", "p11_002PlusIntroduced", "p15Introduced",
        "nativeParityComplete", "isolationSupported",
        "deviceAutomationSupported", "releaseSupported",
    )
    for field in forbidden:
        if claims.get(field) is not False:
            raise ReadinessError(f"forbidden manifest claim: {field}")

def _run_selected(project: Path, test_id: str | None) -> list[str]:
    checks = {
        "tc.p11.readiness.dependency-status": ("dependency-status", check_dependency_status),
        "tc.p11.readiness.native-capability-inventory": ("native-capability-inventory", check_inventory),
        "tc.p11.readiness.platform-gap-matrix": ("platform-gap-matrix", check_platform_matrix),
        "tc.p11.readiness.semantic-conformance": ("semantic-conformance", check_platform_matrix),
        "tc.p11.readiness.fixture-catalog": ("fixture-catalog", check_fixtures),
        "tc.p11.readiness.no-silent-fallback": ("no-silent-fallback", check_no_silent_fallback),
        "tc.p11.readiness.isolation-inventory": ("isolation-inventory", check_isolation),
        "tc.p11.readiness.device-contracts": ("device-contracts", check_devices),
        "tc.p11.readiness.claim-boundary": ("claim-boundary", check_claim_boundary),
        "tc.p11.readiness.nonmutation": ("nonmutation", lambda _: None),
    }
    selected = [test_id] if test_id else sorted(checks)
    completed: list[str] = []
    for stable_id in selected:
        if stable_id not in checks:
            raise ReadinessError(f"unknown stable test ID: {stable_id}")
        name, function = checks[stable_id]
        function(project)
        completed.append(name)
    check_test_center(project)
    check_artifact_manifest(project)
    check_source_manifest(project)
    return completed

def check(project: Path, test_id: str | None = None) -> dict[str, Any]:
    project = project.resolve()
    before = _snapshot(project)
    completed = _run_selected(project, test_id)
    after = _snapshot(project)
    if before != after:
        changed = sorted(path for path in before if before[path] != after[path])
        raise ReadinessError(f"check mode mutated inputs: {changed}")
    return {
        "schemaVersion": "1.0.0",
        "classification": "SOURCE_CONTRACT",
        "resultState": "PASS",
        "selectedTestId": test_id,
        "completedChecks": completed,
        "platformBehavior": {"windows": "BLOCKED", "macos": "BLOCKED", "linux": "BLOCKED"},
        "certification": "NOT_EVALUATED",
        "capabilitySupport": "SOURCE_FOUNDATION",
        "mutatedPaths": [],
    }

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--project", default=".")
    parser.add_argument("--test-id", choices=sorted(STABLE_IDS))
    args = parser.parse_args()
    if not args.check:
        print("write mode is intentionally unavailable; use --check", file=sys.stderr)
        return 2
    try:
        report = check(Path(args.project), args.test_id)
    except (OSError, json.JSONDecodeError, ReadinessError) as exc:
        print(json.dumps({"schemaVersion": "1.0.0", "resultState": "FAIL", "error": str(exc)}, sort_keys=True))
        return 1
    print(json.dumps(report, sort_keys=True))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
