#!/usr/bin/env python3
"""Validate Kristin's immutable P0-004 CI/toolchain declaration.

The source-only mode verifies the workflow, action pins, runner labels, exact
versions, cache identity, and lockfile hashes. The normal mode additionally
proves that the current Python, Flutter, and Dart runtimes match the manifest.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import sys
from typing import Any, Callable

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "config" / "toolchains.lock.json"
WORKFLOW = ROOT / ".github" / "workflows" / "ci.yml"
SEMVER = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$")
FULL_SHA = re.compile(r"^[0-9a-f]{40}$")


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str


def canonical(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def run_case(name: str, action: Callable[[], str]) -> Result:
    try:
        return Result(name, True, action())
    except BaseException as error:
        return Result(name, False, f"{type(error).__name__}: {error}")


def load_manifest() -> dict[str, Any]:
    require(MANIFEST.is_file(), "config/toolchains.lock.json is missing")
    decoded = json.loads(MANIFEST.read_text(encoding="utf-8"))
    require(isinstance(decoded, dict), "toolchain manifest root must be an object")
    return decoded


def exact_version(value: object, label: str) -> str:
    version = str(value or "")
    require(bool(SEMVER.fullmatch(version)), f"{label} must be an exact semantic version, got {version!r}")
    return version


def test_manifest_shape() -> str:
    manifest = load_manifest()
    require(manifest.get("schemaVersion") == "1.0.0", "schemaVersion must be 1.0.0")
    require(manifest.get("milestone") == "P0-004", "milestone must be P0-004")
    source_commit = str(manifest.get("sourceCommit") or "")
    require(bool(FULL_SHA.fullmatch(source_commit)), "sourceCommit must be a full Git SHA")
    python_version = exact_version(manifest.get("python", {}).get("version"), "Python")
    flutter_version = exact_version(manifest.get("flutter", {}).get("version"), "Flutter")
    dart_version = exact_version(manifest.get("dart", {}).get("version"), "Dart")
    require(manifest.get("flutter", {}).get("channel") == "stable", "Flutter channel must be stable")
    expected_fingerprint = sha256_bytes(canonical(declared_input_payload(manifest)))
    require(
        manifest.get("declaredInputFingerprint") == expected_fingerprint,
        "declaredInputFingerprint does not match the canonical declared inputs",
    )
    actions = manifest.get("githubActions")
    require(isinstance(actions, dict) and actions, "githubActions must be a non-empty object")
    for action_id, item in actions.items():
        require(isinstance(item, dict), f"action {action_id} must be an object")
        require(bool(FULL_SHA.fullmatch(str(item.get("commit") or ""))), f"action {action_id} is not pinned to a full SHA")
        require(bool(str(item.get("release") or "")), f"action {action_id} release annotation is missing")
    runners = manifest.get("runners")
    require(isinstance(runners, dict), "runners must be an object")
    require(set(runners) == {"ubuntu", "windows", "macos"}, "runner lanes must be ubuntu/windows/macos")
    for lane, label in runners.items():
        require(bool(str(label)), f"runner label for {lane} is empty")
        require(not str(label).endswith("-latest"), f"runner {lane} still uses a moving -latest label")
    return f"python={python_version} flutter={flutter_version} dart={dart_version} actions={len(actions)}"


def test_lockfiles() -> str:
    manifest = load_manifest()
    lockfiles = manifest.get("lockfiles")
    require(isinstance(lockfiles, list) and lockfiles, "lockfiles must be a non-empty array")
    verified = 0
    for entry in lockfiles:
        require(isinstance(entry, dict), "lockfile entry must be an object")
        relative = str(entry.get("path") or "")
        expected = str(entry.get("sha256") or "")
        require(relative and not Path(relative).is_absolute() and ".." not in Path(relative).parts, f"invalid lockfile path {relative!r}")
        require(re.fullmatch(r"[0-9a-f]{64}", expected) is not None, f"invalid lockfile digest for {relative}")
        path = ROOT / relative
        require(path.is_file(), f"declared lockfile is missing: {relative}")
        actual = sha256_file(path)
        require(actual == expected, f"lockfile drift for {relative}: expected {expected}, got {actual}")
        verified += 1
    return f"verified {verified} lockfile(s)"


def _extract_with_block(workflow: str, action_line_fragment: str) -> str:
    lines = workflow.splitlines()
    for index, line in enumerate(lines):
        if action_line_fragment not in line:
            continue
        uses_indent = len(line) - len(line.lstrip())
        step_start = index
        step_indent = uses_indent
        if index > 0:
            previous = lines[index - 1]
            previous_indent = len(previous) - len(previous.lstrip())
            if previous.lstrip().startswith("- name:") and previous_indent < uses_indent:
                step_start = index - 1
                step_indent = previous_indent
        if line.lstrip().startswith("- uses:"):
            step_indent = uses_indent
        step_end = len(lines)
        for candidate in range(step_start + 1, len(lines)):
            following = lines[candidate]
            indent = len(following) - len(following.lstrip())
            if following.strip() and indent == step_indent and following.lstrip().startswith("-"):
                step_end = candidate
                break
        return "\n".join(lines[step_start:step_end])
    raise AssertionError(f"workflow action was not found: {action_line_fragment}")


def test_workflow_pins() -> str:
    manifest = load_manifest()
    workflow = WORKFLOW.read_text(encoding="utf-8")
    actions = manifest["githubActions"]
    for action_id, entry in actions.items():
        expected = f"uses: {action_id}@{entry['commit']}"
        require(expected in workflow, f"workflow does not contain {expected}")
        require(f"# {entry['release']}" in workflow, f"workflow lacks release annotation for {action_id}")
    uses_lines = [line.strip() for line in workflow.splitlines() if "uses:" in line]
    require(uses_lines, "workflow has no uses entries")
    mutable = []
    for line in uses_lines:
        match = re.search(r"uses:\s*[^@\s]+@([^\s#]+)", line)
        if match is None or FULL_SHA.fullmatch(match.group(1)) is None:
            mutable.append(line)
    require(not mutable, "mutable or malformed action references remain: " + "; ".join(mutable))

    runners = manifest["runners"]
    expected_matrix = f"os: [{runners['ubuntu']}, {runners['windows']}, {runners['macos']}]"
    if expected_matrix not in workflow:
        observed: dict[str, str] = {}
        lines = workflow.splitlines()
        lane_pattern = re.compile(r"^(\s*)-\s+lane:\s*([A-Za-z0-9_-]+)\s*(?:#.*)?$")
        os_pattern = re.compile(r"^\s*os:\s*['\"]?([^'\"\s#]+)['\"]?\s*(?:#.*)?$")
        for index, line in enumerate(lines):
            match = lane_pattern.match(line)
            if match is None:
                continue
            lane = match.group(2)
            require(lane in runners, f"unexpected workflow matrix lane: {lane}")
            require(lane not in observed, f"duplicate workflow matrix lane: {lane}")
            lane_indent = len(match.group(1))
            selected: str | None = None
            for following in lines[index + 1:]:
                if not following.strip():
                    continue
                following_indent = len(following) - len(following.lstrip())
                if following_indent <= lane_indent and following.lstrip().startswith("-"):
                    break
                os_match = os_pattern.match(following)
                if os_match is not None:
                    selected = os_match.group(1)
                    break
            require(selected is not None, f"workflow matrix lane {lane} has no os value")
            observed[lane] = selected
        require(set(observed) == set(runners), f"workflow runner lanes do not match the manifest: {observed}")
        require(observed == runners, f"workflow runner matrix does not match the manifest: {observed}")
    require("ubuntu-latest" not in workflow and "windows-latest" not in workflow and "macos-latest" not in workflow, "moving runner label remains")

    python_block = _extract_with_block(workflow, "actions/setup-python@")
    require(f"python-version: '{manifest['python']['version']}'" in python_block, "setup-python version does not match manifest")

    flutter_block = _extract_with_block(workflow, "subosito/flutter-action@")
    require(f"flutter-version: '{manifest['flutter']['version']}'" in flutter_block, "Flutter version does not match manifest")
    require("channel: stable" in flutter_block, "Flutter channel is not declared")
    require("cache: true" in flutter_block and "pub-cache: true" in flutter_block, "Flutter/Pub caches are not both enabled")
    expected_cache = str(manifest["cache"]["flutterKeyTemplate"])
    expected_pub_cache = str(manifest["cache"]["pubKeyTemplate"])
    require(f"cache-key: '{expected_cache}'" in flutter_block, "Flutter cache key template drifted")
    require(f"pub-cache-key: '{expected_pub_cache}'" in flutter_block, "Pub cache key template drifted")
    require(":version:" in expected_cache and ":hash:" in expected_cache and ":arch:" in expected_cache, "Flutter cache key omits exact version, lock hash, or architecture")
    require(":version:" in expected_pub_cache and ":hash:" in expected_pub_cache and ":arch:" in expected_pub_cache, "Pub cache key omits exact version, lock hash, or architecture")
    require("tool/toolchain_lock_test.py" in workflow, "workflow does not run the toolchain lock gate")
    return f"validated {len(uses_lines)} immutable action reference(s) and explicit runner labels"


def _run(argv: list[str]) -> tuple[int, str]:
    completed = subprocess.run(
        argv,
        cwd=ROOT,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
        timeout=90,
        check=False,
    )
    return completed.returncode, (completed.stdout or "")[-20000:]


def _first_semver(text: str) -> str | None:
    match = re.search(r"\b([0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?)\b", text)
    return match.group(1) if match else None


def resolve_runtime() -> dict[str, Any]:
    flutter_code, flutter_output = _run(["flutter", "--version", "--machine"])
    require(flutter_code == 0, "flutter --version --machine failed: " + flutter_output[-1200:])
    try:
        flutter_json = json.loads(flutter_output)
    except json.JSONDecodeError as error:
        raise AssertionError(f"Flutter machine output is not JSON: {error}") from error
    require(isinstance(flutter_json, dict), "Flutter machine output must be an object")

    dart_code, dart_output = _run(["dart", "--version"])
    require(dart_code == 0, "dart --version failed: " + dart_output[-1200:])
    dart_version = _first_semver(dart_output) or _first_semver(str(flutter_json.get("dartSdkVersion") or ""))
    require(dart_version is not None, "Dart version could not be parsed")
    flutter_version = _first_semver(str(flutter_json.get("frameworkVersion") or ""))
    require(flutter_version is not None, "Flutter version could not be parsed")
    return {
        "python": platform.python_version(),
        "flutter": flutter_version,
        "dart": dart_version,
        "flutterChannel": flutter_json.get("channel"),
        "flutterFrameworkRevision": flutter_json.get("frameworkRevision"),
        "flutterEngineRevision": flutter_json.get("engineRevision"),
    }


def test_runtime_versions() -> str:
    manifest = load_manifest()
    resolved = resolve_runtime()
    expected = {
        "python": manifest["python"]["version"],
        "flutter": manifest["flutter"]["version"],
        "dart": manifest["dart"]["version"],
    }
    mismatched = [f"{key}: expected {expected[key]}, got {resolved[key]}" for key in expected if resolved[key] != expected[key]]
    require(not mismatched, "; ".join(mismatched))
    require(resolved.get("flutterChannel") == manifest["flutter"]["channel"], "resolved Flutter channel differs")
    return f"resolved Python {resolved['python']}, Flutter {resolved['flutter']}, Dart {resolved['dart']}"


def declared_input_payload(manifest: dict[str, Any]) -> dict[str, Any]:
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-only", action="store_true")
    parser.add_argument("--json-output")
    args = parser.parse_args()
    tests = [
        run_case("Toolchain manifest shape", test_manifest_shape),
        run_case("Declared lockfile hashes", test_lockfiles),
        run_case("Immutable workflow inputs", test_workflow_pins),
    ]
    resolved: dict[str, Any] | None = None
    if not args.source_only:
        runtime_result = run_case("Resolved runtime versions", test_runtime_versions)
        tests.append(runtime_result)
        if runtime_result.passed:
            resolved = resolve_runtime()
    manifest = load_manifest() if MANIFEST.is_file() else {}
    input_payload = declared_input_payload(manifest) if manifest else {}
    failed = [item for item in tests if not item.passed]
    payload = {
        "schemaVersion": "1.0.0",
        "milestone": "P0-004",
        "sourceOnly": args.source_only,
        "platform": {
            "system": platform.system(),
            "release": platform.release(),
            "machine": platform.machine(),
        },
        "manifestSha256": sha256_file(MANIFEST) if MANIFEST.is_file() else None,
        "declaredInputFingerprint": sha256_bytes(canonical(input_payload)) if input_payload else None,
        "resolved": resolved,
        "caseCount": len(tests),
        "passedCount": len(tests) - len(failed),
        "failedCount": len(failed),
        "passed": not failed,
        "results": [asdict(item) for item in tests],
    }
    rendered = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if args.json_output:
        output = Path(args.json_output)
        if not output.is_absolute():
            output = ROOT / output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
