from __future__ import annotations

import hashlib
import json
import os
import pathlib
import shutil
import stat
import subprocess
import zipfile
from typing import Any, Iterable

P2_SHA = "7b0d77d8956f05ff907ca7463b0d787dcebf93a60426aab105be2b610e6072b0"
WINDOWS_ALL_APPLICATION_PACKAGES_SID = "*S-1-15-2-1"
WINDOWS_ALL_RESTRICTED_APPLICATION_PACKAGES_SID = "*S-1-15-2-2"
_MACHO_MAGICS = {
    b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
}


def fail(message: str) -> None:
    raise SystemExit(f"ERROR: {message}")


def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def load_json(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"invalid JSON {path}: {error}")
    if not isinstance(value, dict):
        fail(f"JSON object required: {path}")
    return value


def write_json(path: pathlib.Path, value: dict[str, Any]) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")


def copy_tree(source: pathlib.Path, destination: pathlib.Path) -> None:
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination, symlinks=True)


def ensure_macos_node_pty_spawn_helpers(runtime_destination: pathlib.Path) -> list[pathlib.Path]:
    prebuilds = runtime_destination / "automation_host" / "node_modules" / "node-pty" / "prebuilds"
    helpers = sorted(prebuilds.glob("darwin-*/spawn-helper"), key=lambda item: item.as_posix())
    if not helpers:
        fail("macOS node-pty spawn-helper missing from staged runtime")
    repaired: list[pathlib.Path] = []
    for helper in helpers:
        if helper.is_symlink() or not helper.is_file():
            fail(f"macOS node-pty spawn-helper is not a regular file: {helper}")
        helper.chmod(stat.S_IMODE(helper.stat().st_mode) | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        if not os.access(helper, os.X_OK):
            fail(f"macOS node-pty spawn-helper is not executable after staging repair: {helper}")
        repaired.append(helper)
    return repaired


def prepare_windows_browser_sandbox_acl(root: pathlib.Path, *, platform: str, runner=subprocess.run) -> bool:
    if platform != "windows":
        return False
    if not root.is_dir() or root.is_symlink():
        fail(f"Windows packaged browser ACL root invalid: {root}")
    result = runner(
        [
            "icacls.exe", str(root), "/grant",
            f"{WINDOWS_ALL_APPLICATION_PACKAGES_SID}:(OI)(CI)(RX)",
            f"{WINDOWS_ALL_RESTRICTED_APPLICATION_PACKAGES_SID}:(OI)(CI)(RX)",
            "/T", "/Q",
        ],
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or f"exit={result.returncode}").replace("\x00", "").strip()
        fail(f"Windows packaged browser sandbox ACL preparation failed: {detail[-2048:]}")
    return True


def product_runtime_destinations(app_destination: pathlib.Path, app_source: pathlib.Path, platform: str) -> tuple[pathlib.Path, pathlib.Path]:
    base = (
        app_destination / app_source.name / "Contents/Resources/runtime"
        if platform == "macos"
        else app_destination / "runtime"
    )
    return base / "p2/current", base / "p3/current"


def p2_runtime_destination(app_destination: pathlib.Path, app_source: pathlib.Path, platform: str) -> pathlib.Path:
    return product_runtime_destinations(app_destination, app_source, platform)[0]


def locate_app(root: pathlib.Path, platform: str) -> tuple[pathlib.Path, str]:
    if platform == "windows":
        roots = [path for path in root.glob("build/windows/**/runner/Release") if path.is_dir()]
        for directory in sorted(roots, key=lambda value: len(value.parts), reverse=True):
            exes = [p for p in directory.glob("*.exe") if not p.name.lower().startswith(("uninstall", "vc_redist"))]
            if exes:
                chosen = sorted(exes, key=lambda p: p.name)[0]
                return directory, chosen.relative_to(directory).as_posix()
        fail("Flutter Windows release output not found")
    if platform == "linux":
        roots = [path for path in root.glob("build/linux/**/release/bundle") if path.is_dir()]
        for directory in sorted(roots, key=lambda value: len(value.parts), reverse=True):
            candidates = [p for p in directory.iterdir() if p.is_file() and os.access(p, os.X_OK) and p.name != "libflutter_linux_gtk.so"]
            if candidates:
                chosen = sorted(candidates, key=lambda p: p.name)[0]
                return directory, chosen.relative_to(directory).as_posix()
        fail("Flutter Linux release bundle not found")
    apps = sorted(root.glob("build/macos/Build/Products/Release/*.app"), key=lambda p: p.name)
    if not apps:
        fail("Flutter macOS release .app not found")
    app = apps[0]
    macos_dir = app / "Contents/MacOS"
    executables = [p for p in macos_dir.iterdir() if p.is_file() and os.access(p, os.X_OK)] if macos_dir.is_dir() else []
    if not executables:
        fail("macOS app executable not found")
    executable = sorted(executables, key=lambda p: p.name)[0]
    return app, f"{app.name}/Contents/MacOS/{executable.name}"


def hash_rows(root: pathlib.Path) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for path in sorted(root.rglob("*"), key=lambda p: p.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix()
        if path.is_symlink():
            raw = os.readlink(path).encode("utf-8")
            rows.append({"path": relative, "kind": "symlink", "target": os.readlink(path), "sha256": sha_bytes(raw), "bytes": len(raw)})
        elif path.is_file():
            rows.append({"path": relative, "kind": "file", "sha256": sha_file(path), "bytes": path.stat().st_size})
    return rows


def zip_payload(source: pathlib.Path, archive: pathlib.Path) -> None:
    archive.parent.mkdir(parents=True, exist_ok=True)
    temporary = archive.with_suffix(archive.suffix + ".tmp")
    temporary.unlink(missing_ok=True)
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for path in sorted(source.rglob("*"), key=lambda p: p.relative_to(source).as_posix()):
            relative = path.relative_to(source).as_posix()
            if path.is_dir() and not path.is_symlink():
                continue
            info = zipfile.ZipInfo(relative, (2020, 1, 1, 0, 0, 0))
            info.create_system = 3
            if path.is_symlink():
                info.external_attr = (stat.S_IFLNK | 0o777) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                bundle.writestr(info, os.readlink(path).encode("utf-8"))
            else:
                mode = 0o755 if os.access(path, os.X_OK) else 0o644
                info.external_attr = (stat.S_IFREG | mode) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                bundle.writestr(info, path.read_bytes())
    temporary.replace(archive)


def tree_sha256(root: pathlib.Path) -> str:
    if not root.is_dir() or root.is_symlink():
        fail(f"runtime tree invalid: {root}")
    rows: list[str] = []
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        if path.is_symlink():
            fail(f"runtime tree symlink rejected: {path}")
        if path.is_file():
            rows.append(f"{path.relative_to(root).as_posix()}\0{sha_file(path)}")
    return sha_bytes("\n".join(rows).encode("utf-8"))


def _resource_path(root: pathlib.Path, row: dict[str, Any], label: str) -> pathlib.Path:
    relative = pathlib.PurePosixPath(str(row.get("path", "")))
    if relative.is_absolute() or ".." in relative.parts or not relative.parts:
        fail(f"{label} path invalid: {relative}")
    path = root.joinpath(*relative.parts)
    try:
        path.resolve().relative_to(root.resolve())
    except ValueError:
        fail(f"{label} path escapes runtime: {relative}")
    return path


def _rebind_resources(root: pathlib.Path, resources: dict[str, Any]) -> None:
    for key, raw in resources.items():
        if not isinstance(raw, dict):
            fail(f"runtime resource row invalid: {key}")
        path = _resource_path(root, raw, key)
        kind = raw.get("kind")
        if kind == "file":
            if not path.is_file() or path.is_symlink():
                fail(f"runtime resource file missing: {key}: {path}")
            raw["sha256"] = sha_file(path)
            raw["bytes"] = path.stat().st_size
        elif kind == "directory":
            raw["treeSha256"] = tree_sha256(path)
        else:
            fail(f"runtime resource kind invalid: {key}")


def _verify_resources(root: pathlib.Path, resources: dict[str, Any]) -> None:
    for key, raw in resources.items():
        if not isinstance(raw, dict):
            fail(f"runtime resource row invalid: {key}")
        path = _resource_path(root, raw, key)
        if raw.get("kind") == "file":
            if not path.is_file() or path.is_symlink():
                fail(f"runtime resource file missing: {key}: {path}")
            if raw.get("sha256") != sha_file(path) or raw.get("bytes") != path.stat().st_size:
                fail(f"runtime resource digest mismatch: {key}")
        elif raw.get("kind") == "directory":
            if raw.get("treeSha256") != tree_sha256(path):
                fail(f"runtime directory digest mismatch: {key}")
        else:
            fail(f"runtime resource kind invalid: {key}")


def _p2_build_sha(manifest: dict[str, Any]) -> str:
    identity = manifest["identity"]
    resources = manifest["resources"]
    rows = [f"{key}\0{canonical_json(resources[key])}" for key in sorted(resources)]
    payload = "\n".join(rows) + "\n" + str(identity["sourceCommit"]) + "\n" + str(identity["sourceTree"]) + "\n" + str(identity["p1AuthorityServiceContractSha256"])
    return sha_bytes(payload.encode("utf-8"))


def rebind_p2_runtime_manifest(runtime_root: pathlib.Path) -> dict[str, str]:
    path = runtime_root / "runtime-manifest.v3.json"
    manifest = load_json(path)
    if manifest.get("schemaVersion") != "3.0.0" or manifest.get("bundleType") != "kristin-p2-application-runtime-v3":
        fail("P2 runtime manifest schema/bundle invalid")
    resources = manifest.get("resources")
    identity = manifest.get("identity")
    if not isinstance(resources, dict) or not isinstance(identity, dict):
        fail("P2 runtime manifest identity/resources invalid")
    policy_row = resources.get("restrictedWorkerPolicy")
    if not isinstance(policy_row, dict):
        fail("P2 restricted worker policy binding missing")
    policy_path = _resource_path(runtime_root, policy_row, "restrictedWorkerPolicy")
    policy = load_json(policy_path)
    for policy_key, resource_key in (
        ("nodeSha256", "nodeExecutable"),
        ("hostScriptSha256", "automationHost"),
        ("launcherSha256", "restrictedWorkerLauncher"),
    ):
        row = resources.get(resource_key)
        if not isinstance(row, dict):
            fail(f"P2 resource missing for policy: {resource_key}")
        policy[policy_key] = sha_file(_resource_path(runtime_root, row, resource_key))
    write_json(policy_path, policy)
    _rebind_resources(runtime_root, resources)
    contract_path = runtime_root / "contracts/p1_authority_service_contract_v1.dart"
    if not contract_path.is_file() or sha_file(contract_path) != identity.get("p1AuthorityServiceContractSha256"):
        fail("P2 authority contract identity changed during packaging")
    identity["runtimeBuildSha256"] = _p2_build_sha(manifest)
    write_json(path, manifest)
    return {"manifestSha256": sha_file(path), "runtimeBuildSha256": str(identity["runtimeBuildSha256"])}


def _p3_build_sha(manifest: dict[str, Any]) -> str:
    identity = manifest["identity"]
    resources = manifest["resources"]
    rows = [f"{key}\0{canonical_json(resources[key])}" for key in sorted(resources)]
    rows.extend([
        str(identity["sourceCommit"]), str(identity["sourceTree"]),
        str(identity["packageLockSha256"]), str(identity["browserRevision"]),
    ])
    return sha_bytes("\n".join(rows).encode("utf-8"))


def rebind_p3_runtime_manifest(runtime_root: pathlib.Path) -> dict[str, str]:
    path = runtime_root / "browser-runtime-manifest.v1.json"
    manifest = load_json(path)
    if manifest.get("schemaVersion") != "1.0.0" or manifest.get("bundleType") != "kristin-p3-browser-runtime-v1":
        fail("P3 runtime manifest schema/bundle invalid")
    resources = manifest.get("resources")
    identity = manifest.get("identity")
    if not isinstance(resources, dict) or not isinstance(identity, dict):
        fail("P3 runtime manifest identity/resources invalid")
    _rebind_resources(runtime_root, resources)
    package_lock = resources.get("packageLock")
    if not isinstance(package_lock, dict) or package_lock.get("sha256") != identity.get("packageLockSha256"):
        fail("P3 package-lock identity changed during packaging")
    identity["runtimeBuildSha256"] = _p3_build_sha(manifest)
    write_json(path, manifest)
    return {"manifestSha256": sha_file(path), "runtimeBuildSha256": str(identity["runtimeBuildSha256"])}


def verify_runtime_manifest_bindings(runtime_root: pathlib.Path, manifest_name: str) -> dict[str, str]:
    path = runtime_root / manifest_name
    manifest = load_json(path)
    resources = manifest.get("resources")
    identity = manifest.get("identity")
    if not isinstance(resources, dict) or not isinstance(identity, dict):
        fail(f"runtime manifest identity/resources invalid: {manifest_name}")
    _verify_resources(runtime_root, resources)
    if manifest_name == "runtime-manifest.v3.json":
        policy_row = resources.get("restrictedWorkerPolicy")
        if not isinstance(policy_row, dict):
            fail("P2 restricted worker policy binding missing")
        policy = load_json(_resource_path(runtime_root, policy_row, "restrictedWorkerPolicy"))
        for policy_key, resource_key in (
            ("nodeSha256", "nodeExecutable"),
            ("hostScriptSha256", "automationHost"),
            ("launcherSha256", "restrictedWorkerLauncher"),
        ):
            row = resources.get(resource_key)
            if not isinstance(row, dict):
                fail(f"P2 resource missing for policy: {resource_key}")
            if policy.get(policy_key) != sha_file(_resource_path(runtime_root, row, resource_key)):
                fail(f"P2 worker policy digest mismatch: {policy_key}")
        contract = runtime_root / "contracts/p1_authority_service_contract_v1.dart"
        if not contract.is_file() or sha_file(contract) != identity.get("p1AuthorityServiceContractSha256"):
            fail("P2 authority contract digest mismatch")
        expected = _p2_build_sha(manifest)
    elif manifest_name == "browser-runtime-manifest.v1.json":
        package_lock = resources.get("packageLock")
        if not isinstance(package_lock, dict) or package_lock.get("sha256") != identity.get("packageLockSha256"):
            fail("P3 package-lock digest mismatch")
        expected = _p3_build_sha(manifest)
    else:
        fail(f"unsupported runtime manifest: {manifest_name}")
    if identity.get("runtimeBuildSha256") != expected:
        fail(f"runtime build digest mismatch: {manifest_name}")
    return {"manifestSha256": sha_file(path), "runtimeBuildSha256": expected}


def _is_macho(path: pathlib.Path) -> bool:
    try:
        with path.open("rb") as stream:
            return stream.read(4) in _MACHO_MAGICS
    except OSError:
        return False


def _nested_macho_files(roots: Iterable[pathlib.Path]) -> list[pathlib.Path]:
    found: set[pathlib.Path] = set()
    for root in roots:
        if not root.exists():
            continue
        candidates = [root] if root.is_file() else root.rglob("*")
        for path in candidates:
            if path.is_file() and not path.is_symlink() and _is_macho(path):
                found.add(path)
    return sorted(found, key=lambda item: item.as_posix())


def _macos_codesign_target(path: pathlib.Path) -> pathlib.Path:
    parent = path.parent
    if parent.suffix == ".framework" and path.name == parent.stem:
        return parent
    return path


def ad_hoc_sign_macos(
    app_bundle: pathlib.Path,
    p1a_native: pathlib.Path,
    p2_runtime: pathlib.Path,
    p3_runtime: pathlib.Path | None = None,
    *,
    runtime_executables: Iterable[pathlib.Path] = (),
    runner=subprocess.run,
) -> dict[str, Any]:
    commands: list[list[str]] = []

    def execute(argv: list[str], *, allow_failure: bool = False) -> None:
        commands.append(list(argv))
        result = runner(argv, text=True, encoding="utf-8", errors="replace", capture_output=True, check=False)
        if result.returncode and not allow_failure:
            fail(f"macOS ad-hoc code signing failed ({result.returncode}): {' '.join(argv)}\n{result.stdout}\n{result.stderr}")

    execute(["xattr", "-cr", str(app_bundle)], allow_failure=True)
    roots = [p1a_native, p2_runtime]
    if p3_runtime is not None:
        roots.append(p3_runtime)
    macho = _nested_macho_files(roots)
    for explicit in runtime_executables:
        if explicit.is_file() and _is_macho(explicit):
            macho.append(explicit)
    signed_targets: set[pathlib.Path] = set()
    for binary in sorted(set(macho), key=lambda item: item.as_posix()):
        target = _macos_codesign_target(binary)
        if target in signed_targets:
            continue
        signed_targets.add(target)
        execute(["codesign", "--force", "--sign", "-", "--timestamp=none", str(target)])
        execute(["codesign", "--verify", "--strict", "--verbose=2", str(target)])

    execute(["codesign", "--force", "--deep", "--sign", "-", "--timestamp=none", str(app_bundle)])
    execute(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app_bundle)])

    p2_identity = rebind_p2_runtime_manifest(p2_runtime)
    p3_identity = rebind_p3_runtime_manifest(p3_runtime) if p3_runtime is not None else None
    verify_runtime_manifest_bindings(p2_runtime, "runtime-manifest.v3.json")
    if p3_runtime is not None:
        verify_runtime_manifest_bindings(p3_runtime, "browser-runtime-manifest.v1.json")

    execute(["codesign", "--force", "--sign", "-", "--timestamp=none", str(app_bundle)])
    execute(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app_bundle)])

    final_p2 = verify_runtime_manifest_bindings(p2_runtime, "runtime-manifest.v3.json")
    final_p3 = verify_runtime_manifest_bindings(p3_runtime, "browser-runtime-manifest.v1.json") if p3_runtime is not None else None
    if final_p2 != p2_identity or final_p3 != p3_identity:
        fail("final macOS outer seal changed nested runtime identity")
    return {
        "classification": "ad-hoc-nested-signed-manifest-rebound-outer-sealed",
        "p2": final_p2,
        "p3": final_p3,
        "commandCount": len(commands),
    }
