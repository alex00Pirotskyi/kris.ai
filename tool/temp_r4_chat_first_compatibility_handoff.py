#!/usr/bin/env python3
"""Repair the R4 chat-first idempotence contract without weakening it."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BRANCH = "agent/gpt-gold/gs-003c-p2-promotion-current-main"
BASE = "e4f66ce5a95870cad342bbf9aaf89f94dc768f58"
CLEAN_PARENT = "6f3fcf7b0b786bc804d86ff3a07bda1f99301454"
CLEAN_PARENT_TREE = "e58e2d9b74d98476a48d8ae037489ca23110a45a"
WORKFLOW = Path(".github/workflows/temp-r4-chat-first-compatibility-handoff.yml")
SCRIPT = Path("tool/temp_r4_chat_first_compatibility_handoff.py")
PATCHER = Path("tool/v70r4_patch_p2_flutter_runtime_tests.py")
PATCHER_TEST = Path("tool/v70r4_patch_p2_flutter_runtime_tests_test.py")
FINAL_PATHS = {
    ".github/workflows/p1-p2-owner-risk-promotion-v71r12.yml",
    "SOURCE_MANIFEST.sha256",
    "tool/p2_promotion_state_test.py",
    "tool/v70r4_patch_p2_flutter_runtime_tests.py",
    "tool/v70r4_patch_p2_flutter_runtime_tests_test.py",
    "tool/v71r12_exact_source_gate.py",
}

OLD_COMPLETE = '''def _chat_first_contract_complete(source: str) -> bool:
    compact = _compact(source)
    required = (
        "finalp2Shell=source('lib/product/p2_app_shell.dart');",
        "expect(ui,contains('home:P2KristinShell('));",
        "expect(ui,contains('chat:ChatStudio('));",
        "expect(p2Shell,contains('var_index=0;'));",
        "expect(p2Shell,contains('widget.chat,'));",
    )
    return all(marker in compact for marker in required)
'''

NEW_COMPLETE = '''def _legacy_chat_first_contract_complete(source: str) -> bool:
    compact = _compact(source)
    required = (
        "finalp2Shell=source('lib/product/p2_app_shell.dart');",
        "expect(ui,contains('home:P2KristinShell('));",
        "expect(ui,contains('chat:ChatStudio('));",
        "expect(p2Shell,contains('var_index=0;'));",
        "expect(p2Shell,contains('widget.chat,'));",
    )
    return all(marker in compact for marker in required)


def _integrated_chat_first_contract_complete(source: str) -> bool:
    compact = _compact(source)
    required = (
        "finalmain=source('lib/main.dart');",
        "finalui=source('lib/product/ui.dart');",
        "expect(main,contains('ExperiencePlatform('));",
        "expect(main,contains('P5InformationArchitecturePrototype('));",
        "expect(main,contains('OwnerModeSurface('));",
        "expect(ui,contains('home:KristinMainShell('));",
        "expect(ui,contains('var_index=0;'));",
        "finalchatOffset=ui.indexOf('widget.chat,');",
        "finalexperienceOffset=ui.indexOf('P5InformationArchitecturePrototype(');",
        "finalownerOffset=ui.indexOf('widget.ownerMode.buildWorkspace(');",
        "expect(chatOffset,greaterThanOrEqualTo(0));",
        "expect(experienceOffset,greaterThan(chatOffset));",
        "expect(ownerOffset,greaterThan(experienceOffset));",
    )
    return all(marker in compact for marker in required)


def _integrated_chat_first_contract_present(source: str) -> bool:
    compact = _compact(source)
    markers = (
        "home:KristinMainShell(",
        "finalchatOffset=ui.indexOf('widget.chat,');",
        "finalexperienceOffset=ui.indexOf('P5InformationArchitecturePrototype(');",
        "finalownerOffset=ui.indexOf('widget.ownerMode.buildWorkspace(');",
    )
    return any(marker in compact for marker in markers)


def _chat_first_contract_complete(source: str) -> bool:
    return _legacy_chat_first_contract_complete(
        source
    ) or _integrated_chat_first_contract_complete(source)
'''

OLD_PARTIAL = '''    if "final p2Shell" in source or "home: P2KristinShell(" in source:
        fail("chat-first P2 shell contract is partially patched")
'''

NEW_PARTIAL = '''    if "final p2Shell" in source or "home: P2KristinShell(" in source:
        fail("legacy chat-first P2 shell contract is partially patched")
    if _integrated_chat_first_contract_present(source):
        fail("integrated chat-first shell contract is partially patched")
'''

TEST_CONTENT = r'''#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tool/v70r4_patch_p2_flutter_runtime_tests.py"
SPEC = importlib.util.spec_from_file_location("v70r4_patcher", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("unable to load R4 patcher")
PATCHER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PATCHER)


class ChatFirstCompatibilityTest(unittest.TestCase):
    def _temporary_project(self, source: str) -> tuple[tempfile.TemporaryDirectory[str], Path]:
        temp = tempfile.TemporaryDirectory()
        root = Path(temp.name)
        target = root / "test/product/source_contract_test.dart"
        target.parent.mkdir(parents=True)
        target.write_text(source, encoding="utf-8")
        return temp, root

    def test_current_integrated_contract_is_recognized_without_mutation(self) -> None:
        source = (ROOT / "test/product/source_contract_test.dart").read_text(
            encoding="utf-8"
        )
        self.assertTrue(PATCHER._integrated_chat_first_contract_complete(source))
        self.assertTrue(PATCHER._chat_first_contract_complete(source))
        temp, project = self._temporary_project(source)
        self.addCleanup(temp.cleanup)
        before = (project / "test/product/source_contract_test.dart").read_bytes()
        self.assertFalse(PATCHER.patch_chat_first_contract(project))
        self.assertEqual(
            (project / "test/product/source_contract_test.dart").read_bytes(),
            before,
        )

    def test_historical_p2_shell_contract_remains_recognized(self) -> None:
        source = """      final ui = source('lib/product/ui.dart');
      final chat = source('lib/product/chat_studio.dart');
      final p2Shell = source('lib/product/p2_app_shell.dart');
      expect(ui, contains('home: P2KristinShell('));
      expect(ui, contains('chat: ChatStudio('));
      expect(p2Shell, contains('var _index = 0;'));
      expect(p2Shell, contains('widget.chat,'));
      expect(chat, contains("label: 'Chats'"));
