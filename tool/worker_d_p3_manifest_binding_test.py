from __future__ import annotations

import copy
import importlib.util
import json
import subprocess
import tempfile
import unittest
from hashlib import sha256
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("worker_d_p3_manifest_binding.py")
SPEC = importlib.util.spec_from_file_location("worker_d_p3_manifest_binding", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
ROOT = Path(__file__).resolve().parents[1]


def _run(root: Path, *args: str) -> str:
    return subprocess.run(
        list(args),
        cwd=root,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    ).stdout.strip()


class ManifestBindingTests(unittest.TestCase):
    def setUp(self) -> None:
        self._temp = tempfile.TemporaryDirectory()
        self.root = Path(self._temp.name)
        _run(self.root, "git", "init", "-q")
        _run(self.root, "git", "config", "user.email", "p3-test@example.invalid")
        _run(self.root, "git", "config", "user.name", "P3 Test")
        self.manifest = self._seed_repository()

    def tearDown(self) -> None:
        self._temp.cleanup()

    def _write_manifest(self, manifest: dict) -> None:
        path = self.root / MODULE.MANIFEST_PATH
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps(manifest, indent=2) + "\n",
            encoding="utf-8",
            newline="\n",
        )

    def _seed_repository(self) -> dict:
        artifacts = []
        for index, rel in enumerate(sorted(MODULE.EXPECTED_ARTIFACT_PATHS)):
            target = self.root / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            payload = f"artifact-{index}:{rel}\n".encode()
            target.write_bytes(payload)
            artifacts.append({"path": rel, "sha256": sha256(payload).hexdigest()})
        self._write_manifest(
            {
                "artifacts": artifacts,
                "testedSourceCandidate": {"commit": "0" * 40, "tree": "0" * 40},
                "evidencePackagingCandidate": {
                    "binding": MODULE.PACKAGING_BINDING,
                    "classification": MODULE.PACKAGING_CLASSIFICATION,
                    "commit": "0" * 40,
                    "tree": "0" * 40,
                },
            }
        )
        _run(self.root, "git", "add", ".")
        _run(self.root, "git", "commit", "-qm", "stage1")
        stage1 = _run(self.root, "git", "rev-parse", "HEAD")
        stage1_tree = _run(self.root, "git", "rev-parse", "HEAD^{tree}")
        _run(self.root, "git", "commit", "--allow-empty", "-qm", "stage2")
        stage2 = _run(self.root, "git", "rev-parse", "HEAD")
        stage2_tree = _run(self.root, "git", "rev-parse", "HEAD^{tree}")
        manifest = json.loads((self.root / MODULE.MANIFEST_PATH).read_text(encoding="utf-8"))
        manifest["testedSourceCandidate"] = {"commit": stage1, "tree": stage1_tree}
        manifest["evidencePackagingCandidate"].update(
            {"commit": stage2, "tree": stage2_tree}
        )
        self._write_manifest(manifest)
        _run(self.root, "git", "add", MODULE.MANIFEST_PATH)
        _run(self.root, "git", "commit", "-qm", "bind immutable packaging candidate")
        return manifest

    def test_repository_bindings_pass(self):
        self.assertEqual([], MODULE.validate(ROOT))

    def test_synthetic_immutable_bindings_pass(self):
        self.assertEqual([], MODULE.validate(self.root))

    def test_current_head_artifact_drift_requires_explicit_rebind(self):
        target = self.root / sorted(MODULE.EXPECTED_ARTIFACT_PATHS)[0]
        target.write_bytes(target.read_bytes() + b"head-drift\n")
        _run(self.root, "git", "add", str(target.relative_to(self.root)))
        _run(self.root, "git", "commit", "-qm", "mutate manifested artifact")
        errors = MODULE.validate(self.root)
        self.assertTrue(any("drifted after frozen packaging candidate" in e for e in errors))

    def test_working_tree_bytes_do_not_rebind_frozen_git_evidence(self):
        target = self.root / sorted(MODULE.EXPECTED_ARTIFACT_PATHS)[0]
        target.write_bytes(target.read_bytes() + b"uncommitted-drift\n")
        self.assertEqual([], MODULE.validate(self.root))

    def test_recorded_hash_drift_fails(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["artifacts"][0]["sha256"] = "0" * 64
        self._write_manifest(manifest)
        errors = MODULE.validate(self.root)
        self.assertTrue(any("digest mismatch" in e for e in errors))

    def test_packaging_tree_drift_fails(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["evidencePackagingCandidate"]["tree"] = "0" * 40
        self._write_manifest(manifest)
        errors = MODULE.validate(self.root)
        self.assertTrue(any("evidencePackagingCandidate.tree mismatch" in e for e in errors))

    def test_external_null_packaging_slot_fails_closed(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["evidencePackagingCandidate"] = {
            "binding": "EXTERNAL_AFTER_PUBLICATION",
            "classification": MODULE.PACKAGING_CLASSIFICATION,
            "commit": None,
            "tree": None,
        }
        self._write_manifest(manifest)
        errors = MODULE.validate(self.root)
        self.assertTrue(
            any("evidencePackagingCandidate.commit must be a 40-character" in e for e in errors)
        )

    def test_packaging_classification_drift_fails(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["evidencePackagingCandidate"]["classification"] = "SELF_DECLARED"
        self._write_manifest(manifest)
        errors = MODULE.validate(self.root)
        self.assertTrue(
            any(
                "classification must be STAGE_2_EVIDENCE_PACKAGING" in e
                for e in errors
            )
        )

    def test_unknown_packaging_binding_fails(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["evidencePackagingCandidate"]["binding"] = "SELF_DECLARED"
        self._write_manifest(manifest)
        errors = MODULE.validate(self.root)
        self.assertTrue(any("binding must be IMMUTABLE_GIT_CANDIDATE" in e for e in errors))

    def test_duplicate_binding_fails(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["artifacts"].append(dict(manifest["artifacts"][0]))
        self._write_manifest(manifest)
        self.assertTrue(
            any("duplicate manifest artifact path" in e for e in MODULE.validate(self.root))
        )

    def test_missing_binding_fails(self):
        manifest = copy.deepcopy(self.manifest)
        removed = manifest["artifacts"].pop()
        self._write_manifest(manifest)
        errors = MODULE.validate(self.root)
        self.assertTrue(
            any(
                "manifest artifact bindings missing" in e and removed["path"] in e
                for e in errors
            )
        )

    def test_unexpected_binding_fails(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["artifacts"].append(
            {"path": "tool/worker_d_p3_unexpected.py", "sha256": "0" * 64}
        )
        self._write_manifest(manifest)
        errors = MODULE.validate(self.root)
        self.assertTrue(
            any(
                "manifest artifact bindings unexpected" in e
                and "tool/worker_d_p3_unexpected.py" in e
                for e in errors
            )
        )

    def test_unsafe_binding_path_fails(self):
        manifest = copy.deepcopy(self.manifest)
        manifest["artifacts"][0]["path"] = "../escape"
        self._write_manifest(manifest)
        self.assertTrue(any("unsafe path" in e for e in MODULE.validate(self.root)))


if __name__ == "__main__":
    unittest.main()
