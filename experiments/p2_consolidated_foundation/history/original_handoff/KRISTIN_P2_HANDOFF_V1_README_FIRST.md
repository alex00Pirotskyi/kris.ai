# Kristin P2 parallel-build handoff

This bundle is for a **new ChatGPT conversation** that will build the complete P2 integration train in parallel while the current conversation finishes the P1 closure.

It does not claim that P1 is already merged. The current protected main contains P1-001 through P1-003. The complete P1 implementation exists on `integration/p1-full-closure-v54`; V55 repairs clean-clone preservation of `tasks/active` before that branch can merge.

## Intended workflow

1. Finish or continue V55 in the original conversation.
2. Create a separate P2 worktree and side branch with `bootstrap_kristin_p2_side_branch.sh`.
3. Produce a complete tracked-source snapshot with `collect_kristin_p2_source_snapshot.sh`.
4. Upload this handoff ZIP and the generated source-snapshot ZIP to a fresh ChatGPT conversation.
5. Paste the contents of `P2_NEW_CHAT_PROMPT.md` into that conversation.
6. Build P2 on the side branch, without merging it while P1 is unresolved.
7. After P1 is merged and exact tri-OS main CI is green, run `rebase_kristin_p2_after_p1.sh`.
8. Complete the final P2 integration package, one PR, protected-main merge, and exact merged-main CI.

## Commands

```bash
cd /c/dev/flutter

bash ./bootstrap_kristin_p2_side_branch.sh \
  --repo /c/dev/flutter/kris_studio_ai_2 \
  --worktree /c/dev/flutter/kris_studio_ai_2_p2 \
  --branch integration/p2-full-train-wip \
  --push

bash ./collect_kristin_p2_source_snapshot.sh \
  --repo /c/dev/flutter/kris_studio_ai_2 \
  --ref integration/p2-full-train-wip \
  --output-dir /c/dev/flutter/p2_new_chat_context
```

Upload to the new chat:

- `KRISTIN_P2_PARALLEL_BUILD_HANDOFF_V1.zip`
- the generated `KRISTIN_P2_SOURCE_SNAPSHOT_<sha>.zip`
- optionally the generated source-state Markdown and JSON files

## Hard rules

- P2 is one governed integration train, not fourteen unreviewed merges.
- All P2-001 through P2-014 task-level requirements, tests, evidence, and dependency gates remain mandatory.
- Do not merge P2 before final P1 is on protected main and its exact Windows/macOS/Linux CI is green.
- Do not bypass Access Profile v2, Capability Grant v2, the deterministic policy engine, Signed Manifest v2, key revocation, signed audit checkpoints, or authenticated local IPC.
- Owner Mode is intentionally broad authority and must never be mislabeled as a sandbox.
- Untrusted content, model output, environment variables, or workers cannot grant or widen authority.
- The ordinary operator checkout must remain unchanged by integration launchers.
