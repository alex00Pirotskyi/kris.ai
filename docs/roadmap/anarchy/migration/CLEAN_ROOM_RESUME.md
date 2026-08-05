# P24-001 clean-room Worker J resume contract

**Classification:** `PUBLISHED_EXACT_HEAD_REPAIR_IN_PROGRESS`

The committed regression `test_clean_room_worker_j_resume_uses_repository_only` creates a fresh copied checkout containing only repository state and invokes the Worker J resume contract without conversation history, local packages, or hidden notes.

It must discover:

- human authority `docs/roadmap/MASTER.md`;
- machine authority `docs/roadmap/roadmap.yaml` within its declared scope;
- Worker J role and active P24-001 claim;
- existing branch `agent/j/P24-001-roadmap-as-data-adr` and draft PR #66 context;
- exact Git head/tree when available;
- claimed and shared paths;
- required tests and exact-head workflow;
- Worker B and Worker I review blockers;
- the current P24 tri-platform repair/closure action.

It must not instruct Worker J to create the branch, open the PR, or publish the already-published `171053b2...` candidate. The repository-derived next action is to inspect the repaired exact-head P24/product-gates runs, commit only generator-produced index/manifest closure when needed, and request independent reviews only after green CI.

Exact-head CI and the final pushed-state clean-room observation remain adoption-review gates. A clean-room PASS does not adopt PR #63, complete P24-001, complete P2 behavior, or confer product/release support.
