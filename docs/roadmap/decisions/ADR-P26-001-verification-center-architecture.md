# ADR-P26-001 — Verification Center architecture

**Status:** `ACCEPTED`  
**Date:** 2026-08-24  
**Owner:** `P26`

## Context

Kristin has strong verification primitives, but they are distributed across developer
surfaces and phase-specific tooling. Users need one general workspace that binds project
identity, acceptance criteria, safe execution, exact result states, coverage, browser and
native evidence, updater stages, and bounded repair without overstating what was proved.

## Decision

1. Build Verification Center as a product workspace, not a development-only dashboard.
2. Keep it project-neutral; Kristin is the mandatory dogfood project, not the schema.
3. Reuse canonical Test Center identities and assurance levels instead of defining a competing evidence model.
4. Reuse Project Manager and project-profile identity for discovery and source binding.
5. Reuse P2 managed operations and updater stages; reuse P3 governed browser and testing paths.
6. Permit exactly six result states: PASS, FAIL, BLOCKED_ENVIRONMENT, BLOCKED_PERMISSION, NOT_RUN, and UNKNOWN.
7. Aggregate fail-closed: only PASS passes; blockers, NOT_RUN, and UNKNOWN never promote.
8. Support structured, human-authored, and agent-prompt acceptance criteria as first-class records with provenance.
9. Separate analyze-only, quick-check, deep-check, and test-and-repair modes.
10. Limit repair to two recorded attempts and stop on non-progress or any policy boundary.
11. Make `.prowork/verification/` optional, versioned, deterministic, and idempotent.
12. Require explicit confirmation for destructive, remote, restart, rollback, and out-of-project write actions.
13. Keep browser, HTTP fixture, native, updater, coverage, and release evidence at their actual assurance levels.
14. Make the full Kristin dogfood journey release-blocking, while refusing to treat it as proof of every project or platform.

## Consequences

P26-001 establishes governance only. Later packets must land in dependency order.
Unimplemented profiles remain blocked rather than skipped. Source-contract PASS does not
certify packaged product behavior, native support, updater safety, release support, or GA.
