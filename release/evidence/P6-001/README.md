# P6-001 — Model registry v2 source foundation

## Scope

This packet implements only the dependency-satisfied P6-001 registry contract. It adds a deterministic declarative catalog beside the existing runtime Ollama and OpenAI-compatible providers; it does not replace those providers or dispatch a request.

The registry records:

- provider and exact model identity, aliases, digest, parameter size, and quantization;
- measured or unknown context, output, concurrency, tool-call, and streaming limits;
- measured, declared, or unknown tool capability profiles;
- explicit local, customer-managed-endpoint, or third-party-service data boundaries;
- unknown, no-direct-charge, or metered direct invocation cost metadata;
- benchmark evidence bound to stable task-class identifiers;
- task classes approved only when every class has benchmark evidence;
- credential **reference metadata** only, with unexpected value-bearing fields rejected.

## Fail-closed invariants

1. A model discovered through the legacy `ModelIdentity` interface but absent from the registry is created only as a non-persistent `evaluation_only` descriptor.
2. A discovered model with an unregistered provider is rejected because its data boundary cannot be inferred safely.
3. Approval requires complete measured limits, a measured tool profile, known direct cost metadata, at least one approved task class, and benchmark evidence for every approved class.
4. Evaluation-only records cannot expose approved task classes.
5. Provider/model boundary mismatches, duplicate provider/model identities, duplicate aliases, and canonical-ID/alias collisions are rejected.
6. Credential records accept only `referenceId`, `resolver`, `required`, and `purpose`; secret values are not part of the contract.
7. Serialization is deterministic: providers, models, aliases, task classes, reasons, credentials, and benchmark records are canonically ordered.

## Classification and non-claims

Classification: `SOURCE_FOUNDATION` / `evaluation-only by default`.

This packet does not implement P6-002 or later routing behavior, planner/executor/verifier separation, live provider dispatch, prompt-injection containment, model compatibility certification, hardware acceleration, release readiness, or a GA support claim. Runtime tool permission remains governed by existing policy; a model tool profile is evidence, not authority.

## Verification

The focused test module is `test/product/model/model_registry_test.dart`. P6-TC-001 is registered in Worker B's canonical Test Center as `tc.p6.model-registry-v2` with a non-mutating tri-platform Flutter test profile. Repository-level `product-gates` remain the exact-head authority.

The Test Center registry path remains owned by Worker B / MISSION-002. Worker G's central coordination request is `MISSION-006-P6-001-TEST-CENTER`; integration requires Worker B exact-commit/tree review.
