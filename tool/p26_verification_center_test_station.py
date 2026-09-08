#!/usr/bin/env python3
"""Fail-closed, non-shell Test Station runner for P26 Verification Center."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path, PurePosixPath
from typing import Any


STATION_RELATIVE = "docs/roadmap/p26/verification_center_test_station.v1.json"
BUDGET_RELATIVE = "docs/roadmap/p26/performance_budget.v1.json"
SELF_CASE_ID = "p26-test-station-contract"
GOVERNANCE_CASE_IDS = {"p26-roadmap-contract", SELF_CASE_ID}
PROFILE_IDS = [
    "contract",
    "deterministic",
    "behavioral-local",
    "web-fixture",
    "native-owner",
    "updater-operation",
    "dogfood-release",
]
CASE_IDS = [
    "p26-roadmap-contract",
    SELF_CASE_ID,
    "p26-deterministic-fixtures",
    "p26-behavioral-local",
    "p26-web-http-fixture",
    "p26-native-owner",
    "p26-updater-operation",
    "p26-kristin-dogfood",
]
STATION_STATES = {
    "PASS",
    "FAIL",
    "BLOCKED_NOT_IMPLEMENTED",
    "BLOCKED_ENVIRONMENT",
    "BLOCKED_PERMISSION",
    "UNKNOWN",
}
FORBIDDEN_EXECUTABLES = {
    "bash",
    "cmd",
    "cmd.exe",
    "command.com",
    "fish",
    "powershell",
    "powershell.exe",
    "pwsh",
    "pwsh.exe",
    "sh",
    "zsh",
}
PROFILE_ENVIRONMENT = {
    "native-owner": "P26_NATIVE_OWNER_READY",
    "dogfood-release": "P26_DOGFOOD_RELEASE_READY",
}
PROFILE_PERMISSION = {
    "updater-operation": "P26_UPDATER_PERMISSION_GRANTED",
}


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def json_load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise RuntimeError(f"cannot read {path}: {exc}") from exc
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"invalid JSON in {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise RuntimeError(f"{path} must contain a JSON object")
    return value


def run_git(root: Path, *args: str, allow_failure: bool = False) -> str:
    completed = subprocess.run(
        ["git", *args],
        cwd=root,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=20,
        env={**os.environ, "GIT_OPTIONAL_LOCKS": "0"},
        shell=False,
    )
    if completed.returncode != 0 and not allow_failure:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(f"git {' '.join(args)} failed: {detail}")
    return completed.stdout.strip()


def source_identity(root: Path) -> dict[str, Any]:
    status = run_git(root, "status", "--porcelain=v1", "--untracked-files=all")
    branch = run_git(root, "symbolic-ref", "--quiet", "--short", "HEAD", allow_failure=True)
    return {
        "commit": run_git(root, "rev-parse", "HEAD"),
        "tree": run_git(root, "rev-parse", "HEAD^{tree}"),
        "branch": branch or "DETACHED",
        "statusSha256": sha256_bytes(status.encode("utf-8")),
        "statusLineCount": 0 if not status else len(status.splitlines()),
        "status": status,
    }


def public_source_identity(identity: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in identity.items() if key != "status"}


def environment_identity(root: Path) -> dict[str, Any]:
    return {
        "cwd": str(root),
        "os": platform.system(),
        "osRelease": platform.release(),
        "machine": platform.machine(),
        "python": platform.python_version(),
        "pythonExecutable": sys.executable,
    }


def safe_relative_path(value: str) -> bool:
    if not value or "\\" in value or "\x00" in value or "\n" in value or "\r" in value:
        return False
    path = PurePosixPath(value)
    return not path.is_absolute() and ".." not in path.parts


def validate_command(command: Any, case_id: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(command, list) or not command:
        return [f"{case_id}: command must be a non-empty argv array"]
    if not all(isinstance(item, str) and item for item in command):
        return [f"{case_id}: every command argument must be a non-empty string"]
    for index, item in enumerate(command):
        if "\x00" in item or "\n" in item or "\r" in item:
            errors.append(f"{case_id}: argv[{index}] contains a forbidden control character")
    executable = Path(command[0]).name.lower()
    if executable in FORBIDDEN_EXECUTABLES:
        errors.append(f"{case_id}: shell executable {command[0]!r} is forbidden")
    return errors


def validate_station(station: dict[str, Any], root: Path) -> list[str]:
    errors: list[str] = []
    if station.get("schemaVersion") != "1.0.0":
        errors.append("station schemaVersion must be 1.0.0")
    if station.get("suiteId") != "p26.verification-center-test-station-v1":
        errors.append("station suiteId mismatch")

    profiles = station.get("profiles")
    if not isinstance(profiles, list):
        errors.append("station profiles must be an array")
        profiles = []
    profile_ids = [item.get("profileId") for item in profiles if isinstance(item, dict)]
    if profile_ids != PROFILE_IDS:
        errors.append(f"profile order/domain mismatch: {profile_ids!r}")
    if len(profile_ids) != len(set(profile_ids)):
        errors.append("station profile IDs must be unique")

    cases = station.get("cases")
    if not isinstance(cases, list):
        errors.append("station cases must be an array")
        cases = []
    case_ids = [item.get("caseId") for item in cases if isinstance(item, dict)]
    if case_ids != CASE_IDS:
        errors.append(f"case order/domain mismatch: {case_ids!r}")
    if len(case_ids) != len(set(case_ids)):
        errors.append("station case IDs must be unique")

    known_case_ids = set(case_ids)
    for profile in profiles:
        if not isinstance(profile, dict):
            errors.append("station profile entry must be an object")
            continue
        profile_id = profile.get("profileId")
        case_refs = profile.get("caseIds")
        if not isinstance(case_refs, list) or not case_refs:
            errors.append(f"{profile_id}: caseIds must be a non-empty array")
            continue
        if not all(isinstance(value, str) for value in case_refs):
            errors.append(f"{profile_id}: caseIds must contain strings")
            continue
        missing = [value for value in case_refs if value not in known_case_ids]
        if missing:
            errors.append(f"{profile_id}: references unknown cases {missing!r}")

    test_ids: set[str] = set()
    eligible: set[str] = set()
    for case in cases:
        if not isinstance(case, dict):
            errors.append("station case entry must be an object")
            continue
        case_id = case.get("caseId")
        test_id = case.get("testId")
        if not isinstance(case_id, str):
            errors.append("station case has invalid caseId")
            continue
        if not isinstance(test_id, str) or not test_id.startswith("tc.p26."):
            errors.append(f"{case_id}: invalid testId")
        elif test_id in test_ids:
            errors.append(f"{case_id}: duplicate testId {test_id}")
        else:
            test_ids.add(test_id)
        errors.extend(validate_command(case.get("command"), case_id))
        completion_eligible = case.get("completionEligible")
        if completion_eligible is True:
            eligible.add(case_id)
        elif completion_eligible is not False:
            errors.append(f"{case_id}: completionEligible must be boolean")
        if case_id not in GOVERNANCE_CASE_IDS:
            implementation_path = case.get("implementationPath")
            if not isinstance(implementation_path, str) or not safe_relative_path(implementation_path):
                errors.append(f"{case_id}: invalid implementationPath")
        task_ids = case.get("taskIds")
        if not isinstance(task_ids, list) or not task_ids:
            errors.append(f"{case_id}: taskIds must be a non-empty array")
        elif not all(isinstance(value, str) and value.startswith("P26-") for value in task_ids):
            errors.append(f"{case_id}: taskIds contain invalid values")
    if eligible != GOVERNANCE_CASE_IDS:
        errors.append(f"completion-eligible cases must be {sorted(GOVERNANCE_CASE_IDS)!r}")

    contract = next(
        (item for item in profiles if isinstance(item, dict) and item.get("profileId") == "contract"),
        None,
    )
    if not isinstance(contract, dict) or contract.get("caseIds") != [
        "p26-roadmap-contract",
        SELF_CASE_ID,
    ]:
        errors.append("contract profile must contain only the two governance cases")

    for required in (
        root / STATION_RELATIVE,
        root / BUDGET_RELATIVE,
        root / "tool/p26_verification_center_roadmap_test.py",
        root / "tool/p26_verification_center_test_station.py",
    ):
        if not required.is_file():
            errors.append(f"missing station dependency: {required.relative_to(root)}")
    return errors


def resolve_command(command: list[str]) -> list[str]:
    resolved = list(command)
    if Path(resolved[0]).name.lower() in {"python", "python3", "python.exe"}:
        resolved[0] = sys.executable
    return resolved


def output_record(value: bytes, limit: int) -> dict[str, Any]:
    tail = value[-limit:]
    return {
        "bytes": len(value),
        "sha256": sha256_bytes(value),
        "tail": tail.decode("utf-8", errors="replace"),
        "truncated": len(value) > len(tail),
    }


def blocker_for_case(
    profile_id: str,
    case: dict[str, Any],
    root: Path,
) -> tuple[str, str] | None:
    case_id = str(case.get("caseId"))
    if case_id in GOVERNANCE_CASE_IDS:
        return None
    implementation_path = case.get("implementationPath")
    if not isinstance(implementation_path, str) or not (root / implementation_path).is_file():
        return (
            "BLOCKED_NOT_IMPLEMENTED",
            f"implementation path is absent: {implementation_path!r}",
        )
    command = case.get("command")
    if isinstance(command, list) and command:
        executable = resolve_command([str(value) for value in command])[0]
        if not Path(executable).is_file() and shutil.which(executable) is None:
            return ("BLOCKED_ENVIRONMENT", f"required executable is unavailable: {executable}")
    env_name = PROFILE_ENVIRONMENT.get(profile_id)
    if env_name and os.environ.get(env_name) != "1":
        return ("BLOCKED_ENVIRONMENT", f"required environment assertion is absent: {env_name}=1")
    permission_name = PROFILE_PERMISSION.get(profile_id)
    if permission_name and os.environ.get(permission_name) != "1":
        return ("BLOCKED_PERMISSION", f"required permission assertion is absent: {permission_name}=1")
    return None


def execute_case(
    profile_id: str,
    case: dict[str, Any],
    root: Path,
    output_limit: int,
) -> dict[str, Any]:
    case_id = str(case.get("caseId"))
    started = time.time()
    monotonic_start = time.monotonic()
    if case_id == SELF_CASE_ID:
        return {
            "caseId": case_id,
            "testId": case.get("testId"),
            "assuranceLevel": case.get("assuranceLevel"),
            "completionEligible": case.get("completionEligible"),
            "state": "PASS",
            "reason": "station schema, safe-argv policy and source-integrity checks passed",
            "startedAtUnix": started,
            "durationMs": round((time.monotonic() - monotonic_start) * 1000, 3),
            "argv": [],
            "returnCode": 0,
            "stdout": output_record(b"P26_TEST_STATION_SELF_PASS\n", output_limit),
            "stderr": output_record(b"", output_limit),
        }

    blocker = blocker_for_case(profile_id, case, root)
    if blocker is not None:
        state, reason = blocker
        return {
            "caseId": case_id,
            "testId": case.get("testId"),
            "assuranceLevel": case.get("assuranceLevel"),
            "completionEligible": case.get("completionEligible"),
            "state": state,
            "reason": reason,
            "startedAtUnix": started,
            "durationMs": round((time.monotonic() - monotonic_start) * 1000, 3),
            "argv": case.get("command"),
            "returnCode": None,
            "stdout": output_record(b"", output_limit),
            "stderr": output_record(reason.encode("utf-8"), output_limit),
        }

    command = case.get("command")
    if not isinstance(command, list):
        raise RuntimeError(f"{case_id}: invalid command after station validation")
    argv = resolve_command([str(value) for value in command])
    child_env = dict(os.environ)
    child_env["PYTHONDONTWRITEBYTECODE"] = "1"
    child_env["GIT_OPTIONAL_LOCKS"] = "0"
    try:
        completed = subprocess.run(
            argv,
            cwd=root,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=120,
            env=child_env,
            shell=False,
        )
        state = "PASS" if completed.returncode == 0 else "FAIL"
        reason = "command completed successfully" if state == "PASS" else "command returned non-zero"
        return_code: int | None = completed.returncode
        stdout = completed.stdout
        stderr = completed.stderr
    except subprocess.TimeoutExpired as exc:
        state = "FAIL"
        reason = "command exceeded the 120-second station timeout"
        return_code = None
        stdout = exc.stdout or b""
        stderr = (exc.stderr or b"") + reason.encode("utf-8")
    except OSError as exc:
        state = "BLOCKED_ENVIRONMENT"
        reason = f"command could not start: {exc}"
        return_code = None
        stdout = b""
        stderr = reason.encode("utf-8")
    return {
        "caseId": case_id,
        "testId": case.get("testId"),
        "assuranceLevel": case.get("assuranceLevel"),
        "completionEligible": case.get("completionEligible"),
        "state": state,
        "reason": reason,
        "startedAtUnix": started,
        "durationMs": round((time.monotonic() - monotonic_start) * 1000, 3),
        "argv": argv,
        "returnCode": return_code,
        "stdout": output_record(stdout, output_limit),
        "stderr": output_record(stderr, output_limit),
    }


def aggregate(cases: list[dict[str, Any]]) -> str:
    states = [str(case.get("state")) for case in cases]
    if states and all(state == "PASS" for state in states):
        return "PASS"
    for state in (
        "FAIL",
        "BLOCKED_PERMISSION",
        "BLOCKED_ENVIRONMENT",
        "BLOCKED_NOT_IMPLEMENTED",
        "UNKNOWN",
    ):
        if state in states:
            return state
    return "UNKNOWN"


def build_listing(station: dict[str, Any], root: Path) -> dict[str, Any]:
    cases = {
        item.get("caseId"): item
        for item in station.get("cases", [])
        if isinstance(item, dict) and isinstance(item.get("caseId"), str)
    }
    profiles: list[dict[str, Any]] = []
    for profile in station.get("profiles", []):
        if not isinstance(profile, dict):
            continue
        profile_id = str(profile.get("profileId"))
        listed_cases: list[dict[str, Any]] = []
        for case_id in profile.get("caseIds", []):
            case = cases.get(case_id, {})
            blocker = blocker_for_case(profile_id, case, root)
            listed_cases.append(
                {
                    "caseId": case_id,
                    "testId": case.get("testId"),
                    "assuranceLevel": case.get("assuranceLevel"),
                    "completionEligible": case.get("completionEligible"),
                    "availability": "READY" if blocker is None else blocker[0],
                    "reason": None if blocker is None else blocker[1],
                }
            )
        profiles.append(
            {
                "profileId": profile_id,
                "description": profile.get("description"),
                "cases": listed_cases,
            }
        )
    return {
        "suiteId": station.get("suiteId"),
        "profiles": profiles,
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=".", help="Repository root")
    parser.add_argument("--profile", default="contract", help="Station profile ID")
    parser.add_argument("--list", action="store_true", help="List profiles and current availability")
    parser.add_argument(
        "--check",
        action="store_true",
        help="Use temporary evidence storage and enforce source non-mutation",
    )
    parser.add_argument("--evidence-dir", help="Explicit evidence output directory")
    return parser.parse_args(argv)


def write_report(report: dict[str, Any], directory: Path) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "p26-verification-center-station-report.json"
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    root = Path(args.project).expanduser().resolve()
    try:
        station = json_load(root / STATION_RELATIVE)
        budget = json_load(root / BUDGET_RELATIVE)
        validation_errors = validate_station(station, root)
        if validation_errors:
            payload = {
                "suiteId": station.get("suiteId"),
                "status": "FAIL",
                "errors": validation_errors,
            }
            print(json.dumps(payload, indent=2, sort_keys=True))
            return 1

        if args.list:
            print(json.dumps(build_listing(station, root), indent=2, sort_keys=True))
            return 0

        profiles = {
            item.get("profileId"): item
            for item in station.get("profiles", [])
            if isinstance(item, dict)
        }
        profile = profiles.get(args.profile)
        if not isinstance(profile, dict):
            print(
                json.dumps(
                    {
                        "suiteId": station.get("suiteId"),
                        "status": "FAIL",
                        "errors": [f"unknown profile: {args.profile}"],
                    },
                    indent=2,
                    sort_keys=True,
                )
            )
            return 2
        cases_by_id = {
            item.get("caseId"): item
            for item in station.get("cases", [])
            if isinstance(item, dict)
        }
        before = source_identity(root)
        started = time.time()
        output_limit = int(budget.get("metrics", {}).get("logPreviewBytesMax", 65536))
        case_results = [
            execute_case(args.profile, cases_by_id[case_id], root, output_limit)
            for case_id in profile.get("caseIds", [])
        ]
        after = source_identity(root)
        mutation = before["status"] != after["status"] or before["commit"] != after["commit"] or before["tree"] != after["tree"]
        if mutation:
            case_results.append(
                {
                    "caseId": "p26-source-integrity",
                    "testId": "tc.p26.source-integrity",
                    "assuranceLevel": "architecture_lint",
                    "completionEligible": True,
                    "state": "FAIL",
                    "reason": "tracked or untracked repository state changed during station execution",
                    "startedAtUnix": time.time(),
                    "durationMs": 0,
                    "argv": [],
                    "returnCode": None,
                    "stdout": output_record(b"", output_limit),
                    "stderr": output_record(b"source mutation detected", output_limit),
                }
            )
        status = aggregate(case_results)
        report = {
            "schemaVersion": "1.0.0",
            "suiteId": station.get("suiteId"),
            "profileId": args.profile,
            "status": status,
            "startedAtUnix": started,
            "finishedAtUnix": time.time(),
            "sourceBefore": public_source_identity(before),
            "sourceAfter": public_source_identity(after),
            "environment": environment_identity(root),
            "sourceMutationDetected": mutation,
            "cases": case_results,
        }

        explicit_evidence = Path(args.evidence_dir).expanduser().resolve() if args.evidence_dir else None
        if args.check:
            with tempfile.TemporaryDirectory(prefix="p26-station-") as temporary:
                report_path = write_report(report, Path(temporary))
                report["evidence"] = {
                    "ephemeral": True,
                    "reportSha256": sha256_bytes(report_path.read_bytes()),
                }
        elif explicit_evidence is not None:
            report_path = write_report(report, explicit_evidence)
            report["evidence"] = {
                "ephemeral": False,
                "path": str(report_path),
                "reportSha256": sha256_bytes(report_path.read_bytes()),
            }
        else:
            report["evidence"] = {
                "ephemeral": True,
                "note": "no persistent evidence directory requested",
            }
        print(json.dumps(report, indent=2, sort_keys=True))
        return 0 if status == "PASS" else 1
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as exc:
        print(
            json.dumps(
                {
                    "suiteId": "p26.verification-center-test-station-v1",
                    "status": "UNKNOWN",
                    "errors": [str(exc)],
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
