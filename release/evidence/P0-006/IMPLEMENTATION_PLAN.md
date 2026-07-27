# P0-006 implementation plan

P0-006 prepares and verifies repository governance as code, then activates the GitHub ruleset only after P0-003 has same-commit passing Ubuntu, Windows, and macOS evidence through native build.

A source-only implementation does not satisfy P0-006. Completion also requires an active verified GitHub ruleset, labels, a distinct reviewer, and demonstration pull requests showing both blocked and allowed merge behavior.

## Local outputs

- desired-state JSON;
- CODEOWNERS;
- pull-request and issue templates;
- offline contract test;
- mock-server tests for the GitHub client;
- redacted remote receipt format;
- operator and merge policy.

## Remote outputs

- active default-branch ruleset;
- strict required checks `validate-ubuntu`, `validate-windows`, and `validate-macos`;
- one independent approval and last-push approval;
- stale review dismissal and resolved threads;
- force-push/deletion protection and linear history;
- security/release labels;
- verified receipt and test PR links.
