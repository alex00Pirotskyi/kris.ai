# P0-010 implementation

This milestone introduces generated-state policy v2 and a strict Git/source-manifest audit.

The applicator is cumulative-aware. It can run on the reviewed P0-001/P0-002 base or on a branch that also contains later P0 work. It preserves reviewed generated contracts and durable task evidence while removing disposable state such as Python bytecode, Flutter tool markers, timestamped test reports, and regenerated root release reports.

The applicator writes an external backup before deleting any path. It records every removed path, reason, size, and pre-removal SHA-256 under `removal_manifest.json`.

When the P0-009 benchmark exists, the applicator first proves the old baseline is current, then regenerates it after the policy change. A benchmark delta is accepted only when no previously passing case regresses and the generated-state path-policy case passes.

No Git history is rewritten. Deletions remain visible in the review diff until committed.
