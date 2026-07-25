#!/usr/bin/env python3
"""Shared generated-state policy for validation, scanning, packaging, and CI.

The policy distinguishes reproducible workstation/runtime output from source
inputs. Generated Dart contract files under ``lib/product/generated`` remain
source inputs because they are intentionally reviewed and committed; this
module only classifies disposable state.
"""
from __future__ import annotations

from pathlib import PurePath, PurePosixPath
import re
from typing import Iterable

GENERATED_STATE_POLICY_VERSION = "2.0.0"
GITIGNORE_BEGIN = "# BEGIN KRISTIN GENERATED STATE POLICY v2"
GITIGNORE_END = "# END KRISTIN GENERATED STATE POLICY v2"

_GENERATED_DIRECTORY_NAMES = frozenset(
    {
        ".dart_tool",
        ".git",
        ".gradle",
        ".idea",
        ".mypy_cache",
        ".npm",
        ".playwright",
        ".plugin_symlinks",
        ".pnpm-store",
        ".pub",
        ".pub-cache",
        ".pytest_cache",
        ".ruff_cache",
        ".vscode",
        "__pycache__",
        "browser-data",
        "browser-downloads",
        "browser-profiles",
        "browser-traces",
        "build",
        "coverage",
        "dist",
        "htmlcov",
        "node_modules",
        "playwright-report",
        "pods",
        "test-results",
    }
)

_GENERATED_PREFIXES = (
    ("windows", "flutter", "ephemeral"),
    ("linux", "flutter", "ephemeral"),
    ("macos", "flutter", "ephemeral"),
    ("ios", "flutter", "ephemeral"),
    ("android", ".cxx"),
    ("android", ".gradle"),
    ("ios", "pods"),
    ("macos", "pods"),
    ("services", "automation_host", "dist"),
    ("services", "automation_host", ".cache"),
    ("datasets", ".build"),
    ("release", "evidence", "generated"),
    ("release", "reports", "generated"),
    (".yarn", "cache"),
    (".yarn", "unplugged"),
)

_GENERATED_FILE_NAMES = frozenset(
    {
        ".coverage",
        ".ds_store",
        ".flutter",
        ".flutter-plugins",
        ".flutter-plugins-dependencies",
        ".flutter_tool_state",
        ".packages",
        "desktop.ini",
        "flutter_export_environment.sh",
        "generated.xcconfig",
        "lcov.info",
        "thumbs.db",
    }
)

_GENERATED_SUFFIXES = (".pyc", ".pyo")

_GENERATED_PATH_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "timestamped-test-report",
        re.compile(
            r"^reports/kristin-test-(?:system|release)-[0-9]{8}-[0-9]{6}\.(?:json|md)$"
        ),
    ),
    (
        "release-generated-report",
        re.compile(
            r"^release/(?:"
            r"secret_scan\.json|"
            r"sbom\.cdx\.json|"
            r"validation_report\.json|"
            r"validation_report\.md|"
            r"project_manager_v2_results\.json|"
            r"execution_intelligence_results\.json|"
            r"prompt_studio_v2_results\.json|"
            r"architecture_contract_results\.(?:json|md)|"
            r"assurance_report\.(?:json|md)|"
            r"current_status\.json"
            r")$"
        ),
    ),
    (
        "release-transient-log",
        re.compile(r"^release/[^/]+(?:_console\.log|\.exit|\.log)$"),
    ),
    (
        "yarn-install-state",
        re.compile(r"^\.yarn/(?:build-state\.yml|install-state\.gz)$"),
    ),
)

