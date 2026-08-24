# Test Center — P26 Verification Center

## Purpose

This suite verifies P26 governance and later product evidence while preserving the
canonical distinction between architecture lint, unit, integration, platform, benchmark,
adversarial, and release assurance.

## Stable governance checks

| Stable test ID | Assurance | Completion eligible | Meaning |
|---|---:|---:|---|
| `tc.p26.roadmap-contract` | architecture_lint | yes | P26 files, DAG, state contract, budgets and registration are coherent. |
| `tc.p26.test-station-contract` | architecture_lint | yes | Profile selection, blockers, safe argv and source non-mutation are coherent. |

These checks establish only governance and source-contract readiness for `P26-001`.

## Future checks

- `tc.p26.deterministic-fixtures`
- `tc.p26.behavioral-local`
- `tc.p26.web-http-fixture`
- `tc.p26.native-owner`
- `tc.p26.updater-operation`
- `tc.p26.kristin-dogfood`

Until their implementation paths and required environments exist, the Test Station must
return `BLOCKED_NOT_IMPLEMENTED` or `BLOCKED_ENVIRONMENT`; it must not silently skip or
return PASS.

## Exact state boundary

Product reports use only PASS, FAIL, BLOCKED_ENVIRONMENT, BLOCKED_PERMISSION, NOT_RUN,
and UNKNOWN. Test Station infrastructure additionally uses explicit station-level blocker
states to explain why a profile could not be executed. Neither domain may coerce a blocker
or unknown condition into PASS.

## Commands

```bash
python3 tool/p26_verification_center_roadmap_test.py --project .
python3 tool/p26_verification_center_test_station.py --project . --list
python3 tool/p26_verification_center_test_station.py --project . --profile contract --check
```

## Release boundary

The Kristin dogfood profile is mandatory before P26 release eligibility. It is not
completion-eligible during governance and cannot be claimed until real packaged evidence
is bound to the exact candidate and required platform or environment.
