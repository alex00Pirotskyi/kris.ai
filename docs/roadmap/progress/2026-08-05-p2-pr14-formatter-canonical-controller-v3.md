# PR #14 formatter-canonical repair controller v3

**Recorded:** 2026-08-05
**Worker:** A
**Roadmap authority:** `docs/roadmap/MASTER.md`
**Machine authority:** `docs/roadmap/roadmap.yaml`
**Controller branch:** `ci/pr14-source-contract-repair-20260805`
**Exact PR #14 head:** `bdfec2232cc1718e8b160e7e2fe5c4374fd4b42b`
**Exact PR #14 tree:** `181671cace704b3dd1b10496c02b20d006533515`

## What changed

This significant controller commit replaces the disposable v2 workflow with a smaller v3 wrapper. V3 extracts the previously reviewed validation body byte-for-byte from immutable controller commit `9bfcbb7f240ac0af6d87e1acfaae28f4f433e0e5`, injects only the formatter-canonical candidate-construction step and its truthful progress record, and then executes the same exact-head validation, commit, and non-force push path.

## Roadmap authorization

`MASTER.md` requires P2 to preserve deterministic, non-mutating verification, source-versus-behavioral evidence separation, exact landing identity, and tri-platform closure. P0-010 requires standard verification to leave the source tree clean. Formatting the single intended handwritten regression test before the verification snapshot is a bounded repair action, not a weakened or mutating CI gate.

## Challenges encountered

Run `30987841430` failed before editing because its preliminary tree guard was stale. Run `30988129124` used the corrected tree and passed bootstrap, dependency resolution, all current generated-contract checks, typed protocol contracts, durable workflow-kernel tests, and Prompt Studio gates. It then failed closed at `python tool/dart_format_scope.py --check` because the intended test edit needed canonical Dart formatting. The check identified only `test/product/source_contract_test.dart`; its output SHA-256 was `be9dc630a03846edab1dbc77eb10b885cffca30d7206cce0a8ed2237e320439d`. Artifact `8922939745` is bound to `sha256:3873350320c9e346282d5ea38b7c2b35efdd8157ff5039864455c743ac38434c`. Neither failed run created a candidate or changed PR #14.

## Resolution and validation design

V3 performs `dart format test/product/source_contract_test.dart` as an explicit candidate-construction step, records its exit code and output hash, refreshes `SOURCE_MANIFEST.sha256`, and only then takes the immutable intended-delta snapshot. The extracted parent controller subsequently runs the reviewed non-mutating formatter check, fatal analysis, affected test, complete Flutter suite, P1/P2 source gates, automation-host tests, roadmap, governance, generated-state, and whitespace checks. Before/after patch and status snapshots must remain byte-identical.

The target commit remains limited to:

1. `test/product/source_contract_test.dart`;
2. `docs/roadmap/progress/2026-08-05-p2-pr14-source-contract-regression-closure.md`;
3. `SOURCE_MANIFEST.sha256`.

## Compatibility impact

No production API, wire format, persistence schema, generated Dart, runtime composition, authority boundary, or platform adapter changes. The fixed tests assert the governed dynamic source inventory rather than retired fixed literals. Worker C branch `agent/p4-001-search-provider-foundation` is outside all checkout, target, write, and validation scopes.

## Remaining risks and claim boundary

A successful v3 candidate is still source-stage evidence only. P2 cannot become complete until exact-commit protected checks pass, PR #14 lands through protected policy, controlled Windows/macOS/Linux behavioral certification passes against the landing SHA and package digest, cleanup/process-kill and canonical acceptance receipts aggregate, independent AI review passes, and the roadmap/status/handoff ledgers are updated truthfully. This work does not begin P3 or P4 and does not claim GA, production, signed-installer, or penetration-test readiness.

## Next dependency-controlled action

Run v3, inspect the exact receipt and candidate, require every commit-specific PR gate, merge with an expected-head guard only after green status, then execute the protected-main P2 behavioral certification sequence.
