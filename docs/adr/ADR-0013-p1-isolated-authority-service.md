# ADR-0013 — Isolated P1 authority service

**Status:** PROPOSED / SECURITY-REVIEW REQUIRED
**Train:** P1A-001
**Date:** 2026-07-28

## Decision

The concrete P1 desktop authority is moved into a separately installed and
separately reviewed operating-system service under a separate OS identity. P2 may consume only the merged
service contract. It may not carry a broker executable, protected-key handles,
policy engine, grant issuer, use ledger, revocation store, or audit signer.

The service exposes only three typed operations:

1. `authorize-effect-v2` — evaluate policy, validate explicit owner approval,
   issue the exact Capability Grant v2, consume its use, check revocation,
   append the audit checkpoint, and return one Ed25519 effect permit.
2. `record-effect-outcome-v1` — reconcile a permit with a typed effect receipt.
3. `public-verifier-bootstrap-v1` — return public verification material only.

There is no arbitrary HMAC or signature operation and no raw-key export.

## Platform isolation

- **Windows:** a dedicated service identity owns non-exportable CNG keys. A
  named-pipe server validates the client PID, token, non-AppContainer desktop
  identity, signed executable identity, exact image digest, and session. The
  automation worker runs with a restricted/AppContainer token and is rejected.
- **macOS:** an `SMAppService` launch daemon/XPC service owns keychain items.
  XPC peer code-signing and entitlement requirements admit only the main
  ProductRuntime identifier; the sandboxed worker identifier is rejected.
- **Linux:** a root/dedicated service owns the key and ledger. AF_UNIX
  `SO_PEERCRED`, exact `/proc/<pid>/exe` digest and a per-launch credential admit
  the desktop process. The worker uses a distinct UID and cannot read the key,
  connect to the socket, or access the desktop credential.

P1A remains incomplete until real worker-denial, restart, replay, key-access,
and typed-authorization tests pass on all three platforms and an independent
security reviewer approves the exact source and binaries.
