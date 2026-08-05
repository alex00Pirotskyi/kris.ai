def validate_task_records(state: ValidationState) -> None:
    records = state.contract.get("taskRecords")
    if not isinstance(records, list) or not records:
        add_issue(state, "task_records_missing", "control contract requires taskRecords")
        return
    seen: set[str] = set()
    for index, raw in enumerate(records):
        if not isinstance(raw, dict):
            add_issue(state, "task_record_object", f"taskRecords[{index}] must be an object")
            continue
        task_id = str(raw.get("task", ""))
        if task_id in seen:
            add_issue(state, "task_record_duplicate", f"duplicate task record {task_id}", subject=task_id)
        seen.add(task_id)
        if task_id not in state.tasks:
            add_issue(state, "task_record_unknown", f"task record references unknown {task_id}", subject=task_id)
        values = {
            "roadmapStatus": ROADMAP_TASK_STATUSES,
            "workerRuntimeStatus": WORKER_RUNTIME_STATUSES,
            "testExecutionResult": TEST_EXECUTION_RESULTS,
            "certificationStatus": CERTIFICATION_STATUSES,
            "capabilitySupportStatus": CAPABILITY_SUPPORT_STATUSES,
        }
        selected: dict[str, str] = {}
        for key, allowed in values.items():
            value = raw.get(key)
            selected[key] = str(value)
            if value not in allowed:
                add_issue(state, "state_domain_invalid", f"{task_id}.{key} has invalid value {value!r}", subject=task_id)
        # Explicitly reject values borrowed from a different domain even if the
        # textual token happens to look plausible to a human.
        domain_names = list(values)
        for key in domain_names:
            value = selected[key]
            for other_key, other_values in values.items():
                if key != other_key and value in other_values and value not in values[key]:
                    add_issue(state, "state_domain_mixing", f"{task_id}.{key} uses {value} from {other_key}", subject=task_id)
        evidence = raw.get("evidenceBindings")
        if not isinstance(evidence, list) or not evidence:
            add_issue(state, "evidence_binding_missing", f"{task_id} requires evidenceBindings", subject=task_id)
            evidence = []
        evidence_classes: set[str] = set()
        for evidence_index, binding in enumerate(evidence):
            if not isinstance(binding, dict):
                add_issue(state, "evidence_binding_object", f"{task_id}.evidenceBindings[{evidence_index}] must be an object", subject=task_id)
                continue
            path = binding.get("path")
            classification = binding.get("classification")
            if not isinstance(path, str) or not safe_relative(path):
                add_issue(state, "evidence_path_invalid", f"invalid evidence path {path!r}", subject=task_id)
                continue
            target = resolve_safe(state.project, path)
            if not target.is_file():
                add_issue(state, "evidence_path_missing", f"evidence path is missing: {path}", path=path, subject=task_id)
            digest = binding.get("sha256")
            if digest is not None:
                if SHA256_RE.fullmatch(str(digest)) is None:
                    add_issue(state, "evidence_hash_invalid", f"invalid evidence sha256 for {path}", path=path, subject=task_id)
                elif target.is_file() and file_sha256(target) != digest:
                    add_issue(state, "evidence_hash_mismatch", f"evidence hash mismatch for {path}", path=path, subject=task_id)
            if not isinstance(classification, str) or not classification:
                add_issue(state, "evidence_classification_missing", f"evidence classification missing for {path}", path=path, subject=task_id)
            else:
                evidence_classes.add(classification)
        completion_claim = raw.get("completionClaim")
        if not isinstance(completion_claim, bool):
            add_issue(state, "completion_claim_type", f"{task_id}.completionClaim must be boolean", subject=task_id)
            completion_claim = False
        roadmap = selected.get("roadmapStatus")
        test_result = selected.get("testExecutionResult")
        cert = selected.get("certificationStatus")
        support = selected.get("capabilitySupportStatus")
        source_only = "SOURCE_ONLY" in evidence_classes or support == "SOURCE_FOUNDATION"
        if completion_claim and roadmap != "DONE":
            add_issue(state, "unsupported_completion_claim", f"{task_id} claims completion while roadmapStatus={roadmap}", subject=task_id)
        if roadmap == "DONE" and (not completion_claim or cert != "PASS"):
            add_issue(state, "unsupported_completion_claim", f"{task_id} DONE requires explicit completionClaim and certification PASS", subject=task_id)
        if test_result == "PASS" and roadmap == "DONE" and cert != "PASS":
            add_issue(state, "test_pass_status_inflation", f"{task_id} test PASS cannot complete a task without certification PASS", subject=task_id)
        if source_only and support in {"BEHAVIOR_SUPPORTED", "PLATFORM_SUPPORTED", "RELEASE_SUPPORTED"}:
            add_issue(state, "source_status_inflation", f"{task_id} source-only evidence cannot claim {support}", subject=task_id)
        if task_id.startswith("P2-") and source_only and cert == "PASS":
            add_issue(state, "p2_source_behavioral_inflation", f"{task_id} source-only P2 evidence cannot be behaviorally certified", subject=task_id)
        if "HOSTED_CI" in evidence_classes and cert == "PASS" and support in {"BEHAVIOR_SUPPORTED", "PLATFORM_SUPPORTED", "RELEASE_SUPPORTED"}:
            add_issue(state, "hosted_ci_certification_inflation", f"{task_id} hosted CI cannot alone certify {support}", subject=task_id)
        review_binding = raw.get("reviewBinding")
        if review_binding is not None:
            if not isinstance(review_binding, dict):
                add_issue(state, "review_binding_object", f"{task_id}.reviewBinding must be an object", subject=task_id)
            else:
                for key in ("commit", "tree"):
                    if SHA1_RE.fullmatch(str(review_binding.get(key, ""))) is None:
                        add_issue(state, "review_binding_invalid", f"{task_id}.reviewBinding.{key} is invalid", subject=task_id)
                if review_binding.get("decision") not in REVIEW_DECISIONS:
                    add_issue(state, "review_binding_decision", f"{task_id}.reviewBinding decision is invalid", subject=task_id)


