# Kristin command-line diagnostics and release tests

Kristin v1.9.0+190 ships a standard-library Python CLI in `tool/kristin_cli.py`. On Linux, ordinary bounded project commands now run through the namespace sandbox worker when it is available, while sandbox self-tests stay in trusted host mode to avoid nested-userns false failures. It can diagnose a source checkout before Flutter is installed and, when Flutter is available, run the authoritative formatter, analyzer, and behavioral tests.

Dart and Flutter commands use a bounded SDK environment profile so Windows Pub-cache locations, package mirrors, enterprise proxies, and certificate overrides match the invoking terminal. Ordinary project commands retain the narrower default environment. Release source validation is source-only; SDK gates are run once by the outer test command.

## Launchers

PowerShell does not execute files from the current directory without an explicit prefix:

```powershell
.\kristin.cmd <command>
```

macOS or Linux:

```bash
./kristin <command>
```

Set `PYTHON_BIN` on macOS/Linux to select a particular Python 3 executable.

Running the launcher with no command prints onboarding and returns success:

```powershell
.\kristin.cmd
```

## Canonical v1.9 milestone gates

Run the cumulative source gates independently so one long diagnostic process cannot hide another result:

```bash
./kristin test --workflow-kernel --project . --json
./kristin test --project-manager --project . --json
./kristin test --execution-intelligence --project . --json
./kristin test --replay-all --project . --json
./kristin test --system --project . --json
```

Interoperability and release-governance diagnostics:

```bash
./kristin interoperability --self-test --json
```

Project Manager 2 commands are forwarded through the canonical CLI:

```bash
./kristin project status --project . --json
./kristin project action analyze --project . --json
./kristin project action test --project . --json
./kristin project action build --project . --json
./kristin project start --project . --json
./kristin project process-status <process-id> --json
./kristin project stop <process-id> --json
```

Execution-intelligence diagnostics accept versioned JSON documents and produce deterministic reports:

```bash
./kristin intelligence budget execution
./kristin intelligence route --input route-request.json --output route-decision.json
./kristin intelligence progress --input snapshots.json --output progress.json
./kristin intelligence converge --input progress-state.json --output convergence.json
./kristin intelligence verify --input verification-input.json --output verification-report.json
./kristin intelligence compact --input history.json --output compact-history.json
```

These commands diagnose and simulate governed behavior. They do not widen model, file, network, process, or secret permissions.

## Doctor

```powershell
.\kristin.cmd doctor --project .
```

`--project` may be omitted or supplied without a value to select the current directory. Doctor checks project availability/readability, detected profile, required toolchains, test and run profiles, Git, reported free space, local Ollama reachability, and Kristin source-release structure when applicable.

Machine-readable output:

```powershell
.\kristin.cmd doctor --project . --json --output reports\doctor.json
```

## Test ladder

### Quick

```powershell
.\kristin.cmd test --quick --project .
```

For the Kristin source tree, Quick runs:

- optional Dart grammar parsing;
- Python source compilation;
- generated protocol and migration freshness checks;
- 14-case SQLite workflow-kernel crash/recovery gate;
- production diagnostic replay;
- governed architecture validation;
- bounded secret scanning.

It does not require Flutter.

### Durable workflow kernel

```powershell
.\kristin.cmd test --workflow-kernel --project .
```

This network-free gate applies the reviewed SQL migrations to a real SQLite database and verifies append-only events, uncommitted crash rollback, durable result replay, compensation recovery, committed-run recovery, projection rebuild, concurrent writers, migration backup/restore, legacy import ledgers, and Dart integration contracts.

Inspect an application data root:

```powershell
.\kristin.cmd workflow --data-root C:\path\to\kristin-data --json
.\kristin.cmd workflow --data-root C:\path\to\kristin-data --run-id run-123 --json
```

The command opens SQLite read-only, reports schema and integrity state, and returns bounded durable events/checkpoints/idempotency/compensation details.

### Golden diagnostic replay

```powershell
.\kristin.cmd test --replay-all --project .
```

This command always runs the compact redacted Python replay corpus. When Flutter is installed, it also runs `test/product/diagnostic_replay_test.dart` with one worker. The ordinary Quick gate includes the compact replay automatically.

### Full

```powershell
.\kristin.cmd test --full --project .
```

Full includes Quick and, when Flutter is installed:

```text
dart format --output=none --set-exit-if-changed .
flutter pub get
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
```

Kristin pins its own Flutter test gates to one worker so local HTTP and cancellation fixtures remain deterministic under repeated Windows release validation. Direct developer test commands may choose another concurrency value.

Formatting is checked without rewriting source. For another project, Kristin runs the detected direct-command test profile and may run its build profile. Commands are not passed through a command shell. Ordinary commands receive the reduced default environment; Dart and Flutter commands receive the bounded SDK profile described above.

### System

```powershell
.\kristin.cmd test --system --project .
```

System includes Full and deterministic v1 fixtures covering:

- safe in-project absolute-path and `file:` URI normalization;
- continued rejection of outside, traversal, and escape paths;
- bounded recovery from correctable tool arguments;
- AI Prompt Composer schemas and repair contracts;
- immutable prompt versions;
- adaptive 1–100 task plans;
- dependency and parent-hierarchy validation;
- immutable task-plan revisions;
- selected-task compilation with transitive prerequisites;
- Prompt Studio UI, persistence, API, and behavioral-test wiring;
- plan-scaled budgets, fresh linked retries, model-request lifecycle events, stagnant-loop guards, and redacted diagnostic export.
- SDK environment selection, Windows Pub-cache forwarding, and single-pass release validation.
- exact-model Ollama preloading, bounded cold-load retry, progress events, and provider cancellation contracts;
- capability normalization that replaces unsupported human studies with local objective checks and a manual usability checklist;
- nested command-array normalization, project-scoped Git specialization, and process-path boundary checks;
- byte-identical no-op mutation accounting and repeated no-op recovery;
- product-specific wireframe evidence, retry continuity, and least-privilege Prompt Studio task alignment.

