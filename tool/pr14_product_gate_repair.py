#!/usr/bin/env python3
"""Exact, documented PR #14 recovery handoff for the protected product-gates run."""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import traceback
from dataclasses import dataclass, field
from typing import Any, Iterable, Mapping, Sequence

TARGET_BRANCH = "merge/p1-p2-owner-risk-qa-preview"
EXPECTED_TARGET_HEAD = "0b91e02f2d7413c40dcfa81176877cd3a0daf87e"
STATUS_BRANCH = "ci/direct-pr14-repair-trigger"
EXPECTED_TRIGGER_HEAD = "61037b13e71d8b0e6b47feaa9922d476c5666347"
EXPECTED_TRIGGER_PR = 48
CI_PATH = ".github/workflows/ci.yml"
DOC_PATH = "docs/progress/2026-08-05-pr14-ci-recovery.md"
AUTHORIZED_PATHS = (CI_PATH, "SOURCE_MANIFEST.sha256", DOC_PATH)
BOOTSTRAP_STEP_NAME = "Install hash-locked P1/P2 Python test dependencies"
BOOTSTRAP_COMMAND = "python tool/v71r12_bootstrap_hosted_python.py --project ."
ACCEPTED_PULL_REQUEST_ACTIONS = frozenset({"opened", "reopened", "synchronize"})
KNOWN_WORKFLOW_PUSH_REJECTIONS = (
    "refusing to allow a GitHub App",
    "workflows permission",
)


class RepairError(RuntimeError):
    """Raised when an exact recovery invariant is not satisfied."""


@dataclass
class Transcript:
    lines: list[str] = field(default_factory=list)

    def write(self, message: str = "") -> None:
        text = str(message)
        self.lines.extend(text.splitlines() or [""])
        print(text, flush=True)

    def text(self) -> str:
        return "\n".join(self.lines).rstrip() + "\n"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RepairError(message)


