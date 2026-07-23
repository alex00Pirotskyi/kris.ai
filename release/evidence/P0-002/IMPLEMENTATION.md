# P0-002 implementation report

## Decision

The vulnerable v1 protocol is retired rather than repaired in place. Its data classes remain available for reading historical records, but all public trust operations terminate with `v1_trust_disabled`.

## Why fail-closed retirement is required

The old verifier accepted a sender-provided `signer.publicKey` as the HMAC secret. An attacker could choose the secret and every signed field, calculate the matching HMAC, and pass verification. There was no external trust anchor to distinguish an approved signer from the attacker.

## Implemented control

```text
generate_signing_keypair -> v1_trust_disabled
sign_manifest             -> v1_trust_disabled
verify_signed_manifest    -> v1_trust_disabled
```

Rejection happens before envelope parsing. A malformed, forged, typed, algorithm-substituted, or internally consistent v1 envelope receives the same stable outcome.

## Compatibility boundary

The following remain for migration and diagnostics only:

- `SigningKeyPair` legacy shape.
- `SignedManifestEnvelope` legacy shape.
- Canonical JSON and SHA-256 helpers.
- Legacy signing-material serialization.

None can produce an authorization result.

## Executable evidence

`tool/v1_trust_disablement_test.py` runs eight cases, including reconstruction of the exact forgery. The delivery execution passed 8/8.

`ATTACK_REPRODUCTION.json` additionally executes the same forged envelope against the hash-exact pre-patch helper and the patched helper. The pre-patch verifier accepts it; the patched verifier rejects it with `v1_trust_disabled`.
