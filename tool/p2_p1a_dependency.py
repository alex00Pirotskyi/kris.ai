#!/usr/bin/env python3
"""Public-only verifier for the merged P1A V63 evidence graph.

This module is deliberately verification-only. It accepts no private key,
protected handle, policy mutation, grant issuance, or signing operation. P2
uses it to prove that its already-merged P1A dependency contains the exact
signed platform graph that closed P1A before a controlled P2 runner is trusted.
"""
from __future__ import annotations

import base64
import hashlib
import json
import pathlib
import re
import subprocess
from typing import Any

HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
PLATFORMS = ("windows", "macos", "linux")
COMPONENTS = (
    "runnerAttestation",
    "buildProvenance",
    "installerReceipt",
    "keyProviderReceipt",
    "workerDenialReceipt",
    "serviceBehaviorReceipt",
    "cleanupReceipt",
    "githubApiVerification",
)
SIGNED_PURPOSES = {
    "runnerAttestation": "p1a-runner-attestation-receipt",
    "buildProvenance": "p1a-build-provenance",
    "installerReceipt": "p1a-installer-receipt",
    "keyProviderReceipt": "p1a-key-provider-receipt",
    "workerDenialReceipt": "p1a-worker-denial-receipt",
    "cleanupReceipt": "p1a-cleanup-receipt",
    "githubApiVerification": "p1a-github-api-verification",
}
REQUIRED_SERVICE_EVENTS = {
    "desktop-authenticated",
    "owner-approval-recorded",
    "effect-authorized",
    "effect-outcome-recorded",
    "request-replay-denied",
    "service-restarted",
}


