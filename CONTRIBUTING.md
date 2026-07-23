# Contributing

Changes that introduce an external effect must route through the governed runtime and include a permission mapping, project-boundary check, budget, cancellation behavior, redaction behavior, audit/evidence event, deterministic verification, and tests. UI or API code may not call filesystem, process, network, secret, MCP, or deployment primitives directly.

Before submitting a change:

```bash
./tool/bootstrap_platforms.sh
./tool/verify.sh
python3 tool/secret_scan.py
python3 tool/release.py --output-dir dist
```

Never commit real credentials, private project samples, support bundles from users, model transcripts, generated checkpoints, or product-state directories. Security-sensitive changes require threat-model updates.
