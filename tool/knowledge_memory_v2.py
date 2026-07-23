#!/usr/bin/env python3
"""Deterministic v1.8 knowledge, memory, skill, and object-store helpers."""
from __future__ import annotations

from dataclasses import dataclass, field
import datetime as dt
import hashlib
import json
from pathlib import Path
import re

VERSION = "1.9.0+190"

ALLOWED_SKILL_TOOLS = {
    "read_file",
    "inspect_file",
    "write_file",
    "run_command",
    "verify_project",
}


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_text(value: str) -> str:
    return sha256_hex(value.encode("utf-8"))


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def _tokenize(value: str) -> list[str]:
    return re.findall(r"[a-z0-9_./-]+", value.lower())


@dataclass(frozen=True)
class StoredObject:
    sha256: str
    relative_path: str
    media_type: str
    size_bytes: int
    created_at: str
    labels: dict[str, str] = field(default_factory=dict)

    def to_json(self) -> dict[str, object]:
        return {
            "schemaVersion": "1.0.0",
            "sha256": self.sha256,
            "relativePath": self.relative_path,
            "mediaType": self.media_type,
            "sizeBytes": self.size_bytes,
            "createdAt": self.created_at,
            "labels": dict(sorted(self.labels.items())),
        }


class ObjectStore:
    def __init__(self, root: Path) -> None:
        self.root = root

    def relative_path(self, sha256: str, *, extension: str = "") -> str:
        clean = re.sub(r"[^a-f0-9]", "", sha256.lower())
        suffix = f".{extension.strip('.').lower()}" if extension.strip('.') else ""
        return f"sha256/{clean[:2]}/{clean[2:4]}/{clean}{suffix}"

    def put_bytes(
        self,
        data: bytes,
        *,
        media_type: str,
        extension: str = "",
        labels: dict[str, str] | None = None,
    ) -> StoredObject:
        self.root.mkdir(parents=True, exist_ok=True)
        digest = sha256_hex(data)
        relative = self.relative_path(digest, extension=extension)
        target = self.root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists():
            target.write_bytes(data)
        stored = StoredObject(
            sha256=digest,
            relative_path=relative,
            media_type=media_type,
            size_bytes=len(data),
            created_at=utc_now(),
            labels=labels or {},
        )
        manifest = target.with_suffix(target.suffix + '.json')
        if not manifest.exists():
            manifest.write_text(
                json.dumps(stored.to_json(), indent=2, sort_keys=True) + "\n",
                encoding='utf-8',
            )
        return stored

    def put_text(
        self,
        text: str,
        *,
        media_type: str = 'text/plain',
        extension: str = 'txt',
        labels: dict[str, str] | None = None,
    ) -> StoredObject:
        return self.put_bytes(
            text.encode('utf-8'),
            media_type=media_type,
            extension=extension,
            labels=labels,
        )


@dataclass(frozen=True)
class Episode:
    id: str
    project_id: str
    run_id: str
    request: str
    outcome: str
    summary: str
    failure: str
    lessons: str
    files_changed: tuple[str, ...]
    evidence_hashes: tuple[str, ...]
    completed_items: tuple[str, ...] = ()
    failed_items: tuple[str, ...] = ()
    tags: tuple[str, ...] = ()
    mutations: int = 0
    tool_calls: int = 0
    pinned: bool = False
    completed_at: str = ""


@dataclass(frozen=True)
class MemoryAdmissionDecision:
    status: str
    reason: str
    retrieval_allowed: bool
    candidate_skill: bool
    diagnostic_only: bool


