# Kristin P2 parallel-build handoff validation

## Package validation

- P2 task graph contains exactly P2-001 through P2-014.
- P2 dependencies, required outputs, acceptance conditions, and aggregate exit gate are recorded.
- All four shell scripts pass `bash -n`.
- All JSON files parse and required bundle entries are present.
- ZIP extraction/integrity test passes.
- SHA-256 checksum is generated for the final ZIP.

## Synthetic Git/worktree validation

A disposable bare remote, protected-main branch, and complete P1 closure branch were created. The bootstrap script then:

1. selected the remote P1 closure branch;
2. verified P1-001 through P1-012 completed packets;
3. created `integration/p2-full-train-wip`;
4. created a separate P2 worktree;
5. pushed the side branch;
6. preserved the operator checkout HEAD, branch, and status.

The source collector then created a full `git archive` ZIP and source-state Markdown/JSON files for the exact P2 branch commit.

## Rebase launcher validation boundary

The rebase launcher passes shell syntax validation and contains fail-closed checks for:

- final P1 aggregate evidence;
- completed P1-001 through P1-012 packets;
- tracked `tasks/active/.gitkeep`;
- exact successful Windows/macOS/Linux CI for the final main SHA;
- clean P2 worktree;
- P1 exit gate and strict roadmap validation after rebase;
- `--force-with-lease` rather than unconditional force push.

Live rebase execution is intentionally deferred until P1 has merged, because the final protected-main SHA does not yet exist.
