#!/usr/bin/env python3
"""Compatibility types for the disabled v1.9 signed-manifest protocol.

The original v1 verifier authenticated an HMAC with ``signer.publicKey`` from
the untrusted envelope. Because that value was also the HMAC secret, any sender
could choose a secret, sign an arbitrary manifest, place the secret in the
envelope, and pass verification. P0-002 therefore keeps only the legacy data
shapes needed for migration and diagnostics. Every public trust operation fails
closed until Signed Manifest v2 provides an external trust anchor.
"""
from __future__ import annotations

import dataclasses
import datetime as dt
import hashlib
import json
from typing import Any, Mapping, NoReturn

VERSION = '1.9.0+190'
SCHEMA_VERSION = '1.0.0'
SIGNATURE_ALGORITHM = 'hmac-sha256'
LEGACY_TRUST_ENABLED = False
LEGACY_TRUST_ERROR_CODE = 'v1_trust_disabled'
LEGACY_TRUST_REPLACEMENT = 'signed_manifest_v2'
LEGACY_TRUST_REASON = (
    'Legacy v1 signed manifests cannot authorize capabilities, audit '
    'checkpoints, plugins, agents, or updates because the protocol has no '
    'independent trust anchor.'
)


class InteroperabilityError(RuntimeError):
    def __init__(self, code: str, message: str, *, details: dict[str, Any] | None = None) -> None:
        super().__init__(message)
        self.code = code
        self.details = details or {}


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False)


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_json(value: object) -> str:
    return sha256_hex(canonical_json(value).encode('utf-8'))


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


@dataclasses.dataclass(frozen=True)
class SigningKeyPair:
    """Legacy shape retained only so stored v1 records remain readable."""

    key_id: str
    public_key: str
    private_key: str
    algorithm: str = SIGNATURE_ALGORITHM


@dataclasses.dataclass(frozen=True)
class SignedManifestEnvelope:
    """Legacy envelope shape retained for migration and diagnostic display."""

    manifest_type: str
    manifest: dict[str, Any]
    manifest_sha256: str
    signature: str
    signer_key_id: str
    signer_public_key: str
    signed_at: str
    algorithm: str = SIGNATURE_ALGORITHM

    def to_json(self) -> dict[str, Any]:
        return {
            'schemaVersion': SCHEMA_VERSION,
            'manifestType': self.manifest_type,
            'manifest': self.manifest,
            'manifestSha256': self.manifest_sha256,
            'signature': self.signature,
            'signedAt': self.signed_at,
            'signer': {
                'keyId': self.signer_key_id,
                'algorithm': self.algorithm,
                'publicKey': self.signer_public_key,
            },
        }


def legacy_trust_status() -> dict[str, Any]:
    """Return the stable, machine-readable P0-002 disablement status."""

    return {
        'enabled': LEGACY_TRUST_ENABLED,
        'errorCode': LEGACY_TRUST_ERROR_CODE,
        'legacySchemaVersion': SCHEMA_VERSION,
        'replacement': LEGACY_TRUST_REPLACEMENT,
        'reason': LEGACY_TRUST_REASON,
    }


def _raise_legacy_trust_disabled(operation: str) -> NoReturn:
    details = legacy_trust_status()
    details['operation'] = operation
    raise InteroperabilityError(
        LEGACY_TRUST_ERROR_CODE,
        LEGACY_TRUST_REASON,
        details=details,
    )


def generate_signing_keypair(*, key_id: str) -> SigningKeyPair:
    """Reject generation of credentials for the retired v1 protocol."""

    del key_id
    _raise_legacy_trust_disabled('generate_signing_keypair')


def _signing_material(manifest_type: str, manifest_sha256: str, key_id: str, algorithm: str, signed_at: str) -> bytes:
    """Retain the old canonical material only for migration diagnostics."""

    return canonical_json({
        'manifestType': manifest_type,
        'manifestSha256': manifest_sha256,
        'signerKeyId': key_id,
        'algorithm': algorithm,
        'signedAt': signed_at,
    }).encode('utf-8')


def sign_manifest(manifest_type: str, manifest: Mapping[str, Any], key_pair: SigningKeyPair) -> SignedManifestEnvelope:
    """Reject creation of new v1 trust envelopes."""

    del manifest_type, manifest, key_pair
    _raise_legacy_trust_disabled('sign_manifest')


def verify_signed_manifest(envelope: Mapping[str, Any] | SignedManifestEnvelope) -> dict[str, Any]:
    """Reject every v1 envelope before reading attacker-controlled key data."""

    del envelope
    _raise_legacy_trust_disabled('verify_signed_manifest')
