#!/usr/bin/env python3
"""Repository integration gate for P0-010 generated-state hygiene."""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Callable

sys.dont_write_bytecode = True


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str


def run_case(name: str, action: Callable[[], str]) -> Result:
    try:
        return Result(name, True, action())
    except BaseException as error:
        return Result(name, False, f"{type(error).__name__}: {error}")


def run(project: Path, argv: list[str], timeout: int = 180) -> str:
    completed = subprocess.run(
        argv,
        cwd=project,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
        check=False,
        timeout=timeout,
    )
    if completed.returncode != 0:
        raise AssertionError(
            f"command exited {completed.returncode}: {' '.join(argv)}\n"
            f"{completed.stdout[-4000:]}"
        )
    return completed.stdout


def parse_manifest(project: Path) -> list[str]:
    result = []
    for line in (project / "SOURCE_MANIFEST.sha256").read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        match = re.match(r"^[0-9a-fA-F]{64}\s{2,}(.+)$", line)
        if match is None:
            raise AssertionError(f"invalid source manifest line: {line!r}")
        result.append(match.group(1))
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--json-output")
    args = parser.parse_args()
    project = Path(args.project).expanduser().resolve()
    sys.path.insert(0, str(project / "tool"))

    from generated_state_guard import build_audit  # type: ignore
    from source_tree_policy import (  # type: ignore
        GENERATED_STATE_POLICY_VERSION,
        generated_path_reason,
        gitignore_block,
        representative_generated_paths,
        representative_source_paths,
    )

    def required_files() -> str:
        required = (
            ".gitignore",
            "tool/source_tree_policy.py",
            "tool/source_tree_policy_test.py",
            "tool/generated_state_guard.py",
            "tool/generated_state_guard_test.py",
            "tool/p0_010_generated_state_test.py",
            "schemas/generated_state_report.v1.json",
            "docs/roadmap/GENERATED_STATE.md",
            "tasks/active/P0-010.md",
            "release/evidence/P0-010/IMPLEMENTATION.md",
        )
        missing = [path for path in required if not (project / path).is_file()]
        if missing:
            raise AssertionError(f"missing: {missing}")
        return f"required={len(required)}"

    def policy_generated() -> str:
        failures = [path for path in representative_generated_paths() if generated_path_reason(path) is None]
        if failures:
            raise AssertionError(f"not generated: {failures}")
        return f"generatedExamples={len(representative_generated_paths())}"

    def policy_source() -> str:
        failures = [path for path in representative_source_paths() if generated_path_reason(path) is not None]
        if failures:
            raise AssertionError(f"false positives: {failures}")
        return f"sourceExamples={len(representative_source_paths())}"

    def ignore_block() -> str:
        text = (project / ".gitignore").read_text(encoding="utf-8")
        block = gitignore_block()
        if text.count("# BEGIN KRISTIN GENERATED STATE POLICY v2") != 1:
            raise AssertionError("managed .gitignore block count is not one")
        if block not in text:
            raise AssertionError("canonical managed .gitignore block is missing")
        return f"blockBytes={len(block.encode('utf-8'))}"

    def audit() -> str:
        report = build_audit(project)
        if not report.get("passed"):
            raise AssertionError(json.dumps(report, sort_keys=True)[:4000])
        return (
            f"authority={report['trackedAuthority']} "
            f"pendingDeletion={len(report['trackedGeneratedPendingDeletion'])}"
        )

    def manifest_clean() -> str:
        paths = parse_manifest(project)
        failures = [path for path in paths if generated_path_reason(path) is not None]
        if failures:
            raise AssertionError(f"generated paths in manifest: {failures[:30]}")
        return f"manifestEntries={len(paths)}"

    def known_committed_outputs_untracked() -> str:
        manifest_paths = set(parse_manifest(project))
        forbidden = {
            ".flutter",
            ".flutter_tool_state",
            "release/SECRET_SCAN.json",
            "release/SBOM.cdx.json",
            "release/VALIDATION_REPORT.md",
            "release/validation_report.json",
        }
        forbidden.update(
            path for path in manifest_paths
            if path.startswith("tool/__pycache__/")
            or re.fullmatch(r"reports/kristin-test-(?:system|release)-[0-9]{8}-[0-9]{6}\.(?:json|md)", path)
        )
        remaining = sorted(forbidden & manifest_paths)
        if remaining:
            raise AssertionError(f"generated outputs remain in source manifest: {remaining[:30]}")
        # Generated outputs may exist after tests, but the strict audit proves
        # they are not current source inputs.
        return "knownGeneratedOutputsUntracked=true"

    def verify_integration() -> str:
        text = (project / "tool/verify.sh").read_text(encoding="utf-8")
        required = (
            "tool/source_tree_policy_test.py",
            "tool/generated_state_guard_test.py",
            "tool/p0_010_generated_state_test.py --project .",
            "tool/generated_state_guard.py audit --project . --strict",
        )
        missing = [marker for marker in required if marker not in text]
        if missing:
            raise AssertionError(f"verify markers missing: {missing}")
        if "dart format lib test tool/prune_stale_legacy.dart" in text:
            raise AssertionError("verification still mutates Dart source")
        return "verifyIntegration=true"

    def ci_integration() -> str:
        workflow = project / ".github/workflows/ci.yml"
        if not workflow.is_file():
            return "workflow=absent"
        text = workflow.read_text(encoding="utf-8")
        if "P0-010 generated-state hygiene" not in text:
            raise AssertionError("P0-010 CI step is missing")
        if "generated_state_guard.py audit --project . --strict" not in text:
            raise AssertionError("CI strict generated-state audit is missing")
        return "workflowIntegrated=true"

    def unit_policy() -> str:
        output = run(project, [sys.executable, "tool/source_tree_policy_test.py"])
        if "OK" not in output:
            raise AssertionError(output)
        return "sourceTreePolicyUnitSuite=passed"

    def unit_guard() -> str:
        output = run(project, [sys.executable, "tool/generated_state_guard_test.py"])
        if "OK" not in output:
            raise AssertionError(output)
        return "generatedStateGuardUnitSuite=passed"

    def schema_contract() -> str:
        schema = json.loads((project / "schemas/generated_state_report.v1.json").read_text(encoding="utf-8"))
        if schema.get("$id") != "https://kristin.local/schemas/generated_state_report.v1.json":
            raise AssertionError("generated-state report schema ID mismatch")
        claims = schema.get("properties", {}).get("claims", {}).get("properties", {})
        expected = claims.get("generatedStateMayBeTracked", {}).get("const")
        if expected is not False:
            raise AssertionError("schema does not prohibit tracked generated state")
        return "schemaInvariant=true"

    def benchmark_current() -> str:
        runner = project / "tool/benchmark_runner.py"
        baseline = project / "evals/results/p0_009_baseline.json"
        if not runner.is_file() or not baseline.is_file():
            return "P0-009=absent"
        run(project, [sys.executable, "tool/benchmark_runner.py", "check", "--project", "."], timeout=240)
        value = json.loads(baseline.read_text(encoding="utf-8"))
        case = next((item for item in value.get("cases", []) if item.get("id") == "path_safety.generated_state_policy"), None)
        if not isinstance(case, dict) or case.get("status") != "passed":
            raise AssertionError(f"generated-state benchmark did not pass: {case}")
        return f"benchmarkFingerprint={value.get('resultFingerprint')}"

    def trust_preserved() -> str:
        gate = project / "tool/v1_trust_disablement_test.py"
        if not gate.is_file():
            return "P0-002=absent"
        output = run(project, [sys.executable, "tool/v1_trust_disablement_test.py"])
        if "v1_trust_disabled" not in output:
            raise AssertionError(output)
        return "v1TrustDisabled=true"

    def roadmap_current() -> str:
        manifest = project / "docs/roadmap/roadmap.yaml"
        controller = project / "tool/roadmap_control.py"
        if not manifest.is_file() or not controller.is_file():
            return "P0-008=absent"
        run(project, [sys.executable, "tool/roadmap_control.py", "validate", "--project", ".", "--strict"])
        value = json.loads(manifest.read_text(encoding="utf-8"))
        record = next((item for item in value.get("tasks", []) if item.get("id") == "P0-010"), None)
        if not isinstance(record, dict) or record.get("status") not in {"REVIEW", "DONE"}:
            raise AssertionError(f"P0-010 ledger status invalid: {record}")
        return f"ledgerStatus={record.get('status')}"

    def policy_version() -> str:
        if GENERATED_STATE_POLICY_VERSION != "2.0.0":
            raise AssertionError(GENERATED_STATE_POLICY_VERSION)
        return f"policyVersion={GENERATED_STATE_POLICY_VERSION}"

    results = [
        run_case("Required P0-010 files", required_files),
        run_case("Generated examples classify as generated", policy_generated),
        run_case("Source examples remain source", policy_source),
        run_case("Canonical .gitignore managed block", ignore_block),
        run_case("Strict generated-state audit", audit),
        run_case("Source manifest excludes generated state", manifest_clean),
        run_case("Known generated outputs are not source inputs", known_committed_outputs_untracked),
        run_case("Verification ladder integration", verify_integration),
        run_case("CI integration", ci_integration),
        run_case("Source-tree policy unit suite", unit_policy),
        run_case("Generated-state guard unit suite", unit_guard),
        run_case("Generated-state report schema", schema_contract),
        run_case("P0-009 benchmark baseline current", benchmark_current),
        run_case("P0-002 trust retirement preserved", trust_preserved),
        run_case("P0-008 roadmap ledger current", roadmap_current),
        run_case("Policy version explicit", policy_version),
    ]
    passed = sum(item.passed for item in results)
    payload = {
        "schemaVersion": "1.0.0",
        "taskId": "P0-010",
        "passed": passed == len(results),
        "passedCount": passed,
        "failedCount": len(results) - passed,
        "caseCount": len(results),
        "results": [asdict(item) for item in results],
    }
    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if args.json_output:
        output = Path(args.json_output)
        if not output.is_absolute():
            output = project / output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding="utf-8")
    print(text, end="")
    return 0 if payload["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
