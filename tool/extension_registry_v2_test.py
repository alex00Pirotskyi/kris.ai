#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
import tempfile

from ed25519_ref import public_key
from extension_registry_v2 import ExtensionRegistryV2
from signed_manifest_v2 import ExternalKeyring, TrustKey, sign_manifest

SEED = bytes(reversed(range(32)))
KEY_ID = "extension-publisher-test"
CODE_SHA = "a" * 64
TEST_SHA = "b" * 64


def envelope(*, code_sha: str = CODE_SHA, capabilities: list[str] | None = None) -> dict[str, object]:
    return sign_manifest(
        {
            "schemaVersion": "2.0.0",
            "keyId": KEY_ID,
            "intendedUse": "kristin_extension",
            "trustDomain": "kristin.extensions",
            "issuedAt": "2026-01-01T00:00:00Z",
            "expiresAt": "2099-01-01T00:00:00Z",
            "payload": {
                "schemaVersion": "2.0.0",
                "extensionType": "plugin",
                "id": "release-helper",
                "publisher": "example.publisher",
                "version": "2.0.0",
                "codeSha256": code_sha,
                "testsSha256": TEST_SHA,
                "requestedCapabilities": capabilities or ["read_project", "write_artifact"],
                "compatibility": [">=2.0.0", "<3.0.0"],
                "entryPoint": "bin/release_helper",
            },
        },
        seed=SEED,
    )


def keyring() -> ExternalKeyring:
    return ExternalKeyring(
        {
            KEY_ID: TrustKey(
                key_id=KEY_ID,
                public_key=public_key(SEED),
                intended_uses=frozenset({"kristin_extension"}),
                trust_domains=frozenset({"kristin.extensions"}),
            )
        }
    )


def expect_error(fn, code: str) -> None:
    try:
        fn()
    except Exception as exc:
        assert code in str(exc), exc
        return
    raise AssertionError(f"expected {code}")


def main() -> int:
    now = datetime(2026, 8, 23, 12, tzinfo=timezone.utc)
    registry = ExtensionRegistryV2()
    installed = registry.install(
        envelope(),
        keyring=keyring(),
        now=now,
        actual_code_sha256=CODE_SHA,
        actual_tests_sha256=TEST_SHA,
    )
    assert installed.manifest.identity == "example.publisher/release-helper"
    assert registry.capabilities(installed.manifest.identity) == ("read_project", "write_artifact")
    assert registry.inspect(installed.manifest.identity)["enabled"] is False
    registry.enable(installed.manifest.identity)
    assert registry.inspect(installed.manifest.identity)["enabled"] is True
    registry.disable(installed.manifest.identity)
    assert registry.inspect(installed.manifest.identity)["enabled"] is False

    expect_error(
        lambda: registry.install(
            envelope(code_sha="c" * 64),
            keyring=keyring(),
            now=now,
            actual_code_sha256=CODE_SHA,
            actual_tests_sha256=TEST_SHA,
        ),
        "extension_code_digest_mismatch",
    )

    registry.revoke(installed.manifest.identity)
    expect_error(lambda: registry.enable(installed.manifest.identity), "extension_revoked")
    expect_error(
        lambda: registry.install(
            envelope(),
            keyring=keyring(),
            now=now,
            actual_code_sha256=CODE_SHA,
            actual_tests_sha256=TEST_SHA,
        ),
        "extension_identity_revoked",
    )

    with tempfile.TemporaryDirectory(prefix="kristin-extension-") as raw:
        target = Path(raw) / "registry.json"
        registry.export(target)
        exported = target.read_text(encoding="utf-8")
        assert '"requestedCapabilities"' in exported
        assert '"revoked": true' in exported

    print("PASS extension registry v2: signed identity, exact capabilities, revoke and digest checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
