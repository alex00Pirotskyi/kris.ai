# Permanent production-ledger vocabulary regression.


class AnarchyControlPlaneMigrationLedgerVocabularyTest(unittest.TestCase):
    def test_production_migration_ledger_uses_only_validator_event_kinds(self) -> None:
        ledger = read_json(ROOT / "docs/roadmap/anarchy/migration/MIGRATION_LEDGER.yaml")
        allowed = {
            "LIVE_BASELINE", "CLAIM", "AUTHORITY_DECISION_PROPOSED",
            "STALE_CLAIM_CORRECTED", "VALIDATOR_FOUNDATION",
            "CANDIDATE_PUSHED", "STACKED_PR_OPENED", "CI_OBSERVED",
            "SOURCE_MANIFEST_REFRESHED", "REVIEW_OBSERVED",
            "COORDINATION_CHECKPOINT", "CLEAN_ROOM_RESUME",
        }
        events = ledger["events"]
        self.assertEqual([event["sequence"] for event in events], list(range(1, len(events) + 1)))
        self.assertEqual({event["kind"] for event in events} - allowed, set())
