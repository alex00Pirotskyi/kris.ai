# Kristin interoperability security boundary

This document is the operator-facing contract for P7. It describes the versions, trust boundaries, isolation rules, data handling, and revocation behavior implemented by the repository. It does not replace platform behavioral evidence or an independent penetration test.

## MCP

Kristin trusts MCP servers by exact executable path, executable SHA-256, project identity, exact tool allowlist, protocol revision, creation time, expiry, and revocation state. Unknown or draft protocol revisions fail closed.

The current stable MCP revision in source is `2026-07-28`. The compatibility registry also recognizes `2025-11-25`, `2025-06-18`, `2025-03-26`, and legacy `2024-11-05`. A trust record pins one accepted revision; runtime negotiation cannot silently widen it.

A server executable that disappears or changes digest is rejected until explicitly re-approved. MCP arguments containing NUL are rejected. Runtime environment variables are scrubbed. Calls are limited to the exact trusted tool set and project. Server output is labelled `untrusted_mcp_output`, redacted before audit persistence, and cannot grant itself more authority.

Revoking a trust closes its live session and persists a revocation timestamp. Expired or revoked trust cannot be used.

## A2A

Kristin's P7 adapter pins `A2A-Version: 1.0`. Agent cards must declare the pinned version, stable identity, endpoint, at least one skill, and an explicitly supported authentication scheme. Task states include `submitted`, `working`, `input_required`, `completed`, `failed`, `canceled`, and `unknown`.

Streaming task snapshots require monotonically increasing revisions. A terminal task cannot later change terminal state. Disconnecting before a terminal state produces `unknown`, never false completion.

The execution bridge no longer accepts `KRISTIN_A2A_TARGET_JSON`; raw environment data cannot select an executable. An agent is resolved from a Signed Manifest v2 registry under trust domain `kristin.a2a` and intended use `a2a_agent_registry`. The signed descriptor fixes executable, working directory, capabilities, timeout, and output limits. Its canonical SHA-256 is verified before execution.

Each delegation grant is bound to an exact agent ID, task ID, capability set, deadline, timeout, and output limit. The request must be a subset of both the grant and the registered descriptor. Cascading delegation is disabled at the bridge. Agent stdout must be a bounded JSON object; arbitrary text is not promoted to trusted control data.

## Plugins and skills

Plugin/skill installation uses Signed Manifest v2 under trust domain `kristin.extensions` and intended use `kristin_extension`. The signed payload fixes publisher identity, extension identity, version, code digest, test digest, exact requested capabilities, compatibility declarations, and entry point.

Code and test digests are compared against the installed payload before registration. Installation does not implicitly enable an extension. Operators can inspect, enable, disable, and revoke. A revoked identity cannot be re-enabled or silently reinstalled under the same identity.

## Owner Mode and privileged host effects

MCP, A2A, plugins, and skills do not bypass P1/P2 authority. Privileged host effects remain subject to the authority-service and Owner Mode policy boundary. Production Owner Mode must remain unavailable when the P1A connector is missing, invalid, behaviorally uncertified, or not live-probe eligible.

`tool/p1a_install_doctor.py` distinguishes missing install, invalid install, installed-but-evidence-ineligible, and evidence-eligible configuration. It never edits completion flags. Production activation is performed only by the controlled P1A activation path after the signed aggregate evidence passes.

## Data retention and privacy

Interop audit records contain identities, capability names, protocol versions, redacted arguments, and hashes of redacted responses where applicable. Raw project/page/prompt content is not required for release telemetry. P8 telemetry is opt-in, uses an attribute allowlist, hashes sensitive identifiers, supports preview/export/delete, and declares `contentCollection: false`.

Operators should treat all MCP/A2A/extension output as untrusted input until product policy and independent evidence verify the requested postcondition.

## Revocation and incident response

1. Revoke the MCP trust, A2A registry identity, or extension identity immediately.
2. Stop active sessions/tasks and mark unresolved external effects `unknown` or `reconciliation_required` rather than retrying them.
3. Preserve redacted audit and trace receipts.
4. Rotate affected trust keys or service identities when compromise is suspected.
5. Re-run the interoperability adversarial suite, secret scan, dependency policy, and failure replay corpus before restoring trust.
6. Do not clear an independent-review or penetration-test blocker by editing evidence files.
