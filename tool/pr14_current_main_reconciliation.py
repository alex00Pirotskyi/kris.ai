#!/usr/bin/env python3
"""Discover and execute the exact PR #14 reconciliation with protected main.

Discovery is read-only: it attempts a local merge, records every unmerged path
and index stage, then aborts. Execution is disabled until the reviewed config
sets ``ready`` and pins the exact conflict set and one resolution strategy per
conflict.

The executable path runs only from a protected-main push. It merges that exact
control commit into the exact governed P1/P2 target, applies only reviewed
resolutions, regenerates the governed source manifest, validates P0/P1/P2
contracts, creates a two-parent reconciliation commit, and writes a receipt.
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import json
import os
import pathlib
import subprocess
import sys
import traceback
from typing import Any, Mapping, Sequence

SCHEMA_VERSION = "1.0.0"
ROADMAP_AUTHORITY = "docs/roadmap/MASTER.md"
RECONCILIATION_DOC = "docs/progress/2026-08-05-pr14-current-main-reconciliation.md"
CI_PATH = ".github/workflows/ci.yml"
SOURCE_MANIFEST = "SOURCE_MANIFEST.sha256"
BOOTSTRAP_NAME = "Install hash-locked P1/P2 Python test dependencies"
BOOTSTRAP_COMMAND = "python tool/v71r12_bootstrap_hosted_python.py --project ."
KNOWN_WORKFLOW_REJECTIONS = (
    "refusing to allow a GitHub App to create or update workflow",
    "workflows permission",
)
ALLOWED_STRATEGIES = {"ours", "theirs", "delete", "source_manifest", "compose_ci"}


class ReconciliationError(RuntimeError):
    pass


@dataclasses.dataclass(frozen=True)
class Config:
    repository: str
    target_branch: str
    expected_target_head: str
    minimum_main_ancestor: str
    ready: bool
    expected_conflicts: tuple[str, ...]
    resolutions: Mapping[str, str]


@dataclasses.dataclass
class CommandResult:
    returncode: int
    output: str


class Transcript:
    def __init__(self) -> None:
        self.lines: list[str] = []

    def write(self, value: str) -> None:
        self.lines.append(value)
        print(value, flush=True)

    def text(self) -> str:
        return "\n".join(self.lines) + ("\n" if self.lines else "")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ReconciliationError(message)


def run(
    transcript: Transcript,
    command: Sequence[str],
    *,
    cwd: pathlib.Path,
    check: bool = True,
) -> CommandResult:
    rendered = " ".join(command)
    transcript.write(f"$ {rendered}")
    completed = subprocess.run(
        tuple(command),
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    output = completed.stdout or ""
    if output:
        transcript.write(output.rstrip())
    if check and completed.returncode != 0:
        raise ReconciliationError(
            f"command failed ({completed.returncode}): {rendered}"
        )
    return CommandResult(completed.returncode, output)


def output(transcript: Transcript, command: Sequence[str], *, cwd: pathlib.Path) -> str:
    return run(transcript, command, cwd=cwd).output.strip()


def valid_sha(value: Any) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 40
        and all(ch in "0123456789abcdef" for ch in value)
    )


def load_config(path: pathlib.Path) -> Config:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ReconciliationError(f"cannot load config {path}: {exc}") from exc
    require(isinstance(raw, Mapping), "config must be an object")
    require(raw.get("schemaVersion") == SCHEMA_VERSION, "unsupported schemaVersion")
    require(raw.get("roadmapAuthority") == ROADMAP_AUTHORITY, "roadmap authority mismatch")
    repository = raw.get("repository")
    target_branch = raw.get("targetBranch")
    expected_target_head = raw.get("expectedTargetHead")
    minimum_main_ancestor = raw.get("minimumMainAncestor")
    ready = raw.get("ready")
    expected_conflicts = raw.get("expectedConflicts")
    resolutions = raw.get("resolutions")
    require(isinstance(repository, str) and repository.count("/") == 1, "invalid repository")
    require(isinstance(target_branch, str) and target_branch, "invalid targetBranch")
    require(valid_sha(expected_target_head), "invalid expectedTargetHead")
    require(valid_sha(minimum_main_ancestor), "invalid minimumMainAncestor")
    require(isinstance(ready, bool), "ready must be boolean")
    require(isinstance(expected_conflicts, list), "expectedConflicts must be an array")
    require(all(isinstance(row, str) and row for row in expected_conflicts), "invalid conflict path")
    require(len(expected_conflicts) == len(set(expected_conflicts)), "duplicate conflict path")
    sorted_conflicts = tuple(sorted(expected_conflicts))
    require(tuple(expected_conflicts) == sorted_conflicts, "expectedConflicts must be sorted")
    require(isinstance(resolutions, Mapping), "resolutions must be an object")
    for key, value in resolutions.items():
        require(isinstance(key, str) and key, "invalid resolution path")
        require(value in ALLOWED_STRATEGIES, f"invalid resolution strategy for {key}: {value}")
    if ready:
        require(set(resolutions) == set(expected_conflicts), "ready config must resolve every conflict exactly")
    else:
        require(not expected_conflicts and not resolutions, "discovery config must not pre-authorize conflicts")
    return Config(
        repository=repository,
        target_branch=target_branch,
        expected_target_head=expected_target_head,
        minimum_main_ancestor=minimum_main_ancestor,
        ready=ready,
        expected_conflicts=sorted_conflicts,
        resolutions=dict(resolutions),
    )


def git_head(transcript: Transcript, repo: pathlib.Path) -> str:
    return output(transcript, ("git", "rev-parse", "HEAD"), cwd=repo)


def git_branch(transcript: Transcript, repo: pathlib.Path) -> str:
    return output(transcript, ("git", "branch", "--show-current"), cwd=repo)


def ensure_clean(transcript: Transcript, repo: pathlib.Path) -> None:
    require(
        output(transcript, ("git", "status", "--porcelain"), cwd=repo) == "",
        f"checkout is dirty: {repo}",
    )


def verify_target(transcript: Transcript, target: pathlib.Path, config: Config) -> None:
    require(git_head(transcript, target) == config.expected_target_head, "target head mismatch")
    require(git_branch(transcript, target) == config.target_branch, "target branch mismatch")
    ensure_clean(transcript, target)
    run(transcript, ("git", "fetch", "origin", config.target_branch), cwd=target)
    remote = output(
        transcript,
        ("git", "rev-parse", f"origin/{config.target_branch}"),
        cwd=target,
    )
    require(remote == config.expected_target_head, f"remote target mismatch: {remote}")


def merge_in_progress(transcript: Transcript, repo: pathlib.Path) -> bool:
    result = run(
        transcript,
        ("git", "rev-parse", "--verify", "-q", "MERGE_HEAD"),
        cwd=repo,
        check=False,
    )
    return result.returncode == 0


def abort_merge(transcript: Transcript, repo: pathlib.Path) -> None:
    if merge_in_progress(transcript, repo):
        run(transcript, ("git", "merge", "--abort"), cwd=repo)


def conflict_paths(transcript: Transcript, repo: pathlib.Path) -> tuple[str, ...]:
    value = output(
        transcript,
        ("git", "diff", "--name-only", "--diff-filter=U"),
        cwd=repo,
    )
    return tuple(sorted(filter(None, value.splitlines())))


def conflict_stages(transcript: Transcript, repo: pathlib.Path) -> list[dict[str, Any]]:
    value = output(transcript, ("git", "ls-files", "-u"), cwd=repo)
    rows: list[dict[str, Any]] = []
    for line in value.splitlines():
        if not line:
            continue
        metadata, path = line.split("\t", 1)
        mode, sha, stage = metadata.split()
        rows.append({"path": path, "mode": mode, "sha": sha, "stage": int(stage)})
    return rows


def write_json(path: pathlib.Path, payload: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def discover(
    *,
    config_path: pathlib.Path,
    target: pathlib.Path,
    base_sha: str,
    receipt: pathlib.Path,
) -> int:
    transcript = Transcript()
    config = load_config(config_path)
    require(valid_sha(base_sha), "invalid discovery base SHA")
    verify_target(transcript, target, config)
    run(transcript, ("git", "fetch", "origin", base_sha), cwd=target)
    run(
        transcript,
        ("git", "config", "user.name", "Kristin Reconciliation Discovery"),
        cwd=target,
    )
    run(
        transcript,
        ("git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"),
        cwd=target,
    )
    merge = run(
        transcript,
        ("git", "merge", "--no-ff", "--no-commit", base_sha),
        cwd=target,
        check=False,
    )
    conflicts = conflict_paths(transcript, target)
    stages = conflict_stages(transcript, target)
    cached = tuple(
        sorted(
            filter(
                None,
                output(transcript, ("git", "diff", "--cached", "--name-only"), cwd=target).splitlines(),
            )
        )
    )
    require(
        merge.returncode == 0 or conflicts,
        f"merge failed without merge conflicts: rc={merge.returncode}",
    )
    if config.ready:
        require(conflicts == config.expected_conflicts, f"conflict set drift: {conflicts}")
    payload = {
        "schemaVersion": SCHEMA_VERSION,
        "mode": "discover",
        "capturedAtUtc": utc_now(),
        "repository": config.repository,
        "roadmapAuthority": ROADMAP_AUTHORITY,
        "targetBranch": config.target_branch,
        "targetHead": config.expected_target_head,
        "baseHead": base_sha,
        "configReady": config.ready,
        "mergeReturnCode": merge.returncode,
        "conflicts": list(conflicts),
        "conflictStages": stages,
        "autoMergedIndexPaths": list(cached),
    }
    write_json(receipt, payload)
    transcript.write(json.dumps(payload, indent=2, sort_keys=True))
    abort_merge(transcript, target)
    ensure_clean(transcript, target)
    return 0


def compose_ci(
    transcript: Transcript,
    target: pathlib.Path,
    *,
    control_sha: str,
) -> None:
    main_value = output(
        transcript,
        ("git", "show", f"{control_sha}:{CI_PATH}"),
        cwd=target,
    ) + "\n"
    anchor = "      - run: flutter pub get\n\n      - name: Capture CI environment\n"
    insertion = (
        "      - run: flutter pub get\n\n"
        f"      - name: {BOOTSTRAP_NAME}\n"
        f"        run: {BOOTSTRAP_COMMAND}\n\n"
        "      - name: Capture CI environment\n"
    )
    if BOOTSTRAP_NAME not in main_value:
        require(main_value.count(anchor) == 1, "main CI bootstrap anchor mismatch")
        main_value = main_value.replace(anchor, insertion, 1)
    require(main_value.count(BOOTSTRAP_NAME) == 1, "composed CI bootstrap step mismatch")
    require(main_value.count(BOOTSTRAP_COMMAND) == 1, "composed CI bootstrap command mismatch")
    require(
        "  push:\n    branches:\n      - main\n  pull_request:\n" in main_value,
        "composed CI does not restrict push validation to main",
    )
    for obsolete in ("pr14-documented-repair", "pr54-source-manifest-candidate"):
        require(obsolete not in main_value, f"obsolete CI helper remains: {obsolete}")
    (target / CI_PATH).write_text(main_value, encoding="utf-8", newline="\n")
    run(transcript, ("git", "add", "--", CI_PATH), cwd=target)


def resolve_conflicts(
    transcript: Transcript,
    target: pathlib.Path,
    *,
    config: Config,
    control_sha: str,
    observed: tuple[str, ...],
) -> None:
    require(observed == config.expected_conflicts, f"conflict set mismatch: {observed}")
    for path in observed:
        strategy = config.resolutions[path]
        transcript.write(f"RESOLUTION path={path} strategy={strategy}")
        if strategy == "ours":
            run(transcript, ("git", "checkout", "--ours", "--", path), cwd=target)
            run(transcript, ("git", "add", "--", path), cwd=target)
        elif strategy == "theirs":
            run(transcript, ("git", "checkout", "--theirs", "--", path), cwd=target)
            run(transcript, ("git", "add", "--", path), cwd=target)
        elif strategy == "delete":
            run(transcript, ("git", "rm", "--", path), cwd=target)
        elif strategy == "source_manifest":
            require(path == SOURCE_MANIFEST, "source_manifest strategy used on wrong path")
            run(transcript, ("git", "checkout", "--ours", "--", path), cwd=target)
            run(transcript, ("git", "add", "--", path), cwd=target)
        elif strategy == "compose_ci":
            require(path == CI_PATH, "compose_ci strategy used on wrong path")
            compose_ci(transcript, target, control_sha=control_sha)
        else:
            raise ReconciliationError(f"unsupported strategy: {strategy}")
    remaining = conflict_paths(transcript, target)
    require(not remaining, f"unresolved conflicts remain: {remaining}")


def reconciliation_document(
    *,
    config: Config,
    control_sha: str,
    conflicts: tuple[str, ...],
    resolutions: Mapping[str, str],
) -> str:
    rows = "\n".join(
        f"| `{path}` | `{resolutions[path]}` |" for path in conflicts
    ) or "| None | Clean merge |"
    return f"""# PR #14 reconciliation with protected main — 2026-08-05

