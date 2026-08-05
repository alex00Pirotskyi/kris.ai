def parse_phase(project: Path, path: Path) -> tuple[Phase, list[Task]]:
    meta, body = parse_front_matter(path)
    relative = path.relative_to(project).as_posix()
    required = (
        "phase", "title", "execution_view_status", "primary_workers",
        "test_center_module", "source_reference", "live_authority",
    )
    missing = [key for key in required if key not in meta]
    if missing:
        raise ControlPlaneError(f"phase packet {relative} lacks {missing}")
    phase = str(meta["phase"])
    if PHASE_ID_RE.fullmatch(phase) is None:
        raise ControlPlaneError(f"invalid phase ID {phase!r}: {relative}")
    if not path.name.startswith(f"P{int(phase[1:]):02d}-"):
        raise ControlPlaneError(f"phase filename/front matter mismatch: {relative}")
    for key in ("source_reference", "live_authority"):
        target = (path.parent / str(meta[key])).resolve()
        try:
            target.relative_to(project)
        except ValueError as error:
            raise ControlPlaneError(f"phase reference escapes project: {relative}:{key}") from error
        if not target.is_file():
            raise ControlPlaneError(f"broken phase reference: {relative}:{key} -> {meta[key]}")
    lines = body.split("\n")
    try:
        section = lines.index("## Task backlog")
    except ValueError as error:
        raise ControlPlaneError(f"phase packet lacks exact Task backlog section: {relative}") from error
    rows = lines[section + 1 :]
    while rows and not rows[0].strip():
        rows.pop(0)
    if len(rows) < 2 or rows[0] != TASK_TABLE_HEADER or rows[1] != TASK_TABLE_SEPARATOR:
        raise ControlPlaneError(f"phase task table violates explicit contract: {relative}")
    tasks: list[Task] = []
    for line in rows[2:]:
        if line.startswith("## "):
            break
        if not line.strip():
            continue
        if not line.startswith("|") or not line.endswith("|"):
            raise ControlPlaneError(f"invalid task table row in {relative}: {line!r}")
        cells = [cell.strip() for cell in line[1:-1].split("|")]
        if len(cells) != 5:
            raise ControlPlaneError(f"task row must have five cells in {relative}: {line!r}")
        task_id = normalize_cell(cells[0])
        if TASK_ID_RE.fullmatch(task_id) is None:
            raise ControlPlaneError(f"invalid task ID {task_id!r}: {relative}")
        if task_id.split("-", 1)[0] != phase:
            raise ControlPlaneError(f"task/phase mismatch {task_id} vs {phase}: {relative}")
        title = normalize_cell(cells[1])
        required_output = normalize_cell(cells[3])
        done_when = normalize_cell(cells[4])
        if not title or not required_output or not done_when:
            raise ControlPlaneError(f"task lacks title/output/acceptance criteria: {task_id}")
        tasks.append(Task(task_id, phase, title, parse_dependencies(cells[2]), required_output, done_when, relative))
    if not tasks:
        raise ControlPlaneError(f"phase packet has no tasks: {relative}")
    return Phase(phase, relative, str(meta["title"]), tuple(task.task_id for task in tasks), file_sha256(path)), tasks


def parse_worker(project: Path, path: Path) -> Worker:
    meta, body = parse_front_matter(path)
    relative = path.relative_to(project).as_posix()
    required = ("worker", "role", "status", "branch", "active_task", "last_anchor", "reviewer")
    missing = [key for key in required if key not in meta]
    if missing:
        raise ControlPlaneError(f"worker packet {relative} lacks {missing}")
    worker = str(meta["worker"])
    if WORKER_ID_RE.fullmatch(worker) is None or path.name != f"WORKER_{worker}.md":
        raise ControlPlaneError(f"worker identity/filename mismatch: {relative}")
    branch = str(meta["branch"])
    if branch != "none" and (branch.startswith("/") or "\\" in branch or ".." in PurePosixPath(branch).parts):
        raise ControlPlaneError(f"unsafe worker branch: {relative}:{branch!r}")
    links = tuple(sorted(set(re.findall(r"\(\.\./phases/([^)]+\.md)\)", body))))
    if not links:
        raise ControlPlaneError(f"worker packet has no bounded phase links: {relative}")
    for name in links:
        target = (path.parent / "../phases" / name).resolve()
        try:
            target.relative_to(project)
        except ValueError as error:
            raise ControlPlaneError(f"worker link escapes project: {relative}:{name}") from error
        if not target.is_file():
            raise ControlPlaneError(f"broken worker phase link: {relative}:{name}")
    return Worker(worker, relative, str(meta["role"]), branch, str(meta["active_task"]), str(meta["reviewer"]), links, file_sha256(path))


