# Security model

This document describes intended controls and the current preview boundary. It does not claim OS isolation that the source does not implement.

## Permission scopes

Scopes separate project reads, writes, deletes, tests, finite processes, managed processes, network research, dependency acquisition, named-secret use, MCP calls, and deployment packaging. A grant is bound to a project/prepared command, expires, and may be one-time. Model output cannot mint a grant or change its project, scopes, budget, or expiry.

## Secrets

Persistent settings store named secret references, not intended secret values. Values are resolved from the current session or environment when an approved action needs them. Logs and outputs pass through pattern-based redaction.

Redaction is defense in depth, not a guarantee. Operators should not paste secrets into prompts or project files and should review diagnostics before sharing them.

## Workspace files

Paths are interpreted relative to a registered project root and checked against traversal/symlink escape. Mutations can create checkpoints, use temporary replacement, record evidence, and attempt rollback.

Current limitations:

- expected content hashes are not enforced on every existing-file overwrite/delete path;
- the mutation journal does not durably cover every crash window before the first effect;
- Windows replacement can require deleting the destination before rename;
- project-path checks do not constrain what an approved child process can access using the desktop user's privileges.

## Processes and MCP

Commands are argument arrays rather than shell strings, with allowlists/denylists, bounded output, timeouts for finite work, reduced environment inheritance, and tracked managed-process controls.

However, approved processes and MCP servers are not placed in an OS-enforced sandbox. Interpreters and child processes can potentially access files, network resources, or operating-system capabilities available to the desktop user. Treat untrusted projects and third-party MCP servers as high risk until sandbox workers are implemented.

## Research

Research accepts HTTPS targets, rejects URL credentials, performs hostname/address screening, revalidates redirects, and bounds content, redirects, and elapsed work. Stored material is labeled untrusted external data.

The preview validates DNS results before the HTTP client's connection but does not pin the validated address through connection establishment. DNS rebinding therefore remains a known hardening item. Research archives can retain hostile content; retrieved passages are wrapped as data and cannot grant access.

## Knowledge and memory

Knowledge retrieval returns citations, hashes, trust labels, and record identifiers. External research is marked untrusted. Run memory is marked historical evidence, not a command. Neither can expand permissions, tools, project roots, secrets, network policy, MCP trust, or budgets.

Content-addressed objects reduce accidental duplication and provide hash identity; they do not encrypt data or prove the remote origin's authenticity. The derived semantic vector is deterministic local hashing, not a security classifier.

## Local API

The API binds to loopback. Browser access is limited to exact configured origins. Tokens are high entropy, shown once, stored as hashes, constant-time compared, scoped, expiring, revocable, and optionally project-bound. Request sizes/rates are bounded, and correlation IDs connect API requests to events and audit records.

Loopback is not equivalent to user isolation on a shared or compromised workstation. Protect token plaintext and the local account.

## Persistence and audit

Atomic JSON files serialize updates within a collection. They do not provide transactions across collections. Archive records, knowledge links, and episode/index updates can therefore be temporarily inconsistent after a crash and require reconciliation.

The audit hash chain is tamper-evident against accidental modification but is not signed or externally anchored. A local actor with write access could rewrite/truncate it and recompute hashes unless a stronger anchor is added.

## Packaging and support

Deployment packaging rejects symlinks/unsafe size limits, applies exclusions, performs pattern-based credential scanning, and creates manifests/SBOM metadata. It prepares an artifact; it does not authorize publication.

Support bundles and logs must be reviewed before sharing because pattern redaction may leave non-secret project source, prompts, paths, or personal information.
