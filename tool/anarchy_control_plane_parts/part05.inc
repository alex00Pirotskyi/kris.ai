def validate_migration_ledger(state: ValidationState) -> None:
    relative = str(state.contract["migrationLedger"])
    try:
        data = load_json(resolve_safe(state.project, relative, must_exist=True))
    except ControlPlaneError as error:
        add_issue(state, "migration_ledger_parse", str(error), path=relative)
        return
    state.migration_ledger = data
    if data.get("schemaVersion") != "1.0.0" or data.get("classification") != "APPEND_ONLY_MIGRATION_OBSERVATION_NOT_TASK_STATUS_AUTHORITY":
        add_issue(state, "migration_ledger_schema", "migration ledger schema/classification is invalid", path=relative)
    if data.get("task") != "P24-001" or data.get("worker") != "J":
        add_issue(state, "migration_ledger_scope", "migration ledger must remain scoped to Worker J/P24-001", path=relative)
    events = data.get("events")
    if not isinstance(events, list) or not events:
        add_issue(state, "migration_events", "migration ledger requires events", path=relative)
        return
    previous = 0
    allowed_kinds = {
        "LIVE_BASELINE", "CLAIM", "AUTHORITY_DECISION_PROPOSED", "STALE_CLAIM_CORRECTED",
        "VALIDATOR_FOUNDATION", "CANDIDATE_PUSHED", "STACKED_PR_OPENED", "CI_OBSERVED",
        "SOURCE_MANIFEST_REFRESHED", "REVIEW_OBSERVED", "COORDINATION_CHECKPOINT", "CLEAN_ROOM_RESUME",
    }
    for index, raw in enumerate(events):
        if not isinstance(raw, dict):
            add_issue(state, "migration_event_object", f"events[{index}] must be an object", path=relative)
            continue
        sequence = raw.get("sequence")
        if not isinstance(sequence, int) or isinstance(sequence, bool) or sequence != previous + 1:
            add_issue(state, "migration_sequence", f"events[{index}] sequence must be {previous + 1}", path=relative)
        else:
            previous = sequence
        if raw.get("kind") not in allowed_kinds:
            add_issue(state, "migration_event_kind", f"invalid migration event kind {raw.get('kind')!r}", path=relative)
        evidence = raw.get("evidence")
        evidence_paths = evidence if isinstance(evidence, list) else [evidence] if isinstance(evidence, str) else []
        for evidence_path in evidence_paths:
            if not safe_relative(evidence_path) or not resolve_safe(state.project, evidence_path).is_file():
                add_issue(state, "migration_event_evidence", f"event evidence missing/unsafe: {evidence_path!r}", path=relative)
        for forbidden in ("roadmapStatus", "certificationStatus", "capabilitySupportStatus"):
            if forbidden in raw:
                add_issue(state, "migration_ledger_state_authority", f"migration event may not assign {forbidden}", path=relative)
    pending = data.get("pending")
    if not isinstance(pending, list) or any(not isinstance(item, str) or not item for item in pending):
        add_issue(state, "migration_pending", "migration ledger pending must be a string list", path=relative)


