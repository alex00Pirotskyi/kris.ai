# P6-001 — Model registry v2 source foundation

## Scope

This packet implements only P6-001. It adds a deterministic declarative catalog beside the existing runtime providers; it does not dispatch model requests or implement P6-002 routing.

The registry records provider/model identity, aliases, immutable artifact digest, parameter size, quantization, measured or unknown limits, tool profiles, data boundaries, direct invocation cost metadata, benchmark evidence, approved task classes, and non-secret credential references.

## Fail-closed invariants

1. An unregistered discovered model is created only as a non-persistent `evaluation_only` descriptor.
2. A canonical ID or alias reuses approval only when digest, parameter size, and quantization match exactly.
3. Approved records require a non-empty immutable artifact digest.
4. `requireApproved` requires the actual discovered `ModelIdentity`; mutable aliases or tags cannot authorize by string lookup alone.
5. Identity drift receives a deterministic quarantine ID, remains evaluation-only, and cannot pass `requireApproved` through that identity.
6. Quarantine IDs use deterministic base64url encoding within the model-ID character contract.
7. Identity validation lives inside the single exported `ModelDefinitionRegistry`; direct imports cannot bypass the check.
8. Invalid discovered provider/model IDs and unknown providers fail closed.
9. Every benchmark record carries the exact model artifact digest it measured.
10. Approved records reject benchmark evidence measured for another artifact digest.
11. JSON cannot relabel a model digest while retaining stale benchmark evidence from another artifact.
12. Evaluation-only records also reject cross-artifact benchmark evidence, and benchmark-bearing evaluation records require their own immutable artifact digest.
13. Approval requires measured limits, a measured tool profile, known cost metadata, and benchmark evidence for every approved task class.
14. Evaluation-only records cannot expose approved task classes.
15. Boundary mismatches, duplicate identities, duplicate aliases, and canonical-ID/alias collisions are rejected.
16. Credential records contain reference metadata only.
17. Serialization and quarantine identities are deterministic.

## Source and dependency reconciliation

Independent review of `9799768170f13556d3098a07b40be922377f8deb` identified `P6-C-001`: canonical names and aliases could inherit approval without matching artifact identity. That repair now resides in the core registry rather than a wrapper, closing direct-import bypasses.

A later product-first review identified a second source defect: benchmark evidence was task-class-bound but not artifact-bound. Before `b290d1a145a09cfbeead2e9d30fc651c2b2cae67`, measurements from digest A could be reused when constructing a registry record for digest B. `ModelBenchmarkEvidence.modelDigest` is now mandatory, construction and JSON ingestion fail closed on cross-artifact reuse, and direct regressions cover approved, direct-core, JSON relabeling, and evaluation-only paths.

`P6-C-002` identified incomplete authority coverage for Worker B Test Center files. Worker G now consumes Worker B source authority through true two-parent merge `4166abe8e66b43f4683a3fe9b5e75475adf999e5`:

- Worker G parent: `4515c66f857d61fc415f37e737c6926e716ef3b5`
- Worker B parent: `604905039aa26952045e69ebe6799ae464144635`
- merge tree: `7ff410b5606719a3f627ce6a5eea84eb4f2509dc`

Relative to that Worker B parent, the P6 branch is behind by zero commits and has no effective Test Center authority-file or root source-manifest diff. The remaining shared path is only the governed global Dart source inventory entry in `test/product/source_contract_test.dart`.

## Classification and non-claims

Classification: `SOURCE_FOUNDATION` / `evaluation-only by default`.

This packet does not implement role routing, live provider dispatch, compatibility certification, hardware acceleration, behavioral/platform support, release readiness, production readiness, or GA.

## Verification boundary

Focused test modules:

- `test/product/model/model_registry_test.dart`
- `test/product/model/model_registry_identity_guard_test.dart`
- `test/product/model/model_registry_public_contract_test.dart`

The current source/test candidate has not executed under Dart/Flutter in this worker environment, and GitHub allocated no exact-head workflow run for the changed P6 source. Historical green runs are not promoted to current validation.

`SOURCE_MANIFEST.sha256` is inherited from the current Worker B parent rather than carried as a Worker G diff, but it is not claimed current for the added P6 source/tests. It must be regenerated twice through `python tool/p1a_refresh_source_manifest.py .` in an executable canonical environment.

The canonical Test Center remains owned by Worker B / MISSION-002. P6-TC-001 is `OWNER_HANDOFF_PENDING`; no Test Center registration, hierarchy binding, behavior claim, or platform claim is asserted until Worker B publishes the authority-owned integration and exact review.
