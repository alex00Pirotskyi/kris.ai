#!/usr/bin/env python3
"""Validate the portable One-Kristin development checkpoint.

This validator covers bundle integrity, guarded slice ordering, Python syntax,
static architecture contracts, Git-write prohibition in user-facing tooling,
and synthetic Dart source/test composition. It does not claim to replace a
real Dart/Flutter analyzer/test run.
"""
from __future__ import annotations

import ast
import hashlib
import py_compile
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "BUNDLE_MANIFEST.sha256"

ORDER = [
    "apply_one_kristin_state_convergence.py",
    "apply_advanced_same_conversation.py",
    "apply_semantic_slash_understanding.py",
    "apply_blocking_clarification_loop.py",
    "apply_collision_safe_target_resolution.py",
    "apply_truthful_conversation_streaming.py",
    "apply_deterministic_utility_time.py",
    "apply_project_free_research_execution.py",
    "apply_semantic_durable_steering.py",
    "apply_protocol_v3_timestamp_wait.py",
    "apply_bounded_protocol_v3_delegate.py",
    "apply_scope_changing_steering_continuation.py",
    "apply_idle_steering_continuation.py",
    "apply_research_restart_reconciliation.py",
    "apply_research_optional_archive_guard.py",
    "apply_research_archive_degradation.py",
    "apply_delegate_recovery_qualification.py",
    "apply_continuation_handoff_activity_projection.py",
    "apply_authority_convergence_qualification.py",
    "apply_human_readable_failure_projection.py",
]

PAYLOAD_FILES = {
    "ARCHITECTURAL_REMAINDER.md",
    "DEVELOPMENT_NOTES.md",
    "QUALIFICATION_REPORT.md",
    "README.md",
    "RECOVERED_STATE.md",
    *ORDER,
    "apply_all_development_slices.py",
    "qualify_real_checkout.py",
    "validate_anchor_composition.py",
    "validate_development_bundle.py",
    "validate_generated_dart_sources.py",
    "validate_generated_dart_tests.py",
    "validate_one_kristin_state_convergence.py",
    "validate_orchestrator_smoke.py",
    "validate_real_checkout_qualifier.py",
}

missing = sorted(name for name in PAYLOAD_FILES if not (ROOT / name).is_file())
if missing:
    raise SystemExit(f"missing bundle files: {', '.join(missing)}")

actual_payload = {
    path.name
    for path in ROOT.iterdir()
    if path.is_file() and path.name != MANIFEST.name
}
if actual_payload != PAYLOAD_FILES:
    raise SystemExit(
        "bundle payload set drifted: "
        f"missing={sorted(PAYLOAD_FILES - actual_payload)} "
        f"extra={sorted(actual_payload - PAYLOAD_FILES)}"
    )
print(f"OK exact bundle payload set ({len(PAYLOAD_FILES)} files)")

for path in sorted(ROOT.glob("*.py")):
    py_compile.compile(str(path), doraise=True)
    print(f"OK python syntax: {path.name}")


def orchestrator_order() -> list[str]:
    tree = ast.parse((ROOT / "apply_all_development_slices.py").read_text(encoding="utf-8"))
    for node in tree.body:
        if not isinstance(node, ast.Assign):
            continue
        if not any(isinstance(target, ast.Name) and target.id == "SLICES" for target in node.targets):
            continue
        value = ast.literal_eval(node.value)
        return [str(item[1]) for item in value]
    raise SystemExit("apply_all_development_slices.py has no literal SLICES assignment")

observed_order = orchestrator_order()
if observed_order != ORDER:
    raise SystemExit(
        "guarded apply order drifted:\n"
        f"expected={ORDER}\nobserved={observed_order}"
    )
print("OK exact 20-slice guarded apply order")

# Fixture validators create isolated temporary Git repositories. Production
# apply/qualification tooling is forbidden from Git metadata/remote writes.
FIXTURE_GIT_WRITERS = {
    "validate_orchestrator_smoke.py",
    "validate_real_checkout_qualifier.py",
}
ALLOWED_GIT_OPS = {"rev-parse", "status", "diff"}


def literal_string(node: ast.AST) -> str | None:
    return node.value if isinstance(node, ast.Constant) and isinstance(node.value, str) else None


def explicit_git_operation(items: list[ast.AST]) -> str | None:
    if not items or literal_string(items[0]) != "git":
        return None
    index = 1
    if index < len(items) and literal_string(items[index]) == "-C":
        # Skip -C and the following path expression.
        index += 2
    while index < len(items):
        value = literal_string(items[index])
        if value is not None and not value.startswith("-"):
            return value
        index += 1
    return None

