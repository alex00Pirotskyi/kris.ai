#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

import p8_release_evidence_gate as gate

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    report = gate.validate(ROOT)
    assert report["passed"] is True, report
    assert report["sourceTrainMergeAllowed"] is True
    assert report["productionReleaseAllowed"] is False
    assert set(report["externalBlockers"]) == {"P1A", "P5-015", "P8-011", "P8-014"}
    assert report["replayCaseCount"] >= 16
    assert len(str(report["convergenceDigestSha256"])) == 64

    failures: list[str] = []
    gate.require_exact(["a", "b"], {"a", "c"}, "fixture", failures)
    assert failures and "missing=['c']" in failures[0]
    assert "extra=['b']" in failures[0]

    print("PASS P8 release evidence gate: hierarchy, mappings, blockers and replay registry")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
