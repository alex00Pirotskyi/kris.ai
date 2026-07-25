# Kristin Release Gates

**Roadmap authority:** `DERIVED`

This file summarizes the master roadmap. `MASTER.md` remains the human constitution and `roadmap.yaml` remains the P0/P1 machine task authority.

| Gate | Minimum evidence |
|---|---|
| A — Repository health | Protected main, pinned inputs, green Windows/macOS/Linux CI, clean generated state |
| B — Trust and policy | v1 trust disabled, Signed Manifest v2, external roots, policy properties, authenticated IPC |
| C — Owner Mode and terminal | Full declared host authority, PTY, kill, journal, accurate privilege disclosure |
| D — Browser and Web Studio | Fixture suite, profile isolation, takeover, stale-target handling, trace/replay |
| E — Research and data | Fetched evidence, immutable citations, extraction benchmark, datasets and exports |
| F — Agent quality | Supported model matrix, zero unauthorized effects, false-completion and recovery targets |
| G — UX/accessibility | Primary workflows, visible Owner state/kill, keyboard, semantics, performance, onboarding |
| H — Supply chain | Signed/notarized artifacts, SBOM, provenance, TUF, install/update/rollback/uninstall |
| I — Operations | Beta SLOs, RC soak, incident drills, support, privacy, legal, staged rollout |

A release command must refuse to label an artifact stable when a required gate lacks evidence. P0-008 does not itself satisfy any product release gate; it makes task and evidence state discoverable and non-contradictory.
