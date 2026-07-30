# P1A V63 isolated authority-service threat model

## Trust boundary

The desktop ProductRuntime is the only client permitted to request typed authority operations. The automation worker is hostile and may possess full current-account process and filesystem authority. It must therefore execute as a distinct operating-system principal and remain unable to read authority credentials, connect as the desktop, invoke a signing oracle, or access the platform key provider.

## Platform isolation

- **Linux:** dedicated `kristin-authority` service UID, dedicated `kristin-worker` UID/GID, AF_UNIX peer credentials, root-owned systemd unit, encrypted systemd credentials, and PKCS#11/TPM2 provider-backed P-256 key.
- **Windows:** service SID, named-pipe client token and image/signature checks, AppContainer/restricted worker SID, LSA service credentials, and non-exportable CNG Platform KSP P-256 key.
- **macOS:** XPC audit-token and designated-requirement checks, separately signed App Sandbox worker, Keychain service-only credentials, and Secure Enclave P-256 key.

## Authority invariants

The service accepts only typed operations. It validates owner approval, deterministic policy, exact grant binding, budgets, expiry, use count, revocation epoch, durable replay state, worker identity, and audit predecessor before signing a one-use effect permit. No API signs caller-selected bytes.

## Evidence invariants

Completion requires exact-run signed runner/build/installer/provider/worker-denial/cleanup receipts, a service-generated ECDSA behavior receipt, live GitHub job verification, independent signed review, and signed owner approval. Unsigned, self-asserted, source-only, skipped, unsupported, or malformed evidence cannot close P1A.
