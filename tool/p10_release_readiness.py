#!/usr/bin/env python3
"""Fail-closed P10 Beta-exit, RC and GA readiness aggregation for P9/P11 evidence."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
from typing import Any, Mapping

PLATFORMS = ("windows", "macos", "linux")


class ReadinessError(ValueError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def _load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ReadinessError("input_invalid", f"cannot load readiness input: {exc}") from exc
    if not isinstance(value, dict) or value.get("schemaVersion") != 1:
        raise ReadinessError("input_invalid", "readiness input must be a schemaVersion 1 object")
    return value


def _obj(parent: Mapping[str, Any], key: str) -> Mapping[str, Any]:
    value = parent.get(key)
    return value if isinstance(value, dict) else {}


def _truth(parent: Mapping[str, Any], key: str) -> bool:
    return parent.get(key) is True


def _non_negative_number(value: Any) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value < 0:
        return 0.0
    return float(value)


def _non_negative_int(value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        return 0
    return value


def _reported_zero_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool) and value == 0


def _add(blockers: list[dict[str, str]], code: str, detail: str) -> None:
    blockers.append({"code": code, "detail": detail})


def evaluate_readiness(data: Mapping[str, Any]) -> dict[str, Any]:
    candidate = _obj(data, "candidate")
    source_commit = str(candidate.get("sourceCommit") or "")
    version = str(candidate.get("version") or "")
    global_blockers: list[dict[str, str]] = []
    if not re.fullmatch(r"[0-9a-f]{40}", source_commit):
        _add(global_blockers, "candidate.source_identity_missing", "candidate sourceCommit must be an exact 40-character Git SHA")
    if not version:
        _add(global_blockers, "candidate.version_missing", "candidate version is required")

    raw_release_platforms = candidate.get("releasePlatforms")
    release_platforms: list[str] = []
    if isinstance(raw_release_platforms, list):
        for raw in raw_release_platforms:
            if isinstance(raw, str) and raw in PLATFORMS and raw not in release_platforms:
                release_platforms.append(raw)
    if not release_platforms:
        _add(global_blockers, "candidate.release_platforms_missing", "at least one explicit release platform is required")

    p1_p8 = _obj(data, "p1ToP8")
    p9 = _obj(data, "p9")
    p10 = _obj(data, "p10")
    p11 = _obj(data, "p11")
    p11_platforms = _obj(p11, "platforms")

    p9_blockers: list[dict[str, str]] = []
    scalar_p9 = (
        ("releaseBundleVerified", "p9.release_bundle_unverified", "release bundle verification is missing"),
        ("dependencyLocksVerified", "p9.dependency_locks_unverified", "dependency lock verification is missing"),
        ("sbomVerified", "p9.sbom_unverified", "SBOM verification is missing"),
        ("reproducibleBuildVerified", "p9.reproducibility_unverified", "reproducible build evidence is missing"),
        ("updateAuthenticationVerified", "p9.update_auth_unverified", "authenticated update verification is missing"),
        ("rollbackVerified", "p9.rollback_unverified", "rollback behavioral verification is missing"),
        ("cleanInstallVerified", "p9.clean_install_unverified", "clean install verification is missing"),
        ("upgradeVerified", "p9.upgrade_unverified", "upgrade verification is missing"),
        ("privacyAuditClosed", "p9.privacy_audit_open", "privacy/data-flow audit is not closed"),
    )
    for field, code, detail in scalar_p9:
        if not _truth(p9, field):
            _add(p9_blockers, code, detail)

    pen = _obj(p9, "penetrationReview")
    if not _truth(pen, "present"):
        _add(p9_blockers, "p9.penetration_review_missing", "independent penetration review evidence is missing")
    if not _reported_zero_int(pen.get("critical")) or not _reported_zero_int(pen.get("high")):
        _add(p9_blockers, "p9.security_findings_open", "critical/high penetration findings must be explicitly reported as zero")
    if _non_negative_number(p9.get("soakHours")) < 24:
        _add(p9_blockers, "p9.soak_incomplete", "native-shipping soak must reach at least 24 hours")
    if not _reported_zero_int(p9.get("soakCrashCount")):
        _add(p9_blockers, "p9.soak_crashes", "native-shipping soak crash count must be explicitly reported as zero")

    signed = _obj(p9, "signedArtifacts")
    installers = _obj(p9, "nativeInstallers")
    clean_machine = _obj(p9, "cleanMachine")
    platform_matrix: dict[str, Any] = {}
    for platform in PLATFORMS:
        native = _obj(p11_platforms, platform)
        platform_blockers: list[dict[str, str]] = []
        if not _truth(signed, platform):
            _add(platform_blockers, f"platform.{platform}.artifact_unsigned", "verified signed artifact evidence is missing")
        if not _truth(installers, platform):
            _add(platform_blockers, f"platform.{platform}.installer_unverified", "native installer verification is missing")
        if not _truth(clean_machine, platform):
            _add(platform_blockers, f"platform.{platform}.clean_machine_unverified", "clean-machine install/upgrade evidence is missing")
        if not _truth(native, "behaviorVerified"):
            _add(platform_blockers, f"platform.{platform}.native_behavior_unverified", "native behavioral verification is missing")
        if _non_negative_number(native.get("featureParityPercent")) < 95:
            _add(platform_blockers, f"platform.{platform}.feature_parity_below_95", "P3/P4 native feature parity is below 95% or unreported")
        if not _truth(native, "deviceAutomationVerified"):
            _add(platform_blockers, f"platform.{platform}.device_automation_unverified", "device/native automation verification is missing")
        if not _truth(native, "isolationVerified"):
            _add(platform_blockers, f"platform.{platform}.isolation_unverified", "native isolation verification is missing")
        if not _truth(native, "remoteMcpVerified"):
            _add(platform_blockers, f"platform.{platform}.remote_mcp_unverified", "remote MCP auth/audit verification is missing")
        platform_matrix[platform] = {
            "supportClaimed": platform in release_platforms and not platform_blockers,
            "requestedForRelease": platform in release_platforms,
            "blockers": platform_blockers,
        }
        if platform in release_platforms:
            if not _truth(signed, platform):
                _add(p9_blockers, f"p9.{platform}.artifact_unsigned", "release platform lacks verified signing evidence")
            if not _truth(installers, platform):
                _add(p9_blockers, f"p9.{platform}.installer_unverified", "release platform lacks verified native installer evidence")
            if not _truth(clean_machine, platform):
                _add(p9_blockers, f"p9.{platform}.clean_machine_unverified", "release platform lacks clean-machine evidence")

    p9_complete = not p9_blockers and not global_blockers

    beta_blockers = [*global_blockers]
    if not _truth(p1_p8, "evidenceCurrent"):
        _add(beta_blockers, "p1_p8.evidence_stale", "P1-P8 evidence is not explicitly current")
    beta_blockers.extend(p9_blockers)
    if _non_negative_int(p10.get("betaUsers")) < 100:
        _add(beta_blockers, "p10.beta_users_below_100", "Beta evidence requires at least 100 users")
    if _non_negative_number(p10.get("betaDays")) < 14:
        _add(beta_blockers, "p10.beta_duration_below_14_days", "Beta evidence requires at least 14 days")
    if not _reported_zero_int(p10.get("betaSev1Count")):
        _add(beta_blockers, "p10.beta_sev1", "Beta Sev-1 count must be explicitly reported as zero")
    beta_exit_ready = not beta_blockers

    rc_blockers = list(beta_blockers)
    if _non_negative_number(p10.get("rcSoakDays")) < 7:
        _add(rc_blockers, "p10.rc_soak_below_7_days", "RC evidence requires at least seven soak days")
    if not _reported_zero_int(p10.get("rcCrashCount")):
        _add(rc_blockers, "p10.rc_crashes", "RC crash count must be explicitly reported as zero")
    rc_ready = not rc_blockers

    ga_blockers = list(rc_blockers)
    if not _truth(p10, "docsRunbookReady"):
        _add(ga_blockers, "p10.docs_runbook_missing", "release documentation/runbook/support material is not ready")
    if not _truth(p10, "synchronizedReleaseDryRun"):
        _add(ga_blockers, "p10.synchronized_release_unverified", "synchronized signed release mechanics are unverified")
    if not _truth(p10, "humanUsabilityApproved"):
        _add(ga_blockers, "p10.human_usability_missing", "human usability approval is missing")
    for platform in release_platforms:
        ga_blockers.extend(platform_matrix[platform]["blockers"])
    ga_ready = not ga_blockers

    return {
        "schemaVersion": 1,
        "candidate": {"sourceCommit": source_commit, "version": version, "releasePlatforms": release_platforms},
        "resultState": "PASS" if ga_ready else "BLOCKED",
        "p9": {"complete": p9_complete, "blockers": p9_blockers},
        "p10": {
            "betaExitReady": beta_exit_ready,
            "betaExitBlockers": beta_blockers,
            "rcReady": rc_ready,
            "rcBlockers": rc_blockers,
            "gaReady": ga_ready,
            "gaBlockers": ga_blockers,
        },
        "p11": {
            "nativeParityClaimed": False,
            "platformMatrix": platform_matrix,
        },
        "truthBoundary": {
            "sourceImplementedIsSupported": False,
            "singlePlatformIsNativeParity": False,
            "installerBuildIsProductionReady": False,
            "p10InfrastructureIsPromotion": False,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output")
    args = parser.parse_args()
    try:
        report = evaluate_readiness(_load(Path(args.input)))
    except ReadinessError as exc:
        print(json.dumps({"resultState": "FAIL", "code": exc.code, "error": str(exc)}, sort_keys=True))
        return 2
    text = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        output = Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8", newline="\n")
    print(text, end="")
    return 0 if report["resultState"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