## Roadmap authority

`docs/roadmap/MASTER.md` is the human implementation authority. `docs/roadmap/roadmap.yaml` remains the machine dependency ledger.

## Exact parents

- P1/P2 target parent: `{config.expected_target_head}`
- Protected-main parent: `{control_sha}`
- Target branch: `{config.target_branch}`

The resulting candidate must be a two-parent merge commit in that order.

## Why reconciliation was required

After the documented P1/P2 repair was produced and receipted, protected `main` advanced through repository branch hygiene, the protected recovery handoff, and the recovery bookkeeping correction. GitHub therefore reported PR #14 as `mergeable_state: dirty`. Landing without an explicit merge would either discard protected-main controls or overwrite the repaired P1/P2 source.

## Conflict discovery and resolution

The conflict set was discovered read-only on the reconciliation controller PR, including Git index stage identities, before any resolution was authorized.

| Path | Reviewed resolution |
|---|---|
{rows}

`compose_ci` means the current protected-main product workflow is retained, the existing hash-locked P1/P2 bootstrap is inserted exactly once, push validation is restricted to `main`, pull-request validation remains enabled, and the completed PR #48/PR #54 one-shot jobs remain retired. `source_manifest` means the conflicted manifest is not selected from either parent; it is regenerated after the full merged tree and this record exist.