class MemoryAdmissionPolicy:
    def __init__(
        self,
        *,
        require_evidence_hashes: bool = True,
        quarantine_unsuccessful_runs: bool = True,
        promote_successful_mutations: bool = True,
    ) -> None:
        self.require_evidence_hashes = require_evidence_hashes
        self.quarantine_unsuccessful_runs = quarantine_unsuccessful_runs
        self.promote_successful_mutations = promote_successful_mutations

    def evaluate(self, episode: Episode) -> MemoryAdmissionDecision:
        if episode.pinned:
            return MemoryAdmissionDecision('admitted', 'pinned memory remains retrievable', True, False, False)
        if self.require_evidence_hashes and not episode.evidence_hashes:
            return MemoryAdmissionDecision('rejected', 'memory admission requires evidence hashes', False, False, False)
        conversational = self._looks_conversational(episode.request) and not episode.files_changed and not episode.completed_items
        if conversational:
            return MemoryAdmissionDecision('rejected', 'conversational turns do not enter semantic memory', False, False, False)
        if episode.outcome == 'succeeded':
            reusable = bool(episode.files_changed or episode.completed_items) and (episode.mutations > 0 or episode.tool_calls >= 2)
            return MemoryAdmissionDecision(
                'admitted',
                'successful governed run with evidence enters semantic memory',
                True,
                reusable and self.promote_successful_mutations,
                False,
            )
        if self.quarantine_unsuccessful_runs:
            return MemoryAdmissionDecision(
                'quarantined',
                'unsuccessful run is preserved as diagnostic-only memory',
                False,
                False,
                True,
            )
        return MemoryAdmissionDecision('rejected', 'unsuccessful runs are not retained in retrieval memory', False, False, False)

    @staticmethod
    def _looks_conversational(request: str) -> bool:
        lowered = request.lower()
        return any(token in lowered for token in ('what is', 'tell me', 'who is', 'summarize', 'explain'))


@dataclass(frozen=True)
class FreshnessAssessment:
    state: str
    age_days: int
    warning: str


