def atomic_replace(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent, delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        temporary = None
        try:
            directory_fd = os.open(path.parent, os.O_RDONLY)
        except (AttributeError, OSError):
            directory_fd = None
        if directory_fd is not None:
            try:
                os.fsync(directory_fd)
            except OSError:
                pass
            finally:
                os.close(directory_fd)
    finally:
        if temporary is not None:
            try:
                temporary.unlink()
            except FileNotFoundError:
                pass


def write_generated(project: Path) -> dict[str, Any]:
    state = validate_project(project, check_generated=False, check_source_manifest=False, enforce_non_mutation=False)
    if state.errors:
        detail = "; ".join(
            f"{issue.code}: {issue.message}" for issue in state.errors[:5]
        )
        raise ControlPlaneError(
            "refusing write because source control-plane validation failed"
            + (f": {detail}" if detail else "")
        )
    path = resolve_safe(project, str(state.contract["generatedPaths"][0]))
    content = canonical_bytes(generated_index_data(state))
    before = path.read_bytes() if path.exists() else None
    if before != content:
        atomic_replace(path, content)
    return {
        "path": repository_relative(project, path, must_exist=True),
        "changed": before != content,
        "sha256": sha256_bytes(content),
    }


def iter_scope_files(project: Path, relative: str) -> Iterable[Path]:
    path = resolve_safe(project, relative)
    if path.is_file():
        yield path
    elif path.is_dir():
        candidates = list(path.rglob("*"))
        candidates.sort(
            key=lambda item: repository_relative(
                project,
                item,
                must_exist=item.exists(),
            )
        )
        for candidate in candidates:
            if candidate.is_file():
                # Revalidate after sorting so a file replaced by an escaping
                # symlink/junction between enumeration and consumption fails
                # closed instead of entering the snapshot.
                repository_relative(project, candidate, must_exist=True)
                yield candidate


def snapshot_scopes(project: Path, scopes: Sequence[str]) -> dict[str, tuple[str, int, int]]:
    result: dict[str, tuple[str, int, int]] = {}
    for relative in scopes:
        for path in iter_scope_files(project, relative):
            rel = repository_relative(project, path, must_exist=True)
            stat = path.stat()
            result[rel] = (file_sha256(path), stat.st_size, stat.st_mtime_ns)
    return result


def validate_project(
    project: Path,
    *,
    check_generated: bool = True,
    check_source_manifest: bool = True,
    enforce_non_mutation: bool = False,
) -> ValidationState:
    root = project.resolve()
    contract = load_contract(root)
    scopes = [str(item) for item in contract.get("nonMutationScopes", [])]
    before = snapshot_scopes(root, scopes) if enforce_non_mutation else None
    state = ValidationState(root, contract, [], {}, {}, [], [], [])
    discover_phases(state)
    discover_workers(state)
    discover_claims(state)
    validate_coordination_checkpoint(state)
    validate_task_records(state)
    validate_authority(state)
    validate_directive_matrix(state)
    validate_migration_ledger(state)
    validate_reviews(state)
    if check_generated:
        validate_generated(state)
    if check_source_manifest:
        validate_source_manifest(state)
    if enforce_non_mutation:
        after = snapshot_scopes(root, scopes)
        if before != after:
            changed = sorted(set(before or {}) ^ set(after))
            common = set(before or {}) & set(after)
            changed.extend(sorted(path for path in common if (before or {})[path] != after[path]))
            add_issue(state, "check_mode_mutation", "check mode mutated declared scope: " + ", ".join(dict.fromkeys(changed)))
    state.issues.sort(key=lambda issue: (issue.severity, issue.code, issue.path or "", issue.subject or "", issue.message))
    state.blockers = sorted(set(state.blockers))
    return state


def validation_report(state: ValidationState, *, repository_sha: str | None = None, repository_tree: str | None = None) -> dict[str, Any]:
    git_commit, git_tree = current_git_binding(state.project)
    commit = repository_sha or git_commit
    tree = repository_tree or git_tree
    return {
        "schemaVersion": "1.0.0",
        "recordType": "P24AdoptionReviewValidationReport",
        "toolVersion": TOOL_VERSION,
        "classification": "ADOPTION_READY" if state.passed and not state.blockers and state.contract.get("classification") == "ADOPTION_READY" else "ADOPTION_REVIEW",
        "repository": {"commit": commit or "UNRESOLVED", "tree": tree or "UNRESOLVED"},
        "authority": {
            "human": state.contract["authority"]["human"],
            "machine": state.contract["authority"]["machine"],
            "machineScope": state.contract["authority"]["machineScopeMustRemain"],
            "proposalAndReferenceFiles": state.contract["authority"]["proposalAndReferenceRoles"],
        },
        "counts": {
            "phases": len(state.phases),
            "tasks": len(state.tasks),
            "workers": len(state.workers),
            "activeClaims": len([claim for claim in state.claims if claim.active]),
            "claimCollisions": len([issue for issue in state.issues if issue.code in {"active_claim_collision", "shared_contract_collision"}]),
        },
        "dependencyGraph": {"status": "PASS" if not any(issue.code.startswith("dependency_") for issue in state.errors) else "FAIL", "sha256": task_graph_hash(state.tasks.values()) if state.tasks else None},
        "stateDomains": {"status": "PASS" if not any(issue.code.startswith("state_domain") or "inflation" in issue.code for issue in state.errors) else "FAIL"},
        "generatedView": state.generated_status,
        "directiveMatrix": "PASS" if state.directive_matrix is not None and not any(issue.code.startswith("directive_") for issue in state.errors) else "FAIL",
        "migrationLedger": "PASS" if state.migration_ledger is not None and not any(issue.code.startswith("migration_") for issue in state.errors) else "FAIL",
        "sourceManifest": {"status": state.source_manifest_status, "owner": state.contract["sourceManifest"]["owner"]},
        "tests": {
            "validator": "PASS" if state.passed else "FAIL",
            "independentReviews": "BLOCKED" if any("review" in blocker.lower() for blocker in state.blockers) else "PASS",
        },
        "issues": [issue.as_dict() for issue in state.issues],
        "adoptionBlockers": state.blockers,
        "authorityPromotionPerformed": False,
        "passed": state.passed,
    }


def write_report(path: Path, report: Mapping[str, Any]) -> None:
    path = path.resolve()
    atomic_replace(path, canonical_bytes(report))


def resume_worker(project: Path, worker_id: str) -> dict[str, Any]:
    state = validate_project(project, check_generated=False, check_source_manifest=False, enforce_non_mutation=True)
    if worker_id not in state.workers:
        raise ControlPlaneError(f"unknown worker {worker_id}")
    worker = state.workers[worker_id]
    claims = [claim for claim in state.claims if claim.worker == worker_id and claim.active]
    claim = claims[0] if len(claims) == 1 else None
    resume = state.contract["resume"]
    base = claim.data.get("base") if claim else None
    commit, tree = current_git_binding(project)
    return {
        "worker": worker_id,
        "role": worker.role,
        "activeTask": claim.task if claim else worker.active_task,
        "branch": claim.branch if claim else worker.branch,
        "base": base or "UNRESOLVED",
        "head": commit or "UNRESOLVED",
        "tree": tree or "UNRESOLVED",
        "claim": claim.path if claim else "NO_ACTIVE_CLAIM",
        "ownedPaths": list(claim.claimed_paths) if claim else [],
        "sharedContracts": list(claim.shared_contracts) if claim else [],
        "reviewers": list(claim.data.get("reviewerRoles", [])) if claim else [],
        "tests": list(resume.get("tests", [])),
        "ciWorkflow": resume.get("ciWorkflow"),
        "reviewArtifacts": state.contract["reviewRequirements"]["reviewers"],
        "blockers": state.blockers,
        "nextAction": claim.data.get("nextAction") if claim else resume.get("fallbackNextAction"),
        "safeTakeover": claim.data.get("continuity", {}).get("safeTakeover") if claim else "resolve remote claim before acting",
        "authority": {"human": state.contract["authority"]["human"], "machine": state.contract["authority"]["machine"]},
        "validationPassed": state.passed,
    }


def print_summary(report: Mapping[str, Any]) -> None:
    counts = report.get("counts", {})
    print(
        f"P24-001 control plane: {'PASS' if report.get('passed') else 'FAIL'} "
        f"({counts.get('phases', 0)} phases, {counts.get('tasks', 0)} tasks, "
        f"{counts.get('workers', 0)} workers; classification={report.get('classification')})"
    )
    for issue in report.get("issues", []):
        print(f"{str(issue.get('severity', 'error')).upper()} {issue.get('code')}: {issue.get('message')}")
    for blocker in report.get("adoptionBlockers", []):
        print(f"BLOCKER: {blocker}")


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", default=".", help="repository root")
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--check", action="store_true", help="strict non-mutating validation")
    modes.add_argument("--write", action="store_true", help="atomically refresh declared generated view")
    modes.add_argument("--report", metavar="PATH", help="write an explicit validation report")
    modes.add_argument("--resume-worker", metavar="ID", help="print clean-room worker resume context")
    parser.add_argument("--repository-sha", default=None, help="explicit report binding")
    parser.add_argument("--repository-tree", default=None, help="explicit report binding")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    project = Path(args.project).resolve()
    try:
        if args.write:
            result = write_generated(project)
            print(json.dumps(result, sort_keys=True))
            state = validate_project(project, enforce_non_mutation=False)
            report = validation_report(state, repository_sha=args.repository_sha, repository_tree=args.repository_tree)
            print_summary(report)
            return 0 if state.passed else 1
        if args.resume_worker:
            if WORKER_ID_RE.fullmatch(args.resume_worker) is None:
                raise ControlPlaneError("worker ID must be A-J")
            print(json.dumps(resume_worker(project, args.resume_worker), ensure_ascii=False, sort_keys=True, indent=2))
            return 0
        state = validate_project(project, enforce_non_mutation=True)
        report = validation_report(state, repository_sha=args.repository_sha, repository_tree=args.repository_tree)
        if args.report:
            write_report(Path(args.report), report)
        else:
            print_summary(report)
        return 0 if state.passed else 1
    except ControlPlaneError as error:
        print(f"P24-001 control-plane error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
