# P6-001 — Model registry v2 source foundation

## Scope

This packet implements only P6-001. It adds a deterministic model/provider policy catalog beside existing runtime providers; it does not dispatch model requests or implement P6-002 routing.

The registry records provider/model identity, aliases, exact artifact identity, parameter size, quantization, measured or unknown limits, tool profiles, data boundaries, direct invocation cost metadata, immutable benchmark evidence, approved task classes, and non-secret credential references.

## Current fail-closed invariants

1. Unregistered discovered models remain evaluation-only.
2. Unknown providers fail closed because their data boundary cannot be inferred.
3. Non-empty model and benchmark artifact identities must be canonical `sha256:<64 lowercase hex>` values. Tags, short pseudo-digests, uppercase digests, and whitespace variants cannot become immutable identity.
4. Canonical IDs and aliases reuse registered identity only when digest, parameter size, and quantization match exactly.
5. Identity drift receives a deterministic model-ID-safe quarantine identity and cannot pass `requireApproved`.
6. Raw string `lookup(providerId, modelIdOrAlias)` is metadata-only. `ModelRegistryMetadata` intentionally exposes no support status, approved task classes, evaluation reasons, or approval predicate.
7. Runtime registry serialization is metadata-only and does not serialize approval policy.
8. `requireApproved(ModelIdentity, taskClassId)` is the only registry API that can produce an `ApprovedModelHandle`; mutable names or aliases alone cannot authorize.
9. Direct imports of `model_registry.dart` preserve the same authorization boundary.
10. Benchmark evidence is closed embedded content-addressed canonical JSON. Its SHA-256 is recomputed before the record is accepted.
11. Immutable benchmark payloads bind schema/version, exact candidate commit/tree, exact model digest, benchmark ID, task class, score, unit, sample count, direction, and measured timestamp.
12. Registry benchmark metadata must exactly match the verified immutable evidence payload; score/sample metadata cannot drift independently of the referenced bytes.
13. Approved and evaluation-only records reject benchmark evidence measured for another model artifact.
14. Approved task classes require immutable benchmark evidence for every approved task class, and one approved model cannot mix benchmark evidence from different candidate commit/tree identities.
15. Evaluation-only records cannot expose approved task classes.
16. Provider/model data boundaries, duplicate IDs/aliases, and canonical-ID/alias collisions fail closed.
17. Credential records contain reference metadata only.
18. Metadata serialization and quarantine identities are deterministic.

## Review repair history

Earlier review found that canonical names and aliases could inherit approval without exact artifact matching; that repair now lives inside the core registry and `requireApproved` requires the actual discovered `ModelIdentity`.

A later review found benchmark measurements could be reused across model digests. Artifact-bound benchmark evidence and approved/evaluation regressions repaired that defect.

The latest exact review of `2bee9843e331f48aaf2dd1f060ad4320274b59a6` exposed three remaining trust roots:

- string-only `lookup()` still returned approval-bearing records;
- artifact identity accepted arbitrary non-empty strings rather than cryptographic identities;
- benchmark approval trusted an unverified URI/string metadata record.

Source milestone `954f231fa28a22c85e0be3a76205cc31635f6466` repairs all three in product source and focused tests. The runtime lookup/serialization surface is now non-authoritative, artifact IDs are canonical SHA-256 values, and benchmark approval is tied to verified content-addressed evidence payloads rather than an unchecked URI.

## Worker B integration boundary

Worker G previously consumed Worker B source authority through true two-parent merge `4166abe8e66b43f4683a3fe9b5e75475adf999e5` with Worker B parent `604905039aa26952045e69ebe6799ae464144635`. Worker G carries no effective Test Center authority-file diff and does not edit Worker B Test Center ownership.

The remaining shared Worker A path is the governed global Dart source inventory entry in `test/product/source_contract_test.dart`.

## Classification and non-claims

Classification: `SOURCE_FOUNDATION` / evaluation-only by default.

This packet does not implement role routing, live provider dispatch, compatibility certification, hardware acceleration, behavioral/platform support, release readiness, production readiness, or GA.

## Verification boundary

Focused test modules:

- `test/product/model/model_registry_test.dart`
- `test/product/model/model_registry_identity_guard_test.dart`
- `test/product/model/model_registry_public_contract_test.dart`

Published source/test blobs were statically audited for balanced Dart delimiters, stale removed symbols, old `evidenceUri` use, pseudo-digest fixtures, and deterministic benchmark evidence SHA. That bounded static audit passed.

The current source/test candidate has not executed under Dart/Flutter in this worker environment, and GitHub allocated no exact-head workflow run or commit status for source milestone `954f231...`. Historical green runs are not promoted to current validation.

`SOURCE_MANIFEST.sha256` is inherited from Worker B rather than carried as a Worker G diff, but it is not current for the changed P6 source/tests. It must be regenerated twice through `python tool/p1a_refresh_source_manifest.py .` in an executable canonical environment.

The canonical Test Center remains owned by Worker B / MISSION-002. P6-TC-001 is `OWNER_HANDOFF_PENDING`; no Test Center registration, hierarchy binding, behavioral claim, or platform claim is asserted until Worker B publishes the authority-owned integration and exact review.
