#!/usr/bin/env python3
from __future__ import annotations

RECONCILE_BLOCK = r'''
PRODUCT_DIVERGENCE_RE = re.compile(
    r"PRODUCT_RUNTIME_DIVERGENCE:PR(?P<pr>\d+):(?P<runtime>[0-9a-f]{40})!=LIVE:(?P<live>[0-9a-f]{40})"
)
GENERATED_DESCENDANT_MAX_COMMITS = 8
GENERATED_DESCENDANT_POLL_SECONDS = 2.0


class ProductDivergenceWatch(TransientFleetState):
    def __init__(
        self,
        message: str,
        *,
        product_pr: int,
        product_branch: str,
        runtime_ref: str,
        product_ref: str,
        safety_reason: str,
    ):
        signature = (
            f"product-divergence:{product_pr}:{runtime_ref}:{product_ref}:"
            f"{hashlib.sha256(safety_reason.encode('utf-8', errors='replace')).hexdigest()[:12]}"
        )
        super().__init__(message, retry_seconds=2, signature=signature)
        self.product_pr = int(product_pr)
        self.product_branch = str(product_branch)
        self.runtime_ref = str(runtime_ref)
        self.product_ref = str(product_ref)
        self.safety_reason = str(safety_reason)


def parse_product_divergence(text: str) -> tuple[int, str, str] | None:
    match = PRODUCT_DIVERGENCE_RE.search(str(text))
    if match is None:
        return None
    return int(match.group("pr")), match.group("runtime"), match.group("live")


def generated_descendant_path_allowed(task: str, path: str) -> bool:
    value = str(path).replace("\\", "/").lstrip("./")
    if value == "SOURCE_MANIFEST.sha256":
        return True
    prefix = f"release/evidence/{str(task).strip()}/"
    return bool(str(task).strip()) and value.startswith(prefix) and len(value) > len(prefix)


def _remote_head_only(cfg: Config, branch: str) -> str | None:
    result = git(
        cfg.anchor,
        "ls-remote",
        "--heads",
        "origin",
        f"refs/heads/{branch}",
        check=False,
        timeout=120,
    )
    if result.returncode != 0:
        return None
    rows = [line.split() for line in result.stdout.splitlines() if line.strip()]
    if len(rows) != 1 or len(rows[0]) < 2:
        return None
    sha = rows[0][0].strip()
    return sha if re.fullmatch(r"[0-9a-f]{40}", sha) else None


def _github_actions_commit(cfg: Config, commit: str) -> tuple[bool, str]:
    result = run(
        ["gh", "api", f"repos/{cfg.repo_full_name}/commits/{commit}"],
        check=False,
        timeout=120,
    )
    if result.returncode != 0:
        return False, f"cannot resolve GitHub commit identity for {commit}"
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError:
        return False, f"GitHub commit identity response is invalid JSON for {commit}"
    author = value.get("author") if isinstance(value, dict) else None
    committer = value.get("committer") if isinstance(value, dict) else None
    author_login = str(author.get("login") or "") if isinstance(author, dict) else ""
    committer_login = str(committer.get("login") or "") if isinstance(committer, dict) else ""
    if author_login != "github-actions[bot]" or committer_login != "github-actions[bot]":
        return False, (
            f"descendant {commit} is not GitHub-Actions-authored/committed: "
            f"author={author_login or 'none'} committer={committer_login or 'none'}"
        )
    return True, "github-actions[bot]"


def _live_product_semaphore(cfg: Config, product_pr: int) -> str | None:
    work_by_id = {
        str(row.get("workOrderId")): row
        for row in runtime_work_rows(cfg)
        if row.get("workOrderId")
    }
    now = time.time()
    for sem in runtime_semaphore_rows(cfg):
        if sem.get("status") != "ACTIVE":
            continue
        expiry = _parse_utc_epoch(sem.get("expiresAt"))
        if expiry is not None and expiry <= now:
            continue
        if sem.get("productPr") == product_pr:
            return str(sem.get("semaphoreId") or "active Product semaphore")
        work = work_by_id.get(str(sem.get("workOrderId") or ""))
        if isinstance(work, dict) and work.get("parentProductPr") == product_pr:
            return str(sem.get("semaphoreId") or "active Product Work Order semaphore")
    return None


def _generated_descendant_proof(
    cfg: Config,
    product: dict[str, Any],
    runtime_head: str,
    live_head: str,
) -> tuple[bool, str, list[str]]:
    if runtime_head == live_head:
        return False, "runtime and live Product heads are already equal", []
    ancestry = git(
        cfg.anchor,
        "merge-base",
        "--is-ancestor",
        runtime_head,
        live_head,
        check=False,
        timeout=120,
    )
    if ancestry.returncode != 0:
        return False, "live Product head is not a descendant of runtime observed head", []
    commits = [
        row.strip()
        for row in git(
            cfg.anchor,
            "rev-list",
            "--reverse",
            "--ancestry-path",
            f"{runtime_head}..{live_head}",
            timeout=120,
        ).stdout.splitlines()
        if row.strip()
    ]
    if not commits or len(commits) > GENERATED_DESCENDANT_MAX_COMMITS:
        return False, (
            f"generated descendant chain length must be 1..{GENERATED_DESCENDANT_MAX_COMMITS}; "
            f"actual={len(commits)}"
        ), commits
    task = str(product.get("task") or "")
    previous = runtime_head
    for commit in commits:
        parents = git(
            cfg.anchor,
            "show",
            "-s",
            "--format=%P",
            commit,
            timeout=120,
        ).stdout.strip().split()
        if parents != [previous]:
            return False, (
                f"generated descendant chain is not linear at {commit}: parents={parents} "
                f"expected={[previous]}"
            ), commits
        bot_ok, bot_reason = _github_actions_commit(cfg, commit)
        if not bot_ok:
            return False, bot_reason, commits
        paths = [
            row.strip()
            for row in git(
                cfg.anchor,
                "diff-tree",
                "--no-commit-id",
                "--name-only",
                "-r",
                commit,
                timeout=120,
            ).stdout.splitlines()
            if row.strip()
        ]
        if not paths:
            return False, f"generated descendant {commit} is a no-op commit", commits
        unexpected = [path for path in paths if not generated_descendant_path_allowed(task, path)]
        if unexpected:
            return False, (
                f"generated descendant {commit} touched non-generated Product paths: {unexpected}"
            ), commits
        previous = commit
    if previous != live_head:
        return False, f"descendant proof ended at {previous}, expected {live_head}", commits
    return True, "strict GitHub-Actions generated descendant proof passed", commits


def _write_product_reconciliation_event(
    cfg: Config,
    *,
    generation: int,
    product: dict[str, Any],
    old_head: str,
    new_head: str,
    new_tree: str,
    commits: list[str],
    rebound: list[str],
    recorded_at: str,
) -> None:
    event_type = "PRODUCT_RUNTIME_RECONCILED"
    event = {
        "schemaVersion": 1,
        "eventId": f"EVT-{generation:08d}-{event_type}",
        "eventType": event_type,
        "runtimeGeneration": generation,
        "recordedAt": recorded_at,
        "workExecutionId": make_work_execution_id(),
        "workOrderId": None,
        "mission": product.get("mission"),
        "payload": {
            "productPr": product.get("productPr"),
            "branch": product.get("branch"),
            "fromObservedHead": old_head,
            "toObservedHead": new_head,
            "toObservedTree": new_tree,
            "descendantCommits": commits,
            "reboundReadyWorkOrders": rebound,
            "policy": "github-actions-linear-generated-descendant-v1",
        },
    }
    path = (
        cfg.runtime
        / "runtime/events"
        / recorded_at[:10]
        / f"{event['eventId']}.json"
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(event, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def reconcile_safe_generated_product_descendant(
    cfg: Config,
    divergence_text: str,
) -> dict[str, Any]:
    parsed = parse_product_divergence(divergence_text)
    if parsed is None:
        return {"status": "NOT_PRODUCT_DIVERGENCE"}
    product_pr, audit_runtime_head, audit_live_head = parsed
    refresh_snapshots(cfg)
    product = product_pr_record(cfg, product_pr)
    branch = str(product.get("branch") or "")
    runtime_head = str(product.get("observedHead") or "")
    if not branch:
        return {"status": "UNSAFE", "reason": "canonical Product runtime record has no branch"}
    live_head = git(cfg.anchor, "rev-parse", f"origin/{branch}").stdout.strip()
    if runtime_head == live_head:
        return {"status": "ALREADY_RECONCILED", "branch": branch, "head": live_head}
    if runtime_head != audit_runtime_head or live_head != audit_live_head:
        return {
            "status": "RACE",
            "reason": (
                "Product/runtime heads moved since audit: "
                f"audit={audit_runtime_head}->{audit_live_head} now={runtime_head}->{live_head}"
            ),
            "branch": branch,
        }
    info = gh_pr_info(cfg, product_pr)
    if (
        info.get("state") != "OPEN"
        or str(info.get("headRefName") or "") != branch
        or str(info.get("headRefOid") or "") != live_head
    ):
        return {
            "status": "UNSAFE",
            "reason": "live canonical PR identity/head does not match runtime Product branch",
            "branch": branch,
        }
    semaphore = _live_product_semaphore(cfg, product_pr)
    if semaphore:
        return {
            "status": "UNSAFE",
            "reason": f"Product PR #{product_pr} still has live semaphore {semaphore}",
            "branch": branch,
        }
    safe, reason, commits = _generated_descendant_proof(
        cfg,
        product,
        runtime_head,
        live_head,
    )
    if not safe:
        return {"status": "UNSAFE", "reason": reason, "branch": branch, "commits": commits}

    # Structural validation is safe while the live Product observation is one
    # generated descendant behind; the live audit is intentionally deferred
    # until this exact CAS transaction publishes the observation update.
    control_python(
        cfg,
        "mission_orchestrator.py",
        "--project",
        str(cfg.runtime),
        "doctor",
        timeout=1800,
    )
    generation = runtime_generation(cfg)
    remote_runtime_before = git(
        cfg.anchor,
        "rev-parse",
        f"origin/{cfg.runtime_branch}",
    ).stdout.strip()
    product_path = (
        cfg.runtime
        / "runtime/integration/product-prs"
        / f"{str(product.get('task'))}.json"
    )
    current_product = read_json(product_path)
    if str(current_product.get("observedHead") or "") != runtime_head:
        return {"status": "RACE", "reason": "runtime Product record moved before CAS", "branch": branch}
    remote_live_before = _remote_head_only(cfg, branch)
    if remote_live_before != live_head:
        return {"status": "RACE", "reason": "canonical Product branch moved before CAS", "branch": branch}

    now = utc_iso()
    new_tree = exact_tree(cfg.anchor, live_head)
    current_product["observedHead"] = live_head
    current_product["observedAt"] = now
    product_path.write_text(
        json.dumps(current_product, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )

    rebound: list[str] = []
    for row in runtime_work_rows(cfg):
        if row.get("parentProductPr") != product_pr:
            continue
        if row.get("status") not in {"READY", "RESERVED"}:
            continue
        if row.get("baseCommit") == live_head and row.get("baseTree") == new_tree:
            continue
        path = row.get("_path")
        if not isinstance(path, pathlib.Path):
            continue
        item = {key: value for key, value in row.items() if key != "_path"}
        item["baseCommit"] = live_head
        item["baseTree"] = new_tree
        item["updatedAt"] = now
        path.write_text(
            json.dumps(item, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
            newline="\n",
        )
        rebound.append(str(item.get("workOrderId") or ""))

    meta_path = cfg.runtime / "runtime/meta.json"
    meta = read_json(meta_path)
    if int(meta.get("runtimeGeneration", -1)) != generation:
        git(cfg.runtime, "reset", "--hard", f"origin/{cfg.runtime_branch}", check=False)
        git(cfg.runtime, "clean", "-fd", check=False)
        return {"status": "RACE", "reason": "runtime generation moved before CAS", "branch": branch}
    next_generation = generation + 1
    meta["runtimeGeneration"] = next_generation
    meta["updatedAt"] = now
    meta_path.write_text(
        json.dumps(meta, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    _write_product_reconciliation_event(
        cfg,
        generation=next_generation,
        product=current_product,
        old_head=runtime_head,
        new_head=live_head,
        new_tree=new_tree,
        commits=commits,
        rebound=rebound,
        recorded_at=now,
    )

    # Final ref-only CAS guards immediately before publication. The runtime Git
    # push itself is non-force and remains the final cross-worker CAS.
    if _remote_head_only(cfg, cfg.runtime_branch) != remote_runtime_before:
        git(cfg.runtime, "reset", "--hard", f"origin/{cfg.runtime_branch}", check=False)
        git(cfg.runtime, "clean", "-fd", check=False)
        return {"status": "RACE", "reason": "runtime branch moved before publication", "branch": branch}
    if _remote_head_only(cfg, branch) != live_head:
        git(cfg.runtime, "reset", "--hard", f"origin/{cfg.runtime_branch}", check=False)
        git(cfg.runtime, "clean", "-fd", check=False)
        return {"status": "RACE", "reason": "Product branch moved before publication", "branch": branch}
    try:
        runtime_commit = commit_runtime_transition(
            cfg,
            f"mission-runtime: reconcile generated descendant for Product PR #{product_pr}",
        )
    except CASLost:
        return {"status": "RACE", "reason": "runtime publication CAS lost", "branch": branch}
    refresh_snapshots(cfg)
    return {
        "status": "RECONCILED",
        "productPr": product_pr,
        "branch": branch,
        "from": runtime_head,
        "to": live_head,
        "tree": new_tree,
        "commits": commits,
        "rebound": rebound,
        "runtimeCommit": runtime_commit,
        "runtimeGeneration": next_generation,
    }


def wait_for_product_divergence_change(
    cfg: Config,
    watch: ProductDivergenceWatch,
    *,
    jobs_completed: int,
) -> str:
    write_worker_status(
        cfg,
        "RED_ALERT_PRODUCT_DIVERGENCE",
        reason=str(watch),
        redAlert=True,
        productPr=watch.product_pr,
        productBranch=watch.product_branch,
        runtimeRef=watch.runtime_ref,
        productRef=watch.product_ref,
        safetyReason=watch.safety_reason,
        cheapPollSeconds=GENERATED_DESCENDANT_POLL_SECONDS,
        jobsCompleted=jobs_completed,
    )
    print(
        f"[red-alert-product-divergence] PR{watch.product_pr} "
        f"runtime={watch.runtime_ref} product={watch.product_ref}; "
        f"{watch.safety_reason}; polling refs only"
    )
    last_report = time.monotonic()
    while True:
        req = read_stop_request(cfg.root)
        if req:
            return "STOP_REQUESTED"
        runtime_now = _remote_head_only(cfg, cfg.runtime_branch)
        product_now = _remote_head_only(cfg, watch.product_branch)
        if runtime_now != watch.runtime_ref or product_now != watch.product_ref:
            print(
                f"[product-divergence-change] PR{watch.product_pr} authority changed "
                f"runtime={watch.runtime_ref}->{runtime_now} "
                f"product={watch.product_ref}->{product_now}; resuming full validation"
            )
            return "CHANGED"
        if time.monotonic() - last_report >= 30.0:
            print(
                f"[product-divergence-watch] PR{watch.product_pr} unchanged; "
                f"runtime={runtime_now} product={product_now}; still polling refs only"
            )
            last_report = time.monotonic()
        time.sleep(GENERATED_DESCENDANT_POLL_SECONDS)


_base_preflight_v53 = preflight


def resilient_preflight(cfg: Config, retries: int = 6) -> dict[str, Any]:
    last: Exception | None = None
    for attempt in range(1, max(1, int(retries)) + 1):
        try:
            return _base_preflight_v53(cfg)
        except Exception as exc:
            last = exc
            text = str(exc)
            if "EXPIRED_ACTIVE_SEMAPHORES:" in text:
                reap_expired_runtime(cfg)
                refresh_snapshots(cfg)
                continue
            parsed = parse_product_divergence(text)
            if parsed is not None:
                product_pr, runtime_head, live_head = parsed
                result = reconcile_safe_generated_product_descendant(cfg, text)
                status = str(result.get("status") or "")
                if status in {"RECONCILED", "ALREADY_RECONCILED", "RACE"}:
                    refresh_snapshots(cfg)
                    if attempt < max(1, int(retries)):
                        continue
                    raise TransientFleetState(
                        f"Product/runtime reconciliation is still moving: {result}",
                        retry_seconds=2,
                        signature=f"product-reconcile-race:{product_pr}",
                    )
                refresh_snapshots(cfg)
                product = product_pr_record(cfg, product_pr)
                branch = str(product.get("branch") or "")
                runtime_ref = _remote_head_only(cfg, cfg.runtime_branch) or ""
                product_ref = _remote_head_only(cfg, branch) or live_head
                reason = str(result.get("reason") or "automatic generated-descendant reconciliation refused")
                raise ProductDivergenceWatch(
                    text,
                    product_pr=product_pr,
                    product_branch=branch,
                    runtime_ref=runtime_ref,
                    product_ref=product_ref,
                    safety_reason=reason,
                )
            shared_block = control_plane_blocked(text)
            if shared_block is not None:
                refresh_snapshots(cfg)
                raise shared_block
            raise
    raise TransientFleetState(f"preflight remained transiently unhealthy: {last}")


REVIEW_ACTION_SCHEMA = {
    "oneOf": [
        {
            "type": "object",
            "additionalProperties": False,
            "required": ["action", "path", "why"],
            "properties": {
                "action": {"const": "read_file"},
                "path": {"type": "string", "minLength": 1},
                "start_line": {"type": "integer", "minimum": 1},
                "end_line": {"type": "integer", "minimum": 1},
                "why": {"type": "string", "minLength": 1},
            },
        },
        {
            "type": "object",
            "additionalProperties": False,
            "required": ["action", "path", "why"],
            "properties": {
                "action": {"const": "list_files"},
                "path": {"type": "string", "minLength": 1},
                "why": {"type": "string", "minLength": 1},
            },
        },
        {
            "type": "object",
            "additionalProperties": False,
            "required": ["action", "query", "path", "why"],
            "properties": {
                "action": {"const": "search"},
                "query": {"type": "string", "minLength": 1},
                "path": {"type": "string", "minLength": 1},
                "why": {"type": "string", "minLength": 1},
            },
        },
        {
            "type": "object",
            "additionalProperties": False,
            "required": ["action", "argv", "why"],
            "properties": {
                "action": {"const": "run"},
                "argv": {
                    "type": "array",
                    "minItems": 1,
                    "items": {"type": "string"},
                },
                "why": {"type": "string", "minLength": 1},
            },
        },
        {
            "type": "object",
            "additionalProperties": False,
            "required": ["action", "why"],
            "properties": {
                "action": {"const": "review_diff"},
                "why": {"type": "string", "minLength": 1},
            },
        },
        {
            "type": "object",
            "additionalProperties": False,
            "required": ["action", "verdict", "summary", "findings", "why"],
            "properties": {
                "action": {"const": "review_finish"},
                "verdict": {"type": "string", "enum": ["PASS", "FINDINGS"]},
                "summary": {"type": "string"},
                "findings": {"type": "array", "items": {"type": "string"}},
                "why": {"type": "string", "minLength": 1},
            },
        },
        {
            "type": "object",
            "additionalProperties": False,
            "required": ["action", "reason", "why"],
            "properties": {
                "action": {"const": "blocked"},
                "reason": {"type": "string", "minLength": 1},
                "why": {"type": "string", "minLength": 1},
            },
        },
    ]
}

REVIEW_FINAL_SCHEMA = {
    "oneOf": [
        {
            "type": "object",
            "additionalProperties": False,
            "required": ["action", "verdict", "summary", "findings"],
            "properties": {
                "action": {"const": "review_finish"},
                "verdict": {"type": "string", "enum": ["PASS", "FINDINGS"]},
                "summary": {"type": "string"},
                "findings": {"type": "array", "items": {"type": "string"}},
                "why": {"type": "string"},
            },
        },
        {
            "type": "object",
            "additionalProperties": False,
            "required": ["action", "reason"],
            "properties": {
                "action": {"const": "blocked"},
                "reason": {"type": "string", "minLength": 1},
                "why": {"type": "string"},
            },
        },
    ]
}


def chat_reply(
    cfg: Config,
    messages: list[dict[str, str]],
    *,
    max_tokens: int | None = None,
    response_schema: dict[str, Any] | None = None,
) -> ModelReply:
    url = cfg.model_base.rstrip("/") + "/chat/completions"
    payload = {
        "model": cfg.model,
        "messages": compact_messages(
            messages,
            max_chars=max(48_000, min(220_000, int((cfg.ctx_size or 32768) * 2.75))),
        ),
        "temperature": cfg.temperature,
        "max_tokens": int(max_tokens if max_tokens is not None else cfg.max_tokens),
        "stream": False,
    }
    formats: list[dict[str, Any] | None]
    if response_schema is not None:
        formats = [
            {
                "type": "json_schema",
                "json_schema": {
                    "name": "kris_single_action",
                    "strict": True,
                    "schema": response_schema,
                },
            },
            {"type": "json_object"},
            None,
        ]
    else:
        formats = [{"type": "json_object"}, None]
    headers = {"Content-Type": "application/json"}
    if cfg.api_key:
        headers["Authorization"] = f"Bearer {cfg.api_key}"

    def request_once(body: dict[str, Any]) -> dict[str, Any]:
        data = json.dumps(body).encode("utf-8")
        request = urllib.request.Request(url, data=data, headers=headers, method="POST")
        with urllib.request.urlopen(request, timeout=cfg.request_timeout) as response:
            value = json.loads(response.read().decode("utf-8"))
        if not isinstance(value, dict):
            raise WorkerError("Qwen endpoint returned non-object response")
        return value

    started = time.monotonic()
    body: dict[str, Any] | None = None
    last_http: urllib.error.HTTPError | None = None
    for response_format in formats:
        attempt = dict(payload)
        if response_format is not None:
            attempt["response_format"] = response_format
        try:
            body = request_once(attempt)
            break
        except urllib.error.HTTPError as exc:
            last_http = exc
            if exc.code not in {400, 404, 415, 422}:
                raise WorkerError(f"Qwen endpoint HTTP error {exc.code}") from exc
            continue
        except urllib.error.URLError as exc:
            raise WorkerError(f"Qwen endpoint request failed: {exc}") from exc
    if body is None:
        detail = f"HTTP {last_http.code}" if last_http is not None else "unknown response-format failure"
        raise WorkerError(f"Qwen endpoint rejected JSON schema/object/plain fallbacks: {detail}")
    duration_s = time.monotonic() - started
    choices = body.get("choices")
    if not isinstance(choices, list) or not choices:
        raise WorkerError(f"Qwen endpoint returned no choices: {body}")
    message = choices[0].get("message", {})
    content = message.get("content") or message.get("reasoning_content")
    if not isinstance(content, str) or not content.strip():
        raise WorkerError("Qwen endpoint returned empty content")
    usage = body.get("usage") if isinstance(body, dict) else None
    usage = usage if isinstance(usage, dict) else {}

    def _tok(name: str) -> int | None:
        value = usage.get(name)
        return int(value) if isinstance(value, (int, float)) else None

    return ModelReply(
        content=content,
        duration_s=duration_s,
        prompt_tokens=_tok("prompt_tokens"),
        completion_tokens=_tok("completion_tokens"),
        total_tokens=_tok("total_tokens"),
    )

'''
