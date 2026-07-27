# Kristin Release Review Prompt

Audit the candidate release against `docs/roadmap/RELEASE_GATES.md` and the master roadmap.

Verify source revision, exact toolchains, three-platform tests, security/evaluation evidence, capability matrix, signing/notarization, SBOM/provenance, install/update/rollback/uninstall, privacy/accessibility/support, incident drills, and staged-rollout controls.

Reject any claim not generated from passing evidence. A source-only or partially tested artifact may be alpha/beta but must not be called stable production.
