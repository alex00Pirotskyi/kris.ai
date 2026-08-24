#!/usr/bin/env python3
from __future__ import annotations

import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]


def replace_once(path: pathlib.Path, old: str, new: str) -> None:
    text = path.read_text(encoding='utf-8')
    if text.count(old) != 1:
        raise SystemExit(f'PATCH_FAIL {path}: expected exactly one match, found {text.count(old)}')
    path.write_text(text.replace(old, new), encoding='utf-8', newline='\n')


def write(path: pathlib.Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding='utf-8', newline='\n')


# P2 packaged runtime lookup: include macOS Contents/Resources while keeping app-data first.
p2 = ROOT / 'lib/product/p2_runtime_resource_resolver.dart'
replace_once(
    p2,
    """  final Directory applicationDataRoot;\n  final String executablePath;\n\n  Future<P2RuntimeResourceSet> resolve() async {\n""",
    """  final Directory applicationDataRoot;\n  final String executablePath;\n\n  static List<Directory> candidateRoots({\n    required Directory applicationDataRoot,\n    required String executablePath,\n    bool? macOS,\n  }) {\n    final executableRoot = File(executablePath).absolute.parent;\n    final isMacOS = macOS ?? Platform.isMacOS;\n    return <Directory>[\n      Directory(\n        '${applicationDataRoot.absolute.path}${Platform.pathSeparator}'\n        'runtime${Platform.pathSeparator}p2${Platform.pathSeparator}current',\n      ),\n      if (isMacOS)\n        Directory(\n          '${executableRoot.parent.path}${Platform.pathSeparator}Resources'\n          '${Platform.pathSeparator}runtime${Platform.pathSeparator}p2'\n          '${Platform.pathSeparator}current',\n        ),\n      Directory(\n        '${executableRoot.path}${Platform.pathSeparator}'\n        'runtime${Platform.pathSeparator}p2${Platform.pathSeparator}current',\n      ),\n    ];\n  }\n\n  Future<P2RuntimeResourceSet> resolve() async {\n""",
)
replace_once(
    p2,
    """    final executableRoot = File(executablePath).absolute.parent;\n    final candidates = <Directory>[\n      Directory(\n        '${applicationDataRoot.absolute.path}${Platform.pathSeparator}'\n        'runtime${Platform.pathSeparator}p2${Platform.pathSeparator}current',\n      ),\n      Directory(\n        '${executableRoot.path}${Platform.pathSeparator}'\n        'runtime${Platform.pathSeparator}p2${Platform.pathSeparator}current',\n      ),\n    ];\n""",
    """    final candidates = candidateRoots(\n      applicationDataRoot: applicationDataRoot,\n      executablePath: executablePath,\n    );\n""",
)

# P3 packaged browser lookup: same application-owned macOS Resources location.
p3 = ROOT / 'lib/product/browser/browser_runtime_bundle.dart'
replace_once(
    p3,
    """  final Directory applicationDataRoot;\n  final String executablePath;\n\n  Future<P3BrowserRuntimeResourceSet> resolve() async {\n""",
    """  final Directory applicationDataRoot;\n  final String executablePath;\n\n  static List<Directory> candidateRoots({\n    required Directory applicationDataRoot,\n    required String executablePath,\n    bool? macOS,\n  }) {\n    final executableRoot = File(executablePath).absolute.parent;\n    final isMacOS = macOS ?? Platform.isMacOS;\n    return <Directory>[\n      Directory(\n        '${applicationDataRoot.absolute.path}${Platform.pathSeparator}'\n        'runtime${Platform.pathSeparator}p3${Platform.pathSeparator}current',\n      ),\n      if (isMacOS)\n        Directory(\n          '${executableRoot.parent.path}${Platform.pathSeparator}Resources'\n          '${Platform.pathSeparator}runtime${Platform.pathSeparator}p3'\n          '${Platform.pathSeparator}current',\n        ),\n      Directory(\n        '${executableRoot.path}${Platform.pathSeparator}'\n        'runtime${Platform.pathSeparator}p3${Platform.pathSeparator}current',\n      ),\n    ];\n  }\n\n  Future<P3BrowserRuntimeResourceSet> resolve() async {\n""",
)
replace_once(
    p3,
    """    final executableRoot = File(executablePath).absolute.parent;\n    final preferred = Directory(\n      '${applicationDataRoot.absolute.path}${Platform.pathSeparator}'\n      'runtime${Platform.pathSeparator}p3${Platform.pathSeparator}current',\n    );\n    if (await preferred.exists()) {\n      return _resolveExistingCandidate(preferred);\n    }\n\n    final fallback = Directory(\n      '${executableRoot.path}${Platform.pathSeparator}'\n      'runtime${Platform.pathSeparator}p3${Platform.pathSeparator}current',\n    );\n    if (await fallback.exists()) {\n      return _resolveExistingCandidate(fallback);\n    }\n    throw StateError('p3_browser_runtime_bundle_missing');\n""",
    """    final candidates = candidateRoots(\n      applicationDataRoot: applicationDataRoot,\n      executablePath: executablePath,\n    );\n    for (final candidate in candidates) {\n      if (await candidate.exists()) {\n        return _resolveExistingCandidate(candidate);\n      }\n    }\n    throw StateError('p3_browser_runtime_bundle_missing');\n""",
)

