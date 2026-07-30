#!/usr/bin/env python3
"""Contract test for post-merge activation of an installed P1A connector.

Cryptographic receipt validation is covered by p1a_platform_evidence and its
forgery tests. This test isolates activation semantics: exact merged graph,
installed binary binding, atomic public provenance, and tamper rejection.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import pathlib
import tempfile

import p1a_activate_merged_installation as activation


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dump(path: pathlib.Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def expect_rejected(callable_value, label: str) -> None:
    try:
        callable_value()
    except SystemExit:
        return
    raise SystemExit(f"{label}: activation tamper accepted")


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="p1a-activation-v63-") as raw:
        root = pathlib.Path(raw)
        project = root / "project"
        receipt_dir = project / "release/evidence/P1A/platforms" / ("a" * 40) / "linux"
        artifact = receipt_dir / "artifact"
        artifact.mkdir(parents=True)
        installed = root / "installed"
        installed.mkdir()
        service_binary = installed / "service"
        connector_library = installed / "connector.so"
        installer = installed / "installer.sh"
        worker_launcher = installed / "worker-launcher"
        worker_executable = installed / "node"
        for path, body in (
            (service_binary, b"service-v63"),
            (connector_library, b"connector-v63"),
            (installer, b"installer-v63"),
            (worker_launcher, b"launcher-v63"),
            (worker_executable, b"node-v63"),
        ):
            path.write_bytes(body)

        components = {
            "buildProvenance": {
                "serviceBinarySha256": sha(service_binary),
                "connectorLibrarySha256": sha(connector_library),
                "installerSha256": sha(installer),
                "workerLauncherSha256": sha(worker_launcher),
            },
            "installerReceipt": {
                "connectorLibrarySha256": sha(connector_library),
                "installerSha256": sha(installer),
            },
            "serviceBehaviorReceipt": {
                "serviceInstanceId": "p1a-linux-v63",
                "serviceBuildSha256": sha(service_binary),
            },
            "workerDenialReceipt": {
                "launcherSha256": sha(worker_launcher),
                "workerExecutableSha256": sha(worker_executable),
                "workerIdentitySha256": "4" * 64,
                "denialTranscriptSha256": "5" * 64,
            },
        }
        rows: dict[str, dict[str, str]] = {}
        for name, value in components.items():
            path = artifact / f"{name}.json"
            dump(path, value)
            rows[name] = {"path": path.relative_to(artifact).as_posix(), "sha256": sha(path)}
        # Activation only reads these four components, but the receipt carries the
        # complete production component namespace.
        for name in activation.COMPONENTS:
            if name not in rows:
                path = artifact / f"{name}.json"
                dump(path, {"status": "passed"})
                rows[name] = {"path": path.relative_to(artifact).as_posix(), "sha256": sha(path)}
        receipt = {"artifactRoot": "artifact", **rows}
        receipt_path = receipt_dir / "receipt.json"
        dump(receipt_path, receipt)
        trust_path = project / "release/evidence/P1A/EVIDENCE_TRUST.json"
        dump(trust_path, {"schemaVersion": "1.0.0", "trustType": "p1a-evidence-trust-v1"})

        commit, tree, package = "a" * 40, "b" * 40, "c" * 64
        manifest_path = project / "release/evidence/P1A/manifest.json"
        manifest = {
            "schemaVersion": "3.0.0",
            "phase": "P1A",
            "status": "passed",
            "completionClaim": True,
            "p2DependencySatisfied": True,
            "independentSecurityReview": "approved",
            "ownerApproval": "approved",
            "reviewedCommit": commit,
            "reviewedTree": tree,
            "packageSha256": package,
            "platformEvidence": {item: "passed" for item in activation.PLATFORMS},
            "platformReceiptPath": {"linux": receipt_path.relative_to(project).as_posix()},
            "platformReceiptSha256": {"linux": sha(receipt_path)},
            "evidenceTrustPath": trust_path.relative_to(project).as_posix(),
            "evidenceTrustSha256": sha(trust_path),
        }
        dump(manifest_path, manifest)

        config_path = root / "connector-v2.json"
        config = {
            "schemaVersion": "2.0.0",
            "connectorLibraryPath": str(connector_library),
            "completionEligible": False,
            "endpoint": {
                "platform": "linux",
                "transport": "linux-af-unix",
                "address": "/run/kristin-p1a/authority.sock",
                "serviceInstanceId": "p1a-linux-v63",
                "serviceBuildSha256": sha(service_binary),
                "connectorLibrarySha256": sha(connector_library),
                "installerSha256": sha(installer),
                "serverIdentity": {"serviceUid": 301, "desktopUid": 1000, "workerUid": 302, "workerGid": 302},
                "osEnforcedIsolation": True,
                "workerPrincipalSeparated": True,
                "typedOperationsOnly": True,
                "nonExportableKeys": True,
            },
            "provenance": {
                "authorityType": "p1-isolated-authority-service-v2",
                "policySnapshotSha256": "6" * 64,
            },
        }
        dump(config_path, config)

        # Windows cannot open a directory with os.open. Prove the atomic writer
        # bypasses parent-directory fsync there while preserving same-directory
        # atomic replacement and file flushing.
        windows_atomic_path = root / "windows-atomic.json"
        original_os_name = activation.os.name
        original_os_open = activation.os.open
        def guarded_os_open(path_value, *open_args, **open_kwargs):
            if pathlib.Path(path_value) == windows_atomic_path.parent:
                raise AssertionError("Windows path attempted directory os.open")
            return original_os_open(path_value, *open_args, **open_kwargs)
        activation.os.name = "nt"
        activation.os.open = guarded_os_open
        try:
            activation._atomic_write(windows_atomic_path, {"status": "passed"})
            assert json.loads(windows_atomic_path.read_text(encoding="utf-8")) == {
                "status": "passed"
            }
        finally:
            activation.os.open = original_os_open
            activation.os.name = original_os_name

        original_validator = activation.validate_platform_receipt
        activation.validate_platform_receipt = lambda *args, **kwargs: copy.deepcopy(receipt)
        try:
            args = argparse.Namespace(
                project=str(project),
                connector_config=str(config_path),
                aggregate_manifest=str(manifest_path),
                platform_receipt=str(receipt_path),
                evidence_trust=str(trust_path),
                expected_merged_commit=commit,
                output=None,
                openssl="openssl",
            )
            result = activation.activate(args)
            activated = json.loads(config_path.read_text(encoding="utf-8"))
            provenance = activated["provenance"]
            assert result["status"] == "passed" and activated["completionEligible"] is True
            assert provenance["mergedCommit"] == commit and provenance["mergedTree"] == tree
            assert provenance["aggregateManifestSha256"] == sha(manifest_path)
            assert provenance["platformReceiptSha256"] == sha(receipt_path)
            assert provenance["evidenceTrustSha256"] == sha(trust_path)
            assert provenance["workerLauncherSha256"] == sha(worker_launcher)
            assert provenance["workerExecutableSha256"] == sha(worker_executable)
            assert provenance["privateAuthorityMaterialPresent"] is False
            assert provenance["arbitraryMessageSigningApi"] is False

            # Activation is one-way and cannot silently overwrite an active graph.
            expect_rejected(lambda: activation.activate(args), "repeat")

            bad_config = copy.deepcopy(config)
            bad_config["endpoint"]["serviceBuildSha256"] = "f" * 64
            bad_path = root / "bad-connector.json"
            dump(bad_path, bad_config)
            bad_args = copy.copy(args)
            bad_args.connector_config = str(bad_path)
            expect_rejected(lambda: activation.activate(bad_args), "installed-binary-digest")

            bad_manifest = copy.deepcopy(manifest)
            bad_manifest["status"] = "blocked"
            bad_manifest_path = root / "bad-manifest.json"
            dump(bad_manifest_path, bad_manifest)
            bad_manifest_args = copy.copy(args)
            bad_manifest_args.connector_config = str(root / "fresh-connector.json")
            dump(pathlib.Path(bad_manifest_args.connector_config), config)
            bad_manifest_args.aggregate_manifest = str(bad_manifest_path)
            expect_rejected(lambda: activation.activate(bad_manifest_args), "aggregate-status")
        finally:
            activation.validate_platform_receipt = original_validator
    print("P1A V63 merged-installation activation contract: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
