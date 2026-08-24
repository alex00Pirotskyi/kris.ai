#!/usr/bin/env python3
"""Dependency-free v1.2 protocol/schema regression and fuzz gate."""
from __future__ import annotations

import json
import random
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = ROOT / "schemas" / "tool_registry.v2.json"
DECISION_PATH = ROOT / "schemas" / "agent_decision.v1.json"
WORKSPACE_SOURCE = ROOT / "lib" / "product" / "workspace_tools.dart"
WORKSPACE_IMPLEMENTATION = ROOT / "lib" / "product" / "workspace_tools_base.dart.inc"
PROTOCOL_SOURCE = ROOT / "lib" / "product" / "agent_protocol.dart"
DECISION_SOURCE = ROOT / "lib" / "product" / "agent_decision.dart"


class ValidationError(Exception):
    def __init__(self, keyword: str, path: str, message: str):
        super().__init__(message)
        self.keyword = keyword
        self.path = path


def type_matches(value: Any, expected: Any) -> bool:
    values = expected if isinstance(expected, list) else [expected]
    for name in values:
        if name == "null" and value is None:
            return True
        if name == "boolean" and isinstance(value, bool):
            return True
        if name == "integer" and isinstance(value, int) and not isinstance(value, bool):
            return True
        if name == "number" and isinstance(value, (int, float)) and not isinstance(value, bool):
            return True
        if name == "string" and isinstance(value, str):
            return True
        if name == "array" and isinstance(value, list):
            return True
        if name == "object" and isinstance(value, dict):
            return True
    return False


def validate(value: Any, schema: dict[str, Any], path: str = "$") -> None:
    if "const" in schema and value != schema["const"]:
        raise ValidationError("const", path, "constant mismatch")
    if "enum" in schema and value not in schema["enum"]:
        raise ValidationError("enum", path, "enum mismatch")
    if "type" in schema and not type_matches(value, schema["type"]):
        raise ValidationError("type", path, f"expected {schema['type']}")
    if isinstance(value, dict):
        properties = schema.get("properties", {})
        for required in schema.get("required", []):
            if required not in value:
                raise ValidationError("required", f"{path}.{required}", "missing required property")
        for key, item in value.items():
            if key in properties:
                validate(item, properties[key], f"{path}.{key}")
            else:
                additional = schema.get("additionalProperties", True)
                if additional is False:
                    raise ValidationError("additionalProperties", f"{path}.{key}", "unknown property")
                if isinstance(additional, dict):
                    validate(item, additional, f"{path}.{key}")
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0):
            raise ValidationError("minItems", path, "too few items")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            raise ValidationError("maxItems", path, "too many items")
        if isinstance(schema.get("items"), dict):
            for index, item in enumerate(value):
                validate(item, schema["items"], f"{path}[{index}]")
    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0):
            raise ValidationError("minLength", path, "string too short")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            raise ValidationError("maxLength", path, "string too long")
        if "pattern" in schema and re.search(schema["pattern"], value) is None:
            raise ValidationError("pattern", path, "pattern mismatch")
        if schema.get("format") == "https-uri" and not value.startswith("https://"):
            raise ValidationError("format", path, "not https")
        if schema.get("format") == "project-relative-path" and (not value.strip() or "\x00" in value):
            raise ValidationError("format", path, "invalid path token")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            raise ValidationError("minimum", path, "below minimum")
        if "maximum" in schema and value > schema["maximum"]:
            raise ValidationError("maximum", path, "above maximum")
    if "allOf" in schema:
        for branch in schema["allOf"]:
            validate(value, branch, path)
    if "anyOf" in schema:
        passes = 0
        for branch in schema["anyOf"]:
            try:
                validate(value, branch, path)
                passes += 1
            except ValidationError:
                pass
        if passes == 0:
            raise ValidationError("anyOf", path, "no branch matched")
    if "oneOf" in schema:
        passes = 0
        for branch in schema["oneOf"]:
            try:
                validate(value, branch, path)
                passes += 1
            except ValidationError:
                pass
        if passes != 1:
            raise ValidationError("oneOf", path, f"expected exactly one matching branch, found {passes}")


def deep_clone(value: Any) -> Any:
    return json.loads(json.dumps(value))


def normalize(arguments: dict[str, Any], contract: dict[str, Any]) -> dict[str, Any]:
    result = deep_clone(arguments)
    for target, aliases in contract.get("aliases", {}).items():
        for alias in aliases:
            if alias not in result:
                continue
            if target in result and result[target] != result[alias]:
                raise ValidationError("aliasConflict", f"$.{target}", "conflicting alias")
            result.setdefault(target, result[alias])
            del result[alias]
    for name, prop in contract["inputSchema"].get("properties", {}).items():
        if name not in result and "default" in prop:
            result[name] = deep_clone(prop["default"])
        if name not in result:
            continue
        value = result[name]
        if prop.get("type") == "integer" and isinstance(value, str) and re.fullmatch(r"[-+]?\d+", value.strip()):
            result[name] = int(value)
        if prop.get("type") == "boolean" and isinstance(value, str) and value.strip().lower() in {"true", "false"}:
            result[name] = value.strip().lower() == "true"
    validate(result, contract["inputSchema"])
    return result


