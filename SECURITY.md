# Security policy

## Supported release line

This policy applies to **Kristin Local Agent v1.9.0+190** when the release classification remains **`source-release`** and `compiled_release_validated` remains `false`. Historical imported releases are reference material only; they are not the supported security target for new fixes.

A compiled artifact is not a supported production release unless a later reviewed package changes both the release metadata and the validation evidence to say otherwise.

## Current platform and authority truth

| Area | Linux | Windows | macOS |
|---|---|---|---|
| Governed project tools | Supported on a configured workstation | Supported on a configured workstation | Supported on a configured workstation |
| Linux namespace worker | Reference implementation present in source when host prerequisites are available | N/A | N/A |
| Native worker backend | N/A | **Not implemented; fail closed** | **Not implemented; fail closed** |
| Owner Mode / unrestricted full-host authority | **Not implemented in this release** | **Not implemented in this release** | **Not implemented in this release** |
| Signed installer / updater | Not included | Not included | Not included |

Kristin must not describe this source line as a full-host automation product, a hostile-code sandbox, or a signed desktop release.

## Interoperability and update trust freeze

- **v1 signed-manifest trust is disabled.** Do not re-enable or rely on the envelope-supplied HMAC verifier.
- **Signed Manifest v2 is not implemented yet.** Do not claim production manifest trust, signed plugin trust, signed A2A trust, or authenticated source-update trust beyond the currently reviewed local source line.
- MCP and A2A records in this source are governed local/runtime data, not a general-purpose external trust root.

## Enforced or materially implemented controls

- The local HTTP API binds to loopback and does not grant wildcard browser origins.
- Bearer token plaintext is shown once; persisted token records use hashes, scopes, expiry, revocation, and optional project binding.
- Settings use named secret references; runtime outputs pass through bounded pattern redaction.
- Project file tools enforce canonical project boundaries; traversal, schemes, NUL values, external writes, and symlink or reparse escapes remain blocked.
- Provider responses become typed decisions, and all 23 governed tools validate strict input and output contracts before evidence is trusted.
- Missing mutation arguments, conflicting aliases, undeclared authority fields, invalid tool evidence, and unsafe path representations fail closed.
- Prompt Studio 2 validates product specifications and 1–100-task plans before runtime preparation. Unknown tools, missing capabilities, duplicate IDs, dangling references, graph cycles, unsupported external claims, missing artifact validators, unresolved acceptance evidence, unapproved self-modification, and fabricated human workflows fail closed.
- Sandbox-dependent tasks are blocked by default when the sandbox is unavailable, and the legacy unsandboxed dry-run override remains explicit compatibility-only behavior.
- Mutable product state and workflow history use SQLite transactions, WAL, FULL synchronization, append-only run events with payload hashes, durable idempotency records, leases, checkpoints, compensation records, and startup integrity checks.
- Governed file mutation recovery uses before and after hashes, backups, prepared/applied/committed states, and conflict-aware restart reconciliation.
- Ambiguous or non-compensatable external effects are not automatically repeated after a crash.
- Network research requires explicit scope; HTTPS, URL-credential rejection, address screening, redirect revalidation, response limits, and redaction are enforced where implemented.
- Retrieved content, prompts, plans, compilation reports, and run memory are evidence or proposals, not authority to expand permissions, project roots, budgets, secrets, sandbox state, or MCP trust.
- Release packaging uses deterministic ZIP metadata, complete manifests, source policy, SBOM generation, and bounded secret scanning.

## Known security limits

- The Linux reference worker is present, but **Windows and macOS native worker backends are still absent and must fail closed**.
- Approved child processes, interpreters, MCP servers, and format workers retain the desktop user's operating-system privileges.
- The explicit legacy unsandboxed override is compatibility-only and should not be used for untrusted projects.
- Durable replay is strongest for hash-observable local file mutations. Commands, deployments, network calls, and MCP effects can become uncertain after a crash and require independent reconciliation.
- DNS validation is not pinned through connection establishment, leaving a rebinding hardening gap.
- Run-event payload hashes and audit records are not externally signed or anchored.
- Support and log redaction is pattern-based and can retain ordinary source, prompts, paths, project names, URLs, or personal information.
- Static prompt and plan evaluation does not prove semantic correctness, artifact safety, or downstream model behavior.
- Native platform compilation, sandbox escape tests, installer checks, and security red-team gates require configured target systems.
- Signed installers, notarization, authenticated updater execution, and Signed Manifest v2 remain future milestones.

## Reporting a vulnerability

Do not include production credentials, private source code, personal data, or active exploit payloads in a public issue. Provide:

- the exact Kristin version and branch/commit when known;
- the operating system and any relevant host prerequisites;
- synthetic reproduction steps;
- expected and actual behavior;
- the smallest safe diagnostic excerpt;
- whether a support bundle was reviewed locally before sharing.

Rotate any credential that may have been exposed. If a support or diagnostic ZIP is relevant, review it first and remove anything you do not intend to disclose.

## Operator response

For suspected compromise: stop active runs and managed processes, stop the local API, revoke API tokens and MCP trust records, clear session secrets, rotate external credentials, preserve and inspect SQLite state, logs, audit records, and run evidence, compare project files with trusted version control, restore from known-good state, and regenerate deployment artifacts. Do not retry an operation whose external outcome is uncertain until its state is independently reconciled.

See [`docs/SECURITY_MODEL.md`](docs/SECURITY_MODEL.md), [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md), [`docs/PRIVACY.md`](docs/PRIVACY.md), and [`docs/SUPPORT_POLICY.md`](docs/SUPPORT_POLICY.md) before handling untrusted projects or sensitive data.
