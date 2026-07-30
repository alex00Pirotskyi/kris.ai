# Kristin P1A typed authority protocol V2

The stable file name is retained for repository compatibility. V63 accepts only:

- `authorize-effect-v2`
- `record-effect-outcome-v2`
- `describe-authority-v2`
- `record-owner-approval-v2`
- `begin-behavior-session-v2`
- `finalize-behavior-session-v2`

There is no general signing, MAC, key-export, raw-key, or arbitrary-message endpoint.
`authorize-effect-v2` authenticates the desktop caller with the platform transport, evaluates the deterministic P1 policy request, validates trusted owner approval, issues and validates an exact Capability Grant v2, durably consumes its use, checks the revocation epoch, appends the audit-chain record, and returns a one-use public-verifiable effect permit.

The production restricted worker principal is denied by the operating-system boundary before any typed authority operation can succeed.