def unwrap_provider(envelope: dict[str, Any], provider: str) -> Any:
    if provider == "ollama":
        message = envelope.get("message", {})
        return message.get("content", message)
    if provider == "openai":
        call = envelope["choices"][0]["message"]["tool_calls"][0]["function"]
        return {"action": "tool", "tool": call["name"], "arguments": json.loads(call["arguments"])}
    if provider == "mcp":
        return envelope.get("structuredContent") or envelope.get("structured_content") or envelope.get("result")
    if provider == "recorded":
        return envelope.get("normalizedAction") or envelope.get("decision") or envelope.get("response")
    return envelope


def make_envelope(provider: str, payload: dict[str, Any]) -> dict[str, Any]:
    if provider == "ollama":
        return {"message": {"role": "assistant", "content": json.dumps(payload)}}
    if provider == "openai":
        return {"choices": [{"message": {"tool_calls": [{"type": "function", "function": {"name": payload["tool"], "arguments": json.dumps(payload["arguments"])}}]}}]}
    if provider == "mcp":
        return {"structuredContent": payload}
    if provider == "recorded":
        return {"normalizedAction": payload}
    return payload


def decode_payload(value: Any) -> dict[str, Any]:
    while isinstance(value, str):
        value = json.loads(value)
    if not isinstance(value, dict):
        raise AssertionError("provider did not yield an object")
    return value


def tool_result(data: dict[str, Any], *, mutated: bool = False, ok: bool = True) -> dict[str, Any]:
    return {"ok": ok, "summary": "representative runtime result", "data": data, "mutated": mutated}


def representative_output_samples() -> dict[str, dict[str, Any]]:
    digest = "0" * 64
    timestamp = "2026-07-22T00:00:00.000Z"

    def mutation(operation: str, path: str, *, existed: bool) -> dict[str, Any]:
        return {
            "id": f"mutation_{operation}",
            "operation": operation,
            "relativePath": path,
            "existed": existed,
            "beforeHash": digest if existed else "",
            "afterHash": "" if operation == "delete" else digest,
            "backupPath": "" if not existed else ".kristin/backups/sample",
            "timestamp": timestamp,
        }

    return {
        "list_directory": tool_result({"entries": []}),
        "read_file": tool_result({"path": "README.md", "content": "", "sha256": digest, "bytes": 0}),
        "inspect_file": tool_result({
            "path": "README.md",
            "bytes": 0,
            "sha256": digest,
            "format": "text",
            "mimeType": "text/markdown",
            "binary": False,
            "modifiedAt": timestamp,
        }),
        "search_text": tool_result({"results": [], "filesScanned": 0}),
        "index_project": tool_result({"total": 0, "changed": 0, "removed": 0}),
        "index_search": tool_result({"results": []}),
        "write_file": tool_result(mutation("create", "docs/sample.md", existed=False), mutated=True),
        "write_binary_file": tool_result({
            **mutation("create", "artifacts/sample.bin", existed=False),
            "bytes": 4,
            "format": "binary",
            "mimeType": "application/octet-stream",
        }, mutated=True),
        "replace_text": tool_result(mutation("replace", "docs/sample.md", existed=True), mutated=True),
        "apply_patch": tool_result(mutation("replace", "lib/sample.dart", existed=True), mutated=True),
        "delete_file": tool_result(mutation("delete", "docs/obsolete.md", existed=True), mutated=True),
        "run_command": tool_result({"exitCode": 0, "stdout": "", "stderr": "", "durationMs": 1}),
        "start_process": tool_result({"id": "process_1", "pid": 1234}),
        "process_status": tool_result({"id": "process_1", "pid": 1234, "running": True}),
        "stop_process": tool_result({"id": "process_1", "stopped": True}),
        "git_status": tool_result({"branch": "main", "porcelain": ""}),
        "git_diff": tool_result({"diff": ""}),
        "knowledge_search": tool_result({"results": []}),
        "research_fetch": tool_result({
            "knowledgeId": "knowledge_1",
            "archiveId": "archive_1",
            "title": "Example",
            "url": "https://example.com",
            "contentHash": digest,
            "trust": "untrusted",
            "characters": 10,
        }, mutated=True),
        "research_search": tool_result({
            "results": [],
            "knowledgeId": "knowledge_1",
            "archiveId": "archive_1",
            "contentHash": digest,
        }, mutated=True),
        "verify_project": tool_result({"checks": []}),
        "package_deployment": tool_result({"artifacts": [], "manifest": "release/manifest.json"}),
        "mcp_call": tool_result({"content": [], "isError": False}),
    }