# Product package must physically contain both P2 and P3. Reapply Windows browser ACL after copy.
pack = ROOT / 'tool/v70_package_platform.py'
replace_once(
    pack,
    'P2_SHA = "7b0d77d8956f05ff907ca7463b0d787dcebf93a60426aab105be2b610e6072b0"\n',
    'P2_SHA = "7b0d77d8956f05ff907ca7463b0d787dcebf93a60426aab105be2b610e6072b0"\n'
    'WINDOWS_ALL_APPLICATION_PACKAGES_SID = "*S-1-15-2-1"\n'
    'WINDOWS_ALL_RESTRICTED_APPLICATION_PACKAGES_SID = "*S-1-15-2-2"\n',
)
replace_once(
    pack,
    """    return repaired\n\n\ndef locate_app(root: pathlib.Path, platform: str) -> tuple[pathlib.Path, str]:\n""",
    """    return repaired\n\n\ndef prepare_windows_browser_sandbox_acl(\n    root: pathlib.Path,\n    *,\n    platform: str,\n    runner=subprocess.run,\n) -> bool:\n    if platform != 'windows':\n        return False\n    if not root.is_dir() or root.is_symlink():\n        fail(f'Windows packaged browser ACL root invalid: {root}')\n    result = runner(\n        [\n            'icacls.exe',\n            str(root),\n            '/grant',\n            f'{WINDOWS_ALL_APPLICATION_PACKAGES_SID}:(OI)(CI)(RX)',\n            f'{WINDOWS_ALL_RESTRICTED_APPLICATION_PACKAGES_SID}:(OI)(CI)(RX)',\n            '/T',\n            '/Q',\n        ],\n        capture_output=True,\n        text=True,\n        check=False,\n    )\n    if result.returncode != 0:\n        detail = (result.stderr or result.stdout or f'exit={result.returncode}').replace('\\x00', '').strip()\n        fail(f'Windows packaged browser sandbox ACL preparation failed: {detail[-2048:]}')\n    return True\n\n\ndef product_runtime_destinations(\n    app_destination: pathlib.Path,\n    app_source: pathlib.Path,\n    platform: str,\n) -> tuple[pathlib.Path, pathlib.Path]:\n    if platform == 'macos':\n        base = app_destination / app_source.name / 'Contents/Resources/runtime'\n    else:\n        base = app_destination / 'runtime'\n    return base / 'p2/current', base / 'p3/current'\n\n\ndef locate_app(root: pathlib.Path, platform: str) -> tuple[pathlib.Path, str]:\n""",
)
replace_once(
    pack,
    '    parser.add_argument("--product-current-account", action="store_true")\n',
    '    parser.add_argument("--product-current-account", action="store_true")\n'
    '    parser.add_argument("--browser-runtime-stage")\n',
)
replace_once(
    pack,
    """    runtime_stage = pathlib.Path(args.runtime_stage).resolve()\n    output_dir = pathlib.Path(args.output_dir).resolve()\n""",
    """    runtime_stage = pathlib.Path(args.runtime_stage).resolve()\n    output_dir = pathlib.Path(args.output_dir).resolve()\n    browser_runtime_stage = (\n        pathlib.Path(args.browser_runtime_stage).resolve()\n        if args.browser_runtime_stage\n        else None\n    )\n""",
)
replace_once(
    pack,
    """    if not (runtime_stage / "runtime/runtime-manifest.v3.json").is_file():\n        fail("runtime stage invalid")\n    app_source, app_executable = locate_app(root, args.platform)\n""",
    """    if not (runtime_stage / "runtime/runtime-manifest.v3.json").is_file():\n        fail("runtime stage invalid")\n    if args.product_current_account:\n        if browser_runtime_stage is None:\n            fail("product current-account package requires browser runtime stage")\n        if not (browser_runtime_stage / "browser-runtime-manifest.v1.json").is_file():\n            fail("browser runtime stage invalid")\n    elif browser_runtime_stage is not None:\n        fail("browser runtime stage is product-only")\n    app_source, app_executable = locate_app(root, args.platform)\n""",
)
replace_once(
    pack,
    """    app_destination = payload / "app"\n    if args.platform == "macos":\n        app_destination.mkdir()\n        copy_tree(app_source, app_destination / app_source.name)\n        runtime_destination = app_destination / app_source.name / (\n            "Contents/Resources/runtime/p2/current"\n            if args.product_current_account\n            else "Contents/MacOS/runtime/p2/current"\n        )\n    else:\n        copy_tree(app_source, app_destination)\n        runtime_destination = app_destination / "runtime/p2/current"\n    copy_tree(runtime_stage / "runtime", runtime_destination)\n""",
    """    app_destination = payload / "app"\n    browser_runtime_destination: pathlib.Path | None = None\n    if args.platform == "macos":\n        app_destination.mkdir()\n        copy_tree(app_source, app_destination / app_source.name)\n        if args.product_current_account:\n            runtime_destination, browser_runtime_destination = product_runtime_destinations(\n                app_destination, app_source, args.platform\n            )\n        else:\n            runtime_destination = app_destination / app_source.name / "Contents/MacOS/runtime/p2/current"\n    else:\n        copy_tree(app_source, app_destination)\n        if args.product_current_account:\n            runtime_destination, browser_runtime_destination = product_runtime_destinations(\n                app_destination, app_source, args.platform\n            )\n        else:\n            runtime_destination = app_destination / "runtime/p2/current"\n    copy_tree(runtime_stage / "runtime", runtime_destination)\n""",
)
replace_once(
    pack,
    """        if windows_only_conpty.exists():\n            shutil.rmtree(windows_only_conpty)\n    p1a_destination = payload / "p1a-native"\n""",
    """        if windows_only_conpty.exists():\n            shutil.rmtree(windows_only_conpty)\n    if args.product_current_account:\n        assert browser_runtime_stage is not None\n        assert browser_runtime_destination is not None\n        copy_tree(browser_runtime_stage, browser_runtime_destination)\n        prepare_windows_browser_sandbox_acl(\n            browser_runtime_destination / "browser",\n            platform=args.platform,\n        )\n    p1a_destination = payload / "p1a-native"\n""",
)
replace_once(
    pack,
    '        "macosNodePtySpawnHelpers": [\n            item.relative_to(runtime_destination).as_posix()\n            for item in macos_spawn_helpers\n        ],\n        "appExecutable": app_executable,\n',
    '        "macosNodePtySpawnHelpers": [\n            item.relative_to(runtime_destination).as_posix()\n            for item in macos_spawn_helpers\n        ],\n'
    '        "browserRuntimeIncluded": bool(args.product_current_account),\n'
    '        "browserRuntimeManifestSha256": (\n'
    '            sha_file(browser_runtime_destination / "browser-runtime-manifest.v1.json")\n'
    '            if browser_runtime_destination is not None\n'
    '            else None\n'
    '        ),\n'
    '        "appExecutable": app_executable,\n',
)

print('P1_P10_RUNTIME_BUNDLE_PATCH_READY')
