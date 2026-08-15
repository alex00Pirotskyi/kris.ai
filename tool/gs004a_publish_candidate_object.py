#!/usr/bin/env python3
"""Publish exact changed-file blobs for a connector-owned Git tree handoff.

The workflow token may publish immutable blob objects, but it intentionally does
not create a workflow-changing tree or move a ref. The connected repository
authority consumes the logged base tree, parent, and entries.
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


def create_blob(repository: str, token: str, data: bytes) -> str:
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repository}/git/blobs",
        data=json.dumps(
            {
                "content": base64.b64encode(data).decode("ascii"),
                "encoding": "base64",
            }
        ).encode("utf-8"),
        method="POST",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "User-Agent": "kris-ai-gs004a-blob-handoff",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        value = json.loads(response.read().decode("utf-8"))
    if not isinstance(value, dict) or not isinstance(value.get("sha"), str):
        raise RuntimeError("GitHub blob response missing SHA")
    return value["sha"]


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
        raise SystemExit("blob handoff requires a non-empty working-tree delta")

    entries: list[dict[str, object]] = []
    for relative, deleted in paths:
        if deleted:
            entries.append(
                {"path": relative, "mode": "100644", "type": "blob", "sha": None}
            )
            continue
        path = project / relative
        mode = "100755" if os.access(path, os.X_OK) else "100644"
        entries.append(
            {
                "path": relative,
                "mode": mode,
                "type": "blob",
                "sha": create_blob(repository, token, path.read_bytes()),
            }
        )

    result = {
        "baseTree": base_tree,
        "parent": parent,
        "entries": entries,
    }
    rendered = json.dumps(result, sort_keys=True, separators=(",", ":"))
    print("GS004A_BLOB_HANDOFF=" + rendered)
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with Path(output).open("a", encoding="utf-8") as stream:
            stream.write("blob_handoff=" + rendered + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