## Significant changes preserved from protected main

- exact SHA-pinned branch-hygiene automation and its durable cleanup record;
- the completed protected PR #14 recovery handoff and bookkeeping correction;
- current roadmap authority and execution documentation policy;
- product-gate push hygiene, preventing duplicate required contexts on feature branches;
- removal of obsolete PR #48 and PR #54 one-shot jobs from the permanent product workflow.

## Significant changes preserved from the P1/P2 target

- complete P1/P2 owner-risk QA-preview source and native authority-service integration;
- the repaired owner-risk P1A source-lane contract;
- the wheel-only, hash-locked Python dependency bootstrap before full P1 closure;
- the durable PR #14 recovery record and governed P2 source inventory.

## Validation before candidate creation

The reconciliation controller requires the exact parents and conflict set, resolves only the reviewed paths, regenerates `SOURCE_MANIFEST.sha256`, then runs:

- P2 source inventory;
- exact hosted-Python lock validation and installation;
- integration-train gate;
- complete P1 exit gate;
- P0-003 repair gate;
- P0-008 roadmap tests and strict roadmap validation;
- P0-010 generated-state gate;
- portable benchmark check;
- Git whitespace checks;
- exact product-workflow assertions.

Fresh protected Windows, macOS, Ubuntu, P1A, P2, and native-release checks remain required on PR #14 after the branch moves to the reconciliation candidate.

