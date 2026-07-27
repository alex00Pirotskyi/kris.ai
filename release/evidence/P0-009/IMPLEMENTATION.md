# P0-009 Implementation Evidence

Status: `REVIEW`

P0-009 adds the first versioned Kristin benchmark corpus and a deterministic portable baseline.

Implemented categories:

- coding;
- analysis;
- path safety;
- crash recovery;
- browser capability honesty;
- research and citations.

The baseline deliberately records current gaps. Completing P0-009 means the corpus and result are reproducible; it does not mean every case passes or that Kristin is production ready.

The portable baseline is network-free, credential-free, model-free, and SDK-independent. Machine runs and model-candidate runs are separate supplementary results.

Key claim boundaries:

- source inspection is not behavioral proof;
- unsupported is not passed;
- unavailable is not passed;
- not-run is not passed;
- a recorded baseline is not a release-quality claim.

Integrity controls:

- candidate workspaces are evaluated against immutable fixture tests;
- command executables are allowlisted and shell invocation is not used;
- capability source signals do not substitute for behavioral evidence;
- suite dependencies must reference an earlier known case;
- source and fixture inputs are hashed, including currently missing inputs;
- each result has a self-verifying SHA-256 fingerprint;
- command output is bounded and redacted before any diagnostic use.
