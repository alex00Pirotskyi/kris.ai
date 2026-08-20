#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import pathlib
import subprocess
import sys
import tempfile
import types
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
BASE = ROOT / "tool/kris_qwen_worker.py"
V54 = ROOT / "tool/kris_qwen_worker_v54.py"
CATALOG = ROOT / "config/qwen_engineering_skills.v1.json"


def load_module(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def transformed_namespace() -> dict[str, object]:
    module = load_module(V54, "kris_qwen_v54_test_transform")
    text = module.transform(BASE.read_text(encoding="utf-8"))
    namespace: dict[str, object] = {
        "__name__": "kris_qwen_v54_test_runtime",
        "__file__": str(BASE),
        "__package__": None,
        "__cached__": None,
    }
    exec(compile(text, str(BASE), "exec"), namespace, namespace)
    return namespace


class CatalogContractTest(unittest.TestCase):
    def test_catalog_is_bounded_and_unique(self):
        value = json.loads(CATALOG.read_text(encoding="utf-8"))
        self.assertEqual(value["schemaVersion"], "1.0.0")
        self.assertLessEqual(int(value["maxSelectedSkills"]), 8)
        ids = [row["id"] for row in value["skills"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertIn("kris-product-architecture", ids)
        architecture = next(row for row in value["skills"] if row["id"] == "kris-product-architecture")
        self.assertTrue(architecture["always"])


class EngineeringRuntimeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ns = transformed_namespace()
        cls.cfg = types.SimpleNamespace(anchor=ROOT)

    def selected_ids(self, work: dict) -> set[str]:
        rows = self.ns["selected_engineering_skills"](self.cfg, work)
        return {row["id"] for row in rows}

    def test_browser_work_routes_browser_and_architecture(self):
        ids = self.selected_ids({
            "workOrderId": "WO-P3-BROWSER",
            "roadmapTask": "P3-014",
            "type": "PRODUCT_FEATURE",
            "objective": "Improve Browser Workspace inspector and Playwright observation diagnostics",
            "allowedPaths": ["automation_host/src/browser-runtime.mjs", "test/product/browser/**"],
            "requiredTests": ["browser runtime test"],
        })
        self.assertIn("kris-product-architecture", ids)
        self.assertIn("browser-web-studio", ids)

    def test_flutter_work_routes_ui_skill(self):
        ids = self.selected_ids({
            "workOrderId": "WO-P5-UI",
            "roadmapTask": "P5-002",
            "type": "PRODUCT_FEATURE",
            "objective": "Improve Flutter workspace layout and accessibility",
            "allowedPaths": ["lib/product/**", "test/product/**"],
            "requiredTests": ["flutter test"],
        })
        self.assertIn("flutter-product-ui", ids)

    def test_security_work_routes_security_skill(self):
        ids = self.selected_ids({
            "workOrderId": "WO-P2-SECURITY",
            "roadmapTask": "P2-006",
            "type": "PRODUCT_DEFECT_REPAIR",
            "objective": "Repair capability grant and process identity security boundary",
            "allowedPaths": ["authority_service/**"],
            "requiredTests": ["negative security test"],
        })
        self.assertIn("security-boundaries", ids)
        self.assertIn("owner-mode-process", ids)

    def test_recipe_target_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            with self.assertRaises(Exception):
                self.ns["_engineering_recipe_plan"](
                    types.SimpleNamespace(), root, "flutter-test-target", "../outside_test.dart"
                )

    def test_flutter_test_recipe_is_fixed(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            target = root / "test/product/example_test.dart"
            target.parent.mkdir(parents=True)
            target.write_text("void main() {}\n", encoding="utf-8")
            plan = self.ns["_engineering_recipe_plan"](
                types.SimpleNamespace(), root, "flutter-test-target", "test/product/example_test.dart"
            )
            self.assertEqual(
                plan,
                [[
                    "flutter", "test", "--no-pub", "--concurrency=1", "--reporter", "expanded",
                    "test/product/example_test.dart",
                ]],
            )

    def test_native_recipe_uses_ignored_build_directory(self):
        with tempfile.TemporaryDirectory() as td:
            root = pathlib.Path(td)
            source = root / "authority_service"
            source.mkdir(parents=True)
            (source / "CMakeLists.txt").write_text("cmake_minimum_required(VERSION 3.20)\n", encoding="utf-8")
            old = self.ns["resource_plan"]
            self.ns["resource_plan"] = lambda cfg: types.SimpleNamespace(build_jobs=6)
            try:
                plan = self.ns["_engineering_recipe_plan"](
                    types.SimpleNamespace(), root, "native-cmake-test", "authority_service"
                )
            finally:
                self.ns["resource_plan"] = old
            self.assertEqual(plan[0][:3], ["cmake", "-S", "authority_service"])
            self.assertEqual(plan[1][0:2], ["cmake", "--build"])
            self.assertEqual(plan[2][0], "ctest")
            self.assertTrue(plan[0][-1].startswith("build/qwen-recipes/cmake-"))

    def test_ui_map_is_explicitly_text_only(self):
        module = load_module(V54, "kris_qwen_v54_marker_test")
        text = module.transform(BASE.read_text(encoding="utf-8"))
        self.assertIn("TEXTUAL_UI_STRUCTURE_ONLY", text)
        self.assertIn("does not inspect or judge screenshot pixels", text)

    def test_transform_preserves_531_safety_and_adds_engineering_actions(self):
        module = load_module(V54, "kris_qwen_v54_contract_test")
        text = module.transform(BASE.read_text(encoding="utf-8"))
        for marker in (
            'SCRIPT_VERSION = "5.4.0"',
            "RED_ALERT_PRODUCT_DIVERGENCE",
            "RED_ALERT_HARD_ERROR",
            "RED_ALERT_MODEL_SERVER",
            "response_schema=REVIEW_ACTION_SCHEMA",
            '"action":"run_recipe"',
            '"action":"read_skill"',
            '"action":"inspect_pr_checks"',
            "engineeringRecipe",
        ):
            self.assertIn(marker, text)

    def test_real_v54_version_entry_executes(self):
        result = subprocess.run(
            [sys.executable, str(V54), "version"],
            cwd=ROOT,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        value = json.loads(result.stdout)
        self.assertEqual(value["scriptVersion"], "5.4.0")
        self.assertTrue(str(value["path"]).endswith("kris_qwen_worker_v54.py"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
