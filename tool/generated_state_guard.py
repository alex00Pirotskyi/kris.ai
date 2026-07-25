#!/usr/bin/env python3
"""Audit tracked generated state and verify that tests do not dirty source.

The guard is dependency-free. In a Git checkout it uses Git's index as the
tracked-file authority. In a source archive it falls back to
``SOURCE_MANIFEST.sha256``.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import hashlib
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import shutil
import subprocess
import sys
from typing import Any, Iterable

sys.dont_write_bytecode = True

from source_tree_policy import (
    GENERATED_STATE_POLICY_VERSION,
    all_gitignore_patterns,
    generated_path_reason,
    gitignore_block,
    is_generated_path,
    representative_generated_paths,
)

REPORT_SCHEMA_VERSION = "1.0.0"


class GuardError(RuntimeError):
    pass


@dataclass(frozen=True)
class GeneratedFinding:
    path: str
    reason: str
    exists: bool


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def safe_relative(value: str) -> str:
    raw = value.replace("\\", "/").strip()
    while raw.startswith("./"):
        raw = raw[2:]
    raw = re.sub(r"/+", "/", raw)
    if not raw or raw == ".":
        raise GuardError("empty relative path")

    # Path() follows the host OS. That is not sufficient for a cross-platform
    # manifest guard: on Windows, a slash-rooted path such as /tmp/secret is
    # rooted on the current drive but Path.is_absolute() may still report
    # false. Validate with both path grammars and reject drive-relative forms
    # such as C:secret as well as drive-absolute and UNC/rooted paths.
    posix = PurePosixPath(raw)
    windows = PureWindowsPath(raw)
    if (
        raw.startswith("/")
        or posix.is_absolute()
        or windows.is_absolute()
        or bool(windows.drive)
        or ".." in posix.parts
        or ".." in windows.parts
    ):
        raise GuardError(f"unsafe relative path: {value!r}")
    return raw


def run_git(project: Path, arguments: list[str], *, required: bool = True) -> bytes | None:
    git = shutil.which("git")
    if git is None or not (project / ".git").exists():
        if required:
            raise GuardError("Git checkout is required for this operation")
        return None
    completed = subprocess.run(
        [git, *arguments],
        cwd=project,
        env={**os.environ, "LC_ALL": "C"},
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        timeout=60,
    )
    if completed.returncode != 0:
        if required:
            detail = completed.stderr.decode("utf-8", errors="replace")[-2000:]
            raise GuardError(f"git {' '.join(arguments)} failed: {detail}")
        return None
    return completed.stdout


def parse_source_manifest(project: Path) -> list[str]:
    path = project / "SOURCE_MANIFEST.sha256"
    if not path.is_file():
        return []
    result: list[str] = []
    seen: set[str] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        match = re.match(r"^[0-9a-fA-F]{64}\s{2,}(.+)$", line)
        if match is None:
            raise GuardError(f"invalid source manifest line: {line!r}")
        relative = safe_relative(match.group(1))
        if relative in seen:
            raise GuardError(f"duplicate source manifest path: {relative}")
        seen.add(relative)
        result.append(relative)
    return sorted(result)


def tracked_paths(project: Path) -> tuple[str, list[str]]:
    output = run_git(project, ["ls-files", "-z"], required=False)
    if output is not None:
        paths = [safe_relative(item.decode("utf-8", errors="surrogateescape")) for item in output.split(b"\0") if item]
        return "git-index", sorted(set(paths))
    manifest = parse_source_manifest(project)
    if manifest:
        return "source-manifest", manifest
    raise GuardError("neither a Git index nor SOURCE_MANIFEST.sha256 is available")


def tracked_generated_findings(project: Path) -> tuple[str, list[GeneratedFinding]]:
    source, paths = tracked_paths(project)
    findings: list[GeneratedFinding] = []
    for relative in paths:
        reason = generated_path_reason(relative)
        if reason is None:
            continue
        findings.append(
            GeneratedFinding(
                path=relative,
                reason=reason,
                exists=os.path.lexists(project / relative),
            )
        )
    return source, findings


def manifest_generated_findings(project: Path) -> list[GeneratedFinding]:
    findings: list[GeneratedFinding] = []
    for relative in parse_source_manifest(project):
        reason = generated_path_reason(relative)
        if reason is not None:
            findings.append(
                GeneratedFinding(
                    path=relative,
                    reason=reason,
                    exists=os.path.lexists(project / relative),
                )
            )
    return findings


def existing_generated_roots(project: Path, *, limit: int = 5000) -> list[GeneratedFinding]:
    result: list[GeneratedFinding] = []
    for directory, names, files in os.walk(project, topdown=True, followlinks=False):
        root = Path(directory)
        relative_root = root.relative_to(project)
        if relative_root.parts and relative_root.parts[0] == ".git":
            names[:] = []
            continue
        retained: list[str] = []
        for name in sorted(names):
            relative = (relative_root / name).as_posix()
            reason = generated_path_reason(relative)
            if reason is not None:
                result.append(GeneratedFinding(relative, reason, True))
                if len(result) >= limit:
                    return result
            else:
                retained.append(name)
        names[:] = retained
        for name in sorted(files):
            relative = (relative_root / name).as_posix()
            reason = generated_path_reason(relative)
            if reason is not None:
                result.append(GeneratedFinding(relative, reason, True))
                if len(result) >= limit:
                    return result
    return result


def gitignore_coverage(project: Path) -> dict[str, Any]:
    ignore_path = project / ".gitignore"
    text = ignore_path.read_text(encoding="utf-8", errors="replace") if ignore_path.is_file() else ""
    exact_block = gitignore_block() in text
    missing_patterns = [pattern for pattern in all_gitignore_patterns() if pattern not in text]
    ignored: list[str] = []
    missing_examples: list[str] = []
    if (project / ".git").exists() and shutil.which("git"):
        for relative in representative_generated_paths():
            completed = subprocess.run(
                ["git", "check-ignore", "--no-index", "-q", "--", relative],
                cwd=project,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
                timeout=10,
            )
            (ignored if completed.returncode == 0 else missing_examples).append(relative)
    else:
        # Exact managed block is the archive-mode proof; Git behavior is covered
        # by unit tests and CI checkouts.
        ignored = list(representative_generated_paths()) if exact_block else []
        missing_examples = [] if exact_block else list(representative_generated_paths())
    return {
        "exactManagedBlock": exact_block,
        "missingPatternCount": len(missing_patterns),
        "missingPatterns": missing_patterns,
        "ignoredExampleCount": len(ignored),
        "missingExampleCount": len(missing_examples),
        "missingExamples": missing_examples,
    }


def build_audit(project: Path) -> dict[str, Any]:
    source, tracked = tracked_generated_findings(project)
    manifest = manifest_generated_findings(project)
    present = [item for item in tracked if item.exists]
    pending = [item for item in tracked if not item.exists]
    coverage = gitignore_coverage(project)
    existing = existing_generated_roots(project)
    passed = (
        not present
        and not manifest
        and coverage["missingPatternCount"] == 0
        and coverage["missingExampleCount"] == 0
        and coverage["exactManagedBlock"] is True
    )
    report: dict[str, Any] = {
        "schemaVersion": REPORT_SCHEMA_VERSION,
        "policyVersion": GENERATED_STATE_POLICY_VERSION,
        "kind": "generated_state_audit",
        "project": "<PROJECT>",
        "trackedAuthority": source,
        "passed": passed,
        "trackedGeneratedPresent": [asdict(item) for item in present],
        "trackedGeneratedPendingDeletion": [asdict(item) for item in pending],
        "manifestGenerated": [asdict(item) for item in manifest],
        "existingGeneratedRoots": [asdict(item) for item in existing],
        "gitignoreCoverage": coverage,
        "claims": {
            "generatedStateMayBeTracked": False,
            "reviewedGeneratedDartIsDisposable": False,
            "committedEvidenceIsDisposable": False,
        },
    }
    fingerprint_payload = dict(report)
    report["fingerprint"] = sha256_text(canonical_json(fingerprint_payload))
    return report


def dirty_source_paths(project: Path) -> list[str]:
    paths: set[str] = set()
    for args in (
        ["diff", "--name-only", "-z"],
        ["diff", "--cached", "--name-only", "-z"],
        ["ls-files", "--others", "--exclude-standard", "-z"],
    ):
        output = run_git(project, args, required=True) or b""
        for raw in output.split(b"\0"):
            if not raw:
                continue
            relative = safe_relative(raw.decode("utf-8", errors="surrogateescape"))
            if not is_generated_path(relative):
                paths.add(relative)
    return sorted(paths)


def build_snapshot(project: Path) -> dict[str, Any]:
    paths = dirty_source_paths(project)
    payload = {
        "schemaVersion": REPORT_SCHEMA_VERSION,
        "policyVersion": GENERATED_STATE_POLICY_VERSION,
        "kind": "generated_state_source_snapshot",
        "nonGeneratedDirtyPaths": paths,
    }
    payload["fingerprint"] = sha256_text(canonical_json(payload))
    return payload


def verify_snapshot(project: Path, baseline: dict[str, Any]) -> dict[str, Any]:
    current = build_snapshot(project)
    expected = baseline.get("nonGeneratedDirtyPaths")
    if not isinstance(expected, list) or not all(isinstance(item, str) for item in expected):
        raise GuardError("snapshot baseline has invalid nonGeneratedDirtyPaths")
    added = sorted(set(current["nonGeneratedDirtyPaths"]) - set(expected))
    removed = sorted(set(expected) - set(current["nonGeneratedDirtyPaths"]))
    return {
        "schemaVersion": REPORT_SCHEMA_VERSION,
        "policyVersion": GENERATED_STATE_POLICY_VERSION,
        "kind": "generated_state_source_snapshot_verification",
        "passed": not added and not removed,
        "expectedFingerprint": baseline.get("fingerprint"),
        "actualFingerprint": current["fingerprint"],
        "addedNonGeneratedDirtyPaths": added,
        "removedNonGeneratedDirtyPaths": removed,
    }


def write_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def print_or_write(value: dict[str, Any], output: str | None, project: Path) -> None:
    if output:
        target = Path(output)
        if not target.is_absolute():
            target = project / target
        write_json(target, value)
    print(json.dumps(value, indent=2, sort_keys=True))


def command_audit(args: argparse.Namespace) -> int:
    project = Path(args.project).expanduser().resolve()
    try:
        report = build_audit(project)
    except GuardError as error:
        print(str(error), file=sys.stderr)
        return 2
    print_or_write(report, args.json_output, project)
    return 0 if report["passed"] or not args.strict else 1


def command_snapshot(args: argparse.Namespace) -> int:
    project = Path(args.project).expanduser().resolve()
    try:
        report = build_snapshot(project)
    except GuardError as error:
        print(str(error), file=sys.stderr)
        return 2
    print_or_write(report, args.output, project)
    return 0


def command_verify_clean(args: argparse.Namespace) -> int:
    project = Path(args.project).expanduser().resolve()
    baseline_path = Path(args.baseline)
    if not baseline_path.is_absolute():
        baseline_path = project / baseline_path
    try:
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
        report = verify_snapshot(project, baseline)
    except (OSError, json.JSONDecodeError, GuardError) as error:
        print(str(error), file=sys.stderr)
        return 2
    print_or_write(report, args.json_output, project)
    return 0 if report["passed"] else 1


def command_explain(args: argparse.Namespace) -> int:
    result = []
    for item in args.paths:
        try:
            normalized = safe_relative(item)
        except GuardError as error:
            result.append({"path": item, "generated": False, "error": str(error)})
            continue
        reason = generated_path_reason(normalized)
        result.append(
            {
                "path": item,
                "normalized": normalized,
                "generated": reason is not None,
                "reason": reason,
            }
        )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    audit = subparsers.add_parser("audit", help="audit tracked and manifested generated state")
    audit.add_argument("--project", default=".")
    audit.add_argument("--json-output")
    audit.add_argument("--strict", action="store_true")
    audit.set_defaults(func=command_audit)

    snapshot = subparsers.add_parser("snapshot", help="record current non-generated Git dirt")
    snapshot.add_argument("--project", default=".")
    snapshot.add_argument("--output", required=True)
    snapshot.set_defaults(func=command_snapshot)

    verify = subparsers.add_parser("verify-clean", help="verify tests added no non-generated dirt")
    verify.add_argument("--project", default=".")
    verify.add_argument("--baseline", required=True)
    verify.add_argument("--json-output")
    verify.set_defaults(func=command_verify_clean)

    explain = subparsers.add_parser("explain", help="explain policy classification for paths")
    explain.add_argument("paths", nargs="+")
    explain.set_defaults(func=command_explain)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
