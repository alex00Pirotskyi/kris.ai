#!/usr/bin/env python3
from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Iterable

from ed25519_ref import sign, verify
from signed_manifest_v2 import canonical_json


class AuditCheckpointError(ValueError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


@dataclass(frozen=True)
class AuditCheckpoint:
    sequence: int
    event_count: int
    previous_checkpoint_hash: str
    audit_head_hash: str
    key_id: str
    signature_hex: str

    def body(self) -> dict[str, Any]:
        return {
            "schemaVersion": "1.0.0",
            "sequence": self.sequence,
            "eventCount": self.event_count,
            "previousCheckpointHash": self.previous_checkpoint_hash,
            "auditHeadHash": self.audit_head_hash,
            "keyId": self.key_id,
        }

    def to_json(self) -> dict[str, Any]:
        return {**self.body(), "signature": self.signature_hex}


def checkpoint_hash(checkpoint: AuditCheckpoint) -> str:
    import hashlib
    return hashlib.sha256(canonical_json(checkpoint.to_json()).encode("utf-8")).hexdigest()


def create_checkpoint(
    *,
    sequence: int,
    event_count: int,
    previous_checkpoint_hash: str,
    audit_head_hash: str,
    key_id: str,
    seed: bytes,
) -> AuditCheckpoint:
    body = {
        "schemaVersion": "1.0.0",
        "sequence": sequence,
        "eventCount": event_count,
        "previousCheckpointHash": previous_checkpoint_hash,
        "auditHeadHash": audit_head_hash,
        "keyId": key_id,
    }
    signature = sign(seed, canonical_json(body).encode("utf-8")).hex()
    return AuditCheckpoint(
        sequence=sequence,
        event_count=event_count,
        previous_checkpoint_hash=previous_checkpoint_hash,
        audit_head_hash=audit_head_hash,
        key_id=key_id,
        signature_hex=signature,
    )


def verify_chain(
    checkpoints: Iterable[AuditCheckpoint],
    *,
    public_keys: dict[str, bytes],
    expected_final_audit_head: str | None = None,
) -> dict[str, Any]:
    items = list(checkpoints)
    previous_hash = ""
    previous_sequence = 0
    previous_event_count = 0
    for checkpoint in items:
        if checkpoint.sequence != previous_sequence + 1:
            raise AuditCheckpointError("checkpoint_reordered", "Checkpoint sequence is not contiguous.")
        if checkpoint.event_count <= previous_event_count:
            raise AuditCheckpointError("checkpoint_truncated", "Event count did not advance.")
        if checkpoint.previous_checkpoint_hash != previous_hash:
            raise AuditCheckpointError("checkpoint_chain_mismatch", "Checkpoint hash chain is broken.")
        public = public_keys.get(checkpoint.key_id)
        if public is None:
            raise AuditCheckpointError("unknown_signer", f"Unknown checkpoint signer: {checkpoint.key_id}")
        try:
            signature = bytes.fromhex(checkpoint.signature_hex)
        except ValueError as error:
            raise AuditCheckpointError("signature_malformed", "Checkpoint signature is malformed.") from error
        if not verify(
            public,
            canonical_json(checkpoint.body()).encode("utf-8"),
            signature,
        ):
            raise AuditCheckpointError("checkpoint_tampered", "Checkpoint signature is invalid.")
        previous_hash = checkpoint_hash(checkpoint)
        previous_sequence = checkpoint.sequence
        previous_event_count = checkpoint.event_count
    if expected_final_audit_head is not None:
        if not items or items[-1].audit_head_hash != expected_final_audit_head:
            raise AuditCheckpointError("audit_head_mismatch", "Final audit head does not match.")
    return {
        "checkpointCount": len(items),
        "finalCheckpointHash": previous_hash,
        "finalAuditHeadHash": items[-1].audit_head_hash if items else "",
    }
