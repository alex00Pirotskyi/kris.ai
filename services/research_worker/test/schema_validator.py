"""Dependency-free JSON Schema subset validator used only by P4-001 tests.

It is deliberately not a general schema engine. Unknown keywords and external
references fail closed so the reviewed contract subset cannot silently grow.
"""
from __future__ import annotations

import datetime as dt
import json
import math
import re
from dataclasses import dataclass
from typing import Any, Mapping, Sequence

from services.research_worker.src.search.validation import (
    SearchContractError,
    require_public_result_url,
)

DRAFT = "https://json-schema.org/draft/2020-12/schema"
KEYWORDS = {
    "$schema", "$id", "$ref", "$defs", "title", "description", "type",
    "additionalProperties", "required", "properties", "const", "enum",
    "minimum", "maximum", "minLength", "maxLength", "pattern", "format",
    "minItems", "maxItems", "uniqueItems", "items", "minProperties",
    "maxProperties", "oneOf", "allOf", "if", "then", "else",
}
TYPES = {"object", "array", "string", "integer", "number", "boolean", "null"}


@dataclass(frozen=True)
class SchemaValidationError:
    message: str
    absolute_path: tuple[Any, ...]


class ContractSchemaValidator:
    def __init__(self, schema: Mapping[str, Any]):
        validate_schema_document(schema)
        self.schema = schema

    def iter_errors(self, instance: Any):
        errors: list[SchemaValidationError] = []
        self._check(instance, self.schema, (), errors)
        return tuple(errors)

    def _check(self, value, schema, path, errors) -> None:
        if "$ref" in schema:
            self._check(value, _resolve(self.schema, schema["$ref"]), path, errors)
            return
        if "type" in schema and not _type_matches(value, schema["type"]):
            errors.append(SchemaValidationError(f"expected type {schema['type']!r}", path))
            return
        if "const" in schema and value != schema["const"]:
            errors.append(SchemaValidationError("constant mismatch", path))
        if "enum" in schema and value not in schema["enum"]:
            errors.append(SchemaValidationError("value is not in enum", path))
        if isinstance(value, str):
            self._string(value, schema, path, errors)
        elif isinstance(value, Mapping):
            self._object(value, schema, path, errors)
        elif isinstance(value, Sequence) and not isinstance(value, (str, bytes, bytearray)):
            self._array(value, schema, path, errors)
        elif _number(value):
            self._number(value, schema, path, errors)
        for branch in schema.get("allOf", ()):
            self._check(value, branch, path, errors)
        if "oneOf" in schema:
            matches = 0
            for branch in schema["oneOf"]:
                branch_errors: list[SchemaValidationError] = []
                self._check(value, branch, path, branch_errors)
                matches += not branch_errors
            if matches != 1:
                errors.append(SchemaValidationError(f"oneOf matched {matches} branches", path))
        if "if" in schema:
            condition: list[SchemaValidationError] = []
            self._check(value, schema["if"], path, condition)
            selected = schema.get("then") if not condition else schema.get("else")
            if selected is not None:
                self._check(value, selected, path, errors)

    @staticmethod
    def _string(value, schema, path, errors) -> None:
        if len(value) < schema.get("minLength", 0):
            errors.append(SchemaValidationError("string shorter than minLength", path))
        if len(value) > schema.get("maxLength", len(value)):
            errors.append(SchemaValidationError("string longer than maxLength", path))
        if "pattern" in schema and re.search(schema["pattern"], value) is None:
            errors.append(SchemaValidationError("string does not match pattern", path))
        format_name = schema.get("format")
        if format_name == "date-time" and not _date_time(value):
            errors.append(SchemaValidationError("invalid RFC3339 date-time", path))
        elif format_name == "public-result-url":
            try:
                require_public_result_url(value, "schema.url")
            except SearchContractError as exc:
                errors.append(SchemaValidationError(str(exc), path))

    def _object(self, value, schema, path, errors) -> None:
        for name in schema.get("required", ()):
            if name not in value:
                errors.append(SchemaValidationError(f"missing property {name!r}", path))
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            for name in value:
                if name not in properties:
                    errors.append(SchemaValidationError(f"unexpected property {name!r}", path + (name,)))
        if len(value) < schema.get("minProperties", 0):
            errors.append(SchemaValidationError("too few properties", path))
        if len(value) > schema.get("maxProperties", len(value)):
            errors.append(SchemaValidationError("too many properties", path))
        for name, child in value.items():
            if name in properties:
                self._check(child, properties[name], path + (name,), errors)

    def _array(self, value, schema, path, errors) -> None:
        if len(value) < schema.get("minItems", 0):
            errors.append(SchemaValidationError("too few items", path))
        if len(value) > schema.get("maxItems", len(value)):
            errors.append(SchemaValidationError("too many items", path))
        if schema.get("uniqueItems"):
            encoded = [json.dumps(item, sort_keys=True, ensure_ascii=False, allow_nan=False) for item in value]
            if len(encoded) != len(set(encoded)):
                errors.append(SchemaValidationError("items are not unique", path))
        if "items" in schema:
            for index, child in enumerate(value):
                self._check(child, schema["items"], path + (index,), errors)

    @staticmethod
    def _number(value, schema, path, errors) -> None:
        if isinstance(value, float) and not math.isfinite(value):
            errors.append(SchemaValidationError("number is not finite", path))
        elif value < schema.get("minimum", value):
            errors.append(SchemaValidationError("number below minimum", path))
        elif value > schema.get("maximum", value):
            errors.append(SchemaValidationError("number above maximum", path))


