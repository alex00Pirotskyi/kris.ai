# Threat Model

## Protected assets

Project source, user conversations, named secret values, API bearer tokens, model endpoints, local filesystem integrity, developer accounts, deployment artifacts, audit history, support bundles, and workstation availability.

## Adversaries and failures

- Malicious or compromised project content attempting prompt injection.
- Hostile web pages, package metadata, tool output, MCP responses, or A2A responses.
- A model emitting unsafe, malformed, stale, or over-broad actions.
- A local web page attempting cross-origin access to the loopback API.
- A leaked or replayed API token.
- Symlink and path traversal attacks.
- SSRF through DNS, redirects, encoded addresses, or URL credentials.
- Dependency, MCP, A2A, or manifest supply-chain substitution.
- A forged signed manifest or source-update descriptor attempting to act as a trust root.
- Process escape, shell injection, unbounded output, hangs, and orphan processes.
- Crash or power loss during mutation or state transitions.
- Accidental support-bundle disclosure.

## Controls

Controls include explicit project registration, canonical roots, granular consumable grants, exact model identity, task-scoped tools, budgets, array-based process execution, minimum environments, SQLite checkpoints and idempotency, bounded network retrieval, executable hash pins, untrusted-data labeling, redaction, loopback-only API, exact CORS, token hashes/expiry/scopes, audit chaining, deterministic verification, and fail-closed restart reconciliation.

The current source also keeps the v1 signed-manifest trust path disabled and does not claim Signed Manifest v2 yet.

## Residual risk

No local agent can make arbitrary third-party code trustworthy. The Linux reference worker does not make Windows or macOS isolated today, and approved child processes can still use the desktop user's authority. Users should review dependency locks and deployment permissions, keep external accounts protected by MFA, review support bundles before disclosure, and verify release artifacts in an isolated CI environment. A local model can still produce incorrect code; deterministic tests and human approval remain necessary for high-impact systems.
