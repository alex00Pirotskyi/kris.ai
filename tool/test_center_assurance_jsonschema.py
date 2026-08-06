"""Small deterministic JSON Schema subset used by P8 source-contract validation."""
from __future__ import annotations

import json
import re
from datetime import datetime
from typing import Any


class SchemaValidationError(ValueError):
    pass


def _fail(message: str) -> None:
    raise SchemaValidationError(message)


def _object(value: Any, path: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        _fail(f"{path} must be an object")
    return value


def _pointer(document: dict[str, Any], pointer: str) -> Any:
    value: Any = document
    for raw in pointer.lstrip("/").split("/") if pointer else ():
        value = value[raw.replace("~1", "/").replace("~0", "~")]
    return value


def _resolve(ref: str, root: dict[str, Any], external: dict[str, dict[str, Any]]) -> tuple[dict[str, Any], dict[str, Any]]:
    if ref.startswith("#"):
        return _object(_pointer(root, ref[1:]), ref), root
    name, marker, pointer = ref.partition("#")
    if not marker or name not in external:
        _fail(f"unsupported schema reference: {ref}")
    target = external[name]
    return _object(_pointer(target, pointer), ref), target


def validate_instance(value: Any, schema: dict[str, Any], *, root: dict[str, Any], external: dict[str, dict[str, Any]] | None = None, path: str = "$") -> None:
    external = external or {}
    if "$ref" in schema:
        resolved, resolved_root = _resolve(str(schema["$ref"]), root, external)
        validate_instance(value, resolved, root=resolved_root, external=external, path=path)
        return
    for item in schema.get("allOf", []):
        validate_instance(value, _object(item, f"{path}.allOf"), root=root, external=external, path=path)
    if "const" in schema and value != schema["const"]:
        _fail(f"{path} must equal {schema['const']!r}")
    if "enum" in schema and value not in schema["enum"]:
        _fail(f"{path} has unknown value: {value!r}")
    expected = schema.get("type")
    if isinstance(expected, list):
        if value is None and "null" in expected:
            return
        expected = next((item for item in expected if item != "null"), None)
    if expected == "object":
        if not isinstance(value, dict):
            _fail(f"{path} must be an object")
        required = schema.get("required", [])
        missing = [name for name in required if name not in value]
        if missing:
            _fail(f"{path} missing required fields: {missing}")
        properties = schema.get("properties", {})
        additional = schema.get("additionalProperties")
        if additional is False:
            extra = sorted(set(value) - set(properties))
            if extra:
                _fail(f"{path} contains undeclared fields: {extra}")
        for key, child in value.items():
            child_schema = properties.get(key)
            if child_schema is None and isinstance(additional, dict):
                child_schema = additional
            if isinstance(child_schema, dict):
                validate_instance(child, child_schema, root=root, external=external, path=f"{path}.{key}")
    elif expected == "array":
        if not isinstance(value, list):
            _fail(f"{path} must be an array")
        if len(value) < int(schema.get("minItems", 0)):
            _fail(f"{path} has too few items")
        if "maxItems" in schema and len(value) > int(schema["maxItems"]):
            _fail(f"{path} has too many items")
        if schema.get("uniqueItems"):
            encoded = [json.dumps(item, sort_keys=True, separators=(",", ":")) for item in value]
            if len(encoded) != len(set(encoded)):
                _fail(f"{path} contains duplicate items")
        item_schema = schema.get("items")
        if isinstance(item_schema, dict):
            for index, child in enumerate(value):
                validate_instance(child, item_schema, root=root, external=external, path=f"{path}[{index}]")
    elif expected == "string":
        if not isinstance(value, str):
            _fail(f"{path} must be a string")
        if len(value) < int(schema.get("minLength", 0)):
            _fail(f"{path} is too short")
        pattern = schema.get("pattern")
        if pattern and re.fullmatch(str(pattern), value) is None:
            _fail(f"{path} does not match {pattern}")
        if schema.get("format") == "date-time":
            try:
                datetime.fromisoformat(value.replace("Z", "+00:00"))
            except ValueError as exc:
                raise SchemaValidationError(f"{path} is not a date-time") from exc
    elif expected == "integer":
        if not isinstance(value, int) or isinstance(value, bool):
            _fail(f"{path} must be an integer")
        if "minimum" in schema and value < schema["minimum"]:
            _fail(f"{path} is below minimum")
        if "maximum" in schema and value > schema["maximum"]:
            _fail(f"{path} is above maximum")
    elif expected == "number":
        if not isinstance(value, (int, float)) or isinstance(value, bool):
            _fail(f"{path} must be a number")
    elif expected == "boolean" and not isinstance(value, bool):
        _fail(f"{path} must be a boolean")
    elif expected == "null" and value is not None:
        _fail(f"{path} must be null")
