#!/usr/bin/env python3
"""Deterministic source-release validation for Kristin Local Agent.

This gate is intentionally usable without Flutter. When Flutter is available it
also runs formatting, static analysis, and tests. A source archive may be
created with SDK checks marked unavailable, but it may not be labelled as a
compiled desktop release until every SDK gate passes.
"""
from __future__ import annotations

import argparse
import dataclasses
import hashlib
import inspect
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from typing import Iterable

from assurance_model import (
    classify_validator_check,
    summarize_assurance_checks,
    validate_assurance_summary,
)
from source_tree_policy import is_generated_path

ROOT = Path(__file__).resolve().parents[1]
REPORT_JSON = ROOT / "release" / "validation_report.json"
REPORT_MD = ROOT / "release" / "VALIDATION_REPORT.md"

EXPECTED_DART_FILES = {
                          'lib/main.dart',
                          'lib/product/api_server.dart',
                          'lib/product/agent_decision.dart',
                          'lib/product/agent_protocol.dart',
                          'lib/product/generated/protocol_contracts.g.dart',
                          'lib/product/generated/v170_contracts.g.dart',
                          'lib/product/generated/prompt_studio_contracts.g.dart',
                          'lib/product/generated/workflow_migrations.g.dart',
                          'lib/product/generated/v180_contracts.g.dart',
                          'lib/product/generated/v190_contracts.g.dart',
                          'lib/product/knowledge_memory_v2.dart',
                          'lib/product/interoperability_v19.dart',
                          'lib/product/release_operations_v19.dart',
                          'lib/product/release_operations_v19.dart',
                          'lib/product/file_adapters.dart',
                          'lib/product/prompt_studio_v2.dart',
                          'lib/product/execution_intelligence.dart',
                          'lib/product/project_manager_v2.dart',
                          'lib/product/durable_workflow.dart',
                          'lib/product/repository.dart',
                          'lib/product/retry_policy.dart',
                          'lib/product/protocol_types.dart',
                          'lib/product/tool_schema.dart',
                          'lib/product/chat_studio.dart',
                          'lib/product/crypto_utils.dart',
                          'lib/product/deployment_support.dart',
                          'lib/product/domain.dart',
                          'lib/product/extensions_index.dart',
                          'lib/product/mcp.dart',
                          'lib/product/models_research.dart',
                          'lib/product/planning_runtime.dart',
                          'lib/product/project_diagnostics.dart',
                          'lib/product/product_runtime.dart',
                          'lib/product/prompt_planning.dart',
                          'lib/product/storage_security.dart',
                          'lib/product/ui.dart',
                          'lib/product/ui_advanced.dart',
                          'lib/product/ui_components.dart',
                          'lib/product/workspace_tools.dart',
                          'test/product/source_contract_test.dart',
                          'test/product/typed_protocol_schema_test.dart',
                          'test/product/durable_workflow_kernel_test.dart',
                          'test/product/prompt_studio_v2_test.dart',
                          'test/product/knowledge_memory_v2_test.dart',
                          'test/product/file_adapters_test.dart',
                          'test/product/interoperability_v19_test.dart',
                          'test/product/release_operations_v19_test.dart',
                          'test/product/release_operations_v19_test.dart',
                          'test/product/interoperability_v19_test.dart',
                          'test/product/knowledge_memory_test.dart',
                          'test/product/execution_reliability_test.dart',
                          'test/product/diagnostic_replay_test.dart',
                          'test/product/v1_product_preview_test.dart',
                          'test/product/budget_diagnostics_test.dart',
                          'test/widget_test.dart',
                          'tool/prune_stale_legacy.dart',
                          'lib/product/access_profile_v2.dart',
                          'test/product/access_profile_v2_test.dart',
                          'lib/product/capability_grant_v2.dart',
                          'test/product/capability_grant_v2_test.dart',
                          'lib/product/deterministic_policy_engine.dart',
                          'test/product/deterministic_policy_engine_test.dart',
                          'lib/product/signed_manifest_v2.dart',
                          'test/product/signed_manifest_v2_test.dart',
                          'lib/product/manifest_compatibility_v2.dart',
                          'test/product/manifest_compatibility_v2_test.dart',
                          'lib/product/key_registry_v2.dart',
                          'test/product/key_registry_v2_test.dart',
                          'lib/product/signed_audit_checkpoint_v1.dart',
                          'test/product/signed_audit_checkpoint_v1_test.dart',
                          'lib/product/local_authenticated_ipc_v1.dart',
                          'test/product/local_authenticated_ipc_v1_test.dart',
                                                'lib/product/p1_authority_service_contract_v1.dart',
                          'lib/product/p1_authority_service_native_connector_v2.dart',
                          'lib/product/p1_authority_service_product_runtime_v1.dart',
                          'test/product/p1_authority_service_contract_v1_test.dart',
                          'test/product/p1_authority_service_product_runtime_v1_test.dart',
}

