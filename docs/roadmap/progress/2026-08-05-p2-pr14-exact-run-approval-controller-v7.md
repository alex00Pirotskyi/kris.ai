# PR #14 exact workflow-run approval controller v7

**Recorded:** 2026-08-05
**Worker:** A
**Roadmap authority:** `docs/roadmap/MASTER.md`
**Controller parent:** `647c87b760f193e352cdcab0cb3dcfc2c4d3f66f`
**Exact candidate:** `227f1cbfe1c044c4eb4310e872d3aff5b5721615`
**Candidate tree:** `641e11e63fa84f3a16dc4d74b418778839ce5bc2`

## Authorization and purpose

V6 run `30991501835` produced the exact three-path candidate and passed all 36 recorded source, Flutter, P1, P2, automation-host, roadmap, generated-state, governance, and whitespace checks. Because the guarded fast-forward was performed by `github-actions[bot]`, GitHub classified the resulting pull-request runs as `action_required` and created no jobs. This controller uses the documented workflow-run approval endpoint with Actions write permission; it does not rerun, replace, waive, skip, or weaken any repository check.

## Exact scope and safeguards

The controller is bound to PR #14, branch `merge/p1-p2-owner-risk-qa-preview`, head `227f1cbfe1c044c4eb4310e872d3aff5b5721615`, and the eight run IDs created for that exact head. Before approving any run, it verifies the run head, branch, event, and pull-request number. It approves only a run whose current conclusion is `action_required`, records HTTP status `201`, verifies the run leaves the awaiting-approval state, and uploads a 90-day JSON receipt. A moved branch, unrelated PR, different SHA, unexpected workflow state, unavailable permission, or API error fails closed.

## Compatibility and claim boundary

No PR #14 source, API, generated contract, persistence or wire format, runtime composition, roadmap ledger, Worker C branch, P3, or P4 implementation is changed. Approval authorizes the reviewed exact candidate workflows to execute; it is not evidence that they passed and does not complete P2. Fresh commit-specific checks, protected merge, exact-landing behavioral certification, cleanup, evidence aggregation, independent AI review, and truthful generated roadmap views remain mandatory.
