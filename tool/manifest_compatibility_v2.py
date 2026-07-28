#!/usr/bin/env python3
from __future__ import annotations

from typing import Any, Mapping


class ManifestCompatibilityError(ValueError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


LEGACY_FIELDS = frozenset({"hmac", "secret", "keyMaterial", "signingKey", "algorithm"})


def classify_manifest(value: Mapping[str, Any]) -> str:
    version = str(value.get("schemaVersion") or "")
    if version in {"1", "1.0", "1.0.0", "v1"}:
        raise ManifestCompatibilityError(
            "v1_trust_disabled",
            "Signed Manifest v1 can never authorize production trust.",
        )
    if version != "2.0.0":
        raise ManifestCompatibilityError(
            "unsupported_manifest_version",
            f"Unsupported manifest version: {version or '<missing>'}",
        )
    legacy = sorted(LEGACY_FIELDS.intersection(value))
    if legacy:
        raise ManifestCompatibilityError(
            "mixed_format_rejected",
            f"Signed Manifest v2 contains legacy trust fields: {legacy}",
        )
    return "signed_manifest_v2"
