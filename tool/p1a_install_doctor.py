#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import platform as host_platform
from typing import Any, Mapping


PLATFORMS = {"windows", "macos", "linux"}
HEX40 = set("0123456789abcdef")


@dataclass(frozen=True)
class InstallDiagnostic:
    status: str
    diagnostic_code: str
    connector_config: str
    completion_eligible: bool
    service_claim_present: bool
    recovery: str
    details: Mapping[str, Any]

    def to_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": "1.0.0",
            "status": self.status,
            "diagnosticCode": self.diagnostic_code,
            "connectorConfig": self.connector_config,
            "completionEligible": self.completion_eligible,
            "serviceClaimPresent": self.service_claim_present,
            "recovery": self.recovery,
            "details": dict(self.details),
        }


def normalized_platform(value: str | None = None) -> str:
    raw = (value or host_platform.system()).lower()
    if raw.startswith("win"):
        return "windows"
    if raw in {"darwin", "mac", "macos"}:
        return "macos"
    if raw.startswith("linux"):
        return "linux"
    raise ValueError(f"unsupported_platform:{raw}")


def application_support_root(
    platform: str,
    *,
    environment: Mapping[str, str] | None = None,
) -> Path:
    env = dict(environment or os.environ)
    if platform == "windows":
        root = env.get("LOCALAPPDATA", "").strip()
        if not root:
            raise ValueError("p1a_local_app_data_missing")
        return Path(root) / "Kristin"
    home = env.get("HOME", "").strip()
    if not home:
        raise ValueError("p1a_home_missing")
    if platform == "macos":
        return Path(home) / "Library" / "Application Support" / "Kristin"
    xdg = env.get("XDG_DATA_HOME", "").strip()
    return (Path(xdg) if xdg else Path(home) / ".local" / "share") / "kristin"


def _hex(value: Any, length: int) -> bool:
    text = str(value or "").lower()
    return len(text) == length and all(char in HEX40 for char in text)


def _object(value: Any) -> dict[str, Any]:
    return dict(value) if isinstance(value, dict) else {}


