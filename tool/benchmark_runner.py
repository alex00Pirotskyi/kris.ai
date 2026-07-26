#!/usr/bin/env python3
"""Deterministic benchmark corpus runner for Kristin P0-009.

The P0-009 portable baseline is network-free, credential-free, and model-free.
It records current evidence and capability gaps without treating source
inspection, unsupported capabilities, or unavailable SDKs as passing
behavioral proof. Future model/provider runs may evaluate the same corpus by
supplying a candidate root.
"""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any

sys.dont_write_bytecode = True

ALLOWED_STATUSES = ("passed", "failed", "unavailable", "unsupported", "not_run", "error")
ALLOWED_KINDS = (
    "command_exit",
    "command_json_stdout",
    "command_json_file",
    "path_policy",
    "capability_probe",
    "model_workspace",
    "model_json",
)
ALLOWED_ASSURANCE = ("behavioral", "source_contract", "capability_inventory", "benchmark_task")
ALLOWED_PROOF = ("executed_behavior", "source_inspection", "capability_probe", "model_evaluation")
CASE_ID_RE = re.compile(r"^[a-z0-9][a-z0-9_.-]*$")
MAX_COMMAND_OUTPUT_CHARS = 4 * 1024 * 1024
SAFE_ENV_KEYS = (
    "PATH", "SYSTEMROOT", "WINDIR", "COMSPEC", "PATHEXT", "TEMP", "TMP",
    "HOME", "USERPROFILE", "LANG", "LC_ALL",
)


class BenchmarkError(RuntimeError):
    pass


@dataclass(frozen=True)
class CaseResult:
    id: str
    category: str
    title: str
    status: str
    score: float | None
    assuranceLevel: str
    proofKind: str
    reason: str
    observations: dict[str, Any]
    evidenceSha256: str

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


def _duplicate_guard(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise BenchmarkError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=_duplicate_guard,
        )
    except (OSError, json.JSONDecodeError, BenchmarkError) as error:
        raise BenchmarkError(f"cannot parse {path}: {error}") from error
    if not isinstance(value, dict):
        raise BenchmarkError(f"JSON root must be an object: {path}")
    return value


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_text(value: str) -> str:
    return sha256_bytes(value.encode("utf-8"))


