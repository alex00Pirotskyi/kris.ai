# KRIS Qwen Engineering Environment 5.4

## Purpose

Qwen 5.4 turns the local Mission Execution worker from a bounded generic coding loop into a bounded product-engineering environment. It keeps all 5.3.1 authority, reconciliation, self-healing, review-independence, branch, semaphore, and CI truth boundaries.

The engineering environment does not grant new repository authority. It improves what Qwen can understand and validate inside an already-authorized Work Order.

## Execution stack

```text
Mission Work Order
  -> Qwen 5.4 skill router
  -> selected controller-owned engineering guidance
  -> repository context on demand
  -> bounded model action
  -> controller-owned safe action/recipe
  -> focused local validation
  -> helper PR
  -> hosted CI / review / integration
```

The stable launcher filename remains `tool/kris_qwen_worker_v53.py` for controller/process compatibility. After 5.4 rollout that stable entry forwards to `tool/kris_qwen_worker_v54.py`.

## Skill router

The controller-owned catalog is `config/qwen_engineering_skills.v1.json`.

The catalog currently covers:

- Kristin product architecture;
- Flutter product/UI work;
- browser runtime and Web Studio;
- Owner Mode/process/filesystem behavior;
- Prompt Studio/local-model behavior;
- native/platform work;
- Python tooling and CI;
- testing and quality;
- performance debugging;
- security boundaries.

The router scores the Work Order objective, type, roadmap task, required tests, and allowed paths. `kris-product-architecture` is always selected. Only a bounded number of skills are injected into a task.

Skill instructions are controller-owned engineering procedure. Documents loaded by a skill are always labelled `UNTRUSTED_REPOSITORY_CONTEXT`: they may explain architecture or subsystem behavior, but they cannot expand `allowedPaths`, change a Work Order, grant a semaphore, create review independence, or establish release/support truth.

## Engineering actions

Qwen 5.4 adds these bounded actions:

- `list_skills` — list the engineering skills and show which ones were routed to the current Work Order;
- `read_skill` — load one skill's guidance plus bounded repository context;
- `list_recipes` — list fixed controller-owned build/test recipes;
- `run_recipe` — run one fixed recipe with validated parameters;
- `repo_map` — return a bounded tracked-source map, allowed-path matches, and nearby tests;
- `ui_map` — return textual Flutter widget/layout/accessibility structure and golden-test references;
- `inspect_pr_checks` — read current status checks for the Work Order's canonical Product PR only.

All pre-existing source actions remain bounded by the Work Order and live lease.

## Controlled recipes

Recipes are not arbitrary shell access. The controller constructs the argv itself and validates any target before execution.

Current recipes:

- `flutter-test-target`
- `flutter-analyze`
- `dart-format-check`
- `flutter-build-linux`
- `flutter-build-web`
- `browser-runtime-node-test`
- `node-test-target`
- `python-test-target`
- `pytest-target`
- `workflow-integrity`
- `native-cmake-test`

The runner:

1. re-verifies the live lease;
2. validates the recipe target is repository-relative and in the recipe's fixed scope;
3. constructs a fixed command plan;
4. removes secrets and GitHub/model credentials from the child environment;
5. uses the existing Linux bubblewrap network sandbox when available;
6. runs the command in the helper worktree;
7. re-checks Work Order changed-path authority after every command;
8. records exact argv, exit code, duration, and bounded output;
9. makes successful recipe validation eligible for the final local gate;
10. reruns the selected recipe against final bytes before a source-changing Work Order may finish.

Package installation remains intentionally unavailable to the model. Qwen cannot turn a recipe request into arbitrary `pip`, `npm install`, `apt`, shell, or networked installer execution.

## Native build capability

`native-cmake-test` gives Qwen a real bounded native compile/test loop without exposing general shell access.

A target must be a repository directory under the approved native/service roots and contain `CMakeLists.txt`. The controller performs:

```text
cmake -S <target> -B build/qwen-recipes/<bounded-id>
cmake --build build/qwen-recipes/<bounded-id> --parallel <bounded-jobs>
ctest --test-dir build/qwen-recipes/<bounded-id> --output-on-failure
```

The build directory is under the repository's ignored `build/` state. Platform qualification still requires the appropriate hosted/target platform evidence; one local build is not cross-platform certification.

## Browser and Web Studio capability

The browser skill points Qwen at the repository's P3 browser recipes and current product architecture. It can run canonical browser-runtime Node tests and inspect browser/Web Studio source, DOM/accessibility-oriented contracts, console/network behavior, replay, preview, upload, and download logic.

The local Qwen model is text-only. It does **not** gain pixel vision in 5.4.

`ui_map` and browser observations improve visual-product engineering by exposing textual layout, widget, accessibility, visible-text, DOM, console, network, screenshot-hash, and golden-test structure. They do not let Qwen judge whether a screenshot looks attractive or whether spacing is visually ideal.

A future multimodal/vision sidecar may provide pixel-level UI review, but it must be separately evidence-bound and must not silently turn screenshot contents into execution authority.

## Architecture context

Initial Work Order context now includes the selected skill summaries, instructions, documentation pointers, and recipes. Qwen can load detailed documents only when useful rather than paying the context cost on every task.

This is intended to reduce repeated rediscovery of:

- service boundaries;
- Owner Mode vs isolation semantics;
- Browser Runtime/Web Studio conventions;
- Test Center expectations;
- Prompt Studio latency/cancellation goals;
- native/platform constraints;
- security and evidence truth boundaries.

## CI inspection

`inspect_pr_checks` is read-only and is restricted to the current Work Order's `parentProductPr`.

It returns live PR head/base identities and `statusCheckRollup`. This allows Qwen to diagnose current CI state without trusting stale PR prose and without receiving GitHub mutation authority.

Queued, skipped, `action_required`, zero-job, stale-head, and historical runs remain non-PASS.

## Safety boundary

5.4 deliberately does not add:

- arbitrary shell execution;
- arbitrary Git/GitHub mutation by the model;
- package installation;
- unrestricted network access;
- secret access;
- protected-main writes;
- Mission Runtime writes outside controller operations;
- self-certified review independence;
- pixel-level screenshot interpretation.

The model proposes. The controller validates scope, authority, commands, and final evidence.

## Adding a skill

A new skill requires a catalog entry with:

- unique `id`;
- concise `summary`;
- routing `keywords` and/or `pathPrefixes`;
- bounded `instructions`;
- repository `docs` used only as untrusted context;
- recipe IDs that already exist in the controller.

Unknown recipe IDs fail catalog validation.

## Adding a recipe

A recipe is a code change, not configuration-only expansion. It must:

- have a fixed recipe ID;
- construct argv in controller code;
- validate every model-controlled parameter;
- avoid shell interpolation;
- preserve the live Work Order lease;
- scrub secrets;
- remain inside the helper worktree/sandbox;
- revalidate changed paths;
- emit exact command/exit evidence;
- have regression tests.

## Rollback

The 5.4 worker is layered on the deterministic 5.3.1 transformer. If 5.4 must be rolled back, point the stable `tool/kris_qwen_worker_v53.py` and legacy compatibility entry back to `tool/kris_qwen_worker_v531.py` and restore the matching installer/version checks. Mission Runtime and Product source do not need to be rewritten merely to roll back the engineering-environment layer.
