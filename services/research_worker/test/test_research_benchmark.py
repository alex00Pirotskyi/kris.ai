from __future__ import annotations

import json
import pathlib
import unittest

from services.research_worker.src.research.runtime import QueryPlanner


class ResearchBenchmarkTest(unittest.TestCase):
    def test_planner_covers_committed_quality_corpus(self):
        fixture = pathlib.Path(__file__).resolve().parent / "fixtures/p4_research_benchmark.json"
        corpus = json.loads(fixture.read_text())
        planner = QueryPlanner()
        passed = 0
        for case in corpus["cases"]:
            plan = planner.plan(case["question"])
            query_text = "\n".join(plan.queries).lower()
            for term in case["expectedTerms"]:
                self.assertIn(term.lower(), query_text, case["id"])
            kinds = set(case["requiredQueryKinds"])
            if "precision" in kinds:
                self.assertTrue(plan.precision, case["id"])
            if "recall" in kinds:
                self.assertTrue(plan.recall, case["id"])
            if "official" in kinds:
                self.assertTrue(plan.official, case["id"])
            if "freshness" in kinds:
                self.assertTrue(plan.freshness, case["id"])
            if "follow_up" in kinds:
                self.assertTrue(plan.follow_up, case["id"])
            if case["requiresFreshness"]:
                self.assertTrue(plan.freshness, case["id"])
            passed += 1
        coverage = passed / len(corpus["cases"])
        self.assertGreaterEqual(coverage, corpus["thresholds"]["plannerCoverage"])


if __name__ == "__main__":
    unittest.main()
