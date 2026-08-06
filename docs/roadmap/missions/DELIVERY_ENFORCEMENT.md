# Mission delivery enforcement

`tool/mission_control.py` validates the static mission graph.  
`tool/mission_delivery_control.py` validates delivery truth against actual work.

## Goals

The delivery layer prevents the mission framework from reporting healthy coordination while work remains unmeasured or crosses ownership boundaries.

It adds:

1. append-only task delivery records;
2. accepted/merged progress accounting;
3. real changed-file ownership checks;
4. explicit shared-authority grants;
5. namespace existence versus future-reservation semantics;
6. scoped review invalidation;
7. live branch/PR/claim auditing;
8. branch hygiene classification.

## Delivery truth

A roadmap task is not complete merely because source, tests, CI, evidence, or documentation exists.

- `ACCEPTED` requires exact commit/tree, durable evidence, and satisfaction of the task's done condition.
- `MERGED_MAIN` additionally requires the protected-main merge identity.
- Missing records are `NOT_EVALUATED`.
- Synthetic fixtures, hosted source CI, and prose never become behavioral/platform/release proof.

## Commands

```bash
python tool/mission_delivery_control.py --project . validate
python tool/mission_delivery_control.py --project . generate --check
python tool/mission_delivery_control.py --project . work-id
```

Changed-file enforcement:

```bash
python tool/mission_delivery_control.py --project . ownership \
  --mission MISSION-006 \
  --base <base-sha> \
  --head <head-sha> \
  --head-branch agent/g/mission-006-model-routing \
  --output /tmp/mission-ownership.json
```

Scoped review impact:

```bash
python tool/mission_delivery_control.py --project . review-impact \
  --base <reviewed-sha> \
  --head <current-sha> \
  --output /tmp/review-impact.json
```

Live audit:

```bash
GITHUB_TOKEN=... python tool/mission_delivery_control.py --project . live-audit \
  --repo alex00Pirotskyi/kris.ai \
  --output /tmp/mission-live-audit.json
```

Append-only delivery event:

```bash
python tool/mission_delivery_control.py --project . record \
  --mission MISSION-006 \
  --task P6-001 \
  --status REVIEW \
  --work-id WRK-20260806T120000Z-0123abcd \
  --worker G \
  --branch agent/g/mission-006-model-routing \
  --pr 76 \
  --commit <sha> \
  --tree <tree> \
  --evidence "workflow:<run-id>" \
  --next-action "Obtain independent review"
```

## Review validity

Review is scope-bound, not tree-only:

- `SOURCE`
- `SECURITY`
- `EVIDENCE`
- `INTEGRATION`

A source-manifest-only update can invalidate evidence/integration review without invalidating source architecture review. A shared-contract or source change invalidates the affected scopes.

## No second authority

The delivery layer does not replace:

- roadmap authority;
- Test Center authority;
- mission claims;
- source-manifest ownership;
- GitHub branch protection.

It adds enforceable delivery and collision checks around them.
