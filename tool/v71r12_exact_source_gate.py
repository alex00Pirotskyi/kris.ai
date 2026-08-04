#!/usr/bin/env python3
"""Exact, read-only P1/P1A/P2 source gate for V71-R12 promotion.

The same program is executed twice:
1. locally on the clean recovery commit before it may be pushed; and
2. by every hosted Windows/macOS/Linux owner-risk job.

It centralizes the source-contract command list, generator ownership, source
manifest verification, handwritten Dart formatting, analyzer/tests, and Node
contracts. The gate fails closed if any command modifies tracked source.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import locale
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Any, Sequence

SCHEMA_VERSION = "1.0.0"
GATE_ID = "V71-R12-EXACT-SOURCE-GATE"
GENERATOR_SCRIPTS = (
    "tool/generate_prompt_studio_contracts.py",
    "tool/generate_protocol_contracts.py",
    "tool/generate_v170_contracts.py",
    "tool/generate_v180_contracts.py",
    "tool/generate_v190_contracts.py",
    "tool/generate_workflow_migrations.py",
)
GENERATED_CONTRACT_PATHS = (
    "lib/product/generated/prompt_studio_contracts.g.dart",
    "lib/product/generated/protocol_contracts.g.dart",
    "lib/product/generated/v170_contracts.g.dart",
    "lib/product/generated/v180_contracts.g.dart",
    "lib/product/generated/v190_contracts.g.dart",
    "lib/product/generated/workflow_migrations.g.dart",
)
HEX64 = re.compile(r"^[0-9a-f]{64}$")


TASK_IDS = tuple(f"P2-{number:03d}" for number in range(1, 15))
TECHNOLOGY_SPIKE_PATH = "release/evidence/P2-004/technology-spike.json"
BEHAVIORAL_DIAGNOSTIC_PATHS = tuple(
    [f"release/evidence/{task_id}/test-results.json" for task_id in TASK_IDS]
    + [TECHNOLOGY_SPIKE_PATH, "release/evidence/P2/local-behavioral-summary.json"]
)


class GateError(RuntimeError):
    pass


def fail(message: str) -> None:
    raise GateError(message)


def utc_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def decode(data: bytes | None) -> str:
    if data is None:
        return ""
    encodings = ("utf-8-sig", locale.getpreferredencoding(False), "cp1252", "cp437")
    seen: set[str] = set()
    for encoding in encodings:
        if not encoding or encoding.casefold() in seen:
            continue
        seen.add(encoding.casefold())
        try:
            return data.decode(encoding)
        except (LookupError, UnicodeDecodeError):
            pass
    return data.decode("utf-8", errors="replace")


def resolve_executable(name: str) -> str:
    value = shutil.which(name)
    if value is None:
        fail(f"required command missing: {name}")
    return value


def command_line(argv: Sequence[str]) -> list[str]:
    if not argv:
        fail("empty command")
    resolved = resolve_executable(argv[0])
    values = [resolved, *argv[1:]]
    if os.name == "nt" and Path(resolved).suffix.casefold() in {".bat", ".cmd"}:
        comspec = os.environ.get("COMSPEC") or resolve_executable("cmd.exe")
        return [comspec, "/d", "/s", "/c", subprocess.list2cmdline(values)]
    return values


def run_process(
    argv: Sequence[str],
    *,
    cwd: Path,
    timeout: int,
    env: dict[str, str],
) -> tuple[str, float]:
    invocation = command_line(argv)
    started = time.monotonic()
    try:
        completed = subprocess.run(
            invocation,
            cwd=cwd,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=False,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        fail(f"command launch failed: {' '.join(argv)}: {error}")
    output = decode(completed.stdout)
    if output:
        print(output, end="" if output.endswith("\n") else "\n")
    duration = time.monotonic() - started
    if completed.returncode != 0:
        fail(
            f"command failed ({completed.returncode}): {' '.join(argv)}\n"
            f"last output:\n{output[-6000:]}"
        )
    return output, duration


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        fail(f"JSON object required: {path}")
    return value


def canonical_source_bytes(data: bytes) -> bytes:
    """Normalize only UTF-8 text line endings for cross-platform source identity."""
    if b"\0" in data:
        return data
    try:
        data.decode("utf-8")
    except UnicodeDecodeError:
        return data
    return data.replace(b"\r\n", b"\n")


def source_sha256(path: Path) -> str:
    return hashlib.sha256(canonical_source_bytes(path.read_bytes())).hexdigest()


def source_paths(project: Path) -> list[str]:
    policy_path = project / "tool/source_tree_policy.py"
    if not policy_path.is_file():
        fail("tool/source_tree_policy.py missing")
    spec = importlib.util.spec_from_file_location("v71r12_source_policy", policy_path)
    if spec is None or spec.loader is None:
        fail("cannot load source-tree policy")
    policy = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = policy
    spec.loader.exec_module(policy)
    raw = subprocess.check_output(
        ["git", "-C", str(project), "ls-files", "--cached", "--others", "--exclude-standard", "-z"]
    )
    values = sorted(
        {
            item.decode("utf-8", errors="surrogateescape").replace("\\", "/")
            for item in raw.split(b"\0")
            if item
        }
    )
    return [
        relative
        for relative in values
        if relative != "SOURCE_MANIFEST.sha256"
        and not policy.is_generated_path(relative)
        and (project / relative).is_file()
    ]


def verify_source_manifest(project: Path) -> dict[str, Any]:
    manifest = project / "SOURCE_MANIFEST.sha256"
    if not manifest.is_file():
        fail("SOURCE_MANIFEST.sha256 missing")
    raw = manifest.read_bytes()
    if b"\r" in raw or not raw.endswith(b"\n") or raw.endswith(b"\n\n"):
        fail("SOURCE_MANIFEST.sha256 must use LF and exactly one terminal newline")
    rows: dict[str, str] = {}
    previous = ""
    for number, line in enumerate(raw.decode("utf-8").splitlines(), start=1):
        if "  " not in line:
            fail(f"invalid source manifest row {number}")
        digest, relative = line.split("  ", 1)
        if not HEX64.fullmatch(digest) or not relative or relative.startswith("/") or "\\" in relative:
            fail(f"invalid source manifest row {number}: {line!r}")
        if relative in rows:
            fail(f"duplicate source manifest path: {relative}")
        if previous and relative <= previous:
            fail(f"source manifest paths are not strictly sorted: {previous!r}, {relative!r}")
        previous = relative
        rows[relative] = digest
    expected_paths = source_paths(project)
    if list(rows) != expected_paths:
        missing = sorted(set(expected_paths) - set(rows))[:20]
        extra = sorted(set(rows) - set(expected_paths))[:20]
        fail(f"source manifest scope mismatch: missing={missing} extra={extra}")
    mismatches: list[str] = []
    for relative, expected in rows.items():
        actual = source_sha256(project / relative)
        if actual != expected:
            mismatches.append(f"{relative}: {actual} != {expected}")
    if mismatches:
        fail("source manifest digest mismatch:\n" + "\n".join(mismatches[:20]))
    result = {
        "entryCount": len(rows),
        "manifestSha256": hashlib.sha256(raw).hexdigest(),
        "exactPathSet": True,
        "exactDigests": True,
        "canonicalTextDigests": True,
        "lfStable": True,
    }
    print(json.dumps({"sourceManifest": result}, sort_keys=True))
    return result


def tracked_status(project: Path, env: dict[str, str]) -> str:
    output, _ = run_process(
        ["git", "status", "--porcelain", "--untracked-files=no"],
        cwd=project,
        timeout=60,
        env=env,
    )
    return output.strip()


def _git_capture(project: Path, args: Sequence[str], env: dict[str, str]) -> tuple[int, str]:
    completed = subprocess.run(
        command_line(["git", *args]),
        cwd=project,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=False,
        check=False,
    )
    return completed.returncode, decode(completed.stdout)


def _porcelain_path(line: str) -> str:
    if len(line) < 4 or line[2] != " ":
        fail(f"unsupported Git porcelain status row: {line!r}")
    return line[3:].split(" -> ")[-1].replace("\\", "/")


def _git_show_bytes(project: Path, args: Sequence[str], env: dict[str, str]) -> tuple[int, bytes]:
    completed = subprocess.run(
        command_line(["git", *args]),
        cwd=project,
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=False,
        check=False,
    )
    return completed.returncode, completed.stdout or b""


def normalize_handwritten_dart_checkout_bytes(
    project: Path, env: dict[str, str]
) -> dict[str, Any]:
    """Fix CRLF-checkout drift in tracked ``*.dart`` files before format-sensitive gates run.

    Git for Windows with ``core.autocrlf=true`` and no ``.gitattributes`` override
    for ``*.dart`` converts LF blobs to CRLF on checkout. Because ``git`` applies
    the same conversion when comparing, ``git status``/``git diff`` can report a
    perfectly clean tree even though the files physically contain CRLF on disk.
    External tools that read raw bytes -- specifically ``dart format --check`` --
    are not aware of this and flag every such file as needing reformatting, even
    though nothing about its real, committed content changed.

    This function only ever rewrites a working-tree file when stripping ``\\r``
    from it reproduces the HEAD blob byte-for-byte. Any file that differs from
    HEAD in some other way (i.e. genuine uncommitted work) is left completely
    untouched and reported instead of being silently overwritten.
    """
    rc, listed = _git_capture(project, ["ls-files", "-z", "--", "*.dart"], env)
    if rc != 0:
        fail(f"cannot list tracked Dart sources: {listed.strip()}")
    relatives = [value for value in listed.split("\x00") if value]
    normalized: list[str] = []
    dirty: list[str] = []
    for relative in relatives:
        path = project / relative
        if not path.is_file():
            continue
        blob_rc, blob = _git_show_bytes(project, ["show", f"HEAD:{relative}"], env)
        if blob_rc != 0:
            continue  # not present at HEAD (e.g. newly added, not yet committed)
        current = path.read_bytes()
        if current == blob:
            continue
        if current.replace(b"\r\n", b"\n") == blob:
            path.write_bytes(blob)
            normalized.append(relative)
        else:
            dirty.append(relative)
    if dirty:
        fail(
            "tracked Dart sources differ from HEAD beyond CRLF checkout metadata; "
            f"refusing to touch them: {dirty[:12]}"
        )
    if normalized:
        status = tracked_status(project, env)
        if status:
            fail(
                "handwritten Dart checkout-byte normalization left tracked drift:\n"
                f"{status}"
            )
    return {
        "handwrittenDartCheckoutBytesNormalized": bool(normalized),
        "handwrittenDartCheckoutNormalizedPaths": normalized,
    }


def normalize_generated_contract_checkout_metadata(
    project: Path, env: dict[str, str]
) -> dict[str, Any]:
    """Clear Windows CRLF-only status drift without changing Git content.

    Git for Windows with ``core.autocrlf=true`` can report generator-owned Dart
    files as `` M`` after a generator rewrites semantically identical CRLF
    bytes. In that state both ``git diff --exit-code`` and every generator
    ``--check`` pass, but raw porcelain remains dirty and blocks the SDK gate.

    This transaction accepts only unstaged rows for the six reviewed generated
    paths, proves both staged and unstaged diffs are content-empty, and then
    uses ``git add --renormalize`` solely to refresh Git's index/stat view. A
    cached content change is immediately rolled back and rejected.
    """
    rc, raw = _git_capture(project, ["status", "--porcelain=v1", "--untracked-files=no"], env)
    if rc != 0:
        fail(f"cannot inspect generated-contract checkout state: {raw.strip()}")
    lines = [line for line in raw.splitlines() if line]
    if not lines:
        return {
            "generatedContractCheckoutMetadataNormalized": False,
            "generatedContractCheckoutMetadataPaths": [],
            "generatedContractIndexContentUnchanged": True,
        }
    paths: list[str] = []
    allowed = set(GENERATED_CONTRACT_PATHS)
    for line in lines:
        if not line.startswith(" M "):
            fail(f"tracked working tree contains non-normalization status before SDK gate: {line}")
        relative = _porcelain_path(line)
        if relative not in allowed:
            fail(f"tracked working tree contains non-generated change before SDK gate: {relative}")
        paths.append(relative)
    paths = sorted(set(paths))
    for args, label in (
        (["diff", "--quiet", "--", *paths], "unstaged"),
        (["diff", "--cached", "--quiet", "--", *paths], "staged"),
    ):
        diff_rc, diff_output = _git_capture(project, args, env)
        if diff_rc != 0:
            fail(f"generated-contract {label} content drift is not normalization-only: {diff_output.strip()}")
    add_rc, add_output = _git_capture(project, ["add", "--renormalize", "--", *paths], env)
    if add_rc != 0:
        fail(f"cannot refresh generated-contract checkout metadata: {add_output.strip()}")
    cached_rc, cached_output = _git_capture(project, ["diff", "--cached", "--quiet", "--", *paths], env)
    if cached_rc != 0:
        _git_capture(project, ["restore", "--source=HEAD", "--staged", "--", *paths], env)
        fail(
            "generated-contract renormalization changed indexed content; refusing exact gate: "
            + cached_output.strip()
        )
    after_rc, after = _git_capture(project, ["status", "--porcelain=v1", "--untracked-files=no"], env)
    if after_rc != 0 or after.strip():
        fail(f"generated-contract metadata normalization did not restore a clean tree:\n{after}")
    return {
        "generatedContractCheckoutMetadataNormalized": True,
        "generatedContractCheckoutMetadataPaths": paths,
        "generatedContractIndexContentUnchanged": True,
    }


def validate_source_only_technology_spike(value: dict[str, Any], *, label: str) -> None:
    if value.get("schemaVersion") != "1.0.0":
        fail(f"{label} schema invalid: {value}")
    if value.get("sourceOnly") is not True or value.get("completionEligible") is not False:
        fail(f"{label} source-only boundary invalid: {value}")
    decision = value.get("decision")
    if not isinstance(decision, dict) or decision.get("status") != "blocked_external_tri_platform_measurement_required":
        fail(f"{label} decision invalid: {decision}")
    if value.get("platformMeasurements") not in (None, {}):
        fail(f"{label} unexpectedly contains platform completion evidence")


def validate_behavioral_diagnostic(worktree: Path) -> dict[str, Any]:
    spike_path = worktree / TECHNOLOGY_SPIKE_PATH
    validate_source_only_technology_spike(load_json(spike_path), label="behavioral technology spike")
    summary_path = worktree / "release/evidence/P2/local-behavioral-summary.json"
    summary = load_json(summary_path)
    expected_tasks = {task_id: "source_only" for task_id in TASK_IDS}
    if summary.get("schemaVersion") != "1.0.0":
        fail(f"behavioral summary schema invalid: {summary}")
    if summary.get("tasks") != expected_tasks:
        fail(f"behavioral summary task states invalid: {summary.get('tasks')}")
    claims = summary.get("claims")
    if not isinstance(claims, dict) or any(value is not False for value in claims.values()):
        fail(f"behavioral summary claims must remain false: {claims}")
    if summary.get("platform") not in {"win32", "darwin", "linux"}:
        fail(f"behavioral summary platform invalid: {summary.get('platform')}")
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", str(summary.get("generatedAt", ""))) is None:
        fail("behavioral summary generatedAt invalid")
    for task_id in TASK_IDS:
        result_path = worktree / "release/evidence" / task_id / "test-results.json"
        value = load_json(result_path)
        if value.get("schemaVersion") != "1.0.0" or value.get("taskId") != task_id:
            fail(f"behavioral task result identity invalid: {task_id}: {value}")
        if value.get("status") != "source_only":
            fail(f"behavioral task result overclaims completion: {task_id}: {value}")
        if value.get("platform") not in {"win32", "darwin", "linux"}:
            fail(f"behavioral task result platform invalid: {task_id}: {value}")
        if value.get("completedTaskPacket") is not None or value.get("platformReceipts") not in (None, {}):
            fail(f"behavioral task result contains completion evidence: {task_id}")
        tests = value.get("tests")
        if not isinstance(tests, list) or any(not isinstance(row, dict) for row in tests):
            fail(f"behavioral task test rows invalid: {task_id}")
        if any(row.get("status") == "failed" for row in tests):
            fail(f"behavioral task contains failed diagnostic: {task_id}")
    return {
        "behavioralEvidenceIsolated": True,
        "behavioralEvidenceDisposableWorktree": True,
        "behavioralEvidenceTaskCount": len(TASK_IDS),
        "behavioralTechnologySpikeValidated": True,
        "governedWorktreeUnchangedByBehavioralGate": True,
    }


def run_behavioral_gate_isolated(
    project: Path,
    python: str,
    env: dict[str, str],
    step: Any,
    max_timeout: int,
) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="kristin-v71r12-behavioral-") as temporary:
        worktree = Path(temporary) / "worktree"
        run_process(
            ["git", "worktree", "add", "--detach", str(worktree), "HEAD"],
            cwd=project,
            timeout=min(300, max_timeout),
            env=env,
        )
        try:
            step(
                "P2 fast source behavior (isolated disposable worktree)",
                (python, "tool/p2_behavioral_gate.py", "--project", ".", "--fast-source-only"),
                timeout=1200,
                cwd=worktree,
            )
            result = validate_behavioral_diagnostic(worktree)
            changed = tracked_status(worktree, env)
            if not changed:
                fail("behavioral diagnostic unexpectedly produced no isolated evidence")
            changed_paths = []
            for line in changed.splitlines():
                if len(line) >= 3 and line[2] == " ":
                    raw = line[3:]
                elif len(line) >= 2 and line[1] == " ":
                    raw = line[2:]
                else:
                    raw = ""
                raw = raw.split(" -> ")[-1].replace("\\", "/")
                if raw:
                    changed_paths.append(raw)
            unexpected = sorted(set(changed_paths) - set(BEHAVIORAL_DIAGNOSTIC_PATHS))
            if unexpected:
                fail(f"behavioral diagnostic changed unexpected files: {unexpected}")
            result["behavioralEvidenceChangedPaths"] = sorted(set(changed_paths))
            return result
        finally:
            subprocess.run(
                command_line(["git", "worktree", "remove", "--force", str(worktree)]),
                cwd=project,
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )
            subprocess.run(
                command_line(["git", "worktree", "prune"]),
                cwd=project,
                env=env,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )


def run_gate(project: Path, *, json_output: Path | None, timeout_minutes: int) -> dict[str, Any]:
    project = project.resolve()
    if not (project / ".git").exists():
        fail(f"project is not a Git worktree: {project}")
    env = os.environ.copy()
    env.update(
        {
            "PYTHONUTF8": "1",
            "PYTHONIOENCODING": "utf-8",
            "CI": "true",
            "KRISTIN_OWNER_RISK_QA": "1",
            "P1A_PYTHON_VERSION": env.get("P1A_PYTHON_VERSION", "3.13.5"),
            "KRISTIN_V70_P2_PACKAGE_SHA256": env.get(
                "KRISTIN_V70_P2_PACKAGE_SHA256",
                "7b0d77d8956f05ff907ca7463b0d787dcebf93a60426aab105be2b610e6072b0",
            ),
            "npm_config_engine_strict": "false",
        }
    )
    max_timeout = max(60, timeout_minutes * 60)
    steps: list[dict[str, Any]] = []

    def step(
        name: str,
        argv: Sequence[str],
        timeout: int = 600,
        cwd: Path | None = None,
    ) -> str:
        actual_cwd = project if cwd is None else cwd.resolve()
        print(f"\n=== {name} ===")
        output, duration = run_process(
            list(argv), cwd=actual_cwd, timeout=min(timeout, max_timeout), env=env
        )
        steps.append(
            {
                "name": name,
                "command": list(argv),
                "cwd": "." if actual_cwd == project else "isolated-disposable-worktree",
                "durationSeconds": round(duration, 3),
                "passed": True,
            }
        )
        return output

    python = sys.executable
    python_steps: tuple[tuple[str, tuple[str, ...]], ...] = (
        ("Roadmap control unit tests", (python, "tool/roadmap_control_test.py")),
        ("P0-008 roadmap gate", (python, "tool/p0_008_roadmap_test.py", "--project", ".")),
        ("Strict roadmap validation", (python, "tool/roadmap_control.py", "validate", "--project", ".", "--strict")),
        ("Roadmap generated-state check", (python, "tool/roadmap_control.py", "render", "--project", ".", "--check")),
        ("P0-003 repair gate", (python, "tool/p0_003_repair_test.py")),
        ("P1 exit gate", (python, "tool/p1_exit_gate_test.py", "--project", ".")),
        ("P1A source inventory", (python, "tool/p1a_source_inventory_test.py", "--project", ".")),
        ("P1A authority contract", (python, "tool/p1a_authority_contract_test.py", "--project", ".")),
        ("P1A runtime security regression", (python, "tool/p1a_runtime_security_regression_test.py", "--project", ".")),
        ("P1A text EOF contract", (python, "tool/p1a_text_eof_contract_test.py", "--project", ".")),
        ("P1A installer secret contract", (python, "tool/p1a_installer_secret_contract_test.py", "--project", ".")),
        ("P1A build authority snapshot", (python, "tool/p1a_build_authority_snapshot_test.py", "--project", ".")),
        ("P1A toolchain extension", (python, "tool/p1a_toolchain_extension_test.py", "--project", ".")),
        ("P1A product runtime patch", (python, "tool/p1a_patch_product_runtime_test.py", "--project", ".")),
        ("P1A evidence forgery regression", (python, "tool/p1a_evidence_forgery_test.py", "--project", ".")),
        ("P1A finalizer contract", (python, "tool/p1a_finalizer_contract_test.py", "--project", ".")),
        ("P1A source-only exit", (python, "tool/p1a_exit_gate_test.py", "--project", ".", "--source-only")),
        ("P2 toolchain extension", (python, "tool/p2_toolchain_extension_test.py", "--project", ".")),
        ("P2 source inventory", (python, "tool/p2_source_inventory_test.py", "--project", ".")),
        ("P2 evidence contract", (python, "tool/p2_evidence_contract_test.py", "--project", ".")),
        ("P2 application composition", (python, "tool/p2_patch_application_composition_test.py", "--project", ".")),
        ("P2 runtime resource contract", (python, "tool/p2_runtime_resource_contract_test.py")),
        ("P2 shared P1 authority", (python, "tool/p2_shared_p1_authority_contract_test.py", "--project", ".", "--owner-risk-qa")),
        ("P2 runner attestation", (python, "tool/p2_runner_attestation_contract_test.py", "--project", ".")),
        ("P2 post-run cleanup", (python, "tool/p2_post_run_cleanup_contract_test.py", "--project", ".")),
        ("P2 strict finalizer", (python, "tool/p2_strict_finalizer_contract_test.py", "--project", ".")),
        ("P2 task assertion CLI", (python, "tool/p2_task_assertion_cli_test.py", "--project", ".", "--max-command-seconds", "5")),
    )
    for name, argv in python_steps:
        step(name, argv, timeout=1200)

    with tempfile.TemporaryDirectory(prefix="kristin-v71r12-exact-gate-") as temporary:
        temp = Path(temporary)
        analyzer_json = temp / "owner-analyzer.json"
        step(
            "Owner-risk analyzer idempotence",
            (python, "tool/v71r4_patch_owner_risk_analyzer_compatibility.py", "--project", ".", "--json-output", str(analyzer_json)),
        )
        analyzer = load_json(analyzer_json)
        if not (
            analyzer.get("status") == "passed"
            and analyzer.get("changedFileCount") == 0
            and analyzer.get("semanticStateRecognized") is True
            and analyzer.get("runtimeAuthorityObservationContract") is True
            and analyzer.get("ownerRiskAnalyzerCleanContract") is True
        ):
            fail(f"owner-risk analyzer compatibility invalid: {analyzer}")

        owner_json = temp / "owner-tests.json"
        step(
            "Owner-risk Flutter-test compatibility idempotence",
            (python, "tool/v71r12_patch_owner_risk_test_compatibility.py", "--project", ".", "--json-output", str(owner_json)),
        )
        owner = load_json(owner_json)
        required_owner = (
            owner.get("status") == "passed",
            owner.get("changedFileCount") == 0,
            owner.get("semanticStateRecognized") is True,
            owner.get("ownerRiskDenialProvenance") is True,
            owner.get("environmentGatedOwnerRiskSmoke") is True,
            owner.get("qaPreviewGateSemanticContract") is True,
            owner.get("governedLibraryCountUpdated") is True,
            owner.get("reverseTraversalFormatterIndependent") is True,
            owner.get("syntaxTolerantTestCallParser") is True,
            owner.get("semanticContractTestDiscovery") is True,
            owner.get("governedSourceSetSemantics") is True,
            owner.get("ownerRiskAuthorityAddedToGovernedSourceSet") is True,
            owner.get("qaPreviewExpectationSemanticDiscovery") is True,
            owner.get("qaPreviewBannerExpectationSemanticDiscovery") is True,
            owner.get("ownerRiskBannerExpectationUpdated") is True,
            owner.get("ownerRiskBannerSourceContract") is True,
            owner.get("qaPreviewRuntimeAuthorityContract") is True,
            owner.get("qaPreviewBannerExpectationContract") is True,
        )
        if not all(required_owner):
            fail(f"owner-risk Flutter-test compatibility invalid: {owner}")

        behavioral_json = temp / "behavioral.json"
        step(
            "P2 behavioral portability idempotence",
            (python, "tool/v70r5_patch_p2_behavioral_gate_portability.py", "--project", ".", "--json-output", str(behavioral_json)),
        )
        behavioral = load_json(behavioral_json)
        if not (
            behavioral.get("status") == "passed"
            and behavioral.get("changedFileCount") == 0
            and behavioral.get("windowsFastSourceImportCompatible") is True
        ):
            fail(f"behavioral portability invalid: {behavioral}")

        behavioral_isolation = run_behavioral_gate_isolated(
            project, python, env, step, max_timeout
        )

        aggregate = load_json(project / "release/evidence/P2/manifest.json")
        if aggregate.get("completionClaim") is True:
            step("P2 owner-risk completion exit", (python, "tool/p2_exit_gate_test.py", "--project", ".", "--owner-risk-waiver"), timeout=1800)
        else:
            expected = [f"P2-{number:03d}" for number in range(1, 15)]
            matrix = load_json(project / "config/p2_task_matrix.json").get("tasks")
            ids = [row.get("id") for row in matrix] if isinstance(matrix, list) else []
            if ids != expected:
                fail(f"unexpected P2 task matrix: {ids}")
            for task_id in expected:
                value = load_json(project / "release/evidence" / task_id / "manifest.json")
                if value.get("taskId") != task_id or value.get("status") not in {"source_only", "failed"}:
                    fail(f"committed P2 evidence invalid: {task_id}: {value}")
                if value.get("completedTaskPacket") is not None or value.get("platformReceipts") not in ({}, None):
                    fail(f"committed P2 evidence overclaims completion: {task_id}")
                if re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", str(value.get("generatedAt", ""))) is None:
                    fail(f"committed P2 generatedAt invalid: {task_id}")
            if aggregate.get("status") != "source_only_not_complete" or aggregate.get("completedTasks") != [] or aggregate.get("tasks") != expected:
                fail(f"committed P2 aggregate evidence invalid: {aggregate}")
            for task_id in expected:
                step(f"{task_id} source task gate", (python, "tool/p2_task_gate.py", "--project", ".", "--task", task_id), timeout=600)
            step("P2 source-only exit", (python, "tool/p2_exit_gate_test.py", "--project", ".", "--source-only"), timeout=1800)

        r3_json = temp / "r3.json"
        step("R3 semantic idempotence", (python, "tool/v70r3_patch_p2_dart_compatibility.py", "--project", ".", "--json-output", str(r3_json)))
        r3 = load_json(r3_json)
        if not (r3.get("status") == "passed" and r3.get("changedFileCount") == 0 and r3.get("semanticStateRecognized") is True):
            fail(f"R3 compatibility invalid: {r3}")

        r4_json = temp / "r4.json"
        step("R4 semantic idempotence", (python, "tool/v70r4_patch_p2_flutter_runtime_tests.py", "--project", ".", "--json-output", str(r4_json)))
        r4 = load_json(r4_json)
        if not (
            r4.get("status") == "passed"
            and r4.get("changedFileCount") == 0
            and r4.get("semanticStateRecognized") is True
            and r4.get("allFourR4FilesCovered") is True
            and r4.get("ownerWorkspaceOnboardingSyntaxAware") is True
            and r4.get("ownerWorkspaceCompactExpandedRecognized") is True
            and r4.get("ownerWorkspaceTrailingCommaIndependent") is True
        ):
            fail(f"R4 compatibility invalid: {r4}")

    for script in GENERATOR_SCRIPTS:
        if not (project / script).is_file():
            fail(f"required deterministic generator missing: {script}")
        step(f"Generator check: {script}", (python, script, "--check"), timeout=300)

    generated_checkout = normalize_generated_contract_checkout_metadata(project, env)
    if generated_checkout["generatedContractCheckoutMetadataNormalized"]:
        print(json.dumps({"generatedContractCheckout": generated_checkout}, sort_keys=True))
    # Renormalization may only refresh index/stat metadata. Re-run every check
    # afterward so the exact source gate proves the generator contract still
    # holds after the Windows-specific cleanup transaction.
    for script in GENERATOR_SCRIPTS:
        step(f"Generator post-normalization check: {script}", (python, script, "--check"), timeout=300)

    handwritten_checkout = normalize_handwritten_dart_checkout_bytes(project, env)
    if handwritten_checkout["handwrittenDartCheckoutBytesNormalized"]:
        print(json.dumps({"handwrittenDartCheckout": handwritten_checkout}, sort_keys=True))

    manifest_before = verify_source_manifest(project)
    step("Tracked diff cleanliness before SDK gate", ("git", "diff", "--exit-code"), timeout=120)
    step("Whitespace policy before SDK gate", ("git", "diff", "--check"), timeout=120)
    if tracked_status(project, env):
        fail("tracked working tree is not clean before SDK gate")

    step("Flutter dependency resolution", ("flutter", "pub", "get"), timeout=1800)
    step("Handwritten Dart format check", (python, "tool/dart_format_scope.py", "--project", ".", "--check"), timeout=1200)
    step("Flutter analyzer", ("flutter", "analyze", "--no-pub", "--fatal-warnings", "--fatal-infos"), timeout=3600)
    step("Flutter product tests", ("flutter", "test", "--no-pub", "--concurrency=1", "--reporter", "expanded", "test/product"), timeout=7200)
    step("Node dependency installation", ("npm", "ci", "--prefix", "automation_host", "--ignore-scripts=false", "--no-audit", "--no-fund"), timeout=2400)
    step("Node automation-host tests", ("npm", "test", "--prefix", "automation_host"), timeout=2400)

    manifest_after = verify_source_manifest(project)
    if manifest_after != manifest_before:
        fail("source manifest changed during exact source gate")
    step("Tracked diff cleanliness after all source gates", ("git", "diff", "--exit-code"), timeout=120)
    step("Whitespace policy after all source gates", ("git", "diff", "--check"), timeout=120)
    status = tracked_status(project, env)
    if status:
        fail(f"tracked working tree changed during exact source gate:\n{status}")

    payload: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "gateId": GATE_ID,
        "status": "passed",
        "passed": True,
        "generatedAt": utc_now(),
        "project": str(project),
        "commit": subprocess.check_output(["git", "-C", str(project), "rev-parse", "HEAD"], text=True).strip(),
        "tree": subprocess.check_output(["git", "-C", str(project), "rev-parse", "HEAD^{tree}"], text=True).strip(),
        "stepCount": len(steps),
        "steps": steps,
        "allDeterministicGeneratorsChecked": True,
        "generatorScripts": list(GENERATOR_SCRIPTS),
        "generatedContractCheckoutMetadataNormalized": generated_checkout["generatedContractCheckoutMetadataNormalized"],
        "handwrittenDartCheckoutBytesNormalized": handwritten_checkout["handwrittenDartCheckoutBytesNormalized"],
        "generatedContractCheckoutMetadataPaths": generated_checkout["generatedContractCheckoutMetadataPaths"],
        "generatedContractIndexContentUnchanged": generated_checkout["generatedContractIndexContentUnchanged"],
        "generatedContractPorcelainOnlyDriftResolved": True,
        "sourceManifestExact": True,
        "sourceManifest": manifest_after,
        "trackedTreeClean": True,
        "sameProgramLocalAndHosted": True,
        "behavioralEvidenceIsolated": behavioral_isolation["behavioralEvidenceIsolated"],
        "behavioralEvidenceDisposableWorktree": behavioral_isolation["behavioralEvidenceDisposableWorktree"],
        "behavioralEvidenceTaskCount": behavioral_isolation["behavioralEvidenceTaskCount"],
        "behavioralDiagnosticPathCount": len(BEHAVIORAL_DIAGNOSTIC_PATHS),
        "behavioralTechnologySpikeValidated": behavioral_isolation["behavioralTechnologySpikeValidated"],
        "behavioralEvidenceChangedPaths": behavioral_isolation["behavioralEvidenceChangedPaths"],
        "governedWorktreeUnchangedByBehavioralGate": behavioral_isolation["governedWorktreeUnchangedByBehavioralGate"],
        "pushAllowed": True,
    }
    rendered = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    print(rendered, end="")
    if json_output is not None:
        json_output.parent.mkdir(parents=True, exist_ok=True)
        json_output.write_text(rendered, encoding="utf-8", newline="\n")
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--json-output")
    parser.add_argument("--timeout-minutes", type=int, default=180)
    args = parser.parse_args()
    output = Path(args.json_output).expanduser().resolve() if args.json_output else None
    try:
        run_gate(Path(args.project), json_output=output, timeout_minutes=args.timeout_minutes)
    except GateError as error:
        payload = {
            "schemaVersion": SCHEMA_VERSION,
            "gateId": GATE_ID,
            "status": "failed",
            "passed": False,
            "generatedAt": utc_now(),
            "error": str(error),
            "pushAllowed": False,
        }
        rendered = json.dumps(payload, indent=2, sort_keys=True) + "\n"
        print(rendered, end="", file=sys.stderr)
        if output is not None:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(rendered, encoding="utf-8", newline="\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
