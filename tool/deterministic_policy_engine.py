from __future__ import annotations

import copy
import hashlib
import json
import posixpath
from dataclasses import dataclass
from typing import Any, Mapping, Sequence

SCHEMA_VERSION = "2.0.0"
_LAYER_ORDER = {"organization": 0, "project": 1, "user": 2}
_APPROVAL_RANK = {"never": 0, "high_risk_only": 1, "always": 2}
_TRUSTED_APPROVAL_SOURCES = {"owner", "organization_policy"}


class PolicyInputError(ValueError):
    pass


@dataclass(frozen=True)
class PolicyDecision:
    decision_id: str
    status: str
    reason_codes: tuple[str, ...]
    effective_profile_id: str
    effective_scope: Mapping[str, Any]
    effective_budgets: Mapping[str, int]
    grant_draft: Mapping[str, Any] | None

    def to_json(self) -> dict[str, Any]:
        return {
            "schemaVersion": SCHEMA_VERSION,
            "decisionId": self.decision_id,
            "status": self.status,
            "reasonCodes": list(self.reason_codes),
            "effectiveProfileId": self.effective_profile_id,
            "effectiveScope": copy.deepcopy(dict(self.effective_scope)),
            "effectiveBudgets": dict(self.effective_budgets),
            "grantDraft": copy.deepcopy(dict(self.grant_draft)) if self.grant_draft is not None else None,
        }


def _mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        raise PolicyInputError(f"{label} must be an object")
    return dict(value)


