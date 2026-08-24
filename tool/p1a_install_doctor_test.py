#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import tempfile

import p1a_install_doctor as doctor


HEX64 = "a" * 64
HEX40 = "b" * 40


def connector(library: Path, *, eligible: bool) -> dict[str, object]:
    provenance: dict[str, object] = {
        "authorityType": "p1-isolated-authority-service-v2",
        "policySnapshotSha256": HEX64,
        "p1AmendmentMerged": eligible,
        "independentP1aSecurityReviewApproved": eligible,
        "workerDenialTriPlatformPassed": eligible,
        "behavioralWindowsPassed": eligible,
        "behavioralMacosPassed": eligible,
        "behavioralLinuxPassed": eligible,
        "mergedCommit": HEX40 if eligible else "0" * 40,
        "mergedTree": HEX40 if eligible else "0" * 40,
        "aggregateManifestSha256": HEX64 if eligible else "0" * 64,
    }
    return {
        "schemaVersion": "2.0.0",
        "connectorLibraryPath": str(library.resolve()),
        "maxResponseBytes": 4194304,
        "completionEligible": eligible,
        "endpoint": {
            "platform": "windows",
            "transport": "windows-named-pipe",
            "address": r"\\.\pipe\KristinP1AuthorityV63",
            "serviceInstanceId": "p1a-windows-v63",
            "serviceBuildSha256": HEX64,
            "connectorLibrarySha256": HEX64,
            "installerSha256": HEX64,
            "serverIdentity": {"serviceSid": "service", "desktopSid": "desktop", "workerSid": "worker"},
            "osEnforcedIsolation": True,
            "workerPrincipalSeparated": True,
            "typedOperationsOnly": True,
            "nonExportableKeys": True,
        },
        "provenance": provenance,
    }


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="kristin-p1a-doctor-") as raw:
        root = Path(raw)
        config = root / "authority-service" / "connector-v2.json"
        missing = doctor.inspect_connector(config)
        assert missing.status == "missing_install"
        assert missing.diagnostic_code == "merged_p1a_service_unavailable"

        config.parent.mkdir(parents=True)
        config.write_text("not json", encoding="utf-8")
        invalid = doctor.inspect_connector(config)
        assert invalid.status == "invalid_install"

        library = root / "kristin_p1a_connector.dll"
        library.write_bytes(b"fixture")
        config.write_text(json.dumps(connector(library, eligible=False)), encoding="utf-8")
        pending = doctor.inspect_connector(config)
        assert pending.status == "installed_pending_evidence"
        assert pending.completion_eligible is False
        assert pending.details["evidenceFlags"]["behavioralLinuxPassed"] is False
        assert "do not edit completion flags manually" in pending.recovery

        config.write_text(json.dumps(connector(library, eligible=True)), encoding="utf-8")
        ready = doctor.inspect_connector(config)
        assert ready.status == "eligible_config_present"
        assert ready.completion_eligible is True
        assert ready.diagnostic_code == "p1a_connector_ready_for_live_probe"

        linux = doctor.application_support_root(
            "linux",
            environment={"HOME": "/home/test", "XDG_DATA_HOME": "/data/test"},
        )
        assert linux == Path("/data/test") / "kristin"
        macos = doctor.application_support_root(
            "macos",
            environment={"HOME": "/Users/test"},
        )
        assert macos == Path("/Users/test") / "Library" / "Application Support" / "Kristin"
        windows = doctor.application_support_root(
            "windows",
            environment={"LOCALAPPDATA": r"C:\Users\test\AppData\Local"},
        )
        assert str(windows).endswith("Kristin")

    print("PASS P1A install doctor: missing, invalid, evidence-pending and eligible states")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
