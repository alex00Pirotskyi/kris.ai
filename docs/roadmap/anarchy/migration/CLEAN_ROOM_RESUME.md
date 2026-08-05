# P24-001 clean-room Worker J resume observation

**Classification:** `LOCAL_PRE_PUSH_OBSERVATION`

The committed test `test_clean_room_worker_j_resume_uses_repository_only` creates a fresh copied checkout containing only repository state and invokes the Worker J resume contract without conversation history or uncommitted notes.

It must discover:

- human authority `docs/roadmap/MASTER.md`;
- machine authority `docs/roadmap/roadmap.yaml`;
- Worker J role and branch;
- active P24-001 claim;
- exact Git head/tree when available;
- claimed/shared paths;
- required tests and CI workflow;
- missing Worker B/Worker I review blockers;
- one next action containing the stacked draft PR step.

The local regression passed before the first candidate push. Exact-head CI and final pushed-state clean-room evidence remain separate adoption gates.