def git_index_bytes(project: Path, relative: str) -> bytes | None:
    """Return the staged Git blob so checkout EOL policy cannot change evidence."""
    if not safe_relative(relative):
        return None
    try:
        completed = subprocess.run(
            ["git", "show", f":{relative}"],
            cwd=project,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError:
        return None
    return completed.stdout if completed.returncode == 0 else None


def canonical_project_file_bytes(project: Path, path: Path) -> bytes:
    """Hash tracked source from the Git index and untracked fixtures from disk."""
    try:
        relative = path.relative_to(project).as_posix()
    except ValueError:
        return path.read_bytes()
    indexed = git_index_bytes(project, relative)
    return indexed if indexed is not None else path.read_bytes()


def safe_relative(value: str) -> bool:
    if not value or "\\" in value:
        return False
    path = Path(value)
    return not path.is_absolute() and ".." not in path.parts and path.as_posix() == value


def hash_tree(project: Path, root: Path) -> str:
    rows: list[str] = []
    if not root.exists():
        return sha256_text("")
    for path in sorted(root.rglob("*")):
        if not path.is_file() or "__pycache__" in path.parts or path.suffix == ".pyc":
            continue
        relative = path.relative_to(root).as_posix()
        rows.append(
            f"{sha256_bytes(canonical_project_file_bytes(project, path))}  {relative}"
        )
    return sha256_text("\n".join(rows) + ("\n" if rows else ""))


def json_path(value: Any, path: str) -> Any:
    current = value
    if path in ("", "$"):
        return current
    normalized = path[2:] if path.startswith("$.") else path
    for part in normalized.split("."):
        if isinstance(current, dict) and part in current:
            current = current[part]
        elif isinstance(current, list) and part.isdigit() and int(part) < len(current):
            current = current[int(part)]
        else:
            raise BenchmarkError(f"JSON path not found: {path}")
    return current


def redact_output(text: str, project: Path) -> str:
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    roots = {
        str(project),
        project.as_posix(),
        str(project).replace("\\", "/"),
        str(project).replace("/", "\\"),
    }
    for root in sorted(roots, key=len, reverse=True):
        if root:
            normalized = normalized.replace(root, "<ROOT>")
    normalized = re.sub(
        r"(?i)\b(https?|socks5h?)://[^/\s:@]+:[^@\s/]+@",
        r"\1://<redacted>@",
        normalized,
    )
    normalized = re.sub(
        r"(?i)(authorization\s*[:=]\s*bearer\s+)[^\s]+",
        r"\1<redacted>",
        normalized,
    )
    normalized = re.sub(
        r"(?i)(api[_-]?key|token|secret|password)(\s*[:=]\s*)[^\s,;]+",
        r"\1\2<redacted>",
        normalized,
    )
    normalized = re.sub(r"\bsk-[A-Za-z0-9_-]{12,}\b", "<redacted>", normalized)
    return normalized


def validate_suite_data(suite: dict[str, Any], project: Path | None = None) -> list[str]:
    errors: list[str] = []
    if suite.get("schemaVersion") != "1.0.0":
        errors.append("schemaVersion must be 1.0.0")
    for key in ("suiteId", "suiteVersion", "title", "baselineTimestamp"):
        if not isinstance(suite.get(key), str) or not str(suite.get(key)).strip():
            errors.append(f"{key} must be a non-empty string")
    if suite.get("networkPolicy") != "forbidden":
        errors.append("networkPolicy must be forbidden for P0-009")

    categories = suite.get("categories")
    category_ids: set[str] = set()
    if not isinstance(categories, list) or not categories:
        errors.append("categories must be a non-empty list")
    else:
        for item in categories:
            if not isinstance(item, dict) or not isinstance(item.get("id"), str):
                errors.append("each category must be an object with an id")
                continue
            category_id = str(item["id"])
            if category_id in category_ids:
                errors.append(f"duplicate category ID: {category_id}")
            category_ids.add(category_id)

    cases = suite.get("cases")
    if not isinstance(cases, list) or not cases:
        errors.append("cases must be a non-empty list")
        return errors

    seen: set[str] = set()
    case_order: list[str] = []
    required_categories = {
        "coding", "analysis", "path_safety", "crash_recovery",
        "browser_absent", "research",
    }
    for index, case in enumerate(cases):
        if not isinstance(case, dict):
            errors.append(f"cases[{index}] must be an object")
            continue
        case_id = case.get("id")
        if not isinstance(case_id, str) or not CASE_ID_RE.match(case_id):
            errors.append(f"cases[{index}].id is invalid: {case_id!r}")
            continue
        if case_id in seen:
            errors.append(f"duplicate case ID: {case_id}")
        seen.add(case_id)
        case_order.append(case_id)
        if case.get("category") not in category_ids:
            errors.append(f"{case_id} references unknown category {case.get('category')!r}")
        if case.get("kind") not in ALLOWED_KINDS:
            errors.append(f"{case_id} has invalid kind {case.get('kind')!r}")
        if case.get("assuranceLevel") not in ALLOWED_ASSURANCE:
            errors.append(f"{case_id} has invalid assuranceLevel")
        if case.get("proofKind") not in ALLOWED_PROOF:
            errors.append(f"{case_id} has invalid proofKind")
        weight = case.get("weight")
        if not isinstance(weight, (int, float)) or isinstance(weight, bool) or weight <= 0:
            errors.append(f"{case_id} weight must be positive")
        fixture = case.get("fixture")
        if fixture is not None and (
            not isinstance(fixture, str) or not safe_relative(fixture)
        ):
            errors.append(f"{case_id} fixture path is unsafe")
        command = case.get("command")
        if command is not None:
            if (
                not isinstance(command, dict)
                or not isinstance(command.get("argv"), list)
                or not command.get("argv")
            ):
                errors.append(f"{case_id} command must contain argv")
            elif not all(isinstance(item, str) and item for item in command["argv"]):
                errors.append(f"{case_id} command argv must contain non-empty strings")
            else:
                first = command["argv"][0]
                if first not in {"{python}", "flutter", "dart"}:
                    errors.append(
                        f"{case_id} command executable is not allowlisted: {first}"
                    )
                if first == "{python}" and len(command["argv"]) > 1:
                    script = command["argv"][1]
                    if script.startswith("-"):
                        pass
                    elif not safe_relative(script) or not script.startswith("tool/"):
                        errors.append(
                            f"{case_id} Python command must target a safe tool/ script"
                        )
        candidate = case.get("candidate")
        if candidate is not None:
            if not isinstance(candidate, dict):
                errors.append(f"{case_id} candidate must be an object")
            else:
                relative_path = candidate.get("relativePath")
                if not isinstance(relative_path, str) or not safe_relative(relative_path):
                    errors.append(f"{case_id} candidate.relativePath is unsafe")
                if case.get("kind") == "model_workspace":
                    acceptance = candidate.get("acceptanceCommand")
                    if (
                        not isinstance(acceptance, list)
                        or not acceptance
                        or not all(isinstance(item, str) and item for item in acceptance)
                    ):
                        errors.append(f"{case_id} acceptanceCommand is invalid")
                    elif acceptance[0] != "{python}":
                        errors.append(
                            f"{case_id} acceptanceCommand must use the pinned Python runtime"
                        )
                    mutable_paths = candidate.get("mutablePaths")
                    if (
                        not isinstance(mutable_paths, list)
                        or not mutable_paths
                        or any(
                            not isinstance(item, str) or not safe_relative(item)
                            for item in mutable_paths
                        )
                    ):
                        errors.append(f"{case_id} mutablePaths must contain safe paths")

        if project is not None:
            for relative in case.get("requiredFiles") or []:
                if not isinstance(relative, str) or not safe_relative(relative):
                    errors.append(f"{case_id} required file path is unsafe")
            if isinstance(fixture, str) and not (project / fixture).exists():
                errors.append(f"{case_id} fixture does not exist: {fixture}")

    order_by_id = {case_id: index for index, case_id in enumerate(case_order)}
    for index, case in enumerate(cases):
        if not isinstance(case, dict) or not isinstance(case.get("id"), str):
            continue
        requires = case.get("requiresCase")
        if requires is None:
            continue
        if not isinstance(requires, str) or requires not in order_by_id:
            errors.append(f"{case['id']} requires unknown case {requires!r}")
        elif order_by_id[requires] >= index:
            errors.append(
                f"{case['id']} requiresCase must refer to an earlier case: {requires}"
            )

    observed_categories = {
        str(case.get("category")) for case in cases if isinstance(case, dict)
    }
    missing_categories = sorted(required_categories - observed_categories)
    if missing_categories:
        errors.append(
            "required categories missing cases: " + ", ".join(missing_categories)
        )
    return errors


def benchmark_inputs_sha256(
    project: Path,
    suite_path: Path,
    suite: dict[str, Any],
) -> str:
    files: set[str] = {
        suite_path.relative_to(project).as_posix(),
        "tool/benchmark_runner.py",
    }
    for case in suite.get("cases") or []:
        if not isinstance(case, dict):
            continue
        fixture = case.get("fixture")
        if isinstance(fixture, str):
            root = project / fixture
            if root.is_file():
                files.add(fixture)
            elif root.is_dir():
                for path in root.rglob("*"):
                    if (
                        path.is_file()
                        and "__pycache__" not in path.parts
                        and path.suffix != ".pyc"
                    ):
                        files.add(path.relative_to(project).as_posix())
        for relative in case.get("requiredFiles") or []:
            if isinstance(relative, str) and safe_relative(relative):
                files.add(relative)
        probe = case.get("probe")
        if isinstance(probe, dict):
            for relative in (probe.get("anyFiles") or []):
                if isinstance(relative, str) and safe_relative(relative):
                    files.add(relative)
            for relative in (probe.get("behavioralEvidenceFiles") or []):
                if isinstance(relative, str) and safe_relative(relative):
                    files.add(relative)
            files.add("schemas/tool_registry.v2.json")
        command = case.get("command")
        if isinstance(command, dict):
            argv = command.get("argv") or []
            if (
                len(argv) > 1
                and argv[0] == "{python}"
                and isinstance(argv[1], str)
                and safe_relative(argv[1])
            ):
                files.add(argv[1])

    rows: list[str] = []
    for relative in sorted(files):
        path = project / relative
        if not path.is_file():
            rows.append(f"MISSING  {relative}")
        else:
            rows.append(
                f"{sha256_bytes(canonical_project_file_bytes(project, path))}  {relative}"
            )
    return sha256_text("\n".join(rows) + "\n")


def expand_argv(
    argv: list[str],
    project: Path,
    result_path: Path | None = None,
) -> list[str]:
    result: list[str] = []
    for token in argv:
        token = token.replace("{project}", str(project))
        if result_path is not None:
            token = token.replace("{result}", str(result_path))
        if token == "{python}":
            token = sys.executable
        result.append(token)
    return result


def safe_environment(suite: dict[str, Any]) -> dict[str, str]:
    env = {key: os.environ[key] for key in SAFE_ENV_KEYS if key in os.environ}
    env.update(
        {
            "CI": "true",
            "PYTHONDONTWRITEBYTECODE": "1",
            "KRISTIN_BENCHMARK_NETWORK": "forbidden",
            "SOURCE_DATE_EPOCH": str(suite.get("sourceDateEpoch", 1784851200)),
        }
    )
    return env


def run_command(
    argv: list[str],
    project: Path,
    timeout: int,
    suite: dict[str, Any],
) -> tuple[int, str]:
    completed = subprocess.run(
        argv,
        cwd=project,
        env=safe_environment(suite),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
        check=False,
        timeout=timeout,
    )
    output = completed.stdout
    if len(output) > MAX_COMMAND_OUTPUT_CHARS:
        raise BenchmarkError(
            f"command output exceeded {MAX_COMMAND_OUTPUT_CHARS} characters"
        )
    return completed.returncode, redact_output(output, project)


def evidence_hash(observations: dict[str, Any]) -> str:
    return sha256_text(canonical_json(observations))


def result_for(
    case: dict[str, Any],
    status: str,
    score: float | None,
    reason: str,
    observations: dict[str, Any] | None = None,
) -> CaseResult:
    if status not in ALLOWED_STATUSES:
        raise BenchmarkError(f"invalid case status {status}")
    obs = observations or {}
    return CaseResult(
        id=str(case["id"]),
        category=str(case["category"]),
        title=str(case["title"]),
        status=status,
        score=score,
        assuranceLevel=str(case["assuranceLevel"]),
        proofKind=str(case["proofKind"]),
        reason=reason,
        observations=obs,
        evidenceSha256=evidence_hash(obs),
    )


def missing_required_files(case: dict[str, Any], project: Path) -> list[str]:
    return [
        relative
        for relative in case.get("requiredFiles") or []
        if isinstance(relative, str) and not (project / relative).is_file()
    ]


def command_case(
    case: dict[str, Any],
    project: Path,
    suite: dict[str, Any],
    include_sdk: bool,
) -> CaseResult:
    missing = missing_required_files(case, project)
    if missing:
        return result_for(
            case,
            "unavailable",
            None,
            "required_files_missing",
            {"missing": missing},
        )
    command = case.get("command") or {}
    argv_template = list(command.get("argv") or [])
    first = argv_template[0] if argv_template else ""
    if first in {"flutter", "dart"} and not include_sdk:
        return result_for(
            case,
            "unavailable",
            None,
            "portable_baseline_excludes_sdk",
            {"requiredExecutable": first},
        )
    if first in {"flutter", "dart"} and shutil.which(first) is None:
        return result_for(
            case,
            "unavailable",
            None,
            "required_executable_unavailable",
            {"requiredExecutable": first},
        )

    timeout = int(command.get("timeoutSeconds", 180))
    result_file: Path | None = None
    with tempfile.TemporaryDirectory(
        prefix="kristin-benchmark-command-"
    ) as temporary:
        if case["kind"] == "command_json_file":
            result_file = Path(temporary) / "result.json"
        argv = expand_argv(argv_template, project, result_file)
        try:
            exit_code, output = run_command(argv, project, timeout, suite)
        except subprocess.TimeoutExpired:
            return result_for(
                case,
                "failed",
                0.0,
                "command_timeout",
                {"timeoutSeconds": timeout},
            )

        expected_exit = int(command.get("expectedExitCode", 0))
        observations: dict[str, Any] = {"exitCode": exit_code}
        payload: Any = None
        if case["kind"] == "command_json_stdout" and exit_code == expected_exit:
            try:
                payload = json.loads(output)
            except json.JSONDecodeError:
                return result_for(
                    case,
                    "failed",
                    0.0,
                    "invalid_json_stdout",
                    observations,
                )
        elif case["kind"] == "command_json_file" and exit_code == expected_exit:
            if result_file is None or not result_file.is_file():
                return result_for(
                    case,
                    "failed",
                    0.0,
                    "result_file_missing",
                    observations,
                )
            try:
                payload = json.loads(result_file.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                return result_for(
                    case,
                    "failed",
                    0.0,
                    "invalid_json_result_file",
                    observations,
                )

        if payload is not None:
            selected: dict[str, Any] = {}
            for path in case.get("select") or []:
                try:
                    selected[path] = json_path(payload, path)
                except BenchmarkError as error:
                    return result_for(
                        case,
                        "failed",
                        0.0,
                        "selected_json_path_missing",
                        {
                            **observations,
                            "path": path,
                            "error": str(error),
                        },
                    )
            minimums = case.get("expectMin") or {}
            equals = case.get("expectEquals") or {}
            observations["selected"] = {
                path: (
                    {
                        "minimum": minimums[path],
                        "satisfied": isinstance(value, (int, float))
                        and not isinstance(value, bool)
                        and value >= minimums[path],
                    }
                    if path in minimums and path not in equals
                    else value
                )
                for path, value in selected.items()
            }

        failures: list[str] = []
        if exit_code != expected_exit:
            failures.append(f"exitCode={exit_code} expected={expected_exit}")
        for path, expected in (case.get("expectEquals") or {}).items():
            try:
                actual = json_path(payload, path) if payload is not None else None
            except BenchmarkError:
                actual = "<missing>"
            if actual != expected:
                failures.append(f"{path}={actual!r} expected={expected!r}")
        for path, minimum in (case.get("expectMin") or {}).items():
            try:
                actual = json_path(payload, path) if payload is not None else None
            except BenchmarkError:
                actual = None
            if not isinstance(actual, (int, float)) or actual < minimum:
                failures.append(f"{path}={actual!r} expected>={minimum!r}")

        if failures:
            observations["failures"] = failures
            return result_for(
                case,
                "failed",
                0.0,
                "expectation_failed",
                observations,
            )
        return result_for(
            case,
            "passed",
            1.0,
            "command_expectations_satisfied",
            observations,
        )


def import_source_tree_policy(project: Path):
    path = project / "tool/source_tree_policy.py"
    if not path.is_file():
        raise BenchmarkError("tool/source_tree_policy.py is missing")
    spec = importlib.util.spec_from_file_location(
        "p0_009_source_tree_policy", path
    )
    if spec is None or spec.loader is None:
        raise BenchmarkError("cannot load source_tree_policy.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def path_policy_case(case: dict[str, Any], project: Path) -> CaseResult:
    try:
        module = import_source_tree_policy(project)
    except Exception as error:
        return result_for(
            case,
            "unavailable",
            None,
            "path_policy_unavailable",
            {"error": type(error).__name__},
        )
    rows: list[dict[str, Any]] = []
    correct = 0
    for item in case.get("paths") or []:
        path = str(item.get("path"))
        expected = bool(item.get("expectedGenerated"))
        actual = bool(module.is_generated_path(path))
        matches = actual == expected
        correct += int(matches)
        rows.append(
            {
                "path": path,
                "expectedGenerated": expected,
                "actualGenerated": actual,
                "matches": matches,
            }
        )
    total = len(rows)
    score = correct / total if total else 0.0
    observations = {
        "correct": correct,
        "total": total,
        "mismatches": [row for row in rows if not row["matches"]],
    }
    return result_for(
        case,
        "passed" if correct == total else "failed",
        score,
        "all_path_expectations_satisfied"
        if correct == total
        else "path_policy_gaps_recorded",
        observations,
    )


def tool_registry_names(project: Path) -> set[str]:
    path = project / "schemas/tool_registry.v2.json"
    if not path.is_file():
        return set()
    try:
        value = load_json(path)
    except BenchmarkError:
        return set()
    names: list[str] = []
    raw = value.get("tools") or value.get("contracts") or []
    if isinstance(raw, list):
        for item in raw:
            if isinstance(item, dict) and isinstance(item.get("name"), str):
                names.append(str(item["name"]))
    return set(names)


def capability_probe_case(case: dict[str, Any], project: Path) -> CaseResult:
    probe = case.get("probe") or {}
    signals: list[str] = []
    for relative in probe.get("anyFiles") or []:
        if isinstance(relative, str) and (project / relative).exists():
            signals.append(f"file:{relative}")
    names = tool_registry_names(project)
    for prefix in probe.get("toolPrefixes") or []:
        if isinstance(prefix, str) and any(name.startswith(prefix) for name in names):
            signals.append(f"tool-prefix:{prefix}")

    evidence_files = [
        relative
        for relative in (probe.get("behavioralEvidenceFiles") or [])
        if isinstance(relative, str) and safe_relative(relative)
    ]
    present_evidence = [
        relative for relative in evidence_files if (project / relative).is_file()
    ]
    behavior_supported = bool(evidence_files) and len(present_evidence) == len(evidence_files)
    observations = {
        "supported": behavior_supported,
        "implementationSignals": sorted(signals),
        "behavioralEvidenceFiles": evidence_files,
        "presentBehavioralEvidenceFiles": present_evidence,
        "checkedFileCount": len(probe.get("anyFiles") or []),
        "checkedToolPrefixes": list(probe.get("toolPrefixes") or []),
    }
    if behavior_supported:
        return result_for(
            case,
            "passed",
            1.0,
            "behavioral_capability_evidence_present",
            observations,
        )
    reason = (
        "implementation_signal_without_behavioral_evidence"
        if signals
        else str(probe.get("unsupportedReason") or "capability_not_implemented")
    )
    return result_for(case, "unsupported", 0.0, reason, observations)


def case_result_by_id(
    results: list[CaseResult],
    case_id: str,
) -> CaseResult | None:
    return next((item for item in results if item.id == case_id), None)


def model_workspace_case(
    case: dict[str, Any],
    project: Path,
    suite: dict[str, Any],
    candidate_root: Path | None,
    prior: list[CaseResult],
) -> CaseResult:
    requires = case.get("requiresCase")
    if isinstance(requires, str):
        prerequisite = case_result_by_id(prior, requires)
        if prerequisite is not None and prerequisite.status == "unsupported":
            return result_for(
                case,
                "unsupported",
                0.0,
                f"required_capability_unsupported:{requires}",
                {"requiredCase": requires},
            )
    if candidate_root is None:
        return result_for(
            case,
            "not_run",
            None,
            "model_candidate_not_supplied",
            {"candidateInterface": case.get("candidate")},
        )
    candidate = case.get("candidate") or {}
    relative = str(candidate.get("relativePath") or case["id"])
    if not safe_relative(relative):
        return result_for(
            case,
            "error",
            None,
            "candidate_path_unsafe",
            {"relativePath": relative},
        )
    workspace = candidate_root / relative
    if not workspace.is_dir():
        return result_for(
            case,
            "not_run",
            None,
            "candidate_workspace_missing",
            {"expected": relative},
        )
    command = candidate.get("acceptanceCommand") or []
    mutable_paths = candidate.get("mutablePaths") or []
    if not isinstance(command, list) or not command or command[0] != "{python}":
        return result_for(
            case,
            "error",
            None,
            "candidate_acceptance_command_invalid",
        )
    if not isinstance(mutable_paths, list) or not mutable_paths:
        return result_for(case, "error", None, "candidate_mutable_paths_missing")
    fixture = case.get("fixture")
    if not isinstance(fixture, str) or not (project / fixture).is_dir():
        return result_for(case, "error", None, "candidate_fixture_missing")

    try:
        with tempfile.TemporaryDirectory(
            prefix="kristin-benchmark-candidate-"
        ) as temporary:
            evaluation = Path(temporary) / "workspace"
            shutil.copytree(project / fixture, evaluation)
            copied: list[str] = []
            for mutable in mutable_paths:
                if not isinstance(mutable, str) or not safe_relative(mutable):
                    return result_for(
                        case, "error", None, "candidate_mutable_path_unsafe"
                    )
                source = workspace / mutable
                if not source.is_file():
                    return result_for(
                        case,
                        "failed",
                        0.0,
                        "candidate_mutable_file_missing",
                        {"path": mutable},
                    )
                target = evaluation / mutable
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
                copied.append(mutable)
            argv = [
                sys.executable if token == "{python}" else str(token)
                for token in command
            ]
            completed = subprocess.run(
                argv,
                cwd=evaluation,
                env=safe_environment(suite),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                errors="replace",
                timeout=int(candidate.get("timeoutSeconds", 60)),
                check=False,
            )
    except subprocess.TimeoutExpired:
        return result_for(
            case,
            "failed",
            0.0,
            "candidate_acceptance_timeout",
        )
    observations = {
        "exitCode": completed.returncode,
        "immutableEvaluator": True,
        "copiedMutablePaths": sorted(copied),
    }
    return result_for(
        case,
        "passed" if completed.returncode == 0 else "failed",
        1.0 if completed.returncode == 0 else 0.0,
        "candidate_acceptance_passed"
        if completed.returncode == 0
        else "candidate_acceptance_failed",
        observations,
    )


def model_json_case(
    case: dict[str, Any],
    candidate_root: Path | None,
    prior: list[CaseResult],
) -> CaseResult:
    requires = case.get("requiresCase")
    if isinstance(requires, str):
        prerequisite = case_result_by_id(prior, requires)
        if prerequisite is not None and prerequisite.status == "unsupported":
            return result_for(
                case,
                "unsupported",
                0.0,
                f"required_capability_unsupported:{requires}",
                {"requiredCase": requires},
            )
    if candidate_root is None:
        return result_for(
            case,
            "not_run",
            None,
            "model_candidate_not_supplied",
            {"candidateInterface": case.get("candidate")},
        )
    candidate = case.get("candidate") or {}
    relative = str(
        candidate.get("relativePath") or f"{case['id']}.json"
    )
    if not safe_relative(relative):
        return result_for(
            case,
            "error",
            None,
            "candidate_path_unsafe",
            {"relativePath": relative},
        )
    path = candidate_root / relative
    if not path.is_file():
        return result_for(
            case,
            "not_run",
            None,
            "candidate_json_missing",
            {"expected": relative},
        )
    try:
        value = load_json(path)
    except BenchmarkError as error:
        return result_for(
            case,
            "failed",
            0.0,
            "candidate_json_invalid",
            {"error": str(error)},
        )
    failures: list[str] = []
    for path_expr, expected in (candidate.get("expectEquals") or {}).items():
        try:
            actual = json_path(value, path_expr)
        except BenchmarkError:
            actual = "<missing>"
        if actual != expected:
            failures.append(f"{path_expr}={actual!r} expected={expected!r}")
    for path_expr, required in (candidate.get("expectContains") or {}).items():
        try:
            actual = json_path(value, path_expr)
        except BenchmarkError:
            actual = None
        if not isinstance(actual, list) or any(item not in actual for item in required):
            failures.append(f"{path_expr} missing required values")
    observations = {"failureCount": len(failures), "failures": failures}
    return result_for(
        case,
        "failed" if failures else "passed",
        0.0 if failures else 1.0,
        "candidate_expectations_failed"
        if failures
        else "candidate_expectations_passed",
        observations,
    )


def execute_case(
    case: dict[str, Any],
    project: Path,
    suite: dict[str, Any],
    include_sdk: bool,
    candidate_root: Path | None,
    prior: list[CaseResult],
) -> CaseResult:
    kind = case["kind"]
    try:
        if kind in {
            "command_exit",
            "command_json_stdout",
            "command_json_file",
        }:
            return command_case(case, project, suite, include_sdk)
        if kind == "path_policy":
            return path_policy_case(case, project)
        if kind == "capability_probe":
            return capability_probe_case(case, project)
        if kind == "model_workspace":
            return model_workspace_case(
                case,
                project,
                suite,
                candidate_root,
                prior,
            )
        if kind == "model_json":
            return model_json_case(case, candidate_root, prior)
        return result_for(case, "error", None, "unsupported_case_kind")
    except Exception as error:
        return result_for(
            case,
            "error",
            None,
            "benchmark_case_exception",
            {
                "type": type(error).__name__,
                "message": str(error)[:500],
            },
        )


def aggregate_categories(
    suite: dict[str, Any],
    results: list[CaseResult],
) -> list[dict[str, Any]]:
    output: list[dict[str, Any]] = []
    by_category: dict[str, list[CaseResult]] = {}
    weights = {
        str(case["id"]): float(case.get("weight", 1.0))
        for case in suite.get("cases") or []
        if isinstance(case, dict) and isinstance(case.get("id"), str)
    }
    for result in results:
        by_category.setdefault(result.category, []).append(result)
    for category in suite.get("categories") or []:
        category_id = str(category["id"])
        items = by_category.get(category_id, [])
        status_counts = {
            status: sum(1 for item in items if item.status == status)
            for status in ALLOWED_STATUSES
        }
        total_weight = sum(weights.get(item.id, 1.0) for item in items)
        measured_items = [
            item for item in items if item.status in {"passed", "failed", "error"}
        ]
        measured_weight = sum(weights.get(item.id, 1.0) for item in measured_items)
        scored_items = [item for item in items if item.score is not None]
        scored_weight = sum(weights.get(item.id, 1.0) for item in scored_items)
        weighted_score = sum(
            weights.get(item.id, 1.0) * float(item.score or 0.0)
            for item in scored_items
        )
        readiness_score = sum(
            weights.get(item.id, 1.0) * float(item.score or 0.0)
            for item in items
        )
        output.append(
            {
                "id": category_id,
                "name": category.get("name"),
                "caseCount": len(items),
                "measuredCaseCount": len(measured_items),
                "coverage": round(measured_weight / total_weight, 6)
                if total_weight
                else 0.0,
                "score": round(weighted_score / scored_weight, 6)
                if scored_weight
                else None,
                "readiness": round(readiness_score / total_weight, 6)
                if total_weight
                else 0.0,
                "statusCounts": status_counts,
            }
        )
    return output


def build_result(
    project: Path,
    suite_path: Path,
    suite: dict[str, Any],
    results: list[CaseResult],
    mode: str,
) -> dict[str, Any]:
    suite_sha = sha256_bytes(canonical_project_file_bytes(project, suite_path))
    fixture_sha = hash_tree(project, project / "evals/fixtures/p0_009")
    categories = aggregate_categories(suite, results)
    status_counts = {
        status: sum(1 for item in results if item.status == status)
        for status in ALLOWED_STATUSES
    }
    case_weights = {
        str(case["id"]): float(case.get("weight", 1.0))
        for case in suite.get("cases") or []
        if isinstance(case, dict) and isinstance(case.get("id"), str)
    }
    total_weight = sum(case_weights.get(item.id, 1.0) for item in results)
    measured_items = [
        item for item in results if item.status in {"passed", "failed", "error"}
    ]
    measured_weight = sum(case_weights.get(item.id, 1.0) for item in measured_items)
    scored_items = [item for item in results if item.score is not None]
    scored_weight = sum(case_weights.get(item.id, 1.0) for item in scored_items)
    weighted_score = sum(
        case_weights.get(item.id, 1.0) * float(item.score or 0.0)
        for item in scored_items
    )
    readiness_score = sum(
        case_weights.get(item.id, 1.0) * float(item.score or 0.0)
        for item in results
    )
    source_contracts = [
        item for item in results if item.proofKind == "source_inspection"
    ]
    behavioral = [
        item for item in results if item.proofKind == "executed_behavior"
    ]
    report: dict[str, Any] = {
        "schemaVersion": "1.0.0",
        "suiteId": suite["suiteId"],
        "suiteVersion": suite["suiteVersion"],
        "suiteSha256": suite_sha,
        "fixtureSha256": fixture_sha,
        "benchmarkInputsSha256": benchmark_inputs_sha256(
            project,
            suite_path,
            suite,
        ),
        "mode": mode,
        "generatedAt": suite["baselineTimestamp"],
        "networkPolicy": suite["networkPolicy"],
        "cases": [item.as_dict() for item in results],
        "categories": categories,
        "summary": {
            "recordingStatus": "complete"
            if all(item.status in ALLOWED_STATUSES for item in results)
            else "invalid",
            "caseCount": len(results),
            "measuredCaseCount": len(measured_items),
            "coverage": round(measured_weight / total_weight, 6)
            if total_weight
            else 0.0,
            "score": round(weighted_score / scored_weight, 6)
            if scored_weight
            else None,
            "readiness": round(readiness_score / total_weight, 6)
            if total_weight
            else 0.0,
            "statusCounts": status_counts,
            "behavioralCaseCount": len(behavioral),
            "sourceContractCaseCount": len(source_contracts),
            "behavioralPassedCount": sum(
                1 for item in behavioral if item.status == "passed"
            ),
            "sourceContractPassedCount": sum(
                1 for item in source_contracts if item.status == "passed"
            ),
            "benchmarkQualityPassed": all(
                item.status == "passed" for item in results
            ),
        },
        "claims": {
            "sourceInspectionIsBehavioralProof": False,
            "unsupportedCountsAsPassed": False,
            "unavailableCountsAsPassed": False,
            "notRunCountsAsPassed": False,
            "baselineRecordedMeansProductReady": False,
        },
    }
    report["resultFingerprint"] = expected_result_fingerprint(report)
    return report


def render_markdown(report: dict[str, Any]) -> str:
    summary = report["summary"]
    lines = [
        "# Kristin P0-009 Initial Benchmark Baseline",
        "",
        f"- Suite: `{report['suiteId']}` version `{report['suiteVersion']}`",
        f"- Mode: `{report['mode']}`",
        f"- Cases: **{summary['caseCount']}**",
        f"- Measured coverage: **{summary['coverage']:.1%}**",
        f"- Scored readiness: **{summary['readiness']:.1%}**",
        f"- Result fingerprint: `{report['resultFingerprint']}`",
        "",
        "> This is a reproducible starting measurement, not a production-readiness claim. Unsupported, unavailable, failed, and model-not-run cases remain visible and do not count as passing.",
        "",
        "## Category summary",
        "",
        "| Category | Cases | Measured | Coverage | Score | Readiness |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for category in report["categories"]:
        score = (
            "—"
            if category["score"] is None
            else f"{category['score']:.1%}"
        )
        lines.append(
            f"| {category['name']} | {category['caseCount']} | "
            f"{category['measuredCaseCount']} | {category['coverage']:.1%} | "
            f"{score} | {category['readiness']:.1%} |"
        )
    lines.extend(
        [
            "",
            "## Cases",
            "",
            "| Case | Category | Assurance | Status | Score | Reason |",
            "|---|---|---|---|---:|---|",
        ]
    )
    for case in report["cases"]:
        score = "—" if case["score"] is None else f"{case['score']:.1%}"
        lines.append(
            f"| `{case['id']}` | {case['category']} | "
            f"{case['assuranceLevel']} | **{case['status']}** | "
            f"{score} | {case['reason']} |"
        )
    lines.extend(
        [
            "",
            "## Claim boundaries",
            "",
            "- Source inspection is not behavioral proof.",
            "- Unsupported, unavailable, and not-run cases are not passes.",
            "- Completing P0-009 proves corpus/version/reproduction integrity only.",
            "",
        ]
    )
    return "\n".join(lines)


def run_suite(
    project: Path,
    suite_path: Path,
    *,
    mode: str,
    include_sdk: bool,
    candidate_root: Path | None,
) -> dict[str, Any]:
    suite = load_json(suite_path)
    errors = validate_suite_data(suite, project)
    if errors:
        raise BenchmarkError(
            "invalid benchmark suite:\n- " + "\n- ".join(errors)
        )
    results: list[CaseResult] = []
    for case in suite["cases"]:
        results.append(
            execute_case(
                case,
                project,
                suite,
                include_sdk,
                candidate_root,
                results,
            )
        )
    return build_result(project, suite_path, suite, results, mode)


def expected_result_fingerprint(report: dict[str, Any]) -> str:
    value = dict(report)
    value.pop("resultFingerprint", None)
    return sha256_text(canonical_json(value))


def verify_result_fingerprint(report: dict[str, Any]) -> bool:
    fingerprint = report.get("resultFingerprint")
    return (
        isinstance(fingerprint, str)
        and fingerprint == expected_result_fingerprint(report)
    )


def write_result(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def command_validate(args: argparse.Namespace) -> int:
    project = Path(args.project).resolve()
    suite_path = (project / args.suite).resolve()
    try:
        suite = load_json(suite_path)
        errors = validate_suite_data(suite, project)
    except BenchmarkError as error:
        print(str(error), file=sys.stderr)
        return 1
    payload = {
        "schemaVersion": "1.0.0",
        "suite": args.suite,
        "passed": not errors,
        "errorCount": len(errors),
        "errors": errors,
    }
    if args.json:
        print(json.dumps(payload, indent=2, sort_keys=True))
    elif errors:
        print("Benchmark suite: FAIL\n- " + "\n- ".join(errors))
    else:
        print("Benchmark suite: PASS")
    return 0 if not errors else 1


def command_run(args: argparse.Namespace) -> int:
    project = Path(args.project).resolve()
    suite_path = (project / args.suite).resolve()
    candidate_root = (
        Path(args.candidate_root).resolve() if args.candidate_root else None
    )
    try:
        report = run_suite(
            project,
            suite_path,
            mode=args.mode,
            include_sdk=args.include_sdk,
            candidate_root=candidate_root,
        )
    except BenchmarkError as error:
        print(str(error), file=sys.stderr)
        return 1
    output = project / args.output
    write_result(output, report)
    if args.markdown:
        markdown = project / args.markdown
        markdown.parent.mkdir(parents=True, exist_ok=True)
        markdown.write_text(render_markdown(report), encoding="utf-8")
    print(f"Benchmark baseline recorded: {output}")
    print(f"Fingerprint: {report['resultFingerprint']}")
    errors = [item for item in report["cases"] if item["status"] == "error"]
    return 1 if args.strict_infrastructure and errors else 0


def command_check(args: argparse.Namespace) -> int:
    project = Path(args.project).resolve()
    suite_path = (project / args.suite).resolve()
    baseline_path = (project / args.baseline).resolve()
    if not baseline_path.is_file():
        print(f"Baseline is missing: {baseline_path}", file=sys.stderr)
        return 1
    expected = load_json(baseline_path)
    if not verify_result_fingerprint(expected):
        print("P0-009 baseline fingerprint is invalid.", file=sys.stderr)
        return 1
    try:
        actual = run_suite(
            project,
            suite_path,
            mode="portable",
            include_sdk=False,
            candidate_root=None,
        )
    except BenchmarkError as error:
        print(str(error), file=sys.stderr)
        return 1
    if canonical_json(actual) != canonical_json(expected):
        print("P0-009 baseline drift detected.", file=sys.stderr)
        print(
            f"Expected fingerprint: {expected.get('resultFingerprint')}",
            file=sys.stderr,
        )
        print(
            f"Actual fingerprint:   {actual.get('resultFingerprint')}",
            file=sys.stderr,
        )
        return 1
    print(
        f"P0-009 baseline is reproducible: {actual['resultFingerprint']}"
    )
    return 0


def copy_fixture(source: Path, output: Path) -> None:
    if output.exists() and any(output.iterdir()):
        raise BenchmarkError(f"materialize output must be empty: {output}")
    output.mkdir(parents=True, exist_ok=True)
    if source.is_dir():
        for path in source.rglob("*"):
            relative = path.relative_to(source)
            target = output / relative
            if path.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            elif path.is_file():
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, target)
    elif source.is_file():
        shutil.copy2(source, output / source.name)
    else:
        raise BenchmarkError(f"fixture does not exist: {source}")


def command_materialize(args: argparse.Namespace) -> int:
    project = Path(args.project).resolve()
    suite_path = (project / args.suite).resolve()
    suite = load_json(suite_path)
    errors = validate_suite_data(suite, project)
    if errors:
        print(
            "invalid benchmark suite:\n- " + "\n- ".join(errors),
            file=sys.stderr,
        )
        return 1
    case = next(
        (item for item in suite["cases"] if item["id"] == args.case),
        None,
    )
    if case is None:
        print(f"Unknown case: {args.case}", file=sys.stderr)
        return 2
    fixture = case.get("fixture")
    if not isinstance(fixture, str):
        print(
            f"Case has no materializable fixture: {args.case}",
            file=sys.stderr,
        )
        return 2
    try:
        copy_fixture(project / fixture, Path(args.output).resolve())
    except BenchmarkError as error:
        print(str(error), file=sys.stderr)
        return 1
    print(f"Materialized {args.case} to {Path(args.output).resolve()}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    validate = sub.add_parser("validate")
    validate.add_argument("--project", default=".")
    validate.add_argument(
        "--suite",
        default="evals/datasets/p0_009_initial_benchmark.v1.json",
    )
    validate.add_argument("--json", action="store_true")
    validate.set_defaults(handler=command_validate)

    run = sub.add_parser("run")
    run.add_argument("--project", default=".")
    run.add_argument(
        "--suite",
        default="evals/datasets/p0_009_initial_benchmark.v1.json",
    )
    run.add_argument(
        "--output",
        default="evals/results/p0_009_baseline.json",
    )
    run.add_argument(
        "--markdown",
        default="evals/results/P0_009_BASELINE.md",
    )
    run.add_argument(
        "--mode",
        choices=("portable", "machine"),
        default="portable",
    )
    run.add_argument("--include-sdk", action="store_true")
    run.add_argument("--candidate-root")
    run.add_argument("--strict-infrastructure", action="store_true")
    run.set_defaults(handler=command_run)

    check = sub.add_parser("check")
    check.add_argument("--project", default=".")
    check.add_argument(
        "--suite",
        default="evals/datasets/p0_009_initial_benchmark.v1.json",
    )
    check.add_argument(
        "--baseline",
        default="evals/results/p0_009_baseline.json",
    )
    check.set_defaults(handler=command_check)

    materialize = sub.add_parser("materialize")
    materialize.add_argument("--project", default=".")
    materialize.add_argument(
        "--suite",
        default="evals/datasets/p0_009_initial_benchmark.v1.json",
    )
    materialize.add_argument("--case", required=True)
    materialize.add_argument("--output", required=True)
    materialize.set_defaults(handler=command_materialize)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    return int(args.handler(args))


if __name__ == "__main__":
    raise SystemExit(main())
