def build_repository(root: Path) -> None:
    initialize_git(root)
    write(root / "docs/roadmap/MASTER.md", "# Synthetic Master\n\n**Roadmap authority:** `HUMAN_CONSTITUTION`\n")
    write_json(
        root / "docs/roadmap/roadmap.yaml",
        {
            "schemaVersion": "1.0.0",
            "authority": {
                "human": "docs/roadmap/MASTER.md",
                "machine": "docs/roadmap/roadmap.yaml",
                "scope": ["P0", "P1"],
            },
        },
    )
    write(root / "docs/roadmap/STATUS.md", "# Generated compatibility status\n")
    write(root / "docs/roadmap/anarchy/ANARCHY_GOD_TIER_EXECUTION.md", "# Proposal\n")
    write(root / "docs/roadmap/anarchy/reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md", "# Hash-linked reference\n")
    for number in range(25):
        write(root / "docs/roadmap/anarchy/phases" / phase_name(number), make_phase(number))
    for index in range(10):
        letter = chr(ord("A") + index)
        write(root / f"docs/roadmap/anarchy/workers/WORKER_{letter}.md", make_worker(letter))
    write_json(root / "docs/roadmap/anarchy/migration/P24-001_CONTROL_PLANE.json", build_contract())
    write(root / "docs/roadmap/anarchy/migration/P24-001_RECONCILIATION_ADR.md", "# Proposed ADR\n\nNo authority promotion is performed.\n")
    write_json(root / "docs/roadmap/anarchy/migration/DIRECTIVE_MATRIX.yaml", valid_directives())
    write_json(root / "docs/roadmap/anarchy/migration/MIGRATION_LEDGER.yaml", valid_ledger())
    write_json(root / "docs/roadmap/anarchy/migration/BASELINE.json", {"classification": "SOURCE_ONLY"})
    write_json(root / "docs/roadmap/anarchy/coordination/P24-001_WORKER_CHECKPOINT.json", valid_checkpoint())
    write_json(root / "docs/roadmap/anarchy/claims/P24-001-WORKER-J.yaml", valid_claim())
    write(root / "release/evidence/P24-001/FOUNDATION.md", "# Source foundation\n")
    (root / "schemas").mkdir(parents=True, exist_ok=True)
    (root / "tool").mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / "schemas/anarchy_execution.schema.json", root / "schemas/anarchy_execution.schema.json")
    shutil.copy2(MODULE_PATH, root / "tool/anarchy_control_plane.py")
    shutil.copy2(Path(__file__), root / "tool/anarchy_control_plane_test.py")
    shutil.copytree(ROOT / "tool/anarchy_control_plane_parts", root / "tool/anarchy_control_plane_parts")
    shutil.copytree(ROOT / "tool/anarchy_control_plane_test_parts", root / "tool/anarchy_control_plane_test_parts")
    write(root / "tool/source_tree_policy.py", synthetic_source_policy())
    write(root / "tool/p1a_refresh_source_manifest.py", synthetic_manifest_generator())
    write(root / ".github/workflows/p24-adoption-review.yml", "name: synthetic-p24\n")
    shutil.copytree(FIXTURES, root / "test/anarchy_control_plane/fixtures")
    # Generate the bounded deterministic view before the canonical source manifest.
    result = acp.write_generated(root)
    assert result["changed"] is True
    run(sys.executable, "tool/p1a_refresh_source_manifest.py", ".", cwd=root)
    commit_all(root)


@contextmanager
def repository() -> Path:
    temporary = tempfile.TemporaryDirectory(prefix="p24-control-")
    try:
        root = Path(temporary.name)
        build_repository(root)
        yield root
    finally:
        temporary.cleanup()


def update_contract(root: Path, mutate) -> None:
    path = root / acp.CONTRACT_PATH
    value = read_json(path)
    mutate(value)
    write_json(path, value)


def update_claim(root: Path, mutate) -> None:
    path = root / "docs/roadmap/anarchy/claims/P24-001-WORKER-J.yaml"
    value = read_json(path)
    mutate(value)
    write_json(path, value)


def review_artifact(root: Path, *, decision: str = "PASS", stale: bool = True) -> dict[str, object]:
    commit, tree = acp.current_git_binding(root)
    assert commit and tree
    value: dict[str, object] = {
        "schemaVersion": "1.0.0",
        "recordType": "IndependentReview",
        "reviewerRole": "Worker B",
        "candidate": {"commit": "f" * 40 if stale else commit, "tree": "e" * 40 if stale else tree},
        "filesReviewed": ["tool/anarchy_control_plane.py"],
        "commandsExecuted": ["python -m unittest -v tool/anarchy_control_plane_test.py"],
        "findings": [],
        "decision": decision,
        "timestampUtc": "2026-08-05T12:00:00Z",
    }
    value["artifactHash"] = acp.canonical_review_hash(value)
    return value


