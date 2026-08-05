# P2 exact protected-landing dispatch controller v9

**Recorded:** 2026-08-05
**Worker:** A
**Roadmap authority:** `docs/roadmap/MASTER.md`
**Protected landing:** `0a4176bcbcb975684c3a590be652c9fffe1ce770`
**Landing tree:** `641e11e63fa84f3a16dc4d74b418778839ce5bc2`
**Package SHA-256:** `7b0d77d8956f05ff907ca7463b0d787dcebf93a60426aab105be2b610e6072b0`

PR #14 landed through the active protected squash policy only after exact-head tri-OS product, P1 Authority Service source/native, and P2 source checks passed. This disposable controller verifies `main`, the Git tree, and the committed package-digest file before dispatching `.github/workflows/p2-owner-mode.yml` with exact `source_sha` and `package_sha256` inputs. It snapshots prior workflow-dispatch run IDs, accepts only one newly created run bound to the exact landing SHA and `main`, and uploads a durable receipt containing actor and run identity. It does not alter variables, environment protection, runner labels, workflow eligibility, source, evidence classification, Worker C, P3, or P4. The strict workflow itself remains authoritative for actor authorization, package-variable equality, signed provisioning, controlled interactive runner availability, behavioral execution, cleanup, and final receipts. A failed or skipped lane remains a blocker and is never relabeled as proof.
