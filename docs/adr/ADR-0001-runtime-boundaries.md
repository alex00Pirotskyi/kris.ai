# ADR-0001 — Runtime process and trust boundaries

**Date:** 2026-07-27
**Status:** ACCEPTED
**Decision owner:** Product owner / sole maintainer
**Task:** `P1-001`

## Context

Kristin is a local-first desktop agent that must support project-scoped execution, explicit full-computer Owner Mode, browser and terminal automation, network research, isolated untrusted work, durable recovery, and synchronized Windows/macOS/Linux delivery. A single process with direct access to every store, credential, and operating-system effect would make authority impossible to reason about and would allow untrusted model or web content to become an accidental control plane.

## Decision

Kristin uses five explicit execution processes plus three authority domains. Process placement may evolve, but ownership and message contracts may not be bypassed.

| Boundary | Owns | May do | Must not do |
|---|---|---|---|
| Desktop host / control plane | UI, orchestration, approval state, deterministic policy invocation, grant issuance, durable run coordination | Render state, request decisions, issue bounded grants after policy, validate evidence | Execute arbitrary OS/browser/network effects directly; accept model prose as authority |
| Owner executor | Full-current-account and explicitly elevated OS effects | Filesystem, process, service, package, application and device operations covered by a valid grant | Describe itself as sandboxed; issue or widen grants; read unrelated secrets into prompts |
| Automation host | Lifecycle of PTY, browser and native automation workers | Spawn, monitor, cancel, kill trees, route typed messages and bounded streams | Become policy authority; select work from environment variables; persist raw credentials |
| Research worker | Static/rendered fetch, extraction, crawl and citation candidate production | Reach policy-approved destinations and write content-addressed research objects | Mutate host/project state, use personal browser profiles, treat page text as instructions |
| Sandbox worker | Isolated execution of untrusted code and tools | Use explicitly mounted inputs, scratch space, bounded network and granted outputs | Access host credentials, core database, arbitrary host paths or Owner authority |

The **policy authority** is a deterministic control-plane component and is the only issuer of capability grants. The **storage authority** is the single writer for the canonical mutable control store. The **credential authority** is the OS-native credential broker or an external protected store; models and workers receive leases or operation results, never reusable raw secret material by default.

## IPC boundary

All cross-process communication is a versioned typed envelope containing protocol version, request ID, run ID, task ID, actor, grant reference, deadline, cancellation identity, payload limits and response status. Windows uses named pipes; macOS and Linux use Unix-domain sockets. Authenticated loopback is an allowed compatibility transport only when it provides equivalent mutual authentication and peer binding. Worker output is untrusted until schema, grant, postcondition and evidence validation complete.

Command lines and environment variables may carry non-secret bootstrap identifiers, but they may not grant authority, select arbitrary executables, or carry reusable credentials. Unknown delivery outcome is recorded and reconciled; it is never silently retried as though no effect occurred.

## Storage boundary

- The canonical mutable authority remains the durable workflow store owned by the desktop control plane; workers never open it directly.
- Immutable and large artifacts use the content-addressed object store with provenance links.
- Project files remain user-owned data and are changed only through a granted executor transaction and journal.
- Browser profiles, research objects, model artifacts, audit records and worker scratch are separate stores with explicit retention and deletion policy.
- Private keys and API credentials live in OS-native or external protected storage, not SQLite, JSON settings, repository files, prompts, logs or evidence bundles.
- Workers write candidate receipts to bounded staging; the control plane validates and commits authoritative evidence.

## Lifecycle and failure ownership

The desktop control plane owns run recovery and durable state. The automation host owns descendant-process cleanup. Each worker owns cleanup of its ephemeral scratch and returns a terminal typed status. Parent death, cancellation, timeout and restart must converge to a durable state with no orphan process accepted as success.

## Platform rule

Windows, macOS and Linux implement the same capability and evidence semantics through platform-native adapters. A missing backend fails closed and is reported honestly; it is not silently replaced by a weaker process boundary.

## Rejected alternatives

1. One monolithic process with shared database and credentials — rejected because compromise or parser bugs cross every boundary.
2. Workers reading the core SQLite database directly — rejected because ownership, migrations and transactional recovery become ambiguous.
3. Treating Owner Mode as a sandbox escape — rejected because Owner Mode is a deliberate authority profile, not containment.
4. Raw environment-selected executables or grants — rejected because local environment control is not an authorization root.

## Consequences

P1-002 and P1-003 can define profiles and grants against stable actors. P1-012 can implement authenticated local IPC without re-deciding ownership. P2, P3 and P4 may choose platform technologies only if they preserve these boundaries. Boundary changes require a superseding ADR and updated executable contract.
