# MISSION-008 — Release Engineering, Supply Chain, Signing, Installers, and Updates

**Default executor:** Worker B
**Priority:** `HIGH`
**Roadmap phases:** `P9`
**Authority:** execution overlay only; `docs/roadmap/MASTER.md` remains human authority.

## Mission objective

Build reproducible packaging, SBOM and provenance, signing, notarization, installers, secure updates, rollback, release verification, and synchronized tri-desktop release gates.

## Transfer and resume protocol

1. Re-resolve protected main, mission branch, PR, head/tree, CI, reviews, and dependency state.
2. Load this contract, the mission state, active claim, latest checkpoint, entry graph, and task interlocks.
3. Reuse valid implementation and evidence already present; never restart completed work without a proven defect.
4. Select the highest-priority dependency-satisfied task or a clearly labeled dependency-safe source/fixture/documentation packet.
5. Implement, test, document, commit, push, inspect exact-head CI, repair, obtain required independent review, and update state/checkpoint.
6. Yield only with an exact continuation point or complete the mission and release its claim.

## Current repository anchor

- No active claim. The mission is available only when its entry dependencies and ownership checks pass.

## P9 — Release engineering, installers, signing, and updates

**Packet:** `docs/roadmap/anarchy/phases/P09-release-engineering-installers-signing-and-updates.md`
**Current execution view:** `BLOCKED_BY_P8_AND_PLATFORM_ARTIFACTS`
**Test Center module:** `Release & Update Certification`

### Purpose

This is the bounded execution packet for P9. It preserves the task wording from the v3.2 strategic plan while requiring every worker to reconcile against the live repository before editing.

### Exact task program

| Task | Work | Dependencies | Required output | Done when |
|---|---|---|---|---|
| `P9-001` | Redesign CI pipeline | `P0-003`, `P8-001` | Split PR, nightly, platform, adversarial, benchmark, and release workflows with artifact retention. | Failures do not hide downstream evidence and required gates are enforced. |
| `P9-002` | Extend generated-state policy | `P3-001`, `P4-011` | Exclude Playwright, Node, browser profiles, traces, downloads, dataset intermediates, and native build state. | Validator, scanner, and packager use one tested policy. |
| `P9-003` | Reproducible dependency and browser lock | `P3-001`, `P8-008` | Lock Flutter/Dart, Python, automation host, browser binaries, native tools, and checksums. | Clean builders resolve identical inputs. |
| `P9-004` | SBOM and provenance | `P9-001`, `P9-003` | Generate source/build SBOMs, GitHub artifact attestations, checksums, and SLSA-aligned provenance. | Consumer can verify artifact to source/workflow. |
| `P9-005` | Windows installer and signing | `P9-003` | Build installer, code sign, timestamp, verify, install, upgrade, rollback, and uninstall on clean images. | All Windows release tests pass. |
| `P9-006` | macOS signing and notarization | `P9-003` | Sign nested binaries/helpers, hardened runtime, notarize, staple, verify, install, upgrade, rollback, uninstall. | All macOS release tests pass. |
| `P9-007` | Linux packages | `P9-003` | Produce supported signed package/bundle, dependency declarations, install/upgrade/rollback/uninstall tests. | Supported distributions pass. |
| `P9-008` | TUF repository and channels | `P1-008`, `P9-004` | Create offline root, delegated nightly/alpha/beta/stable/emergency targets, snapshot, timestamp, and publication. | Metadata expiry, rollback, freeze, mix-and-match, and compromise tests pass. |
| `P9-009` | Updater and rollback engine | `P9-008` | Download, verify, stage, stop workers, backup state, install, health-check, rollback, and report. | Injected failure at every stage returns to working version. |
| `P9-010` | Database upgrade compatibility | `P8-002`, `P9-009` | Test N-2 upgrade, N-1 rollback where supported, forward-only declarations, and backups. | No unsupported migration path is offered. |
| `P9-011` | Reproducible unsigned payload comparison | `P9-003`, `P9-004` | Build twice on clean builders and compare unsigned payloads; isolate intended signature/timestamp differences. | Payloads match or documented nondeterminism blocks release. |
| `P9-012` | Release command and evidence bundle | `P9-001`, `P9-004` | Create one release orchestrator that refuses missing gates and exports reports, SBOM, provenance, hashes, and notes. | A release cannot be labeled compiled/stable without all evidence. |
| `P9-013` | Support, privacy, license, and EULA documents | `P5-011`, `P8-010` | Finalize support matrix, privacy, retention, third-party notices, license, terms, and Owner Mode disclosure. | Human legal review recorded. |
| `P9-014` | Release website and verification guide | `P9-004`, `P9-012` | Publish checksums, signatures, provenance verification, install, update, rollback, and known limits. | Fresh user can verify an artifact independently. |
| `P9-015` | Key compromise drill | `P9-008`, `P9-012` | Simulate targets/timestamp/root compromise, rotate/revoke, issue emergency metadata, and block old artifacts. | Runbook succeeds from offline root. |
| `P9-016` | Bad update drill | `P9-009` | Publish faulty beta fixture, detect, halt rollout, rollback, and preserve state. | Staged rollout stops automatically. |

