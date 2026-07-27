# Capability Grant v2

P1-003 defines the per-effect authority envelope consumed by workers. Access Profile v2 remains the maximum ceiling; a grant is the narrower, authenticated authorization for one run/task/actor/tool context.

## Required binding

Every grant binds `runId`, `taskId`, `actorId`, `toolId`, and `accessProfileId`. It additionally carries explicit path, process, network, browser-profile, secret-lease, budget, expiry, nonce, and use-count scopes. A worker compares every binding against its authenticated invocation context before any effect.

## Authentication boundary

The envelope carries only `algorithm`, `keyId`, and `mac`. The HMAC key is supplied from the external ephemeral runtime keyring owned by the desktop policy authority; no envelope field can introduce key material. P1-005 and P1-006 separately own durable Ed25519 manifest trust and do not get replaced by this local runtime grant MAC.

## Consumption order

1. Parse and reject unknown/missing fields.
2. Resolve the external issuer key.
3. Authenticate the canonical envelope with the domain separator.
4. Match run, task, actor, tool, and access profile.
5. Enforce not-before and expiry.
6. Atomically consume `(grantId, nonce, invocationId)` and `maxUses`.
7. Only then invoke the effect adapter.

Modified, expired, replayed, exhausted, wrong-run, wrong-task, wrong-actor, wrong-tool, and wrong-profile grants fail closed with typed codes. Ambiguous effects still require reconciliation; a grant is authority, not evidence of completion.
