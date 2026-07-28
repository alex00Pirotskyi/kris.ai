#!/usr/bin/env python3
from __future__ import annotations

from hashlib import sha512

Q = 2**255 - 19
L = 2**252 + 27742317777372353535851937790883648493
D = (-121665 * pow(121666, Q - 2, Q)) % Q
I = pow(2, (Q - 1) // 4, Q)


class Ed25519Error(ValueError):
    pass


def _xrecover(y: int) -> int:
    xx = (y * y - 1) * pow(D * y * y + 1, Q - 2, Q) % Q
    x = pow(xx, (Q + 3) // 8, Q)
    if (x * x - xx) % Q != 0:
        x = x * I % Q
    if x & 1:
        x = Q - x
    return x


B_Y = 4 * pow(5, Q - 2, Q) % Q
B = (_xrecover(B_Y), B_Y)


def _edwards(p: tuple[int, int], q: tuple[int, int]) -> tuple[int, int]:
    x1, y1 = p
    x2, y2 = q
    common = D * x1 * x2 * y1 * y2
    x3 = (x1 * y2 + x2 * y1) * pow(1 + common, Q - 2, Q) % Q
    y3 = (y1 * y2 + x1 * x2) * pow(1 - common, Q - 2, Q) % Q
    return x3, y3


def _scalarmult(p: tuple[int, int], scalar: int) -> tuple[int, int]:
    result = (0, 1)
    addend = p
    value = scalar
    while value:
        if value & 1:
            result = _edwards(result, addend)
        addend = _edwards(addend, addend)
        value >>= 1
    return result


def _encodepoint(point: tuple[int, int]) -> bytes:
    x, y = point
    return (y | ((x & 1) << 255)).to_bytes(32, "little")


def _decodepoint(data: bytes) -> tuple[int, int]:
    if len(data) != 32:
        raise Ed25519Error("invalid public key length")
    y = int.from_bytes(data, "little") & ((1 << 255) - 1)
    if y >= Q:
        raise Ed25519Error("non-canonical point")
    x = _xrecover(y)
    sign = data[31] >> 7
    if (x & 1) != sign:
        x = Q - x
    point = (x, y)
    if (-x * x + y * y - 1 - D * x * x * y * y) % Q != 0:
        raise Ed25519Error("point is not on curve")
    return point


def _clamped_scalar(seed: bytes) -> tuple[int, bytes]:
    if len(seed) != 32:
        raise Ed25519Error("seed must be 32 bytes")
    digest = bytearray(sha512(seed).digest())
    digest[0] &= 248
    digest[31] &= 63
    digest[31] |= 64
    return int.from_bytes(digest[:32], "little"), bytes(digest[32:])


def public_key(seed: bytes) -> bytes:
    scalar, _ = _clamped_scalar(seed)
    return _encodepoint(_scalarmult(B, scalar))


def sign(seed: bytes, message: bytes) -> bytes:
    scalar, prefix = _clamped_scalar(seed)
    public = public_key(seed)
    r = int.from_bytes(sha512(prefix + message).digest(), "little") % L
    encoded_r = _encodepoint(_scalarmult(B, r))
    challenge = int.from_bytes(sha512(encoded_r + public + message).digest(), "little") % L
    s = (r + challenge * scalar) % L
    return encoded_r + s.to_bytes(32, "little")


def verify(public: bytes, message: bytes, signature: bytes) -> bool:
    try:
        if len(signature) != 64:
            return False
        encoded_r = signature[:32]
        s = int.from_bytes(signature[32:], "little")
        if s >= L:
            return False
        r = _decodepoint(encoded_r)
        a = _decodepoint(public)
        challenge = int.from_bytes(sha512(encoded_r + public + message).digest(), "little") % L
        return _scalarmult(B, s) == _edwards(r, _scalarmult(a, challenge))
    except (Ed25519Error, ValueError):
        return False
