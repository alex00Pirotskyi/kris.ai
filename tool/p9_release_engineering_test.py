#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest

TOOL = Path(__file__).resolve().parent
if str(TOOL) not in sys.path:
    sys.path.insert(0, str(TOOL))

from p9_release_engineering import (
    ReleaseEngineeringError,
    artifact_file_manifest,
    artifact_tree_sha256,
    create_release_bundle,
    load_release_config,
    sha256_file,
    verify_release_bundle,
)


LOCK = '''packages:\n  collection:\n    dependency: transitive\n    description:\n      name: collection\n      sha256: abc\n      url: "https://pub.dev"\n    source: hosted\n    version: "1.19.1"\n  sqlite3:\n    dependency: "direct main"\n    description:\n      name: sqlite3\n      sha256: def\n      url: "https://pub.dev"\n    source: hosted\n    version: "2.9.4"\n'''


class P9ReleaseEngineeringTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="p9-release-test-")
        self.root = Path(self.temp.name)
        (self.root / "config").mkdir()
        shutil.copyfile(TOOL.parent / "config" / "release_targets.v1.json", self.root / "config" / "release_targets.v1.json")
        (self.root / "pubspec.lock").write_text(LOCK, encoding="utf-8")
        self.artifact = self.root / "artifact"
        (self.artifact / "data").mkdir(parents=True)
        (self.artifact / "kris_studio_ai_2").write_bytes(b"native-binary\x00fixture")
        (self.artifact / "data" / "flutter_assets.dat").write_bytes(b"assets")
        self.source = "a" * 40

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _bundle(self, name: str = "release.zip", signing=None):
        return create_release_bundle(
            project=self.root,
            artifact=self.artifact,
            platform="linux",
            output=self.root / name,
            source_commit=self.source,
            signing_evidence=signing,
        )

    def test_release_config_is_incremental_and_credentials_remain_external(self) -> None:
        config = load_release_config(self.root)
        self.assertEqual(set(config["targets"]), {"windows", "macos", "linux"})
        for target in config["targets"].values():
            self.assertEqual(target["buildArgv"][0], "flutter")
            self.assertNotIn("clean", target["buildArgv"])
            self.assertIn("--no-pub", target["buildArgv"])
            self.assertEqual(target["signing"]["credentialBoundary"], "external")

    def test_unsigned_bundle_is_reproducible_and_verifies(self) -> None:
        first = self._bundle("first.zip")
        second = self._bundle("second.zip")
        self.assertEqual(sha256_file(Path(first["bundle"])), sha256_file(Path(second["bundle"])))
        verified = verify_release_bundle(
            project=self.root,
            bundle=Path(first["bundle"]),
            provenance_path=Path(first["provenance"]),
        )
        self.assertEqual(verified["resultState"], "PASS")
        self.assertFalse(verified["signed"])
        self.assertEqual(verified["supportClaim"], "UNSIGNED_RELEASE_FOUNDATION")
        with self.assertRaisesRegex(ReleaseEngineeringError, "signed release required") as caught:
            verify_release_bundle(
                project=self.root,
                bundle=Path(first["bundle"]),
                provenance_path=Path(first["provenance"]),
                require_signed=True,
            )
        self.assertEqual(caught.exception.code, "signing_required")

    def test_signing_evidence_binds_exact_native_tree(self) -> None:
        tree_sha = artifact_tree_sha256(artifact_file_manifest(self.artifact))
        evidence = {
            "scheme": "detached-package-signature",
            "verified": True,
            "identity": "fixture-release-key",
            "subjectSha256": tree_sha,
        }
        result = self._bundle("signed.zip", signing=evidence)
        verified = verify_release_bundle(
            project=self.root,
            bundle=Path(result["bundle"]),
            provenance_path=Path(result["provenance"]),
            require_signed=True,
        )
        self.assertTrue(verified["signed"])
        self.assertEqual(verified["supportClaim"], "OS_SIGNING_EVIDENCE_BOUND")
        bad = dict(evidence, subjectSha256="0" * 64)
        with self.assertRaises(ReleaseEngineeringError) as caught:
            self._bundle("bad-signing.zip", signing=bad)
        self.assertEqual(caught.exception.code, "signing_digest")

    def test_macos_signing_requires_notarization_evidence(self) -> None:
        tree_sha = artifact_tree_sha256(artifact_file_manifest(self.artifact))
        with self.assertRaises(ReleaseEngineeringError) as caught:
            create_release_bundle(
                project=self.root,
                artifact=self.artifact,
                platform="macos",
                output=self.root / "mac.zip",
                source_commit=self.source,
                signing_evidence={
                    "scheme": "codesign+notarization",
                    "verified": True,
                    "identity": "Developer ID Application: fixture",
                    "subjectSha256": tree_sha,
                    "notarizationVerified": False,
                },
            )
        self.assertEqual(caught.exception.code, "notarization_unverified")

    def test_lock_and_config_drift_fail_closed(self) -> None:
        result = self._bundle()
        (self.root / "pubspec.lock").write_text(LOCK + "\n# drift\n", encoding="utf-8")
        with self.assertRaises(ReleaseEngineeringError) as caught:
            verify_release_bundle(
                project=self.root,
                bundle=Path(result["bundle"]),
                provenance_path=Path(result["provenance"]),
            )
        self.assertEqual(caught.exception.code, "lock_drift")

    def test_unsafe_artifact_symlink_is_rejected(self) -> None:
        outside = self.root / "outside.txt"
        outside.write_text("outside", encoding="utf-8")
        link = self.artifact / "escape"
        try:
            link.symlink_to(outside)
        except (OSError, NotImplementedError):
            self.skipTest("host does not permit disposable symlink creation")
        with self.assertRaises(ReleaseEngineeringError) as caught:
            self._bundle("unsafe.zip")
        self.assertEqual(caught.exception.code, "artifact_symlink_escape")

    def test_safe_relative_symlink_is_preserved_in_bundle(self) -> None:
        target = self.artifact / "data" / "target.txt"
        target.write_text("target", encoding="utf-8")
        link = self.artifact / "data" / "current.txt"
        try:
            link.symlink_to("target.txt")
        except (OSError, NotImplementedError):
            self.skipTest("host does not permit disposable symlink creation")
        result = self._bundle("symlink.zip")
        verified = verify_release_bundle(
            project=self.root,
            bundle=Path(result["bundle"]),
            provenance_path=Path(result["provenance"]),
        )
        self.assertEqual(verified["resultState"], "PASS")


if __name__ == "__main__":
    unittest.main()
