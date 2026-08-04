# P2 V63 independent security-review packet

**Status: PENDING INDEPENDENT REVIEW**

This packet was prepared by the implementation-producing AI conversation. It is not an independent security opinion and contains no reviewer approval.

## Exact review binding

The prepare-stage launcher emits an exact review request containing:

- reviewed source commit and Git tree;
- V63 ZIP SHA-256;
- exact P1 base-main SHA/tree, aggregate-manifest digest, executed P1 exit-gate digest, and product-gates run;
- exact P2 workflow run;
- SHA-256 for the Windows, macOS, and Linux task-specific receipts.

The independent review JSON must match every value. `criticalHighFindingsRemaining` must be empty. `approve_with_conditions` is accepted only when `conditions` and `satisfiedConditions` match exactly. The final evidence commit is constrained to evidence, completed P2 packets, roadmap output, and source-authority files; it cannot change reviewed implementation source.

## High-authority entry points

- `P2EffectBoundary.authorize`
- `P2FilesystemService.read`, `write`, `enumerate`, and `moveToQuarantine`
- `P2FiniteCommandService.run`
- authenticated automation-host `pty.open`, `input`, `resize`, `attach`, `detach`, `interrupt`, and `terminate`
- `P2AutomationHostOperations` through `P2OwnerRuntimeComposition`
- snapshot/undo and emergency-watchdog transports
- Owner Workspace typed actions

## Review focus

1. Single ProductRuntime-owned P1 authority; exact policy/Capability Grant v2 binding; protected HMAC operations; desktop-authoritative durable use consumption; revocation/expiry/budget checks; signed audit checkpoint; public-key-only worker bootstrap; one-use ECDSA P-256 permit; deadlines; restart state restoration; and replay rejection.
2. Per-session run/task/actor/tool/profile/capability/grant binding on every PTY request.
3. Absolute-path authorization, final-target identity, symlink/junction/reparse traversal, and rename TOCTOU.
4. Direct executable/argument/cwd/environment handling and secret-flow boundaries.
5. PTY quotas, ANSI/binary/Unicode output, transcript truncation, detach/reconnect, and output floods.
6. Windows suspended launch into a Job Object, structured kill-receipt/exit-code/zero-active-process validation, nested-job behavior, and POSIX PID/PGID/UID/start-token validation.
7. Package/service/application, clipboard/screen support honesty and target-image fixtures.
8. Best-effort undo taxonomy and unknown-completion reconciliation.
9. Frozen-UI emergency kill independence.
10. Owner Mode versus `isolated_untrusted` labelling.

## Residual risks requiring explicit disposition

- Dart/Flutter source must format, analyze, compile, and pass tests with the repository's exact pinned SDK.
- Target desktop runners must provide task-specific package/service/application/clipboard/screen receipts; headless or unsupported environments remain blocked.
- Path-race prevention remains platform-dependent where Dart cannot hold a native directory handle through final rename.
- Arbitrary commands can commit external effects that are not reversible.
- Screenshot redaction cannot infer every sensitive region.

## Reviewer sign-off fields

Reviewer name: ______________________________

Reviewer organization/relationship: ______________________________

Independent from implementation-producing conversation: Yes / No

Reviewed commit SHA: ______________________________

Reviewed Git tree: ______________________________

V63 package SHA-256: ______________________________

P1 exact-base verification SHA-256: ______________________________

Platform receipt SHA-256 map: ______________________________

Decision: Approve / Approve with conditions / Reject

Critical/high findings remaining: ______________________________

Conditions and proof of satisfaction: ______________________________

Review artifact SHA-256: ______________________________