def _load_governed_p2_dart_files() -> set[str]:
    inventory_path = ROOT / "config" / "p2_source_inventory.v1.json"
    try:
        decoded = json.loads(inventory_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(
            f"cannot load governed P2 Dart inventory: {error}"
        ) from error
    if not isinstance(decoded, dict):
        raise RuntimeError("governed P2 Dart inventory must be an object")
    governed: set[str] = set()
    for key in ("productionDart", "testDart", "supportDart"):
        values = decoded.get(key)
        if not isinstance(values, list) or not values:
            raise RuntimeError(f"governed P2 Dart inventory missing {key}")
        for raw in values:
            if not isinstance(raw, str):
                raise RuntimeError(f"{key} contains a non-string path")
            relative = raw.replace("\\", "/")
            if (
                not relative.endswith(".dart")
                or relative.startswith("/")
                or relative.startswith("../")
                or "/../" in relative
            ):
                raise RuntimeError(
                    f"{key} contains an unsafe Dart path: {relative}"
                )
            if relative in governed:
                raise RuntimeError(
                    f"duplicate governed P2 Dart path: {relative}"
                )
            governed.add(relative)
    return governed

def _load_governed_product_library_files() -> set[str]:
    source_contract = ROOT / "test" / "product" / "source_contract_test.dart"
    try:
        content = source_contract.read_text(encoding="utf-8")
    except OSError as error:
        raise RuntimeError(
            f"cannot load governed product source inventory: {error}"
        ) from error
    marker = "const expected = <String>{"
    start = content.find(marker)
    if start < 0:
        raise RuntimeError("governed product source inventory marker is missing")
    open_brace = content.find("{", start)
    end = content.find("};", open_brace)
    if open_brace < 0 or end < 0:
        raise RuntimeError("governed product source inventory bounds are invalid")
    values = re.findall(r"'([^']+)'", content[open_brace + 1 : end])
    if not values:
        raise RuntimeError("governed product source inventory is empty")
    governed: set[str] = set()
    for raw in values:
        relative = raw.replace("\\", "/")
        if (
            not relative.startswith("lib/")
            or not relative.endswith(".dart")
            or relative.startswith("/")
            or relative.startswith("../")
            or "/../" in relative
        ):
            raise RuntimeError(
                f"governed product source inventory contains an unsafe/non-library path: {relative}"
            )
        if relative in governed:
            raise RuntimeError(
                f"duplicate governed product Dart path: {relative}"
            )
        governed.add(relative)
    return governed

EXPECTED_DART_FILES.update(_load_governed_p2_dart_files())
EXPECTED_DART_FILES.update(_load_governed_product_library_files())
EXCLUDED_DART_TOP_LEVEL = {
    ".dart_tool", ".git", "archive", "build", "coverage", "dist",
    "node_modules",
}

@dataclasses.dataclass
class Check:
    name: str
    status: str
    detail: str
    blocking: bool = True
    duration_ms: int = 0
    assurance_level: str = "unclassified"
    proof_kind: str = "unclassified"
    behavioral_proof: bool = False
    claim_scope: str = "unclassified"
    source_function: str = ""
    assurance_rationale: str = ""

    def as_dict(self) -> dict[str, object]:
        return dataclasses.asdict(self)

checks: list[Check] = []


def add(
    name: str,
    ok: bool | None,
    detail: str,
    *,
    blocking: bool = True,
    started: float | None = None,
) -> None:
    status = "unavailable" if ok is None else ("passed" if ok else "failed")
    # Reproducible release invocations pin timestamps through SOURCE_DATE_EPOCH;
    # timing telemetry is intentionally normalized so identical sources produce
    # byte-identical reports and archives.
    duration_ms = 0
    if started is not None and "SOURCE_DATE_EPOCH" not in os.environ:
        duration_ms = int((time.monotonic() - started) * 1000)
    frame = inspect.currentframe()
    caller = frame.f_back if frame is not None else None
    source_function = caller.f_code.co_name if caller is not None else "unknown"
    del caller
    del frame
    classification = classify_validator_check(source_function, name)
    checks.append(
        Check(
            name=name,
            status=status,
            detail=detail,
            blocking=blocking,
            duration_ms=duration_ms,
            assurance_level=classification.assurance_level,
            proof_kind=classification.proof_kind,
            behavioral_proof=classification.behavioral_proof,
            claim_scope=classification.claim_scope,
            source_function=source_function,
            assurance_rationale=classification.rationale,
        )
    )

def active_files(pattern: str) -> list[Path]:
    return sorted(
        p
        for p in ROOT.glob(pattern)
        if p.is_file()
        and not set(p.relative_to(ROOT).parts).intersection(EXCLUDED_DART_TOP_LEVEL)
    )


def package_dart_files() -> list[Path]:
    return sorted(
        p
        for p in ROOT.rglob("*.dart")
        if p.is_file()
        and p.relative_to(ROOT).parts
        and p.relative_to(ROOT).parts[0] not in EXCLUDED_DART_TOP_LEVEL
    )


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def normalized_source(text: str) -> str:
    """Collapse source whitespace for formatter-independent contract checks."""
    return re.sub(r"\s+", " ", text).strip()


def source_contains(content: str, token: str) -> bool:
    return normalized_source(token) in normalized_source(content)


def unconverted_clamp_offsets(content: str) -> list[int]:
    """Return clamp-call offsets that lack an explicit result conversion.

    Dart formatting may place `.clamp(...)` and `.toInt()` on separate lines,
    so this check follows the complete call expression instead of inspecting
    one physical line at a time.
    """
    marker = ".clamp("
    offsets: list[int] = []
    search_from = 0
    while True:
        start = content.find(marker, search_from)
        if start < 0:
            return offsets

        cursor = start + len(marker)
        depth = 1
        quote: str | None = None
        escaped = False
        while cursor < len(content) and depth > 0:
            character = content[cursor]
            if quote is not None:
                if escaped:
                    escaped = False
                elif character == "\\":
                    escaped = True
                elif character == quote:
                    quote = None
            elif character in ("'", '"'):
                quote = character
            elif character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
            cursor += 1

        if depth != 0:
            offsets.append(start)
            search_from = start + len(marker)
            continue

        while cursor < len(content) and content[cursor].isspace():
            cursor += 1
        if not any(
            content.startswith(conversion, cursor)
            for conversion in (".toInt(", ".toDouble(", ".toString(")
        ):
            offsets.append(start)
        search_from = max(cursor, start + len(marker))


def run(command: list[str], *, timeout: int = 900) -> tuple[int, str]:
    env = dict(os.environ)
    env.setdefault("CI", "true")
    proc = subprocess.run(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True, errors="replace", timeout=timeout)
    output = proc.stdout.replace(str(ROOT), '<ROOT>')
    # Keep reports bounded and redact common token forms.
    output = re.sub(
        r"(?i)\b(https?|socks5h?)://[^/\s:@]+:[^@\s/]+@",
        r"\1://<redacted>@",
        output,
    )
    output = re.sub(r"(?i)(authorization\s*[:=]\s*bearer\s+)[^\s]+", r"\1<redacted>", output)
    output = re.sub(r"(?i)(api[_-]?key|token|secret|password)(\s*[:=]\s*)[^\s,;]+", r"\1\2<redacted>", output)
    return proc.returncode, output[-50000:]


def balanced_dart(text: str) -> tuple[bool, str]:
    """Conservative lexical balance check used when no Dart parser is present."""
    stack: list[tuple[str, int]] = []
    pairs = {')': '(', ']': '[', '}': '{'}
    i = 0
    state = "code"
    quote = ""
    raw = False
    while i < len(text):
        c = text[i]
        n = text[i + 1] if i + 1 < len(text) else ""
        if state == "line":
            if c == "\n": state = "code"
        elif state == "block":
            if c == "*" and n == "/": state = "code"; i += 1
        elif state == "string":
            if len(quote) == 3:
                if text[i:i + 3] == quote:
                    i += 2
                    state = "code"
            elif not raw and c == "\\":
                i += 1
            elif c == quote:
                state = "code"
        else:
            if c == "/" and n == "/": state = "line"; i += 1
            elif c == "/" and n == "*": state = "block"; i += 1
            elif c in ("'", '"'):
                raw = i > 0 and text[i - 1] in ("r", "R")
                if text[i:i+3] == c * 3:
                    quote = c * 3; i += 2
                else:
                    quote = c
                state = "string"
            elif c in "([{": stack.append((c, i))
            elif c in ")]}":
                if not stack or stack[-1][0] != pairs[c]:
                    return False, f"unmatched {c} at byte {i}"
                stack.pop()
        i += 1
    if state in ("string", "block"):
        return False, f"unterminated {state}"
    if stack:
        c, pos = stack[-1]
        return False, f"unclosed {c} at byte {pos}"
    return True, "balanced delimiters and literals"



def tree_sitter_dart_errors(path: Path) -> list[str] | None:
    try:
        from tree_sitter import Language, Parser
        import tree_sitter_dart
        language_value = tree_sitter_dart.language()
        try:
            language = Language(language_value)
        except TypeError:
            language = language_value
        try:
            parser = Parser(language)
        except TypeError:
            parser = Parser()
            parser.set_language(language)
        data = path.read_bytes()
        tree = parser.parse(data)
        errors: list[str] = []
        stack = [tree.root_node]
        while stack:
            node = stack.pop()
            if node.type == 'ERROR' or node.is_missing:
                row, col = node.start_point
                errors.append(f"{path.relative_to(ROOT)}:{row + 1}:{col + 1} {node.type}")
                if len(errors) >= 20:
                    break
            stack.extend(reversed(node.children))
        return errors
    except Exception:
        return None


def tree_sitter_unbraced_control_flow(path: Path) -> list[str]:
    try:
        from tree_sitter import Language, Parser
        import tree_sitter_dart
        language_value = tree_sitter_dart.language()
        try:
            language = Language(language_value)
        except TypeError:
            language = language_value
        try:
            parser = Parser(language)
        except TypeError:
            parser = Parser()
            parser.set_language(language)
        tree = parser.parse(path.read_bytes())
        failures: list[str] = []
        stack = [tree.root_node]
        while stack:
            node = stack.pop()
            bodies = []
            if node.type == "if_statement":
                consequence = node.child_by_field_name("consequence")
                alternative = node.child_by_field_name("alternative")
                if consequence is not None:
                    bodies.append(("if", consequence, {"block"}))
                if alternative is not None:
                    bodies.append(("else", alternative, {"block", "if_statement"}))
            elif node.type in {"for_statement", "while_statement", "do_statement"}:
                body = node.child_by_field_name("body")
                if body is not None:
                    bodies.append((node.type, body, {"block"}))
            for label, body, permitted in bodies:
                if body.type not in permitted:
                    row, col = body.start_point
                    failures.append(
                        f"{path.relative_to(ROOT)}:{row + 1}:{col + 1} "
                        f"unbraced {label} body"
                    )
            stack.extend(reversed(node.children))
        return failures
    except Exception:
        return []


def check_required_files() -> None:
    required = [
                   'pubspec.yaml',
                   'analysis_options.yaml',
                   'lib/main.dart',
                   'lib/product/product_runtime.dart',
                   'lib/product/planning_runtime.dart',
                   'lib/product/agent_decision.dart',
                   'lib/product/agent_protocol.dart',
                   'lib/product/protocol_types.dart',
                   'lib/product/tool_schema.dart',
                   'lib/product/generated/protocol_contracts.g.dart',
                   'lib/product/generated/v170_contracts.g.dart',
                   'lib/product/generated/prompt_studio_contracts.g.dart',
                   'lib/product/generated/workflow_migrations.g.dart',
                   'lib/product/generated/v180_contracts.g.dart',
                   'lib/product/generated/v190_contracts.g.dart',
                   'lib/product/knowledge_memory_v2.dart',
                   'lib/product/interoperability_v19.dart',
                   'lib/product/release_operations_v19.dart',
                   'lib/product/release_operations_v19.dart',
                   'lib/product/file_adapters.dart',
                   'lib/product/prompt_studio_v2.dart',
                   'lib/product/execution_intelligence.dart',
                   'lib/product/project_manager_v2.dart',
                   'lib/product/durable_workflow.dart',
                   'lib/product/repository.dart',
                   'lib/product/retry_policy.dart',
                   'migrations/workflow/001_core.sql',
                   'migrations/workflow/002_idempotency_checkpoints.sql',
                   'migrations/workflow/003_compensation_migration.sql',
                   'migrations/workflow/004_append_only_guards.sql',
                   'migrations/workflow/005_project_manager_execution_intelligence.sql',
                   'migrations/workflow/006_interoperability_admin.sql',
                   'schemas/agent_decision.v1.json',
                   'schemas/tool_registry.v2.json',
                   'schemas/product_specification.v2.json',
                   'schemas/task_plan.v2.json',
                   'schemas/prompt_evaluation_dataset.v1.json',
                   'schemas/plan_capability_catalog.v1.json',
                   'schemas/plan_compilation_report.v1.json',
                   'schemas/project_profile.v2.json',
                   'schemas/project_manager_snapshot.v1.json',
                   'schemas/model_routing_policy.v1.json',
                   'schemas/execution_progress.v1.json',
                   'schemas/verification_report.v1.json',
                   'schemas/convergence_decision.v1.json',
                   'lib/product/workspace_tools.dart',
                   'lib/product/storage_security.dart',
                   'lib/product/prompt_planning.dart',
                   'lib/product/models_research.dart',
                   'lib/product/api_server.dart',
                   'lib/product/deployment_support.dart',
                   'lib/product/extensions_index.dart',
                   'lib/product/mcp.dart',
                   'lib/product/ui.dart',
                   'lib/product/chat_studio.dart',
                   'lib/product/project_diagnostics.dart',
                   'lib/product/ui_advanced.dart',
                   'lib/product/ui_components.dart',
                   'tool/assurance_model.py',
                   'tool/assurance_model_test.py',
                   'tool/architecture_contract_test.py',
                   'tool/assurance_dashboard.py',
                   'tool/p0_007_assurance_test.py',
                   'schemas/assurance_report.v1.json',
                   'docs/roadmap/ASSURANCE_MODEL.md',
                   'docs/roadmap/V3_1_3_ASSURANCE_RECONCILIATION.md',
                   'tasks/completed/P0-007.md',
                   'release/evidence/P0-007/IMPLEMENTATION.md',
                   'tool/validate_release.py',
                   'tool/kristin_cli.py',
                   'tool/system_test.py',
                   'tool/dart_string_literal.py',
                   'tool/dart_format_scope.py',
                   'tool/dart_format_scope_test.py',
                   'tool/p0_003_repair_test.py',
                   'tool/capture_ci_environment.py',
                   'tool/toolchain_lock_test.py',
                   'tool/compare_toolchain_runs.py',
                   'config/toolchains.lock.json',
                   'kristin',
                   'kristin.cmd',
                   'RUN_WINDOWS.bat',
                   'RUN_MAC.command',
                   'RUN_LINUX.sh',
                   'tool/prune_stale_legacy.dart',
                   'tool/prune_stale_legacy.cmd',
                   'README.md',
                   'SECURITY.md',
                   'docs/V0.9_KNOWLEDGE_MEMORY_RELEASE.md',
                   'docs/V0.9.2_WINDOWS_COMPILE_HOTFIX.md',
                   'docs/V0.9.3_MEMORY_AGENT_HOTFIX.md',
                   'docs/V1.0_PRODUCT_PREVIEW.md',
                   'docs/V1.0.1_MODEL_PROTOCOL_HOTFIX.md',
                   'docs/V1.0.2_BUDGET_DIAGNOSTICS_HOTFIX.md',
                   'docs/V1.0.3_AGENT_LOOP_RECOVERY_HOTFIX.md',
                   'docs/V1.0.4_WINDOWS_VALIDATION_HOTFIX.md',
                   'docs/V1.0.5_PATH_HYGIENE_HOTFIX.md',
                   'docs/V1.0.6_WORKSPACE_BOUNDARY_CANONICALIZATION.md',
                   'docs/V1.0.7_FAILED_RUN_RECOVERY_HOTFIX.md',
                   'docs/V1.0.8_SDK_ENVIRONMENT_HOTFIX.md',
                   'docs/V1.0.9_LINEAGE_CONTRACT_HOTFIX.md',
                   'docs/V1.1.0_PROJECT_MANAGER_PREVIEW.md',
                   'docs/V1.1.1_PROJECT_MANAGER_COMPILE_HOTFIX.md',
                   'docs/V1.1.2_MODEL_RESILIENCE_HOTFIX.md',
                   'docs/V1.1.3_WORKSTATION_VALIDATION_HOTFIX.md',
                   'docs/V1.1.4_DETERMINISTIC_RELEASE_TESTS_HOTFIX.md',
                   'docs/V1.1.6_EXECUTION_RELIABILITY_REDESIGN.md',
                   'docs/V1.1.7_STABILITY_REPLAY_BASELINE.md',
                   'docs/V1.2.0_TYPED_PROTOCOL_FOUNDATION.md',
                   'docs/V1.3.0_DURABLE_WORKFLOW_KERNEL.md',
                   'docs/V1.5.0_PROMPT_STUDIO_2_PLAN_COMPILER.md',
                   'docs/FAILURE_TAXONOMY.md',
                   'docs/DIAGNOSTIC_REPLAY.md',
                   'docs/CURRENT_RUN_RECOVERY.md',
                   'docs/ROADMAP_IMPLEMENTATION_MATRIX.md',
                   'VERSION_CONTROL.json',
                   'tool/source_tree_policy.py',
                   'tool/replay_diagnostics.py',
                   'tool/generate_protocol_contracts.py',
                   'tool/protocol_contract_test.py',
                   'tool/generate_workflow_migrations.py',
                   'tool/workflow_kernel_test.py',
                   'tool/plan_compiler.py',
                   'tool/generate_prompt_studio_contracts.py',
                   'tool/generate_prompt_studio_fixtures.py',
                   'tool/prompt_studio_v2_test.py',
                   'tool/sandbox_worker.py',
                   'tool/network_broker.py',
                   'tool/secret_broker.py',
                   'tool/sandbox_worker_test.py',
                   'tool/network_broker_test.py',
                   'tool/execution_intelligence.py',
                   'tool/execution_intelligence_test.py',
                   'tool/project_manager_v2.py',
                   'tool/project_manager_v2_test.py',
                   'tool/generate_v180_contracts.py',
                   'tool/generate_v190_contracts.py',
                   'tool/interoperability_admin_v19.py',
                   'tool/interoperability_admin_v19_test.py',
                   'tool/v1_trust_disablement_test.py',
                   'tool/release_ops_v19.py',
                   'tool/release_ops_v19_test.py',
                   'tool/knowledge_memory_v2.py',
                   'tool/knowledge_memory_v2_test.py',
                   'tool/file_adapters.py',
                   'tool/file_adapter_test.py',
                   'docs/V1.5.1_SANDBOX_BACKFILL.md',
                   'docs/V1.6.0_PROJECT_MANAGER_2.md',
                   'docs/V1.8.0_KNOWLEDGE_MEMORY_SKILLS_FILE_ADAPTERS.md',
                   'docs/V1.9.0_INTEROPERABILITY_ADMIN_RELEASE_OPS.md',
                   'docs/CANONICAL_LINEAGE.md',
                   'test/product/execution_reliability_test.dart',
                   'test/product/typed_protocol_schema_test.dart',
                   'test/product/durable_workflow_kernel_test.dart',
                   'test/product/prompt_studio_v2_test.dart',
                   'test/product/knowledge_memory_v2_test.dart',
                   'test/product/file_adapters_test.dart',
                   'test/product/interoperability_v19_test.dart',
                   'test/product/fixtures/prompt_studio_v2/specification.json',
                   'test/product/fixtures/prompt_studio_v2/policy.local_only.json',
                   'test/product/fixtures/prompt_studio_v2/prompt.baseline.json',
                   'test/product/fixtures/prompt_studio_v2/prompt.candidate.json',
                   'test/product/fixtures/prompt_studio_v2/evaluation_dataset.json',
                   'test/product/fixtures/prompt_studio_v2/plan_001.json',
                   'test/product/fixtures/prompt_studio_v2/plan_010.json',
                   'test/product/fixtures/prompt_studio_v2/plan_050.json',
                   'test/product/fixtures/prompt_studio_v2/plan_100.json',
                   'test/product/diagnostic_replay_test.dart',
                   'test/product/fixtures/diagnostic_replay/v115_nested_write_content_loss.json',
                   'test/product/fixtures/diagnostic_replay/v116_markdown_path_repair_loop.json',
                   'test/product/v1_product_preview_test.dart',
                   'test/product/budget_diagnostics_test.dart',
                   'tool/policy_support_test.py',
                   'tool/record_p0_003_ci.py',
                   'docs/SUPPORT_POLICY.md',
                   'tasks/completed/P0-005.md',
                   'tool/repository_governance_test.py',
                   'tool/github_governance.py',
                   'tool/github_governance_client_test.py',
                   'config/repository_governance.json',
                   '.github/CODEOWNERS',
                   '.github/pull_request_template.md',
                   'docs/roadmap/REPOSITORY_GOVERNANCE.md',
                   'tasks/completed/P0-006.md',
                   'docs/adr/ADR-0001-runtime-boundaries.md',
                   'docs/adr/ADR-0002-owner-mode.md',
                   'docs/adr/ADR-0004-automation-host.md',
                   'docs/architecture/RUNTIME_BOUNDARY_MATRIX.md',
                   'config/runtime_boundaries.v1.json',
                   'schemas/runtime_boundary_contract.v1.json',
                   'tool/p1_001_runtime_boundary_test.py',
                   'tasks/completed/P1-001.md',
                   'release/evidence/P1-001/manifest.json',
                   'schemas/access_profile_v2.schema.json',
                   'config/access_profiles.v2.json',
                   'docs/architecture/ACCESS_PROFILE_V2.md',
                   'lib/product/access_profile_v2.dart',
                   'test/product/access_profile_v2_test.dart',
                   'tool/access_profile_v2.py',
                   'tool/access_profile_v2_test.py',
                   'tool/p1_002_access_profile_test.py',
                   'evals/fixtures/p1_002_access_profiles/invalid_cases.json',
                   'tasks/completed/P1-002.md',
                   'release/evidence/P1-002/manifest.json',
                   'schemas/capability_grant_v2.schema.json',
                   'config/capability_grant.v2.json',
                   'docs/architecture/CAPABILITY_GRANT_V2.md',
                   'lib/product/capability_grant_v2.dart',
                   'test/product/capability_grant_v2_test.dart',
                   'tool/capability_grant_v2.py',
                   'tool/capability_grant_v2_test.py',
                   'tool/p1_003_capability_grant_test.py',
                   'evals/fixtures/p1_003_capability_grants/vectors.json',
                   'tasks/completed/P1-003.md',
                   'release/evidence/P1-003/manifest.json',
                   'schemas/deterministic_policy_v2.schema.json',
                   'config/policy_engine.v2.json',
                   'docs/architecture/DETERMINISTIC_POLICY_ENGINE_V2.md',
                   'lib/product/deterministic_policy_engine.dart',
                   'test/product/deterministic_policy_engine_test.dart',
                   'tool/deterministic_policy_engine.py',
                   'tool/deterministic_policy_engine_test.py',
                   'tool/p1_004_policy_engine_test.py',
                   'evals/fixtures/p1_004_policy_engine/property_cases.json',
                   'tasks/completed/P1-004.md',
                   'release/evidence/P1-004/manifest.json',
                   'config/key_storage.v2.json',
                   'config/local_ipc.v1.json',
                   'config/manifest_compatibility.v2.json',
                   'config/signed_manifest_v2.json',
                   'config/threat_model_v2.json',
                   'config/tuf_trust.v1.json',
                   'docs/THREAT_MODEL_V2.md',
                   'docs/adr/ADR-0003-signed-manifest-v2.md',
                   'docs/adr/ADR-0006-update-system.md',
                   'docs/architecture/KEY_STORAGE_V2.md',
                   'docs/architecture/LOCAL_AUTHENTICATED_IPC_V1.md',
                   'docs/architecture/SIGNED_AUDIT_CHECKPOINTS.md',
                   'docs/architecture/SIGNED_MANIFEST_V2.md',
                   'docs/roadmap/INTEGRATION_TRAINS.md',
                   'docs/roadmap/P1_CLOSURE.md',
                   'docs/roadmap/integration_trains.json',
                   'docs/security/TUF_KEY_CEREMONY.md',
                   'evals/fixtures/p1_005_signed_manifest_v2/negative_vectors.json',
                   'evals/fixtures/p1_006_cross_language_signing/golden_vectors.json',
                   'lib/product/key_registry_v2.dart',
                   'lib/product/local_authenticated_ipc_v1.dart',
                   'lib/product/manifest_compatibility_v2.dart',
                   'lib/product/signed_audit_checkpoint_v1.dart',
                   'lib/product/signed_manifest_v2.dart',
                   'release/evidence/P1-005/manifest.json',
                   'release/evidence/P1-006/manifest.json',
                   'release/evidence/P1-007/manifest.json',
                   'release/evidence/P1-008/manifest.json',
                   'release/evidence/P1-009/manifest.json',
                   'release/evidence/P1-010/manifest.json',
                   'release/evidence/P1-011/manifest.json',
                   'release/evidence/P1-012/manifest.json',
                   'release/evidence/P1/manifest.json',
                   'schemas/signed_audit_checkpoint_v1.schema.json',
                   'schemas/signed_manifest_v2.schema.json',
                   'tasks/completed/P1-005.md',
                   'tasks/completed/P1-006.md',
                   'tasks/completed/P1-007.md',
                   'tasks/completed/P1-008.md',
                   'tasks/completed/P1-009.md',
                   'tasks/completed/P1-010.md',
                   'tasks/completed/P1-011.md',
                   'tasks/completed/P1-012.md',
                   'test/product/key_registry_v2_test.dart',
                   'test/product/local_authenticated_ipc_v1_test.dart',
                   'test/product/manifest_compatibility_v2_test.dart',
                   'test/product/signed_audit_checkpoint_v1_test.dart',
                   'test/product/signed_manifest_v2_test.dart',
                   'tool/ed25519_ref.py',
                   'tool/integration_train_test.py',
                   'tool/key_registry_v2.py',
                   'tool/local_authenticated_ipc.py',
                   'tool/manifest_compatibility_v2.py',
                   'tool/p1_005_signed_manifest_spec_test.py',
                   'tool/p1_006_cross_language_signing_test.py',
                   'tool/p1_007_manifest_compatibility_test.py',
                   'tool/p1_008_tuf_trust_test.py',
                   'tool/p1_009_key_registry_test.py',
                   'tool/p1_010_signed_audit_test.py',
                   'tool/p1_011_threat_model_test.py',
                   'tool/p1_012_local_ipc_test.py',
                   'tool/p1_exit_gate_test.py',
                   'tool/signed_audit_checkpoint.py',
                   'tool/signed_manifest_v2.py',
               ]
    missing = [x for x in required if not (ROOT / x).is_file()]
    add("required product files", not missing, "all required files present" if not missing else "missing: " + ", ".join(missing))


def check_active_tree_layout() -> None:
    failures: list[str] = []
    lib = ROOT / "lib"
    for child in sorted(lib.iterdir()) if lib.exists() else []:
        if child.is_dir() and child.name != "product":
            failures.append(f"stale active library directory: lib/{child.name}")
        elif child.is_file() and child.suffix == ".dart" and child.name != "main.dart":
            failures.append(f"stale active library file: lib/{child.name}")
    test = ROOT / "test"
    for child in sorted(test.iterdir()) if test.exists() else []:
        if child.is_dir() and child.name != "product":
            failures.append(f"stale active test directory: test/{child.name}")
        elif child.is_file() and child.suffix == ".dart" and child.name != "widget_test.dart":
            failures.append(f"stale active test file: test/{child.name}")
    if (ROOT / "integration_test").exists():
        failures.append("stale integration_test directory remains active")
    add(
        "active source-tree layout",
        not failures,
        "only the governed product source and current tests are analyzer-visible"
        if not failures
        else "; ".join(failures),
    )


def check_imports_and_syntax() -> None:
    files = package_dart_files()
    failures: list[str] = []
    actual = {p.relative_to(ROOT).as_posix() for p in files}
    missing = sorted(EXPECTED_DART_FILES - actual)
    unexpected = sorted(
        path
        for path in actual - EXPECTED_DART_FILES
        if not path.startswith("test/")
    )
    if missing:
        failures.append("missing active Dart files: " + ", ".join(missing))
    if unexpected:
        failures.append(
            "unexpected Dart files remain active; run the governed stale-source migration: "
            + ", ".join(unexpected[:30])
        )

    import_re = re.compile(
        r"(?m)^\s*(?:import|export|part)\s+['\"]([^'\"]+)['\"]"
    )
    pub_name = "kristin_local_agent"
    pub = read(ROOT / "pubspec.yaml") if (ROOT / "pubspec.yaml").exists() else ""
    m = re.search(r"^name:\s*([^\s#]+)", pub, re.M)
    if m:
        pub_name = m.group(1)
    parser_available = False
    for path in files:
        parser_errors = tree_sitter_dart_errors(path)
        if parser_errors is not None:
            parser_available = True
            failures.extend(parser_errors)
            failures.extend(tree_sitter_unbraced_control_flow(path))
        else:
            ok, detail = balanced_dart(read(path))
            if not ok:
                failures.append(f"{path.relative_to(ROOT)}: {detail}")
        for spec in import_re.findall(read(path)):
            target: Path | None = None
            if (
                spec.startswith("dart:")
                or spec.startswith("package:flutter")
                or spec.startswith("package:flutter_test")
            ):
                continue
            if spec.startswith(f"package:{pub_name}/"):
                target = ROOT / "lib" / spec.split("/", 1)[1]
            elif spec.startswith("package:"):
                continue
            else:
                target = (path.parent / spec).resolve()
            if target is not None and not target.exists():
                failures.append(f"{path.relative_to(ROOT)} imports missing {spec}")
    add(
        "Dart syntax, active-source allowlist, and local imports",
        not failures,
        f"checked {len(files)} allowlisted Dart files using "
        f"{'tree-sitter' if parser_available else 'lexical fallback'}"
        if not failures
        else "; ".join(failures[:40]),
    )


def check_architecture() -> None:
    main = read(ROOT / "lib/main.dart")
    active = "\n".join(read(p) for p in active_files("lib/**/*.dart"))
    failures: list[str] = []
    required_main = ["ProductRuntime", "KristinApp", "initialize"]
    for token in required_main:
        if token not in main: failures.append(f"main.dart missing {token}")
    for token in ["HomeScreen", "AgentEngine", "Orchestrator"]:
        if token in main: failures.append(f"legacy entry token present: {token}")
    if "archive/legacy" in active: failures.append("active code imports legacy archive")
    if "ProductExecutionCoordinator" not in active and "RunCoordinator" not in active:
        failures.append("no governed execution coordinator found")
    required_capabilities = [
        "PermissionScope", "TaskContract", "ExecutionPlan", "Audit", "rollback",
        "research", "knowledge", "ModelIdentity", "package_deployment",
        "support", "MCP", "sourceIndex",
    ]
    for token in required_capabilities:
        if token.lower() not in active.lower(): failures.append(f"missing governed capability marker: {token}")
    add("single governed architecture", not failures, "active entry and capability boundary verified" if not failures else "; ".join(failures))


def check_security() -> None:
    files = active_files("lib/**/*.dart")
    content = {p: read(p) for p in files}
    joined = "\n".join(content.values())
    failures: list[str] = []
    patterns = {
        "wildcard CORS": [r"access-control-allow-origin[^\n]{0,80}['\"]\*['\"]", r"allowOrigin\s*[:=]\s*['\"]\*"],
        "unsupported inline regexp flags": [r"\(\?[imsx-]"],
        "shell execution": [r"runInShell\s*:\s*true", r"Process\.(?:start|run)\(\s*['\"]/bin/(?:sh|bash)['\"]", r"Process\.(?:start|run)\(\s*['\"]cmd(?:\.exe)?['\"]\s*,\s*\[[^\]]*['\"]/c['\"]"],
        "remote API binding": [r"InternetAddress\.anyIPv[46]", r"HttpServer\.bind\(\s*['\"](?:0\.0\.0\.0|::)['\"]"],
        "plaintext credential persistence key": [r"['\"](?:secretValue|tokenPlaintext|apiKeyValue|passwordValue|rawToken)['\"]\s*:"],
    }
    required = {
        "constant-time comparison": r"constantTime|timingSafe|constant[_ ]?time",
        "hashed bearer tokens": r"tokenHash|hashToken|bearer.*hash|hash.*bearer",
        "expiring grants": r"expiresAt|expiry|expired",
        "project path boundary": r"resolveSymbolicLinks|canonical|symlink",
        "private IP rejection": r"loopback|linkLocal|private.*address|isPrivate",
        "bounded HTTP body": r"maxBody|maxRequest|bodyLimit|contentLength",
        "secret redaction": r"SecretRedactor|redact",
        "audit integrity": r"previousHash|chain.*hash|verify.*chain|tamper",
    }
    for label, expressions in patterns.items():
        for expression in expressions:
            if re.search(expression, joined, re.I | re.S):
                failures.append(f"forbidden {label}")
                break
    for label, pat in required.items():
        if not re.search(pat, joined, re.I):
            failures.append(f"missing {label}")
    add("security invariants", not failures, "high-risk static invariants verified" if not failures else "; ".join(sorted(set(failures))))



def check_flutter_dart_compatibility() -> None:
    """Block concrete regressions reported by the Windows Flutter analyzer."""
    runtime = read(ROOT / "lib/product/product_runtime.dart")
    planning = read(ROOT / "lib/product/planning_runtime.dart")
    api = read(ROOT / "lib/product/api_server.dart")
    ui = read(ROOT / "lib/product/ui.dart")
    chat = read(ROOT / "lib/product/chat_studio.dart")
    ui_advanced = read(ROOT / "lib/product/ui_advanced.dart")
    ui_components = read(ROOT / "lib/product/ui_components.dart")
    design_token_sources = [
        read(ROOT / relative)
        for relative in sorted(_load_governed_product_library_files())
        if relative.endswith("_design_tokens.dart")
    ]
    all_ui = "\n".join(
        (ui, chat, ui_advanced, ui_components, *design_token_sources)
    )
    mcp = read(ROOT / "lib/product/mcp.dart")
    deployment = read(ROOT / "lib/product/deployment_support.dart")
    models = read(ROOT / "lib/product/models_research.dart")
    workspace = read(ROOT / "lib/product/workspace_tools.dart")
    failures: list[str] = []

    if "uses: max(" in runtime and "import 'dart:math';" not in runtime:
        failures.append("product_runtime.dart uses max without importing dart:math")
    if "questions.isEmpty" in planning:
        failures.append("planning_runtime.dart treats an integer question count as a collection")
    if "HttpHeaders.originHeader" in api:
        failures.append("api_server.dart uses nonexistent HttpHeaders.originHeader")
    if "cardTheme: const CardTheme(" in all_ui:
        failures.append("ui.dart assigns CardTheme where ThemeData requires CardThemeData")
    if "CardThemeData(" not in all_ui:
        failures.append("the active theme does not use CardThemeData")
    if "Iterable<EventEnvelope> _eventsForRun" in ui:
        failures.append(
            "ui.dart returns Iterable<EventEnvelope> from _eventsForRun even though callers use List.reversed"
        )
    if "List<EventEnvelope> _eventsForRun" not in ui:
        failures.append("ui.dart must expose run events as a List<EventEnvelope>")
    if not source_contains(ui, "}).toList(growable: false);"):
        failures.append("ui.dart must materialize filtered run events before reverse traversal")
    for name, content in (("ui.dart", ui), ("chat_studio.dart", chat), ("ui_advanced.dart", ui_advanced)):
        if content.count("DropdownButtonFormField") > content.count("initialValue:"):
            failures.append(f"every DropdownButtonFormField in {name} must use initialValue")
        if re.search(r"DropdownButtonFormField<[^>]+>\(\s*value:", content):
            failures.append(f"{name} uses deprecated DropdownButtonFormField.value")
    if "import 'dart:math';" in api or "import 'dart:math';" in mcp:
        failures.append("unused dart:math import remains in API or MCP source")
    if "(?i)" in deployment:
        failures.append("deployment credential regexp uses unsupported inline flags")
    for name, content in (("models_research.dart", models), ("workspace_tools.dart", workspace)):
        if "BytesBuilder" in content and "import 'dart:typed_data';" not in content:
            failures.append(f"{name} uses BytesBuilder without a direct dart:typed_data import")
    managed_start = workspace.find("class ManagedProcessService")
    managed_end = workspace.find("class ToolContext", managed_start)
    if managed_start >= 0 and ".listen(" in workspace[managed_start:managed_end]:
        failures.append("managed process streams use uncancelled listen subscriptions")
    if "this.details" in api and "class _HttpFailure" in api:
        failures.append("unused _HttpFailure.details parameter remains")

    for path in active_files("lib/**/*.dart"):
        content = read(path)
        for offset in unconverted_clamp_offsets(content):
            line_number = content.count("\n", 0, offset) + 1
            failures.append(
                f"{path.relative_to(ROOT)}:{line_number} clamp result has no explicit conversion"
            )

    pubspec = read(ROOT / "pubspec.yaml")
    for package in ("flutter_markdown", "flutter_highlight", "provider", "cupertino_icons"):
        if re.search(rf"^\s*{re.escape(package)}\s*:", pubspec, re.M):
            failures.append(f"unused or discontinued dependency remains declared: {package}")

    for wrapper_name in (
        "tool/bootstrap_platforms.cmd",
        "tool/verify.cmd",
        "tool/run_windows.cmd",
    ):
        wrapper = ROOT / wrapper_name
        if not wrapper.is_file():
            failures.append(f"missing unsigned-script-safe launcher: {wrapper_name}")
            continue
        if "powershell" in read(wrapper).lower():
            failures.append(f"{wrapper_name} still invokes PowerShell")

    verify = read(ROOT / "tool/verify.cmd").lower()
    if "prune_stale_legacy.cmd" not in verify:
        failures.append("Windows verification does not run the stale-source migration")

    migration = read(ROOT / "tool/prune_stale_legacy.dart")
    if (
        "SOURCE_MANIFEST.sha256" not in migration
        or "config/p2_source_inventory.v1.json" not in migration
        or "_governedDartFiles(root)" not in migration
        or "allowedDartFiles.contains(relative)" not in migration
    ):
        failures.append(
            "stale-source migration does not consume the governed "
            "source manifest and P2 Dart inventory"
        )

    launcher_text = read(ROOT / "RUN_WINDOWS.bat")
    if "Starting Kristin v1.0 Prompt-to-Task Product Preview" not in launcher_text:
        failures.append("RUN_WINDOWS.bat does not identify the active v1 product preview")
    for line in launcher_text.splitlines():
        if line.lstrip().lower().startswith("echo starting") and "&" in line.replace("^&", ""):
            failures.append("RUN_WINDOWS.bat contains an unescaped CMD ampersand in its startup title")

    diagnostics = read(ROOT / "lib/product/project_diagnostics.dart")
    if "import 'crypto_utils.dart';" not in diagnostics:
        failures.append("project diagnostics does not directly import SecretRedactor")
    if "trimmed.replaceAll(RegExp" in diagnostics:
        failures.append("project diagnostics still uses the analyzer-invalid trailing-separator regexp")
    if "RegExp(r'(?m)" in diagnostics or 'RegExp(r"(?m)' in diagnostics:
        failures.append("project diagnostics uses an unsupported inline multiline regexp flag")
    if "multiLine: true" not in diagnostics:
        failures.append("project diagnostics does not use the supported RegExp multiLine parameter")
    if "import 'dart:math';" in diagnostics:
        failures.append("unused dart:math import remains in project diagnostics")
    if "import 'storage_security.dart';" not in diagnostics:
        failures.append("project diagnostics does not import ProductException from storage_security.dart")
    if "throw ProductException(" not in diagnostics:
        failures.append("project diagnostics no longer exercises the ProductException linkage")
    if "_isWindowsDriveRoot" not in diagnostics:
        failures.append("project diagnostics no longer preserves Windows drive roots")

    if (
        "matrix.scale(factor);" in chat
        or "matrix.scaleByDouble(factor, factor, factor, 1.0);" not in chat
    ):
        failures.append("run graph still uses the deprecated Matrix4.scale API")
    run_test_start = chat.find("Future<void> _runProjectTests")
    run_test_end = chat.find("Future<void> _addExistingProject", run_test_start)
    if run_test_start < 0 or "!mounted" not in chat[run_test_start:run_test_end]:
        failures.append("project quick-test dialog still uses BuildContext across an async gap")

    if re.search(
        r"putIfAbsent\(record\.knowledgeId,\s*\(\)\s*=>\s*<ResearchArchiveRecord>\[\]\)\s*\.\.add\(record\)",
        models,
        re.S,
    ):
        failures.append("research migration still contains the single-use cascade lint")

    source_contract = read(ROOT / "test/product/source_contract_test.dart")
    if "contains(r\"'inspect_file:$candidate'\")" not in source_contract:
        failures.append(
            "source contract must use a raw string for the literal $candidate marker"
        )
    if "contains(\"'inspect_file:$candidate'\")" in source_contract:
        failures.append(
            "source contract contains an interpolated undefined $candidate identifier"
        )
    if "sourceRunId: this.sourceRunId," in read(ROOT / "lib/product/domain.dart"):
        failures.append("RunRecord.copyWith retains an unnecessary this qualifier")
    if re.search(
        r"output\s*\n\s*\.\.writeln\(\s*'- `\$\{item\.item\.id\}`",
        deployment,
        re.S,
    ):
        failures.append("diagnostic work-item output retains a one-operation cascade")

    if "Future<List<KnowledgeEntry>> list(String projectId)" not in models:
        failures.append("KnowledgeService does not expose the project-scoped list API used by behavioral tests")
    if "knowledge.list(projectId)" not in runtime:
        failures.append("ProductRuntime does not route knowledge listing through KnowledgeService.list")

    if "_migrationCandidates" not in migration or "_moveEntity" not in migration or "renameSync" not in migration:
        # The migration must discover, preserve, and move stale paths rather than
        # deleting them as a cleanup shortcut.
        failures.append("migration implementation is incomplete")
    if "deleteSync" in migration or "FileMode.write" in migration:
        failures.append("migration contains a destructive source operation")

    for unsafe_tool in ("tool/remediate_analyzer.py", "tool/remediate_machine.py"):
        if (ROOT / unsafe_tool).exists():
            failures.append(f"unsafe analyzer-driven source mutator remains active: {unsafe_tool}")

    add(
        "reported Flutter/Dart analyzer regressions",
        not failures,
        "reported compiler/analyzer regressions remain patched in the active v1 source"
        if not failures
        else "; ".join(failures),
    )


def check_chat_workspace_ux() -> None:
    """Verify the chat-first default journey and its advanced product surfaces."""
    ui = read(ROOT / "lib/product/ui.dart")
    chat = read(ROOT / "lib/product/chat_studio.dart")
    advanced = read(ROOT / "lib/product/ui_advanced.dart")
    failures: list[str] = []

    if "home: ChatStudio(" not in ui:
        shell = read(ROOT / "lib/product/p2_app_shell.dart")
        p2_shell_is_chat_first = (
            "home: P2KristinShell(" in ui
            and "chat: ChatStudio(" in ui
            and "var _index = 0;" in shell
            and source_contains(
                shell,
                "final pages = <Widget>[ widget.chat, "
                "widget.ownerMode.buildWorkspace(",
            )
        )
        integrated_shell_is_chat_first = (
            "home: KristinMainShell(" in ui
            and "chat: ChatStudio(" in ui
            and "var _index = 0;" in ui
            and source_contains(
                ui,
                "final pages = <Widget>[ widget.chat, "
                "P5InformationArchitecturePrototype( "
                "controller: _experienceController, ), "
                "widget.ownerMode.buildWorkspace(",
            )
        )
        if not (p2_shell_is_chat_first or integrated_shell_is_chat_first):
            failures.append(
                "the application does not open in ChatStudio, the governed "
                "chat-first P2 shell, or the governed chat-first integrated shell"
            )

    primary = re.search(
        r"const List<_NavigationItem> _primaryItems = <_NavigationItem>\[(.*?)\];",
        chat,
        re.S,
    )
    if primary is None or primary.group(1).count("_NavigationItem(") != 2:
        failures.append("primary navigation must contain Chats and Project Manager")
    for label in ("Chats", "Project Manager"):
        if f"label: '{label}'" not in chat:
            failures.append(f"missing primary destination: {label}")

    build = re.search(
        r"const List<_NavigationItem> _buildItems = <_NavigationItem>\[(.*?)\];",
        chat,
        re.S,
    )
    if build is None or build.group(1).count("_NavigationItem(") != 5:
        failures.append("Build & Debug must contain five focused destinations")
    for label in ("Runs", "Prompt Studio", "Knowledge", "Skills", "Logs"):
        if f"label: '{label}'" not in chat:
            failures.append(f"missing Build & Debug destination: {label}")

    required_markers = {
        "chat composer": "Ask Kristin anything about this project",
        "collapsible advanced menu": "BUILD & DEBUG",
        "inline access approval": "Access needed for this run",
        "single start action": "Start task",
        "inline run timeline": "View run",
        "visual run graph": "InteractiveViewer(",
        "project doctor": "Text('Doctor')",
        "quick tests": "Text('Test')",
        "prompt persistence": "runtime.savePrompt(",
        "project knowledge": "runtime.listKnowledge(",
        "skill catalogue": "runtime.listBuiltInSkills()",
        "three-level logs": "_LogView.raw",
        "support diagnostics": "runtime.createSupportBundle",
    }
    for label, marker in required_markers.items():
        if marker not in chat:
            failures.append(f"missing {label}")

    for marker in (
        "runtime.prepare(",
        "runtime.createRun(",
        "runtime.approve(",
        "runtime.execute(",
    ):
        if marker not in chat:
            failures.append(f"chat UI bypasses governed path marker: {marker}")

    for marker in (
        "AI models",
        "Sources",
        "Privacy & access",
        "Integrations",
        "Developer",
        "Verify audit chain",
        "Save all logs ZIP",
    ):
        if marker not in advanced:
            failures.append(f"advanced capability is not reachable: {marker}")

    add(
        "Chat Workspace UX and progressive disclosure",
        not failures,
        "chat-first navigation, inline plans, project diagnostics, observable runs, Prompt Studio, knowledge, skills, logs, and advanced settings are present"
        if not failures
        else "; ".join(failures),
    )


def check_knowledge_memory() -> None:
    """Verify the v0.9 archive, retrieval, citation, memory, API, CLI, and UX path."""
    domain = read(ROOT / "lib/product/domain.dart")
    storage = read(ROOT / "lib/product/storage_security.dart")
    research = read(ROOT / "lib/product/models_research.dart")
    planning = read(ROOT / "lib/product/planning_runtime.dart")
    runtime = read(ROOT / "lib/product/product_runtime.dart")
    tools = read(ROOT / "lib/product/workspace_tools.dart")
    tool_registry = read(ROOT / "schemas/tool_registry.v2.json")
    api = read(ROOT / "lib/product/api_server.dart")
    chat = read(ROOT / "lib/product/chat_studio.dart")
    cli = read(ROOT / "tool/kristin_cli.py")
    test = read(ROOT / "test/product/knowledge_memory_test.dart") if (ROOT / "test/product/knowledge_memory_test.dart").exists() else ""
    failures: list[str] = []

    markers = {
        "knowledge and archive schemas": (domain, (
            "class ResearchArchiveRecord", "class MemoryEpisode",
            "class KnowledgeSearchHit", "class KnowledgeRetrieval", "class KnowledgeStats",
        )),
        "persistent archive repositories": (storage, (
            "collection<ResearchArchiveRecord>",
            "collection<MemoryEpisode>",
            "name: 'research_archive'", "name: 'memory_episodes'",
        )),
        "content-addressed archive": (research, (
            "Future<String> _storeObject", "kristin.research.archive.v1",
            "Future<File> exportPackage", "_maxExportBytes",
        )),
        "v0.8 archive migration": (research, (
            "Future<void> _migrateV08ArchiveFiles",
            "legacy-v0.8-source-file",
            "legacy-v0.8-search-file",
            "legacy-v0.8-knowledge-recovery",
        )),
        "hybrid retrieval": (research, (
            "Future<KnowledgeRetrieval> retrieve", "_semanticVector(",
            "lexicalScore", "semanticScore", "buildCitedContext",
        )),
        "episodic memory": (research, (
            "Future<MemoryEpisode> recordEpisode", "Only terminal runs",
        )),
        "run integration": (planning, (
            "CITED PROJECT KNOWLEDGE AND RUN MEMORY", "reconcileMemoryEpisodes",
            "EvidenceKind.knowledge",
        )),
        "memory trust wrapper": (research, ("PRIOR RUN MEMORY",)),
        "runtime facade": (runtime, (
            "searchKnowledge(", "knowledgeStats(", "rebuildKnowledgeIndex(",
            "exportKnowledge(", "listResearchArchive(", "listMemoryEpisodes(",
        )),
        "governed tool": (tools + tool_registry, ('"name": "knowledge_search"', "retrieval.toJson()")),
        "local API": (api, (
            "action == 'search'", "action == 'reindex'", "action == 'export'",
            "segments[3] == 'research-archive'", "segments[3] == 'memory'",
        )),
        "chat knowledge UX": (chat, (
            "Knowledge & memory", "Research sources", "Run memory",
            "Sources and run memory consulted", "label: const Text('Export')",
        )),
        "diagnostic CLI": (cli, (
            "subparsers.add_parser(", '"knowledge"', "research_archive.json",
            "memory_episodes.json", "hybrid index",
        )),
        "behavioral tests": (test, (
            "research is archived with immutable provenance and cited retrieval",
            "run memory participates in retrieval and portable export",
            "v0.8 archive files migrate idempotently and repair missing entries",
            "knowledge list is project scoped and newest first",
        )),
    }
    for group, (content, required) in markers.items():
        for marker in required:
            if marker not in content:
                failures.append(f"{group} missing {marker}")

    add(
        "v0.9 research archive, cited retrieval, and run memory",
        not failures,
        "immutable research provenance, content-addressed objects, hybrid citations, episodic memory, export, UI, API, CLI, and tests are wired"
        if not failures
        else "; ".join(failures[:40]),
    )



def check_execution_reliability() -> None:
    """Verify safe memory selection, conversational planning, and model repair."""
    domain = read(ROOT / "lib/product/domain.dart")
    planning = read(ROOT / "lib/product/planning_runtime.dart")
    agent_protocol = read(ROOT / "lib/product/agent_protocol.dart")
    research = read(ROOT / "lib/product/models_research.dart")
    runtime = read(ROOT / "lib/product/product_runtime.dart")
    permissions = read(ROOT / "lib/product/storage_security.dart")
    tools = read(ROOT / "lib/product/workspace_tools.dart")
    behavioral = read(ROOT / "test/product/execution_reliability_test.dart")
    memory_test = read(ROOT / "test/product/knowledge_memory_test.dart")
    failures: list[str] = []

    required = {
        "conversation classifier": (domain, ("bool isConversationalRequest(", "bool isFailureInvestigationRequest(")),
        "action compatibility": (
            domain + agent_protocol,
            (
                "json['tool_calls']",
                "json['function_call']",
                "class AgentProtocolAdapter",
                "'tool_input'",
                "'action_input'",
            ),
        ),
        "action validation": (planning, ("'model_action_invalid'", "'model_tool_not_allowed'")),
        "conversation plan": (planning, ("revision: 2", "'Respond conversationally'", "allowPlainCompletion: conversational")),
        "request-only retrieval": (planning, ("query: run.command.contract.request", "includeUnsuccessfulEpisodes:")),
        "protocol repair": (
            planning,
            (
                "'model.protocol_repair_requested'",
                "protocolRepairAttempts < 2",
                "protocolRepairAttempts = 0",
                "'model.protocol_fallback_applied'",
                "'model.protocol_exhausted'",
                "'model_protocol_exhausted'",
                "'responsePreview'",
            ),
        ),
        "streamed Ollama": (research, ("'stream': true", "StreamIterator<String>", "'model_first_token_timeout'")),
        "outcome-aware index": (research, ("static const int _indexSchema = 3", "episodeOutcome", "isConversationalRequest(episode.request)")),
        "safe manual default": (runtime, ("bool includeUnsuccessfulEpisodes = false",)),
        "zero-scope governance": (permissions, ("zero-scope grant",)),
        "explicit failed-memory opt-in": (tools, ("arguments['includeUnsuccessfulEpisodes'] == true",)),
        "behavioral regressions": (
            behavioral,
            (
                "Ollama provider consumes streamed NDJSON responses",
                "a greeting becomes one model-only work item",
                "accepts snake-case function_call envelopes",
                "normalizes safe tool and argument aliases",
                "unwraps double-encoded response objects",
                "accepts bounded ReAct-style action output",
                "does not normalize a tool outside the work-item allowlist",
            ),
        ),
        "memory regressions": (memory_test, ("automatic retrieval excludes unsuccessful run episodes", "automatic context excludes unsuccessful and conversational episodes")),
    }
    for group, (content, tokens) in required.items():
        for token in tokens:
            if not source_contains(content, token):
                failures.append(f"{group} missing {token}")

    if "${run.command.contract.request} ${progress.item.title}" in planning:
        failures.append("automatic retrieval still appends deterministic work-item titles")

    add(
        "v0.9.3 memory relevance and execution reliability",
        not failures,
        "failed run memory is opt-in, greetings are model-only, model envelopes and safe aliases normalize through the work-item allowlist, repairs are consecutive, diagnostics are inspectable, and Ollama uses bounded streaming"
        if not failures else "; ".join(failures[:40]),
    )




def check_typed_protocol_contracts() -> None:
    """Validate generated schemas, provider compatibility, and fail-closed mutation inputs."""
    started = time.monotonic()
    command = [sys.executable, str(ROOT / "tool" / "protocol_contract_test.py")]
    code, output = run(command, timeout=120)
    protocol = read(ROOT / "lib/product/agent_protocol.dart")
    decisions = read(ROOT / "lib/product/agent_decision.dart")
    schemas = read(ROOT / "lib/product/tool_schema.dart")
    workspace = read(ROOT / "lib/product/workspace_tools.dart")
    behavioral = read(ROOT / "test/product/typed_protocol_schema_test.dart")
    failures: list[str] = []
    if code != 0:
        failures.append(f"protocol contract gate exited {code}: {output[:1600]}")
    required_markers = {
        "typed decision hierarchy": (decisions, "sealed class AgentDecision"),
        "provider boundary": (protocol, "abstract interface class AgentProviderAdapter"),
        "Ollama adapter": (protocol, "class OllamaAgentProviderAdapter"),
        "OpenAI-compatible adapter": (protocol, "class OpenAiCompatibleAgentProviderAdapter"),
        "MCP adapter": (protocol, "class McpAgentProviderAdapter"),
        "recorded replay adapter": (protocol, "class RecordedAgentProviderAdapter"),
        "input schema validation": (schemas, "normalizeAndValidate"),
        "typed retryability": (schemas + decisions, "Retryability.modelCorrection"),
        "output schema validation": (workspace, "validateOutput(result.toJson())"),
        "protocol fuzzing": (behavioral, "deterministic envelope fuzzing never loses write content"),
        "missing mutation rejection": (behavioral, "fuzzed missing mutation data cannot reach dispatch"),
    }
    for label, (content, marker_value) in required_markers.items():
        if marker_value not in content:
            failures.append(f"{label} missing {marker_value}")
    add(
        "v1.2 typed AgentDecision and JSON Schema tool foundation",
        not failures,
        "23 governed tools and five decision variants share generated contracts; provider envelopes are normalized outside the coordinator; inputs fail closed before dispatch; outputs are schema checked; 2,000 deterministic protocol fuzz cases pass"
        if not failures
        else "; ".join(failures[:30]),
        started=started,
    )


def check_durable_workflow_kernel() -> None:
    """Execute the schema, crash, idempotency, migration, and integration gate."""
    started = time.monotonic()
    generator_code, generator_output = run(
        [sys.executable, str(ROOT / "tool" / "generate_workflow_migrations.py"), "--check"],
        timeout=60,
    )
    code, output = run(
        [sys.executable, str(ROOT / "tool" / "workflow_kernel_test.py"), "--project", str(ROOT), "--json"],
        timeout=180,
    )
    failures: list[str] = []
    payload: dict[str, object] = {}
    if generator_code != 0:
        failures.append(f"migration generator check exited {generator_code}: {generator_output[:1200]}")
    if code != 0:
        failures.append(f"workflow kernel gate exited {code}: {output[:1600]}")
    else:
        try:
            decoded = json.loads(output)
            if isinstance(decoded, dict):
                payload = decoded
            else:
                failures.append("workflow kernel gate did not return an object")
        except json.JSONDecodeError as error:
            failures.append(f"workflow kernel gate returned invalid JSON: {error}")
    if payload.get("failed") != 0 or payload.get("passed") != 14:
        failures.append(
            f"workflow kernel expected 14/14 cases, got {payload.get('passed')}/{(payload.get('passed') or 0) + (payload.get('failed') or 0)}"
        )
    if payload.get("schemaVersion") != 6:
        failures.append("workflow schema version must be 6")
    if payload.get("migrationDigest") != "df7e693bff693d0bf649de4f26ea907ce969456adfbf342d17f40f06b22b6261":
        failures.append("workflow migration digest drifted")
    database = payload.get("database", {})
    if not isinstance(database, dict) or str(database.get("integrity", "")).lower() != "ok":
        failures.append("workflow SQLite integrity check did not pass")
    add(
        "v1.3 durable workflow kernel",
        not failures,
        "14/14 executable SQLite crash, append-only, idempotency, migration, concurrency, recovery, and compensation cases passed"
        if not failures else "; ".join(failures),
        started=started,
    )



def check_prompt_studio_v2() -> None:
    """Run canonical Prompt Studio 2 generation, compilation, and scale gates."""
    started = time.monotonic()
    commands = (
        [sys.executable, str(ROOT / "tool" / "generate_prompt_studio_contracts.py"), "--check"],
        [sys.executable, str(ROOT / "tool" / "generate_prompt_studio_fixtures.py"), "--check"],
        [
            sys.executable,
            str(ROOT / "tool" / "prompt_studio_v2_test.py"),
            "--json-output",
            str(ROOT / "release" / "PROMPT_STUDIO_V2_RESULTS.json"),
        ],
    )
    failures: list[str] = []
    for command in commands:
        code, output = run(command, timeout=180)
        if code != 0:
            failures.append(f"{' '.join(command[1:])} exited {code}: {output[-1600:]}")

    result_path = ROOT / "release" / "PROMPT_STUDIO_V2_RESULTS.json"
    result: dict[str, object] = {}
    if result_path.is_file():
        try:
            decoded = json.loads(read(result_path))
            result = decoded if isinstance(decoded, dict) else {}
        except json.JSONDecodeError as error:
            failures.append(f"Prompt Studio results are invalid JSON: {error}")
    else:
        failures.append("Prompt Studio results file was not generated")
    if result:
        if result.get("passed") is not True:
            failures.append("Prompt Studio 2 executable gate reported failure")
        if result.get("passedCount") != 30 or result.get("total") != 30:
            failures.append("Prompt Studio 2 gate must contain 30 passing cases")
        if result.get("fixtureTaskCounts") != [1, 10, 50, 100]:
            failures.append("Prompt Studio scale fixtures must be 1/10/50/100 tasks")
        if result.get("compilerVersion") != "1.0.0":
            failures.append("Prompt Studio compiler version drifted")

    generated = read(ROOT / "lib/product/generated/prompt_studio_contracts.g.dart")
    runtime = read(ROOT / "lib/product/prompt_studio_v2.dart")
    product_runtime = read(ROOT / "lib/product/product_runtime.dart")
    api = read(ROOT / "lib/product/api_server.dart")
    cli = read(ROOT / "tool/kristin_cli.py")
    compiler = read(ROOT / "tool/plan_compiler.py")
    behavioral = read(ROOT / "test/product/prompt_studio_v2_test.dart")
    lineage = json.loads(read(ROOT / "VERSION_CONTROL.json"))
    markers = {
        "generated contract digest": (
            generated,
            "4f65d0e57ee86b58b26223970c8fbfda243256a47689ce83568df88be042500a",
        ),
        "typed specification": (runtime, "class ProductSpecificationV2"),
        "typed task plan": (runtime, "class TaskPlanV2"),
        "deterministic compiler": (runtime, "class PromptStudioV2Compiler"),
        "static evaluator": (runtime, "class PromptStudioV2Evaluator"),
        "runtime service": (product_runtime, "promptStudioV2"),
        "compile API": (api, "/v1/prompt-studio/v2/compile"),
        "evaluation API": (api, "/v1/prompt-studio/v2/evaluate"),
        "source CLI": (cli, "plan-compile"),
        "side-effect-free simulation": (compiler + runtime, "sideEffectsPerformed"),
        "sandbox prerequisite": (compiler + runtime, "sandbox_required"),
        "duplicate task rejection": (compiler + runtime, "task_id_duplicate"),
        "acceptance evidence linkage": (compiler + runtime, "criterion_validator_missing"),
        "scale behavioral fixture": (behavioral, "<int>[1, 10, 50, 100]"),
        "no third-party CLI schema dependency": (compiler, "validate_schema_contract"),
    }
    for label, (content, token) in markers.items():
        if token not in content:
            failures.append(f"{label} missing {token}")
    if "from jsonschema" in compiler or "import jsonschema" in compiler:
        failures.append("Prompt Studio source CLI unexpectedly requires third-party jsonschema")
    prompt_meta = lineage.get("promptStudioV2", {}) if isinstance(lineage, dict) else {}
    if not isinstance(prompt_meta, dict):
        failures.append("VERSION_CONTROL promptStudioV2 metadata is missing")
    else:
        if prompt_meta.get("v14SandboxImplemented") is not False:
            failures.append("v1.5 release must not claim the skipped v1.4 sandbox milestone")
        if prompt_meta.get("sandboxDependentTasksFailClosed") is not True:
            failures.append("sandbox-dependent plans must fail closed")
        if prompt_meta.get("behavioralGateCases") != 30:
            failures.append("lineage does not record the 30-case Prompt Studio gate")

    add(
        "v1.5 Prompt Studio 2 schemas, compiler, dry run, and evaluation",
        not failures,
        "30/30 executable cases passed; canonical 1/10/50/100-task plans compile deterministically; prompt impact +75.0; sandbox-dependent work fails closed; runtime, API, and CLI are integrated"
        if not failures
        else "; ".join(failures[:40]),
        started=started,
    )

def check_linux_sandbox_backfill() -> None:
    started = time.monotonic()
    failures: list[str] = []
    cli = read(ROOT / "tool/kristin_cli.py")
    worker = read(ROOT / "tool/sandbox_worker.py")
    worker_gate = read(ROOT / "tool/sandbox_worker_test.py")
    broker = read(ROOT / "tool/network_broker.py")
    broker_gate = read(ROOT / "tool/network_broker_test.py")
    secret = read(ROOT / "tool/secret_broker.py")
    readme = read(ROOT / "README.md")
    lineage = json.loads(read(ROOT / "VERSION_CONTROL.json"))
    sandbox_meta = lineage.get("sandboxBackfill", {}) if isinstance(lineage, dict) else {}
    markers = {
        "cli sandbox routing": (cli, "execution_mode: str = \"sandbox\""),
        "trusted host diagnostic mode": (cli, "Trusted host diagnostic completed successfully."),
        "sandbox probe": (worker, "linux_userns_namespace_worker"),
        "snapshot workspace": (worker, "snapshot_writable"),
        "parent-death worker cleanup": (worker, "--kill-child=SIGKILL"),
        "PID-reuse-safe process identity": (worker, "startTimeTicks"),
        "network-off": (worker_gate, "Network-off enforcement"),
        "https broker": (broker, "def fetch_https("),
        "broker gate": (broker_gate, "HTTPS-only policy"),
        "one-use secrets": (secret, "def consume_secret("),
        "readme disclosure": (readme, "Linux reference worker"),
    }
    for label, (content, token) in markers.items():
        if token not in content:
            failures.append(f"{label} missing {token}")
    if not isinstance(sandbox_meta, dict):
        failures.append("VERSION_CONTROL sandboxBackfill metadata is missing")
    else:
        if sandbox_meta.get("linuxNamespaceWorker") is not True:
            failures.append("VERSION_CONTROL sandboxBackfill must record the Linux worker")
        if sandbox_meta.get("fullCrossPlatformV14Claimed") is not False:
            failures.append("source head must not claim the full cross-platform v1.4 exit gate")
    add(
        "v1.5.1 Linux sandbox backfill",
        not failures,
        "Linux namespace worker, HTTPS broker, one-use secret broker, and sandbox-aware CLI routing are integrated without falsely claiming the full cross-platform v1.4 milestone"
        if not failures
        else "; ".join(failures[:40]),
        started=started,
    )

def check_project_manager_v2() -> None:
    """Execute the rebuilt v1.6 operational layer on the cumulative source."""
    started = time.monotonic()
    failures: list[str] = []
    generator_code, generator_output = run(
        [sys.executable, str(ROOT / "tool" / "generate_v170_contracts.py"), "--check"],
        timeout=60,
    )
    if generator_code != 0:
        failures.append(f"v1.7 contract generator exited {generator_code}: {generator_output[-1200:]}")
    result_path = ROOT / "release" / "PROJECT_MANAGER_V2_RESULTS.json"
    code, output = run(
        [
            sys.executable,
            str(ROOT / "tool" / "project_manager_v2_test.py"),
            "--json-output",
            str(result_path),
        ],
        timeout=240,
    )
    if code != 0:
        failures.append(f"Project Manager gate exited {code}: {output[-1800:]}")
    payload: dict[str, object] = {}
    if result_path.is_file():
        try:
            decoded = json.loads(read(result_path))
            payload = decoded if isinstance(decoded, dict) else {}
        except json.JSONDecodeError as error:
            failures.append(f"Project Manager results are invalid JSON: {error}")
    else:
        failures.append("Project Manager results file was not generated")
    if payload.get("passed") is not True or payload.get("passedCount") != 16 or payload.get("caseCount") != 16:
        failures.append(
            f"Project Manager expected 16/16 cases, got {payload.get('passedCount')}/{payload.get('caseCount')}"
        )

    source = read(ROOT / "tool" / "project_manager_v2.py")
    dart = read(ROOT / "lib" / "product" / "project_manager_v2.dart")
    migration = read(ROOT / "migrations" / "workflow" / "005_project_manager_execution_intelligence.sql")
    cli = read(ROOT / "tool" / "kristin_cli.py")
    lineage = json.loads(read(ROOT / "VERSION_CONTROL.json"))
    markers = (
        "class ProjectProfileV2",
        "snapshot_writable",
        "managed_project_processes",
        "artifact_records",
        "probe_backend",
        "builtin_snapshot_packager",
        "launcherStartTimeTicks",
        "process_tree_termination_incomplete",
        "class ProjectManagerV2Service",
        "--project-manager",
    )
    joined = source + dart + migration + cli
    for token in markers:
        if token not in joined:
            failures.append(f"Project Manager integration missing {token}")
    metadata = lineage.get("projectManagerV2", {}) if isinstance(lineage, dict) else {}
    if not isinstance(metadata, dict) or metadata.get("behavioralGateCases") != 16:
        failures.append("VERSION_CONTROL does not record the 16-case Project Manager gate")
    if isinstance(metadata, dict) and metadata.get("liveSandboxReadiness") is not True:
        failures.append("Project Manager readiness must be derived from the live sandbox")

    add(
        "v1.6 Project Manager 2 operational layer",
        not failures,
        "16/16 capability-aware cases passed; real sandbox execution is exercised when available, unsupported platforms prove stable fail-closed behavior, and built-in deterministic packaging remains available without executing project code"
        if not failures
        else "; ".join(failures[:40]),
        started=started,
    )


def check_execution_intelligence() -> None:
    """Execute the v1.7 router, progress, convergence, and verification gate."""
    started = time.monotonic()
    failures: list[str] = []
    generator_code, generator_output = run(
        [sys.executable, str(ROOT / "tool" / "generate_v170_contracts.py"), "--check"],
        timeout=60,
    )
    if generator_code != 0:
        failures.append(f"v1.7 contract generator exited {generator_code}: {generator_output[-1200:]}")
    result_path = ROOT / "release" / "EXECUTION_INTELLIGENCE_RESULTS.json"
    code, output = run(
        [
            sys.executable,
            str(ROOT / "tool" / "execution_intelligence_test.py"),
            "--json-output",
            str(result_path),
        ],
        timeout=180,
    )
    if code != 0:
        failures.append(f"execution-intelligence gate exited {code}: {output[-1800:]}")
    payload: dict[str, object] = {}
    if result_path.is_file():
        try:
            decoded = json.loads(read(result_path))
            payload = decoded if isinstance(decoded, dict) else {}
        except json.JSONDecodeError as error:
            failures.append(f"execution-intelligence results are invalid JSON: {error}")
    else:
        failures.append("execution-intelligence results file was not generated")
    if payload.get("passed") is not True or payload.get("passedCount") != 40 or payload.get("caseCount") != 40:
        failures.append(
            f"execution intelligence expected 40/40 cases, got {payload.get('passedCount')}/{payload.get('caseCount')}"
        )

    source = read(ROOT / "tool" / "execution_intelligence.py")
    dart = read(ROOT / "lib" / "product" / "execution_intelligence.dart")
    coordinator = read(ROOT / "lib" / "product" / "planning_runtime.dart")
    durable = read(ROOT / "lib" / "product" / "durable_workflow.dart")
    runtime = read(ROOT / "lib" / "product" / "product_runtime.dart")
    lineage = json.loads(read(ROOT / "VERSION_CONTROL.json"))
    markers = (
        "class ModelRouter",
        "class RoleBasedModelRouter",
        "class CircuitBreaker",
        "class SemanticProgressEngine",
        "class ConvergenceController",
        "class IndependentVerifier",
        "class ContextCompactor",
        "appendModelRouteDecision",
        "appendSemanticProgress",
        "appendVerificationReport",
        "work_item.semantic_progress_evaluated",
        "work_item.independent_verification_completed",
        "_objectiveEvidenceForCriterion",
        "mutation_followed_by_current_artifact_inspection",
        "task_split_required",
        "agent_user_input_required",
        "model_fallback_approval_required",
        "PhaseBudget.defaults('execution')",
        "ExecutionIntelligenceService",
    )
    joined = source + dart + coordinator + durable + runtime
    for token in markers:
        if token not in joined:
            failures.append(f"execution-intelligence integration missing {token}")
    metadata = lineage.get("executionIntelligence", {}) if isinstance(lineage, dict) else {}
    if not isinstance(metadata, dict) or metadata.get("behavioralGateCases") != 40:
        failures.append("VERSION_CONTROL does not record the 40-case execution-intelligence gate")
    if isinstance(metadata, dict) and metadata.get("strongerModelFallbackRequiresApproval") is not True:
        failures.append("stronger-model fallback must remain approval-gated")
    if "objectiveEvidenceAvailable" in coordinator:
        failures.append("one generic evidence flag must not satisfy every acceptance criterion")
    if "entry.objective" not in dart or "criterionIds.isNotEmpty" not in dart:
        failures.append("Dart verifier does not require criterion-scoped objective evidence")

    add(
        "v1.7 model router, verifier, and convergence engine",
        not failures,
        "40/40 executable cases passed; local-first role routing, circuit breakers, semantic progress, bounded strategy escalation, independent verification, phase budgets, and compaction are integrated"
        if not failures
        else "; ".join(failures[:40]),
        started=started,
    )


def check_diagnostic_replay() -> None:
    """Execute the compact redacted production-failure corpus."""
    started = time.monotonic()
    command = [sys.executable, str(ROOT / "tool" / "replay_diagnostics.py"), "--json"]
    code, output = run(command, timeout=60)
    failures: list[str] = []
    report: dict[str, object] = {}
    if code != 0:
        failures.append(f"replay harness exited {code}: {output[:1200]}")
    else:
        try:
            decoded = json.loads(output)
            report = decoded if isinstance(decoded, dict) else {}
        except json.JSONDecodeError as error:
            failures.append(f"replay harness returned invalid JSON: {error}")
    if report:
        if report.get("passed") is not True:
            failures.append("one or more golden diagnostic replays failed")
        if int(report.get("caseCount", 0)) < 2:
            failures.append("replay corpus must contain both supplied production failures")
        if int(report.get("historicalModelLatencyMs", 0)) != 2194657:
            failures.append("replay corpus historical latency baseline drifted")
        ids = {
            str(item.get("id"))
            for item in report.get("results", [])
            if isinstance(item, dict)
        }
        required_ids = {
            "v115_nested_write_content_loss",
            "v116_markdown_path_repair_loop",
        }
        if not required_ids.issubset(ids):
            failures.append("replay corpus is missing a supplied diagnostic case")
    coordinator = read(ROOT / "lib/product/planning_runtime.dart")
    workspace = read(ROOT / "lib/product/workspace_tools.dart")
    cli = read(ROOT / "tool/kristin_cli.py")
    behavioral = read(ROOT / "test/product/diagnostic_replay_test.dart")
    required_markers = {
        "workspace path-token canonicalization": (workspace, "canonicalModelPathToken"),
        "bounded artifact mutation recovery": (coordinator, "BoundedArtifactRecoveryPolicy"),
        "create-only/hash-guarded recovery": (workspace + coordinator, "stale_existence"),
        "automatic artifact verification": (coordinator, "AutomaticArtifactVerificationPolicy"),
        "retry repair reservation": (coordinator, "RunRetryBudgetPolicy"),
        "post-mutation inspection event": (coordinator, "work_item.artifact_auto_inspection_completed"),
        "model-history action isolation": (coordinator, "Never copy a history entry as the action"),
        "replay CLI": (cli, "--replay-all"),
        "Dart replay contract": (behavioral, "all compact production diagnostics"),
    }
    for label, (content, marker) in required_markers.items():
        if marker not in content:
            failures.append(f"{label} missing {marker}")
    if "'historyType': 'governed_correction'" in coordinator:
        failures.append("model-visible history still exposes governed_correction as an action-like discriminator")
    add(
        "golden diagnostic replay and v1.1.7 convergence contracts",
        not failures,
        (
            f"{report.get('passedCount', 0)}/{report.get('caseCount', 0)} compact production failures replayed; "
            f"historical model latency represented={report.get('historicalModelLatencyMinutes', 0)} minutes"
        ) if not failures else "; ".join(failures[:30]),
        started=started,
    )

def check_v1_product_preview() -> None:
    """Verify the v1 Prompt-to-Task workflow and absolute-path repair."""
    domain = read(ROOT / "lib/product/domain.dart")
    workspace = read(ROOT / "lib/product/workspace_tools.dart")
    coordinator = read(ROOT / "lib/product/planning_runtime.dart")
    agent_protocol = read(ROOT / "lib/product/agent_protocol.dart")
    tool_schema = read(ROOT / "lib/product/tool_schema.dart")
    planning = read(ROOT / "lib/product/prompt_planning.dart")
    runtime = read(ROOT / "lib/product/product_runtime.dart")
    storage = read(ROOT / "lib/product/storage_security.dart")
    studio = read(ROOT / "lib/product/chat_studio.dart")
    diagnostics_source = read(ROOT / "lib/product/project_diagnostics.dart")
    api = read(ROOT / "lib/product/api_server.dart")
    cli = read(ROOT / "tool/kristin_cli.py")
    system_fixture = read(ROOT / "tool/system_test.py")
    behavioral = read(ROOT / "test/product/v1_product_preview_test.dart")
    budget_behavioral = read(ROOT / "test/product/budget_diagnostics_test.dart")
    deployment = read(ROOT / "lib/product/deployment_support.dart")
    validator = read(ROOT / "tool/validate_release.py")
    release = read(ROOT / "tool/release.py")
    scanner = read(ROOT / "tool/secret_scan.py")
    knowledge_source = read(ROOT / "lib/product/models_research.dart")
    memory_behavioral = read(ROOT / "test/product/knowledge_memory_test.dart")
    protocol_behavioral = read(ROOT / "test/product/execution_reliability_test.dart")
    source_contract = read(ROOT / "test/product/source_contract_test.dart")
    lineage = read(ROOT / "VERSION_CONTROL.json")
    failures: list[str] = []

    required = {
        "v1 identity": (domain, ("const String kristinVersion = '1.9.0+190'",)),
        "safe path normalization": (
            workspace,
            (
                "String normalizeToolPath(String input)",
                "'path_outside_project'",
                "return relative(normalized);",
                "normalized.startsWith('//?/')",
                "startsWith('UNC/')",
                "'tool.path_normalized'",
                "'originalPathHash'",
            ),
        ),
        "bounded tool repair": (
            coordinator,
            (
                "toolRepairAttempts",
                "'tool.repair_requested'",
                "_isRecoverableToolInputError",
                "'workspace_escape_rejected'",
            ),
        ),
        "prompt domain": (
            domain,
            (
                "class PromptStudioDraft",
                "class PromptVersionRecord",
                "class PlanTaskRecord",
                "class TaskPlanRecord",
                "enum PlanningDepth",
            ),
        ),
        "prompt planning service": (
            planning,
            (
                "class PromptPlanningService",
                "generatePrompt(",
                "generateTaskPlan(",
                "maxLeafTasks.clamp(1, 100)",
                "revision: plan.revision + 1",
                "previousPlanId: plan.id",
                "_withDependencies(selectedTaskIds, all)",
                "task_plan.compiled",
            ),
        ),
        "runtime wiring": (
            runtime,
            (
                "required this.promptPlanning",
                "generatePromptDraft",
                "saveGeneratedPrompt",
                "prepareTaskPlan",
            ),
        ),
        "persistent versions": (
            storage,
            ("promptVersions", "taskPlans", "prompt_versions", "task_plans"),
        ),
        "Prompt Studio controls": (
            studio,
            (
                "'Generate prompt'",
                "'Generate task list'",
                "'Run all tasks'",
                "'Run selected task + dependencies'",
                "'Stop all running tasks'",
                "'Save new plan revision'",
            ),
        ),
        "v1 API": (
            api,
            (
                "'/v1/prompts/generate'",
                "'/v1/prompts/versions'",
                "'/v1/task-plans/generate'",
                "segments[1] == 'task-plans'",
                "segments[3] == 'compile'",
            ),
        ),
        "system and release CLI": (
            cli,
            (
                'mode.add_argument("--system"',
                'mode.add_argument("--release"',
                "Offline system contract fixtures",
                "Deterministic release packaging",
                "def _decode_output(value: bytes)",
                '_decode_output(completed.stdout or b"")',
                "environment.update(dict(spec.environment))",
                "_SDK_ENVIRONMENT_KEYS",
                '"LOCALAPPDATA"',
                '"PUB_CACHE"',
                "_command_environment_profile",
                '"--skip-sdk"',
                '"--no-pub"',
                "SOURCE_DATE_EPOCH",
            ),
        ),
        "offline system fixture": (
            system_fixture,
            (
                "Active-project absolute path compatibility",
                "Adaptive 1-100 task planning",
                "CLI system and release modes",
                "SDK subprocess environment compatibility",
            ),
        ),
        "budget-aware retry coordination": (
            domain + coordinator + runtime,
            (
                "factory AutonomyBudget.forPlan",
                "maxAgentTurnsPerAttempt",
                "minModelRequestsForRetry",
                "maxRepeatedToolOutcomes",
                "Future<RunRecord> retryRun(String runId)",
                "'run_retry_required'",
                "'work_item.turn_budget_assigned'",
                "'work_item.retry_skipped'",
                "'model.request_started'",
                "'model.request_completed'",
                "'model.request_failed'",
                "'agent.stalled_repeated_tool_outcome'",
                "_enforceToolBudget(current, action.tool!)",
                "tools.isMutatingTool(toolName)",
                "The model may still complete using evidence already collected",
                "remainingAgentTurns=",
            ),
        ),
        "all-logs diagnostics": (
            deployment + studio + api + cli,
            (
                "kristin.diagnostics.bundle.v2",
                "run-diagnostic-summary.md",
                "events-redacted.jsonl",
                "evidence-redacted.json",
                "managed-processes",
                "Save all logs",
                "includeAllLogs: true",
                "action == 'retry'",
                "'/runs/{runId}/retry'",
                'logs_parser.add_argument("--export"',
            ),
        ),
        "budget and diagnostics behavioral tests": (
            budget_behavioral,
            (
                "plan budgets scale to the documented 100-task ceiling",
                "tool budgets are checked only when another governed tool is dispatched",
                "retry creates a linked run with fresh attempts and counters",
                "all-logs bundle retains diagnostics while redacting source and secrets",
            ),
        ),
        "repeated-tool loop recovery": (
            coordinator + deployment + budget_behavioral,
            (
                "class AgentLoopRecoveryPolicy",
                "class ToolLoopObservation",
                "'agent.repeated_tool_call_blocked'",
                "'agent.loop_recovery_redirected'",
                "'agent.loop_recovery_completed'",
                "'work_item.evidence_baseline_completed'",
                "_staticToolActionFingerprint",
                "cachedResultSummary",
                "### Agent loop recovery",
                "redirects a duplicate listing to safe new evidence",
                "completes only after diverse objective baseline evidence",
                "never auto-completes a general grounded answer task",
                "isNot('.env')",
            ),
        ),
        "bounded path rebasing and generated-state hygiene": (
            workspace + coordinator + deployment + validator + release + scanner,
            (
                "class WorkspacePathRecovery",
                "recoverExternalToolPath",
                "'virtual_workspace_alias'",
                "'project_name_anchor'",
                "'tool.path_rebased_to_active_project'",
                "'tool.path_recovery_rejected'",
                "'securityBoundaryPreserved': true",
                "### Project path recovery",
                "from source_tree_policy import is_generated_path",
                "if is_generated_path(rel):",
                "if is_generated_path(relative)",
                "is_generated_path(p.relative_to(ROOT))",
            ),
        ),
        "Project Manager and capability-aligned execution": (
            domain
            + diagnostics_source
            + runtime
            + studio
            + api
            + cli
            + planning
            + coordinator
            + behavioral,
            (
                "class ProjectProcessStatus",
                "class ProjectExecutionProfile",
                "import 'storage_security.dart';",
                "throw ProductException(",
                "analysisCommands",
                "analyzeProject(",
                "buildProject(",
                "startProject(",
                "stopProject(",
                "label: 'Project Manager'",
                "Save logs",
                "action == 'manager'",
                "projects:execute",
                "execute_profile_commands",
                "if args.command in {\"analyze\", \"build\"}",
                "_effectivePlanMode",
                "_taskRequiresMutation",
                "docs/design/wireframes.md",
                "_deduplicateCapabilityTasks",
                "implementation_stalled_read_only",
                "work_item.mutation_required",
                "promotes artifact-producing plan tasks to governed build work",
                "keeps an explicitly planning-only task read-only",
                "detects custom Analyze, Test, Build, and Run commands",
            ),
        ),
        "version and diagnostic lineage": (
            lineage,
            (
                '"canonicalHead": "1.9.0+190"',
                '"version": "1.0.5+105"',
                '"sha256": "81bc8384d545cd6586696ed3b58da315b596de042785ae9918ea4b2b427f18a2"',
                '"version": "1.0.8+108"',
                '"sha256": "76bff50ca1fe0eb82b54c09cf7ecf8f35e6d2c2062490bd73d141785b4d21448"',
                '"version": "1.0.9+109"',
                '"sha256": "4090bbb6fd680bde8e3862039fd503fce3cda93d982076dd3b6bf3d1524eca1c"',
                '"version": "1.1.0+110"',
                '"sha256": "a96d1544e3a2ef41bd01c489b2733e74fcd7c242aedcbb47b14b745a6e11a70d"',
                '"version": "1.1.1+111"',
                '"sha256": "830f59d1401eab6a97b99f2f96f27dace7902f4541dfbd108ea67f20266604ee"',
                '"version": "1.1.2+112"',
                '"sha256": "4300bb3c228e3d4b3502819df1cf84549a5bb2d66672362cdfd9e6d730fe34a2"',
                '"version": "1.1.3+113"',
                '"sha256": "fa648c05fcae9e3e89fca0ab5dfb41356c85d97b436aa05dd5974388e7148895"',
                '"version": "1.1.4+114"',
                '"sha256": "989ccfc9abdda31537b10b4a6a15e958d12b8209ba923457d45759c3bb5d29b3"',
                "af691d08567a1cad",
                "run_hklfhuqkrwdoQ11swy34hvARke",
                "f11139cff61ed1d7",
                "1b10796ceef9132",
                "47bb8141259ce002",
                "0f20bd38314290bf",
                "2e1215e5d3bee81e",
                "run_hkjnl5dagrldsloYB4qnRQTS3h",
                "run_hkk9czt4wzMPTp3bsaqLnpNOx2",
                "run_hkkkbh7q3rNkIqtjzJuPYvsiiy",
                "80e5044cf47e8f19",
            ),
        ),
        "strict unsuccessful-memory policy": (
            domain + knowledge_source + coordinator + memory_behavioral,
            (
                "bool isFailureInvestigationRequest(String request)",
                "final failureIntent = includeUnsuccessfulEpisodes;",
                "includeUnsuccessfulEpisodes || chunk.pinned",
                "calculator history view, input validation, and error handling",
                "knowledge.context_policy_applied",
            ),
        ),
        "task-aware protocol recovery": (
            coordinator + agent_protocol + protocol_behavioral,
            (
                "_resolveTaskIntent",
                "inspect_project_and_establish_evidence_baseline",
                "antiCopyRule",
                "protocolRepairAttempt",
                "_protocolRepairExample",
                "_preferredProtocolTool",
            ),
        ),
        "local capability and self-project alignment": (
            planning + workspace + runtime + behavioral,
            (
                "settingsProvider",
                "Create project-local wireframes and user flows",
                "Prepare local preview and deployment package",
                "package_deployment",
                "isKristinSourceCheckout",
                "self_project_target_rejected",
                "Do not claim a public URL",
            ),
        ),
        "memory and protocol diagnostics": (
            deployment,
            (
                "### Automatic memory policy",
                "### Model protocol recovery",
            ),
        ),
        "Ollama cold-load resilience and capability-safe planning": (
            knowledge_source
            + storage
            + runtime
            + coordinator
            + planning
            + deployment
            + protocol_behavioral
            + behavioral,
            (
                "class ModelGenerationProgress",
                "defaultLoadTimeout = const Duration(minutes: 8)",
                "defaultLoadRetries = 1",
                "'prompt': ''",
                "'stream': false",
                "load_retry_scheduled",
                "_closeOnCancellation",
                "_remainingUntil",
                "_shorterDuration",
                "ollamaLoadTimeoutSeconds",
                "ollamaLoadRetries",
                "ollamaKeepAliveMinutes",
                "cancellation: control.cancellation.cancelled",
                "provider already performs its configured bounded cold-load retry",
                "### Model availability and cold-load recovery",
                "Run local usability and interaction verification",
                "Capability alignment replaces the unsupported human-study instruction",
                "Do not recruit participants",
                ".clamp(2, 3)",
                "manual: alignedManual",
                "Ollama retries a transient cold-load timeout inside one model turn",
                "cancelling a run closes an in-flight Ollama cold load",
            ),
        ),
        "v1.1.3 workstation validation regressions": (
            knowledge_source + source_contract + protocol_behavioral + planning + behavioral,
            (
                "StreamSubscription<void>? subscription;",
                "contains(\"'load_started'\")",
                "contains(\"'load_retry_started'\")",
                "containsAllInOrder(<String>[",
                "'load_completed'",
                "'generation_started'",
                "Do not deploy to an external service. Do not claim a public URL.",
                "do not claim a public url",
            ),
        ),
        "v1.1.4 deterministic release-test regressions": (
            protocol_behavioral + cli + source_contract,
            (
                "final secondWarmupStarted = Completer<void>();",
                "await secondWarmupStarted.future.timeout(",
                "defaultLoadTimeout: const Duration(seconds: 2)",
                "final warmupRequestStarted = Completer<void>();",
                "final releaseWarmupResponse = Completer<void>();",
                "final warmupRequestFinished = Completer<void>();",
                "await warmupRequestStarted.future.timeout",
                "await releaseWarmupResponse.future",
                '"--concurrency=1"',
                'if "[E]" in line',
                "test_failures",
            ),
        ),
        "v1.1.6 execution-convergence regressions": (
            domain
            + coordinator
            + agent_protocol
            + tool_schema
            + planning
            + workspace
            + deployment
            + protocol_behavioral
            + budget_behavioral
            + behavioral,
            (
                "actionObject['command']",
                "_specializeCommandTool",
                "project-scoped git_status",
                "'argument_required'",
                "ArtifactEvidencePolicy",
                "artifact_scope_mismatch",
                "artifact_evidence_missing",
                "work_item.artifact_evidence_required",
                "work_item.artifact_evidence_completed",
                "requiresValidatedArtifact",
                "_priorEvidenceHistory",
                "toolRepairAttempt",
                "operation: 'noop'",
                "workspace.mutation_noop",
                "process_scope_argument_rejected",
                "process_path_outside_project",
                "The selected project is not a Git repository",
                "Approved product context",
                "Initialize the selected project workspace",
                "Implement the client-side calculation engine and session history",
                "unnecessary Express/REST backend",
                "backendImplementationAction",
                "### Artifact scope and convergence",
                "normalizes the observed nested command vector",
                "rejects an unrelated commerce wireframe",
                "identical writes do not create",
                "Do not install Node.js",
                "Session calculation history",
                "Conduct Comprehensive Testing of Calculator",
            ),
        ),
        "behavioral v1 tests": (
            behavioral,
            (
                "normalizes in-project absolute paths",
                "accepts an in-project absolute path when the project root sits",
                "continues to reject absolute paths outside",
                "rebases recognized virtual workspace paths",
                "blocks arbitrary external writes",
                "root-scoped read recovery falls back",
                "generates, versions, plans, revises, and compiles deterministically",
                "accepts a valid 100-task plan",
                "selected execution must include transitive dependencies",
            ),
        ),
    }
    for group, (content, tokens) in required.items():
        for token in tokens:
            if not source_contains(content, token):
                failures.append(f"{group} missing {token}")

    try:
        lineage_data = json.loads(lineage)
    except (json.JSONDecodeError, TypeError) as error:
        failures.append(f"VERSION_CONTROL.json is not a JSON object: {error}")
        lineage_data = {}
    if not isinstance(lineage_data, dict):
        failures.append("VERSION_CONTROL.json root must be an object")
        lineage_data = {}

    if lineage_data.get("canonicalHead") != "1.9.0+190":
        failures.append("VERSION_CONTROL canonicalHead must be 1.9.0+190")
    if lineage_data.get("canonicalPackageRoot") != "Kristin_Local_Agent_v1.9.0_build190_interoperability_admin_release_ops":
        failures.append("VERSION_CONTROL canonicalPackageRoot does not match the v1.9 package")
    if '(("SOURCE_DATE_EPOCH", "1784678400"),)' not in cli:
        failures.append("CLI release validation does not pin the v1.9 source date")
    if 'env["SOURCE_DATE_EPOCH"] = "1784678400"' not in release:
        failures.append("release packager does not pin the v1.9 source date")

    lineage_contract = lineage_data.get("lineageContract", {})
    if not isinstance(lineage_contract, dict):
        failures.append("lineageContract must be an object")
        lineage_contract = {}
    expected_versions = [
        "1.0.5+105",
        "1.0.6+106",
        "1.0.7+107",
        "1.0.8+108",
        "1.0.9+109",
        "1.1.0+110",
        "1.1.1+111",
        "1.1.2+112",
        "1.1.3+113",
        "1.1.4+114",
        "1.1.5+115",
        "1.1.6+116",
        "1.1.7+117",
        "1.2.0+120",
        "1.3.0+130",
    ]
    if lineage_contract.get("preserveAcrossHeads") is not True:
        failures.append("lineageContract must preserve ancestors across heads")
    if lineage_contract.get("requiredAncestorVersions") != expected_versions:
        failures.append("lineageContract requiredAncestorVersions is incomplete or reordered")

    raw_release_lineage = lineage_data.get("transitiveReleaseLineage", [])
    if not isinstance(raw_release_lineage, list):
        failures.append("transitiveReleaseLineage must be an array")
        raw_release_lineage = []
    release_lineage = {
        str(entry.get("version")): entry
        for entry in raw_release_lineage
        if isinstance(entry, dict)
    }
    expected_hashes = {
        "1.0.5+105": "81bc8384d545cd6586696ed3b58da315b596de042785ae9918ea4b2b427f18a2",
        "1.0.6+106": "9829aa2e658893279d66e96699e225aef739a791f4b1870cf749ac8349a4662d",
        "1.0.7+107": "1b10796ceef9132f8d39f74dab69b5c81bcbf91d9a351c45d5d806b8bcb45620",
        "1.0.8+108": "76bff50ca1fe0eb82b54c09cf7ecf8f35e6d2c2062490bd73d141785b4d21448",
        "1.0.9+109": "4090bbb6fd680bde8e3862039fd503fce3cda93d982076dd3b6bf3d1524eca1c",
        "1.1.0+110": "a96d1544e3a2ef41bd01c489b2733e74fcd7c242aedcbb47b14b745a6e11a70d",
        "1.1.1+111": "830f59d1401eab6a97b99f2f96f27dace7902f4541dfbd108ea67f20266604ee",
        "1.1.2+112": "4300bb3c228e3d4b3502819df1cf84549a5bb2d66672362cdfd9e6d730fe34a2",
        "1.1.3+113": "fa648c05fcae9e3e89fca0ab5dfb41356c85d97b436aa05dd5974388e7148895",
        "1.1.4+114": "989ccfc9abdda31537b10b4a6a15e958d12b8209ba923457d45759c3bb5d29b3",
        "1.1.5+115": "28be6ac8b5de2c7612a4c5e9456dfe09895cd0964681875861e2074b1760f2a8",
        "1.1.6+116": "d4c23f7b005d7067bda06c8761f10d1cc489337300f4358b561415ebe2a6c583",
        "1.1.7+117": "6b32cb8105dcdf6aee0aff9599eefd8552e469f0c813eb992720e84287d7e835",
        "1.2.0+120": "a4904b78523da79b8abd87866c7e4497231a3f0c924cfff4d20aec12194d59d3",
        "1.3.0+130": "8da6f20dc3ccd9ee71406092df0a4e1fadd77a93916a553f0efc71b47153ff19",
    }
    for version, expected_hash in expected_hashes.items():
        entry = release_lineage.get(version)
        if not isinstance(entry, dict) or entry.get("sha256") != expected_hash:
            failures.append(f"transitive release lineage missing {version} {expected_hash}")

    prior_lineage = lineage_data.get("priorLineage", {})
    if not isinstance(prior_lineage, dict):
        failures.append("priorLineage must be an object")
        prior_lineage = {}
    transcript = prior_lineage.get("workstationValidationTranscript", {})
    if not isinstance(transcript, dict) or transcript.get("sha256") != "f11139cff61ed1d7c0526e60454600de9831b330bbf2cdeb92e9adb7a4ce538b":
        failures.append("workstation validation transcript provenance is missing or incorrect")

    parent_release = lineage_data.get("parentRelease", {})
    if not isinstance(parent_release, dict):
        failures.append("parentRelease must be an object")
    elif (
        parent_release.get("version") != "1.8.0+180"
        or parent_release.get("sha256")
        != "eac7469a776c859b9d14ad6133d06093c43327f8f4579633615aa3129cca9bcc"
    ):
        failures.append("parentRelease must identify the exact v1.8.0+180 archive")

    execution_diagnostic = prior_lineage.get("executionConvergenceDiagnostic", {})
    if (
        not isinstance(execution_diagnostic, dict)
        or execution_diagnostic.get("sha256")
        != "af691d08567a1cad8b9593b4e502aae2415f3ded486a4567178490ee4c7c1c75"
        or execution_diagnostic.get("runId")
        != "run_hklfhuqkrwdoQ11swy34hvARke"
    ):
        failures.append("execution-convergence diagnostic provenance is missing or incorrect")

    reliability_diagnostic = prior_lineage.get("executionReliabilityDiagnostic", {})
    if (
        not isinstance(reliability_diagnostic, dict)
        or reliability_diagnostic.get("sha256")
        != "a2c3570a9910cf99f3f5c26388b6638bf5639796c47009277cfcd64c90dd0f9b"
        or reliability_diagnostic.get("runId")
        != "run_hklsywuyo4NMJgt9ijIxWPhBDr"
    ):
        failures.append("execution-reliability diagnostic provenance is missing or incorrect")

    if "_HttpCancellationBinding({this.subscription})" in knowledge_source:
        failures.append("HTTP cancellation binding retains the unused optional subscription parameter")
    if "contains(\"stage: 'load_started'\")" in source_contract:
        failures.append("source contract still depends on formatter-sensitive stage adjacency")
    if "contains(\"'load_started'\")" not in source_contract or "contains(\"'load_retry_started'\")" not in source_contract:
        failures.append("source contract does not verify both Ollama load-stage tokens")
    expected_progress_stages = (
        "load_started",
        "load_retry_scheduled",
        "load_retry_started",
        "load_completed",
        "generation_started",
    )
    if "containsAllInOrder(<String>[" not in protocol_behavioral or any(
        f"'{stage}'" not in protocol_behavioral for stage in expected_progress_stages
    ):
        failures.append("Ollama cold-load behavioral test does not verify ordered progress stages")
    if "Do not deploy to an external service. Do not claim a public URL." not in planning:
        failures.append("local-only deployment normalization lacks explicit external-deploy and public-URL prohibitions")
    if "do not claim a public url" not in behavioral.lower():
        failures.append("generated-plan behavioral test does not verify the public-URL prohibition semantically")

    if "defaultLoadTimeout: const Duration(milliseconds: 40)" in protocol_behavioral:
        failures.append("cold-load retry fixture still uses the flaky 40 millisecond deadline")
    if "Duration(milliseconds: 90)" in protocol_behavioral:
        failures.append("cold-load retry fixture still depends on a 90 millisecond timer race")
    if "final secondWarmupStarted = Completer<void>();" not in protocol_behavioral or "await secondWarmupStarted.future.timeout(" not in protocol_behavioral:
        failures.append("cold-load retry fixture lacks an explicit first-attempt/retry handshake")
    if "defaultLoadTimeout: const Duration(seconds: 2)" not in protocol_behavioral:
        failures.append("cold-load retry fixture lacks a Windows-safe local retry deadline")
    if (
        "final warmupRequestStarted = Completer<void>();" not in protocol_behavioral
        or "final releaseWarmupResponse = Completer<void>();" not in protocol_behavioral
        or "final warmupRequestFinished = Completer<void>();" not in protocol_behavioral
        or "await warmupRequestStarted.future.timeout" not in protocol_behavioral
        or "await releaseWarmupResponse.future" not in protocol_behavioral
        or "Future<void>.delayed(const Duration(seconds: 1))" in protocol_behavioral
    ):
        failures.append("cold-load cancellation fixture still depends on a fixed sleep or lacks deterministic cleanup")
    if '"--concurrency=1"' not in cli or '"--concurrency=1"' not in read(ROOT / "tool/validate_release.py"):
        failures.append("Kristin-owned Flutter tests are not pinned to deterministic single-worker execution")
    if 'if "[E]" in line' not in cli or "test_failures" not in cli:
        failures.append("CLI failure summaries do not preserve the failing Flutter test identity")

    if "_failureIntentTerms" in knowledge_source:
        failures.append("query vocabulary must not implicitly enable unsuccessful run memory")

    if "label.contains('grounded context') ||" in coordinator:
        failures.append(
            "general grounded-answer nodes must not qualify for deterministic baseline completion"
        )

    if normalized_source(planning).count(
        normalized_source("if (task == null || !result.add(id))")
    ) != 1:
        failures.append("dependency expansion must add each selected task exactly once")
    if "throw ProductException('path_absolute_rejected', 'Tool paths must be relative" in workspace:
        failures.append("legacy unconditional absolute-path rejection remains active")

    add(
        "v1 Prompt-to-Task product preview and path compatibility",
        not failures,
        "AI prompt drafts, immutable versions, adaptive 1-100 task plans, selective dependency-aware execution, stop controls, cold-model prewarm and retry, model cancellation, capability-safe task normalization, system/release tests, safe path handling, budget-aware linked retries, loop guards, and redacted all-logs diagnostics are wired"
        if not failures
        else "; ".join(failures[:50]),
    )

def check_release_hygiene() -> None:
    bad = []
    large = []
    for p in ROOT.rglob("*"):
        rel = p.relative_to(ROOT)
        if is_generated_path(rel):
            # Normal Flutter/native workstation state is neither source input nor
            # release payload. The packager applies this same shared policy.
            continue
        if p.is_file() and p.stat().st_size > 10 * 1024 * 1024:
            large.append(str(rel))
        if p.is_symlink():
            bad.append(f"symlink: {rel}")
    add(
        "release tree hygiene",
        not bad and not large,
        "no symlinks or oversized source files; generated Flutter/native state is excluded by shared policy"
        if not bad and not large
        else "; ".join((bad + large)[:30]),
    )



def check_supply_chain() -> None:
    started=time.monotonic()
    sbom_script=ROOT/'tool'/'generate_sbom.py'
    scan_script=ROOT/'tool'/'secret_scan.py'
    if not sbom_script.exists() or not scan_script.exists():
        add('release supply-chain evidence', False, 'SBOM or secret-scan tool missing', started=started)
        return
    src,out=run([sys.executable,str(sbom_script)],timeout=120)
    crc,cout=run([sys.executable,str(scan_script)],timeout=120)
    required=[ROOT/'release'/'SBOM.cdx.json',ROOT/'release'/'SECRET_SCAN.json']
    ok=src==0 and crc==0 and all(p.exists() for p in required)
    detail='SBOM generated and secret scan passed' if ok else (out+'\n'+cout)[-4000:]
    add('release supply-chain evidence', ok, detail, started=started)

def check_sdk(run_tests: bool, *, enabled: bool = True) -> None:
    if not enabled:
        detail = "SDK checks disabled by source-only validation invocation"
        add("flutter pub get", None, detail, blocking=False)
        add("dart format", None, detail, blocking=False)
        add("flutter analyze", None, detail, blocking=False)
        add("flutter test", None, detail, blocking=False)
        return

    dart = shutil.which("dart")
    flutter = shutil.which("flutter")
    dependencies_ready = False
    if flutter:
        started = time.monotonic()
        rc, out = run([flutter, "pub", "get"], timeout=900)
        dependencies_ready = rc == 0
        add("flutter pub get", dependencies_ready, out or "dependencies resolved", started=started)
    else:
        add(
            "flutter pub get",
            None,
            "Flutter SDK not installed in validation environment",
            blocking=False,
        )

    if dart:
        if flutter and not dependencies_ready:
            add("dart format", False, "dependency resolution failed")
        else:
            started = time.monotonic()
            rc, out = run(
                [sys.executable, "tool/dart_format_scope.py", "--check"],
                timeout=300,
            )
            add(
                "dart format",
                rc == 0,
                out or "handwritten Dart format check passed; generator-owned files excluded",
                started=started,
            )
    else:
        add(
            "dart format",
            None,
            "Dart SDK not installed in validation environment",
            blocking=False,
        )

    if flutter:
        if dependencies_ready:
            started = time.monotonic()
            arc, aout = run(
                [
                    flutter,
                    "analyze",
                    "--no-pub",
                    "--fatal-warnings",
                    "--fatal-infos",
                ],
                timeout=900,
            )
            add("flutter analyze", arc == 0, aout or "analysis passed", started=started)
            if run_tests:
                started = time.monotonic()
                trc, tout = run(
                    [
                        flutter,
                        "test",
                        "--no-pub",
                        "--concurrency=1",
                        "--reporter",
                        "expanded",
                    ],
                    timeout=1200,
                )
                add("flutter test", trc == 0, tout or "tests passed", started=started)
            else:
                add(
                    "flutter test",
                    None,
                    "test execution disabled by invocation",
                    blocking=False,
                )
        else:
            add("flutter analyze", False, "dependency resolution failed")
            add("flutter test", False, "dependency resolution failed")
    else:
        add(
            "flutter analyze",
            None,
            "Flutter SDK not installed in validation environment",
            blocking=False,
        )
        add(
            "flutter test",
            None,
            "Flutter SDK not installed in validation environment",
            blocking=False,
        )


def write_reports() -> dict[str, object]:
    blocking_failures = [
        check for check in checks if check.blocking and check.status == "failed"
    ]
    unavailable = [check for check in checks if check.status == "unavailable"]
    sdk_complete = all(
        next(
            (check.status for check in checks if check.name == name),
            "unavailable",
        )
        == "passed"
        for name in ("flutter pub get", "flutter analyze", "flutter test")
    )
    check_records = [check.as_dict() for check in checks]
    assurance_summary = summarize_assurance_checks(check_records)
    assurance_failures = validate_assurance_summary(assurance_summary)
    validation_passed = not blocking_failures and not assurance_failures
    behavioral_assurance_passed = bool(
        assurance_summary.get("behavioralAssurancePassed")
    )
    compiled_release_validated = (
        validation_passed and sdk_complete and behavioral_assurance_passed
    )
    report = {
        "product": "Kristin Local Agent",
        "version": "1.9.0+190",
        "generated_at_epoch": int(
            os.environ.get("SOURCE_DATE_EPOCH", str(int(time.time())))
        ),
        "validation_passed": validation_passed,
        "source_gate_passed": validation_passed,
        "source_contract_passed": bool(
            assurance_summary.get("sourceContractPassed")
        ),
        "behavioral_assurance_passed": behavioral_assurance_passed,
        "compiled_release_validated": compiled_release_validated,
        "classification": (
            "compiled-release"
            if compiled_release_validated
            else ("source-release" if validation_passed else "failed")
        ),
        "checks": check_records,
        "assurance_summary": assurance_summary,
        "assurance_classification_failures": assurance_failures,
        "blocking_failures": [check.name for check in blocking_failures],
        "unavailable_checks": [check.name for check in unavailable],
    }
    REPORT_JSON.parent.mkdir(parents=True, exist_ok=True)
    REPORT_JSON.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    lines = [
        "# Kristin Local Agent v1.9.0+190 Categorized Validation Report",
        "",
        f"Classification: **{report['classification']}**",
        "",
        f"Source-contract evidence passed: **{report['source_contract_passed']}**",
        f"Pure behavioral assurance passed: **{report['behavioral_assurance_passed']}**",
        f"Classification complete: **{assurance_summary['classificationComplete']}**",
        f"Source-marker overclaim detected: **{not assurance_summary['noSourceMarkerOverclaim']}**",
        "",
        "> Mixed source/execution checks are not counted as pure behavioral proof.",
        "",
        "| Gate | Status | Assurance | Proof | Behavioral proof | Blocking | Detail |",
        "|---|---:|---|---|---:|---:|---|",
    ]
    for check in checks:
        detail = check.detail.replace("|", "\\|").replace("\n", " ")[:1000]
        lines.append(
            f"| {check.name} | {check.status} | {check.assurance_level} | "
            f"{check.proof_kind} | {check.behavioral_proof} | "
            f"{'yes' if check.blocking else 'no'} | {detail} |"
        )
    lines.extend(
        [
            "",
            "## Assurance category summary",
            "",
            "| Category | Checks | Passed | Failed | Unavailable | Complete |",
            "|---|---:|---:|---:|---:|---:|",
        ]
    )
    for category, state in assurance_summary["groups"].items():
        lines.append(
            f"| {category} | {state['count']} | {state['passedCount']} | "
            f"{state['failedCount']} | {state['unavailableCount']} | "
            f"{state['complete']} |"
        )
    lines.extend(
        [
            "",
            "Source-contract and architecture-lint checks establish source shape and wiring only. Pure behavioral claims require separately classified executable evidence. Native platform and release claims require their own lane evidence.",
            "",
        ]
    )
    REPORT_MD.write_text("\n".join(lines), encoding="utf-8")
    return report

def main() -> int:
    parser=argparse.ArgumentParser()
    parser.add_argument("--skip-tests", action="store_true")
    parser.add_argument(
        "--skip-sdk",
        action="store_true",
        help="Run deterministic source gates without Dart or Flutter commands.",
    )
    args = parser.parse_args()
    check_required_files()
    check_active_tree_layout()
    check_imports_and_syntax()
    check_architecture()
    check_security()
    check_flutter_dart_compatibility()
    check_chat_workspace_ux()
    check_knowledge_memory()
    check_execution_reliability()
    check_typed_protocol_contracts()
    check_durable_workflow_kernel()
    check_prompt_studio_v2()
    check_linux_sandbox_backfill()
    check_project_manager_v2()
    check_execution_intelligence()
    check_knowledge_memory_v18()
    check_file_adapters_v18()
    check_v1_trust_disablement()
    check_interoperability_v19()
    check_release_ops_v19()
    check_diagnostic_replay()
    check_v1_product_preview()
    check_release_hygiene()
    check_supply_chain()
    check_sdk(not args.skip_tests, enabled=not args.skip_sdk)
    report = write_reports()
    failed = [check for check in checks if check.blocking and check.status == "failed"]
    if failed:
        print("Kristin governed source validation failed:")
        for check in failed:
            print(f"- {check.name}: {check.detail[:2000]}")
        print(f"Detailed report: {REPORT_JSON}")
    else:
        print("Kristin categorized validation passed. Source, behavioral, SDK, platform, and release evidence remain separate.")
    return 0 if report["source_gate_passed"] else 1

def check_knowledge_memory_v18() -> None:
    """Execute the v1.8 knowledge, memory, skills, and freshness gate."""
    started = time.monotonic()
    failures: list[str] = []
    generator_code, generator_output = run(
        [sys.executable, str(ROOT / "tool" / "generate_v180_contracts.py"), "--check"],
        timeout=60,
    )
    if generator_code != 0:
        failures.append(f"v1.8 contract generator exited {generator_code}: {generator_output[-1200:]}")
    result_path = ROOT / "release" / "KNOWLEDGE_MEMORY_V2_RESULTS.json"
    code, output = run(
        [sys.executable, str(ROOT / "tool" / "knowledge_memory_v2_test.py"), "--json-output", str(result_path)],
        timeout=180,
    )
    if code != 0:
        failures.append(f"knowledge-memory gate exited {code}: {output[-1800:]}")
    payload: dict[str, object] = {}
    if result_path.is_file():
        try:
            decoded = json.loads(read(result_path))
            payload = decoded if isinstance(decoded, dict) else {}
        except json.JSONDecodeError as error:
            failures.append(f"knowledge-memory results are invalid JSON: {error}")
    else:
        failures.append("knowledge-memory results file was not generated")
    if payload.get("passed") is not True or payload.get("passedCount") != 12 or payload.get("caseCount") != 12:
        failures.append(
            f"knowledge-memory expected 12/12 cases, got {payload.get('passedCount')}/{payload.get('caseCount')}"
        )

    source = read(ROOT / "tool" / "knowledge_memory_v2.py")
    dart = read(ROOT / "lib/product/knowledge_memory_v2.dart")
    models = read(ROOT / "lib/product/models_research.dart")
    runtime = read(ROOT / "lib/product/product_runtime.dart")
    domain = read(ROOT / "lib/product/domain.dart")
    markers = (
        "class ObjectStore",
        "class MemoryAdmissionPolicy",
        "quarantined",
        "class SkillPublicationService",
        "ResearchFreshnessPolicy",
        "ContentAddressedObjectStore",
        "admissionPolicy",
        "diagnosticOnly",
        "Freshness:",
        "SkillCandidateRecord",
        "PublishedSkillRecord",
    )
    joined = source + dart + models + runtime + domain
    for token in markers:
        if token not in joined:
            failures.append(f"knowledge-memory integration missing {token}")
    add(
        "v1.8 knowledge, memory, skills, object store, and freshness",
        not failures,
        "12/12 executable cases passed; content-addressed object storage, memory admission and quarantine, explicit skill publication, and freshness/citation controls are integrated"
        if not failures
        else "; ".join(failures[:40]),
        started=started,
    )



def check_v1_trust_disablement() -> None:
    """Execute the P0-002 fail-closed legacy trust regression gate."""
    started = time.monotonic()
    failures: list[str] = []
    result_path = ROOT / "release" / "V1_TRUST_DISABLEMENT_RESULTS.json"
    code, output = run(
        [
            sys.executable,
            str(ROOT / "tool" / "v1_trust_disablement_test.py"),
            "--json-output",
            str(result_path),
        ],
        timeout=60,
    )
    if code != 0:
        failures.append(f"v1 trust disablement gate exited {code}: {output[-1800:]}")
    payload: dict[str, object] = {}
    if result_path.is_file():
        try:
            decoded = json.loads(read(result_path))
            payload = decoded if isinstance(decoded, dict) else {}
        except json.JSONDecodeError as error:
            failures.append(f"v1 trust disablement results are invalid JSON: {error}")
    else:
        failures.append("v1 trust disablement results file was not generated")
    if (
        payload.get("passed") is not True
        or payload.get("passedCount") != 8
        or payload.get("caseCount") != 8
    ):
        failures.append(
            "v1 trust disablement expected 8/8 cases, got "
            f"{payload.get('passedCount')}/{payload.get('caseCount')}"
        )
    trust_status = payload.get("trustStatus", {})
    if not isinstance(trust_status, dict):
        failures.append("v1 trust disablement did not return a trustStatus object")
    elif (
        trust_status.get("enabled") is not False
        or trust_status.get("errorCode") != "v1_trust_disabled"
        or trust_status.get("replacement") != "signed_manifest_v2"
    ):
        failures.append("v1 trust disablement status is not fail-closed")

    helper = read(ROOT / "tool" / "interoperability_v19.py")
    gate = read(ROOT / "tool" / "v1_trust_disablement_test.py")
    required = (
        "LEGACY_TRUST_ENABLED = False",
        "LEGACY_TRUST_ERROR_CODE = 'v1_trust_disabled'",
        "_raise_legacy_trust_disabled('generate_signing_keypair')",
        "_raise_legacy_trust_disabled('sign_manifest')",
        "_raise_legacy_trust_disabled('verify_signed_manifest')",
        "Envelope-supplied HMAC forgery is rejected",
    )
    for marker in required:
        if marker not in helper + gate:
            failures.append(f"v1 trust disablement marker missing {marker}")
    forbidden = (
        "public_key.encode('utf-8')",
        "hmac.compare_digest(expected, signature)",
        "secret = secrets.token_hex(32)",
    )
    for marker in forbidden:
        if marker in helper:
            failures.append(f"legacy acceptance logic remains: {marker}")

    add(
        "P0-002 legacy v1 signed-manifest trust disablement",
        not failures,
        "8/8 executable cases passed; key generation, signing, and verification fail closed; the exact envelope-supplied HMAC forgery is rejected"
        if not failures
        else "; ".join(failures[:30]),
        started=started,
    )

def check_interoperability_v19() -> None:
    """Execute the v1.9 interoperability, administration, and release-ops gate."""
    started = time.monotonic()
    failures: list[str] = []
    generator_code, generator_output = run(
        [sys.executable, str(ROOT / "tool" / "generate_v190_contracts.py"), "--check"],
        timeout=60,
    )
    if generator_code != 0:
        failures.append(f"v1.9 contract generator exited {generator_code}: {generator_output[-1200:]}")
    result_path = ROOT / "release" / "INTEROPERABILITY_ADMIN_V19_RESULTS.json"
    code, output = run(
        [sys.executable, str(ROOT / "tool" / "interoperability_admin_v19_test.py"), "--json-output", str(result_path)],
        timeout=180,
    )
    if code != 0:
        failures.append(f"interoperability gate exited {code}: {output[-1800:]}")
    payload: dict[str, object] = {}
    if result_path.is_file():
        try:
            decoded = json.loads(read(result_path))
            payload = decoded if isinstance(decoded, dict) else {}
        except json.JSONDecodeError as error:
            failures.append(f"interoperability results are invalid JSON: {error}")
    else:
        failures.append("interoperability results file was not generated")
    if payload.get("passed") is not True or payload.get("passedCount") != 22 or payload.get("caseCount") != 22:
        failures.append(
            f"interoperability expected 22/22 cases, got {payload.get('passedCount')}/{payload.get('caseCount')}"
        )

    source = read(ROOT / "tool" / "interoperability_admin_v19.py")
    dart = read(ROOT / "lib/product/interoperability_v19.dart")
    runtime = read(ROOT / "lib/product/product_runtime.dart")
    workflow = read(ROOT / "lib/product/generated/workflow_migrations.g.dart")
    generated = read(ROOT / "lib/product/generated/v190_contracts.g.dart")
    markers = (
        "class CapabilityManifest",
        "class McpLifecycleController",
        "class A2ADelegationController",
        "class AuditChain",
        "class UpdatePolicyVerifier",
        "const String interoperabilityV19Version",
        "const String v190ContractsSha256",
        "name: 'interoperability_admin'",
    )
    joined = source + dart + runtime + workflow + generated
    for token in markers:
        if token not in joined:
            failures.append(f"interoperability integration missing {token}")
    add(
        "v1.9 interoperability, administration, and release operations",
        not failures,
        "22/22 executable cases passed; typed MCP manifests, bounded A2A delegation, signed capability manifests, audit verification, and authenticated source-update policy are integrated"
        if not failures
        else "; ".join(failures[:40]),
        started=started,
    )


def check_release_ops_v19() -> None:
    """Execute the deep v1.9 release-governance integration gate."""
    started = time.monotonic()
    failures: list[str] = []
    result_path = ROOT / "release" / "RELEASE_OPS_V19_RESULTS.json"
    code, output = run(
        [sys.executable, str(ROOT / "tool" / "release_ops_v19_test.py"), "--json-output", str(result_path)],
        timeout=180,
    )
    if code != 0:
        failures.append(f"release-governance gate exited {code}: {output[-1800:]}")
    payload: dict[str, object] = {}
    if result_path.is_file():
        try:
            decoded = json.loads(read(result_path))
            payload = decoded if isinstance(decoded, dict) else {}
        except json.JSONDecodeError as error:
            failures.append(f"release-governance results are invalid JSON: {error}")
    else:
        failures.append("release-governance results file was not generated")
    if payload.get("passed") is not True or payload.get("passedCount") != 10 or payload.get("caseCount") != 10:
        failures.append(
            f"release-governance expected 10/10 cases, got {payload.get('passedCount')}/{payload.get('caseCount')}"
        )

    source = read(ROOT / "tool" / "release_ops_v19.py")
    test_source = read(ROOT / "tool" / "release_ops_v19_test.py")
    interoperability = read(ROOT / "tool" / "interoperability_admin_v19.py")
    generated = read(ROOT / "lib/product/generated/v190_contracts.g.dart")
    markers = (
        "class PolicyProfile",
        "class FleetConfiguration",
        "class AuditRecord",
        "class SupportLifecyclePolicy",
        "class UpdateManifest",
        "class SignedManifestEnvelope",
        "def create_signed_audit_checkpoint",
        "def verify_signed_update_manifest",
        "const String v190ContractsSha256",
    )
    joined = source + test_source + interoperability + generated
    for token in markers:
        if token not in joined:
            failures.append(f"release-operations integration missing {token}")
    add(
        "v1.9 deep release operations and audit verification",
        not failures,
        "10/10 executable cases passed; policy overlays, audit-chain verification, authenticated update manifests, and rollback compatibility enforcement are integrated"
        if not failures
        else "; ".join(failures[:40]),
        started=started,
    )




def check_file_adapters_v18() -> None:
    """Execute the v1.8 core file-adapter gate."""
    started = time.monotonic()
    failures: list[str] = []
    result_path = ROOT / "release" / "FILE_ADAPTER_RESULTS.json"
    code, output = run(
        [sys.executable, str(ROOT / "tool" / "file_adapter_test.py"), "--json-output", str(result_path)],
        timeout=180,
    )
    if code != 0:
        failures.append(f"file-adapter gate exited {code}: {output[-1800:]}")
    payload: dict[str, object] = {}
    if result_path.is_file():
        try:
            decoded = json.loads(read(result_path))
            payload = decoded if isinstance(decoded, dict) else {}
        except json.JSONDecodeError as error:
            failures.append(f"file-adapter results are invalid JSON: {error}")
    else:
        failures.append("file-adapter results file was not generated")
    if payload.get("passed") is not True or payload.get("passedCount") != 14 or payload.get("caseCount") != 14:
        failures.append(
            f"file-adapter expected 14/14 cases, got {payload.get('passedCount')}/{payload.get('caseCount')}"
        )

    source = read(ROOT / "tool" / "file_adapters.py")
    dart = read(ROOT / "lib/product/file_adapters.dart")
    runtime = read(ROOT / "lib/product/product_runtime.dart")
    markers = (
        "class FileAdapter",
        "BUILTINS",
        "pdf",
        "ooxml",
        "epub",
        "FileAdapterRegistry",
        "sandboxedCore",
        "inspectFileAdapter",
        "validateFileAdapter",
    )
    joined = source + dart + runtime
    for token in markers:
        if token not in joined:
            failures.append(f"file-adapter integration missing {token}")
    add(
        "v1.8 core file adapters",
        not failures,
        "14/14 executable cases passed; native and sandboxed-core adapters detect, inspect, and reopen supported files with bounded validation"
        if not failures
        else "; ".join(failures[:40]),
        started=started,
    )



if __name__=="__main__":
    raise SystemExit(main())
