#!/usr/bin/env python3
"""Generate the Dart protocol-contract constants from canonical JSON schemas.

The JSON files in schemas/ are the source of truth. This generator is
intentionally dependency-free so it can run in release and recovery gates.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
TOOL_SCHEMA = ROOT / "schemas" / "tool_registry.v2.json"
DECISION_SCHEMA = ROOT / "schemas" / "agent_decision.v1.json"
OUTPUT = ROOT / "lib" / "product" / "generated" / "protocol_contracts.g.dart"
PERMISSIONS = {
    "projectRead",
    "projectWrite",
    "projectDelete",
    "executeFinite",
    "executeManaged",
    "networkResearch",
    "networkPackages",
    "secretUse",
    "deploymentPackage",
    "mcpConnect",
}
RISKS = {"read", "mutation", "destructive", "process", "network", "external"}
IDEMPOTENCY = {
    "normalized_arguments",
    "content_hash",
    "project_snapshot",
    "operation_key",
    "request_hash",
}


def load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"{path.relative_to(ROOT)} must contain a JSON object")
    return value


def validate_schema_node(node: Any, location: str) -> None:
    if not isinstance(node, dict):
        raise ValueError(f"{location} must be a schema object")
    schema_type = node.get("type")
    if schema_type is not None and not isinstance(schema_type, (str, list)):
        raise ValueError(f"{location}.type must be a string or list")
    required = node.get("required", [])
    properties = node.get("properties", {})
    if not isinstance(required, list) or not all(isinstance(v, str) for v in required):
        raise ValueError(f"{location}.required must be a string list")
    if not isinstance(properties, dict):
        raise ValueError(f"{location}.properties must be an object")
    missing = [name for name in required if name not in properties]
    if missing and properties:
        raise ValueError(f"{location} requires undefined properties: {missing}")
    for name, child in properties.items():
        validate_schema_node(child, f"{location}.properties.{name}")
    items = node.get("items")
    if items is not None:
        validate_schema_node(items, f"{location}.items")
    additional = node.get("additionalProperties")
    if isinstance(additional, dict):
        validate_schema_node(additional, f"{location}.additionalProperties")
    for keyword in ("oneOf", "anyOf", "allOf"):
        branches = node.get(keyword, [])
        if branches:
            if not isinstance(branches, list):
                raise ValueError(f"{location}.{keyword} must be a list")
            for index, branch in enumerate(branches):
                if "$ref" not in branch:
                    validate_schema_node(branch, f"{location}.{keyword}[{index}]")


def validate_contracts(registry: dict[str, Any], decision: dict[str, Any]) -> None:
    if registry.get("registryVersion") != "2.0.0":
        raise ValueError("tool registryVersion must be 2.0.0")
    tools = registry.get("tools")
    if not isinstance(tools, list) or not tools:
        raise ValueError("tool registry must contain tools")
    names: set[str] = set()
    for index, tool in enumerate(tools):
        where = f"tools[{index}]"
        if not isinstance(tool, dict):
            raise ValueError(f"{where} must be an object")
        name = tool.get("name")
        if not isinstance(name, str) or not re.fullmatch(r"[a-z][a-z0-9_]*", name):
            raise ValueError(f"{where}.name is invalid")
        if name in names:
            raise ValueError(f"duplicate tool name: {name}")
        names.add(name)
        if tool.get("permission") not in PERMISSIONS:
            raise ValueError(f"{name}: unknown permission {tool.get('permission')}")
        if tool.get("risk") not in RISKS:
            raise ValueError(f"{name}: unknown risk {tool.get('risk')}")
        if tool.get("idempotency") not in IDEMPOTENCY:
            raise ValueError(f"{name}: unknown idempotency {tool.get('idempotency')}")
        if not isinstance(tool.get("description"), str) or not tool["description"].strip():
            raise ValueError(f"{name}: description is required")
        if not isinstance(tool.get("example"), dict):
            raise ValueError(f"{name}: example must be an object")
        aliases = tool.get("aliases", {})
        if not isinstance(aliases, dict):
            raise ValueError(f"{name}: aliases must be an object")
        input_schema = tool.get("inputSchema")
        output_schema = tool.get("outputSchema")
        validate_schema_node(input_schema, f"{name}.inputSchema")
        validate_schema_node(output_schema, f"{name}.outputSchema")
        properties = input_schema.get("properties", {})
        for canonical, values in aliases.items():
            if canonical not in properties:
                raise ValueError(f"{name}: alias target {canonical} is not an input property")
            if not isinstance(values, list) or not all(isinstance(v, str) and v for v in values):
                raise ValueError(f"{name}: aliases for {canonical} must be a string list")
        unknown_example = set(tool["example"]) - set(properties)
        if unknown_example:
            raise ValueError(f"{name}: example contains unknown fields {sorted(unknown_example)}")
    by_name = {tool["name"]: tool for tool in tools}
    write_required = set(by_name["write_file"]["inputSchema"].get("required", []))
    if not {"path", "content"}.issubset(write_required):
        raise ValueError("write_file must require path and content")
    for mutation in ("write_file", "write_binary_file", "replace_text", "apply_patch", "delete_file"):
        if by_name[mutation]["risk"] not in {"mutation", "destructive"}:
            raise ValueError(f"{mutation} must be classified as mutating")
    if decision.get("schemaVersion") != "1.0.0":
        raise ValueError("AgentDecision schemaVersion must be 1.0.0")
    definitions = decision.get("$defs")
    if not isinstance(definitions, dict):
        raise ValueError("AgentDecision $defs are required")
    expected = {"toolDecision", "completeDecision", "failDecision", "askUserDecision", "delegateDecision"}
    if not expected.issubset(definitions):
        raise ValueError(f"AgentDecision is missing definitions: {sorted(expected - set(definitions))}")
    for name in expected:
        validate_schema_node(definitions[name], f"AgentDecision.$defs.{name}")


def dart_string(value: str) -> str:
    escaped = (
        value.replace("\\", "\\\\")
        .replace("'", "\\'")
        .replace("$", "\\$")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
        .replace("\u2028", "\\u2028")
        .replace("\u2029", "\\u2029")
    )
    return f"'{escaped}'"


def dart_literal(value: Any, indent: int = 0) -> str:
    pad = "  " * indent
    next_pad = "  " * (indent + 1)
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return dart_string(value)
    if isinstance(value, list):
        if not value:
            return "<Object?>[]"
        body = ",\n".join(f"{next_pad}{dart_literal(item, indent + 1)}" for item in value)
        return f"<Object?>[\n{body},\n{pad}]"
    if isinstance(value, dict):
        if not value:
            return "<String, dynamic>{}"
        body = ",\n".join(
            f"{next_pad}{dart_string(str(key))}: {dart_literal(item, indent + 1)}"
            for key, item in value.items()
        )
        return f"<String, dynamic>{{\n{body},\n{pad}}}"
    raise TypeError(f"unsupported value: {type(value).__name__}")


def render(registry: dict[str, Any], decision: dict[str, Any]) -> str:
    canonical = json.dumps(
        {"toolRegistry": registry, "agentDecision": decision},
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")
    digest = hashlib.sha256(canonical).hexdigest()
    names = [tool["name"] for tool in registry["tools"]]
    return "\n".join(
        [
            "// GENERATED CODE - DO NOT EDIT.",
            "// Generated by tool/generate_protocol_contracts.py from schemas/.",
            "",
            f"const String generatedProtocolContractDigest = '{digest}';",
            f"const String generatedToolRegistryVersion = {dart_string(registry['registryVersion'])};",
            f"const String generatedAgentDecisionSchemaVersion = {dart_string(decision['schemaVersion'])};",
            "",
            "const List<String> generatedToolNames = <String>[",
            *[f"  {dart_string(name)}," for name in names],
            "];",
            "",
            "const Map<String, dynamic> generatedToolRegistry =",
            f"    {dart_literal(registry, 2)};",
            "",
            "const Map<String, dynamic> generatedAgentDecisionSchema =",
            f"    {dart_literal(decision, 2)};",
            "",
        ]
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if generated Dart is stale")
    args = parser.parse_args()
    registry = load_json(TOOL_SCHEMA)
    decision = load_json(DECISION_SCHEMA)
    validate_contracts(registry, decision)
    rendered = render(registry, decision)
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="utf-8") != rendered:
            print(f"STALE: {OUTPUT.relative_to(ROOT)}", file=sys.stderr)
            return 1
        print(
            f"PASS: protocol contracts current; tools={len(registry['tools'])}; "
            f"digest={hashlib.sha256(rendered.encode()).hexdigest()[:16]}"
        )
        return 0
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(rendered, encoding="utf-8")
    print(f"generated {OUTPUT.relative_to(ROOT)} ({len(registry['tools'])} tools)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
