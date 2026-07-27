# Kristin Bootstrap Roadmap Control Plane

**Roadmap authority:** `DERIVED`
**Milestone:** `P0-008`
**Scope:** `P0` and `P1`

## Authority model

- `docs/roadmap/MASTER.md` is the human engineering constitution.
- `docs/roadmap/roadmap.yaml` is the machine dependency, status, packet, and evidence authority for the bootstrap scope.
- `docs/roadmap/STATUS.md` and `docs/roadmap/HANDOFF.md` are generated views.
- GitHub issues, pull requests, chat transcripts, and project boards may mirror state but may not override it.
- P24 expands this bootstrap to every task and release claim.

The `.yaml` file uses the JSON subset of YAML 1.2. This is deliberate: P0-008 must run with the Python standard library on a clean checkout. A later ADR may adopt a richer YAML parser.

## Status transition rules

```text
NOT_STARTED -> READY        when every dependency is DONE
READY       -> IN_PROGRESS  when a work packet is acquired
IN_PROGRESS-> REVIEW        after implementation evidence exists
REVIEW      -> DONE         after acceptance and required independent review
any         -> BLOCKED      with an explicit blocker
any         -> DEFERRED     with an explicit owner decision and reason
```

`DONE`, `REVIEW`, and `IN_PROGRESS` are invalid when a dependency is not `DONE`. `READY` is derived and must not be used to hide an incomplete dependency. A dependency-complete task may not remain `NOT_STARTED`.

## Fresh-session workflow

```bash
python3 tool/roadmap_control.py validate --project . --strict
python3 tool/roadmap_control.py next --project . --json
python3 tool/roadmap_control.py explain <TASK-ID> --project .
```

The implementation AI reads the selected packet, ADRs, risks, metrics, and evidence; performs one task; records evidence; updates the manifest; renders the derived files; validates; and stops.

## What P0-008 does not do

P0-008 does not approve runtime boundaries, Owner Mode, Signed Manifest v2, automation-host technology, browser storage, or updater architecture. Their ADR files are intentionally `PROPOSED`. P0-008 also does not split the entire roadmap or compile release claims; those remain P24 work.
