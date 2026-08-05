#!/usr/bin/env python3
from __future__ import annotations

import base64
import hashlib
import json
import os
import pathlib
import platform
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from ed25519_ref import public_key, sign
from p2_p1a_dependency import validate_merged_p1a_graph

ROOT = pathlib.Path(__file__).resolve().parents[1]
P1A_COMPONENT_PURPOSES = {
    "runnerAttestation": "p1a-runner-attestation-receipt",
    "buildProvenance": "p1a-build-provenance",
    "installerReceipt": "p1a-installer-receipt",
    "keyProviderReceipt": "p1a-key-provider-receipt",
    "workerDenialReceipt": "p1a-worker-denial-receipt",
    "cleanupReceipt": "p1a-cleanup-receipt",
    "githubApiVerification": "p1a-github-api-verification",
}


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object, *, newline: bool = False) -> bytes:
    data = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    )
    return (data + ("\n" if newline else "")).encode("utf-8")


def dump(path: pathlib.Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def make(parent: pathlib.Path, name: str, content: str = "x") -> pathlib.Path:
    path = parent / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return path


def canonical_directory_digest(root: pathlib.Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(
        (item for item in root.rglob("*") if item.is_file()),
        key=lambda item: item.relative_to(root).as_posix(),
    ):
        relative = path.relative_to(root).as_posix().encode("utf-8")
        data = path.read_bytes()
        digest.update(len(relative).to_bytes(8, "big"))
        digest.update(relative)
        digest.update(len(data).to_bytes(8, "big"))
        digest.update(hashlib.sha256(data).digest())
    return digest.hexdigest()


def signed_ed25519(
    body: dict, *, seed: bytes, key_id: str, purpose: str
) -> dict:
    unsigned = dict(body)
    message = canonical(unsigned)
    unsigned["signature"] = {
        "algorithm": "ed25519",
        "keyId": key_id,
        "purpose": purpose,
        "signedSha256": hashlib.sha256(message).hexdigest(),
        "signatureBase64": base64.b64encode(sign(seed, message)).decode("ascii"),
    }
    return unsigned


def signed_service_receipt(body: dict) -> dict:
    message = canonical(body)
    script = r"""
const crypto=require('crypto');
const msg=Buffer.from(process.argv[1],'base64');
const pair=crypto.generateKeyPairSync('ec',{namedCurve:'prime256v1'});
const pub=pair.publicKey.export({format:'der',type:'spki'});
const sig=crypto.sign('sha256',msg,pair.privateKey);
console.log(JSON.stringify({publicKeySpkiBase64:pub.toString('base64'),signatureBase64:sig.toString('base64')}));
"""
    result = subprocess.run(
        ["node", "-e", script, base64.b64encode(message).decode("ascii")],
        capture_output=True,
        text=True,
        check=True,
    )
    values = json.loads(result.stdout)
    signed = dict(body)
    signed["signature"] = {
        "algorithm": "ecdsa-p256-sha256",
        "publicKeySpkiBase64": values["publicKeySpkiBase64"],
        "signatureBase64": values["signatureBase64"],
        "providerAttestationSha256": "8" * 64,
        "nonExportable": True,
        "privateExportDenied": True,
    }
    return signed


def build_p1a_graph(project: pathlib.Path, *, seed: bytes, platform_name: str = "linux") -> dict[str, pathlib.Path]:
    evidence = project / "release/evidence/P1A"
    commit = "b" * 40
    tree = "c" * 40
    package = "d" * 64
    receipt_dir = evidence / "platforms" / commit / platform_name
    artifact = receipt_dir / "artifact"
    artifact.mkdir(parents=True)
    installed = project / "installed" / platform_name
    installed.mkdir(parents=True, exist_ok=True)
    service_binary = make(installed, "kristin_p1_authority_service", "service-binary-v63")
    connector_library = make(installed, "kristin_p1a_connector", "connector-library-v63")
    worker_launcher = make(installed, "kristin_p2_worker_launcher", "worker-launcher-v63")
    worker_executable = make(installed, "node", "restricted-worker-executable-v63")
    installer = make(installed, "installer", "installer-v63")
    uninstaller = make(installed, "uninstaller", "uninstaller-v63")
    exact = {
        "schemaVersion": "1.0.0",
        "repository": "owner/repo",
        "workflowPath": ".github/workflows/p1-authority-amendment.yml",
        "workflowRef": "refs/heads/p1a",
        "workflowRunId": "901",
        "runAttempt": "1",
        "jobName": f"p1a-behavioral-{platform_name}",
        "githubJobId": "902",
        "sourceCommit": commit,
        "sourceTree": tree,
        "platform": platform_name,
        "runnerId": "903",
        "runnerName": "p1a-fixture-runner",
        "runnerGroup": "kristin-p1a-controlled",
        "ephemeralSessionId": "p1a-ephemeral",
    }
    exact_hash = hashlib.sha256(canonical(exact)).hexdigest()
    key_id = "p1a-fixture-evidence"
    component_bodies = {
        "runnerAttestation": {},
        "buildProvenance": {
            "serviceBinarySha256": sha(service_binary),
            "connectorLibrarySha256": sha(connector_library),
            "workerLauncherSha256": sha(worker_launcher),
            "installerSha256": sha(installer),
            "uninstallerSha256": sha(uninstaller),
            "sourceInventorySha256": "1" * 64,
            "reproducibleBuildInputsSha256": "2" * 64,
            "toolchains": {
                "python": {"version": "3.13.5", "executableSha256": "3" * 64},
                "cmake": {"version": "4.0.3", "executableSha256": "4" * 64},
                "compiler": {"version": "fixture-1", "executableSha256": "5" * 64},
            },
        },
        "installerReceipt": {
            "serviceInstalled": True,
            "separateServiceIdentity": True,
            "connectorInstalled": True,
            "workerLauncherInstalled": True,
            "rollbackAvailable": True,
            "installerSha256": sha(installer),
            "uninstallerSha256": sha(uninstaller),
            "installedServiceSha256": sha(service_binary),
            "installedConnectorSha256": sha(connector_library),
            "installedWorkerLauncherSha256": sha(worker_launcher),
        },
        "keyProviderReceipt": {
            "providerBacked": True,
            "privateExportAttempted": True,
            "privateExportDenied": True,
            "serviceOnlyAclObserved": True,
            "providerName": "fixture-non-exportable-provider",
            "keyId": "fixture-p1a-key",
            "providerAttestationSha256": "8" * 64,
            "signingOperationProvenanceSha256": "9" * 64,
        },
        "workerDenialReceipt": {
            "productionRestrictedLauncherUsed": True,
            "exactWorkerPrincipalObserved": True,
            "authorityConnectionDenied": True,
            "authorityKeyReadDenied": True,
            "osKeyStoreSigningDenied": True,
            "arbitraryMessageSigningDenied": True,
            "workerIdentityBoundToSession": True,
            "launcherSha256": sha(worker_launcher),
            "workerExecutableSha256": sha(worker_executable),
            "workerIdentitySha256": "4" * 64,
            "denialTranscriptSha256": "5" * 64,
            "workerIdentity": {"kind": "uid", "value": "32101"},
        },
        "cleanupReceipt": {
            "serviceUninstalled": True,
            "workerLauncherRemoved": True,
            "connectorRemoved": True,
            "testKeyRemoved": True,
            "zeroManagedProcesses": True,
            "zeroOrphanedProcesses": True,
            "temporaryAuthorityStateRemoved": True,
            "postRunCleanup": True,
            "uninstallerSha256": sha(uninstaller),
        },
        "githubApiVerification": {
            "repository": exact["repository"],
            "workflowRunId": exact["workflowRunId"],
            "runAttempt": exact["runAttempt"],
            "githubJobId": exact["githubJobId"],
            "headSha": commit,
            "statusAtCapture": "completed",
            "conclusion": "success",
        },
    }
    component_rows: dict[str, dict] = {}
    for name, values in component_bodies.items():
        body = {
            "schemaVersion": "1.0.0",
            "platform": platform_name,
            "status": "passed",
            "completionEligible": True,
            "syntheticContractFixture": False,
            "exactBinding": exact,
            **values,
        }
        signed = signed_ed25519(
            body,
            seed=seed,
            key_id=key_id,
            purpose=P1A_COMPONENT_PURPOSES[name],
        )
        path = artifact / f"{name}.json"
        dump(path, signed)
        component_rows[name] = {
            "path": path.relative_to(artifact).as_posix(),
            "sha256": sha(path),
        }

    service_body = {
        "schemaVersion": "2.0.0",
        "receiptType": "p1a-service-behavior-v2",
        "platform": platform_name,
        "sourceCommit": commit,
        "sourceTree": tree,
        "exactRunBindingSha256": exact_hash,
        "completionEligible": True,
        "syntheticContractFixture": False,
        "serviceInstanceId": "p1a-linux-fixture",
        "serviceBuildSha256": sha(service_binary),
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
        "behaviorSession": {
            "events": [
                {"event": "desktop-authenticated"},
                {"event": "owner-approval-recorded"},
                {"event": "effect-authorized"},
                {"event": "effect-outcome-recorded"},
                {"event": "request-replay-denied"},
                {"event": "service-restarted"},
            ]
        },
    }
    service = signed_service_receipt(service_body)
    service_path = artifact / "serviceBehaviorReceipt.json"
    dump(service_path, service)
    component_rows["serviceBehaviorReceipt"] = {
        "path": service_path.relative_to(artifact).as_posix(),
        "sha256": sha(service_path),
    }

    platform_body = {
        "schemaVersion": "3.0.0",
        "receiptType": "p1a-platform-behavioral-v3",
        "phase": "P1A",
        "platform": platform_name,
        "sourceCommit": commit,
        "sourceTree": tree,
        "packageSha256": package,
        "status": "passed",
        "sourceOnly": False,
        "completionEligible": True,
        "syntheticContractFixture": False,
        "exactBinding": exact,
        "exactRunBindingSha256": exact_hash,
        "artifactRoot": "artifact",
        "artifactDigestAlgorithm": "canonical-unpacked-v1",
        "artifactSha256": canonical_directory_digest(artifact),
        **component_rows,
    }
    platform_receipt = signed_ed25519(
        platform_body,
        seed=seed,
        key_id=key_id,
        purpose="p1a-platform-receipt",
    )
    receipt_path = receipt_dir / "receipt.json"
    dump(receipt_path, platform_receipt)

    purposes = ["p1a-platform-receipt", *P1A_COMPONENT_PURPOSES.values()]
    trust = {
        "schemaVersion": "1.0.0",
        "trustType": "p1a-evidence-trust-v1",
        "keys": [
            {
                "keyId": key_id,
                "algorithm": "ed25519",
                "publicKeyBase64": base64.b64encode(public_key(seed)).decode("ascii"),
                "purposes": sorted(set(purposes)),
                "platforms": [platform_name],
            }
        ],
    }
    trust_path = evidence / "EVIDENCE_TRUST.json"
    dump(trust_path, trust)

    live = {
        "repository": "owner/repo",
        "workflowRunId": exact["workflowRunId"],
        "runAttempt": exact["runAttempt"],
        "githubJobId": exact["githubJobId"],
        "headSha": commit,
        "jobName": exact["jobName"],
        "conclusion": "success",
    }
    graph = {
        name: row["sha256"] for name, row in component_rows.items()
    }
    graph["liveGithubSuccess"] = live
    receipt_rel = receipt_path.relative_to(project).as_posix()
    manifest = {
        "schemaVersion": "3.0.0",
        "phase": "P1A",
        "status": "passed",
        "completionClaim": True,
        "p2DependencySatisfied": True,
        "reviewedCommit": commit,
        "reviewedTree": tree,
        "packageSha256": package,
        "platformEvidence": {item: "passed" for item in ("windows", "macos", "linux")},
        "platformReceiptPath": {
            item: (
                receipt_rel
                if item == platform_name
                else f"release/evidence/P1A/platforms/unused/{item}/receipt.json"
            )
            for item in ("windows", "macos", "linux")
        },
        "platformReceiptSha256": {
            item: (
                sha(receipt_path)
                if item == platform_name
                else hashlib.sha256(f"unused:{item}".encode("utf-8")).hexdigest()
            )
            for item in ("windows", "macos", "linux")
        },
        "platformComponentGraph": {
            item: (graph if item == platform_name else {"liveGithubSuccess": live})
            for item in ("windows", "macos", "linux")
        },
        "evidenceTrustPath": "release/evidence/P1A/EVIDENCE_TRUST.json",
        "evidenceTrustSha256": sha(trust_path),
        "independentSecurityReview": "approved",
        "ownerApproval": "approved",
        "requiredWorkflowJobs": [
            "p1a-behavioral-windows",
            "p1a-behavioral-macos",
            "p1a-behavioral-linux",
        ],
    }
    manifest_path = evidence / "manifest.json"
    dump(manifest_path, manifest)
    return {
        "evidenceRoot": evidence,
        "manifest": manifest_path,
        "receipt": receipt_path,
        "trust": trust_path,
        "workerDenial": artifact / "workerDenialReceipt.json",
        "serviceBinary": service_binary,
        "connectorLibrary": connector_library,
        "workerLauncher": worker_launcher,
        "workerExecutable": worker_executable,
        "installer": installer,
        "uninstaller": uninstaller,
    }


def invoke(
    env: dict[str, str],
    project: pathlib.Path,
    policy: pathlib.Path,
    job: pathlib.Path,
    output: pathlib.Path,
    expect: bool = True,
) -> None:
    completed = subprocess.run(
        [
            sys.executable,
            str(ROOT / "tool/p2_runner_attestation.py"),
            "--project",
            str(project),
            "--policy",
            str(policy),
            "--job-identity",
            str(job),
            "--output",
            str(output),
            "--platform",
            "linux",
            "--commit-sha",
            "a" * 40,
        ],
        env=env,
        text=True,
        capture_output=True,
    )
    if (completed.returncode == 0) != expect:
        raise AssertionError((completed.returncode, completed.stdout, completed.stderr))


def main() -> int:
    if platform.system() != "Linux":
        print("P2 runner attestation V63 contract: SKIP non-Linux")
        return 0
    with tempfile.TemporaryDirectory(prefix="p2-runner-att-v63-") as temp_value:
        temp = pathlib.Path(temp_value)
        project = temp / "project"
        (project / ".github/workflows").mkdir(parents=True)
        shutil.copy2(
            ROOT / ".github/workflows/p2-owner-mode.yml",
            project / ".github/workflows/p2-owner-mode.yml",
        )
        roots = {name: temp / name for name in ("runtime", "package", "service", "e2e")}
        for path in roots.values():
            path.mkdir()
        config = make(temp, "configuration.json", '{"status":"passed"}\n')
        cleanup = make(temp, "cleanup-provider", "#!/bin/sh\nexit 1\n")
        cleanup.chmod(0o755)
        p1a = build_p1a_graph(project, seed=bytes(range(32)))
        p1a_summary = validate_merged_p1a_graph(
            project_root=project,
            platform="linux",
            evidence_root=p1a["evidenceRoot"],
            merged_manifest_path=p1a["manifest"],
            platform_receipt_path=p1a["receipt"],
            evidence_trust_path=p1a["trust"],
        )
        connector_config = temp / "p1a-connector-v2.json"
        dump(connector_config, {
            "schemaVersion":"2.0.0",
            "connectorLibraryPath":str(p1a["connectorLibrary"].resolve()),
            "maxResponseBytes":4194304,
            "completionEligible":True,
            "endpoint":{
                "platform":"linux","transport":"linux-af-unix","address":"/run/kristin-p1a/authority.sock",
                "serviceInstanceId":p1a_summary["serviceInstanceId"],
                "serviceBuildSha256":p1a_summary["serviceBuildSha256"],
                "connectorLibrarySha256":sha(p1a["connectorLibrary"]),
                "installerSha256":sha(p1a["installer"]),
                "serverIdentity":{"serviceUid":991,"desktopUid":1000,"workerUid":992,"workerGid":992},
                "osEnforcedIsolation":True,"workerPrincipalSeparated":True,"typedOperationsOnly":True,"nonExportableKeys":True,
            },
            "provenance":{
                "authorityType":"p1-isolated-authority-service-v2","activationType":"merged-p1a-v63-signed-evidence-activation",
                "p1AmendmentMerged":True,"p1AmendmentSchemaVersion":"3.0.0","independentP1aSecurityReviewApproved":True,
                "workerDenialTriPlatformPassed":True,"behavioralWindowsPassed":True,"behavioralMacosPassed":True,"behavioralLinuxPassed":True,
                "mergedCommit":p1a_summary["p1aMergedCommit"],"mergedTree":p1a_summary["p1aMergedTree"],
                "aggregateManifestSha256":p1a_summary["mergedManifestSha256"],"platformReceiptSha256":p1a_summary["platformReceiptSha256"],
                "evidenceTrustSha256":p1a_summary["evidenceTrustSha256"],"serviceBehaviorReceiptSha256":p1a_summary["serviceBehaviorReceiptSha256"],
                "workerDenialReceiptSha256":p1a_summary["workerDenialReceiptSha256"],"workerLauncherSha256":p1a_summary["workerLauncherSha256"],
                "workerExecutableSha256":p1a_summary["workerExecutableSha256"],"workerIdentitySha256":p1a_summary["workerIdentitySha256"],
                "denialTranscriptSha256":p1a_summary["denialTranscriptSha256"],"p1aPackageSha256":p1a_summary["p1aPackageSha256"],
                "privateAuthorityMaterialPresent":False,"arbitraryMessageSigningApi":False,"completionEligible":True,
                "policySnapshotSha256":"9"*64,
            },
        })
        other = {
            "controlledPackageArchive": make(roots["package"], "package.tgz"),
            "controlledServiceDefinition": make(roots["service"], "service.json"),
            "technologyNodeReceipt": make(temp, "node.json"),
            "technologyNativeReceipt": make(temp, "native.json"),
            "technologyDartReceipt": make(temp, "dart.json"),
        }
        files = {
            "p1AuthorityServiceMergedManifest": p1a["manifest"],
            "p1AuthorityServicePlatformReceipt": p1a["receipt"],
            "p1AuthorityServiceEvidenceTrust": p1a["trust"],
            "p1AuthorityServiceWorkerLauncher": p1a["workerLauncher"],
            "p1AuthorityServiceConnectorConfig": connector_config,
            **other,
        }
        directories = {
            "e2eWorkspaceRoot": roots["e2e"],
            "applicationRuntimeRoot": roots["runtime"],
            "p1AuthorityServiceEvidenceRoot": p1a["evidenceRoot"],
            "controlledPackageRoot": roots["package"],
            "controlledServiceRoot": roots["service"],
        }
        resources = {
            **{
                key: {"kind": "file", "path": str(path.resolve()), "sha256": sha(path)}
                for key, path in files.items()
            },
            **{
                key: {"kind": "directory", "path": str(path.resolve())}
                for key, path in directories.items()
            },
        }
        module = pathlib.Path(sys.modules["ed25519_ref"].__file__).resolve()
        shutil.copy2(module, temp / "ed25519_ref.py")
        seed = bytes(range(32))
        public = public_key(seed).hex()
        extra = {
            "labels": [
                "self-hosted",
                "kristin-p2",
                "linux",
                "interactive-desktop",
                "ubuntu-24.04",
            ],
            "hostPlatform": "linux",
            "hostImageSha256": "1" * 64,
            "configurationReceiptPath": str(config.resolve()),
            "configurationSha256": sha(config),
            "interactiveSession": {
                "loggedIn": True,
                "identity": "fixture-user",
                "sessionId": "fixture-desktop",
            },
            "permissions": {
                "clipboard": True,
                "screenCapture": True,
                "activeWindow": True,
                "accessibility": True,
            },
            "noConcurrentUntrustedWorkload": True,
            "workerCannotAccessAuthorityService": True,
            "p2ReceivesAuthoritySecrets": False,
            "controlledOperations": {
                "packageManager": "npm-local-controlled",
                "packageName": "fixture-package",
                "serviceProvider": "systemd-user",
                "serviceId": "fixture.service",
            },
            "controlledResources": resources,
        }
        extra_path = temp / "extra.json"
        dump(extra_path, extra)
        provider = temp / "attest-provider.py"
        provider.write_text(
            f'''#!/usr/bin/env python3
import argparse,datetime as dt,json,pathlib,sys
sys.path.insert(0,{str(temp)!r});from ed25519_ref import public_key,sign
SEED=bytes(range(32))
def canonical(v):return (json.dumps(v,sort_keys=True,separators=(",",":"),ensure_ascii=False)+"\\n").encode()
a=argparse.ArgumentParser();a.add_argument("--request");a.add_argument("--output");n=a.parse_args();r=json.loads(pathlib.Path(n.request).read_text());extra=json.loads(pathlib.Path({str(extra_path)!r}).read_text());now=dt.datetime.now(dt.timezone.utc);body={{**r,**extra,"schemaVersion":"5.0.0","attestationType":"p2-controlled-runner-attestation-v5","validFrom":(now-dt.timedelta(seconds=1)).isoformat(),"validUntil":(now+dt.timedelta(minutes=5)).isoformat(),"publicKeyHex":public_key(SEED).hex()}};body["signatureHex"]=sign(SEED,canonical(body)).hex();pathlib.Path(n.output).write_text(json.dumps(body,indent=2,sort_keys=True)+"\\n")
''',
            encoding="utf-8",
        )
        provider.chmod(0o755)
        labels = extra["labels"]
        runner_row = {
            "runnerId": 42,
            "runnerName": "fixture-runner",
            "runnerGroup": "kristin-p2-controlled",
            "runnerGroupId": 9,
            "labels": labels,
            "hostImageSha256": "1" * 64,
            "configurationReceiptPath": str(config.resolve()),
            "configurationSha256": sha(config),
            "attestationProviderPath": str(provider.resolve()),
            "attestationProviderSha256": sha(provider),
            "postRunCleanupProviderPath": str(cleanup.resolve()),
            "postRunCleanupProviderSha256": sha(cleanup),
        }
        policy = {
            "schemaVersion": "5.0.0",
            "policyType": "p2-controlled-runner-policy-v5",
            "requiredPermissions": [
                "clipboard",
                "screenCapture",
                "activeWindow",
                "accessibility",
            ],
            "maximumAttestationAgeSeconds": 900,
            "attestationTrustRoots": [public],
            "cleanupTrustRoots": [public],
            "provisioningPacketSha256": "5" * 64,
            "runners": {"linux": runner_row},
        }
        policy_path = temp / "policy.json"
        dump(policy_path, policy)
        job = {
            "schemaVersion": "1.0.0",
            "receiptType": "p2-github-job-identity-v1",
            "repository": "owner/repo",
            "repositoryId": 77,
            "workflowName": "P2 Owner Mode",
            "workflowPath": ".github/workflows/p2-owner-mode.yml",
            "workflowRef": "owner/repo/.github/workflows/p2-owner-mode.yml@refs/heads/test",
            "workflowRunId": "123",
            "runAttempt": 1,
            "jobName": "p2-behavioral-linux",
            "githubJobId": 456,
            "sourceCommit": "a" * 40,
            "runnerId": 42,
            "runnerName": "fixture-runner",
            "runnerGroupId": 9,
            "runnerGroup": "kristin-p2-controlled",
            "labels": labels,
            "platform": "linux",
            "apiPayloadSha256": "6" * 64,
            "runnerEphemeralSessionId": "ephemeral-123",
            "status": "observed",
        }
        job_path = temp / "job.json"
        dump(job_path, job)
        job_sha = sha(job_path)
        environment = {
            **os.environ,
            "GITHUB_REPOSITORY": "owner/repo",
            "GITHUB_REPOSITORY_ID": "77",
            "GITHUB_WORKFLOW": "P2 Owner Mode",
            "GITHUB_WORKFLOW_REF": job["workflowRef"],
            "GITHUB_RUN_ID": "123",
            "GITHUB_RUN_ATTEMPT": "1",
            "GITHUB_JOB": "p2-behavioral-linux",
            "GITHUB_SHA": "a" * 40,
            "KRISTIN_P2_GITHUB_JOB_ID": "456",
            "KRISTIN_P2_RUNNER_ID": "42",
            "RUNNER_NAME": "fixture-runner",
            "KRISTIN_P2_RUNNER_GROUP": "kristin-p2-controlled",
            "KRISTIN_P2_RUNNER_GROUP_ID": "9",
            "KRISTIN_P2_GITHUB_JOB_IDENTITY_SHA256": job_sha,
            "KRISTIN_P2_RUNNER_EPHEMERAL_SESSION_ID": "ephemeral-123",
        }
        output = temp / "receipt.json"
        invoke(environment, project, policy_path, job_path, output, True)
        receipt = json.loads(output.read_text(encoding="utf-8"))
        assert (
            receipt["p1AuthorityService"]["workerDenialReceiptSha256"]
            == sha(p1a["workerDenial"])
        )
        assert receipt["p1AuthorityService"]["workerIdentitySha256"] == "4" * 64
        assert receipt["completionEligibleForTaskClosure"] is False

        for key, value in (
            ("GITHUB_RUN_ID", "999"),
            ("GITHUB_RUN_ATTEMPT", "2"),
            ("GITHUB_JOB", "another-job"),
            ("KRISTIN_P2_GITHUB_JOB_ID", "999"),
            ("KRISTIN_P2_RUNNER_EPHEMERAL_SESSION_ID", "replayed-session"),
        ):
            invoke(
                {**environment, key: value},
                project,
                policy_path,
                job_path,
                temp / f"bad-{key}.json",
                False,
            )

        denial_body = json.loads(p1a["workerDenial"].read_text(encoding="utf-8"))
        denial_body["authorityConnectionDenied"] = False
        dump(p1a["workerDenial"], denial_body)
        invoke(
            environment,
            project,
            policy_path,
            job_path,
            temp / "bad-denial.json",
            False,
        )
    print("P2 exact runner/P1A V63 signed-graph attestation contract: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
