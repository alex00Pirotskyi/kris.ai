# ADR-0005 — Browser Profile and Research Storage

**Status:** ACCEPTED
**Owner tasks:** `P3-008`, `P4-011`
**Accepted:** 2026-08-23
**Acceptance evidence:** `release/evidence/P3-008/manifest.json`, `release/evidence/P4-011/manifest.json`

## Decision

Kristin keeps browser profile state and research evidence local-first and application-owned, but they use different storage contracts because their secrecy and retention requirements differ.

Persistent browser authentication state is stored per bounded profile identifier. Cookies, local-storage state and equivalent browser credentials are serialized only in memory and passed to an authenticated platform-backed cipher before durable write. The P3 profile store persists ciphertext, size/hash metadata and schema identity; it never writes the plaintext profile state itself. Associated data binds ciphertext to the exact profile identifier and record version. Corrupt, oversized, malformed or unauthenticated records fail closed. Ephemeral sessions do not create persistent profile records. Profile removal deletes the application-owned profile directory.

Research evidence is content-addressed by canonical SHA-256 and stored under the application data root with explicit provenance, source metadata, freshness and dataset-version references. Raw/rendered evidence and derived/indexed representations are separate objects so rebuilding an index or transform never changes the immutable source identity. P4 storage may use ordinary durable files/JSON indexes for metadata, but must not silently move source evidence into an external service or global database.

## Security boundaries

- Browser credentials/profile state require authenticated encryption supplied by the platform security boundary; repository code does not invent or persist a static encryption key.
- Browser profile IDs are bounded safe identifiers and cannot influence paths outside the application-owned profile root.
- Research content-addressed objects are integrity-bound and immutable by digest; secret-bearing browser profile state is never copied into research evidence, replay bundles, logs or model context.
- Export and deletion are explicit operations. Deleting a browser profile removes its durable authentication state; deleting research data follows the dataset/evidence retention contract rather than the browser profile lifecycle.
- Model context receives only the bounded fields selected by the calling product workflow. Durable browser/research stores are not implicit prompt context.

## Acceptance evidence

`P3-008` is accepted only with the browser profile isolation evidence packet and its behavioral tests. The profile store writes ciphertext rather than plaintext, rejects unsafe profile identifiers, binds authenticated ciphertext to the exact profile identity through associated data, and fails closed when ciphertext from one valid profile is transplanted into another profile record.

`P4-011` is accepted only with the research storage evidence packet and its behavioral tests. Identical content resolves to the same SHA-256 object identity while fetch-version records remain distinct provenance authorities; citations bind to immutable fetch/extraction identities instead of mutable live content.

The closure candidate must pass the focused owner-task tests, the complete governed browser and research suites, fatal static analysis, the complete Flutter regression, and the deterministic release validator before these acceptance records may be published as a clean candidate.

## Consequences

P3 can support reusable authenticated profiles without weakening the existing ephemeral-session default. P4 can deduplicate and version evidence deterministically while remaining local-first. Both phases share application-owned storage governance and hashing conventions without conflating secrets with research artifacts.

ADR acceptance establishes implementation authority for the P3/P4 storage contracts only. It does not promote packaged-release support, production support, independent security-review identity, or GA status.
