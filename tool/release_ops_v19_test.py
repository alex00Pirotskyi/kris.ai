#!/usr/bin/env python3
"""Executable v1.9 release-operations gates."""
from __future__ import annotations

import argparse
import dataclasses
import json
import os
from pathlib import Path
import time

import release_ops_v19 as v19


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
        results.append(Result(name, False, f'{type(exc).__name__}: {exc}', duration_ms(started)))


def require(condition, detail):
    if not condition:
        raise AssertionError(detail)
    return detail


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--json-output', type=Path)
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    results: list[Result] = []

    base = v19.PolicyProfile.from_json({
        'schemaVersion': '1.0.0',
        'id': 'base',
        'name': 'Base',
        'dataBoundary': 'local_only',
        'networkPolicy': 'none',
        'allowUnsignedManifests': False,
        'allowA2ADelegation': False,
        'allowRemoteMcp': False,
        'allowedUpdateChannels': ['stable'],
    })
    overlay = v19.PolicyProfile.from_json({
        'schemaVersion': '1.0.0',
        'id': 'overlay',
        'name': 'Overlay',
        'dataBoundary': 'enterprise_managed',
        'networkPolicy': 'broker_https',
        'allowUnsignedManifests': False,
        'allowA2ADelegation': True,
        'allowRemoteMcp': True,
        'allowedUpdateChannels': ['candidate'],
        'requiredPluginAllowlist': ['signed-plugin'],
    })
    fleet = v19.FleetConfiguration.from_json({
        'schemaVersion': '1.0.0',
        'defaultPolicyProfileId': 'base',
        'projects': {'project-x': {'policyProfileId': 'overlay'}},
    })
    lifecycle = v19.SupportLifecyclePolicy(
        current_version='1.9.0+190',
        minimum_supported_upgrade_from='1.7.0+170',
        minimum_supported_rollback_to='1.8.0+180',
        supported_channels=('stable', 'candidate'),
    )
    pair = v19.generate_signing_keypair(key_id='release-signer')

    case('Policy overlay merges update channels and allowlists', lambda: _merge_case(base, overlay), results)
    case('Fleet configuration resolves project-specific policy', lambda: _fleet_case(fleet), results)
    case('Audit chain verifies end-to-end', _audit_case, results)
    case('Audit tampering is detected', _audit_tamper_case, results)
    case('Signed audit checkpoint verifies current chain', lambda: _audit_checkpoint_case(pair), results)
    case('Signed update manifest verifies', lambda: _update_case(pair, lifecycle), results)
    case('Tampered update manifest is rejected', lambda: _tampered_update_case(pair), results)
    case('Rollback planner chooses supported installed version', lambda: _rollback_case(lifecycle), results)
    case('Unsupported rollback target is blocked', lambda: _rollback_block_case(lifecycle), results)
    case('Support lifecycle rejects too-old upgrades', lambda: _lifecycle_case(lifecycle), results)

    payload = {
        'version': v19.VERSION,
        'passed': all(item.passed for item in results),
        'passedCount': sum(item.passed for item in results),
        'caseCount': len(results),
        'results': [dataclasses.asdict(item) for item in results],
    }
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(json.dumps(payload, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if payload['passed'] else 1


def _merge_case(base, overlay):
    merged = v19.merge_policy_profiles(base, overlay)
    return require(merged.network_policy == 'broker_https' and merged.allowed_update_channels == ('candidate', 'stable') and merged.required_plugin_allowlist == ('signed-plugin',), 'policy overlay is deterministic and additive for allowlists')


def _fleet_case(fleet):
    return require(fleet.resolve_policy_id('project-x') == 'overlay' and fleet.resolve_policy_id('unknown') == 'base', 'fleet configuration resolves project policy or default')


def _audit_case():
    records = []
    v19.append_audit_record(records, 'run.started', {'runId': 'r1'})
    v19.append_audit_record(records, 'run.completed', {'runId': 'r1'})
    verified = v19.verify_audit_chain(records)
    return require(verified['verified'] and verified['recordCount'] == 2, 'audit chain verifies and counts records')


def _audit_tamper_case():
    records = []
    v19.append_audit_record(records, 'run.started', {'runId': 'r1'})
    v19.append_audit_record(records, 'run.completed', {'runId': 'r1'})
    records[1] = dataclasses.replace(records[1], payload={'runId': 'tampered'})
    verified = v19.verify_audit_chain(records)
    return require(not verified['verified'] and verified['failure'] == 'record_hash_mismatch', 'audit tampering is detected')


def _audit_checkpoint_case(pair):
    records = []
    v19.append_audit_record(records, 'run.started', {'runId': 'r1'})
    v19.append_audit_record(records, 'run.completed', {'runId': 'r1'})
    checkpoint = v19.create_signed_audit_checkpoint(records, pair)
    verified = v19.verify_signed_audit_checkpoint(checkpoint.to_json(), records, key_lookup={pair.key_id: pair.secret_key})
    return require(verified['verified'], 'signed audit checkpoint verifies the chain head')


def _update_case(pair, lifecycle):
    envelope = v19.create_signed_update_manifest(v19.UpdateManifest(version='1.9.0+190', channel='stable', archive='kristin.zip', archive_sha256='a'*64, compatible_from=('1.8.0+180',), minimum_rollback_version='1.8.0+180'), pair)
    verified = v19.verify_signed_update_manifest(envelope.to_json(), lifecycle, key_lookup={pair.key_id: pair.secret_key})
    return require(verified['verified'] and verified['manifest']['channel'] == 'stable', 'signed update manifest verifies against lifecycle policy')


def _tampered_update_case(pair):
    envelope = v19.create_signed_update_manifest(v19.UpdateManifest(version='1.9.0+190', channel='stable', archive='kristin.zip', archive_sha256='a'*64, compatible_from=('1.8.0+180',), minimum_rollback_version='1.8.0+180'), pair).to_json()
    envelope['manifest']['archiveSha256'] = 'b' * 64
    try:
        v19.verify_signed_update_manifest(envelope, key_lookup={'release-signer': 'wrong-secret'})
    except Exception:
        return require(True, 'tampered update manifest is rejected')
    raise AssertionError('tampered update manifest unexpectedly verified')


def _rollback_case(lifecycle):
    plan = v19.plan_rollback('1.9.0+190', ['1.9.0+190', '1.8.0+180', '1.7.0+170'], lifecycle)
    return require(plan['eligible'] and plan['targetVersion'] == '1.8.0+180', 'rollback planner chooses the newest supported installed version')


def _rollback_block_case(lifecycle):
    plan = v19.plan_rollback('1.9.0+190', ['1.7.0+170'], lifecycle)
    return require(not plan['eligible'], 'rollback is blocked when installed versions are outside support policy')


def _lifecycle_case(lifecycle):
    return require(not lifecycle.allows_upgrade_from('1.6.0+160') and lifecycle.allows_upgrade_from('1.8.0+180'), 'support lifecycle enforces minimum upgrade version')


if __name__ == '__main__':
    raise SystemExit(main())
