#!/usr/bin/env python3
"""Bookkeeping-corrected protected-main PR #14 repair handoff.

This wrapper deliberately leaves the reviewed authorization and candidate
construction in ``pr14_main_push_repair`` unchanged. It replaces only two
bookkeeping primitives exposed by run 30976062209:

* candidate scope includes both tracked modifications and untracked files;
* the two exact receipt files are force-added because ``repair.log`` is
  intentionally ignored by the general source-tree policy.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys
import tempfile
from typing import Any, Mapping, Sequence

import pr14_main_push_repair as base


def collect_candidate_paths(
    transcript: base.Transcript,
    target: pathlib.Path,
) -> list[str]:
    """Return every non-ignored tracked or untracked candidate path."""

    tracked = base.command_output(
        transcript,
        ("git", "diff", "--name-only"),
        cwd=target,
    ).splitlines()
    untracked = base.command_output(
        transcript,
        ("git", "ls-files", "--others", "--exclude-standard"),
        cwd=target,
    ).splitlines()
    return sorted({path for path in (*tracked, *untracked) if path})


def validate_candidate_scope(
    transcript: base.Transcript,
    target: pathlib.Path,
) -> None:
    changed = collect_candidate_paths(transcript, target)
    transcript.write(f"CHANGED_PATHS={json.dumps(changed)}")
    base.require(
        tuple(changed) == base.AUTHORIZED_PATHS,
        f"candidate scope mismatch: {changed}",
    )

    ci_value = (target / base.CI_PATH).read_text(encoding="utf-8")
    base.require(
        ci_value.count(f"      - name: {base.BOOTSTRAP_STEP_NAME}\n") == 1,
        "bootstrap step count mismatch",
    )
    base.require(
        ci_value.count(f"        run: {base.BOOTSTRAP_COMMAND}\n") == 1,
        "bootstrap command count mismatch",
    )
    doc_value = (target / base.DOC_PATH).read_text(encoding="utf-8")
    for marker in (
        "**Human roadmap authority:** `docs/roadmap/MASTER.md`",
        "## Challenges passed",
        "protected `main`",
        f"Authorizing product run:** `{base.EXPECTED_SOURCE_PRODUCT_RUN_ID}`",
    ):
        base.require(marker in doc_value, f"candidate document marker missing: {marker}")


def stage_receipt_files(
    transcript: base.Transcript,
    status: pathlib.Path,
) -> None:
    """Stage only the reviewed receipt pair, overriding the general log ignore."""

    base.run_command(
        transcript,
        ("git", "add", "-f", "--", "repair.log", "repair-status.json"),
        cwd=status,
    )


def publish_receipt(
    transcript: base.Transcript,
    status: pathlib.Path,
    payload: Mapping[str, Any],
) -> None:
    (status / "repair.log").write_text(
        transcript.text(),
        encoding="utf-8",
        newline="\n",
    )
    (status / "repair-status.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    base.run_command(
        transcript,
        ("git", "config", "user.name", "Kristin CI Repair"),
        cwd=status,
    )
    base.run_command(
        transcript,
        (
            "git",
            "config",
            "user.email",
            "41898282+github-actions[bot]@users.noreply.github.com",
        ),
        cwd=status,
    )
    stage_receipt_files(transcript, status)
    staged = base.run_command(
        transcript,
        ("git", "diff", "--cached", "--quiet"),
        cwd=status,
        check=False,
    )
    if staged.returncode == 0:
        transcript.write("STATUS_RECEIPT_UNCHANGED=true")
        return
    base.require(
        staged.returncode == 1,
        f"unexpected git diff --quiet exit code: {staged.returncode}",
    )
    base.run_command(
        transcript,
        ("git", "diff", "--cached", "--check"),
        cwd=status,
    )
    base.run_command(
        transcript,
        ("git", "commit", "-m", "ci: record protected-main PR14 repair receipt"),
        cwd=status,
    )
    receipt_commit = base.git_output(transcript, status, "rev-parse", "HEAD")
    base.run_command(
        transcript,
        (
            "git",
            "push",
            "origin",
            f"{receipt_commit}:refs/heads/{base.STATUS_BRANCH}",
        ),
        cwd=status,
    )
    remote = base.git_output(
        transcript,
        status,
        "ls-remote",
        "origin",
        f"refs/heads/{base.STATUS_BRANCH}",
    )
    remote_sha = remote.split()[0] if remote else ""
    base.require(
        remote_sha == receipt_commit,
        f"status receipt ref mismatch: {remote_sha}",
    )
    transcript.write(f"STATUS_RECEIPT_COMMIT={receipt_commit}")


def _git(repo: pathlib.Path, *args: str) -> str:
    completed = subprocess.run(
        ("git", *args),
        cwd=repo,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if completed.returncode != 0:
        raise AssertionError(
            f"git {' '.join(args)} failed ({completed.returncode}): {completed.stdout}"
        )
    return completed.stdout.strip()


def self_test() -> int:
    base.self_test()
    with tempfile.TemporaryDirectory(prefix="pr14-bookkeeping-self-test-") as raw:
        repo = pathlib.Path(raw)
        _git(repo, "init", "-b", "main")
        _git(repo, "config", "user.name", "PR14 Self Test")
        _git(repo, "config", "user.email", "pr14-self-test@example.invalid")

        (repo / ".gitignore").write_text("*.log\n", encoding="utf-8", newline="\n")
        ci_path = repo / base.CI_PATH
        ci_path.parent.mkdir(parents=True, exist_ok=True)
        ci_path.write_text("original\n", encoding="utf-8", newline="\n")
        manifest = repo / "SOURCE_MANIFEST.sha256"
        manifest.write_text("old\n", encoding="utf-8", newline="\n")
        _git(repo, "add", ".gitignore", base.CI_PATH, "SOURCE_MANIFEST.sha256")
        _git(repo, "commit", "-m", "seed")

        ci_path.write_text("changed\n", encoding="utf-8", newline="\n")
        manifest.write_text("new\n", encoding="utf-8", newline="\n")
        doc = repo / base.DOC_PATH
        doc.parent.mkdir(parents=True, exist_ok=True)
        doc.write_text("new documentation\n", encoding="utf-8", newline="\n")
        observed = collect_candidate_paths(base.Transcript(), repo)
        base.require(
            tuple(observed) == base.AUTHORIZED_PATHS,
            f"self-test candidate path mismatch: {observed}",
        )

        _git(repo, "reset", "--hard", "HEAD")
        (repo / "repair.log").write_text("ignored receipt\n", encoding="utf-8")
        (repo / "repair-status.json").write_text("{}\n", encoding="utf-8")
        stage_receipt_files(base.Transcript(), repo)
        staged = _git(repo, "diff", "--cached", "--name-only").splitlines()
        base.require(
            staged == ["repair-status.json", "repair.log"],
            f"self-test receipt staging mismatch: {staged}",
        )

    print("PR14 handoff bookkeeping self-test: PASS")
    return 0


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--control", type=pathlib.Path)
    parser.add_argument("--target", type=pathlib.Path)
    parser.add_argument("--status", type=pathlib.Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if not args.self_test:
        missing = [
            name
            for name in ("control", "target", "status")
            if getattr(args, name) is None
        ]
        if missing:
            parser.error(f"missing required execution paths: {', '.join(missing)}")
    return args


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if args.self_test:
        return self_test()

    base.validate_candidate_scope = validate_candidate_scope
    base.publish_receipt = publish_receipt
    return base.execute(
        args.control.resolve(),
        args.target.resolve(),
        args.status.resolve(),
    )


if __name__ == "__main__":
    raise SystemExit(main())
