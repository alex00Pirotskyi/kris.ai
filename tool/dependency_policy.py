#!/usr/bin/env python3
from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import urllib.error
import urllib.request
from typing import Any, Iterable


ALLOWED_LICENSES = frozenset({
    "MIT",
    "Apache-2.0",
    "BSD-2-Clause",
    "BSD-3-Clause",
    "ISC",
    "MPL-2.0",
})
DENIED_LICENSES = frozenset({"GPL-2.0", "GPL-3.0", "AGPL-3.0", "SSPL-1.0", "BUSL-1.1"})


@dataclass(frozen=True)
class Dependency:
    ecosystem: str
    name: str
    version: str
    integrity: str
    license: str
    direct: bool

    @property
    def identity(self) -> str:
        return f"{self.ecosystem}:{self.name}@{self.version}"

    def osv_query(self) -> dict[str, object]:
        return {
            "package": {"ecosystem": self.ecosystem, "name": self.name},
            "version": self.version,
        }


def parse_npm_lock(path: Path) -> list[Dependency]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("lockfileVersion") != 3 or not isinstance(payload.get("packages"), dict):
        raise ValueError("npm_lock_v3_required")
    root = payload["packages"].get("") or {}
    direct_names = set((root.get("dependencies") or {}).keys()) | set((root.get("devDependencies") or {}).keys())
    dependencies: list[Dependency] = []
    for key, raw in sorted(payload["packages"].items()):
        if not key or not key.startswith("node_modules/") or not isinstance(raw, dict):
            continue
        name = key[len("node_modules/") :]
        version = str(raw.get("version") or "")
        integrity = str(raw.get("integrity") or "")
        license_name = str(raw.get("license") or "")
        resolved = str(raw.get("resolved") or "")
        if not version or not integrity.startswith("sha512-") or not resolved.startswith("https://registry.npmjs.org/"):
            raise ValueError(f"npm_lock_integrity_invalid:{name}")
        if not license_name:
            raise ValueError(f"npm_license_missing:{name}")
        dependencies.append(Dependency("npm", name, version, integrity, license_name, name in direct_names))
    return dependencies


def parse_pub_lock(path: Path, *, pub_cache: Path | None = None) -> list[Dependency]:
    lines = path.read_text(encoding="utf-8").splitlines()
    dependencies: list[Dependency] = []
    current: str | None = None
    current_indent = 0
    fields: dict[str, str] = {}

    def flush() -> None:
        nonlocal current, fields
        if current is None:
            return
        if fields.get("source") == "hosted":
            version = fields.get("version", "").strip('"')
            sha256 = fields.get("sha256", "").strip('"')
            if not version or not re.fullmatch(r"[0-9a-f]{64}", sha256):
                raise ValueError(f"pub_lock_integrity_invalid:{current}")
            license_name = detect_pub_license(pub_cache, current, version) if pub_cache else "UNVERIFIED"
            dependencies.append(
                Dependency(
                    "Pub",
                    current,
                    version,
                    f"sha256-{sha256}",
                    license_name,
                    fields.get("dependency", "").strip('"') == "direct main",
                )
            )
        current = None
        fields = {}

    for line in lines:
        if re.match(r"^  [A-Za-z0-9_.-]+:$", line):
            flush()
            current = line.strip()[:-1]
            current_indent = len(line) - len(line.lstrip())
            continue
        if current is None:
            continue
        indent = len(line) - len(line.lstrip())
        if indent <= current_indent and line.strip():
            flush()
            continue
        stripped = line.strip()
        if ":" in stripped:
            key, value = stripped.split(":", 1)
            if key in {"source", "version", "dependency", "sha256"}:
                fields[key] = value.strip()
    flush()
    return dependencies


def detect_pub_license(pub_cache: Path | None, name: str, version: str) -> str:
    if pub_cache is None:
        return "UNVERIFIED"
    roots = [pub_cache / "hosted" / "pub.dev", pub_cache / "hosted" / "pub.dartlang.org"]
    package = next((root / f"{name}-{version}" for root in roots if (root / f"{name}-{version}").is_dir()), None)
    if package is None:
        return "MISSING"
    candidates = [path for path in package.iterdir() if path.is_file() and path.name.upper().startswith("LICENSE")]
    if not candidates:
        return "MISSING"
    text = candidates[0].read_text(encoding="utf-8", errors="replace").lower()
    if "apache license" in text and "version 2.0" in text:
        return "Apache-2.0"
    if "mozilla public license" in text and "2.0" in text:
        return "MPL-2.0"
    if "permission is hereby granted, free of charge" in text:
        return "MIT"
    if "redistribution and use in source and binary forms" in text:
        return "BSD-3-Clause" if "neither the name" in text else "BSD-2-Clause"
    if "permission to use, copy, modify, and/or distribute this software" in text:
        return "ISC"
    if "gnu affero general public license" in text:
        return "AGPL-3.0"
    if "gnu general public license" in text:
        return "GPL-3.0"
    return "UNKNOWN"


