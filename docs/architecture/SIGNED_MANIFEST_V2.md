# Signed Manifest v2

Signed Manifest v2 is the common trust envelope for worker descriptors, extensions, agents, releases, audit checkpoints and update targets.

Verification order:

1. Reject unsupported or legacy versions.
2. Validate schema and canonical JSON subset.
3. Resolve `keyId` from the external protected key registry.
4. Check revocation, intended use and trust domain.
5. Check issue and expiry times.
6. Verify Ed25519 over the canonical envelope body.
7. Return the payload only after every check passes.

`tool/ed25519_ref.py` and `lib/product/signed_manifest_v2.dart` implement the same RFC 8032 and manifest golden vectors. Test seeds are fixtures only and are never production trust roots.
