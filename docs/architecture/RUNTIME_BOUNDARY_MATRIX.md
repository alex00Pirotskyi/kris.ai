# Kristin runtime boundary matrix v1

This is a derived implementation view of `ADR-0001`, `ADR-0002`, and `ADR-0004`. The machine-readable authority is `config/runtime_boundaries.v1.json`.

```text
User / UI
  -> Desktop host and deterministic policy authority
       -> Owner executor (explicit high authority; not sandboxed)
       -> Automation host
            -> Research worker (untrusted network content)
            -> Sandbox worker (isolated untrusted execution)
            -> future PTY/browser/native workers

OS credential broker -> scoped operation/lease -> granted executor or worker
Desktop storage authority <-> durable workflow store and evidence ledger
Workers -> candidate receipts -> validation -> authoritative evidence commit
```

## Non-bypass rules

1. Models, prompts, web pages and worker output cannot issue grants.
2. Workers do not open the core database.
3. Owner Mode is explicit and never described as sandboxed.
4. IPC is authenticated, versioned, bounded and identity-bound.
5. Secrets remain in OS-native or external protected storage by default.
6. Windows, macOS and Linux preserve equivalent authority/evidence semantics.
