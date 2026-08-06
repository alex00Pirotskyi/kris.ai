# Shared-path coordination

Shared files are not unowned files.

The policy in `config/mission_delivery.v1.json` declares:

- one owning mission;
- exact shared path patterns;
- exact requesting mission;
- allowed operations;
- whether owner review is mandatory;
- a durable coordination ID.

## Current shared authorities

- Test Center registry — MISSION-002.
- Test Center hierarchy — MISSION-002.
- Test Center implementation/tests — MISSION-002.
- Test Center schemas — MISSION-002.
- Canonical source manifest — canonical generator only.

## Enforcement

A requesting mission may change a shared path only when a matching grant exists.

The ownership report classifies each changed file as:

```text
MISSION_OWNED
APPROVED_SHARED
GENERATOR_OWNED
OTHER_MISSION_PATH
UNGRANTED_SHARED_AUTHORITY
UNDECLARED_PATH
```

Only the first three are permitted.

A grant never transfers authority. Owner review remains required when the policy says so.
