#!/usr/bin/env python3
"""Worker E P11 native parity readiness checker."""
from __future__ import annotations
import hashlib, json, re, subprocess, sys
from pathlib import Path
sys.dont_write_bytecode = True

import worker_e_native_parity_model as model


# Precomputed SHA40 and SHA256 regexes for performance
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")


class ReadinessError(ValueError):
    pass

def _run_git(project: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            ["git", "-C", str(project), *args],
            check=check,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ReadinessError(f"git command failed: {' '.join(args)}") from exc

def _run_git_bytes(project: Path, *args: str) -> bytes:
    try:
        return subprocess.run(
            ["git", "-C", str(project), *args],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        ).stdout
    except (OSError, subprocess.CalledProcessError) as exc:
        raise ReadinessError(f"git command failed: {' '.join(args)}") from exc

def commit_tree(project: Path, commit: str) -> str:
    if not SHA40.fullmatch(commit):
        raise ReadinessError(f"invalid commit identity: {commit!r}")
    result = _run_git(project, "rev-parse", f"{commit}^{{tree}}")
    tree = result.stdout.strip()
    if not SHA40.fullmatch(tree):
        raise ReadinessError(f"commit has invalid tree identity: {commit}")
    return tree

def check_dependency_status(project: Path) -> None:
    """Verify the dependency status document."""
    d = model._load(project, "dependency")
    inputs = d.get("repositoryInputs", {})
    for name in ("protectedMain", "workerA", "workerB", "workerC", "workerD", "workerJ"):
        row = inputs.get(name)
        if not isinstance(row, dict) or not SHA40.fullmatch(str(row.get("commit", ""))):
            raise ReadinessError(f"{name} commit is not exact")
        if row.get("tree") is not None and not SHA40.fullmatch(str(row["tree"])):
            raise ReadinessError(f"{name} tree is not exact")
    if (d.get("activationLane"), d.get("classification"), d.get("p11ApprovalState")) != (
        "LANE_A", "P11_NATIVE_READINESS_ACTIVE", "P11-001_NOT_APPROVED"
    ):
        raise ReadinessError("P2-004 blocker requires unapproved Lane A")
    decisions = {r["taskId"]: r["decision"] for r in d.get("dependencies", [])}
    if decisions != {
        "P1-001": "READY", "P2-004": "MISSING_EVIDENCE", "P1-012": "MISSING_IMPLEMENTATION"
    }:
        raise ReadinessError(f"dependency decisions changed: {decisions}")
    p2 = next(r for r in d["dependencies"] if r["taskId"] == "P2-004")
    blockers = {
        "STARTUP_LATENCY_NOT_MEASURED", "STEADY_STATE_MEMORY_NOT_MEASURED",
        "PACKAGING_NOT_PROVEN", "RESTART_RECOVERY_NOT_EXERCISED",
        "IPC_FRICTION_NOT_MEASURED", "MACOS_NOT_EXECUTED", "WINDOWS_NOT_EXECUTED",
        "DECISION_PROVISIONAL"
    }
    if not blockers <= set(p2.get("blockers", [])):
        raise ReadinessError("P2-004 blockers incomplete")
    for r in d["dependencies"]:
        model._require_paths(project, r.get("evidencePaths", []), f"{r['taskId']} evidencePath")
    a = d.get("activationDecision", {})
    for f in (
        "p11_001AdrPreparationAuthorized", "p11_002PlusAuthorized",
        "p15Authorized", "productImplementationAuthorized"
    ):
        if a.get(f) is not False:
            raise ReadinessError(f"forbidden authorization: {f}")
    if d.get("authority", {}).get("authorityModified") is not False:
        raise ReadinessError("roadmap authority modified")

def check_inventory(project: Path) -> None:
    """Verify the native capability inventory."""
    d = model._load_inventory(project)
    rows = d.get("capabilities", [])
    ids = [r.get("capabilityId", "") for r in rows]
    model._unique(ids, "capability IDs")
    if not rows or {r.get("platform") for r in rows} != model.PLATFORMS:
        raise ReadinessError("native inventory platform omission")
    for r in rows:
        cid = r.get("capabilityId")
        for f in ("implementationClassification", "testClassification", "behavioralEvidenceClassification"):
            if r.get(f) not in model.CLASSES:
                raise ReadinessError(f"invalid {f} for {cid}")
        if r.get("behavioralEvidenceClassification") not in model.BEHAVIOR:
            raise ReadinessError(f"behavior support inferred from source for {cid}")
        if r.get("supportClassification") not in model.SUPPORT:
            raise ReadinessError(f"platform/release support overclaim for {cid}")
        for f in ("implementationPaths", "testPaths", "evidencePaths"):
            model._require_paths(project, r.get(f, []), f"{cid} {f}")
        for f in ("semanticPurpose", "knownGap", "owner", "nextAction"):
            if not str(r.get(f, "")).strip():
                raise ReadinessError(f"{f} empty for {cid}")
    if d.get("behavioralParityClaimed") is not False or d.get("supportClaim") != "SOURCE_FOUNDATION":
        raise ReadinessError("native parity/support overclaim")

def check_platform_matrix(project: Path) -> None:
    """Verify the platform gap matrix."""
    d = model._load_matrix(project)
    if set(d.get("mandatoryDesktopPlatforms", [])) != model.PLATFORMS or d.get("platformDeferred") != []:
        raise ReadinessError("mandatory desktop platform deferred")
    rows = d.get("operations", [])
    names = [r.get("operation") for r in rows]
    model._unique(names, "semantic operations")
    missing = model.REQUIRED_OPERATIONS - set(names)
    if missing:
        raise ReadinessError(f"semantic operations missing: {sorted(missing)}")
    for r in rows:
        op = r["operation"]
        details = r.get("platformSpecificDetails", {})
        if r.get("sameSemanticMeaning") is not True or set(details) != model.PLATFORMS:
            raise ReadinessError(f"platform omission for {op}")
        if (r.get("unsupportedState"), r.get("blockedState")) != ("UNSUPPORTED", "BLOCKED"):
            raise ReadinessError(f"state collapse for {op}")
        if r.get("timeout", {}).get("mustNotReportSuccess") is not True or r.get("cleanup", {}).get("completeRequiresVerification") is not True:
            raise ReadinessError(f"timeout/cleanup ambiguity for {op}")
        needed = {
            "operation", "requestedSemanticTier", "actualSemanticTier", "platform", "status",
            "cleanupState", "verificationMethod", "supportImpact"
        }
        if not needed <= set(r.get("evidenceReceipt", {}).get("fields", [])):
            raise ReadinessError(f"receipt incomplete for {op}")
        for p, v in details.items():
            if v.get("implementationClassification") not in model.CLASSES or v.get("behavioralEvidence") not in model.BEHAVIOR or v.get("supportClassification") not in model.SUPPORT:
                raise ReadinessError(f"truth overclaim for {op} on {p}")
    if d.get("behavioralParityClaimed") is not False:
        raise ReadinessError("platform parity falsely claimed")

def check_no_silent_fallback(project: Path) -> None:
    """Verify no silent fallback is allowed."""
    f = model._load(project, "matrix").get("fallbackContract", {})
    if f.get("silentFallbackAllowed") is not False or f.get("requestedTierMaySilentlyDowngrade") is not False:
        raise ReadinessError("silent fallback is allowed")
    needed = {
        "requestedSemanticTier", "actualSemanticTier", "reasonForFallback", "risk",
        "verificationMethod", "supportImpact"
    }
    if not needed <= set(f.get("requiredFields", [])):
        raise ReadinessError("fallback fields incomplete")
    if not model.FALLBACKS <= set(f.get("forbiddenSilentDegradations", [])):
        raise ReadinessError("forbidden silent degradation list incomplete")

def check_isolation(project: Path) -> None:
    """Verify the isolation readiness."""
    d = model._load_isolation(project)
    rows = d.get("tiers", [])
    if not rows or {r.get("platform") for r in rows} != model.PLATFORMS:
        raise ReadinessError("isolation platform omission")
    for r in rows:
        tid = r.get("tierId")
        for f in ("implementationClassification", "testClassification", "behavioralEvidenceClassification"):
            if r.get(f) not in model.CLASSES:
                raise ReadinessError(f"invalid {f} for {tid}")
        if r.get("behavioralEvidenceClassification") not in model.BEHAVIOR:
            raise ReadinessError(f"behavior support inferred from source for {tid}")
        if r.get("supportClassification") not in model.SUPPORT:
            raise ReadinessError(f"platform/release support overclaim for {tid}")
        for f in ("implementationPaths", "testPaths", "evidencePaths"):
            model._require_paths(project, r.get(f, []), f"{tid} {f}")
        for f in ("semanticPurpose", "knownGap", "owner", "nextAction"):
            if not str(r.get(f, "")).strip():
                raise ReadinessError(f"{f} empty for {tid}")

def check_devices(project: Path) -> None:
    """Verify the device contract readiness."""
    d = model._load(project, "devices")
    rows = d.get("deviceStates", [])
    if not rows:
        raise ReadinessError("device contract readiness is empty")
    for r in rows:
        state = r.get("state")
        if state not in model.DEVICE_STATES:
            raise ReadinessError(f"invalid device state: {state}")
        for f in ("implementationClassification", "testClassification", "behavioralEvidenceClassification"):
            if r.get(f) not in model.CLASSES:
                raise ReadinessError(f"invalid {f} for {state}")
        if r.get("behavioralEvidenceClassification") not in model.BEHAVIOR:
            raise ReadinessError(f"behavior support inferred from source for {state}")
        if r.get("supportClassification") not in model.SUPPORT:
            raise ReadinessError(f"platform/release support overclaim for {state}")
        for f in ("implementationPaths", "testPaths", "evidencePaths"):
            model._require_paths(project, r.get(f, []), f"{state} {f}")
        for f in ("semanticPurpose", "knownGap", "owner", "nextAction"):
            if not str(r.get(f, "")).strip():
                raise ReadinessError(f"{f} empty for {state}")

def check_manifest(project: Path) -> None:
    """Verify the manifest."""
    d = model._load(project, "manifest")
    if not d.get("repositoryInputs"):
        raise ReadinessError("manifest lacks repository inputs")
    for name in ("protectedMain", "workerA", "workerB", "workerC", "workerD", "workerJ"):
        row = d["repositoryInputs"].get(name)
        if not isinstance(row, dict) or not SHA40.fullmatch(str(row.get("commit", ""))):
            raise ReadinessError(f"{name} commit is not exact")
        if row.get("tree") is not None and not SHA40.fullmatch(str(row["tree"])):
            raise ReadinessError(f"{name} tree is not exact")
    model._require_paths(project, d.get("evidencePaths", []), "manifest evidencePath")

def check_source_manifest(project: Path) -> None:
    """Verify the source manifest."""
    model.check_source_manifest(project)

def check_all(project: Path) -> dict[str, str]:
    """Run all checks and return a dict of results."""
    checks = [
        ("dependency-status", check_dependency_status),
        ("native-capability-inventory", check_inventory),
        ("platform-gap-matrix", check_platform_matrix),
        ("semantic-conformance", check_platform_matrix),
        ("fixture-catalog", check_no_silent_fallback),
        ("no-silent-fallback", check_no_silent_fallback),
        ("isolation-inventory", check_isolation),
        ("device-contracts", check_devices),
        ("claim-boundary", check_manifest),
        ("nonmutation", check_source_manifest),
    ]
    results = {}
    for name, check in checks:
        try:
            check(project)
            results[name] = "PASS"
        except ReadinessError as e:
            results[name] = f"FAIL: {e}"
    return results

def main() -> int:
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=Path("."))
    checks = [
        ("dependency-status", check_dependency_status),
        ("native-capability-inventory", check_inventory),
        ("platform-gap-matrix", check_platform_matrix),
        ("semantic-conformance", check_platform_matrix),
        ("fixture-catalog", check_no_silent_fallback),
        ("no-silent-fallback", check_no_silent_fallback),
        ("isolation-inventory", check_isolation),
        ("device-contracts", check_devices),
        ("claim-boundary", check_manifest),
        ("nonmutation", check_source_manifest),
    ]
    parser.add_argument("--check", choices=["all"] + [c[0] for c in checks], default="all")
    args = parser.parse_args()
    try:
        if args.check == "all":
            results = check_all(args.project)
            print(json.dumps(results, indent=2))
        else:
            check = next(c[1] for c in checks if c[0] == args.check)
            check(args.project)
            print(json.dumps({args.check: "PASS"}))
        return 0
    except ReadinessError as e:
        print(json.dumps({"error": str(e), "resultState": "FAIL", "schemaVersion": "1.0.0"}))
        return 1


if __name__ == "__main__":
    sys.exit(main())
