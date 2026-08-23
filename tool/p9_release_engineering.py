#!/usr/bin/env python3
"""P9 release packaging, SBOM, provenance, signing-boundary and reproducibility tooling."""
from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import os
from pathlib import Path, PurePosixPath, PureWindowsPath
import re
import stat
import subprocess
import sys
import tempfile
import zipfile
from typing import Any, Iterable, Mapping

TOOL_VERSION = "1.0.0"
SUPPORTED_PLATFORMS = frozenset({"windows", "macos", "linux"})
DEFAULT_CONFIG = Path("config/release_targets.v1.json")
RELEASE_MANIFEST = "KRISTIN_RELEASE_MANIFEST.json"
SBOM_NAME = "KRISTIN_SBOM.spdx.json"


class ReleaseEngineeringError(ValueError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def canonical_json_bytes(value: Any) -> bytes:
    return (json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _safe_relative(value: str, *, field: str = "path") -> str:
    raw = str(value).replace("\\", "/").strip()
    while raw.startswith("./"):
        raw = raw[2:]
    posix = PurePosixPath(raw)
    windows = PureWindowsPath(raw)
    if (
        not raw
        or raw == "."
        or raw.startswith("/")
        or posix.is_absolute()
        or windows.is_absolute()
        or windows.drive
        or ".." in posix.parts
        or ".." in windows.parts
        or "\0" in raw
    ):
        raise ReleaseEngineeringError("unsafe_path", f"{field} must be repository-relative: {value!r}")
    return posix.as_posix()


def _load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ReleaseEngineeringError("json_invalid", f"cannot load {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ReleaseEngineeringError("json_invalid", f"{path} must contain a JSON object")
    return value


def load_release_config(project: Path, relative: Path = DEFAULT_CONFIG) -> dict[str, Any]:
    path = project / relative
    data = _load_json(path)
    if data.get("schemaVersion") != 1:
        raise ReleaseEngineeringError("config_version", "release target schemaVersion must be 1")
    if not isinstance(data.get("productVersion"), str) or not data["productVersion"].strip():
        raise ReleaseEngineeringError("config_version", "productVersion is required")
    targets = data.get("targets")
    if not isinstance(targets, dict) or set(targets) != SUPPORTED_PLATFORMS:
        raise ReleaseEngineeringError("config_targets", "release targets must be exactly windows, macos and linux")
    for platform, target in targets.items():
        if not isinstance(target, dict):
            raise ReleaseEngineeringError("config_target", f"target {platform} must be an object")
        argv = target.get("buildArgv")
        if not isinstance(argv, list) or not argv or any(not isinstance(x, str) or not x for x in argv):
            raise ReleaseEngineeringError("config_command", f"target {platform} has invalid buildArgv")
        if argv[0] != "flutter" or "clean" in argv:
            raise ReleaseEngineeringError("config_command", f"target {platform} buildArgv must be an incremental Flutter build")
        _safe_relative(target.get("artifactPath", ""), field=f"{platform}.artifactPath")
        signing = target.get("signing")
        if not isinstance(signing, dict) or signing.get("credentialBoundary") != "external":
            raise ReleaseEngineeringError("config_signing", f"target {platform} must keep signing credentials external")
    return data


def parse_pubspec_lock(path: Path) -> list[dict[str, str]]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ReleaseEngineeringError("lock_missing", f"cannot read {path}: {exc}") from exc
    packages: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for line in lines:
        package_match = re.match(r"^  ([A-Za-z0-9_.-]+):\s*$", line)
        if package_match:
            if current and current.get("name") and current.get("version"):
                packages.append(current)
            current = {"name": package_match.group(1)}
            continue
        if current is None:
            continue
        version_match = re.match(r'^    version:\s+["\']?([^"\']+)["\']?\s*$', line)
        if version_match:
            current["version"] = version_match.group(1)
            continue
        source_match = re.match(r"^    source:\s+(.+?)\s*$", line)
        if source_match:
            current["source"] = source_match.group(1).strip('"\'')
        checksum_match = re.match(r'^      sha256:\s+["\']?([0-9a-fA-F]{64})["\']?\s*$', line)
        if checksum_match:
            current["checksum"] = checksum_match.group(1).lower()
    if current and current.get("name") and current.get("version"):
        packages.append(current)
    if not packages:
        raise ReleaseEngineeringError("lock_invalid", "pubspec.lock contains no resolved packages")
    names = [row["name"] for row in packages]
    if len(names) != len(set(names)):
        raise ReleaseEngineeringError("lock_invalid", "pubspec.lock contains duplicate package identities")
    return packages


def build_spdx_sbom(project: Path, *, version: str) -> dict[str, Any]:
    lock = project / "pubspec.lock"
    packages = parse_pubspec_lock(lock)
    rows = []
    for package in sorted(packages, key=lambda row: row["name"]):
        name = package["name"]
        package_version = package["version"]
        row: dict[str, Any] = {
            "SPDXID": f"SPDXRef-Package-{re.sub(r'[^A-Za-z0-9.-]+', '-', name)}",
            "name": name,
            "versionInfo": package_version,
            "downloadLocation": "NOASSERTION",
            "filesAnalyzed": False,
            "supplier": "NOASSERTION",
        }
        if package.get("source") == "hosted":
            row["externalRefs"] = [{
                "referenceCategory": "PACKAGE-MANAGER",
                "referenceType": "purl",
                "referenceLocator": f"pkg:pub/{name}@{package_version}",
            }]
        if package.get("checksum"):
            row["checksums"] = [{"algorithm": "SHA256", "checksumValue": package["checksum"]}]
        rows.append(row)
    return {
        "spdxVersion": "SPDX-2.3",
        "dataLicense": "CC0-1.0",
        "SPDXID": "SPDXRef-DOCUMENT",
        "name": f"Kristin Local Agent {version}",
        "documentNamespace": f"https://kristin.invalid/spdx/{version}/{sha256_file(lock)}",
        "creationInfo": {
            "creators": [f"Tool: Kristin-P9-Release-Engineering-{TOOL_VERSION}"],
            "created": "1970-01-01T00:00:00Z",
        },
        "packages": rows,
    }


@dataclasses.dataclass(frozen=True)
class ArtifactEntry:
    relative: str
    path: Path
    entry_type: str
    mode: int
    link_target: str | None = None


def _safe_symlink_target(path: Path, root: Path) -> str:
    raw = os.readlink(path)
    if not isinstance(raw, str) or not raw or "\0" in raw:
        raise ReleaseEngineeringError("artifact_symlink", f"artifact symlink has an invalid target: {path}")
    posix = PurePosixPath(raw.replace("\\", "/"))
    windows = PureWindowsPath(raw)
    if posix.is_absolute() or windows.is_absolute() or windows.drive:
        raise ReleaseEngineeringError("artifact_symlink_escape", f"artifact symlink target must be relative: {path}")
    resolved_root = root.resolve()
    try:
        resolved_target = (path.parent / raw).resolve(strict=False)
        resolved_target.relative_to(resolved_root)
    except (OSError, ValueError) as exc:
        raise ReleaseEngineeringError("artifact_symlink_escape", f"artifact symlink escapes root: {path}") from exc
    return raw


def _is_junction(path: Path) -> bool:
    probe = getattr(path, "is_junction", None)
    if probe is None:
        return False
    try:
        return bool(probe())
    except OSError as exc:
        raise ReleaseEngineeringError("artifact_reparse", f"cannot classify artifact reparse point: {path}: {exc}") from exc


def _iter_artifact_entries(root: Path) -> list[ArtifactEntry]:
    if not root.exists():
        raise ReleaseEngineeringError("artifact_missing", f"artifact path does not exist: {root}")
    if root.is_symlink():
        raise ReleaseEngineeringError("artifact_symlink", "artifact root may not be a symlink")
    if _is_junction(root):
        raise ReleaseEngineeringError("artifact_reparse", "artifact root may not be a Windows junction/reparse point")
    if root.is_file():
        mode = stat.S_IMODE(root.stat().st_mode)
        return [ArtifactEntry(root.name, root, "file", mode)]
    result: list[ArtifactEntry] = []
    resolved_root = root.resolve()
    for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
        relative = _safe_relative(path.relative_to(root).as_posix(), field="artifact entry")
        if _is_junction(path):
            raise ReleaseEngineeringError("artifact_reparse", f"artifact contains unsupported Windows junction/reparse point: {path}")
        if path.is_symlink():
            target = _safe_symlink_target(path, root)
            mode = stat.S_IMODE(path.lstat().st_mode) or 0o777
            result.append(ArtifactEntry(relative, path, "symlink", mode, target))
            continue
        if path.is_dir():
            continue
        if not path.is_file():
            raise ReleaseEngineeringError("artifact_type", f"artifact contains unsupported filesystem entry: {path}")
        resolved = path.resolve()
        try:
            resolved.relative_to(resolved_root)
        except ValueError as exc:
            raise ReleaseEngineeringError("artifact_escape", f"artifact escapes root: {path}") from exc
        mode = stat.S_IMODE(path.stat().st_mode)
        result.append(ArtifactEntry(relative, path, "file", mode))
    if not result:
        raise ReleaseEngineeringError("artifact_empty", "artifact directory contains no files")
    return result


def artifact_file_manifest(root: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for entry in _iter_artifact_entries(root):
        if entry.entry_type == "symlink":
            target_bytes = str(entry.link_target).encode("utf-8")
            rows.append({
                "path": entry.relative,
                "type": "symlink",
                "mode": entry.mode,
                "target": entry.link_target,
                "bytes": len(target_bytes),
                "sha256": sha256_bytes(target_bytes),
            })
        else:
            rows.append({
                "path": entry.relative,
                "type": "file",
                "mode": entry.mode,
                "bytes": entry.path.stat().st_size,
                "sha256": sha256_file(entry.path),
            })
    return rows


def artifact_tree_sha256(rows: Iterable[Mapping[str, Any]]) -> str:
    normalized: list[dict[str, Any]] = []
    seen: set[str] = set()
    for row in rows:
        path = _safe_relative(str(row["path"]), field="artifact manifest path")
        if path in seen:
            raise ReleaseEngineeringError("artifact_duplicate", f"artifact manifest contains duplicate path: {path}")
        seen.add(path)
        entry_type = str(row.get("type") or "file")
        if entry_type not in {"file", "symlink"}:
            raise ReleaseEngineeringError("artifact_type", f"unsupported artifact manifest type: {entry_type}")
        item = {
            "path": path,
            "type": entry_type,
            "mode": int(row.get("mode", 0)),
            "bytes": int(row["bytes"]),
            "sha256": str(row["sha256"]),
        }
        if entry_type == "symlink":
            item["target"] = str(row.get("target") or "")
        normalized.append(item)
    normalized.sort(key=lambda item: item["path"])
    return sha256_bytes(canonical_json_bytes(normalized))


def _zip_info(name: str, *, mode: int, file_type: int) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_STORED
    info.create_system = 3
    info.external_attr = ((file_type | (mode & 0o777)) & 0xFFFF) << 16
    return info


def _zip_write_bytes(archive: zipfile.ZipFile, name: str, data: bytes, *, mode: int = 0o644) -> None:
    archive.writestr(_zip_info(name, mode=mode, file_type=stat.S_IFREG), data)


def _zip_write_entry(archive: zipfile.ZipFile, entry: ArtifactEntry) -> None:
    name = f"payload/{entry.relative}"
    if entry.entry_type == "symlink":
        archive.writestr(
            _zip_info(name, mode=entry.mode or 0o777, file_type=stat.S_IFLNK),
            str(entry.link_target).encode("utf-8"),
        )
        return
    archive.writestr(
        _zip_info(name, mode=entry.mode or 0o644, file_type=stat.S_IFREG),
        entry.path.read_bytes(),
    )


def validate_signing_evidence(platform: str, evidence: Mapping[str, Any], *, subject_sha256: str) -> dict[str, Any]:
    expected_scheme = {
        "windows": "authenticode",
        "macos": "codesign+notarization",
        "linux": "detached-package-signature",
    }[platform]
    if evidence.get("scheme") != expected_scheme:
        raise ReleaseEngineeringError("signing_scheme", f"{platform} requires {expected_scheme}")
    if evidence.get("verified") is not True:
        raise ReleaseEngineeringError("signing_unverified", "signing evidence is not verified")
    if evidence.get("subjectSha256") != subject_sha256:
        raise ReleaseEngineeringError("signing_digest", "signing evidence does not bind the exact native artifact tree")
    if not str(evidence.get("identity") or "").strip():
        raise ReleaseEngineeringError("signing_identity", "signing identity is required")
    if platform == "macos" and evidence.get("notarizationVerified") is not True:
        raise ReleaseEngineeringError("notarization_unverified", "macOS release requires verified notarization evidence")
    return {
        "scheme": expected_scheme,
        "verified": True,
        "identity": str(evidence["identity"]),
        "subjectSha256": subject_sha256,
        **({"notarizationVerified": True} if platform == "macos" else {}),
    }


def create_release_bundle(
    *,
    project: Path,
    artifact: Path,
    platform: str,
    output: Path,
    source_commit: str,
    signing_evidence: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    project = project.resolve()
    if platform not in SUPPORTED_PLATFORMS:
        raise ReleaseEngineeringError("platform_unsupported", f"unsupported platform: {platform}")
    config = load_release_config(project)
    version = str(config["productVersion"])
    if not re.fullmatch(r"[0-9a-f]{40}", source_commit):
        raise ReleaseEngineeringError("source_identity", "source_commit must be an exact 40-character Git SHA")
    files = artifact_file_manifest(artifact)
    tree_sha = artifact_tree_sha256(files)
    signing = None
    if signing_evidence is not None:
        signing = validate_signing_evidence(platform, signing_evidence, subject_sha256=tree_sha)
    sbom = build_spdx_sbom(project, version=version)
    lock_sha = sha256_file(project / "pubspec.lock")
    release_manifest = {
        "schemaVersion": 1,
        "product": config.get("product", "Kristin Local Agent"),
        "version": version,
        "platform": platform,
        "sourceCommit": source_commit,
        "artifactTreeSha256": tree_sha,
        "files": files,
        "dependencyLocks": {"pubspec.lock": lock_sha},
        "packageKind": config["targets"][platform]["packageKind"],
        "osSigningEvidenceBound": signing is not None,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{output.name}.", suffix=".tmp", dir=output.parent)
    os.close(fd)
    temp_path = Path(temp_name)
    try:
        with zipfile.ZipFile(temp_path, "w", allowZip64=True) as archive:
            for entry in _iter_artifact_entries(artifact):
                _zip_write_entry(archive, entry)
            _zip_write_bytes(archive, RELEASE_MANIFEST, canonical_json_bytes(release_manifest))
            _zip_write_bytes(archive, SBOM_NAME, canonical_json_bytes(sbom))
        os.replace(temp_path, output)
    finally:
        temp_path.unlink(missing_ok=True)
    bundle_sha = sha256_file(output)
    provenance = {
        "schemaVersion": 1,
        "builder": f"Kristin-P9-Release-Engineering/{TOOL_VERSION}",
        "sourceCommit": source_commit,
        "platform": platform,
        "version": version,
        "buildArgv": config["targets"][platform]["buildArgv"],
        "artifactTreeSha256": tree_sha,
        "bundleSha256": bundle_sha,
        "bundleBytes": output.stat().st_size,
        "dependencyLocks": {"pubspec.lock": lock_sha},
        "releaseTargetConfigSha256": sha256_file(project / DEFAULT_CONFIG),
        "sbomSha256": sha256_bytes(canonical_json_bytes(sbom)),
        "osSigning": signing or {
            "verified": False,
            "scheme": config["targets"][platform]["signing"]["scheme"],
            "credentialBoundary": "external",
        },
        "supportClaim": "OS_SIGNING_EVIDENCE_BOUND" if signing else "UNSIGNED_RELEASE_FOUNDATION",
    }
    provenance_path = output.with_suffix(output.suffix + ".provenance.json")
    provenance_path.write_bytes(canonical_json_bytes(provenance))
    return {"bundle": str(output), "provenance": str(provenance_path), **provenance}


def verify_release_bundle(
    *,
    project: Path,
    bundle: Path,
    provenance_path: Path,
    require_signed: bool = False,
) -> dict[str, Any]:
    provenance = _load_json(provenance_path)
    actual_bundle_sha = sha256_file(bundle)
    if provenance.get("bundleSha256") != actual_bundle_sha:
        raise ReleaseEngineeringError("bundle_digest", "bundle SHA-256 does not match provenance")
    if provenance.get("dependencyLocks", {}).get("pubspec.lock") != sha256_file(project / "pubspec.lock"):
        raise ReleaseEngineeringError("lock_drift", "pubspec.lock differs from the release provenance")
    if provenance.get("releaseTargetConfigSha256") != sha256_file(project / DEFAULT_CONFIG):
        raise ReleaseEngineeringError("config_drift", "release target configuration differs from the provenance")
    with zipfile.ZipFile(bundle, "r") as archive:
        infos = archive.infolist()
        normalized_names: list[str] = []
        for info in infos:
            normalized_names.append(_safe_relative(info.filename, field="bundle entry"))
        if len(normalized_names) != len(set(normalized_names)):
            raise ReleaseEngineeringError("bundle_duplicate", "bundle contains duplicate or normalization-colliding paths")
        try:
            manifest = json.loads(archive.read(RELEASE_MANIFEST))
            sbom = json.loads(archive.read(SBOM_NAME))
        except (KeyError, json.JSONDecodeError) as exc:
            raise ReleaseEngineeringError("bundle_metadata", "bundle metadata is missing or invalid") from exc
        rows = manifest.get("files")
        if not isinstance(rows, list) or not rows:
            raise ReleaseEngineeringError("bundle_metadata", "release manifest contains no artifact files")
        expected_names = {RELEASE_MANIFEST, SBOM_NAME}
        for row in rows:
            if not isinstance(row, dict):
                raise ReleaseEngineeringError("bundle_metadata", "release manifest file rows must be objects")
            relative = _safe_relative(str(row.get("path", "")), field="manifest file")
            payload_name = f"payload/{relative}"
            expected_names.add(payload_name)
            try:
                info = archive.getinfo(payload_name)
                data = archive.read(info)
            except KeyError as exc:
                raise ReleaseEngineeringError("bundle_file_missing", f"missing payload entry: {relative}") from exc
            entry_type = str(row.get("type") or "file")
            archived_mode = (info.external_attr >> 16) & 0o777
            archived_type = stat.S_IFMT((info.external_attr >> 16) & 0xFFFF)
            if archived_mode != int(row.get("mode", 0)) & 0o777:
                raise ReleaseEngineeringError("bundle_file_mode", f"payload mode mismatch: {relative}")
            if entry_type == "symlink":
                if archived_type != stat.S_IFLNK:
                    raise ReleaseEngineeringError("bundle_file_type", f"payload is not a symlink: {relative}")
                try:
                    target = data.decode("utf-8")
                except UnicodeDecodeError as exc:
                    raise ReleaseEngineeringError("bundle_symlink", f"symlink target is not UTF-8: {relative}") from exc
                if target != row.get("target"):
                    raise ReleaseEngineeringError("bundle_symlink", f"symlink target mismatch: {relative}")
            elif entry_type == "file":
                if archived_type == stat.S_IFLNK:
                    raise ReleaseEngineeringError("bundle_file_type", f"regular payload encoded as symlink: {relative}")
            else:
                raise ReleaseEngineeringError("bundle_file_type", f"unsupported manifest entry type: {entry_type}")
            if len(data) != row.get("bytes") or sha256_bytes(data) != row.get("sha256"):
                raise ReleaseEngineeringError("bundle_file_digest", f"payload mismatch: {relative}")
        if set(normalized_names) != expected_names:
            extra = sorted(set(normalized_names) - expected_names)
            missing = sorted(expected_names - set(normalized_names))
            raise ReleaseEngineeringError("bundle_layout", f"bundle layout differs from manifest; extra={extra}, missing={missing}")
        computed_tree = artifact_tree_sha256(rows)
        if manifest.get("artifactTreeSha256") != computed_tree:
            raise ReleaseEngineeringError("bundle_tree_digest", "artifact tree digest is invalid")
        for field in ("platform", "version", "sourceCommit", "artifactTreeSha256"):
            if manifest.get(field) != provenance.get(field):
                raise ReleaseEngineeringError("metadata_binding", f"release manifest {field} does not match provenance")
        if manifest.get("osSigningEvidenceBound") is not (provenance.get("osSigning", {}).get("verified") is True):
            raise ReleaseEngineeringError("metadata_binding", "release manifest signing-evidence state does not match provenance")
        if sbom.get("spdxVersion") != "SPDX-2.3" or not sbom.get("packages"):
            raise ReleaseEngineeringError("sbom_invalid", "SPDX SBOM is missing resolved packages")
        if provenance.get("sbomSha256") != sha256_bytes(canonical_json_bytes(sbom)):
            raise ReleaseEngineeringError("sbom_digest", "SPDX SBOM does not match provenance")
    signing = provenance.get("osSigning", {})
    signed = signing.get("verified") is True
    if require_signed and not signed:
        raise ReleaseEngineeringError("signing_required", "signed release required but no verified signing evidence is bound")
    if signed:
        validate_signing_evidence(
            str(provenance.get("platform")),
            signing,
            subject_sha256=str(manifest.get("artifactTreeSha256") or ""),
        )
    return {
        "schemaVersion": 1,
        "resultState": "PASS",
        "platform": provenance.get("platform"),
        "version": provenance.get("version"),
        "bundleSha256": actual_bundle_sha,
        "signed": signed,
        "supportClaim": "OS_SIGNING_EVIDENCE_BOUND" if signed else "UNSIGNED_RELEASE_FOUNDATION",
    }


def run_incremental_build(project: Path, platform: str) -> dict[str, Any]:
    config = load_release_config(project)
    if platform not in SUPPORTED_PLATFORMS:
        raise ReleaseEngineeringError("platform_unsupported", f"unsupported platform: {platform}")
    argv = list(config["targets"][platform]["buildArgv"])
    proc = subprocess.run(argv, cwd=project, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    if proc.returncode != 0:
        raise ReleaseEngineeringError("build_failed", proc.stdout[-12000:])
    artifact = project / _safe_relative(config["targets"][platform]["artifactPath"])
    if not artifact.exists():
        raise ReleaseEngineeringError("artifact_missing", f"build succeeded but artifact is missing: {artifact}")
    return {"argv": argv, "artifact": str(artifact), "outputTail": proc.stdout[-4000:]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    plan = sub.add_parser("plan")
    plan.add_argument("--project", default=".")
    plan.add_argument("--platform", choices=sorted(SUPPORTED_PLATFORMS), required=True)
    build = sub.add_parser("build")
    build.add_argument("--project", default=".")
    build.add_argument("--platform", choices=sorted(SUPPORTED_PLATFORMS), required=True)
    package = sub.add_parser("package")
    package.add_argument("--project", default=".")
    package.add_argument("--platform", choices=sorted(SUPPORTED_PLATFORMS), required=True)
    package.add_argument("--artifact", required=True)
    package.add_argument("--output", required=True)
    package.add_argument("--source-commit", required=True)
    package.add_argument("--signing-evidence")
    verify = sub.add_parser("verify")
    verify.add_argument("--project", default=".")
    verify.add_argument("--bundle", required=True)
    verify.add_argument("--provenance", required=True)
    verify.add_argument("--require-signed", action="store_true")
    args = parser.parse_args()
    try:
        project = Path(args.project).resolve()
        if args.command == "plan":
            config = load_release_config(project)
            target = config["targets"][args.platform]
            result = {"schemaVersion": 1, "platform": args.platform, **target, "productVersion": config["productVersion"]}
        elif args.command == "build":
            result = run_incremental_build(project, args.platform)
        elif args.command == "package":
            evidence = _load_json(Path(args.signing_evidence)) if args.signing_evidence else None
            result = create_release_bundle(
                project=project,
                artifact=Path(args.artifact).resolve(),
                platform=args.platform,
                output=Path(args.output).resolve(),
                source_commit=args.source_commit,
                signing_evidence=evidence,
            )
        else:
            result = verify_release_bundle(
                project=project,
                bundle=Path(args.bundle).resolve(),
                provenance_path=Path(args.provenance).resolve(),
                require_signed=args.require_signed,
            )
        print(json.dumps(result, sort_keys=True))
        return 0
    except (OSError, zipfile.BadZipFile, ReleaseEngineeringError) as exc:
        code = exc.code if isinstance(exc, ReleaseEngineeringError) else "io_error"
        print(json.dumps({"resultState": "FAIL", "code": code, "error": str(exc)}, sort_keys=True))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
