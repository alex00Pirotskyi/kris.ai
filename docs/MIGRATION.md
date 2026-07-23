# Migration

## Upgrade to v1.9.0+190

Extract the v1.7 archive into a new clean source directory. Do not overlay it on an older source tree and do not copy an older `RELEASE.json`, `SOURCE_MANIFEST.sha256`, generated migration registry, release report, `.dart_tool`, `build`, or native ephemeral directory. The separate application data root remains the mutable authority.

On first startup, the workflow database advances transactionally to schema 6. Existing databases are backed up before migration; migration hashes are verified; startup restores the prior database if a migration or import fails. Legacy JSON files remain available as import evidence and are not silently deleted.

Old terminal runs remain immutable diagnostic history. Create a fresh linked run under v1.9 rather than resuming a plan produced under earlier protocol, capability, sandbox, convergence, or interoperability policy. Project profiles should be reviewed because readiness is now intersected with live sandbox capability. Unsupported Windows/macOS isolated execution, network, secret, or preview-port requirements remain blocked.

Recommended source checks after extraction:

```bash
python tool/generate_protocol_contracts.py --check
python tool/generate_workflow_migrations.py --check
python tool/generate_v170_contracts.py --check
./kristin test --workflow-kernel --project .
./kristin test --project-manager --project .
./kristin test --execution-intelligence --project .
./kristin test --replay-all --project .
python tool/validate_release.py --skip-sdk
```

Rollback requires stopping Kristin and managed workers, preserving the complete data root, and restoring the pre-migration SQLite backup as a unit. An older binary does not understand schema-6 audit, interoperability, update-policy, Project Manager, route, progress, or verification records.

## Recommended upgrade to v1.3.0+130

Extract the v1.3.0 source archive into a clean source directory. Do not overwrite a prior release tree or copy its `RELEASE.json`, `SOURCE_MANIFEST.sha256`, generated platform state, reports, or build output. The application data root remains separate.

Before first launch, stop Kristin and managed project processes, then make an external backup of the complete data root. V1.3.0 changes mutable-state authority from whole-collection JSON files to `state/workflow.sqlite3`.

At startup Kristin will:

1. create or open the SQLite database with WAL and full synchronization;
2. apply contiguous reviewed migrations and record their hashes;
3. take a consistent pre-startup database backup when upgrading or importing legacy files;
4. copy each legacy JSON source byte-for-byte into `support/migration-backups/`;
5. import records transactionally while preserving existing SQLite records;
6. record a source-hash import ledger so restart is idempotent;
7. verify SQLite integrity, foreign keys, run/event hashes, and run projections.

Legacy JSON files are not deleted. Keep them and the migration backups until the new database has been independently backed up and normal startup, project listing, run history, knowledge, and settings have been verified.

Run the source gates before launching:

```powershell
.\kristin.cmd --version
.\kristin.cmd test --workflow-kernel --project .
.\kristin.cmd test --replay-all --project .
.\kristin.cmd test --system --project .
```

Inspect a migrated data root with:

```powershell
.\kristin.cmd workflow --data-root C:\path\to\kristin-data --json
```

### Startup failure behavior

A migration checksum mismatch, corrupt legacy source, failed integrity check, or import error aborts startup. If a database existed before startup, Kristin restores the verified pre-startup backup. If this was the first database creation, it removes the partial database, WAL, and shared-memory files. Do not manually merge a partially migrated database. Preserve the error and backup directory for diagnosis.

### Rollback to v1.2.0

V1.2.0 does not read the v1.3 SQLite authority. To roll back:

1. stop Kristin;
2. preserve `workflow.sqlite3`, its WAL/SHM files, and migration backups;
3. restore the complete pre-upgrade data-root backup or the original legacy JSON files;
4. run v1.2.0 from its own clean source directory;
5. do not copy v1.3 run state back into v1.2 JSON collections manually.

Project files are separate from application-state migration. Review Git/workspace checkpoints independently.

## Prior v1.2.0 typed-protocol upgrade guidance

## Recommended upgrade to v1.2.0+120

Extract the v1.2.0 source into a clean directory. Do not copy `RELEASE.json`, `SOURCE_MANIFEST.sha256`, generated Flutter state, or release reports from v1.1.7. Registered projects and application data remain in the separate Kristin data root.

Do not resume run `run_hklw4ohlv7ocm6ItzHe1N5AB0I`. It is terminal and its literal backtick path plus exhausted repair counters are immutable diagnostic history. Review `docs/CURRENT_RUN_RECOVERY.md`, resolve the malformed project-local path manually, remove the unresolved `{{variable_name}}` prompt placeholder, and create a fresh plan/run.

Before the fresh run, execute:

```powershell
.\kristin.cmd test --replay-all --project .
```

