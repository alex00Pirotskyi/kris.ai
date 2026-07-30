# P1A isolated authority-service threat model

## Protected assets

Policy state, owner approvals, Capability Grant v2 signing material, durable use
state, revocation state, audit-checkpoint signing material, effect-permit keys,
and the exact desktop-client identity.

## Adversaries

- compromised model output, repository, tool output, environment or worker;
- compromised automation-host dependency;
- same-login-session process running with the worker's restricted principal;
- replay after authority, desktop or worker restart;
- malicious request using an allowed service transport;
- path replacement, executable substitution and PID reuse.

The current OS-account owner and platform administrator remain trusted roots.
Owner Mode is not a sandbox for the effects the owner explicitly authorizes.

## Mandatory invariants

1. The worker has no private/symmetric authority material and no generic signer.
2. The authority service authenticates the exact ProductRuntime client before
   parsing an authorization request.
3. Authorization, grant issuance, use consumption, revocation check, nonce and
   deadline validation, and audit append occur in one service transaction.
4. A permit is single-use, exact-request-bound and public-key verifiable.
5. Authority keys are non-exportable or readable only by the service identity.
6. Worker denial is proved with the real worker binary on Windows, macOS and
   Linux; file-mode metadata or source assertions are not proof.
7. Service restart cannot reset replay or use-consumption state.
8. Unsupported or unprovisioned platform isolation fails closed.
