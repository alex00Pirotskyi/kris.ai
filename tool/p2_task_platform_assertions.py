#!/usr/bin/env python3
"""Execute machine-observed, task-specific P2 assertions.

A task can pass only from executed repository tests and, for host effects, an
executed Kristin product path. Product-path evidence must bind the exact task,
platform, commit, P1 authorization boundary, production adapter, OS
postcondition, and structured receipt. Helper-only smoke is never sufficient.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import platform
import shutil
import signal
import subprocess
import sys
import time
from typing import Callable

PLATFORM = {"Windows": "windows", "Darwin": "macos", "Linux": "linux"}[platform.system()]
PASS = {"passed"}
NON_PASS = {
    "failed",
    "blocked",
    "unsupported",
    "source_only",
    "skipped",
    "not_tested",
    "malformed",
    "absent",
}
PRODUCT_TASKS = {
    "P2-001",
    "P2-002",
    "P2-003",
    "P2-005",
    "P2-006",
    "P2-007",
    "P2-008",
    "P2-009",
    "P2-010",
    "P2-011",
    "P2-012",
    "P2-013",
}
HEX40 = __import__("re").compile(r"^[0-9a-f]{40}$")


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: pathlib.Path) -> str:
    return sha256_bytes(path.read_bytes())


def safe_tail(value: str) -> str:
    value = value[-4000:]
    if any(marker in value.lower() for marker in (
        "token", "password", "secret", "authorization", "api_key", "apikey",
        "private_key", "bearer",
    )):
        return "[REDACTED: credential-shaped diagnostic]"
    return value


def sanitized_environment(extra: dict[str, str] | None = None) -> dict[str, str]:
    allow = {
        "PATH", "Path", "HOME", "USERPROFILE", "SystemRoot", "WINDIR", "ComSpec",
        "PATHEXT", "ProgramFiles", "ProgramFiles(x86)", "LOCALAPPDATA", "APPDATA",
        "TEMP", "TMP", "TMPDIR", "SHELL", "LANG", "LC_ALL", "TERM", "XAUTHORITY",
        "DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS",
        "LD_LIBRARY_PATH", "DYLD_LIBRARY_PATH", "PUB_CACHE", "CI", "GITHUB_ACTIONS",
        "GITHUB_WORKSPACE", "RUNNER_OS", "RUNNER_TEMP", "RUNNER_TOOL_CACHE",
        "KRISTIN_WINDOWS_JOB_HELPER", "KRISTIN_POSIX_WATCHDOG_HELPER",
        "KRISTIN_NATIVE_PTY_PROBE", "KRISTIN_INTERACTIVE_DESKTOP_ADAPTER",
        "KRISTIN_P2_INTERACTIVE_DESKTOP", "KRISTIN_P2_BEHAVIORAL_LANE_ATTESTED",
                "KRISTIN_P2_CONTROLLED_PACKAGE_MANAGER", "KRISTIN_P2_CONTROLLED_PACKAGE_NAME",
        "KRISTIN_P2_CONTROLLED_PACKAGE_SOURCE", "KRISTIN_P2_CONTROLLED_PACKAGE_PREFIX",
        "KRISTIN_P2_NPM_EXECUTABLE", "KRISTIN_P2_NATIVE_SERVICE_ID",
        "KRISTIN_P2_NATIVE_SERVICE_PROVIDER", "KRISTIN_P2_NATIVE_SERVICE_ATTESTATION",
        "KRISTIN_P2_NATIVE_SERVICE_ATTESTATION_SHA256",
        "KRISTIN_P2_RUNNER_ATTESTATION_RECEIPT", "KRISTIN_P2_RUNNER_ATTESTATION_SHA256",
        "KRISTIN_P2_RUNNER_POLICY", "KRISTIN_P2_RUNNER_POLICY_SHA256",
        "KRISTIN_P2_COMMIT_SHA",
        "KRISTIN_P2_TECH_NODE_RECEIPT",
        "KRISTIN_P2_TECH_NATIVE_RECEIPT",
        "KRISTIN_P2_TECH_DART_RECEIPT",
        "KRISTIN_P2_TECH_AUTHORIZED_ROOT",
        "KRISTIN_P2_TECH_TRUST_MANIFEST",
        "KRISTIN_P2_TECH_TRUST_MANIFEST_SHA256",
        "KRISTIN_P2_TECH_SESSION_ID",
        "KRISTIN_P2_TECH_NONCE",
        "GITHUB_RUN_ID", "GITHUB_JOB", "RUNNER_NAME",
                "KRISTIN_P2_APPLICATION_COMPOSITION_EVIDENCE",
        "KRISTIN_P2_TOOLCHAIN_EXTENSION_FINGERPRINT",
        "KRISTIN_P2_NATIVE_RUNTIME_MANIFEST", "KRISTIN_P2_NATIVE_RUNTIME_MANIFEST_SHA256",
        "KRISTIN_P2_E2E_ROOT", "KRISTIN_P2_APPLICATION_RUNTIME_MANIFEST",
        "KRISTIN_P2_APPLICATION_RUNTIME_MANIFEST_SHA256", "KRISTIN_P2_AUTHORITY_PROVISIONING_SHA256",
        "GITHUB_REPOSITORY", "GITHUB_WORKFLOW", "GITHUB_WORKFLOW_REF", "GITHUB_RUN_ATTEMPT",
    }
    result = {key: value for key, value in os.environ.items() if key in allow and value}
    if extra:
        for key, value in extra.items():
            if any(marker in key.lower() for marker in ("secret", "token", "password", "key")) and key not in {
                "KRISTIN_WINDOWS_JOB_HELPER",
                "KRISTIN_POSIX_WATCHDOG_HELPER",
            }:
                raise SystemExit(f"credential-shaped assertion environment key rejected: {key}")
            if value:
                result[key] = value
    return result


def _terminate_process_tree(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    if os.name == "nt":
        try:
            subprocess.run(
                ["taskkill.exe", "/PID", str(process.pid), "/T", "/F"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=20,
                check=False,
            )
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass
    else:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            return
        except PermissionError:
            try:
                process.kill()
            except ProcessLookupError:
                return
    if process.poll() is None:
        try:
            process.kill()
        except ProcessLookupError:
            pass


def execute(
    command: list[str],
    cwd: pathlib.Path,
    *,
    timeout: int,
    environment: dict[str, str] | None = None,
) -> dict:
    started = time.time()
    creation_flags = subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0
    try:
        process = subprocess.Popen(
            command,
            cwd=cwd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            stdin=subprocess.DEVNULL,
            env=sanitized_environment(environment),
            start_new_session=(os.name != "nt"),
            creationflags=creation_flags,
        )
    except FileNotFoundError as exc:
        return {
            "command": command,
            "returnCode": 127,
            "stdoutSha256": sha256_bytes(b""),
            "stderrSha256": sha256_bytes(str(exc).encode("utf-8", "replace")),
            "stderrTail": "command_not_found",
            "durationMs": round((time.time() - started) * 1000, 3),
        }
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        _terminate_process_tree(process)
        try:
            stdout, stderr = process.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            try:
                process.kill()
            except ProcessLookupError:
                pass
            stdout, stderr = process.communicate()
        stdout = stdout or ""
        stderr = stderr or ""
        return {
            "command": command,
            "returnCode": 124,
            "stdoutSha256": sha256_bytes(stdout.encode("utf-8", "replace")),
            "stderrSha256": sha256_bytes(stderr.encode("utf-8", "replace")),
            "stderrTail": "command_timeout",
            "durationMs": round((time.time() - started) * 1000, 3),
        }
    stdout = stdout or ""
    stderr = stderr or ""
    return {
        "command": command,
        "returnCode": process.returncode,
        "stdoutSha256": sha256_bytes(stdout.encode("utf-8", "replace")),
        "stderrSha256": sha256_bytes(stderr.encode("utf-8", "replace")),
        "stdoutTail": safe_tail(stdout) if process.returncode else "",
        "stderrTail": safe_tail(stderr) if process.returncode else "",
        "durationMs": round((time.time() - started) * 1000, 3),
    }


def read_json(path: pathlib.Path) -> tuple[str, dict]:
    if not path.is_file():
        return "absent", {"status": "absent", "reason": "observation_artifact_missing"}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        return "malformed", {"status": "malformed", "error": str(exc)}
    if not isinstance(data, dict):
        return "malformed", {"status": "malformed", "error": "JSON root is not an object"}
    return str(data.get("status", "absent")), data


def resolve_test_source(spec: dict, command: list[str], cwd: pathlib.Path, root: pathlib.Path) -> str:
    explicit = str(spec.get("source", "")).strip()
    if explicit:
        candidate = (root / explicit).resolve()
        if not candidate.is_file():
            raise SystemExit(f"declared test source missing: {explicit}")
        return pathlib.PurePosixPath(explicit).as_posix()
    for value in command:
        if not isinstance(value, str) or not value.endswith((".dart", ".py", ".mjs", ".js", ".c", ".cpp")):
            continue
        candidate = pathlib.Path(value)
        if not candidate.is_absolute():
            candidate = (cwd / candidate).resolve()
        try:
            relative = candidate.relative_to(root)
        except ValueError:
            continue
        if candidate.is_file():
            return relative.as_posix()
    raise SystemExit(f"machine assertion has no repository test source: {command!r}")


def _nonempty_hex(value: object, length: int = 64) -> bool:
    return isinstance(value, str) and bool(__import__("re").fullmatch(rf"[0-9a-f]{{{length}}}", value))


def validate_product_evidence(
    data: dict,
    *,
    task: str,
    commit_sha: str,
    assertion_id: str,
) -> dict:
    required = {
        "schemaVersion": "2.0.0",
        "resultType": "p2-shipped-product-observation-v2",
        "taskId": task,
        "assertionId": f"p2-{task[3:]}.product-runtime-e2e",
        "platform": PLATFORM,
        "commitSha": commit_sha,
        "entryPoint": "ProductRuntime.initialize",
        "applicationComposition": "ProductRuntime.p2OwnerMode",
        "authorizationBoundary": "p1-isolated-authority-service-effect-permit-v2",
        "status": "passed",
        "sourceOnly": False,
        "fixtureAuthority": False,
        "completionEligible": True,
    }
    for key, value in required.items():
        if data.get(key) != value:
            observed = str(data.get("status", "malformed"))
            return {
                "status": observed if observed in NON_PASS else "malformed",
                "reason": f"product_evidence_{key}_mismatch",
                "expected": value,
                "observed": data.get(key),
            }
    encoded = json.dumps(data, sort_keys=True).lower()
    if any(marker in encoded for marker in (
        "fixture-authority", "fixture_authority", "mock-authority",
        "test-authority", "_nodefixture", "fixture.",
        "p1desktopcontrolplaneauthorityv2", "p2durablegrantuseledger",
        "protectedauthoritybroker", "messagebase64",
    )):
        return {"status": "malformed", "reason": "fixture_parallel_or_broker_authority_evidence"}
    for key in (
        "applicationCompositionSha256", "runnerAttestationSha256",
        "toolchainExtensionFingerprint", "nativeRuntimeManifestSha256",
    ):
        if not _nonempty_hex(data.get(key)):
            return {"status": "malformed", "reason": f"product_{key}_invalid"}
    authority = data.get("authority")
    if (
        not isinstance(authority, dict)
        or authority.get("authorityImplementation") != "P1IsolatedAuthorityServiceV2"
        or authority.get("authorityKind") != "p1-isolated-authority-service-v2"
        or authority.get("completionEligible") is not True
    ):
        return {"status": "malformed", "reason": "merged_p1a_authority_missing"}
    for key in (
        "policyDecisionId", "capabilityGrantId", "authenticatedIpcChannelId",
        "authenticatedIpcRequestId", "auditCheckpointId", "serviceInstanceId",
    ):
        if not str(authority.get(key, "")).strip():
            return {"status": "malformed", "reason": f"authority_{key}_missing"}
    for key in (
        "policyDecisionSha256", "capabilityGrantSha256", "authenticatedIpcSha256",
        "effectPermitSha256", "auditCheckpointSha256", "serviceBuildSha256",
        "serviceEndpointAttestationSha256", "p1aPlatformReceiptSha256",
        "p1aEvidenceTrustSha256", "p1aServiceBehaviorReceiptSha256",
        "workerDenialReceiptSha256", "p1aWorkerLauncherSha256",
        "p1aWorkerExecutableSha256", "p1aWorkerIdentitySha256",
        "p1aDenialTranscriptSha256", "p1aPackageSha256",
        "p1AmendmentManifestSha256",
    ):
        if not _nonempty_hex(authority.get(key)):
            return {"status": "malformed", "reason": f"authority_{key}_invalid"}
    if not _nonempty_hex(authority.get("effectPermitSignerPublicKeySpkiSha256")):
        return {"status": "malformed", "reason": "authority_public_verifier_invalid"}
    for key in ("durableConsumptionStateVersion", "durableConsumptionUseNumber", "revocationEpoch"):
        if not isinstance(authority.get(key), int) or authority[key] < 0:
            return {"status": "malformed", "reason": f"authority_{key}_invalid"}
    exact_flags = {
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
    }
    for key, value in exact_flags.items():
        if authority.get(key) is not value:
            return {"status": "malformed", "reason": f"authority_{key}_invalid"}
    p1a = authority.get("p1aEvidence")
    if not isinstance(p1a, dict):
        return {"status": "malformed", "reason": "p1a_evidence_missing"}
    for key in ("p1AmendmentMerged", "independentP1aSecurityReviewApproved", "workerDenialTriPlatformPassed"):
        if p1a.get(key) is not True:
            return {"status": "malformed", "reason": f"p1a_{key}_not_proved"}
    for key in (
        "aggregateManifestSha256", "platformReceiptSha256",
        "evidenceTrustSha256", "serviceBehaviorReceiptSha256",
        "workerDenialReceiptSha256", "workerLauncherSha256",
        "workerExecutableSha256", "workerIdentitySha256",
        "denialTranscriptSha256", "p1aPackageSha256",
    ):
        if not _nonempty_hex(p1a.get(key)):
            return {"status": "malformed", "reason": f"p1a_{key}_invalid"}
    if p1a.get("privateAuthorityMaterialPresent") is not False or p1a.get("arbitraryMessageSigningApi") is not False:
        return {"status": "malformed", "reason": "p1a_authority_material_or_signing_api_invalid"}
    approval = authority.get("approval")
    protected = authority.get("protectedKeys")
    if not isinstance(approval, dict) or approval.get("completionEligible") is not True:
        return {"status": "malformed", "reason": "external_owner_approval_missing"}
    if (
        not isinstance(protected, dict)
        or protected.get("completionEligible") is not True
        or protected.get("kind") != "non-exportable-service-owned-keys"
    ):
        return {"status": "malformed", "reason": "isolated_non_exportable_keys_missing"}
    effect = data.get("osEffect")
    postcondition = data.get("postcondition")
    receipt = data.get("receipt")
    if not isinstance(effect, dict) or not effect:
        return {"status": "malformed", "reason": "product_os_effect_missing"}
    if not isinstance(postcondition, dict) or postcondition.get("observed") is not True:
        return {"status": "malformed", "reason": "product_postcondition_unobserved"}
    if (
        not isinstance(receipt, dict)
        or receipt.get("completionEligible") is not True
        or receipt.get("fixtureAuthority") is not False
        or receipt.get("targetHostOperation") is not True
        or not str(receipt.get("status", "")).strip()
    ):
        return {"status": "malformed", "reason": "completion_receipt_invalid"}
    adapter = str(data.get("productionAdapter", ""))
    if not adapter.startswith("ProductRuntime/"):
        return {"status": "malformed", "reason": "shipped_production_adapter_missing"}
    task_requirements = {
        "P2-001": effect.get("kind") == "owner_mode_settings_enable_disable_reset" and all(postcondition.get(k) is True for k in ("explicitAcknowledgementRequired","fullCurrentAccountLabelObserved","notSandboxLabelObserved","persistentIndicatorObserved","disableResetObserved","settingsPersistedAfterReenable")),
        "P2-005": effect.get("kind") == "interactive_pty_detach_reconnect" and postcondition.get("consumerDetached") is True and postcondition.get("outputWhileDetached") is True and isinstance(postcondition.get("reconnectCursor"),int) and postcondition.get("reconnectCursor") >= 0 and postcondition.get("backlogReplayExact") is True and postcondition.get("noDuplicationOrLoss") is True,
        "P2-006": effect.get("kind") == "managed_process_tree_kill" and postcondition.get("descendantProcessCreated") is True and postcondition.get("identityVerified") is True and postcondition.get("activeProcesses") == 0 and postcondition.get("zeroSurvivingDescendants") is True,
        "P2-007": effect.get("kind") == "controlled_target_host_package_lifecycle" and all(postcondition.get(k) is True for k in ("controlledTargetHost","dryRunObserved","installObserved","installedStateObserved","removeObserved","removedStateObserved","executableVersionProvenanceObserved")) and int(postcondition.get("sdkRows",0)) > 0,
        "P2-008": effect.get("kind") == "controlled_user_service_and_application_lifecycle" and all(postcondition.get(k) is True for k in ("initialStoppedObserved","startObserved","runningObserved","stopObserved","stoppedObserved","applicationOpenObserved","applicationCloseObserved")) and postcondition.get("elevationExercised") is False,
        "P2-009": effect.get("kind") == "interactive_clipboard_screen_active_window" and all(postcondition.get(k) is True for k in ("clipboardRoundTrip","screenCaptured","activeWindowObserved","ordinaryLogContentAbsent")),
        "P2-010": effect.get("kind") == "product_snapshot_restore" and postcondition.get("restoredContent") is True,
        "P2-011": effect.get("kind") == "product_runtime_external_watchdog_kill_during_ui_freeze" and all(postcondition.get(k) is True for k in ("watchdogAutomaticallyArmed","heartbeatObserved","desktopHeartbeatFrozen","externalKillObserved","identityVerified","zeroSurvivingDescendants")) and postcondition.get("activeProcesses") == 0,
        "P2-012": effect.get("kind") == "shipped_terminal_workspace_managed_session" and all(postcondition.get(k) is True for k in ("tabCreatedFromManagedPty","shellAndCwdObserved","runTaskGrantIdentityObserved","searchObserved","accessibilityLabelObserved","keyboardEmergencyActionExposed","interruptObserved","terminateTreeObserved")),
        "P2-013": effect.get("kind") == "production_authority_restart_replay_reconciliation" and all(postcondition.get(k) is True for k in ("firstDispatchSucceeded","durableConsumptionRecorded","durableStateVersionRecorded","productRuntimeRestarted","replayRejectedAfterRestart","reconciliationObserved")),
    }
    if task in task_requirements and task_requirements[task] is not True:
        return {"status": "malformed", "reason": f"{task.lower()}_product_postcondition_incomplete"}
    return {
        "status": "passed",
        "productAssertionId": data["assertionId"],
        "productEntryPoint": data["entryPoint"],
        "applicationCompositionSha256": data["applicationCompositionSha256"],
        "productionAdapter": adapter,
        "authorityImplementation": authority["authorityImplementation"],
        "serviceInstanceId": authority["serviceInstanceId"],
        "capabilityGrantId": authority["capabilityGrantId"],
        "policyDecisionId": authority["policyDecisionId"],
        "runnerAttestationSha256": data["runnerAttestationSha256"],
        "nativeRuntimeManifestSha256": data["nativeRuntimeManifestSha256"],
        "osEffectKind": effect.get("kind"),
        "postconditionObserved": True,
        "receiptStatus": receipt.get("status"),
        "taskAssertionId": assertion_id,
    }

def validate_technology_spike(data: dict) -> dict:
    required_ids = [
        "typescript-node-node-pty-with-native-lifecycle-adapters",
        "native-platform-pty-supervisor",
        "dart-control-plane-native-pty-helper",
    ]
    required_proofs = {
        "consumerDetached", "outputWhileDetached", "reconnectCursorObserved",
        "backlogReplayExact", "noDuplicationOrLoss", "descendantProcessCreated",
        "descendantTerminated", "zeroSurvivingDescendants",
    }
    if (
        data.get("schemaVersion") != "4.0.0"
        or data.get("measurementType") != "p2-equivalent-pty-technology-spike-v4"
        or data.get("platform") != PLATFORM
        or data.get("commitSha") != os.environ.get("KRISTIN_P2_COMMIT_SHA")
    ):
        return {"status": "malformed", "reason": "technology_spike_identity"}
    trust = data.get("trust")
    try:
        expected_attempt = int(os.environ.get("GITHUB_RUN_ATTEMPT", "0"))
    except ValueError:
        expected_attempt = 0
    if (
        not isinstance(trust, dict)
        or not _nonempty_hex(trust.get("manifestSha256"))
        or not str(trust.get("measurementSessionId", "")).strip()
        or trust.get("measurementSessionId") != os.environ.get("KRISTIN_P2_TECH_SESSION_ID")
        or trust.get("workflowRunId") != os.environ.get("GITHUB_RUN_ID")
        or trust.get("workflowRunAttempt") != expected_attempt
        or not _nonempty_hex(trust.get("nonceSha256"))
        or not str(trust.get("issuedAt", "")).endswith("Z")
        or not str(trust.get("expiresAt", "")).endswith("Z")
    ):
        return {"status": "blocked", "reason": "technology_spike_trust_binding"}
    candidates = data.get("candidates")
    if not isinstance(candidates, list) or [row.get("id") for row in candidates if isinstance(row, dict)] != required_ids:
        return {"status": "blocked", "reason": "technology_spike_candidate_set"}
    if data.get("blockedCandidates") != []:
        return {"status": "blocked", "reason": "technology_spike_blocked_candidates"}
    implementations = set()
    observation_ids = set()
    evidence_paths = set()
    evidence_digests = set()
    for row in candidates:
        if not isinstance(row, dict) or row.get("status") != "passed" or len(row.get("rounds", [])) != 3:
            return {"status": "blocked", "reason": "technology_candidate_not_measured", "candidate": row.get("id") if isinstance(row, dict) else None}
        implementations.add(row.get("implementationSha256"))
        if not _nonempty_hex(row.get("sourceReceiptSha256")) or not _nonempty_hex(row.get("implementationSha256")) or not _nonempty_hex(row.get("executableSha256")):
            return {"status": "blocked", "reason": "technology_candidate_hash_binding", "candidate": row.get("id")}
        proofs = row.get("proofs")
        if not isinstance(proofs, dict) or any(proofs.get(key) is not True for key in required_proofs):
            return {"status": "blocked", "reason": "technology_candidate_proof_gap", "candidate": row.get("id")}
        for round_row in row.get("rounds", []):
            if not isinstance(round_row, dict) or round_row.get("status") != "passed":
                return {"status": "blocked", "reason": "technology_round_incomplete", "candidate": row.get("id")}
            observation_id = str(round_row.get("observationId", ""))
            evidence_path = str(round_row.get("evidencePath", ""))
            evidence_digest = round_row.get("evidenceSha256")
            if (
                not observation_id
                or observation_id in observation_ids
                or not str(round_row.get("observedAt", "")).endswith("Z")
                or not evidence_path
                or evidence_path in evidence_paths
                or not _nonempty_hex(evidence_digest)
                or evidence_digest in evidence_digests
            ):
                return {"status": "blocked", "reason": "technology_round_trusted_identity", "candidate": row.get("id")}
            observation_ids.add(observation_id)
            evidence_paths.add(evidence_path)
            evidence_digests.add(evidence_digest)
            detach = round_row.get("detachReconnect")
            tree = round_row.get("processTree")
            if not isinstance(detach, dict) or not isinstance(tree, dict):
                return {"status": "blocked", "reason": "technology_round_proof_missing", "candidate": row.get("id")}
            if detach.get("consumerDetached") is not True or detach.get("outputWhileDetached") is not True or detach.get("backlogReplayExact") is not True or detach.get("noDuplicationOrLoss") is not True:
                return {"status": "blocked", "reason": "technology_detach_reconnect_not_proved", "candidate": row.get("id")}
            if tree.get("descendantCreated") is not True or tree.get("identityVerified") is not True or tree.get("zeroSurvivingDescendants") is not True or tree.get("remainingDescendants") != []:
                return {"status": "blocked", "reason": "technology_descendant_kill_not_proved", "candidate": row.get("id")}
    if len(implementations) != 3:
        return {"status": "blocked", "reason": "technology_candidates_not_independent"}
    if len(observation_ids) != 9 or len(evidence_paths) != 9 or len(evidence_digests) != 9:
        return {"status": "blocked", "reason": "technology_round_identities_not_independent"}
    decision = data.get("decision")
    if not isinstance(decision, dict) or decision.get("status") != "platform_measurement_complete" or decision.get("selected") not in required_ids or decision.get("requiresTriOsAggregation") is not True:
        return {"status": "blocked", "reason": "technology_decision_incomplete"}
    return {
        "status": "passed",
        "selected": decision["selected"],
        "measuredCandidates": required_ids,
        "trustManifestSha256": trust["manifestSha256"],
        "measurementSessionId": trust["measurementSessionId"],
    }

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--task", required=True)
    parser.add_argument("--commit-sha", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--artifact-root", required=True)
    parser.add_argument("--max-command-seconds", type=int, default=900)
    args = parser.parse_args()
    if not HEX40.fullmatch(args.commit_sha):
        raise SystemExit("exact 40-character commit SHA required")
    root = pathlib.Path(args.project).resolve()
    output = pathlib.Path(args.output).resolve()
    artifact_root = pathlib.Path(args.artifact_root).resolve()
    try:
        output.relative_to(artifact_root)
    except ValueError as exc:
        raise SystemExit("task result output must be inside artifact root") from exc

    evidence_root = artifact_root / "assertions" / PLATFORM / args.task
    evidence_root.mkdir(parents=True, exist_ok=True)
    shared = artifact_root / "shared" / PLATFORM
    shared.mkdir(parents=True, exist_ok=True)

    python = sys.executable
    flutter = shutil.which("flutter") or "flutter"
    node = shutil.which("node") or "node"
    absolute_node = str(pathlib.Path(node).resolve()) if pathlib.Path(node).is_file() else node

    def product_spec(task: str, assertion_id: str) -> dict:
        product_path = evidence_root / f"{assertion_id}-product.json"
        return {
            "id": assertion_id,
            "command": [flutter, "test", "test/product/p2_shipped_product_runtime_e2e_test.dart"],
            "source": "test/product/p2_shipped_product_runtime_e2e_test.dart",
            "json": product_path,
            "environment": {
                "KRISTIN_P2_TASK_ID": task,
                "KRISTIN_P2_COMMIT_SHA": args.commit_sha,
                "KRISTIN_P2_PRODUCT_EVIDENCE": str(product_path),
                "KRISTIN_NODE_EXECUTABLE": absolute_node,
                **{
                    key: value
                    for key, value in os.environ.items()
                    if key.startswith("KRISTIN_P2_") or key in {"GITHUB_RUN_ID", "GITHUB_JOB", "RUNNER_NAME"}
                },
            },
            "validator": lambda data, task=task, assertion_id=assertion_id: validate_product_evidence(
                data, task=task, commit_sha=args.commit_sha, assertion_id=assertion_id
            ),
        }

    technology_path = evidence_root / "technology-spike.json"
    fixture = lambda name: shared / f"{name}.json"
    specs: dict[str, list[dict]] = {
        "P2-001": [
            {"id": "p2-001.owner-state", "command": [flutter, "test", "test/product/p2_owner_mode_test.dart"]},
            {"id": "p2-001.onboarding-workspace", "command": [flutter, "test", "test/product/p2_owner_workspace_test.dart"]},
            product_spec("P2-001", "p2-001.product-owner-mode-e2e"),
        ],
        "P2-002": [
            {"id": "p2-002.filesystem-contract", "command": [flutter, "test", "test/product/p2_filesystem_service_test.dart"]},
            product_spec("P2-002", "p2-002.product-filesystem-e2e"),
        ],
        "P2-003": [
            {"id": "p2-003.effect-boundary-binding", "command": [flutter, "test", "test/product/p2_effect_boundary_test.dart"]},
                        product_spec("P2-003", "p2-003.product-finite-command-e2e"),
        ],
        "P2-004": [
            {
                "id": "p2-004.equivalent-platform-spike",
                "command": [python, "tool/p2_technology_spike.py", "--project", str(root), "--output", str(technology_path), "--commit-sha", args.commit_sha],
                "source": "tool/p2_technology_spike.py",
                "json": technology_path,
                "validator": validate_technology_spike,
            },
            {"id": "p2-004.governed-toolchain-extension", "command": [python, "tool/p2_toolchain_extension_test.py", "--project", str(root)]},
        ],
        "P2-005": [
            {"id": "p2-005.product-composition-contract", "command": [flutter, "test", "test/product/p2_runtime_composition_test.dart"]},
            product_spec("P2-005", "p2-005.product-pty-e2e"),
            {"id": "p2-005.ipc-session-binding", "command": [node, "--test", "src/host.test.mjs"], "cwd": root / "automation_host", "source": "automation_host/src/host.test.mjs"},
        ],
        "P2-006": [
            {"id": "p2-006.process-identity-contract", "command": [flutter, "test", "test/product/p2_process_terminal_contract_test.dart"]},
            product_spec("P2-006", "p2-006.product-tree-kill-e2e"),
        ],
        "P2-007": [
            {"id": "p2-007.product-adapter-contract", "command": [flutter, "test", "test/product/p2_automation_host_operations_test.dart"]},
            product_spec("P2-007", "p2-007.product-package-sdk-e2e"),
        ],
        "P2-008": [
            {"id": "p2-008.product-adapter-contract", "command": [flutter, "test", "test/product/p2_automation_host_operations_test.dart"]},
            product_spec("P2-008", "p2-008.product-service-application-e2e"),
        ],
        "P2-009": [
            {"id": "p2-009.product-adapter-contract", "command": [flutter, "test", "test/product/p2_automation_host_operations_test.dart"]},
            product_spec("P2-009", "p2-009.product-interactive-desktop-e2e"),
            {"id": "p2-009.redaction-no-log", "command": [node, "--test", "--test-name-pattern", "secret-shaped|secret environment", "src/host.test.mjs"], "cwd": root / "automation_host", "source": "automation_host/src/host.test.mjs"},
        ],
        "P2-010": [
            {"id": "p2-010.product-restore-contract", "command": [flutter, "test", "test/product/p2_snapshot_undo_test.dart"]},
            product_spec("P2-010", "p2-010.product-restore-e2e"),
        ],
        "P2-011": [
            {"id": "p2-011.product-watchdog-composition", "command": [flutter, "test", "test/product/p2_runtime_composition_test.dart"]},
            product_spec("P2-011", "p2-011.product-frozen-ui-watchdog-e2e"),
        ],
        "P2-012": [
            {"id": "p2-012.workspace-actions-accessibility", "command": [flutter, "test", "test/product/p2_owner_workspace_test.dart"]},
            {"id": "p2-012.terminal-keyboard-contract", "command": [flutter, "test", "test/product/p2_process_terminal_contract_test.dart"]},
            product_spec("P2-012", "p2-012.product-terminal-workspace-e2e"),
        ],
        "P2-013": [
            product_spec("P2-013", "p2-013.product-restart-replay-e2e"),
            {"id": "p2-013.restart-replay-state", "command": [node, "--test", "--test-name-pattern", "restart|consumption receipt", "src/host.test.mjs"], "cwd": root / "automation_host", "source": "automation_host/src/host.test.mjs"},
            {"id": "p2-013.bounded-adversarial-fixture", "command": [python, "tool/p2_task_fixture.py", "--project", str(root), "--task", "P2-013", "--output", str(fixture("p2-013-adversarial"))], "json": fixture("p2-013-adversarial"), "source": "tool/p2_task_fixture.py"},
        ],
        "P2-014": [
            {"id": "p2-014.guide-ui-consistency", "command": [python, "tool/p2_task_fixture.py", "--project", str(root), "--task", "P2-014", "--output", str(fixture("p2-014-guide"))], "json": fixture("p2-014-guide"), "source": "tool/p2_task_fixture.py"},
        ],
    }
    if args.task not in specs:
        raise SystemExit(f"unknown task {args.task}")

    assertions: list[dict] = []
    for spec in specs[args.task]:
        json_path = pathlib.Path(spec["json"]).resolve() if spec.get("json") else None
        if json_path and json_path.exists():
            json_path.unlink()
        cwd = pathlib.Path(spec.get("cwd", root)).resolve()
        result = execute(
            [str(part) for part in spec["command"]],
            cwd,
            timeout=args.max_command_seconds,
            environment=spec.get("environment"),
        )
        observed = "passed" if result["returnCode"] == 0 else "failed"
        observation: dict = {}
        observation_artifact_path: str | None = None
        observation_artifact_sha: str | None = None
        if json_path:
            raw_status, data = read_json(json_path)
            observation = data
            if spec.get("validator") and json_path.is_file():
                try:
                    observation = spec["validator"](data)
                    raw_status = str(observation.get("status", "malformed"))
                except Exception as exc:
                    observation = {"status": "malformed", "error": safe_tail(str(exc))}
                    raw_status = "malformed"
            observed = "passed" if result["returnCode"] == 0 and raw_status == "passed" else raw_status
            if json_path.is_file():
                try:
                    observation_artifact_path = json_path.relative_to(artifact_root).as_posix()
                except ValueError as exc:
                    raise SystemExit(f"observation artifact escaped root: {json_path}") from exc
                observation_artifact_sha = sha256_file(json_path)
        if observed not in PASS | NON_PASS:
            observed = "failed"

        record_base = {
            "schemaVersion": "1.0.0",
            "assertionId": spec["id"],
            "taskId": args.task,
            "platform": PLATFORM,
            "commitSha": args.commit_sha,
            "command": result["command"],
            "testSource": resolve_test_source(spec, result["command"], cwd, root),
            "observedStatus": observed,
            "returnCode": result["returnCode"],
            "stdoutSha256": result["stdoutSha256"],
            "stderrSha256": result["stderrSha256"],
            "durationMs": result["durationMs"],
            "observation": observation,
            "diagnostic": {key: result[key] for key in ("stdoutTail", "stderrTail") if result.get(key)},
            **({"observationArtifactPath": observation_artifact_path, "observationArtifactSha256": observation_artifact_sha} if observation_artifact_path else {}),
        }
        record_base["resultHash"] = sha256_bytes(canonical(record_base))
        evidence_path = evidence_root / f"{spec['id']}.json"
        evidence_path.write_text(json.dumps(record_base, indent=2) + "\n", encoding="utf-8")
        summary = {
            "assertionId": spec["id"],
            "taskId": args.task,
            "platform": PLATFORM,
            "command": result["command"],
            "testSource": record_base["testSource"],
            "observedStatus": observed,
            "returnCode": result["returnCode"],
            "resultHash": record_base["resultHash"],
            "evidencePath": evidence_path.relative_to(artifact_root).as_posix(),
            "evidenceSha256": sha256_file(evidence_path),
        }
        if observation_artifact_path:
            summary["observationArtifactPath"] = observation_artifact_path
            summary["observationArtifactSha256"] = observation_artifact_sha
        assertions.append(summary)

    status = "passed" if assertions and all(row["observedStatus"] == "passed" for row in assertions) else "blocked"
    payload = {
        "schemaVersion": "1.0.0",
        "resultType": "p2-task-observed-result-v1",
        "taskId": args.task,
        "platform": PLATFORM,
        "commitSha": args.commit_sha,
        "generatedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "status": status,
        "sourceOnly": False,
        "productPathRequired": args.task in PRODUCT_TASKS,
        "assertions": assertions,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2))
    return 0 if status == "passed" else 3


if __name__ == "__main__":
    raise SystemExit(main())
