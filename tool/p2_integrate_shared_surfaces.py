#!/usr/bin/env python3
"""Integrate P2 sources without changing the P0/P1 bootstrap roadmap authority."""
from __future__ import annotations
import argparse, ast, json, pathlib


def load_inventory(root: pathlib.Path) -> tuple[list[str], list[str]]:
    data = json.loads((root / 'config/p2_source_inventory.v1.json').read_text(encoding='utf-8'))
    production, tests = data.get('productionDart'), data.get('testDart')
    if not isinstance(production, list) or not all(isinstance(x, str) for x in production):
        raise SystemExit('invalid P2 production inventory')
    if not isinstance(tests, list) or not all(isinstance(x, str) for x in tests):
        raise SystemExit('invalid P2 test inventory')
    if len(production) != len(set(production)) or len(tests) != len(set(tests)):
        raise SystemExit('duplicate P2 source inventory entry')
    for relative in production + tests:
        if not (root / relative).is_file():
            raise SystemExit(f'governed P2 source missing: {relative}')
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
    absolute = sum(map(len, lines[:container.end_lineno - 1])) + container.end_col_offset - 1
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
    missing = [entry for entry in entries if f"'{entry}'," not in block and f'"{entry}",' not in block]
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
    parser.add_argument('--finalize-roadmap', action='store_true')
    args = parser.parse_args()
    root = pathlib.Path(args.project).resolve()
    production, tests = load_inventory(root)
    add_python_entries(root / 'tool/validate_release.py', 'EXPECTED_DART_FILES', production + tests)
    add_dart_inventory(root / 'test/product/source_contract_test.dart', production)
    append_once(root / 'tool/verify.sh', '# P2 OWNER MODE TRAIN V65', """# P2 OWNER MODE TRAIN V65
python tool/toolchain_lock_test.py --source-only
python tool/p2_toolchain_extension_test.py --project .
python tool/p2_source_inventory_test.py --project .
python tool/p2_patch_application_composition_test.py --project .
python tool/p2_evidence_contract_test.py --project .
python tool/p2_strict_finalizer_contract_test.py --project .
python tool/p2_task_assertion_cli_test.py --project .
python tool/p2_behavioral_gate.py --project .
python tool/p2_exit_gate_test.py --project . --source-only
if [[ -f release/evidence/P2/manifest.json ]] && grep -q '"status": "passed"' release/evidence/P2/manifest.json; then
  python tool/p2_exit_gate_test.py --project .
fi""")
    append_once(root / 'docs/roadmap/DECISIONS.md', '## P2 automation host — V65', """## P2 automation host — V65

P2 is a delegation-only Owner Mode consumer of the separately completed P1A authority service. Source landing on protected main remains incomplete and cannot unlock P3. P2 task state is carried by dedicated task/evidence packets and the signed aggregate exit graph; the historical P0/P1 bootstrap roadmap and generated views remain untouched.""")
    print(f'P2 shared surfaces V65: PASS ({len(production)} production, {len(tests)} tests; bootstrap roadmap untouched)')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
