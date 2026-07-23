# Kristin Master Roadmap V3.1 Reconciliation

**Status:** approved implementation authority candidate  
**Document version:** `3.1.0-top-tier-consumer-execution-corrected`  
**Source reviewed:** `KRISTIN_TOP_TIER_CONSUMER_AI_AGENT_MASTER_ROADMAP_V3_0.md`  
**Target repository path:** `docs/roadmap/MASTER.md`

## Decision

Adopt V3.1 as the sole human-readable roadmap authority after it is committed. Earlier roadmaps should be retained only as historical records with a `SUPERSEDED` pointer to `docs/roadmap/MASTER.md`.

The V3.0 expansion is strategically strong: it adds synchronized Windows/macOS/Linux delivery, Owner Mode, native desktop control, universal connectors, application and content factories, multimodal/realtime interaction, provider orchestration, portable skills, consumer productization, no-SQL migration planning, and machine-validated roadmap data. The V3.1 corrections below make that expansion executable without contradicting the current v1.9 source baseline.

## Normative corrections

1. **Versions have distinct meanings.**
   - Product target: Kristin 4.x.
   - Roadmap document: V3.1.
   - Current implementation baseline: v1.9.0+190 until code and release metadata advance.

2. **Execution order is dependency order, not numeric display order.**

   ```text
   P0 → P1 → P2–P19 → P21 → P22 → P23 → P24 → P20
   ```

   P20 remains the terminal synchronized-GA phase even though later-added specialist phases have higher numbers.

3. **SQLite remains authoritative until the P24 migration is proven.**
   The current SQLite durability kernel must not be deleted or bypassed. P24 introduces the abstraction, dual-write/replay verification, corruption recovery, benchmark comparison, migration, and rollback evidence required before the embedded object/document authority becomes canonical.

4. **Roadmap-as-data starts in P0-008 and matures in P24.**
   P0-008 must provide a bootstrap parser/validator for task IDs, dependencies, statuses, and evidence paths. P24 expands it into the final generated manifest and claim system.

5. **Vertical product slices begin at P2.**
   P0 and P1 are allowed to deliver reproducible foundation slices: a runnable gate, fixture, evidence record, or policy decision. From P2 onward every phase must produce a user-observable vertical result on Windows, macOS, and Linux where desktop-impacting.

6. **P0-003 must preserve capability truth.**
   - It may run deterministic host probes that test CLI/environment plumbing and never execute untrusted project code.
   - It may run the built-in deterministic snapshot packager without a sandbox because that path does not execute project code.
   - Analyze/Test/Build/Run remain fail-closed when the real sandbox backend is unavailable.
   - Windows/macOS native Owner Mode and hostile-workload isolation are implemented later through P2 and P11, not simulated in P0.

7. **P0-003 depends on P0-002.**
   The insecure v1 trust path must be disabled before CI is treated as production evidence.

8. **All AI prompts and status files must reference `docs/roadmap/MASTER.md`.**
   Stale paths and the old `2.1.0-omni-provider-orchestration` identifier are invalid.

## Current repository divergence

The public GitHub `main` observed during this review still exposes the vulnerable v1 HMAC verifier and does not visibly contain the P0-002 retirement files. Therefore:

- P0-003 may be started only on a local branch/check-out where `v1_trust_disabled` and `tool/v1_trust_disablement_test.py` are present.
- This delivery refuses to apply when P0-002 cannot be proven locally.
- No public branch or release is considered updated merely because an external patch bundle exists.

## P0-003 interpretation

P0-003 is complete only when all three CI lanes reach every existing step and pass:

```text
protocol generators
workflow migration gate
SQLite durability gate
Prompt Studio gates
format check
Flutter analysis
Flutter tests
release/source validator
native release build
```

A platform without a real sandbox passes Project Manager capability tests by proving the stable fail-closed result, not by executing project code on the host. The result report must state which sandbox-dependent cases executed and which validated fail-closed behavior.

## Supersession instructions

Commit:

```text
docs/roadmap/MASTER.md
docs/roadmap/V3_1_RECONCILIATION.md
```

For every older roadmap retained in the repository, add near its title:

```markdown
> **SUPERSEDED:** Use `docs/roadmap/MASTER.md`.
```

Do not copy conflicting task tables into `STATUS.md`; status should identify task IDs and link back to the master roadmap.
