# Permanent production Worker-J packet regression.


class AnarchyControlPlaneProductionWorkerJPacketTest(unittest.TestCase):
    def test_production_worker_j_packet_has_bounded_p24_phase_link(self) -> None:
        worker = acp.parse_worker(
            ROOT,
            ROOT / "docs/roadmap/anarchy/workers/WORKER_J.md",
        )
        self.assertEqual(worker.worker, "J")
        self.assertEqual(worker.branch, "agent/j/P24-001-roadmap-as-data-adr")
        self.assertIn(
            "../phases/P24-roadmap-integrity-traceability-and-no-sql-authority.md",
            worker.phase_links,
        )
