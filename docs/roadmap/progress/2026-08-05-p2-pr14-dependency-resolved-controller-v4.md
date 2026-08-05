# PR #14 dependency-resolved formatter controller v4

**Recorded:** 2026-08-05
**Worker:** A
**Roadmap authority:** `docs/roadmap/MASTER.md`
**Machine authority:** `docs/roadmap/roadmap.yaml`
**Controller branch:** `ci/pr14-source-contract-repair-20260805`
**Controller parent:** `ecf6d6d1890837b23ff20b69307ed0404fb9d39a`
**Exact PR #14 head:** `bdfec2232cc1718e8b160e7e2fe5c4374fd4b42b`
**Exact PR #14 tree:** `181671cace704b3dd1b10496c02b20d006533515`

## What changed

This significant controller commit advances the disposable exact-head wrapper from v3 to v4. It adds one target-scoped `flutter pub get` step before candidate formatting so the Dart formatter can resolve the repository's `analysis_options.yaml` and `package:flutter_lints/flutter.yaml`. The previously reviewed parent repair, exact target guard, validation profile, three-path commit restriction, and non-force push path remain unchanged.

## Roadmap authorization

`MASTER.md` requires P2 landing verification to remain deterministic and non-mutating, while P0-010 requires the verified source tree to remain clean. Resolving declared dependencies before formatting the single intended handwritten regression test is a bounded candidate-construction prerequisite. It does not weaken the later `python tool/dart_format_scope.py --check` gate, mutate generated Dart, expand product scope, or convert source validation into behavioral evidence.

## Challenges encountered

Controller run `30989119599` passed the exact head/tree checks, formatted the intended test with exit code zero, refreshed the source manifest, and passed the hosted Python bootstrap, dependency resolution inside the parent, all current generated-contract checks, typed protocol contracts, durable workflow-kernel tests, and Prompt Studio gates. The early formatter, however, ran before dependency resolution and warned that `package:flutter_lints/flutter.yaml` could not be resolved. It consequently produced a different form from the later governed formatter, which failed closed and reported only `Changed test/product/source_contract_test.dart`.

Machine evidence for that failed-closed run:

- run: `30989119599`;
- candidate-format output SHA-256: `282ea833865ea07acf3f495681b128750c36263054f0d955a5866c4effa20e54`;
- governed format-check output SHA-256: `60a71cf72bf39e985b5a1862a090df0d90eb64c94c1c8b78d30d78c60e865c4b`;
- artifact: `8923344309`;
- artifact archive digest: `sha256:597030611c1f162f8e4aeef0f0488ba0f4dd42c2371b911c333281edb41bf02a`;
- candidate commit: absent;
- target ref update: false.

## Resolution and validation

V4 resolves target Flutter dependencies immediately after the locked Flutter setup and before extracting the immutable parent controller. The parent then rechecks the exact PR branch SHA and tree before patching, formats only `test/product/source_contract_test.dart`, records the formatter exit code and output hash, refreshes `SOURCE_MANIFEST.sha256`, snapshots the intentional delta, and runs its complete non-mutating verification profile. A concurrent target movement still fails closed before any commit or push.

The target commit remains restricted to:

1. `SOURCE_MANIFEST.sha256`;
2. `docs/roadmap/progress/2026-08-05-p2-pr14-source-contract-regression-closure.md`;
3. `test/product/source_contract_test.dart`.

## Compatibility impact

No production API, wire format, persistence schema, generated contract, runtime composition, authority boundary, or platform adapter changes. Worker C branch `agent/p4-001-search-provider-foundation` remains outside checkout, write, reset, merge, and validation scope.

## Remaining risks and claim boundary

A successful v4 run remains source-stage evidence only. PR #14 still requires fresh exact-commit protected checks and protected landing. P2 still requires controlled Windows, macOS, and Linux behavioral certification against the landing SHA and package digest, canonical acceptance, cleanup and process-kill receipts, final evidence aggregation, independent AI review, and truthful roadmap/status/handoff updates. This work does not begin P3 or P4 and does not claim GA, production, signed-installer, consumer, or penetration-test readiness.

## Next dependency-controlled action

Run v4, inspect its exact receipt and candidate identity, require every commit-specific PR gate, repair any genuine remaining failure, merge through the protected mechanism with an expected-head guard, then execute the protected-main P2 behavioral certification and evidence closure sequence.
