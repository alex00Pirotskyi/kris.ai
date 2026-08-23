#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
import zipfile

TOOL = Path(__file__).resolve().parent
if str(TOOL) not in sys.path:
    sys.path.insert(0, str(TOOL))

from ed25519_ref import public_key
from p9_release_engineering import create_release_bundle, sha256_file
import p9_update_install as updater
from p9_update_install import UpdateInstallError, accept_update, install_verified_update, recover_interrupted, rollback, verify_update
from signed_manifest_v2 import sign_manifest


LOCK = '''packages:\n  sqlite3:\n    dependency: "direct main"\n    description:\n      name: sqlite3\n      sha256: def\n      url: "https://pub.dev"\n    source: hosted\n    version: "2.9.4"\n'''
SEED = bytes(range(32))
NOW = datetime(2026, 8, 24, 0, 0, tzinfo=timezone.utc)


class P9UpdateInstallTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="p9-update-test-")
        self.root = Path(self.temp.name)
        self.project = self.root / "project"
        (self.project / "config").mkdir(parents=True)
        config_path = self.project / "config" / "release_targets.v1.json"
        shutil.copyfile(TOOL.parent / "config" / "release_targets.v1.json", config_path)
        config = json.loads(config_path.read_text(encoding="utf-8"))
        config["productVersion"] = "1.9.1+191"
        config_path.write_text(json.dumps(config), encoding="utf-8")
        (self.project / "pubspec.lock").write_text(LOCK, encoding="utf-8")
        self.artifact_tree = self.root / "artifact"
        self.artifact_tree.mkdir()
        (self.artifact_tree / "app.bin").write_bytes(b"new-version")
        created = create_release_bundle(
            project=self.project,
            artifact=self.artifact_tree,
            platform="linux",
            output=self.root / "release.zip",
            source_commit="b" * 40,
        )
        self.bundle = Path(created["bundle"])
        self.trust = self.root / "trust.json"
        self.trust.write_text(json.dumps({
            "keys": [{
                "keyId": "release-test",
                "publicKeyHex": public_key(SEED).hex(),
                "intendedUses": [updater.UPDATE_USE],
                "trustDomains": [updater.UPDATE_DOMAIN],
                "revoked": False,
            }]
        }), encoding="utf-8")
        self.envelope = self._envelope(self.bundle)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _envelope(self, artifact: Path, **payload_changes):
        payload = {
            "version": "1.9.1+191",
            "platform": "linux",
            "channel": "stable",
            "artifactSha256": sha256_file(artifact),
            "artifactSize": artifact.stat().st_size,
        }
        payload.update(payload_changes)
        return sign_manifest({
            "schemaVersion": "2.0.0",
            "keyId": "release-test",
            "intendedUse": updater.UPDATE_USE,
            "trustDomain": updater.UPDATE_DOMAIN,
            "issuedAt": (NOW - timedelta(minutes=1)).isoformat(),
            "expiresAt": (NOW + timedelta(hours=1)).isoformat(),
            "payload": payload,
        }, seed=SEED)

    def _verify(self, envelope=None, artifact=None):
        return verify_update(
            envelope=envelope or self.envelope,
            trust_store=self.trust,
            artifact=artifact or self.bundle,
            platform="linux",
            current_version="1.9.0+190",
            now=NOW,
        )

    def test_signed_update_verification_and_transactional_rollback(self) -> None:
        verified = self._verify()
        install_root = self.root / "installed"
        install_root.mkdir()
        (install_root / "old.txt").write_text("old-version", encoding="utf-8")
        installed = install_verified_update(bundle=self.bundle, install_root=install_root, verified_payload=verified)
        self.assertEqual(installed["resultState"], "PASS")
        self.assertTrue(installed["rollbackAvailable"])
        self.assertEqual((install_root / "payload" / "app.bin").read_bytes(), b"new-version")
        restored = rollback(install_root)
        self.assertEqual(restored["resultState"], "PASS")
        self.assertEqual((install_root / "old.txt").read_text(), "old-version")

    def test_accept_discards_verified_rollback_only_and_blocks_replay(self) -> None:
        verified = self._verify()
        install_root = self.root / "accepted-install"
        install_root.mkdir()
        (install_root / "old.txt").write_text("old-version", encoding="utf-8")
        installed = install_verified_update(bundle=self.bundle, install_root=install_root, verified_payload=verified)
        self.assertTrue(installed["rollbackAvailable"])
        with self.assertRaises(UpdateInstallError) as caught:
            install_verified_update(bundle=self.bundle, install_root=install_root, verified_payload=verified)
        self.assertEqual(caught.exception.code, "rollback_pending")

        accepted = accept_update(install_root)
        self.assertTrue(accepted["accepted"])
        self.assertTrue(accepted["rollbackDiscarded"])
        self.assertFalse(updater._backup_path(install_root).exists())

        with self.assertRaises(UpdateInstallError) as caught:
            install_verified_update(bundle=self.bundle, install_root=install_root, verified_payload=verified)
        self.assertEqual(caught.exception.code, "current_version_mismatch")

    def test_accept_refuses_tampered_current_install(self) -> None:
        verified = self._verify()
        install_root = self.root / "tampered-accept"
        install_root.mkdir()
        (install_root / "old.txt").write_text("old-version", encoding="utf-8")
        install_verified_update(bundle=self.bundle, install_root=install_root, verified_payload=verified)
        (install_root / "payload" / "app.bin").write_bytes(b"tampered")
        with self.assertRaises(UpdateInstallError) as caught:
            accept_update(install_root)
        self.assertEqual(caught.exception.code, "installed_file_digest")
        self.assertTrue(updater._backup_path(install_root).exists())

    def test_bad_signature_platform_and_artifact_digest_fail_closed(self) -> None:
        bad_signature = dict(self.envelope)
        bad_signature["signature"] = "00" * 64
        with self.assertRaises(UpdateInstallError) as caught:
            self._verify(bad_signature)
        self.assertEqual(caught.exception.code, "manifest_signature_invalid")

        wrong_platform = self._envelope(self.bundle, platform="windows")
        with self.assertRaises(UpdateInstallError) as caught:
            self._verify(wrong_platform)
        self.assertEqual(caught.exception.code, "platform_mismatch")

        modified = self.root / "modified.zip"
        modified.write_bytes(self.bundle.read_bytes() + b"tamper")
        with self.assertRaises(UpdateInstallError) as caught:
            self._verify(self.envelope, modified)
        self.assertIn(caught.exception.code, {"artifact_size", "artifact_digest"})

    def test_expired_and_revoked_metadata_fail_closed(self) -> None:
        with self.assertRaises(UpdateInstallError) as caught:
            verify_update(
                envelope=self.envelope,
                trust_store=self.trust,
                artifact=self.bundle,
                platform="linux",
                current_version="1.9.0+190",
                now=NOW + timedelta(days=2),
            )
        self.assertEqual(caught.exception.code, "manifest_manifest_expired")
        trust = json.loads(self.trust.read_text())
        trust["keys"][0]["revoked"] = True
        self.trust.write_text(json.dumps(trust), encoding="utf-8")
        with self.assertRaises(UpdateInstallError) as caught:
            self._verify()
        self.assertEqual(caught.exception.code, "manifest_key_revoked")

    def test_failed_activation_verification_restores_previous_install(self) -> None:
        bad_bundle = self.root / "bad-release.zip"
        manifest = {
            "schemaVersion": 1,
            "version": "1.9.1+191",
            "platform": "linux",
            "files": [{"path": "app.bin", "bytes": 3, "sha256": "0" * 64}],
        }
        with zipfile.ZipFile(bad_bundle, "w") as archive:
            archive.writestr("payload/app.bin", b"bad")
            archive.writestr(updater.RELEASE_MANIFEST, json.dumps(manifest))
            archive.writestr("KRISTIN_SBOM.spdx.json", json.dumps({"spdxVersion": "SPDX-2.3", "packages": [{"name": "fixture"}]}))
        verified = self._verify(self._envelope(bad_bundle), bad_bundle)
        install_root = self.root / "installed-failure"
        install_root.mkdir()
        (install_root / "old.txt").write_text("survives", encoding="utf-8")
        with self.assertRaises(UpdateInstallError) as caught:
            install_verified_update(bundle=bad_bundle, install_root=install_root, verified_payload=verified)
        self.assertEqual(caught.exception.code, "installed_file_digest")
        self.assertEqual((install_root / "old.txt").read_text(), "survives")
        self.assertFalse(updater._journal_path(install_root).exists())

    def test_interrupted_recovery_restores_previous_and_rejects_unsafe_journal(self) -> None:
        install_root = self.root / "recover-install"
        install_root.mkdir()
        (install_root / "broken.txt").write_text("broken")
        previous = updater._backup_path(install_root)
        previous.mkdir()
        (previous / "old.txt").write_text("old")
        stage = self.root / f".{install_root.name}.stage-fixture"
        stage.mkdir()
        updater._write_atomic(updater._journal_path(install_root), {
            "schemaVersion": 1,
            "installRoot": str(install_root),
            "stage": str(stage),
            "previous": str(previous),
            "version": "1.9.1+191",
            "platform": "linux",
            "hadPrevious": True,
            "phase": "ACTIVATED",
        })
        result = recover_interrupted(install_root)
        self.assertEqual(result["recovery"], "RESTORED_PREVIOUS")
        self.assertEqual((install_root / "old.txt").read_text(), "old")
        self.assertFalse(stage.exists())

        unsafe = self.root / "unrelated-directory"
        unsafe.mkdir()
        updater._write_atomic(updater._journal_path(install_root), {
            "schemaVersion": 1,
            "installRoot": str(install_root),
            "stage": str(unsafe),
            "previous": str(updater._backup_path(install_root)),
            "version": "1.9.1+191",
            "platform": "linux",
            "hadPrevious": False,
            "phase": "PREPARING",
        })
        with self.assertRaises(UpdateInstallError) as caught:
            recover_interrupted(install_root)
        self.assertEqual(caught.exception.code, "journal_unsafe")
        self.assertTrue(unsafe.exists())

    def test_failed_fresh_install_removes_unverified_activation(self) -> None:
        bad_bundle = self.root / "bad-fresh.zip"
        manifest = {
            "schemaVersion": 1,
            "version": "1.9.1+191",
            "platform": "linux",
            "files": [{"path": "app.bin", "type": "file", "mode": 384, "bytes": 3, "sha256": "0" * 64}],
        }
        with zipfile.ZipFile(bad_bundle, "w") as archive:
            archive.writestr("payload/app.bin", b"bad")
            archive.writestr(updater.RELEASE_MANIFEST, json.dumps(manifest))
            archive.writestr("KRISTIN_SBOM.spdx.json", json.dumps({"spdxVersion": "SPDX-2.3", "packages": [{"name": "fixture"}]}))
        verified = self._verify(self._envelope(bad_bundle), bad_bundle)
        install_root = self.root / "fresh-failure"
        with self.assertRaises(UpdateInstallError):
            install_verified_update(bundle=bad_bundle, install_root=install_root, verified_payload=verified)
        self.assertFalse(install_root.exists())
        self.assertFalse(updater._journal_path(install_root).exists())

    def test_safe_relative_symlink_round_trips_through_install(self) -> None:
        artifact = self.root / "symlink-artifact"
        artifact.mkdir()
        target = artifact / "target.bin"
        target.write_bytes(b"target")
        link = artifact / "current.bin"
        try:
            link.symlink_to("target.bin")
        except (OSError, NotImplementedError):
            self.skipTest("host does not permit disposable symlink creation")
        created = create_release_bundle(
            project=self.project,
            artifact=artifact,
            platform="linux",
            output=self.root / "symlink-release.zip",
            source_commit="d" * 40,
        )
        bundle = Path(created["bundle"])
        verified = self._verify(self._envelope(bundle), bundle)
        install_root = self.root / "symlink-install"
        install_verified_update(bundle=bundle, install_root=install_root, verified_payload=verified)
        installed_link = install_root / "payload" / "current.bin"
        self.assertTrue(installed_link.is_symlink())
        self.assertEqual(installed_link.read_bytes(), b"target")

    def test_archive_traversal_is_rejected_before_install_mutation(self) -> None:
        evil = self.root / "evil.zip"
        with zipfile.ZipFile(evil, "w") as archive:
            archive.writestr("../escape.txt", b"escape")
            archive.writestr(updater.RELEASE_MANIFEST, json.dumps({"version": "1.9.1+191", "platform": "linux", "files": []}))
        verified = self._verify(self._envelope(evil), evil)
        install_root = self.root / "safe-install"
        install_root.mkdir()
        (install_root / "old.txt").write_text("old")
        with self.assertRaises(UpdateInstallError) as caught:
            install_verified_update(bundle=evil, install_root=install_root, verified_payload=verified)
        self.assertEqual(caught.exception.code, "archive_path")
        self.assertEqual((install_root / "old.txt").read_text(), "old")
        self.assertFalse((self.root / "escape.txt").exists())


if __name__ == "__main__":
    unittest.main()
