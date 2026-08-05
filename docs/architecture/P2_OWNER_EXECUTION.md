# P2 Owner execution architecture — V63

`ProductRuntime -> merged P1A isolated authority-service client -> OS-authenticated typed authorize-effect request -> policy/grant/use/revocation/audit checks inside P1A -> one-use ECDSA P-256 effect permit -> supervised executor public-key verification -> final target revalidation -> effect -> redacted outcome -> typed P1A outcome recording -> desktop evidence acceptance`

Owner Mode raises the scope ceiling to the full host available to the current OS account. It is not containment and never silently becomes `isolated_untrusted`. Every effect remains bound to the exact run, task, actor, tool, access profile, capability, operation, scope, budgets, expiry, use number, request ID, worker session, and trusted owner approval.

P2 does not construct a policy engine, grant issuer, durable use ledger, revocation store, audit signer, protected-key broker, or P1 authority composition. It consumes the ProductRuntime `p1AuthorityService` handle introduced by the separately reviewed P1A amendment. The automation worker receives public verification material only and is a distinct OS principal denied service/key-store access.

Cancellation and kill are idempotent. Process identities include an OS creation/start token or supervisor identity, never PID alone. Ambiguous completion is journaled as `unknown` and reconciled before retry. Reversibility is declared before the effect and never inferred from success.
