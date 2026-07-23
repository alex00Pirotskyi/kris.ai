# Kristin Local Agent v1.3.0+130 durable workflow status

Classification: **validated source release**

## Decision

This release implements the Product-Grade V2 roadmap's durable-kernel milestone before adding OS sandboxing or broader autonomy. It retains the v1.1.7 production replay baseline and v1.2 typed protocol/tool contracts, then moves mutable runtime state and execution recovery to SQLite.

## Implemented controls

- SQLite authority for mutable entity/document repositories and run state;
- four contiguous reviewed migrations with generated hashes and drift rejection;
- WAL journaling, full synchronization, foreign keys, bounded writer waits, and immediate transactions;
- append-only run events committed transactionally with materialized run projections;
- durable task attempts, checkpoints, run leases, idempotency records, compensation records, migration ledgers, and recovery decisions;
- stable operation idempotency keys and durable replay of completed results;
- prepared-before-effect file mutation journaling and hash-based recovery/rollback;
- stale-run recovery that distinguishes committed completion from interruption;
- byte-exact legacy JSON backups and idempotent import;
- pre-startup database backup and restoration after any migration/import failure;
- SQLite-authoritative CLI inspection and diagnostic export.

## Available validation in this environment

- workflow-kernel executable cases: 14 passed, 0 failed;
- SQLite integrity: `ok`;
- compact production diagnostic replay: 2 passed, 0 failed;
- historical model latency represented: 2,194,657 ms (36.578 minutes);
- deterministic provider fuzz cases: 2,000;
- representative governed-tool output contracts: 23/23;
- deterministic offline system contracts: 31 passed, 0 failed;
- governed source-release checks: 19 passed, 0 blocking failures;
- secret scan: zero findings;
- generated migration and protocol registries: current.

Dart and Flutter are unavailable in the preparation environment. `dart format`, `flutter pub get`, `flutter analyze`, `flutter test`, native desktop builds, installer qualification, and platform security tests remain required on configured workstations before this can be classified as a compiled desktop release.

## Deferred boundary

V1.3.0 is not an OS sandbox release. Agent-controlled commands, managed processes, MCP servers, and future file adapters still execute with desktop-user privileges. Network and secret brokers, worker isolation, resource enforcement, and cross-restart process reconciliation are the v1.4.0 milestone.
