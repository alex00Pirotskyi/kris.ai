#!/usr/bin/env python3
"""Canonical Test Center and Development Verification contract validation.

Check mode is read-only. Writing a generated report is an explicit, separate action.
"""
from __future__ import annotations

import argparse
import copy
import fnmatch
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any, Iterable, Mapping, Sequence

SCHEMA_RELATIVE = Path("schemas/test_center.v1.json")
REGISTRY_RELATIVE = Path("config/test_center_registry.v1.json")
GENERATED_REPORT_RELATIVE = Path(
    "release/evidence/worker-b/test-center-contract-validation.json"
)

STABLE_TEST_ID_RE = re.compile(
    r"^tc\.[a-z0-9]+(?:[._-][a-z0-9]+)*\.[a-z0-9]+(?:[._-][a-z0-9]+)*$"
)
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
GIT_SHA_RE = re.compile(r"^[0-9a-f]{40}$")
SHELL_EXECUTABLES = {
    "bash",
    "bash.exe",
    "cmd",
    "cmd.exe",
    "dash",
    "fish",
    "ksh",
    "powershell",
    "powershell.exe",
    "pwsh",
    "pwsh.exe",
    "sh",
    "sh.exe",
    "zsh",
}
SHELL_CONTROL_TOKENS = {"&&", "||", ";", "|", ">", ">>", "<", "<<"}
MUTATING_FLAGS = {"--apply", "--fix", "--in-place", "--write", "-w"}
MUTATING_GIT_SUBCOMMANDS = {
    "add",
    "am",
    "apply",
    "checkout",
    "cherry-pick",
    "clean",
    "commit",
    "merge",
    "mv",
    "pull",
    "push",
    "rebase",
    "reset",
    "restore",
    "rm",
    "switch",
    "tag",
}
MUTATING_DART_SUBCOMMANDS = {"fix", "format"}
MUTATING_FLUTTER_SUBCOMMANDS = {"build", "clean", "create"}
MUTATING_SCRIPT_RE = re.compile(
    r"(?:^|[_-])(generate|generator|repair|format|commit|push|merge)(?:[_-]|\.|$)"
)
TEST_RESULT_STATES = {
    "PASS",
    "FAIL",
    "ERROR",
    "SKIPPED",
    "BLOCKED",
    "UNKNOWN",
    "FLAKY",
    "NOT_IMPLEMENTED",
}
ROADMAP_TASK_STATES = {
    "NOT_STARTED",
    "READY",
    "IN_PROGRESS",
    "BLOCKED",
    "REVIEW",
    "DONE",
    "DEFERRED",
}
WORKER_RUNTIME_STATES = {
    "UNCLAIMED",
    "CLAIMED",
    "ACTIVE",
    "YIELDED",
    "BLOCKED",
    "CANCELLED",
    "COMPLETED",
}
CERTIFICATION_STATES = {
    "NOT_EVALUATED",
    "PARTIAL",
    "PASS",
    "FAIL",
    "STALE",
    "REVOKED",
}
CAPABILITY_SUPPORT_STATES = {
    "NOT_IMPLEMENTED",
    "SOURCE_FOUNDATION",
    "EXPERIMENTAL",
    "BEHAVIOR_SUPPORTED",
    "PLATFORM_SUPPORTED",
    "RELEASE_SUPPORTED",
    "DEGRADED",
    "UNSUPPORTED",
    "REVOKED",
}
STATE_DOMAIN_VALUES = {
    "ROADMAP_TASK": ROADMAP_TASK_STATES,
    "WORKER_RUNTIME": WORKER_RUNTIME_STATES,
    "TEST_EXECUTION": TEST_RESULT_STATES,
    "CERTIFICATION": CERTIFICATION_STATES,
    "CAPABILITY_SUPPORT": CAPABILITY_SUPPORT_STATES,
}
LEGACY_RESULT_MAP = {
    "passed": "PASS",
    "failed": "FAIL",
    "unavailable": "BLOCKED",
    "not_run": "SKIPPED",
}


