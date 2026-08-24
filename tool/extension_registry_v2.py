#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
from typing import Any, Mapping

from signed_manifest_v2 import ExternalKeyring, canonical_json, verify_manifest


@dataclass(frozen=True)
class ExtensionManifestV2:
    extension_type: str
    identifier: str
    publisher: str
    version: str
    code_sha256: str
    requested_capabilities: tuple[str, ...]
    compatibility: tuple[str, ...]
    entry_point: str
    tests_sha256: str

    @classmethod
    def from_payload(cls, payload: Mapping[str, Any]) -> "ExtensionManifestV2":
        if payload.get("schemaVersion") != "2.0.0":
            raise ValueError("extension_manifest_version_invalid")
        extension_type = str(payload.get("extensionType") or "")
        if extension_type not in {"plugin", "skill"}:
            raise ValueError("extension_manifest_type_invalid")
        identifier = str(payload.get("id") or "").strip()
        publisher = str(payload.get("publisher") or "").strip()
        version = str(payload.get("version") or "").strip()
        entry_point = str(payload.get("entryPoint") or "").strip()
        code_sha256 = _digest_field(payload.get("codeSha256"), "extension_code_digest_invalid")
        tests_sha256 = _digest_field(payload.get("testsSha256"), "extension_tests_digest_invalid")
        capabilities = tuple(
            sorted(
                {
                    str(value)
                    for value in payload.get("requestedCapabilities") or []
                    if str(value).strip()
                }
            )
        )
        compatibility = tuple(
            str(value) for value in payload.get("compatibility") or [] if str(value).strip()
        )
        if not identifier or not publisher or not version or not entry_point:
            raise ValueError("extension_manifest_identity_incomplete")
        _version_tuple(version)
        if not compatibility:
            raise ValueError("extension_manifest_compatibility_missing")
        return cls(
            extension_type=extension_type,
            identifier=identifier,
            publisher=publisher,
            version=version,
            code_sha256=code_sha256,
            requested_capabilities=capabilities,
            compatibility=compatibility,
            entry_point=entry_point,
            tests_sha256=tests_sha256,
        )

    @property
    def identity(self) -> str:
        return f"{self.publisher}/{self.identifier}"


@dataclass
class InstalledExtension:
    manifest: ExtensionManifestV2
    manifest_sha256: str
    enabled: bool = False
    revoked: bool = False
    capability_review_required: bool = False

    def to_json(self) -> dict[str, Any]:
        return {
            "identity": self.manifest.identity,
            "type": self.manifest.extension_type,
            "version": self.manifest.version,
            "publisher": self.manifest.publisher,
            "codeSha256": self.manifest.code_sha256,
            "requestedCapabilities": list(self.manifest.requested_capabilities),
            "compatibility": list(self.manifest.compatibility),
            "entryPoint": self.manifest.entry_point,
            "testsSha256": self.manifest.tests_sha256,
            "manifestSha256": self.manifest_sha256,
            "enabled": self.enabled,
            "revoked": self.revoked,
            "capabilityReviewRequired": self.capability_review_required,
        }


