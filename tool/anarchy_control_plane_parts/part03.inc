def discover_workers(state: ValidationState) -> None:
    inventory = state.contract["inventory"]
    paths = glob_files(state.project, str(inventory["workerPacketGlob"]))
    expected = int(inventory["expectedWorkerCount"])
    if len(paths) != expected:
        add_issue(state, "worker_count", f"expected {expected} worker packets, found {len(paths)}")
    workers: dict[str, Worker] = {}
    for path in paths:
        relative = path.relative_to(state.project).as_posix()
        try:
            worker = parse_worker(state.project, path)
        except ControlPlaneError as error:
            add_issue(state, "worker_packet_invalid", str(error), path=relative)
            continue
        if worker.worker in workers:
            add_issue(state, "worker_duplicate", f"duplicate worker identity {worker.worker}", path=relative, subject=worker.worker)
        else:
            workers[worker.worker] = worker
    expected_ids = {chr(ord("A") + index) for index in range(expected)}
    if set(workers) != expected_ids:
        add_issue(state, "worker_identity_set", f"expected A-J, found {sorted(workers)}")
    state.workers = workers


def pattern_root(pattern: str) -> str:
    indices = [index for token in ("*", "?") if (index := pattern.find(token)) >= 0]
    return pattern[: min(indices)].rstrip("/") if indices else pattern.rstrip("/")


def patterns_overlap(left: str, right: str) -> bool:
    a = pattern_root(left)
    b = pattern_root(right)
    return left == right or a == b or a.startswith(b + "/") or b.startswith(a + "/")


def parse_claim(state: ValidationState, path: Path) -> Claim | None:
    relative = path.relative_to(state.project).as_posix()
    try:
        data = load_json(path)
    except ControlPlaneError as error:
        add_issue(state, "claim_parse", str(error), path=relative)
        return None
    required = (
        "schemaVersion", "recordType", "task", "worker", "state", "branch", "base",
        "claimedPaths", "sharedContracts", "reviewerRoles", "nextAction", "continuity",
    )
    missing = [key for key in required if key not in data]
    if missing:
        add_issue(state, "claim_fields", f"claim lacks {missing}", path=relative)
        return None
    if data.get("schemaVersion") != "1.0.0" or data.get("recordType") != "AnarchyClaim":
        add_issue(state, "claim_schema", "claim schemaVersion/recordType is invalid", path=relative)
    task = str(data.get("task", ""))
    worker = str(data.get("worker", ""))
    status = str(data.get("state", ""))
    branch = str(data.get("branch", ""))
    if task not in state.tasks:
        add_issue(state, "claim_task_unknown", f"claim references unknown task {task}", path=relative, subject=task)
    if worker not in state.workers:
        add_issue(state, "claim_worker_unknown", f"claim references unknown worker {worker}", path=relative, subject=worker)
    if status not in CLAIM_STATUSES:
        add_issue(state, "claim_state_invalid", f"invalid claim state {status}", path=relative, subject=task)
    if not branch or branch.startswith("/") or "\\" in branch or ".." in PurePosixPath(branch).parts:
        add_issue(state, "claim_branch_unsafe", f"unsafe claim branch {branch!r}", path=relative, subject=task)
    base = data.get("base")
    if not isinstance(base, dict) or SHA1_RE.fullmatch(str(base.get("commit", ""))) is None or SHA1_RE.fullmatch(str(base.get("tree", ""))) is None:
        add_issue(state, "claim_base_binding", "claim base must include exact commit/tree", path=relative, subject=task)
    claimed_raw = data.get("claimedPaths")
    shared_raw = data.get("sharedContracts")
    if not isinstance(claimed_raw, list) or not claimed_raw:
        add_issue(state, "claim_paths_missing", "claim requires non-empty claimedPaths", path=relative, subject=task)
        claimed_raw = []
    if not isinstance(shared_raw, list):
        add_issue(state, "claim_shared_contracts", "sharedContracts must be a list", path=relative, subject=task)
        shared_raw = []
    claimed: list[str] = []
    shared: list[str] = []
    for key, raw_values, destination, code in (
        ("claimedPaths", claimed_raw, claimed, "claim_path_unsafe"),
        ("sharedContracts", shared_raw, shared, "shared_contract_path_unsafe"),
    ):
        for value in raw_values:
            if not isinstance(value, str) or value.startswith("/") or "\\" in value or ".." in PurePosixPath(value).parts:
                add_issue(state, code, f"unsafe {key} entry {value!r}", path=relative, subject=task)
            else:
                destination.append(value)
    reviewers = data.get("reviewerRoles")
    if not isinstance(reviewers, list) or not reviewers or any(not isinstance(value, str) or not value for value in reviewers):
        add_issue(state, "claim_reviewer_missing", "claim requires reviewerRoles", path=relative, subject=task)
    if not isinstance(data.get("nextAction"), str) or not str(data["nextAction"]).strip():
        add_issue(state, "claim_next_action", "claim requires durable nextAction", path=relative, subject=task)
    continuity = data.get("continuity")
    if not isinstance(continuity, dict):
        add_issue(state, "claim_continuity", "claim continuity must be an object", path=relative, subject=task)
        continuity = {}
    if status == "YIELDED":
        for key in ("yieldedAtUtc", "lastVerifiedHead", "lastVerifiedTree", "safeTakeover", "nextAction"):
            if not continuity.get(key):
                add_issue(state, "yield_continuity", f"yield lacks continuity.{key}", path=relative, subject=task)
    if status == "TAKEN_OVER":
        for key in ("previousClaim", "previousState", "previousHead", "previousTree", "yieldedAtUtc", "takeoverBaseCommit", "takeoverBaseTree"):
            if not continuity.get(key):
                add_issue(state, "unsafe_takeover", f"takeover lacks continuity.{key}", path=relative, subject=task)
        if continuity.get("previousState") != "YIELDED":
            add_issue(state, "unsafe_takeover", "takeover previousState must be YIELDED", path=relative, subject=task)
    for key in ("lastVerifiedHead", "lastVerifiedTree", "previousHead", "previousTree", "takeoverBaseCommit", "takeoverBaseTree"):
        value = continuity.get(key)
        if value is not None and SHA1_RE.fullmatch(str(value)) is None:
            add_issue(state, "continuity_binding_invalid", f"continuity.{key} is not a 40-hex binding", path=relative, subject=task)
    return Claim(relative, task, worker, status, branch, tuple(claimed), tuple(shared), data)


