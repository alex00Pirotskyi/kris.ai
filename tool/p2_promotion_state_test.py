#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import sys
import unittest

from p2_evidence_state import validate_repository


ROOT = Path(__file__).resolve().parents[1]
GATE_PATH = ROOT / "tool/v71r12_exact_source_gate.py"
SPEC = importlib.util.spec_from_file_location("p2_owner_risk_gate", GATE_PATH)
if SPEC is None or SPEC.loader is None: raise RuntimeError("unable to load owner-risk gate")
GATE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = GATE
SPEC.loader.exec_module(GATE)


class P2PromotionStateTest(unittest.TestCase):
    def test_canonical_state_is_valid(self) -> None:
        result = validate_repository(ROOT)
        self.assertEqual(result["acceptedDecisionTasks"], ["P2-004"])
        self.assertEqual(result["behaviorCertifiedTasks"], [])
        self.assertFalse(result["platformQualified"])
        self.assertFalse(result["releaseSupported"])

    def test_exact_source_gate_uses_canonical_state(self) -> None:
        source = (ROOT / "tool/v71r12_exact_source_gate.py").read_text(
            encoding="utf-8"
        )
        self.assertIn("P2 canonical evidence state", source)
        self.assertIn("tool/p2_evidence_state.py", source)
        self.assertIn(
            'project / "release/evidence/P2-004/state.json"',
            source,
        )
        self.assertIn('if task_id == "P2-004":', source)
        self.assertIn("committed unfinished P2 evidence invalid", source)
        self.assertNotIn("committed P2 evidence invalid:", source)
        self.assertLess(
            source.index('if task_id == "P2-004":'),
            source.index("committed unfinished P2 evidence invalid"),
        )

    def test_r4_read_only_shell_audit(self) -> None:
        source = GATE_PATH.read_text(encoding="utf-8")
        self.assertIn("audit_r4_compatibility(project)", source)
        self.assertNotIn('step("R4 semantic idempotence"', source)
        result = GATE.audit_r4_compatibility(ROOT)
        self.assertEqual(result["selectedShell"], "integrated-p5-successor")
        self.assertEqual(result["pageOrder"], ["chat", "experience", "owner_mode"])
        self.assertFalse(result["historicalPatcherExecuted"])

    def test_reordered_shell_fails_closed_and_decoys_are_ignored(self) -> None:
        auditor = GATE._load_read_only_r4_auditor(ROOT)
        good = "// home: P2KristinShell(\nconst x = 'home: P2KristinShell(';\nWidget build(){return MaterialApp(home: KristinMainShell());}\nclass S{Widget build(){final pages=<Widget>[widget.chat,P5InformationArchitecturePrototype(),widget.ownerMode.buildWorkspace(),];return IndexedStack(children:pages);}}"
        result = GATE.audit_governed_shell_sources(good, "class L{Widget build(){final pages=<Widget>[widget.chat,widget.ownerMode.buildWorkspace(),];}}", lexer=auditor._dart_tokens)
        self.assertTrue(result["chatFirst"])
        bad = good.replace("widget.chat,P5InformationArchitecturePrototype()", "P5InformationArchitecturePrototype(),widget.chat")
        with self.assertRaisesRegex(GATE.GateError, "page order invalid"):
            GATE.audit_governed_shell_sources(bad, "class L{Widget build(){final pages=<Widget>[widget.chat,widget.ownerMode.buildWorkspace(),];}}", lexer=auditor._dart_tokens)

    def test_unfinished_capabilities_remain_source_only(self) -> None:
        phase = json.loads(
            (ROOT / "release/evidence/P2/state.json").read_text(encoding="utf-8")
        )
        states = phase["taskStates"]
        self.assertEqual(states["P2-004"], "accepted_decision")
        for task_id, status in states.items():
            if task_id != "P2-004":
                self.assertEqual(status, "source_only", task_id)
        self.assertEqual(phase["behaviorCertifiedTasks"], [])
        self.assertFalse(phase["phaseCompletionEligible"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
