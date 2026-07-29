# Security and completion boundaries

This directory is a quarantined source library.

## Never promote directly

The following reference areas must not be copied into production without fresh review and exact tests:

- authority/IPC adapters;
- worker launch and identity assumptions;
- runner attestation and cleanup logic;
- evidence finalizers and task promotion gates;
- CI workflow definitions;
- package/service/clipboard/screen completion claims;
- technology-spike completion claims.

## Excluded from this consolidation

- all P1A authority-service source and private-key/broker material;
- live product/runtime/UI patches;
- live `.github` workflow installation;
- live roadmap/evidence/task-completion changes;
- PR or merge automation.

## Required trust direction

```text
P1A isolated authority → typed one-use authorization → restricted P2 worker
```

Never reverse this direction or allow the worker to mint authority.
