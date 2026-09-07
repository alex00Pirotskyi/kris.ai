# One Kristin development overlay — rebuilt checkpoint

The previous runtime-local overlay disappeared when the execution container was recycled. This draft branch is anchored to PR #291 head `dd2f46ba6df3fb25adc2c8c927e807147b8f16f2` and is used as the preservation checkpoint for development-first work.

Current rebuilt scope:

- semantic `TaskSpecificationPatch` steering domain;
- canonical task-family DAG executor seam for Research/Diagnostics/Utilities;
- deterministic IANA/DST `utility.time` foundation with injected clock and ambiguity-safe location resolution;
- canonical `CapabilityInvocation`/permission-envelope resolver foundation;
- focused unit tests for utility time, semantic steering, graph execution, and authority semantics;
- `timezone` dependency declaration.

This is a development checkpoint, not a qualification artifact. Flutter/Dart tests and analyzer have not run in this execution environment.
