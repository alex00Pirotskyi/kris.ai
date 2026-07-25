#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import argparse
import json
from pathlib import Path
import shutil
import subprocess
from unittest import mock
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
RUNNER_PATH = ROOT / "tool" / "benchmark_runner.py"
SPEC = importlib.util.spec_from_file_location("benchmark_runner_under_test", RUNNER_PATH)
assert SPEC is not None and SPEC.loader is not None
BR = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = BR
SPEC.loader.exec_module(BR)


class BenchmarkRunnerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="kristin-p0-009-test-")
        self.project = Path(self.temporary.name)
        self._copy("tool/benchmark_runner.py")
        self._copy("evals/datasets/p0_009_initial_benchmark.v1.json")
        self._copy_tree("evals/fixtures/p0_009")
        self._write_stubs()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _copy(self, relative: str) -> None:
        source = ROOT / relative
        target = self.project / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)

    def _copy_tree(self, relative: str) -> None:
        source = ROOT / relative
        target = self.project / relative
        shutil.copytree(source, target)

    def _write(self, relative: str, text: str) -> None:
        path = self.project / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def _write_stubs(self) -> None:
        self._write(
            "tool/source_tree_policy.py",
            "from pathlib import PurePath\n"
            "GENERATED={'.dart_tool','node_modules','build','dist','__pycache__'}\n"
            "def is_generated_path(relative):\n"
            "    p=PurePath(relative); parts=tuple(x.lower() for x in p.parts)\n"
            "    return any(x in GENERATED for x in parts) or parts[:3] == ('windows','flutter','ephemeral')\n",
        )
        self._write(
            "tool/protocol_contract_test.py",
            "print('protocol gate passed')\n",
        )
        self._write(
            "tool/system_test.py",
            """import json\nprint(json.dumps({'passed': 7, 'failed': 0}, sort_keys=True))\n""",
        )
        self._write(
            "tool/workflow_kernel_test.py",
            """import json\nprint(json.dumps({'passed':14,'failed':0,'schemaVersion':6,'database':{'integrity':'ok'}},sort_keys=True))\n""",
        )
        self._write(
            "tool/replay_diagnostics.py",
            """import json\nprint(json.dumps({'passed':True,'caseCount':2,'passedCount':2},sort_keys=True))\n""",
        )
        self._write(
            "tool/knowledge_memory_v2_test.py",
            """import argparse,json\np=argparse.ArgumentParser();p.add_argument('--json-output',required=True);a=p.parse_args();open(a.json_output,'w',encoding='utf-8').write(json.dumps({'passed':True,'passedCount':12,'caseCount':12},sort_keys=True)+'\\n')\n""",
        )
        self._write(
            "test/product/v1_product_preview_test.dart",
            "// fixture only\n",
        )
        self._write(
            "schemas/tool_registry.v2.json",
            json.dumps({"version": "2.0.0", "tools": [{"name": "inspect_file"}]}) + "\n",
        )

    def _fake_run_command(
        self,
        argv: list[str],
        project: Path,
        timeout: int,
        suite: dict[str, object],
    ) -> tuple[int, str]:
        joined = " ".join(argv)
        if "protocol_contract_test.py" in joined:
            return 0, "protocol gate passed\n"
        if "system_test.py" in joined:
            return 0, json.dumps({"passed": 7, "failed": 0}, sort_keys=True)
        if "workflow_kernel_test.py" in joined:
            return 0, json.dumps(
                {
                    "passed": 14,
                    "failed": 0,
                    "schemaVersion": 6,
                    "database": {"integrity": "ok"},
                },
                sort_keys=True,
            )
        if "replay_diagnostics.py" in joined:
            return 0, json.dumps(
                {"passed": True, "caseCount": 2, "passedCount": 2},
                sort_keys=True,
            )
        if "knowledge_memory_v2_test.py" in joined:
            output = Path(argv[argv.index("--json-output") + 1])
            output.write_text(
                json.dumps(
                    {"passed": True, "passedCount": 12, "caseCount": 12},
                    sort_keys=True,
                )
                + "\n",
                encoding="utf-8",
            )
            return 0, ""
        raise AssertionError(f"unexpected test command: {argv}")

    @property
    def suite_path(self) -> Path:
        return self.project / "evals/datasets/p0_009_initial_benchmark.v1.json"

    def run_report(self, candidate_root: Path | None = None) -> dict[str, object]:
        with mock.patch.object(BR, "run_command", side_effect=self._fake_run_command):
            return BR.run_suite(
                self.project,
                self.suite_path,
                mode="portable",
                include_sdk=False,
                candidate_root=candidate_root,
            )

    def test_portable_baseline_is_byte_deterministic(self) -> None:
        first = self.run_report()
        second = self.run_report()
        self.assertEqual(BR.canonical_json(first), BR.canonical_json(second))
        self.assertEqual(first["resultFingerprint"], second["resultFingerprint"])

    def test_baseline_preserves_non_pass_states(self) -> None:
        report = self.run_report()
        statuses = {item["id"]: item["status"] for item in report["cases"]}
        self.assertEqual(statuses["coding.python_bugfix_task"], "not_run")
        self.assertEqual(statuses["path_safety.generated_state_policy"], "failed")
        self.assertEqual(statuses["path_safety.flutter_workspace_behavior"], "unavailable")
        self.assertEqual(statuses["browser_absent.capability_inventory"], "unsupported")
        self.assertEqual(statuses["browser_absent.form_completion_task"], "unsupported")
        self.assertFalse(report["summary"]["benchmarkQualityPassed"])

    def test_source_contract_is_not_behavioral_proof(self) -> None:
        report = self.run_report()
        case = next(item for item in report["cases"] if item["id"] == "analysis.offline_system_contract")
        self.assertEqual(case["proofKind"], "source_inspection")
        self.assertFalse(report["claims"]["sourceInspectionIsBehavioralProof"])

    def test_duplicate_case_id_is_rejected(self) -> None:
        suite = BR.load_json(self.suite_path)
        suite["cases"].append(dict(suite["cases"][0]))
        errors = BR.validate_suite_data(suite, self.project)
        self.assertTrue(any("duplicate case ID" in item for item in errors))

    def test_unsafe_command_is_rejected(self) -> None:
        suite = BR.load_json(self.suite_path)
        suite["cases"][0]["command"] = {"argv": ["bash", "-lc", "echo no"]}
        errors = BR.validate_suite_data(suite, self.project)
        self.assertTrue(any("not allowlisted" in item for item in errors))

    def test_coding_candidate_can_be_evaluated(self) -> None:
        candidate_root = self.project / "candidates"
        workspace = candidate_root / "coding.python_bugfix_task"
        shutil.copytree(
            self.project / "evals/fixtures/p0_009/coding/python_bugfix",
            workspace,
        )
        calculator = workspace / "calculator.py"
        calculator.write_text(
            calculator.read_text(encoding="utf-8").replace("return left * right", "return left / right"),
            encoding="utf-8",
        )
        report = self.run_report(candidate_root)
        case = next(item for item in report["cases"] if item["id"] == "coding.python_bugfix_task")
        self.assertEqual(case["status"], "passed")
        self.assertEqual(case["score"], 1.0)

    def test_json_candidates_can_be_evaluated(self) -> None:
        candidate_root = self.project / "candidates"
        candidate_root.mkdir(parents=True)
        (candidate_root / "analysis.architecture_review_task.json").write_text(
            json.dumps(
                {
                    "summary": {"currentAuthority": "sqlite_workflow_kernel", "v1Trust": "disabled"},
                    "claims": [
                        "model_output_is_not_authority",
                        "source_checks_are_not_behavioral_proof",
                        "owner_mode_is_not_a_sandbox",
                    ],
                    "citations": ["runtime_boundaries.md", "trust_status.md"],
                }
            ),
            encoding="utf-8",
        )
        (candidate_root / "research.local_citation_task.json").write_text(
            json.dumps(
                {
                    "answer": {"officialReleaseDate": "2026-01-15", "disagreementNoted": True},
                    "citations": ["official_release.md", "changelog.md", "secondary_report.md"],
                }
            ),
            encoding="utf-8",
        )
        report = self.run_report(candidate_root)
        statuses = {item["id"]: item["status"] for item in report["cases"]}
        self.assertEqual(statuses["analysis.architecture_review_task"], "passed")
        self.assertEqual(statuses["research.local_citation_task"], "passed")

    def test_browser_candidate_cannot_override_missing_capability(self) -> None:
        candidate_root = self.project / "candidates"
        candidate_root.mkdir(parents=True)
        (candidate_root / "browser_absent.form_completion_task.json").write_text(
            json.dumps({"submitted": True, "receipt": "KRISTIN-FIXTURE-OK", "evidence": ["before_observation", "after_observation"]}),
            encoding="utf-8",
        )
        report = self.run_report(candidate_root)
        case = next(item for item in report["cases"] if item["id"] == "browser_absent.form_completion_task")
        self.assertEqual(case["status"], "unsupported")

    def test_materialize_copies_fixture(self) -> None:
        output = self.project / "materialized"
        BR.copy_fixture(
            self.project / "evals/fixtures/p0_009/coding/python_bugfix",
            output,
        )
        self.assertTrue((output / "calculator.py").is_file())
        self.assertTrue((output / "TASK.md").is_file())

    def test_check_detects_baseline_drift(self) -> None:
        report = self.run_report()
        baseline = self.project / "evals/results/p0_009_baseline.json"
        BR.write_result(baseline, report)
        args = argparse.Namespace(
            project=str(self.project),
            suite="evals/datasets/p0_009_initial_benchmark.v1.json",
            baseline="evals/results/p0_009_baseline.json",
        )
        with mock.patch.object(
            BR, "run_command", side_effect=self._fake_run_command
        ):
            self.assertEqual(BR.command_check(args), 0)
            value = json.loads(baseline.read_text(encoding="utf-8"))
            value["summary"]["caseCount"] = 99
            baseline.write_text(json.dumps(value), encoding="utf-8")
            self.assertEqual(BR.command_check(args), 1)


    def test_output_redaction_removes_credentials_and_root(self) -> None:
        text = f"{self.project} https://user:pass@example.invalid token=ABCDEF sk-abcdefghijklmnop"
        redacted = BR.redact_output(text, self.project)
        self.assertNotIn(str(self.project), redacted)
        self.assertNotIn("user:pass", redacted)
        self.assertNotIn("ABCDEF", redacted)
        self.assertNotIn("sk-abcdefghijklmnop", redacted)

    def test_candidate_cannot_replace_immutable_acceptance_test(self) -> None:
        candidate_root = self.project / "candidates"
        workspace = candidate_root / "coding.python_bugfix_task"
        shutil.copytree(
            self.project / "evals/fixtures/p0_009/coding/python_bugfix",
            workspace,
        )
        (workspace / "test_calculator.py").write_text(
            "import unittest\nclass Fake(unittest.TestCase):\n    def test_fake(self): self.assertTrue(True)\n",
            encoding="utf-8",
        )
        report = self.run_report(candidate_root)
        case = next(
            item for item in report["cases"]
            if item["id"] == "coding.python_bugfix_task"
        )
        self.assertEqual(case["status"], "failed")
        self.assertTrue(case["observations"]["immutableEvaluator"])

    def test_browser_source_signal_without_evidence_remains_unsupported(self) -> None:
        self._write("lib/product/browser_session.dart", "// source signal only\n")
        report = self.run_report()
        case = next(
            item for item in report["cases"]
            if item["id"] == "browser_absent.capability_inventory"
        )
        self.assertEqual(case["status"], "unsupported")
        self.assertEqual(
            case["reason"], "implementation_signal_without_behavioral_evidence"
        )

    def test_unknown_and_forward_case_dependencies_are_rejected(self) -> None:
        suite = BR.load_json(self.suite_path)
        suite["cases"][0]["requiresCase"] = "missing.case"
        errors = BR.validate_suite_data(suite, self.project)
        self.assertTrue(any("requires unknown case" in item for item in errors))
        suite = BR.load_json(self.suite_path)
        suite["cases"][0]["requiresCase"] = suite["cases"][1]["id"]
        errors = BR.validate_suite_data(suite, self.project)
        self.assertTrue(any("earlier case" in item for item in errors))

    def test_input_fingerprint_tracks_newly_available_required_file(self) -> None:
        suite = BR.load_json(self.suite_path)
        suite["cases"][0].setdefault("requiredFiles", []).append(
            "tool/future_gate.py"
        )
        modified_suite = self.project / "evals/datasets/modified.json"
        modified_suite.write_text(
            json.dumps(suite, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        before = BR.benchmark_inputs_sha256(
            self.project, modified_suite, suite
        )
        self._write("tool/future_gate.py", "print('available')\n")
        after = BR.benchmark_inputs_sha256(
            self.project, modified_suite, suite
        )
        self.assertNotEqual(before, after)

    def test_real_subprocess_command_execution(self) -> None:
        suite = BR.load_json(self.suite_path)
        case = next(
            item for item in suite["cases"]
            if item["id"] == "coding.protocol_contract_gate"
        )
        result = BR.command_case(case, self.project, suite, include_sdk=False)
        self.assertEqual(result.status, "passed")
        self.assertEqual(result.observations["exitCode"], 0)

    def test_result_fingerprint_is_self_verifying(self) -> None:
        report = self.run_report()
        self.assertTrue(BR.verify_result_fingerprint(report))
        report["summary"]["caseCount"] = 99
        self.assertFalse(BR.verify_result_fingerprint(report))

    def test_required_six_categories_exist(self) -> None:
        suite = BR.load_json(self.suite_path)
        errors = BR.validate_suite_data(suite, self.project)
        self.assertEqual(errors, [])
        categories = {item["id"] for item in suite["categories"]}
        self.assertEqual(categories, {"coding", "analysis", "path_safety", "crash_recovery", "browser_absent", "research"})


if __name__ == "__main__":
    unittest.main()