## Challenges passed

1. **Dirty PR state:** merge conflicts are treated as an explicit governed change, not bypassed through a force push or direct main merge.
2. **Workflow divergence:** the final product workflow is composed from protected main plus the exact P1/P2 bootstrap instead of blindly selecting either side.
3. **Generated inventory conflict:** the source manifest is regenerated from the resolved tree rather than manually merged.
4. **Duplicate status contexts:** feature-branch pushes no longer produce a second product matrix with the same required names; pull requests still receive the complete matrix and `main` still receives post-merge validation.
5. **Workflow-write restriction:** if the Actions token cannot move a ref containing workflow changes, the exact candidate object and receipt are retained for a separately authenticated fast-forward after verification.
6. **Documentation durability:** the exact parents, conflicts, resolutions, validation, and claim boundary are committed with the candidate.

## Claim boundary

This is still an **owner-risk QA preview**. Reconciliation does not claim independent security review, public-GA eligibility, production-release eligibility, signed-installer readiness, or unrestricted consumer release. It does not by itself complete P2 evidence closure or unblock P3.

## Next controlled steps

1. Verify the reconciliation receipt, candidate parents, conflict set, and product-workflow assertions.
2. Move the target only to the exact receipted candidate.
3. Require fresh protected PR #14 checks against current `main`.
4. Merge P1/P2 only when all required checks are green.
5. Finalize owner-risk P2 evidence and clean temporary reconciliation/recovery refs.
6. Select the first dependency-satisfied next task from `docs/roadmap/MASTER.md`.
"""


def verify_ci_contract(target: pathlib.Path) -> None:
    value = (target / CI_PATH).read_text(encoding="utf-8")
    require(value.count(BOOTSTRAP_NAME) == 1, "final CI bootstrap step count mismatch")
    require(value.count(BOOTSTRAP_COMMAND) == 1, "final CI bootstrap command count mismatch")
    require(
        "  push:\n    branches:\n      - main\n  pull_request:\n" in value,
        "final CI push/pull_request trigger contract mismatch",
    )
    for obsolete in ("pr14-documented-repair", "pr54-source-manifest-candidate"):
        require(obsolete not in value, f"obsolete product helper remains: {obsolete}")


def execute(
    *,
    config_path: pathlib.Path,
    control: pathlib.Path,
    target: pathlib.Path,
    receipt: pathlib.Path,
) -> int:
    transcript = Transcript()
    config = load_config(config_path)
    require(config.ready, "reconciliation config is not ready")
    repository = os.environ.get("GITHUB_REPOSITORY", "")
    event_name = os.environ.get("GITHUB_EVENT_NAME", "")
    ref = os.environ.get("GITHUB_REF", "")
    control_sha = os.environ.get("CONTROL_SHA", "")
    require(repository == config.repository, f"repository mismatch: {repository}")
    require(event_name == "push", f"event mismatch: {event_name}")
    require(ref == "refs/heads/main", f"ref mismatch: {ref}")
    require(valid_sha(control_sha), "invalid CONTROL_SHA")

    payload: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "mode": "execute",
        "capturedAtUtc": utc_now(),
        "repository": config.repository,
        "roadmapAuthority": ROADMAP_AUTHORITY,
        "targetBranch": config.target_branch,
        "targetParent": config.expected_target_head,
        "mainParent": control_sha,
        "expectedConflicts": list(config.expected_conflicts),
        "resolutions": dict(config.resolutions),
        "workflowRunId": os.environ.get("GITHUB_RUN_ID"),
        "workflowRunAttempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
        "candidate": "",
        "refUpdatedByAction": False,
        "status": "failed",
        "error": "",
    }
    try:
        require(git_head(transcript, control) == control_sha, "control checkout mismatch")
        ensure_clean(transcript, control)
        verify_target(transcript, target, config)
        ancestor = run(
            transcript,
            ("git", "merge-base", "--is-ancestor", config.minimum_main_ancestor, control_sha),
            cwd=control,
            check=False,
        )
        require(ancestor.returncode == 0, "control main does not descend from minimumMainAncestor")
        run(transcript, ("git", "fetch", "origin", control_sha), cwd=target)
        run(transcript, ("git", "config", "user.name", "Kristin PR14 Reconciler"), cwd=target)
        run(
            transcript,
            ("git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"),
            cwd=target,
        )
        merge = run(
            transcript,
            ("git", "merge", "--no-ff", "--no-commit", control_sha),
            cwd=target,
            check=False,
        )
        observed = conflict_paths(transcript, target)
        payload["observedConflicts"] = list(observed)
        payload["conflictStages"] = conflict_stages(transcript, target)
        require(
            merge.returncode == 0 or observed,
            f"merge failed without conflicts: rc={merge.returncode}",
        )
        resolve_conflicts(
            transcript,
            target,
            config=config,
            control_sha=control_sha,
            observed=observed,
        )
        doc = reconciliation_document(
            config=config,
            control_sha=control_sha,
            conflicts=observed,
            resolutions=config.resolutions,
        )
        doc_path = target / RECONCILIATION_DOC
        doc_path.parent.mkdir(parents=True, exist_ok=True)
        doc_path.write_text(doc, encoding="utf-8", newline="\n")
        run(transcript, ("git", "add", "--", RECONCILIATION_DOC), cwd=target)

        commands: tuple[tuple[str, ...], ...] = (
            (sys.executable, "tool/p2_refresh_source_manifest.py", "."),
            (sys.executable, "tool/p2_source_inventory_test.py", "--project", "."),
            (sys.executable, "tool/v71r12_bootstrap_hosted_python.py", "--project", "."),
            (sys.executable, "tool/integration_train_test.py", "--project", "."),
            (sys.executable, "tool/p1_exit_gate_test.py", "--project", "."),
            (sys.executable, "tool/p0_003_repair_test.py"),
            (sys.executable, "tool/p0_008_roadmap_test.py", "--project", "."),
            (sys.executable, "tool/roadmap_control.py", "validate", "--project", ".", "--strict"),
            (sys.executable, "tool/p0_010_generated_state_test.py", "--project", "."),
            (sys.executable, "tool/benchmark_runner.py", "check", "--project", "."),
            ("git", "diff", "--check"),
        )
        for command in commands:
            run(transcript, command, cwd=target)
        verify_ci_contract(target)
        run(transcript, ("git", "add", "-A"), cwd=target)
        run(transcript, ("git", "diff", "--cached", "--check"), cwd=target)
        run(
            transcript,
            ("git", "commit", "-m", "merge: reconcile documented P1/P2 with protected main"),
            cwd=target,
        )
        candidate = git_head(transcript, target)
        parent1 = output(transcript, ("git", "rev-parse", "HEAD^1"), cwd=target)
        parent2 = output(transcript, ("git", "rev-parse", "HEAD^2"), cwd=target)
        require(parent1 == config.expected_target_head, f"first parent mismatch: {parent1}")
        require(parent2 == control_sha, f"second parent mismatch: {parent2}")
        changed = tuple(
            sorted(
                filter(
                    None,
                    output(
                        transcript,
                        ("git", "diff", "--name-only", f"{parent1}..{candidate}"),
                        cwd=target,
                    ).splitlines(),
                )
            )
        )
        payload["candidate"] = candidate
        payload["candidateChangedPaths"] = list(changed)
        push = run(
            transcript,
            ("git", "push", "origin", f"{candidate}:refs/heads/{config.target_branch}"),
            cwd=target,
            check=False,
        )
        if push.returncode == 0:
            remote = output(
                transcript,
                ("git", "ls-remote", "origin", f"refs/heads/{config.target_branch}"),
                cwd=target,
            )
            remote_sha = remote.split()[0] if remote else ""
            require(remote_sha == candidate, f"target ref verification mismatch: {remote_sha}")
            payload["refUpdatedByAction"] = True
        else:
            require(
                any(marker in push.output for marker in KNOWN_WORKFLOW_REJECTIONS),
                "target push failed for an unrecognized reason",
            )
            transcript.write("RECONCILIATION_OBJECT_TRANSFERRED_FOR_CONNECTED_REF_UPDATE=true")
        payload["status"] = "success"
    except Exception as exc:
        payload["error"] = f"{type(exc).__name__}: {exc}"
        transcript.write(payload["error"])
        transcript.write(traceback.format_exc().rstrip())
    payload["transcript"] = transcript.text()
    write_json(receipt, payload)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload["status"] == "success" and payload["candidate"] else 1


def validate_control(config_path: pathlib.Path, ci_path: pathlib.Path) -> int:
    config = load_config(config_path)
    value = ci_path.read_text(encoding="utf-8")
    require(
        "  push:\n    branches:\n      - main\n  pull_request:\n" in value,
        "product gate must restrict push to main and retain pull_request",
    )
    require("pr14-documented-repair" not in value, "obsolete PR14 helper remains")
    require("pr54-source-manifest-candidate" not in value, "obsolete PR54 helper remains")
    print(
        json.dumps(
            {
                "ready": config.ready,
                "expectedConflicts": list(config.expected_conflicts),
                "productGatePushBranches": ["main"],
                "pullRequestEnabled": True,
                "obsoleteHelpersRemoved": True,
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


def self_test() -> int:
    sample = (
        "name: product-gates\n"
        "on:\n"
        "  workflow_dispatch:\n"
        "  push:\n"
        "    branches:\n"
        "      - main\n"
        "  pull_request:\n"
        "jobs:\n"
        "  validate:\n"
        "    steps:\n"
        "      - run: flutter pub get\n"
        "\n"
        "      - name: Capture CI environment\n"
        "        run: true\n"
    )
    anchor = "      - run: flutter pub get\n\n      - name: Capture CI environment\n"
    insertion = (
        "      - run: flutter pub get\n\n"
        f"      - name: {BOOTSTRAP_NAME}\n"
        f"        run: {BOOTSTRAP_COMMAND}\n\n"
        "      - name: Capture CI environment\n"
    )
    require(sample.count(anchor) == 1, "self-test anchor mismatch")
    composed = sample.replace(anchor, insertion, 1)
    require(composed.count(BOOTSTRAP_NAME) == 1, "self-test bootstrap name mismatch")
    require(composed.count(BOOTSTRAP_COMMAND) == 1, "self-test bootstrap command mismatch")
    require(
        "  push:\n    branches:\n      - main\n  pull_request:\n" in composed,
        "self-test trigger mismatch",
    )
    require(valid_sha("a" * 40), "self-test valid SHA rejected")
    require(not valid_sha("z" * 40), "self-test invalid SHA accepted")
    print("PR14 current-main reconciliation self-test: PASS")
    return 0


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=pathlib.Path)
    parser.add_argument("--target", type=pathlib.Path)
    parser.add_argument("--control", type=pathlib.Path)
    parser.add_argument("--base-sha")
    parser.add_argument("--receipt", type=pathlib.Path)
    parser.add_argument("--discover", action="store_true")
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--validate-control", action="store_true")
    parser.add_argument("--ci", type=pathlib.Path)
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        if args.self_test:
            return self_test()
        if args.validate_control:
            require(args.config is not None and args.ci is not None, "validate-control paths missing")
            return validate_control(args.config.resolve(), args.ci.resolve())
        if args.discover:
            require(
                args.config is not None
                and args.target is not None
                and args.base_sha is not None
                and args.receipt is not None,
                "discover arguments missing",
            )
            return discover(
                config_path=args.config.resolve(),
                target=args.target.resolve(),
                base_sha=args.base_sha,
                receipt=args.receipt.resolve(),
            )
        if args.execute:
            require(
                args.config is not None
                and args.control is not None
                and args.target is not None
                and args.receipt is not None,
                "execute arguments missing",
            )
            return execute(
                config_path=args.config.resolve(),
                control=args.control.resolve(),
                target=args.target.resolve(),
                receipt=args.receipt.resolve(),
            )
        raise ReconciliationError("select exactly one mode")
    except ReconciliationError as exc:
        print(f"pr14 reconciliation: ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
