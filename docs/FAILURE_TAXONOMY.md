# Kristin execution failure taxonomy

This taxonomy is the first v1.1.7 stability-freeze baseline. The class determines whether retry, deterministic recovery, user approval, or immediate termination is valid.

| Class | Meaning | Automatic retry | Required response |
|---|---|---:|---|
| `provider_transient` | Timeout, temporary provider unavailability, connection reset, or bounded cold-load failure | bounded | Retry inside provider or one fresh attempt if budget and circuit state allow |
| `protocol_schema` | Model output cannot be normalized into a canonical decision | bounded | Return exact schema error and task-appropriate canonical example |
| `tool_input` | Required argument missing or safe canonical form not supplied | bounded | Repair the named argument without changing authority |
| `path_presentation` | Whole-scalar quote or Markdown wrapper is presentation syntax | deterministic | Canonicalize before policy; retain normal boundary enforcement |
| `project_scope` | Path, process, or resource falls outside the approved project | no mutation retry | Block; optionally gather bounded root evidence for read-only mistakes |
| `policy_rejection` | Permission, privacy, network, secret, self-modification, or security policy rejects action | no | Stop or request explicit approval; never retry unchanged |
| `artifact_incomplete` | Expected artifact exists but objective coverage or validation is incomplete | bounded | Mutate exact artifact, then inspect and validate |
| `verification_failure` | Objective validator, analyzer, test, or health check fails | bounded by strategy | Repair from concrete evidence; do not accept model prose as completion |
| `semantic_non_progress` | Repeated reads, no-op writes, duplicate errors, or identical decisions change no durable fact | no identical retry | Change strategy, split task, ask user, route model, or stop |
| `resource_unavailable` | Required SDK, executable, model, service, or port is unavailable | conditional | Wait only for an explicit resource state or require configuration |
| `state_conflict` | Expected hash, transaction journal, or concurrent project state changed | no blind retry | Re-inspect, rebase, or request user resolution |
| `deterministic_bug` | Runtime invariant, parser, persistence, or policy implementation is wrong | no | Fail precisely, preserve replay, patch runtime, add regression fixture |
| `budget_exhausted` | A phase-specific hard limit was reached | no | Report consumed and remaining budgets plus the first causal error |
| `cancelled` | User or policy cancellation was observed | no | Stop side effects, reconcile process state, and record cancellation evidence |

## Retry invariants

1. Policy and security rejections are never retried automatically.
2. A retry must have enough remaining phase budget to perform a meaningful correction.
3. Identical state plus identical action is not a retry; it is a loop.
4. Every retry records the prior error class and the durable fact expected to change.
5. A mutation is not success until affected artifacts are independently observed and validated.
6. A terminal error reports the first causal class separately from later budget or convergence consequences.
