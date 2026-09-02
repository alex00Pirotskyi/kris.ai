# KRISTIN CORRECTIVE QUALIFICATION + MAIN LANDING CONTRACT

Status: **AUTHORITATIVE QWEN QUALIFICATION / INTEGRATION / LANDING WORK ORDER**

This document is the source of truth for qualifying and landing the combined One-Kristin + dynamic self-awareness + autonomic-recovery corrective candidate.

## 1. Authoritative source and supersession

Authoritative immutable source candidate:

- Branch: `candidate/kristin-self-awareness-corrective-landing-source`
- SHA: `3119211e11ce5ccf8b6411aa7fa05bbd8c640139`
- Traceability implementation branch: `feat/kristin-self-awareness-autonomic-recovery`
- Corrective handoff: `docs/implementation-handoffs/kristin-self-awareness-corrective-pass.md`

Historical candidate, preserved for audit only and explicitly superseded:

- Branch: `candidate/kristin-self-awareness-landing-source`
- SHA: `81091cdf615c8fe4a0e8382ec402b977ea2ea8c6`

Do not move, rewrite, or add commits to either candidate branch.

PR #291, #300, and #301 are historical only and MUST NOT be used as landing vehicles.

Expected `main` observed when this contract was updated:

- `74515b89dd16a1084b40760bd482524cca5e1b2c`

That SHA is not a landing assumption. Qwen MUST resolve live `main` before integration and again immediately before landing.

## 2. Required reading

Before editing or qualifying:

1. read `docs/implementation-handoffs/kristin-self-awareness-corrective-pass.md` from the authoritative candidate;
2. read this contract completely;
3. use older Kristin implementation/landing handoffs only as historical context, never as a substitute for the corrective candidate state.

The implementation worker intentionally did not run analyzer, tests, CI, release qualification, or landing. Qwen owns qualification truth.

## 3. Qwen role and permitted scope

Qwen acts as:

- **TESTER**
- **DEFECT HUNTER**
- **INTEGRATOR**
- **MAIN LANDING EXECUTOR**

Qwen may repair defects required to qualify and land the candidate, including compile/interface defects, current-`main` integration conflicts, runtime wiring defects, tests, release checks, and CI defects.

Qwen MUST NOT use this assignment for unrelated feature development, speculative redesign, or broad cleanup.

Every material repair changes the candidate-under-test SHA and therefore requires final qualification to be re-established on the new exact SHA.

## 4. Clean integration procedure

1. Verify `candidate/kristin-self-awareness-corrective-landing-source` still resolves exactly to `3119211e11ce5ccf8b6411aa7fa05bbd8c640139`.
2. Resolve live `main`.
3. Create a fresh qualification/integration branch from that live `main`.
4. Integrate the exact immutable corrective candidate into the fresh branch.
5. Perform all repairs and qualification on the integration branch only.
6. Do not edit either immutable candidate.
7. Do not edit or directly manipulate `main` during qualification.
8. Before final landing, resolve live `main` again. If it advanced, reconcile and requalify the resulting exact SHA.

## 5. Non-negotiable architecture invariants

Qualification MUST preserve all of the following:

- There is one Kristin conversation/session control plane; do not reintroduce split conversational authorities.
- Capability **knowledge**, operational **availability**, **health**, **authority**, and exact Runner **tool availability** are separate facts.
- `USER CAPABILITY != EXECUTION TOOL`.
- Coordinator capabilities such as `agent.create_project`, `agent.modify_project`, `agent.fix_project`, and recovery coordinators MUST NOT leak into exact Runner tool lists.
- A self-model/catalog/planner may restrict or describe capability use; it MUST NOT mint Runner tools or permission grants.
- Authority MUST NOT be inferred from capability availability, health, Browser readiness, Owner readiness, or recovery-host readiness.
- Browser and Owner state must be reported truthfully from the real runtime.
- Original task continuation is permitted only after mandatory recovery verification succeeds.
- Explicit user cancellation is final; autonomic recovery MUST NOT resurrect cancelled work.
- The SHA that lands MUST be the exact SHA that passed the final mandatory qualification gates.

Any violation is a hard stop.

## 6. Corrective implementation claims Qwen MUST prove

The corrective pass claims to wire previously identified gaps. Treat every item below as a verification target, not as an assumption.

### A. Universal Task Kernel uses live self-awareness

Prove that:

- `KernelSelfModelRegistry` is actually installed on the production Chat/ProductRuntime composition path;
- understanding and planning consume the live self-model capability intersection;
- the self-model can remove unavailable capabilities but cannot add a capability absent from the caller/catalog;
- exact Runner tool names remain a separate input;
- consumed coordinator capabilities remain explicit and never become execution tools;
- research, diagnostics, semantic replans, and primary planning cannot silently reconstruct a broader static capability universe.

