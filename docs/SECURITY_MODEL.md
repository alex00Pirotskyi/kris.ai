# Security model

This document describes the **current** controls for the reviewed `v1.9.0+190` source-release preview. It does not claim signed installers, authenticated update installation, unrestricted full-host Owner Mode, or cross-platform OS isolation that the source does not implement today.

## Authority model

The current source line remains **project-bound and governed**. Model output cannot mint authority or change project roots, scopes, budgets, expiry, sandbox state, provider trust, or release classification.

**Owner Mode is a roadmap target, not a current capability.** References to future full-computer access belong to the roadmap, not to the supported behavior of this source release.

## Platform execution boundary

- On Linux, a reference namespace worker plus HTTPS and one-use secret brokers are present in source and may be used when the host supports them.
- On Windows and macOS, native worker backends are not implemented and must fail closed rather than pretending isolation exists.
- Approved child processes, interpreters, and MCP servers still run with the desktop user's privileges.

## Secrets and credentials

Persistent settings store named secret references, not intended secret values. Values are resolved from the current session or environment when an approved action needs them. Logs and outputs pass through pattern-based redaction.

Redaction is defense in depth, not a guarantee. Operators should not paste secrets into prompts or project files and should review diagnostics before sharing them.

## Workspace files and mutations

Paths are interpreted relative to a registered project root and checked against traversal and symlink or reparse escape. Mutations can create checkpoints, use temporary replacement, record evidence, and attempt rollback.

Current limitations:

- expected content hashes are not enforced on every existing-file overwrite/delete path;
- the mutation journal does not durably cover every crash window before the first effect;
- Windows replacement can require deleting the destination before rename;
- project-path checks do not constrain what an approved child process can access using the desktop user's privileges.

## Processes, MCP, and A2A

Commands are argument arrays rather than shell strings, with allowlists/denylists, bounded output, timeouts for finite work, reduced environment inheritance, and tracked managed-process controls.

However, approved processes, interpreters, MCP servers, and A2A helpers are not placed in a cross-platform OS-enforced sandbox. Treat untrusted projects and third-party integrations as high risk until the later worker milestones are complete.

## Research

Research accepts HTTPS targets, rejects URL credentials, performs hostname/address screening, revalidates redirects, and bounds content, redirects, and elapsed work. Stored material is labeled untrusted external data.

The preview validates DNS results before the HTTP client's connection but does not pin the validated address through connection establishment. DNS rebinding therefore remains a known hardening item. Research archives can retain hostile content; retrieved passages are wrapped as data and cannot grant access.

## Knowledge and memory

Knowledge retrieval returns citations, hashes, trust labels, and record identifiers. External research is marked untrusted. Run memory is marked historical evidence, not a command. Neither can expand permissions, tools, project roots, secrets, network policy, MCP trust, or budgets.

Content-addressed objects reduce accidental duplication and provide hash identity; they do not encrypt data or prove the remote origin's authenticity. The derived semantic vector is deterministic local hashing, not a security classifier.

## Local API

The API binds to loopback. Browser access is limited to exact configured origins. Tokens are high entropy, shown once, stored as hashes, constant-time compared, scoped, expiring, revocable, and optionally project-bound. Request sizes and rates are bounded, and correlation IDs connect API requests to events and audit records.

Loopback is not equivalent to user isolation on a shared or compromised workstation. Protect token plaintext and the local account.

## Persistence and audit

SQLite is the authoritative local workflow store for mutable product and run state in this source line. It provides transactional run projection, append-only events, idempotency records, checkpoints, compensation records, and startup recovery. Derived indexes and archives still require reconciliation when a failure interrupts multi-step work.

The audit hash chain is tamper-evident against accidental modification but is not signed or externally anchored. A local actor with write access could rewrite or truncate it and recompute hashes unless a stronger anchor is added.

## Interoperability and updates

The legacy v1 signed-manifest trust path is disabled. Signed Manifest v2 is not yet implemented. The current source therefore does **not** provide a production external trust root for plugins, skills, A2A agents, or authenticated source updates.

## Packaging and support

Deployment packaging rejects symlinks and unsafe size limits, applies exclusions, performs pattern-based credential scanning, and creates manifests/SBOM metadata. It prepares an artifact; it does not authorize publication.

Support bundles and logs must be reviewed before sharing because pattern redaction may leave non-secret project source, prompts, paths, or personal information.