"""
        self.assertTrue(PATCHER._legacy_chat_first_contract_complete(source))
        self.assertTrue(PATCHER._chat_first_contract_complete(source))

    def test_historical_unpatched_contract_still_transforms_once(self) -> None:
        source = """      final ui = source('lib/product/ui.dart');
      final chat = source('lib/product/chat_studio.dart');
      expect(ui, contains('home: ChatStudio('));
      expect(chat, contains("label: 'Chats'"));
"""
        temp, project = self._temporary_project(source)
        self.addCleanup(temp.cleanup)
        self.assertTrue(PATCHER.patch_chat_first_contract(project))
        updated = (project / "test/product/source_contract_test.dart").read_text(
            encoding="utf-8"
        )
        self.assertTrue(PATCHER._legacy_chat_first_contract_complete(updated))
        self.assertFalse(PATCHER.patch_chat_first_contract(project))

    def test_partial_integrated_contract_fails_closed(self) -> None:
        source = (ROOT / "test/product/source_contract_test.dart").read_text(
            encoding="utf-8"
        )
        anchor = "      expect(ownerOffset, greaterThan(experienceOffset));\n"
        self.assertEqual(source.count(anchor), 1)
        partial = source.replace(anchor, "", 1)
        self.assertFalse(PATCHER._integrated_chat_first_contract_complete(partial))
        self.assertTrue(PATCHER._integrated_chat_first_contract_present(partial))
        temp, project = self._temporary_project(partial)
        self.addCleanup(temp.cleanup)
        with self.assertRaisesRegex(
            PATCHER.PatchError,
            "integrated chat-first shell contract is partially patched",
        ):
            PATCHER.patch_chat_first_contract(project)

    def test_partial_legacy_contract_fails_closed(self) -> None:
        source = """      final ui = source('lib/product/ui.dart');
      final p2Shell = source('lib/product/p2_app_shell.dart');
      expect(ui, contains('home: P2KristinShell('));
