from __future__ import annotations

import json
from pathlib import Path

ROOT = Path('.')


def replace_once(path: str, old: str, new: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}')
    target.write_text(text.replace(old, new, 1), encoding='utf-8')


package_path = ROOT / 'automation_host/package.json'
package = json.loads(package_path.read_text(encoding='utf-8'))
if package.get('dependencies', {}).get('node-pty') != '1.1.0':
    raise SystemExit('automation_host/package.json: node-pty pin drifted')
if 'allowScripts' in package:
    raise SystemExit('automation_host/package.json: allowScripts already present')
ordered = {}
for key, value in package.items():
    ordered[key] = value
    if key == 'dependencies':
        ordered['allowScripts'] = {'node-pty@1.1.0': True}
package_path.write_text(json.dumps(ordered, indent=2) + '\n', encoding='utf-8')

replace_once(
    'tool/v70_package_platform.py',
    '''def locate_app(root: pathlib.Path, platform: str) -> tuple[pathlib.Path, str]:\n''',
    '''def ensure_macos_node_pty_spawn_helpers(runtime_destination: pathlib.Path) -> list[pathlib.Path]:\n    prebuilds = (\n        runtime_destination\n        / "automation_host"\n        / "node_modules"\n        / "node-pty"\n        / "prebuilds"\n    )\n    helpers = sorted(prebuilds.glob("darwin-*/spawn-helper"), key=lambda item: item.as_posix())\n    if not helpers:\n        fail("macOS node-pty spawn-helper missing from staged runtime")\n    repaired: list[pathlib.Path] = []\n    for helper in helpers:\n        if helper.is_symlink() or not helper.is_file():\n            fail(f"macOS node-pty spawn-helper is not a regular file: {helper}")\n        mode = stat.S_IMODE(helper.stat().st_mode)\n        helper.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)\n        if not os.access(helper, os.X_OK):\n            fail(f"macOS node-pty spawn-helper is not executable after staging repair: {helper}")\n        repaired.append(helper)\n    return repaired\n\n\ndef locate_app(root: pathlib.Path, platform: str) -> tuple[pathlib.Path, str]:\n''',
)

replace_once(
    'tool/v70_package_platform.py',
    '''def ad_hoc_sign_macos(app_bundle: pathlib.Path, p1a_native: pathlib.Path) -> str:\n''',
    '''def ad_hoc_sign_macos(\n    app_bundle: pathlib.Path,\n    p1a_native: pathlib.Path,\n    runtime_executables: list[pathlib.Path] | tuple[pathlib.Path, ...] = (),\n) -> str:\n''',
)

replace_once(
    'tool/v70_package_platform.py',
    '''    for binary in sorted((path for path in p1a_native.rglob("*") if path.is_file() and os.access(path, os.X_OK)), key=lambda item: item.as_posix()):\n        execute(["codesign", "--force", "--sign", "-", "--timestamp=none", str(binary)])\n        execute(["codesign", "--verify", "--strict", "--verbose=2", str(binary)])\n    execute(["codesign", "--force", "--deep", "--sign", "-", "--timestamp=none", str(app_bundle)])\n''',
    '''    for binary in sorted((path for path in p1a_native.rglob("*") if path.is_file() and os.access(path, os.X_OK)), key=lambda item: item.as_posix()):\n        execute(["codesign", "--force", "--sign", "-", "--timestamp=none", str(binary)])\n        execute(["codesign", "--verify", "--strict", "--verbose=2", str(binary)])\n    for binary in sorted(runtime_executables, key=lambda item: item.as_posix()):\n        if not binary.is_file() or not os.access(binary, os.X_OK):\n            fail(f"macOS staged runtime executable is invalid before signing: {binary}")\n        execute(["codesign", "--force", "--sign", "-", "--timestamp=none", str(binary)])\n        execute(["codesign", "--verify", "--strict", "--verbose=2", str(binary)])\n    execute(["codesign", "--force", "--deep", "--sign", "-", "--timestamp=none", str(app_bundle)])\n''',
)

replace_once(
    'tool/v70_package_platform.py',
    '''    copy_tree(runtime_stage / "runtime", runtime_destination)\n    if args.platform == "macos":\n        windows_only_conpty = (\n''',
    '''    copy_tree(runtime_stage / "runtime", runtime_destination)\n    macos_spawn_helpers: list[pathlib.Path] = []\n    if args.platform == "macos":\n        macos_spawn_helpers = ensure_macos_node_pty_spawn_helpers(runtime_destination)\n        windows_only_conpty = (\n''',
)

