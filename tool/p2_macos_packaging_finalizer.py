#!/usr/bin/env python3
from __future__ import annotations

import base64
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BASE = "e4f66ce5a95870cad342bbf9aaf89f94dc768f58"
BRANCH = "agent/gpt-gold/gs-003d-macos-package-signing"
WORKFLOW = Path(".github/workflows/p2-macos-packaging-finalizer.yml")
SCRIPT = Path("tool/p2_macos_packaging_finalizer.py")
PACKAGER = Path("tool/v70_package_platform.py")
TEST = Path("tool/p2_macos_packaging_test.py")

OLD_SIGNER = '''def ad_hoc_sign_macos(app_bundle: pathlib.Path, p1a_native: pathlib.Path) -> str:
    def execute(argv: list[str]) -> None:
        result = subprocess.run(argv, text=True, encoding="utf-8", errors="replace", capture_output=True)
        if result.returncode:
            fail(f"macOS ad-hoc code signing failed ({result.returncode}): {' '.join(argv)}\\n{result.stdout}\\n{result.stderr}")

    subprocess.run(["xattr", "-cr", str(app_bundle)], text=True, encoding="utf-8", errors="replace", capture_output=True)
    for binary in sorted((path for path in p1a_native.rglob("*") if path.is_file() and os.access(path, os.X_OK)), key=lambda item: item.as_posix()):
        execute(["codesign", "--force", "--sign", "-", "--timestamp=none", str(binary)])
        execute(["codesign", "--verify", "--strict", "--verbose=2", str(binary)])
    execute(["codesign", "--force", "--deep", "--sign", "-", "--timestamp=none", str(app_bundle)])
    execute(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app_bundle)])
    return "ad-hoc-resigned-after-runtime-staging"
'''

NEW_SIGNER = '''MACHO_MAGICS = {
    bytes.fromhex(value)
    for value in (
        "feedface", "cefaedfe", "feedfacf", "cffaedfe",
        "cafebabe", "bebafeca", "cafebabf", "bfbafeca",
    )
}


def is_macho_file(path: pathlib.Path) -> bool:
    if path.is_symlink() or not path.is_file():
        return False
    try:
        with path.open("rb") as stream:
            return stream.read(4) in MACHO_MAGICS
    except OSError:
        return False


def macos_signing_targets(app_bundle: pathlib.Path, p1a_native: pathlib.Path) -> list[pathlib.Path]:
    candidates = {
        path.resolve()
        for root in (app_bundle, p1a_native)
        for path in root.rglob("*")
        if is_macho_file(path)
    }
    return sorted(candidates, key=lambda item: (-len(item.parts), item.as_posix()))


def ad_hoc_sign_macos(app_bundle: pathlib.Path, p1a_native: pathlib.Path) -> str:
    def execute(argv: list[str]) -> None:
        result = subprocess.run(argv, text=True, encoding="utf-8", errors="replace", capture_output=True)
        if result.returncode:
            fail(f"macOS ad-hoc code signing failed ({result.returncode}): {' '.join(argv)}\\n{result.stdout}\\n{result.stderr}")

    subprocess.run(["xattr", "-cr", str(app_bundle)], text=True, encoding="utf-8", errors="replace", capture_output=True)
    for binary in macos_signing_targets(app_bundle, p1a_native):
        execute(["codesign", "--force", "--sign", "-", "--timestamp=none", str(binary)])
        execute(["codesign", "--verify", "--strict", "--verbose=2", str(binary)])
    execute(["codesign", "--force", "--sign", "-", "--timestamp=none", str(app_bundle)])
    execute(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app_bundle)])
    return "ad-hoc-resigned-after-runtime-staging"
'''

TEST_SOURCE = r'''#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "tool/v70_package_platform.py"
SPEC = importlib.util.spec_from_file_location("v70_package_platform", PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("cannot load platform packager")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

MACHO = bytes.fromhex("cffaedfe") + b"test"


class Result:
    returncode = 0
    stdout = ""
    stderr = ""


class MacosPackagingTest(unittest.TestCase):
    def test_signing_skips_symlinks_and_never_uses_deep_for_signing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = root / "Kristin.app"
            runtime = app / "Contents/MacOS/runtime/automation_host"
            bin_dir = runtime / "node_modules/.bin"
            bin_dir.mkdir(parents=True)
            node = runtime / "node"
            node.write_bytes(MACHO)
            node.chmod(0o755)
            (bin_dir / "node").symlink_to(Path("../../node"))
            main = app / "Contents/MacOS/Kristin"
            main.parent.mkdir(parents=True, exist_ok=True)
            main.write_bytes(MACHO)
            main.chmod(0o755)
            p1a = root / "p1a-native"
            helper = p1a / "nested/helper"
            helper.parent.mkdir(parents=True)
            helper.write_bytes(MACHO)
            helper.chmod(0o755)
            (p1a / "script.sh").write_text("#!/bin/sh\n", encoding="utf-8")

            calls: list[list[str]] = []
            def fake_run(argv, **kwargs):
                calls.append([str(value) for value in argv])
                return Result()

            with mock.patch.object(MODULE.subprocess, "run", side_effect=fake_run):
                value = MODULE.ad_hoc_sign_macos(app, p1a)
            self.assertEqual(value, "ad-hoc-resigned-after-runtime-staging")
            sign = [row for row in calls if row and row[0] == "codesign" and "--force" in row]
            verify = [row for row in calls if row and row[0] == "codesign" and "--verify" in row]
            self.assertTrue(sign)
            self.assertTrue(verify)
            self.assertTrue(all("--deep" not in row for row in sign))
            self.assertIn(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)], verify)
            self.assertEqual(sign[-1][-1], str(app))
            signed_paths = [row[-1] for row in sign[:-1]]
            self.assertNotIn(str(bin_dir / "node"), signed_paths)
            self.assertEqual(signed_paths, [str(path) for path in MODULE.macos_signing_targets(app, p1a)])
            self.assertTrue(all(not Path(path).is_symlink() for path in signed_paths))

    def test_macho_detection_and_launcher_source_contract(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            binary = root / "binary"
            binary.write_bytes(MACHO)
            link = root / "link"
            link.symlink_to(binary.name)
            text = root / "text"
            text.write_text("not macho", encoding="utf-8")
            self.assertTrue(MODULE.is_macho_file(binary))
            self.assertFalse(MODULE.is_macho_file(link))
            self.assertFalse(MODULE.is_macho_file(text))
        source = PATH.read_text(encoding="utf-8")
        self.assertNotIn("codesign --force --deep --sign", source)
        self.assertIn("codesign --verify --deep --strict", source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
'''


