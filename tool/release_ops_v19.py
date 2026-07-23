#!/usr/bin/env python3
"""Kristin v1.9 administration and release-operations primitives.

This module is intentionally standard-library only. It provides deterministic
policy overlays, append-only audit verification, authenticated update-manifest
verification, and rollback planning for source-release operations.

Note: this implementation uses keyed integrity (HMAC-SHA256) rather than
asymmetric public-key signing. It supports authenticated manifests and audit
checkpoints for governed local release workflows without claiming native code
signing or platform installer signing.
"""
from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import hashlib
import hmac
import json
from pathlib import Path
import secrets
from typing import Any, Mapping

VERSION = '1.9.0+190'
SCHEMA_VERSION = '1.0.0'
SIGNATURE_ALGORITHM = 'hmac-sha256'


class InteroperabilityError(RuntimeError):
    def __init__(self, code: str, message: str, *, details: Mapping[str, Any] | None = None) -> None:
        super().__init__(message)
        self.code = code
        self.details = dict(details or {})

    def __str__(self) -> str:
        if self.details:
            return f'{self.code}: {super().__str__()} ({json.dumps(self.details, sort_keys=True)})'
        return f'{self.code}: {super().__str__()}'


def canonical_json(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False)


def sha256_json(value: object) -> str:
    return hashlib.sha256(canonical_json(value).encode('utf-8')).hexdigest()


@dataclasses.dataclass(frozen=True)
class SigningKeyPair:
    key_id: str
    secret_key: str
    algorithm: str = SIGNATURE_ALGORITHM

    def to_json(self) -> dict[str, Any]:
        return {
            'schemaVersion': SCHEMA_VERSION,
            'keyId': self.key_id,
            'secretKey': self.secret_key,
            'algorithm': self.algorithm,
        }


@dataclasses.dataclass(frozen=True)
class SignedManifestEnvelope:
    manifest_type: str
    manifest: dict[str, Any]
    signature: dict[str, str]
    schema_version: str = SCHEMA_VERSION

    def to_json(self) -> dict[str, Any]:
        return {
            'schemaVersion': self.schema_version,
            'manifestType': self.manifest_type,
            'manifest': self.manifest,
            'signature': self.signature,
        }


def generate_signing_keypair(*, key_id: str = 'release-signer') -> SigningKeyPair:
    return SigningKeyPair(key_id=key_id, secret_key=secrets.token_hex(32))


def _signature_material(manifest_type: str, manifest: Mapping[str, Any], *, key_id: str, signed_at: str) -> dict[str, Any]:
    return {
        'algorithm': SIGNATURE_ALGORITHM,
        'keyId': key_id,
        'manifestType': manifest_type,
        'manifestSha256': sha256_json(manifest),
        'signedAt': signed_at,
    }


def sign_manifest(manifest_type: str, manifest: Mapping[str, Any], key_pair: SigningKeyPair, *, signed_at: str | None = None) -> SignedManifestEnvelope:
    manifest_name = str(manifest_type).strip()
    if not manifest_name:
        raise InteroperabilityError('manifest_type_invalid', 'Manifest type must not be empty.')
    body = dict(manifest)
    timestamp = signed_at or dt.datetime.now(dt.timezone.utc).isoformat()
    material = canonical_json(_signature_material(manifest_name, body, key_id=key_pair.key_id, signed_at=timestamp))
    signature = hmac.new(key_pair.secret_key.encode('utf-8'), material.encode('utf-8'), hashlib.sha256).hexdigest()
    return SignedManifestEnvelope(
        manifest_type=manifest_name,
        manifest=body,
        signature={
            'algorithm': SIGNATURE_ALGORITHM,
            'keyId': key_pair.key_id,
            'signedAt': timestamp,
            'manifestSha256': sha256_json(body),
            'signature': signature,
        },
    )


