#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Product current-account runtime is an app resource on macOS. Keep the legacy
# executable-sibling location as a fallback so existing QA bundles remain
# compatible, but prefer the standard Contents/Resources layout for products.
dart = ROOT / 'lib/product/p2_bundled_current_account_runtime.dart'
text = dart.read_text(encoding='utf-8')
start_marker = "    final bundledRoot = Directory(\n"
end_marker = "    final bundled = _object(\n"
start = text.find(start_marker)
end = text.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit(f'dart bundle structural anchors missing: start={start} end={end}')
new = """    final bundledCandidates = <Directory>[
      if (Platform.isMacOS)
        Directory(
          '${executable.parent.parent.path}${Platform.pathSeparator}Resources'
          '${Platform.pathSeparator}runtime${Platform.pathSeparator}p2'
          '${Platform.pathSeparator}current',
        ),
      Directory(
        '${executable.parent.path}${Platform.pathSeparator}runtime'
        '${Platform.pathSeparator}p2${Platform.pathSeparator}current',
      ),
    ];
    Directory? selectedBundledRoot;
    for (final candidate in bundledCandidates) {
      final manifest = File(
        '${candidate.path}${Platform.pathSeparator}runtime-manifest.v3.json',
      );
      if (!await manifest.exists()) continue;
      if (await FileSystemEntity.isLink(manifest.path)) {
        throw StateError('p2_bundled_runtime_manifest_symlink');
      }
      selectedBundledRoot = candidate;
      break;
    }
    if (selectedBundledRoot == null) return false;
    final bundledRoot = selectedBundledRoot;
    final bundledManifest = File(
      '${bundledRoot.path}${Platform.pathSeparator}runtime-manifest.v3.json',
    );

"""
dart.write_text(text[:start] + new + text[end:], encoding='utf-8', newline='\n')

# Product bundles use Contents/Resources. Historical owner-risk QA packaging
# remains byte-for-byte on its previous Contents/MacOS path.
packager = ROOT / 'tool/v70_package_platform.py'
text = packager.read_text(encoding='utf-8')
old = '        runtime_destination = app_destination / app_source.name / "Contents/MacOS/runtime/p2/current"\n'
new = '''        runtime_destination = app_destination / app_source.name / (\n            "Contents/Resources/runtime/p2/current"\n            if args.product_current_account\n            else "Contents/MacOS/runtime/p2/current"\n        )\n'''
if text.count(old) != 1:
    raise SystemExit(f'packager mac runtime anchor count={text.count(old)}')
packager.write_text(text.replace(old, new, 1), encoding='utf-8', newline='\n')

print('OWNER_MACOS_RESOURCES_FINALIZE_OK')
