#!/usr/bin/env python3
from __future__ import annotations

from dataclasses import asdict, dataclass, replace
from typing import Iterable


class KeyRegistryError(ValueError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class ProtectedKeyHandle:
    key_id: str
    purpose: str
    provider: str
    reference: str
    public_key_hex: str
    trust_domain: str
    status: str = "active"

    def to_json(self) -> dict[str, str]:
        value = asdict(self)
        forbidden = {"private_key", "seed", "secret", "key_material", "raw_secret"}
        if forbidden.intersection(value):
            raise KeyRegistryError("secret_serialization", "Private key material cannot be serialized.")
        return {
            "keyId": self.key_id,
            "purpose": self.purpose,
            "provider": self.provider,
            "reference": self.reference,
            "publicKeyHex": self.public_key_hex,
            "trustDomain": self.trust_domain,
            "status": self.status,
        }


class ProtectedKeyRegistry:
    def __init__(self, handles: Iterable[ProtectedKeyHandle] = ()) -> None:
        self._handles = {handle.key_id: handle for handle in handles}

    def register(self, handle: ProtectedKeyHandle) -> None:
        if handle.key_id in self._handles:
            raise KeyRegistryError("duplicate_key_id", f"Duplicate key id: {handle.key_id}")
        if handle.provider not in {
            "windows_credential_manager",
            "macos_keychain",
            "linux_secret_service",
            "external_hsm",
            "ephemeral_test",
        }:
            raise KeyRegistryError("unsupported_provider", f"Unsupported provider: {handle.provider}")
        if not handle.reference or any(
            marker in handle.reference.lower()
            for marker in ("privatekey=", "seed=", "secret=", "keymaterial=")
        ):
            raise KeyRegistryError("invalid_reference", "Key reference must be opaque and secret-free.")
        self._handles[handle.key_id] = handle

    def resolve(self, key_id: str, *, purpose: str, trust_domain: str) -> ProtectedKeyHandle:
        handle = self._handles.get(key_id)
        if handle is None:
            raise KeyRegistryError("unknown_key", f"Unknown key id: {key_id}")
        if handle.status != "active":
            raise KeyRegistryError("key_revoked", f"Key is not active: {key_id}")
        if handle.purpose != purpose:
            raise KeyRegistryError("wrong_key_purpose", "Key purpose does not match.")
        if handle.trust_domain != trust_domain:
            raise KeyRegistryError("wrong_trust_domain", "Trust domain does not match.")
        return handle

    def revoke(self, key_id: str) -> ProtectedKeyHandle:
        handle = self._handles.get(key_id)
        if handle is None:
            raise KeyRegistryError("unknown_key", f"Unknown key id: {key_id}")
        revoked = replace(handle, status="revoked")
        self._handles[key_id] = revoked
        return revoked

    def export_public_registry(self) -> list[dict[str, str]]:
        return [self._handles[key].to_json() for key in sorted(self._handles)]