def verify_signed_manifest(envelope: Mapping[str, Any], key_lookup: Mapping[str, str] | None = None) -> dict[str, Any]:
    if key_lookup is None:
        key_lookup = {}
    if not isinstance(envelope, Mapping):
        raise InteroperabilityError('envelope_invalid', 'Signed manifest envelope must be an object.')
    manifest = envelope.get('manifest')
    signature = envelope.get('signature')
    manifest_type = str(envelope.get('manifestType', '')).strip()
    if not isinstance(manifest, Mapping) or not isinstance(signature, Mapping) or not manifest_type:
        raise InteroperabilityError('envelope_invalid', 'Signed manifest envelope is missing manifest, signature, or manifestType.')
    algorithm = str(signature.get('algorithm', ''))
    key_id = str(signature.get('keyId', ''))
    signed_at = str(signature.get('signedAt', ''))
    manifest_sha256 = str(signature.get('manifestSha256', ''))
    signature_hex = str(signature.get('signature', ''))
    if algorithm != SIGNATURE_ALGORITHM:
        raise InteroperabilityError('signature_algorithm_invalid', 'Unsupported signature algorithm.')
    if sha256_json(manifest) != manifest_sha256:
        raise InteroperabilityError('manifest_sha256_mismatch', 'Manifest hash does not match signature envelope.')
    secret = key_lookup.get(key_id)
    if not secret:
        raise InteroperabilityError('unknown_signer', 'No signing key is registered for the provided key id.')
    material = canonical_json(_signature_material(manifest_type, manifest, key_id=key_id, signed_at=signed_at))
    expected = hmac.new(secret.encode('utf-8'), material.encode('utf-8'), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected, signature_hex):
        raise InteroperabilityError('signature_mismatch', 'Manifest signature does not verify.')
    return {
        'verified': True,
        'manifestType': manifest_type,
        'manifestSha256': manifest_sha256,
        'signerKeyId': key_id,
        'algorithm': algorithm,
    }


def parse_version(text: str) -> tuple[int, int, int, int]:
    version, plus, build = text.partition('+')
    parts = version.split('.')
    if len(parts) != 3 or not all(part.isdigit() for part in parts):
        raise InteroperabilityError('version_invalid', f'Invalid semantic version: {text}')
    build_value = int(build) if plus and build.isdigit() else 0
    return int(parts[0]), int(parts[1]), int(parts[2]), build_value


def version_ge(left: str, right: str) -> bool:
    return parse_version(left) >= parse_version(right)


@dataclasses.dataclass(frozen=True)
class PolicyProfile:
    id: str
    name: str
    data_boundary: str
    network_policy: str
    allow_unsigned_manifests: bool
    allow_a2a_delegation: bool
    allow_remote_mcp: bool
    allow_cloud_models: bool = False
    allowed_update_channels: tuple[str, ...] = ('stable',)
    required_plugin_allowlist: tuple[str, ...] = ()
    schema_version: str = SCHEMA_VERSION

    @classmethod
    def from_json(cls, raw: Mapping[str, Any]) -> 'PolicyProfile':
        data = {str(key): value for key, value in raw.items()}
        required = {'id', 'name', 'dataBoundary', 'networkPolicy', 'allowUnsignedManifests', 'allowA2ADelegation', 'allowRemoteMcp', 'allowedUpdateChannels'}
        missing = sorted(required - set(data))
        if missing:
            raise InteroperabilityError('policy_profile_missing', f'Missing policy profile fields: {", ".join(missing)}')
        boundary = str(data['dataBoundary'])
        network = str(data['networkPolicy'])
        if boundary not in {'local_only', 'brokered_https', 'enterprise_managed'}:
            raise InteroperabilityError('policy_profile_boundary_invalid', 'Unsupported dataBoundary.')
        if network not in {'none', 'broker_https'}:
            raise InteroperabilityError('policy_profile_network_invalid', 'Unsupported networkPolicy.')
        channels = tuple(sorted(set(str(item) for item in data['allowedUpdateChannels'])))
        return cls(
            id=str(data['id']),
            name=str(data['name']),
            data_boundary=boundary,
            network_policy=network,
            allow_unsigned_manifests=bool(data['allowUnsignedManifests']),
            allow_a2a_delegation=bool(data['allowA2ADelegation']),
            allow_remote_mcp=bool(data['allowRemoteMcp']),
            allow_cloud_models=bool(data.get('allowCloudModels', False)),
            allowed_update_channels=channels,
            required_plugin_allowlist=tuple(sorted(set(str(item) for item in data.get('requiredPluginAllowlist', [])))),
        )

    def to_json(self) -> dict[str, Any]:
        return {
            'schemaVersion': self.schema_version,
            'id': self.id,
            'name': self.name,
            'dataBoundary': self.data_boundary,
            'networkPolicy': self.network_policy,
            'allowUnsignedManifests': self.allow_unsigned_manifests,
            'allowA2ADelegation': self.allow_a2a_delegation,
            'allowRemoteMcp': self.allow_remote_mcp,
            'allowCloudModels': self.allow_cloud_models,
            'allowedUpdateChannels': list(self.allowed_update_channels),
            'requiredPluginAllowlist': list(self.required_plugin_allowlist),
        }


def merge_policy_profiles(base: PolicyProfile, overlay: PolicyProfile) -> PolicyProfile:
    return PolicyProfile(
        id=overlay.id or base.id,
        name=overlay.name or base.name,
        data_boundary=overlay.data_boundary or base.data_boundary,
        network_policy=overlay.network_policy or base.network_policy,
        allow_unsigned_manifests=overlay.allow_unsigned_manifests,
        allow_a2a_delegation=overlay.allow_a2a_delegation,
        allow_remote_mcp=overlay.allow_remote_mcp,
        allow_cloud_models=overlay.allow_cloud_models,
        allowed_update_channels=tuple(sorted(set(base.allowed_update_channels) | set(overlay.allowed_update_channels))),
        required_plugin_allowlist=tuple(sorted(set(base.required_plugin_allowlist) | set(overlay.required_plugin_allowlist))),
    )


