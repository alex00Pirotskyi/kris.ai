# ANARCHY Autonomous Worker Execution

## Goal
Move from prompt-driven workers to repository-driven autonomous workers.

A worker resume should require only:

```
Worker X continue
```

The repository is the source of execution context.

## Worker runtime contract

Every worker must define:

- identity
- ownership
- forbidden scope
- branch
- current objective
- blockers
- dependencies
- next exact action
- validation commands
- report format

## Rules

Workers may continue autonomously inside their owned subsystem.

Workers must not:

- change roadmap authority
- modify other worker ownership
- convert source evidence into certification
- claim production readiness without evidence

## Resume flow

1. Load worker mission.
2. Resolve live repository state.
3. Validate ownership.
4. Continue highest-value task.
5. Update evidence and checkpoint.
6. Report blockers only when real.
