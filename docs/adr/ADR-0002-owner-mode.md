# ADR-0002 — Owner Mode authority, elevation and safety semantics

**Date:** 2026-07-27
**Status:** ACCEPTED
**Decision owner:** Product owner / sole maintainer
**Task:** `P1-001`

## Context

The product owner requires full-computer authority on Windows, macOS and Linux. Hiding that authority behind project tools or calling it a sandbox would be misleading. At the same time, broad authority must not let model text, web content or a compromised worker become the grant issuer.

## Decision

Owner Mode is an explicit access profile that can exercise the maximum authority available to the current OS account. Native elevation may be requested through a visible OS-approved flow when the platform permits it. Owner Mode is **not a sandbox** and is never enabled merely because a tool path is outside a registered project.

The deterministic policy authority issues bounded, auditable grants to the Owner executor. Interactive Owner Mode, unattended Owner Mode and isolated-untrusted execution are distinct states. Disabling approvals does not disable request identity, journaling, output limits, process-tree cleanup, durable evidence, secret redaction or the emergency kill path.

## Invariants

- The UI continuously identifies Owner Mode and the target effect domain.
- A model, prompt, tool output, page, repository or worker cannot grant or widen authority.
- Raw secrets are not copied into prompts, normal logs or evidence. Credential use occurs through brokered operations or bounded leases.
- Elevation requires an OS-native owner interaction or preconfigured external authority; no unattended prompt may synthesize consent.
- Every effect is bound to run, task, actor, capability, target, budget, expiry and use count once Capability Grant v2 exists.
- Unknown effects are reconciled before retry.
- Emergency stop terminates the complete managed process tree and records the outcome.
- Owner Mode may access non-project paths; safer profiles remain fail-closed.

## Consequences

P1-002 owns the profile schema, P1-003 owns grant binding, P1-004 owns deterministic resolution, and P2 owns concrete filesystem/terminal/OS adapters. This ADR does not claim those implementations already exist.
