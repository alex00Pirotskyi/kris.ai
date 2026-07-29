# Kristin P2 consolidated source foundation V2

This repairs the V1 application failure. V1 preserved reference `.dart` files directly under `experiments/`, causing the governed source validator to treat them as active application code. V2 stores the exact reference tree in a sealed deterministic ZIP instead.

## Safety boundary

The repository receives only:

- Markdown handoff/history;
- JSON task/provenance/archive manifests;
- `reference_archives/KRISTIN_P2_V62_REFERENCE_SOURCE.zip`;
- refreshed `SOURCE_MANIFEST.sha256`.

No P2 production path, workflow, roadmap completion, evidence finalizer, P1/P1A authority code, or completed task packet is installed.

## Existing failed V1 worktree

Use `repair-existing`. The launcher verifies the existing experiment tree byte-for-byte against the V1 package fingerprint before replacing it. Unknown edits fail closed.

## Fresh use

Use `apply-fresh` with a new branch/worktree only when no V1 worktree exists.

P2 remains 0/14 roadmap tasks DONE. The handoff reduces implementation planning to five workstreams without overclaiming completion.
