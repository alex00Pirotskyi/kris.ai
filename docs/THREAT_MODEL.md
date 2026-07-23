# Threat Model

## Protected assets

Project source, user conversations, named secret values, API bearer tokens, model endpoints, local filesystem integrity, developer accounts, deployment artifacts, audit history, and availability of the workstation.

## Adversaries and failures

- Malicious or compromised project content attempting prompt injection.
- Hostile web pages, package metadata, tool output, or MCP responses.
- A model emitting unsafe, malformed, stale, or over-broad actions.
- A local web page attempting cross-origin access to the loopback API.
- A leaked or replayed API token.
- Symlink and path traversal attacks.
- SSRF through DNS, redirects, encoded addresses, or URL credentials.
- Dependency or MCP supply-chain substitution.
- Process escape, shell injection, unbounded output, hangs, and orphan processes.
- Crash/power loss during mutation or state transitions.
- Accidental support-bundle disclosure.

## Controls

Controls include explicit project registration, canonical roots, granular consumable grants, exact model identity, task-scoped tools, budgets, array-based process execution, minimum environments, transaction checkpoints, stale hashes, bounded network retrieval, executable hash pins, untrusted-data labeling, redaction, loopback-only API, exact CORS, token hashes/expiry/scopes, audit chaining, deterministic verification, and fail-closed restart reconciliation.

## Residual risk

No local agent can make arbitrary third-party code trustworthy. Users should review dependency locks and deployment permissions, run generated services with least operating-system privilege, keep external accounts protected by MFA, and verify release artifacts in an isolated CI environment. A local model can still produce incorrect code; deterministic tests and human approval remain necessary for high-impact systems.
