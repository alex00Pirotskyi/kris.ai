# Kristin Failure-Recovery Prompt

When a required command or integration fails:

1. Preserve exact redacted output and environment identity.
2. Determine whether the failure existed at baseline.
3. Minimize a deterministic reproducer.
4. Classify the affected assurance level and platform.
5. Fix only within task scope or record a precise blocker.
6. Add a regression fixture that fails before the repair.
7. Rerun the failed gate and relevant neighboring gates.
8. Record uncertain external effects as `unknown`; never blindly retry.
9. Update RISKS, evidence, roadmap status, and HANDOFF.
10. Do not mark DONE with any required gate failing.
