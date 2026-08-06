# P6-001 — Model registry v2 source foundation

## Scope

This packet implements only the dependency-satisfied P6-001 registry contract. It adds a deterministic declarative catalog beside the existing runtime Ollama and OpenAI-compatible providers; it does not replace those providers or dispatch a request.

The registry records provider/model identity, aliases, artifact digest, parameter size, quantization, measured or unknown limits, tool profiles, explicit data boundaries, direct invocation cost metadata, benchmark evidence, approved task classes, and non-secret credential references.

## Fail-closed invariants

1. A model discovered through the legacy `ModelIdentity` interface but absent from the registry is created only as a non-persistent `evaluation_only` descriptor.
2. A discovered canonical ID or alias reuses a registered definition only when digest, parameter size, and quantization match exactly.
3. Any discovered identity drift receives a deterministic quarantine model ID, remains evaluation-only, and cannot pass `requireApproved`.
4. Quarantine IDs use deterministic base64url identity encoding and remain within the model-ID character contract.
5. Product source must consume the public `model.dart` facade; direct imports of `model_registry.dart` are rejected by a repository regression.
6. A discovered model with an unregistered provider is rejected because its data boundary cannot be inferred safely.
7. Approval requires complete measured limits, a measured tool profile, known cost metadata, and benchmark evidence for every approved task class.
8. Evaluation-only records cannot expose approved task classes.
9. Provider/model boundary mismatches, duplicate identities, duplicate aliases, and canonical-ID/alias collisions are rejected.
10. Credential records accept reference metadata only; secret values are outside the contract.
11. Serialization and quarantine identities are deterministic.

## Review repair

Independent review of commit `9799768170f13556d3098a07b40be922377f8deb` identified `P6-C-001`: canonical names and aliases could inherit approval without matching artifact identity. The public `model.dart` contract now wraps the immutable registry and quarantines digest, parameter-size, or quantization drift. Dedicated regressions cover all three fields through both canonical IDs and aliases.

The hardened facade also removes fixed-width integer hashing from quarantine IDs and enforces that product code cannot bypass the facade through a direct internal import.

`P6-C-002` identified incomplete authority coverage for Worker B Test Center files. Worker G removed every Test Center registry, hierarchy, and Test Center code change from its branch by consuming Worker B head `f14ba34e501972b13cd4310c4869c87e021012da`. P6-TC-001 is now an explicit owner handoff, not an integrated registration claim.

## Classification and non-claims

Classification: `SOURCE_FOUNDATION` / `evaluation-only by default`.

This packet does not implement P6-002 or later routing behavior, live provider dispatch, compatibility certification, hardware acceleration, behavioral support, platform support, release readiness, production readiness, or GA.

## Verification boundary

Focused test modules:

- `test/product/model/model_registry_test.dart`
- `test/product/model/model_registry_identity_guard_test.dart`
- `test/product/model/model_registry_public_contract_test.dart`

The canonical Test Center remains owned by Worker B / MISSION-002. Coordination request `MISSION-006-P6-001-TEST-CENTER` remains pending. No Test Center registration, hierarchy binding, behavior claim, or platform claim is asserted until Worker B publishes the authority-owned integration and exact review.
