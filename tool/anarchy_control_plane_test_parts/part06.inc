# Workflow evidence must remain bounded and preserve the first failure.


class AnarchyControlPlaneWorkflowEvidenceTest(unittest.TestCase):
    def test_artifact_upload_is_bounded_and_preserves_diagnostics(self) -> None:
        workflow = (ROOT / ".github/workflows/p24-adoption-review.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn("if: always()", workflow)
        self.assertNotIn("${{ runner.temp }}/p24-*", workflow)
        for name in (
            "p24-diagnostic.json",
            "p24-tests.log",
            "p24-generation.log",
            "p24-exact-check.log",
            "p24-isolated-generation-proof.json",
            "p24-validation-report.json",
            "expected-P24-001_CONTROL_PLANE_INDEX.json",
            "expected-SOURCE_MANIFEST.sha256",
        ):
            self.assertIn(f"${{{{ runner.temp }}}}/{name}", workflow)
        driver = (ROOT / "tool/p24_ci_driver_parts/part01.inc").read_text(
            encoding="utf-8"
        )
        self.assertIn("firstFailure", driver)
