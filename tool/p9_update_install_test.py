#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import shutil
import stat
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
            "compatibleFrom": ["1.9.0+190"],
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

    def _write_managed_install(
        self,
        root: Path,
        *,
        version: str,
        content: bytes = b"old-version",
        file_name: str = "app.bin",
    ) -> None:
        payload = root / "payload"
        payload.mkdir(parents=True)
        target = payload / file_name
        target.write_bytes(content)
        if os.name != "nt":
            os.chmod(target, 0o644)
        mode = stat.S_IMODE(target.stat().st_mode)
        manifest = {
            "schemaVersion": 1,
            "product": updater.PRODUCT_NAME,
            "version": version,
            "platform": "linux",
            "files": [{
                "path": file_name,
                "type": "file",
                "mode": mode,
                "bytes": len(content),
                "sha256": updater._sha256_file(target),
            }],
        }
        (root / updater.RELEASE_MANIFEST).write_text(json.dumps(manifest), encoding="utf-8")

    def test_signed_update_verification_and_transactional_rollback(self) -> None:
        verified = self._verify()
        install_root = self.root / "installed"
        self._write_managed_install(install_root, version="1.9.0+190")
        installed = install_verified_update(bundle=self.bundle, install_root=install_root, verified_payload=verified)
        self.assertEqual(installed["resultState"], "PASS")
        self.assertTrue(installed["rollbackAvailable"])
        self.assertEqual((install_root / "payload" / "app.bin").read_bytes(), b"new-version")
        restored = rollback(install_root)
        self.assertEqual(restored["resultState"], "PASS")
        self.assertEqual((install_root / "payload" / "app.bin").read_bytes(), b"old-version")

    def test_accept_discards_verified_rollback_only_and_blocks_replay(self) -> None:
        verified = self._verify()
        install_root = self.root / "accepted-install"
        self._write_managed_install(install_root, version="1.9.0+190")
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
        self._write_managed_install(install_root, version="1.9.0+190")
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

    def test_update_metadata_must_explicitly_allow_installed_version(self) -> None:
        incompatible = self._envelope(self.bundle, compatibleFrom=["1.8.0+180"])
        with self.assertRaises(UpdateInstallError) as caught:
            self._verify(incompatible)
        self.assertEqual(caught.exception.code, "update_incompatible")

        malformed = self._envelope(self.bundle, compatibleFrom=["1.9.0+190", "1.9.0+190"])
        with self.assertRaises(UpdateInstallError) as caught:
            self._verify(malformed)
        self.assertEqual(caught.exception.code, "compatibility_invalid")

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
            "product": updater.PRODUCT_NAME,
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
        self._write_managed_install(install_root, version="1.9.0+190", content=b"survives")
        with self.assertRaises(UpdateInstallError) as caught:
            install_verified_update(bundle=bad_bundle, install_root=install_root, verified_payload=verified)
        self.assertEqual(caught.exception.code, "installed_file_digest")
        self.assertEqual((install_root / "payload" / "app.bin").read_bytes(), b"survives")
        self.assertFalse(updater._journal_path(install_root).exists())

    def test_interrupted_recovery_restores_previous_and_rejects_unsafe_journal(self) -> None:
        install_root = self.root / "recover-install"
        self._write_managed_install(install_root, version="1.9.1+191", content=b"broken-new")
        previous = updater._backup_path(install_root)
        self._write_managed_install(previous, version="1.9.0+190", content=b"old")
        transaction_id = "a" * 32
        stage = self.root / f".{install_root.name}.stage-{transaction_id}"
        stage.mkdir()
        updater._write_atomic(updater._journal_path(install_root), {
            "schemaVersion": 1,
            "transactionId": transaction_id,
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
        self.assertEqual((install_root / "payload" / "app.bin").read_bytes(), b"old")
        self.assertFalse(stage.exists())

        unsafe = self.root / "unrelated-directory"
        unsafe.mkdir()
        updater._write_atomic(updater._journal_path(install_root), {
            "schemaVersion": 1,
            "transactionId": "b" * 32,
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
            "product": updater.PRODUCT_NAME,
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
            archive.writestr(updater.RELEASE_MANIFEST, json.dumps({
                "schemaVersion": 1,
                "product": updater.PRODUCT_NAME,
                "version": "1.9.1+191",
                "platform": "linux",
                "files": [],
            }))
        verified = self._verify(self._envelope(evil), evil)
        install_root = self.root / "safe-install"
        self._write_managed_install(install_root, version="1.9.0+190")
        with self.assertRaises(UpdateInstallError) as caught:
            install_verified_update(bundle=evil, install_root=install_root, verified_payload=verified)
        self.assertEqual(caught.exception.code, "archive_path")
        self.assertEqual((install_root / "payload" / "app.bin").read_bytes(), b"old-version")
        self.assertFalse((self.root / "escape.txt").exists())

    def test_existing_unmanaged_directory_is_never_adopted_or_uninstalled(self) -> None:
        verified = self._verify()
        install_root = self.root / "unmanaged"
        install_root.mkdir()
        sentinel = install_root / "sentinel.txt"
        sentinel.write_text("keep", encoding="utf-8")
        with self.assertRaises(UpdateInstallError) as caught:
            install_verified_update(bundle=self.bundle, install_root=install_root, verified_payload=verified)
        self.assertEqual(caught.exception.code, "install_root_unmanaged")
        self.assertTrue(sentinel.exists())
        self.assertFalse(updater._journal_path(install_root).exists())

        with self.assertRaises(UpdateInstallError) as caught:
            updater.uninstall(install_root)
        self.assertEqual(caught.exception.code, "install_root_unmanaged")
        self.assertEqual(sentinel.read_text(encoding="utf-8"), "keep")

    def test_unmanaged_rollback_backup_is_never_deleted_or_restored(self) -> None:
        verified = self._verify()
        install_root = self.root / "managed-with-foreign-backup"
        install_verified_update(bundle=self.bundle, install_root=install_root, verified_payload=verified)
        previous = updater._backup_path(install_root)
        previous.mkdir()
        sentinel = previous / "sentinel.txt"
        sentinel.write_text("foreign", encoding="utf-8")

        for operation in (accept_update, rollback, updater.uninstall):
            with self.subTest(operation=operation.__name__):
                with self.assertRaises(UpdateInstallError) as caught:
                    operation(install_root)
                self.assertEqual(caught.exception.code, "rollback_backup_unmanaged")
                self.assertTrue(install_root.exists())
                self.assertEqual(sentinel.read_text(encoding="utf-8"), "foreign")

    def test_verified_fresh_install_can_be_uninstalled(self) -> None:
        verified = self._verify()
        install_root = self.root / "verified-uninstall"
        install_verified_update(bundle=self.bundle, install_root=install_root, verified_payload=verified)
        result = updater.uninstall(install_root)
        self.assertTrue(result["uninstalled"])
        self.assertFalse(install_root.exists())


if __name__ == "__main__":
    unittest.main()
