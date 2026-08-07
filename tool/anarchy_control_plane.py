#!/usr/bin/env python3
"""Load the reviewable P24-001 control-plane implementation parts fail-closed."""
from __future__ import annotations

import fnmatch
from pathlib import Path
import stat
import subprocess
from typing import Sequence


class PartLoadError(RuntimeError):
    """Raised before any split control-plane source is executed."""


def _git(project: Path, *args: str) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            ["git", *args],
            cwd=project,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        detail = getattr(error, "stderr", "") or str(error)
        raise PartLoadError(f"git verification failed: {detail.strip()}") from error


def _load_tracked_part_sources(
    entry_file: str,
    directory_name: str,
    expected_names: Sequence[str],
) -> tuple[str, ...]:
    """Return exact committed split parts in allowlist order, before execution."""
    entry = Path(entry_file)
    project = entry.resolve().parent.parent
    parts = entry.with_name(directory_name)

    top = Path(_git(project, "rev-parse", "--show-toplevel").stdout.strip()).resolve()
    if top != project:
        raise PartLoadError(f"unexpected repository root: {top} != {project}")
    if parts.is_symlink():
        raise PartLoadError(f"part directory may not be a symlink: {parts}")
    try:
        mode = parts.lstat().st_mode
    except OSError as error:
        raise PartLoadError(f"cannot inspect part directory {parts}: {error}") from error
    if not stat.S_ISDIR(mode):
        raise PartLoadError(f"part directory is not a directory: {parts}")

    expected = tuple(expected_names)
    if len(expected) != len(set(expected)):
        raise PartLoadError("expected part allowlist contains duplicate names")
    if any(not fnmatch.fnmatchcase(name, "part*.inc") for name in expected):
        raise PartLoadError("expected part allowlist contains an invalid filename")

    try:
        actual = sorted(
            path.name
            for path in parts.iterdir()
            if fnmatch.fnmatchcase(path.name, "part*.inc")
        )
    except OSError as error:
        raise PartLoadError(f"cannot enumerate part directory {parts}: {error}") from error

    wanted = sorted(expected)
    if actual != wanted:
        missing = sorted(set(wanted) - set(actual))
        extra = sorted(set(actual) - set(wanted))
        raise PartLoadError(
            f"split-part allowlist mismatch: missing={missing or 'none'} extra={extra or 'none'}"
        )

    source: list[str] = []
    for name in expected:
        path = parts / name
        if path.is_symlink():
            raise PartLoadError(f"split part may not be a symlink: {path}")
        try:
            mode = path.lstat().st_mode
        except OSError as error:
            raise PartLoadError(f"cannot inspect split part {path}: {error}") from error
        if not stat.S_ISREG(mode):
            raise PartLoadError(f"split part is not a regular file: {path}")

        resolved = path.resolve(strict=True)
        try:
            relative = resolved.relative_to(project).as_posix()
        except ValueError as error:
            raise PartLoadError(f"split part escapes repository: {path}") from error

        tracked = _git(project, "ls-files", "--error-unmatch", "--", relative).stdout.strip()
        if tracked.replace("\\", "/") != relative:
            raise PartLoadError(f"split part tracking identity mismatch: {relative}")
        try:
            subprocess.run(
                ["git", "diff", "--quiet", "--no-ext-diff", "HEAD", "--", relative],
                cwd=project,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )
        except (OSError, subprocess.CalledProcessError) as error:
            raise PartLoadError(
                f"split part differs from committed HEAD and will not execute: {relative}"
            ) from error
        try:
            source.append(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError) as error:
            raise PartLoadError(f"cannot read UTF-8 split part {relative}: {error}") from error
    return tuple(source)


def _load_tracked_parts(
    entry_file: str,
    directory_name: str,
    expected_names: Sequence[str],
) -> str:
    """Compatibility helper used by the regression loader and security tests."""
    return "".join(
        _load_tracked_part_sources(entry_file, directory_name, expected_names)
    )


