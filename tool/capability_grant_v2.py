from __future__ import annotations

import copy
import hashlib
import hmac
import json
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Mapping

DOMAIN_SEPARATOR = b"kristin.capability-grant.v2\x00"
ALGORITHM = "hmac-sha256"
SCHEMA_VERSION = "2.0.0"
_ALLOWED_TOP_LEVEL = {
    "schemaVersion",
    "grantId",
    "issuer",
    "binding",
    "scope",
    "budgets",
    "validity",
    "nonce",
    "auth",
}
_FORBIDDEN_EMBEDDED_KEYS = {
    "keyMaterial",
    "secretValue",
    "rawSecret",
    "privateKey",
    "signingKey",
}
_ALLOWED_ACTORS = {
    "desktop_host",
    "owner_executor",
    "automation_host",
    "research_worker",
    "sandbox_worker",
}
_ALLOWED_PROFILES = {
    "chat",
    "project",
    "owner",
    "owner_unattended",
    "isolated_untrusted",
}


class GrantValidationError(ValueError):
    pass


class GrantVerificationError(RuntimeError):
    def __init__(self, code: str, message: str | None = None):
        super().__init__(message or code)
        self.code = code


def _canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
        allow_nan=False,
    ).encode("utf-8")


def _parse_utc(value: str, field: str) -> datetime:
    if not isinstance(value, str) or not value.strip():
        raise GrantValidationError(f"{field} must be a non-empty RFC3339 timestamp")
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError as error:
        raise GrantValidationError(f"{field} must be RFC3339") from error
    if parsed.tzinfo is None:
        raise GrantValidationError(f"{field} must include a timezone")
    return parsed.astimezone(timezone.utc)


