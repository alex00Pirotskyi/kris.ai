# Governed fixture location, portable containment, and exact Worker B v1 binding.
FIXTURES = ROOT / "test/product/anarchy_control_plane/fixtures"


class AnarchyControlPlanePathAndTestContractTest(unittest.TestCase):
    def test_fixture_discovery_uses_governed_product_tree(self) -> None:
        expected = {
            "clean_room/expected.json",
            "collision/cases.json",
            "negative/cases.json",
            "positive/repository.json",
            "takeover/cases.json",
        }
        discovered = {
            path.relative_to(FIXTURES).as_posix()
            for path in FIXTURES.rglob("*.json")
        }
        self.assertEqual(discovered, expected)
        self.assertFalse((ROOT / "test/anarchy_control_plane").exists())

    def test_resolve_safe_canonicalizes_a_lexical_root_alias(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p24-root-alias-") as temporary:
            root = Path(temporary) / "repository"
            nested = root / "nested"
            nested.mkdir(parents=True)
            sentinel = root / "sentinel.txt"
            sentinel.write_text("sentinel\n", encoding="utf-8", newline="\n")
            alias = nested / ".."
            self.assertEqual(
                acp.resolve_safe(alias, "sentinel.txt", must_exist=True),
                sentinel.resolve(strict=True),
            )

    @unittest.skipUnless(sys.platform == "darwin", "macOS alias regression")
    def test_resolve_safe_accepts_var_private_var_alias(self) -> None:
        base = Path("/var/tmp")
        if not base.is_dir():
            self.skipTest("/var/tmp is unavailable")
        with tempfile.TemporaryDirectory(prefix="p24-var-alias-", dir=base) as temporary:
            lexical_root = Path(temporary) / "repository"
            lexical_root.mkdir()
            sentinel = lexical_root / "sentinel.txt"
            sentinel.write_text("sentinel\n", encoding="utf-8", newline="\n")
            self.assertNotEqual(str(lexical_root), str(lexical_root.resolve(strict=True)))
            self.assertEqual(
                acp.resolve_safe(lexical_root, "sentinel.txt", must_exist=True),
                sentinel.resolve(strict=True),
            )

    @unittest.skipUnless(os.name == "nt", "Windows 8.3 alias regression")
    def test_resolve_safe_accepts_windows_short_path_alias(self) -> None:
        import ctypes
        from ctypes import wintypes

        with tempfile.TemporaryDirectory(prefix="p24 windows long root ") as temporary:
            long_root = Path(temporary) / "repository with spaces"
            long_root.mkdir()
            sentinel = long_root / "sentinel.txt"
            sentinel.write_text("sentinel\n", encoding="utf-8", newline="\n")
            get_short = ctypes.windll.kernel32.GetShortPathNameW
            get_short.argtypes = [wintypes.LPCWSTR, wintypes.LPWSTR, wintypes.DWORD]
            get_short.restype = wintypes.DWORD
            buffer = ctypes.create_unicode_buffer(32768)
            length = get_short(str(long_root), buffer, len(buffer))
            if not length or length >= len(buffer):
                self.skipTest("GetShortPathNameW unavailable")
            short_root = Path(buffer.value)
            if os.path.normcase(str(short_root)) == os.path.normcase(str(long_root)):
                self.skipTest("8.3 aliases are disabled on the runner volume")
            self.assertEqual(
                os.path.normcase(str(acp.resolve_safe(short_root, "sentinel.txt", must_exist=True))),
                os.path.normcase(str(sentinel.resolve(strict=True))),
            )

    def test_resolve_safe_accepts_mixed_runtime_separators(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p24-mixed-separator-") as temporary:
            root = Path(temporary) / "repository"
            target = root / "nested" / "sentinel.txt"
            target.parent.mkdir(parents=True)
            target.write_text("sentinel\n", encoding="utf-8", newline="\n")
            self.assertEqual(
                acp.resolve_safe(root, "nested\\sentinel.txt", must_exist=True),
                target.resolve(strict=True),
            )

    @unittest.skipUnless(os.name == "nt", "Windows case normalization regression")
    def test_resolve_safe_uses_windows_case_rules(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p24-case-") as temporary:
            root = Path(temporary) / "Repository"
            root.mkdir()
            target = root / "MixedCase.txt"
            target.write_text("sentinel\n", encoding="utf-8", newline="\n")
            resolved = acp.resolve_safe(root, "mixedcase.TXT", must_exist=True)
            self.assertEqual(os.path.normcase(str(resolved)), os.path.normcase(str(target.resolve(strict=True))))

    def test_resolve_safe_accepts_valid_in_root_and_root_itself(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p24-in-root-") as temporary:
            root = Path(temporary) / "repository"
            nested = root / "nested"
            nested.mkdir(parents=True)
            self.assertEqual(acp.resolve_safe(root, ".", must_exist=True), root.resolve(strict=True))
            self.assertEqual(acp.resolve_safe(root, "nested", must_exist=True), nested.resolve(strict=True))

    def test_resolve_safe_rejects_parent_traversal_and_sibling_prefix(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p24-traversal-") as temporary:
            root = Path(temporary) / "repo"
            sibling = Path(temporary) / "repo-sibling"
            root.mkdir()
            sibling.mkdir()
            with self.assertRaises(acp.ControlPlaneError):
                acp.resolve_safe(root, "../outside.txt")
            with self.assertRaises(acp.ControlPlaneError):
                acp.resolve_safe(root, "../repo-sibling")

    def test_resolve_safe_rejects_symlink_or_junction_escape(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p24-link-escape-") as temporary:
            root = Path(temporary) / "repository"
            outside = Path(temporary) / "outside"
            root.mkdir()
            outside.mkdir()
            (outside / "secret.txt").write_text("secret\n", encoding="utf-8", newline="\n")
            link = root / "escape"
            try:
                link.symlink_to(outside, target_is_directory=True)
            except (OSError, NotImplementedError) as error:
                self.skipTest(f"symlink/junction creation unavailable: {error}")
            with self.assertRaises(acp.ControlPlaneError):
                acp.resolve_safe(root, "escape/secret.txt", must_exist=True)

    def test_resolve_safe_rejects_missing_required_and_malformed_paths(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p24-malformed-") as temporary:
            root = Path(temporary) / "repository"
            root.mkdir()
            with self.assertRaises(acp.ControlPlaneError):
                acp.resolve_safe(root, "missing.txt", must_exist=True)
            for unsafe in ("", "/absolute", "C:\\absolute", "\\\\server\\share", "bad\x00path"):
                with self.subTest(path=unsafe):
                    with self.assertRaises(acp.ControlPlaneError):
                        acp.resolve_safe(root, unsafe)

    def test_nonexistent_write_target_resolves_only_through_safe_parent(self) -> None:
        with tempfile.TemporaryDirectory(prefix="p24-write-target-") as temporary:
            root = Path(temporary) / "repository"
            parent = root / "generated"
            parent.mkdir(parents=True)
            expected = parent.resolve(strict=True) / "new.json"
            self.assertEqual(acp.resolve_safe(root, "generated/new.json"), expected)

    def test_test_result_state_matches_worker_b_canonical_v1_exactly(self) -> None:
        expected = (
            "PASS", "FAIL", "ERROR", "SKIPPED", "BLOCKED", "UNKNOWN", "FLAKY", "NOT_IMPLEMENTED",
        )
        self.assertEqual(acp.TEST_EXECUTION_RESULTS, expected)
        self.assertEqual(acp.WORKER_B_TEST_CENTER_CONTRACT["canonicalCommit"], "5e093094bfb8287e70e684026ac88542a221016d")
        self.assertEqual(acp.WORKER_B_TEST_CENTER_CONTRACT["observedIntegrationHead"], "2b8988b84c4eb8929cc1e733de274d5f484afea1")
        schema = read_json(ROOT / "schemas/anarchy_execution.schema.json")
        reference = schema["$defs"]["testExecutionResultReference"]
        self.assertEqual(tuple(reference["enum"]), expected)
        self.assertIn("5e093094bfb8287e70e684026ac88542a221016d", reference["x-external-contract"])
        self.assertEqual(reference["x-canonical-owner"], "Worker B")

    def test_legacy_reason_encoded_as_result_state_is_rejected(self) -> None:
        with repository() as root:
            update_contract(
                root,
                lambda data: data["taskRecords"][0].__setitem__(
                    "testExecutionResult", "SKIPPED_WITH_REASON"
                ),
            )
            state = acp.validate_project(root, check_generated=False, check_source_manifest=False)
            self.assertIn("state_domain_invalid", issue_codes(state))

    def test_canonical_skipped_state_uses_separate_reason_and_classification(self) -> None:
        with repository() as root:
            def mutate(data):
                record = data["taskRecords"][0]
                record["testExecutionResult"] = "SKIPPED"
                record["testResultReason"] = "Not applicable to this synthetic platform fixture."
                record["testAssuranceClass"] = "source_contract"
                record["testFailureClassification"] = "NONE"

            update_contract(root, mutate)
            state = acp.validate_project(root, check_generated=False, check_source_manifest=False)
            forbidden = {
                "state_domain_invalid",
                "test_result_reason_missing",
                "test_assurance_class_invalid",
                "test_failure_classification_invalid",
                "test_result_metadata_conflict",
            }
            self.assertFalse(forbidden & issue_codes(state), [issue.as_dict() for issue in state.issues])

    def test_test_result_metadata_remains_separate_from_other_state_domains(self) -> None:
        with repository() as root:
            def mutate(data):
                record = data["taskRecords"][0]
                record["testExecutionResult"] = "BLOCKED"
                record["testResultReason"] = "A required independent review is unavailable."
                record["testAssuranceClass"] = "source_contract"
                record["testFailureClassification"] = "MISSING_DEPENDENCY"
                record["roadmapStatus"] = "IN_PROGRESS"
                record["workerRuntimeStatus"] = "WAITING_FOR_REVIEW"
                record["certificationStatus"] = "PARTIAL"
                record["capabilitySupportStatus"] = "SOURCE_FOUNDATION"

            update_contract(root, mutate)
            state = acp.validate_project(root, check_generated=False, check_source_manifest=False)
            forbidden = {
                "state_domain_invalid",
                "test_result_reason_missing",
                "test_assurance_class_invalid",
                "test_failure_classification_invalid",
                "test_result_metadata_conflict",
                "unsupported_completion_claim",
                "p2_source_inflation",
            }
            self.assertFalse(forbidden & issue_codes(state), [issue.as_dict() for issue in state.issues])

# Keep the synthetic repository builder aligned with the governed product-test
# fixture root and the canonical Worker B metadata fields introduced above.
_p24_build_contract_v1 = build_contract


def build_contract() -> dict[str, object]:
    result = _p24_build_contract_v1()
    records = result.get("taskRecords")
    if isinstance(records, list):
        for raw in records:
            if not isinstance(raw, dict):
                continue
            raw.setdefault("testAssuranceClass", "source_contract")
            raw.setdefault("testFailureClassification", "NONE")
            raw.setdefault(
                "testResultReason",
                "Synthetic source-contract observation; no completion or support promotion is inferred.",
            )
    return result


_p24_valid_claim_v1 = valid_claim


def valid_claim() -> dict[str, object]:
    result = _p24_valid_claim_v1()
    result["nextAction"] = "Inspect the exact-head tri-OS CI and repair only proven P24 defects."
    return result


_p24_build_repository_v1 = build_repository


def build_repository(root: Path) -> None:
    original_copytree = shutil.copytree
    retired = root / "test/anarchy_control_plane/fixtures"
    governed = root / "test/product/anarchy_control_plane/fixtures"

    def redirect_copytree(src, dst, *args, **kwargs):
        destination = Path(dst)
        if destination == retired:
            destination = governed
        return original_copytree(src, destination, *args, **kwargs)

    with mock.patch.object(shutil, "copytree", side_effect=redirect_copytree):
        _p24_build_repository_v1(root)


def _test_scoped_schema_preserves_worker_b_exact_reference(self) -> None:
    schema = read_json(ROOT / "schemas/anarchy_execution.schema.json")
    self.assertFalse(schema["x-scope"]["testCenterReplacement"])
    self.assertFalse(schema["x-scope"]["roadmapAuthorityReplacement"])
    result_reference = schema["$defs"]["testExecutionResultReference"]
    certification_reference = schema["$defs"]["certificationStatusReference"]
    self.assertEqual(result_reference["x-canonical-owner"], "Worker B")
    self.assertEqual(result_reference["x-shared-contract-state"], "EXACT_VERSION_REFERENCE")
    self.assertEqual(certification_reference["x-shared-contract-state"], "EXACT_VERSION_REFERENCE")
    self.assertIn(
        "5e093094bfb8287e70e684026ac88542a221016d",
        result_reference["x-external-contract"],
    )


AnarchyControlPlaneTest.test_scoped_schema_preserves_worker_b_ownership = (
    _test_scoped_schema_preserves_worker_b_exact_reference
)