_ALLOWED_EVIDENCE_CLASSIFICATIONS = frozenset(
    {
        "PROPOSED_ADOPTION_REVIEW_ADR",
        "PROPOSED_RECONCILIATION_MATRIX",
        "SOURCE_FOUNDATION",
        "SOURCE_ONLY",
        "HOSTED_CI",
    }
)
_HIGH_SUPPORT_STATUSES = frozenset(
    {"BEHAVIOR_SUPPORTED", "PLATFORM_SUPPORTED", "RELEASE_SUPPORTED"}
)


def _apply_task_record_evidence_guard(state: object) -> None:
    """Prevent submitter-defined evidence labels from manufacturing acceptance."""
    records = getattr(state, "contract", {}).get("taskRecords")
    if not isinstance(records, list):
        return
    commit, tree = current_git_binding(getattr(state, "project"))
    for index, raw in enumerate(records):
        if not isinstance(raw, dict):
            continue
        task_id = str(raw.get("task", f"taskRecords[{index}]"))
        evidence = raw.get("evidenceBindings")
        bindings = evidence if isinstance(evidence, list) else []
        for evidence_index, binding in enumerate(bindings):
            if not isinstance(binding, dict):
                continue
            classification = binding.get("classification")
            if classification not in _ALLOWED_EVIDENCE_CLASSIFICATIONS:
                add_issue(
                    state,
                    "evidence_classification_invalid",
                    f"{task_id}.evidenceBindings[{evidence_index}] uses ungoverned classification {classification!r}",
                    subject=task_id,
                )

        high_assurance_claim = (
            raw.get("completionClaim") is True
            or raw.get("roadmapStatus") == "DONE"
            or raw.get("certificationStatus") == "PASS"
            or raw.get("capabilitySupportStatus") in _HIGH_SUPPORT_STATUSES
        )
        if not high_assurance_claim:
            continue

        add_issue(
            state,
            "evidence_assurance_unavailable",
            (
                f"{task_id} requests completion/certification/support from a P24 evidence "
                "vocabulary that is intentionally limited to proposal, source, and hosted-CI evidence"
            ),
            subject=task_id,
        )
        for evidence_index, binding in enumerate(bindings):
            if not isinstance(binding, dict):
                continue
            digest = binding.get("sha256")
            if not isinstance(digest, str) or SHA256_RE.fullmatch(digest) is None:
                add_issue(
                    state,
                    "evidence_hash_required",
                    f"{task_id}.evidenceBindings[{evidence_index}] requires immutable sha256 for an assurance-bearing claim",
                    subject=task_id,
                )

        review = raw.get("reviewBinding")
        if not isinstance(review, dict):
            add_issue(
                state,
                "review_binding_required",
                f"{task_id} assurance-bearing claim requires an exact PASS reviewBinding",
                subject=task_id,
            )
            continue
        if review.get("decision") != "PASS":
            add_issue(
                state,
                "review_binding_required",
                f"{task_id} assurance-bearing claim requires reviewBinding.decision=PASS",
                subject=task_id,
            )
        if commit and tree and (
            review.get("commit") != commit or review.get("tree") != tree
        ):
            add_issue(
                state,
                "review_binding_stale",
                f"{task_id} assurance-bearing reviewBinding does not match current candidate",
                subject=task_id,
            )


_EXPECTED_PARTS = (
    "part01.inc",
    "part02.inc",
    "part03.inc",
    "part04.inc",
    "part05.inc",
    "part05b.inc",
    "part05c.inc",
    "part05d.inc",
    "part06.inc",
)
_PART_SOURCES = _load_tracked_part_sources(
    __file__,
    "anarchy_control_plane_parts",
    _EXPECTED_PARTS,
)

# Load every definition except the CLI tail, then install the fail-closed evidence
# policy before part06 can invoke main() when this file is executed directly.
exec(compile("".join(_PART_SOURCES[:-1]), __file__, "exec"), globals(), globals())

_BASE_VALIDATE_TASK_RECORDS = validate_task_records


def validate_task_records(state: ValidationState) -> None:
    _BASE_VALIDATE_TASK_RECORDS(state)
    _apply_task_record_evidence_guard(state)


exec(compile(_PART_SOURCES[-1], __file__, "exec"), globals(), globals())
