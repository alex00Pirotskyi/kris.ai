#!/usr/bin/env python3
"""Activate an installed P1A connector only from the exact merged V63 graph.

The platform installer deliberately writes a completion-ineligible connector
configuration.  After the P1A evidence commit is squash-merged and exact
merged-main CI passes, this tool re-validates the committed signed evidence
and atomically writes a public, completion-eligible provenance block.  It
never reads or writes private signing material, grant credentials, approval
credentials, policy mutation state, or worker secrets.
"""
from __future__ import annotations

import argparse
import errno
import hashlib
import json
import os
import pathlib
import stat
import sys
import tempfile
from typing import Any

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from p1a_platform_evidence import COMPONENTS, validate_platform_receipt
from p1a_signed_evidence import HEX40, HEX64, load_object, sha256_file

PLATFORMS = ("windows", "macos", "linux")


def _safe_relative(value: object, label: str) -> pathlib.PurePosixPath:
    rel = pathlib.PurePosixPath(str(value or ""))
    if not str(rel) or rel.is_absolute() or ".." in rel.parts:
        raise SystemExit(f"{label}: unsafe relative path")
    return rel


def _object(value: object, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise SystemExit(f"{label}: object required")
    return dict(value)


def _component(
    receipt_path: pathlib.Path,
    receipt: dict[str, Any],
    name: str,
) -> tuple[pathlib.Path, dict[str, Any]]:
    artifact_root = (
        receipt_path.parent / _safe_relative(receipt.get("artifactRoot"), "artifactRoot")
    ).resolve()
    row = _object(receipt.get(name), name)
    path = (artifact_root / _safe_relative(row.get("path"), name)).resolve()
    if artifact_root not in path.parents or not path.is_file() or path.is_symlink():
        raise SystemExit(f"{name}: component unavailable")
    if sha256_file(path) != row.get("sha256"):
        raise SystemExit(f"{name}: component digest mismatch")
    return path, load_object(path)


def _hex(value: object, length: int, label: str) -> str:
    text = str(value or "").lower()
    pattern = HEX40 if length == 40 else HEX64
    if not pattern.fullmatch(text):
        raise SystemExit(f"{label}: exact hexadecimal digest required")
    return text


def _fsync_parent_directory(directory: pathlib.Path) -> None:
    """Durably persist a rename where the host supports directory fsync.

    Windows does not expose directory handles through ``os.open``. The file
    itself is flushed before ``os.replace``, and the replacement remains
    atomic because the temporary file is created in the destination directory.
    POSIX hosts additionally fsync the parent directory when supported.
    """

    if os.name == "nt":
        return
    flags = os.O_RDONLY
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    try:
        directory_fd = os.open(str(directory), flags)
    except OSError as error:
        if error.errno in {errno.EINVAL, errno.ENOTSUP, errno.EACCES, errno.EPERM}:
            return
        raise
    try:
        try:
            os.fsync(directory_fd)
        except OSError as error:
            if error.errno not in {errno.EINVAL, errno.ENOTSUP, errno.EBADF}:
                raise
    finally:
        os.close(directory_fd)


def _atomic_write(path: pathlib.Path, value: dict[str, Any]) -> None:
    if path.exists() and path.is_symlink():
        raise SystemExit("connector configuration symlink forbidden")
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8")
    fd, temporary = tempfile.mkstemp(
        prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent)
    )
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, stat.S_IRUSR | stat.S_IWUSR)
        os.replace(temporary, path)
        _fsync_parent_directory(path.parent)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def activate(args: argparse.Namespace) -> dict[str, Any]:
    project = pathlib.Path(args.project).resolve()
    config_path = pathlib.Path(args.connector_config).resolve()
    if not config_path.is_file() or config_path.is_symlink():
        raise SystemExit("installed connector configuration unavailable")
    config_bytes = config_path.read_bytes()
    config = json.loads(config_bytes)
    if not isinstance(config, dict) or config.get("schemaVersion") != "2.0.0":
        raise SystemExit("installed connector configuration identity invalid")
    endpoint = _object(config.get("endpoint"), "endpoint")
    platform = str(endpoint.get("platform", ""))
    if platform not in PLATFORMS:
        raise SystemExit("installed connector platform invalid")
    if config.get("completionEligible") is True:
        raise SystemExit("connector is already completion eligible; refuse silent rewrite")

    manifest_path = pathlib.Path(args.aggregate_manifest).resolve()
    manifest = load_object(manifest_path)
    required_manifest = {
        "schemaVersion": "3.0.0",
        "phase": "P1A",
        "status": "passed",
        "completionClaim": True,
        "p2DependencySatisfied": True,
        "independentSecurityReview": "approved",
        "ownerApproval": "approved",
    }
    for key, expected in required_manifest.items():
        if manifest.get(key) != expected:
            raise SystemExit(f"merged P1A aggregate invalid: {key}")
    commit = _hex(manifest.get("reviewedCommit"), 40, "reviewedCommit")
    tree = _hex(manifest.get("reviewedTree"), 40, "reviewedTree")
    package_sha = _hex(manifest.get("packageSha256"), 64, "packageSha256")
    if args.expected_merged_commit and commit != args.expected_merged_commit.lower():
        raise SystemExit("merged P1A commit does not match expected protected-main commit")
    if manifest.get("platformEvidence") != {item: "passed" for item in PLATFORMS}:
        raise SystemExit("merged P1A tri-platform status invalid")

    receipt_paths = _object(manifest.get("platformReceiptPath"), "platformReceiptPath")
    trust_relative = _safe_relative(manifest.get("evidenceTrustPath"), "evidenceTrustPath")
    receipt_path = (
        pathlib.Path(args.platform_receipt).resolve()
        if args.platform_receipt
        else (project / _safe_relative(receipt_paths.get(platform), "platformReceiptPath")).resolve()
    )
    trust_path = (
        pathlib.Path(args.evidence_trust).resolve()
        if args.evidence_trust
        else (project / trust_relative).resolve()
    )
    for label, path in (("platform receipt", receipt_path), ("evidence trust", trust_path)):
        if not path.is_file() or path.is_symlink():
            raise SystemExit(f"{label} unavailable")

    receipt = validate_platform_receipt(
        receipt_path,
        commit=commit,
        tree=tree,
        package_sha256=package_sha,
        trust_path=trust_path,
        allow_synthetic=False,
        openssl_executable=args.openssl,
        require_live_github_success=False,
    )
    receipt_digest = sha256_file(receipt_path)
    platform_digests = _object(manifest.get("platformReceiptSha256"), "platformReceiptSha256")
    if platform_digests.get(platform) != receipt_digest:
        raise SystemExit("merged P1A platform receipt digest mismatch")
    trust_digest = sha256_file(trust_path)
    if manifest.get("evidenceTrustSha256") != trust_digest:
        raise SystemExit("merged P1A evidence trust digest mismatch")

    components = {name: _component(receipt_path, receipt, name) for name in COMPONENTS}
    build = components["buildProvenance"][1]
    installer = components["installerReceipt"][1]
    service = components["serviceBehaviorReceipt"][1]
    denial = components["workerDenialReceipt"][1]

    service_build = _hex(
        build.get("serviceBinarySha256")
        or service.get("serviceBuildSha256")
        or service.get("serviceBinarySha256"),
        64,
        "serviceBinarySha256",
    )
    connector_sha = _hex(
        build.get("connectorLibrarySha256") or installer.get("connectorLibrarySha256"),
        64,
        "connectorLibrarySha256",
    )
    installer_sha = _hex(
        build.get("installerSha256") or installer.get("installerSha256"),
        64,
        "installerSha256",
    )
    worker_launcher_sha = _hex(
        denial.get("launcherSha256") or build.get("workerLauncherSha256"),
        64,
        "workerLauncherSha256",
    )
    worker_executable_sha = _hex(
        denial.get("workerExecutableSha256"), 64, "workerExecutableSha256"
    )
    worker_identity_sha = _hex(
        denial.get("workerIdentitySha256"), 64, "workerIdentitySha256"
    )
    denial_transcript_sha = _hex(
        denial.get("denialTranscriptSha256"), 64, "denialTranscriptSha256"
    )

    expected_endpoint = {
        "serviceBuildSha256": service_build,
        "connectorLibrarySha256": connector_sha,
        "installerSha256": installer_sha,
    }
    for key, expected in expected_endpoint.items():
        if str(endpoint.get(key, "")).lower() != expected:
            raise SystemExit(f"installed connector endpoint digest mismatch: {key}")
    if service.get("serviceInstanceId") != endpoint.get("serviceInstanceId"):
        raise SystemExit("installed connector service instance mismatch")

    provenance = _object(config.get("provenance"), "provenance")
    if provenance.get("authorityType") != "p1-isolated-authority-service-v2":
        raise SystemExit("installed connector authority type invalid")
    policy_snapshot_sha = _hex(
        provenance.get("policySnapshotSha256"), 64, "policySnapshotSha256"
    )

    activated = dict(config)
    activated["completionEligible"] = True
    activated["provenance"] = {
        "authorityType": "p1-isolated-authority-service-v2",
        "runtimeEligible": True,
        "securityIsolationActive": True,
        "activationType": "merged-p1a-v63-signed-evidence-activation",
        "p1AmendmentMerged": True,
        "p1AmendmentSchemaVersion": "3.0.0",
        "independentP1aSecurityReviewApproved": True,
        "workerDenialTriPlatformPassed": True,
        "behavioralWindowsPassed": True,
        "behavioralMacosPassed": True,
        "behavioralLinuxPassed": True,
        "mergedCommit": commit,
        "mergedTree": tree,
        "aggregateManifestSha256": sha256_file(manifest_path),
        "platformReceiptSha256": receipt_digest,
        "evidenceTrustSha256": trust_digest,
        "serviceBehaviorReceiptSha256": str(receipt["serviceBehaviorReceipt"]["sha256"]),
        "workerDenialReceiptSha256": str(receipt["workerDenialReceipt"]["sha256"]),
        "workerLauncherSha256": worker_launcher_sha,
        "workerExecutableSha256": worker_executable_sha,
        "workerIdentitySha256": worker_identity_sha,
        "denialTranscriptSha256": denial_transcript_sha,
        "p1aPackageSha256": package_sha,
        "policySnapshotSha256": policy_snapshot_sha,
        "connectorConfigPreActivationSha256": hashlib.sha256(config_bytes).hexdigest(),
        "privateAuthorityMaterialPresent": False,
        "arbitraryMessageSigningApi": False,
        "completionEligible": True,
    }
    output = pathlib.Path(args.output).resolve() if args.output else config_path
    if output != config_path and output.exists() and output.is_symlink():
        raise SystemExit("connector output symlink forbidden")
    _atomic_write(output, activated)
    return {
        "schemaVersion": "1.0.0",
        "activationType": "p1a-merged-installation-activation-v63",
        "status": "passed",
        "platform": platform,
        "connectorConfig": str(output),
        "connectorConfigSha256": sha256_file(output),
        "mergedCommit": commit,
        "mergedTree": tree,
        "aggregateManifestSha256": sha256_file(manifest_path),
        "platformReceiptSha256": receipt_digest,
        "evidenceTrustSha256": trust_digest,
        "completionEligible": True,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--connector-config", required=True)
    parser.add_argument("--aggregate-manifest", required=True)
    parser.add_argument("--platform-receipt")
    parser.add_argument("--evidence-trust")
    parser.add_argument("--expected-merged-commit")
    parser.add_argument("--output")
    parser.add_argument("--openssl", default="openssl")
    args = parser.parse_args()
    print(json.dumps(activate(args), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