_GITIGNORE_PATTERNS = (
    "# Python",
    "**/__pycache__/",
    "*.py[cod]",
    "*$py.class",
    ".pytest_cache/",
    ".mypy_cache/",
    ".ruff_cache/",
    ".coverage",
    "htmlcov/",
    "",
    "# Flutter, Dart, and native build state",
    ".dart_tool/",
    ".packages",
    ".pub/",
    ".pub-cache/",
    "build/",
    "coverage/",
    ".flutter",
    ".flutter_tool_state",
    ".flutter-plugins",
    ".flutter-plugins-dependencies",
    "**/.plugin_symlinks/",
    "**/flutter/ephemeral/",
    "android/.cxx/",
    "android/.gradle/",
    "ios/Pods/",
    "macos/Pods/",
    "",
    "# Node, browser automation, and Web Studio runtime state",
    "node_modules/",
    ".npm/",
    ".pnpm-store/",
    ".yarn/cache/",
    ".yarn/unplugged/",
    ".yarn/build-state.yml",
    ".yarn/install-state.gz",
    ".playwright/",
    "playwright-report/",
    "test-results/",
    "browser-data/",
    "browser-profiles/",
    "browser-downloads/",
    "browser-traces/",
    "services/automation_host/dist/",
    "services/automation_host/.cache/",
    "",
    "# Dataset and generated evidence intermediates",
    "datasets/.build/",
    "release/evidence/generated/",
    "release/reports/generated/",
    "",
    "# Reproducible reports emitted by standard verification",
    "reports/kristin-test-*.json",
    "reports/kristin-test-*.md",
    "release/SECRET_SCAN.json",
    "release/SBOM.cdx.json",
    "release/VALIDATION_REPORT.md",
    "release/validation_report.json",
    "release/PROJECT_MANAGER_V2_RESULTS.json",
    "release/EXECUTION_INTELLIGENCE_RESULTS.json",
    "release/PROMPT_STUDIO_V2_RESULTS.json",
    "release/ARCHITECTURE_CONTRACT_RESULTS.json",
    "release/ARCHITECTURE_CONTRACT_RESULTS.md",
    "release/ASSURANCE_REPORT.json",
    "release/ASSURANCE_REPORT.md",
    "release/CURRENT_STATUS.json",
    "release/*.log",
    "release/*.exit",
    "release/*_console.log",
    "",
    "# IDE and operating-system state",
    ".idea/",
    ".vscode/",
    "*.iml",
    ".DS_Store",
    "Thumbs.db",
    "Desktop.ini",
)


def _normalized_parts(relative: PurePath | str) -> tuple[str, ...]:
    raw = str(relative).replace("\\", "/").strip()
    while raw.startswith("./"):
        raw = raw[2:]
    raw = re.sub(r"/+", "/", raw)
    if raw in {"", "."}:
        return ()
    return tuple(
        part.lower()
        for part in PurePosixPath(raw).parts
        if part not in {"", "."}
    )


def normalized_relative_path(relative: PurePath | str) -> str:
    """Return the policy's canonical slash-separated, case-folded path."""
    return "/".join(_normalized_parts(relative))


def generated_path_reason(relative: PurePath | str) -> str | None:
    """Return a stable reason when *relative* is disposable generated state."""
    parts = _normalized_parts(relative)
    if not parts:
        return None
    normalized = "/".join(parts)
    for part in parts:
        if part in _GENERATED_DIRECTORY_NAMES:
            return f"directory:{part}"
    if parts[-1] in _GENERATED_FILE_NAMES:
        return f"file:{parts[-1]}"
    if parts[-1].endswith(_GENERATED_SUFFIXES):
        return "python-bytecode"
    for prefix in _GENERATED_PREFIXES:
        if parts[: len(prefix)] == prefix:
            return "prefix:" + "/".join(prefix)
    for label, pattern in _GENERATED_PATH_PATTERNS:
        if pattern.fullmatch(normalized):
            return f"pattern:{label}"
    return None


def is_generated_path(relative: PurePath | str) -> bool:
    """Return ``True`` for reproducible, disposable workstation state."""
    return generated_path_reason(relative) is not None


def gitignore_block() -> str:
    """Return the canonical managed block appended to ``.gitignore``."""
    return "\n".join((GITIGNORE_BEGIN, *_GITIGNORE_PATTERNS, GITIGNORE_END, ""))


def representative_generated_paths() -> tuple[str, ...]:
    return (
        ".flutter",
        ".flutter_tool_state",
        "tool/__pycache__/source_tree_policy.cpython-313.pyc",
        ".dart_tool/package_config.json",
        "windows/flutter/ephemeral/flutter_windows.dll",
        "android/.cxx/debug/state",
        "node_modules/pkg/index.js",
        ".playwright/browser/chromium",
        "playwright-report/index.html",
        "test-results/run.json",
        "browser-profiles/personal/Default/Cookies",
        "browser-traces/run.zip",
        "services/automation_host/.cache/state",
        "services/automation_host/dist/index.js",
        "datasets/.build/intermediate.jsonl",
        "release/evidence/generated/transient.json",
        "reports/kristin-test-system-20260724-010203.json",
        "release/SECRET_SCAN.json",
        "release/validation_report.json",
    )


def representative_source_paths() -> tuple[str, ...]:
    return (
        ".metadata",
        "pubspec.lock",
        "lib/product/generated/v190_contracts.g.dart",
        "docs/roadmap/MASTER.md",
        "release/evidence/P0-009/manifest.json",
        "evals/results/p0_009_baseline.json",
        "schemas/tool_registry.v2.json",
        "services/automation_host/src/index.ts",
    )


def all_gitignore_patterns() -> tuple[str, ...]:
    return tuple(line for line in _GITIGNORE_PATTERNS if line and not line.startswith("#"))


def classify_many(paths: Iterable[PurePath | str]) -> dict[str, str | None]:
    return {str(path): generated_path_reason(path) for path in paths}
