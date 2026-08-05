class AnarchyControlPlaneTest(unittest.TestCase):
    maxDiff = None

    def test_scoped_schema_preserves_worker_b_ownership(self) -> None:
        schema = read_json(ROOT / "schemas/anarchy_execution.schema.json")
        self.assertFalse(schema["x-scope"]["testCenterReplacement"])
        self.assertFalse(schema["x-scope"]["roadmapAuthorityReplacement"])
        self.assertEqual(schema["$defs"]["testExecutionResultReference"]["x-canonical-owner"], "Worker B")
        self.assertEqual(schema["$defs"]["certificationStatusReference"]["x-shared-contract-state"], "BLOCKED_BY_SHARED_CONTRACT")

    def test_positive_repository_has_25_phases_359_tasks_and_10_workers(self) -> None:
        expected = read_json(FIXTURES / "positive/repository.json")["expected"]
        with repository() as root:
            state = acp.validate_project(root, enforce_non_mutation=True)
            report = acp.validation_report(state)
            self.assertTrue(state.passed, [issue.as_dict() for issue in state.issues])
            self.assertEqual(len(state.phases), expected["phaseCount"])
            self.assertEqual(len(state.tasks), expected["taskCount"])
            self.assertEqual(len(state.workers), expected["workerCount"])
            self.assertEqual(report["classification"], expected["classification"])
            self.assertEqual(state.generated_status, "CURRENT")
            self.assertEqual(state.source_manifest_status, "CURRENT")
            self.assertIn("Worker B exact-head review artifact missing", state.blockers)
            self.assertIn("Worker I exact-head review artifact missing", state.blockers)

    def test_every_negative_fixture_fails_with_expected_rule(self) -> None:
        fixtures = read_json(FIXTURES / "negative/cases.json")["cases"]
        for fixture in fixtures:
            with self.subTest(fixture=fixture["id"]), repository() as root:
                apply_operation(root, str(fixture["operation"]))
                state = acp.validate_project(root)
                self.assertIn(fixture["expectedCode"], issue_codes(state), [issue.as_dict() for issue in state.issues])
                self.assertFalse(state.passed)

    def test_active_claim_collision_fixture(self) -> None:
        fixture = read_json(FIXTURES / "collision/cases.json")["cases"][0]
        with repository() as root:
            add_collision_claim(root, str(fixture["variant"]))
            state = acp.validate_project(root)
            self.assertIn(fixture["expectedCode"], issue_codes(state))

    def test_shared_contract_collision_fixture(self) -> None:
        fixture = read_json(FIXTURES / "collision/cases.json")["cases"][1]
        with repository() as root:
            add_collision_claim(root, str(fixture["variant"]))
            state = acp.validate_project(root)
            self.assertIn(fixture["expectedCode"], issue_codes(state))

    def test_yield_and_takeover_require_continuity(self) -> None:
        fixtures = read_json(FIXTURES / "takeover/cases.json")["cases"]
        for fixture in fixtures:
            with self.subTest(fixture=fixture["id"]), repository() as root:
                def mutate(data):
                    data["state"] = fixture["value"]
                    data["continuity"] = {}
                update_claim(root, mutate)
                state = acp.validate_project(root)
                self.assertIn(fixture["expectedCode"], issue_codes(state))

    def test_safe_takeover_fixture_passes_continuity_rules(self) -> None:
        with repository() as root:
            def mutate(data):
                data["state"] = "TAKEN_OVER"
                data["continuity"] = {
                    "previousClaim": "docs/roadmap/anarchy/claims/OLD.yaml",
                    "previousState": "YIELDED",
                    "previousHead": "1" * 40,
                    "previousTree": "2" * 40,
                    "yieldedAtUtc": "2026-08-05T11:00:00Z",
                    "takeoverBaseCommit": "1" * 40,
                    "takeoverBaseTree": "2" * 40,
                    "safeTakeover": "Exact yielded head/tree preserved.",
                }
            update_claim(root, mutate)
            state = acp.validate_project(root, check_source_manifest=False, check_generated=False)
            self.assertNotIn("unsafe_takeover", issue_codes(state))
            self.assertNotIn("yield_continuity", issue_codes(state))

    def test_check_mode_is_byte_and_mtime_non_mutating(self) -> None:
        with repository() as root:
            contract = acp.load_contract(root)
            scopes = [str(item) for item in contract["nonMutationScopes"]]
            before = acp.snapshot_scopes(root, scopes)
            state = acp.validate_project(root, enforce_non_mutation=True)
            after = acp.snapshot_scopes(root, scopes)
            self.assertTrue(state.passed, [issue.as_dict() for issue in state.issues])
            self.assertEqual(before, after)
            completed = subprocess.run(
                [sys.executable, "tool/anarchy_control_plane.py", "--check", "--project", "."],
                cwd=root,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
            self.assertEqual(before, acp.snapshot_scopes(root, scopes))

    def test_write_mode_is_deterministic_and_idempotent(self) -> None:
        with repository() as root:
            generated = root / "docs/roadmap/anarchy/generated/P24-001_CONTROL_PLANE_INDEX.json"
            generated.write_text("stale\n", encoding="utf-8")
            first = acp.write_generated(root)
            first_bytes = generated.read_bytes()
            first_hash = hashlib.sha256(first_bytes).hexdigest()
            second = acp.write_generated(root)
            second_bytes = generated.read_bytes()
            self.assertTrue(first["changed"])
            self.assertFalse(second["changed"])
            self.assertEqual(first_bytes, second_bytes)
            self.assertEqual(first_hash, second["sha256"])

    def test_atomic_write_failure_leaves_original_and_no_partial_file(self) -> None:
        with repository() as root:
            generated = root / "docs/roadmap/anarchy/generated/P24-001_CONTROL_PLANE_INDEX.json"
            original = b"original-authority-view\n"
            generated.write_bytes(original)
            with mock.patch.object(acp.os, "replace", side_effect=OSError("injected interruption")):
                with self.assertRaises(OSError):
                    acp.write_generated(root)
            self.assertEqual(generated.read_bytes(), original)
            self.assertEqual(list(generated.parent.glob(f".{generated.name}.*.tmp")), [])

    def test_canonical_source_manifest_generator_is_idempotent(self) -> None:
        with repository() as root:
            before = (root / "SOURCE_MANIFEST.sha256").read_bytes()
            run(sys.executable, "tool/p1a_refresh_source_manifest.py", ".", cwd=root)
            first = (root / "SOURCE_MANIFEST.sha256").read_bytes()
            run(sys.executable, "tool/p1a_refresh_source_manifest.py", ".", cwd=root)
            second = (root / "SOURCE_MANIFEST.sha256").read_bytes()
            self.assertEqual(before, first)
            self.assertEqual(first, second)
            state = acp.validate_project(root)
            self.assertEqual(state.source_manifest_status, "CURRENT")

    def test_generated_report_is_bounded_and_honest(self) -> None:
        with repository() as root:
            state = acp.validate_project(root)
            report = acp.validation_report(state, repository_sha="a" * 40, repository_tree="b" * 40)
            self.assertEqual(report["classification"], "ADOPTION_REVIEW")
            self.assertFalse(report["authorityPromotionPerformed"])
            self.assertEqual(report["repository"], {"commit": "a" * 40, "tree": "b" * 40})
            self.assertEqual(report["counts"]["phases"], 25)
            self.assertEqual(report["counts"]["tasks"], 359)
            self.assertEqual(report["tests"]["independentReviews"], "BLOCKED")

    def test_clean_room_worker_j_resume_uses_repository_only(self) -> None:
        expected = read_json(FIXTURES / "clean_room/expected.json")
        with repository() as root, tempfile.TemporaryDirectory(prefix="p24-clean-room-") as temporary:
            clean = Path(temporary) / "repo"
            shutil.copytree(root, clean)
            resume = acp.resume_worker(clean, "J")
            self.assertEqual(resume["worker"], expected["worker"])
            self.assertEqual(resume["activeTask"], expected["activeTask"])
            self.assertEqual(resume["branch"], expected["branch"])
            self.assertEqual(resume["claim"], expected["claim"])
            self.assertEqual(resume["authority"], expected["authority"])
            self.assertIn(expected["nextActionContains"], resume["nextAction"])
            self.assertTrue(resume["validationPassed"])

    def test_directive_and_migration_records_cannot_assign_task_state(self) -> None:
        with repository() as root:
            matrix_path = root / "docs/roadmap/anarchy/migration/DIRECTIVE_MATRIX.yaml"
            matrix = read_json(matrix_path)
            matrix["directives"][0]["roadmapStatus"] = "DONE"
            write_json(matrix_path, matrix)
            ledger_path = root / "docs/roadmap/anarchy/migration/MIGRATION_LEDGER.yaml"
            ledger = read_json(ledger_path)
            ledger["events"][0]["certificationStatus"] = "PASS"
            write_json(ledger_path, ledger)
            state = acp.validate_project(root)
            self.assertIn("directive_state_authority", issue_codes(state))
            self.assertIn("migration_ledger_state_authority", issue_codes(state))

    def test_resource_limits_are_declared(self) -> None:
        self.assertGreaterEqual(acp.MAX_TASKS, 359)
        self.assertLessEqual(acp.MAX_TASKS, 5000)
        self.assertLessEqual(acp.MAX_CONTROL_BYTES, 2 * 1024 * 1024)
        self.assertLessEqual(acp.MAX_EDGES, 20000)


if __name__ == "__main__":
    unittest.main(verbosity=2)
