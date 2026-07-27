from __future__ import annotations

import json
import unittest
from datetime import datetime, timezone
from pathlib import Path

from capability_grant_v2 import GrantUseLedger, GrantVerificationError, verify_and_consume

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "evals/fixtures/p1_003_capability_grants/vectors.json"
KEY_ID = "fixture-key-1"
KEY = b"fixture-only-not-a-secret"


def _now(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def _verify(grant, *, ledger=None, invocation="inv-1", expected_run_id="run-001"):
    return verify_and_consume(
        grant,
        keyring={KEY_ID: KEY},
        ledger=ledger or GrantUseLedger(),
        expected_run_id=expected_run_id,
        expected_task_id="task-001",
        expected_actor_id="owner_executor",
        expected_tool_id="filesystem.write",
        expected_access_profile_id="owner",
        invocation_id=invocation,
        now=_now(json.loads(FIXTURE.read_text(encoding="utf-8"))["fixedNow"]),
    )


class CapabilityGrantV2Test(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))

    def test_valid_grant_verifies(self):
        value = _verify(self.fixture["validGrant"])
        self.assertEqual(value["binding"]["runId"], "run-001")

    def test_required_adversarial_vectors_fail_closed(self):
        observed = {}
        for case in self.fixture["cases"]:
            ledger = GrantUseLedger()
            try:
                if case["kind"] == "context":
                    _verify(case["grant"], ledger=ledger, expected_run_id=case["expectedRunId"])
                elif case["kind"] == "replay":
                    _verify(case["grant"], ledger=ledger, invocation=case["invocationId"])
                    _verify(case["grant"], ledger=ledger, invocation=case["invocationId"])
                elif case["kind"] == "exhaust":
                    _verify(case["grant"], ledger=ledger, invocation=case["firstInvocationId"])
                    _verify(case["grant"], ledger=ledger, invocation=case["secondInvocationId"])
                else:
                    _verify(case["grant"], ledger=ledger)
            except GrantVerificationError as error:
                observed[case["name"]] = error.code
        expected = {case["name"]: case["expectedError"] for case in self.fixture["cases"]}
        self.assertEqual(observed, expected)

    def test_envelope_contains_no_issuer_key_material(self):
        serialized = json.dumps(self.fixture["validGrant"], sort_keys=True)
        self.assertNotIn(KEY.decode(), serialized)
        for forbidden in ("keyMaterial", "secretValue", "rawSecret", "privateKey", "signingKey"):
            self.assertNotIn(forbidden, serialized)


if __name__ == "__main__":
    unittest.main(verbosity=2)
