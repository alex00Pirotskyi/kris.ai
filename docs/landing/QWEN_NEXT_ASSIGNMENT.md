# QWEN NEXT ASSIGNMENT — Kristin Corrective Qualification + Main Landing

Priority: **CRITICAL / NEXT SAFE LANDING JOB**

Role: **TESTER + DEFECT_HUNTER + INTEGRATOR + MAIN LANDING EXECUTOR**

Authoritative contract:

`docs/landing/kristin-combined-authoritative-qualification-and-main-landing.md`

## Authoritative immutable source candidate

- Branch: `candidate/kristin-self-awareness-corrective-landing-source`
- SHA: `3119211e11ce5ccf8b6411aa7fa05bbd8c640139`
- Implementation branch for traceability only: `feat/kristin-self-awareness-autonomic-recovery`
- Corrective implementation handoff: `docs/implementation-handoffs/kristin-self-awareness-corrective-pass.md`

Historical superseded candidate — preserve, do not modify or land:

- Branch: `candidate/kristin-self-awareness-landing-source`
- SHA: `81091cdf615c8fe4a0e8382ec402b977ea2ea8c6`

Expected `main` observed when this assignment was updated:

- `74515b89dd16a1084b40760bd482524cca5e1b2c`

This is informational only. Resolve live `main` immediately before creating the integration branch and again immediately before landing.

## Execution instruction

Once the current already-reserved Qwen Work Order reaches a safe terminal/released boundary, stop taking unrelated self-generated development work and execute this assignment.

Read, in order:

1. `docs/implementation-handoffs/kristin-self-awareness-corrective-pass.md` from the immutable corrective candidate;
2. the authoritative landing contract above;
3. older Kristin handoffs only as historical context.

Your job is NOT new feature development. Your job is to qualify, repair only landing-blocking defects, and land the corrective candidate safely.

You must:

1. verify the corrective candidate branch still resolves exactly to `3119211e11ce5ccf8b6411aa7fa05bbd8c640139`;
2. resolve current `main` and create a fresh qualification/integration branch from it;
3. integrate the exact corrective candidate into that clean branch;
4. inspect and prove the combined One-Kristin + live self-awareness + autonomic-recovery architecture;
5. specifically prove production kernel self-awareness, concrete ProductRuntime recovery wiring, `run.failed` supervision, bounded progress-aware recovery learning, and deterministic Chat self-awareness;
6. prove L3 recovery executes governed kernel repair to terminal completion before verification, never expands authority, and resumes the original task only after verification;
7. prove user cancellation remains final and cannot be resurrected by recovery;
8. prove L4 is fail-closed: an independent recovery host and external authority provider must separately establish `owner` / `owner.self_repair`; Owner runtime readiness alone is never authority;
9. run every mandatory repository qualification gate, including focused regression coverage for the corrective pass;
10. repair any compile, interface, integration, runtime-wiring, test, release, or CI defect required for safe landing, but do not perform unrelated redesign or feature work;
11. after every material repair, re-run the required qualification and establish a new exact final qualification SHA;
12. prove all mandatory local and hosted gates on that exact final SHA;
13. create/use a clean landing PR to live `main`;
14. land only the exact SHA that passed final qualification;
15. verify `main` after landing and write the final landing report.

Do not use PR #291, #300, or #301 as landing vehicles. They are historical only.

Do not modify either immutable candidate branch.

Do not touch `main` directly during qualification.

Do not infer authority from capability availability, health, Browser readiness, Owner readiness, or recovery-host availability.

Do not waive failing gates.

If live `main` changes after final qualification, refresh the integration, establish a new exact SHA, and requalify before landing.

If a hard-stop condition in the authoritative contract remains unresolved, report BLOCKED and do not land.

This assignment supersedes autonomous unrelated Qwen feature-generation work until the landing contract reaches exactly one of:

- **VERIFIED LANDED**
- **BLOCKED WITH EXACT EVIDENCE**
