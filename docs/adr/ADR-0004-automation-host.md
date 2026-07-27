# ADR-0004 — Automation host and worker supervision boundary

**Date:** 2026-07-27
**Status:** ACCEPTED
**Decision owner:** Product owner / sole maintainer
**Task:** `P1-001`

## Context

Interactive terminal, browser automation, native desktop control and isolated execution require long-lived processes, streaming I/O, cancellation and platform-specific cleanup. Choosing Node, Rust or another host before measuring packaging and lifecycle behavior would create premature lock-in.

## Decision

Kristin has one technology-neutral **automation host boundary**. It is an out-of-process supervisor owned by the desktop control plane. It starts registered worker descriptors, binds each worker to a run/task/grant, provides bounded versioned IPC, streams redacted output, enforces deadlines, and terminates process trees on cancellation or parent death.

The automation host is not policy authority, storage authority, credential authority, or evidence authority. It cannot widen a grant, choose an arbitrary executable from environment data, open the core database, or mark task acceptance. It may cache non-authoritative health and routing metadata only.

PTY, browser, research, sandbox and future native-control workers implement separate descriptors and capability sets. P2-004 will select concrete host technology using measured startup, memory, packaging, Windows/macOS/Linux lifecycle reliability and process-tree control. That measurement may change the implementation language without changing this ADR's boundary.

## Failure semantics

- Start returns a stable worker identity or a typed failure.
- Every request has a request ID and explicit deadline.
- Cancellation and kill are idempotent.
- Ambiguous completion is recorded as unknown and reconciled.
- Worker stdout/stderr and protocol frames are separate bounded channels.
- A worker crash cannot promote partial output into authoritative evidence.
- Orphans after stop, timeout or desktop exit are release-blocking defects.

## Consequences

P2-004 may compare technologies without reopening authority ownership. P1-012 provides authenticated transport. P2/P3/P4 workers remain replaceable behind shared conformance tests.