def run_command(
    transcript: Transcript,
    command: Sequence[str],
    *,
    cwd: pathlib.Path,
    env: Mapping[str, str] | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    rendered = " ".join(command)
    transcript.write(f"$ ({cwd}) {rendered}")
    completed = subprocess.run(
        list(command),
        cwd=str(cwd),
        env=dict(env) if env is not None else None,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if completed.stdout:
        transcript.write(completed.stdout.rstrip())
    transcript.write(f"EXIT_CODE={completed.returncode}")
    if check and completed.returncode != 0:
        raise RepairError(f"command failed ({completed.returncode}): {rendered}")
    return completed


def command_output(
    transcript: Transcript,
    command: Sequence[str],
    *,
    cwd: pathlib.Path,
    env: Mapping[str, str] | None = None,
) -> str:
    return run_command(transcript, command, cwd=cwd, env=env).stdout.strip()


def load_json_command(
    transcript: Transcript,
    command: Sequence[str],
    *,
    cwd: pathlib.Path,
    env: Mapping[str, str] | None = None,
) -> Any:
    value = command_output(transcript, command, cwd=cwd, env=env)
    try:
        return json.loads(value)
    except json.JSONDecodeError as exc:
        raise RepairError(f"invalid JSON from {' '.join(command)}: {exc}") from exc


def read_json(path: pathlib.Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise RepairError(f"cannot read JSON {path}: {exc}") from exc


def git_output(transcript: Transcript, repo: pathlib.Path, *args: str) -> str:
    return command_output(transcript, ("git", *args), cwd=repo)


def verify_checkout(
    transcript: Transcript,
    repo: pathlib.Path,
    *,
    expected_head: str,
    expected_branch: str | None = None,
) -> None:
    require(repo.is_dir(), f"checkout missing: {repo}")
    head = git_output(transcript, repo, "rev-parse", "HEAD")
    require(head == expected_head, f"checkout head mismatch for {repo}: {head}")
    if expected_branch is not None:
        branch = git_output(transcript, repo, "branch", "--show-current")
        require(branch == expected_branch, f"checkout branch mismatch for {repo}: {branch}")
    status = git_output(transcript, repo, "status", "--porcelain")
    require(status == "", f"checkout is dirty before recovery: {repo}")


def verify_event(event: Mapping[str, Any], repository: str) -> None:
    action = event.get("action")
    require(action in ACCEPTED_PULL_REQUEST_ACTIONS, f"unsupported pull-request action: {action!r}")
    pull = event.get("pull_request") or {}
    require(pull.get("number") == EXPECTED_TRIGGER_PR, "event PR number mismatch")
    require(pull.get("draft") is True, "event trigger PR must remain draft")
    base = pull.get("base") or {}
    require(base.get("ref") == "main", "event base branch mismatch")
    head = pull.get("head") or {}
    require(head.get("ref") == STATUS_BRANCH, "event trigger branch mismatch")
    require(head.get("sha") == EXPECTED_TRIGGER_HEAD, "event trigger head mismatch")
    require((head.get("repo") or {}).get("full_name") == repository, "event repository mismatch")


def verify_trigger_pr(pull: Mapping[str, Any], repository: str) -> None:
    require(pull.get("number") == EXPECTED_TRIGGER_PR, "fetched trigger PR number mismatch")
    require(pull.get("state") == "open", "fetched trigger PR is not open")
    require(pull.get("draft") is True, "fetched trigger PR must remain draft")
    require((pull.get("base") or {}).get("ref") == "main", "fetched trigger base mismatch")
    head = pull.get("head") or {}
    require(head.get("ref") == STATUS_BRANCH, "fetched trigger branch mismatch")
    require(head.get("sha") == EXPECTED_TRIGGER_HEAD, "fetched trigger head mismatch")
    require((head.get("repo") or {}).get("full_name") == repository, "fetched trigger repository mismatch")


def verify_current_product_run(
    run: Mapping[str, Any],
    jobs_payload: Mapping[str, Any],
    *,
    repository: str,
    run_id: int,
    run_attempt: int,
    transcript: Transcript,
) -> None:
    expected = {
        "id": run_id,
        "name": "product-gates",
        "event": "pull_request",
        "status": "in_progress",
        "head_branch": STATUS_BRANCH,
        "head_sha": EXPECTED_TRIGGER_HEAD,
        "run_attempt": run_attempt,
    }
    for key, value in expected.items():
        require(run.get(key) == value, f"product run {key} mismatch: {run.get(key)!r} != {value!r}")
    require(
        (run.get("head_repository") or {}).get("full_name") == repository,
        "product run repository mismatch",
    )
    pull_numbers = {row.get("number") for row in (run.get("pull_requests") or [])}
    require(EXPECTED_TRIGGER_PR in pull_numbers, "product run does not reference exact trigger PR")

    jobs = jobs_payload.get("jobs") or []
    for name in ("validate-ubuntu", "validate-windows", "validate-macos"):
        matches = [row for row in jobs if row.get("name") == name]
        require(len(matches) == 1, f"product job count mismatch for {name}: {len(matches)}")
        row = matches[0]
        require(row.get("status") == "completed", f"product job not completed: {name}")
        require(row.get("conclusion") == "success", f"product job not successful: {name}")
        transcript.write(f"CURRENT_PRODUCT_JOB={name} ID={row.get('id')} CONCLUSION=success")


def apply_ci_bootstrap(ci_path: pathlib.Path) -> None:
    value = ci_path.read_text(encoding="utf-8")
    old = (
        "      - run: flutter pub get\n"
        "\n"
        "      - name: Capture CI environment\n"
    )
    new = (
        "      - run: flutter pub get\n"
        "\n"
        f"      - name: {BOOTSTRAP_STEP_NAME}\n"
        f"        run: {BOOTSTRAP_COMMAND}\n"
        "\n"
        "      - name: Capture CI environment\n"
    )
    require(value.count(old) == 1, f"product CI bootstrap anchor count: {value.count(old)}")
    require(BOOTSTRAP_STEP_NAME not in value, "product CI bootstrap step is already present")
    ci_path.write_text(value.replace(old, new, 1), encoding="utf-8", newline="\n")


def candidate_document(source_run_id: int, source_run_attempt: int) -> str:
    return f"""# PR #14 owner-risk QA preview recovery: product CI bootstrap

**Recorded:** 2026-08-05
**Human roadmap authority:** `docs/roadmap/MASTER.md`
**Machine dependency authority:** `docs/roadmap/roadmap.yaml`
**Recovery target:** `{TARGET_BRANCH}` at `{EXPECTED_TARGET_HEAD}`
**Authorizing product run:** `{source_run_id}`, attempt `{source_run_attempt}`

## Purpose

This significant recovery step makes the protected product gate reproducible on clean Windows, macOS, and Ubuntu runners before the P1/P2 owner-risk QA preview can be reconsidered for landing. It changes no product behavior and widens no authority boundary.

The product workflow invokes the complete P1 exit gate. Two Ed25519 reference tests import the pinned `cryptography` dependency, but the workflow previously reached them before installing the repository's existing hash-locked hosted-Python dependency bundle. A clean runner could therefore fail with `ModuleNotFoundError: cryptography` despite green product source, Flutter analysis/tests, P1 contracts, and isolated P1/P2 runtime validation.

## Exact change

1. `.github/workflows/ci.yml` installs the existing wheel-only, hash-locked P1/P2 Python test dependency closure immediately after `flutter pub get` and before every Python trust-closure test.
2. `SOURCE_MANIFEST.sha256` is regenerated by `tool/p2_refresh_source_manifest.py`.
3. This document records implementation, challenges, evidence boundaries, and governed next steps.

No dependency version, test assertion, product API, runtime message format, access profile, security classification, or release claim changes.

## Challenges passed

- Formal manual-dispatch and owner-risk pull-request source contracts were separated without weakening the formal lane.
- A verifier false positive was corrected by matching the exact inserted five-line block instead of counting unrelated conditions globally.
- GitHub correctly blocked an Actions token from updating workflow files without workflow-write authority; the exact validated commit object is retained for a separately authenticated ref update.
- Connector-authored commits did not reliably emit push workflows. Reviewed pull-request, `pull_request_target`, `workflow_run`, run-attempt-pinned, and explicit owner-comment transports produced no machine-readable receipt.
- One Ubuntu hosted runner stalled inside package installation while Windows and macOS completed. That partial run was rejected and could not authorize mutation.
- The final transport is a dependent job inside `product-gates`, the workflow repeatedly proven to execute on protected pull requests. GitHub schedules it only after the current Windows, macOS, and Ubuntu matrix has succeeded.
- The dependent job re-fetches the current run and requires exactly one successful `validate-ubuntu`, `validate-windows`, and `validate-macos` job before it checks out the governed target.
- Clean hosted runners exposed the missing dependency bootstrap. The fix reuses the existing locked dependency closure rather than adding unpinned installation or weakening the P1 exit gate.

## Candidate validation

Before target mutation, the executor verifies exact PR #48, branch, SHA, draft state, same-repository provenance, current product run identity, and all three successful platform jobs from that same run.

Against the exact target head it runs the P2 source inventory, owner-risk P1A dependency contract, hash-locked bootstrap, integration-train gate, full P1 exit gate, P0-003 repair gate, P0-008 roadmap controls, strict roadmap validator, P0-010 generated-state gate, Git whitespace checks, and exact three-path/exact-once assertions.

Earlier isolated P1/P2 validation, including tri-platform run `30913519385`, remains owner-risk QA evidence. It is not substituted for fresh protected checks required after reconciliation.

## Claim boundary

This remains an **owner-risk QA preview** for immediate application testing. Formal independent security completion, public-GA eligibility, production-release eligibility, signed-installer readiness, and unrestricted consumer release remain false. `docs/roadmap/MASTER.md` remains the sole human roadmap authority.

## Next governed steps

1. Verify `repair-status.json` and the exact child commit.
2. Attach the commit through connected GitHub authority if workflow writes are blocked.
3. Reconcile with then-current protected `main`, regenerate inventories, and add a separate reconciliation document.
4. Reopen PR #14 and require fresh protected P1A, P2, and product checks on Windows, macOS, and Ubuntu.
5. Merge only when every required check is green, then publish a separate landing and roadmap-transition document before advancing the next `MASTER.md` task.
"""


def validate_candidate_scope(transcript: Transcript, target: pathlib.Path) -> None:
    changed = command_output(
        transcript,
        ("git", "diff", "--name-only"),
        cwd=target,
    ).splitlines()
    changed = sorted(filter(None, changed))
    transcript.write(f"CHANGED_PATHS={json.dumps(changed)}")
    require(tuple(changed) == AUTHORIZED_PATHS, f"candidate scope mismatch: {changed}")

    ci_value = (target / CI_PATH).read_text(encoding="utf-8")
    require(ci_value.count(f"      - name: {BOOTSTRAP_STEP_NAME}\n") == 1, "bootstrap step count mismatch")
    require(ci_value.count(f"        run: {BOOTSTRAP_COMMAND}\n") == 1, "bootstrap command count mismatch")
    doc_value = (target / DOC_PATH).read_text(encoding="utf-8")
    require("**Human roadmap authority:** `docs/roadmap/MASTER.md`" in doc_value, "roadmap marker missing")
    require("## Challenges passed" in doc_value, "challenge documentation missing")
    require("dependent job inside `product-gates`" in doc_value, "product-gates handoff marker missing")


def construct_candidate(
    transcript: Transcript,
    target: pathlib.Path,
    *,
    source_run_id: int,
    source_run_attempt: int,
) -> tuple[str, bool]:
    apply_ci_bootstrap(target / CI_PATH)
    doc_path = target / DOC_PATH
    doc_path.parent.mkdir(parents=True, exist_ok=True)
    doc_path.write_text(
        candidate_document(source_run_id, source_run_attempt),
        encoding="utf-8",
        newline="\n",
    )

    commands: Iterable[Sequence[str]] = (
        (sys.executable, "tool/p2_refresh_source_manifest.py", "."),
        (sys.executable, "tool/p2_source_inventory_test.py", "--project", "."),
        (sys.executable, "tool/p2_shared_p1_authority_contract_test.py", "--project", ".", "--owner-risk-qa"),
        (sys.executable, "tool/v71r12_bootstrap_hosted_python.py", "--project", "."),
        (sys.executable, "tool/integration_train_test.py", "--project", "."),
        (sys.executable, "tool/p1_exit_gate_test.py", "--project", "."),
        (sys.executable, "tool/p0_003_repair_test.py"),
        (sys.executable, "tool/p0_008_roadmap_test.py", "--project", "."),
        (sys.executable, "tool/roadmap_control.py", "validate", "--project", ".", "--strict"),
        (sys.executable, "tool/p0_010_generated_state_test.py", "--project", "."),
        ("git", "diff", "--check"),
    )
    for command in commands:
        run_command(transcript, command, cwd=target)

    validate_candidate_scope(transcript, target)
    run_command(transcript, ("git", "config", "user.name", "Kristin CI Repair"), cwd=target)
    run_command(
        transcript,
        ("git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"),
        cwd=target,
    )
    run_command(transcript, ("git", "add", *AUTHORIZED_PATHS), cwd=target)
    run_command(transcript, ("git", "diff", "--cached", "--check"), cwd=target)
    run_command(
        transcript,
        ("git", "commit", "-m", "fix(ci): bootstrap P1 closure and document PR14 recovery"),
        cwd=target,
    )
    candidate = git_output(transcript, target, "rev-parse", "HEAD")
    parent = git_output(transcript, target, "rev-parse", "HEAD^")
    require(parent == EXPECTED_TARGET_HEAD, f"candidate parent mismatch: {parent}")

    push = run_command(
        transcript,
        ("git", "push", "origin", f"{candidate}:refs/heads/{TARGET_BRANCH}"),
        cwd=target,
        check=False,
    )
    if push.returncode == 0:
        remote = git_output(transcript, target, "ls-remote", "origin", f"refs/heads/{TARGET_BRANCH}")
        remote_sha = remote.split()[0] if remote else ""
        require(remote_sha == candidate, f"target ref verification mismatch: {remote_sha}")
        return candidate, True

    output = push.stdout or ""
    require(
        any(marker in output for marker in KNOWN_WORKFLOW_PUSH_REJECTIONS),
        "target push failed for an unrecognized reason",
    )
    transcript.write("REPAIR_OBJECT_TRANSFERRED_FOR_CONNECTED_REF_UPDATE=true")
    return candidate, False


def receipt_payload(
    *,
    repair_rc: int,
    error: str,
    source_run_id: int,
    source_run_attempt: int,
    control_sha: str,
    candidate: str,
    ref_updated: bool,
    workflow_run_id: str,
    workflow_run_attempt: str,
) -> dict[str, Any]:
    return {
        "schemaVersion": "1.4.0",
        "repairRc": repair_rc,
        "error": error,
        "targetBranch": TARGET_BRANCH,
        "expectedHead": EXPECTED_TARGET_HEAD,
        "triggerBranch": STATUS_BRANCH,
        "triggerHead": EXPECTED_TRIGGER_HEAD,
        "triggerPullRequest": EXPECTED_TRIGGER_PR,
        "sourceProductRunId": str(source_run_id),
        "sourceProductRunAttempt": str(source_run_attempt),
        "controlBaseSha": control_sha,
        "repairedCommit": candidate,
        "refUpdatedByAction": ref_updated,
        "workflowRunId": workflow_run_id,
        "workflowRunAttempt": workflow_run_attempt,
        "roadmapAuthority": "docs/roadmap/MASTER.md",
        "authorizedPaths": list(AUTHORIZED_PATHS),
    }


def publish_receipt(
    transcript: Transcript,
    status: pathlib.Path,
    payload: Mapping[str, Any],
) -> None:
    (status / "repair.log").write_text(transcript.text(), encoding="utf-8", newline="\n")
    (status / "repair-status.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    run_command(transcript, ("git", "config", "user.name", "Kristin CI Repair"), cwd=status)
    run_command(
        transcript,
        ("git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"),
        cwd=status,
    )
    run_command(transcript, ("git", "add", "repair.log", "repair-status.json"), cwd=status)
    staged = run_command(transcript, ("git", "diff", "--cached", "--quiet"), cwd=status, check=False)
    if staged.returncode == 0:
        transcript.write("STATUS_RECEIPT_UNCHANGED=true")
        return
    require(staged.returncode == 1, f"unexpected git diff --quiet exit code: {staged.returncode}")
    run_command(
        transcript,
        ("git", "commit", "-m", "ci: record product-gate documented PR14 repair candidate"),
        cwd=status,
    )
    run_command(transcript, ("git", "push", "origin", f"HEAD:refs/heads/{STATUS_BRANCH}"), cwd=status)


def execute(control: pathlib.Path, target: pathlib.Path, status: pathlib.Path) -> int:
    transcript = Transcript()
    repair_rc = 1
    error = "candidate construction did not start"
    candidate = ""
    ref_updated = False
    repository = os.environ.get("GITHUB_REPOSITORY", "")
    run_id_text = os.environ.get("GITHUB_RUN_ID", "")
    run_attempt_text = os.environ.get("GITHUB_RUN_ATTEMPT", "")
    control_sha = os.environ.get("CONTROL_SHA", "")

    try:
        require(repository == "alex00Pirotskyi/kris.ai", f"repository mismatch: {repository!r}")
        require(run_id_text.isdigit(), "GITHUB_RUN_ID is invalid")
        require(run_attempt_text.isdigit(), "GITHUB_RUN_ATTEMPT is invalid")
        require(len(control_sha) == 40, "CONTROL_SHA is invalid")
        run_id = int(run_id_text)
        run_attempt = int(run_attempt_text)

        verify_checkout(transcript, control, expected_head=control_sha)
        verify_checkout(
            transcript,
            status,
            expected_head=EXPECTED_TRIGGER_HEAD,
            expected_branch=STATUS_BRANCH,
        )
        verify_checkout(
            transcript,
            target,
            expected_head=EXPECTED_TARGET_HEAD,
            expected_branch=TARGET_BRANCH,
        )
        remote_target = git_output(transcript, target, "rev-parse", f"origin/{TARGET_BRANCH}")
        require(remote_target == EXPECTED_TARGET_HEAD, f"remote target mismatch: {remote_target}")

        event_path = pathlib.Path(os.environ.get("GITHUB_EVENT_PATH", ""))
        event = read_json(event_path)
        verify_event(event, repository)

        api_env = os.environ.copy()
        pull = load_json_command(
            transcript,
            ("gh", "api", f"repos/{repository}/pulls/{EXPECTED_TRIGGER_PR}"),
            cwd=control,
            env=api_env,
        )
        verify_trigger_pr(pull, repository)
        run = load_json_command(
            transcript,
            ("gh", "api", f"repos/{repository}/actions/runs/{run_id}"),
            cwd=control,
            env=api_env,
        )
        jobs = load_json_command(
            transcript,
            ("gh", "api", f"repos/{repository}/actions/runs/{run_id}/jobs?per_page=100"),
            cwd=control,
            env=api_env,
        )
        verify_current_product_run(
            run,
            jobs,
            repository=repository,
            run_id=run_id,
            run_attempt=run_attempt,
            transcript=transcript,
        )
        candidate, ref_updated = construct_candidate(
            transcript,
            target,
            source_run_id=run_id,
            source_run_attempt=run_attempt,
        )
        repair_rc = 0
        error = ""
    except Exception as exc:
        error = f"{type(exc).__name__}: {exc}"
        transcript.write(error)
        transcript.write(traceback.format_exc().rstrip())

    payload = receipt_payload(
        repair_rc=repair_rc,
        error=error,
        source_run_id=int(run_id_text) if run_id_text.isdigit() else 0,
        source_run_attempt=int(run_attempt_text) if run_attempt_text.isdigit() else 0,
        control_sha=control_sha,
        candidate=candidate,
        ref_updated=ref_updated,
        workflow_run_id=run_id_text,
        workflow_run_attempt=run_attempt_text,
    )
    try:
        publish_receipt(transcript, status, payload)
    except Exception as exc:
        transcript.write(f"RECEIPT_PUBLISH_FAILURE={type(exc).__name__}: {exc}")
        transcript.write(traceback.format_exc().rstrip())
        return 1
    return 0 if repair_rc == 0 and candidate else 1


def self_test() -> int:
    with tempfile.TemporaryDirectory(prefix="pr14-repair-self-test-") as raw:
        root = pathlib.Path(raw)
        ci = root / "ci.yml"
        ci.write_text(
            "name: product-gates\n"
            "jobs:\n"
            "  validate:\n"
            "    steps:\n"
            "      - run: flutter pub get\n"
            "\n"
            "      - name: Capture CI environment\n"
            "        run: true\n",
            encoding="utf-8",
            newline="\n",
        )
        apply_ci_bootstrap(ci)
        value = ci.read_text(encoding="utf-8")
        require(value.count(BOOTSTRAP_STEP_NAME) == 1, "self-test bootstrap name mismatch")
        require(value.count(BOOTSTRAP_COMMAND) == 1, "self-test bootstrap command mismatch")
        try:
            apply_ci_bootstrap(ci)
        except RepairError:
            pass
        else:
            raise RepairError("self-test repeated edit did not fail closed")

        doc = candidate_document(123, 2)
        require("docs/roadmap/MASTER.md" in doc, "self-test roadmap marker missing")
        require("## Challenges passed" in doc, "self-test challenges marker missing")
        require("dependent job inside `product-gates`" in doc, "self-test handoff marker missing")
        payload = receipt_payload(
            repair_rc=0,
            error="",
            source_run_id=123,
            source_run_attempt=2,
            control_sha="a" * 40,
            candidate="b" * 40,
            ref_updated=False,
            workflow_run_id="123",
            workflow_run_attempt="2",
        )
        require(payload["authorizedPaths"] == list(AUTHORIZED_PATHS), "self-test receipt scope mismatch")
        require(payload["roadmapAuthority"] == "docs/roadmap/MASTER.md", "self-test roadmap authority mismatch")
    print("PR14 product-gate repair self-test: PASS")
    return 0


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--control", type=pathlib.Path)
    parser.add_argument("--target", type=pathlib.Path)
    parser.add_argument("--status", type=pathlib.Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if not args.self_test:
        missing = [name for name in ("control", "target", "status") if getattr(args, name) is None]
        if missing:
            parser.error(f"missing required execution paths: {', '.join(missing)}")
    return args


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if args.self_test:
        return self_test()
    return execute(args.control.resolve(), args.target.resolve(), args.status.resolve())


if __name__ == "__main__":
    raise SystemExit(main())
