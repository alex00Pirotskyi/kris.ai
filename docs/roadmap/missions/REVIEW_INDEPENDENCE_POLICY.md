# Mission Execution 1.5 Review Independence Policy

This policy separates **worker identity**, **execution role**, **execution context** and **GitHub/service identity**. A Worker letter is never evidence of independent GitHub identity.

## R0 — Builder Check

R0 is an exact-candidate self-check. It may authorize helper handoff, never terminal roadmap acceptance.

## R1 — Context Independent Review

R1 requires a distinct `reviewContextId` that is not an implementer authoring context and a reviewer that did not author the reviewed diff. R1 may satisfy normal product-source review where the delivery policy permits it.

## R2 — Identity Independent Review

R2 additionally requires a repository-verifiable reviewer GitHub/service/human identity distinct from the implementer identity. R2 is mandatory for configured high-risk boundaries including credentials/identity authority, signing, release authorization, support promotion and GA.

## Exact binding

Every review receipt binds the exact candidate commit/tree and review scope. Scoped carry-forward is permitted only when `review-impact` proves the carried scope unchanged. Source/security review never carries across changed source/security paths.
