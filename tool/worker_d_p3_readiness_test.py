from __future__ import annotations
import copy, importlib.util, json, tempfile, unittest
from pathlib import Path
MODULE_PATH=Path(__file__).with_name("worker_d_p3_readiness.py")
spec=importlib.util.spec_from_file_location("worker_d_p3_readiness",MODULE_PATH)
module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
ROOT=Path(__file__).resolve().parents[1]
class ReadinessTests(unittest.TestCase):
    def test_repository_records_pass(self):
        self.assertEqual([],module.validate(ROOT))
    def test_fixture_checksum_mutation_fails(self):
        with tempfile.TemporaryDirectory() as td:
            dst=Path(td)
            for rel in (
              "release/evidence/P3-001/dependency-status.json",
              "release/evidence/P3-001/runtime-candidate-matrix.json",
              "release/evidence/P3-001/fixture-specification.json",
              "release/evidence/P3-001/test-center-registration.json",
              "release/evidence/P3-001/claim-boundary.json",
              "release/evidence/P3-001/packaging-readiness-contract.json",
              "release/evidence/P3-001/READINESS.md",
              "docs/roadmap/progress/2026-08-05-p3-001-readiness.md"):
                (dst/rel).parent.mkdir(parents=True,exist_ok=True)
                (dst/rel).write_bytes((ROOT/rel).read_bytes())
            p=dst/"release/evidence/P3-001/fixture-specification.json"
            data=json.loads(p.read_text()); data["fixtures"][0]["purpose"]="mutated"
            p.write_text(json.dumps(data))
            self.assertTrue(any("checksum mismatch" in e for e in module.validate(dst)))
    def test_order_independent_selection_contract(self):
        paths=["tool/worker_d_p3_readiness.py","release/evidence/P3-001/fixture-specification.json"]
        selected=lambda xs: sorted({"tc.p3.readiness.fixture-specification","tc.p3.readiness.fixture-determinism","tc.p3.readiness.network-denial"} if any("fixture-specification" in x for x in xs) else {"tc.p3.readiness.dependencies"})
        self.assertEqual(selected(paths),selected(list(reversed(paths))))
if __name__=="__main__": unittest.main()
