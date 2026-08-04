#!/usr/bin/env python3
"""Deterministic Dart single-quoted string literal encoding.

The schema generators embed canonical JSON as single-quoted Dart strings.
Backslash, quote, and dollar characters must be escaped for Dart source while
preserving the original runtime string value. In particular, JSON Schema keys
such as ``$id``, ``$schema``, ``$ref``, and JSONPath values beginning with ``$``
would otherwise be parsed as Dart interpolation.
"""
from __future__ import annotations


def dart_single_quoted_string(value: str) -> str:
    """Return *value* encoded for the body of a Dart single-quoted literal."""
    return (
        value.replace("\\", "\\\\")
        .replace("'", "\\'")
        .replace("$", "\\$")
        .replace("\r", "\\r")
        .replace("\n", "\\n")
        .replace("\u2028", "\\u2028")
        .replace("\u2029", "\\u2029")
    )