def task_graph_hash(tasks: Iterable[Task]) -> str:
    rows = [
        {"id": task.task_id, "phase": task.phase, "dependsOn": list(task.dependencies), "packet": task.packet}
        for task in tasks
    ]
    rows.sort(key=lambda row: str(row["id"]))
    return sha256_bytes(json.dumps(rows, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def find_cycle(tasks: Mapping[str, Task]) -> list[str]:
    marks: dict[str, int] = {}
    stack: list[str] = []
    result: list[str] = []

    def visit(task_id: str) -> bool:
        marks[task_id] = 1
        stack.append(task_id)
        for dep in tasks[task_id].dependencies:
            if dep not in tasks:
                continue
            if marks.get(dep, 0) == 0 and visit(dep):
                return True
            if marks.get(dep) == 1:
                start = stack.index(dep)
                result.extend(stack[start:] + [dep])
                return True
        stack.pop()
        marks[task_id] = 2
        return False

    for task_id in sorted(tasks):
        if marks.get(task_id, 0) == 0 and visit(task_id):
            break
    return result


def glob_files(project: Path, pattern: str) -> list[Path]:
    if not safe_pattern(pattern):
        raise ControlPlaneError(f"unsafe glob pattern: {pattern!r}")
    return sorted((path for path in project.glob(pattern) if path.is_file()), key=lambda p: p.relative_to(project).as_posix())


def add_issue(state: ValidationState, code: str, message: str, *, path: str | None = None, subject: str | None = None, severity: str = "error") -> None:
    state.issues.append(Issue(severity, code, message, path, subject))


def require_dict(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ControlPlaneError(f"{label} must be an object")
    return value


def require_list(value: Any, label: str) -> list[Any]:
    if not isinstance(value, list):
        raise ControlPlaneError(f"{label} must be a list")
    return value


def validate_contract_shape(project: Path, contract: dict[str, Any]) -> None:
    if contract.get("schemaVersion") != "1.0.0" or contract.get("recordType") != "P24AdoptionReviewControl":
        raise ControlPlaneError("P24 control contract schemaVersion/recordType is invalid")
    if contract.get("task") != "P24-001":
        raise ControlPlaneError("control contract must remain scoped to P24-001")
    if contract.get("classification") not in ADOPTION_CLASSIFICATIONS:
        raise ControlPlaneError("invalid adoption classification")
    authority = require_dict(contract.get("authority"), "authority")
    if authority.get("human") != "docs/roadmap/MASTER.md" or authority.get("machine") != "docs/roadmap/roadmap.yaml":
        raise ControlPlaneError("authority decision changed: expected MASTER.md and roadmap.yaml")
    if authority.get("machineScopeMustRemain") != ["P0", "P1"]:
        raise ControlPlaneError("adoption review may not expand roadmap.yaml beyond P0/P1")
    resolve_safe(project, str(authority["human"]), must_exist=True)
    resolve_safe(project, str(authority["machine"]), must_exist=True)
    roles = require_list(authority.get("proposalAndReferenceRoles"), "authority.proposalAndReferenceRoles")
    for index, raw in enumerate(roles):
        item = require_dict(raw, f"proposalAndReferenceRoles[{index}]")
        path = str(item.get("path", ""))
        if item.get("role") not in {"PROPOSAL", "REFERENCE", "COMPATIBILITY_VIEW", "MIGRATION_EVIDENCE"}:
            raise ControlPlaneError(f"invalid role for {path}")
        resolve_safe(project, path, must_exist=True)
    inventory = require_dict(contract.get("inventory"), "inventory")
    for key in ("phasePacketGlob", "workerPacketGlob", "claimGlob"):
        if not isinstance(inventory.get(key), str) or not safe_pattern(str(inventory[key])):
            raise ControlPlaneError(f"inventory.{key} is invalid")
    for key, limit in (("expectedPhaseCount", MAX_PHASES), ("expectedTaskCount", MAX_TASKS), ("expectedWorkerCount", MAX_WORKERS)):
        value = inventory.get(key)
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0 or value > limit:
            raise ControlPlaneError(f"inventory.{key} is invalid")
    bindings = require_dict(contract.get("stateDomainBindings"), "stateDomainBindings")
    if set(bindings) != set(STATE_DOMAIN_VALUES):
        raise ControlPlaneError("stateDomainBindings must contain exactly five domains")
    for domain, values in STATE_DOMAIN_VALUES.items():
        binding = require_dict(bindings[domain], f"stateDomainBindings.{domain}")
        if binding.get("values") != list(values):
            raise ControlPlaneError(f"{domain} values do not match the scoped reference vocabulary")
        owner = str(binding.get("canonicalOwner", ""))
        if domain in {"TestExecutionResult", "CertificationStatus"} and "Worker B" not in owner:
            raise ControlPlaneError(f"{domain} must remain externally owned by Worker B")
    generated = require_list(contract.get("generatedPaths"), "generatedPaths")
    if len(generated) != 1:
        raise ControlPlaneError("P24-001 must declare exactly one bounded generated index")
    for value in generated:
        if not isinstance(value, str) or not safe_relative(value) or not value.startswith("docs/roadmap/anarchy/generated/"):
            raise ControlPlaneError(f"unsafe generated path: {value!r}")
    for value in require_list(contract.get("nonMutationScopes"), "nonMutationScopes"):
        if not isinstance(value, str) or not safe_relative(value):
            raise ControlPlaneError(f"unsafe non-mutation scope: {value!r}")
    manifest = require_dict(contract.get("sourceManifest"), "sourceManifest")
    if manifest.get("owner") != "tool/p1a_refresh_source_manifest.py":
        raise ControlPlaneError("canonical source manifest owner must be tool/p1a_refresh_source_manifest.py")
    resolve_safe(project, str(manifest["owner"]), must_exist=True)
    for key in ("directiveMatrix", "migrationLedger", "coordinationCheckpoint"):
        value = contract.get(key)
        if not isinstance(value, str) or not safe_relative(value):
            raise ControlPlaneError(f"{key} path is invalid")
    require_dict(contract.get("reviewRequirements"), "reviewRequirements")
    require_dict(contract.get("resume"), "resume")


def load_contract(project: Path) -> dict[str, Any]:
    contract = load_json(resolve_safe(project, CONTRACT_PATH, must_exist=True))
    validate_contract_shape(project, contract)
    return contract


def discover_phases(state: ValidationState) -> None:
    inventory = state.contract["inventory"]
    paths = glob_files(state.project, str(inventory["phasePacketGlob"]))
    expected_phases = int(inventory["expectedPhaseCount"])
    if len(paths) != expected_phases:
        add_issue(state, "phase_count", f"expected {expected_phases} phase packets, found {len(paths)}")
    phases: list[Phase] = []
    tasks: dict[str, Task] = {}
    for path in paths:
        relative = path.relative_to(state.project).as_posix()
        try:
            phase, phase_tasks = parse_phase(state.project, path)
        except ControlPlaneError as error:
            add_issue(state, "phase_packet_invalid", str(error), path=relative)
            continue
        if any(previous.phase == phase.phase for previous in phases):
            add_issue(state, "phase_duplicate", f"duplicate phase packet {phase.phase}", path=relative, subject=phase.phase)
        phases.append(phase)
        for task in phase_tasks:
            if task.task_id in tasks:
                add_issue(state, "task_id_duplicate", f"duplicate task {task.task_id}: {tasks[task.task_id].packet} and {task.packet}", path=relative, subject=task.task_id)
            else:
                tasks[task.task_id] = task
    expected_tasks = int(inventory["expectedTaskCount"])
    if len(tasks) != expected_tasks:
        add_issue(state, "task_count", f"expected {expected_tasks} unique task IDs, found {len(tasks)}")
    if len(tasks) > MAX_TASKS:
        add_issue(state, "task_resource_limit", f"task count exceeds {MAX_TASKS}")
    edges = sum(len(task.dependencies) for task in tasks.values())
    if edges > MAX_EDGES:
        add_issue(state, "dependency_resource_limit", f"dependency edge count exceeds {MAX_EDGES}")
    for task in sorted(tasks.values(), key=lambda item: item.task_id):
        for dependency in task.dependencies:
            if TASK_ID_RE.fullmatch(dependency) is None:
                add_issue(state, "dependency_unknown", f"unknown dependency token {dependency}", path=task.packet, subject=task.task_id)
            elif dependency not in tasks:
                add_issue(state, "dependency_missing", f"{task.task_id} depends on missing {dependency}", path=task.packet, subject=task.task_id)
            elif dependency == task.task_id:
                add_issue(state, "dependency_self", f"{task.task_id} depends on itself", path=task.packet, subject=task.task_id)
    cycle = find_cycle(tasks)
    if cycle:
        add_issue(state, "dependency_cycle", "dependency cycle: " + " -> ".join(cycle), subject=cycle[0])
    phases.sort(key=lambda phase: int(phase.phase[1:]))
    state.phases = phases
    state.tasks = tasks

