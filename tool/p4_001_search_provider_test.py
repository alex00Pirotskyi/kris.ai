#!/usr/bin/env python3
"""Machine-observed source gate for Worker C's P4-001 foundation."""
from __future__ import annotations
import argparse
import ast
import contextlib
import hashlib
import io
import json
import pathlib
import sys
import unittest
REQUIRED = (
    'schemas/web_search_request.v1.json',
    'schemas/web_search_page.v1.json',
    'schemas/web_search_error.v1.json',
    'services/research_worker/src/search/validation.py',
    'services/research_worker/src/search/models.py',
    'services/research_worker/src/search/provider.py',
    'services/research_worker/src/search/fixture_provider.py',
    'services/research_worker/test/schema_validator.py',
    'services/research_worker/test/test_contract_models.py',
    'services/research_worker/test/test_fixture_provider.py',
    'services/research_worker/test/test_contract_regressions.py',
    'evals/fixtures/p4_001_search_provider/contract_cases.json',
)
FORBIDDEN_IMPORTS = {'playwright', 'selenium', 'requests', 'httpx', 'aiohttp', 'subprocess', 'sqlite3', 'psutil'}

def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', default='.')
    parser.add_argument('--json-output')
    args = parser.parse_args()
    project = pathlib.Path(args.project).resolve()
    assertions = []
    missing = [path for path in REQUIRED if not (project / path).is_file()]
    assertions.append({'id': 'P4-001.files.present', 'passed': not missing, 'detail': f'missing={missing}'})
    syntax_errors = []
    forbidden = []
    for relative in REQUIRED:
        path = project / relative
        if path.suffix != '.py' or not path.is_file():
            continue
        try:
            tree = ast.parse(path.read_text(encoding='utf-8'), filename=relative)
        except SyntaxError as exc:
            syntax_errors.append(f'{relative}:{exc.lineno}:{exc.msg}')
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                names = [alias.name.split('.')[0] for alias in node.names]
            elif isinstance(node, ast.ImportFrom) and node.module:
                names = [node.module.split('.')[0]]
            else:
                continue
            for name in names:
                if name in FORBIDDEN_IMPORTS:
                    forbidden.append(f'{relative}:{name}')
    assertions.extend((
        {'id': 'P4-001.python.syntax', 'passed': not syntax_errors, 'detail': f'errors={syntax_errors}'},
        {'id': 'P4-001.dependency.boundary', 'passed': not forbidden, 'detail': f'forbiddenImports={forbidden}'},
    ))
    start_dir = project / 'services/research_worker/test'
    sys.path.insert(0, str(project))
    suite = unittest.defaultTestLoader.discover(str(start_dir), pattern='test_*.py')
    output = io.StringIO()
    with contextlib.redirect_stderr(output), contextlib.redirect_stdout(output):
        result = unittest.TextTestRunner(stream=output, verbosity=2).run(suite)
    assertions.append({'id': 'P4-001.fixture.contracts', 'passed': result.wasSuccessful(), 'detail': f'testsRun={result.testsRun}, failures={len(result.failures)}, errors={len(result.errors)}, skipped={len(result.skipped)}'})
    passed = all(bool(item['passed']) for item in assertions)
    report = {
        'schemaVersion': '1.0.0',
        'taskId': 'P4-001',
        'classification': 'source_only_machine_observed',
        'status': 'passed' if passed else 'failed',
        'testsRun': result.testsRun,
        'failures': len(result.failures),
        'errors': len(result.errors),
        'skipped': len(result.skipped),
        'networkUsage': 'none',
        'assertions': assertions,
        'sourceHashes': {path: sha256(project / path) for path in REQUIRED if (project / path).is_file()},
        'unittestOutput': output.getvalue(),
        'completionEligible': False,
        'completionReason': 'Worker C source foundation only; exact-head CI and independent review remain required.',
    }
    rendered = json.dumps(report, indent=2, sort_keys=True) + '\n'
    if args.json_output:
        target = pathlib.Path(args.json_output)
        if not target.is_absolute():
            target = project / target
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(rendered, encoding='utf-8')
    print(rendered, end='')
    return 0 if passed else 1

if __name__ == '__main__':
    raise SystemExit(main())