@dataclasses.dataclass(frozen=True)
class FleetConfiguration:
    default_policy_profile_id: str
    project_policies: dict[str, str]
    schema_version: str = SCHEMA_VERSION

    @classmethod
    def from_json(cls, raw: Mapping[str, Any]) -> 'FleetConfiguration':
        projects = raw.get('projects') or {}
        if not isinstance(projects, dict):
            raise InteroperabilityError('fleet_projects_invalid', 'fleetConfiguration.projects must be an object.')
        resolved: dict[str, str] = {}
        for project_id, entry in projects.items():
            if not isinstance(entry, dict) or not entry.get('policyProfileId'):
                raise InteroperabilityError('fleet_project_policy_missing', f'Project {project_id} lacks policyProfileId.')
            resolved[str(project_id)] = str(entry['policyProfileId'])
        return cls(default_policy_profile_id=str(raw.get('defaultPolicyProfileId', 'default')), project_policies=resolved)

    def resolve_policy_id(self, project_id: str) -> str:
        return self.project_policies.get(project_id, self.default_policy_profile_id)


@dataclasses.dataclass(frozen=True)
class AuditRecord:
    sequence: int
    kind: str
    payload: dict[str, Any]
    previous_sha256: str | None
    record_sha256: str
    created_at: str

    def to_json(self) -> dict[str, Any]:
        return {
            'sequence': self.sequence,
            'kind': self.kind,
            'payload': self.payload,
            'previousSha256': self.previous_sha256,
            'recordSha256': self.record_sha256,
            'createdAt': self.created_at,
        }