for path in sorted(ROOT.glob("*.py")):
    if path.name in FIXTURE_GIT_WRITERS:
        continue
    tree = ast.parse(path.read_text(encoding="utf-8"))
    violations: list[str] = []
    for node in ast.walk(tree):
        if isinstance(node, (ast.List, ast.Tuple)):
            op = explicit_git_operation(list(node.elts))
            if op is not None and op not in ALLOWED_GIT_OPS:
                violations.append(op)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "git":
            # All production git(...) helpers use the repo path first.
            for arg in node.args[1:2]:
                op = literal_string(arg)
                if op is not None and op not in ALLOWED_GIT_OPS:
                    violations.append(op)
    if violations:
        raise SystemExit(f"Git write/unknown operation(s) in {path.name}: {sorted(set(violations))}")
print("OK production tooling contains no Git write operations")

contracts = {
    "apply_deterministic_utility_time.py": [
        "timezone: 0.10.1",
        "lib/product/utility_time.dart",
        "locationQueryFromMessage('/time')",
    ],
    "apply_project_free_research_execution.py": [
        "ResearchTaskFamilyExecutor",
        "taskFamilyExecutions",
        "executeResearchTaskPlan",
        "import 'task_kernel/universal_task_plan.dart';",
        "AgentPromptInjectionGuard",
        "AgentContextSource.web",
        "authorityBearing': false",
        "chat direct research untrusted evidence envelope",
        "studio research untrusted context import",
    ],
    "apply_semantic_durable_steering.py": [
        "TaskSpecificationPatch",
        "runSteeringRecords",
        "await steering.takePending",
    ],
    "apply_bounded_protocol_v3_delegate.py": [
        "AgentDelegationRecord",
        "agentDelegations",
        "_maxDistinctDelegationsPerWorkItem = 2",
        "AgentDestinationGuard().requireAuthorized",
        "cancellation: control.cancellation.cancelled",
    ],
    "apply_scope_changing_steering_continuation.py": [
        "CommandPlanningContextRecord",
        "_interruptAtSteeringReplanBoundary",
        "taskKernel.reconcile",
        "authorityInherited",
        "createContinuationRun",
        "reconciliation.plan.enabledTasks.isEmpty",
        "Verify reconciled project state",
        "semantic_durable_steering_test.dart",
    ],
    "apply_research_archive_degradation.py": [
        "research.optional_archive_failed",
        "task_family.research_archive_failed",
        "answerPreserved",
    ],
    "apply_delegate_recovery_qualification.py": [
        "reconcileInterruptedDelegations",
        "agent_delegation_previous_failure",
        "agent_delegation_retry_exhausted",
    ],
    "apply_human_readable_failure_projection.py": [
        "technicalError",
        "Error details",
        "ProductErrorNormalizer.userMessage",
    ],
    "qualify_real_checkout.py": [
        "locked toolchain preflight",
        "verify timezone lock",
        "verify_existing_lock_versions",
        "pre-existing locked packages",
        "sync governed toolchain lock",
        "locked toolchain post-Pub",
        "declaredInputFingerprint",
        "refresh SOURCE_MANIFEST.sha256",
    ],
}
for name, needles in contracts.items():
    source = (ROOT / name).read_text(encoding="utf-8")
    absent = [needle for needle in needles if needle not in source]
    if absent:
        raise SystemExit(f"{name} missing static contract(s): {absent}")
    print(f"OK static contracts: {name}")

for validator in [
    "validate_anchor_composition.py",
    "validate_generated_dart_sources.py",
    "validate_generated_dart_tests.py",
]:
    subprocess.run([sys.executable, str(ROOT / validator)], check=True)
    print(f"OK child validator: {validator}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

if not MANIFEST.is_file():
    raise SystemExit("BUNDLE_MANIFEST.sha256 is missing")
rows: dict[str, str] = {}
for number, line in enumerate(MANIFEST.read_text(encoding="utf-8").splitlines(), start=1):
    if "  " not in line:
        raise SystemExit(f"invalid bundle manifest row {number}")
    digest, name = line.split("  ", 1)
    if name in rows:
        raise SystemExit(f"duplicate bundle manifest path: {name}")
    rows[name] = digest
if set(rows) != PAYLOAD_FILES:
    raise SystemExit(
        "bundle manifest scope mismatch: "
        f"missing={sorted(PAYLOAD_FILES - set(rows))} extra={sorted(set(rows) - PAYLOAD_FILES)}"
    )
mismatches = [name for name, digest in rows.items() if sha256(ROOT / name) != digest]
if mismatches:
    raise SystemExit(f"bundle manifest digest mismatch: {mismatches}")
print(f"OK exact bundle SHA-256 manifest ({len(rows)} payload files)")

print("PASS portable development checkpoint validation")
print("NOTE: real Dart/Flutter composition still requires the real kris.ai checkout/toolchain.")
