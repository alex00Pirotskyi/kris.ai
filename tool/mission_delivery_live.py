#!/usr/bin/env python3
from __future__ import annotations
import argparse
import datetime as dt
import fnmatch
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import urllib.error
import urllib.request
from collections import defaultdict
from typing import Any, Iterable

from mission_delivery_lib import *
from mission_delivery_checks import *
def github_api(repo: str, path: str, token: str | None) -> Any:
    url = f"https://api.github.com/repos/{repo}/{path.lstrip('/')}"
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "kris-mission-delivery-control/1",
            **({"Authorization": f"Bearer {token}"} if token else {}),
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        raise DeliveryError(f"GitHub API {url} failed {exc.code}: {body}") from exc
    except urllib.error.URLError as exc:
        raise DeliveryError(f"GitHub API unavailable for {url}: {exc}") from exc


def live_audit(repo: str, model: dict[str, Any], token: str | None) -> dict[str, Any]:
    branches = github_api(repo, "branches?per_page=100", token)
    branch_by_name = {item["name"]: item for item in branches}
    claim_rows = []
    findings = []
    for mission, claim in sorted(model["claims"].items()):
        branch_name = claim["branch"]
        branch = branch_by_name.get(branch_name)
        row = {
            "mission": mission,
            "worker": claim.get("worker"),
            "branch": branch_name,
            "claimHead": claim.get("head"),
            "branchExists": branch is not None,
            "liveBranchHead": branch["commit"]["sha"] if branch else None,
            "pullRequest": claim.get("pr"),
        }
        if branch is None:
            findings.append({"severity": "HIGH", "mission": mission, "finding": "CLAIM_BRANCH_MISSING"})
        elif claim.get("head") != branch["commit"]["sha"]:
            findings.append({"severity": "MEDIUM", "mission": mission, "finding": "CLAIM_HEAD_STALE"})
        pr_number = claim.get("pr")
        if pr_number:
            try:
                pr = github_api(repo, f"pulls/{pr_number}", token)
                row.update(
                    {
                        "prOpen": pr.get("state") == "open",
                        "prHeadBranch": pr.get("head", {}).get("ref"),
                        "prHeadSha": pr.get("head", {}).get("sha"),
                    }
                )
                if pr.get("state") != "open":
                    findings.append({"severity": "HIGH", "mission": mission, "finding": "CLAIM_PR_NOT_OPEN"})
                if pr.get("head", {}).get("ref") != branch_name:
                    findings.append({"severity": "HIGH", "mission": mission, "finding": "CLAIM_PR_BRANCH_MISMATCH"})
            except DeliveryError as exc:
                row["prError"] = str(exc)
                findings.append({"severity": "HIGH", "mission": mission, "finding": "CLAIM_PR_UNRESOLVED"})
        claim_rows.append(row)

    lifecycle = model["config"]["branchLifecycle"]
    hygiene = []
    for item in branches:
        name = item["name"]
        classification = "ACTIVE"
        if matches_any(name, lifecycle.get("protectedPatterns", [])):
            classification = "PROTECTED"
        elif matches_any(name, lifecycle.get("backupPatterns", [])):
            classification = "BACKUP_CANDIDATE"
        elif matches_any(name, lifecycle.get("ephemeralPatterns", [])):
            classification = "EPHEMERAL_CANDIDATE"
        hygiene.append({"branch": name, "head": item["commit"]["sha"], "classification": classification})
    return {
        "schemaVersion": 1,
        "repo": repo,
        "auditedAt": utc_now(),
        "claims": claim_rows,
        "findings": findings,
        "branchHygiene": hygiene,
        "pass": not any(item["severity"] == "HIGH" for item in findings),
    }