def inspect_connector(config_path: Path) -> InstallDiagnostic:
    config_path = config_path.expanduser().resolve()
    if not config_path.is_file():
        return InstallDiagnostic(
            status="missing_install",
            diagnostic_code="merged_p1a_service_unavailable",
            connector_config=str(config_path),
            completion_eligible=False,
            service_claim_present=False,
            recovery=(
                "Install the Kristin Authority Service for this platform. "
                "Do not create connector-v2.json by hand; the platform installer must provision the service, connector library, OS identity, and non-exportable key material."
            ),
            details={"connectorPresent": False},
        )
    if config_path.is_symlink():
        return InstallDiagnostic(
            status="invalid_install",
            diagnostic_code="p1a_connector_symlink_forbidden",
            connector_config=str(config_path),
            completion_eligible=False,
            service_claim_present=False,
            recovery="Reinstall the Authority Service from the reviewed platform installer; connector configuration symlinks are rejected.",
            details={"connectorPresent": True, "symlink": True},
        )
    try:
        raw = config_path.read_bytes()
        decoded = json.loads(raw)
    except (OSError, json.JSONDecodeError) as exc:
        return InstallDiagnostic(
            status="invalid_install",
            diagnostic_code="p1a_connector_configuration_invalid",
            connector_config=str(config_path),
            completion_eligible=False,
            service_claim_present=False,
            recovery="Reinstall the Authority Service. The installed connector configuration is unreadable or malformed.",
            details={"connectorPresent": True, "errorType": type(exc).__name__},
        )
    if not isinstance(decoded, dict) or decoded.get("schemaVersion") != "2.0.0":
        return InstallDiagnostic(
            status="invalid_install",
            diagnostic_code="p1a_connector_configuration_version_invalid",
            connector_config=str(config_path),
            completion_eligible=False,
            service_claim_present=False,
            recovery="Reinstall the Authority Service with the current installer; only connector schema 2.0.0 is accepted.",
            details={"connectorPresent": True},
        )
    endpoint = _object(decoded.get("endpoint"))
    provenance = _object(decoded.get("provenance"))
    platform = str(endpoint.get("platform") or "")
    library = Path(str(decoded.get("connectorLibraryPath") or ""))
    service_claim_present = bool(endpoint.get("serviceInstanceId"))
    shape_ok = (
        platform in PLATFORMS
        and library.is_absolute()
        and library.is_file()
        and endpoint.get("osEnforcedIsolation") is True
        and endpoint.get("workerPrincipalSeparated") is True
        and endpoint.get("typedOperationsOnly") is True
        and endpoint.get("nonExportableKeys") is True
        and _hex(endpoint.get("serviceBuildSha256"), 64)
        and _hex(endpoint.get("connectorLibrarySha256"), 64)
        and _hex(endpoint.get("installerSha256"), 64)
        and provenance.get("authorityType") == "p1-isolated-authority-service-v2"
        and _hex(provenance.get("policySnapshotSha256"), 64)
    )
    if not shape_ok:
        return InstallDiagnostic(
            status="invalid_install",
            diagnostic_code="p1a_connector_installation_ineligible",
            connector_config=str(config_path),
            completion_eligible=False,
            service_claim_present=service_claim_present,
            recovery="Reinstall the Authority Service. The connector identity, library, isolation claims, or provenance are incomplete.",
            details={
                "connectorPresent": True,
                "platform": platform,
                "connectorLibraryPresent": library.is_file() if library.is_absolute() else False,
            },
        )
    completion_eligible = decoded.get("completionEligible") is True
    evidence_flags = {
        "p1AmendmentMerged": provenance.get("p1AmendmentMerged") is True,
        "independentP1aSecurityReviewApproved": provenance.get("independentP1aSecurityReviewApproved") is True,
        "workerDenialTriPlatformPassed": provenance.get("workerDenialTriPlatformPassed") is True,
        "behavioralWindowsPassed": provenance.get("behavioralWindowsPassed") is True,
        "behavioralMacosPassed": provenance.get("behavioralMacosPassed") is True,
        "behavioralLinuxPassed": provenance.get("behavioralLinuxPassed") is True,
    }
    evidence_complete = all(evidence_flags.values())
    merged_identity = _hex(provenance.get("mergedCommit"), 40) and _hex(provenance.get("mergedTree"), 40)
    aggregate = _hex(provenance.get("aggregateManifestSha256"), 64)
    if not completion_eligible or not evidence_complete or not merged_identity or not aggregate:
        return InstallDiagnostic(
            status="installed_pending_evidence",
            diagnostic_code="p1a_installed_completion_ineligible",
            connector_config=str(config_path),
            completion_eligible=False,
            service_claim_present=service_claim_present,
            recovery=(
                "The native Authority Service is installed, but production Owner Mode must remain locked until the signed P1A aggregate proves all three platform behaviors, worker denial, independent review, and owner approval. "
                "Run the controlled P1A certification and then p1a_activate_merged_installation.py; do not edit completion flags manually."
            ),
            details={
                "connectorPresent": True,
                "platform": platform,
                "evidenceFlags": evidence_flags,
                "mergedIdentityPresent": merged_identity,
                "aggregateManifestPresent": aggregate,
                "connectorSha256": hashlib.sha256(raw).hexdigest(),
            },
        )
    return InstallDiagnostic(
        status="eligible_config_present",
        diagnostic_code="p1a_connector_ready_for_live_probe",
        connector_config=str(config_path),
        completion_eligible=True,
        service_claim_present=service_claim_present,
        recovery="Connector configuration is evidence-eligible. Start Kristin to perform the native connector/service identity probe; Owner Mode is available only if that live probe succeeds.",
        details={
            "connectorPresent": True,
            "platform": platform,
            "evidenceFlags": evidence_flags,
            "connectorSha256": hashlib.sha256(raw).hexdigest(),
        },
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--platform", choices=sorted(PLATFORMS))
    parser.add_argument("--application-support-root")
    parser.add_argument("--connector-config")
    parser.add_argument("--json-output")
    args = parser.parse_args()
    platform = normalized_platform(args.platform)
    if args.connector_config:
        config = Path(args.connector_config)
    else:
        root = (
            Path(args.application_support_root)
            if args.application_support_root
            else application_support_root(platform)
        )
        config = root / "authority-service" / "connector-v2.json"
    diagnostic = inspect_connector(config)
    payload = diagnostic.to_json()
    if args.json_output:
        target = Path(args.json_output).expanduser().resolve()
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if diagnostic.status == "eligible_config_present" else 2


if __name__ == "__main__":
    raise SystemExit(main())