def validate_authority(state: ValidationState) -> None:
    authority = state.contract["authority"]
    machine_path = resolve_safe(state.project, str(authority["machine"]), must_exist=True)
    try:
        machine = load_json(machine_path)
    except ControlPlaneError as error:
        add_issue(state, "machine_authority_parse", str(error), path=str(authority["machine"]))
        return
    machine_authority = machine.get("authority")
    if not isinstance(machine_authority, dict) or machine_authority.get("human") != "docs/roadmap/MASTER.md" or machine_authority.get("machine") != "docs/roadmap/roadmap.yaml":
        add_issue(state, "machine_authority_binding", "roadmap.yaml authority binding changed", path=str(authority["machine"]))
    if not isinstance(machine_authority, dict) or machine_authority.get("scope") != ["P0", "P1"]:
        add_issue(state, "machine_authority_scope", "roadmap.yaml must remain scoped to P0/P1 during adoption review", path=str(authority["machine"]))
    human_path = resolve_safe(state.project, str(authority["human"]), must_exist=True)
    human_text = read_bounded(human_path).decode("utf-8", errors="strict")
    if "**Roadmap authority:** `HUMAN_CONSTITUTION`" not in human_text:
        add_issue(state, "human_authority_marker", "MASTER.md lacks the canonical HUMAN_CONSTITUTION marker", path=str(authority["human"]))
    authority_pattern = re.compile(r"\*\*Roadmap authority:\*\*\s*`([^`]+)`", re.I)
    for path in sorted((state.project / "docs/roadmap").rglob("*.md")):
        relative = path.relative_to(state.project).as_posix()
        if relative == authority["human"]:
            continue
        text = read_bounded(path).decode("utf-8", errors="replace")
        for match in authority_pattern.finditer(text):
            marker = match.group(1).strip().upper()
            if marker in {"HUMAN_CONSTITUTION", "NORMATIVE", "CANONICAL_HUMAN_AUTHORITY"}:
                add_issue(state, "competing_roadmap_authority", f"competing roadmap authority marker {marker}", path=relative)
    forbidden_promotions = (
        "ANARCHY proposal is normative",
        "PR #63 is normative",
        "v3.2 is normative",
    )
    for path in glob_files(state.project, "docs/roadmap/anarchy/migration/*"):
        if path.suffix.lower() not in {".md", ".json", ".yaml"}:
            continue
        text = read_bounded(path).decode("utf-8", errors="replace")
        for phrase in forbidden_promotions:
            if phrase.lower() in text.lower():
                add_issue(state, "proposal_promoted_to_authority", f"migration artifact contains forbidden authority promotion phrase: {phrase}", path=path.relative_to(state.project).as_posix())


