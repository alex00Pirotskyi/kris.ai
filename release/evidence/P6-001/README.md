# P6-001 — Model registry v2 source foundation

## Scope

This packet implements only P6-001. It adds a deterministic declarative catalog beside the existing runtime providers; it does not dispatch model requests or implement P6-002 routing.

The registry records provider/model identity, aliases, immutable artifact digest, parameter size, quantization, measured or unknown limits, tool profiles, data boundaries, direct invocation cost metadata, benchmark evidence, approved task classes, and non-secret credential references.

## Fail-closed invariants

1. An unregistered discovered model is created only as a non-persistent `evaluation_only` descriptor.
2. A canonical ID or alias reuses approval only when digest, parameter size, and quantization match exactly.
3. Approved records require a non-empty immutable artifact digest.
4. Identity drift receives a deterministic quarantine ID, remains evaluation-only, and cannot pass `requireApproved` through that identity.
5. Quarantine IDs use deterministic base64url encoding within the model-ID character contract.
6. Identity validation lives inside the single exported `ModelDefinitionRegistry`; direct imports cannot bypass the check.
7. Invalid discovered provider/model IDs and unknown providers fail closed.
8. Approval requires measured limits, a measured tool profile, known cost metadata, and benchmark evidence for every approved task class.
9. Evaluation-only records cannot expose approved task classes.
10. Boundary mismatches, duplicate identities, duplicate aliases, and canonical-ID/alias collisions are rejected.
11. Credential records contain reference metadata only.
12. Serialization and quarantine identities are deterministic.

## Review repair

Independent review of `9799768170f13556d3098a07b40be922377f8deb` identified `P6-C-001`: canonical names and aliases could inherit approval without matching artifact identity. The repair now resides in the core registry rather than a wrapper, closing direct-import bypasses. Regressions cover digest, parameter-size, and quantization drift through canonical IDs and aliases, invalid discovered IDs, deterministic quarantine, and approval rejection.

`P6-C-002` identified incomplete authority coverage for Worker B Test Center files. Worker G consumed current Worker B head `71770c8ced388d83a278d951fd45a07afdec84db`; the effective PR diff contains no Test Center registry, schema, hierarchy, or Test Center code path. P6-TC-001 is an explicit owner handoff, not an integrated registration claim.

## Classification and non-claims

Classification: `SOURCE_FOUNDATION` / `evaluation-only by default`.

This packet does not implement role routing, live provider dispatch, compatibility certification, hardware acceleration, behavioral/platform support, release readiness, production readiness, or GA.

## Verification boundary

Focused test modules:

- `test/product/model/model_registry_test.dart`
- `test/product/model/model_registry_identity_guard_test.dart`
- `test/product/model/model_registry_public_contract_test.dart`

The canonical Test Center remains owned by Worker B / MISSION-002. No Test Center registration, hierarchy binding, behavior claim, or platform claim is asserted until Worker B publishes the authority-owned integration and exact review.
