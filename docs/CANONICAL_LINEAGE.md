# Canonical Kristin source lineage

## Definitive head

The canonical cumulative source head is:

```text
Kristin Local Agent v1.9.0+190
Kristin_Local_Agent_v1.9.0_build190_interoperability_admin_release_ops
```

Its direct packaged parent is the real, reproducible v1.8 source release:

```text
Kristin_Local_Agent_v1.8.0_build180_knowledge_memory_skills_adapters.zip
SHA-256 eac7469a776c859b9d14ad6133d06093c43327f8f4579633615aa3129cca9bcc
```

## Consolidated milestone chain

| Milestone | Retained implementation |
|---|---|
| v1.1.7 | deterministic production-failure replay corpus |
| v1.2.0 | typed `AgentDecision` protocol and 23 generated tool contracts |
| v1.3.0 | SQLite workflow kernel, idempotency, checkpoints, compensation, recovery |
| v1.4 slice | Linux namespace worker, HTTPS broker, one-use secret broker |
| v1.5.0 | Prompt Studio 2 schemas, deterministic plan compiler, evaluation fixtures |
| v1.6.0 | strict project profiles, live sandbox readiness, retained snapshots, durable process and artifact records |
| v1.7.0 | role router, circuit breakers, semantic progress, convergence, independent verification, phase budgets, context compaction |
| v1.8.0 | object store, memory admission/quarantine, freshness, skill publication, core file adapters |
| v1.9.0 | typed MCP lifecycle, bounded A2A delegation, signed/authenticated manifests, audit verification, policy profiles, release/update governance |
| v1.9.0 | typed MCP lifecycle, bounded A2A contracts, signed capability manifests, audit verification, policy/fleet profiles, support compatibility, authenticated update manifests |

## Versioning rule from this point

Future development starts only from the v1.9.0+190 archive or its exact manifest-verified extraction. A report-only directory, an older source ZIP, or a branch without a package hash must not be promoted as the canonical head.

Every future release must update together:

- `pubspec.yaml`;
- `lib/product/domain.dart`;
- CLI and package constants;
- `VERSION_CONTROL.json`;
- workflow migration metadata;
- interoperability/admin contracts and tests;
- deterministic replay and milestone tests;
- package manifest, release metadata, and external checksum.