def _require_map(value: Any, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise GrantValidationError(f"{field} must be an object")
    return value


def _require_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise GrantValidationError(f"{field} must be a non-empty string")
    return value.strip()


def _walk_forbidden_keys(value: Any, path: str = "$") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key in _FORBIDDEN_EMBEDDED_KEYS:
                raise GrantValidationError(f"{path}.{key} embeds forbidden key material")
            _walk_forbidden_keys(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            _walk_forbidden_keys(child, f"{path}[{index}]")


def _validate_scope(scope: dict[str, Any]) -> None:
    required = {"paths", "process", "network", "browser", "secrets"}
    missing = sorted(required - set(scope))
    if missing:
        raise GrantValidationError(f"scope missing: {missing}")
    for field in required:
        _require_map(scope[field], f"scope.{field}")
    secrets = scope["secrets"]
    if secrets.get("rawReveal") is not False:
        raise GrantValidationError("scope.secrets.rawReveal must be false")
    for lease in secrets.get("leaseIds", []):
        _require_string(lease, "scope.secrets.leaseIds[]")
    if scope["network"].get("listen") not in (False, None):
        raise GrantValidationError("scope.network.listen must be false in Capability Grant v2")


def _validate_budgets(budgets: dict[str, Any]) -> None:
    required = {
        "wallClockMs",
        "maxOutputBytes",
        "maxNetworkBytes",
        "maxCostMicros",
        "maxMutations",
    }
    missing = sorted(required - set(budgets))
    if missing:
        raise GrantValidationError(f"budgets missing: {missing}")
    for field in required:
        value = budgets[field]
        if not isinstance(value, int) or isinstance(value, bool) or value < 0:
            raise GrantValidationError(f"budgets.{field} must be a non-negative integer")


def validate_grant_json(data: Mapping[str, Any], *, require_mac: bool = True) -> dict[str, Any]:
    if not isinstance(data, Mapping):
        raise GrantValidationError("grant must be an object")
    grant = copy.deepcopy(dict(data))
    unknown = sorted(set(grant) - _ALLOWED_TOP_LEVEL)
    missing = sorted(_ALLOWED_TOP_LEVEL - set(grant))
    if unknown:
        raise GrantValidationError(f"unknown top-level grant fields: {unknown}")
    if missing:
        raise GrantValidationError(f"grant missing: {missing}")
    if grant["schemaVersion"] != SCHEMA_VERSION:
        raise GrantValidationError("schemaVersion must be 2.0.0")
    _require_string(grant["grantId"], "grantId")
    _require_string(grant["nonce"], "nonce")

    issuer = _require_map(grant["issuer"], "issuer")
    if issuer.get("actorId") != "desktop_host" or issuer.get("authority") != "desktop_host:deterministic_policy":
        raise GrantValidationError("issuer must be desktop_host deterministic policy")

    binding = _require_map(grant["binding"], "binding")
    for field in ("runId", "taskId", "actorId", "toolId", "accessProfileId"):
        _require_string(binding.get(field), f"binding.{field}")
    if binding["actorId"] not in _ALLOWED_ACTORS:
        raise GrantValidationError("binding.actorId is not a registered runtime actor")
    if binding["accessProfileId"] not in _ALLOWED_PROFILES:
        raise GrantValidationError("binding.accessProfileId is not canonical")

    _validate_scope(_require_map(grant["scope"], "scope"))
    _validate_budgets(_require_map(grant["budgets"], "budgets"))

    validity = _require_map(grant["validity"], "validity")
    issued = _parse_utc(validity.get("issuedAt"), "validity.issuedAt")
    not_before = _parse_utc(validity.get("notBefore"), "validity.notBefore")
    expires = _parse_utc(validity.get("expiresAt"), "validity.expiresAt")
    if not (issued <= not_before < expires):
        raise GrantValidationError("validity timestamps must satisfy issuedAt <= notBefore < expiresAt")
    max_uses = validity.get("maxUses")
    if not isinstance(max_uses, int) or isinstance(max_uses, bool) or max_uses < 1:
        raise GrantValidationError("validity.maxUses must be a positive integer")

    auth = _require_map(grant["auth"], "auth")
    if auth.get("algorithm") != ALGORITHM:
        raise GrantValidationError("auth.algorithm must be hmac-sha256")
    _require_string(auth.get("keyId"), "auth.keyId")
    mac = auth.get("mac")
    if require_mac and (not isinstance(mac, str) or len(mac) != 64 or any(ch not in "0123456789abcdef" for ch in mac)):
        raise GrantValidationError("auth.mac must be a lowercase SHA-256 hex digest")
    if not require_mac and mac not in (None, ""):
        if not isinstance(mac, str) or len(mac) != 64:
            raise GrantValidationError("auth.mac has invalid shape")

    _walk_forbidden_keys(grant)
    return grant


def signing_payload(grant: Mapping[str, Any]) -> dict[str, Any]:
    value = validate_grant_json(grant, require_mac=False)
    auth = dict(value["auth"])
    auth.pop("mac", None)
    value["auth"] = auth
    return value


def compute_mac(grant: Mapping[str, Any], key: bytes) -> str:
    if not isinstance(key, (bytes, bytearray)) or len(key) < 8:
        raise GrantValidationError("issuer key must be external bytes with at least 8 bytes")
    return hmac.new(bytes(key), DOMAIN_SEPARATOR + _canonical_json_bytes(signing_payload(grant)), hashlib.sha256).hexdigest()


def sign_grant(grant: Mapping[str, Any], *, key_id: str, key: bytes) -> dict[str, Any]:
    value = copy.deepcopy(dict(grant))
    value["auth"] = {"algorithm": ALGORITHM, "keyId": _require_string(key_id, "keyId"), "mac": ""}
    value["auth"]["mac"] = compute_mac(value, key)
    return validate_grant_json(value)


@dataclass
class GrantUseLedger:
    uses_by_grant: dict[str, int]
    invocations: set[tuple[str, str]]
    nonce_owner: dict[str, str]

    def __init__(self) -> None:
        self.uses_by_grant = {}
        self.invocations = set()
        self.nonce_owner = {}

    def consume(self, grant: Mapping[str, Any], invocation_id: str) -> None:
        grant_id = _require_string(grant.get("grantId"), "grantId")
        nonce = _require_string(grant.get("nonce"), "nonce")
        invocation = _require_string(invocation_id, "invocationId")
        owner = self.nonce_owner.get(nonce)
        if owner is not None and owner != grant_id:
            raise GrantVerificationError("grant_replayed", "nonce was already bound to another grant")
        token = (grant_id, invocation)
        if token in self.invocations:
            raise GrantVerificationError("grant_replayed", "invocation was already consumed")
        max_uses = int(grant["validity"]["maxUses"])
        current = self.uses_by_grant.get(grant_id, 0)
        if current >= max_uses:
            raise GrantVerificationError("grant_exhausted")
        self.nonce_owner[nonce] = grant_id
        self.invocations.add(token)
        self.uses_by_grant[grant_id] = current + 1


def verify_and_consume(
    grant: Mapping[str, Any],
    *,
    keyring: Mapping[str, bytes],
    ledger: GrantUseLedger,
    expected_run_id: str,
    expected_task_id: str,
    expected_actor_id: str,
    expected_tool_id: str,
    expected_access_profile_id: str,
    invocation_id: str,
    now: datetime | None = None,
) -> dict[str, Any]:
    try:
        value = validate_grant_json(grant)
    except GrantValidationError as error:
        raise GrantVerificationError("grant_invalid", str(error)) from error

    auth = value["auth"]
    key = keyring.get(auth["keyId"])
    if key is None:
        raise GrantVerificationError("unknown_grant_key")
    expected_mac = compute_mac(value, key)
    if not hmac.compare_digest(auth["mac"], expected_mac):
        raise GrantVerificationError("grant_integrity_mismatch")

    binding = value["binding"]
    checks = (
        ("runId", expected_run_id, "wrong_run"),
        ("taskId", expected_task_id, "wrong_task"),
        ("actorId", expected_actor_id, "wrong_actor"),
        ("toolId", expected_tool_id, "wrong_tool"),
        ("accessProfileId", expected_access_profile_id, "wrong_access_profile"),
    )
    for field, expected, code in checks:
        if binding[field] != expected:
            raise GrantVerificationError(code)

    current = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    not_before = _parse_utc(value["validity"]["notBefore"], "validity.notBefore")
    expires = _parse_utc(value["validity"]["expiresAt"], "validity.expiresAt")
    if current < not_before:
        raise GrantVerificationError("grant_not_yet_valid")
    if current >= expires:
        raise GrantVerificationError("grant_expired")

    ledger.consume(value, invocation_id)
    return value