def run(*args: str, capture: bool = False) -> str:
    result = subprocess.run(args, cwd=ROOT, text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None)
    if result.returncode:
        raise SystemExit(f"failed ({result.returncode}): {' '.join(args)}\n{result.stdout or ''}")
    return (result.stdout or "").strip()


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise SystemExit(f"{label}: expected one anchor, found {text.count(old)}")
    return text.replace(old, new, 1)


def api(endpoint: str, payload: dict[str, object]) -> dict[str, object]:
    token = os.environ["GITHUB_TOKEN"]
    repository = os.environ["GITHUB_REPOSITORY"]
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repository}{endpoint}",
        data=json.dumps(payload).encode("utf-8"), method="POST",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            value = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        raise SystemExit(f"GitHub API failed: {error.code}: {error.read().decode('utf-8', errors='replace')}") from error
    if not isinstance(value, dict):
        raise SystemExit("GitHub API returned non-object")
    return value


def blob(path: Path) -> str:
    return str(api("/git/blobs", {"content": base64.b64encode(path.read_bytes()).decode("ascii"), "encoding": "base64"})["sha"])


def main() -> int:
    trigger = os.environ.get("GITHUB_SHA", "")
    if not re.fullmatch(r"[0-9a-f]{40}", trigger):
        raise SystemExit("invalid trigger")
    if run("git", "branch", "--show-current", capture=True) != BRANCH:
        raise SystemExit("wrong branch")
    if run("git", "rev-parse", "HEAD", capture=True) != trigger:
        raise SystemExit("wrong trigger head")
    run("git", "merge-base", "--is-ancestor", BASE, trigger)

    source = (ROOT / PACKAGER).read_text(encoding="utf-8")
    source = replace_once(source, OLD_SIGNER, NEW_SIGNER, "macOS signer")
    source = replace_once(source,
        '/usr/bin/codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"',
        '/usr/bin/codesign --force --sign - --timestamp=none "$APP_BUNDLE"',
        "launcher signer")
    (ROOT / PACKAGER).write_text(source, encoding="utf-8", newline="\n")
    (ROOT / TEST).write_text(TEST_SOURCE, encoding="utf-8", newline="\n")
    for path in (ROOT / WORKFLOW, ROOT / SCRIPT):
        path.unlink()

    run("python3", "-m", "py_compile", str(PACKAGER), str(TEST))
    run("python3", str(TEST))
    run("git", "diff", "--check")
    run("git", "add", "-A")
    effective = set(run("git", "diff", "--cached", "--name-only", BASE, "--", capture=True).splitlines())
    expected = {PACKAGER.as_posix(), TEST.as_posix()}
    if effective != expected:
        raise SystemExit(f"source scope mismatch: {sorted(effective)}")

    trigger_tree = run("git", "rev-parse", "HEAD^{tree}", capture=True)
    source_entries = [
        {"path": PACKAGER.as_posix(), "mode": "100644", "type": "blob", "sha": blob(ROOT / PACKAGER)},
        {"path": TEST.as_posix(), "mode": "100644", "type": "blob", "sha": blob(ROOT / TEST)},
        {"path": WORKFLOW.as_posix(), "mode": "100644", "type": "blob", "sha": None},
        {"path": SCRIPT.as_posix(), "mode": "100644", "type": "blob", "sha": None},
    ]
    source_tree = api("/git/trees", {"base_tree": trigger_tree, "tree": source_entries})
    source_commit = api("/git/commits", {"message": "fix(p2): sign macOS Mach-O descendants without deep traversal", "tree": source_tree["sha"], "parents": [trigger]})

    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    first = (ROOT / "SOURCE_MANIFEST.sha256").read_bytes()
    run("python3", "tool/p1a_refresh_source_manifest.py", ".")
    if (ROOT / "SOURCE_MANIFEST.sha256").read_bytes() != first:
        raise SystemExit("manifest not byte-stable")
    run("python3", "tool/p1a_text_eof_contract_test.py", "--project", ".")
    manifest_tree = api("/git/trees", {"base_tree": source_tree["sha"], "tree": [{"path": "SOURCE_MANIFEST.sha256", "mode": "100644", "type": "blob", "sha": blob(ROOT / "SOURCE_MANIFEST.sha256")} ]})
    final_commit = api("/git/commits", {"message": "chore(release): finalize macOS packaging repair source manifest", "tree": manifest_tree["sha"], "parents": [source_commit["sha"]]})
    print(json.dumps({"sourceCommit": source_commit["sha"], "sourceTree": source_tree["sha"], "finalCommit": final_commit["sha"], "finalTree": manifest_tree["sha"], "sourcePaths": sorted(expected), "manifestOnlySecondCommit": True}, indent=2))
    print("SOURCE_COMMIT=" + str(source_commit["sha"]))
    print("FINAL_COMMIT=" + str(final_commit["sha"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