### B. Runtime self-model lifecycle is truthful and bounded

Prove that:

- selected project/model state is session-scoped overlay state rather than accidental global mutable truth;
- concurrent refreshes are serialized/coalesced safely;
- semantic state/change fingerprints do not report observation timestamps as material state changes;
- capability descriptors use explicit project/model requirements;
- a selected model is available only when fresh discovery actually contains that exact model;
- provider discovery is bounded/cached appropriately and records per-provider failures without converting partial failure into false global health;
- probe scheduling selects due probes before expensive refresh work where intended;
- probe health has an independent TTL;
- post-probe refresh publishes probe results back into the self-model used by planning/Chat;
- Browser and Owner availability/diagnostic state comes from the actual ProductRuntime handles.

### C. ProductRuntime recovery is concrete, durable, and connected

Prove `lib/product/recovery/product_runtime_recovery.dart` is production wiring, not a disconnected abstraction:

- structured failures, attempts, and recovery experiences persist through the canonical durable event journal;
- the production composition installs the `run.failed` watcher;
- direct operational failures can enter the same supervisor without blocking the user-visible error path;
- recovery-generated internal child runs do not recursively create concurrent supervisors;
- linked continuations of the original user task remain observable so recurrence can advance the bounded strategy ladder;
- recovery shutdown/lifecycle behavior does not leak duplicate watchers or corrupt runtime shutdown.

### D. L3 code repair is a governed kernel operation

Prove L3 recovery:

- creates a real recovery `TaskSpecification`;
- plans and compiles through the existing Universal Task Kernel;
- executes a real governed recovery run;
- waits for terminal recovery work before verification begins;
- cannot carry forward permissions that were not active on the original governed task;
- rejects any permission-scope expansion;
- does not resume the original task before verification passes;
- preserves original run/task lineage and evidence.

### E. L4 staged self-repair remains fail-closed

Prove the staged host flow is:

`stage -> qualify -> activate -> verify -> rollback on failure`

and that:

- the recovery host is an independent `KristinRecoveryHost` boundary;
- host registration/readiness is not authority;
- a separate external governed authority provider must positively establish `owner` / `owner.self_repair`;
- Owner runtime availability, completion eligibility, or secure-isolation readiness alone can never satisfy that authority;
- absence of an external authority provider or recovery host yields truthful blocked / not-evaluated state;
- Kristin MUST NOT claim L4 operational readiness when those external prerequisites are absent;
- activation or verification failure rolls back to last-known-good state.

Claiming usable L4 without both the independent host and externally proven authority is a hard stop.

### F. Recovery is bounded and progress-aware

Prove that:

- terminal/permission/unknown failures cannot fall through to L0 transient retry;
- retry/escalation attempts are bounded;
- repeated ineffective strategies are suppressed for the same normalized failure/environment;
- durable recovery experience influences later strategy selection;
- merely producing a new evidence/event ID is NOT material progress;
- semantic before/after state or successful verification establishes progress;
- failed verification can trigger rollback where deterministic rollback exists;
- repeated no-progress cycles terminate/escalate rather than loop forever.

### G. One Kristin Chat exposes the same live self-model

Prove deterministic Chat handling for self-awareness questions such as:

- “what can you do?”
- “why can’t you do X?”
- “what do you need for X?”
- “what changed?”
- “check your health”
- “check your integrity”

The answers must come from the same live self-model used by planning, must distinguish unavailable from unauthorized, and must never claim an effect or grant authority.

## 7. Focused qualification scenarios

In addition to the repository’s normal suite, add or execute focused coverage sufficient to prove:

1. known capability vs currently unavailable vs authority-blocked vs exact-tool-executable;
2. project/model session overlay isolation between different conversations/contexts;
3. concurrent self-model refresh serialization;
4. provider partial-failure behavior;
5. selected model missing from fresh discovery;
6. probe due/TTL/post-refresh publication behavior;
7. semantic change fingerprint immunity to observation-time-only churn;
8. terminal, permission, and unknown failures never selecting L0 retry;
9. bounded repeated failure and learned-ineffective strategy skipping;
10. added evidence IDs alone do not count as progress;
11. L3 recovery reaches terminal result before verifier invocation;
12. recovery authority carry-forward rejects scope expansion;
13. explicit user cancellation is never automatically resumed;
14. internal recovery child runs are excluded from recursive supervision while linked continuations remain recurrence-visible;
15. original task continuation occurs only after successful recovery verification;
16. L4 requires independent host + external authority and rolls back failed candidate activation/verification;
17. deterministic Chat self-awareness uses the live state seen by planning.