def discover_claims(state: ValidationState) -> None:
    claims = [claim for path in glob_files(state.project, str(state.contract["inventory"]["claimGlob"])) if (claim := parse_claim(state, path)) is not None]
    by_task: dict[str, Claim] = {}
    by_worker: dict[str, Claim] = {}
    locks: list[tuple[str, Claim]] = []
    for claim in claims:
        if not claim.active:
            continue
        if claim.task in by_task:
            add_issue(state, "active_claim_collision", f"active task collision: {by_task[claim.task].path} and {claim.path}", path=claim.path, subject=claim.task)
        else:
            by_task[claim.task] = claim
        if claim.worker in by_worker:
            add_issue(state, "worker_multiple_active_claims", f"worker {claim.worker} claims {by_worker[claim.worker].task} and {claim.task}", path=claim.path, subject=claim.worker)
        else:
            by_worker[claim.worker] = claim
        for lock in claim.shared_contracts:
            for previous_lock, previous in locks:
                if previous.worker != claim.worker and patterns_overlap(previous_lock, lock):
                    add_issue(state, "shared_contract_collision", f"shared lock collision: {previous.worker}:{previous_lock} vs {claim.worker}:{lock}", path=claim.path, subject=lock)
            locks.append((lock, claim))
    state.claims = sorted(claims, key=lambda claim: claim.path)


def validate_coordination_checkpoint(state: ValidationState) -> None:
    relative = str(state.contract["coordinationCheckpoint"])
    try:
        data = load_json(resolve_safe(state.project, relative, must_exist=True))
    except ControlPlaneError as error:
        add_issue(state, "coordination_parse", str(error), path=relative)
        return
    state.coordination = data
    if data.get("schemaVersion") != "1.0.0" or data.get("recordType") != "WorkerCoordinationCheckpoint":
        add_issue(state, "coordination_schema", "coordination checkpoint schemaVersion/recordType is invalid", path=relative)
    if data.get("classification") != "ADOPTION_REVIEW_COORDINATION_NOT_TASK_AUTHORITY":
        add_issue(state, "coordination_classification", "coordination checkpoint must remain a non-authoritative adoption-review view", path=relative)
    workers = data.get("workers")
    if not isinstance(workers, list):
        add_issue(state, "coordination_workers", "coordination workers must be a list", path=relative)
        return
    seen: set[str] = set()
    expected_fields = (
        "worker", "state", "lane", "taskOrHoldReason", "branch", "base", "ownedPaths",
        "forbiddenPaths", "sharedContracts", "reviewer", "dependency", "nextAction",
    )
    for index, raw in enumerate(workers):
        if not isinstance(raw, dict):
            add_issue(state, "coordination_worker_object", f"workers[{index}] must be an object", path=relative)
            continue
        missing = [key for key in expected_fields if key not in raw]
        if missing:
            add_issue(state, "coordination_worker_fields", f"workers[{index}] lacks {missing}", path=relative)
        worker = str(raw.get("worker", ""))
        if worker in seen:
            add_issue(state, "coordination_worker_duplicate", f"duplicate worker {worker}", path=relative, subject=worker)
        seen.add(worker)
        if worker not in state.workers:
            add_issue(state, "coordination_worker_unknown", f"unknown worker {worker}", path=relative, subject=worker)
        if raw.get("state") not in COORDINATION_STATUSES:
            add_issue(state, "coordination_state_invalid", f"invalid coordination state {raw.get('state')!r}", path=relative, subject=worker)
        branch = raw.get("branch")
        if not isinstance(branch, str) or not branch or branch.startswith("/") or "\\" in branch or ".." in PurePosixPath(branch).parts:
            add_issue(state, "coordination_branch_unsafe", f"unsafe branch {branch!r}", path=relative, subject=worker)
        base = raw.get("base")
        if not isinstance(base, dict):
            add_issue(state, "coordination_base", "coordination base must be an object", path=relative, subject=worker)
        else:
            for key in ("commit", "tree"):
                value = base.get(key)
                if value not in {"UNRESOLVED", "NOT_CREATED", "DELETED_AFTER_MERGE"} and SHA1_RE.fullmatch(str(value)) is None:
                    add_issue(state, "coordination_base_binding", f"base.{key} must be a 40-hex binding or explicit unresolved marker", path=relative, subject=worker)
        for key in ("ownedPaths", "forbiddenPaths", "sharedContracts"):
            values = raw.get(key)
            if not isinstance(values, list) or any(not isinstance(value, str) or not value for value in values):
                add_issue(state, "coordination_path_list", f"{key} must be a non-empty-string list", path=relative, subject=worker)
        for key in ("lane", "taskOrHoldReason", "reviewer", "dependency", "nextAction"):
            if not isinstance(raw.get(key), str) or not str(raw.get(key)).strip():
                add_issue(state, "coordination_text_field", f"{key} must be non-empty", path=relative, subject=worker)
    if seen != set(state.workers):
        add_issue(state, "coordination_worker_set", f"checkpoint workers must exactly match A-J; found {sorted(seen)}", path=relative)

