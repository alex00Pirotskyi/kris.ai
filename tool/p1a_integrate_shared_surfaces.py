#!/usr/bin/env python3
"""Integrate the separately governed P1A source without changing bootstrap roadmap authority.

The P0/P1 bootstrap roadmap and its generated views are owned by the existing
roadmap controller. P1A is recorded through its dedicated active/completed task
packet, evidence graph, ADR/security documents, DECISIONS entry, release
verification hooks, and governed source inventories only.
"""
from __future__ import annotations
import argparse, ast, json, pathlib


def inventory(root: pathlib.Path) -> tuple[list[str], list[str]]:
    data = json.loads((root / 'config/p1a_source_inventory.v1.json').read_text(encoding='utf-8'))
    production, tests = data.get('productionDart'), data.get('testDart')
    if not isinstance(production, list) or not isinstance(tests, list):
        raise SystemExit('invalid P1A Dart inventory')
    if len(production) != len(set(production)) or len(tests) != len(set(tests)):
        raise SystemExit('duplicate P1A Dart inventory')
    for relative in production + tests:
        if not (root / relative).is_file():
            raise SystemExit(f'governed P1A source missing: {relative}')
    return sorted(production), sorted(tests)


def add_python_entries(path: pathlib.Path, name: str, entries: list[str]) -> None:
    source = path.read_text(encoding='utf-8')
    tree = ast.parse(source)
    container = None
    existing: set[str] = set()
    for node in ast.walk(tree):
        if (isinstance(node, ast.Assign)
                and any(isinstance(target, ast.Name) and target.id == name for target in node.targets)
                and isinstance(node.value, (ast.Set, ast.List, ast.Tuple))):
            container = node.value
            existing = {item.value for item in container.elts
                        if isinstance(item, ast.Constant) and isinstance(item.value, str)}
            break
    if container is None or container.end_lineno is None or container.end_col_offset is None:
        raise SystemExit(f'{path}: {name} inventory anchor missing')
    missing = [entry for entry in entries if entry not in existing]
    if not missing:
        return
    lines = source.splitlines(keepends=True)
    line_index = container.end_lineno - 1
    absolute = sum(map(len, lines[:line_index])) + container.end_col_offset - 1
    indentation = min((item.col_offset for item in container.elts), default=4)
    updated = source[:absolute] + ''.join(' ' * indentation + repr(entry) + ',\n' for entry in missing) + source[absolute:]
    compile(updated, str(path), 'exec')
    path.write_text(updated, encoding='utf-8')


def add_dart_inventory(path: pathlib.Path, entries: list[str]) -> None:
    source = path.read_text(encoding='utf-8')
    start = '      const expected = <String>{\n'
    end = '      };\n      final actual = activeDartFiles()'
    if source.count(start) != 1 or source.count(end) != 1:
        raise SystemExit('governed Dart source inventory anchors changed')
    position = source.index(end, source.index(start))
    block = source[source.index(start) + len(start):position]
    missing = [entry for entry in entries
               if f"'{entry}'," not in block and f'"{entry}",' not in block]
    if missing:
        path.write_text(source[:position] + ''.join(f"        '{entry}',\n" for entry in missing) + source[position:], encoding='utf-8')


def append_once(path: pathlib.Path, marker: str, text: str) -> None:
    source = path.read_text(encoding='utf-8') if path.exists() else ''
    if marker in source:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(source.rstrip() + ('\n\n' if source.strip() else '') + text.rstrip() + '\n', encoding='utf-8')


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', default='.')
    # Kept for compatibility with evidence finalization. It deliberately does
    # not promote or rewrite the bootstrap roadmap/generated views.
    parser.add_argument('--finalize-roadmap', action='store_true')
    args = parser.parse_args()
    root = pathlib.Path(args.project).resolve()
    production, tests = inventory(root)
    add_python_entries(root / 'tool/validate_release.py', 'EXPECTED_DART_FILES', production + tests)
    add_dart_inventory(root / 'test/product/source_contract_test.dart', production)
    append_once(root / 'tool/verify.sh', '# P1 AUTHORITY SERVICE AMENDMENT V65', """# P1 AUTHORITY SERVICE AMENDMENT V65
python tool/p1a_source_inventory_test.py --project .
python tool/p1a_authority_contract_test.py --project .
python tool/p1a_installer_secret_contract_test.py --project .
python tool/p1a_build_authority_snapshot_test.py --project .
python tool/p1a_toolchain_extension_test.py --project .
python tool/p1a_patch_product_runtime_test.py --project .
python tool/p1a_finalizer_contract_test.py --project .
if [[ -f release/evidence/P1A/manifest.json ]] && grep -q '"status": "passed"' release/evidence/P1A/manifest.json; then
  python tool/p1a_exit_gate_test.py --project .
else
  python tool/p1a_exit_gate_test.py --project . --source-only
fi""")
    append_once(root / 'docs/roadmap/DECISIONS.md', '## P1 authority-service amendment V65', """## P1 authority-service amendment V65

P1A-001 is a separately governed security amendment. It introduces an OS-isolated, typed P1 authority service owned outside the full-current-account automation worker boundary. Historical P1 evidence and the bootstrap P0/P1 roadmap remain immutable. P1A state is carried only by its dedicated task packet and signed evidence graph. Source landing on protected main is explicitly non-completing; only a later evidence-only closure can satisfy the P2 dependency.""")
    print(f'P1A shared surfaces V65: PASS ({len(production)} production, {len(tests)} tests; bootstrap roadmap untouched)')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
