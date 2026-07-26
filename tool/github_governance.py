#!/usr/bin/env python3
"""Plan, apply, and verify P0-006 GitHub repository governance.

The token is read from an environment variable only. It is never printed or
persisted. Source preparation and the P0-003 dependency must already be in the
checkout before remote enforcement can be activated.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode, urlparse
from urllib.request import Request, urlopen

DEFAULT_API_BASE = "https://api.github.com"
DEFAULT_TOKEN_ENV = "GITHUB_TOKEN"
FULL_SHA = re.compile(r"^[0-9a-f]{40}$")
REQUIRED_CHECKS = ("validate-ubuntu", "validate-windows", "validate-macos")


class GovernanceError(RuntimeError):
    """Expected refusal or remote API failure."""


def canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise GovernanceError(f"required file is missing: {path}") from error
    except json.JSONDecodeError as error:
        raise GovernanceError(f"invalid JSON in {path}: {error}") from error
    if not isinstance(value, dict):
        raise GovernanceError(f"{path} root must be an object")
    return value


def split_repository(value: str) -> tuple[str, str]:
    normalized = value.strip().removesuffix(".git").strip("/")
    if normalized.startswith("https://github.com/"):
        normalized = normalized[len("https://github.com/") :]
    if normalized.startswith("git@github.com:"):
        normalized = normalized[len("git@github.com:") :]
    parts = normalized.split("/")
    if len(parts) != 2 or not all(parts):
        raise GovernanceError("repository must be OWNER/REPO or a github.com repository URL")
    return parts[0], parts[1]


def discover_repository(project: Path) -> str | None:
    if not (project / ".git").exists():
        return None
    completed = subprocess.run(
        ["git", "remote", "get-url", "origin"],
        cwd=project,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        return None
    value = completed.stdout.strip()
    try:
        owner, repo = split_repository(value)
    except GovernanceError:
        return None
    return f"{owner}/{repo}"


def current_head(project: Path) -> str | None:
    if not (project / ".git").exists():
        return None
    completed = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=project,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        return None
    value = completed.stdout.strip()
    return value if FULL_SHA.fullmatch(value) else None


def is_ancestor(project: Path, ancestor: str, descendant: str) -> bool:
    if not (project / ".git").exists():
        return ancestor == descendant
    completed = subprocess.run(
        ["git", "merge-base", "--is-ancestor", ancestor, descendant],
        cwd=project,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return completed.returncode == 0


def validate_p0_003(project: Path) -> dict[str, Any]:
    payload = load_object(project / "release/evidence/P0-003/ci_matrix.json")
    failures: list[str] = []
    if payload.get("milestone") != "P0-003":
        failures.append("milestone is not P0-003")
    if payload.get("status") != "passed":
        failures.append("status is not passed")
    commit = str(payload.get("commit") or "")
    if FULL_SHA.fullmatch(commit) is None:
        failures.append("commit is not a full 40-character SHA")
    if not str(payload.get("workflowRunUrl") or "").startswith("https://"):
        failures.append("workflowRunUrl is missing")
    lanes = payload.get("lanes")
    if not isinstance(lanes, dict):
        failures.append("lanes is not an object")
        lanes = {}
    for lane, check_name in zip(("ubuntu", "windows", "macos"), REQUIRED_CHECKS):
        item = lanes.get(lane)
        if not isinstance(item, dict):
            failures.append(f"{lane} lane is missing")
            continue
        if item.get("status") != "passed":
            failures.append(f"{lane} status is not passed")
        if item.get("nativeBuild") != "passed":
            failures.append(f"{lane} nativeBuild is not passed")
        if item.get("checkName") != check_name:
            failures.append(f"{lane} checkName is not {check_name}")
        if not str(item.get("jobUrl") or "").startswith("https://"):
            failures.append(f"{lane} jobUrl is missing")
        if not item.get("environmentEvidence"):
            failures.append(f"{lane} environmentEvidence is missing")
    head = current_head(project)
    if head and commit and not is_ancestor(project, commit, head):
        failures.append(f"P0-003 commit {commit} is not an ancestor of current HEAD {head}")
    if failures:
        raise GovernanceError("P0-003 dependency is not closed:\n- " + "\n- ".join(failures))
    return payload


def build_ruleset(config: dict[str, Any]) -> dict[str, Any]:
    ruleset = config.get("ruleset")
    if not isinstance(ruleset, dict):
        raise GovernanceError("repository_governance.json ruleset must be an object")
    checks = ruleset.get("requiredStatusChecks")
    if checks != list(REQUIRED_CHECKS):
        raise GovernanceError(f"requiredStatusChecks must be exactly {list(REQUIRED_CHECKS)!r}")
    if ruleset.get("bypassActors") != []:
        raise GovernanceError("P0-006 permits no silent bypass actors")
    rules: list[dict[str, Any]] = []
    if ruleset.get("blockDeletions") is True:
        rules.append({"type": "deletion"})
    if ruleset.get("blockForcePushes") is True:
        rules.append({"type": "non_fast_forward"})
    if ruleset.get("requireLinearHistory") is True:
        rules.append({"type": "required_linear_history"})
    if ruleset.get("requireSignedCommits") is True:
        rules.append({"type": "required_signatures"})
    if ruleset.get("requirePullRequest") is True:
        rules.append(
            {
                "type": "pull_request",
                "parameters": {
                    "allowed_merge_methods": list(ruleset.get("allowedMergeMethods") or []),
                    "dismiss_stale_reviews_on_push": bool(ruleset.get("dismissStaleReviewsOnPush")),
                    "require_code_owner_review": bool(ruleset.get("requireCodeOwnerReview")),
                    "require_last_push_approval": bool(ruleset.get("requireLastPushApproval")),
                    "required_approving_review_count": int(ruleset.get("requiredApprovingReviewCount") or 0),
                    "required_review_thread_resolution": bool(ruleset.get("requiredReviewThreadResolution")),
                },
            }
        )
    rules.append(
        {
            "type": "required_status_checks",
            "parameters": {
                "do_not_enforce_on_create": False,
                "required_status_checks": [{"context": item} for item in checks],
                "strict_required_status_checks_policy": bool(ruleset.get("strictRequiredStatusChecks")),
            },
        }
    )
    return {
        "name": str(ruleset.get("name")),
        "target": str(ruleset.get("target") or "branch"),
        "enforcement": str(ruleset.get("enforcement") or "active"),
        "bypass_actors": [],
        "conditions": {
            "ref_name": {
                "include": list(ruleset.get("include") or ["~DEFAULT_BRANCH"]),
                "exclude": list(ruleset.get("exclude") or []),
            }
        },
        "rules": rules,
    }


def build_repository_patch(config: dict[str, Any]) -> dict[str, Any]:
    settings = config.get("repositorySettings")
    if not isinstance(settings, dict):
        raise GovernanceError("repositorySettings must be an object")
    return {
        "allow_merge_commit": bool(settings.get("allowMergeCommit")),
        "allow_squash_merge": bool(settings.get("allowSquashMerge")),
        "allow_rebase_merge": bool(settings.get("allowRebaseMerge")),
        "delete_branch_on_merge": bool(settings.get("deleteBranchOnMerge")),
        "allow_auto_merge": bool(settings.get("allowAutoMerge")),
    }


class GitHubClient:
    def __init__(self, api_base: str, api_version: str, token: str | None, timeout: int = 30):
        parsed = urlparse(api_base)
        if parsed.scheme not in {"http", "https"} or not parsed.netloc:
            raise GovernanceError("api base must be an http(s) URL")
        self.api_base = api_base.rstrip("/")
        self.api_version = api_version
        self.token = token
        self.timeout = timeout

    def request(self, method: str, path: str, body: Any | None = None) -> tuple[int, Any]:
        url = self.api_base + path
        headers = {
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": self.api_version,
            "User-Agent": "kristin-p0-006-governance/1.0",
        }
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        data = None
        if body is not None:
            data = canonical(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = Request(url, data=data, method=method, headers=headers)
        try:
            with urlopen(request, timeout=self.timeout) as response:
                raw = response.read()
                value = json.loads(raw.decode("utf-8")) if raw else None
                return int(response.status), value
        except HTTPError as error:
            raw = error.read().decode("utf-8", errors="replace")
            try:
                detail = json.loads(raw)
            except json.JSONDecodeError:
                detail = {"message": raw[-2000:]}
            raise GovernanceError(
                f"GitHub API {method} {path} failed with HTTP {error.code}: "
                f"{detail.get('message') if isinstance(detail, dict) else detail}"
            ) from error
        except URLError as error:
            raise GovernanceError(f"GitHub API {method} {path} failed: {error.reason}") from error


def find_ruleset(client: GitHubClient, owner: str, repo: str, name: str) -> dict[str, Any] | None:
    _status, value = client.request(
        "GET", f"/repos/{quote(owner)}/{quote(repo)}/rulesets?" + urlencode({"includes_parents": "false", "per_page": 100})
    )
    if not isinstance(value, list):
        raise GovernanceError("GitHub rulesets response was not an array")
    matches = [item for item in value if isinstance(item, dict) and item.get("name") == name]
    if len(matches) > 1:
        raise GovernanceError(f"multiple rulesets named {name!r} exist")
    return matches[0] if matches else None


def apply_ruleset(client: GitHubClient, owner: str, repo: str, desired: dict[str, Any]) -> dict[str, Any]:
    existing = find_ruleset(client, owner, repo, str(desired["name"]))
    if existing is None:
        _status, value = client.request("POST", f"/repos/{quote(owner)}/{quote(repo)}/rulesets", desired)
        action = "created"
    else:
        ruleset_id = existing.get("id")
        if not isinstance(ruleset_id, int):
            raise GovernanceError("existing ruleset lacks an integer id")
        _status, value = client.request(
            "PUT", f"/repos/{quote(owner)}/{quote(repo)}/rulesets/{ruleset_id}", desired
        )
        action = "updated"
    if not isinstance(value, dict):
        raise GovernanceError("GitHub ruleset write response was not an object")
    return {"action": action, "id": value.get("id"), "name": value.get("name"), "enforcement": value.get("enforcement")}


def apply_repository_settings(client: GitHubClient, owner: str, repo: str, patch: dict[str, Any]) -> dict[str, Any]:
    _status, value = client.request("PATCH", f"/repos/{quote(owner)}/{quote(repo)}", patch)
    if not isinstance(value, dict):
        raise GovernanceError("repository settings response was not an object")
    return {
        "defaultBranch": value.get("default_branch"),
        "allowMergeCommit": value.get("allow_merge_commit"),
        "allowSquashMerge": value.get("allow_squash_merge"),
        "allowRebaseMerge": value.get("allow_rebase_merge"),
        "deleteBranchOnMerge": value.get("delete_branch_on_merge"),
        "allowAutoMerge": value.get("allow_auto_merge"),
    }


def list_labels(client: GitHubClient, owner: str, repo: str) -> dict[str, dict[str, Any]]:
    _status, value = client.request("GET", f"/repos/{quote(owner)}/{quote(repo)}/labels?per_page=100")
    if not isinstance(value, list):
        raise GovernanceError("labels response was not an array")
    return {str(item.get("name")): item for item in value if isinstance(item, dict) and item.get("name")}


def apply_labels(client: GitHubClient, owner: str, repo: str, labels: list[dict[str, Any]]) -> list[dict[str, Any]]:
    existing = list_labels(client, owner, repo)
    results: list[dict[str, Any]] = []
    for label in labels:
        name = str(label.get("name") or "")
        update_body = {
            "new_name": name,
            "color": str(label.get("color") or "ededed").lstrip("#"),
            "description": str(label.get("description") or ""),
        }
        if name in existing:
            _status, value = client.request(
                "PATCH", f"/repos/{quote(owner)}/{quote(repo)}/labels/{quote(name, safe='')}", update_body
            )
            action = "updated"
        else:
            create_body = {
                "name": name,
                "color": update_body["color"],
                "description": update_body["description"],
            }
            _status, value = client.request("POST", f"/repos/{quote(owner)}/{quote(repo)}/labels", create_body)
            action = "created"
        results.append({"name": name, "action": action, "id": value.get("id") if isinstance(value, dict) else None})
    return results


def normalize_rule_types(value: dict[str, Any]) -> dict[str, Any]:
    rules = value.get("rules") if isinstance(value, dict) else None
    result: dict[str, Any] = {}
    if isinstance(rules, list):
        for item in rules:
            if isinstance(item, dict) and item.get("type"):
                result[str(item["type"])] = item.get("parameters") or {}
    return result


def verify_remote(
    client: GitHubClient,
    owner: str,
    repo: str,
    config: dict[str, Any],
    desired: dict[str, Any],
) -> dict[str, Any]:
    summary = find_ruleset(client, owner, repo, str(desired["name"]))
    if summary is None or not isinstance(summary.get("id"), int):
        raise GovernanceError("desired ruleset does not exist")
    ruleset_id = int(summary["id"])
    _status, full = client.request("GET", f"/repos/{quote(owner)}/{quote(repo)}/rulesets/{ruleset_id}")
    if not isinstance(full, dict):
        raise GovernanceError("ruleset verification response was not an object")
    failures: list[str] = []
    if full.get("name") != desired.get("name"):
        failures.append(f"ruleset name is {full.get('name')!r}, expected {desired.get('name')!r}")
    if full.get("target") != desired.get("target"):
        failures.append(f"ruleset target is {full.get('target')!r}, expected {desired.get('target')!r}")
    if full.get("enforcement") != desired.get("enforcement"):
        failures.append(
            f"ruleset enforcement is {full.get('enforcement')!r}, expected {desired.get('enforcement')!r}"
        )
    if full.get("bypass_actors") not in ([], None):
        failures.append("ruleset has bypass actors")
    conditions = full.get("conditions")
    ref_name = conditions.get("ref_name") if isinstance(conditions, dict) else None
    desired_ref = desired.get("conditions", {}).get("ref_name", {})
    if not isinstance(ref_name, dict):
        failures.append("ruleset ref-name condition is missing")
    else:
        if sorted(ref_name.get("include") or []) != sorted(desired_ref.get("include") or []):
            failures.append(f"ruleset includes differ: {ref_name.get('include')!r}")
        if sorted(ref_name.get("exclude") or []) != sorted(desired_ref.get("exclude") or []):
            failures.append(f"ruleset excludes differ: {ref_name.get('exclude')!r}")
    rule_types = normalize_rule_types(full)
    desired_rule_types = normalize_rule_types(desired)
    for required in ("deletion", "non_fast_forward", "required_linear_history", "pull_request", "required_status_checks"):
        if required not in rule_types:
            failures.append(f"ruleset missing {required}")
    unexpected_rules = sorted(set(rule_types) - set(desired_rule_types))
    if unexpected_rules:
        failures.append("ruleset has unexpected rules: " + ", ".join(unexpected_rules))
    pull = rule_types.get("pull_request", {})
    desired_pull = desired_rule_types.get("pull_request", {})
    for key in (
        "dismiss_stale_reviews_on_push",
        "require_code_owner_review",
        "require_last_push_approval",
        "required_approving_review_count",
        "required_review_thread_resolution",
    ):
        if pull.get(key) != desired_pull.get(key):
            failures.append(f"pull-request rule {key} is {pull.get(key)!r}, expected {desired_pull.get(key)!r}")
    if sorted(pull.get("allowed_merge_methods") or []) != sorted(desired_pull.get("allowed_merge_methods") or []):
        failures.append(
            f"allowed merge methods are {pull.get('allowed_merge_methods')!r}, "
            f"expected {desired_pull.get('allowed_merge_methods')!r}"
        )
    status = rule_types.get("required_status_checks", {})
    desired_status = desired_rule_types.get("required_status_checks", {})
    contexts = [item.get("context") for item in status.get("required_status_checks", []) if isinstance(item, dict)]
    desired_contexts = [
        item.get("context")
        for item in desired_status.get("required_status_checks", [])
        if isinstance(item, dict)
    ]
    if contexts != desired_contexts:
        failures.append(f"required status checks differ: {contexts}")
    for key in ("strict_required_status_checks_policy", "do_not_enforce_on_create"):
        if status.get(key) != desired_status.get(key):
            failures.append(f"status-check rule {key} is {status.get(key)!r}, expected {desired_status.get(key)!r}")

    _repo_status, repository = client.request("GET", f"/repos/{quote(owner)}/{quote(repo)}")
    if not isinstance(repository, dict):
        failures.append("repository settings response was not an object")
        repository = {}
    desired_settings = build_repository_patch(config)
    for key, expected in desired_settings.items():
        if repository.get(key) != expected:
            failures.append(f"repository setting {key} is {repository.get(key)!r}, expected {expected!r}")

    labels = list_labels(client, owner, repo)
    desired_labels = config.get("labels")
    if not isinstance(desired_labels, list):
        desired_labels = []
    missing_labels: list[str] = []
    for item in desired_labels:
        if not isinstance(item, dict):
            continue
        name = str(item.get("name"))
        actual = labels.get(name)
        if actual is None:
            missing_labels.append(name)
            continue
        expected_color = str(item.get("color") or "").lstrip("#").lower()
        actual_color = str(actual.get("color") or "").lstrip("#").lower()
        if actual_color != expected_color:
            failures.append(f"label {name!r} color is {actual_color!r}, expected {expected_color!r}")
        if str(actual.get("description") or "") != str(item.get("description") or ""):
            failures.append(f"label {name!r} description differs")
    if missing_labels:
        failures.append("missing labels: " + ", ".join(missing_labels))
    if failures:
        raise GovernanceError("remote governance verification failed:\n- " + "\n- ".join(failures))
    return {
        "ruleset": {
            "id": ruleset_id,
            "name": full.get("name"),
            "enforcement": full.get("enforcement"),
            "requiredChecks": contexts,
            "ruleTypes": sorted(rule_types),
        },
        "repositorySettings": {
            "defaultBranch": repository.get("default_branch"),
            **{key: repository.get(key) for key in desired_settings},
        },
        "labels": sorted(str(item.get("name")) for item in desired_labels if isinstance(item, dict)),
    }


def write_receipt(project: Path, payload: dict[str, Any], relative: str) -> Path:
    target = Path(relative)
    if not target.is_absolute():
        target = project / target
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return target


def main() -> int:
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--plan", action="store_true")
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--verify", action="store_true")
    parser.add_argument("--project", default=".")
    parser.add_argument("--repository")
    parser.add_argument("--config", default="config/repository_governance.json")
    parser.add_argument("--api-base", default=DEFAULT_API_BASE)
    parser.add_argument("--token-env", default=DEFAULT_TOKEN_ENV)
    parser.add_argument("--confirm-solo-maintainer", action="store_true")
    parser.add_argument("--receipt", default="release/evidence/P0-006/github_governance_receipt.json")
    args = parser.parse_args()

    project = Path(args.project).expanduser().resolve()
    config_path = Path(args.config)
    if not config_path.is_absolute():
        config_path = project / config_path
    config = load_object(config_path)
    p0_003 = validate_p0_003(project)
    repository = args.repository or str(config.get("repository") or "") or discover_repository(project)
    if not repository:
        raise GovernanceError("repository is not configured and could not be discovered")
    owner, repo = split_repository(repository)
    desired_ruleset = build_ruleset(config)
    desired_repository = build_repository_patch(config)
    labels = config.get("labels")
    if not isinstance(labels, list):
        raise GovernanceError("labels must be an array")

    plan = {
        "schemaVersion": "1.0.0",
        "milestone": "P0-006",
        "repository": f"{owner}/{repo}",
        "apiBase": args.api_base,
        "apiVersion": str(config.get("githubApiVersion") or "2026-03-10"),
        "p0_003Commit": p0_003.get("commit"),
        "ruleset": desired_ruleset,
        "repositorySettings": desired_repository,
        "labels": labels,
        "tokenSource": f"environment:{args.token_env}",
        "tokenPersisted": False,
    }
    if args.plan:
        print(json.dumps(plan, indent=2, sort_keys=True))
        return 0

    if args.apply and not args.confirm_solo_maintainer:
        raise GovernanceError(
            "refusing to activate solo-maintainer governance without --confirm-solo-maintainer; "
            "review and commit the Stage B self-review attestation first"
        )
    token = os.environ.get(args.token_env)
    if not token:
        raise GovernanceError(f"{args.token_env} is not set; token is read from the environment only")
    client = GitHubClient(args.api_base, plan["apiVersion"], token)

    apply_result: dict[str, Any] | None = None
    if args.apply:
        apply_result = {
            "ruleset": apply_ruleset(client, owner, repo, desired_ruleset),
            "repositorySettings": apply_repository_settings(client, owner, repo, desired_repository),
            "labels": apply_labels(client, owner, repo, labels),
        }
    verified = verify_remote(client, owner, repo, config, desired_ruleset)
    receipt = {
        "schemaVersion": "1.0.0",
        "milestone": "P0-006",
        "status": "passed",
        "mode": "apply" if args.apply else "verify",
        "repository": f"{owner}/{repo}",
        "apiBase": args.api_base,
        "apiVersion": plan["apiVersion"],
        "p0_003Commit": p0_003.get("commit"),
        "currentHead": current_head(project),
        "completedAt": dt.datetime.now(dt.timezone.utc).isoformat(),
        "applyResult": apply_result,
        "verified": verified,
        "tokenSource": f"environment:{args.token_env}",
        "tokenPersisted": False,
    }
    target = write_receipt(project, receipt, args.receipt)
    print(json.dumps({**receipt, "receiptPath": str(target)}, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except GovernanceError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)