def validate_directive_matrix(state: ValidationState) -> None:
    relative = str(state.contract["directiveMatrix"])
    try:
        data = load_json(resolve_safe(state.project, relative, must_exist=True))
    except ControlPlaneError as error:
        add_issue(state, "directive_matrix_parse", str(error), path=relative)
        return
    state.directive_matrix = data
    if data.get("schemaVersion") != "1.0.0" or data.get("classification") != "PROPOSED_RECONCILIATION_DECISIONS_NOT_TASK_STATUS_AUTHORITY":
        add_issue(state, "directive_matrix_schema", "directive matrix classification/schema is invalid", path=relative)
    directives = data.get("directives")
    if not isinstance(directives, list):
        add_issue(state, "directive_matrix_list", "directives must be a list", path=relative)
        return
    expected = int(state.contract["inventory"].get("expectedDirectiveCount", 0))
    if expected and len(directives) != expected:
        add_issue(state, "directive_count", f"expected {expected} directives, found {len(directives)}", path=relative)
    seen: set[str] = set()
    required = (
        "id", "source", "repositoryEquivalent", "decision", "rationale", "dependency",
        "affected", "migrationAction", "rollbackAction", "validation",
    )
    for index, raw in enumerate(directives):
        if not isinstance(raw, dict):
            add_issue(state, "directive_object", f"directives[{index}] must be an object", path=relative)
            continue
        missing = [key for key in required if key not in raw]
        if missing:
            add_issue(state, "directive_fields", f"directive[{index}] lacks {missing}", path=relative)
        directive_id = str(raw.get("id", ""))
        if DIRECTIVE_ID_RE.fullmatch(directive_id) is None:
            add_issue(state, "directive_id_invalid", f"invalid directive ID {directive_id!r}", path=relative)
        if directive_id in seen:
            add_issue(state, "directive_id_duplicate", f"duplicate directive ID {directive_id}", path=relative, subject=directive_id)
        seen.add(directive_id)
        if raw.get("decision") not in DIRECTIVE_DECISIONS:
            add_issue(state, "directive_decision_invalid", f"invalid directive decision {raw.get('decision')!r}", path=relative, subject=directive_id)
        for key in ("source", "repositoryEquivalent", "rationale", "dependency", "migrationAction", "rollbackAction", "validation"):
            if not isinstance(raw.get(key), str) or not str(raw.get(key)).strip():
                add_issue(state, "directive_text_missing", f"{directive_id}.{key} must be non-empty", path=relative, subject=directive_id)
        if not isinstance(raw.get("affected"), list):
            add_issue(state, "directive_affected_invalid", f"{directive_id}.affected must be a list", path=relative, subject=directive_id)
        if any(key in raw for key in ("roadmapStatus", "workerRuntimeStatus", "testExecutionResult", "certificationStatus", "capabilitySupportStatus")):
            add_issue(state, "directive_state_authority", f"{directive_id} may not assign task or certification state", path=relative, subject=directive_id)

