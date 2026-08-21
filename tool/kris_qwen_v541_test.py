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
V541 = ROOT / "tool/kris_qwen_worker_v541.py"
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
    transformer = load_module(V541, "kris_qwen_v541_test_transform")
    text = transformer.transform(BASE.read_text(encoding="utf-8"))
    name = "kris_qwen_v541_test_runtime"
    runtime = types.ModuleType(name)
    runtime.__file__ = str(V541)
    runtime.__package__ = None
    runtime.__cached__ = None
    sys.modules[name] = runtime
    exec(compile(text, str(BASE), "exec"), runtime.__dict__, runtime.__dict__)
    return runtime.__dict__


class EngineeringDeploymentRegressionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ns = transformed_namespace()

    def test_catalog_comes_from_validated_execution_checkout_not_worker_anchor(self):
        with tempfile.TemporaryDirectory() as td:
            cfg = types.SimpleNamespace(anchor=pathlib.Path(td) / "authority-clone-without-catalog")
            actual = self.ns["_engineering_catalog_path"](cfg)
        self.assertEqual(actual, CATALOG)
        self.assertTrue(actual.is_file())

    def test_catalog_loader_works_when_authority_clone_has_no_catalog(self):
        with tempfile.TemporaryDirectory() as td:
            cfg = types.SimpleNamespace(anchor=pathlib.Path(td) / "empty-authority-clone")
            value = self.ns["load_engineering_skill_catalog"](cfg)
        self.assertEqual(value["schemaVersion"], "1.0.0")
        self.assertGreater(len(value["skills"]), 0)

    def test_environment_validation_precedes_semaphore_reservation(self):
        transformer = load_module(V541, "kris_qwen_v541_order_test")
        text = transformer.transform(BASE.read_text(encoding="utf-8"))
        marker = "validate_engineering_environment(cfg)\n        lease = reserve_work(cfg, worker_identity, work_execution_id)"
        self.assertIn(marker, text)
        self.assertNotIn(
            "lease = reserve_work(cfg, worker_identity, work_execution_id)\n        validate_engineering_environment(cfg)",
            text,
        )

    def test_transform_retains_54_engineering_and_531_safety(self):
        transformer = load_module(V541, "kris_qwen_v541_contract_test")
        text = transformer.transform(BASE.read_text(encoding="utf-8"))
        for marker in (
            'SCRIPT_VERSION = "5.4.1"',
            "def execute_engineering_recipe",
            "TEXTUAL_UI_STRUCTURE_ONLY",
            "RED_ALERT_PRODUCT_DIVERGENCE",
            "RED_ALERT_HARD_ERROR",
            "RED_ALERT_MODEL_SERVER",
            "response_schema=REVIEW_ACTION_SCHEMA",
        ):
            self.assertIn(marker, text)

    def test_real_v541_version_entry_executes(self):
        result = subprocess.run(
            [sys.executable, str(V541), "version"],
            cwd=ROOT,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )
        value = json.loads(result.stdout)
        self.assertEqual(value["scriptVersion"], "5.4.1")
        self.assertTrue(str(value["path"]).endswith("kris_qwen_worker_v541.py"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
