"""Minimal deterministic Ed25519 test helper.

This helper is test/support code only. Production code uses OS-isolated P1A permits
and public-key verification in the automation host.
"""
from __future__ import annotations

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey


def _private(seed: bytes) -> Ed25519PrivateKey:
    if not isinstance(seed, (bytes, bytearray)) or len(seed) != 32:
        raise ValueError("Ed25519 seed must be exactly 32 bytes")
    return Ed25519PrivateKey.from_private_bytes(bytes(seed))


def public_key(seed: bytes) -> bytes:
    return _private(seed).public_key().public_bytes(
        serialization.Encoding.Raw,
        serialization.PublicFormat.Raw,
    )


def sign(seed: bytes, message: bytes) -> bytes:
    if not isinstance(message, (bytes, bytearray)):
        raise TypeError("message must be bytes")
    return _private(seed).sign(bytes(message))


def verify(public_key_bytes: bytes, message: bytes, signature: bytes) -> bool:
    try:
        Ed25519PublicKey.from_public_bytes(bytes(public_key_bytes)).verify(bytes(signature), bytes(message))
        return True
    except Exception:
        return False