def query_osv(dependencies: list[Dependency], *, timeout_seconds: int = 30) -> dict[str, list[dict[str, Any]]]:
    request = urllib.request.Request(
        "https://api.osv.dev/v1/querybatch",
        data=json.dumps({"queries": [dependency.osv_query() for dependency in dependencies]}).encode("utf-8"),
        headers={"Content-Type": "application/json", "User-Agent": "Kristin-P8-Dependency-Policy/1.0"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            payload = json.load(response)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"osv_scan_unavailable:{type(exc).__name__}") from exc
    results = payload.get("results")
    if not isinstance(results, list) or len(results) != len(dependencies):
        raise RuntimeError("osv_scan_response_invalid")
    output: dict[str, list[dict[str, Any]]] = {}
    for dependency, row in zip(dependencies, results, strict=True):
        vulns = row.get("vulns") if isinstance(row, dict) else None
        output[dependency.identity] = list(vulns) if isinstance(vulns, list) else []
    return output


def load_advisories(path: Path) -> dict[str, list[dict[str, Any]]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    rows = payload.get("dependencies")
    if not isinstance(rows, dict):
        raise ValueError("dependency_advisory_feed_invalid")
    return {str(key): list(value) if isinstance(value, list) else [] for key, value in rows.items()}


def evaluate(
    dependencies: list[Dependency],
    advisories: dict[str, list[dict[str, Any]]],
    *,
    allow_unverified_license: bool = False,
) -> dict[str, object]:
    failures: list[dict[str, object]] = []
    for dependency in dependencies:
        if dependency.license in DENIED_LICENSES:
            failures.append({"identity": dependency.identity, "code": "license_denied", "license": dependency.license})
        elif dependency.license not in ALLOWED_LICENSES:
            if not (allow_unverified_license and dependency.license == "UNVERIFIED"):
                failures.append({"identity": dependency.identity, "code": "license_unapproved", "license": dependency.license})
        vulnerabilities = advisories.get(dependency.identity)
        if vulnerabilities is None:
            failures.append({"identity": dependency.identity, "code": "advisory_result_missing"})
            continue
        for vulnerability in vulnerabilities:
            failures.append(
                {
                    "identity": dependency.identity,
                    "code": "known_vulnerability",
                    "advisoryId": str(vulnerability.get("id") or "unknown"),
                }
            )
    rows = [
        {
            "identity": item.identity,
            "license": item.license,
            "direct": item.direct,
            "integrity": item.integrity,
            "vulnerabilityCount": len(advisories.get(item.identity, [])),
        }
        for item in sorted(dependencies, key=lambda item: item.identity)
    ]
    canonical = json.dumps(rows, sort_keys=True, separators=(",", ":"))
    return {
        "schemaVersion": "1.0.0",
        "passed": not failures,
        "dependencyCount": len(rows),
        "dependencySetSha256": hashlib.sha256(canonical.encode("utf-8")).hexdigest(),
        "dependencies": rows,
        "failures": failures,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=".")
    parser.add_argument("--pub-cache", default=os.environ.get("PUB_CACHE", ""))
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--online-osv", action="store_true")
    source.add_argument("--advisories")
    parser.add_argument("--report", default="release/DEPENDENCY_POLICY.json")
    parser.add_argument("--allow-unverified-pub-license", action="store_true")
    args = parser.parse_args()
    root = Path(args.project).resolve()
    pub_cache = Path(args.pub_cache).expanduser().resolve() if args.pub_cache else None
    dependencies = parse_npm_lock(root / "automation_host" / "package-lock.json")
    dependencies.extend(parse_pub_lock(root / "pubspec.lock", pub_cache=pub_cache))
    advisories = query_osv(dependencies) if args.online_osv else load_advisories(Path(args.advisories).resolve())
    report = evaluate(
        dependencies,
        advisories,
        allow_unverified_license=args.allow_unverified_pub_license,
    )
    report["generatedAt"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    target = root / args.report
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "dependencyCount": report["dependencyCount"], "report": str(target)}, sort_keys=True))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
