# Operations guide

## First launch

1. Register a project directory.
2. Run **Doctor** and **Quick Test** before invoking an agent task.
3. Select an exact installed model identity.
4. Keep local-only mode enabled until external research or another network capability is needed.
5. Start with a low-risk Analyze/Ask request and review the proposed plan and scopes.

## Building or repairing a project

Describe observable acceptance criteria. Let the plan inspect before it mutates. Grant only displayed scopes. Review changed files, deterministic test evidence, command output, and the run graph before accepting a result or committing it.

`kristin run` is dry-run by default. Use `--execute` only after reviewing the detected project profile and command.

## Knowledge and research

Use project notes for information you control. For external material, grant research only to the prepared command that needs it. Every successful fetch/search can become a project-scoped archive record and retrievable knowledge entry.

Operational expectations:

- treat archived web content as untrusted data;
- inspect requested/final URLs, timestamps, hashes, and redirects when provenance matters;
- pin durable project requirements or especially useful episodes;
- rebuild the derived index after manual state repair;
- export knowledge before major migration or retention cleanup;
- do not assume the archive mirrors resources Kristin did not fetch.

The archive may contain copyrighted, confidential, personal, or security-sensitive material retrieved during work. Apply a project retention policy and protect the Kristin data root accordingly.

## Run memory

A terminal run is summarized into a project-scoped memory episode. Later tasks may retrieve that episode as historical evidence. Review prior-run claims against current source and tests because projects change.

Pinning raises retrieval preference; it does not make a memory authoritative. Failed/cancelled/interrupted episodes are retained because they can explain prior failure modes, but the model is told they are evidence rather than instructions.

## Backup and export

The portable knowledge export includes project knowledge metadata, research provenance, memory episodes, and archived object bytes available for the project. Store exports as project-confidential material.

For a complete operational backup, stop Kristin and preserve the whole data root, including `state/workflow.sqlite3`, any `-wal`/`-shm` companions, `support/migration-backups/`, archive objects, logs, and project checkpoints. A knowledge export or copied SQLite main file alone is not a complete live backup. Prefer a stopped application or a SQLite-consistent backup.

## Recovery

On startup, expired run leases are reconciled from durable checkpoints. A workspace that was committed with all work items succeeded can be recovered as succeeded even when the process exited before the final run acknowledgement; other stale active runs become interrupted. File mutations are journaled before effects and reconciled by before/after hashes. Ambiguous state stops with `transaction_recovery_required` rather than repeating or overwriting work.

After unexpected behavior:

1. Stop active runs and managed processes.
2. Preserve logs, audit data, run/evidence records, and relevant project Git state.
3. Run Doctor, Quick Test, and `kristin test --workflow-kernel`.
4. Run `kristin workflow --data-root <root> --json`, verify the audit chain, and inspect recent durable events and raw logs.
5. Rebuild the knowledge index if state is valid but retrieval appears stale.
6. Restore project files from Git/checkpoints as appropriate.

## Repeated-tool recovery

If a local model repeats the same successful read-only tool request, Kristin reuses the cached result and records `agent.repeated_tool_call_blocked`. It may redirect the dedicated evidence-baseline node to a different allowlisted read-only probe. This is a recovery signal, not expanded autonomy.

A recovered run can contain `agent.loop_recovery_redirected` followed by `agent.loop_recovery_completed`. A terminal `agent_stalled_repeated_tool_outcome` now means duplicate reads were blocked and no unused safe progress action remained. Export the full run diagnostics before retrying with another model or a smaller work item.

## Diagnostics

Use:

```text
kristin doctor
kristin test --quick
kristin workflow --data-root <data-root> --json
kristin logs --tail 200
kristin logs --export --run-id <run-id>
kristin knowledge --project-id <id> --archive
kristin knowledge --project-id <id> --memory
kristin report
```

The **Save all logs** bundle includes redacted retained run state, evidence metadata, events, audit records, budget counters, retry decisions, and bounded managed-process output. Source-like fields are hashed and recognized secrets are redacted, but ordinary requests, URLs, relative paths, errors, and model previews can remain. Review every bundle before sharing it.
