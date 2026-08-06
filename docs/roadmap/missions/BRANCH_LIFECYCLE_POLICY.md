# Branch lifecycle policy

Branches are execution artifacts, not permanent archives.

## Default

Use one focused mission/task branch and append-only checkpoints.

Do not create backup branches by default.

## Protected

- `main`
- `agent/anarchy-autonomous-worker-missions`
- branches referenced by accepted or merged delivery evidence

## Ephemeral

Patterns such as:

```text
ci/*
automation/*
carrier/*
temp/*
```

must carry a cleanup disposition. Remove them after the durable candidate and evidence are published, provided no open PR or unique evidence depends on them.

## Backup candidates

Patterns such as:

```text
*-backup*
*-prestack-*
validated/*
validation/*
```

are surfaced by live audit. They are not deleted automatically.

Delete only when:

1. no open PR targets the branch;
2. no active claim references it;
3. no unique review/evidence identity depends on it;
4. supersession is recorded.

## Staleness

The policy default is 14 days. Live audit reports candidates; humans or an authorized cleanup mission decide deletion.
