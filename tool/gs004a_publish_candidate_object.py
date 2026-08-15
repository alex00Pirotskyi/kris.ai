#!/usr/bin/env python3
"""Publish an unreferenced exact Git candidate through the Git Data API.

The workflow token may create Git objects but is intentionally not allowed to
move a ref containing workflow changes. The repository connector performs the
final reviewed ref movement after inspecting the candidate SHA/tree.
"""
from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.request


def git(project: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=project,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout.strip()


def api(repository: str, token: str, path: str, payload: dict) -> dict:
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repository}{path}",
        data=json.dumps(payload).encode("utf-8"),
        method="POST",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "kris-ai-gs004a-candidate-publisher",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        value = json.loads(response.read().decode("utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"GitHub API object required for {path}")
    return value


def status_paths(project: Path) -> list[tuple[str, bool]]:
    raw = git(project, "status", "--porcelain=v1", "--untracked-files=all")
    values: list[tuple[str, bool]] = []
    for line in raw.splitlines():
        if len(line) < 4:
            raise RuntimeError(f"unsupported porcelain row: {line!r}")
        status = line[:2]
        relative = line[3:].split(" -> ")[-1].replace("\\", "/")
        deleted = "D" in status and not (project / relative).exists()
        values.append((relative, deleted))
    return sorted(set(values))


def main() -> int:
    project = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    repository = os.environ["GITHUB_REPOSITORY"]
    token = os.environ["GITHUB_TOKEN"]
    parent = git(project, "rev-parse", "HEAD")
    base_tree = git(project, "rev-parse", "HEAD^{tree}")
    paths = status_paths(project)
    if not paths:
        raise SystemExit("candidate publication requires a non-empty working-tree delta")

    entries: list[dict] = []
    for relative, deleted in paths:
        if deleted:
            entries.append(
                {"path": relative, "mode": "100644", "type": "blob", "sha": None}
            )
            continue
        path = project / relative
        data = path.read_bytes()
        blob = api(
            repository,
            token,
            "/git/blobs",
            {
                "content": base64.b64encode(data).decode("ascii"),
                "encoding": "base64",
            },
        )
        mode = "100755" if os.access(path, os.X_OK) else "100644"
        entries.append(
            {"path": relative, "mode": mode, "type": "blob", "sha": blob["sha"]}
        )

    tree = api(
        repository,
        token,
        "/git/trees",
        {"base_tree": base_tree, "tree": entries},
    )
    commit = api(
        repository,
        token,
        "/git/commits",
        {
            "message": "chore(runtime): pin workflow dependencies and finalize sanitation",
            "tree": tree["sha"],
            "parents": [parent],
        },
    )
    result = {
        "candidateCommit": commit["sha"],
        "candidateTree": tree["sha"],
        "parent": parent,
        "changedPaths": [relative for relative, _ in paths],
    }
    print("GS004A_CANDIDATE=" + json.dumps(result, sort_keys=True))
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with Path(output).open("a", encoding="utf-8") as stream:
            stream.write(f"candidate_commit={commit['sha']}\n")
            stream.write(f"candidate_tree={tree['sha']}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
