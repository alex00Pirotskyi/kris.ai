from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from hashlib import sha256
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("worker_d_p3_manifest_binding.py")
SPEC = importlib.util.spec_from_file_location("worker_d_p3_manifest_binding", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
ROOT = Path(__file__).resolve().parents[1]


class ManifestBindingTests(unittest.TestCase):
    def copy_bound_tree(self, destination: Path) -> dict:
        manifest_source = ROOT / MODULE.MANIFEST_PATH
        manifest = json.loads(manifest_source.read_text(encoding="utf-8"))
        manifest_target = destination / MODULE.MANIFEST_PATH
        manifest_target.parent.mkdir(parents=True, exist_ok=True)
        manifest_target.write_bytes(manifest_source.read_bytes())
        for artifact in manifest["artifacts"]:
            rel = artifact["path"]
            source = ROOT / rel
            target = destination / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
        return manifest

    def write_manifest(self, destination: Path, manifest: dict) -> None:
        path = destination / MODULE.MANIFEST_PATH
        path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")

    def test_repository_bindings_pass(self):
        self.assertEqual([], MODULE.validate(ROOT))

    def test_bound_file_byte_drift_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.copy_bound_tree(root)
            target = root / "release/evidence/P3-001/claim-boundary.json"
            target.write_bytes(target.read_bytes() + b"\n")
            self.assertTrue(any("digest mismatch" in e for e in MODULE.validate(root)))

    def test_recorded_hash_drift_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest = self.copy_bound_tree(root)
            manifest["artifacts"][0]["sha256"] = "0" * 64
            self.write_manifest(root, manifest)
            self.assertTrue(any("digest mismatch" in e for e in MODULE.validate(root)))

    def test_duplicate_binding_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest = self.copy_bound_tree(root)
            manifest["artifacts"].append(dict(manifest["artifacts"][0]))
            self.write_manifest(root, manifest)
            self.assertTrue(any("duplicate manifest artifact path" in e for e in MODULE.validate(root)))

    def test_missing_binding_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest = self.copy_bound_tree(root)
            removed = manifest["artifacts"].pop()
            self.write_manifest(root, manifest)
            errors = MODULE.validate(root)
            self.assertTrue(any("manifest artifact bindings missing" in e and removed["path"] in e for e in errors))

    def test_unexpected_binding_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest = self.copy_bound_tree(root)
            extra_rel = "tool/worker_d_p3_unexpected.py"
            extra = root / extra_rel
            extra.parent.mkdir(parents=True, exist_ok=True)
            extra.write_text("print('unexpected')\n", encoding="utf-8")
            manifest["artifacts"].append({"path": extra_rel, "sha256": sha256(extra.read_bytes()).hexdigest()})
            self.write_manifest(root, manifest)
            errors = MODULE.validate(root)
            self.assertTrue(any("manifest artifact bindings unexpected" in e and extra_rel in e for e in errors))

    def test_unsafe_binding_path_fails(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest = self.copy_bound_tree(root)
            manifest["artifacts"][0]["path"] = "../escape"
            self.write_manifest(root, manifest)
            self.assertTrue(any("unsafe path" in e for e in MODULE.validate(root)))


if __name__ == "__main__":
    unittest.main()
