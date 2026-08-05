# Kristin P2 automation host — V63

The automation host is a supervised effect executor. It never issues grants, widens policy, selects authority roots, reads protected-key handles, invokes an authority signer, or receives symmetric/private authorization material.

## Authorization boundary

For each effect, the separately governed and already merged P1A authority service authenticates the ProductRuntime desktop principal through an OS-enforced service boundary. The service validates the deterministic policy decision, owner approval, exact Capability Grant v2, durable pre-effect use, current revocation state, nonce/deadline, and audit state **inside the service** before it returns a typed one-use ECDSA P-256 effect permit.

The P2 adapter is delegation-only. The worker bootstrap contains only the public ECDSA P-256 verification key plus non-secret replay/use/revocation state. `host.mjs` rejects IPC HMAC keys, grant or consumption keyrings, private keys, seeds, signing secrets, key handles, broker paths, and arbitrary-message signing requests.

Every PTY/session request must present a fresh permit whose exact binding matches the stored session identity. Replayed request IDs, expired permits, revoked grants, changed payloads, changed authorization records, or another worker session fail before dispatch. A separately provisioned worker principal must be unable to connect to the authority service or use the platform keystore.

## Lifecycle boundary

The host enforces bounded output, typed lifecycle states, exact process identity, idempotent cancellation, and full-tree termination through native platform supervisors. It returns candidate redacted receipts; only the desktop control plane and P1A service can complete the authority/evidence path.
