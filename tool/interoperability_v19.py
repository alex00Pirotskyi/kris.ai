#!/usr/bin/env python3
"""Deterministic manifest-signing helpers for v1.9 release operations.

This module is intentionally standard-library only. It provides the minimal
shared contracts needed by `release_ops_v19.py` for authenticated manifest,
audit-checkpoint, and update-policy verification in source-only environments.
"""
from __future__ import annotations

import dataclasses
import datetime as dt
import hashlib
import hmac
import json
import secrets
from typing import Any, Mapping

VERSION = '1.9.0+190'
SCHEMA_VERSION = '1.0.0'
SIGNATURE_ALGORITHM = 'hmac-sha256'


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
    key_id: str
    public_key: str
    private_key: str
    algorithm: str = SIGNATURE_ALGORITHM


@dataclasses.dataclass(frozen=True)
class SignedManifestEnvelope:
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


def generate_signing_keypair(*, key_id: str) -> SigningKeyPair:
    secret = secrets.token_hex(32)
    return SigningKeyPair(key_id=str(key_id), public_key=secret, private_key=secret)


def _signing_material(manifest_type: str, manifest_sha256: str, key_id: str, algorithm: str, signed_at: str) -> bytes:
    return canonical_json({
        'manifestType': manifest_type,
        'manifestSha256': manifest_sha256,
        'signerKeyId': key_id,
        'algorithm': algorithm,
        'signedAt': signed_at,
    }).encode('utf-8')


def sign_manifest(manifest_type: str, manifest: Mapping[str, Any], key_pair: SigningKeyPair) -> SignedManifestEnvelope:
    manifest_json = dict(manifest)
    manifest_sha256 = sha256_json(manifest_json)
    signed_at = utc_now()
    signature = hmac.new(
        key_pair.private_key.encode('utf-8'),
        _signing_material(manifest_type, manifest_sha256, key_pair.key_id, key_pair.algorithm, signed_at),
        hashlib.sha256,
    ).hexdigest()
    return SignedManifestEnvelope(
        manifest_type=str(manifest_type),
        manifest=manifest_json,
        manifest_sha256=manifest_sha256,
        signature=signature,
        signer_key_id=key_pair.key_id,
        signer_public_key=key_pair.public_key,
        signed_at=signed_at,
        algorithm=key_pair.algorithm,
    )


def verify_signed_manifest(envelope: Mapping[str, Any] | SignedManifestEnvelope) -> dict[str, Any]:
    if isinstance(envelope, SignedManifestEnvelope):
        payload = envelope.to_json()
    else:
        payload = dict(envelope)
    try:
        manifest_type = str(payload['manifestType'])
        manifest = dict(payload['manifest'])
        manifest_sha256 = str(payload['manifestSha256'])
        signature = str(payload['signature'])
        signed_at = str(payload['signedAt'])
        signer = dict(payload['signer'])
        key_id = str(signer['keyId'])
        algorithm = str(signer['algorithm'])
        public_key = str(signer['publicKey'])
    except Exception as exc:  # noqa: BLE001
        raise InteroperabilityError('signed_manifest_invalid', 'Signed manifest envelope is malformed.') from exc
    if algorithm != SIGNATURE_ALGORITHM:
        raise InteroperabilityError('signature_algorithm_unsupported', f'Unsupported signature algorithm: {algorithm}')
    actual_sha256 = sha256_json(manifest)
    if actual_sha256 != manifest_sha256:
        raise InteroperabilityError('manifest_payload_tampered', 'Manifest payload hash does not match the envelope.')
    expected = hmac.new(
        public_key.encode('utf-8'),
        _signing_material(manifest_type, manifest_sha256, key_id, algorithm, signed_at),
        hashlib.sha256,
    ).hexdigest()
    if not hmac.compare_digest(expected, signature):
        raise InteroperabilityError('manifest_signature_invalid', 'Manifest signature verification failed.')
    return {
        'verified': True,
        'manifestType': manifest_type,
        'manifest': manifest,
        'manifestSha256': manifest_sha256,
        'signerKeyId': key_id,
        'algorithm': algorithm,
    }
