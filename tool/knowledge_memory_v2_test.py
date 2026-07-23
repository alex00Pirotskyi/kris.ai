#!/usr/bin/env python3
"""Executable v1.8 knowledge, memory, skill, and freshness gates."""
from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import json
import os
from pathlib import Path
import tempfile
import time

import knowledge_memory_v2 as km


@dataclasses.dataclass
class Result:
    name: str
    passed: bool
    detail: str
    durationMs: int



def duration_ms(started: float) -> int:
    if "SOURCE_DATE_EPOCH" in os.environ:
        return 0
    return int((time.monotonic() - started) * 1000)

def case(name, action, results):
    started = time.monotonic()
    try:
        detail = action()
        results.append(Result(name, True, detail, duration_ms(started)))
    except Exception as exc:  # noqa: BLE001
        results.append(Result(name, False, f"{type(exc).__name__}: {exc}", duration_ms(started)))


def require(condition, detail):
    if not condition:
        raise AssertionError(detail)
    return detail


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--json-output', type=Path)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    results: list[Result] = []

    with tempfile.TemporaryDirectory(prefix='kristin-v180-') as tmp:
        store = km.ObjectStore(Path(tmp) / 'objects')
        episode_ok = km.Episode(
            id='ep-success', project_id='project-a', run_id='run-1', request='Repair the build pipeline and package the app', outcome='succeeded',
            summary='Updated the build profile and package output passed validation.', failure='', lessons='Use the retained snapshot and verify the artifact before packaging.',
            files_changed=('kristin.project.json', 'tool/release.py'), evidence_hashes=('a'*64, 'b'*64), completed_items=('Build', 'Package'), tags=('episode', 'fix'),
            mutations=2, tool_calls=4,
        )
        episode_fail = km.Episode(
            id='ep-fail', project_id='project-a', run_id='run-2', request='Run the preview server', outcome='failed',
            summary='', failure='Port collision prevented startup.', lessons='Preview ports need explicit reservation.', files_changed=(), evidence_hashes=('c'*64,), failed_items=('Run',), tags=('episode', 'failed'),
            mutations=0, tool_calls=2,
        )
        policy = km.MemoryAdmissionPolicy()

        case('Object store writes deterministic sha256 paths', lambda: _object_store_case(store), results)
        case('Successful governed episode is admitted', lambda: _admit_success_case(policy, episode_ok), results)
        case('Failed run is quarantined', lambda: _quarantine_case(policy, episode_fail), results)
        case('Conversational turn is rejected', lambda: _conversational_case(policy), results)
        case('Pinned diagnostic memory bypasses quarantine', lambda: _pinned_case(policy, episode_fail), results)
        case('Freshness policy distinguishes fresh aging and stale', _freshness_case, results)
        case('Skill candidate extraction requires admitted reusable work', lambda: _skill_extract_case(policy, episode_ok), results)
        case('Skill publication blocks permission expansion', _permission_expansion_case, results)
        case('Skill publication requires replay pass', lambda: _publish_case(policy, episode_ok), results)
        case('Object store manifest is stable', lambda: _manifest_case(store), results)
        case('Evidence hashes are required for admission', lambda: _missing_evidence_case(policy), results)
        case('Skill approval remains explicit', lambda: _approval_case(policy, episode_ok), results)

    payload = {
        'version': km.VERSION,
        'passed': all(item.passed for item in results),
        'passedCount': sum(item.passed for item in results),
        'caseCount': len(results),
        'results': [dataclasses.asdict(item) for item in results],
    }
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding='utf-8')
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload['passed'] else 1


def _object_store_case(store: km.ObjectStore) -> str:
    item = store.put_text('hello knowledge', extension='txt', labels={'kind': 'note'})
    return require(item.relative_path.startswith('sha256/'), f'object stored at {item.relative_path}')


def _admit_success_case(policy: km.MemoryAdmissionPolicy, episode: km.Episode) -> str:
    decision = policy.evaluate(episode)
    return require(decision.status == 'admitted' and decision.candidate_skill, 'successful mutation episode is admitted and reusable')


