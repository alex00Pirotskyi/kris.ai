# Mission Execution 1.5 — Connector-Native Runtime CAS

This protocol is the authoritative fallback transport for Mission Execution 1.5 workers that can access GitHub through a connector/API but do not have a faithful local Git checkout.

It preserves the same runtime-generation, exact-base, semaphore, collision, and non-force publication semantics as the local `mission_orchestrator.py` path.

## Transport equivalence

Two transports are valid for an authoritative runtime transition:

1. **LOCAL_GIT** — run the repository orchestrator against a faithful checkout, then commit the complete generation transition once and non-force fast-forward `agent/mission-runtime`.
2. **CONNECTOR_CAS** — construct the complete generation transition as one Git Database commit whose single parent is the exact current `agent/mission-runtime` head, then move the branch with a non-force ref update.

Neither transport is weaker. Both must satisfy the same schemas and semantic invariants.

`runtime/tx/*` branches remain forbidden for new work.

## Required connector primitives

The connector/API path is usable only when equivalents of all of these operations exist:

- fetch branch/ref head;
- fetch commit metadata including its tree SHA;
- fetch files/directories at an immutable commit SHA;
- create blob;
- create tree from an exact base tree;
- create commit with an exact parent;
- compare commits or otherwise inspect the candidate diff;
- non-force update branch ref.

Typical GitHub connector operations are equivalent to:

- `fetch` / `fetch_file`
- `fetch_commit`
- `create_blob`
- `create_tree`
- `create_commit`
- `compare_commits`
- `update_ref(force=false)`

The GitHub Contents API (`create_file`, `update_file`, `delete_file`) MUST NOT be used to publish a multi-file authoritative runtime generation because it creates one commit per file.

## Immutable snapshot

Before planning a transition:

1. Resolve `R0` = exact current head of `agent/mission-runtime`.
2. Fetch commit `R0` and record `T0 = R0^{tree}` from GitHub commit metadata.
3. Fetch `runtime/meta.json` and every runtime object required by the operation **at ref `R0`**, not at the moving branch name.
4. Record `G0 = runtimeGeneration`.
5. Fetch the current control-plane implementation and schemas used by the operation.
6. Re-resolve the affected canonical Product PR/helper branch from live GitHub refs.
7. For every Work Order or semaphore `baseCommit/baseTree`, fetch the base commit through GitHub and require its returned tree SHA to equal the stored `baseTree`.

If any required object cannot be resolved exactly, do not publish a runtime mutation.

## Semantic planning

The connector worker must reproduce the current Mission Execution 1.5 transition semantics; it may not invent a reduced or approximate state change.

Read the exact current implementation in `tool/mission_runtime_model.py` / `tool/mission_orchestrator.py` plus the current runtime schemas before deriving the candidate.

For the requested operation, derive the same complete file set the orchestrator would produce, including as applicable:

- Work Order mutation;
- semaphore creation/mutation/release;
- runtime meta generation increment;
- exactly one runtime event for the transition;
- canonical Product PR observation update when the operation is a post-integration reconciliation.

Require:

- `G1 == G0 + 1`;
- the event `runtimeGeneration == G1`;
- event/work-order/mission identities match the operation;
- any Work Order `activeSemaphoreId` references the semaphore created or already active in the same resulting snapshot;
- any active semaphore points back to the same Work Order;
- allowed paths do not exceed Work Order/authority scope;
- dependencies are satisfied at the declared level;
- no active semaphore collision exists;
- WRITE/AUTHORITY helper branch rules remain valid;
- INTEGRATION semaphore Product PR and branch bindings remain exact;
- live Product PR observations are not stale.

If the worker cannot determine the exact transition semantics from the current repository, it must not guess.

## Construct the candidate without moving authority

1. Create blobs for every changed/new runtime file.
2. Create tree `T1` using `T0` as `base_tree_sha` and replacing/adding only the intended paths.
3. Create commit `C1` with:
   - tree = `T1`;
   - parent = `R0`;
   - one descriptive runtime-transition commit message.
4. Do **not** move `agent/mission-runtime` yet.
5. Compare `R0...C1` and require the changed path set to equal the exact planned transition path set.
6. Fetch each changed file at `C1` and re-check schema/identity/generation relationships.
7. Require the candidate commit parent to remain exactly `R0`.

An unreferenced candidate commit is not runtime authority.

## Compare-and-swap publication

Immediately before publication:

1. Re-fetch `agent/mission-runtime` head as `Rcheck`.
2. Require `Rcheck == R0`.
3. If it differs, abandon `C1`, refetch the new runtime generation, and recompute the entire transition.
4. If it matches, call the equivalent of:

   `update_ref(branch=agent/mission-runtime, sha=C1, force=false)`

5. A non-fast-forward or conflict response means the CAS lost. Do not retry the same candidate. Recompute from the new runtime head.
6. Never use `force=true`.

Because `C1` has exactly `R0` as its parent, another worker winning from `R0` creates a sibling history and GitHub's non-force ref update rejects the stale candidate.

## Post-publication proof

After a successful ref update:

1. Re-fetch `agent/mission-runtime` and require its head equals `C1`.
2. Fetch `runtime/meta.json` at `C1` and require generation `G1`.
3. Fetch the transition event at `C1`.
4. Fetch the Work Order/semaphore/Product PR records affected by the transition.
5. Re-resolve the live product/helper refs.
6. Re-run the semantic equivalent of `doctor` and `mission_v15_live_runtime_audit` from immutable GitHub data.
7. Only after those checks may the worker mutate the product/helper/shared-authority branch authorized by the new runtime state.

A connector success response without repository confirmation is not evidence.

## Product/helper writes under connector mode

Product/helper commits may use normal connector file/Git operations only after the required runtime semaphore is durably visible.

For concurrent canonical Product PR integration, exact-head protection is mandatory. Re-resolve the target branch immediately before publication and use a non-force expected-head-safe operation. If the target moves, recompute rather than overwriting it.

## Failure classification

Do **not** report `NO_LOCAL_EXECUTABLE_WORK` merely because local Git is unavailable.

If LOCAL_GIT is unavailable but CONNECTOR_CAS primitives exist, continue with CONNECTOR_CAS.

Only report:

`BLOCKED_EXTERNAL: ATOMIC_RUNTIME_PUBLISH_UNAVAILABLE`

when neither transport can produce and verify one coherent non-force CAS runtime generation.

If no Work Order can be safely executed even with an available transport, report `NO_EXECUTABLE_WORK`, not `NO_LOCAL_EXECUTABLE_WORK`.
