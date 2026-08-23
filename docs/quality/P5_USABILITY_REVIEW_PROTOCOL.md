# P5 Human Usability Review Protocol

**Task:** P5-015  
**Dependency:** P5-011 onboarding/capability doctor and P5-014 UX regression gate must be landed before a session counts toward closure.

## Representative sessions

Run the same release-candidate build with at least three representative users who did not implement the tested flow. At least one session must be on Windows and one on macOS. A user may satisfy more than one experience category, but the packet must include:

1. New/local-first user: start Kristin, understand readiness, select/connect a model, create/open a project and send a simple Chat request.
2. Builder: run a task that uses project files, observe planning/model/tool progress, handle an approval checkpoint, inspect the resulting run/evidence and recover from one seeded failure.
3. Power/Owner Mode user: identify Owner Mode state, enter the governed activation flow where available, run an interactive terminal/process task, stop it, and understand the remaining authority/risk state.

If P1A/P2 controlled certification is not complete, the Owner Mode session must be recorded as blocked and P5-015 cannot use that blocked flow to claim full product completion.

## Session rules

- Do not coach the participant unless the script explicitly requests a hint.
- Record task completion, time-to-understanding, wrong turns, confusing labels, unrecoverable states and unsolicited comments.
- Do not record project content, secrets, terminal credentials or model prompts in the evidence packet. Use synthetic fixtures where screen recording would expose content.
- Every finding has an owner, severity and disposition.

## Severity rubric

| Severity | Definition | Closure rule |
|---|---|---|
| Critical | Prevents a primary workflow, can cause unauthorized action/data loss, or makes authority state materially misleading | Must be fixed and retested before RC |
| High | Primary flow succeeds only with substantial help or repeated recovery | Must be fixed or explicitly accepted by product owner before RC |
| Medium | Noticeable friction with a clear workaround | Tracked with owner and target |
| Low | Polish/copy/discoverability issue | May remain with rationale |

## Required evidence packet

Create `release/evidence/P5-015/` containing:

- `manifest.json` — exact candidate SHA/tree, session count, platforms and aggregate disposition;
- one redacted `session-<id>.json` per participant with role category, platform, script version, outcomes and finding IDs;
- `findings.json` — normalized findings, severities, owners and fix/acceptance commits;
- `retest.json` — proof that every critical/high fix was retested on the exact successor candidate;
- no participant names, emails, project paths, prompts, secrets or recordings.

## Completion rule

P5-015 is complete only when representative sessions were actually performed and the packet proves there is **no unresolved critical usability blocker** on the release candidate. Automated agents may prepare this protocol, validate the packet and fix findings, but they must not fabricate human participants, observations or approvals.