## 8. Mandatory qualification gates

Qwen MUST discover and execute the repository’s current required gates rather than relying only on this list.

At minimum, final qualification must include, where supported by the repository:

- Dart formatting check;
- analyzer with repository-required fatal warnings/infos;
- full automated test suite;
- focused Kristin/self-awareness/recovery tests;
- repository release validation;
- security/source-manifest/native/tool/e2e checks required by current `main`;
- hosted CI checks required for landing;
- required OS/platform checks on the **exact final qualification SHA**.

No failing mandatory gate may be waived.

Record every exact command/check and its result in the final landing report.

## 9. Repair policy during qualification

Allowed:

- compile fixes;
- API/interface compatibility fixes;
- current-`main` integration fixes;
- missing production wiring discovered by qualification;
- regression tests required to prove the contract;
- release/CI fixes needed for the candidate to satisfy existing repository policy.

Not allowed:

- unrelated product features;
- unrelated architecture redesign;
- broad opportunistic cleanup;
- weakening tests/checks/policies to manufacture green status;
- changing an immutable candidate branch.

After a material repair:

1. commit it on the qualification/integration branch;
2. establish the new exact candidate-under-test SHA;
3. rerun all gates invalidated by that change;
4. perform the complete mandatory final qualification on one exact final SHA before landing.

## 10. Exact-SHA qualification rule

Before opening/using the landing PR, record one final qualification SHA.

The following MUST all refer to that same SHA:

- final local mandatory qualification;
- mandatory hosted/CI gates;
- landing PR head;
- the SHA approved for merge.

Any commit, rebase, merge-from-main, conflict resolution, generated-file change, or other content change after qualification creates a new SHA and invalidates previous exact-SHA qualification.

Requalify before landing.

## 11. Hard-stop conditions

Report **BLOCKED WITH EXACT EVIDENCE** and do not land if any unresolved condition remains, including:

- authoritative candidate branch no longer equals `3119211e11ce5ccf8b6411aa7fa05bbd8c640139`;
- live `main` changes after qualification and the new integration has not been requalified;
- analyzer, tests, release validation, required security/tool/native/e2e checks, or required CI remain failing;
- self-awareness/catalog/planning can introduce an execution capability/tool the caller/Runner did not provide;
- coordinator capabilities leak into Runner execution tools;
- capability availability, health, Browser readiness, Owner readiness, or recovery-host readiness is treated as authority;
- recovery resumes original work before verification succeeds;
- recovery resumes or recreates explicitly cancelled user work;
- L4 is represented as operational without an independent recovery host and externally proven `owner` / `owner.self_repair` authority;
- recovery can loop without bounded attempts or without semantic progress;
- evidence/event creation alone is accepted as progress;
- selected model/provider/Browser/Owner state is reported more optimistically than fresh runtime evidence supports;
- session-scoped self-model selection leaks across conversations;
- multiple competing Kristin conversational/control-plane states are reintroduced;
- the proposed landing requires destructive or unreviewed direct manipulation of `main`.

## 12. Landing procedure

When and only when one exact final SHA is fully green:

1. resolve live `main` again;
2. if it changed, refresh/reconcile the qualification branch and requalify;
3. open or use a clean landing PR from the qualification branch to live `main`;
4. do not use PR #291, #300, or #301;
5. confirm the PR head is exactly the final qualified SHA;
6. require all repository-required hosted gates;
7. merge only that exact qualified content through the repository’s normal landing mechanism;
8. do not force-push or directly rewrite `main`.

## 13. Post-landing verification and report

After merge:

- resolve `main` and record the landed SHA;
- verify the qualified candidate content is an ancestor/content of the landed result as appropriate for the repository’s merge method;
- run any repository-required post-landing smoke/verification;
- confirm the landing did not reintroduce authority/tool/control-plane violations.

Final report MUST include:

- immutable source candidate branch + SHA;
- live `main` base SHA used for final integration;
- qualification/integration branch;
- final exact qualified SHA;
- every mandatory command/check and result;
- focused corrective scenarios and results;
- all qualification repairs with commit SHAs;
- explicit L4 truth: host state and external authority state, including blocked/not-evaluated if that is the real result;
- landing PR number;
- resulting `main` SHA;
- residual risks, if any.

## 14. Terminal outcomes

This work order has exactly two acceptable terminal states:

### **VERIFIED LANDED**

All mandatory gates passed on the exact landed content and post-landing verification succeeded.

### **BLOCKED WITH EXACT EVIDENCE**

A hard-stop condition remains. Report the exact failing command/check, SHA, logs/evidence, and why landing was refused.

There is no “mostly green,” “waived,” or “land now and fix later” terminal state.