When Flutter is installed, the focused behavioral suites `test/product/v1_product_preview_test.dart` and `test/product/budget_diagnostics_test.dart` are also run after the complete Flutter test suite.

### Release

```powershell
.\kristin.cmd test --release --project .
```

Release includes System, runs the complete source-release validator, then builds two clean ZIP archives independently and compares their SHA-256 hashes. The check fails on packaging errors, duplicate ZIP members, multiple top-level folders, corruption, or nondeterministic output.

## Test reports

Every `doctor`, `test`, and `report` invocation writes three correlated artifacts under `reports/` unless `--output` is supplied:

```text
*.json   structured result
*.md     readable summary
*.log    bounded raw command output
```

A non-zero exit code means at least one blocking check failed. `WARN` and `SKIP` are reported separately from failures.

## Prompt Studio 2 compilation and evaluation

The v1.5 commands operate on canonical JSON documents and perform no project side effects:

```bash
./kristin plan-compile \
  --spec test/product/fixtures/prompt_studio_v2/specification.json \
  --plan test/product/fixtures/prompt_studio_v2/plan_100.json \
  --policy test/product/fixtures/prompt_studio_v2/policy.local_only.json \
  --output reports/plan-compilation.json \
  --fail-on-errors

./kristin prompt-evaluate \
  --baseline test/product/fixtures/prompt_studio_v2/prompt.baseline.json \
  --candidate test/product/fixtures/prompt_studio_v2/prompt.candidate.json \
  --dataset test/product/fixtures/prompt_studio_v2/evaluation_dataset.json \
  --output reports/prompt-impact.json

./kristin plan-compare \
  --spec test/product/fixtures/prompt_studio_v2/specification.json \
  --baseline path/to/baseline-plan.json \
  --candidate path/to/candidate-plan.json \
  --policy test/product/fixtures/prompt_studio_v2/policy.local_only.json \
  --output reports/plan-impact.json
```

`plan-compile` returns the canonical compilation report and exits nonzero with `--fail-on-errors` when blocking issues remain. `prompt-evaluate` compares prompt versions against a deterministic user-authored dataset. `plan-compare` compiles two plan revisions under the same specification and policy and reports changes in executability, issue counts, quality, schedule, and hashes.

The compiler is side-effect free. It does not imply that v1.4 sandbox workers exist; sandbox-dependent tasks fail closed unless an explicit legacy unsandboxed dry-run override is present in the policy.

Regenerate and verify the release corpus with:

```bash
python tool/generate_prompt_studio_contracts.py --check
python tool/generate_prompt_studio_fixtures.py --check
python tool/prompt_studio_v2_test.py
```

## Project Manager commands

The CLI uses the same detected project profile as the desktop Project Manager:

```powershell
.\kristin.cmd doctor --project .
.\kristin.cmd analyze --project .
.\kristin.cmd test --quick --project .
.\kristin.cmd build --project .
.\kristin.cmd run --project .
```

`analyze` runs the detected static-analysis commands. `build` runs the detected build command. Both produce bounded structured results and non-zero exit status on blocking failure. A custom `kristin.project.json` can define `analyze`, `test`, `build`, and `run` command objects.

## Run detection

```powershell
.\kristin.cmd run --project .
```

The default is a dry run that prints the detected command. Start it explicitly with:

```powershell
.\kristin.cmd run --project . --execute
```

Long-running processes remain ordinary child processes in this source preview; the CLI does not add an OS sandbox.

## Logs

```powershell
.\kristin.cmd logs --tail 100
.\kristin.cmd logs --data-root C:\path\to\kristin-data --tail 100
```

The command reads bounded recent durable `run_events` from SQLite and audit records; it uses legacy `events.jsonl` only when no workflow database exists. Save a redacted diagnostic ZIP with retained events, audit data, run state, a readable run-diagnostic summary, evidence metadata, settings fingerprints, and bounded managed-process logs:

```powershell
.\kristin.cmd logs --export
.\kristin.cmd logs --export --run-id run-123
.\kristin.cmd logs --export --run-id run-123 --output .\reports\kristin-diagnostics.zip
```

Source-like payload fields are replaced by hashes and recognized secrets are redacted. Review the ZIP before sharing it.

## Knowledge, research archive, and run memory

Choose the same data root and project ID used by the desktop runtime:

```powershell
.\kristin.cmd knowledge `
  --data-root C:\path\to\kristin-data `
  --project-id project-123
```

Provenance records:

```powershell
.\kristin.cmd knowledge --data-root C:\path\to\data --project-id project-123 --archive
```

Run memory:

```powershell
.\kristin.cmd knowledge --data-root C:\path\to\data --project-id project-123 --memory
```

Diagnostic search:

```powershell
.\kristin.cmd knowledge `
  --data-root C:\path\to\data `
  --project-id project-123 `
  --query "how tests were repaired" `
  --limit 10
```

The CLI reads persisted state without starting Flutter. Its query mode is intentionally lexical and diagnostic; the desktop runtime and loopback API use the full hybrid retrieval algorithm and return structured citations.

## Combined report

```powershell
.\kristin.cmd report --project . --output reports\combined.json
```

This combines Doctor and Quick Test results, including product version, UTC generation time, selected project, detected profile, statuses, commands, exit codes, durations, and bounded output.