class ResearchFreshnessPolicy:
    def __init__(self, *, fresh_days: int = 30, aging_days: int = 180, citation_required: bool = True) -> None:
        self.fresh_days = fresh_days
        self.aging_days = aging_days
        self.citation_required = citation_required

    def evaluate(self, captured_at: dt.datetime, *, now: dt.datetime | None = None) -> FreshnessAssessment:
        reference = now or dt.datetime.now(dt.timezone.utc)
        age_days = max(0, int((reference - captured_at).total_seconds() // 86400))
        if age_days <= self.fresh_days:
            return FreshnessAssessment('fresh', age_days, 'citation required')
        if age_days <= self.aging_days:
            return FreshnessAssessment('aging', age_days, 'cite capture date when using this source')
        return FreshnessAssessment('stale', age_days, 'stale research requires an explicit warning and citation')


@dataclass(frozen=True)
class SkillCandidate:
    id: str
    project_id: str
    source_episode_id: str
    title: str
    instructions: str
    triggers: tuple[str, ...]
    recommended_tools: tuple[str, ...]
    evidence_hashes: tuple[str, ...]
    candidate_hash: str
    created_at: str

    def to_json(self) -> dict[str, object]:
        return {
            'schemaVersion': '1.0.0',
            'id': self.id,
            'projectId': self.project_id,
            'sourceEpisodeId': self.source_episode_id,
            'title': self.title,
            'instructions': self.instructions,
            'triggers': list(self.triggers),
            'recommendedTools': list(self.recommended_tools),
            'evidenceHashes': list(self.evidence_hashes),
            'candidateHash': self.candidate_hash,
            'createdAt': self.created_at,
        }


@dataclass(frozen=True)
class PublishedSkill:
    id: str
    candidate_id: str
    version: int
    title: str
    instructions: str
    recommended_tools: tuple[str, ...]
    approval_note: str
    manifest_hash: str
    published_at: str

    def to_json(self) -> dict[str, object]:
        return {
            'schemaVersion': '1.0.0',
            'id': self.id,
            'candidateId': self.candidate_id,
            'version': self.version,
            'title': self.title,
            'instructions': self.instructions,
            'recommendedTools': list(self.recommended_tools),
            'approvalNote': self.approval_note,
            'manifestHash': self.manifest_hash,
            'publishedAt': self.published_at,
        }


def extract_skill_candidate(episode: Episode, decision: MemoryAdmissionDecision) -> SkillCandidate | None:
    if not decision.candidate_skill:
        return None
    triggers = tuple(sorted({token for token in _tokenize(episode.request) if token not in {'the', 'and', 'for', 'with', 'from'}}))[:8]
    tools = {'read_file', 'inspect_file', 'verify_project'}
    if episode.mutations > 0:
        tools.add('write_file')
    if episode.tool_calls >= 2:
        tools.add('run_command')
    title = episode.request.strip()[:120] or 'Governed procedure'
    instructions = '\n'.join(
        part for part in (
            f'Objective: {episode.request.strip()}',
            f'Summary: {episode.summary.strip()}' if episode.summary.strip() else '',
            f'Lessons: {episode.lessons.strip()}' if episode.lessons.strip() else '',
            f"Changed files: {', '.join(episode.files_changed)}" if episode.files_changed else '',
        )
        if part
    )
    payload = {
        'projectId': episode.project_id,
        'sourceEpisodeId': episode.id,
        'title': title,
        'instructions': instructions,
        'triggers': list(triggers),
        'recommendedTools': sorted(tools),
        'evidenceHashes': list(episode.evidence_hashes),
    }
    return SkillCandidate(
        id=f'skill_candidate_{sha256_text(episode.id)[:12]}',
        project_id=episode.project_id,
        source_episode_id=episode.id,
        title=title,
        instructions=instructions,
        triggers=triggers,
        recommended_tools=tuple(sorted(tools)),
        evidence_hashes=episode.evidence_hashes,
        candidate_hash=sha256_text(canonical_json(payload)),
        created_at=utc_now(),
    )


def evaluate_skill_candidate(
    candidate: SkillCandidate,
    *,
    replay_passed: bool,
    approval_required: bool = True,
) -> dict[str, object]:
    issues: list[str] = []
    if not candidate.evidence_hashes:
        issues.append('candidate_missing_evidence')
    if any(tool not in ALLOWED_SKILL_TOOLS for tool in candidate.recommended_tools):
        issues.append('candidate_permission_expansion')
    if not replay_passed:
        issues.append('candidate_replay_required')
    if approval_required:
        issues.append('candidate_requires_approval')
    return {
        'candidateId': candidate.id,
        'passed': not issues,
        'issues': issues,
        'evaluationHash': sha256_text(canonical_json({
            'candidateHash': candidate.candidate_hash,
            'replayPassed': replay_passed,
            'approvalRequired': approval_required,
            'issues': issues,
        })),
    }


def publish_skill(
    candidate: SkillCandidate,
    *,
    approval_note: str,
    replay_passed: bool,
    version: int = 1,
) -> PublishedSkill:
    if not replay_passed:
        raise ValueError('replay_passed must be true before publication')
    if not approval_note.strip():
        raise ValueError('approval_note is required')
    if any(tool not in ALLOWED_SKILL_TOOLS for tool in candidate.recommended_tools):
        raise ValueError('candidate expands permissions')
    manifest = {
        'candidateId': candidate.id,
        'title': candidate.title,
        'instructions': candidate.instructions,
        'recommendedTools': list(candidate.recommended_tools),
        'approvalNote': approval_note.strip(),
        'version': version,
    }
    return PublishedSkill(
        id=f'published_skill_{sha256_text(candidate.id + str(version))[:12]}',
        candidate_id=candidate.id,
        version=version,
        title=candidate.title,
        instructions=candidate.instructions,
        recommended_tools=candidate.recommended_tools,
        approval_note=approval_note.strip(),
        manifest_hash=sha256_text(canonical_json(manifest)),
        published_at=utc_now(),
    )
