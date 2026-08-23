#!/usr/bin/env python3
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import tempfile

import p8_soak_gate as soak


def sample(at: datetime, *, rss: int, handles: int, completed: int, failed: int = 0, crashes: int = 0, unauthorized: int = 0) -> dict[str, object]:
    return {
        "timestamp": at.isoformat().replace("+00:00", "Z"),
        "rssBytes": rss,
        "openHandles": handles,
        "activeRuns": 1,
        "completedRuns": completed,
        "failedRuns": failed,
        "unauthorizedEffects": unauthorized,
        "crashes": crashes,
    }


def main() -> int:
    start = datetime(2026, 8, 22, 12, tzinfo=timezone.utc)
    healthy = [
        soak.SoakSample.from_json(
            sample(
                start + timedelta(minutes=12 * index),
                rss=200 * 1024 * 1024 + index * 64 * 1024,
                handles=100 + index // 12,
                completed=index * 10,
            )
        )
        for index in range(121)
    ]
    report = soak.evaluate(healthy)
    assert report["passed"] is True, report
    assert report["observedDurationSeconds"] == 24 * 60 * 60
    assert report["sampleCount"] == 121
    assert len(str(report["sampleCorpusSha256"])) == 64

    short = soak.evaluate(
        healthy[:10],
        soak.SoakBudget(required_seconds=3600, minimum_samples=10),
    )
    assert short["passed"] is False
    assert "soak_duration_insufficient" in short["failures"]

    bad = list(healthy)
    final = bad[-1]
    bad[-1] = soak.SoakSample(
        timestamp=final.timestamp,
        rss_bytes=2 * 1024 * 1024 * 1024,
        open_handles=5000,
        active_runs=0,
        completed_runs=1000,
        failed_runs=100,
        unauthorized_effects=1,
        crashes=1,
    )
    report = soak.evaluate(bad)
    assert report["passed"] is False
    for code in (
        "soak_crash_observed",
        "soak_unauthorized_effect_observed",
        "soak_failure_rate_exceeded",
        "soak_rss_growth_exceeded",
        "soak_handle_growth_exceeded",
    ):
        assert code in report["failures"], report

    with tempfile.TemporaryDirectory(prefix="kristin-soak-") as raw:
        path = Path(raw) / "samples.jsonl"
        path.write_text(
            "\n".join(
                json.dumps(
                    sample(
                        start + timedelta(hours=index),
                        rss=1000 + index,
                        handles=10,
                        completed=index,
                    ),
                    sort_keys=True,
                )
                for index in range(3)
            )
            + "\n",
            encoding="utf-8",
        )
        loaded = soak.load_samples(path)
        assert len(loaded) == 3

    print("PASS P8 soak gate: duration, leak slope, reliability and authority-loss checks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
