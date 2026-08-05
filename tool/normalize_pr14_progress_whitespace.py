#!/usr/bin/env python3
"""Normalize four legacy Markdown hard-break spaces blocking PR14 reconciliation.

The two durable recovery records predate the repository's current Git
whitespace gate. Only their two metadata lines use Markdown's trailing-two-
space hard break. This tool requires those exact four occurrences, removes
only those spaces, and fails if any target content drifts.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import tempfile
from typing import Sequence

TARGETS = (
    pathlib.PurePosixPath("docs/progress/2026-08-05-pr14-explicit-comment-trigger.md"),
    pathlib.PurePosixPath("docs/progress/2026-08-05-pr14-run-attempt-pinning.md"),
)
RECORDED_OLD = "**Recorded:** 2026-08-05  \n"
RECORDED_NEW = "**Recorded:** 2026-08-05\n"
AUTHORITY_OLD = "**Human roadmap authority:** `docs/roadmap/MASTER.md`  \n"
AUTHORITY_NEW = "**Human roadmap authority:** `docs/roadmap/MASTER.md`\n"


class NormalizationError(RuntimeError):
    pass


def normalize_text(value: str, *, label: str) -> str:
    if value.count(RECORDED_OLD) != 1:
        raise NormalizationError(
            f"{label}: expected exactly one recorded metadata hard break, "
            f"found {value.count(RECORDED_OLD)}"
        )
    if value.count(AUTHORITY_OLD) != 1:
        raise NormalizationError(
            f"{label}: expected exactly one roadmap-authority hard break, "
            f"found {value.count(AUTHORITY_OLD)}"
        )
    result = value.replace(RECORDED_OLD, RECORDED_NEW, 1)
    result = result.replace(AUTHORITY_OLD, AUTHORITY_NEW, 1)
    if result == value:
        raise NormalizationError(f"{label}: normalization produced no change")
    return result


def normalize_project(project: pathlib.Path) -> dict[str, object]:
    changed: list[str] = []
    for relative in TARGETS:
        path = project / relative
        if not path.is_file():
            raise NormalizationError(f"missing target file: {relative}")
        original = path.read_text(encoding="utf-8")
        normalized = normalize_text(original, label=str(relative))
        path.write_text(normalized, encoding="utf-8", newline="\n")
        changed.append(str(relative))
    return {
        "schemaVersion": "1.0.0",
        "roadmapAuthority": "docs/roadmap/MASTER.md",
        "changedPaths": changed,
        "removedTrailingSpaceOccurrences": 4,
        "status": "normalized",
    }


def self_test() -> int:
    sample = (
        "# Title\n\n"
        + RECORDED_OLD
        + AUTHORITY_OLD
        + "**Repository:** `example/repo`\n\n"
        + "Body  text remains unchanged.\n"
    )
    normalized = normalize_text(sample, label="fixture")
    assert RECORDED_OLD not in normalized
    assert AUTHORITY_OLD not in normalized
    assert normalized.count(RECORDED_NEW) == 1
    assert normalized.count(AUTHORITY_NEW) == 1
    assert "Body  text remains unchanged." in normalized

    for drift in (
        sample.replace(RECORDED_OLD, RECORDED_NEW),
        sample.replace(AUTHORITY_OLD, AUTHORITY_NEW),
        sample + RECORDED_OLD,
    ):
        try:
            normalize_text(drift, label="drift")
        except NormalizationError:
            pass
        else:
            raise AssertionError("drifted fixture was accepted")

    with tempfile.TemporaryDirectory(prefix="pr14-whitespace-self-test-") as raw:
        root = pathlib.Path(raw)
        for relative in TARGETS:
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(sample, encoding="utf-8", newline="\n")
        receipt = normalize_project(root)
        assert receipt["changedPaths"] == [str(path) for path in TARGETS]
        for relative in TARGETS:
            value = (root / relative).read_text(encoding="utf-8")
            assert value == normalized

    print("PR14 progress whitespace normalizer self-test: PASS")
    return 0


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=pathlib.Path, default=pathlib.Path("."))
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    if args.self_test:
        return self_test()
    try:
        receipt = normalize_project(args.project.resolve())
    except NormalizationError as exc:
        print(f"PR14 whitespace normalization: ERROR: {exc}")
        return 1
    print(json.dumps(receipt, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
