#!/usr/bin/env python3
import importlib.util
import pathlib
import unittest

MODULE_PATH = pathlib.Path(__file__).with_name('p2_004_technology_selection.py')
spec = importlib.util.spec_from_file_location('p2_selection', MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)


def platform_record(name: str, *, node_ok: bool = True) -> dict:
    node_rounds = [
        {"roundId": index, "status": "passed" if node_ok else "failed", "realPtyBehavior": node_ok, "startupMs": 1.0, "rssBytes": 100}
        for index in range(1, 4)
    ]
    return {
        "platform": name,
        "commitSha": "a" * 40,
        "candidates": {
            module.NODE: {"selectionEligible": node_ok, "summary": {"rounds": node_rounds}},
            module.NATIVE: {"selectionEligible": name != "windows", "summary": {"rounds": []}},
            module.DART: {"selectionEligible": False, "summary": {"rounds": []}},
        },
    }


class SelectionAggregationTest(unittest.TestCase):
    def test_selects_node_with_real_tri_platform_pty(self):
        result = module.aggregate([platform_record("linux"), platform_record("macos"), platform_record("windows")])
        self.assertEqual(result["status"], "selected")
        self.assertEqual(result["decision"]["selected"], module.NODE)
        self.assertFalse(result["truthBoundary"]["p2_005InteractivePtyCertified"])
        self.assertFalse(result["truthBoundary"]["p2_006ProcessTreeCertified"])

    def test_missing_platform_blocks(self):
        result = module.aggregate([platform_record("linux"), platform_record("macos")])
        self.assertEqual(result["status"], "blocked")
        self.assertEqual(result["reason"], "tri_platform_records_required")

    def test_failed_selected_candidate_blocks(self):
        result = module.aggregate([platform_record("linux"), platform_record("macos"), platform_record("windows", node_ok=False)])
        self.assertEqual(result["status"], "blocked")
        self.assertEqual(result["reason"], "selected_candidate_lacks_real_tri_platform_pty_measurement")

    def test_commit_mismatch_blocks(self):
        rows = [platform_record("linux"), platform_record("macos"), platform_record("windows")]
        rows[-1]["commitSha"] = "b" * 40
        result = module.aggregate(rows)
        self.assertEqual(result["status"], "blocked")
        self.assertEqual(result["reason"], "commit_mismatch")


if __name__ == '__main__':
    unittest.main()
