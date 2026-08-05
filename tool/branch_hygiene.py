#!/usr/bin/env python3
"""Fail-closed GitHub branch hygiene for the Kristin repository.

The tool reads an exact, reviewed deletion allowlist. It performs a complete
preflight before deleting any ref:

* repository/default-branch identity must match the policy;
* every present candidate must still point at its reviewed SHA;
* no candidate may be protected or be the default branch;
* no candidate may be the head of an open pull request;
* keep and delete sets must be disjoint;
* only recognized cleanup classes are accepted.

The GitHub token is used only when --execute is supplied. Plan mode is read-only.
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Mapping, Sequence

API_VERSION = "2022-11-28"
ACCEPT = "application/vnd.github+json"
ALLOWED_CLASSES = {
    "disposable-ci",
    "superseded-repair",
    "merged-foundation",
    "superseded-integration",
    "failure-snapshot",
}


class HygieneError(RuntimeError):
    """Raised when the cleanup policy or remote state is unsafe."""


@dataclasses.dataclass(frozen=True)
class BranchState:
    name: str
    sha: str
    protected: bool


@dataclasses.dataclass(frozen=True)
class Candidate:
    name: str
    expected_sha: str
    cleanup_class: str
    reason: str
    closed_pr: int | None = None


class GitHubClient:
    def __init__(self, repository: str, token: str | None) -> None:
        if repository.count("/") != 1:
            raise HygieneError(f"invalid repository name: {repository!r}")
        self.repository = repository
        self.token = token

    def _request(self, method: str, path: str) -> tuple[int, bytes]:
        url = f"https://api.github.com{path}"
        headers = {
            "Accept": ACCEPT,
            "X-GitHub-Api-Version": API_VERSION,
            "User-Agent": "kristin-branch-hygiene/1.0",
        }
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        request = urllib.request.Request(url, method=method, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.status, response.read()
        except urllib.error.HTTPError as exc:
            body = exc.read()
            if exc.code == 404:
                return exc.code, body
            detail = body.decode("utf-8", errors="replace")
            raise HygieneError(
                f"GitHub API {method} {path} failed with HTTP {exc.code}: {detail}"
            ) from exc
        except urllib.error.URLError as exc:
            raise HygieneError(f"GitHub API {method} {path} failed: {exc}") from exc

    def get_json(self, path: str) -> Any:
        status, body = self._request("GET", path)
        if status == 404:
            return None
        if status != 200:
            raise HygieneError(f"unexpected GET status {status} for {path}")
        return json.loads(body.decode("utf-8"))

    def delete_ref(self, branch: str) -> str:
        if not self.token:
            raise HygieneError("GITHUB_TOKEN is required for --execute")
        encoded = urllib.parse.quote(f"heads/{branch}", safe="")
        status, _ = self._request(
            "DELETE", f"/repos/{self.repository}/git/refs/{encoded}"
        )
        if status == 204:
            return "deleted"
        if status == 404:
            return "already_absent"
        raise HygieneError(f"unexpected DELETE status {status} for {branch}")

    def repository_info(self) -> Mapping[str, Any]:
        value = self.get_json(f"/repos/{self.repository}")
        if not isinstance(value, Mapping):
            raise HygieneError("repository metadata is unavailable")
        return value

    def list_branches(self) -> list[BranchState]:
        result: list[BranchState] = []
        page = 1
        while True:
            rows = self.get_json(
                f"/repos/{self.repository}/branches?per_page=100&page={page}"
            )
            if not isinstance(rows, list):
                raise HygieneError("branch listing did not return a list")
            for row in rows:
                if not isinstance(row, Mapping):
                    raise HygieneError("invalid branch row")
                commit = row.get("commit")
                if not isinstance(commit, Mapping):
                    raise HygieneError("branch commit metadata is missing")
                result.append(
                    BranchState(
                        name=_required_string(row, "name"),
                        sha=_required_string(commit, "sha"),
                        protected=bool(row.get("protected")),
                    )
                )
            if len(rows) < 100:
                break
            page += 1
        return result

    def list_open_pr_heads(self) -> set[str]:
        result: set[str] = set()
        page = 1
        while True:
            rows = self.get_json(
                f"/repos/{self.repository}/pulls?state=open&per_page=100&page={page}"
            )
            if not isinstance(rows, list):
                raise HygieneError("pull-request listing did not return a list")
            for row in rows:
                if not isinstance(row, Mapping):
                    raise HygieneError("invalid pull-request row")
                head = row.get("head")
                if isinstance(head, Mapping):
                    ref = head.get("ref")
                    repo = head.get("repo")
                    full_name = repo.get("full_name") if isinstance(repo, Mapping) else None
                    if isinstance(ref, str) and full_name == self.repository:
                        result.add(ref)
            if len(rows) < 100:
                break
            page += 1
        return result


def _required_string(value: Mapping[str, Any], key: str) -> str:
    item = value.get(key)
    if not isinstance(item, str) or not item.strip():
        raise HygieneError(f"missing non-empty string field: {key}")
    return item


def _load_policy(path: Path) -> Mapping[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise HygieneError(f"cannot load branch-hygiene policy {path}: {exc}") from exc
    if not isinstance(value, Mapping):
        raise HygieneError("branch-hygiene policy must be an object")
    return value


def _parse_policy(value: Mapping[str, Any]) -> tuple[str, str, list[str], list[Candidate]]:
    if value.get("schemaVersion") != "1.0.0":
        raise HygieneError("unsupported branch-hygiene schemaVersion")
    roadmap = _required_string(value, "roadmapAuthority")
    if roadmap != "docs/roadmap/MASTER.md":
        raise HygieneError("roadmap authority must be docs/roadmap/MASTER.md")
    default_branch = _required_string(value, "defaultBranch")

    keep_rows = value.get("keep")
    delete_rows = value.get("delete")
    if not isinstance(keep_rows, list) or not isinstance(delete_rows, list):
        raise HygieneError("keep and delete must be arrays")

    keep: list[str] = []
    for row in keep_rows:
        if not isinstance(row, Mapping):
            raise HygieneError("invalid keep row")
        name = _required_string(row, "name")
        _required_string(row, "reason")
        keep.append(name)

    candidates: list[Candidate] = []
    for row in delete_rows:
        if not isinstance(row, Mapping):
            raise HygieneError("invalid delete row")
        cleanup_class = _required_string(row, "class")
        if cleanup_class not in ALLOWED_CLASSES:
            raise HygieneError(f"unrecognized cleanup class: {cleanup_class}")
        closed_pr = row.get("closedPr")
        if closed_pr is not None and (
            not isinstance(closed_pr, int) or isinstance(closed_pr, bool) or closed_pr <= 0
        ):
            raise HygieneError("closedPr must be a positive integer")
        expected_sha = _required_string(row, "expectedSha")
        if len(expected_sha) != 40 or any(ch not in "0123456789abcdef" for ch in expected_sha):
            raise HygieneError(f"invalid expected SHA: {expected_sha!r}")
        candidates.append(
            Candidate(
                name=_required_string(row, "name"),
                expected_sha=expected_sha,
                cleanup_class=cleanup_class,
                reason=_required_string(row, "reason"),
                closed_pr=closed_pr,
            )
        )

    if len(keep) != len(set(keep)):
        raise HygieneError("duplicate branch in keep list")
    candidate_names = [row.name for row in candidates]
    if len(candidate_names) != len(set(candidate_names)):
        raise HygieneError("duplicate branch in delete list")
    overlap = sorted(set(keep) & set(candidate_names))
    if overlap:
        raise HygieneError(f"branches appear in both keep and delete: {overlap}")
    if default_branch not in keep:
        raise HygieneError("default branch must be explicitly retained")
    return roadmap, default_branch, keep, candidates


def _preflight(
    *,
    default_branch: str,
    keep: Sequence[str],
    candidates: Sequence[Candidate],
    branches: Sequence[BranchState],
    open_pr_heads: set[str],
) -> tuple[list[dict[str, Any]], list[str]]:
    branch_map = {row.name: row for row in branches}
    errors: list[str] = []
    plan: list[dict[str, Any]] = []

    default = branch_map.get(default_branch)
    if default is None:
        errors.append(f"default branch {default_branch!r} is missing")
    elif not default.protected:
        errors.append(f"default branch {default_branch!r} is not protected")

    for name in keep:
        if name not in branch_map:
            errors.append(f"retained branch is missing: {name}")

    for candidate in candidates:
        current = branch_map.get(candidate.name)
        entry: dict[str, Any] = {
            "name": candidate.name,
            "class": candidate.cleanup_class,
            "reason": candidate.reason,
            "expectedSha": candidate.expected_sha,
            "closedPr": candidate.closed_pr,
        }
        if current is None:
            entry["preflight"] = "already_absent"
            plan.append(entry)
            continue

        candidate_errors: list[str] = []
        entry["observedSha"] = current.sha
        entry["protected"] = current.protected
        if candidate.name == default_branch:
            candidate_errors.append(f"candidate is the default branch: {candidate.name}")
        if current.protected:
            candidate_errors.append(f"candidate is protected: {candidate.name}")
        if current.sha != candidate.expected_sha:
            candidate_errors.append(
                f"candidate SHA changed for {candidate.name}: "
                f"{current.sha} != {candidate.expected_sha}"
            )
        if candidate.name in open_pr_heads:
            candidate_errors.append(
                f"candidate is the head of an open PR: {candidate.name}"
            )
        errors.extend(candidate_errors)
        entry["preflight"] = "blocked" if candidate_errors else "delete"
        plan.append(entry)

    return plan, errors


def _receipt_base(
    *,
    repository: str,
    roadmap: str,
    default_branch: str,
    branch_count: int,
    keep: Sequence[str],
    plan: Sequence[Mapping[str, Any]],
) -> dict[str, Any]:
    return {
        "schemaVersion": "1.0.0",
        "repository": repository,
        "roadmapAuthority": roadmap,
        "defaultBranch": default_branch,
        "capturedAtUtc": dt.datetime.now(dt.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "workflow": {
            "runId": os.environ.get("GITHUB_RUN_ID"),
            "runAttempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
            "sha": os.environ.get("GITHUB_SHA"),
            "actor": os.environ.get("GITHUB_ACTOR"),
        },
        "beforeBranchCount": branch_count,
        "keep": list(keep),
        "plan": list(plan),
    }


def _write_receipt(path: Path | None, value: Mapping[str, Any]) -> None:
    payload = json.dumps(value, indent=2, sort_keys=True) + "\n"
    if path is not None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(payload, encoding="utf-8", newline="\n")
    print(payload, end="")


def _run_remote(args: argparse.Namespace) -> int:
    config_path = Path(args.config).resolve()
    policy = _load_policy(config_path)
    roadmap, default_branch, keep, candidates = _parse_policy(policy)
    client = GitHubClient(args.repository, os.environ.get("GITHUB_TOKEN"))

    repository_info = client.repository_info()
    observed_default = repository_info.get("default_branch")
    if observed_default != default_branch:
        raise HygieneError(
            f"default-branch mismatch: {observed_default!r} != {default_branch!r}"
        )

    branches = client.list_branches()
    open_pr_heads = client.list_open_pr_heads()
    plan, errors = _preflight(
        default_branch=default_branch,
        keep=keep,
        candidates=candidates,
        branches=branches,
        open_pr_heads=open_pr_heads,
    )
    receipt = _receipt_base(
        repository=args.repository,
        roadmap=roadmap,
        default_branch=default_branch,
        branch_count=len(branches),
        keep=keep,
        plan=plan,
    )
    receipt["openPullRequestHeads"] = sorted(open_pr_heads)
    receipt["mode"] = "execute" if args.execute else "plan"

    if errors:
        receipt["status"] = "blocked"
        receipt["errors"] = errors
        _write_receipt(Path(args.receipt) if args.receipt else None, receipt)
        return 2

    if not args.execute:
        receipt["status"] = "ready"
        receipt["deleteCount"] = sum(
            row.get("preflight") == "delete" for row in plan
        )
        receipt["alreadyAbsentCount"] = sum(
            row.get("preflight") == "already_absent" for row in plan
        )
        _write_receipt(Path(args.receipt) if args.receipt else None, receipt)
        return 0

    results: list[dict[str, Any]] = []
    execution_errors: list[str] = []
    for row in plan:
        result = dict(row)
        if row.get("preflight") == "already_absent":
            result["result"] = "already_absent"
            results.append(result)
            continue
        try:
            result["result"] = client.delete_ref(str(row["name"]))
        except HygieneError as exc:
            result["result"] = "error"
            result["error"] = str(exc)
            execution_errors.append(str(exc))
        results.append(result)

    after = client.list_branches()
    after_names = {row.name for row in after}
    residual = sorted(
        row.name for row in candidates if row.name in after_names
    )
    if residual:
        execution_errors.append(f"candidate branches remain after deletion: {residual}")

    receipt["results"] = results
    receipt["afterBranchCount"] = len(after)
    receipt["deleted"] = sorted(
        str(row["name"]) for row in results if row.get("result") == "deleted"
    )
    receipt["alreadyAbsent"] = sorted(
        str(row["name"])
        for row in results
        if row.get("result") == "already_absent"
    )
    receipt["remainingBranches"] = sorted(after_names)
    if execution_errors:
        receipt["status"] = "partial_failure"
        receipt["errors"] = execution_errors
        _write_receipt(Path(args.receipt) if args.receipt else None, receipt)
        return 3

    receipt["status"] = "success"
    _write_receipt(Path(args.receipt) if args.receipt else None, receipt)
    return 0


def _self_test() -> int:
    valid = {
        "schemaVersion": "1.0.0",
        "roadmapAuthority": "docs/roadmap/MASTER.md",
        "defaultBranch": "main",
        "keep": [
            {"name": "main", "reason": "default"},
            {"name": "active", "reason": "active"},
        ],
        "delete": [
            {
                "name": "old",
                "expectedSha": "a" * 40,
                "class": "disposable-ci",
                "reason": "closed helper",
                "closedPr": 1,
            }
        ],
    }
    _, default, keep, candidates = _parse_policy(valid)
    branches = [
        BranchState("main", "b" * 40, True),
        BranchState("active", "c" * 40, False),
        BranchState("old", "a" * 40, False),
    ]
    plan, errors = _preflight(
        default_branch=default,
        keep=keep,
        candidates=candidates,
        branches=branches,
        open_pr_heads={"active"},
    )
    assert not errors, errors
    assert plan[0]["preflight"] == "delete"

    _, errors = _preflight(
        default_branch=default,
        keep=keep,
        candidates=candidates,
        branches=branches,
        open_pr_heads={"old"},
    )
    assert any("open PR" in value for value in errors)

    moved = [
        BranchState("main", "b" * 40, True),
        BranchState("active", "c" * 40, False),
        BranchState("old", "d" * 40, False),
    ]
    _, errors = _preflight(
        default_branch=default,
        keep=keep,
        candidates=candidates,
        branches=moved,
        open_pr_heads=set(),
    )
    assert any("SHA changed" in value for value in errors)

    missing = [
        BranchState("main", "b" * 40, True),
        BranchState("active", "c" * 40, False),
    ]
    plan, errors = _preflight(
        default_branch=default,
        keep=keep,
        candidates=candidates,
        branches=missing,
        open_pr_heads=set(),
    )
    assert not errors
    assert plan[0]["preflight"] == "already_absent"

    duplicate = json.loads(json.dumps(valid))
    duplicate["delete"].append(dict(duplicate["delete"][0]))
    try:
        _parse_policy(duplicate)
    except HygieneError:
        pass
    else:
        raise AssertionError("duplicate delete branch was accepted")

    print("branch_hygiene self-test: PASS")
    return 0


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--config",
        default="config/branch_hygiene.json",
        help="reviewed exact branch cleanup policy",
    )
    parser.add_argument(
        "--repository",
        default=os.environ.get("GITHUB_REPOSITORY", ""),
        help="owner/name repository identity",
    )
    parser.add_argument("--receipt", help="optional JSON receipt path")
    parser.add_argument(
        "--execute",
        action="store_true",
        help="delete exact reviewed refs after a complete safe preflight",
    )
    parser.add_argument("--self-test", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        if args.self_test:
            return _self_test()
        if not args.repository:
            raise HygieneError("--repository or GITHUB_REPOSITORY is required")
        return _run_remote(args)
    except HygieneError as exc:
        print(f"branch_hygiene: ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
