#!/usr/bin/env python3
"""P24-001 deterministic ANARCHY adoption-review control-plane validator.

Scope is intentionally limited to P24-001 migration/execution-control records.
The tool does not replace docs/roadmap/roadmap.yaml and does not define Worker
B's Test Center, Project Test Profile, Testing Studio, or certification system.

--check is strictly read-only. --write atomically refreshes only the generated
paths declared by the P24 control contract. --report writes an explicit runtime
report. SOURCE_MANIFEST.sha256 remains owned by p1a_refresh_source_manifest.py.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass, asdict
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tempfile
from typing import Any, Iterable, Mapping, Sequence

TOOL_VERSION = "1.0.0"
CONTRACT_PATH = "docs/roadmap/anarchy/migration/P24-001_CONTROL_PLANE.json"
SCHEMA_PATH = "schemas/anarchy_execution.schema.json"
SOURCE_MANIFEST_PATH = "SOURCE_MANIFEST.sha256"

ROADMAP_TASK_STATUSES = ("NOT_STARTED", "READY", "IN_PROGRESS", "BLOCKED", "REVIEW", "DONE", "DEFERRED")
WORKER_RUNTIME_STATUSES = (
    "AVAILABLE", "CLAIMING", "BASELINING", "IMPLEMENTING", "VERIFYING",
    "WAITING_FOR_REVIEW", "REPAIRING", "READY_TO_MERGE", "INTEGRATING",
    "YIELDED", "CAPABILITY_BLOCKED",
)
TEST_EXECUTION_RESULTS = (
    "PASS", "FAIL", "BLOCKED", "SKIPPED_NOT_APPLICABLE", "SKIPPED_WITH_REASON",
    "FLAKY_QUARANTINED", "UNKNOWN_RECONCILIATION_REQUIRED", "CANCELLED",
)
CERTIFICATION_STATUSES = ("NOT_EVALUATED", "PARTIAL", "PASS", "FAIL", "STALE", "REVOKED")
CAPABILITY_SUPPORT_STATUSES = (
    "NOT_IMPLEMENTED", "SOURCE_FOUNDATION", "EXPERIMENTAL", "BEHAVIOR_SUPPORTED",
    "PLATFORM_SUPPORTED", "RELEASE_SUPPORTED", "DEGRADED", "UNSUPPORTED", "REVOKED",
)
COORDINATION_STATUSES = ("ACTIVE", "READY", "HOLD", "BLOCKED", "YIELDED")
CLAIM_STATUSES = ("CLAIMED", "YIELDED", "TAKEN_OVER", "CLOSED", "REVOKED")
REVIEW_DECISIONS = ("PASS", "REQUEST_CHANGES", "BLOCKED_BY_CONTRACT", "BLOCKED_EXTERNAL")
DIRECTIVE_DECISIONS = ("ACCEPT", "ACCEPT_WITH_CHANGES", "REJECT", "DEFER")
ADOPTION_CLASSIFICATIONS = ("ADOPTION_REVIEW", "ADOPTION_READY")
STATE_DOMAIN_VALUES: Mapping[str, tuple[str, ...]] = {
    "RoadmapTaskStatus": ROADMAP_TASK_STATUSES,
    "WorkerRuntimeStatus": WORKER_RUNTIME_STATUSES,
    "TestExecutionResult": TEST_EXECUTION_RESULTS,
    "CertificationStatus": CERTIFICATION_STATUSES,
    "CapabilitySupportStatus": CAPABILITY_SUPPORT_STATUSES,
}

TASK_ID_RE = re.compile(r"^P(?P<phase>(?:[0-9]|1[0-9]|2[0-4]))-(?P<number>[0-9]{3})$")
TASK_TOKEN_RE = re.compile(r"P(?:[0-9]|1[0-9]|2[0-4])-[0-9]{3}")
TASK_TOKEN_LOOSE_RE = re.compile(r"P[0-9]+-[0-9]{3}")
PHASE_ID_RE = re.compile(r"^P(?:[0-9]|1[0-9]|2[0-4])$")
WORKER_ID_RE = re.compile(r"^[A-J]$")
SHA1_RE = re.compile(r"^[0-9a-f]{40}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
DIRECTIVE_ID_RE = re.compile(r"^(?:ANARCHY|V32)-DIR-[0-9]{3}$")
TASK_TABLE_HEADER = "| ID | Task | Depends on | Required output | Done when |"
TASK_TABLE_SEPARATOR = "|---|---|---|---|---|"
MAX_CONTROL_BYTES = 2 * 1024 * 1024
MAX_TASKS = 5000
MAX_PHASES = 64
MAX_WORKERS = 64
MAX_EDGES = 20000


class ControlPlaneError(RuntimeError):
    pass


@dataclass(frozen=True)
class Issue:
    severity: str
    code: str
    message: str
    path: str | None = None
    subject: str | None = None

    def as_dict(self) -> dict[str, object]:
        return asdict(self)


@dataclass(frozen=True)
class Task:
    task_id: str
    phase: str
    title: str
    dependencies: tuple[str, ...]
    required_output: str
    done_when: str
    packet: str


@dataclass(frozen=True)
class Phase:
    phase: str
    path: str
    title: str
    task_ids: tuple[str, ...]
    sha256: str


@dataclass(frozen=True)
class Worker:
    worker: str
    path: str
    role: str
    branch: str
    active_task: str
    reviewer: str
    phase_links: tuple[str, ...]
    sha256: str


@dataclass(frozen=True)
class Claim:
    path: str
    task: str
    worker: str
    state: str
    branch: str
    claimed_paths: tuple[str, ...]
    shared_contracts: tuple[str, ...]
    data: Mapping[str, Any]

    @property
    def active(self) -> bool:
        return self.state in {"CLAIMED", "TAKEN_OVER"}


@dataclass
class ValidationState:
    project: Path
    contract: dict[str, Any]
    phases: list[Phase]
    tasks: dict[str, Task]
    workers: dict[str, Worker]
    claims: list[Claim]
    issues: list[Issue]
    blockers: list[str]
    coordination: dict[str, Any] | None = None
    directive_matrix: dict[str, Any] | None = None
    migration_ledger: dict[str, Any] | None = None
    generated_status: str = "NOT_CHECKED"
    source_manifest_status: str = "NOT_CHECKED"

    @property
    def errors(self) -> list[Issue]:
        return [issue for issue in self.issues if issue.severity == "error"]

    @property
    def passed(self) -> bool:
        return not self.errors


def duplicate_guard(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ControlPlaneError(f"duplicate object key: {key}")
        result[key] = value
    return result


def canonical_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def file_sha256(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def safe_relative(value: str) -> bool:
    if not isinstance(value, str) or not value or "\\" in value or "\x00" in value:
        return False
    pure = PurePosixPath(value)
    return not pure.is_absolute() and ".." not in pure.parts and pure.as_posix() == value


def safe_pattern(value: str) -> bool:
    if not isinstance(value, str) or not value or "\\" in value or "\x00" in value:
        return False
    pure = PurePosixPath(value)
    return not pure.is_absolute() and ".." not in pure.parts


def resolve_safe(project: Path, relative: str, *, must_exist: bool = False) -> Path:
    if not safe_relative(relative):
        raise ControlPlaneError(f"unsafe repository-relative path: {relative!r}")
    path = (project / relative).resolve()
    try:
        path.relative_to(project)
    except ValueError as error:
        raise ControlPlaneError(f"path escapes repository: {relative}") from error
    if must_exist and not path.exists():
        raise ControlPlaneError(f"required path is missing: {relative}")
    return path


def read_bounded(path: Path, limit: int = MAX_CONTROL_BYTES) -> bytes:
    try:
        size = path.stat().st_size
        if size > limit:
            raise ControlPlaneError(f"file exceeds {limit} bytes: {path}")
        return path.read_bytes()
    except OSError as error:
        raise ControlPlaneError(f"cannot read {path}: {error}") from error


def load_json(path: Path) -> dict[str, Any]:
    raw = read_bounded(path, 16 * 1024 * 1024)
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=duplicate_guard)
    except (UnicodeDecodeError, json.JSONDecodeError, ControlPlaneError) as error:
        raise ControlPlaneError(f"cannot parse JSON-subset file {path}: {error}") from error
    if not isinstance(value, dict):
        raise ControlPlaneError(f"JSON-subset root must be an object: {path}")
    return value


def parse_front_matter(path: Path) -> tuple[dict[str, Any], str]:
    raw = read_bounded(path)
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ControlPlaneError(f"file is not UTF-8: {path}") from error
    if "\r" in text:
        raise ControlPlaneError(f"control Markdown must use LF line endings: {path}")
    lines = text.split("\n")
    if not lines or lines[0] != "---":
        raise ControlPlaneError(f"missing opening front matter: {path}")
    try:
        end = lines.index("---", 1)
    except ValueError as error:
        raise ControlPlaneError(f"missing closing front matter: {path}") from error
    meta: dict[str, Any] = {}
    for line_no, line in enumerate(lines[1:end], start=2):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if ":" not in line:
            raise ControlPlaneError(f"invalid front matter {path}:{line_no}")
        key, raw_value = line.split(":", 1)
        key = key.strip()
        raw_value = raw_value.strip()
        if not re.fullmatch(r"[a-z][a-z0-9_]*", key):
            raise ControlPlaneError(f"invalid front matter key {path}:{line_no}: {key!r}")
        if key in meta:
            raise ControlPlaneError(f"duplicate front matter key {path}:{line_no}: {key}")
        if raw_value.startswith("[") and raw_value.endswith("]"):
            inner = raw_value[1:-1].strip()
            meta[key] = [] if not inner else [part.strip().strip('"\'') for part in inner.split(",")]
        elif len(raw_value) >= 2 and raw_value[0] == raw_value[-1] and raw_value[0] in {'"', "'"}:
            meta[key] = raw_value[1:-1]
        else:
            meta[key] = raw_value
    return meta, "\n".join(lines[end + 1 :])


def normalize_cell(value: str) -> str:
    return re.sub(r"\s+", " ", value.replace("`", "")).strip()


def expand_range(start: str, end: str) -> list[str]:
    left = TASK_ID_RE.fullmatch(start)
    right = TASK_ID_RE.fullmatch(end)
    if left is None or right is None or left.group("phase") != right.group("phase"):
        raise ControlPlaneError(f"invalid dependency range: {start} through {end}")
    first = int(left.group("number"))
    last = int(right.group("number"))
    if first > last or last - first > MAX_TASKS:
        raise ControlPlaneError(f"unsafe dependency range: {start} through {end}")
    return [f"P{left.group('phase')}-{number:03d}" for number in range(first, last + 1)]


def parse_dependencies(cell: str) -> tuple[str, ...]:
    text = normalize_cell(cell)
    if text.lower() in {"none", "n/a", "not applicable"}:
        return ()
    found: list[str] = []
    spans: list[tuple[int, int]] = []
    range_re = re.compile(
        r"(?P<a>P(?:[0-9]|1[0-9]|2[0-4])-[0-9]{3})\s+(?:through|to)\s+"
        r"(?P<b>P(?:[0-9]|1[0-9]|2[0-4])-[0-9]{3})",
        flags=re.I,
    )
    for match in range_re.finditer(text):
        found.extend(expand_range(match.group("a"), match.group("b")))
        spans.append(match.span())
    masked = list(text)
    for start, end in spans:
        masked[start:end] = " " * (end - start)
    remainder = "".join(masked)
    found.extend(match.group(0) for match in TASK_TOKEN_LOOSE_RE.finditer(remainder))
    residue = TASK_TOKEN_LOOSE_RE.sub(" ", remainder)
    residue = re.sub(r"\b(?:and|through|to|from|all|tasks?)\b", " ", residue, flags=re.I)
    residue = re.sub(r"[\s,;/+&()\[\]-]+", "", residue)
    if residue:
        raise ControlPlaneError(f"unsupported dependency syntax: {cell!r}")
    if not found:
        raise ControlPlaneError(f"dependency cell has no task IDs: {cell!r}")
    return tuple(dict.fromkeys(found))