def _quarantine_case(policy: km.MemoryAdmissionPolicy, episode: km.Episode) -> str:
    decision = policy.evaluate(episode)
    return require(decision.status == 'quarantined' and decision.diagnostic_only and not decision.retrieval_allowed, 'failed run is diagnostic-only')


def _conversational_case(policy: km.MemoryAdmissionPolicy) -> str:
    episode = km.Episode(id='ep-chat', project_id='p', run_id='r', request='What is the project status?', outcome='succeeded', summary='Answered a question.', failure='', lessons='No durable decision.', files_changed=(), evidence_hashes=('d'*64,), tool_calls=1)
    decision = policy.evaluate(episode)
    return require(decision.status == 'rejected', 'conversational request does not enter semantic memory')


def _pinned_case(policy: km.MemoryAdmissionPolicy, episode: km.Episode) -> str:
    decision = policy.evaluate(dataclasses.replace(episode, pinned=True))
    return require(decision.status == 'admitted' and decision.retrieval_allowed, 'pinned memory remains retrievable')


def _freshness_case() -> str:
    policy = km.ResearchFreshnessPolicy(fresh_days=7, aging_days=30)
    now = dt.datetime(2026, 7, 22, tzinfo=dt.timezone.utc)
    fresh = policy.evaluate(now - dt.timedelta(days=3), now=now)
    aging = policy.evaluate(now - dt.timedelta(days=15), now=now)
    stale = policy.evaluate(now - dt.timedelta(days=90), now=now)
    return require((fresh.state, aging.state, stale.state) == ('fresh', 'aging', 'stale'), 'freshness tiers are stable')


def _skill_extract_case(policy: km.MemoryAdmissionPolicy, episode: km.Episode) -> str:
    candidate = km.extract_skill_candidate(episode, policy.evaluate(episode))
    return require(candidate is not None and candidate.recommended_tools and candidate.evidence_hashes, 'candidate extracted with tools and evidence')


def _permission_expansion_case() -> str:
    candidate = km.SkillCandidate(id='c', project_id='p', source_episode_id='e', title='Unsafe', instructions='test', triggers=('unsafe',), recommended_tools=('rm_everything',), evidence_hashes=('e'*64,), candidate_hash='f'*64, created_at=km.utc_now())
    evaluation = km.evaluate_skill_candidate(candidate, replay_passed=True)
    return require('candidate_permission_expansion' in evaluation['issues'], 'unknown tool blocks publication')


def _publish_case(policy: km.MemoryAdmissionPolicy, episode: km.Episode) -> str:
    candidate = km.extract_skill_candidate(episode, policy.evaluate(episode))
    assert candidate is not None
    published = km.publish_skill(candidate, approval_note='Reviewed and approved.', replay_passed=True)
    return require(bool(published.manifest_hash) and published.version == 1, 'publish creates stable manifest hash')


def _manifest_case(store: km.ObjectStore) -> str:
    first = store.put_text('same content', extension='txt')
    second = store.put_text('same content', extension='txt')
    return require(first.sha256 == second.sha256 and first.relative_path == second.relative_path, 'identical content deduplicates')


def _missing_evidence_case(policy: km.MemoryAdmissionPolicy) -> str:
    episode = km.Episode(id='ep-noev', project_id='p', run_id='r', request='Repair build', outcome='succeeded', summary='Did work', failure='', lessons='Need evidence', files_changed=('a.txt',), evidence_hashes=(), mutations=1)
    decision = policy.evaluate(episode)
    return require(decision.status == 'rejected', 'evidence hashes are required')


def _approval_case(policy: km.MemoryAdmissionPolicy, episode: km.Episode) -> str:
    candidate = km.extract_skill_candidate(episode, policy.evaluate(episode))
    assert candidate is not None
    evaluation = km.evaluate_skill_candidate(candidate, replay_passed=True, approval_required=True)
    return require('candidate_requires_approval' in evaluation['issues'], 'candidate remains approval-gated')


if __name__ == '__main__':
    raise SystemExit(main())