def apply_operation(root: Path, operation: str) -> None:
    phase0 = root / "docs/roadmap/anarchy/phases" / phase_name(0)
    worker_a = root / "docs/roadmap/anarchy/workers/WORKER_A.md"
    if operation == "duplicate_task":
        text = phase0.read_text(encoding="utf-8")
        row = "| `P0-001` | Duplicate | `none` | Duplicate output. | Duplicate done. |\n"
        write(phase0, text.replace("\n## Test Center deliverables", "\n" + row + "\n## Test Center deliverables"))
    elif operation in {"unknown_dependency", "missing_dependency"}:
        replacement = "P25-001" if operation == "unknown_dependency" else "P0-999"
        text = phase0.read_text(encoding="utf-8")
        write(phase0, text.replace("| `P0-002` | Task P0-002 | `P0-001` |", f"| `P0-002` | Task P0-002 | `{replacement}` |"))
    elif operation == "dependency_cycle":
        text = phase0.read_text(encoding="utf-8")
        write(phase0, text.replace("| `P0-001` | Task P0-001 | `none` |", "| `P0-001` | Task P0-001 | `P0-002` |"))
    elif operation == "invalid_roadmap_status":
        update_contract(root, lambda data: data["taskRecords"][0].__setitem__("roadmapStatus", "FINISHED"))
    elif operation == "invalid_worker_runtime":
        update_contract(root, lambda data: data["taskRecords"][0].__setitem__("workerRuntimeStatus", "ACTIVE"))
    elif operation == "invalid_test_result":
        update_contract(root, lambda data: data["taskRecords"][0].__setitem__("testExecutionResult", "SUCCESS"))
    elif operation == "invalid_certification":
        update_contract(root, lambda data: data["taskRecords"][0].__setitem__("certificationStatus", "APPROVED"))
    elif operation == "invalid_capability":
        update_contract(root, lambda data: data["taskRecords"][0].__setitem__("capabilitySupportStatus", "SUPPORTED"))
    elif operation == "state_domain_mixing":
        update_contract(root, lambda data: data["taskRecords"][0].__setitem__("roadmapStatus", "PASS"))
    elif operation == "unsupported_completion":
        def mutate(data):
            data["taskRecords"][0]["roadmapStatus"] = "DONE"
            data["taskRecords"][0]["completionClaim"] = False
            data["taskRecords"][0]["certificationStatus"] = "PARTIAL"
        update_contract(root, mutate)
    elif operation == "p2_inflation":
        update_contract(root, lambda data: data["taskRecords"][1].__setitem__("capabilitySupportStatus", "BEHAVIOR_SUPPORTED"))
    elif operation == "hosted_ci_inflation":
        def mutate(data):
            data["taskRecords"][1]["capabilitySupportStatus"] = "BEHAVIOR_SUPPORTED"
            data["taskRecords"][1]["certificationStatus"] = "PASS"
        update_contract(root, mutate)
    elif operation == "competing_authority":
        write(root / "docs/roadmap/OTHER.md", "# Other\n\n**Roadmap authority:** `HUMAN_CONSTITUTION`\n")
    elif operation == "broken_phase_reference":
        text = phase0.read_text(encoding="utf-8")
        write(phase0, text.replace("source_reference: ../reference/MASTER_V3_2_AUTOMATED_DEVELOPMENT_VERIFICATION.md", "source_reference: ../reference/MISSING.md"))
    elif operation == "broken_worker_reference":
        text = worker_a.read_text(encoding="utf-8")
        write(worker_a, text.replace(phase_name(24), "P24-missing.md"))
    elif operation == "missing_evidence":
        update_contract(root, lambda data: data["taskRecords"][0].__setitem__("evidenceBindings", []))
    elif operation == "stale_review":
        write_json(root / "docs/roadmap/anarchy/reviews/P24-001-WORKER-B.json", review_artifact(root, stale=True))
    elif operation == "review_comment":
        write_json(root / "docs/roadmap/anarchy/reviews/P24-001-WORKER-B.json", review_artifact(root, decision="COMMENT", stale=False))
    elif operation == "generated_drift":
        path = root / "docs/roadmap/anarchy/generated/P24-001_CONTROL_PLANE_INDEX.json"
        path.write_bytes(path.read_bytes() + b" ")
    elif operation == "directive_invalid":
        path = root / "docs/roadmap/anarchy/migration/DIRECTIVE_MATRIX.yaml"
        value = read_json(path)
        value["directives"][0]["decision"] = "PROMOTE"
        write_json(path, value)
    elif operation == "ledger_invalid":
        path = root / "docs/roadmap/anarchy/migration/MIGRATION_LEDGER.yaml"
        value = read_json(path)
        value["events"].append({"sequence": 3, "kind": "CLAIM", "evidence": "docs/roadmap/anarchy/migration/BASELINE.json"})
        write_json(path, value)
    elif operation == "source_manifest_drift":
        path = root / "SOURCE_MANIFEST.sha256"
        path.write_bytes(path.read_bytes() + b"0" * 64 + b"  stale\n")
    elif operation == "claim_path_traversal":
        update_claim(root, lambda data: data["claimedPaths"].append("../outside"))
    elif operation == "crlf_phase":
        phase0.write_bytes(phase0.read_bytes().replace(b"\n", b"\r\n"))
    else:
        raise AssertionError(f"unknown fixture operation: {operation}")


def add_collision_claim(root: Path, variant: str) -> None:
    value = valid_claim()
    value["worker"] = "B"
    value["branch"] = "agent/b/collision"
    value["task"] = "P24-001" if variant == "same_task" else "P24-002"
    value["claimedPaths"] = ["synthetic/collision/**"]
    value["sharedContracts"] = ["docs/roadmap/anarchy/migration/**"] if variant == "shared_lock" else ["synthetic/other/**"]
    write_json(root / "docs/roadmap/anarchy/claims/COLLISION.yaml", value)


def issue_codes(state: acp.ValidationState) -> set[str]:
    return {issue.code for issue in state.issues}

