# P2 PR #14 source-contract regression closure

**Recorded:** 2026-08-05
**Worker:** A
**Roadmap authority:** `docs/roadmap/MASTER.md`
**Machine authority:** `docs/roadmap/roadmap.yaml`
**Controller run:** `30991501835`, attempt `1`

## Exact repository state

- Protected base `main`: `de8dc3bcde31356b490c32b7d60bb373d9fa68ed`
- Protected base tree: `f7c295b5bafa366e19af78fd49b90445d6f766fc`
- PR #14 branch: `merge/p1-p2-owner-risk-qa-preview`
- Exact pre-repair head and candidate parent: `bdfec2232cc1718e8b160e7e2fe5c4374fd4b42b`
- Exact pre-repair tree: `181671cace704b3dd1b10496c02b20d006533515`
- Pre-repair parent: `5e496d9348ae32213b06c55099b76751e7e835d0`
- Pre-repair parent tree: `181671cace704b3dd1b10496c02b20d006533515`
- Current PR synthetic merge at repair preflight: `eaad3ca616a1079be5aee800e775981106c13f2a`
- Historical failing product run synthetic merge: `24189051ccef3fa26cd15428b83058443ccb0230`

## Roadmap authorization

`MASTER.md` requires P2 to deliver a complete, tri-platform Owner Mode vertical slice while preserving truthful evidence and non-mutating verification. P0-010 additionally requires standard verification to remain source-clean. This repair is limited to the stale source-contract assertions that prevent the already-implemented governed inventory architecture from reaching the P2 landing gates.

## Failure evidence and root cause

Product workflow `30985513818` failed identically in the Windows, macOS, and Ubuntu product jobs during `flutter test --no-pub --concurrency=1 --reporter expanded`. P2 source workflow `30985513862` reproduced the same two failures; its Ubuntu job was `92241780114`, macOS job `92241780185`, and Windows job `92241780173`.

The failing tests were:

1. `security invariants Windows verification migrates stale legacy code safely`;
2. `product completeness Windows launchers avoid stale overlays and PowerShell-only entry points`.

The implementation correctly changed stale-source protection from a fixed literal-only allowlist to `_governedDartFiles(root)`, which validates and unions `config/p2_source_inventory.v1.json` with `SOURCE_MANIFEST.sha256`, then checks `allowedDartFiles.contains(relative)`. Two legacy assertions still required obsolete source text: bare `ui_advanced.dart`/`ui_components.dart` literals and `_allowedDartFiles.contains(relative)`. This was a stale-test regression, not a product defect and not a platform-specific failure.

## Minimal repair and permanent regression coverage

The production implementation and interfaces are unchanged. The test now:

- verifies `lib/product/ui_advanced.dart` and `lib/product/ui_components.dart` through `SOURCE_MANIFEST.sha256`, which is unioned by `_governedDartFiles(root)` with the P2 source inventory;
- verifies construction through `_governedDartFiles(root)` and consumption through `allowedDartFiles.contains(relative)`;
- retains fail-closed, quarantine, rename-only, and no-delete assertions.

Changed target paths are intentionally limited to:

1. `test/product/source_contract_test.dart`;
2. `docs/roadmap/progress/2026-08-05-p2-pr14-source-contract-regression-closure.md`;
3. `SOURCE_MANIFEST.sha256` refreshed by `python tool/p2_refresh_source_manifest.py .`.

## Verification

The exact-SHA controller commits only after every listed command exits zero. Per-command exit codes and SHA-256 output hashes are retained in the workflow artifact alongside the complete logs:

- exact hash-locked Python bootstrap;
- `flutter pub get`;
- all current generated-contract `--check` gates;
- governed `python tool/dart_format_scope.py --check`;
- fatal Flutter analysis;
- the exact affected source-contract test;
- the complete Flutter suite;
- P2 inventory, evidence, runtime-resource, shared-P1A, runner-attestation, cleanup, strict-finalizer, and task-assertion gates;
- automation-host install and tests;
- integration-train, P1 exit, P0 repair, roadmap, generated-state, governance, and Git whitespace gates;
- before/after working-tree comparison proving automatic verification did not mutate the intended source delta.

## Failed-closed controller corrections

Runs `30987841430`, `30988129124`, and `30989119599` failed closed on, respectively, a stale tree guard, non-canonical candidate formatting, and formatting before Flutter dependency resolution. Run `30989744903` resolved dependencies and passed governed formatting plus fatal analysis, then proved the first test repair used the P2-only inventory instead of the full governed union. `SOURCE_MANIFEST.sha256` contains both legacy UI paths and `_governedDartFiles(root)` consumes it with the P2 inventory. Affected-test output SHA-256: `e0c5bd28d3006a198ef4b2a419353876131308665fec41d47ace1ba73bcad3b6`; artifact `8923596034`, archive digest `sha256:ea0d0d00dbe9565a5f3e507468a2e44e8842d2bb1dd5f21f5e72959cc5673e7d`. None of those runs created a candidate or branch update. Final run `30991501835` binds the assertion to the actual source-manifest authority without changing production code.

## Failed-closed staged-whitespace correction

Controller run `30990878896` passed all substantive source, Flutter, P1, P2, automation-host, roadmap, generated-state, governance, and non-mutating verification gates. It then failed closed at `git diff --cached --check` because the generated progress header used four Markdown hard-break lines with trailing spaces. Artifact `8924108162` has archive digest `sha256:68d2713ac9b550055c1038b7ab2f41e57bf192cf4a57fa12c025d67ed8e73248`; all 36 recorded commands exited zero, including affected-test hash `f4cebfd453355a13de543d7c4ee403f1fc98662c303af2547ce3aaca6dc16e3b` and full-suite hash `b10223a2088b68c02628460f03d4de73e6fd87aab3217f0c5a34c8e178ab923e`. No candidate commit or branch update occurred. V6 strips trailing whitespace from the progress document before refreshing the source manifest and taking the immutable verification snapshot.

## Formatter and compatibility impact

The live P2 workflow already uses `python tool/dart_format_scope.py --check` and finishes with `git diff --exit-code`; no broad generator-mutating formatter remains in this path. The controller formats only the intended handwritten regression test during candidate construction, before verification. Generated Dart remains generator-owned, and the before/after snapshot proves automatic verification is non-mutating. This repair changes no API, wire format, persistence schema, runtime composition, platform adapter, or Owner Mode authority behavior.

## Concurrent and parallel work

Legitimate commits through `bdfec2232cc1718e8b160e7e2fe5c4374fd4b42b` are preserved. The controller checks the target head and tree before editing, again before committing, and again before non-force push. Any concurrent branch movement fails closed. Worker C branch `agent/p4-001-search-provider-foundation` is not read, modified, rebased, reset, or merged.

## Claim boundary and remaining risks

This commit is source-stage repair evidence only. It does not mark P2 complete, does not convert hosted source checks into behavioral proof, and does not claim GA, signed-installer readiness, production readiness, independent penetration testing, P3, browser, or P4 completion. P2 remains incomplete until the exact landing commit passes protected checks and the roadmap-required Windows, macOS, and Linux controlled behavioral certification, acceptance scenario, cleanup/process-kill receipts, evidence aggregation, and independent AI review.

## Merge and next dependency-controlled action

Require fresh checks on the exact candidate commit, then merge PR #14 only through the protected repository policy. After protected landing, dispatch the exact P2 behavioral workflow against that landing SHA and source digest. Only after all mandatory platform receipts and final aggregation pass may the P2 status and handoff be advanced. The first dependency-satisfied P3 task may then be identified but is not implemented by this work.
