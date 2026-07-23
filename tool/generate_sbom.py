#!/usr/bin/env python3
"""Generate a deterministic CycloneDX SBOM from pubspec and pubspec.lock."""
from __future__ import annotations

from pathlib import Path
import hashlib
import json
import re
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
VERSION = "1.9.0+190"


def declared_dependencies() -> dict[str, dict[str, str]]:
    pubspec = ROOT / "pubspec.yaml"
    if not pubspec.exists():
        return {}
    output: dict[str, dict[str, str]] = {}
    section: str | None = None
    current: str | None = None
    for raw in pubspec.read_text(encoding="utf-8", errors="replace").splitlines():
        if raw and not raw.startswith(" "):
            key = raw.split(":", 1)[0].strip()
            section = key if key in {"dependencies", "dev_dependencies"} else None
            current = None
            continue
        if section is None:
            continue
        match = re.match(r"^  ([A-Za-z0-9_+.-]+):(?:\s*(.*?)\s*)?$", raw)
        if match:
            current = match.group(1)
            constraint = (match.group(2) or "").strip().strip("'\"")
            output[current] = {
                "name": current,
                "scope": "optional" if section == "dev_dependencies" else "required",
                "declared": constraint or "sdk-or-nested",
                "source": "pubspec.yaml",
            }
            continue
        if current is not None:
            sdk = re.match(r"^    sdk:\s*([^#\s]+)", raw)
            if sdk:
                output[current]["declared"] = f"sdk:{sdk.group(1)}"
    return output


def locked_dependencies() -> dict[str, dict[str, str]]:
    lock = ROOT / "pubspec.lock"
    if not lock.exists():
        return {}
    output: dict[str, dict[str, str]] = {}
    current: str | None = None
    for raw in lock.read_text(encoding="utf-8", errors="replace").splitlines():
        match = re.match(r"^  ([A-Za-z0-9_+.-]+):\s*$", raw)
        if match:
            current = match.group(1)
            output[current] = {"name": current, "source": "pubspec.lock"}
            continue
        if current is None:
            continue
        version = re.match(r'^    version:\s*["\']?([^"\']+)["\']?\s*$', raw)
        if version:
            output[current]["version"] = version.group(1)
        dependency = re.match(r"^    dependency:\s*(.+?)\s*$", raw)
        if dependency:
            value = dependency.group(1)
            output[current]["scope"] = "optional" if value == "direct dev" else "required"
    return output


def component(name: str, data: dict[str, str]) -> dict[str, object]:
    version = data.get("version") or data.get("declared") or "unresolved"
    encoded_version = quote(version, safe="._-")
    result: dict[str, object] = {
        "type": "framework" if version.startswith("sdk:") else "library",
        "name": name,
        "version": version,
        "scope": data.get("scope", "required"),
        "bom-ref": f"pkg:pub/{name}@{encoded_version}",
        "purl": f"pkg:pub/{name}@{encoded_version}",
        "properties": [
            {"name": "kristin:dependency-source", "value": data.get("source", "unknown")},
            {"name": "kristin:resolution", "value": "locked" if data.get("version") else "declared-only"},
        ],
    }
    if data.get("declared"):
        result["properties"].append({"name": "kristin:declared-constraint", "value": data["declared"]})
    return result


declared = declared_dependencies()
locked = locked_dependencies()
merged: dict[str, dict[str, str]] = {}
for name in sorted(set(declared) | set(locked)):
    merged[name] = {**declared.get(name, {}), **locked.get(name, {})}
    if name in declared:
        merged[name].setdefault("scope", declared[name]["scope"])
        merged[name].setdefault("declared", declared[name]["declared"])

components = [component(name, merged[name]) for name in sorted(merged)]
identity = ";".join(str(item["bom-ref"]) for item in components)
serial = hashlib.sha256(f"kristin-{VERSION};{identity}".encode("utf-8")).hexdigest()
sbom = {
    "bomFormat": "CycloneDX",
    "specVersion": "1.5",
    "serialNumber": f"urn:uuid:{serial[:8]}-{serial[8:12]}-{serial[12:16]}-{serial[16:20]}-{serial[20:32]}",
    "version": 1,
    "metadata": {
        "timestamp": "2026-07-22T00:00:00Z",
        "component": {
            "type": "application",
            "name": "Kristin Local Agent",
            "version": VERSION,
        },
        "properties": [
            {
                "name": "kristin:lockfile-status",
                "value": "present" if (ROOT / "pubspec.lock").exists() else "absent-resolve-on-target",
            }
        ],
    },
    "components": components,
}
out = ROOT / "release" / "SBOM.cdx.json"
out.parent.mkdir(exist_ok=True)
out.write_text(json.dumps(sbom, indent=2, sort_keys=True) + "\n", encoding="utf-8")
