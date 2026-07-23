#!/usr/bin/env python3
"""Deterministic Prompt Studio 2 plan compiler and static evaluation runner.

This module is intentionally model-free. Model output becomes eligible for execution
only after the compiler validates schemas, capability alignment, graph integrity,
artifact validators, local-only policy, and sandbox prerequisites.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import sys
from collections import defaultdict, deque
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any, Iterable, Mapping, Sequence


ROOT = Path(__file__).resolve().parents[1]
COMPILER_VERSION = "1.0.0"
REPORT_SCHEMA_VERSION = "1.0.0"
SCHEMA_FILES = {
    "specification": "product_specification.v2.json",
    "plan": "task_plan.v2.json",
    "evaluation": "prompt_evaluation_dataset.v1.json",
    "capabilities": "plan_capability_catalog.v1.json",
    "report": "plan_compilation_report.v1.json",
    "tools": "tool_registry.v2.json",
}
ERROR = "error"
WARNING = "warning"
INFO = "info"


class CompilationInputError(RuntimeError):
    pass


def _project_relative_path(value: object) -> bool:
    if not isinstance(value, str) or not value or "\x00" in value:
        return False
    normalized = value.replace("\\", "/")
    if normalized.startswith("/") or re.match(r"^[A-Za-z]:/", normalized):
        return False
    path = PurePosixPath(normalized)
    return bool(path.parts) and ".." not in path.parts

def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_json(value: object) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise CompilationInputError(f"missing JSON file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise CompilationInputError(f"invalid JSON in {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise CompilationInputError(f"expected a JSON object in {path}")
    return value


def write_json(path: Path | None, value: Mapping[str, Any]) -> None:
    text = json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    if path is None:
        sys.stdout.write(text)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def schema_path(name: str, root: Path = ROOT) -> Path:
    return root / "schemas" / SCHEMA_FILES[name]


def load_contracts(root: Path = ROOT) -> dict[str, dict[str, Any]]:
    return {name: read_json(schema_path(name, root)) for name in SCHEMA_FILES}


def _json_path(parts: Sequence[object]) -> str:
    if not parts:
        return "$"
    result = "$"
    for part in parts:
        if isinstance(part, int):
            result += f"[{part}]"
        else:
            result += f".{part}"
    return result


def _json_type(value: object) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, Mapping):
        return "object"
    return type(value).__name__


def _matches_type(value: object, expected: object) -> bool:
    choices = expected if isinstance(expected, list) else [expected]
    actual = _json_type(value)
    return any(
        str(choice) == actual
        or (str(choice) == "number" and actual == "integer")
        for choice in choices
    )


def _equivalent(left: object, right: object) -> bool:
    try:
        return canonical_json(left) == canonical_json(right)
    except (TypeError, ValueError):
        return left == right


def _format_valid(value: str, format_name: str) -> bool:
    if format_name == "project-relative-path":
        return _project_relative_path(value)
    if format_name == "date-time":
        try:
            from datetime import datetime
            datetime.fromisoformat(value.replace("Z", "+00:00"))
            return True
        except ValueError:
            return False
    if format_name == "https-uri":
        from urllib.parse import urlsplit
        parsed = urlsplit(value)
        return (
            parsed.scheme.lower() == "https"
            and bool(parsed.hostname)
            and not parsed.fragment
            and parsed.username is None
            and parsed.password is None
        )
    return True


def _schema_issue(
    issues: list[dict[str, Any]],
    *,
    document_name: str,
    path: Sequence[object],
    keyword: str,
    message: str,
) -> None:
    issues.append(
        {
            "severity": ERROR,
            "code": f"{document_name}_schema_invalid",
            "message": message,
            "path": _json_path(path),
            "keyword": keyword,
        }
    )


def _validate_value(
    value: object,
    schema: Mapping[str, Any],
    *,
    document_name: str,
    path: tuple[object, ...],
    issues: list[dict[str, Any]],
) -> None:
    if "const" in schema and not _equivalent(value, schema["const"]):
        _schema_issue(
            issues,
            document_name=document_name,
            path=path,
            keyword="const",
            message="value does not match the required constant",
        )
        return
    enum_values = schema.get("enum")
    if isinstance(enum_values, list) and not any(
        _equivalent(value, candidate) for candidate in enum_values
    ):
        _schema_issue(
            issues,
            document_name=document_name,
            path=path,
            keyword="enum",
            message="value is not one of the allowed values",
        )
        return
    expected_type = schema.get("type")
    if expected_type is not None and not _matches_type(value, expected_type):
        _schema_issue(
            issues,
            document_name=document_name,
            path=path,
            keyword="type",
            message=f"expected JSON type {expected_type}, got {_json_type(value)}",
        )
        return

    if isinstance(value, Mapping):
        properties = schema.get("properties", {})
        properties = properties if isinstance(properties, Mapping) else {}
        required = schema.get("required", [])
        if isinstance(required, list):
            for name in required:
                if isinstance(name, str) and name not in value:
                    _schema_issue(
                        issues,
                        document_name=document_name,
                        path=(*path, name),
                        keyword="required",
                        message=f'required property "{name}" is missing',
                    )
        additional = schema.get("additionalProperties", True)
        for key, child_value in value.items():
            key_text = str(key)
            child_schema = properties.get(key_text)
            if isinstance(child_schema, Mapping):
                _validate_value(
                    child_value,
                    child_schema,
                    document_name=document_name,
                    path=(*path, key_text),
                    issues=issues,
                )
            elif additional is False:
                _schema_issue(
                    issues,
                    document_name=document_name,
                    path=(*path, key_text),
                    keyword="additionalProperties",
                    message=f'property "{key_text}" is not allowed',
                )
            elif isinstance(additional, Mapping):
                _validate_value(
                    child_value,
                    additional,
                    document_name=document_name,
                    path=(*path, key_text),
                    issues=issues,
                )

    if isinstance(value, list):
        minimum = schema.get("minItems")
        maximum = schema.get("maxItems")
        if isinstance(minimum, int) and len(value) < minimum:
            _schema_issue(
                issues,
                document_name=document_name,
                path=path,
                keyword="minItems",
                message=f"array has fewer than {minimum} items",
            )
        if isinstance(maximum, int) and len(value) > maximum:
            _schema_issue(
                issues,
                document_name=document_name,
                path=path,
                keyword="maxItems",
                message=f"array has more than {maximum} items",
            )
        if schema.get("uniqueItems") is True:
            seen: set[str] = set()
            for index, item in enumerate(value):
                fingerprint = canonical_json(item)
                if fingerprint in seen:
                    _schema_issue(
                        issues,
                        document_name=document_name,
                        path=(*path, index),
                        keyword="uniqueItems",
                        message="array items must be unique",
                    )
                seen.add(fingerprint)
        items_schema = schema.get("items")
        if isinstance(items_schema, Mapping):
            for index, item in enumerate(value):
                _validate_value(
                    item,
                    items_schema,
                    document_name=document_name,
                    path=(*path, index),
                    issues=issues,
                )

    if isinstance(value, str):
        minimum = schema.get("minLength")
        maximum = schema.get("maxLength")
        if isinstance(minimum, int) and len(value) < minimum:
            _schema_issue(
                issues,
                document_name=document_name,
                path=path,
                keyword="minLength",
                message=f"string is shorter than {minimum} characters",
            )
        if isinstance(maximum, int) and len(value) > maximum:
            _schema_issue(
                issues,
                document_name=document_name,
                path=path,
                keyword="maxLength",
                message=f"string is longer than {maximum} characters",
            )
        pattern = schema.get("pattern")
        if isinstance(pattern, str) and re.search(pattern, value) is None:
            _schema_issue(
                issues,
                document_name=document_name,
                path=path,
                keyword="pattern",
                message="string does not match the required pattern",
            )
        format_name = schema.get("format")
        if isinstance(format_name, str) and not _format_valid(value, format_name):
            _schema_issue(
                issues,
                document_name=document_name,
                path=path,
                keyword="format",
                message=f"string is not a valid {format_name} value",
            )

    if isinstance(value, (int, float)) and not isinstance(value, bool):
        minimum = schema.get("minimum")
        maximum = schema.get("maximum")
        exclusive_minimum = schema.get("exclusiveMinimum")
        exclusive_maximum = schema.get("exclusiveMaximum")
        if isinstance(minimum, (int, float)) and value < minimum:
            _schema_issue(
                issues,
                document_name=document_name,
                path=path,
                keyword="minimum",
                message=f"number is below minimum {minimum}",
            )
        if isinstance(maximum, (int, float)) and value > maximum:
            _schema_issue(
                issues,
                document_name=document_name,
                path=path,
                keyword="maximum",
                message=f"number is above maximum {maximum}",
            )
        if isinstance(exclusive_minimum, (int, float)) and value <= exclusive_minimum:
            _schema_issue(
                issues,
                document_name=document_name,
                path=path,
                keyword="exclusiveMinimum",
                message=f"number must be greater than {exclusive_minimum}",
            )
        if isinstance(exclusive_maximum, (int, float)) and value >= exclusive_maximum:
            _schema_issue(
                issues,
                document_name=document_name,
                path=path,
                keyword="exclusiveMaximum",
                message=f"number must be less than {exclusive_maximum}",
            )

    for keyword in ("allOf", "anyOf", "oneOf"):
        branches = schema.get(keyword)
        if not isinstance(branches, list) or not branches:
            continue
        branch_results: list[list[dict[str, Any]]] = []
        for branch in branches:
            branch_issues: list[dict[str, Any]] = []
            if isinstance(branch, Mapping):
                _validate_value(
                    value,
                    branch,
                    document_name=document_name,
                    path=path,
                    issues=branch_issues,
                )
            else:
                branch_issues.append({"invalid": True})
            branch_results.append(branch_issues)
        passing = sum(not result for result in branch_results)
        valid = (
            passing == len(branch_results)
            if keyword == "allOf"
            else passing == 1
            if keyword == "oneOf"
            else passing >= 1
        )
        if not valid:
            _schema_issue(
                issues,
                document_name=document_name,
                path=path,
                keyword=keyword,
                message=f"value does not satisfy {keyword}",
            )


def validate_schema_contract(
    schema: Mapping[str, Any],
    *,
    document_name: str,
) -> list[str]:
    """Perform deterministic structural checks on the supported schema subset."""
    failures: list[str] = []
    allowed_types = {"null", "boolean", "integer", "number", "string", "array", "object"}

    def walk(value: object, path: str) -> None:
        if not isinstance(value, Mapping):
            failures.append(f"{path}: schema node must be an object")
            return
        expected = value.get("type")
        choices = expected if isinstance(expected, list) else [expected] if expected is not None else []
        for choice in choices:
            if choice not in allowed_types:
                failures.append(f"{path}.type: unsupported type {choice!r}")
        properties = value.get("properties")
        if properties is not None and not isinstance(properties, Mapping):
            failures.append(f"{path}.properties: must be an object")
        if isinstance(properties, Mapping):
            for name, child in properties.items():
                walk(child, f"{path}.properties.{name}")
        required = value.get("required")
        if required is not None and (
            not isinstance(required, list)
            or any(not isinstance(item, str) for item in required)
        ):
            failures.append(f"{path}.required: must be an array of strings")
        items = value.get("items")
        if items is not None:
            walk(items, f"{path}.items")
        additional = value.get("additionalProperties")
        if additional is not None and not isinstance(additional, (bool, Mapping)):
            failures.append(f"{path}.additionalProperties: must be boolean or schema")
        if isinstance(additional, Mapping):
            walk(additional, f"{path}.additionalProperties")
        for keyword in ("allOf", "anyOf", "oneOf"):
            branches = value.get(keyword)
            if branches is None:
                continue
            if not isinstance(branches, list) or not branches:
                failures.append(f"{path}.{keyword}: must be a non-empty array")
                continue
            for index, branch in enumerate(branches):
                walk(branch, f"{path}.{keyword}[{index}]")

    walk(schema, f"schema:{document_name}")
    return failures


def validate_document(
    document: Mapping[str, Any],
    schema: Mapping[str, Any],
    *,
    document_name: str,
) -> list[dict[str, Any]]:
    issues: list[dict[str, Any]] = []
    _validate_value(
        document,
        schema,
        document_name=document_name,
        path=(),
        issues=issues,
    )
    issues.sort(key=lambda item: (str(item.get("path")), str(item.get("keyword")), str(item.get("message"))))
    return issues

def issue(
    severity: str,
    code: str,
    message: str,
    *,
    task_id: str | None = None,
    path: str | None = None,
    details: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    value: dict[str, Any] = {
        "severity": severity,
        "code": code,
        "message": message,
    }
    if task_id:
        value["taskId"] = task_id
    if path:
        value["path"] = path
    if details:
        value["details"] = dict(details)
    return value


def default_policy() -> dict[str, Any]:
    return {
        "localOnly": True,
        "sandboxAvailable": False,
        "legacyUnsandboxedExecutionApproved": False,
        "networkAllowed": False,
        "humanWorkflowAvailable": False,
        "selfModificationApproved": False,
        "deploymentTarget": None,
        "maxTasks": 100,
        "maxTotalModelTurns": 1200,
        "maxTotalToolCalls": 5000,
        "maxTotalOutputBytes": 500_000_000,
    }


def normalize_policy(raw: Mapping[str, Any] | None) -> dict[str, Any]:
    policy = default_policy()
    if raw:
        for key in policy:
            if key in raw:
                policy[key] = raw[key]
    policy["maxTasks"] = max(1, min(100, int(policy["maxTasks"])))
    policy["maxTotalModelTurns"] = max(0, int(policy["maxTotalModelTurns"]))
    policy["maxTotalToolCalls"] = max(0, int(policy["maxTotalToolCalls"]))
    policy["maxTotalOutputBytes"] = max(0, int(policy["maxTotalOutputBytes"]))
    for key in (
        "localOnly",
        "sandboxAvailable",
        "legacyUnsandboxedExecutionApproved",
        "networkAllowed",
        "humanWorkflowAvailable",
        "selfModificationApproved",
    ):
        policy[key] = bool(policy[key])
    if policy["deploymentTarget"] is not None:
        policy["deploymentTarget"] = str(policy["deploymentTarget"]).strip() or None
    return policy


@dataclass(frozen=True)
class Capability:
    name: str
    tools: frozenset[str]
    requires_sandbox: bool
    network: bool
    mutation: bool


def capability_catalog(raw: Mapping[str, Any]) -> tuple[dict[str, Capability], dict[str, list[str]], dict[str, str]]:
    capabilities: dict[str, Capability] = {}
    for item in raw.get("capabilities", []):
        if not isinstance(item, dict):
            continue
        name = str(item.get("name", ""))
        if not name:
            continue
        capabilities[name] = Capability(
            name=name,
            tools=frozenset(str(tool) for tool in item.get("tools", []) if str(tool)),
            requires_sandbox=bool(item.get("requiresSandbox")),
            network=bool(item.get("network")),
            mutation=bool(item.get("mutation")),
        )
    defaults = {
        str(key): [str(value) for value in values]
        for key, values in raw.get("taskTypeDefaults", {}).items()
        if isinstance(values, list)
    }
    validator_caps = {
        str(key): str(value)
        for key, value in raw.get("validatorCapabilities", {}).items()
    }
    return capabilities, defaults, validator_caps


def tool_names(tool_registry: Mapping[str, Any]) -> set[str]:
    return {
        str(item.get("name"))
        for item in tool_registry.get("tools", [])
        if isinstance(item, dict) and item.get("name")
    }


def tool_risks(tool_registry: Mapping[str, Any]) -> dict[str, str]:
    return {
        str(item.get("name")): str(item.get("risk", "read"))
        for item in tool_registry.get("tools", [])
        if isinstance(item, dict) and item.get("name")
    }


def validator_ids(artifacts: Iterable[Mapping[str, Any]], verification: Iterable[Mapping[str, Any]] = ()) -> set[str]:
    values: set[str] = set()
    for artifact in artifacts:
        for validator in artifact.get("validators", []):
            if isinstance(validator, dict) and validator.get("id"):
                values.add(str(validator["id"]))
    for validator in verification:
        if isinstance(validator, dict) and validator.get("id"):
            values.add(str(validator["id"]))
    return values


def deterministic_artifact(artifact: Mapping[str, Any]) -> bool:
    return any(
        isinstance(item, dict)
        and item.get("deterministic") is True
        and item.get("kind") != "manual_review"
        for item in artifact.get("validators", [])
    )


def task_text(task: Mapping[str, Any]) -> str:
    parts: list[str] = [
        str(task.get("title", "")),
        str(task.get("objective", "")),
        str(task.get("instructions", "")),
    ]
    for artifact in task.get("outputArtifacts", []):
        if isinstance(artifact, dict):
            parts.extend([str(artifact.get("description", "")), str(artifact.get("path", ""))])
    for criterion in task.get("acceptanceCriteria", []):
        if isinstance(criterion, dict):
            parts.append(str(criterion.get("statement", "")))
    return " ".join(parts).lower()


EXTERNAL_CLAIM = re.compile(
    r"\b(?:public\s+url|host(?:ed|ing)?\s+online|deploy\s+to\s+(?:cloud|production|vercel|netlify|aws|azure|gcp)|"
    r"publish\s+(?:online|publicly)|live\s+web\s+(?:research|verification)|browserstack|figma|adobe\s+xd|sketch|"
    r"external\s+(?:api|service)|remote\s+service|internet\s+access)\b",
    re.IGNORECASE,
)
HUMAN_CLAIM = re.compile(
    r"\b(?:recruit|interview|survey|focus\s+group|user\s+study|participants?|human\s+tester|stakeholder\s+approval)\b",
    re.IGNORECASE,
)


def inferred_capabilities(
    task: Mapping[str, Any],
    *,
    defaults: Mapping[str, Sequence[str]],
    validator_caps: Mapping[str, str],
) -> set[str]:
    inferred = set(defaults.get(str(task.get("taskType", "analysis")), ()))
    if task.get("outputArtifacts") and not task.get("manual"):
        inferred.add("project.mutate")
    for artifact in task.get("outputArtifacts", []):
        if not isinstance(artifact, dict):
            continue
        for validator in artifact.get("validators", []):
            if isinstance(validator, dict):
                capability = validator_caps.get(str(validator.get("kind", "")))
                if capability:
                    inferred.add(capability)
    for validator in task.get("verification", []):
        if isinstance(validator, dict):
            capability = validator_caps.get(str(validator.get("kind", "")))
            if capability:
                inferred.add(capability)
    if task.get("dataBoundary") == "network":
        inferred.add("research.network")
    if task.get("dataBoundary") == "external":
        inferred.add("external.mcp")
    if task.get("manual"):
        inferred.add("human.approval")
    return inferred


def _cycles(nodes: Sequence[str], edges: Mapping[str, set[str]]) -> list[list[str]]:
    state: dict[str, int] = {node: 0 for node in nodes}
    stack: list[str] = []
    found: list[list[str]] = []

    def visit(node: str) -> None:
        state[node] = 1
        stack.append(node)
        for dependency in sorted(edges.get(node, set())):
            if dependency not in state:
                continue
            if state[dependency] == 0:
                visit(dependency)
            elif state[dependency] == 1:
                index = stack.index(dependency)
                found.append(stack[index:] + [dependency])
        stack.pop()
        state[node] = 2

    for node in nodes:
        if state[node] == 0:
            visit(node)
    unique: dict[tuple[str, ...], list[str]] = {}
    for cycle in found:
        if len(cycle) < 2:
            continue
        core = cycle[:-1]
        rotations = [tuple(core[i:] + core[:i]) for i in range(len(core))]
        key = min(rotations)
        unique[key] = list(key) + [key[0]]
    return list(unique.values())


def topological_batches(tasks: Sequence[Mapping[str, Any]]) -> tuple[list[str], list[list[str]]]:
    enabled = [task for task in tasks if task.get("enabled") is not False]
    ids = {str(task["id"]) for task in enabled}
    dependencies = {
        str(task["id"]): {str(dep) for dep in task.get("dependencies", []) if str(dep) in ids}
        for task in enabled
    }
    reverse: dict[str, set[str]] = defaultdict(set)
    indegree = {task_id: len(deps) for task_id, deps in dependencies.items()}
    for task_id, deps in dependencies.items():
        for dep in deps:
            reverse[dep].add(task_id)
    order_key = {str(task["id"]): (int(task.get("order", 0)), str(task["id"])) for task in enabled}
    ready = sorted((task_id for task_id, count in indegree.items() if count == 0), key=lambda item: order_key[item])
    order: list[str] = []
    batches: list[list[str]] = []
    while ready:
        batch = list(ready)
        batches.append(batch)
        order.extend(batch)
        next_ready: list[str] = []
        for task_id in batch:
            for child in sorted(reverse.get(task_id, set()), key=lambda item: order_key[item]):
                indegree[child] -= 1
                if indegree[child] == 0:
                    next_ready.append(child)
        ready = sorted(next_ready, key=lambda item: order_key[item])
    if len(order) != len(enabled):
        remaining = sorted(ids - set(order), key=lambda item: order_key[item])
        order.extend(remaining)
    return order, batches


def longest_effort_path(tasks: Sequence[Mapping[str, Any]], order: Sequence[str]) -> int:
    by_id = {str(task["id"]): task for task in tasks if task.get("enabled") is not False}
    distance: dict[str, int] = {}
    for task_id in order:
        task = by_id.get(task_id)
        if task is None:
            continue
        effort = int(task.get("effortPoints", 1))
        parents = [distance.get(str(dep), 0) for dep in task.get("dependencies", [])]
        distance[task_id] = effort + (max(parents) if parents else 0)
    return max(distance.values(), default=0)


def quality_grade(score: float) -> str:
    if score >= 90:
        return "A"
    if score >= 80:
        return "B"
    if score >= 70:
        return "C"
    if score >= 60:
        return "D"
    return "F"


def compile_plan(
    specification: Mapping[str, Any],
    plan: Mapping[str, Any],
    *,
    policy: Mapping[str, Any] | None = None,
    contracts: Mapping[str, Mapping[str, Any]] | None = None,
) -> dict[str, Any]:
    contracts = dict(contracts or load_contracts())
    policy_value = normalize_policy(policy)
    issues: list[dict[str, Any]] = []
    spec_schema_issues = validate_document(
        specification, contracts["specification"], document_name="specification"
    )
    plan_schema_issues = validate_document(plan, contracts["plan"], document_name="plan")
    issues.extend(spec_schema_issues)
    issues.extend(plan_schema_issues)

    # Schema errors can make fields unavailable. Continue with bounded best-effort
    # semantic diagnostics, but never mark such a plan executable.
    capabilities, defaults, validator_caps = capability_catalog(contracts["capabilities"])
    known_tools = tool_names(contracts["tools"])
    risks = tool_risks(contracts["tools"])
    tasks_raw = plan.get("tasks", [])
    tasks = [task for task in tasks_raw if isinstance(task, dict)]
    by_id: dict[str, Mapping[str, Any]] = {}
    for task in tasks:
        task_id = str(task.get("id", ""))
        if not task_id:
            continue
        if task_id in by_id:
            issues.append(
                issue(
                    ERROR,
                    "task_id_duplicate",
                    f"Duplicate task ID {task_id} prevents deterministic graph compilation.",
                    task_id=task_id,
                    path="$.tasks",
                )
            )
            continue
        by_id[task_id] = task
    ids = list(by_id)

    if plan.get("specificationId") != specification.get("id"):
        issues.append(
            issue(
                ERROR,
                "specification_link_mismatch",
                "The plan does not reference the supplied product specification.",
                path="$.specificationId",
            )
        )
    spec_local = bool(specification.get("dataPolicy", {}).get("localOnly", True))
    plan_local = bool(plan.get("localOnly", True))
    if spec_local != plan_local:
        issues.append(
            issue(
                ERROR,
                "local_only_contract_mismatch",
                "The plan localOnly flag must match the product specification data policy.",
                path="$.localOnly",
            )
        )
    effective_local_only = bool(policy_value["localOnly"] or spec_local or plan_local)
    if len(tasks) > policy_value["maxTasks"]:
        issues.append(
            issue(
                ERROR,
                "task_limit_exceeded",
                f"The plan contains {len(tasks)} tasks but policy allows {policy_value['maxTasks']}.",
                path="$.tasks",
            )
        )

    spec_artifacts = [item for item in specification.get("artifacts", []) if isinstance(item, dict)]
    spec_validator_ids = validator_ids(spec_artifacts)
    spec_requirement_ids: set[str] = set()
    seen_requirement_ids: set[str] = set()
    for field in ("functionalRequirements", "nonFunctionalRequirements"):
        for requirement in specification.get(field, []):
            if not isinstance(requirement, dict) or not requirement.get("id"):
                continue
            requirement_id = str(requirement["id"])
            if requirement_id in seen_requirement_ids:
                issues.append(
                    issue(
                        ERROR,
                        "requirement_id_duplicate",
                        f"Duplicate specification requirement ID {requirement_id}.",
                        path=f"$.{field}",
                    )
                )
            seen_requirement_ids.add(requirement_id)
            spec_requirement_ids.add(requirement_id)
    seen_artifacts: set[str] = set()
    seen_validators: set[str] = set()
    for artifact in spec_artifacts:
        artifact_id = str(artifact.get("id", ""))
        if artifact_id in seen_artifacts:
            issues.append(issue(ERROR, "artifact_id_duplicate", f"Duplicate specification artifact ID {artifact_id}."))
        seen_artifacts.add(artifact_id)
        for validator in artifact.get("validators", []):
            if not isinstance(validator, dict):
                continue
            validator_id = str(validator.get("id", ""))
            if validator_id in seen_validators:
                issues.append(issue(ERROR, "validator_id_duplicate", f"Duplicate validator ID {validator_id}."))
            seen_validators.add(validator_id)
    seen_criterion_ids: set[str] = set()
    for criterion in specification.get("acceptanceCriteria", []):
        if not isinstance(criterion, dict):
            continue
        criterion_id = str(criterion.get("id", ""))
        if criterion_id in seen_criterion_ids:
            issues.append(
                issue(
                    ERROR,
                    "criterion_id_duplicate",
                    f"Duplicate specification acceptance criterion ID {criterion_id}.",
                    path="$.acceptanceCriteria",
                )
            )
        seen_criterion_ids.add(criterion_id)
        for validator_id in criterion.get("evidenceValidatorIds", []):
            if str(validator_id) not in spec_validator_ids:
                issues.append(
                    issue(
                        ERROR,
                        "criterion_validator_missing",
                        f"Specification criterion {criterion_id} references missing validator {validator_id}.",
                    )
                )
        for requirement_id in criterion.get("requirementIds", []):
            if str(requirement_id) not in spec_requirement_ids:
                issues.append(
                    issue(
                        ERROR,
                        "criterion_requirement_missing",
                        f"Specification criterion {criterion_id} references missing requirement {requirement_id}.",
                    )
                )

    dependency_edges: dict[str, set[str]] = {}
    parent_edges: dict[str, set[str]] = {}
    for task in tasks:
        task_id = str(task.get("id", ""))
        dependencies = {str(dep) for dep in task.get("dependencies", [])}
        dependency_edges[task_id] = dependencies
        parent_id = task.get("parentId")
        parent_edges[task_id] = {str(parent_id)} if parent_id else set()
        for dependency in dependencies:
            if dependency not in by_id:
                issues.append(
                    issue(
                        ERROR,
                        "dependency_missing",
                        f"Task {task_id} references missing dependency {dependency}.",
                        task_id=task_id,
                    )
                )
            elif by_id[dependency].get("enabled") is False and task.get("enabled") is not False:
                issues.append(
                    issue(
                        ERROR,
                        "dependency_disabled",
                        f"Enabled task {task_id} depends on disabled task {dependency}.",
                        task_id=task_id,
                    )
                )
        if parent_id:
            if str(parent_id) not in by_id:
                issues.append(
                    issue(
                        ERROR,
                        "parent_missing",
                        f"Task {task_id} references missing parent {parent_id}.",
                        task_id=task_id,
                    )
                )
            elif str(parent_id) == task_id:
                issues.append(issue(ERROR, "parent_self_reference", f"Task {task_id} cannot parent itself.", task_id=task_id))
    for cycle in _cycles(ids, dependency_edges):
        issues.append(issue(ERROR, "dependency_cycle", f"Dependency cycle detected: {' -> '.join(cycle)}."))
    for cycle in _cycles(ids, parent_edges):
        issues.append(issue(ERROR, "parent_cycle", f"Parent hierarchy cycle detected: {' -> '.join(cycle)}."))

    compiled_tasks: list[dict[str, Any]] = []
    capability_required_count = 0
    capability_covered_count = 0
    criterion_count = 0
    criterion_verified_count = 0
    artifact_count = 0
    artifact_validated_count = 0
    produced_paths: dict[str, str] = {}
    task_block_reasons: dict[str, list[str]] = defaultdict(list)
    approvals: set[str] = set()

    for index, task in enumerate(tasks):
        task_id = str(task.get("id", f"task_{index + 1:03d}"))
        enabled = task.get("enabled") is not False
        manual = bool(task.get("manual"))
        explicit_caps = {str(item) for item in task.get("requiredCapabilities", [])}
        inferred = inferred_capabilities(task, defaults=defaults, validator_caps=validator_caps)
        required = explicit_caps | inferred
        allowed = {str(item) for item in task.get("allowedTools", [])}
        unknown_tools = sorted(allowed - known_tools)
        for tool in unknown_tools:
            issues.append(issue(ERROR, "tool_unknown", f"Task {task_id} allows unknown tool {tool}.", task_id=task_id))
            task_block_reasons[task_id].append("tool_unknown")
        for capability_name in sorted(required):
            capability_required_count += 1
            capability = capabilities.get(capability_name)
            if capability is None:
                issues.append(issue(ERROR, "capability_unknown", f"Task {task_id} requires unknown capability {capability_name}.", task_id=task_id))
                task_block_reasons[task_id].append("capability_unknown")
                continue
            if capability_name == "human.approval":
                covered = manual or task.get("taskType") in {"approval", "manual"}
            else:
                covered = bool(capability.tools & allowed)
            if covered:
                capability_covered_count += 1
            else:
                issues.append(
                    issue(
                        ERROR,
                        "capability_tool_gap",
                        f"Task {task_id} requires {capability_name} but allowedTools contains no tool that provides it.",
                        task_id=task_id,
                        details={"capability": capability_name, "providerTools": sorted(capability.tools)},
                    )
                )
                task_block_reasons[task_id].append("capability_tool_gap")
            if capability.network and enabled and not manual:
                if effective_local_only or not policy_value["networkAllowed"]:
                    issues.append(
                        issue(
                            ERROR,
                            "network_capability_blocked",
                            f"Task {task_id} requires network capability {capability_name} under a network-blocking policy.",
                            task_id=task_id,
                        )
                    )
                    task_block_reasons[task_id].append("network_capability_blocked")
            if capability.requires_sandbox and enabled and not manual and not policy_value["sandboxAvailable"]:
                if policy_value["legacyUnsandboxedExecutionApproved"]:
                    issues.append(
                        issue(
                            WARNING,
                            "legacy_unsandboxed_execution",
                            f"Task {task_id} requires {capability_name}; execution is permitted only by the explicit legacy unsandboxed override.",
                            task_id=task_id,
                        )
                    )
                    approvals.add("legacy_unsandboxed_execution")
                else:
                    issues.append(
                        issue(
                            ERROR,
                            "sandbox_required",
                            f"Task {task_id} requires {capability_name}, but the v1.4 sandbox boundary is unavailable.",
                            task_id=task_id,
                        )
                    )
                    task_block_reasons[task_id].append("sandbox_required")

        missing_declared = sorted(inferred - explicit_caps)
        for capability_name in missing_declared:
            issues.append(
                issue(
                    ERROR,
                    "required_capability_undeclared",
                    f"Task {task_id} needs inferred capability {capability_name}, but it is absent from requiredCapabilities.",
                    task_id=task_id,
                )
            )
            task_block_reasons[task_id].append("required_capability_undeclared")

        text = task_text(task)
        if effective_local_only and EXTERNAL_CLAIM.search(text):
            severity = WARNING if manual else ERROR
            issues.append(
                issue(
                    severity,
                    "local_only_external_claim",
                    f"Task {task_id} contains an external-service or public-hosting claim in local-only mode.",
                    task_id=task_id,
                )
            )
            if severity == ERROR:
                task_block_reasons[task_id].append("local_only_external_claim")
        if HUMAN_CLAIM.search(text) and not policy_value["humanWorkflowAvailable"]:
            if not manual:
                issues.append(
                    issue(
                        ERROR,
                        "human_workflow_missing",
                        f"Task {task_id} claims human participation but is not manual and no human workflow is configured.",
                        task_id=task_id,
                    )
                )
                task_block_reasons[task_id].append("human_workflow_missing")
            else:
                issues.append(
                    issue(
                        WARNING,
                        "human_workflow_manual",
                        f"Task {task_id} remains manual until a human workflow is configured.",
                        task_id=task_id,
                    )
                )
        if task.get("targetScope") == "host_application" and not policy_value["selfModificationApproved"]:
            issues.append(
                issue(
                    ERROR,
                    "self_modification_not_approved",
                    f"Task {task_id} targets Kristin itself without an explicit development-project approval.",
                    task_id=task_id,
                )
            )
            task_block_reasons[task_id].append("self_modification_not_approved")

        if task.get("taskType") == "deployment" and not manual:
            deployment = specification.get("deploymentBoundary", {})
            mode = deployment.get("mode") if isinstance(deployment, dict) else "none"
            target = policy_value["deploymentTarget"] or (deployment.get("target") if isinstance(deployment, dict) else None)
            if mode in {"none", "external_manual"}:
                issues.append(
                    issue(
                        ERROR,
                        "deployment_mode_not_executable",
                        f"Task {task_id} is automated, but the specification deployment mode is {mode}.",
                        task_id=task_id,
                    )
                )
                task_block_reasons[task_id].append("deployment_mode_not_executable")
            if mode == "external_automated" and not target:
                issues.append(
                    issue(
                        ERROR,
                        "deployment_target_missing",
                        f"Task {task_id} requests automated deployment without a configured target.",
                        task_id=task_id,
                    )
                )
                task_block_reasons[task_id].append("deployment_target_missing")
            approvals.add("deployment")

        local_validator_ids = validator_ids(
            [item for item in task.get("outputArtifacts", []) if isinstance(item, dict)],
            [item for item in task.get("verification", []) if isinstance(item, dict)],
        )
        for criterion in task.get("acceptanceCriteria", []):
            if not isinstance(criterion, dict):
                continue
            criterion_count += 1
            refs = {str(item) for item in criterion.get("evidenceValidatorIds", [])}
            if refs and refs <= local_validator_ids:
                criterion_verified_count += 1
            else:
                issues.append(
                    issue(
                        ERROR,
                        "acceptance_evidence_missing",
                        f"Task {task_id} has an acceptance criterion without resolvable validator evidence.",
                        task_id=task_id,
                        details={"criterionId": criterion.get("id"), "missing": sorted(refs - local_validator_ids)},
                    )
                )
                task_block_reasons[task_id].append("acceptance_evidence_missing")

        for artifact in task.get("outputArtifacts", []):
            if not isinstance(artifact, dict):
                continue
            artifact_count += 1
            if deterministic_artifact(artifact) or manual:
                artifact_validated_count += 1
            elif artifact.get("required"):
                issues.append(
                    issue(
                        ERROR,
                        "artifact_validator_missing",
                        f"Required artifact {artifact.get('id')} from task {task_id} lacks a deterministic validator.",
                        task_id=task_id,
                    )
                )
                task_block_reasons[task_id].append("artifact_validator_missing")
            path = str(artifact.get("path", "")).replace("\\", "/")
            if path:
                prior = produced_paths.get(path)
                if prior and prior not in {str(item) for item in task.get("dependencies", [])}:
                    issues.append(
                        issue(
                            ERROR,
                            "artifact_path_producer_conflict",
                            f"Tasks {prior} and {task_id} both produce {path} without an explicit dependency.",
                            task_id=task_id,
                        )
                    )
                    task_block_reasons[task_id].append("artifact_path_producer_conflict")
                produced_paths[path] = task_id

        task_risk = str(task.get("risk", "low"))
        if task_risk in {"high", "critical"}:
            approvals.add(f"risk:{task_risk}")
        if task.get("dataBoundary") in {"secret", "external", "network"}:
            approvals.add(f"data_boundary:{task.get('dataBoundary')}")
        if any(risks.get(tool) in {"destructive", "external", "network"} for tool in allowed):
            approvals.add("high_risk_tool")

        if not enabled:
            status = "disabled"
        elif manual:
            status = "manual"
        elif task_block_reasons[task_id]:
            status = "blocked"
        else:
            status = "ready"
        compiled_tasks.append(
            {
                "id": task_id,
                "status": status,
                "inferredCapabilities": sorted(inferred),
                "requiredCapabilities": sorted(required),
                "allowedTools": sorted(allowed),
                "approvalRequired": bool(
                    task_risk in {"high", "critical"}
                    or task.get("dataBoundary") in {"secret", "external", "network"}
                    or manual
                ),
                "blockReasons": sorted(set(task_block_reasons[task_id])),
            }
        )

    order, batches = topological_batches(tasks)
    batch_index = {task_id: index for index, batch in enumerate(batches) for task_id in batch}
    for compiled in compiled_tasks:
        compiled["topologicalIndex"] = order.index(compiled["id"]) if compiled["id"] in order else None
        compiled["executionBatch"] = batch_index.get(compiled["id"])

    total_model_turns = sum(int(task.get("budgets", {}).get("modelTurns", 0)) for task in tasks if task.get("enabled") is not False)
    total_tool_calls = sum(int(task.get("budgets", {}).get("toolCalls", 0)) for task in tasks if task.get("enabled") is not False)
    total_output_bytes = sum(int(task.get("budgets", {}).get("outputBytes", 0)) for task in tasks if task.get("enabled") is not False)
    for name, actual, maximum in (
        ("model turns", total_model_turns, policy_value["maxTotalModelTurns"]),
        ("tool calls", total_tool_calls, policy_value["maxTotalToolCalls"]),
        ("output bytes", total_output_bytes, policy_value["maxTotalOutputBytes"]),
    ):
        if actual > maximum:
            issues.append(issue(ERROR, "plan_budget_exceeded", f"Plan {name} budget {actual} exceeds policy maximum {maximum}."))

    graph_errors = sum(1 for item in issues if item["severity"] == ERROR and item["code"] in {
        "task_id_duplicate", "dependency_missing", "dependency_disabled", "dependency_cycle", "parent_missing", "parent_cycle", "parent_self_reference"
    })
    policy_errors = sum(1 for item in issues if item["severity"] == ERROR and item["code"] in {
        "network_capability_blocked", "sandbox_required", "local_only_external_claim", "human_workflow_missing",
        "self_modification_not_approved", "deployment_mode_not_executable", "deployment_target_missing", "plan_budget_exceeded"
    })
    schema_score = 20.0 if not (spec_schema_issues or plan_schema_issues) else 0.0
    graph_score = max(0.0, 20.0 - graph_errors * 5.0)
    capability_score = 20.0 if capability_required_count == 0 else 20.0 * capability_covered_count / capability_required_count
    verification_score = 15.0 if criterion_count == 0 else 15.0 * criterion_verified_count / criterion_count
    artifact_score = 15.0 if artifact_count == 0 else 15.0 * artifact_validated_count / artifact_count
    policy_score = max(0.0, 10.0 - policy_errors * 3.0)
    errors = [item for item in issues if item["severity"] == ERROR]
    warnings = [item for item in issues if item["severity"] == WARNING]
    base_score = schema_score + graph_score + capability_score + verification_score + artifact_score + policy_score
    # Any blocking compiler error must have a visible quality impact even when
    # category coverage metrics remain numerically complete. Warnings are also
    # measurable but intentionally much smaller.
    total_score = round(max(0.0, base_score - min(40.0, len(errors) * 10.0) - min(10.0, len(warnings) * 1.0)), 2)
    status_counts: dict[str, int] = defaultdict(int)
    for task in compiled_tasks:
        status_counts[str(task["status"])] += 1
    simulation = {
        "dryRun": True,
        "sideEffectsPerformed": False,
        "taskCount": len(tasks),
        "enabledTaskCount": sum(1 for task in tasks if task.get("enabled") is not False),
        "readyTaskCount": status_counts["ready"],
        "manualTaskCount": status_counts["manual"],
        "blockedTaskCount": status_counts["blocked"],
        "disabledTaskCount": status_counts["disabled"],
        "executionBatchCount": len(batches),
        "criticalPathEffortPoints": longest_effort_path(tasks, order),
        "estimatedBudgets": {
            "modelTurns": total_model_turns,
            "toolCalls": total_tool_calls,
            "outputBytes": total_output_bytes,
        },
        "materialOutputPaths": sorted(produced_paths),
        "requiredApprovals": sorted(approvals),
        "sandboxAvailable": policy_value["sandboxAvailable"],
        "localOnly": effective_local_only,
    }
    input_hash = sha256_json(
        {
            "specification": specification,
            "plan": plan,
            "policy": policy_value,
            "toolRegistryVersion": contracts["tools"].get("registryVersion"),
            "capabilityCatalogVersion": contracts["capabilities"].get("catalogVersion"),
        }
    )
    report: dict[str, Any] = {
        "schemaVersion": REPORT_SCHEMA_VERSION,
        "planId": str(plan.get("id", "")),
        "specificationId": str(specification.get("id", "")),
        "inputHash": input_hash,
        "compilerVersion": COMPILER_VERSION,
        "executable": not errors,
        "issues": sorted(
            issues,
            key=lambda item: (
                {ERROR: 0, WARNING: 1, INFO: 2}.get(str(item.get("severity")), 3),
                str(item.get("taskId", "")),
                str(item.get("code", "")),
                str(item.get("path", "")),
            ),
        ),
        "topologicalOrder": order,
        "executionBatches": batches,
        "compiledTasks": compiled_tasks,
        "quality": {
            "score": total_score,
            "grade": quality_grade(total_score),
            "categories": {
                "schema": round(schema_score, 2),
                "graph": round(graph_score, 2),
                "capability": round(capability_score, 2),
                "verification": round(verification_score, 2),
                "artifacts": round(artifact_score, 2),
                "policy": round(policy_score, 2),
            },
            "metrics": {
                "errors": len(errors),
                "warnings": len(warnings),
                "capabilitiesCovered": capability_covered_count,
                "capabilitiesRequired": capability_required_count,
                "criteriaVerified": criterion_verified_count,
                "criteriaTotal": criterion_count,
                "artifactsValidated": artifact_validated_count,
                "artifactsTotal": artifact_count,
            },
        },
        "simulation": simulation,
    }
    report["outputHash"] = sha256_json(report)
    report_schema_issues = validate_document(report, contracts["report"], document_name="compilation_report")
    if report_schema_issues:
        raise RuntimeError(f"compiler emitted an invalid report: {report_schema_issues}")
    return report


def _prompt_text(prompt: Mapping[str, Any]) -> tuple[str, str, set[str]]:
    general_fields = (
        "title", "purpose", "systemPrompt", "userPrompt"
    )
    list_fields = (
        "assumptions", "clarifyingQuestions", "outputExpectations", "guardrails", "stopConditions"
    )
    parts = [str(prompt.get(field, "")) for field in general_fields]
    for field in list_fields:
        parts.extend(str(value) for value in prompt.get(field, []) if value is not None)
    criteria = " ".join(str(value) for value in prompt.get("acceptanceCriteria", []))
    variables = {str(value) for value in prompt.get("variables", [])}
    return " ".join(parts).lower(), criteria.lower(), variables


def evaluate_prompt(prompt: Mapping[str, Any], dataset: Mapping[str, Any], *, contracts: Mapping[str, Mapping[str, Any]] | None = None) -> dict[str, Any]:
    contracts = dict(contracts or load_contracts())
    dataset_issues = validate_document(dataset, contracts["evaluation"], document_name="evaluation_dataset")
    if dataset_issues:
        raise CompilationInputError(f"evaluation dataset failed schema validation: {dataset_issues}")
    body, criteria, variables = _prompt_text(prompt)
    mode = str(prompt.get("mode", ""))
    cases: list[dict[str, Any]] = []
    weighted_score = 0.0
    total_weight = 0.0
    for case in dataset.get("cases", []):
        if not isinstance(case, dict):
            continue
        checks: list[dict[str, Any]] = []
        for term in case.get("requiredTerms", []):
            passed = str(term).lower() in body
            checks.append({"kind": "required_term", "value": term, "passed": passed})
        for term in case.get("forbiddenTerms", []):
            passed = str(term).lower() not in body
            checks.append({"kind": "forbidden_term", "value": term, "passed": passed})
        for variable in case.get("requiredVariables", []):
            passed = str(variable) in variables
            checks.append({"kind": "required_variable", "value": variable, "passed": passed})
        for term in case.get("requiredCriterionTerms", []):
            passed = str(term).lower() in criteria
            checks.append({"kind": "criterion_term", "value": term, "passed": passed})
        expected_mode = str(case.get("expectedMode", ""))
        checks.append({"kind": "expected_mode", "value": expected_mode, "passed": mode == expected_mode})
        passed_count = sum(1 for item in checks if item["passed"])
        score = 100.0 if not checks else round(100.0 * passed_count / len(checks), 2)
        weight = float(case.get("weight", 1.0))
        weighted_score += score * weight
        total_weight += weight
        cases.append(
            {
                "id": str(case.get("id", "")),
                "score": score,
                "passed": all(item["passed"] for item in checks),
                "checks": checks,
                "tags": list(case.get("tags", [])),
                "weight": weight,
            }
        )
    overall = round(weighted_score / total_weight, 2) if total_weight else 0.0
    result: dict[str, Any] = {
        "schemaVersion": "1.0.0",
        "datasetId": dataset.get("id"),
        "promptHash": sha256_json(prompt),
        "score": overall,
        "passedCases": sum(1 for case in cases if case["passed"]),
        "caseCount": len(cases),
        "cases": cases,
    }
    result["resultHash"] = sha256_json(result)
    return result


def prompt_diff(baseline: Mapping[str, Any], candidate: Mapping[str, Any]) -> dict[str, Any]:
    fields = sorted(set(baseline) | set(candidate))
    changed: list[dict[str, Any]] = []
    for field in fields:
        before = baseline.get(field)
        after = candidate.get(field)
        if canonical_json(before) == canonical_json(after):
            continue
        item: dict[str, Any] = {
            "field": field,
            "beforeHash": sha256_json(before),
            "afterHash": sha256_json(after),
        }
        if isinstance(before, list) and isinstance(after, list):
            before_set = {canonical_json(value): value for value in before}
            after_set = {canonical_json(value): value for value in after}
            item["added"] = [after_set[key] for key in sorted(after_set.keys() - before_set.keys())]
            item["removed"] = [before_set[key] for key in sorted(before_set.keys() - after_set.keys())]
        changed.append(item)
    result: dict[str, Any] = {
        "schemaVersion": "1.0.0",
        "baselineHash": sha256_json(baseline),
        "candidateHash": sha256_json(candidate),
        "changedFields": changed,
        "changedFieldCount": len(changed),
    }
    result["diffHash"] = sha256_json(result)
    return result


def compare_prompt_versions(
    baseline: Mapping[str, Any],
    candidate: Mapping[str, Any],
    dataset: Mapping[str, Any],
    *,
    contracts: Mapping[str, Mapping[str, Any]] | None = None,
) -> dict[str, Any]:
    baseline_result = evaluate_prompt(baseline, dataset, contracts=contracts)
    candidate_result = evaluate_prompt(candidate, dataset, contracts=contracts)
    result: dict[str, Any] = {
        "schemaVersion": "1.0.0",
        "datasetId": dataset.get("id"),
        "baseline": baseline_result,
        "candidate": candidate_result,
        "diff": prompt_diff(baseline, candidate),
        "measuredImpact": {
            "scoreDelta": round(candidate_result["score"] - baseline_result["score"], 2),
            "passedCaseDelta": candidate_result["passedCases"] - baseline_result["passedCases"],
            "acceptanceCriterionDelta": len(candidate.get("acceptanceCriteria", [])) - len(baseline.get("acceptanceCriteria", [])),
            "variableDelta": len(candidate.get("variables", [])) - len(baseline.get("variables", [])),
        },
    }
    result["comparisonHash"] = sha256_json(result)
    return result


def compare_plans(
    specification: Mapping[str, Any],
    baseline: Mapping[str, Any],
    candidate: Mapping[str, Any],
    *,
    policy: Mapping[str, Any] | None = None,
    contracts: Mapping[str, Mapping[str, Any]] | None = None,
) -> dict[str, Any]:
    contracts_value = dict(contracts or load_contracts())
    baseline_report = compile_plan(specification, baseline, policy=policy, contracts=contracts_value)
    candidate_report = compile_plan(specification, candidate, policy=policy, contracts=contracts_value)
    result: dict[str, Any] = {
        "schemaVersion": "1.0.0",
        "baselinePlanId": baseline.get("id"),
        "candidatePlanId": candidate.get("id"),
        "baseline": {
            "quality": baseline_report["quality"],
            "executable": baseline_report["executable"],
            "issueCodes": [item["code"] for item in baseline_report["issues"]],
            "outputHash": baseline_report["outputHash"],
        },
        "candidate": {
            "quality": candidate_report["quality"],
            "executable": candidate_report["executable"],
            "issueCodes": [item["code"] for item in candidate_report["issues"]],
            "outputHash": candidate_report["outputHash"],
        },
        "measuredImpact": {
            "qualityScoreDelta": round(candidate_report["quality"]["score"] - baseline_report["quality"]["score"], 2),
            "errorDelta": candidate_report["quality"]["metrics"]["errors"] - baseline_report["quality"]["metrics"]["errors"],
            "warningDelta": candidate_report["quality"]["metrics"]["warnings"] - baseline_report["quality"]["metrics"]["warnings"],
            "readyTaskDelta": candidate_report["simulation"]["readyTaskCount"] - baseline_report["simulation"]["readyTaskCount"],
        },
    }
    result["comparisonHash"] = sha256_json(result)
    return result


def parse_policy(path: str | None) -> dict[str, Any]:
    return normalize_policy(read_json(Path(path)) if path else None)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    compile_cmd = sub.add_parser("compile", help="Compile and dry-run one v2 plan")
    compile_cmd.add_argument("--spec", required=True)
    compile_cmd.add_argument("--plan", required=True)
    compile_cmd.add_argument("--policy")
    compile_cmd.add_argument("--output")
    compile_cmd.add_argument("--fail-on-errors", action="store_true")

    evaluate_cmd = sub.add_parser("evaluate-prompt", help="Compare two prompt versions on a static evaluation dataset")
    evaluate_cmd.add_argument("--baseline", required=True)
    evaluate_cmd.add_argument("--candidate", required=True)
    evaluate_cmd.add_argument("--dataset", required=True)
    evaluate_cmd.add_argument("--output")

    compare_cmd = sub.add_parser("compare-plans", help="Compile two plan revisions and report measured impact")
    compare_cmd.add_argument("--spec", required=True)
    compare_cmd.add_argument("--baseline", required=True)
    compare_cmd.add_argument("--candidate", required=True)
    compare_cmd.add_argument("--policy")
    compare_cmd.add_argument("--output")

    validate_cmd = sub.add_parser("validate-contracts", help="Validate all Prompt Studio 2 schema files")
    validate_cmd.add_argument("--output")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    contracts = load_contracts()
    if args.command == "compile":
        report = compile_plan(
            read_json(Path(args.spec)),
            read_json(Path(args.plan)),
            policy=parse_policy(args.policy),
            contracts=contracts,
        )
        write_json(Path(args.output) if args.output else None, report)
        if args.fail_on_errors and not report["executable"]:
            return 2
        return 0
    if args.command == "evaluate-prompt":
        report = compare_prompt_versions(
            read_json(Path(args.baseline)),
            read_json(Path(args.candidate)),
            read_json(Path(args.dataset)),
            contracts=contracts,
        )
        write_json(Path(args.output) if args.output else None, report)
        return 0
    if args.command == "compare-plans":
        report = compare_plans(
            read_json(Path(args.spec)),
            read_json(Path(args.baseline)),
            read_json(Path(args.candidate)),
            policy=parse_policy(args.policy),
            contracts=contracts,
        )
        write_json(Path(args.output) if args.output else None, report)
        return 0
    if args.command == "validate-contracts":
        result = {
            "schemaVersion": "1.0.0",
            "compilerVersion": COMPILER_VERSION,
            "contracts": {
                name: {
                    "file": SCHEMA_FILES[name],
                    "sha256": hashlib.sha256(schema_path(name).read_bytes()).hexdigest(),
                }
                for name in sorted(contracts)
            },
        }
        result["contractSetHash"] = sha256_json(result)
        write_json(Path(args.output) if args.output else None, result)
        return 0
    raise AssertionError(args.command)


if __name__ == "__main__":
    raise SystemExit(main())