def main() -> int:
    subprocess.run([sys.executable, str(ROOT / "tool" / "generate_protocol_contracts.py"), "--check"], cwd=ROOT, check=True)
    registry = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
    decision = json.loads(DECISION_PATH.read_text(encoding="utf-8"))
    tools = registry["tools"]
    by_name = {tool["name"]: tool for tool in tools}
    assert len(tools) == len(by_name) == 23
    assert registry["registryVersion"] == "2.0.0"
    assert decision["schemaVersion"] == "1.0.0"
    assert {"toolDecision", "completeDecision", "failDecision", "askUserDecision", "delegateDecision"}.issubset(decision["$defs"])

    wrapper_source = WORKSPACE_SOURCE.read_text(encoding="utf-8")
    if "workspace_tools_base.dart.inc" not in wrapper_source:
        raise AssertionError("workspace tool adapter must explicitly bind the governed implementation")
    source = wrapper_source + "\n" + WORKSPACE_IMPLEMENTATION.read_text(encoding="utf-8")
    handlers = set(re.findall(r"contract:\s*schemas\.require\('([a-z0-9_]+)'\)", source))
    if handlers != set(by_name):
        raise AssertionError(f"handler/schema drift: only_handlers={sorted(handlers-set(by_name))}, only_schemas={sorted(set(by_name)-handlers)}")

    write = by_name["write_file"]
    assert {"path", "content"}.issubset(write["inputSchema"]["required"])
    try:
        normalize({"path": "docs/missing.md"}, write)
    except ValidationError as error:
        assert error.keyword == "required" and error.path.endswith(".content")
    else:
        raise AssertionError("write_file without content passed validation")

    exact = "# Exact\n\nKeep whitespace, ${tokens}, and Unicode Ω.\n"
    aliased = normalize({"filePath": "docs/exact.md", "body": exact, "expected_exists": "false"}, write)
    assert aliased["content"] == exact
    assert aliased["path"] == "docs/exact.md"
    assert aliased["expectedExists"] is False

    output_samples = representative_output_samples()
    if set(output_samples) != set(by_name):
        raise AssertionError(
            f"output sample drift: missing={sorted(set(by_name)-set(output_samples))}, "
            f"extra={sorted(set(output_samples)-set(by_name))}"
        )
    for contract in tools:
        validate(normalize(contract["example"], contract), contract["inputSchema"])
        validate(output_samples[contract["name"]], contract["outputSchema"])

    invalid_write_output = deep_clone(output_samples["write_file"])
    del invalid_write_output["data"]["afterHash"]
    try:
        validate(invalid_write_output, write["outputSchema"])
    except ValidationError as error:
        assert error.keyword == "required" and error.path.endswith(".afterHash")
    else:
        raise AssertionError("write_file output without afterHash passed validation")

    providers = ["ollama", "openai", "mcp", "recorded"]
    aliases = ["content", "body", "fileContent", "new_content"]
    path_aliases = ["path", "filePath", "file_path", "target"]
    randomizer = random.Random(120)
    cases = 2000
    for index in range(cases):
        content = f"case-{index}-{randomizer.randrange(1 << 40)}\n" + "x" * randomizer.randrange(200)
        arguments = {
            path_aliases[index % len(path_aliases)]: f"docs/fuzz-{index}.md",
            aliases[index % len(aliases)]: content,
        }
        payload = {"action": "tool", "tool": "write_file", "arguments": arguments}
        provider = providers[index % len(providers)]
        recovered = decode_payload(unwrap_provider(make_envelope(provider, payload), provider))
        canonical = normalize(recovered["arguments"], write)
        if canonical["content"] != content:
            raise AssertionError(f"canonical content loss at fuzz case {index}")
        if canonical["path"] != f"docs/fuzz-{index}.md":
            raise AssertionError(f"canonical path loss at fuzz case {index}")

    protocol_source = PROTOCOL_SOURCE.read_text(encoding="utf-8")
    decision_source = DECISION_SOURCE.read_text(encoding="utf-8")
    required_markers = [
        "class AgentProtocolAdapter",
        "AgentDecision parseDecision",
        "class OllamaAgentProviderAdapter",
        "class OpenAiCompatibleAgentProviderAdapter",
        "class McpAgentProviderAdapter",
        "class RecordedAgentProviderAdapter",
        "toolSchemas.normalizeAndValidate",
        "canonicalCandidates",
        "decisionCodec.decodeCanonical(candidate)",
    ]
    for marker in required_markers:
        if marker not in protocol_source:
            raise AssertionError(f"missing protocol marker: {marker}")
    for marker in ["sealed class AgentDecision", "class ToolDecision", "class CompleteDecision", "class FailDecision", "class AskUserDecision", "class DelegateDecision"]:
        if marker not in decision_source:
            raise AssertionError(f"missing decision marker: {marker}")

    print(
        "PASS: typed protocol/schema gate; "
        f"tools={len(tools)} output_contracts={len(output_samples)} "
        f"providers={len(providers)} fuzz_cases={cases} "
        "missing_mutation_data_blocked=true invalid_output_blocked=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
