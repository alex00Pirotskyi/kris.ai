# Kristin

Kristin is a local-first desktop AI agent built with Flutter. The repository contains the desktop product, local model/runtime integration, governed project automation, browser and Web Studio foundations, research/data tooling, tests, and the release/security contracts used to validate source delivery.

The current source tree is a development product, not a GA release. Source capabilities that have landed are intentionally separated from platform qualification, packaging/signing, independent review, and production-support claims.

## What is in the product today

- **Local chat and model runtime** with Ollama-oriented local model discovery, warm reuse, cancellation, load progress, protocol repair, and local conversation state.
- **Prompt Studio foundation** with bounded clarification, prompt generation, execution-plan review, fast paths, provider caching, and bounded execution retry behavior. P25 remains active product work; landing the foundation does not mean the full P25 roadmap is complete.
- **Project workspace and governed execution** for project inspection, analyze/test/build/run/stop flows, safe file operations, audit boundaries, and task execution.
- **Owner Mode source integration** including interactive PTY/process lifecycle work. Formal P2 platform/release qualification remains separate from the presence of this source.
- **Browser automation and Web Studio foundations** including browser replay, persistent profiles, takeover/resume, editor/live preview work, and local preview contracts. Broader P5 closure is still unfinished.
- **Research and data workspace** with search planning, fetching/extraction, immutable citations/source versions, local indexing, datasets, source-change monitoring, and Web Preview.
- **Local knowledge and memory foundations** with inspectable citations and local persistence.

## Development quick start

Kristin now has one small development entry point:

```text
python dev.py doctor
python dev.py bootstrap
python dev.py run
```

You can name the desktop target explicitly:

```text
python dev.py bootstrap windows
python dev.py run windows

python dev.py bootstrap macos
python dev.py run macos

python dev.py bootstrap linux
python dev.py run linux
```

`bootstrap` is the explicit setup command. It enables the host desktop target, creates a missing Flutter desktop runner only when necessary, resolves Flutter packages, and installs the Node automation host when npm is available.

`run` is deliberately fast. It does **not** run `flutter clean`, regenerate platform runners, execute the full test suite, run release validation, rewrite formatting, or regenerate the tracked source manifest before starting the app.

The compatibility launchers remain available:

- Windows: `RUN_WINDOWS.bat`
- macOS: `RUN_MAC.command`
- Linux: `RUN_LINUX.sh`

They delegate to `dev.py run <platform>`.

## Development commands

```text
python dev.py doctor [windows|macos|linux]
python dev.py bootstrap [windows|macos|linux]
python dev.py run [windows|macos|linux]
python dev.py check
python dev.py ci
python dev.py package
```

- `doctor` checks the local toolchain and desktop-runner state.
- `bootstrap` performs explicit one-time/when-needed setup.
- `run` starts the Flutter desktop app without release-scale validation.
- `check` runs the fast non-mutating developer checks: core protocol/source inventory, format scope, analyzer, and focused product contracts.
- `ci` runs the repository's existing full verification path.
- `package` invokes the deterministic source release packager.

On Windows, `py -3 dev.py ...` is equivalent when the Python launcher is preferred.

### Toolchain

The repository is currently validated around:

- Flutter / Dart from the locked repository toolchain
- Python 3 for contracts, validation, and development tooling
- Node.js `24.18.0` for `automation_host`
- Ollama for the primary local-model workflow

Run `python dev.py doctor` first when a machine is not ready.

## Repository map

```text
lib/product/          Desktop product/runtime/UI source
test/product/         Product and source-contract tests
automation_host/      PTY/browser automation host
authority_service/    Native authority-service source and connectors
services/             Restricted/native worker services
migrations/           Local data migrations
schemas/              Protocol/data schemas
config/               Current runtime/security/test contracts
tool/                 Validation, release, and repository tooling
docs/                 Architecture, roadmap, recipes, decisions, history
release/              Current policy/schemas plus historical validation material
tasks/                Current and historical task packets
.github/workflows/    CI and compatibility gates
```

The repository still contains more historical control-plane/evidence material than the desired steady state. Repository rehabilitation is removing that coupling in bounded steps rather than rewriting the product or discarding useful history.

## Validation

For normal product work, prefer:

```text
python dev.py check
```

Before a release-sensitive change:

```text
python dev.py ci
```

The full CI path includes strict source/roadmap/security contracts, analyzer and Flutter tests, automation-host validation, and release-source validation. GitHub also exercises platform-specific Windows, macOS, and Linux gates.

Validation success means the tested source/candidate passed those gates. It does not by itself establish signed distribution, production support, independent human approval, or GA readiness.

## Local-first and security boundary

Kristin is designed around local execution and local project/data access. Networked capabilities such as research are explicit product features rather than a requirement for the core local model workflow. High-risk project actions are governed by capability/runtime boundaries, audit contracts, and project path restrictions.

Do not commit credentials, local model secrets, signing material, or generated local state. See [SECURITY.md](SECURITY.md) for the repository security policy.

## Current delivery truth

The active mainline contains substantial source delivery across the early product phases, but phase/source status is not the same thing as release status:

- P1 canonical source/evidence closure is present; P1A remains a separate qualification track.
- P2 has major Owner Mode source delivery, while its canonical release/platform qualification remains incomplete.
- P3 browser/Web Studio source has landed; formal evidence/acceptance is tracked separately.
- P4 research/data source is landed and has exact-tree product validation.
- P5 is not complete.
- P25 Prompt Studio foundation is landed and its roadmap remains active.

Signing/notarization, independent review, legal/license authority, and other human/credential-dependent release requirements are deliberately not represented as complete unless they have actually been provisioned.

## Contributing and deeper documentation

- [CONTRIBUTING.md](CONTRIBUTING.md) — contribution workflow
- [SECURITY.md](SECURITY.md) — security policy
- [CHANGELOG.md](CHANGELOG.md) — release/change history
- [`docs/roadmap/MASTER.md`](docs/roadmap/MASTER.md) — current roadmap control document
- [`docs/roadmap/ASSURANCE_MODEL.md`](docs/roadmap/ASSURANCE_MODEL.md) — assurance terminology and boundaries
- [`docs/recipes/P3_BROWSER_TASK_RECIPES.md`](docs/recipes/P3_BROWSER_TASK_RECIPES.md) — browser task recipes

Historical progress/evidence documents are retained for traceability while the active developer surface is being simplified.
