#!/usr/bin/env python3
"""Apply and qualify the One-Kristin development bundle in a real checkout.

Development-only by design:
- mutates source/worktree files only when explicitly requested;
- never stages, commits, branches, pushes, merges, or calls GitHub;
- records every command/result in JSON and Markdown reports;
- refreshes SOURCE_MANIFEST.sha256 only after all requested qualification gates pass.

This harness mirrors the repository's reviewed CI gates where practical while
remaining suitable for a developer workstation. It does not pretend local
success is equivalent to tri-platform CI.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import os
import platform
import shutil
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Sequence

EXPECTED_HEAD = "dd2f46ba6df3fb25adc2c8c927e807147b8f16f2"
BUNDLE = Path(__file__).resolve().parent
APPLY_ALL = BUNDLE / "apply_all_development_slices.py"

FOCUSED_TESTS = [
    "test/product/kristin_conversation_session_test.dart",
    "test/product/advanced_same_conversation_contract_test.dart",
    "test/product/task_kernel/semantic_slash_understanding_test.dart",
    "test/product/blocking_clarification_contract_test.dart",
    "test/product/chat_target_collision_test.dart",
    "test/product/truthful_conversation_streaming_test.dart",
    "test/product/utility_time_test.dart",
    "test/product/task_kernel/research_task_family_execution_test.dart",
    "test/product/semantic_durable_steering_test.dart",
    "test/product/runner_deferred_timestamp_wait_contract_test.dart",
    "test/product/runner_bounded_delegate_contract_test.dart",
    "test/product/steering_scope_continuation_contract_test.dart",
    "test/product/steering_idle_continuation_contract_test.dart",
    "test/product/task_kernel/research_restart_reconciliation_test.dart",
    "test/product/research_optional_archive_contract_test.dart",
    "test/product/research_archive_degradation_contract_test.dart",
    "test/product/runner_delegate_recovery_contract_test.dart",
    "test/product/chat_continuation_activity_contract_test.dart",
    "test/product/authority_convergence_contract_test.dart",
    "test/product/chat_failure_projection_contract_test.dart",
]

PRE_ANALYZER_REPO_GATES = [
    ["python", "tool/generate_v170_contracts.py", "--check"],
    ["python", "tool/generate_v180_contracts.py", "--check"],
    ["python", "tool/generate_v190_contracts.py", "--check"],
    ["python", "tool/generate_protocol_contracts.py", "--check"],
    ["python", "tool/source_tree_policy_test.py"],
    ["python", "tool/generated_state_guard_test.py"],
    ["python", "tool/generated_state_guard.py", "audit", "--project", ".", "--strict"],
    ["python", "tool/p0_007_assurance_test.py", "--project", "."],
    ["python", "tool/generate_workflow_migrations.py", "--check"],
    ["python", "tool/workflow_kernel_test.py", "--project", "."],
    ["python", "tool/generate_prompt_studio_contracts.py", "--check"],
    ["python", "tool/generate_prompt_studio_fixtures.py", "--check"],
    ["python", "tool/prompt_studio_v2_test.py"],
    ["python", "tool/dart_format_scope.py", "--check"],
]

POST_FLUTTER_REPO_GATES = [
    ["python", "tool/validate_release.py", "--skip-tests"],
]


@dataclass
class CommandResult:
    name: str
    argv: list[str]
    status: str
    returncode: int | None
    elapsed_seconds: float
    stdout_tail: str = ""
    stderr_tail: str = ""
    note: str = ""


class QualificationFailure(RuntimeError):
    pass


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(root), *args],
        text=True,
        stderr=subprocess.STDOUT,
    ).strip()


def _tail(value: str, max_chars: int = 12000) -> str:
    value = value.strip()
    return value[-max_chars:] if len(value) > max_chars else value


def run_step(
    results: list[CommandResult],
    name: str,
    argv: Sequence[str],
    *,
    cwd: Path,
    required: bool = True,
    env: dict[str, str] | None = None,
) -> bool:
    started = time.monotonic()
    print(f"\n== {name} ==", flush=True)
    print("+", " ".join(argv), flush=True)
    try:
        completed = subprocess.run(
            list(argv),
            cwd=cwd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=env,
            check=False,
        )
    except FileNotFoundError as error:
        elapsed = time.monotonic() - started
        result = CommandResult(
            name=name,
            argv=list(argv),
            status="missing_tool",
            returncode=None,
            elapsed_seconds=round(elapsed, 3),
            note=str(error),
        )
        results.append(result)
        print(f"MISSING TOOL: {error}", file=sys.stderr)
        if required:
            raise QualificationFailure(f"{name}: required tool missing")
        return False

    elapsed = time.monotonic() - started
    result = CommandResult(
        name=name,
        argv=list(argv),
        status="passed" if completed.returncode == 0 else "failed",
        returncode=completed.returncode,
        elapsed_seconds=round(elapsed, 3),
        stdout_tail=_tail(completed.stdout),
        stderr_tail=_tail(completed.stderr),
    )
    results.append(result)
    if completed.stdout:
        print(completed.stdout, end="" if completed.stdout.endswith("\n") else "\n")
    if completed.stderr:
        print(completed.stderr, file=sys.stderr, end="" if completed.stderr.endswith("\n") else "\n")
    if completed.returncode != 0 and required:
        raise QualificationFailure(f"{name} failed with exit code {completed.returncode}")
    return completed.returncode == 0


def verify_checkout(root: Path, *, allow_head_mismatch: bool, allow_dirty: bool) -> dict[str, str]:
    if not (root / ".git").exists():
        raise QualificationFailure(f"{root} is not a Git checkout")
    head = git(root, "rev-parse", "HEAD")
    branch = git(root, "rev-parse", "--abbrev-ref", "HEAD")
    dirty = git(root, "status", "--porcelain")
    if head != EXPECTED_HEAD and not allow_head_mismatch:
        raise QualificationFailure(
            f"refusing HEAD {head}; expected recovered head {EXPECTED_HEAD}. "
            "Use --allow-head-mismatch only after reviewing source drift."
        )
    if dirty and not allow_dirty:
        raise QualificationFailure(
            "checkout is already dirty; refusing to mix this bundle with unknown work"
        )
    return {"head": head, "branch": branch, "dirtyBefore": dirty}


def changed_paths(root: Path) -> list[str]:
    # Includes tracked modifications/deletions and untracked files. Git is read-only here.
    out = git(root, "status", "--porcelain=v1", "--untracked-files=all")
    paths: list[str] = []
    for line in out.splitlines():
        if len(line) < 4:
            continue
        value = line[3:]
        if " -> " in value:
            value = value.split(" -> ", 1)[1]
        value = value.strip().strip('"')
        if value and value not in paths:
            paths.append(value)
    return paths


def format_changed_dart(results: list[CommandResult], root: Path) -> None:
    dart = shutil.which("dart")
    if not dart:
        raise QualificationFailure("dart is required for --format")
    targets = [
        path
        for path in changed_paths(root)
        if path.endswith(".dart") and (root / path).exists()
    ]
    if not targets:
        results.append(
            CommandResult(
                name="format changed Dart",
                argv=[dart, "format"],
                status="skipped",
                returncode=0,
                elapsed_seconds=0,
                note="no changed Dart files",
            )
        )
        return
    run_step(results, "format changed Dart", [dart, "format", *targets], cwd=root)


def existing_focused_tests(root: Path) -> list[str]:
    return [path for path in FOCUSED_TESTS if (root / path).exists()]


def verify_bundle_applied(root: Path) -> None:
    markers = {
        "lib/product/run_steering_record.dart": "TaskSpecificationPatch",
        "lib/product/task_kernel/research_task_family_executor.dart": "ResearchTaskFamilyExecutor",
        "lib/product/agent_delegation_record.dart": "AgentDelegationRecord",
        "test/product/authority_convergence_contract_test.dart": "authority",
        "test/product/chat_failure_projection_contract_test.dart": "technical",
    }
    missing = []
    for relative, needle in markers.items():
        path = root / relative
        if not path.exists() or needle.lower() not in path.read_text(encoding="utf-8").lower():
            missing.append(relative)
    if missing:
        raise QualificationFailure(
            "--already-applied was requested but bundle markers are missing: "
            + ", ".join(missing)
        )



def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _canonical_json(value: object) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        + "\n"
    ).encode("utf-8")


def _declared_toolchain_payload(manifest: dict[str, object]) -> dict[str, object]:
    return {
        "schemaVersion": manifest["schemaVersion"],
        "sourceCommit": manifest["sourceCommit"],
        "python": manifest["python"],
        "flutter": manifest["flutter"],
        "dart": manifest["dart"],
        "githubActions": manifest["githubActions"],
        "runners": manifest["runners"],
        "cache": manifest["cache"],
        "lockfiles": manifest["lockfiles"],
    }


def locked_package_versions(root: Path) -> dict[str, str]:
    path = root / "pubspec.lock"
    if not path.is_file():
        raise QualificationFailure("pubspec.lock is missing")
    source = path.read_text(encoding="utf-8")
    versions: dict[str, str] = {}
    for match in re.finditer(
        r"(?ms)^  (?P<name>[A-Za-z0-9_]+):\n(?P<body>(?:    .*\n)+?)(?=^  [A-Za-z0-9_]+:|^sdks:|\Z)",
        source,
    ):
        version = re.search(
            r'^    version:\s+["\']?([^"\'\s]+)["\']?\s*$',
            match.group("body"),
            re.MULTILINE,
        )
        if version is not None:
            versions[match.group("name")] = version.group(1)
    if not versions:
        raise QualificationFailure("pubspec.lock contains no resolvable package versions")
    return versions


def verify_existing_lock_versions(
    before: dict[str, str],
    after: dict[str, str],
) -> None:
    removed = sorted(set(before) - set(after))
    changed = sorted(
        name for name in set(before) & set(after) if before[name] != after[name]
    )
    if removed or changed:
        details = []
        if removed:
            details.append("removed=" + ",".join(removed))
        if changed:
            details.append(
                "changed="
                + ",".join(
                    f"{name}:{before[name]}->{after[name]}" for name in changed
                )
            )
        raise QualificationFailure(
            "flutter pub get changed pre-existing locked packages: "
            + "; ".join(details)
        )


def verify_timezone_lock(root: Path) -> None:
    path = root / "pubspec.lock"
    if not path.is_file():
        raise QualificationFailure("pubspec.lock is missing after flutter pub get")
    source = path.read_text(encoding="utf-8")
    match = re.search(
        r"(?ms)^  timezone:\n(?P<body>(?:    .*\n)+?)(?=^  [A-Za-z0-9_]+:|^sdks:|\Z)",
        source,
    )
    if match is None:
        raise QualificationFailure("pubspec.lock does not contain timezone")
    body = match.group("body")
    if not re.search(r'^    dependency:\s+["\']?direct main["\']?\s*$', body, re.MULTILINE):
        raise QualificationFailure("timezone must resolve as a direct main dependency")
    if not re.search(r'^    version:\s+["\']?0\.10\.1["\']?\s*$', body, re.MULTILINE):
        raise QualificationFailure("timezone must resolve at exactly 0.10.1")


def sync_governed_toolchain_lock(root: Path) -> None:
    lockfile = root / "pubspec.lock"
    config = root / "config" / "toolchains.lock.json"
    if not lockfile.is_file() or not config.is_file():
        raise QualificationFailure("governed toolchain lock inputs are missing")
    manifest = json.loads(config.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict):
        raise QualificationFailure("config/toolchains.lock.json must contain an object")
    lockfiles = manifest.get("lockfiles")
    if not isinstance(lockfiles, list):
        raise QualificationFailure("toolchains.lock.json lockfiles must be an array")
    updated = False
    digest = _sha256_file(lockfile)
    for item in lockfiles:
        if isinstance(item, dict) and item.get("path") == "pubspec.lock":
            item["sha256"] = digest
            updated = True
    if not updated:
        raise QualificationFailure("toolchains.lock.json does not govern pubspec.lock")
    manifest["declaredInputFingerprint"] = hashlib.sha256(
        _canonical_json(_declared_toolchain_payload(manifest))
    ).hexdigest()
    config.write_text(
        json.dumps(manifest, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def run_locked_toolchain_gate(
    results: list[CommandResult], root: Path, report_dir: Path, *, name: str
) -> None:
    gate = root / "tool" / "toolchain_lock_test.py"
    if not gate.is_file():
        raise QualificationFailure("tool/toolchain_lock_test.py is missing")
    report_dir.mkdir(parents=True, exist_ok=True)
    receipt = report_dir / ("toolchain-preflight.json" if "preflight" in name else "toolchain-post-pub.json")
    run_step(
        results,
        name,
        [sys.executable, str(gate.relative_to(root)), "--json-output", str(receipt)],
        cwd=root,
    )


def write_reports(
    report_dir: Path,
    *,
    metadata: dict[str, object],
    results: list[CommandResult],
    outcome: str,
    failure: str | None,
    changed: list[str],
) -> tuple[Path, Path]:
    report_dir.mkdir(parents=True, exist_ok=True)
    json_path = report_dir / "one-kristin-qualification.json"
    md_path = report_dir / "one-kristin-qualification.md"
    payload = {
        "schemaVersion": 1,
        "outcome": outcome,
        "failure": failure,
        "metadata": metadata,
        "changedPaths": changed,
        "steps": [asdict(item) for item in results],
    }
    json_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    rows = []
    for item in results:
        rc = "—" if item.returncode is None else str(item.returncode)
        rows.append(f"| {item.name} | {item.status} | {rc} | {item.elapsed_seconds:.3f}s |")
    md = [
        "# One-Kristin real-checkout qualification",
        "",
        f"**Outcome:** `{outcome}`",
        f"**Recovered head expected:** `{EXPECTED_HEAD}`",
        f"**Checkout head:** `{metadata.get('checkout', {}).get('head', '')}`",
        f"**Platform:** `{metadata.get('platform', '')}`",
        f"**Python:** `{metadata.get('python', '')}`",
        "",
    ]
    if failure:
        md += [f"**Failure:** `{failure}`", ""]
    md += [
        "## Steps",
        "",
        "| Step | Status | RC | Time |",
        "|---|---|---:|---:|",
        *rows,
        "",
        "## Changed paths",
        "",
        *([f"- `{path}`" for path in changed] or ["- None"]),
        "",
        "## Interpretation",
        "",
        "A local pass proves composition on this checkout and platform only. It does not replace the repository's tri-platform protected workflows or provider dogfooding.",
        "",
    ]
    md_path.write_text("\n".join(md), encoding="utf-8")
    return json_path, md_path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("repo", type=Path, help="path to a real kris.ai checkout")
    parser.add_argument("--apply", action="store_true", help="apply the 20 guarded development slices")
    parser.add_argument(
        "--already-applied",
        action="store_true",
        help="qualify a checkout where the 20-slice bundle has already been applied",
    )
    parser.add_argument("--format", action="store_true", help="format changed Dart files after apply")
    parser.add_argument("--focused", action="store_true", help="run focused One-Kristin tests")
    parser.add_argument("--full-flutter", action="store_true", help="run the full Flutter test suite")
    parser.add_argument("--repo-gates", action="store_true", help="run reviewed local repository Python/source gates")
    parser.add_argument(
        "--refresh-source-manifest",
        action="store_true",
        help="refresh SOURCE_MANIFEST.sha256 only after every requested gate has passed",
    )
    parser.add_argument("--allow-head-mismatch", action="store_true")
    parser.add_argument("--allow-dirty", action="store_true")
    parser.add_argument(
        "--report-dir",
        type=Path,
        default=None,
        help="report directory (default: sibling <repo>.one-kristin-qualification outside checkout)",
    )
    args = parser.parse_args()

    root = args.repo.resolve()
    if args.apply and args.already_applied:
        parser.error("choose either --apply or --already-applied, not both")
    report_dir = (
        args.report_dir
        or (root.parent / f"{root.name}.one-kristin-qualification")
    ).resolve()
    if report_dir == root or report_dir.is_relative_to(root):
        parser.error(
            "--report-dir must be outside the repository so qualification "
            "artifacts cannot pollute source-tree or source-manifest gates"
        )
    if args.refresh_source_manifest:
        missing_prereqs = []
        if not (args.apply or args.already_applied):
            missing_prereqs.append("--apply or --already-applied")
        if not args.format:
            missing_prereqs.append("--format")
        if not args.repo_gates:
            missing_prereqs.append("--repo-gates")
        if not args.full_flutter:
            missing_prereqs.append("--full-flutter")
        if missing_prereqs:
            parser.error(
                "--refresh-source-manifest requires a completed local qualification "
                "sequence: " + ", ".join(missing_prereqs)
            )
    results: list[CommandResult] = []
    failure: str | None = None
    outcome = "failed"
    checkout: dict[str, str] = {}
    metadata: dict[str, object] = {
        "expectedHead": EXPECTED_HEAD,
        "platform": platform.platform(),
        "python": sys.version.split()[0],
        "bundle": str(BUNDLE),
        "requested": {
            "apply": args.apply,
            "alreadyApplied": args.already_applied,
            "format": args.format,
            "focused": args.focused,
            "fullFlutter": args.full_flutter,
            "repoGates": args.repo_gates,
            "refreshSourceManifest": args.refresh_source_manifest,
        },
    }

    try:
        checkout = verify_checkout(
            root,
            allow_head_mismatch=args.allow_head_mismatch,
            allow_dirty=args.allow_dirty,
        )
        metadata["checkout"] = checkout

        if args.already_applied:
            verify_bundle_applied(root)
            results.append(
                CommandResult(
                    name="verify bundle already applied",
                    argv=[],
                    status="passed",
                    returncode=0,
                    elapsed_seconds=0,
                    note="required One-Kristin markers are present",
                )
            )

        if args.apply:
            argv = [sys.executable, str(APPLY_ALL), str(root), "--apply"]
            if args.allow_head_mismatch:
                argv.append("--allow-head-mismatch")
            if args.allow_dirty:
                argv.append("--allow-dirty")
            run_step(results, "apply 20 guarded slices", argv, cwd=root)

        needs_flutter = args.focused or args.full_flutter or args.repo_gates
        needs_toolchain = args.format or needs_flutter
        flutter = shutil.which("flutter")
        if needs_toolchain and not flutter:
            raise QualificationFailure(
                "flutter is required for formatting or requested Flutter qualification"
            )
        if needs_toolchain:
            # Formatting is SDK-version-sensitive too. Establish the exact
            # installed Python/Flutter/Dart toolchain before either Dart
            # formatting or Pub is allowed to rewrite tracked source state.
            run_locked_toolchain_gate(
                results, root, report_dir, name="locked toolchain preflight"
            )
        if needs_flutter:
            locked_before_pub = locked_package_versions(root)
            run_step(
                results,
                "flutter pub get",
                [flutter, "pub", "get"],
                cwd=root,
            )
            verify_timezone_lock(root)
            locked_after_pub = locked_package_versions(root)
            verify_existing_lock_versions(locked_before_pub, locked_after_pub)
            results.append(
                CommandResult(
                    name="verify timezone lock",
                    argv=[],
                    status="passed",
                    returncode=0,
                    elapsed_seconds=0,
                    note="timezone is direct main 0.10.1 and pre-existing package versions are unchanged",
                )
            )
            sync_governed_toolchain_lock(root)
            results.append(
                CommandResult(
                    name="sync governed toolchain lock",
                    argv=[],
                    status="passed",
                    returncode=0,
                    elapsed_seconds=0,
                    note="pubspec.lock SHA and declaredInputFingerprint updated canonically",
                )
            )
            run_locked_toolchain_gate(
                results, root, report_dir, name="locked toolchain post-Pub"
            )

        if args.format:
            format_changed_dart(results, root)

        # The reviewed CI checks generated/source contracts before analyzer.
        if args.repo_gates:
            for command in PRE_ANALYZER_REPO_GATES:
                argv = [sys.executable if command[0] == "python" else command[0], *command[1:]]
                run_step(results, "repo gate: " + " ".join(command[1:]), argv, cwd=root)

        if needs_flutter:
            run_step(
                results,
                "flutter analyze",
                [flutter, "analyze", "--no-pub", "--fatal-warnings", "--fatal-infos"],
                cwd=root,
            )

        if args.focused:
            tests = existing_focused_tests(root)
            if not tests:
                raise QualificationFailure("none of the focused One-Kristin tests exist after apply")
            run_step(
                results,
                "focused One-Kristin tests",
                [flutter, "test", "--no-pub", "--concurrency=1", "--reporter", "expanded", *tests],
                cwd=root,
            )

        if args.full_flutter:
            run_step(
                results,
                "full Flutter tests",
                [flutter, "test", "--no-pub", "--concurrency=1", "--reporter", "expanded"],
                cwd=root,
            )

        if args.repo_gates:
            for command in POST_FLUTTER_REPO_GATES:
                argv = [sys.executable if command[0] == "python" else command[0], *command[1:]]
                run_step(results, "repo gate: " + " ".join(command[1:]), argv, cwd=root)

        # Refreshing the governed source manifest is deliberately last. The
        # reviewed workflow uses this exact tool and fails if the manifest is stale.
        if args.refresh_source_manifest:
            refresher = root / "tool" / "p2_refresh_source_manifest.py"
            if not refresher.exists():
                raise QualificationFailure("source-manifest refresher is missing")
            run_step(
                results,
                "refresh SOURCE_MANIFEST.sha256",
                [sys.executable, str(refresher.relative_to(root)), "."],
                cwd=root,
            )
            run_step(results, "git diff --check", ["git", "diff", "--check"], cwd=root)

        outcome = "passed"
    except QualificationFailure as error:
        failure = str(error)
        print(f"QUALIFICATION FAILED: {failure}", file=sys.stderr)
    except subprocess.CalledProcessError as error:
        failure = f"checkout guard failed: {error.output or error}"
        print(f"QUALIFICATION FAILED: {failure}", file=sys.stderr)
    except Exception as error:  # fail closed while still writing a report
        failure = f"unexpected qualifier failure: {error}"
        print(f"QUALIFICATION FAILED: {failure}", file=sys.stderr)

    try:
        changed = changed_paths(root) if (root / ".git").exists() else []
    except Exception:
        changed = []
    metadata["checkout"] = checkout
    metadata["dart"] = shutil.which("dart") or ""
    metadata["flutter"] = shutil.which("flutter") or ""
    json_path, md_path = write_reports(
        report_dir,
        metadata=metadata,
        results=results,
        outcome=outcome,
        failure=failure,
        changed=changed,
    )
    print(f"Qualification JSON: {json_path}")
    print(f"Qualification Markdown: {md_path}")
    print("No Git write operation was performed by this harness.")
    return 0 if outcome == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