def _string(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise PolicyInputError(f"{label} must be a non-empty string")
    return value.strip()


def _string_list(value: Any, label: str) -> list[str]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise PolicyInputError(f"{label} must be an array")
    return [_string(item, f"{label}[]") for item in value]


def _canonical(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def _decision_id(request: Mapping[str, Any], config: Mapping[str, Any]) -> str:
    normalized_request = copy.deepcopy(dict(request))
    overlays = normalized_request.get("overlays")
    if isinstance(overlays, list):
        normalized_request["overlays"] = sorted(
            overlays,
            key=lambda item: (
                _LAYER_ORDER.get(item.get("layer"), 99) if isinstance(item, Mapping) else 99,
                str(item.get("overlayId", "")) if isinstance(item, Mapping) else "",
            ),
        )
    payload = {"request": normalized_request, "policyRevision": config.get("policyRevision")}
    return "policy-" + hashlib.sha256(_canonical(payload).encode("utf-8")).hexdigest()[:32]


def _normalize_path(value: str) -> str:
    text = value.strip().replace("\\", "/")
    if not text:
        return ""
    drive = ""
    if len(text) >= 2 and text[1] == ":":
        drive, text = text[:2].lower(), text[2:]
    normalized = posixpath.normpath(text)
    if normalized == ".":
        normalized = ""
    if normalized.startswith("../") or normalized == "..":
        raise PolicyInputError("path traversal is not a valid policy target")
    if drive:
        normalized = drive + (normalized if normalized.startswith("/") else "/" + normalized)
    return normalized.rstrip("/") or "/"


def _path_within(path: str, prefix: str) -> bool:
    path_n = _normalize_path(path)
    prefix_n = _normalize_path(prefix)
    if prefix_n == "/":
        return path_n.startswith("/")
    return path_n == prefix_n or path_n.startswith(prefix_n + "/")


def _destination_allowed(host: str, allowed: Sequence[str]) -> bool:
    value = host.strip().lower().rstrip(".")
    for item in allowed:
        pattern = item.strip().lower().rstrip(".")
        if pattern == "*":
            return True
        if pattern.startswith("*.") and (value == pattern[2:] or value.endswith(pattern[1:])):
            return True
        if value == pattern:
            return True
    return False


def _intersection(current: list[str], constraint: list[str]) -> list[str]:
    if not constraint:
        return []
    if "*" in current:
        return sorted(set(constraint))
    if "*" in constraint:
        return sorted(set(current))
    return sorted(set(current).intersection(constraint))


def _path_intersection(current: list[str], constraint: list[str]) -> list[str]:
    result: set[str] = set()
    for left in current:
        for right in constraint:
            if _path_within(left, right):
                result.add(_normalize_path(left))
            elif _path_within(right, left):
                result.add(_normalize_path(right))
    return sorted(result)


def _approval_policy_stricter(left: str, right: str) -> str:
    if left not in _APPROVAL_RANK or right not in _APPROVAL_RANK:
        raise PolicyInputError("unknown approval policy")
    return left if _APPROVAL_RANK[left] >= _APPROVAL_RANK[right] else right


def _base_scope(profile: Mapping[str, Any], context: Mapping[str, Any]) -> dict[str, Any]:
    filesystem = _mapping(profile.get("filesystem"), "profile.filesystem")
    process = _mapping(profile.get("process"), "profile.process")
    network = _mapping(profile.get("network"), "profile.network")
    browser = _mapping(profile.get("browser"), "profile.browser")
    credentials = _mapping(profile.get("credentials"), "profile.credentials")

    filesystem_scope = filesystem.get("scope")
    if filesystem_scope == "none":
        paths: list[str] = []
    elif filesystem_scope == "project":
        paths = [_normalize_path(_string(context.get("projectRoot"), "context.projectRoot"))]
    elif filesystem_scope == "current_account":
        paths = [_normalize_path(item) for item in _string_list(context.get("currentAccountRoots"), "context.currentAccountRoots")]
    elif filesystem_scope == "sandbox":
        paths = [_normalize_path(_string(context.get("sandboxRoot"), "context.sandboxRoot"))]
    else:
        raise PolicyInputError(f"unsupported filesystem scope: {filesystem_scope}")

    network_scope = network.get("scope")
    if network_scope == "none":
        destinations: list[str] = []
    elif network_scope == "unrestricted":
        destinations = ["*"]
    elif network_scope == "allowlist":
        key = "grantDestinations" if profile.get("profileId") == "isolated_untrusted" else "projectDestinations"
        destinations = sorted(set(_string_list(context.get(key), f"context.{key}")))
    else:
        raise PolicyInputError(f"unsupported network scope: {network_scope}")

    browser_scope = browser.get("scope")
    if browser_scope == "none":
        browser_profiles: list[str] = []
    elif browser_scope == "isolated":
        browser_profiles = ["isolated"]
    elif browser_scope == "user_selected":
        browser_profiles = sorted(set(_string_list(context.get("userSelectedBrowserProfiles"), "context.userSelectedBrowserProfiles")))
    elif browser_scope == "unrestricted":
        available = _string_list(context.get("availableBrowserProfiles"), "context.availableBrowserProfiles")
        browser_profiles = sorted(set(available)) if available else ["*"]
    else:
        raise PolicyInputError(f"unsupported browser scope: {browser_scope}")

    secret_leases = [] if credentials.get("mode") == "none" else sorted(set(_string_list(context.get("availableSecretLeaseIds"), "context.availableSecretLeaseIds")))

    return {
        "pathPrefixes": paths,
        "networkDestinations": destinations,
        "browserProfiles": browser_profiles,
        "secretLeaseIds": secret_leases,
        "filesystem": copy.deepcopy(filesystem),
        "process": copy.deepcopy(process),
        "network": copy.deepcopy(network),
        "browser": copy.deepcopy(browser),
        "credentials": copy.deepcopy(credentials),
    }


def _profile_budgets(profile_id: str, config: Mapping[str, Any]) -> dict[str, int]:
    raw = _mapping(_mapping(config.get("profileBudgets"), "config.profileBudgets").get(profile_id), f"config.profileBudgets.{profile_id}")
    result: dict[str, int] = {}
    for field in ("wallClockMs", "maxOutputBytes", "maxNetworkBytes", "maxCostMicros", "maxMutations"):
        value = raw.get(field)
        if not isinstance(value, int) or value < 0:
            raise PolicyInputError(f"invalid profile budget {profile_id}.{field}")
        result[field] = value
    return result


def _valid_approval(value: Mapping[str, Any] | None) -> tuple[bool, str | None]:
    if not value:
        return False, None
    approved = value.get("approved") is True
    source = value.get("source")
    approval_id = value.get("approvalId")
    if approved and source not in _TRUSTED_APPROVAL_SOURCES:
        return False, "untrusted_authority_source"
    if approved and (not isinstance(approval_id, str) or not approval_id.strip()):
        return False, "approval_identity_missing"
    return approved, None


def _overlay_key(value: Mapping[str, Any]) -> tuple[int, str]:
    layer = value.get("layer")
    if layer not in _LAYER_ORDER:
        raise PolicyInputError(f"unknown overlay layer: {layer}")
    return _LAYER_ORDER[layer], _string(value.get("overlayId"), "overlay.overlayId")


def evaluate_policy(
    request_value: Mapping[str, Any],
    *,
    access_catalog: Mapping[str, Any],
    policy_config: Mapping[str, Any],
) -> dict[str, Any]:
    request = copy.deepcopy(_mapping(request_value, "request"))
    if request.get("schemaVersion") != SCHEMA_VERSION:
        raise PolicyInputError("request schemaVersion must be 2.0.0")
    binding = _mapping(request.get("binding"), "request.binding")
    effect = _mapping(request.get("effect"), "request.effect")
    context = _mapping(request.get("context"), "request.context")
    profile_id = _string(binding.get("accessProfileId"), "binding.accessProfileId")
    profiles = {item.get("profileId"): item for item in access_catalog.get("profiles", []) if isinstance(item, Mapping)}
    profile = profiles.get(profile_id)
    if not isinstance(profile, Mapping):
        raise PolicyInputError(f"unknown access profile: {profile_id}")

    decision_id = _decision_id(request, policy_config)
    reasons: set[str] = set()
    capability_id = _string(binding.get("capabilityId"), "binding.capabilityId")
    tool_id = _string(binding.get("toolId"), "binding.toolId")
    actor_id = _string(binding.get("actorId"), "binding.actorId")
    for field in ("runId", "taskId"):
        _string(binding.get(field), f"binding.{field}")

    registry = _mapping(policy_config.get("capabilityRegistry"), "policy_config.capabilityRegistry")
    capability = registry.get(capability_id)
    if not isinstance(capability, Mapping):
        reasons.add("unknown_capability")
        capability = {"domain": "unknown", "risk": "high", "tools": []}
    tools = capability.get("tools") if isinstance(capability, Mapping) else []
    if not isinstance(tools, list) or tool_id not in tools:
        reasons.add("tool_not_registered_for_capability")
    if effect.get("domain") != capability.get("domain"):
        reasons.add("capability_effect_mismatch")

    expected_actor = capability.get("actor")
    if expected_actor and actor_id != expected_actor:
        reasons.add("wrong_actor")

    scope = _base_scope(profile, context)
    base_scope = copy.deepcopy(scope)
    budgets = _profile_budgets(profile_id, policy_config)
    requested_budgets = _mapping(request.get("requestedBudgets") or {}, "request.requestedBudgets")
    for field, ceiling in list(budgets.items()):
        requested = requested_budgets.get(field, ceiling)
        if not isinstance(requested, int) or requested < 0:
            reasons.add("invalid_budget")
            requested = 0
        budgets[field] = min(ceiling, requested)

    approval_policy = str(profile.get("approvalPolicy"))
    denied_capabilities: set[str] = set()
    denied_tools: set[str] = set()
    force_deny = False
    overlays = request.get("overlays") or []
    if not isinstance(overlays, list):
        raise PolicyInputError("request.overlays must be an array")
    for overlay in sorted((_mapping(item, "overlay") for item in overlays), key=_overlay_key):
        denied_capabilities.update(_string_list(overlay.get("denyCapabilities"), "overlay.denyCapabilities"))
        denied_tools.update(_string_list(overlay.get("denyTools"), "overlay.denyTools"))
        force_deny = force_deny or overlay.get("forceDeny") is True
        if overlay.get("pathPrefixes") is not None:
            scope["pathPrefixes"] = _path_intersection(scope["pathPrefixes"], [_normalize_path(item) for item in _string_list(overlay.get("pathPrefixes"), "overlay.pathPrefixes")])
        if overlay.get("networkDestinations") is not None:
            scope["networkDestinations"] = _intersection(scope["networkDestinations"], [item.lower() for item in _string_list(overlay.get("networkDestinations"), "overlay.networkDestinations")])
        if overlay.get("browserProfiles") is not None:
            scope["browserProfiles"] = _intersection(scope["browserProfiles"], _string_list(overlay.get("browserProfiles"), "overlay.browserProfiles"))
        if overlay.get("secretLeaseIds") is not None:
            scope["secretLeaseIds"] = _intersection(scope["secretLeaseIds"], _string_list(overlay.get("secretLeaseIds"), "overlay.secretLeaseIds"))
        max_budgets = _mapping(overlay.get("maxBudgets") or {}, "overlay.maxBudgets")
        for field, value in max_budgets.items():
            if field not in budgets or not isinstance(value, int) or value < 0:
                reasons.add("invalid_overlay_budget")
                continue
            budgets[field] = min(budgets[field], value)
        if overlay.get("approvalPolicy") is not None:
            approval_policy = _approval_policy_stricter(approval_policy, str(overlay.get("approvalPolicy")))

    if capability_id in denied_capabilities:
        reasons.add("capability_denied_by_overlay")
    if tool_id in denied_tools:
        reasons.add("tool_denied_by_overlay")
    if force_deny:
        reasons.add("force_deny")

    approval = _mapping(request.get("approval") or {}, "request.approval")
    approved, approval_error = _valid_approval(approval)
    if approval_error:
        reasons.add(approval_error)

    widening = _mapping(request.get("explicitWidening") or {}, "request.explicitWidening")
    widening_requested = any(widening.get(key) for key in ("restorePaths", "restoreNetworkDestinations", "restoreBrowserProfiles", "restoreSecretLeaseIds"))
    if widening_requested:
        widening_approved, widening_error = _valid_approval(widening)
        if widening_error:
            reasons.add(widening_error)
        if not widening_approved:
            reasons.add("explicit_widening_not_approved")
        else:
            for path in _string_list(widening.get("restorePaths"), "explicitWidening.restorePaths"):
                normalized = _normalize_path(path)
                if any(_path_within(normalized, prefix) for prefix in base_scope["pathPrefixes"]):
                    scope["pathPrefixes"] = sorted(set(scope["pathPrefixes"] + [normalized]))
                else:
                    reasons.add("widening_exceeds_profile_ceiling")
            for host in _string_list(widening.get("restoreNetworkDestinations"), "explicitWidening.restoreNetworkDestinations"):
                if _destination_allowed(host, base_scope["networkDestinations"]):
                    scope["networkDestinations"] = sorted(set(scope["networkDestinations"] + [host.lower()]))
                else:
                    reasons.add("widening_exceeds_profile_ceiling")
            for browser_profile in _string_list(widening.get("restoreBrowserProfiles"), "explicitWidening.restoreBrowserProfiles"):
                if "*" in base_scope["browserProfiles"] or browser_profile in base_scope["browserProfiles"]:
                    scope["browserProfiles"] = sorted(set(scope["browserProfiles"] + [browser_profile]))
                else:
                    reasons.add("widening_exceeds_profile_ceiling")
            for lease in _string_list(widening.get("restoreSecretLeaseIds"), "explicitWidening.restoreSecretLeaseIds"):
                if lease in base_scope["secretLeaseIds"]:
                    scope["secretLeaseIds"] = sorted(set(scope["secretLeaseIds"] + [lease]))
                else:
                    reasons.add("widening_exceeds_profile_ceiling")

    domain = effect.get("domain")
    action = effect.get("action")
    target = effect.get("target")
    if domain == "filesystem":
        if scope["filesystem"].get(action) is not True:
            reasons.add("filesystem_action_denied")
        if not isinstance(target, str) or not any(_path_within(target, prefix) for prefix in scope["pathPrefixes"]):
            reasons.add("path_outside_effective_scope")
    elif domain == "process":
        process = scope["process"]
        required_flag = {
            "finite_command": "finiteCommands",
            "interactive_pty": "interactivePty",
            "package": "packages",
            "service": "services",
        }.get(str(action))
        if action == "elevation":
            if process.get("elevation") not in {"interactive_only", "preconfigured"}:
                reasons.add("elevation_denied")
        elif required_flag is None or process.get(required_flag) is not True:
            reasons.add("process_action_denied")
    elif domain == "network":
        host = target if isinstance(target, str) else ""
        if not _destination_allowed(host, scope["networkDestinations"]):
            reasons.add("network_destination_denied")
        if context.get("privateNetwork") is True and scope["network"].get("privateAddresses") is not True:
            reasons.add("private_network_denied")
        if action == "listen" and scope["network"].get("listen") is not True:
            reasons.add("network_listen_denied")
    elif domain == "browser":
        browser_profile = target if isinstance(target, str) else ""
        if "*" not in scope["browserProfiles"] and browser_profile not in scope["browserProfiles"]:
            reasons.add("browser_profile_denied")
        if context.get("authenticatedBrowser") is True and scope["browser"].get("authenticatedProfiles") is not True:
            reasons.add("authenticated_browser_denied")
    elif domain == "secret":
        lease = target if isinstance(target, str) else ""
        if scope["credentials"].get("mode") == "none" or lease not in scope["secretLeaseIds"]:
            reasons.add("secret_lease_denied")
        if context.get("rawReveal") is True:
            reasons.add("raw_secret_reveal_denied")
    elif domain == "sandbox":
        if profile_id != "isolated_untrusted" or profile.get("sandboxed") is not True:
            reasons.add("sandbox_profile_required")
    else:
        reasons.add("unknown_effect_domain")

    risk = capability.get("risk")
    approval_required = approval_policy == "always" or (approval_policy == "high_risk_only" and risk == "high")
    blocking_reasons = set(reasons)
    if approval_required and not approved and not blocking_reasons:
        status = "approval_required"
        reason_codes = ("approval_required",)
    elif blocking_reasons:
        status = "deny"
        reason_codes = tuple(sorted(blocking_reasons))
    else:
        status = "allow"
        reason_codes = ()

    grant_draft = None
    if status == "allow":
        grant_draft = {
            "issuer": {"actorId": "desktop_host", "authority": "desktop_host:deterministic_policy"},
            "binding": {
                "runId": binding["runId"],
                "taskId": binding["taskId"],
                "actorId": actor_id,
                "toolId": tool_id,
                "accessProfileId": profile_id,
            },
            "capabilityId": capability_id,
            "scope": {
                "paths": list(scope["pathPrefixes"]),
                "networkDestinations": list(scope["networkDestinations"]),
                "browserProfiles": list(scope["browserProfiles"]),
                "secretLeaseIds": list(scope["secretLeaseIds"]),
                "effect": copy.deepcopy(effect),
            },
            "budgets": dict(budgets),
            "policyDecisionId": decision_id,
        }

    return PolicyDecision(
        decision_id=decision_id,
        status=status,
        reason_codes=reason_codes,
        effective_profile_id=profile_id,
        effective_scope=scope,
        effective_budgets=budgets,
        grant_draft=grant_draft,
    ).to_json()