No application-state storage migration is introduced in v1.2.0. The AgentDecision and tool contracts change in source/runtime code only; registered projects and application JSON state remain compatible.

## Historical upgrade guidance

### Recommended upgrade to v1.1.6+116

Extract the complete v1 source ZIP into a new directory. Do not copy it over a historical folder that contains old patch launchers, generated platform files, build output, or archived source.

PowerShell example:

```powershell
Expand-Archive `
  .\Kristin_Local_Agent_v1.1.6_build116_execution_reliability_redesign.zip `
  -DestinationPath C:\dev\flutter

Set-Location `
  C:\dev\flutter\Kristin_Local_Agent_v1.1.6_build116_execution_reliability_redesign

.\kristin.cmd --version
.\kristin.cmd doctor --project .
.\kristin.cmd test --system --project .
.\kristin.cmd test --release --project .
```

On a Flutter workstation, also run:

```powershell
dart format .
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

The source directory and application data root are separate. A clean source extraction does not delete registered projects, prompts, archived research, knowledge, run history, or API tokens.

## V1.1.6 failed-run and task-plan migration

No application-data schema migration is required. The supplied v1.1.5 run and its task plan remain immutable diagnostic history. Do not resume or Retry that run because it already contains a zero-byte `docs/design/wireframes.md`, retained empty-file evidence, and the old protocol behavior that dropped direct nested write content. Prepare a fresh run so the v1.1.6 coordinator can reconstruct artifact state and enforce the new mutation-required transition.

After upgrading:

1. select the intended separate target project in Project Manager;
2. create a new Prompt Studio prompt version;
3. generate a new task plan so approved product context and least-privilege tools are compiled into each task;
4. review the normalized setup, client-side calculation, design, verification, and deployment tasks;
5. start a new run and use **Save all logs** if it fails.

Existing project files remain intact. Byte-identical rewrites are now recorded as no-op operations and will not create new rollback backups or consume mutation budget.

## V1.1.4 release-test migration

No application-data migration is required. Extract into a clean source directory and rerun the native and Kristin test commands. V1.1.4 changes test synchronization, Kristin-controlled Flutter-test concurrency, failure summarization, contracts, and release metadata. Registered projects, prompts, plans, knowledge, research archives, runs, and tokens remain in the separate application-data root.

## V1.1.3 validation-contract migration

No application-data migration is required. Use a clean source extraction and rerun formatting, analysis, Flutter tests, and the Kristin system/release commands. V1.1.3 changes one private cancellation helper, two regression contracts, version metadata, and documentation; project state is unaffected.

## V1.1.2 failed-run migration

No application-data migration is required. The old run and task plan remain immutable diagnostic history. Do not resume the v1.1.1 plan from run `run_hkkkbh7q3rNkIqtjzJuPYvsiiy`: its later user-testing task contains unsupported human recruitment and feedback instructions. Generate a new prompt version and task plan so v1.1.2 can apply capability normalization and bounded retry defaults.

The first launch of a local model can still be hardware-dependent. Review the AI Models settings before increasing the cold-load deadline beyond the eight-minute default. Stop now cancels the active provider wait; a cancelled run should be retried as a fresh linked run.

## V1.1.0 Project Manager migration

No application-data migration is required. Extract into a clean source directory and open the new **Project Manager** tab. Existing registered projects, prompt versions, task plans, knowledge, archived research, runs, and API tokens remain in the separate application-data root.

Review each detected Analyze/Test/Build/Run command before using it. For an unsupported project, add `kristin.project.json` with explicit command entries. Long-running Project Manager processes are not restored after the application exits; start them again from the Project Manager after restart.

Do not resume the failed plan from diagnostic run `run_hkk9czt4wzMPTp3bsaqLnpNOx2`. Generate a new plan so artifact-producing tasks are recompiled with the corrected governed mutation capability and duplicate deployment tasks are removed.

## V1.0.9 lineage-contract migration

No application-data migration is required. Use a clean source extraction and rerun the native and Kristin test commands. V1.0.9 changes release metadata, validation contracts, version constants, and documentation; registered projects, prompts, research archives, knowledge, run history, and API tokens remain in the separate application-data root.

Do not copy an older `VERSION_CONTROL.json`, `RELEASE.json`, `SOURCE_MANIFEST.sha256`, or release report into the new source tree. Those files are version-specific integrity evidence.

## V1.0.8 SDK environment migration

No application-data migration is required. Use a clean source extraction, then rerun the two Kristin test commands. Do not copy generated `.dart_tool`, `build`, or `windows/flutter/ephemeral` content from the older source folder. V1.0.8 forwards the required SDK environment internally and runs package resolution only once per test invocation.

