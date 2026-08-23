#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
from typing import Any, Iterable


@dataclass(frozen=True)
class SoakSample:
    timestamp: datetime
    rss_bytes: int
    open_handles: int
    active_runs: int
    completed_runs: int
    failed_runs: int
    unauthorized_effects: int
    crashes: int

    @classmethod
    def from_json(cls, value: dict[str, Any]) -> "SoakSample":
        timestamp = datetime.fromisoformat(str(value["timestamp"]).replace("Z", "+00:00")).astimezone(timezone.utc)
        numeric = {
            key: int(value.get(key, 0))
            for key in (
                "rssBytes",
                "openHandles",
                "activeRuns",
                "completedRuns",
                "failedRuns",
                "unauthorizedEffects",
                "crashes",
            )
        }
        if any(number < 0 for number in numeric.values()):
            raise ValueError("soak_sample_negative_value")
        return cls(
            timestamp=timestamp,
            rss_bytes=numeric["rssBytes"],
            open_handles=numeric["openHandles"],
            active_runs=numeric["activeRuns"],
            completed_runs=numeric["completedRuns"],
            failed_runs=numeric["failedRuns"],
            unauthorized_effects=numeric["unauthorizedEffects"],
            crashes=numeric["crashes"],
        )


@dataclass(frozen=True)
class SoakBudget:
    required_seconds: int = 24 * 60 * 60
    maximum_rss_growth_bytes_per_hour: int = 32 * 1024 * 1024
    maximum_handle_growth_per_hour: float = 25.0
    maximum_failure_rate: float = 0.01
    minimum_samples: int = 120


def load_samples(path: Path) -> list[SoakSample]:
    samples: list[SoakSample] = []
    for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw.strip():
            continue
        try:
            decoded = json.loads(raw)
            if not isinstance(decoded, dict):
                raise ValueError("object required")
            samples.append(SoakSample.from_json(decoded))
        except Exception as exc:
            raise ValueError(f"soak_sample_invalid:{line_number}:{type(exc).__name__}") from exc
    samples.sort(key=lambda item: item.timestamp)
    if any(right.timestamp <= left.timestamp for left, right in zip(samples, samples[1:])):
        raise ValueError("soak_sample_timestamps_not_strict")
    return samples


def _slope_per_hour(samples: list[SoakSample], selector) -> float:
    if len(samples) < 2:
        return math.inf
    origin = samples[0].timestamp
    xs = [(sample.timestamp - origin).total_seconds() / 3600.0 for sample in samples]
    ys = [float(selector(sample)) for sample in samples]
    x_mean = sum(xs) / len(xs)
    y_mean = sum(ys) / len(ys)
    denominator = sum((x - x_mean) ** 2 for x in xs)
    if denominator == 0:
        return math.inf
    return sum((x - x_mean) * (y - y_mean) for x, y in zip(xs, ys, strict=True)) / denominator


def evaluate(samples: list[SoakSample], budget: SoakBudget = SoakBudget()) -> dict[str, Any]:
    failures: list[str] = []
    if len(samples) < budget.minimum_samples:
        failures.append("soak_sample_count_insufficient")
    duration_seconds = 0
    if len(samples) >= 2:
        duration_seconds = int((samples[-1].timestamp - samples[0].timestamp).total_seconds())
    if duration_seconds < budget.required_seconds:
        failures.append("soak_duration_insufficient")
    rss_slope = _slope_per_hour(samples, lambda item: item.rss_bytes)
    handle_slope = _slope_per_hour(samples, lambda item: item.open_handles)
    if rss_slope > budget.maximum_rss_growth_bytes_per_hour:
        failures.append("soak_rss_growth_exceeded")
    if handle_slope > budget.maximum_handle_growth_per_hour:
        failures.append("soak_handle_growth_exceeded")
    crashes = max((sample.crashes for sample in samples), default=0)
    unauthorized_effects = max((sample.unauthorized_effects for sample in samples), default=0)
    if crashes:
        failures.append("soak_crash_observed")
    if unauthorized_effects:
        failures.append("soak_unauthorized_effect_observed")
    completed = max((sample.completed_runs for sample in samples), default=0)
    failed = max((sample.failed_runs for sample in samples), default=0)
    attempted = completed + failed
    failure_rate = (failed / attempted) if attempted else 0.0
    if failure_rate > budget.maximum_failure_rate:
        failures.append("soak_failure_rate_exceeded")
    canonical_samples = [
        {
            "timestamp": sample.timestamp.isoformat().replace("+00:00", "Z"),
            "rssBytes": sample.rss_bytes,
            "openHandles": sample.open_handles,
            "activeRuns": sample.active_runs,
            "completedRuns": sample.completed_runs,
            "failedRuns": sample.failed_runs,
            "unauthorizedEffects": sample.unauthorized_effects,
            "crashes": sample.crashes,
        }
        for sample in samples
    ]
    corpus_sha = hashlib.sha256(
        json.dumps(canonical_samples, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return {
        "schemaVersion": "1.0.0",
        "passed": not failures,
        "requiredDurationSeconds": budget.required_seconds,
        "observedDurationSeconds": duration_seconds,
        "sampleCount": len(samples),
        "rssGrowthBytesPerHour": round(rss_slope, 3) if math.isfinite(rss_slope) else None,
        "handleGrowthPerHour": round(handle_slope, 6) if math.isfinite(handle_slope) else None,
        "failureRate": failure_rate,
        "crashes": crashes,
        "unauthorizedEffects": unauthorized_effects,
        "sampleCorpusSha256": corpus_sha,
        "failures": sorted(set(failures)),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--required-seconds", type=int, default=24 * 60 * 60)
    parser.add_argument("--minimum-samples", type=int, default=120)
    parser.add_argument("--max-rss-growth-bytes-per-hour", type=int, default=32 * 1024 * 1024)
    parser.add_argument("--max-handle-growth-per-hour", type=float, default=25.0)
    parser.add_argument("--max-failure-rate", type=float, default=0.01)
    args = parser.parse_args()
    budget = SoakBudget(
        required_seconds=args.required_seconds,
        maximum_rss_growth_bytes_per_hour=args.max_rss_growth_bytes_per_hour,
        maximum_handle_growth_per_hour=args.max_handle_growth_per_hour,
        maximum_failure_rate=args.max_failure_rate,
        minimum_samples=args.minimum_samples,
    )
    report = evaluate(load_samples(Path(args.samples).resolve()), budget)
    report["evaluatedAt"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    target = Path(args.report).resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "observedDurationSeconds": report["observedDurationSeconds"], "report": str(target)}, sort_keys=True))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