def append_audit_record(records: list[AuditRecord], kind: str, payload: Mapping[str, Any]) -> AuditRecord:
    previous = records[-1].record_sha256 if records else None
    candidate = {
        'sequence': len(records) + 1,
        'kind': kind,
        'payload': dict(payload),
        'previousSha256': previous,
        'createdAt': dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    record_hash = sha256_json(candidate)
    record = AuditRecord(
        sequence=candidate['sequence'],
        kind=kind,
        payload=dict(payload),
        previous_sha256=previous,
        record_sha256=record_hash,
        created_at=candidate['createdAt'],
    )
    records.append(record)
    return record


def verify_audit_chain(records: list[AuditRecord]) -> dict[str, Any]:
    previous = None
    for index, record in enumerate(records, start=1):
        candidate = {
            'sequence': record.sequence,
            'kind': record.kind,
            'payload': record.payload,
            'previousSha256': record.previous_sha256,
            'createdAt': record.created_at,
        }
        expected = sha256_json(candidate)
        if record.sequence != index:
            return {'verified': False, 'failure': 'sequence_gap', 'index': index}
        if record.previous_sha256 != previous:
            return {'verified': False, 'failure': 'previous_hash_mismatch', 'index': index}
        if record.record_sha256 != expected:
            return {'verified': False, 'failure': 'record_hash_mismatch', 'index': index}
        previous = record.record_sha256
    return {'verified': True, 'headSha256': previous, 'recordCount': len(records)}


def create_signed_audit_checkpoint(records: list[AuditRecord], key_pair: SigningKeyPair) -> SignedManifestEnvelope:
    verification = verify_audit_chain(records)
    if not verification['verified']:
        raise InteroperabilityError('audit_chain_invalid', 'Cannot checkpoint an invalid audit chain.', details=verification)
    manifest = {
        'schemaVersion': SCHEMA_VERSION,
        'recordCount': verification['recordCount'],
        'headSha256': verification['headSha256'] or '0' * 64,
        'createdAt': dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    return sign_manifest('audit_checkpoint', manifest, key_pair)


def verify_signed_audit_checkpoint(envelope: Mapping[str, Any], records: list[AuditRecord], *, key_lookup: Mapping[str, str] | None = None) -> dict[str, Any]:
    verification = verify_signed_manifest(envelope, key_lookup=key_lookup or {})
    chain = verify_audit_chain(records)
    if not chain['verified']:
        raise InteroperabilityError('audit_chain_invalid', 'Audit chain is invalid.', details=chain)
    manifest = dict(envelope['manifest'])
    if int(manifest['recordCount']) != int(chain['recordCount']) or str(manifest['headSha256']) != str(chain['headSha256'] or '0' * 64):
        raise InteroperabilityError('audit_checkpoint_mismatch', 'Audit checkpoint does not match the current chain.')
    return {'verified': True, 'chain': chain, 'signature': verification}


@dataclasses.dataclass(frozen=True)
class SupportLifecyclePolicy:
    current_version: str
    minimum_supported_upgrade_from: str
    minimum_supported_rollback_to: str
    supported_channels: tuple[str, ...]
    schema_version: str = SCHEMA_VERSION

    def to_json(self) -> dict[str, Any]:
        return {
            'schemaVersion': self.schema_version,
            'currentVersion': self.current_version,
            'minimumSupportedUpgradeFrom': self.minimum_supported_upgrade_from,
            'minimumSupportedRollbackTo': self.minimum_supported_rollback_to,
            'supportedChannels': list(self.supported_channels),
        }

    def allows_upgrade_from(self, version: str) -> bool:
        return version_ge(version, self.minimum_supported_upgrade_from) and version_ge(self.current_version, version)

    def allows_rollback_to(self, version: str) -> bool:
        return version_ge(version, self.minimum_supported_rollback_to) and version_ge(self.current_version, version)


@dataclasses.dataclass(frozen=True)
class UpdateManifest:
    version: str
    channel: str
    archive: str
    archive_sha256: str
    compatible_from: tuple[str, ...]
    minimum_rollback_version: str
    notes: str = ''
    product: str = 'Kristin Local Agent'
    released_at: str = dataclasses.field(default_factory=lambda: dt.datetime.now(dt.timezone.utc).isoformat())
    schema_version: str = SCHEMA_VERSION

    def to_json(self) -> dict[str, Any]:
        return {
            'schemaVersion': self.schema_version,
            'product': self.product,
            'version': self.version,
            'channel': self.channel,
            'archive': self.archive,
            'archiveSha256': self.archive_sha256,
            'releasedAt': self.released_at,
            'minimumRollbackVersion': self.minimum_rollback_version,
            'compatibleFrom': list(self.compatible_from),
            'notes': self.notes,
        }


def create_signed_update_manifest(manifest: UpdateManifest, key_pair: SigningKeyPair) -> SignedManifestEnvelope:
    return sign_manifest('update', manifest.to_json(), key_pair)


def verify_signed_update_manifest(envelope: Mapping[str, Any], support_policy: SupportLifecyclePolicy | None = None, *, key_lookup: Mapping[str, str] | None = None) -> dict[str, Any]:
    verification = verify_signed_manifest(envelope, key_lookup=key_lookup or {})
    manifest = dict(envelope['manifest'])
    if support_policy is not None:
        if str(manifest['channel']) not in set(support_policy.supported_channels):
            raise InteroperabilityError('update_channel_unsupported', 'Update channel is not enabled by lifecycle policy.')
        if not support_policy.allows_upgrade_from(str(manifest['compatibleFrom'][0])):
            raise InteroperabilityError('update_upgrade_path_unsupported', 'Update manifest is not compatible with minimum supported upgrade version.')
    return {'verified': True, 'signature': verification, 'manifest': manifest}


def plan_rollback(current_version: str, installed_versions: list[str], lifecycle: SupportLifecyclePolicy) -> dict[str, Any]:
    candidates = sorted((version for version in installed_versions if version_ge(current_version, version) and lifecycle.allows_rollback_to(version)), key=parse_version, reverse=True)
    if not candidates:
        return {'eligible': False, 'reason': 'no_supported_rollback_candidate'}
    if candidates[0] == current_version and len(candidates) > 1:
        target = candidates[1]
    else:
        target = candidates[0]
    if target == current_version:
        return {'eligible': False, 'reason': 'current_version_only'}
    return {'eligible': True, 'targetVersion': target, 'supported': lifecycle.allows_rollback_to(target)}


def _main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description='Kristin v1.9 release operations')
    sub = parser.add_subparsers(dest='command')
    sub.add_parser('generate-keypair')
    parser_verify = sub.add_parser('audit-verify')
    parser_verify.add_argument('--audit', type=Path, required=True)
    args = parser.parse_args(argv)
    if args.command == 'generate-keypair':
        print(json.dumps(dataclasses.asdict(generate_signing_keypair()), indent=2, sort_keys=True))
        return 0
    if args.command == 'audit-verify':
        payload = json.loads(args.audit.read_text(encoding='utf-8'))
        records = [AuditRecord(sequence=int(item['sequence']), kind=str(item['kind']), payload=dict(item['payload']), previous_sha256=item.get('previousSha256'), record_sha256=str(item['recordSha256']), created_at=str(item['createdAt'])) for item in payload]
        print(json.dumps(verify_audit_chain(records), indent=2, sort_keys=True))
        return 0
    parser.print_help()
    return 0


if __name__ == '__main__':
    raise SystemExit(_main())
