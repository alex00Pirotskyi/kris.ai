#!/usr/bin/env python3
"""Resolve the exact current P1A Actions job and controlled runner identity.

The output is not itself completion evidence. It is an API-observed input bound
inside the externally signed runner/build/behavior receipts.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import time
import urllib.request


def required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise SystemExit(f"{name} required")
    return value


def canonical(value: object) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--github-env", required=True)
    parser.add_argument("--platform", choices=("linux", "macos", "windows"), required=True)
    parser.add_argument("--job-name", required=True)
    parser.add_argument("--commit-sha", required=True)
    args = parser.parse_args()

    repository = required("GITHUB_REPOSITORY")
    run_id = required("GITHUB_RUN_ID")
    run_attempt = required("GITHUB_RUN_ATTEMPT")
    token = required("GITHUB_TOKEN")
    runner_name = required("RUNNER_NAME")
    if len(args.commit_sha) != 40:
        raise SystemExit("exact commit required")

    url = (
        f"https://api.github.com/repos/{repository}/actions/runs/{run_id}/"
        f"attempts/{run_attempt}/jobs?per_page=100"
    )
    selected = None
    deadline = time.monotonic() + 120
    last = ""
    while time.monotonic() < deadline:
        try:
            request = urllib.request.Request(
                url,
                headers={
                    "Accept": "application/vnd.github+json",
                    "Authorization": f"Bearer {token}",
                    "X-GitHub-Api-Version": "2022-11-28",
                    "User-Agent": "kristin-p1a-v63",
                },
            )
            with urllib.request.urlopen(request, timeout=30) as response:
                data = json.loads(response.read())
            matches = [
                row
                for row in data.get("jobs", [])
                if row.get("name") == args.job_name and row.get("runner_name") == runner_name
            ]
            if len(matches) == 1:
                selected = matches[0]
                break
            last = f"matches={len(matches)}"
        except Exception as error:  # network and API errors are fail-closed
            last = repr(error)
        time.sleep(3)
    if selected is None:
        raise SystemExit(f"exact current GitHub job unresolved: {last}")

    labels = list(map(str, selected.get("labels") or []))
    expected_os = {
        "linux": "ubuntu-24.04",
        "macos": "macos-15",
        "windows": "windows-2025",
    }[args.platform]
    required_labels = {
        "self-hosted",
        "kristin-p1a",
        args.platform,
        "authority-isolated",
        "interactive-desktop",
        expected_os,
    }
    if not required_labels.issubset(labels):
        raise SystemExit(
            f"GitHub P1A job labels mismatch: missing={sorted(required_labels - set(labels))}"
        )
    runner_group = str(selected.get("runner_group_name") or "")
    if runner_group != "kristin-p1a-controlled":
        raise SystemExit(f"unexpected P1A runner group: {runner_group!r}")

    row = {
        "schemaVersion": "1.0.0",
        "receiptType": "p1a-github-job-identity-v1",
        "repository": repository,
        "repositoryId": int(required("GITHUB_REPOSITORY_ID")),
        "workflowName": required("GITHUB_WORKFLOW"),
        "workflowPath": ".github/workflows/p1-authority-amendment.yml",
        "workflowRef": required("GITHUB_WORKFLOW_REF"),
        "workflowRunId": run_id,
        "runAttempt": int(run_attempt),
        "jobName": args.job_name,
        "githubJobId": int(selected["id"]),
        "sourceCommit": args.commit_sha,
        "runnerId": int(selected["runner_id"]),
        "runnerName": str(selected["runner_name"]),
        "runnerGroupId": int(selected["runner_group_id"]),
        "runnerGroup": runner_group,
        "labels": labels,
        "platform": args.platform,
        "apiPayloadSha256": hashlib.sha256(canonical(selected)).hexdigest(),
        "status": "observed",
        "completionEligible": False,
    }
    output = pathlib.Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(row, indent=2, sort_keys=True) + "\n")
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    values = {
        "KRISTIN_P1A_GITHUB_JOB_ID": row["githubJobId"],
        "KRISTIN_P1A_RUNNER_ID": row["runnerId"],
        "KRISTIN_P1A_RUNNER_GROUP_ID": row["runnerGroupId"],
        "KRISTIN_P1A_RUNNER_GROUP": row["runnerGroup"],
        "KRISTIN_P1A_GITHUB_JOB_IDENTITY_RECEIPT": output,
        "KRISTIN_P1A_GITHUB_JOB_IDENTITY_SHA256": digest,
    }
    with pathlib.Path(args.github_env).open("a", encoding="utf-8") as stream:
        for key, value in values.items():
            stream.write(f"{key}={value}\n")
    print(json.dumps({"receipt": str(output), "sha256": digest}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