"""
        temp, project = self._temporary_project(source)
        self.addCleanup(temp.cleanup)
        with self.assertRaisesRegex(
            PATCHER.PatchError,
            "legacy chat-first P2 shell contract is partially patched",
        ):
            PATCHER.patch_chat_first_contract(project)


if __name__ == "__main__":
    unittest.main(verbosity=2)
'''


def run(*args: str, capture: bool = False) -> str:
    result = subprocess.run(
        list(args),
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(args)}\n"
            f"{result.stdout or ''}"
        )
    return (result.stdout or "").strip()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


def verify_transport(trigger: str) -> None:
    if not re.fullmatch(r"[0-9a-f]{40}", trigger):
        raise RuntimeError("GITHUB_SHA is missing or invalid")
    if run("git", "branch", "--show-current", capture=True) != BRANCH:
        raise RuntimeError("unexpected branch")
    if run("git", "rev-parse", "HEAD", capture=True) != trigger:
        raise RuntimeError("checkout does not match exact trigger head")
    run("git", "merge-base", "--is-ancestor", CLEAN_PARENT, trigger)
    if run("git", "rev-parse", f"{CLEAN_PARENT}^{{tree}}", capture=True) != CLEAN_PARENT_TREE:
        raise RuntimeError("clean owner-risk candidate tree changed unexpectedly")
    if (ROOT / PATCHER_TEST).exists():
        raise RuntimeError("R4 patcher regression unexpectedly exists on clean parent")


def patch_sources() -> None:
    patcher = ROOT / PATCHER
    text = patcher.read_text(encoding="utf-8")
    text = replace_once(
        text,
        OLD_COMPLETE,
        NEW_COMPLETE,
        "chat-first complete-state recognizer",
    )
    text = replace_once(
        text,
        OLD_PARTIAL,
        NEW_PARTIAL,
        "chat-first partial-state guard",
    )
    patcher.write_text(text, encoding="utf-8", newline="\n")
    (ROOT / PATCHER_TEST).write_text(
        TEST_CONTENT,
        encoding="utf-8",
        newline="\n",
    )


def remove_transport() -> None:
    for relative in (WORKFLOW, SCRIPT):
        path = ROOT / relative
        if not path.is_file():
            raise RuntimeError(f"missing temporary path: {relative}")
        path.unlink()


def refresh_manifest_twice() -> None:
    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    first = (ROOT / "SOURCE_MANIFEST.sha256").read_bytes()
    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    if (ROOT / "SOURCE_MANIFEST.sha256").read_bytes() != first:
        raise RuntimeError("SOURCE_MANIFEST.sha256 is not byte-stable")
    run("python3", "tool/p1a_text_eof_contract_test.py", "--project", ".")


def validate() -> None:
    patch_sources()
    run(
        "python3",
        "-m",
        "py_compile",
        PATCHER.as_posix(),
        PATCHER_TEST.as_posix(),
        "tool/v71r12_exact_source_gate.py",
        "tool/p2_promotion_state_test.py",
    )
    run("python3", PATCHER_TEST.as_posix())
    result_path = Path(os.environ["RUNNER_TEMP"]) / "r4-current-state.json"
    run(
        "python3",
        PATCHER.as_posix(),
        "--project",
        ".",
        "--json-output",
        str(result_path),
    )
    result = json.loads(result_path.read_text(encoding="utf-8"))
    if result.get("changedFileCount") != 0 or result.get("semanticStateRecognized") is not True:
        raise RuntimeError(f"R4 current state is not idempotent: {result}")
    if result.get("chatFirstP2ShellContractFixed") is not True:
        raise RuntimeError("R4 chat-first compatibility result is false")
    run("python3", "tool/p2_evidence_state.py", "--project", ".")
    run("python3", "tool/p2_evidence_state_test.py")
    run("python3", "tool/p2_promotion_state_test.py")
    remove_transport()
    refresh_manifest_twice()
    run("python3", PATCHER_TEST.as_posix())
    run(
        "python3",
        PATCHER.as_posix(),
        "--project",
        ".",
        "--json-output",
        str(result_path),
    )
    run("ruby", "tool/workflow_integrity_test.rb", ".")
    run("git", "diff", "--check")


def prove_scope() -> list[str]:
    run("git", "add", "-A")
    run("git", "diff", "--cached", "--check")
    paths = run(
        "git",
        "diff",
        "--cached",
        "--name-only",
        BASE,
        "--",
        capture=True,
    ).splitlines()
    if set(paths) != FINAL_PATHS:
        raise RuntimeError(
            f"exact R4 candidate scope mismatch: expected {sorted(FINAL_PATHS)}, got {paths}"
        )
    for temporary in (WORKFLOW.as_posix(), SCRIPT.as_posix()):
        if temporary in paths or (ROOT / temporary).exists():
            raise RuntimeError(f"temporary handoff survived: {temporary}")
    return paths


def build_handoff(paths: list[str], trigger: str) -> None:
    target_root = Path(os.environ["RUNNER_TEMP"]) / "r4-chat-first-candidate"
    if target_root.exists():
        shutil.rmtree(target_root)
    target_root.mkdir(parents=True)
    files = []
    for relative in sorted(paths):
        source = ROOT / relative
        target = target_root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        payload = source.read_bytes()
        files.append(
            {
                "path": relative,
                "bytes": len(payload),
                "sha256": hashlib.sha256(payload).hexdigest(),
                "gitBlob": run("git", "hash-object", relative, capture=True),
            }
        )
    metadata = {
        "schemaVersion": 1,
        "baseCommit": BASE,
        "baseTree": run("git", "rev-parse", f"{BASE}^{{tree}}", capture=True),
        "cleanParent": CLEAN_PARENT,
        "transportCommit": trigger,
        "effectivePaths": sorted(paths),
        "files": files,
        "validation": {
            "currentIntegratedContractRecognized": True,
            "historicalP2ContractRecognized": True,
            "historicalTransformationPreserved": True,
            "partialIntegratedContractRejected": True,
            "partialLegacyContractRejected": True,
            "currentRepositoryIdempotent": True,
        },
        "truthBoundary": {
            "p2AcceptedDecisionTasks": ["P2-004"],
            "p2BehaviorCertifiedTasks": [],
            "p2PhaseComplete": False,
            "platformQualified": False,
            "releaseSupported": False,
            "productionSupported": False,
            "gaPromoted": False,
        },
    }
    (target_root / "metadata.json").write_text(
        json.dumps(metadata, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(json.dumps(metadata, indent=2, sort_keys=True))


def main() -> int:
    trigger = os.environ.get("GITHUB_SHA", "").strip()
    verify_transport(trigger)
    validate()
    build_handoff(prove_scope(), trigger)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
