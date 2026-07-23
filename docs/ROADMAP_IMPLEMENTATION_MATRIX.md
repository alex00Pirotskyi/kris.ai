# Product-Grade V2 implementation matrix — canonical v1.9.0+190

## Canonical position

Kristin is back on one cumulative source line through the roadmap-defined v1.9 milestone. The manifest-verified v1.8 archive is the direct source parent; v1.9 adds typed interoperability, administration, audit, and release-governance capabilities on top of the v1.2–v1.8 foundation.

## Implemented cumulative foundation

| Roadmap milestone | Status in this source | Primary evidence |
|---|---|---|
| v1.1.7 replay baseline | Implemented | `tool/replay_diagnostics.py`, two production fixtures |
| v1.2 typed protocol | Implemented | five decisions, four adapters, 23 input/output tool contracts, 2,000 fuzz cases |
| v1.3 durable kernel | Implemented and extended to schema 6 | six migrations, 14 crash/recovery/concurrency cases |
| v1.4 sandbox and brokers | Linux reference slice implemented; cross-platform gate incomplete | namespace worker, HTTPS broker, one-use secret broker |
| v1.5 Prompt Studio 2 | Implemented | five contracts, 1/10/50/100 task plans, 30 cases |
| v1.6 Project Manager 2 | Source operational layer implemented | strict profiles, live readiness, snapshots, durable processes/artifacts, 16 cases |
| v1.7 router/verifier/convergence | Implemented | routing, circuits, semantic progress, strategy escalation, objective verification, 40 cases |
| v1.8 knowledge/memory/skills/adapters | Implemented | object store, admission/quarantine, freshness, skill publication, core file adapters |
| v1.9 interoperability/admin/release ops | Implemented source-side | typed MCP manifests, bounded A2A, signed capability manifests, audit-chain verification, policy/fleet profiles, authenticated update-policy verification, 22 cases |

## Current v1.9 exit-gate assessment

| Roadmap v1.9 exit gate | Status | Evidence/qualification |
|---|---|---|
| Plugin and agent identities are verifiable | Implemented | signed capability manifests verify deterministically and tamper/unknown-signer cases fail closed |
| Upgrades and rollbacks pass on all supported systems | Partially implemented, not fully qualified | authenticated source-update manifests and rollback-policy verification are implemented, but native installers and platform update application remain out of scope in this environment |
| Audit-chain break is detected | Implemented | append-only audit verification passes and tampering is detected deterministically |
| External delegation cannot exceed the task contract | Implemented | A2A contracts bound capabilities, artifacts, data boundary, payload size, and turns |

## Security and platform qualification

Implemented:

- Linux project-command isolation;
- no-network worker mode;
- public HTTPS broker with private-address rejection;
- one-use secret delivery;
- bounded process resources and logs;
- process-group Stop;
- fail-closed readiness;
- signed manifest verification;
- audit-chain verification;
- policy/fleet overlay validation;
- authenticated update-policy verification.

Still incomplete:

- native Windows isolated worker;
- native macOS isolated worker;
- worker-to-host preview port publication;
- signed desktop installers;
- platform updater execution and rollback;
- native Flutter UI integration tests.

## Next roadmap step

The roadmap is now complete through **v1.9.0**. The next canonical step is not a new feature milestone but the **v2.0 GA acceptance program**: finish the remaining platform, installer, upgrade/rollback, audit, cross-platform worker, and desktop workflow gates before claiming product-grade general availability.