class ContractError(ValueError):
    """Raised when schema-valid data violates a cross-record safety invariant."""


def _load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _canonical_json(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode(
        "utf-8"
    )


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _ensure_relative_path(value: str, field: str) -> str:
    normalized = value.replace("\\", "/")
    path = PurePosixPath(normalized)
    if not value or path.is_absolute() or ".." in path.parts or "\x00" in value:
        raise ContractError(f"{field} must be a non-empty repository-relative path: {value!r}")
    if normalized.startswith("~/") or re.match(r"^[A-Za-z]:/", normalized):
        raise ContractError(f"{field} must not be absolute: {value!r}")
    return str(path)


def validate_argv(argv: Sequence[str]) -> None:
    if not isinstance(argv, list) or not argv:
        raise ContractError("argv must be a non-empty array")
    if any(not isinstance(token, str) or token == "" for token in argv):
        raise ContractError("argv tokens must be non-empty strings")
    if any("\x00" in token or "\n" in token or "\r" in token for token in argv):
        raise ContractError("argv tokens must not contain NUL or line breaks")
    executable = PurePosixPath(argv[0].replace("\\", "/")).name.lower()
    if executable in SHELL_EXECUTABLES:
        raise ContractError(f"shell executable is not permitted in verification profile: {argv[0]}")
    if any(token in SHELL_CONTROL_TOKENS for token in argv[1:]):
        raise ContractError("shell control tokens are not permitted in argv")
    lowered = [token.lower() for token in argv]
    if any(token in MUTATING_FLAGS for token in lowered[1:]):
        raise ContractError("mutating flags are not permitted in verification argv")
    if executable in {"git", "git.exe"} and len(lowered) > 1:
        if lowered[1] in MUTATING_GIT_SUBCOMMANDS:
            raise ContractError(f"mutating git operation is not permitted: {argv[1]}")
    if executable in {"dart", "dart.exe"} and len(lowered) > 1:
        if lowered[1] in MUTATING_DART_SUBCOMMANDS:
            raise ContractError(f"format/repair operation is not permitted: {argv[1]}")
    if executable in {"flutter", "flutter.bat"} and len(lowered) > 1:
        if lowered[1] in MUTATING_FLUTTER_SUBCOMMANDS:
            raise ContractError(f"mutating Flutter operation is not permitted: {argv[1]}")
    if executable.startswith("python") and len(argv) > 1:
        script_name = PurePosixPath(argv[1].replace("\\", "/")).name.lower()
        if MUTATING_SCRIPT_RE.search(script_name) and "--check" not in lowered[2:]:
            raise ContractError(
                "generation, repair, or formatting scripts require a separate governed "
                "operation and may enter verification only through an explicit --check mode"
            )


def validate_project_test_profile(profile: Mapping[str, Any]) -> None:
    if profile.get("mutationPolicy") != "NON_MUTATING":
        raise ContractError("Development Verification profiles must be NON_MUTATING")
    validate_argv(profile.get("argv", []))
    _ensure_relative_path(str(profile.get("workingDirectory", "")), "workingDirectory")
    for key in ("inputPaths", "expectedOutputs", "affectedPaths"):
        values = profile.get(key, [])
        if not isinstance(values, list):
            raise ContractError(f"{key} must be an array")
        for value in values:
            _ensure_relative_path(str(value), key)
    destination = _ensure_relative_path(
        str(profile.get("evidenceDestination", "")), "evidenceDestination"
    )
    if not destination.startswith("release/evidence/"):
        raise ContractError("evidenceDestination must remain under release/evidence/")
    env = profile.get("environmentAllowlist", [])
    if len(env) != len(set(env)):
        raise ContractError("environmentAllowlist must not contain duplicates")
    for name in env:
        if not re.fullmatch(r"[A-Z_][A-Z0-9_]*", name):
            raise ContractError(f"invalid environment variable allowlist entry: {name!r}")


def validate_stable_test_identity(registry: Mapping[str, Any]) -> None:
    ids: list[str] = []
    for case in registry.get("testCases", []):
        ids.append(case["testId"])
    for profile in registry.get("projectTestProfiles", []):
        ids.append(profile["stableCheckId"])
    invalid = sorted({value for value in ids if not STABLE_TEST_ID_RE.fullmatch(value)})
    if invalid:
        raise ContractError(f"invalid stable test IDs: {invalid}")
    case_ids = [case["testId"] for case in registry.get("testCases", [])]
    duplicates = sorted({value for value in case_ids if case_ids.count(value) > 1})
    if duplicates:
        raise ContractError(f"duplicate test case IDs: {duplicates}")
    profile_ids = [
        profile["stableCheckId"] for profile in registry.get("projectTestProfiles", [])
    ]
    duplicates = sorted({value for value in profile_ids if profile_ids.count(value) > 1})
    if duplicates:
        raise ContractError(f"duplicate Project Test Profile IDs: {duplicates}")
    if set(profile_ids) != set(case_ids):
        missing_profiles = sorted(set(case_ids) - set(profile_ids))
        missing_cases = sorted(set(profile_ids) - set(case_ids))
        raise ContractError(
            "stable test identity must be one-to-one between cases and profiles; "
            f"missing profiles={missing_profiles}, missing cases={missing_cases}"
        )


def _normalize_repo_path(value: str) -> str:
    normalized = _ensure_relative_path(value, "changedPath")
    return normalized.lstrip("./")


def select_affected_tests(
    changed_paths: Iterable[str], mappings: Iterable[Mapping[str, Any]]
) -> list[str]:
    normalized_paths = sorted({_normalize_repo_path(path) for path in changed_paths})
    selected: set[str] = set()
    ordered_mappings = sorted(
        mappings, key=lambda item: (item.get("priority", 1000), item["mappingId"])
    )
    for mapping in ordered_mappings:
        includes = sorted(set(mapping["pathPatterns"]))
        excludes = sorted(set(mapping.get("excludedPaths", [])))
        for changed in normalized_paths:
            included = any(fnmatch.fnmatchcase(changed, pattern) for pattern in includes)
            excluded = any(fnmatch.fnmatchcase(changed, pattern) for pattern in excludes)
            if included and not excluded:
                selected.update(mapping["testIds"])
                break
    return sorted(selected)


def normalize_result_state(value: str, *, allow_legacy: bool = False) -> str:
    if value in TEST_RESULT_STATES:
        return value
    if allow_legacy and value in LEGACY_RESULT_MAP:
        return LEGACY_RESULT_MAP[value]
    raise ContractError(f"unknown test result state; coercion rejected: {value!r}")


def normalize_legacy_result(
    legacy: Mapping[str, Any], *, test_id: str, module_id: str
) -> dict[str, Any]:
    """Explicit adapter for the existing assurance-report status domain.

    It never infers roadmap, certification, or capability-support state.
    """
    state = normalize_result_state(str(legacy.get("status")), allow_legacy=True)
    return {
        "testId": test_id,
        "moduleId": module_id,
        "resultState": state,
        "exitCode": legacy.get("exitCode"),
        "failureClassification": "NONE" if state == "PASS" else "UNKNOWN",
        "certificationImpact": "NONE" if state == "PASS" else "BLOCKS_SCOPE",
    }


def validate_evidence_binding(
    evidence: Mapping[str, Any], *, candidate_commit: str, candidate_tree: str
) -> None:
    if evidence.get("immutable") is not True:
        raise ContractError("evidence reference must be immutable")
    if evidence.get("commit") != candidate_commit or evidence.get("tree") != candidate_tree:
        raise ContractError("evidence belongs to another commit/tree")
    if not SHA256_RE.fullmatch(str(evidence.get("sha256", ""))):
        raise ContractError("evidence sha256 must be lowercase hexadecimal")


def validate_test_execution_result(result: Mapping[str, Any]) -> None:
    normalize_result_state(str(result.get("resultState")))
    if result["resultState"] == "PASS" and result.get("exitCode") not in (0, None):
        raise ContractError("PASS result cannot have a non-zero exit code")
    if result["resultState"] != "PASS" and result.get("failureClassification") == "NONE":
        raise ContractError("non-PASS result requires a failure classification")
    start = datetime.fromisoformat(str(result["startedAt"]).replace("Z", "+00:00"))
    end = datetime.fromisoformat(str(result["endedAt"]).replace("Z", "+00:00"))
    if end < start:
        raise ContractError("endedAt precedes startedAt")
    duration = int((end - start).total_seconds() * 1000)
    if abs(duration - int(result["durationMillis"])) > 1:
        raise ContractError("durationMillis does not match start/end")
    for evidence in result.get("evidenceReferences", []):
        validate_evidence_binding(
            evidence, candidate_commit=result["commit"], candidate_tree=result["tree"]
        )


def validate_certification(record: Mapping[str, Any]) -> None:
    candidate_commit = record["candidateCommit"]
    candidate_tree = record["candidateTree"]
    for evidence in record.get("evidenceBindings", []):
        validate_evidence_binding(
            evidence, candidate_commit=candidate_commit, candidate_tree=candidate_tree
        )
    for result in record.get("observedResults", []):
        validate_test_execution_result(result)
        if result["commit"] != candidate_commit or result["tree"] != candidate_tree:
            raise ContractError("observed test result belongs to another candidate")
    if record["status"] != "PASS":
        return
    if record["staleness"]["isStale"]:
        raise ContractError("stale certification cannot PASS")
    if not record.get("independentReview"):
        raise ContractError("independent review is required for certification PASS")
    review = record["independentReview"]
    if review["decision"] != "PASS":
        raise ContractError("independent review decision must PASS")
    if review["reviewedCommit"] != candidate_commit or review["reviewedTree"] != candidate_tree:
        raise ContractError("independent review belongs to another candidate")
    required_platforms = set(record["platformMatrix"]["required"])
    observed_platforms = set(record["platformMatrix"]["observed"])
    missing_platforms = sorted(required_platforms - observed_platforms)
    if missing_platforms:
        raise ContractError(f"required platform evidence missing: {missing_platforms}")
    required_tests = set(record["requiredTestIds"])
    observed_by_id: dict[str, list[Mapping[str, Any]]] = {}
    for result in record["observedResults"]:
        observed_by_id.setdefault(result["testId"], []).append(result)
    missing_tests = sorted(required_tests - set(observed_by_id))
    if missing_tests:
        raise ContractError(f"mandatory test evidence missing: {missing_tests}")
    for test_id in sorted(required_tests):
        results = observed_by_id[test_id]
        platforms_for_test = {result["platform"] for result in results}
        missing_for_test = sorted(required_platforms - platforms_for_test)
        if missing_for_test:
            raise ContractError(
                f"mandatory test {test_id} is missing platforms: {missing_for_test}"
            )
        for result in results:
            if result["platform"] not in required_platforms:
                continue
            if result["resultState"] != "PASS":
                raise ContractError(
                    f"mandatory test {test_id} on {result['platform']} is "
                    f"{result['resultState']}, not PASS"
                )
            if result["cleanupState"] not in {"CLEAN", "NOT_REQUIRED"}:
                raise ContractError(
                    f"cleanup unresolved for mandatory test {test_id} on "
                    f"{result['platform']}"
                )
            if not result.get("evidenceReferences"):
                raise ContractError(
                    f"mandatory evidence missing for {test_id} on {result['platform']}"
                )
    blocking_findings = [
        finding
        for finding in record.get("findings", [])
        if finding["severity"] in {"CRITICAL", "HIGH"}
        and finding["disposition"] != "RESOLVED"
    ]
    if blocking_findings:
        raise ContractError("critical/high finding remains unresolved")
    if not record.get("evidenceBindings"):
        raise ContractError("certification PASS requires evidence bindings")


def validate_presentation(record: Mapping[str, Any]) -> None:
    domain = record["stateDomain"]
    state = record["currentState"]
    if state not in STATE_DOMAIN_VALUES[domain]:
        raise ContractError(f"state {state!r} is invalid for domain {domain}")
    exact = record.get("lastExactCommitResult")
    if exact:
        normalize_result_state(exact["resultState"])
        if record["staleResultWarning"] and not record["requiredNextAction"]:
            raise ContractError("stale-result warning requires an explicit next action")


def validate_registry(registry: Mapping[str, Any]) -> None:
    validate_stable_test_identity(registry)
    module_ids = [module["moduleId"] for module in registry["testModules"]]
    if len(module_ids) != len(set(module_ids)):
        raise ContractError("duplicate TestModule moduleId")
    module_set = set(module_ids)
    case_ids = {case["testId"] for case in registry["testCases"]}
    for case in registry["testCases"]:
        if case["moduleId"] not in module_set:
            raise ContractError(f"unknown moduleId for {case['testId']}")
    for profile in registry["projectTestProfiles"]:
        validate_project_test_profile(profile)
    mapping_ids = [mapping["mappingId"] for mapping in registry["affectedTestMappings"]]
    if len(mapping_ids) != len(set(mapping_ids)):
        raise ContractError("duplicate AffectedTestMapping mappingId")
    for mapping in registry["affectedTestMappings"]:
        unknown = sorted(set(mapping["testIds"]) - case_ids)
        if unknown:
            raise ContractError(f"affected-test mapping references unknown test IDs: {unknown}")
    for presentation in registry.get("testingStudioPresentationRecords", []):
        validate_presentation(presentation)


def _json_type_matches(value: Any, expected: str) -> bool:
    if expected == "object":
        return isinstance(value, Mapping)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "null":
        return value is None
    raise ContractError(f"unsupported JSON Schema type: {expected!r}")


def _resolve_local_ref(root: Mapping[str, Any], reference: str) -> Mapping[str, Any]:
    if not reference.startswith("#/"):
        raise ContractError(f"only local JSON Schema references are permitted: {reference!r}")
    current: Any = root
    for raw_part in reference[2:].split("/"):
        part = raw_part.replace("~1", "/").replace("~0", "~")
        if not isinstance(current, Mapping) or part not in current:
            raise ContractError(f"unresolved JSON Schema reference: {reference!r}")
        current = current[part]
    if not isinstance(current, Mapping):
        raise ContractError(f"JSON Schema reference is not an object: {reference!r}")
    return current


def _validate_schema_document(schema: Mapping[str, Any]) -> None:
    if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
        raise ContractError("Test Center schema must declare JSON Schema Draft 2020-12")
    if not isinstance(schema.get("$defs"), Mapping) or not schema["$defs"]:
        raise ContractError("Test Center schema must define non-empty $defs")
    allowed = {
        "$defs", "$id", "$ref", "$schema", "additionalProperties", "allOf", "anyOf",
        "const", "description", "enum", "format", "items", "maximum", "minItems",
        "minLength", "minProperties", "minimum", "oneOf", "pattern", "properties",
        "required", "title", "type", "uniqueItems",
    }

    def walk(node: Any, path: tuple[str, ...]) -> None:
        if isinstance(node, list):
            for index, value in enumerate(node):
                walk(value, path + (str(index),))
            return
        if not isinstance(node, Mapping):
            return
        unknown = sorted(set(node) - allowed)
        if unknown:
            raise ContractError(
                f"unsupported JSON Schema keywords at {'/'.join(path) or '<root>'}: {unknown}"
            )
        if "$ref" in node:
            if not isinstance(node["$ref"], str):
                raise ContractError("JSON Schema $ref must be a string")
            _resolve_local_ref(schema, node["$ref"])
        if "type" in node:
            types = node["type"] if isinstance(node["type"], list) else [node["type"]]
            supported = {"array", "boolean", "integer", "null", "number", "object", "string"}
            if not types or any(value not in supported for value in types):
                raise ContractError(f"unsupported JSON Schema type declaration: {node['type']!r}")
        if "required" in node:
            if not isinstance(node["required"], list) or any(
                not isinstance(value, str) for value in node["required"]
            ):
                raise ContractError("JSON Schema required must be an array of strings")
            if len(node["required"]) != len(set(node["required"])):
                raise ContractError("JSON Schema required contains duplicates")
        if "properties" in node and not isinstance(node["properties"], Mapping):
            raise ContractError("JSON Schema properties must be an object")
        for key in ("allOf", "anyOf", "oneOf"):
            if key in node and (
                not isinstance(node[key], list) or not node[key]
                or any(not isinstance(item, Mapping) for item in node[key])
            ):
                raise ContractError(f"JSON Schema {key} must be a non-empty schema array")
        for key, value in node.items():
            if key in {"properties", "$defs"}:
                for child_name, child in value.items():
                    walk(child, path + (key, str(child_name)))
            elif key in {"items", "additionalProperties"} and isinstance(value, Mapping):
                walk(value, path + (key,))
            elif key in {"allOf", "anyOf", "oneOf"}:
                walk(value, path + (key,))

    walk(schema, ())


def _schema_errors(
    value: Any,
    schema: Mapping[str, Any],
    root: Mapping[str, Any],
    path: tuple[str, ...] = (),
) -> list[dict[str, str]]:
    errors: list[dict[str, str]] = []

    def fail(message: str) -> None:
        errors.append({"path": "/".join(path), "message": message})

    if "$ref" in schema:
        errors.extend(_schema_errors(value, _resolve_local_ref(root, schema["$ref"]), root, path))
    for member in schema.get("allOf", []):
        errors.extend(_schema_errors(value, member, root, path))
    if "anyOf" in schema:
        branches = [_schema_errors(value, member, root, path) for member in schema["anyOf"]]
        if all(branch for branch in branches):
            fail("value does not satisfy anyOf")
    if "oneOf" in schema:
        matches = sum(not _schema_errors(value, member, root, path) for member in schema["oneOf"])
        if matches != 1:
            fail(f"value must satisfy exactly one oneOf branch, observed {matches}")
    if "const" in schema and value != schema["const"]:
        fail(f"value must equal const {schema['const']!r}")
    if "enum" in schema and value not in schema["enum"]:
        fail(f"value is not in enum {schema['enum']!r}")

    expected = schema.get("type")
    if expected is not None:
        expected_types = expected if isinstance(expected, list) else [expected]
        if not any(_json_type_matches(value, item) for item in expected_types):
            fail(f"expected type {expected!r}, got {type(value).__name__}")
            return errors

    if isinstance(value, str):
        if "minLength" in schema and len(value) < schema["minLength"]:
            fail(f"string length is below {schema['minLength']}")
        if "pattern" in schema and re.search(schema["pattern"], value) is None:
            fail(f"string does not match pattern {schema['pattern']!r}")
        if schema.get("format") == "date-time":
            try:
                parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            except ValueError:
                fail("string is not an RFC 3339 date-time")
            else:
                if parsed.tzinfo is None:
                    fail("date-time must include an offset")

    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            fail(f"array length is below {schema['minItems']}")
        if schema.get("uniqueItems"):
            rendered = [json.dumps(item, sort_keys=True, separators=(",", ":")) for item in value]
            if len(rendered) != len(set(rendered)):
                fail("array items must be unique")
        item_schema = schema.get("items")
        if isinstance(item_schema, Mapping):
            for index, item in enumerate(value):
                errors.extend(_schema_errors(item, item_schema, root, path + (str(index),)))

    if isinstance(value, Mapping):
        required = schema.get("required", [])
        for name in required:
            if name not in value:
                errors.append({"path": "/".join(path + (name,)), "message": "required property missing"})
        if "minProperties" in schema and len(value) < schema["minProperties"]:
            fail(f"object property count is below {schema['minProperties']}")
        properties = schema.get("properties", {})
        for name, child in properties.items():
            if name in value:
                errors.extend(_schema_errors(value[name], child, root, path + (name,)))
        extras = sorted(set(value) - set(properties))
        additional = schema.get("additionalProperties", True)
        if additional is False and extras:
            fail(f"additional properties are not permitted: {extras}")
        elif isinstance(additional, Mapping):
            for name in extras:
                errors.extend(_schema_errors(value[name], additional, root, path + (name,)))

    if isinstance(value, int) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            fail(f"integer is below minimum {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            fail(f"integer exceeds maximum {schema['maximum']}")
    return errors


def validate_project(project: Path) -> dict[str, Any]:
    project = project.resolve()
    schema_path = project / SCHEMA_RELATIVE
    registry_path = project / REGISTRY_RELATIVE
    schema = _load_json(schema_path)
    registry = _load_json(registry_path)
    _validate_schema_document(schema)
    errors = sorted(_schema_errors(registry, schema, schema), key=lambda error: error["path"])
    if errors:
        raise ContractError("schema validation failed: " + json.dumps(errors, sort_keys=True))
    validate_registry(registry)
    deterministic_a = select_affected_tests(
        ["tool/test_center_contracts.py", "schemas/test_center.v1.json"],
        registry["affectedTestMappings"],
    )
    deterministic_b = select_affected_tests(
        ["schemas/test_center.v1.json", "tool/test_center_contracts.py"],
        list(reversed(registry["affectedTestMappings"])),
    )
    if deterministic_a != deterministic_b:
        raise ContractError("affected-test selection is not deterministic")
    return {
        "schemaVersion": "1.0.0",
        "status": "PASS",
        "checkMode": "NON_MUTATING",
        "schema": str(SCHEMA_RELATIVE),
        "schemaSha256": _sha256_bytes(schema_path.read_bytes()),
        "registry": str(REGISTRY_RELATIVE),
        "registrySha256": _sha256_bytes(registry_path.read_bytes()),
        "moduleCount": len(registry["testModules"]),
        "testCaseCount": len(registry["testCases"]),
        "projectTestProfileCount": len(registry["projectTestProfiles"]),
        "affectedMappingCount": len(registry["affectedTestMappings"]),
        "deterministicSelection": deterministic_a,
        "stateDomains": {
            name: sorted(values) for name, values in sorted(STATE_DOMAIN_VALUES.items())
        },
    }


def _write_report(project: Path, report: Mapping[str, Any], output: Path) -> None:
    target = (project / output).resolve()
    project_resolved = project.resolve()
    try:
        target.relative_to(project_resolved)
    except ValueError as exc:
        raise ContractError("report output must remain inside the project") from exc
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(_canonical_json(report))


def _parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    check = sub.add_parser("check", help="validate without writing")
    check.add_argument("--project", type=Path, default=Path("."))
    write = sub.add_parser("write-report", help="explicitly write a generated report")
    write.add_argument("--project", type=Path, default=Path("."))
    write.add_argument("--output", type=Path, default=GENERATED_REPORT_RELATIVE)
    select = sub.add_parser("select-affected", help="print deterministic affected tests")
    select.add_argument("--project", type=Path, default=Path("."))
    select.add_argument("paths", nargs="+")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv or sys.argv[1:])
    try:
        if args.command == "select-affected":
            registry = _load_json(args.project.resolve() / REGISTRY_RELATIVE)
            validate_registry(registry)
            print(json.dumps(select_affected_tests(args.paths, registry["affectedTestMappings"])))
            return 0
        report = validate_project(args.project)
        if args.command == "write-report":
            _write_report(args.project.resolve(), report, args.output)
        print(json.dumps(report, indent=2, sort_keys=True))
        return 0
    except (ContractError, KeyError, TypeError, ValueError) as exc:
        print(json.dumps({"status": "FAIL", "error": str(exc)}, sort_keys=True), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
