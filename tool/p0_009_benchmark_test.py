#!/usr/bin/env python3
"""Repository integration gate for P0-009."""
from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
from typing import Any

SUPPORTED_ROADMAP_VERSIONS = {
    "3.1.5-p0-009-initial-benchmark",
    "3.1.6-p0-010-generated-state-hygiene",
    "3.1.7-p25-prompt-studio-product-rescue",
}


def roadmap_version_supported(value: object) -> bool:
    return isinstance(value, str) and value in SUPPORTED_ROADMAP_VERSIONS

sys.dont_write_bytecode = True


@dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str


def load_module(project: Path):
    path = project / "tool/benchmark_runner.py"
    spec = importlib.util.spec_from_file_location("p0_009_benchmark_runner", path)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load benchmark_runner.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def finish(results: list[Result], json_output: str | None) -> int:
    payload = {
        "schemaVersion": "1.0.0",
        "gateId": "p0-009-initial-benchmark",
        "passed": all(item.passed for item in results),
        "passedCount": sum(1 for item in results if item.passed),
        "caseCount": len(results),
        "results": [asdict(item) for item in results],
    }
    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if json_output:
        path = Path(json_output)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    print(text, end="")
    return 0 if payload["passed"] else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--json-output")
    args = parser.parse_args()
    project = Path(args.project).resolve()
    results: list[Result] = []

    required = [
        "tool/benchmark_runner.py",
        "tool/benchmark_runner_test.py",
        "tool/p0_009_benchmark_test.py",
        "evals/datasets/p0_009_initial_benchmark.v1.json",
        "evals/results/p0_009_baseline.json",
        "evals/results/P0_009_BASELINE.md",
        "schemas/benchmark_suite.v1.json",
        "schemas/benchmark_result.v1.json",
        "docs/roadmap/BENCHMARKS.md",
        "tasks/completed/P0-009.md",
        "release/evidence/P0-009/IMPLEMENTATION.md",
        "release/evidence/P0-009/manifest.json",
    ]
    missing = [relative for relative in required if not (project / relative).is_file()]
    results.append(Result("Required P0-009 files", not missing, "all required files present" if not missing else "missing: " + ", ".join(missing)))
    if missing:
        return finish(results, args.json_output)

    try:
        br = load_module(project)
        suite_path = project / "evals/datasets/p0_009_initial_benchmark.v1.json"
        suite = br.load_json(suite_path)
        suite_errors = br.validate_suite_data(suite, project)
    except Exception as error:
        br = None
        suite = {}
        suite_errors = [f"{type(error).__name__}: {error}"]
    results.append(Result("Benchmark suite contract", not suite_errors, "suite validated" if not suite_errors else "; ".join(suite_errors[:10])))

    categories = {item.get("id") for item in suite.get("categories", []) if isinstance(item, dict)}
    required_categories = {"coding", "analysis", "path_safety", "crash_recovery", "browser_absent", "research"}
    case_counts = {category: 0 for category in required_categories}
    for case in suite.get("cases", []):
        if isinstance(case, dict) and case.get("category") in case_counts:
            case_counts[str(case["category"])] += 1
    categories_ok = categories == required_categories and all(count >= 2 for count in case_counts.values())
    results.append(Result("Six required benchmark categories", categories_ok, f"case counts: {case_counts}"))

    baseline = json.loads((project / "evals/results/p0_009_baseline.json").read_text(encoding="utf-8"))
    baseline_ok = (
        baseline.get("schemaVersion") == "1.0.0"
        and baseline.get("suiteId") == "kristin.p0-009.initial"
        and baseline.get("mode") == "portable"
        and baseline.get("summary", {}).get("recordingStatus") == "complete"
        and baseline.get("summary", {}).get("caseCount") == len(suite.get("cases", []))
        and isinstance(baseline.get("resultFingerprint"), str)
        and len(baseline.get("resultFingerprint")) == 64
    )
    results.append(Result("Versioned portable baseline", baseline_ok, f"fingerprint={baseline.get('resultFingerprint')}"))

    claims = baseline.get("claims", {})
    claims_ok = claims == {
        "sourceInspectionIsBehavioralProof": False,
        "unsupportedCountsAsPassed": False,
        "unavailableCountsAsPassed": False,
        "notRunCountsAsPassed": False,
        "baselineRecordedMeansProductReady": False,
    }
    results.append(Result("Benchmark claim boundaries", claims_ok, "non-pass and source-only evidence cannot become product proof"))

    cases = {item.get("id"): item for item in baseline.get("cases", []) if isinstance(item, dict)}
    path_case = cases.get("path_safety.generated_state_policy", {})
    path_ok = path_case.get("proofKind") == "executed_behavior" and path_case.get("status") in {"passed", "failed"}
    results.append(Result("Path-safety result is measured", path_ok, f"status={path_case.get('status')} score={path_case.get('score')}"))

    crash = cases.get("crash_recovery.sqlite_workflow_kernel", {})
    crash_ok = crash.get("assuranceLevel") == "behavioral" and crash.get("proofKind") == "executed_behavior" and crash.get("status") in {"passed", "failed", "unavailable"}
    results.append(Result("Crash-recovery case classification", crash_ok, f"status={crash.get('status')}"))

    source = cases.get("analysis.offline_system_contract", {})
    source_ok = source.get("assuranceLevel") == "source_contract" and source.get("proofKind") == "source_inspection"
    results.append(Result("Source analysis remains source-only", source_ok, f"status={source.get('status')}"))

    browser = cases.get("browser_absent.capability_inventory", {})
    browser_task = cases.get("browser_absent.form_completion_task", {})
    browser_ok = (
        browser.get("status") in {"unsupported", "passed"}
        and browser.get("status") != "failed"
        and not (browser.get("status") == "unsupported" and browser_task.get("status") == "passed")
    )
    results.append(Result("Browser absence is honest", browser_ok, f"inventory={browser.get('status')} task={browser_task.get('status')}"))

    model_cases = [item for item in baseline.get("cases", []) if item.get("proofKind") == "model_evaluation"]
    model_ok = bool(model_cases) and all(item.get("status") in {"not_run", "unsupported"} for item in model_cases)
    results.append(Result("No fabricated model result", model_ok, f"model cases={len(model_cases)}"))

    if br is not None:
        rerun = br.run_suite(project, suite_path, mode="portable", include_sdk=False, candidate_root=None)
        reproducible = br.canonical_json(rerun) == br.canonical_json(baseline)
    else:
        reproducible = False
    results.append(Result("Byte-equivalent baseline rerun", reproducible, "portable rerun matches committed baseline" if reproducible else "baseline drift"))

    verify = (project / "tool/verify.sh").read_text(encoding="utf-8", errors="replace") if (project / "tool/verify.sh").is_file() else ""
    hooks = (
        "tool/benchmark_runner_test.py" in verify
        and "tool/p0_009_benchmark_test.py" in verify
        and "tool/benchmark_runner.py check" in verify
    )
    results.append(Result("Verification integration", hooks, "benchmark unit, repository, and reproducibility gates are wired"))

    workflow = (project / ".github/workflows/ci.yml").read_text(encoding="utf-8", errors="replace") if (project / ".github/workflows/ci.yml").is_file() else ""
    ci_ok = "P0-009 reproducible benchmark baseline" in workflow and "benchmark_runner.py check" in workflow
    results.append(Result("CI integration", ci_ok, "CI contains the P0-009 baseline step"))

    schema_suite = json.loads((project / "schemas/benchmark_suite.v1.json").read_text(encoding="utf-8"))
    schema_result = json.loads((project / "schemas/benchmark_result.v1.json").read_text(encoding="utf-8"))
    schema_ok = schema_suite.get("properties", {}).get("networkPolicy", {}).get("const") == "forbidden" and schema_result.get("properties", {}).get("claims", {}).get("properties", {}).get("sourceInspectionIsBehavioralProof", {}).get("const") is False
    results.append(Result("Benchmark JSON schemas", schema_ok, "suite and result claim invariants are encoded"))

    manifest_path = project / "SOURCE_MANIFEST.sha256"
    manifest_text = manifest_path.read_text(encoding="utf-8", errors="replace") if manifest_path.is_file() else ""
    manifest_required = [
        "tool/benchmark_runner.py",
        "evals/datasets/p0_009_initial_benchmark.v1.json",
        "evals/results/p0_009_baseline.json",
        "schemas/benchmark_result.v1.json",
    ]
    manifest_ok = all(relative in manifest_text for relative in manifest_required)
    results.append(Result("Source-manifest integration", manifest_ok, "benchmark inputs and committed baseline are tracked"))

    trust_path = project / "tool/interoperability_v19.py"
    if trust_path.is_file() and "v1_trust_disabled" in trust_path.read_text(encoding="utf-8", errors="replace"):
        trust_ok = (project / "tool/v1_trust_disablement_test.py").is_file()
    else:
        trust_ok = True
    results.append(Result("P0-002 trust retirement preserved", trust_ok, "P0-009 does not re-enable legacy manifest trust"))

    roadmap_manifest = project / "docs/roadmap/roadmap.yaml"
    if roadmap_manifest.is_file():
        roadmap = json.loads(roadmap_manifest.read_text(encoding="utf-8"))
        task = next((item for item in roadmap.get("tasks", []) if item.get("id") == "P0-009"), None)
        roadmap_ok = (
            isinstance(task, dict)
            and task.get("status") in {"REVIEW", "DONE"}
            and "evals/results/p0_009_baseline.json" in (task.get("evidence") or [])
            and roadmap_version_supported(roadmap.get("roadmapVersion"))
        )
    else:
        roadmap_ok = True
    results.append(Result("Roadmap-control integration when present", roadmap_ok, "P0-009 is REVIEW/DONE with baseline evidence under a supported cumulative roadmap version"))

    return finish(results, args.json_output)


if __name__ == "__main__":
    raise SystemExit(main())