def current_git_binding(project: Path) -> tuple[str | None, str | None]:
    try:
        commit = subprocess.check_output(["git", "-C", str(project), "rev-parse", "HEAD"], stderr=subprocess.DEVNULL, text=True).strip()
        tree = subprocess.check_output(["git", "-C", str(project), "rev-parse", "HEAD^{tree}"], stderr=subprocess.DEVNULL, text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return None, None
    if SHA1_RE.fullmatch(commit) is None or SHA1_RE.fullmatch(tree) is None:
        return None, None
    return commit, tree


def canonical_review_hash(data: Mapping[str, Any]) -> str:
    value = dict(data)
    value.pop("artifactHash", None)
    return sha256_bytes(canonical_bytes(value))


def validate_reviews(state: ValidationState) -> None:
    requirements = state.contract["reviewRequirements"]
    reviewers = requirements.get("reviewers")
    if not isinstance(reviewers, list) or {str(item.get("role")) for item in reviewers if isinstance(item, dict)} != {"Worker B", "Worker I"}:
        add_issue(state, "review_requirements", "review requirements must contain exactly Worker B and Worker I")
        return
    commit, tree = current_git_binding(state.project)
    for raw in reviewers:
        assert isinstance(raw, dict)
        role = str(raw.get("role"))
        relative = str(raw.get("artifact", ""))
        if not safe_relative(relative):
            add_issue(state, "review_artifact_path", f"unsafe review artifact path for {role}: {relative!r}")
            continue
        path = resolve_safe(state.project, relative)
        if not path.is_file():
            blocker = f"{role} exact-head review artifact missing"
            if blocker not in state.blockers:
                state.blockers.append(blocker)
            continue
        try:
            data = load_json(path)
        except ControlPlaneError as error:
            add_issue(state, "review_artifact_parse", str(error), path=relative, subject=role)
            continue
        if data.get("schemaVersion") != "1.0.0" or data.get("recordType") != "IndependentReview" or data.get("reviewerRole") != role:
            add_issue(state, "review_artifact_schema", f"invalid review artifact for {role}", path=relative, subject=role)
        candidate = data.get("candidate")
        if not isinstance(candidate, dict) or SHA1_RE.fullmatch(str(candidate.get("commit", ""))) is None or SHA1_RE.fullmatch(str(candidate.get("tree", ""))) is None:
            add_issue(state, "review_candidate_binding", f"{role} review lacks exact commit/tree", path=relative, subject=role)
        elif commit and tree and (candidate.get("commit") != commit or candidate.get("tree") != tree):
            add_issue(state, "review_stale_binding", f"{role} review targets {candidate.get('commit')}/{candidate.get('tree')}, current is {commit}/{tree}", path=relative, subject=role)
        if data.get("decision") not in REVIEW_DECISIONS:
            add_issue(state, "review_decision_invalid", f"invalid {role} decision", path=relative, subject=role)
        if not isinstance(data.get("filesReviewed"), list) or not data.get("filesReviewed"):
            add_issue(state, "review_files_missing", f"{role} review lacks filesReviewed", path=relative, subject=role)
        if not isinstance(data.get("commandsExecuted"), list):
            add_issue(state, "review_commands_invalid", f"{role} commandsExecuted must be a list", path=relative, subject=role)
        findings = data.get("findings")
        if not isinstance(findings, list):
            add_issue(state, "review_findings_invalid", f"{role} findings must be a list", path=relative, subject=role)
            findings = []
        blocking = [finding for finding in findings if isinstance(finding, dict) and str(finding.get("severity", "")).lower() in {"critical", "high"} and finding.get("disposition") not in {"RESOLVED", "ACCEPTED_AS_NON_BLOCKING"}]
        if blocking:
            add_issue(state, "review_blocking_findings", f"{role} has unresolved critical/high findings", path=relative, subject=role)
        if data.get("artifactHash") != canonical_review_hash(data):
            add_issue(state, "review_artifact_hash", f"{role} review artifact hash is invalid", path=relative, subject=role)
        if data.get("decision") != "PASS":
            blocker = f"{role} review decision is {data.get('decision')}"
            if blocker not in state.blockers:
                state.blockers.append(blocker)


def load_source_policy(project: Path) -> Any:
    policy_path = resolve_safe(project, "tool/source_tree_policy.py", must_exist=True)
    spec = importlib.util.spec_from_file_location("p24_source_tree_policy", policy_path)
    if spec is None or spec.loader is None:
        raise ControlPlaneError("cannot load source tree policy")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def tracked_source_paths(project: Path) -> list[str]:
    try:
        raw = subprocess.check_output(
            ["git", "-C", str(project), "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
            stderr=subprocess.PIPE,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise ControlPlaneError(f"git source inventory failed: {error}") from error
    values = {
        item.decode("utf-8", errors="surrogateescape").replace("\\", "/")
        for item in raw.split(b"\0")
        if item
    }
    return sorted(values)


def expected_source_manifest_bytes(project: Path) -> bytes:
    policy = load_source_policy(project)
    lines: list[str] = []
    for relative in tracked_source_paths(project):
        if relative == SOURCE_MANIFEST_PATH or policy.is_generated_path(relative):
            continue
        if not safe_relative(relative):
            raise ControlPlaneError(f"git inventory contains unsafe path: {relative!r}")
        path = resolve_safe(project, relative)
        if path.is_file():
            lines.append(f"{file_sha256(path)}  {relative}")
    return ("\n".join(lines) + "\n").encode("utf-8")


def validate_source_manifest(state: ValidationState) -> None:
    relative = SOURCE_MANIFEST_PATH
    path = resolve_safe(state.project, relative)
    if not path.is_file():
        add_issue(state, "source_manifest_missing", "SOURCE_MANIFEST.sha256 is missing", path=relative)
        state.source_manifest_status = "MISSING"
        return
    try:
        expected = expected_source_manifest_bytes(state.project)
    except ControlPlaneError as error:
        add_issue(state, "source_manifest_check", str(error), path=relative)
        state.source_manifest_status = "ERROR"
        return
    actual = read_bounded(path, 64 * 1024 * 1024)
    if actual != expected:
        add_issue(state, "source_manifest_drift", "SOURCE_MANIFEST.sha256 differs from canonical p1a_refresh_source_manifest.py output", path=relative)
        state.source_manifest_status = "DRIFT"
    else:
        state.source_manifest_status = "CURRENT"


def generated_index_data(state: ValidationState) -> dict[str, Any]:
    directives = state.directive_matrix.get("directives", []) if isinstance(state.directive_matrix, dict) else []
    events = state.migration_ledger.get("events", []) if isinstance(state.migration_ledger, dict) else []
    workers = state.coordination.get("workers", []) if isinstance(state.coordination, dict) else []
    return {
        "schemaVersion": "1.0.0",
        "recordType": "P24AdoptionReviewGeneratedIndex",
        "classification": "ADOPTION_REVIEW_GENERATED_NAVIGATION_NOT_AUTHORITY",
        "generated": {
            "owner": "tool/anarchy_control_plane.py",
            "generatorVersion": TOOL_VERSION,
            "doNotEdit": True,
            "sourceContract": CONTRACT_PATH,
        },
        "authority": {
            "human": state.contract["authority"]["human"],
            "machine": state.contract["authority"]["machine"],
            "machineScope": state.contract["authority"]["machineScopeMustRemain"],
        },
        "inventory": {
            "phaseCount": len(state.phases),
            "taskCount": len(state.tasks),
            "workerCount": len(state.workers),
            "activeClaimCount": len([claim for claim in state.claims if claim.active]),
            "directiveCount": len(directives),
            "migrationEventCount": len(events),
            "coordinationWorkerCount": len(workers),
            "taskGraphSha256": task_graph_hash(state.tasks.values()),
        },
        "phases": [
            {"phase": phase.phase, "packet": phase.path, "taskCount": len(phase.task_ids), "sha256": phase.sha256}
            for phase in state.phases
        ],
        "workers": [
            {"worker": worker.worker, "packet": worker.path, "branch": worker.branch, "sha256": worker.sha256}
            for worker in sorted(state.workers.values(), key=lambda value: value.worker)
        ],
        "claims": [
            {"task": claim.task, "worker": claim.worker, "state": claim.state, "branch": claim.branch, "path": claim.path}
            for claim in state.claims
        ],
        "adoption": {
            "classification": state.contract["classification"],
            "authorityPromotionPerformed": False,
            "reviewersRequired": ["Worker B", "Worker I"],
        },
    }


def validate_generated(state: ValidationState) -> None:
    generated = str(state.contract["generatedPaths"][0])
    path = resolve_safe(state.project, generated)
    expected = canonical_bytes(generated_index_data(state))
    if not path.is_file():
        add_issue(state, "generated_view_missing", f"generated view is missing: {generated}", path=generated)
        state.generated_status = "MISSING"
        return
    actual = read_bounded(path, 16 * 1024 * 1024)
    if actual != expected:
        add_issue(state, "generated_view_drift", f"generated view drift: {generated}", path=generated)
        state.generated_status = "DRIFT"
    else:
        state.generated_status = "CURRENT"

