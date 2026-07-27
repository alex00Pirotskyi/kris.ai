#!/usr/bin/env python3
"""Offline consistency gate for P0-005 security and support policy truth."""
from __future__ import annotations

import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def result(name: str, passed: bool, detail: str) -> dict[str, object]:
    return {"name": name, "passed": passed, "detail": detail}


def main() -> int:
    readme = read("README.md")
    security = read("SECURITY.md")
    security_model = read("docs/SECURITY_MODEL.md")
    threat_model = read("docs/THREAT_MODEL.md")
    support = read("docs/SUPPORT_POLICY.md")
    ui = read("lib/product/ui_advanced.dart")
    release = json.loads(read("RELEASE.json"))

    checks: list[dict[str, object]] = []

    checks.append(
        result(
            "README source-preview classification",
            all(
                token in readme
                for token in (
                    "## Release classification, platform support, and security truth",
                    "`source-release` preview",
                    "`compiled_release_validated` as `false`",
                    "Owner Mode",
                    "Roadmap target only",
                )
            ),
            "README states source-preview classification and that Owner Mode is not implemented.",
        )
    )

    checks.append(
        result(
            "README platform matrix truth",
            all(
                token in readme
                for token in (
                    "Linux reference namespace worker",
                    "Windows/macOS execution boundary",
                    "fail closed",
                    "Signed Manifest v2 is not yet implemented",
                )
            ),
            "README states Linux reference-worker truth, Windows/macOS fail-closed status, and manifest-trust freeze.",
        )
    )

    checks.append(
        result(
            "SECURITY supported line and freeze",
            all(
                token in security
                for token in (
                    "Kristin Local Agent v1.9.0+190",
                    "`source-release`",
                    "v1 signed-manifest trust is disabled",
                    "Signed Manifest v2 is not implemented yet",
                )
            ),
            "SECURITY.md targets v1.9.0+190 and documents the interop freeze.",
        )
    )

    checks.append(
        result(
            "SECURITY platform truth",
            all(
                token in security
                for token in (
                    "Linux namespace worker",
                    "Windows",
                    "macOS",
                    "Not implemented; fail closed",
                    "Owner Mode / unrestricted full-host authority",
                )
            ),
            "SECURITY.md includes an explicit platform/authority table.",
        )
    )

    checks.append(
        result(
            "Security model uses SQLite truth",
            "SQLite is the authoritative local workflow store" in security_model
            and "Atomic JSON files serialize updates within a collection." not in security_model,
            "docs/SECURITY_MODEL.md reflects the current SQLite workflow authority and removes stale JSON-authority wording.",
        )
    )

    checks.append(
        result(
            "Threat model includes manifest and interop threats",
            all(
                token in threat_model
                for token in (
                    "A forged signed manifest",
                    "MCP, A2A, or manifest supply-chain substitution",
                    "v1 signed-manifest trust path disabled",
                )
            ),
            "docs/THREAT_MODEL.md includes manifest/interop substitution threats and the current trust freeze.",
        )
    )

    checks.append(
        result(
            "Support policy exists",
            all(
                token in support
                for token in (
                    "# Support policy",
                    "`source-release` preview",
                    "Owner Mode / unrestricted host authority",
                    "Source-only validation commands",
                )
            ),
            "docs/SUPPORT_POLICY.md defines the supported artifact and reporting boundary.",
        )
    )

    checks.append(
        result(
            "Release metadata agrees",
            release.get("classification") == "source-release"
            and release.get("compiled_release_validated") is False
            and release.get("release_channel") == "preview"
            and release.get("owner_mode_implemented") is False
            and release.get("signed_manifest_v1_trust_enabled") is False
            and release.get("signed_manifest_v2_implemented") is False,
            "RELEASE.json exposes the same source-preview and interop-freeze truth.",
        )
    )

    checks.append(
        result(
            "Release metadata platform truth",
            isinstance(release.get("platform_support_matrix"), dict)
            and release["platform_support_matrix"].get("linux_namespace_worker") == "reference_worker_when_available"
            and release["platform_support_matrix"].get("windows_native_worker") == "not_implemented_fail_closed"
            and release["platform_support_matrix"].get("macos_native_worker") == "not_implemented_fail_closed",
            "RELEASE.json records Linux reference-worker support and Windows/macOS fail-closed status.",
        )
    )

    checks.append(
        result(
            "UI developer page agrees with docs",
            all(
                token in ui
                for token in (
                    "Classification: source-release preview",
                    "Owner Mode: roadmap target only in this source release",
                    "Workers: Linux reference worker when available; Windows/macOS native workers fail closed",
                    "Support boundary: reviewed source tree and source-only gates",
                    "Audit, release boundary, and support",
                )
            ),
            "Advanced UI shows the same classification, Owner Mode status, and platform truth as the docs.",
        )
    )

    passed_count = sum(1 for item in checks if item["passed"])
    payload = {
        "milestone": "P0-005",
        "caseCount": len(checks),
        "passedCount": passed_count,
        "passed": passed_count == len(checks),
        "results": checks,
    }
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
