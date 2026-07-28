# ADR-0003 — Signed Manifest v2 trust format

**Status:** ACCEPTED
**Date:** 2026-07-28
**Tasks:** P1-005, P1-006, P1-007

Kristin adopts Ed25519 signatures over the RFC 8785 canonical JSON subset defined by `config/signed_manifest_v2.json`. Trust roots are resolved from an external protected key registry by `keyId`; no envelope may carry private key material or a self-selected trust root.

Every signed envelope binds an intended use, trust domain, issue time, expiry and payload. Verification fails closed for unknown/revoked keys, wrong purpose/domain, expiry, mutation, malformed signatures, unsupported versions and mixed v1/v2 fields. Legacy Signed Manifest v1 remains permanently unable to authorize production trust.

The schema subset forbids floating-point values. This keeps Python and Dart canonicalization byte-identical until a separately tested full RFC 8785 number implementation is adopted.
