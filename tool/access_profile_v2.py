#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping

PROFILE_IDS = ("chat", "project", "owner", "owner_unattended", "isolated_untrusted")
APPROVAL_POLICIES = ("always", "high_risk_only", "never")


class AccessProfileValidationError(ValueError):
    pass


def _require_mapping(value: Any, label: str) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        raise AccessProfileValidationError(f"{label} must be an object")
    return dict(value)


def _require_bool(value: Any, label: str) -> bool:
    if not isinstance(value, bool):
        raise AccessProfileValidationError(f"{label} must be boolean")
    return value


def _set_dotted(target: dict[str, Any], dotted: str, value: Any) -> None:
    parts = dotted.split(".")
    current = target
    for part in parts[:-1]:
        child = current.get(part)
        if not isinstance(child, dict):
            raise AccessProfileValidationError(f"cannot patch non-object path: {dotted}")
        current = child
    current[parts[-1]] = value


def validate_profile(value: Mapping[str, Any]) -> dict[str, Any]:
    profile = copy.deepcopy(_require_mapping(value, "profile"))
    profile_id = profile.get("profileId")
    if profile.get("schemaVersion") != "2.0.0":
        raise AccessProfileValidationError("schemaVersion must be 2.0.0")
    if profile_id not in PROFILE_IDS:
        raise AccessProfileValidationError(f"unknown profileId: {profile_id}")
    if not isinstance(profile.get("profileRevision"), int) or profile["profileRevision"] < 1:
        raise AccessProfileValidationError("profileRevision must be a positive integer")
    if profile.get("approvalPolicy") not in APPROVAL_POLICIES:
        raise AccessProfileValidationError("invalid approvalPolicy")
    for field in ("sandboxed", "interactive", "unattendedAllowed"):
        _require_bool(profile.get(field), field)
    filesystem = _require_mapping(profile.get("filesystem"), "filesystem")
    process = _require_mapping(profile.get("process"), "process")
    network = _require_mapping(profile.get("network"), "network")
    browser = _require_mapping(profile.get("browser"), "browser")
    credentials = _require_mapping(profile.get("credentials"), "credentials")
    boundary = _require_mapping(profile.get("dataBoundary"), "dataBoundary")
    if boundary.get("contentMayBecomeAuthority") is not False:
        raise AccessProfileValidationError("content cannot become authority")
    if profile_id == "chat":
        if any(
            (
                filesystem.get("read"), filesystem.get("write"), filesystem.get("delete"),
                process.get("finiteCommands"), process.get("interactivePty"),
                network.get("scope") != "none", browser.get("scope") != "none",
                credentials.get("mode") != "none",
            )
        ):
            raise AccessProfileValidationError("chat profile cannot authorize effects")
    elif profile_id == "project":
        if filesystem.get("scope") != "project" or not filesystem.get("roots"):
            raise AccessProfileValidationError("project profile requires project roots")
        if filesystem.get("absolutePaths") is not False:
            raise AccessProfileValidationError("project profile cannot authorize arbitrary absolute paths")
        if process.get("elevation") != "none" or process.get("services") is not False:
            raise AccessProfileValidationError("project profile cannot elevate or control services")
    elif profile_id == "owner":
        if profile.get("sandboxed") is not False or filesystem.get("scope") != "current_account":
            raise AccessProfileValidationError("owner must be explicit non-sandbox authority")
        if profile.get("interactive") is not True or profile.get("unattendedAllowed") is not False:
            raise AccessProfileValidationError("owner profile must remain interactive")
        if credentials.get("rawReveal") not in ("never", "interactive_break_glass"):
            raise AccessProfileValidationError("owner rawReveal is invalid")
    elif profile_id == "owner_unattended":
        if profile.get("sandboxed") is not False or filesystem.get("scope") != "current_account":
            raise AccessProfileValidationError("owner_unattended must be explicit non-sandbox authority")
        if profile.get("interactive") is not False or profile.get("unattendedAllowed") is not True:
            raise AccessProfileValidationError("owner_unattended lifecycle is invalid")
        if process.get("elevation") != "none":
            raise AccessProfileValidationError("owner_unattended cannot request elevation")
        if credentials.get("rawReveal") != "never":
            raise AccessProfileValidationError("unattended raw secret reveal is forbidden")
        if credentials.get("mode") != "brokered_leases" or credentials.get("unattendedUse") is not True:
            raise AccessProfileValidationError("owner_unattended requires brokered unattended leases")
    elif profile_id == "isolated_untrusted":
        if profile.get("sandboxed") is not True:
            raise AccessProfileValidationError("isolated_untrusted must be sandboxed")
        if filesystem.get("scope") != "sandbox" or filesystem.get("absolutePaths") is not False:
            raise AccessProfileValidationError("isolated_untrusted filesystem must remain sandbox-only")
        if process.get("scope") != "sandbox" or process.get("elevation") != "none":
            raise AccessProfileValidationError("isolated_untrusted process scope is invalid")
        if credentials.get("mode") != "none" or credentials.get("rawReveal") != "never":
            raise AccessProfileValidationError("isolated_untrusted credentials must be none")
        if network.get("privateAddresses") is not False or network.get("listen") is not False:
            raise AccessProfileValidationError("isolated_untrusted network must reject private/listening access")
        if browser.get("authenticatedProfiles") is not False:
            raise AccessProfileValidationError("isolated_untrusted cannot use authenticated browser profiles")
    return profile


@dataclass(frozen=True)
class AccessProfileV2:
    value: dict[str, Any]

    @classmethod
    def from_json(cls, value: Mapping[str, Any]) -> "AccessProfileV2":
        return cls(validate_profile(value))

    @classmethod
    def from_file(cls, path: str | Path) -> "AccessProfileV2":
        return cls.from_json(json.loads(Path(path).read_text(encoding="utf-8")))

    @property
    def profile_id(self) -> str:
        return str(self.value["profileId"])

    def to_json(self) -> dict[str, Any]:
        return copy.deepcopy(self.value)

    def canonical_json(self) -> str:
        return json.dumps(self.value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def load_catalog(path: str | Path) -> dict[str, AccessProfileV2]:
    raw = json.loads(Path(path).read_text(encoding="utf-8"))
    if raw.get("schemaVersion") != "2.0.0":
        raise AccessProfileValidationError("catalog schemaVersion must be 2.0.0")
    if raw.get("authoritySemantics") != "maximum_ceiling_not_capability_grant":
        raise AccessProfileValidationError("catalog must declare ceiling-not-grant semantics")
    if raw.get("overlaysMayOnlyNarrow") is not True:
        raise AccessProfileValidationError("overlaysMayOnlyNarrow must be true")
    profiles = [AccessProfileV2.from_json(value) for value in raw.get("profiles", [])]
    result = {value.profile_id: value for value in profiles}
    if tuple(sorted(result)) != tuple(sorted(PROFILE_IDS)) or len(profiles) != len(result):
        raise AccessProfileValidationError("catalog must contain each canonical profile exactly once")
    if raw.get("defaultProfile") != "chat":
        raise AccessProfileValidationError("defaultProfile must be chat")
    return result


def apply_fixture_patch(profile: Mapping[str, Any], patch: Mapping[str, Any]) -> dict[str, Any]:
    value = copy.deepcopy(dict(profile))
    for dotted, replacement in patch.items():
        _set_dotted(value, str(dotted), replacement)
    return value
