#!/usr/bin/env python3
from __future__ import annotations
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import worker_e_test_center_registration as registration

BASE = {"schemaVersion": "1.0.0", "testModules": [], "testCases": [], "projectTestProfiles": [], "affectedTestMappings": []}

class RegistrationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "config").mkdir()
        (self.root / "release/evidence/P11-001").mkdir(parents=True)
        (self.root / registration.REGISTRY).write_text(json.dumps(BASE))
        source_root = Path(__file__).resolve().parents[1]
        (self.root / registration.SPEC).write_text((source_root / registration.SPEC).read_text())
        (self.root / registration.HANDOFF).write_text((source_root / registration.HANDOFF).read_text())
    def tearDown(self):
        self.temp.cleanup()
    def test_pending_is_nonmutating(self):
        before = (self.root / registration.REGISTRY).read_bytes()
        first = registration.validate_handoff(self.root)
        second = registration.validate_handoff(self.root)
        self.assertEqual("OWNER_HANDOFF_PENDING", first["state"])
        self.assertEqual(first, second)
        self.assertEqual(before, (self.root / registration.REGISTRY).read_bytes())
    def test_partial_publication_fails(self):
        data = copy.deepcopy(BASE)
        data["testModules"].append({"moduleId": registration.MODULE_ID})
        (self.root / registration.REGISTRY).write_text(json.dumps(data))
        with self.assertRaisesRegex(registration.RegistrationError, "partial or stale"):
            registration.validate_handoff(self.root)
    def test_complete_publication_passes(self):
        spec = json.loads((self.root / registration.SPEC).read_text())
        complete = registration.build_registry(copy.deepcopy(BASE), spec)
        (self.root / registration.REGISTRY).write_bytes(registration.canonical_bytes(complete))
        self.assertEqual("OWNER_PUBLICATION_PRESENT", registration.validate_handoff(self.root)["state"])

if __name__ == "__main__":
    unittest.main(verbosity=2)
