# Task Execution in v0.4.1

The previous keyword-generated task queues are retired from the active path.
New work uses four local object families:

1. `task_contracts` — typed interpretation of the request.
2. `build_plans` — validated dependency DAGs.
3. `task_runs` — current, completed, failed, or interrupted run state.
4. `verification_evidence` — concrete node, artifact, and plugin evidence.

Every execution transition is also appended to the JSONL journal. At startup,
any run left in `running` state is marked `interrupted`, preserving its previous
last event instead of silently restarting or corrupting one global queue file.

Legacy `task_queues.json` data is migrated once into the
`legacy_task_queues` collection and the original file is archived with the
`.migrated-v0.4.1` suffix. Legacy records are retained for inspection/export but
are never used to create new plans.