## V1.0.7 failed-run recovery migration

Do not resume or Retry the failed plan created by the older build. Its task graph may contain unavailable web/design/deployment instructions and its evidence already contains the poisoned failed-memory context. After upgrading:

1. Create a separate target folder such as `C:\dev\projects\calculator-app`.
2. Register and select that folder in Kristin; do not select Kristin’s own source checkout.
3. Generate a new Prompt Studio draft and a new task plan.
4. Review the local-only capability alignment before starting the run.
5. Use **Save all logs** again if the fresh run fails.

Failed episodes remain available in Logs and Knowledge for explicit diagnosis, but they are no longer inserted into ordinary build context from generic words such as `error`, `history`, or `test`.


## Repeated-tool recovery migration

No state migration is required. Existing failed runs and their diagnostic episodes remain immutable historical records. Upgrade the source, start Kristin, then use **Retry** to create a fresh linked run. The new run starts with reset counters and applies duplicate-read deduplication and bounded evidence recovery.

The recovery cache exists only inside one active work-item attempt and is not persisted as authoritative state. Automatic probes use only tools already allowed by the work item and exclude hidden and secret-like paths.


## Failed-run retry migration

v1.0.6 does not mutate old run records. Existing failed runs retain their original attempts, counters, events, evidence, and episodic memory. Selecting **Retry** creates a new linked run with `sourceRunId`, reset counters, and a plan-scaled budget. Direct execution of a failed run now returns `run_retry_required`; use the Retry control or `POST /v1/runs/{runId}/retry`.

## v1 state additions

v1 adds:

```text
state/prompt_versions.json
state/task_plans.json
```

These collections hold immutable prompt and task-plan revisions. Existing v0.9 `prompts.json` records remain available and can continue to be edited in the legacy template surface. New AI-generated Prompt Studio drafts are saved as version records only after user review.

Task plans do not grant permissions or execute themselves. Compilation produces an ordinary governed prepared command that still requires the existing permission and execution workflow.

## Path compatibility migration

No data migration is required for the absolute-path repair. After upgrade:

- project-relative paths continue to work;
- absolute paths and local `file:` URIs that resolve inside the active project are normalized to project-relative paths;
- outside paths, traversal, NUL bytes, non-file schemes, and symbolic-link escapes remain blocked;
- correctable path input errors can receive bounded model repair turns.

Old terminal run memories containing `path_absolute_rejected` remain diagnostic history. They are not deleted and are excluded from normal automatic context unless explicitly relevant or pinned.

## v0.8 research migration

During `ProductRuntime.initialize()`, the Knowledge service checks the old archive layout and existing knowledge entries:

- ordinary notes remain notes;
- one-level v0.8 `*.source.json` and `*.search.json` files are read in place, bounded to 64 MiB per legacy file, and never refetched;
- raw source bodies, extracted text, and search JSON are copied into content-addressed object storage;
- deterministic archive IDs derived from the old relative path make the import idempotent and allow interrupted imports to repair missing linked entries;
- matching research-source/search entries are linked to imported archive records;
- malformed or oversized legacy snapshots remain untouched for manual recovery and do not block newer state.

The migration does not refetch the web, delete old snapshots, or rewrite project source files.

## Run-memory reconciliation

After interrupted-run reconciliation, Kristin scans persisted terminal runs. A succeeded, failed, cancelled, or interrupted run without a corresponding episode is summarized into `state/memory_episodes.json`. Existing episodes are matched by run ID to prevent duplicate backfill.

Failed and interrupted episodes remain available in Build & Debug → Knowledge → Run memory. Normal automatic retrieval excludes them unless the request explicitly investigates a failure or the episode is pinned.

## Derived indexes

The local index under `cache/knowledge-index/` is disposable derived state. The v0.9.3 schema-3 fingerprint causes older indexes to rebuild from authoritative knowledge and memory records. It can also be rebuilt from the Knowledge UI or API.

Prompt versions and task plans are authoritative records, not derived index content.

## Rollback considerations

A v0.9 build does not understand the v1 prompt-version and task-plan collections, although it should ignore unrelated files. Before rollback:

1. stop Kristin and all managed processes;
2. back up the complete data root;
3. export important project knowledge;
4. retain `prompts.json`, `prompt_versions.json`, and `task_plans.json` together;
5. retain `knowledge.json`, `research_archive.json`, `memory_episodes.json`, and `research-archive/` together.

Rolling back removes v1 UI/API access to generated prompt and plan history; it does not automatically delete those records.

## Historical source migration

The stale-source quarantine utilities remain available for old working folders. They move unexpected historical Dart source into a timestamped archive rather than recursively deleting it. Obsolete patch overlays and generated build/cache directories are excluded from the clean v1 package.
