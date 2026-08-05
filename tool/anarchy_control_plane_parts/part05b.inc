# P24-001 exact-head portability and Worker B Test Center v1 binding repair.
#
# These overrides are loaded after the reviewable implementation parts. They
# keep P24 scoped to execution-control validation while binding its result and
# certification reference vocabularies to Worker B's canonical v1 contract.
TEST_EXECUTION_RESULTS = (
    "PASS", "FAIL", "ERROR", "SKIPPED", "BLOCKED", "UNKNOWN", "FLAKY", "NOT_IMPLEMENTED",
)
TEST_ASSURANCE_CLASSES = (
    "architecture_lint", "source_contract", "behavioral", "sdk_toolchain",
    "platform", "release", "mixed", "unclassified",
)
TEST_FAILURE_CLASSIFICATIONS = (
    "NONE", "ASSERTION", "INFRASTRUCTURE", "TIMEOUT", "SECURITY", "CLEANUP",
    "MISSING_DEPENDENCY", "UNSAFE_PROFILE", "UNKNOWN",
)
WORKER_B_TEST_CENTER_CONTRACT = {
    "schemaVersion": "1.0.0",
    "canonicalCommit": "5e093094bfb8287e70e684026ac88542a221016d",
    "canonicalSchema": "schemas/test_center.v1.json",
    "integrationBranch": "agent/b/test-center-contracts-and-review",
    "observedIntegrationHead": "2b8988b84c4eb8929cc1e733de274d5f484afea1",
    "observedIntegrationTree": "b33344fd5a7bcc212fd94933e4962654de062aac",
    "owner": "Worker B",
}
STATE_DOMAIN_VALUES = {**STATE_DOMAIN_VALUES, "TestExecutionResult": TEST_EXECUTION_RESULTS}


def _normalize_runtime_relative(relative: str) -> str:
    """Normalize a runtime path without relaxing persisted path contracts.

    Control-plane records remain canonical POSIX repository-relative strings.
    Runtime callers may use the host separator, so this helper accepts mixed
    separators after first rejecting absolute, drive-qualified, UNC, NUL, and
    parent-traversal forms. The normalized value is never written back.
    """
    if not isinstance(relative, str) or not relative or "\x00" in relative:
        raise ControlPlaneError(f"unsafe repository-relative path: {relative!r}")
    if relative.startswith(("/", "\\\\", "//")) or re.match(r"^[A-Za-z]:", relative):
        raise ControlPlaneError(f"unsafe repository-relative path: {relative!r}")
    normalized = relative.replace("\\", "/")
    pure = PurePosixPath(normalized)
    if pure.is_absolute() or ".." in pure.parts:
        raise ControlPlaneError(f"unsafe repository-relative path: {relative!r}")
    # Empty components and '.' are resolved by Path; '..' is never allowed.
    return pure.as_posix()


def _canonical_path(path: Path, *, strict: bool) -> Path:
    try:
        return path.resolve(strict=strict)
    except (OSError, RuntimeError, ValueError) as error:
        raise ControlPlaneError(f"cannot canonicalize repository path {path}: {error}") from error


def _same_or_descendant(root: Path, candidate: Path) -> bool:
    """Compare canonical paths with host-appropriate case/separator rules."""
    root_text = os.path.normcase(os.path.normpath(str(root)))
    candidate_text = os.path.normcase(os.path.normpath(str(candidate)))
    try:
        return os.path.commonpath((root_text, candidate_text)) == root_text
    except (OSError, ValueError):
        return False


def resolve_safe(project: Path, relative: str, *, must_exist: bool = False) -> Path:
    """Resolve a path inside the canonical repository root, fail-closed.

    Both operands are canonicalized before containment comparison. This accepts
    legitimate aliases such as macOS /var -> /private/var and Windows 8.3 ->
    long-path forms, while resolved symlink/junction escapes, sibling-prefix
    confusion, absolute/drive/UNC inputs, and parent traversal remain rejected.
    Existing targets are resolved strictly; non-existing write targets resolve
    through all existing parents and are allowed only when ``must_exist`` is
    false.
    """
    normalized = _normalize_runtime_relative(relative)
    root = _canonical_path(Path(project), strict=True)
    lexical = root / normalized
    target_exists = lexical.exists()
    if must_exist and not target_exists:
        raise ControlPlaneError(f"required path is missing: {relative}")
    candidate = _canonical_path(lexical, strict=must_exist or target_exists)
    if not _same_or_descendant(root, candidate):
        raise ControlPlaneError(f"path escapes repository: {relative}")
    return candidate


_p24_validate_task_records_v1 = validate_task_records


def validate_task_records(state: ValidationState) -> None:
    _p24_validate_task_records_v1(state)
    records = state.contract.get("taskRecords")
    if not isinstance(records, list):
        return
    for index, raw in enumerate(records):
        if not isinstance(raw, dict):
            continue
        task_id = str(raw.get("task", f"taskRecords[{index}]"))
        result = str(raw.get("testExecutionResult", ""))
        assurance = raw.get("testAssuranceClass")
        failure = raw.get("testFailureClassification")
        reason = raw.get("testResultReason")
        if assurance not in TEST_ASSURANCE_CLASSES:
            add_issue(
                state,
                "test_assurance_class_invalid",
                f"{task_id}.testAssuranceClass is invalid: {assurance!r}",
                subject=task_id,
            )
        if failure not in TEST_FAILURE_CLASSIFICATIONS:
            add_issue(
                state,
                "test_failure_classification_invalid",
                f"{task_id}.testFailureClassification is invalid: {failure!r}",
                subject=task_id,
            )
        if not isinstance(reason, str) or not reason.strip():
            add_issue(
                state,
                "test_result_reason_missing",
                f"{task_id}.testResultReason must be a non-empty field separate from result state",
                subject=task_id,
            )
        if result == "PASS" and failure != "NONE":
            add_issue(
                state,
                "test_result_metadata_conflict",
                f"{task_id} PASS requires failure classification NONE",
                subject=task_id,
            )
        if result in {"FAIL", "ERROR"} and failure == "NONE":
            add_issue(
                state,
                "test_result_metadata_conflict",
                f"{task_id} {result} requires a non-NONE failure classification",
                subject=task_id,
            )
