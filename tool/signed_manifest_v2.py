#!/usr/bin/env python3
from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Mapping

from ed25519_ref import public_key, sign, verify


class ManifestVerificationError(ValueError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def canonical_json(value: Any) -> str:
    def normalize(item: Any) -> Any:
        if item is None or isinstance(item, (str, bool, int)):
            return item
        if isinstance(item, float):
            raise ManifestVerificationError(
                "non_canonical_number",
                "Signed Manifest v2 forbids floating-point values in the signed subset.",
            )
        if isinstance(item, list):
            return [normalize(child) for child in item]
        if isinstance(item, dict):
            if not all(isinstance(key, str) for key in item):
                raise ManifestVerificationError("non_string_key", "Object keys must be strings.")
            return {key: normalize(item[key]) for key in sorted(item)}
        raise ManifestVerificationError(
            "unsupported_type", f"Unsupported canonical JSON type: {type(item).__name__}"
        )

    return json.dumps(
        normalize(value),
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    )


@dataclass(frozen=True)
class TrustKey:
    key_id: str
    public_key: bytes
    intended_uses: frozenset[str]
    trust_domains: frozenset[str]
    revoked: bool = False


class ExternalKeyring:
    def __init__(self, keys: Mapping[str, TrustKey]) -> None:
        self._keys = dict(keys)

    def resolve(self, key_id: str) -> TrustKey:
        key = self._keys.get(key_id)
        if key is None:
            raise ManifestVerificationError("unknown_key", f"Unknown key id: {key_id}")
        if key.revoked:
            raise ManifestVerificationError("key_revoked", f"Key is revoked: {key_id}")
        return key


def signing_body(envelope: Mapping[str, Any]) -> dict[str, Any]:
    body = dict(envelope)
    body.pop("signature", None)
    return body


def sign_manifest(
    body: Mapping[str, Any],
    *,
    seed: bytes,
) -> dict[str, Any]:
    required = {
        "schemaVersion",
        "keyId",
        "intendedUse",
        "trustDomain",
        "issuedAt",
        "expiresAt",
        "payload",
    }
    missing = sorted(required - set(body))
    if missing:
        raise ManifestVerificationError("missing_field", f"Missing fields: {missing}")
    if body.get("schemaVersion") != "2.0.0":
        raise ManifestVerificationError("unsupported_version", "Only schemaVersion 2.0.0 is accepted.")
    message = canonical_json(dict(body)).encode("utf-8")
    envelope = dict(body)
    envelope["signature"] = sign(seed, message).hex()
    return envelope


def verify_manifest(
    envelope: Mapping[str, Any],
    *,
    keyring: ExternalKeyring,
    now: datetime,
    expected_use: str | None = None,
    expected_domain: str | None = None,
) -> dict[str, Any]:
    if envelope.get("schemaVersion") != "2.0.0":
        raise ManifestVerificationError("unsupported_version", "Only Signed Manifest v2 is accepted.")
    signature_hex = envelope.get("signature")
    if not isinstance(signature_hex, str):
        raise ManifestVerificationError("signature_missing", "Signature is required.")
    try:
        signature = bytes.fromhex(signature_hex)
    except ValueError as error:
        raise ManifestVerificationError("signature_malformed", "Signature is not valid hex.") from error
    key_id = str(envelope.get("keyId") or "")
    intended_use = str(envelope.get("intendedUse") or "")
    trust_domain = str(envelope.get("trustDomain") or "")
    key = keyring.resolve(key_id)
    if intended_use not in key.intended_uses:
        raise ManifestVerificationError("intended_use_denied", "Key is not trusted for this intended use.")
    if trust_domain not in key.trust_domains:
        raise ManifestVerificationError("trust_domain_denied", "Key is not trusted for this domain.")
    if expected_use is not None and intended_use != expected_use:
        raise ManifestVerificationError("wrong_intended_use", "Manifest intended use does not match.")
    if expected_domain is not None and trust_domain != expected_domain:
        raise ManifestVerificationError("wrong_trust_domain", "Manifest trust domain does not match.")
    try:
        issued_at = datetime.fromisoformat(str(envelope["issuedAt"]).replace("Z", "+00:00"))
        expires_at = datetime.fromisoformat(str(envelope["expiresAt"]).replace("Z", "+00:00"))
    except (KeyError, ValueError) as error:
        raise ManifestVerificationError("invalid_time", "Manifest timestamps are invalid.") from error
    instant = now.astimezone(timezone.utc)
    if issued_at.astimezone(timezone.utc) > instant:
        raise ManifestVerificationError("not_yet_valid", "Manifest is not yet valid.")
    if expires_at.astimezone(timezone.utc) <= instant:
        raise ManifestVerificationError("manifest_expired", "Manifest has expired.")
    body = signing_body(envelope)
    message = canonical_json(body).encode("utf-8")
    if not verify(key.public_key, message, signature):
        raise ManifestVerificationError("signature_invalid", "Signature verification failed.")
    return body