replace_once(
    'tool/v70_package_platform.py',
    '''    if args.platform == "macos":\n        qa_code_signing = ad_hoc_sign_macos(app_destination / app_source.name, p1a_destination)\n''',
    '''    if args.platform == "macos":\n        qa_code_signing = ad_hoc_sign_macos(\n            app_destination / app_source.name,\n            p1a_destination,\n            runtime_executables=macos_spawn_helpers,\n        )\n''',
)

replace_once(
    'tool/v70_package_platform.py',
    '''        "qaCodeSigning": qa_code_signing,\n        "appExecutable": app_executable,\n''',
    '''        "qaCodeSigning": qa_code_signing,\n        "macosNodePtySpawnHelpers": [\n            item.relative_to(runtime_destination).as_posix()\n            for item in macos_spawn_helpers\n        ],\n        "appExecutable": app_executable,\n''',
)

test_path = ROOT / 'tool/p2_packaging_contract_test.py'
if test_path.exists():
    raise SystemExit('tool/p2_packaging_contract_test.py already exists')
test_path.write_text('''#!/usr/bin/env python3\nfrom __future__ import annotations\n\nimport importlib.util\nimport json\nimport os\nimport pathlib\nimport stat\nimport tempfile\n\nROOT = pathlib.Path(__file__).resolve().parents[1]\nPACKAGE = ROOT / "automation_host/package.json"\nLOCK = ROOT / "automation_host/package-lock.json"\nPACKAGER = ROOT / "tool/v70_package_platform.py"\n\n\ndef require(condition: bool, message: str) -> None:\n    if not condition:\n        raise SystemExit(f"P2_PACKAGING_CONTRACT_FAIL {message}")\n\n\ndef load_packager():\n    spec = importlib.util.spec_from_file_location("kristin_v70_package_platform", PACKAGER)\n    require(spec is not None and spec.loader is not None, "packager import spec missing")\n    module = importlib.util.module_from_spec(spec)\n    spec.loader.exec_module(module)\n    return module\n\n\ndef main() -> int:\n    package = json.loads(PACKAGE.read_text(encoding="utf-8"))\n    lock = json.loads(LOCK.read_text(encoding="utf-8"))\n    require(package.get("dependencies", {}).get("node-pty") == "1.1.0", "node-pty dependency must stay exactly pinned")\n    require(package.get("allowScripts") == {"node-pty@1.1.0": True}, "install-script approval must be exact node-pty@1.1.0 only")\n    locked = lock.get("packages", {}).get("node_modules/node-pty", {})\n    require(locked.get("version") == "1.1.0", "package lock node-pty version drift")\n    require(locked.get("hasInstallScript") is True, "node-pty install-script fact missing from lock")\n\n    source = PACKAGER.read_text(encoding="utf-8")\n    require("ensure_macos_node_pty_spawn_helpers(runtime_destination)" in source, "staging repair is not invoked")\n    require("runtime_executables=macos_spawn_helpers" in source, "repaired helpers are not explicitly signed")\n    require('"macosNodePtySpawnHelpers"' in source, "QA metadata does not record repaired helpers")\n\n    module = load_packager()\n    with tempfile.TemporaryDirectory() as temporary:\n        runtime = pathlib.Path(temporary) / "runtime"\n        helpers = []\n        for arch in ("darwin-arm64", "darwin-x64"):\n            helper = runtime / "automation_host/node_modules/node-pty/prebuilds" / arch / "spawn-helper"\n            helper.parent.mkdir(parents=True, exist_ok=True)\n            helper.write_bytes(b"fixture")\n            if os.name != "nt":\n                helper.chmod(0o644)\n            helpers.append(helper)\n        repaired = module.ensure_macos_node_pty_spawn_helpers(runtime)\n        require(repaired == helpers, "spawn-helper repair order/path set drift")\n        if os.name != "nt":\n            for helper in repaired:\n                mode = stat.S_IMODE(helper.stat().st_mode)\n                require(mode & stat.S_IXUSR != 0, f"user executable bit missing: {helper}")\n                require(mode & stat.S_IXGRP != 0, f"group executable bit missing: {helper}")\n                require(mode & stat.S_IXOTH != 0, f"other executable bit missing: {helper}")\n\n    with tempfile.TemporaryDirectory() as temporary:\n        missing = pathlib.Path(temporary) / "runtime"\n        try:\n            module.ensure_macos_node_pty_spawn_helpers(missing)\n        except SystemExit as exc:\n            require("spawn-helper missing" in str(exc), "missing helper must fail closed with specific reason")\n        else:\n            raise SystemExit("P2_PACKAGING_CONTRACT_FAIL missing spawn-helper did not fail closed")\n\n    print("P2_PACKAGING_CONTRACT_PASS")\n    return 0\n\n\nif __name__ == "__main__":\n    raise SystemExit(main())\n''', encoding='utf-8')

print('P2_SOURCE_CLOSURE_PATCH_APPLIED')
