#!/usr/bin/env python3
"""Executable P0-002 gate for the retired v1 signed-manifest trust path."""
from __future__ import annotations

import argparse
import dataclasses
import hashlib
import hmac
import inspect
import json
from pathlib import Path
from typing import Callable

import interoperability_v19 as legacy


@dataclasses.dataclass(frozen=True)
class Result:
    name: str
    passed: bool
    detail: str


def _expect_disabled(action: Callable[[], object], operation: str) -> str:
    try:
        action()
    except legacy.InteroperabilityError as error:
        if error.code != legacy.LEGACY_TRUST_ERROR_CODE:
            raise AssertionError(
                f'expected {legacy.LEGACY_TRUST_ERROR_CODE}, got {error.code}'
            ) from error
        if error.details.get('operation') != operation:
            raise AssertionError(
                f'expected operation {operation}, got {error.details.get("operation")}'
            ) from error
        if error.details.get('enabled') is not False:
            raise AssertionError('disablement receipt did not record enabled=false') from error
        return f'code={error.code} operation={operation}'
    raise AssertionError('legacy trust operation unexpectedly succeeded')


def _attacker_forgery() -> dict[str, object]:
    """Recreate the exact self-authenticating construction accepted before P0-002."""

    attacker_material = 'attacker-controlled-hmac-material'
    key_id = 'attacker-key'
    manifest_type = 'capability'
    signed_at = '2026-07-23T00:00:00+00:00'
    manifest = {
        'id': 'malicious.owner-mode-plugin',
        'capabilities': ['host:*', 'secrets:*', 'updates:install'],
    }
    manifest_sha256 = legacy.sha256_json(manifest)
    material = legacy.canonical_json({
        'manifestType': manifest_type,
        'manifestSha256': manifest_sha256,
        'signerKeyId': key_id,
        'algorithm': legacy.SIGNATURE_ALGORITHM,
        'signedAt': signed_at,
    }).encode('utf-8')
    signature = hmac.new(
        attacker_material.encode('utf-8'),
        material,
        hashlib.sha256,
    ).hexdigest()
    return {
        'schemaVersion': legacy.SCHEMA_VERSION,
        'manifestType': manifest_type,
        'manifest': manifest,
        'manifestSha256': manifest_sha256,
        'signature': signature,
        'signedAt': signed_at,
        'signer': {
            'keyId': key_id,
            'algorithm': legacy.SIGNATURE_ALGORITHM,
            'publicKey': attacker_material,
        },
    }


def _run_case(name: str, action: Callable[[], str]) -> Result:
    try:
        return Result(name=name, passed=True, detail=action())
    except Exception as error:  # noqa: BLE001 - reported as gate evidence
        return Result(name=name, passed=False, detail=f'{type(error).__name__}: {error}')


def _status_case() -> str:
    status = legacy.legacy_trust_status()
    if status != {
        'enabled': False,
        'errorCode': 'v1_trust_disabled',
        'legacySchemaVersion': '1.0.0',
        'replacement': 'signed_manifest_v2',
        'reason': legacy.LEGACY_TRUST_REASON,
    }:
        raise AssertionError(f'unexpected disablement status: {status}')
    return 'enabled=false replacement=signed_manifest_v2'


def _key_generation_case() -> str:
    return _expect_disabled(
        lambda: legacy.generate_signing_keypair(key_id='legacy-release'),
        'generate_signing_keypair',
    )


def _signing_case() -> str:
    key_pair = legacy.SigningKeyPair(
        key_id='legacy-release',
        public_key='not-trusted',
        private_key='not-trusted',
    )
    return _expect_disabled(
        lambda: legacy.sign_manifest('update', {'version': '9.9.9'}, key_pair),
        'sign_manifest',
    )


def _forgery_case() -> str:
    return _expect_disabled(
        lambda: legacy.verify_signed_manifest(_attacker_forgery()),
        'verify_signed_manifest',
    )


def _typed_envelope_case() -> str:
    forged = _attacker_forgery()
    signer = dict(forged['signer'])
    envelope = legacy.SignedManifestEnvelope(
        manifest_type=str(forged['manifestType']),
        manifest=dict(forged['manifest']),
        manifest_sha256=str(forged['manifestSha256']),
        signature=str(forged['signature']),
        signer_key_id=str(signer['keyId']),
        signer_public_key=str(signer['publicKey']),
        signed_at=str(forged['signedAt']),
    )
    return _expect_disabled(
        lambda: legacy.verify_signed_manifest(envelope),
        'verify_signed_manifest',
    )


def _malformed_case() -> str:
    return _expect_disabled(
        lambda: legacy.verify_signed_manifest({'signer': {'publicKey': 'chosen'}}),
        'verify_signed_manifest',
    )


def _algorithm_substitution_case() -> str:
    forged = _attacker_forgery()
    signer = dict(forged['signer'])
    signer['algorithm'] = 'Ed25519'
    forged['signer'] = signer
    return _expect_disabled(
        lambda: legacy.verify_signed_manifest(forged),
        'verify_signed_manifest',
    )


def _source_hardening_case() -> str:
    source = inspect.getsource(legacy)
    forbidden = (
        "public_key.encode('utf-8')",
        "hmac.compare_digest(expected, signature)",
        "'verified': True",
        'secret = secrets.token_hex(32)',
    )
    present = [marker for marker in forbidden if marker in source]
    if present:
        raise AssertionError(f'legacy acceptance logic remains: {present}')
    required = (
        'LEGACY_TRUST_ENABLED = False',
        "LEGACY_TRUST_ERROR_CODE = 'v1_trust_disabled'",
        "_raise_legacy_trust_disabled('generate_signing_keypair')",
        "_raise_legacy_trust_disabled('sign_manifest')",
        "_raise_legacy_trust_disabled('verify_signed_manifest')",
    )
    missing = [marker for marker in required if marker not in source]
    if missing:
        raise AssertionError(f'disablement markers missing: {missing}')
    return 'legacy verifier contains no acceptance or envelope-key verification path'


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--json-output', type=Path)
    args = parser.parse_args()

    cases = (
        ('Disablement status is explicit', _status_case),
        ('Legacy key generation is blocked', _key_generation_case),
        ('Legacy manifest signing is blocked', _signing_case),
        ('Envelope-supplied HMAC forgery is rejected', _forgery_case),
        ('Typed legacy envelope is rejected', _typed_envelope_case),
        ('Malformed legacy envelope is rejected fail-closed', _malformed_case),
        ('Algorithm substitution cannot bypass disablement', _algorithm_substitution_case),
        ('Legacy acceptance implementation is absent', _source_hardening_case),
    )
    results = [_run_case(name, action) for name, action in cases]
    payload = {
        'milestone': 'P0-002',
        'version': legacy.VERSION,
        'caseCount': len(results),
        'passedCount': sum(item.passed for item in results),
        'failedCount': sum(not item.passed for item in results),
        'passed': all(item.passed for item in results),
        'trustStatus': legacy.legacy_trust_status(),
        'results': [dataclasses.asdict(item) for item in results],
    }
    rendered = json.dumps(payload, indent=2, sort_keys=True) + '\n'
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(rendered, encoding='utf-8')
    print(rendered, end='')
    return 0 if payload['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
