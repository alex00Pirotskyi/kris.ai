#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

from p2_evidence_state import (
    EvidenceStateError,
    P2_004_DIAGNOSTIC,
    P2_004_MANIFEST,
    P2_004_SPIKE,
    P2_004_STATE,
    P2_LEGACY_MANIFEST,
    P2_PHASE_STATE,
    validate_repository,
)


ROOT = Path(__file__).resolve().parents[1]
FIXTURE_PATHS = (
    P2_004_STATE,
    P2_PHASE_STATE,
    P2_004_MANIFEST,
    P2_004_SPIKE,
    P2_004_DIAGNOSTIC,
    P2_LEGACY_MANIFEST,
    "docs/adr/ADR-0012-p2-automation-host.md",
)


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class P2EvidenceStateTest(unittest.TestCase):
    def fixture(self) -> tuple[tempfile.TemporaryDirectory[str], Path]:
        temporary = tempfile.TemporaryDirectory(prefix="p2-evidence-state-")
        root = Path(temporary.name)
        for relative in FIXTURE_PATHS:
            source = ROOT / relative
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
        return temporary, root

    def mutate(self, root: Path, relative: str, callback) -> None:
        path = root / relative
        value = load(path)
        callback(value)
        path.write_text(
            json.dumps(value, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
            newline="\n",
        )

    def assert_rejected(self, root: Path) -> None:
        with self.assertRaises(EvidenceStateError):
            validate_repository(root)

    def test_repository_state_is_valid(self) -> None:
        result = validate_repository(ROOT)
        self.assertEqual(result["acceptedDecisionTasks"], ["P2-004"])
        self.assertEqual(result["behaviorCertifiedTasks"], [])
        self.assertFalse(result["platformQualified"])
        self.assertFalse(result["releaseSupported"])
        self.assertFalse(result["productionSupported"])
        self.assertFalse(result["gaPromoted"])

    def test_behavior_overclaim_is_rejected(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        self.mutate(
            root,
            P2_004_STATE,
            lambda value: value.update(
                {
                    "claimLevel": "BEHAVIOR_VERIFIED",
                    "productBehaviorObserved": True,
                }
            ),
        )
        self.assert_rejected(root)

    def test_platform_promotion_is_rejected(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        self.mutate(
            root,
            P2_004_STATE,
            lambda value: value.update({"platformQualified": True}),
        )
        self.assert_rejected(root)

    def test_phase_completion_from_decision_only_is_rejected(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        self.mutate(
            root,
            P2_PHASE_STATE,
            lambda value: value.update(
                {"status": "complete", "phaseCompletionEligible": True}
            ),
        )
        self.assert_rejected(root)

    def test_missing_accepted_decision_binding_is_rejected(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        self.mutate(
            root,
            P2_PHASE_STATE,
            lambda value: value.update({"acceptedDecisionTasks": []}),
        )
        self.assert_rejected(root)

    def test_legacy_acceptance_cannot_remain_state_authority(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        self.mutate(
            root,
            P2_004_MANIFEST,
            lambda value: value.update(
                {"recordRole": "active", "stateAuthority": True}
            ),
        )
        self.assert_rejected(root)

    def test_diagnostic_cannot_become_active_state(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        self.mutate(
            root,
            P2_004_DIAGNOSTIC,
            lambda value: value.update(
                {"recordRole": "active", "stateAuthority": True}
            ),
        )
        self.assert_rejected(root)

    def test_closed_task_state_rejects_unknown_fields(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        self.mutate(
            root,
            P2_004_STATE,
            lambda value: value.update({"unsupportedPromotion": True}),
        )
        self.assert_rejected(root)

    def test_downstream_certification_cannot_be_inferred(self) -> None:
        temporary, root = self.fixture()
        self.addCleanup(temporary.cleanup)
        self.mutate(
            root,
            P2_004_STATE,
            lambda value: value["downstreamTasks"].update({"P2-005": True}),
        )
        self.assert_rejected(root)


if __name__ == "__main__":
    unittest.main(verbosity=2)
