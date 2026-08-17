#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import os
import pathlib
import sys
import tempfile
import unittest

MODULE_PATH = pathlib.Path(__file__).with_name("kris_qwen_v6_guard.py")
SPEC = importlib.util.spec_from_file_location("kris_qwen_v6_guard", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
v6 = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = v6
SPEC.loader.exec_module(v6)


class GitHubClassificationTest(unittest.TestCase):
    def test_authentication_errors_are_infrastructure_state(self) -> None:
        self.assertIsNotNone(
            v6.github_auth_failure(
                ["gh", "pr", "view", "141"],
                "",
                "not logged into any GitHub hosts; run gh auth login",
                1,
            )
        )
        self.assertIsNotNone(
            v6.github_auth_failure(
                ["git", "push", "origin", "HEAD"],
                "",
                "fatal: could not read Username for https://github.com: terminal prompts disabled",
                128,
            )
        )
        self.assertIsNone(
            v6.github_auth_failure(
                ["gh", "pr", "view", "999999"],
                "",
                "GraphQL: Could not resolve to a PullRequest",
                1,
            )
        )
        self.assertIsNone(v6.github_auth_failure(["python3"], "", "boom", 1))


class ActionSchemaTest(unittest.TestCase):
    def test_closed_action_schema_rejects_unknown_fields(self) -> None:
        with self.assertRaisesRegex(v6.V6GuardError, "unknown fields"):
            v6.validate_action_shape(
                {"action": "read_file", "path": "README.md", "why": "inspect", "shell": True}
            )

    def test_action_payloads_are_bounded(self) -> None:
        with self.assertRaisesRegex(v6.V6GuardError, "write_file content"):
            v6.validate_action_shape(
                {
                    "action": "write_file",
                    "path": "x.txt",
                    "content": "x" * (v6.MAX_WRITE_BYTES + 1),
                    "why": "bounded negative control",
                }
            )
        with self.assertRaisesRegex(v6.V6GuardError, "run argv"):
            v6.validate_action_shape(
                {"action": "run", "argv": ["echo"] * (v6.MAX_ARG_COUNT + 1), "why": "bounded"}
            )

    def test_review_mode_remains_read_only(self) -> None:
        with self.assertRaisesRegex(v6.V6GuardError, "review mode"):
            v6.validate_action_shape(
                {"action": "write_file", "path": "x", "content": "x", "why": "not allowed"},
                review=True,
            )


class SharedAuthorityTest(unittest.TestCase):
    def setUp(self) -> None:
        self.authorities = {
            "authorities": {
                "source-inventory": {
                    "ownerMission": "MISSION-001",
                    "path": "test/product/source_contract_test.dart",
                    "mode": "APPEND_SAFE_DART_SET",
                    "eligibleRequestingMissions": ["MISSION-003"],
                },
                "product-runtime-composition": {
                    "ownerMission": "MISSION-001",
                    "path": "lib/product/product_runtime.dart",
                    "mode": "MANUAL_EXACT_DART_COMPOSITION_V1",
                    "eligibleRequestingMissions": ["MISSION-003"],
                },
                "test-center-registry": {
                    "ownerMission": "MISSION-002",
                    "path": "config/test_center_registry.v1.json",
                    "mode": "APPEND_SAFE_JSON",
                    "eligibleRequestingMissions": ["MISSION-004"],
                },
                "test-center-hierarchy": {
                    "ownerMission": "MISSION-002",
                    "path": "config/test_center_assurance_hierarchy.v1.json",
                    "mode": "APPEND_SAFE_JSON",
                    "eligibleRequestingMissions": ["MISSION-004"],
                },
                "test-center-proof-lineage": {
                    "ownerMission": "MISSION-002",
                    "path": "release/evidence/TEST_CENTER/P8-001/contracts/assurance-proof-contract.v1.json",
                    "mode": "APPEND_SAFE_JSON",
                    "eligibleRequestingMissions": ["MISSION-004"],
                },
            }
        }

    def test_p3_runtime_and_inventory_are_deferred_not_sanitized(self) -> None:
        report = v6.classify_shared_authority_paths(
            effective_paths=[
                "lib/product/browser/browser_runtime.dart",
                "lib/product/product_runtime.dart",
                "test/product/source_contract_test.dart",
                "README.md",
            ],
            allowed_patterns=["lib/product/browser/**"],
            authority_config=self.authorities,
            mission="MISSION-003",
        )
        self.assertTrue(report["requiresSharedAuthority"])
        self.assertEqual(
            report["sharedPaths"],
            ["lib/product/product_runtime.dart", "test/product/source_contract_test.dart"],
        )
        self.assertEqual(report["ordinaryForeignPaths"], ["README.md"])
        self.assertTrue(all(row["requestingMissionEligible"] for row in report["requiredAuthorities"]))

    def test_p4_registry_hierarchy_and_lineage_are_all_reported(self) -> None:
        paths = [
            "config/test_center_registry.v1.json",
            "config/test_center_assurance_hierarchy.v1.json",
            "release/evidence/TEST_CENTER/P8-001/contracts/assurance-proof-contract.v1.json",
        ]
        report = v6.classify_shared_authority_paths(
            effective_paths=paths,
            allowed_patterns=["services/research_worker/**"],
            authority_config=self.authorities,
            mission="MISSION-004",
        )
        self.assertEqual(report["sharedPaths"], sorted(paths))
        self.assertEqual(len(report["requiredAuthorities"]), 3)
        self.assertEqual(report["ordinaryForeignPaths"], [])

    def test_non_shared_foreign_path_remains_ordinary_sanitizer_input(self) -> None:
        report = v6.classify_shared_authority_paths(
            effective_paths=["README.md"],
            allowed_patterns=["lib/product/browser/**"],
            authority_config=self.authorities,
            mission="MISSION-003",
        )
        self.assertFalse(report["requiresSharedAuthority"])
        self.assertEqual(report["ordinaryForeignPaths"], ["README.md"])

    def test_report_is_durable_and_exact(self) -> None:
        report = v6.classify_shared_authority_paths(
            effective_paths=["lib/product/product_runtime.dart"],
            allowed_patterns=["lib/product/browser/**"],
            authority_config=self.authorities,
            mission="MISSION-003",
        )
        with tempfile.TemporaryDirectory() as raw:
            path = pathlib.Path(raw) / "shared-authority.json"
            written = v6.write_shared_authority_report(
                path,
                classification=report,
                work_order={"workOrderId": "WO-1", "mission": "MISSION-003", "roadmapTask": "P3-002"},
                product_branch="agent/product/p3",
                product_head="a" * 40,
                main_head="b" * 40,
            )
            self.assertEqual(json.loads(path.read_text()), written)
            self.assertEqual(written["state"], "BLOCKED_SHARED_AUTHORITY")


class OperationJournalTest(unittest.TestCase):
    def test_prepare_is_idempotent_and_complete_is_durable(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            journal = v6.OperationJournal(pathlib.Path(raw) / "ops.json")
            first = journal.prepare("PUSH_HELPER", {"branch": "agent/x", "commit": "a" * 40})
            second = journal.prepare("PUSH_HELPER", {"commit": "a" * 40, "branch": "agent/x"})
            self.assertEqual(first, second)
            completed = journal.complete(first["key"], {"remoteHead": "a" * 40})
            self.assertEqual(completed["state"], "COMPLETED")
            self.assertEqual(journal.get(first["key"])["result"]["remoteHead"], "a" * 40)


@unittest.skipUnless(pathlib.Path("/proc/self/stat").is_file(), "Linux /proc required")
class ProcessIdentityTest(unittest.TestCase):
    def test_identity_binds_pid_start_time_executable_and_cmdline(self) -> None:
        identity = v6.linux_process_identity(os.getpid())
        self.assertIsNotNone(identity)
        assert identity is not None
        self.assertTrue(v6.process_identity_matches(identity.to_json(), identity))
        tampered = identity.to_json()
        tampered["start_ticks"] += 1
        self.assertFalse(v6.process_identity_matches(tampered, identity))


class FilesystemSandboxTest(unittest.TestCase):
    def test_external_symlink_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = pathlib.Path(raw)
            (root / "safe").write_text("ok")
            (root / "escape").symlink_to("/etc/passwd")
            self.assertEqual(v6.audit_worktree_links(root), ["escape"])

    def test_sensitive_mount_overrides_hide_root_and_home_when_present(self) -> None:
        args = v6.sensitive_mount_overrides()
        if pathlib.Path("/root").exists():
            self.assertIn("/root", args)
        if pathlib.Path("/home").exists():
            self.assertIn("/home", args)


if __name__ == "__main__":
    unittest.main(verbosity=2)
