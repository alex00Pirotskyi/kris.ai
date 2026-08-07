#!/usr/bin/env python3
"""Deterministic Mission Execution 1.5 semaphore/dispatcher scale regressions."""
from __future__ import annotations

import os
import pathlib
import sys
import unittest

THIS = pathlib.Path(__file__).resolve()
if str(THIS.parent) not in sys.path:
    sys.path.insert(0, str(THIS.parent))

from mission_runtime_model import dispatch_score, semaphore_collides

WORKER_COUNT = int(os.environ.get("MISSION_V15_WORKERS", "100"))


def sem(kind: str, idx: int, **extra):
    item = {
        "kind": kind,
        "semaphoreId": f"SEM-{idx:04d}",
        "allowedPaths": [],
        "productPr": None,
        "authorityId": None,
        "resourceId": None,
    }
    item.update(extra)
    return item


class SemaphoreScaleTests(unittest.TestCase):
    def test_non_overlapping_write_scopes_scale_without_global_mutex(self):
        items = [
            sem("WRITE", i, allowedPaths=[f"lib/product/shard_{i}/**"])
            for i in range(WORKER_COUNT)
        ]
        for i, left in enumerate(items):
            for right in items[i + 1 :]:
                self.assertFalse(semaphore_collides(left, right))

    def test_same_write_scope_collides(self):
        self.assertTrue(
            semaphore_collides(
                sem("WRITE", 1, allowedPaths=["lib/product/model/**"]),
                sem("WRITE", 2, allowedPaths=["lib/product/model/a.dart"]),
            )
        )

    def test_integration_is_product_pr_scoped(self):
        self.assertTrue(
            semaphore_collides(
                sem("INTEGRATION", 1, productPr=76),
                sem("INTEGRATION", 2, productPr=76),
            )
        )
        self.assertFalse(
            semaphore_collides(
                sem("INTEGRATION", 1, productPr=76),
                sem("INTEGRATION", 2, productPr=62),
            )
        )

    def test_release_is_resource_scoped(self):
        self.assertTrue(
            semaphore_collides(
                sem("RELEASE", 1, resourceId="SOURCE_MANIFEST"),
                sem("RELEASE", 2, resourceId="SOURCE_MANIFEST"),
            )
        )
        self.assertFalse(
            semaphore_collides(
                sem("RELEASE", 1, resourceId="SOURCE_MANIFEST"),
                sem("RELEASE", 2, resourceId="INSTALLER_SIGNING"),
            )
        )

    def test_integration_outranks_new_product_build(self):
        integration = {"type": "INTEGRATION", "priority": 50, "parentProductPr": 76}
        feature = {"type": "PRODUCT_FEATURE", "priority": 100, "parentProductPr": 62}
        self.assertGreater(dispatch_score(integration, {}), dispatch_score(feature, {}))

    def test_backpressure_blocks_more_build_when_two_helpers_wait(self):
        feature = {"type": "PRODUCT_FEATURE", "priority": 100, "parentProductPr": 76}
        self.assertLess(dispatch_score(feature, {76: 2}), 0)

    def test_requested_worker_count_is_supported(self):
        self.assertGreaterEqual(WORKER_COUNT, 1)
        self.assertLessEqual(WORKER_COUNT, 1000)


if __name__ == "__main__":
    unittest.main()
