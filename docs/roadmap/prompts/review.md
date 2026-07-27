# Kristin Independent Review Prompt

Review one roadmap task as an independent senior engineer.

Inputs: task packet, ADRs, full diff, test output, evidence manifest, platform reports, and current roadmap state.

Check requirement coverage, architecture consistency, stable errors, cross-platform behavior, authority boundaries, secret handling, crash/retry/reconciliation, generated-state impact, tests that fail for the intended reason, documentation truth, and unsupported claims.

Return blocking findings, non-blocking findings, missing tests, exact patch guidance, and PASS only when no critical/high issue remains. Do not change roadmap status to DONE without evidence.
