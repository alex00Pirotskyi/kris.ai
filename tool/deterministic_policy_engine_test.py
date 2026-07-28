#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import random
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


ENGINE = load(ROOT / "tool" / "deterministic_policy_engine.py", "p1_004_policy_engine")
CATALOG = json.loads((ROOT / "config" / "access_profiles.v2.json").read_text(encoding="utf-8"))
CONFIG = json.loads((ROOT / "config" / "policy_engine.v2.json").read_text(encoding="utf-8"))
FIXTURE = json.loads((ROOT / "evals" / "fixtures" / "p1_004_policy_engine" / "property_cases.json").read_text(encoding="utf-8"))


class DeterministicPolicyEngineTest(unittest.TestCase):
    def evaluate(self, request):
        return ENGINE.evaluate_policy(request, access_catalog=CATALOG, policy_config=CONFIG)

    def test_shared_cases(self):
        for case in FIXTURE["cases"]:
            with self.subTest(case=case["name"]):
                result = self.evaluate(case["request"])
                self.assertEqual(case["expectedStatus"], result["status"])
                self.assertTrue(set(case.get("expectedReasons", [])).issubset(result["reasonCodes"]))

    def test_overlay_order_is_deterministic(self):
        case = next(item for item in FIXTURE["cases"] if item["name"] == "overlay_order_reference")
        request = copy.deepcopy(case["request"])
        forward = self.evaluate(request)
        request["overlays"] = list(reversed(request["overlays"]))
        reverse = self.evaluate(request)
        self.assertEqual(forward, reverse)

    def test_deny_is_monotonic(self):
        seed = int(FIXTURE["propertySeed"])
        randomizer = random.Random(seed)
        source = copy.deepcopy(FIXTURE["cases"][0]["request"])
        for index in range(300):
            request = copy.deepcopy(source)
            request["requestId"] = f"monotonic-{index}"
            if randomizer.random() < 0.5:
                request["overlays"] = [{"layer": "organization", "overlayId": f"deny-{index}", "denyCapabilities": [request["binding"]["capabilityId"]]}]
                self.assertEqual("deny", self.evaluate(request)["status"])
            else:
                request["overlays"] = [{"layer": "organization", "overlayId": f"force-{index}", "forceDeny": True}]
                self.assertEqual("deny", self.evaluate(request)["status"])

    def test_budget_overlays_never_widen(self):
        source = copy.deepcopy(FIXTURE["cases"][0]["request"])
        baseline = self.evaluate(source)["effectiveBudgets"]
        for limit in (0, 1, 10, 100, 1000, 1000000):
            request = copy.deepcopy(source)
            request["overlays"] = [{"layer": "project", "overlayId": f"budget-{limit}", "maxBudgets": {"maxMutations": limit}}]
            effective = self.evaluate(request)["effectiveBudgets"]
            self.assertLessEqual(effective["maxMutations"], baseline["maxMutations"])
            self.assertLessEqual(effective["maxMutations"], limit)

    def test_model_text_cannot_create_approval_or_widening(self):
        forged = next(item for item in FIXTURE["cases"] if item["name"] == "model_cannot_approve")
        self.assertEqual("deny", self.evaluate(forged["request"])["status"])
        widening = copy.deepcopy(next(item for item in FIXTURE["cases"] if item["name"] == "approved_widening_within_ceiling")["request"])
        widening["explicitWidening"]["source"] = "web"
        result = self.evaluate(widening)
        self.assertEqual("deny", result["status"])
        self.assertIn("untrusted_authority_source", result["reasonCodes"])

    def test_owner_mode_retains_intended_authority_ceiling(self):
        approved = next(item for item in FIXTURE["cases"] if item["name"] == "owner_delete_approved")
        result = self.evaluate(approved["request"])
        self.assertEqual("allow", result["status"])
        self.assertEqual("owner", result["effectiveProfileId"])
        self.assertFalse(result["effectiveScope"]["credentials"].get("rawReveal") == "always")
        self.assertIsNotNone(result["grantDraft"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
