#!/usr/bin/env python3
"""Authenticated P9 update verification with transactional install, recovery and rollback."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import shutil
import stat
import sys
import tempfile
import uuid
import zipfile
from typing import Any, Mapping

_TOOL_DIR = str(Path(__file__).resolve().parent)
if _TOOL_DIR not in sys.path:
    sys.path.insert(0, _TOOL_DIR)

from signed_manifest_v2 import ExternalKeyring, ManifestVerificationError, TrustKey, verify_manifest

UPDATE_USE = "kristin.release.update"
UPDATE_DOMAIN = "kristin.release"
SUPPORTED_PLATFORMS = frozenset({"windows", "macos", "linux"})
RELEASE_MANIFEST = "KRISTIN_RELEASE_MANIFEST.json"


class UpdateInstallError(ValueError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def _canonical(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _safe_archive_name(value: str) -> str:
    raw = str(value).replace("\\", "/")
    path = PurePosixPath(raw)
    windows = PureWindowsPath(raw)
    if (
        not raw
        or raw.startswith("/")
        or path.is_absolute()
        or windows.is_absolute()
        or windows.drive
        or ".." in path.parts
        or ".." in windows.parts
        or "\0" in raw
    ):
        raise UpdateInstallError("archive_path", f"unsafe archive path: {value!r}")
    return path.as_posix()


def _parse_version(value: str) -> tuple[int, int, int, int]:
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?", str(value))
    if not match:
        raise UpdateInstallError("version_invalid", f"invalid Kristin version: {value!r}")
    major, minor, patch, build = match.groups()
    return int(major), int(minor), int(patch), int(build or 0)


def load_trust_store(path: Path) -> ExternalKeyring:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise UpdateInstallError("trust_store_invalid", f"cannot load trust store: {exc}") from exc
    rows = data.get("keys") if isinstance(data, dict) else None
    if not isinstance(rows, list) or not rows:
        raise UpdateInstallError("trust_store_invalid", "trust store requires a non-empty keys array")
    keys: dict[str, TrustKey] = {}
    for row in rows:
        if not isinstance(row, dict):
            raise UpdateInstallError("trust_store_invalid", "trust key must be an object")
        key_id = str(row.get("keyId") or "")
        if not key_id or key_id in keys:
            raise UpdateInstallError("trust_store_invalid", "trust key IDs must be unique and non-empty")
        try:
            public = bytes.fromhex(str(row.get("publicKeyHex") or ""))
        except ValueError as exc:
            raise UpdateInstallError("trust_store_invalid", f"invalid public key for {key_id}") from exc
        if len(public) != 32:
            raise UpdateInstallError("trust_store_invalid", f"Ed25519 public key must be 32 bytes: {key_id}")
        keys[key_id] = TrustKey(
            key_id=key_id,
            public_key=public,
            intended_uses=frozenset(str(x) for x in row.get("intendedUses", [])),
            trust_domains=frozenset(str(x) for x in row.get("trustDomains", [])),
            revoked=row.get("revoked") is True,
        )
    return ExternalKeyring(keys)


def verify_update(
    *,
    envelope: Mapping[str, Any],
    trust_store: Path,
    artifact: Path,
    platform: str,
    current_version: str,
    now: datetime,
) -> dict[str, Any]:
    if platform not in SUPPORTED_PLATFORMS:
        raise UpdateInstallError("platform_unsupported", f"unsupported platform: {platform}")
    try:
        body = verify_manifest(
            envelope,
            keyring=load_trust_store(trust_store),
            now=now,
            expected_use=UPDATE_USE,
            expected_domain=UPDATE_DOMAIN,
        )
    except ManifestVerificationError as exc:
        raise UpdateInstallError(f"manifest_{exc.code}", str(exc)) from exc
    payload = body.get("payload")
    if not isinstance(payload, dict):
        raise UpdateInstallError("payload_invalid", "update payload must be an object")
    required = {"version", "platform", "channel", "artifactSha256", "artifactSize"}
    missing = sorted(required - set(payload))
    if missing:
        raise UpdateInstallError("payload_invalid", f"update payload missing fields: {missing}")
    if payload["platform"] != platform:
        raise UpdateInstallError("platform_mismatch", "update metadata targets a different platform")
    if payload["channel"] not in {"stable", "beta", "rc"}:
        raise UpdateInstallError("channel_invalid", "unsupported update channel")
    if _parse_version(str(payload["version"])) <= _parse_version(current_version):
        raise UpdateInstallError("version_not_newer", "normal update must move to a newer version")
    actual_size = artifact.stat().st_size
    if int(payload["artifactSize"]) != actual_size:
        raise UpdateInstallError("artifact_size", "update artifact size does not match signed metadata")
    actual_sha = _sha256_file(artifact)
    if payload["artifactSha256"] != actual_sha:
        raise UpdateInstallError("artifact_digest", "update artifact SHA-256 does not match signed metadata")
    return {**payload, "verified": True, "artifactSha256": actual_sha, "currentVersion": current_version}


def _journal_path(install_root: Path) -> Path:
    return install_root.parent / f".{install_root.name}.update-journal.json"


def _backup_path(install_root: Path) -> Path:
    return install_root.parent / f".{install_root.name}.previous"


def _remove_path(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink(missing_ok=True)
    elif path.exists():
        shutil.rmtree(path)


def _load_installed_manifest(install_root: Path) -> dict[str, Any]:
    path = install_root / RELEASE_MANIFEST
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise UpdateInstallError("installed_manifest", f"installed release manifest is missing or invalid: {exc}") from exc
    if not isinstance(value, dict):
        raise UpdateInstallError("installed_manifest", "installed release manifest must be an object")
    return value


def _write_atomic(path: Path, value: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(_canonical(dict(value)))
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(name, path)
    finally:
        Path(name).unlink(missing_ok=True)


def _symlink_target_is_safe(link_path: Path, raw_target: str, destination: Path) -> bool:
    if not raw_target or "\0" in raw_target:
        return False
    posix = PurePosixPath(raw_target.replace("\\", "/"))
    windows = PureWindowsPath(raw_target)
    if posix.is_absolute() or windows.is_absolute() or windows.drive:
        return False
    try:
        (link_path.parent / raw_target).resolve(strict=False).relative_to(destination.resolve())
    except (OSError, ValueError):
        return False
    return True


def _extract_bundle(bundle: Path, destination: Path, *, expected_version: str, platform: str) -> dict[str, Any]:
    with zipfile.ZipFile(bundle, "r") as archive:
        infos = archive.infolist()
        normalized: list[str] = []
        for info in infos:
            normalized.append(_safe_archive_name(info.filename))
        if len(normalized) != len(set(normalized)):
            raise UpdateInstallError("archive_duplicate", "update archive contains duplicate or normalization-colliding entries")
        try:
            manifest = json.loads(archive.read(RELEASE_MANIFEST))
        except (KeyError, json.JSONDecodeError) as exc:
            raise UpdateInstallError("release_manifest", "release manifest is missing or invalid") from exc
        if not isinstance(manifest, dict):
            raise UpdateInstallError("release_manifest", "release manifest must be an object")
        if manifest.get("version") != expected_version or manifest.get("platform") != platform:
            raise UpdateInstallError("release_manifest", "release manifest version/platform does not match signed metadata")
        rows = manifest.get("files")
        if not isinstance(rows, list) or not rows:
            raise UpdateInstallError("release_manifest", "release manifest contains no payload files")
        row_by_payload: dict[str, Mapping[str, Any]] = {}
        for row in rows:
            if not isinstance(row, dict):
                raise UpdateInstallError("release_manifest", "release manifest file rows must be objects")
            relative = _safe_archive_name(str(row.get("path", "")))
            payload_name = f"payload/{relative}"
            if payload_name in row_by_payload:
                raise UpdateInstallError("release_manifest", f"duplicate manifest path: {relative}")
            row_by_payload[payload_name] = row
        expected = {RELEASE_MANIFEST, "KRISTIN_SBOM.spdx.json", *row_by_payload.keys()}
        if set(normalized) != expected:
            raise UpdateInstallError("archive_layout", "update archive entries do not exactly match the release manifest")

        destination.mkdir(parents=True, exist_ok=False)
        symlinks: list[tuple[zipfile.ZipInfo, str, str]] = []
        for info, safe in zip(infos, normalized):
            target = destination / safe
            try:
                target.parent.resolve().relative_to(destination.resolve())
            except ValueError as exc:
                raise UpdateInstallError("archive_escape", f"archive entry escapes destination: {safe}") from exc
            archived_type = stat.S_IFMT((info.external_attr >> 16) & 0xFFFF)
            if archived_type == stat.S_IFLNK:
                row = row_by_payload.get(safe)
                if row is None or row.get("type") != "symlink":
                    raise UpdateInstallError("archive_symlink", f"untracked symlink entry: {safe}")
                try:
                    raw_target = archive.read(info).decode("utf-8")
                except UnicodeDecodeError as exc:
                    raise UpdateInstallError("archive_symlink", f"symlink target is not UTF-8: {safe}") from exc
                if raw_target != row.get("target") or not _symlink_target_is_safe(target, raw_target, destination):
                    raise UpdateInstallError("archive_symlink", f"unsafe or mismatched symlink target: {safe}")
                symlinks.append((info, safe, raw_target))
                continue
            if safe in row_by_payload and row_by_payload[safe].get("type", "file") != "file":
                raise UpdateInstallError("archive_file_type", f"manifest expects a symlink but archive contains a file: {safe}")
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(info, "r") as src, target.open("wb") as dst:
                shutil.copyfileobj(src, dst, length=1024 * 1024)
            mode = (info.external_attr >> 16) & 0o777
            if mode and os.name != "nt":
                os.chmod(target, mode)

        for info, safe, raw_target in symlinks:
            target = destination / safe
            if os.path.lexists(target):
                raise UpdateInstallError("archive_symlink", f"symlink path collides with an extracted entry: {safe}")
            target.parent.mkdir(parents=True, exist_ok=True)
            try:
                os.symlink(raw_target, target)
            except OSError as exc:
                raise UpdateInstallError("archive_symlink", f"cannot materialize symlink {safe}: {exc}") from exc
        return manifest


def _verify_installed_tree(install_root: Path, manifest: Mapping[str, Any]) -> None:
    rows = manifest.get("files")
    if not isinstance(rows, list) or not rows:
        raise UpdateInstallError("installed_manifest", "installed manifest contains no payload files")
    for row in rows:
        if not isinstance(row, dict):
            raise UpdateInstallError("installed_manifest", "installed manifest file row must be an object")
        relative = _safe_archive_name(str(row.get("path", "")))
        path = install_root / "payload" / relative
        entry_type = row.get("type", "file")
        if entry_type == "symlink":
            if not path.is_symlink():
                raise UpdateInstallError("installed_file_type", f"installed payload is not a symlink: {relative}")
            target = os.readlink(path)
            target_bytes = target.encode("utf-8")
            if target != row.get("target") or len(target_bytes) != row.get("bytes") or hashlib.sha256(target_bytes).hexdigest() != row.get("sha256"):
                raise UpdateInstallError("installed_file_digest", f"installed symlink mismatch: {relative}")
        elif entry_type == "file":
            if path.is_symlink() or not path.is_file():
                raise UpdateInstallError("installed_file_missing", f"installed payload missing: {relative}")
            if path.stat().st_size != row.get("bytes") or _sha256_file(path) != row.get("sha256"):
                raise UpdateInstallError("installed_file_digest", f"installed payload mismatch: {relative}")
            if os.name != "nt" and (stat.S_IMODE(path.stat().st_mode) & 0o777) != (int(row.get("mode", 0)) & 0o777):
                raise UpdateInstallError("installed_file_mode", f"installed payload mode mismatch: {relative}")
        else:
            raise UpdateInstallError("installed_file_type", f"unsupported installed payload type: {entry_type}")


def install_verified_update(
    *,
    bundle: Path,
    install_root: Path,
    verified_payload: Mapping[str, Any],
) -> dict[str, Any]:
    if verified_payload.get("verified") is not True:
        raise UpdateInstallError("update_unverified", "transactional install requires verified update metadata")
    if _sha256_file(bundle) != verified_payload.get("artifactSha256"):
        raise UpdateInstallError("artifact_digest", "bundle changed after metadata verification")
    parent = install_root.parent
    parent.mkdir(parents=True, exist_ok=True)
    journal = _journal_path(install_root)
    if journal.exists():
        raise UpdateInstallError("recovery_required", "an update journal already exists; recover before installing")
    previous = _backup_path(install_root)
    if previous.exists():
        raise UpdateInstallError("rollback_pending", "previous-version backup already exists; accept or roll back before updating again")
    if install_root.exists() and (install_root / RELEASE_MANIFEST).is_file():
        current_manifest = _load_installed_manifest(install_root)
        _verify_installed_tree(install_root, current_manifest)
        installed_version = str(current_manifest.get("version") or "")
        if verified_payload.get("currentVersion") != installed_version:
            raise UpdateInstallError(
                "current_version_mismatch",
                "verified update metadata was evaluated against a different installed version",
            )
        if _parse_version(str(verified_payload.get("version") or "")) <= _parse_version(installed_version):
            raise UpdateInstallError("version_not_newer", "normal update must move to a newer installed version")
    transaction_id = uuid.uuid4().hex
    stage = parent / f".{install_root.name}.stage-{transaction_id}"
    had_previous = install_root.exists()
    state = {
        "schemaVersion": 1,
        "transactionId": transaction_id,
        "installRoot": str(install_root),
        "stage": str(stage),
        "previous": str(previous),
        "version": verified_payload["version"],
        "platform": verified_payload["platform"],
        "artifactSha256": verified_payload["artifactSha256"],
        "hadPrevious": had_previous,
        "phase": "PREPARING",
    }
    _write_atomic(journal, state)
    manifest: dict[str, Any] | None = None
    try:
        manifest = _extract_bundle(
            bundle,
            stage,
            expected_version=str(verified_payload["version"]),
            platform=str(verified_payload["platform"]),
        )
        state["phase"] = "STAGED"
        _write_atomic(journal, state)
        if had_previous:
            os.replace(install_root, previous)
            state["phase"] = "BACKED_UP"
            _write_atomic(journal, state)
        os.replace(stage, install_root)
        state["phase"] = "ACTIVATED"
        _write_atomic(journal, state)
        _verify_installed_tree(install_root, manifest)
        state["phase"] = "COMMITTED"
        _write_atomic(journal, state)
        journal.unlink()
        return {
            "schemaVersion": 1,
            "resultState": "PASS",
            "transactionId": transaction_id,
            "version": verified_payload["version"],
            "rollbackAvailable": previous.exists(),
            "installRoot": str(install_root),
        }
    except Exception:
        _remove_path(stage)
        if previous.exists():
            _remove_path(install_root)
            os.replace(previous, install_root)
        elif not had_previous and state.get("phase") in {"ACTIVATED", "COMMITTED"}:
            _remove_path(install_root)
        journal.unlink(missing_ok=True)
        raise


def accept_update(install_root: Path) -> dict[str, Any]:
    if _journal_path(install_root).exists():
        raise UpdateInstallError("recovery_required", "recover interrupted update before accepting it")
    if not install_root.exists():
        raise UpdateInstallError("install_missing", "cannot accept an update because the current installation is missing")
    manifest = _load_installed_manifest(install_root)
    _verify_installed_tree(install_root, manifest)
    previous = _backup_path(install_root)
    rollback_was_available = previous.exists()
    if rollback_was_available:
        _remove_path(previous)
    return {
        "schemaVersion": 1,
        "resultState": "PASS",
        "accepted": True,
        "version": manifest.get("version"),
        "rollbackDiscarded": rollback_was_available,
        "installRoot": str(install_root),
    }


def rollback(install_root: Path) -> dict[str, Any]:
    previous = _backup_path(install_root)
    if not previous.exists():
        raise UpdateInstallError("rollback_unavailable", "no previous installation is available")
    failed = install_root.parent / f".{install_root.name}.failed-{uuid.uuid4().hex}"
    if install_root.exists():
        os.replace(install_root, failed)
    try:
        os.replace(previous, install_root)
    except Exception:
        if failed.exists() and not install_root.exists():
            os.replace(failed, install_root)
        raise
    if failed.exists():
        shutil.rmtree(failed, ignore_errors=True)
    return {"schemaVersion": 1, "resultState": "PASS", "rollbackRestored": True, "installRoot": str(install_root)}


def recover_interrupted(install_root: Path) -> dict[str, Any]:
    journal = _journal_path(install_root)
    if not journal.exists():
        return {"schemaVersion": 1, "resultState": "PASS", "recovery": "NOT_REQUIRED"}
    try:
        state = json.loads(journal.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise UpdateInstallError("journal_corrupt", f"cannot recover corrupt update journal: {exc}") from exc
    if not isinstance(state, dict) or state.get("schemaVersion") != 1:
        raise UpdateInstallError("journal_corrupt", "update journal schema is invalid")
    if Path(str(state.get("installRoot") or "")).resolve() != install_root.resolve():
        raise UpdateInstallError("journal_unsafe", "journal install root does not match the requested installation")
    stage = Path(str(state.get("stage") or ""))
    previous = Path(str(state.get("previous") or ""))
    expected_parent = install_root.parent.resolve()
    expected_previous = _backup_path(install_root).resolve()
    stage_resolved = stage.resolve()
    previous_resolved = previous.resolve()
    if stage_resolved.parent != expected_parent or not stage.name.startswith(f".{install_root.name}.stage-"):
        raise UpdateInstallError("journal_unsafe", "journal stage path is outside the update transaction namespace")
    if previous_resolved != expected_previous:
        raise UpdateInstallError("journal_unsafe", "journal backup path is not the canonical rollback path")
    phase = state.get("phase")
    if phase not in {"PREPARING", "STAGED", "BACKED_UP", "ACTIVATED", "COMMITTED"}:
        raise UpdateInstallError("journal_corrupt", f"unknown update phase: {phase!r}")
    had_previous = state.get("hadPrevious") is True

    if phase == "COMMITTED":
        try:
            manifest = _load_installed_manifest(install_root)
            if manifest.get("version") != state.get("version") or manifest.get("platform") != state.get("platform"):
                raise UpdateInstallError("installed_manifest", "committed install metadata does not match the transaction journal")
            _verify_installed_tree(install_root, manifest)
        except Exception:
            if previous.exists():
                _remove_path(install_root)
                os.replace(previous, install_root)
            elif not had_previous:
                _remove_path(install_root)
            raise
        journal.unlink(missing_ok=True)
        return {"schemaVersion": 1, "resultState": "PASS", "recovery": "COMMIT_FINALIZED"}

    _remove_path(stage)
    if phase in {"BACKED_UP", "ACTIVATED"}:
        if had_previous:
            if not previous.exists():
                raise UpdateInstallError("recovery_incomplete", "previous installation is missing; automatic recovery cannot continue")
            _remove_path(install_root)
            os.replace(previous, install_root)
            recovery = "RESTORED_PREVIOUS"
        else:
            if phase == "ACTIVATED":
                _remove_path(install_root)
            recovery = "RESTORED_NOT_INSTALLED"
    else:
        recovery = "CLEANED_STAGE"
    journal.unlink(missing_ok=True)
    return {"schemaVersion": 1, "resultState": "PASS", "recovery": recovery}


def uninstall(install_root: Path) -> dict[str, Any]:
    if _journal_path(install_root).exists():
        raise UpdateInstallError("recovery_required", "recover interrupted update before uninstall")
    if not install_root.exists():
        return {"schemaVersion": 1, "resultState": "PASS", "uninstalled": False, "reason": "NOT_INSTALLED"}
    quarantine = install_root.parent / f".{install_root.name}.uninstall-{uuid.uuid4().hex}"
    os.replace(install_root, quarantine)
    try:
        shutil.rmtree(quarantine)
    except Exception:
        if not install_root.exists() and quarantine.exists():
            os.replace(quarantine, install_root)
        raise
    previous = _backup_path(install_root)
    if previous.exists():
        shutil.rmtree(previous)
    return {"schemaVersion": 1, "resultState": "PASS", "uninstalled": True}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    verify = sub.add_parser("verify-update")
    verify.add_argument("--envelope", required=True)
    verify.add_argument("--trust-store", required=True)
    verify.add_argument("--artifact", required=True)
    verify.add_argument("--platform", choices=sorted(SUPPORTED_PLATFORMS), required=True)
    verify.add_argument("--current-version", required=True)
    install = sub.add_parser("install")
    install.add_argument("--envelope", required=True)
    install.add_argument("--trust-store", required=True)
    install.add_argument("--artifact", required=True)
    install.add_argument("--platform", choices=sorted(SUPPORTED_PLATFORMS), required=True)
    install.add_argument("--current-version", required=True)
    install.add_argument("--install-root", required=True)
    recover = sub.add_parser("recover")
    recover.add_argument("--install-root", required=True)
    rb = sub.add_parser("rollback")
    rb.add_argument("--install-root", required=True)
    accept = sub.add_parser("accept")
    accept.add_argument("--install-root", required=True)
    un = sub.add_parser("uninstall")
    un.add_argument("--install-root", required=True)
    args = parser.parse_args()
    try:
        if args.command == "verify-update":
            envelope = json.loads(Path(args.envelope).read_text(encoding="utf-8"))
            result = verify_update(
                envelope=envelope,
                trust_store=Path(args.trust_store),
                artifact=Path(args.artifact),
                platform=args.platform,
                current_version=args.current_version,
                now=datetime.now(timezone.utc),
            )
        elif args.command == "install":
            envelope = json.loads(Path(args.envelope).read_text(encoding="utf-8"))
            artifact = Path(args.artifact)
            verified = verify_update(
                envelope=envelope,
                trust_store=Path(args.trust_store),
                artifact=artifact,
                platform=args.platform,
                current_version=args.current_version,
                now=datetime.now(timezone.utc),
            )
            result = install_verified_update(
                bundle=artifact,
                install_root=Path(args.install_root),
                verified_payload=verified,
            )
        elif args.command == "recover":
            result = recover_interrupted(Path(args.install_root))
        elif args.command == "rollback":
            result = rollback(Path(args.install_root))
        elif args.command == "accept":
            result = accept_update(Path(args.install_root))
        else:
            result = uninstall(Path(args.install_root))
        print(json.dumps(result, sort_keys=True))
        return 0
    except (OSError, zipfile.BadZipFile, json.JSONDecodeError, UpdateInstallError) as exc:
        code = exc.code if isinstance(exc, UpdateInstallError) else "io_error"
        print(json.dumps({"resultState": "FAIL", "code": code, "error": str(exc)}, sort_keys=True))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