class ExtensionRegistryV2:
    def __init__(self) -> None:
        self._installed: dict[str, InstalledExtension] = {}

    def _verify_candidate(
        self,
        envelope: Mapping[str, Any],
        *,
        keyring: ExternalKeyring,
        now: datetime,
        actual_code_sha256: str,
        actual_tests_sha256: str,
    ) -> tuple[ExtensionManifestV2, str]:
        body = verify_manifest(
            envelope,
            keyring=keyring,
            now=now,
            expected_use="kristin_extension",
            expected_domain="kristin.extensions",
        )
        payload = body.get("payload")
        if not isinstance(payload, dict):
            raise ValueError("extension_manifest_payload_invalid")
        manifest = ExtensionManifestV2.from_payload(payload)
        if manifest.code_sha256 != actual_code_sha256:
            raise ValueError("extension_code_digest_mismatch")
        if manifest.tests_sha256 != actual_tests_sha256:
            raise ValueError("extension_tests_digest_mismatch")
        manifest_sha256 = hashlib.sha256(canonical_json(dict(body)).encode("utf-8")).hexdigest()
        return manifest, manifest_sha256

    def install(
        self,
        envelope: Mapping[str, Any],
        *,
        keyring: ExternalKeyring,
        now: datetime,
        actual_code_sha256: str,
        actual_tests_sha256: str,
    ) -> InstalledExtension:
        manifest, manifest_sha256 = self._verify_candidate(
            envelope,
            keyring=keyring,
            now=now,
            actual_code_sha256=actual_code_sha256,
            actual_tests_sha256=actual_tests_sha256,
        )
        prior = self._installed.get(manifest.identity)
        if prior is not None:
            if prior.revoked:
                raise ValueError("extension_identity_revoked")
            raise ValueError("extension_already_installed")
        installed = InstalledExtension(
            manifest=manifest,
            manifest_sha256=manifest_sha256,
            enabled=False,
            revoked=False,
            capability_review_required=bool(manifest.requested_capabilities),
        )
        self._installed[manifest.identity] = installed
        return installed

    def update(
        self,
        identity: str,
        envelope: Mapping[str, Any],
        *,
        keyring: ExternalKeyring,
        now: datetime,
        actual_code_sha256: str,
        actual_tests_sha256: str,
    ) -> InstalledExtension:
        prior = self._required(identity)
        if prior.revoked:
            raise ValueError("extension_identity_revoked")
        manifest, manifest_sha256 = self._verify_candidate(
            envelope,
            keyring=keyring,
            now=now,
            actual_code_sha256=actual_code_sha256,
            actual_tests_sha256=actual_tests_sha256,
        )
        if manifest.identity != identity:
            raise ValueError("extension_update_identity_mismatch")
        if _version_tuple(manifest.version) <= _version_tuple(prior.manifest.version):
            raise ValueError("extension_update_version_not_newer")
        capabilities_changed = (
            manifest.requested_capabilities != prior.manifest.requested_capabilities
        )
        updated = InstalledExtension(
            manifest=manifest,
            manifest_sha256=manifest_sha256,
            enabled=prior.enabled and not capabilities_changed,
            revoked=False,
            capability_review_required=capabilities_changed,
        )
        self._installed[identity] = updated
        return updated

    def enable(self, identity: str, *, capabilities_approved: bool = False) -> InstalledExtension:
        extension = self._required(identity)
        if extension.revoked:
            raise ValueError("extension_revoked")
        if extension.capability_review_required:
            if not capabilities_approved:
                raise ValueError("extension_capability_review_required")
            extension.capability_review_required = False
        extension.enabled = True
        return extension

    def disable(self, identity: str) -> InstalledExtension:
        extension = self._required(identity)
        extension.enabled = False
        return extension

    def revoke(self, identity: str) -> InstalledExtension:
        extension = self._required(identity)
        extension.enabled = False
        extension.revoked = True
        extension.capability_review_required = False
        return extension

    def inspect(self, identity: str) -> dict[str, Any]:
        return self._required(identity).to_json()

    def inspect_all(self) -> list[dict[str, Any]]:
        return [self._installed[key].to_json() for key in sorted(self._installed)]

    def capabilities(self, identity: str) -> tuple[str, ...]:
        return self._required(identity).manifest.requested_capabilities

    def export(self, path: Path) -> None:
        payload = {
            "schemaVersion": "2.0.0",
            "extensions": self.inspect_all(),
        }
        path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    def _required(self, identity: str) -> InstalledExtension:
        extension = self._installed.get(identity)
        if extension is None:
            raise ValueError("extension_not_installed")
        return extension


def _digest_field(value: Any, code: str) -> str:
    digest = str(value or "").lower()
    if len(digest) != 64 or any(ch not in "0123456789abcdef" for ch in digest):
        raise ValueError(code)
    return digest


def _version_tuple(value: str) -> tuple[int, int, int, str]:
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(?:[-+]([0-9A-Za-z.-]+))?", value)
    if match is None:
        raise ValueError("extension_version_invalid")
    major, minor, patch, suffix = match.groups()
    return int(major), int(minor), int(patch), suffix or ""
