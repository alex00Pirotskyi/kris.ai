# ADR-0006 — TUF update trust and recovery

**Status:** ACCEPTED
**Date:** 2026-07-28
**Task:** P1-008

Kristin update trust uses The Update Framework role model: offline root, targets, snapshot and timestamp. Root uses a multi-key threshold and remains offline. Online roles are independently rotatable and short-lived. Consistent snapshots and delegated nightly, alpha, beta, stable and emergency channels are mandatory.

The design rejects rollback, freeze, mix-and-match and signer-substitution attacks. Root rotation and compromise recovery require the ceremony in `docs/security/TUF_KEY_CEREMONY.md`. Implementation and release publication remain later P9 tasks; this ADR fixes trust ownership and recovery semantics now.