### Test Center deliverables

- `P9-TC-001` CI lane and artifact-retention verification
- `P9-TC-002` generated-state packaging policy
- `P9-TC-003` reproducible dependency/browser locks
- `P9-TC-004` SBOM/provenance verification
- `P9-TC-005` Windows install/update/rollback/uninstall
- `P9-TC-006` macOS sign/notarize/install/update/rollback
- `P9-TC-007` Linux package install/update/rollback
- `P9-TC-008` TUF attack suite
- `P9-TC-009` updater injected-failure matrix
- `P9-TC-010` state/database compatibility
- `P9-TC-011` two-clean-build payload comparison
- `P9-TC-012` release-command refusal tests
- `P9-TC-013` document/legal checklist coverage
- `P9-TC-014` consumer artifact verification scenario
- `P9-TC-015` key compromise drill
- `P9-TC-016` bad update drill

### Acceptance scenarios

- Add one criterion-scoped acceptance scenario for every user-visible outcome.

### Exit gate

- The phase's mandatory Test Center module, acceptance scenarios, platform lanes, regression coverage, evidence, and certification pass according to Appendix S.
- Signed installers/packages pass clean-machine install, upgrade, rollback, and uninstall.
- TUF metadata and updater tests pass.
- SBOM, SLSA-aligned provenance, attestations, hashes, and verification guide exist.
- Release command refuses incomplete evidence.

## Cross-mission task interlocks

- `P9-001` waits for `P0-003` from `MISSION-001`.
- `P9-001` waits for `P8-001` from `MISSION-002`.
- `P9-002` waits for `P3-001` from `MISSION-003`.
- `P9-002` waits for `P4-011` from `MISSION-004`.
- `P9-003` waits for `P3-001` from `MISSION-003`.
- `P9-003` waits for `P8-008` from `MISSION-002`.
- `P9-008` waits for `P1-008` from `MISSION-001`.
- `P9-010` waits for `P8-002` from `MISSION-002`.
- `P9-013` waits for `P5-011` from `MISSION-005`.
- `P9-013` waits for `P8-010` from `MISSION-002`.

## Git, collision, and merge contract

- One active claim per mission. A replacement worker must receive a recorded yield or transfer.
- Do not edit another active mission's exclusive paths or shared authority without an explicit coordination packet.
- Workers may commit, push, update their draft PR, and iterate CI inside their bounded claim.
- No blanket right to bypass branch protection, required checks, security review, dependency gates, or roadmap authority.
- A materially changed exact candidate invalidates commit-bound reviews and evidence.
- Every significant push updates mission state and creates or supersedes a checkpoint.

## Mission definition of done

The mission is complete only when every assigned roadmap task is truthfully complete; applicable unit, contract, component, integration, negative, regression, platform, recovery, performance, acceptance, certification, and release gates pass; evidence and documentation are durable; required independent reviews bind the final exact commit/tree; and the integrated product capability works on every mandatory platform claimed by the roadmap.

## Resume command

```text
Take the repo. You are Worker B. Take MISSION-008 and continue autonomously.
```
