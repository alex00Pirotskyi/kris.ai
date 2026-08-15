#!/usr/bin/env python3
"""Merge exact P5-001, validate actual main, and close runtime authority."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
REPO = "alex00Pirotskyi/kris.ai"
API = f"https://api.github.com/repos/{REPO}"
RUNTIME_BRANCH = "agent/mission-runtime"
PR_NUMBER = 72
EXPECTED_HEAD = "e43f76203a7b96e33d1f324b98d134583ca00a80"
EXPECTED_TREE = "13360a13e915ef798b07f977ab490626a6b042fb"
WORK_ORDER = "WO-P5-001-CURRENT-MAIN-LANDING-6F4A91C2"
SEMAPHORE = "SEM-P5-001-CURRENT-MAIN-LANDING-6F4A91C2"
WORK_EXECUTION_ID = "WRK-20260815T103835Z-6f4a91c2"
WORKER = "GPT-5.6-PRO-6F4A91C2"
TEMP_PATHS = (
    ".github/workflows/temp-p5-runtime-main-finalize-20260815.yml",
    "tool/temp_p5_runtime_main_finalize_20260815.py",
)


def now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def run(*args: str, cwd: Path = ROOT, capture: bool = False) -> str:
    result = subprocess.run(
        list(args),
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(args)}\n"
            f"{(result.stdout or '')[-4000:]}"
        )
    return (result.stdout or "").strip()


def api(path: str, *, method: str = "GET", body: dict | None = None) -> dict:
    token = os.environ.get("GH_TOKEN", "").strip()
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "kris-p5-main-finalizer",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    payload = None if body is None else json.dumps(body).encode("utf-8")
    request = Request(API + path, data=payload, headers=headers, method=method)
    try:
        with urlopen(request, timeout=45) as response:
            raw = response.read()
    except HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"GitHub API {method} {path} failed: {exc.code}: {detail[:2000]}") from exc
    return json.loads(raw.decode("utf-8")) if raw else {}


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")


def settle_pr_and_main() -> tuple[str, str]:
    pr = api(f"/pulls/{PR_NUMBER}")
    if pr["head"]["sha"] != EXPECTED_HEAD:
        raise RuntimeError(f"PR #{PR_NUMBER} head moved to {pr['head']['sha']}")

    if not pr.get("merged", False):
        if pr.get("state") != "open":
            raise RuntimeError(f"PR #{PR_NUMBER} is {pr.get('state')} but not merged")
        response = api(
            f"/pulls/{PR_NUMBER}/merge",
            method="PUT",
            body={
                "sha": EXPECTED_HEAD,
                "merge_method": "squash",
                "commit_title": "feat(p5): ship integrated Experience workspace",
                "commit_message": (
                    "Land the exact P5-001 candidate after owner-context tri-platform "
                    "and compatibility validation. P5-002+, accessibility certification, "
                    "support, release, production, and GA remain outside this landing."
                ),
            },
        )
        if not response.get("merged", False):
            raise RuntimeError(f"PR #{PR_NUMBER} merge was refused: {response}")

    for _ in range(30):
        pr = api(f"/pulls/{PR_NUMBER}")
        main_ref = api("/git/ref/heads/main")
        main_sha = main_ref["object"]["sha"]
        if pr.get("merged", False) and pr.get("merge_commit_sha") == main_sha:
            break
        time.sleep(2)
    else:
        raise RuntimeError("merged PR and protected main did not converge")

    run("git", "fetch", "--no-tags", "origin", "+refs/heads/main:refs/remotes/origin/main")
    fetched_main = run("git", "rev-parse", "refs/remotes/origin/main", capture=True)
    if fetched_main != main_sha:
        raise RuntimeError("API main and fetched main disagree")
    main_tree = run("git", "rev-parse", f"{main_sha}^{{tree}}", capture=True)
    if main_tree != EXPECTED_TREE:
        raise RuntimeError(
            f"actual main tree {main_tree} does not match validated P5 tree {EXPECTED_TREE}"
        )
    return main_sha, main_tree


def validate_main(main_sha: str) -> None:
    checkout = ROOT.parent / "p5-main-checkout"
    if checkout.exists():
        shutil.rmtree(checkout, ignore_errors=True)
    run("git", "worktree", "prune")
    run("git", "worktree", "add", "--detach", str(checkout), main_sha)
    try:
        run("flutter", "pub", "get", cwd=checkout)
        run("python3", "tool/dart_format_scope.py", "--check", cwd=checkout)
        run(
            "flutter",
            "analyze",
            "--no-pub",
            "--fatal-warnings",
            "--fatal-infos",
            cwd=checkout,
        )
        run(
            "flutter",
            "test",
            "--no-pub",
            "--concurrency=1",
            "--reporter",
            "expanded",
            cwd=checkout,
        )
        run("npm", "ci", "--prefix", "automation_host", cwd=checkout)
        run("npm", "test", "--prefix", "automation_host", cwd=checkout)

        validator_code = r'''
import importlib.util
import sys
from pathlib import Path
root = Path.cwd()
sys.path.insert(0, str(root / "tool"))
spec = importlib.util.spec_from_file_location("p5_main_validate_release", root / "tool/validate_release.py")
if spec is None or spec.loader is None:
    raise RuntimeError("cannot load release validator")
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
module.checks.clear()
module.check_chat_workspace_ux()
failures = [c.detail for c in module.checks if c.blocking and c.status != "passed"]
if failures:
    raise RuntimeError(f"chat workspace release validation failed: {failures}")
'''
        run("python3", "-c", validator_code, cwd=checkout)
        run("python3", "tool/p1a_refresh_source_manifest.py", ".", cwd=checkout)
        first = (checkout / "SOURCE_MANIFEST.sha256").read_bytes()
        run("python3", "tool/p1a_refresh_source_manifest.py", ".", cwd=checkout)
        if (checkout / "SOURCE_MANIFEST.sha256").read_bytes() != first:
            raise RuntimeError("actual-main source manifest is not byte-stable")
        run("python3", "tool/p1a_text_eof_contract_test.py", "--project", ".", cwd=checkout)
        run("git", "diff", "--exit-code", cwd=checkout)
    finally:
        run("git", "worktree", "remove", "--force", str(checkout))


def finalize_runtime(
    *,
    work_status: str,
    product_status: str,
    event_type: str,
    detail: str,
    main_sha: str | None,
    main_tree: str | None,
) -> None:
    run("git", "fetch", "--no-tags", "origin", f"+refs/heads/{RUNTIME_BRANCH}:refs/remotes/origin/{RUNTIME_BRANCH}")
    remote = run("git", "rev-parse", f"refs/remotes/origin/{RUNTIME_BRANCH}", capture=True)
    arm_sha = os.environ.get("GITHUB_SHA", "").strip()
    run("git", "merge-base", "--is-ancestor", arm_sha, remote)
    run("git", "reset", "--hard", remote)

    for relative in TEMP_PATHS:
        path = ROOT / relative
        if path.exists():
            path.unlink()

    stamp = now()
    meta_path = ROOT / "runtime/meta.json"
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    generation = int(meta["runtimeGeneration"]) + 1
    meta["runtimeGeneration"] = generation
    meta["updatedAt"] = stamp
    write_json(meta_path, meta)

    wo_path = ROOT / f"runtime/work-orders/MISSION-005/{WORK_ORDER}.json"
    wo = json.loads(wo_path.read_text(encoding="utf-8"))
    if wo.get("activeSemaphoreId") not in (SEMAPHORE, None):
        raise RuntimeError("P5 landing Work Order semaphore binding changed")
    wo["activeSemaphoreId"] = None
    wo["status"] = work_status
    wo["updatedAt"] = stamp
    wo["lastActor"] = f"{WORKER}:{event_type}"
    write_json(wo_path, wo)

    sem_path = ROOT / f"runtime/semaphores/MISSION-005/{SEMAPHORE}.json"
    sem = json.loads(sem_path.read_text(encoding="utf-8"))
    sem["status"] = "RELEASED"
    sem["refreshedAt"] = stamp
    sem["expiresAt"] = stamp
    sem["runtimeGeneration"] = generation
    write_json(sem_path, sem)

    product_path = ROOT / "runtime/integration/product-prs/P5-001.json"
    product = json.loads(product_path.read_text(encoding="utf-8"))
    product["observedHead"] = main_sha or EXPECTED_HEAD
    product["observedAt"] = stamp
    product["status"] = product_status
    write_json(product_path, product)

    event_name = f"EVT-{generation:08d}-{event_type}.json"
    event = {
        "eventId": event_name.removesuffix(".json"),
        "eventType": event_type,
        "mission": "MISSION-005",
        "payload": {
            "detail": detail[:2000],
            "expectedProductHead": EXPECTED_HEAD,
            "expectedProductTree": EXPECTED_TREE,
            "mainCommit": main_sha,
            "mainTree": main_tree,
            "productPr": PR_NUMBER,
            "semaphoreId": SEMAPHORE,
        },
        "recordedAt": stamp,
        "runtimeGeneration": generation,
        "schemaVersion": 1,
        "workExecutionId": WORK_EXECUTION_ID,
        "workOrderId": WORK_ORDER,
    }
    write_json(ROOT / "runtime/events/2026-08-15" / event_name, event)

    run("git", "config", "user.name", "github-actions[bot]")
    run("git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com")
    run("git", "add", "-A")
    run("git", "diff", "--cached", "--check")
    if not run("git", "diff", "--cached", "--name-only", capture=True):
        raise RuntimeError("runtime finalization produced no durable change")
    run(
        "git",
        "commit",
        "-m",
        (
            "mission-runtime: close exact P5 main landing"
            if work_status == "LANDED"
            else "mission-runtime: record exact P5 landing blocker"
        ),
    )
    run("git", "push", "origin", f"HEAD:refs/heads/{RUNTIME_BRANCH}")


def main() -> int:
    main_sha: str | None = None
    main_tree: str | None = None
    try:
        main_sha, main_tree = settle_pr_and_main()
    except Exception as exc:
        finalize_runtime(
            work_status="BLOCKED",
            product_status="BLOCKED",
            event_type="LANDING_BLOCKED",
            detail=str(exc),
            main_sha=None,
            main_tree=None,
        )
        print(f"P5_LANDING_BLOCKED={exc}")
        return 2

    try:
        validate_main(main_sha)
    except Exception as exc:
        finalize_runtime(
            work_status="BLOCKED",
            product_status="LANDED_VALIDATION_BLOCKED",
            event_type="MAIN_VALIDATION_BLOCKED",
            detail=str(exc),
            main_sha=main_sha,
            main_tree=main_tree,
        )
        print(f"P5_MAIN_VALIDATION_BLOCKED={exc}")
        return 3

    finalize_runtime(
        work_status="LANDED",
        product_status="LANDED",
        event_type="PRODUCT_LANDED",
        detail="Exact P5-001 candidate merged and passed full actual-main validation.",
        main_sha=main_sha,
        main_tree=main_tree,
    )
    print(f"P5_LANDED_MAIN={main_sha}")
    print(f"P5_LANDED_TREE={main_tree}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
