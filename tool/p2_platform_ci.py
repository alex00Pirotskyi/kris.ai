#!/usr/bin/env python3
"""Execute exact-SHA P2 product-path behavioral evidence on a governed runner.

This runner is deliberately unable to close P2 from source markers or helper-only
smoke tests. It builds the native lifecycle binaries from reviewed source, runs
Flutter product entry points, the authenticated automation host, native effects,
and task-specific postcondition checks, then emits only machine-bound artifacts.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import platform
import re
import shutil
import subprocess
import sys
import time

from p2_evidence_contract import TASKS
from p2_toolchains import load_exact_toolchains

PLATFORM = {"Windows": "windows", "Darwin": "macos", "Linux": "linux"}[platform.system()]


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_tail(value: str) -> str:
    value = value[-4000:]
    if any(marker in value.lower() for marker in ("token", "secret", "password", "authorization", "api_key")):
        return "[REDACTED: credential-shaped diagnostic]"
    return value


def run(command: list[str], cwd: pathlib.Path, *, timeout: int = 1800) -> dict:
    completed = subprocess.run(
        command,
        cwd=cwd,
        text=True,
        capture_output=True,
        timeout=timeout,
        stdin=subprocess.DEVNULL,
    )
    row = {
        "command": command,
        "returnCode": completed.returncode,
        "stdoutSha256": hashlib.sha256(completed.stdout.encode("utf-8", "replace")).hexdigest(),
        "stderrSha256": hashlib.sha256(completed.stderr.encode("utf-8", "replace")).hexdigest(),
    }
    if completed.returncode:
        row["stdoutTail"] = safe_tail(completed.stdout)
        row["stderrTail"] = safe_tail(completed.stderr)
        raise RuntimeError(json.dumps(row, indent=2))
    return row


def exactly_one(root: pathlib.Path, name: str) -> pathlib.Path:
    candidates = sorted(path for path in root.rglob(name) if path.is_file())
    if len(candidates) != 1:
        raise SystemExit(f"exact native output {name!r} required; found {candidates}")
    return candidates[0]


def native_source_rows(
    source: pathlib.Path,
    artifact_root: pathlib.Path,
    install_root: pathlib.Path,
) -> list[dict]:
    """Copy every reviewed native source into the exact CI artifact.

    Release validation must never trust source-path strings alone. The copied
    sources are hashed and bound to the same canonical artifact digest as the
    binaries and task results.
    """
    rows = []
    source_artifact_root = install_root / "sources"
    for path in sorted(item for item in source.rglob("*") if item.is_file()):
        relative = path.relative_to(source)
        copied = source_artifact_root / relative
        copied.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, copied)
        rows.append(
            {
                "path": copied.relative_to(artifact_root).as_posix(),
                "sourceRelativePath": relative.as_posix(),
                "bytes": copied.stat().st_size,
                "sha256": sha256_file(copied),
            }
        )
    if not rows:
        raise SystemExit("native source inventory must not be empty")
    return rows


def prepare_native_runtime(root: pathlib.Path, artifact_root: pathlib.Path, steps: list[dict]) -> dict:
    cmake = shutil.which("cmake")
    if not cmake:
        raise SystemExit("exact native CMake toolchain is mandatory")
    source = root / "automation_host/native" / ("windows" if PLATFORM == "windows" else "posix")
    build_root = artifact_root / f".native-build-{PLATFORM}"
    install_root = artifact_root / "native" / PLATFORM
    install_root.mkdir(parents=True, exist_ok=True)
    if build_root.exists():
        shutil.rmtree(build_root)

    configure = [cmake, "-S", str(source), "-B", str(build_root)]
    steps.append(run(configure, root))
    build = [cmake, "--build", str(build_root), "--config", "Release"]
    steps.append(run(build, root))

    suffix = ".exe" if PLATFORM == "windows" else ""
    binaries: dict[str, pathlib.Path] = {}
    if PLATFORM == "windows":
        binaries["windowsJobSupervisor"] = exactly_one(build_root, f"kristin_job_supervisor{suffix}")
    else:
        binaries["posixWatchdog"] = exactly_one(build_root, "kristin_posix_watchdog")
    binaries["nativePtyProbe"] = exactly_one(build_root, f"kristin_native_pty_probe{suffix}")

    installed: dict[str, pathlib.Path] = {}
    for key, built in binaries.items():
        target = install_root / built.name
        shutil.copy2(built, target)
        if PLATFORM != "windows":
            target.chmod(0o755)
        installed[key] = target

    if PLATFORM == "windows":
        os.environ["KRISTIN_WINDOWS_JOB_HELPER"] = str(installed["windowsJobSupervisor"])
    else:
        os.environ["KRISTIN_POSIX_WATCHDOG_HELPER"] = str(installed["posixWatchdog"])
    os.environ["KRISTIN_NATIVE_PTY_PROBE"] = str(installed["nativePtyProbe"])

    probe = subprocess.run(
        [str(installed["nativePtyProbe"])],
        cwd=root,
        text=True,
        capture_output=True,
        timeout=60,
        stdin=subprocess.DEVNULL,
    )
    try:
        probe_receipt = json.loads(probe.stdout.strip())
    except Exception as exc:
        raise SystemExit(f"native PTY probe emitted malformed receipt: {exc}")
    if probe.returncode != 0 or not isinstance(probe_receipt, dict) or probe_receipt.get("status") != "passed":
        raise SystemExit(f"native PTY probe failed: rc={probe.returncode} stderr={safe_tail(probe.stderr)!r}")

    cmake_version = subprocess.check_output([cmake, "--version"], text=True).splitlines()[0]
    cache = build_root / "CMakeCache.txt"
    cache_text = cache.read_text(encoding="utf-8", errors="replace") if cache.is_file() else ""
    compiler_key = "CMAKE_CXX_COMPILER" if PLATFORM == "windows" else "CMAKE_C_COMPILER"
    compiler_raw = ""
    for line in cache_text.splitlines():
        if line.startswith(compiler_key + ":FILEPATH="):
            compiler_raw = line.split("=", 1)[1].strip()
            break
    compiler_path = pathlib.Path(compiler_raw) if compiler_raw else None
    if compiler_path is None or not compiler_path.is_file():
        raise SystemExit(f"native compiler provenance missing from CMake cache: {compiler_key}")
    compiler_probe = subprocess.run(
        [str(compiler_path), "--version"], text=True, capture_output=True,
        timeout=30, stdin=subprocess.DEVNULL,
    )
    compiler_output = (compiler_probe.stdout + "\n" + compiler_probe.stderr).strip()
    if not compiler_output:
        compiler_probe = subprocess.run(
            [str(compiler_path)], text=True, capture_output=True,
            timeout=30, stdin=subprocess.DEVNULL,
        )
        compiler_output = (compiler_probe.stdout + "\n" + compiler_probe.stderr).strip()
    if not compiler_output:
        raise SystemExit("native compiler identity probe produced no output")
    compiler_provenance = {
        "kind": compiler_key,
        "path": str(compiler_path.resolve()),
        "executableSha256": sha256_file(compiler_path),
        "identity": compiler_output.splitlines()[0],
        "identityOutputSha256": hashlib.sha256(compiler_output.encode("utf-8", "replace")).hexdigest(),
    }
    manifest = {
        "schemaVersion": "1.0.0",
        "platform": PLATFORM,
        "buildSystem": cmake_version,
        "configureCommand": configure,
        "buildCommand": build,
        "compilerProvenance": compiler_provenance,
        "sourceFiles": native_source_rows(source, artifact_root, install_root),
        "binaries": {
            key: {
                "path": path.relative_to(artifact_root).as_posix(),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }
            for key, path in installed.items()
        },
        "nativePtyProbeReceipt": probe_receipt,
        "nativePtyProbeStdoutSha256": hashlib.sha256(probe.stdout.encode("utf-8", "replace")).hexdigest(),
        "nativePtyProbeStderrSha256": hashlib.sha256(probe.stderr.encode("utf-8", "replace")).hexdigest(),
    }
    manifest_path = install_root / "native-runtime-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    manifest["manifestPath"] = manifest_path.relative_to(artifact_root).as_posix()
    manifest["manifestSha256"] = sha256_file(manifest_path)
    shutil.rmtree(build_root)
    return manifest



def run_json(command: list[str], cwd: pathlib.Path, *, timeout: int = 1800) -> tuple[dict, dict]:
    started = time.time()
    completed = subprocess.run(command, cwd=cwd, text=True, capture_output=True, timeout=timeout, stdin=subprocess.DEVNULL)
    step = {
        "command": command,
        "returnCode": completed.returncode,
        "stdoutSha256": hashlib.sha256(completed.stdout.encode("utf-8", "replace")).hexdigest(),
        "stderrSha256": hashlib.sha256(completed.stderr.encode("utf-8", "replace")).hexdigest(),
        "durationMs": round((time.time() - started) * 1000, 3),
    }
    if completed.returncode:
        step["stdoutTail"] = safe_tail(completed.stdout)
        step["stderrTail"] = safe_tail(completed.stderr)
        raise RuntimeError(json.dumps(step, indent=2))
    try:
        data = json.loads(completed.stdout)
    except Exception as exc:
        raise SystemExit(f"JSON-producing command returned malformed output: {command}: {exc}") from exc
    if not isinstance(data, dict):
        raise SystemExit(f"JSON-producing command returned non-object: {command}")
    return step, data


def resource_path(attestation: dict, logical: str, *, kind: str = "file") -> pathlib.Path:
    row = (attestation.get("resolvedResources") or {}).get(logical)
    if not isinstance(row, dict) or row.get("kind") != kind:
        raise SystemExit(f"validated runner resource missing: {logical}")
    path = pathlib.Path(str(row.get("path", ""))).resolve()
    if (kind == "file" and not path.is_file()) or (kind == "directory" and not path.is_dir()):
        raise SystemExit(f"validated runner resource disappeared: {logical}")
    if kind == "file" and sha256_file(path) != row.get("sha256"):
        raise SystemExit(f"validated runner resource digest changed: {logical}")
    return path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--output", required=True)
    parser.add_argument("--workflow-run-id", required=True)
    parser.add_argument("--job-name", required=True)
    parser.add_argument("--artifact-name", required=True)
    parser.add_argument("--commit-sha", required=True)
    parser.add_argument("--runner-attestation", required=True)
    parser.add_argument("--package-sha256", required=True)
    parser.add_argument("--require-all", action="store_true")
    args = parser.parse_args()
    if re.fullmatch(r"[0-9a-f]{64}", args.package_sha256.lower()) is None:
        raise SystemExit("exact immutable P2 source-package SHA-256 required")
    args.package_sha256 = args.package_sha256.lower()
    root = pathlib.Path(args.project).resolve()
    output = pathlib.Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    artifact_root = output.parent / "artifact"
    if artifact_root.exists():
        shutil.rmtree(artifact_root)
    artifact_root.mkdir(parents=True, exist_ok=True)
    attestation_path = pathlib.Path(args.runner_attestation).resolve()
    if not attestation_path.is_file():
        raise SystemExit("validated controlled-runner attestation receipt is mandatory")
    runner_attestation = json.loads(attestation_path.read_text(encoding="utf-8"))
    exact_binding = runner_attestation.get("exactBinding")
    if (
        runner_attestation.get("schemaVersion") != "5.0.0"
        or runner_attestation.get("receiptType") != "p2-controlled-runner-attestation-receipt-v5"
        or runner_attestation.get("status") != "passed"
        or runner_attestation.get("platform") != PLATFORM
        or runner_attestation.get("postRunCleanupObserved") is not False
        or runner_attestation.get("completionEligibleForTaskClosure") is not False
        or not isinstance(exact_binding, dict)
        or exact_binding.get("sourceCommit") != args.commit_sha
        or str(exact_binding.get("workflowRunId")) != str(args.workflow_run_id)
        or exact_binding.get("jobName") != args.job_name
        or exact_binding.get("repository") != os.environ.get("GITHUB_REPOSITORY")
        or str(exact_binding.get("repositoryId")) != str(os.environ.get("GITHUB_REPOSITORY_ID", ""))
        or exact_binding.get("workflowName") != os.environ.get("GITHUB_WORKFLOW")
        or exact_binding.get("workflowPath") != ".github/workflows/p2-owner-mode.yml"
        or exact_binding.get("workflowFileSha256") != sha256_file(root / ".github/workflows/p2-owner-mode.yml")
        or exact_binding.get("workflowRef") != os.environ.get("GITHUB_WORKFLOW_REF")
        or str(exact_binding.get("runAttempt")) != str(os.environ.get("GITHUB_RUN_ATTEMPT", ""))
        or exact_binding.get("jobName") != os.environ.get("GITHUB_JOB")
        or str(exact_binding.get("githubJobId")) != str(os.environ.get("KRISTIN_P2_GITHUB_JOB_ID", ""))
        or str(exact_binding.get("runnerId")) != str(os.environ.get("KRISTIN_P2_RUNNER_ID", ""))
        or exact_binding.get("runnerName") != os.environ.get("RUNNER_NAME")
        or exact_binding.get("runnerGroup") != os.environ.get("KRISTIN_P2_RUNNER_GROUP")
        or str(exact_binding.get("runnerGroupId")) != str(os.environ.get("KRISTIN_P2_RUNNER_GROUP_ID", ""))
        or exact_binding.get("githubJobIdentitySha256") != os.environ.get("KRISTIN_P2_GITHUB_JOB_IDENTITY_SHA256")
        or exact_binding.get("runnerEphemeralSessionId") != os.environ.get("KRISTIN_P2_RUNNER_EPHEMERAL_SESSION_ID")
    ):
        raise SystemExit("validated runner receipt is not bound to this exact repository/workflow/run/attempt/job/runner session")
    verification = runner_attestation.get("verification")
    if not isinstance(verification, dict) or not verification or any(value is not True for value in verification.values()):
        raise SystemExit("runner receipt verification set incomplete")
    if runner_attestation.get("noConcurrentUntrustedWorkload") is not True:
        raise SystemExit("runner exclusivity invalid")
    roots = runner_attestation.get("resolvedRoots")
    if not isinstance(roots, dict):
        raise SystemExit("runner root binding missing")
    e2e_root = pathlib.Path(str(roots.get("e2eWorkspaceRoot", ""))).resolve()
    runtime_stage_root = pathlib.Path(str(roots.get("applicationRuntimeRoot", ""))).resolve()
    if not e2e_root.is_dir() or not runtime_stage_root.is_dir():
        raise SystemExit("runner E2E/application runtime roots unavailable")
    expected_runtime_parent = (e2e_root / "runtime" / "p2").resolve()
    if runtime_stage_root != expected_runtime_parent:
        raise SystemExit("attested application runtime root must equal application data runtime/p2")

    toolchains = load_exact_toolchains(root)
    steps: list[dict] = []
    actual_sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    actual_tree = subprocess.check_output(["git", "rev-parse", "HEAD^{tree}"], cwd=root, text=True).strip()
    if actual_sha != args.commit_sha:
        raise SystemExit("platform CI commit does not match requested exact SHA")
    steps.append(run(["git", "rev-parse", "HEAD"], root))

    node = shutil.which("node"); npm = shutil.which("npm"); flutter = shutil.which("flutter"); dart = shutil.which("dart")
    if not all((node, npm, flutter, dart)):
        raise SystemExit("exact Node, npm, Flutter, and Dart toolchains are mandatory")
    actual_python = platform.python_version()
    if actual_python != toolchains["python"]:
        raise SystemExit(f"Python version mismatch: {actual_python} != {toolchains['python']}")
    node = str(pathlib.Path(node).resolve())

    node_version = subprocess.check_output([node, "--version"], text=True).strip().lstrip("v")
    flutter_info = json.loads(subprocess.check_output([flutter, "--version", "--machine"], text=True))
    dart_version_output = subprocess.check_output([dart, "--version"], text=True, stderr=subprocess.STDOUT).strip()
    dart_match = __import__("re").search(r"Dart SDK version:\s*([^\s]+)", dart_version_output)
    if node_version != toolchains["node"] or flutter_info.get("frameworkVersion") != toolchains["flutter"] or dart_match is None or dart_match.group(1) != toolchains["dart"]:
        raise SystemExit("exact Node/Flutter/Dart toolchain mismatch")

    steps.append(run([sys.executable, "tool/toolchain_lock_test.py", "--source-only"], root))
    steps.append(run([sys.executable, "tool/p2_toolchain_extension_test.py", "--project", str(root)], root))
    steps.append(run([sys.executable, "tool/p2_source_inventory_test.py", "--project", str(root)], root))
    steps.append(run([sys.executable, "tool/p2_evidence_contract_test.py"], root))
    steps.append(run([sys.executable, "tool/p2_runner_attestation_contract_test.py"], root))
    steps.append(run([sys.executable, "tool/p2_post_run_cleanup_contract_test.py"], root))
    steps.append(run([flutter, "pub", "get"], root))
    steps.append(run([dart, "format", "--output=none", "--set-exit-if-changed", "lib/product", "test/product"], root))
    steps.append(run([flutter, "analyze"], root))
    steps.append(run([npm, "test"], root / "automation_host"))

    native_runtime = prepare_native_runtime(root, artifact_root, steps)
    native_manifest_path = artifact_root / native_runtime["manifestPath"]
    if not native_manifest_path.is_file() or sha256_file(native_manifest_path) != native_runtime["manifestSha256"]:
        raise SystemExit("native runtime manifest binding failed")

    operations = runner_attestation.get("controlledOperations") or {}
    policy_path = pathlib.Path(str(runner_attestation.get("runnerPolicyPath", ""))).resolve()
    if not policy_path.is_file() or sha256_file(policy_path) != runner_attestation.get("runnerPolicySha256"):
        raise SystemExit("external runner policy changed")
    package_source = resource_path(runner_attestation, "controlledPackageArchive")
    service_definition = resource_path(runner_attestation, "controlledServiceDefinition")
    p1a_merged_manifest = resource_path(runner_attestation, "p1AuthorityServiceMergedManifest")
    p1a_platform_receipt = resource_path(runner_attestation, "p1AuthorityServicePlatformReceipt")
    p1a_evidence_trust = resource_path(runner_attestation, "p1AuthorityServiceEvidenceTrust")
    p1a_worker_launcher = resource_path(runner_attestation, "p1AuthorityServiceWorkerLauncher")
    p1a_connector_config = resource_path(runner_attestation, "p1AuthorityServiceConnectorConfig")
    p1a_evidence_root = pathlib.Path(str(roots["p1AuthorityServiceEvidenceRoot"])).resolve()
    p1a_summary = runner_attestation.get("p1AuthorityService")
    required_p1a_digests = (
        "mergedManifestSha256", "platformReceiptSha256", "evidenceTrustSha256",
        "serviceBehaviorReceiptSha256", "workerDenialReceiptSha256",
        "serviceBuildSha256", "workerLauncherSha256", "workerExecutableSha256",
        "workerIdentitySha256", "denialTranscriptSha256", "p1aPackageSha256",
    )
    if not isinstance(p1a_summary, dict) or any(
        not isinstance(p1a_summary.get(key), str) or len(p1a_summary[key]) != 64
        for key in required_p1a_digests
    ) or p1a_summary.get("completionEligible") is not True:
        raise SystemExit("validated P1A V63 signed evidence graph missing")
    runtime_provisioning_environment = {
        "KRISTIN_P2_CONTROLLED_PACKAGE_MANAGER": str(operations["packageManager"]),
        "KRISTIN_P2_CONTROLLED_PACKAGE_NAME": str(operations["packageName"]),
        "KRISTIN_P2_CONTROLLED_PACKAGE_SOURCE": str(package_source),
        "KRISTIN_P2_CONTROLLED_PACKAGE_PREFIX": str(pathlib.Path(str(roots["controlledPackageRoot"])) / "install"),
        "KRISTIN_P2_NPM_EXECUTABLE": str(pathlib.Path(npm).resolve()),
        "KRISTIN_P2_NATIVE_SERVICE_ID": str(operations["serviceId"]),
        "KRISTIN_P2_NATIVE_SERVICE_PROVIDER": str(operations["serviceProvider"]),
        "KRISTIN_P2_NATIVE_SERVICE_ATTESTATION": str(service_definition),
        "KRISTIN_P2_NATIVE_SERVICE_ATTESTATION_SHA256": sha256_file(service_definition),
        "KRISTIN_P2_RUNNER_ATTESTATION_RECEIPT": str(attestation_path),
        "KRISTIN_P2_RUNNER_ATTESTATION_SHA256": sha256_file(attestation_path),
        "KRISTIN_P2_RUNNER_POLICY": str(policy_path),
        "KRISTIN_P2_RUNNER_POLICY_SHA256": sha256_file(policy_path),
        "KRISTIN_P2_E2E_ROOT": str(e2e_root),
        "KRISTIN_P2_RUNNER_ID": str(exact_binding["runnerId"]),
        "KRISTIN_P2_RUNNER_GROUP": str(exact_binding["runnerGroup"]),
        "KRISTIN_P2_RUNNER_CONFIGURATION_SHA256": str(runner_attestation["configurationSha256"]),
        "KRISTIN_P2_TOOLCHAIN_EXTENSION_FINGERPRINT": str(toolchains["p2_fingerprint"]),
        "KRISTIN_P2_COMMIT_SHA": args.commit_sha,
        "KRISTIN_P2_SOURCE_PACKAGE_SHA256": args.package_sha256,
        "KRISTIN_P2_NATIVE_RUNTIME_MANIFEST": str(native_manifest_path.resolve()),
        "KRISTIN_P2_NATIVE_RUNTIME_MANIFEST_SHA256": native_runtime["manifestSha256"],
        "KRISTIN_P1A_MERGED_MANIFEST": str(p1a_merged_manifest),
        "KRISTIN_P1A_MERGED_MANIFEST_SHA256": sha256_file(p1a_merged_manifest),
        "KRISTIN_P1A_PLATFORM_RECEIPT": str(p1a_platform_receipt),
        "KRISTIN_P1A_PLATFORM_RECEIPT_SHA256": sha256_file(p1a_platform_receipt),
        "KRISTIN_P1A_EVIDENCE_TRUST": str(p1a_evidence_trust),
        "KRISTIN_P1A_EVIDENCE_TRUST_SHA256": sha256_file(p1a_evidence_trust),
        "KRISTIN_P1A_SERVICE_BEHAVIOR_RECEIPT_SHA256": p1a_summary["serviceBehaviorReceiptSha256"],
        "KRISTIN_P1A_WORKER_DENIAL_RECEIPT_SHA256": p1a_summary["workerDenialReceiptSha256"],
        "KRISTIN_P1A_WORKER_LAUNCHER_SHA256": p1a_summary["workerLauncherSha256"],
        "KRISTIN_P1A_WORKER_EXECUTABLE_SHA256": p1a_summary["workerExecutableSha256"],
        "KRISTIN_P1A_WORKER_IDENTITY_SHA256": p1a_summary["workerIdentitySha256"],
        "KRISTIN_P1A_DENIAL_TRANSCRIPT_SHA256": p1a_summary["denialTranscriptSha256"],
        "GITHUB_RUN_ID": str(exact_binding["workflowRunId"]),
        "GITHUB_RUN_ATTEMPT": str(exact_binding["runAttempt"]),
        "GITHUB_JOB": str(exact_binding["jobName"]),
        "GITHUB_REPOSITORY": str(exact_binding["repository"]),
        "GITHUB_WORKFLOW": str(exact_binding["workflowName"]),
        "GITHUB_WORKFLOW_REF": str(exact_binding["workflowRef"]),
        "RUNNER_NAME": str(exact_binding["runnerName"]),
    }
    runtime_provisioning_path = e2e_root / "runtime-provisioning.v1.json"
    runtime_provisioning_path.write_text(json.dumps({
        "schemaVersion":"1.0.0",
        "provisioningType":"kristin-p2-application-runtime-environment-v1",
        "containsSecrets":False,
        "commitSha":args.commit_sha,
        "runnerAttestationSha256":sha256_file(attestation_path),
        "environment":runtime_provisioning_environment,
    },indent=2,sort_keys=True)+"\n",encoding="utf-8")

    # Stage exact source/runtime bytes into an application-owned runtime root.
    # The restricted-principal launcher remains the exact separately installed
    # P1A-owned OS identity transition boundary. It is referenced and digest
    # bound rather than copied, because copying a setuid/AppContainer/signed
    # helper would destroy the installer-enforced ownership/signing semantics.
    installed_runtime = e2e_root / "runtime" / "p2" / "current"
    staged_node = (installed_runtime / "node" / pathlib.Path(node).name).resolve()
    staged_host = (installed_runtime / "automation_host" / "src" / "host.mjs").resolve()
    staged_cwd = (installed_runtime / "automation_host").resolve()
    connector_config = json.loads(p1a_connector_config.read_text(encoding="utf-8"))
    connector_endpoint = connector_config.get("endpoint") if isinstance(connector_config, dict) else None
    if not isinstance(connector_endpoint, dict) or connector_endpoint.get("address") != p1a_summary.get("authorityAddress"):
        raise SystemExit("activated P1A connector endpoint changed after runner attestation")
    server_identity = p1a_summary.get("endpointServerIdentity")
    if not isinstance(server_identity, dict) or not server_identity:
        raise SystemExit("activated P1A server identity missing")
    worker_policy = {
        "schemaVersion": "2.0.0",
        "platform": PLATFORM,
        "nodeExecutable": str(staged_node),
        "nodeSha256": sha256_file(pathlib.Path(node)),
        "hostScript": str(staged_host),
        "hostScriptSha256": sha256_file(root / "automation_host/src/host.mjs"),
        "workingDirectory": str(staged_cwd),
        "launcherPath": str(p1a_worker_launcher),
        "launcherSha256": sha256_file(p1a_worker_launcher),
        "authorityAddress": str(p1a_summary["authorityAddress"]),
        "sourceCommit": args.commit_sha,
        "sourceTree": actual_tree,
        "packageSha256": args.package_sha256,
        "linux": {
            "workerUid": int(server_identity.get("workerUid", -1)),
            "workerGid": int(server_identity.get("workerGid", -1)),
            "unshareMount": True,
            "unshareIpc": True,
            "unshareUts": True,
        },
        "windows": {
            "appContainerName": "Kristin.Agent.Worker",
            "expectedWorkerSid": str(server_identity.get("workerSid", "")),
            "capabilitySids": [],
        },
        "macos": {
            "sandboxProfile": str(server_identity.get("sandboxProfile", "kristin-worker-v63")),
            "expectedRequirement": str(server_identity.get("workerRequirement", server_identity.get("expectedRequirement", "anchor apple generic and identifier \"com.kristin.worker\""))),
            "authorityClientEntitlement": False,
        },
        "allowedEnvironmentKeys": [
            "SystemRoot", "WINDIR", "TEMP", "TMP", "LANG", "LC_ALL", "TERM",
            "KRISTIN_WORKER_SESSION_ID", "KRISTIN_RESTRICTED_WORKER",
            "KRISTIN_P1A_AUTHORITY_ADDRESS", "KRISTIN_P1A_BEHAVIOR_SESSION_ID",
        ],
    }
    if PLATFORM == "linux" and (worker_policy["linux"]["workerUid"] <= 0 or worker_policy["linux"]["workerGid"] <= 0):
        raise SystemExit("installed Linux P1A worker UID/GID missing")
    if PLATFORM == "windows" and not worker_policy["windows"]["expectedWorkerSid"]:
        raise SystemExit("installed Windows P1A worker SID missing")
    if PLATFORM == "macos" and not worker_policy["macos"]["expectedRequirement"]:
        raise SystemExit("installed macOS P1A worker code requirement missing")
    worker_policy_path = e2e_root / "worker-policy.v2.json"
    worker_policy_path.write_text(json.dumps(worker_policy, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if PLATFORM != "windows":
        worker_policy_path.chmod(0o600)

    runtime_command = [
        sys.executable, "tool/p2_stage_runtime_bundle.py", "--project", str(root),
        "--destination", str(installed_runtime), "--node-executable", node,
        "--source-commit", args.commit_sha, "--source-tree", actual_tree,
        "--provisioning-json", str(runtime_provisioning_path),
        "--restricted-worker-launcher", str(p1a_worker_launcher),
        "--restricted-worker-policy", str(worker_policy_path),
        "--interactive-desktop-adapter", str((root / "automation_host/src/interactive-desktop-adapter.mjs").resolve()),
        "--include-node-modules",
    ]
    binaries = native_runtime.get("binaries", {})
    if PLATFORM == "windows":
        runtime_command += ["--windows-job-helper", str((artifact_root / binaries["windowsJobSupervisor"]["path"]).resolve())]
    else:
        runtime_command += ["--posix-watchdog", str((artifact_root / binaries["posixWatchdog"]["path"]).resolve())]
    step, runtime_stage = run_json(runtime_command, root); steps.append(step)
    runtime_manifest_path = pathlib.Path(runtime_stage["manifest"]).resolve()
    if runtime_manifest_path.parent != installed_runtime or sha256_file(runtime_manifest_path) != runtime_stage["manifestSha256"]:
        raise SystemExit("application-owned runtime stage binding invalid")

    # The isolated P1A service is already installed outside the P2 runtime.
    # Copy the exact signed public P1A V63 graph, including the platform receipt's
    # artifact directory. No authority secret, protected handle, or signer is copied.
    p1a_evidence_dir = artifact_root / "authority-service"
    p1a_evidence_dir.mkdir(parents=True, exist_ok=True)
    p1a_manifest_copy = p1a_evidence_dir / "merged-manifest.json"
    p1a_trust_copy = p1a_evidence_dir / "evidence-trust.json"
    shutil.copyfile(p1a_merged_manifest, p1a_manifest_copy)
    shutil.copyfile(p1a_evidence_trust, p1a_trust_copy)
    p1a_platform_copy_dir = p1a_evidence_dir / "platform"
    shutil.copytree(p1a_platform_receipt.parent, p1a_platform_copy_dir)
    p1a_platform_copy = p1a_platform_copy_dir / p1a_platform_receipt.name
    if not p1a_platform_copy.is_file():
        raise SystemExit("copied P1A platform receipt missing")
    p1a_copies = {
        "mergedManifest": {"path": p1a_manifest_copy.relative_to(artifact_root).as_posix(), "sha256": sha256_file(p1a_manifest_copy)},
        "platformReceipt": {"path": p1a_platform_copy.relative_to(artifact_root).as_posix(), "sha256": sha256_file(p1a_platform_copy)},
        "evidenceTrust": {"path": p1a_trust_copy.relative_to(artifact_root).as_posix(), "sha256": sha256_file(p1a_trust_copy)},
        "evidenceRoot": {"path": p1a_evidence_dir.relative_to(artifact_root).as_posix()},
    }

    application_composition_path = (artifact_root / "application-composition" / PLATFORM / f"application-composition-{args.commit_sha}.json").resolve()
    application_composition_path.parent.mkdir(parents=True, exist_ok=True)
    steps.append(run([sys.executable, "tool/p2_patch_application_composition.py", "--project", str(root), "--verify-only", "--source-commit", args.commit_sha, "--output", str(application_composition_path)], root))
    application_composition = json.loads(application_composition_path.read_text(encoding="utf-8"))
    if (
        application_composition.get("resultType") != "p2-shipped-application-composition-patch-v5"
        or application_composition.get("sourceCommit") != args.commit_sha
        or application_composition.get("entryPoint") != "ProductRuntime.initialize"
        or application_composition.get("p2CompositionField") != "ProductRuntime.p2OwnerMode"
        or application_composition.get("p1AuthorityField") != "ProductRuntime.p1AuthorityService"
        or application_composition.get("p1AuthorityImplementation") != "merged-P1A-isolated-service"
        or application_composition.get("p2CanConstructP1Authority") is not False
        or application_composition.get("applicationOwnedRuntimeResources") is not True
    ):
        raise SystemExit("shipped shared-P1/application composition binding invalid")

    env_values = {
        "KRISTIN_INTERACTIVE_DESKTOP_ADAPTER": str((installed_runtime / "native/interactiveDesktopAdapter/interactive-desktop-adapter.mjs").resolve()),
        "KRISTIN_P2_CONTROLLED_PACKAGE_MANAGER": str(operations["packageManager"]),
        "KRISTIN_P2_CONTROLLED_PACKAGE_NAME": str(operations["packageName"]),
        "KRISTIN_P2_CONTROLLED_PACKAGE_SOURCE": str(package_source),
        "KRISTIN_P2_CONTROLLED_PACKAGE_PREFIX": str(pathlib.Path(str(roots["controlledPackageRoot"])) / "install"),
        "KRISTIN_P2_NPM_EXECUTABLE": str(pathlib.Path(npm).resolve()),
        "KRISTIN_P2_NATIVE_SERVICE_ID": str(operations["serviceId"]),
        "KRISTIN_P2_NATIVE_SERVICE_PROVIDER": str(operations["serviceProvider"]),
        "KRISTIN_P2_NATIVE_SERVICE_ATTESTATION": str(service_definition),
        "KRISTIN_P2_NATIVE_SERVICE_ATTESTATION_SHA256": sha256_file(service_definition),
        "KRISTIN_P2_TECH_NODE_RECEIPT": str(resource_path(runner_attestation, "technologyNodeReceipt")),
        "KRISTIN_P2_TECH_NATIVE_RECEIPT": str(resource_path(runner_attestation, "technologyNativeReceipt")),
        "KRISTIN_P2_TECH_DART_RECEIPT": str(resource_path(runner_attestation, "technologyDartReceipt")),
        "KRISTIN_P2_RUNNER_ATTESTATION_RECEIPT": str(attestation_path),
        "KRISTIN_P2_RUNNER_ATTESTATION_SHA256": sha256_file(attestation_path),
        "KRISTIN_P2_RUNNER_POLICY": str(policy_path),
        "KRISTIN_P2_RUNNER_POLICY_SHA256": sha256_file(policy_path),
        "KRISTIN_P2_E2E_ROOT": str(e2e_root),
        "KRISTIN_P2_TOOLCHAIN_EXTENSION_FINGERPRINT": str(toolchains["p2_fingerprint"]),
        "KRISTIN_P2_APPLICATION_COMPOSITION_EVIDENCE": str(application_composition_path),
        "KRISTIN_P2_COMMIT_SHA": args.commit_sha,
        "KRISTIN_P2_SOURCE_PACKAGE_SHA256": args.package_sha256,
        "KRISTIN_P2_NATIVE_RUNTIME_MANIFEST": str(native_manifest_path.resolve()),
        "KRISTIN_P2_NATIVE_RUNTIME_MANIFEST_SHA256": native_runtime["manifestSha256"],
        "KRISTIN_P2_APPLICATION_RUNTIME_MANIFEST": str(runtime_manifest_path),
        "KRISTIN_P2_APPLICATION_RUNTIME_MANIFEST_SHA256": runtime_stage["manifestSha256"],
        "KRISTIN_P1A_MERGED_MANIFEST": str(p1a_merged_manifest),
        "KRISTIN_P1A_MERGED_MANIFEST_SHA256": sha256_file(p1a_merged_manifest),
        "KRISTIN_P1A_PLATFORM_RECEIPT": str(p1a_platform_receipt),
        "KRISTIN_P1A_PLATFORM_RECEIPT_SHA256": sha256_file(p1a_platform_receipt),
        "KRISTIN_P1A_EVIDENCE_TRUST": str(p1a_evidence_trust),
        "KRISTIN_P1A_EVIDENCE_TRUST_SHA256": sha256_file(p1a_evidence_trust),
        "KRISTIN_P1A_SERVICE_BEHAVIOR_RECEIPT_SHA256": p1a_summary["serviceBehaviorReceiptSha256"],
        "KRISTIN_P1A_WORKER_DENIAL_RECEIPT_SHA256": p1a_summary["workerDenialReceiptSha256"],
        "KRISTIN_P1A_WORKER_LAUNCHER_SHA256": p1a_summary["workerLauncherSha256"],
        "KRISTIN_P1A_WORKER_EXECUTABLE_SHA256": p1a_summary["workerExecutableSha256"],
        "KRISTIN_P1A_WORKER_IDENTITY_SHA256": p1a_summary["workerIdentitySha256"],
        "KRISTIN_P1A_DENIAL_TRANSCRIPT_SHA256": p1a_summary["denialTranscriptSha256"],
        "GITHUB_RUN_ID": str(exact_binding["workflowRunId"]),
        "GITHUB_RUN_ATTEMPT": str(exact_binding["runAttempt"]),
        "GITHUB_JOB": str(exact_binding["jobName"]),
        "GITHUB_REPOSITORY": str(exact_binding["repository"]),
        "GITHUB_WORKFLOW": str(exact_binding["workflowName"]),
        "GITHUB_WORKFLOW_REF": str(exact_binding["workflowRef"]),
        "RUNNER_NAME": str(exact_binding["runnerName"]),
        "KRISTIN_P2_INTERACTIVE_DESKTOP": "1",
        "KRISTIN_P2_BEHAVIORAL_LANE_ATTESTED": "1",
    }
    # The shipped ProductRuntime consumes the immutable application-owned
    # provisioning resource. Process environment is used only by the governed
    # test harness for task selection/evidence destinations.
    for key, value in runtime_provisioning_environment.items():
        if key in env_values and env_values[key] != value:
            raise SystemExit(f"runtime provisioning/process harness conflict: {key}")
    os.environ.update(env_values)

    attestation_evidence = artifact_root / "runner" / "attestation.json"
    attestation_evidence.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(attestation_path, attestation_evidence)
    runtime_evidence = artifact_root / "runtime" / "runtime-manifest.v3.json"
    runtime_evidence.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(runtime_manifest_path, runtime_evidence)

    task_assertions: dict[str, dict] = {}
    for task in TASKS:
        task_path = artifact_root / "task-results" / PLATFORM / f"{task}.json"
        completed = subprocess.run([
            sys.executable, "tool/p2_task_platform_assertions.py", "--project", str(root), "--task", task,
            "--commit-sha", args.commit_sha, "--output", str(task_path), "--artifact-root", str(artifact_root),
            "--max-command-seconds", "1200",
        ], cwd=root, text=True, capture_output=True, stdin=subprocess.DEVNULL, env={**os.environ, **env_values})
        if not task_path.is_file():
            task_assertions[task] = {"status":"absent","sourceOnly":False,"assertions":[],"runnerReturnCode":completed.returncode}
            continue
        row = json.loads(task_path.read_text(encoding="utf-8"))
        if row.get("taskId") != task or row.get("commitSha") != args.commit_sha or row.get("platform") != PLATFORM:
            row = {"status":"malformed","sourceOnly":False,"assertions":[]}
        task_assertions[task] = {
            "status":row.get("status","malformed"),"sourceOnly":row.get("sourceOnly",True),"assertions":row.get("assertions",[]),
            "taskResultPath":task_path.relative_to(artifact_root).as_posix(),"taskResultSha256":sha256_file(task_path),
            "runnerReturnCode":completed.returncode,"runnerStdoutSha256":hashlib.sha256(completed.stdout.encode("utf-8","replace")).hexdigest(),
            "runnerStderrSha256":hashlib.sha256(completed.stderr.encode("utf-8","replace")).hexdigest(),
            **({"runnerStdoutTail":safe_tail(completed.stdout),"runnerStderrTail":safe_tail(completed.stderr)} if completed.returncode else {}),
        }
    all_pass = all(
        row.get("status") == "passed" and row.get("sourceOnly") is False and row.get("runnerReturnCode") == 0
        and isinstance(row.get("assertions"), list) and row["assertions"]
        and all(isinstance(item,dict) and item.get("observedStatus") == "passed" for item in row["assertions"])
        for row in task_assertions.values()
    )
    steps.append(run(["git", "diff", "--exit-code"], root))
    payload = {
        "schemaVersion":"5.0.0","receiptType":"p2-task-platform-provisional-v5","phase":"P2",
        "generatedAt":time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime()),"platform":PLATFORM,"runner":platform.platform(),
        "commitSha":args.commit_sha,"exactBinding":exact_binding,"workflowName":"P2 Owner Mode","workflowRunId":args.workflow_run_id,
        "jobName":args.job_name,"artifactName":args.artifact_name,"artifactSha256":"pending-launcher-binding",
        "artifactDigestAlgorithm":"pending-launcher-binding","status":"provisional_passed" if all_pass else "blocked",
        "sourceOnly":False,"completionEligible":False,"postRunCleanupObserved":False,"postRunCleanupRequired":True,
        "interactiveDesktopAttested":True,"behavioralLaneAttested":True,
        "applicationComposition":{"path":application_composition_path.relative_to(artifact_root).as_posix(),"sha256":sha256_file(application_composition_path),"entryPoint":"ProductRuntime.initialize","p2CompositionField":"ProductRuntime.p2OwnerMode","p1AuthorityField":"ProductRuntime.p1AuthorityService","p1AuthorityImplementation":"merged-P1A-isolated-service"},
        "applicationRuntime":{"manifestPath":runtime_evidence.relative_to(artifact_root).as_posix(),"manifestSha256":runtime_stage["manifestSha256"],"runtimeBuildSha256":runtime_stage["runtimeBuildSha256"],"sourceCheckoutIndependent":True},
        "p1AuthorityService":{
            "authorityType":"p1-isolated-authority-service-v2",
            "completionEligible":True,
            "osEnforcedIsolation":True,
            "workerPrincipalSeparated":True,
            "typedOperationsOnly":True,
            "nonExportableKeys":True,
            "workerDeniedByOs":True,
            "workerCannotAccessAuthorityService":True,
            "p2DelegationOnly":True,
            "rawAuthoritySecretsIncluded":False,
            "serviceInstanceId":p1a_summary.get("serviceInstanceId"),
            "serviceBuildSha256":p1a_summary["serviceBuildSha256"],
            "workerLauncherSha256":p1a_summary["workerLauncherSha256"],
            "workerExecutableSha256":p1a_summary["workerExecutableSha256"],
            "workerIdentitySha256":p1a_summary["workerIdentitySha256"],
            "denialTranscriptSha256":p1a_summary["denialTranscriptSha256"],
            "serviceBehaviorReceiptSha256":p1a_summary["serviceBehaviorReceiptSha256"],
            "workerDenialReceiptSha256":p1a_summary["workerDenialReceiptSha256"],
            "p1aMergedCommit":p1a_summary["p1aMergedCommit"],
            "p1aMergedTree":p1a_summary["p1aMergedTree"],
            "p1aPackageSha256":p1a_summary["p1aPackageSha256"],
            "installedWorkerLauncherPathSha256":hashlib.sha256(str(p1a_worker_launcher).encode("utf-8")).hexdigest(),
            "installedWorkerLauncherSha256":sha256_file(p1a_worker_launcher),
            "installedConnectorConfigSha256":sha256_file(p1a_connector_config),
            "authorityAddressSha256":hashlib.sha256(str(p1a_summary["authorityAddress"]).encode("utf-8")).hexdigest(),
            "mergedManifest":p1a_copies["mergedManifest"],
            "platformReceipt":p1a_copies["platformReceipt"],
            "evidenceTrust":p1a_copies["evidenceTrust"],
            "evidenceRoot":p1a_copies["evidenceRoot"],
        },
        "p2ToolchainExtensionFingerprint":toolchains["p2_fingerprint"],
        "runnerProvisioningPacketSha256":runner_attestation.get("provisioningPacketSha256"),
        "runnerAttestation":{"path":attestation_evidence.relative_to(artifact_root).as_posix(),"sha256":sha256_file(attestation_evidence),"runnerId":runner_attestation.get("runnerId"),"runnerName":runner_attestation.get("runnerName"),"runnerGroup":runner_attestation.get("runnerGroup"),"runnerEphemeralSessionId":runner_attestation.get("runnerEphemeralSessionId"),"configurationSha256":runner_attestation.get("configurationSha256"),"interactiveSession":runner_attestation.get("interactiveSession"),"permissions":runner_attestation.get("permissions"),"verification":verification,"workerCannotAccessAuthorityService":runner_attestation.get("workerCannotAccessAuthorityService"),"p2ReceivesAuthoritySecrets":runner_attestation.get("p2ReceivesAuthoritySecrets"),"postRunCleanupObserved":False},
        "toolchains":{**toolchains,"pythonRuntime":{"version":actual_python,"executable":str(pathlib.Path(sys.executable).resolve()),"executableSha256":sha256_file(pathlib.Path(sys.executable).resolve())},"nodeRuntime":{"version":node_version,"executable":node,"executableSha256":sha256_file(pathlib.Path(node))},"flutterRuntime":flutter_info,"dartVersion":dart_version_output},
        "taskAssertions":task_assertions,"baselineSteps":steps,"nativeRuntime":native_runtime,
    }
    output.write_text(json.dumps(payload,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print(json.dumps(payload,indent=2,sort_keys=True))
    if args.require_all and not all_pass: return 3
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
