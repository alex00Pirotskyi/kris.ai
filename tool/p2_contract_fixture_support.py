#!/usr/bin/env python3
"""Synthetic V63 evidence graph for validator regression tests only."""
from __future__ import annotations

import hashlib
import json
import pathlib
import sys

from p2_evidence_contract import (
    PRODUCT_ASSERTION_IDS,
    REQUIRED_ASSERTION_IDS,
    TASKS,
    canonical,
    canonical_directory_digest,
    sha256_file,
)
from p2_p1a_dependency import validate_merged_p1a_graph
from p2_runner_attestation_contract_test import build_p1a_graph


def write_json(path: pathlib.Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _specialized(task: str) -> tuple[dict, dict]:
    rows = {
        "P2-001": ("owner_mode_settings_enable_disable_reset", {"explicitAcknowledgementRequired": True, "fullCurrentAccountLabelObserved": True, "notSandboxLabelObserved": True, "persistentIndicatorObserved": True, "disableResetObserved": True, "settingsPersistedAfterReenable": True}),
        "P2-005": ("interactive_pty_detach_reconnect", {"consumerDetached": True, "outputWhileDetached": True, "backlogReplayExact": True, "noDuplicationOrLoss": True}),
        "P2-006": ("managed_process_tree_kill", {"descendantProcessCreated": True, "identityVerified": True, "activeProcesses": 0, "zeroSurvivingDescendants": True}),
        "P2-007": ("controlled_target_host_package_lifecycle", {"controlledTargetHost": True, "dryRunObserved": True, "installObserved": True, "installedStateObserved": True, "removeObserved": True, "removedStateObserved": True, "executableVersionProvenanceObserved": True}),
        "P2-008": ("controlled_user_service_and_application_lifecycle", {"startObserved": True, "runningObserved": True, "stopObserved": True, "stoppedObserved": True, "applicationOpenObserved": True, "applicationCloseObserved": True, "elevationExercised": False}),
        "P2-009": ("interactive_clipboard_screen_active_window", {"clipboardRoundTrip": True, "screenCaptured": True, "activeWindowObserved": True, "ordinaryLogContentAbsent": True}),
        "P2-010": ("product_snapshot_restore", {"restoredContent": True}),
        "P2-011": ("product_runtime_external_watchdog_kill_during_ui_freeze", {"watchdogAutomaticallyArmed": True, "heartbeatObserved": True, "desktopHeartbeatFrozen": True, "externalKillObserved": True, "identityVerified": True, "activeProcesses": 0, "zeroSurvivingDescendants": True}),
        "P2-012": ("shipped_terminal_workspace_managed_session", {"tabCreatedFromManagedPty": True, "shellAndCwdObserved": True, "runTaskGrantIdentityObserved": True, "searchObserved": True, "accessibilityLabelObserved": True, "keyboardEmergencyActionExposed": True, "interruptObserved": True, "terminateTreeObserved": True}),
        "P2-013": ("production_authority_restart_replay_reconciliation", {"firstDispatchSucceeded": True, "durableConsumptionRecorded": True, "durableStateVersionRecorded": True, "productRuntimeRestarted": True, "replayRejectedAfterRestart": True, "reconciliationObserved": True}),
    }
    kind, post = rows.get(task, ("synthetic_contract_effect", {}))
    return {"kind": kind}, {"observed": True, **post}


def _native(root: pathlib.Path, platform: str) -> dict:
    suffix = ".exe" if platform == "windows" else ""
    native_root = root / "native" / platform
    sources = native_root / "sources"
    sources.mkdir(parents=True, exist_ok=True)
    probe = native_root / f"kristin_native_pty_probe{suffix}"
    lifecycle = native_root / (
        "kristin_job_supervisor.exe" if platform == "windows" else "kristin_posix_watchdog"
    )
    probe.write_bytes(b"probe")
    lifecycle.write_bytes(b"life")
    cmake = sources / "CMakeLists.txt"
    code = sources / "source.c"
    cmake.write_text("# fixture\n", encoding="utf-8")
    code.write_text("/* fixture */\n", encoding="utf-8")
    required = "windowsJobSupervisor" if platform == "windows" else "posixWatchdog"
    manifest = {
        "schemaVersion": "1.0.0",
        "platform": platform,
        "buildSystem": "synthetic-contract-fixture",
        "sourceFiles": [
            {
                "path": item.relative_to(root).as_posix(),
                "sourceRelativePath": item.relative_to(sources).as_posix(),
                "bytes": item.stat().st_size,
                "sha256": sha256_file(item),
            }
            for item in (cmake, code)
        ],
        "binaries": {
            "nativePtyProbe": {"path": probe.relative_to(root).as_posix(), "bytes": probe.stat().st_size, "sha256": sha256_file(probe)},
            required: {"path": lifecycle.relative_to(root).as_posix(), "bytes": lifecycle.stat().st_size, "sha256": sha256_file(lifecycle)},
        },
        "nativePtyProbeReceipt": {"status": "passed", "platform": platform, "syntheticContractFixture": True},
        "syntheticContractFixture": True,
    }
    manifest_path = native_root / "native-runtime-manifest.json"
    write_json(manifest_path, manifest)
    return {**manifest, "manifestPath": manifest_path.relative_to(root).as_posix(), "manifestSha256": sha256_file(manifest_path)}


def _row(root: pathlib.Path, path: pathlib.Path) -> dict:
    return {"path": path.relative_to(root).as_posix(), "sha256": sha256_file(path)}


def build_platform_receipt(
    base: pathlib.Path,
    platform: str,
    commit: str,
    *,
    product_adapter: str = "ProductRuntime/P2SyntheticContractAdapter",
) -> pathlib.Path:
    receipt_dir = base / platform
    root = receipt_dir / "artifact"
    root.mkdir(parents=True, exist_ok=True)
    task_rows: dict[str, dict] = {}
    digest = hashlib.sha256(f"{platform}:{commit}".encode()).hexdigest()

    p1a_project = root / "authority-service-source"
    p1a_paths = build_p1a_graph(
        p1a_project,
        seed=hashlib.sha256(f"p1a:{platform}".encode()).digest(),
        platform_name=platform,
    )
    p1a_summary = validate_merged_p1a_graph(
        project_root=p1a_project,
        platform=platform,
        evidence_root=p1a_paths["evidenceRoot"],
        merged_manifest_path=p1a_paths["manifest"],
        platform_receipt_path=p1a_paths["receipt"],
        evidence_trust_path=p1a_paths["trust"],
    )
    p1a_rows = {
        "mergedManifest": _row(root, p1a_paths["manifest"]),
        "platformReceipt": _row(root, p1a_paths["receipt"]),
        "evidenceTrust": _row(root, p1a_paths["trust"]),
        "evidenceRoot": {"path": p1a_paths["evidenceRoot"].relative_to(root).as_posix()},
    }
    p1a_provenance = {
        "authorityType": "p1-isolated-authority-service-v2",
        "activationType": "merged-p1a-v63-signed-evidence-activation",
        "p1AmendmentMerged": True,
        "p1AmendmentSchemaVersion": "3.0.0",
        "independentP1aSecurityReviewApproved": True,
        "workerDenialTriPlatformPassed": True,
        "behavioralWindowsPassed": True,
        "behavioralMacosPassed": True,
        "behavioralLinuxPassed": True,
        "mergedCommit": p1a_summary["p1aMergedCommit"],
        "mergedTree": p1a_summary["p1aMergedTree"],
        "aggregateManifestSha256": p1a_summary["mergedManifestSha256"],
        "platformReceiptSha256": p1a_summary["platformReceiptSha256"],
        "evidenceTrustSha256": p1a_summary["evidenceTrustSha256"],
        "serviceBehaviorReceiptSha256": p1a_summary["serviceBehaviorReceiptSha256"],
        "workerDenialReceiptSha256": p1a_summary["workerDenialReceiptSha256"],
        "workerLauncherSha256": p1a_summary["workerLauncherSha256"],
        "workerExecutableSha256": p1a_summary["workerExecutableSha256"],
        "workerIdentitySha256": p1a_summary["workerIdentitySha256"],
        "denialTranscriptSha256": p1a_summary["denialTranscriptSha256"],
        "p1aPackageSha256": p1a_summary["p1aPackageSha256"],
        "privateAuthorityMaterialPresent": False,
        "arbitraryMessageSigningApi": False,
        "completionEligible": True,
    }

    for task in TASKS:
        assertions: list[dict] = []
        for assertion_id in sorted(REQUIRED_ASSERTION_IDS[task]):
            product = PRODUCT_ASSERTION_IDS.get(task) == assertion_id
            summary: dict = {"status": "passed"}
            extra: dict = {}
            if product:
                observation_path = root / "product-observations" / platform / task / f"{assertion_id}.json"
                effect, post = _specialized(task)
                authority = {
                    "authorityImplementation": "P1IsolatedAuthorityServiceV2",
                    "authorityKind": "p1-isolated-authority-service-v2",
                    "completionEligible": True,
                    "p1aService": True,
                    "p2AdapterDelegationOnly": True,
                    "p2CanIssueGrants": False,
                    "workerPublicVerifierOnly": True,
                    "workerCanForgeAuthority": False,
                    "workerCanReachAuthoritySigner": False,
                    "workerDeniedByOs": True,
                    "osEnforcedIsolation": True,
                    "workerPrincipalSeparated": True,
                    "typedOperationsOnly": True,
                    "nonExportableKeys": True,
                    "workerReceivesSymmetricAuthorityKeys": False,
                    "workerReceivesPrivateSigningMaterial": False,
                    "serviceInstanceId": p1a_summary["serviceInstanceId"],
                    "serviceBuildSha256": p1a_summary["serviceBuildSha256"],
                    "serviceEndpointAttestationSha256": p1a_summary["platformReceiptSha256"],
                    "p1aPlatformReceiptSha256": p1a_summary["platformReceiptSha256"],
                    "p1aEvidenceTrustSha256": p1a_summary["evidenceTrustSha256"],
                    "p1aServiceBehaviorReceiptSha256": p1a_summary["serviceBehaviorReceiptSha256"],
                    "workerDenialReceiptSha256": p1a_summary["workerDenialReceiptSha256"],
                    "p1aWorkerLauncherSha256": p1a_summary["workerLauncherSha256"],
                    "p1aWorkerExecutableSha256": p1a_summary["workerExecutableSha256"],
                    "p1aWorkerIdentitySha256": p1a_summary["workerIdentitySha256"],
                    "p1aDenialTranscriptSha256": p1a_summary["denialTranscriptSha256"],
                    "p1aPackageSha256": p1a_summary["p1aPackageSha256"],
                    "p1AmendmentManifestSha256": p1a_summary["mergedManifestSha256"],
                    "policyDecisionId": f"policy-{task}",
                    "policyDecisionSha256": digest,
                    "capabilityGrantId": f"grant-{task}",
                    "capabilityGrantSha256": digest,
                    "authenticatedIpcChannelId": "channel",
                    "authenticatedIpcRequestId": f"request-{task}",
                    "authenticatedIpcSha256": digest,
                    "effectPermitSha256": digest,
                    "effectPermitSignerPublicKeySpkiSha256": digest,
                    "auditCheckpointId": f"audit-{task}",
                    "auditCheckpointSha256": digest,
                    "durableConsumptionStateVersion": 1,
                    "durableConsumptionUseNumber": 1,
                    "revocationEpoch": 1,
                    "p1aEvidence": p1a_provenance,
                    "approval": {"completionEligible": True},
                    "protectedKeys": {"kind": "non-exportable-service-owned-keys", "completionEligible": True},
                }
                observation = {
                    "schemaVersion": "2.0.0",
                    "resultType": "p2-shipped-product-observation-v2",
                    "taskId": task,
                    "assertionId": f"p2-{task[3:]}.product-runtime-e2e",
                    "platform": platform,
                    "commitSha": commit,
                    "entryPoint": "ProductRuntime.initialize",
                    "applicationComposition": "ProductRuntime.p2OwnerMode",
                    "applicationCompositionSha256": digest,
                    "authorizationBoundary": "p1-isolated-authority-service-effect-permit-v2",
                    "authority": authority,
                    "productionAdapter": product_adapter,
                    "runnerAttestationSha256": digest,
                    "toolchainExtensionFingerprint": digest,
                    "nativeRuntimeManifestSha256": digest,
                    "osEffect": effect,
                    "postcondition": post,
                    "receipt": {"status": "succeeded", "completionEligible": True, "fixtureAuthority": False, "targetHostOperation": True},
                    "status": "passed",
                    "sourceOnly": False,
                    "fixtureAuthority": False,
                    "completionEligible": True,
                    "startedAt": "2026-07-28T00:00:00Z",
                    "completedAt": "2026-07-28T00:00:01Z",
                    "syntheticContractFixture": True,
                }
                write_json(observation_path, observation)
                extra = {"observationArtifactPath": observation_path.relative_to(root).as_posix(), "observationArtifactSha256": sha256_file(observation_path)}
                summary = {"status": "passed", "taskAssertionId": assertion_id}
            unsigned = {
                "schemaVersion": "1.0.0",
                "assertionId": assertion_id,
                "taskId": task,
                "platform": platform,
                "commitSha": commit,
                "command": [sys.executable, "-c", "raise SystemExit(0)"],
                "testSource": "test/product/p2_shipped_product_runtime_e2e_test.dart" if product else "tool/p2_contract_fixture_support.py",
                "observedStatus": "passed",
                "returnCode": 0,
                "stdoutSha256": hashlib.sha256(b"").hexdigest(),
                "stderrSha256": hashlib.sha256(b"").hexdigest(),
                "durationMs": 1.0,
                "observation": summary,
                "diagnostic": {},
                "syntheticContractFixture": True,
                **extra,
            }
            record = {**unsigned, "resultHash": hashlib.sha256(canonical(unsigned)).hexdigest()}
            evidence_path = root / "assertions" / platform / task / f"{assertion_id}.json"
            write_json(evidence_path, record)
            assertions.append({
                "assertionId": assertion_id,
                "taskId": task,
                "platform": platform,
                "command": record["command"],
                "testSource": record["testSource"],
                "observedStatus": "passed",
                "returnCode": 0,
                "resultHash": record["resultHash"],
                "evidencePath": evidence_path.relative_to(root).as_posix(),
                "evidenceSha256": sha256_file(evidence_path),
                **extra,
            })
        task_path = root / "task-results" / platform / f"{task}.json"
        task_body = {"schemaVersion": "1.0.0", "resultType": "p2-task-observed-result-v1", "taskId": task, "platform": platform, "commitSha": commit, "generatedAt": "2026-07-28T00:00:00Z", "status": "passed", "sourceOnly": False, "productPathRequired": task in PRODUCT_ASSERTION_IDS, "assertions": assertions, "syntheticContractFixture": True}
        write_json(task_path, task_body)
        task_rows[task] = {"status": "passed", "sourceOnly": False, "runnerReturnCode": 0, "taskResultPath": task_path.relative_to(root).as_posix(), "taskResultSha256": sha256_file(task_path), "runnerStdoutSha256": hashlib.sha256(b"").hexdigest(), "runnerStderrSha256": hashlib.sha256(b"").hexdigest(), "assertions": assertions}

    exact = {"repository": "synthetic/contract", "repositoryId": 1, "workflowName": "P2 Owner Mode", "workflowPath": ".github/workflows/p2-owner-mode.yml", "workflowFileSha256": digest, "workflowRef": "synthetic/ref", "workflowRunId": {"windows": "101", "macos": "102", "linux": "103"}[platform], "runAttempt": 1, "jobName": f"p2-behavioral-{platform}", "githubJobId": 201, "sourceCommit": commit, "runnerId": 301, "runnerName": f"synthetic-{platform}", "runnerGroup": "kristin-p2-controlled", "runnerGroupId": 9, "githubJobIdentitySha256": digest, "runnerEphemeralSessionId": f"session-{platform}"}
    cleanup_assertions = {key: True for key in ("managedProcessTreesTerminated", "zeroSurvivingDescendants", "controlledUserServicesStoppedAndRemoved", "controlledPackagesRemoved", "clipboardTestDataCleared", "screenArtifactsRemoved", "authorityEvidenceArtifactsCleared", "workspacesRemoved", "noTestSecretsRemaining", "noConcurrentUntrustedWorkload")}
    cleanup_path = root / "cleanup" / "validated-cleanup.json"
    write_json(cleanup_path, {"schemaVersion": "2.0.0", "receiptType": "p2-validated-post-run-cleanup-v2", "status": "passed", "completionEligibleForPlatformFinalization": True, "exactBinding": exact, "assertions": cleanup_assertions, "syntheticContractFixture": True})
    verification = {key: True for key in ("signatureVerified", "exactRepositoryVerified", "exactWorkflowVerified", "exactWorkflowRefVerified", "exactWorkflowRunVerified", "exactRunAttemptVerified", "exactJobVerified", "githubApiJobIdentityVerified", "sourceCommitVerified", "runnerIdentityVerified", "runnerGroupAndLabelsVerified", "ephemeralSessionVerified", "hostImageVerified", "interactiveSessionVerified", "permissionsVerified", "exclusiveWorkloadVerified", "configurationReceiptVerified", "p1aMergedManifestVerified", "p1aSignedPlatformReceiptVerified", "p1aEvidenceTrustVerified", "p1aServiceBehaviorVerified", "p1aWorkerDenialVerified", "workerAuthorityIsolationVerified", "packageResourcesVerified", "serviceResourcesVerified", "technologyResourcesVerified")}
    runner_path = root / "runner" / "attestation.json"
    write_json(runner_path, {"schemaVersion": "5.0.0", "receiptType": "p2-controlled-runner-attestation-receipt-v5", "status": "passed", "platform": platform, "exactBinding": exact, "runnerId": 301, "runnerName": f"synthetic-{platform}", "runnerGroup": "kristin-p2-controlled", "runnerEphemeralSessionId": f"session-{platform}", "configurationSha256": digest, "interactiveSession": {"loggedIn": True}, "permissions": {"clipboard": True, "screenCapture": True, "activeWindow": True, "accessibility": True}, "verification": verification, "p1AuthorityService": p1a_summary, "workerCannotAccessAuthorityService": True, "p2ReceivesAuthoritySecrets": False, "completionEligibleForTaskClosure": False, "syntheticContractFixture": True})
    native = _native(root, platform)
    receipt = {
        "schemaVersion": "5.0.0",
        "receiptType": "p2-task-platform-behavioral-v5",
        "phase": "P2",
        "platform": platform,
        "status": "passed",
        "sourceOnly": False,
        "completionEligible": True,
        "postRunCleanupObserved": True,
        "interactiveDesktopAttested": True,
        "behavioralLaneAttested": True,
        "commitSha": commit,
        "workflowName": "P2 Owner Mode",
        "workflowRunId": exact["workflowRunId"],
        "jobId": str(exact["githubJobId"]),
        "jobName": exact["jobName"],
        "artifactName": f"p2-{platform}-{commit}",
        "artifactDigestAlgorithm": "canonical-unpacked-v1",
        "artifactRoot": "artifact",
        "exactBinding": exact,
        "applicationComposition": {"path": "application-composition.json", "sha256": digest, "entryPoint": "ProductRuntime.initialize", "p2CompositionField": "ProductRuntime.p2OwnerMode", "p1AuthorityField": "ProductRuntime.p1AuthorityService", "p1AuthorityImplementation": "merged-P1A-isolated-service"},
        "applicationRuntime": {"sourceCheckoutIndependent": True, "manifestSha256": digest, "runtimeBuildSha256": digest},
        "p1AuthorityService": {"authorityType": "p1-isolated-authority-service-v2", "completionEligible": True, "osEnforcedIsolation": True, "workerPrincipalSeparated": True, "typedOperationsOnly": True, "nonExportableKeys": True, "workerDeniedByOs": True, "workerCannotAccessAuthorityService": True, "p2DelegationOnly": True, "rawAuthoritySecretsIncluded": False, **{key: p1a_summary[key] for key in ("serviceInstanceId", "serviceBuildSha256", "workerLauncherSha256", "workerExecutableSha256", "workerIdentitySha256", "denialTranscriptSha256", "serviceBehaviorReceiptSha256", "workerDenialReceiptSha256", "p1aMergedCommit", "p1aMergedTree", "p1aPackageSha256")}, **p1a_rows},
        "p2ToolchainExtensionFingerprint": digest,
        "runnerProvisioningPacketSha256": digest,
        "runnerAttestation": {"path": runner_path.relative_to(root).as_posix(), "sha256": sha256_file(runner_path), "runnerId": 301, "runnerName": f"synthetic-{platform}", "runnerGroup": "kristin-p2-controlled", "runnerEphemeralSessionId": f"session-{platform}", "configurationSha256": digest, "verification": verification, "workerCannotAccessAuthorityService": True, "p2ReceivesAuthoritySecrets": False},
        "postRunCleanup": {"path": cleanup_path.relative_to(root).as_posix(), "sha256": sha256_file(cleanup_path), "signedCleanupSha256": digest, "status": "passed", "assertions": cleanup_assertions, "exactBinding": exact},
        "toolchains": {"pythonRuntime": {"version": "3.13.5", "executable": "/synthetic/python", "executableSha256": digest}, "nodeRuntime": {"version": "24.18.0", "executable": "/synthetic/node", "executableSha256": digest}},
        "nativeRuntime": native,
        "taskAssertions": task_rows,
        "syntheticContractFixture": True,
    }
    receipt["artifactSha256"] = canonical_directory_digest(root)
    path = receipt_dir / "receipt.json"
    write_json(path, receipt)
    return path
