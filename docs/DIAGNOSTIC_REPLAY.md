# Diagnostic replay corpus

## Purpose

Production failures become compact, redacted, versioned fixtures rather than unstructured anecdotes. A replay stores only the causal envelope, observed counters/state, provenance hashes, and repaired expectations needed to reproduce the bug class.

Complete user diagnostic archives are not committed to the source tree.

## Fixture contract

Each `kristin.diagnostic-replay.v1` file contains:

- `id` and title;
- source archive name and SHA-256;
- product version, run ID, and project ID;
- observed terminal state and bounded metrics;
- minimal causal model/tool input;
- expected normalized action, path, policy decision, or classification.

The compact corpus currently covers:

- direct nested `write_file.content` loss and zero-byte mutation in v1.1.5;
- Markdown-wrapped path literals, artifact-scope bypass, read-only recovery looping, copied coordinator metadata, and insufficient retry reserve in v1.1.6.

## Commands

Fast standard-library replay:

```bash
python tool/replay_diagnostics.py
```

JSON report:

```bash
python tool/replay_diagnostics.py --json
```

Product CLI, including Dart behavioral replay when Flutter exists:

```bash
./kristin test --replay-all --project .
```

## Promotion procedure

A production diagnostic may enter the corpus only after:

1. archive integrity and schema are verified;
2. the first causal state transition is separated from terminal noise;
3. secrets and source-like payloads are excluded;
4. the fixture is the smallest input that reproduces the failure class;
5. a repaired expectation is objective and deterministic;
6. both the compact harness and Dart behavior test consume the same fixture;
7. source and release validators fail when the fixture regresses;
8. the archive SHA-256 and run identity are recorded in `VERSION_CONTROL.json`.

## Privacy boundary

Replay fixtures are not complete transcripts. They must not contain plaintext secrets, full project source, private URLs, raw research pages, or unnecessary model context. Hashes preserve provenance without turning the source package into a diagnostic-data archive.
