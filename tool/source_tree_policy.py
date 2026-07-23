#!/usr/bin/env python3
"""Shared source-tree filtering for validation, scanning, and packaging.

Flutter and native build tools intentionally create generated state inside some
platform directories. Those files are useful on a workstation but are not
source inputs and must not make source validation fail or enter a release ZIP.
"""
from __future__ import annotations

from pathlib import PurePath

_GENERATED_DIRECTORY_NAMES = {
    ".dart_tool",
    ".git",
    ".gradle",
    ".idea",
    ".plugin_symlinks",
    ".vscode",
    "__pycache__",
    "build",
    "coverage",
    "dist",
    "node_modules",
    "pods",
}

_GENERATED_PREFIXES = (
    ("windows", "flutter", "ephemeral"),
    ("linux", "flutter", "ephemeral"),
    ("macos", "flutter", "ephemeral"),
    ("ios", "flutter", "ephemeral"),
    ("android", ".cxx"),
)

_GENERATED_FILE_NAMES = {
    ".flutter-plugins",
    ".flutter-plugins-dependencies",
    "flutter_export_environment.sh",
    "generated.xcconfig",
}


def is_generated_path(relative: PurePath | str) -> bool:
    """Return True for reproducible, tool-generated workstation state."""
    path = PurePath(relative)
    parts = tuple(part.lower() for part in path.parts)
    if not parts:
        return False
    if any(part in _GENERATED_DIRECTORY_NAMES for part in parts):
        return True
    if parts[-1] in _GENERATED_FILE_NAMES:
        return True
    return any(parts[: len(prefix)] == prefix for prefix in _GENERATED_PREFIXES)
