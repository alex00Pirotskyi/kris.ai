# Kristin Local Agent v1.9.0+190 Validation Report

Classification: **source-release**

| Gate | Status | Blocking | Detail |
|---|---:|---:|---|
| required product files | passed | yes | all required files present |
| active source-tree layout | passed | yes | only the governed product source and current tests are analyzer-visible |
| Dart syntax, active-source allowlist, and local imports | passed | yes | checked 53 allowlisted Dart files using lexical fallback |
| single governed architecture | passed | yes | active entry and capability boundary verified |
| security invariants | passed | yes | high-risk static invariants verified |
| reported Flutter/Dart analyzer regressions | passed | yes | reported compiler/analyzer regressions remain patched in the active v1 source |
| Chat Workspace UX and progressive disclosure | passed | yes | chat-first navigation, inline plans, project diagnostics, observable runs, Prompt Studio, knowledge, skills, logs, and advanced settings are present |
| v0.9 research archive, cited retrieval, and run memory | passed | yes | immutable research provenance, content-addressed objects, hybrid citations, episodic memory, export, UI, API, CLI, and tests are wired |
| v0.9.3 memory relevance and execution reliability | passed | yes | failed run memory is opt-in, greetings are model-only, model envelopes and safe aliases normalize through the work-item allowlist, repairs are consecutive, diagnostics are inspectable, and Ollama uses bounded streaming |
| v1.2 typed AgentDecision and JSON Schema tool foundation | passed | yes | 23 governed tools and five decision variants share generated contracts; provider envelopes are normalized outside the coordinator; inputs fail closed before dispatch; outputs are schema checked; 2,000 deterministic protocol fuzz cases pass |
| v1.3 durable workflow kernel | passed | yes | 14/14 executable SQLite crash, append-only, idempotency, migration, concurrency, recovery, and compensation cases passed |
| v1.5 Prompt Studio 2 schemas, compiler, dry run, and evaluation | passed | yes | 30/30 executable cases passed; canonical 1/10/50/100-task plans compile deterministically; prompt impact +75.0; sandbox-dependent work fails closed; runtime, API, and CLI are integrated |
| v1.5.1 Linux sandbox backfill | passed | yes | Linux namespace worker, HTTPS broker, one-use secret broker, and sandbox-aware CLI routing are integrated without falsely claiming the full cross-platform v1.4 milestone |
| v1.6 Project Manager 2 operational layer | passed | yes | 16/16 executable cases passed; strict profiles, live sandbox readiness, retained snapshots, PID-reuse-safe complete-tree Run/Stop, parent-death cleanup, artifacts, and packaging are integrated |
| v1.7 model router, verifier, and convergence engine | passed | yes | 40/40 executable cases passed; local-first role routing, circuit breakers, semantic progress, bounded strategy escalation, independent verification, phase budgets, and compaction are integrated |
| v1.8 knowledge, memory, skills, object store, and freshness | passed | yes | 12/12 executable cases passed; content-addressed object storage, memory admission and quarantine, explicit skill publication, and freshness/citation controls are integrated |
| v1.8 core file adapters | passed | yes | 14/14 executable cases passed; native and sandboxed-core adapters detect, inspect, and reopen supported files with bounded validation |
| v1.9 interoperability, administration, and release operations | passed | yes | 22/22 executable cases passed; typed MCP manifests, bounded A2A delegation, signed capability manifests, audit verification, and authenticated source-update policy are integrated |
| v1.9 deep release operations and audit verification | passed | yes | 10/10 executable cases passed; policy overlays, audit-chain verification, authenticated update manifests, and rollback compatibility enforcement are integrated |
| golden diagnostic replay and v1.1.7 convergence contracts | passed | yes | 2/2 compact production failures replayed; historical model latency represented=36.578 minutes |
| v1 Prompt-to-Task product preview and path compatibility | passed | yes | AI prompt drafts, immutable versions, adaptive 1-100 task plans, selective dependency-aware execution, stop controls, cold-model prewarm and retry, model cancellation, capability-safe task normalization, system/release tests, safe path handling, budget-aware linked retries, loop guards, and redacted all-logs diagnostics are wired |
| release tree hygiene | passed | yes | no symlinks or oversized source files; generated Flutter/native state is excluded by shared policy |
| release supply-chain evidence | passed | yes | SBOM generated and secret scan passed |
| dart format | unavailable | no | SDK checks disabled by source-only validation invocation |
| flutter pub get | unavailable | no | SDK checks disabled by source-only validation invocation |
| flutter analyze | unavailable | no | SDK checks disabled by source-only validation invocation |
| flutter test | unavailable | no | SDK checks disabled by source-only validation invocation |

A source release has passed deterministic architecture and security gates. It is not a compiled desktop release unless Flutter dependency resolution, analysis, tests, and platform builds also pass in the target environment.
