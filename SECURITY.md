# Security policy

## Supported release

Security fixes in this package target Kristin Local Agent **v1.5.0+150** and its preserved v1.3 durable workflow, v1.2 typed protocol, and v1.1.7 replay baselines. Historical migration material is unsupported and excluded from clean release packages.

## Reporting a vulnerability

Do not include production credentials, private source code, personal data, or active exploit payloads in a public issue. Provide the affected version, operating system, reproduction steps using synthetic data, expected and actual behavior, and the smallest safe diagnostic excerpt. Rotate any credential that may have been exposed.

## Enforced or materially implemented controls

- The local HTTP API binds to loopback and does not grant wildcard browser origins.
- Bearer token plaintext is shown once; persisted token records use hashes, scopes, expiry, revocation, and optional project binding.
- Settings use named secret references; runtime outputs pass through bounded pattern redaction.
- Project file tools enforce canonical project boundaries; traversal, schemes, NUL values, external writes, and symlink or reparse escapes remain blocked.
- Provider responses become typed decisions, and all 23 governed tools validate strict input and output contracts before evidence is trusted.
- Missing mutation arguments, conflicting aliases, undeclared authority fields, invalid tool evidence, and unsafe path representations fail closed.
- Prompt Studio 2 validates product specifications and 1–100-task plans before runtime preparation. Unknown tools, missing capabilities, duplicate IDs, dangling references, graph cycles, unsupported external claims, missing artifact validators, unresolved acceptance evidence, unapproved self-modification, and fabricated human workflows fail closed.
- The v1.5 compiler does not claim v1.4 sandboxing. Process-, network-, MCP-, deployment-, and other sandbox-dependent tasks are blocked by default when the sandbox is unavailable.
- The legacy unsandboxed dry-run override must be explicit, creates a warning and approval requirement, and never represents itself as isolation or execution permission.
- Mutable product state and workflow history use SQLite transactions, WAL, FULL synchronization, append-only run events with payload hashes, durable idempotency records, leases, checkpoints, compensation records, and startup integrity checks.
- Governed file mutation recovery uses before and after hashes, backups, prepared/applied/committed states, and conflict-aware restart reconciliation.
- Ambiguous or non-compensatable external effects are not automatically repeated after a crash.
- Network research requires explicit scope; HTTPS, URL-credential rejection, address screening, redirect revalidation, response limits, and redaction are enforced where implemented.
- Retrieved content, prompts, plans, compilation reports, and run memory are evidence or proposals, not authority to expand permissions, project roots, budgets, secrets, sandbox state, or MCP trust.
- Release packaging uses deterministic ZIP metadata, complete manifests, source policy, SBOM generation, and bounded secret scanning.

## Known security limits

- **The OS sandbox workers, network broker, secret broker, and platform backends planned for v1.4 are not implemented in this release.**
- Approved child processes, interpreters, MCP servers, and format workers retain the desktop user's operating-system privileges.
- The explicit legacy unsandboxed override is compatibility-only and should not be used for untrusted projects.
- Durable replay is strongest for hash-observable local file mutations. Commands, deployments, network calls, and MCP effects can become uncertain after a crash and require independent reconciliation.
- DNS validation is not pinned through connection establishment, leaving a rebinding hardening gap.
- Run-event payload hashes and audit records are not externally signed or anchored.
- Support and log redaction is pattern-based and can retain ordinary source, prompts, paths, project names, URLs, or personal information.
- Static prompt and plan evaluation does not prove semantic correctness, artifact safety, or downstream model behavior.
- Native platform compilation, sandbox escape tests, installer checks, and security red-team gates require configured target systems.

See `docs/SECURITY_MODEL.md`, `docs/THREAT_MODEL.md`, `docs/V1.5.0_PROMPT_STUDIO_2_PLAN_COMPILER.md`, and `docs/ROADMAP_IMPLEMENTATION_MATRIX.md` before handling untrusted projects or sensitive data.

## Operator response

For suspected compromise: stop active runs and managed processes, stop the local API, revoke API tokens and MCP trust records, clear session secrets, rotate external credentials, preserve and inspect SQLite state, logs, audit records, and run evidence, compare project files with trusted version control, restore from known-good state, and regenerate deployment artifacts. Do not retry an operation whose external outcome is uncertain until its state is independently reconciled.
