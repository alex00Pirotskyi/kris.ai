#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from pathlib import Path


def add(results, name, passed, detail):
    results.append({"name": name, "passed": bool(passed), "detail": detail})


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', default='.')
    parser.add_argument('--json-output')
    args = parser.parse_args()
    root = Path(args.project).resolve()
    results = []
    required = [
        'schemas/deterministic_policy_v2.schema.json', 'config/policy_engine.v2.json',
        'docs/architecture/DETERMINISTIC_POLICY_ENGINE_V2.md',
        'lib/product/deterministic_policy_engine.dart', 'test/product/deterministic_policy_engine_test.dart',
        'tool/deterministic_policy_engine.py', 'tool/deterministic_policy_engine_test.py',
        'evals/fixtures/p1_004_policy_engine/property_cases.json',
        'tasks/completed/P1-004.md', 'release/evidence/P1-004/manifest.json',
    ]
    missing = [item for item in required if not (root / item).is_file()]
    add(results, 'Required P1-004 files', not missing, 'all present' if not missing else str(missing))

    engine = load(root / 'tool/deterministic_policy_engine.py', 'p1_004_engine')
    catalog = json.loads((root / 'config/access_profiles.v2.json').read_text(encoding='utf-8'))
    config = json.loads((root / 'config/policy_engine.v2.json').read_text(encoding='utf-8'))
    fixture = json.loads((root / 'evals/fixtures/p1_004_policy_engine/property_cases.json').read_text(encoding='utf-8'))
    observed = {}
    for case in fixture['cases']:
        decision = engine.evaluate_policy(case['request'], access_catalog=catalog, policy_config=config)
        observed[case['name']] = decision['status']
    expected = {case['name']: case['expectedStatus'] for case in fixture['cases']}
    add(results, 'Shared policy corpus', observed == expected, f'cases={len(observed)}')

    order_case = next(case for case in fixture['cases'] if case['name'] == 'overlay_order_reference')
    first = engine.evaluate_policy(order_case['request'], access_catalog=catalog, policy_config=config)
    reversed_request = json.loads(json.dumps(order_case['request']))
    reversed_request['overlays'].reverse()
    second = engine.evaluate_policy(reversed_request, access_catalog=catalog, policy_config=config)
    add(results, 'Deterministic overlay ordering', first == second, f"decisionId={first['decisionId']}")

    denial_names = {'unknown_capability_denied', 'organization_deny_wins', 'model_cannot_approve', 'widening_above_ceiling_denied'}
    denied = all(observed[name] == 'deny' for name in denial_names)
    add(results, 'Deny-by-default and trusted-authority boundary', denied, f'denied={sorted(denial_names)}')

    owner = next(case for case in fixture['cases'] if case['name'] == 'owner_delete_approved')
    owner_decision = engine.evaluate_policy(owner['request'], access_catalog=catalog, policy_config=config)
    owner_ok = owner_decision['status'] == 'allow' and owner_decision['effectiveProfileId'] == 'owner' and owner_decision['grantDraft'] is not None
    add(results, 'Owner Mode intended authority', owner_ok, 'approved current-account effect emits bounded grant draft')

    dart = (root / 'lib/product/deterministic_policy_engine.dart').read_text(encoding='utf-8') + (root / 'test/product/deterministic_policy_engine_test.dart').read_text(encoding='utf-8')
    dart_ok = all(token in dart for token in ('class DeterministicPolicyEngineV2', 'explicit_widening_not_approved', 'untrusted_authority_source', 'overlay ordering produces byte-equivalent decisions'))
    add(results, 'Dart policy and property contract', dart_ok, 'Dart engine mirrors shared deterministic invariants')

    validator = (root / 'tool/validate_release.py').read_text(encoding='utf-8')
    source_contract = (root / 'test/product/source_contract_test.dart').read_text(encoding='utf-8')
    inventory = (
        'lib/product/deterministic_policy_engine.dart' in validator
        and 'test/product/deterministic_policy_engine_test.dart' in validator
        and 'lib/product/deterministic_policy_engine.dart' in source_contract
        and 'test/product/deterministic_policy_engine_test.dart' not in source_contract
    )
    add(results, 'Governed Dart inventories', inventory, 'release and library-only inventories remain distinct')

    roadmap = json.loads((root / 'docs/roadmap/roadmap.yaml').read_text(encoding='utf-8'))
    tasks = {item['id']: item for item in roadmap['tasks']}
    ready = sorted(task_id for task_id, item in tasks.items() if item.get('status') == 'READY')
    state = tasks.get('P1-004', {}).get('status') == 'DONE' and all(tasks.get(item, {}).get('status') in {'READY', 'DONE'} for item in ('P1-005', 'P1-011', 'P1-012'))
    add(results, 'Roadmap state', state, f"P1-004={tasks.get('P1-004', {}).get('status')} ready={ready}")

    ci = (root / '.github/workflows/ci.yml').read_text(encoding='utf-8')
    verify = (root / 'tool/verify.sh').read_text(encoding='utf-8')
    add(results, 'CI and local verification', 'P1-004 deterministic policy engine' in ci and 'p1_004_policy_engine_test.py' in verify, 'gates wired')
    add(results, 'Release validation integration', 'tool/p1_004_policy_engine_test.py' in validator and 'schemas/deterministic_policy_v2.schema.json' in validator, 'required files wired')

    passed = all(item['passed'] for item in results)
    report = {
        'schemaVersion': '1.0.0', 'taskId': 'P1-004', 'caseCount': len(results),
        'passedCount': sum(1 for item in results if item['passed']),
        'failedCount': sum(1 for item in results if not item['passed']),
        'passed': passed, 'results': results,
    }
    text = json.dumps(report, indent=2, sort_keys=True) + '\n'
    if args.json_output:
        output = root / args.json_output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(text, encoding='utf-8', newline='\n')
    print(text, end='')
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