def canonical(value: object) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load_object(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:  # pragma: no cover - error text only
        raise SystemExit(f"{path}: invalid JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise SystemExit(f"{path}: JSON object required")
    return value


def canonical_directory_digest(root: pathlib.Path) -> str:
    h = hashlib.sha256()
    for path in sorted(
        (item for item in root.rglob("*") if item.is_file()),
        key=lambda item: item.relative_to(root).as_posix(),
    ):
        relative = path.relative_to(root).as_posix().encode("utf-8")
        data = path.read_bytes()
        h.update(len(relative).to_bytes(8, "big"))
        h.update(relative)
        h.update(len(data).to_bytes(8, "big"))
        h.update(hashlib.sha256(data).digest())
    return h.hexdigest()


def _safe_component(root: pathlib.Path, row: object, label: str) -> tuple[pathlib.Path, dict[str, Any]]:
    if not isinstance(row, dict):
        raise SystemExit(f"P1A {label}: component row required")
    relative = pathlib.PurePosixPath(str(row.get("path", "")))
    digest = str(row.get("sha256", ""))
    if (
        not str(relative)
        or relative.is_absolute()
        or ".." in relative.parts
        or not HEX64.fullmatch(digest)
    ):
        raise SystemExit(f"P1A {label}: unsafe component binding")
    path = (root / relative).resolve()
    if root.resolve() not in path.parents or not path.is_file() or path.is_symlink():
        raise SystemExit(f"P1A {label}: component unavailable")
    if sha256_file(path) != digest:
        raise SystemExit(f"P1A {label}: component digest mismatch")
    return path, load_object(path)


def _trusted_key(trust: dict[str, Any], key_id: str, purpose: str, platform: str) -> dict[str, Any]:
    if trust.get("schemaVersion") != "1.0.0" or trust.get("trustType") != "p1a-evidence-trust-v1":
        raise SystemExit("P1A evidence trust identity invalid")
    rows = [
        row
        for row in trust.get("keys", [])
        if isinstance(row, dict) and row.get("keyId") == key_id
    ]
    if len(rows) != 1:
        raise SystemExit("P1A evidence signer is not uniquely trusted")
    row = rows[0]
    if row.get("algorithm") != "ed25519":
        raise SystemExit("P1A evidence signer algorithm invalid")
    if purpose not in row.get("purposes", []):
        raise SystemExit("P1A evidence signer purpose is not trusted")
    if platform not in row.get("platforms", []):
        raise SystemExit("P1A evidence signer platform is not trusted")
    return row


def _node_verify(
    *, algorithm: str, public_key_b64: str, message: bytes, signature_b64: str
) -> None:
    script = r"""
const crypto=require('crypto');
const [algorithm,pub,msg,sig]=process.argv.slice(1);
const publicBytes=Buffer.from(pub,'base64');
const key=algorithm==='ed25519'
  ? crypto.createPublicKey({key:Buffer.concat([Buffer.from('302a300506032b6570032100','hex'),publicBytes]),format:'der',type:'spki'})
  : crypto.createPublicKey({key:publicBytes,format:'der',type:'spki'});
const ok=algorithm==='ed25519'
  ? crypto.verify(null,Buffer.from(msg,'base64'),key,Buffer.from(sig,'base64'))
  : crypto.verify('sha256',Buffer.from(msg,'base64'),key,Buffer.from(sig,'base64'));
process.exit(ok?0:3);
"""
    result = subprocess.run(
        [
            "node",
            "-e",
            script,
            algorithm,
            public_key_b64,
            base64.b64encode(message).decode("ascii"),
            signature_b64,
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise SystemExit("P1A evidence signature invalid")


def _unsigned(document: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in document.items() if key != "signature"}


def verify_ed25519_document(
    document: dict[str, Any], trust: dict[str, Any], *, purpose: str, platform: str
) -> None:
    signature = document.get("signature")
    if (
        not isinstance(signature, dict)
        or signature.get("algorithm") != "ed25519"
        or signature.get("purpose") != purpose
    ):
        raise SystemExit("P1A signed component metadata invalid")
    key_id = str(signature.get("keyId", ""))
    row = _trusted_key(trust, key_id, purpose, platform)
    message = canonical(_unsigned(document))
    signed_digest = str(signature.get("signedSha256", ""))
    if not HEX64.fullmatch(signed_digest) or hashlib.sha256(message).hexdigest() != signed_digest:
        raise SystemExit("P1A signed component digest invalid")
    public_key = str(row.get("publicKeyBase64", ""))
    signature_b64 = str(signature.get("signatureBase64", ""))
    if len(public_key) < 40 or len(signature_b64) < 40:
        raise SystemExit("P1A signed component key/signature shape invalid")
    _node_verify(
        algorithm="ed25519",
        public_key_b64=public_key,
        message=message,
        signature_b64=signature_b64,
    )


def verify_service_receipt(document: dict[str, Any]) -> None:
    signature = document.get("signature")
    if (
        not isinstance(signature, dict)
        or signature.get("algorithm") != "ecdsa-p256-sha256"
        or signature.get("nonExportable") is not True
        or signature.get("privateExportDenied") is not True
    ):
        raise SystemExit("P1A service receipt non-exportable-key attestation invalid")
    public_key = str(signature.get("publicKeySpkiBase64", ""))
    signature_b64 = str(signature.get("signatureBase64", ""))
    provider_attestation = str(signature.get("providerAttestationSha256", ""))
    if len(public_key) < 80 or len(signature_b64) < 40 or not HEX64.fullmatch(provider_attestation):
        raise SystemExit("P1A service receipt signature shape invalid")
    _node_verify(
        algorithm="ecdsa-p256-sha256",
        public_key_b64=public_key,
        message=canonical(_unsigned(document)),
        signature_b64=signature_b64,
    )


def validate_merged_p1a_graph(
    *,
    project_root: pathlib.Path,
    platform: str,
    evidence_root: pathlib.Path,
    merged_manifest_path: pathlib.Path,
    platform_receipt_path: pathlib.Path,
    evidence_trust_path: pathlib.Path,
    enforce_manifest_path: bool = True,
) -> dict[str, Any]:
    if platform not in PLATFORMS:
        raise SystemExit("P1A platform invalid")
    project_root = project_root.resolve()
    evidence_root = evidence_root.resolve()
    paths = {
        "manifest": merged_manifest_path.resolve(),
        "receipt": platform_receipt_path.resolve(),
        "trust": evidence_trust_path.resolve(),
    }
    for label, path in paths.items():
        if not path.is_file() or path.is_symlink():
            raise SystemExit(f"P1A {label} unavailable")
        try:
            path.relative_to(evidence_root)
        except ValueError as exc:
            raise SystemExit(f"P1A {label} escapes evidence root") from exc

    manifest = load_object(paths["manifest"])
    expected_manifest = {
        "schemaVersion": "3.0.0",
        "phase": "P1A",
        "status": "passed",
        "completionClaim": True,
        "p2DependencySatisfied": True,
        "independentSecurityReview": "approved",
        "ownerApproval": "approved",
    }
    for key, value in expected_manifest.items():
        if manifest.get(key) != value:
            raise SystemExit(f"merged P1A manifest invalid: {key}")
    commit = str(manifest.get("reviewedCommit", ""))
    tree = str(manifest.get("reviewedTree", ""))
    package_sha = str(manifest.get("packageSha256", ""))
    if not HEX40.fullmatch(commit) or not HEX40.fullmatch(tree) or not HEX64.fullmatch(package_sha):
        raise SystemExit("merged P1A source/package identity invalid")
    if manifest.get("platformEvidence") != {item: "passed" for item in PLATFORMS}:
        raise SystemExit("merged P1A tri-platform status invalid")
    required_jobs = {
        "p1a-behavioral-windows",
        "p1a-behavioral-macos",
        "p1a-behavioral-linux",
    }
    if set(manifest.get("requiredWorkflowJobs", [])) != required_jobs:
        raise SystemExit("merged P1A behavioral workflow contract invalid")

    receipt_digest = sha256_file(paths["receipt"])
    receipt_digests = manifest.get("platformReceiptSha256")
    if not isinstance(receipt_digests, dict) or receipt_digests.get(platform) != receipt_digest:
        raise SystemExit("merged P1A platform receipt digest mismatch")
    receipt_paths = manifest.get("platformReceiptPath")
    if not isinstance(receipt_paths, dict):
        raise SystemExit("merged P1A platform receipt path graph missing")
    expected_receipt = (project_root / pathlib.PurePosixPath(str(receipt_paths.get(platform, "")))).resolve()
    if enforce_manifest_path and expected_receipt != paths["receipt"]:
        raise SystemExit("merged P1A platform receipt path mismatch")
    if manifest.get("evidenceTrustSha256") != sha256_file(paths["trust"]):
        raise SystemExit("merged P1A evidence trust digest mismatch")

    trust = load_object(paths["trust"])
    receipt = load_object(paths["receipt"])
    expected_receipt_identity = {
        "schemaVersion": "3.0.0",
        "receiptType": "p1a-platform-behavioral-v3",
        "phase": "P1A",
        "platform": platform,
        "sourceCommit": commit,
        "sourceTree": tree,
        "packageSha256": package_sha,
        "status": "passed",
        "sourceOnly": False,
        "completionEligible": True,
        "syntheticContractFixture": False,
    }
    for key, value in expected_receipt_identity.items():
        if receipt.get(key) != value:
            raise SystemExit(f"merged P1A platform receipt invalid: {key}")
    exact = receipt.get("exactBinding")
    if not isinstance(exact, dict) or exact.get("sourceCommit") != commit or exact.get("sourceTree") != tree or exact.get("platform") != platform:
        raise SystemExit("merged P1A exact run binding invalid")
    verify_ed25519_document(receipt, trust, purpose="p1a-platform-receipt", platform=platform)

    artifact_relative = pathlib.PurePosixPath(str(receipt.get("artifactRoot", "")))
    if not str(artifact_relative) or artifact_relative.is_absolute() or ".." in artifact_relative.parts:
        raise SystemExit("merged P1A artifact root unsafe")
    artifact_root = (paths["receipt"].parent / artifact_relative).resolve()
    if not artifact_root.is_dir() or artifact_root.is_symlink() or paths["receipt"].parent.resolve() not in artifact_root.parents:
        raise SystemExit("merged P1A artifact root unavailable")
    if receipt.get("artifactDigestAlgorithm") != "canonical-unpacked-v1" or canonical_directory_digest(artifact_root) != receipt.get("artifactSha256"):
        raise SystemExit("merged P1A artifact digest mismatch")

    component_rows: dict[str, tuple[pathlib.Path, dict[str, Any]]] = {
        name: _safe_component(artifact_root, receipt.get(name), name)
        for name in COMPONENTS
    }
    build = component_rows["buildProvenance"][1]
    for key in (
        "serviceBinarySha256", "connectorLibrarySha256", "workerLauncherSha256",
        "installerSha256", "uninstallerSha256", "sourceInventorySha256",
        "reproducibleBuildInputsSha256",
    ):
        if not HEX64.fullmatch(str(build.get(key, ""))):
            raise SystemExit(f"merged P1A native build provenance missing: {key}")
    toolchains = build.get("toolchains")
    if not isinstance(toolchains, dict):
        raise SystemExit("merged P1A governed native toolchains missing")
    for key in ("python", "cmake", "compiler"):
        row = toolchains.get(key)
        if not isinstance(row, dict) or not str(row.get("version", "")).strip() or not HEX64.fullmatch(str(row.get("executableSha256", ""))):
            raise SystemExit(f"merged P1A governed toolchain identity missing: {key}")
    for name, purpose in SIGNED_PURPOSES.items():
        body = component_rows[name][1]
        verify_ed25519_document(body, trust, purpose=purpose, platform=platform)
        if body.get("status") != "passed" or body.get("platform") != platform or body.get("exactBinding") != exact or body.get("completionEligible") is not True:
            raise SystemExit(f"merged P1A {name} binding invalid")

    service = component_rows["serviceBehaviorReceipt"][1]
    if (
        service.get("schemaVersion") != "2.0.0"
        or service.get("receiptType") != "p1a-service-behavior-v2"
        or service.get("sourceCommit") != commit
        or service.get("sourceTree") != tree
        or service.get("exactRunBindingSha256") != receipt.get("exactRunBindingSha256")
        or service.get("completionEligible") is not True
    ):
        raise SystemExit("merged P1A service behavior binding invalid")
    verify_service_receipt(service)
    session = service.get("behaviorSession")
    events = session.get("events") if isinstance(session, dict) else None
    observed = {
        row.get("event") for row in events if isinstance(row, dict)
    } if isinstance(events, list) else set()
    if not REQUIRED_SERVICE_EVENTS.issubset(observed):
        raise SystemExit("merged P1A service event proof incomplete")
    required_service_claims = {
        "typedOperationsOnly": True,
        "arbitraryMessageSigningApi": False,
        "policyValidatedInsideService": True,
        "grantIssuedInsideService": True,
        "grantValidatedInsideService": True,
        "useConsumedInsideService": True,
        "revocationCheckedInsideService": True,
        "auditAppendedInsideService": True,
        "replayAfterRestartDenied": True,
        "nonExportableKey": True,
    }
    if any(service.get(key) is not value for key, value in required_service_claims.items()):
        raise SystemExit("merged P1A service authority claims incomplete")

    key_provider = component_rows["keyProviderReceipt"][1]
    if (
        key_provider.get("providerBacked") is not True
        or key_provider.get("privateExportAttempted") is not True
        or key_provider.get("privateExportDenied") is not True
        or key_provider.get("serviceOnlyAclObserved") is not True
    ):
        raise SystemExit("merged P1A key-provider proof incomplete")

    denial = component_rows["workerDenialReceipt"][1]
    installer = component_rows["installerReceipt"][1]
    if (
        installer.get("serviceInstalled") is not True
        or installer.get("separateServiceIdentity") is not True
        or installer.get("connectorInstalled") is not True
        or installer.get("workerLauncherInstalled") is not True
        or installer.get("rollbackAvailable") is not True
    ):
        raise SystemExit("merged P1A installer proof incomplete")
    installer_cross = {
        "installerSha256": build["installerSha256"],
        "uninstallerSha256": build["uninstallerSha256"],
        "installedServiceSha256": build["serviceBinarySha256"],
        "installedConnectorSha256": build["connectorLibrarySha256"],
        "installedWorkerLauncherSha256": build["workerLauncherSha256"],
    }
    for key, value in installer_cross.items():
        if installer.get(key) != value:
            raise SystemExit(f"merged P1A installer/build provenance mismatch: {key}")
    if service.get("serviceBuildSha256") != build["serviceBinarySha256"] and service.get("serviceBinarySha256") != build["serviceBinarySha256"]:
        raise SystemExit("merged P1A service/build provenance mismatch")
    if denial.get("launcherSha256") != build["workerLauncherSha256"]:
        raise SystemExit("merged P1A worker launcher/build provenance mismatch")
    provider_attestation = str(key_provider.get("providerAttestationSha256", ""))
    signing_provenance = str(key_provider.get("signingOperationProvenanceSha256", ""))
    if not HEX64.fullmatch(provider_attestation) or not HEX64.fullmatch(signing_provenance) or not str(key_provider.get("providerName", "")).strip() or not str(key_provider.get("keyId", "")).strip():
        raise SystemExit("merged P1A non-exportable key provider provenance incomplete")
    signature = service.get("signature")
    if not isinstance(signature, dict) or signature.get("providerAttestationSha256") != provider_attestation:
        raise SystemExit("merged P1A service/key-provider attestation mismatch")

    cleanup = component_rows["cleanupReceipt"][1]
    if cleanup.get("uninstallerSha256") != build["uninstallerSha256"] or cleanup.get("postRunCleanup") is not True:
        raise SystemExit("merged P1A cleanup/uninstaller provenance mismatch")
    for key in (
        "serviceUninstalled",
        "workerLauncherRemoved",
        "connectorRemoved",
        "testKeyRemoved",
        "zeroManagedProcesses",
        "zeroOrphanedProcesses",
        "temporaryAuthorityStateRemoved",
    ):
        if cleanup.get(key) is not True:
            raise SystemExit(f"merged P1A cleanup proof missing: {key}")

    github = component_rows["githubApiVerification"][1]
    if (
        github.get("repository") != exact.get("repository")
        or str(github.get("workflowRunId")) != str(exact.get("workflowRunId"))
        or str(github.get("runAttempt")) != str(exact.get("runAttempt"))
        or str(github.get("githubJobId")) != str(exact.get("githubJobId"))
        or github.get("headSha") != commit
        or github.get("statusAtCapture") not in ("in_progress", "completed")
        or github.get("conclusion") not in (None, "success")
    ):
        raise SystemExit("merged P1A GitHub API capture binding invalid")

    required_denial = {
        "productionRestrictedLauncherUsed": True,
        "exactWorkerPrincipalObserved": True,
        "authorityConnectionDenied": True,
        "authorityKeyReadDenied": True,
        "osKeyStoreSigningDenied": True,
        "arbitraryMessageSigningDenied": True,
        "workerIdentityBoundToSession": True,
    }
    if any(denial.get(key) is not value for key, value in required_denial.items()):
        raise SystemExit("merged P1A exact worker denial incomplete")
    for key in (
        "launcherSha256",
        "workerExecutableSha256",
        "workerIdentitySha256",
        "denialTranscriptSha256",
    ):
        if not HEX64.fullmatch(str(denial.get(key, ""))):
            raise SystemExit(f"merged P1A worker denial digest missing: {key}")

    service_build = str(
        build.get("serviceBinarySha256")
        or service.get("serviceBuildSha256")
        or service.get("serviceBinarySha256")
        or ""
    )
    if not HEX64.fullmatch(service_build):
        raise SystemExit("merged P1A service build digest missing")
    service_instance = str(service.get("serviceInstanceId", "")).strip()
    if not service_instance:
        raise SystemExit("merged P1A service instance identity missing")

    graph = manifest.get("platformComponentGraph")
    if not isinstance(graph, dict) or not isinstance(graph.get(platform), dict):
        raise SystemExit("merged P1A component graph missing")
    platform_graph = graph[platform]
    for name in COMPONENTS:
        if platform_graph.get(name) != str(receipt[name]["sha256"]):
            raise SystemExit(f"merged P1A component graph mismatch: {name}")
    if not isinstance(platform_graph.get("liveGithubSuccess"), dict):
        raise SystemExit("merged P1A live GitHub success graph missing")

    return {
        "schemaVersion": "1.0.0",
        "dependencyType": "merged-p1a-v63-signed-platform-graph",
        "platform": platform,
        "mergedManifestSha256": sha256_file(paths["manifest"]),
        "platformReceiptSha256": receipt_digest,
        "evidenceTrustSha256": sha256_file(paths["trust"]),
        "serviceBehaviorReceiptSha256": str(receipt["serviceBehaviorReceipt"]["sha256"]),
        "workerDenialReceiptSha256": str(receipt["workerDenialReceipt"]["sha256"]),
        "serviceBuildSha256": service_build,
        "serviceInstanceId": service_instance,
        "p1aMergedCommit": commit,
        "p1aMergedTree": tree,
        "p1aPackageSha256": package_sha,
        "workerLauncherSha256": denial["launcherSha256"],
        "workerExecutableSha256": denial["workerExecutableSha256"],
        "workerIdentitySha256": denial["workerIdentitySha256"],
        "denialTranscriptSha256": denial["denialTranscriptSha256"],
        "workerIdentity": denial.get("workerIdentity"),
        "exactBinding": exact,
        "componentGraph": {
            name: str(receipt[name]["sha256"]) for name in COMPONENTS
        },
        "liveGithubSuccess": platform_graph["liveGithubSuccess"],
        "completionEligible": True,
        "p2DependencySatisfied": True,
    }