def validate_schema_document(schema: Mapping[str, Any]) -> None:
    if not isinstance(schema, Mapping) or schema.get("$schema") != DRAFT:
        raise ValueError("schema must declare Draft 2020-12")
    if not isinstance(schema.get("$id"), str) or not schema["$id"].startswith("https://"):
        raise ValueError("schema must declare an HTTPS $id")
    _inspect(schema, schema, ("$",))


def _inspect(node: Any, root: Mapping[str, Any], path: tuple[Any, ...]) -> None:
    if not isinstance(node, Mapping):
        raise ValueError(f"schema node {path!r} is not an object")
    unknown = set(node) - KEYWORDS
    if unknown:
        raise ValueError(f"unsupported keywords at {path!r}: {sorted(unknown)}")
    if "$ref" in node:
        if set(node) != {"$ref"}:
            raise ValueError(f"$ref has siblings at {path!r}")
        _resolve(root, node["$ref"])
        return
    declared = node.get("type")
    declared_types = [declared] if isinstance(declared, str) else declared
    if declared_types is not None and (
        not isinstance(declared_types, list) or not declared_types
        or any(item not in TYPES for item in declared_types)
    ):
        raise ValueError(f"invalid type at {path!r}")
    for name in ("required", "enum"):
        if name in node and not isinstance(node[name], list):
            raise ValueError(f"{name} at {path!r} is not an array")
    if len(node.get("required", ())) != len(set(node.get("required", ()))):
        raise ValueError(f"duplicate required entry at {path!r}")
    for group in ("properties", "$defs"):
        if group in node:
            if not isinstance(node[group], Mapping):
                raise ValueError(f"{group} at {path!r} is not an object")
            for name, child in node[group].items():
                _inspect(child, root, path + (group, name))
    if "items" in node:
        _inspect(node["items"], root, path + ("items",))
    for group in ("oneOf", "allOf"):
        if group in node:
            if not isinstance(node[group], list) or not node[group]:
                raise ValueError(f"{group} at {path!r} is empty")
            for index, child in enumerate(node[group]):
                _inspect(child, root, path + (group, index))
    for name in ("if", "then", "else"):
        if name in node:
            _inspect(node[name], root, path + (name,))
    if "pattern" in node:
        re.compile(node["pattern"])
    if "format" in node and node["format"] not in {
        "date-time",
        "public-result-url",
    }:
        raise ValueError(f"unsupported format at {path!r}")


def _resolve(root: Mapping[str, Any], ref: Any) -> Mapping[str, Any]:
    if not isinstance(ref, str) or not ref.startswith("#/"):
        raise ValueError("only local JSON Pointer references are supported")
    current: Any = root
    for raw in ref[2:].split("/"):
        token = raw.replace("~1", "/").replace("~0", "~")
        if not isinstance(current, Mapping) or token not in current:
            raise ValueError(f"unresolved reference {ref}")
        current = current[token]
    if not isinstance(current, Mapping):
        raise ValueError(f"reference {ref} is not an object")
    return current


def _type_matches(value: Any, declared: str | list[str]) -> bool:
    values = [declared] if isinstance(declared, str) else declared
    return any({
        "null": value is None,
        "boolean": isinstance(value, bool),
        "integer": isinstance(value, int) and not isinstance(value, bool),
        "number": _number(value),
        "string": isinstance(value, str),
        "object": isinstance(value, Mapping),
        "array": isinstance(value, Sequence) and not isinstance(value, (str, bytes, bytearray)),
    }[item] for item in values)


def _number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _date_time(value: str) -> bool:
    if not value.endswith("Z"):
        return False
    try:
        parsed = dt.datetime.fromisoformat(value[:-1] + "+00:00")
    except ValueError:
        return False
    return parsed.utcoffset() == dt.timedelta(0)
